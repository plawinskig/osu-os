/*
 * latency-probe - input-to-photon latency probe for a Wayland compositor
 * (osu!kiosk, Stage 5 Step D; a development tool, see PROGRESS.md).
 *
 * The whole surface flips between black and white on every key press and
 * every pointer button press. A high-speed camera sees each flip as one
 * unambiguous event, so the physical press and the first changed frame on
 * the panel can be paired up. The probe also times each press itself:
 * from the input event timestamp (taken by the kernel and passed on by
 * libinput and the compositor: CLOCK_MONOTONIC, whole milliseconds) to the
 * presentation timestamp of the first frame that shows the new colour
 * (wp_presentation: the page flip completion, i.e. the start of scanout).
 * That covers the software path. The camera adds what happens before the
 * kernel sees the input (keyboard controller, USB polling) and after the
 * scanout starts (panel response).
 *
 * Usage: latency-probe idle|mailbox|vsync > presses.csv
 *
 * The modes reproduce three ways a client can drive the compositor. They
 * matter because cage, like any wlroots compositor without a frame delay,
 * renders right after each vblank: what a press costs depends on whether
 * the compositor is idle and on when the client draws.
 *   idle     Draw only when a press arrives. The compositor is idle in
 *            between, as with a terminal or any other event-driven app.
 *   mailbox  Keep the compositor busy with a new frame on every frame
 *            callback, as a running game does, and draw a press at once:
 *            a game rendering without vsync.
 *   vsync    The same busy loop, but a press only shows up in the frame
 *            drawn after the next frame callback: a game with vsync.
 *
 * Output: a few "#" lines with the test conditions, then one CSV line per
 * press on stdout (line-buffered). Columns:
 *   press       press number, from 1
 *   source      key or button
 *   input_ms    input event timestamp (CLOCK_MONOTONIC, milliseconds)
 *   recv_ms     event handled by the probe      \
 *   commit_ms   first commit with the new colour  > relative to input_ms
 *   present_ms  that colour presented on screen  /
 *   refresh_ns  output refresh period reported with the presentation
 *   flags       wp_presentation flags (hex), or "superseded" for a press
 *               that a later press undid before any frame showed it
 * Input timestamps are whole milliseconds, so every relative time
 * overstates the latency by 0-1 ms.
 *
 * Escape exits; it is not counted as a press, and neither are releases.
 */

#define _GNU_SOURCE /* memfd_create() */

#include <errno.h>
#include <inttypes.h>
#include <linux/input-event-codes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>

#include "presentation-time-client-protocol.h"
#include "xdg-shell-client-protocol.h"

/* Every buffer is filled with one colour when it is created and keeps it;
 * a frame only rewrites the heartbeat pixel. A press then never waits for
 * a full-screen fill, whatever the compositor does with the buffers.
 * wlroots' GLES2 renderer copies a wl_shm buffer at commit and releases it
 * at once, so one buffer per colour would do there. The pixman renderer
 * keeps the shown buffer until the next one replaces it, with another one
 * possibly queued behind it: three per colour cover that too. */
#define BUFFERS_PER_COLOR 3
#define BUFFER_COUNT (2 * BUFFERS_PER_COLOR)
#define MAX_PRESSES 4096

/* Only used if the compositor leaves the size to the client (a 0x0
 * configure). cage always sends the output size. */
#define FALLBACK_WIDTH 640
#define FALLBACK_HEIGHT 480

#define COLOR_BLACK 0x000000u
#define COLOR_WHITE 0xffffffu
/* Flips the lowest bit of every channel of pixel (0, 0): a real change
 * that the compositor has to render, but invisible on the panel. */
#define HEARTBEAT_XOR 0x010101u

enum mode {
	MODE_IDLE,
	MODE_MAILBOX,
	MODE_VSYNC,
};

struct probe;

struct buffer {
	struct probe *probe;
	struct wl_buffer *wl_buffer;
	uint32_t *pixels;
	uint32_t color; /* of every pixel except the heartbeat one, fixed */
	bool busy;      /* committed and not released by the compositor yet */
};

struct press {
	const char *source; /* "key" or "button" */
	uint32_t input_ms;  /* event timestamp, CLOCK_MONOTONIC milliseconds */
	uint64_t recv_ns;   /* when the probe handled the event */
	uint64_t commit_ns; /* first commit that shows the press, 0 until then */
};

/* Ties one presentation feedback request to the frame it was made for. */
struct feedback {
	struct probe *probe;
	uint32_t generation;
};

struct probe {
	enum mode mode;
	bool running;
	int exit_code;

	struct wl_display *display;
	struct wl_compositor *compositor;
	struct wl_shm *shm;
	struct wl_seat *seat;
	struct xdg_wm_base *wm_base;
	struct wp_presentation *presentation;
	bool has_clock_id;
	uint32_t clock_id;

	struct wl_keyboard *keyboard;
	struct wl_pointer *pointer;

	struct wl_surface *surface;
	struct xdg_surface *xdg_surface;
	struct xdg_toplevel *xdg_toplevel;

	/* Size asked for by the last xdg_toplevel.configure, and the size
	 * the buffers were made for: they differ until the configure is
	 * applied in xdg_surface_configure(). */
	int32_t requested_width, requested_height;
	int32_t width, height;
	void *pool_data;
	size_t pool_size;
	struct buffer buffers[BUFFER_COUNT];

	/* The number of presses so far; its parity is the current colour. */
	uint32_t generation;
	uint32_t committed_generation; /* generation of the last commit */
	uint32_t reported_generation;  /* last press written to stdout */
	bool full_damage_pending;      /* first frame, or new buffer size */
	bool heartbeat;
	bool frame_pending;            /* a frame callback is outstanding */
	uint32_t buffer_waits;         /* frames delayed by no free buffer */

	struct press presses[MAX_PRESSES + 1]; /* indexed by generation */
};

static uint64_t now_ns(void)
{
	struct timespec now;

	clock_gettime(CLOCK_MONOTONIC, &now);
	return (uint64_t)now.tv_sec * 1000000000u + (uint64_t)now.tv_nsec;
}

/* Milliseconds from a 32-bit millisecond input timestamp, which wraps
 * every 49.7 days, to a CLOCK_MONOTONIC instant in nanoseconds. Doing the
 * subtraction in 32 bits keeps it right across a wrap. */
static double ms_since_input(uint32_t input_ms, uint64_t instant_ns)
{
	int32_t whole_ms = (int32_t)((uint32_t)(instant_ns / 1000000u) - input_ms);

	return whole_ms + (double)(instant_ns % 1000000u) / 1e6;
}

static uint32_t color_of(uint32_t generation)
{
	return generation % 2 == 0 ? COLOR_BLACK : COLOR_WHITE;
}

/* ------------------------------------------------------------------ */
/* Output                                                              */
/* ------------------------------------------------------------------ */

static void print_sysfs_value(const char *label, const char *path)
{
	char value[64] = "n/a";
	FILE *file = fopen(path, "r");

	/* A missing file is an answer too (no cpufreq driver, no usbhid,
	 * another GPU driver), so it is written down instead of failing. */
	if (file != NULL) {
		if (fgets(value, sizeof(value), file) == NULL)
			snprintf(value, sizeof(value), "unreadable");
		fclose(file);
		value[strcspn(value, "\n")] = '\0';
	}
	printf("# %s=%s\n", label, value);
}

/* Records the conditions of the run, so that every CSV file describes
 * itself: the CPU frequency policy and USB mouse polling change the
 * result, and are easy to get wrong when written down by hand. */
static void print_header(const struct probe *probe, const char *mode_name)
{
	bool monotonic = (clockid_t)probe->clock_id == CLOCK_MONOTONIC;

	printf("# latency-probe mode=%s\n", mode_name);
	printf("# presentation clock_id=%" PRIu32 " (%s)\n", probe->clock_id,
	       monotonic ? "CLOCK_MONOTONIC"
			 : "not CLOCK_MONOTONIC, present_ms is meaningless");
	print_sysfs_value("cpu0 scaling_driver",
			  "/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver");
	print_sysfs_value("cpu0 scaling_governor",
			  "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor");
	print_sysfs_value("cpu0 scaling_cur_freq_khz",
			  "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq");
	print_sysfs_value("usbhid mousepoll_ms (0: the device's own interval)",
			  "/sys/module/usbhid/parameters/mousepoll");
	print_sysfs_value("card0 gt_cur_freq_mhz",
			  "/sys/class/drm/card0/gt_cur_freq_mhz");
	puts("press,source,input_ms,recv_ms,commit_ms,present_ms,refresh_ns,flags");
}

static void print_presented(const struct probe *probe, uint32_t generation,
			    uint64_t present_ns, uint32_t refresh_ns,
			    uint32_t flags)
{
	const struct press *press = &probe->presses[generation];

	printf("%" PRIu32 ",%s,%" PRIu32 ",%.3f,%.3f,%.3f,%" PRIu32 ",0x%" PRIx32 "\n",
	       generation, press->source, press->input_ms,
	       ms_since_input(press->input_ms, press->recv_ns),
	       ms_since_input(press->input_ms, press->commit_ns),
	       ms_since_input(press->input_ms, present_ns),
	       refresh_ns, flags);
}

static void print_superseded(const struct probe *probe, uint32_t generation)
{
	const struct press *press = &probe->presses[generation];

	printf("%" PRIu32 ",%s,%" PRIu32 ",%.3f,,,,superseded\n",
	       generation, press->source, press->input_ms,
	       ms_since_input(press->input_ms, press->recv_ns));
}

/* ------------------------------------------------------------------ */
/* Buffers and frames                                                  */
/* ------------------------------------------------------------------ */

static bool submit_frame(struct probe *probe, bool request_frame);

static void buffer_release(void *data, struct wl_buffer *wl_buffer)
{
	struct buffer *buffer = data;
	struct probe *probe = buffer->probe;

	buffer->busy = false;
	if (!probe->running)
		return;
	/* Resume whatever a missing free buffer held up: the busy loop, or
	 * an idle-mode press that has not been drawn yet. */
	if (probe->mode != MODE_IDLE && !probe->frame_pending)
		submit_frame(probe, true);
	else if (probe->mode == MODE_IDLE &&
		 probe->committed_generation != probe->generation)
		submit_frame(probe, false);
}

static const struct wl_buffer_listener buffer_listener = {
	.release = buffer_release,
};

static void destroy_buffers(struct probe *probe)
{
	for (int i = 0; i < BUFFER_COUNT; i++) {
		if (probe->buffers[i].wl_buffer != NULL)
			wl_buffer_destroy(probe->buffers[i].wl_buffer);
		probe->buffers[i] = (struct buffer){0};
	}
	if (probe->pool_data != NULL)
		munmap(probe->pool_data, probe->pool_size);
	probe->pool_data = NULL;
	probe->pool_size = 0;
}

/* Allocates BUFFER_COUNT XRGB8888 buffers of width x height in one shared
 * memory pool, BUFFERS_PER_COLOR filled black and as many white. Prints
 * the reason and returns false on failure. */
static bool create_buffers(struct probe *probe, int32_t width, int32_t height)
{
	size_t pixel_count = (size_t)width * (size_t)height;
	size_t stride = (size_t)width * 4;
	size_t buffer_size = stride * (size_t)height;
	size_t pool_size = buffer_size * BUFFER_COUNT;

	/* The size comes from the compositor; wl_shm_create_pool() takes
	 * an int32_t, which also bounds the stride and the offsets below. */
	if (pool_size > INT32_MAX) {
		fprintf(stderr, "latency-probe: %" PRId32 "x%" PRId32
			" is too large for one wl_shm pool\n", width, height);
		return false;
	}
	int fd = memfd_create("latency-probe", MFD_CLOEXEC);
	if (fd < 0) {
		fprintf(stderr, "latency-probe: memfd_create: %s\n", strerror(errno));
		return false;
	}
	if (ftruncate(fd, (off_t)pool_size) < 0) {
		fprintf(stderr, "latency-probe: ftruncate to %zu bytes: %s\n",
			pool_size, strerror(errno));
		close(fd);
		return false;
	}
	void *pool_data = mmap(NULL, pool_size, PROT_READ | PROT_WRITE,
			       MAP_SHARED, fd, 0);
	if (pool_data == MAP_FAILED) {
		fprintf(stderr, "latency-probe: mmap of %zu bytes: %s\n",
			pool_size, strerror(errno));
		close(fd);
		return false;
	}

	struct wl_shm_pool *pool = wl_shm_create_pool(probe->shm, fd, (int32_t)pool_size);
	for (int i = 0; i < BUFFER_COUNT; i++) {
		struct buffer *buffer = &probe->buffers[i];
		size_t offset = buffer_size * (size_t)i;

		buffer->probe = probe;
		buffer->pixels = (uint32_t *)((char *)pool_data + offset);
		buffer->color = i < BUFFERS_PER_COLOR ? COLOR_BLACK : COLOR_WHITE;
		for (size_t p = 0; p < pixel_count; p++)
			buffer->pixels[p] = buffer->color;
		buffer->wl_buffer = wl_shm_pool_create_buffer(pool, (int32_t)offset,
							      width, height,
							      (int32_t)stride,
							      WL_SHM_FORMAT_XRGB8888);
		wl_buffer_add_listener(buffer->wl_buffer, &buffer_listener, buffer);
	}
	/* The buffers keep the shared memory alive on both sides; the pool
	 * object and the fd are not needed any more. */
	wl_shm_pool_destroy(pool);
	close(fd);

	probe->pool_data = pool_data;
	probe->pool_size = pool_size;
	probe->width = width;
	probe->height = height;
	return true;
}

static struct buffer *find_free_buffer(struct probe *probe, uint32_t color)
{
	for (int i = 0; i < BUFFER_COUNT; i++) {
		struct buffer *buffer = &probe->buffers[i];

		if (!buffer->busy && buffer->color == color)
			return buffer;
	}
	return NULL;
}

static void frame_done(void *data, struct wl_callback *callback, uint32_t time)
{
	struct probe *probe = data;

	wl_callback_destroy(callback);
	probe->frame_pending = false;
	if (probe->running)
		submit_frame(probe, true);
}

static const struct wl_callback_listener frame_listener = {
	.done = frame_done,
};

static void feedback_sync_output(void *data,
				 struct wp_presentation_feedback *wp_feedback,
				 struct wl_output *output)
{
}

static void feedback_presented(void *data,
			       struct wp_presentation_feedback *wp_feedback,
			       uint32_t tv_sec_hi, uint32_t tv_sec_lo,
			       uint32_t tv_nsec, uint32_t refresh,
			       uint32_t seq_hi, uint32_t seq_lo, uint32_t flags)
{
	struct feedback *feedback = data;
	struct probe *probe = feedback->probe;
	uint64_t seconds = ((uint64_t)tv_sec_hi << 32) | tv_sec_lo;
	uint64_t present_ns = seconds * 1000000000u + tv_nsec;

	/* The first presented frame that contains press k completes press
	 * k. Any press between the last reported one and k was undone by a
	 * later press before a frame could show it. Frames that contain
	 * only already reported presses (the busy loop) print nothing. */
	for (uint32_t g = probe->reported_generation + 1; g <= feedback->generation; g++) {
		if (g == feedback->generation)
			print_presented(probe, g, present_ns, refresh, flags);
		else
			print_superseded(probe, g);
	}
	if (feedback->generation > probe->reported_generation)
		probe->reported_generation = feedback->generation;

	wp_presentation_feedback_destroy(wp_feedback);
	free(feedback);
}

static void feedback_discarded(void *data,
			       struct wp_presentation_feedback *wp_feedback)
{
	/* A later commit replaced this frame before it reached the screen.
	 * That commit holds the same or a newer generation, and its own
	 * feedback reports the press: nothing is lost here. */
	wp_presentation_feedback_destroy(wp_feedback);
	free(data);
}

static const struct wp_presentation_feedback_listener feedback_listener = {
	.sync_output = feedback_sync_output,
	.presented = feedback_presented,
	.discarded = feedback_discarded,
};

/*
 * Commits a free buffer of the current generation's colour, together with
 * a presentation feedback request tagged with that generation. With
 * request_frame set it also asks for a frame callback, which is what keeps
 * the busy loop of the mailbox and vsync modes going. Returns false if no
 * buffer of that colour is free; buffer_release() then retries.
 */
static bool submit_frame(struct probe *probe, bool request_frame)
{
	struct buffer *buffer = find_free_buffer(probe, color_of(probe->generation));
	if (buffer == NULL) {
		/* Counted and reported at exit: a press that waits here for a
		 * buffer would charge the probe's own delay to the compositor. */
		probe->buffer_waits++;
		return false;
	}

	struct feedback *feedback = malloc(sizeof(*feedback));
	if (feedback == NULL) {
		fprintf(stderr, "latency-probe: out of memory for a presentation feedback\n");
		probe->running = false;
		probe->exit_code = 1;
		return false;
	}
	feedback->probe = probe;
	feedback->generation = probe->generation;

	bool full_damage = probe->full_damage_pending ||
			   color_of(probe->committed_generation) != color_of(probe->generation);
	/* The heartbeat makes every busy-loop frame a real change, so cage
	 * renders and flips on every vblank, as it would under a game. It is
	 * also the only pixel a frame writes. */
	if (probe->mode != MODE_IDLE)
		probe->heartbeat = !probe->heartbeat;
	buffer->pixels[0] = probe->heartbeat ? buffer->color ^ HEARTBEAT_XOR
					     : buffer->color;

	wl_surface_attach(probe->surface, buffer->wl_buffer, 0, 0);
	if (full_damage)
		wl_surface_damage_buffer(probe->surface, 0, 0, probe->width, probe->height);
	else
		wl_surface_damage_buffer(probe->surface, 0, 0, 1, 1);
	if (request_frame) {
		struct wl_callback *callback = wl_surface_frame(probe->surface);

		wl_callback_add_listener(callback, &frame_listener, probe);
		probe->frame_pending = true;
	}
	struct wp_presentation_feedback *wp_feedback =
		wp_presentation_feedback(probe->presentation, probe->surface);
	wp_presentation_feedback_add_listener(wp_feedback, &feedback_listener, feedback);

	/* Taken before the commit leaves the process: the compositor may act
	 * on it (and even present it) before this process runs again. */
	uint64_t commit_ns = now_ns();
	wl_surface_commit(probe->surface);
	/* Send the commit now instead of when the event loop next blocks:
	 * the time to the compositor is part of what is being measured. */
	wl_display_flush(probe->display);

	buffer->busy = true;
	probe->full_damage_pending = false;
	probe->committed_generation = probe->generation;
	struct press *press = &probe->presses[probe->generation];
	if (probe->generation > 0 && press->commit_ns == 0)
		press->commit_ns = commit_ns;
	return true;
}

/* ------------------------------------------------------------------ */
/* Input                                                               */
/* ------------------------------------------------------------------ */

static void handle_press(struct probe *probe, const char *source, uint32_t time_ms)
{
	if (probe->generation == MAX_PRESSES) {
		fprintf(stderr, "latency-probe: the table of %d presses is full, exiting\n",
			MAX_PRESSES);
		probe->running = false;
		return;
	}
	probe->generation++;
	probe->presses[probe->generation] = (struct press){
		.source = source,
		.input_ms = time_ms,
		.recv_ns = now_ns(),
	};

	/* vsync mode waits for the next frame callback, like a game that
	 * samples input once per vsync'd frame. idle and mailbox draw at
	 * once; in mailbox mode the busy loop keeps running alongside.
	 * Before the first configure there is nothing to draw into yet, and
	 * the first frame picks the press up. */
	if (probe->mode != MODE_VSYNC && probe->width > 0)
		submit_frame(probe, false);
}

static void keyboard_keymap(void *data, struct wl_keyboard *keyboard,
			    uint32_t format, int32_t fd, uint32_t size)
{
	/* Raw evdev key codes are all the probe needs. */
	close(fd);
}

static void keyboard_enter(void *data, struct wl_keyboard *keyboard,
			   uint32_t serial, struct wl_surface *surface,
			   struct wl_array *keys)
{
	/* Keys already held on enter, such as the Enter that started the
	 * probe from a terminal, are not presses made in the probe. */
}

static void keyboard_leave(void *data, struct wl_keyboard *keyboard,
			   uint32_t serial, struct wl_surface *surface)
{
}

static void keyboard_key(void *data, struct wl_keyboard *keyboard,
			 uint32_t serial, uint32_t time, uint32_t key,
			 uint32_t state)
{
	struct probe *probe = data;

	if (state != WL_KEYBOARD_KEY_STATE_PRESSED)
		return;
	if (key == KEY_ESC) {
		probe->running = false;
		return;
	}
	handle_press(probe, "key", time);
}

static void keyboard_modifiers(void *data, struct wl_keyboard *keyboard,
			       uint32_t serial, uint32_t depressed,
			       uint32_t latched, uint32_t locked, uint32_t group)
{
}

static void keyboard_repeat_info(void *data, struct wl_keyboard *keyboard,
				 int32_t rate, int32_t delay)
{
}

static const struct wl_keyboard_listener keyboard_listener = {
	.keymap = keyboard_keymap,
	.enter = keyboard_enter,
	.leave = keyboard_leave,
	.key = keyboard_key,
	.modifiers = keyboard_modifiers,
	.repeat_info = keyboard_repeat_info,
};

static void pointer_enter(void *data, struct wl_pointer *pointer,
			  uint32_t serial, struct wl_surface *surface,
			  wl_fixed_t x, wl_fixed_t y)
{
	/* Hide the cursor: a moving cursor would itself change the picture
	 * that the camera watches. */
	wl_pointer_set_cursor(pointer, serial, NULL, 0, 0);
}

static void pointer_leave(void *data, struct wl_pointer *pointer,
			  uint32_t serial, struct wl_surface *surface)
{
}

static void pointer_motion(void *data, struct wl_pointer *pointer,
			   uint32_t time, wl_fixed_t x, wl_fixed_t y)
{
}

static void pointer_button(void *data, struct wl_pointer *pointer,
			   uint32_t serial, uint32_t time, uint32_t button,
			   uint32_t state)
{
	if (state == WL_POINTER_BUTTON_STATE_PRESSED)
		handle_press(data, "button", time);
}

static void pointer_axis(void *data, struct wl_pointer *pointer,
			 uint32_t time, uint32_t axis, wl_fixed_t value)
{
}

/* wl_seat is bound at version 1 (see registry_global()), so only the
 * version 1 pointer events can arrive. */
static const struct wl_pointer_listener pointer_listener = {
	.enter = pointer_enter,
	.leave = pointer_leave,
	.motion = pointer_motion,
	.button = pointer_button,
	.axis = pointer_axis,
};

static void seat_capabilities(void *data, struct wl_seat *seat,
			      uint32_t capabilities)
{
	struct probe *probe = data;
	bool has_keyboard = capabilities & WL_SEAT_CAPABILITY_KEYBOARD;
	bool has_pointer = capabilities & WL_SEAT_CAPABILITY_POINTER;

	/* Capabilities come and go with devices, e.g. when the USB mouse is
	 * plugged in again after a usbhid.mousepoll change. */
	if (has_keyboard && probe->keyboard == NULL) {
		probe->keyboard = wl_seat_get_keyboard(seat);
		wl_keyboard_add_listener(probe->keyboard, &keyboard_listener, probe);
	} else if (!has_keyboard && probe->keyboard != NULL) {
		wl_keyboard_destroy(probe->keyboard);
		probe->keyboard = NULL;
	}
	if (has_pointer && probe->pointer == NULL) {
		probe->pointer = wl_seat_get_pointer(seat);
		wl_pointer_add_listener(probe->pointer, &pointer_listener, probe);
	} else if (!has_pointer && probe->pointer != NULL) {
		wl_pointer_destroy(probe->pointer);
		probe->pointer = NULL;
	}
}

static void seat_name(void *data, struct wl_seat *seat, const char *name)
{
}

static const struct wl_seat_listener seat_listener = {
	.capabilities = seat_capabilities,
	.name = seat_name,
};

/* ------------------------------------------------------------------ */
/* Window                                                              */
/* ------------------------------------------------------------------ */

static void wm_base_ping(void *data, struct xdg_wm_base *wm_base, uint32_t serial)
{
	xdg_wm_base_pong(wm_base, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
	.ping = wm_base_ping,
};

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel,
			       int32_t width, int32_t height,
			       struct wl_array *states)
{
	struct probe *probe = data;

	probe->requested_width = width > 0 ? width : FALLBACK_WIDTH;
	probe->requested_height = height > 0 ? height : FALLBACK_HEIGHT;
}

static void toplevel_close(void *data, struct xdg_toplevel *toplevel)
{
	struct probe *probe = data;

	probe->running = false;
}

static const struct xdg_toplevel_listener toplevel_listener = {
	.configure = toplevel_configure,
	.close = toplevel_close,
};

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface,
				  uint32_t serial)
{
	struct probe *probe = data;

	xdg_surface_ack_configure(xdg_surface, serial);
	if (probe->requested_width == probe->width &&
	    probe->requested_height == probe->height)
		return;

	destroy_buffers(probe);
	if (!create_buffers(probe, probe->requested_width, probe->requested_height)) {
		probe->running = false;
		probe->exit_code = 1;
		return;
	}
	/* The first configure starts the busy loop. A later resize needs one
	 * new full frame; a running loop carries on by itself. */
	probe->full_damage_pending = true;
	submit_frame(probe, probe->mode != MODE_IDLE && !probe->frame_pending);
}

static const struct xdg_surface_listener xdg_surface_listener = {
	.configure = xdg_surface_configure,
};

/* ------------------------------------------------------------------ */
/* Globals                                                             */
/* ------------------------------------------------------------------ */

static void presentation_clock_id(void *data, struct wp_presentation *presentation,
				  uint32_t clock_id)
{
	struct probe *probe = data;

	probe->clock_id = clock_id;
	probe->has_clock_id = true;
}

static const struct wp_presentation_listener presentation_listener = {
	.clock_id = presentation_clock_id,
};

static void registry_global(void *data, struct wl_registry *registry,
			    uint32_t name, const char *interface,
			    uint32_t version)
{
	struct probe *probe = data;

	/* Every global is bound at the lowest version that has what the
	 * probe uses, so that only events it handles can arrive. */
	if (strcmp(interface, wl_compositor_interface.name) == 0 && version >= 4) {
		/* Version 4: wl_surface.damage_buffer. */
		probe->compositor = wl_registry_bind(registry, name,
						     &wl_compositor_interface, 4);
	} else if (strcmp(interface, wl_shm_interface.name) == 0) {
		probe->shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
	} else if (strcmp(interface, wl_seat_interface.name) == 0 &&
		   probe->seat == NULL) {
		probe->seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
		wl_seat_add_listener(probe->seat, &seat_listener, probe);
	} else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
		probe->wm_base = wl_registry_bind(registry, name,
						  &xdg_wm_base_interface, 1);
		xdg_wm_base_add_listener(probe->wm_base, &wm_base_listener, probe);
	} else if (strcmp(interface, wp_presentation_interface.name) == 0) {
		probe->presentation = wl_registry_bind(registry, name,
						       &wp_presentation_interface, 1);
		wp_presentation_add_listener(probe->presentation,
					     &presentation_listener, probe);
	}
}

static void registry_global_remove(void *data, struct wl_registry *registry,
				   uint32_t name)
{
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_global_remove,
};

static bool check_globals(const struct probe *probe)
{
	bool ok = true;

	if (probe->compositor == NULL) {
		fprintf(stderr, "latency-probe: no wl_compositor version 4 or later\n");
		ok = false;
	}
	if (probe->shm == NULL) {
		fprintf(stderr, "latency-probe: no wl_shm\n");
		ok = false;
	}
	if (probe->seat == NULL) {
		fprintf(stderr, "latency-probe: no wl_seat\n");
		ok = false;
	}
	if (probe->wm_base == NULL) {
		fprintf(stderr, "latency-probe: no xdg_wm_base\n");
		ok = false;
	}
	if (probe->presentation == NULL) {
		fprintf(stderr, "latency-probe: no wp_presentation, cannot time presses\n");
		ok = false;
	} else if (!probe->has_clock_id) {
		fprintf(stderr, "latency-probe: wp_presentation sent no clock_id\n");
		ok = false;
	}
	return ok;
}

/* ------------------------------------------------------------------ */
/* Main                                                                */
/* ------------------------------------------------------------------ */

static void usage(void)
{
	fputs("usage: latency-probe idle|mailbox|vsync > presses.csv\n"
	      "Flips the screen between black and white on every key or button\n"
	      "press and prints the latency of each press as CSV. Escape exits.\n",
	      stderr);
}

static bool parse_mode(const char *name, enum mode *mode)
{
	if (strcmp(name, "idle") == 0)
		*mode = MODE_IDLE;
	else if (strcmp(name, "mailbox") == 0)
		*mode = MODE_MAILBOX;
	else if (strcmp(name, "vsync") == 0)
		*mode = MODE_VSYNC;
	else
		return false;
	return true;
}

int main(int argc, char *argv[])
{
	/* Static storage: the press table is large for a stack frame. */
	static struct probe probe;

	if (argc != 2 || !parse_mode(argv[1], &probe.mode)) {
		usage();
		return 2;
	}
	/* One line per press, each written out at once: a run that ends
	 * badly still leaves every reported press in the file. */
	setvbuf(stdout, NULL, _IOLBF, 0);
	probe.running = true;

	probe.display = wl_display_connect(NULL);
	if (probe.display == NULL) {
		const char *socket = getenv("WAYLAND_DISPLAY");

		fprintf(stderr, "latency-probe: cannot connect to a Wayland compositor"
			" (WAYLAND_DISPLAY=%s)\n", socket != NULL ? socket : "unset");
		return 1;
	}
	struct wl_registry *registry = wl_display_get_registry(probe.display);
	wl_registry_add_listener(registry, &registry_listener, &probe);
	/* The first roundtrip delivers the globals, the second the events
	 * they send right after binding (presentation clock, seat
	 * capabilities). */
	wl_display_roundtrip(probe.display);
	wl_display_roundtrip(probe.display);
	if (!check_globals(&probe)) {
		wl_display_disconnect(probe.display);
		return 1;
	}
	print_header(&probe, argv[1]);

	probe.surface = wl_compositor_create_surface(probe.compositor);
	probe.xdg_surface = xdg_wm_base_get_xdg_surface(probe.wm_base, probe.surface);
	xdg_surface_add_listener(probe.xdg_surface, &xdg_surface_listener, &probe);
	probe.xdg_toplevel = xdg_surface_get_toplevel(probe.xdg_surface);
	xdg_toplevel_add_listener(probe.xdg_toplevel, &toplevel_listener, &probe);
	xdg_toplevel_set_title(probe.xdg_toplevel, "latency-probe");
	xdg_toplevel_set_fullscreen(probe.xdg_toplevel, NULL);
	/* An initial commit without a buffer asks for the first configure;
	 * drawing starts from there. */
	wl_surface_commit(probe.surface);

	while (probe.running) {
		if (wl_display_dispatch(probe.display) < 0) {
			fprintf(stderr, "latency-probe: lost the Wayland connection: %s\n",
				strerror(errno));
			probe.exit_code = 1;
			break;
		}
	}
	/* In the CSV too, so that the data says whether any press had to
	 * wait for a buffer (it should never happen with cage's GLES2
	 * renderer, which copies wl_shm buffers and releases them at once). */
	printf("# frames delayed by no free buffer: %" PRIu32 "\n", probe.buffer_waits);
	fprintf(stderr, "latency-probe: %" PRIu32 " presses, %" PRIu32 " reported,"
		" %" PRIu32 " frames delayed by no free buffer\n",
		probe.generation, probe.reported_generation, probe.buffer_waits);
	wl_display_disconnect(probe.display);
	return probe.exit_code;
}
