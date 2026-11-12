#!/bin/bash
# QEMU test driver for osu!kiosk. Runs from any directory: all paths are
# relative to this script's directory (board/osukiosk/).
#
# Usage:
#   qemu-test.sh direct   <name> [boot-wait-s] [-- tty2-command ...]
#   qemu-test.sh syslinux <name> [boot-wait-s] [-- tty2-command ...]
#
#   direct    Boots ../../../buildroot/output/images/bzImage directly, with
#             output/boot.vfat and a sparse copy of data.img attached as two
#             USB sticks. console=ttyS0 is added, so kernel messages land in
#             the serial log.
#   syslinux  Boots the assembled output/osukiosk.img through SeaBIOS and
#             syslinux, the same path a real laptop takes. The kernel
#             command line comes from extlinux.conf; BOOT_LINE is typed at
#             the boot: prompt (a label such as "debug", optionally
#             followed by kernel parameters).
#
#   After <boot-wait-s> (default 60) tty1 is screendumped. Each
#   tty2-command is then typed key by key, through the QEMU monitor, into
#   the tty2 root shell, and tty2 is screendumped last. That shell exists
#   only with osukiosk.debug or osukiosk.hold on the kernel command line
#   (CMDLINE_EXTRA, or BOOT_LINE=debug / hold); a normal boot has none.
#   A tty2-command of the form mon:<command> is not typed: <command> goes
#   to the QEMU monitor as it is (a single key such as "sendkey esc", a
#   "mouse_button 1", or an extra "screendump qemu-artifacts/<name>-x.ppm",
#   which is converted to PNG like the others).
#
# Environment:
#   CMDLINE_EXTRA  extra kernel parameters, direct mode (e.g. osukiosk.debug)
#   BOOT_LINE      line typed at the syslinux boot: prompt, syslinux mode
#   QEMU_EXTRA     extra QEMU arguments, split on whitespace
#   QEMU_MEM       guest RAM in MiB (default 4096; the system image alone
#                  takes its own size of RAM, and the game needs more)
#   QEMU_VGA       display device options, split on whitespace (default
#                  "-vga virtio": one virtio-vga screen that shows SeaBIOS,
#                  syslinux and the text console, then cage; two outputs:
#                  "-vga none -device virtio-vga,max_outputs=2,id=gpu")
#   KVM=0          emulate the CPU instead of using KVM; by default KVM is
#                  used whenever /dev/kvm is usable
#   STEP_WAIT      seconds to wait after each typed tty2 command (default 2)
#   FINAL_WAIT     extra seconds before the tty2 screendump (default 0)
#   FRESH_DATA=1   start direct mode from a new copy of data.img; by default
#                  the copy is reused, so /data written in one run can be
#                  read in the next one (e.g. a normal run, then a debug run)
#   NO_DATA=1      direct mode without the data stick, like a machine on
#                  which the data partition is missing
#
# Artifacts go to qemu-artifacts/ next to this script (gitignored): PNG
# screendumps, the serial log, the data.img copy and the monitor socket,
# whose relative path stays under the 108-byte socket path limit. QEMU
# never writes to data.img or output/osukiosk.img: direct mode uses the
# copy, syslinux mode and the boot.vfat stick use snapshot=on. Do not run
# two direct-mode instances at once, they would share the data copy.
#
# Reading the results:
# - The end of a run ("quit") is a power cut for the guest: F2FS rolls
#   /data back to its last checkpoint, so only synced files survive into
#   the next run. A "poweroff" typed as the last tty2-command shuts the
#   guest down cleanly instead (rcK runs and /data is unmounted), and QEMU
#   exits by itself; the final tty2 screendump is then missing.
# - cage runs on the virtio-vga output: udev loads virtio-gpu like any
#   other driver module, Mesa has no virtio driver in the image and falls
#   back to kms_swrast (llvmpipe), so the session renders in software.
#   A screendump shows the active VT: cage on tty1, the text console on
#   the others.
# - The tty2 screendump holds only the last 25 lines. In direct mode, a
#   first tty2-command of 'exec >/dev/ttyS0 2>&1' sends the output of all
#   the following ones to the serial log instead.
#
# Examples (from the repository root):
#   # Smoke test: boot to the session, screendump tty1.
#   board/osukiosk/qemu-test.sh direct smoke
#
#   # Diagnosis without cage taking over the console: hold mode + tty2.
#   # Hold mode leaves the logs of the previous run untouched.
#   CMDLINE_EXTRA=osukiosk.hold board/osukiosk/qemu-test.sh direct hold 60 -- \
#       'cat /proc/cmdline' 'tail -n 8 /data/log/session.log'
#
#   # The whole session without a GPU, started by init. Hold mode keeps tty2
#   # stable (in debug mode the crash-looping cage switches to tty1 every
#   # 10 s). The session script is swapped for a copy that selects cage's
#   # headless output, the pixman renderer and the guest's real keyboard
#   # through libinput (su passes WLR_* on), skips the hold check and adds
#   # -s; killing the hold session's sleep makes init start that copy. The
#   # next two lines are typed into foot inside cage: "exit" there makes init
#   # start the session again, and Ctrl+Alt+F2 (-s) leads back to tty2.
#   CMDLINE_EXTRA=osukiosk.hold STEP_WAIT=8 board/osukiosk/qemu-test.sh direct chain 25 -- \
#       'sed -e "2i export WLR_BACKENDS=headless,libinput WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman" -e "s/^if has_boot_flag osukiosk.hold; then$/if false; then/" -e "s/^CAGE_FLAGS=$/CAGE_FLAGS=-s/" /usr/bin/osukiosk-session >/run/s' \
#       'chmod 0755 /run/s; mount --bind /run/s /usr/bin/osukiosk-session; kill $(pidof sleep)' \
#       'touch $HOME/typed-ok' 'exit' \
#       'mon:sendkey ctrl-alt-f2' 'ls -l /data/home/typed-ok; grep -c "cage flags: -s" /data/log/session.log*'
#
#   # Raw monitor commands between typed lines: back to tty1 for an extra
#   # screendump in the middle of the run, then on in the tty2 shell.
#   CMDLINE_EXTRA=osukiosk.hold board/osukiosk/qemu-test.sh direct mon 60 -- \
#       'mon:sendkey ctrl-alt-f1' 'mon:screendump qemu-artifacts/mon-tty1-again.ppm' \
#       'mon:sendkey ctrl-alt-f2' 'cat /proc/cmdline'
#
#   # Emulated Intel HDA sound card; the mixer levels come from the udev
#   # rule and S42alsa (/data/alsa/asound.state, saved by a clean poweroff).
#   CMDLINE_EXTRA=osukiosk.hold \
#   QEMU_EXTRA='-audiodev none,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0' \
#       board/osukiosk/qemu-test.sh direct audio 60 -- 'aplay -l' 'amixer -c 0 sget Master'
#
#   # No data partition: the serial log shows the fallback to tmpfs.
#   NO_DATA=1 board/osukiosk/qemu-test.sh direct nodata 40
#
#   # Full boot through syslinux, a label typed at boot:.
#   BOOT_LINE=hold board/osukiosk/qemu-test.sh syslinux sys 50 -- 'cat /proc/cmdline'

set -uo pipefail
# Character classes in key_for and the generated file names assume C.
export LC_ALL=C

cd "$(dirname "$0")" || exit 1

usage() {
	echo "usage: $0 direct|syslinux <name> [boot-wait-s] [-- tty2-command ...]" >&2
	exit 2
}

require() {
	[ -e "$1" ] || { echo "qemu-test.sh: missing $1 ($2)" >&2; exit 1; }
}

MODE=${1:-}
NAME=${2:-}
[ -n "$MODE" ] && [ -n "$NAME" ] || usage
shift 2
WAIT=60
if [ $# -gt 0 ] && [ "$1" != "--" ]; then
	WAIT=$1
	shift
fi
if [ $# -gt 0 ]; then
	[ "$1" = "--" ] || usage
	shift
fi

ART=qemu-artifacts
SOCK=$ART/mon-$NAME.sock
SERIAL=$ART/serial-$NAME.log
KERNEL=../../../buildroot/output/images/bzImage
mkdir -p "$ART"
rm -f "$SOCK" "$SERIAL" "$ART/$NAME"-*.png "$ART/$NAME"-*.ppm

case "$MODE" in
direct)
	require "$KERNEL" "build the main system first"
	require output/boot.vfat "run genimage first, see the build-osukiosk-image skill"
	BOOT_ARGS=(
		-kernel "$KERNEL"
		-append "console=tty1 console=ttyS0 loglevel=7 ${CMDLINE_EXTRA:-}"
		-drive "file=output/boot.vfat,if=none,id=usbboot,format=raw,snapshot=on"
		-device usb-storage,drive=usbboot
	)
	if [ "${NO_DATA:-0}" = 1 ]; then
		echo "data: none (NO_DATA=1)"
	else
		require data.img "the F2FS data partition template"
		DATA=$ART/data.img
		if [ "${FRESH_DATA:-0}" = 1 ] || [ ! -e "$DATA" ]; then
			cp --sparse=always data.img "$DATA" || exit 1
			echo "data: fresh copy of data.img"
		else
			echo "data: reusing $DATA (FRESH_DATA=1 for a new copy)"
		fi
		BOOT_ARGS+=(
			-drive "file=$DATA,if=none,id=usbdata,format=raw"
			-device usb-storage,drive=usbdata
		)
	fi
	;;
syslinux)
	require output/osukiosk.img "assemble it, extlinux included, with the build-osukiosk-image skill"
	BOOT_ARGS=(
		-drive "file=output/osukiosk.img,if=none,id=stick,format=raw,snapshot=on"
		-device usb-storage,drive=stick,bootindex=0
	)
	;;
*)
	usage
	;;
esac

# Without KVM, QEMU emulates every instruction: the system still boots,
# but the .NET game and the llvmpipe software renderer become unusably
# slow.
KVM_ARGS=()
if [ "${KVM:-1}" = 1 ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
	KVM_ARGS=(-enable-kvm -cpu host -smp 4)
else
	echo "qemu-test.sh: running without KVM, the guest CPU is emulated" >&2
fi

# QEMU_VGA and QEMU_EXTRA are split on whitespace on purpose: they carry
# several options.
# shellcheck disable=SC2086
qemu-system-x86_64 -m "${QEMU_MEM:-4096}" \
	"${KVM_ARGS[@]}" \
	${QEMU_VGA:--vga virtio} \
	-device qemu-xhci \
	"${BOOT_ARGS[@]}" \
	-serial "file:$SERIAL" \
	-monitor "unix:$SOCK,server,nowait" \
	-display none \
	-no-reboot \
	${QEMU_EXTRA:-} &
QEMU_PID=$!

# One-shot monitor commands; nc closes the connection 1 s after its input
# ends, which is plenty for anything but long sendkey sequences.
mon() {
	printf '%s\n' "$@" | nc -U -q1 "$SOCK" >/dev/null
}

screendump() {
	mon "screendump $ART/$NAME-$1.ppm"
}

finish() {
	if kill -0 "$QEMU_PID" 2>/dev/null; then
		mon quit || kill "$QEMU_PID"
		wait "$QEMU_PID" 2>/dev/null
	fi
	rm -f "$SOCK"
	local ppm
	for ppm in "$ART/$NAME"-*.ppm; do
		[ -e "$ppm" ] || continue
		if command -v convert >/dev/null; then
			convert "$ppm" "${ppm%.ppm}.png" && rm -f "$ppm"
		fi
	done
	ls -1 "$ART/$NAME"-* "$SERIAL" 2>/dev/null
}
trap finish EXIT

for _ in $(seq 1 100); do
	[ -S "$SOCK" ] && break
	sleep 0.05
done
if [ ! -S "$SOCK" ]; then
	echo "qemu-test.sh: the QEMU monitor socket $SOCK did not appear" >&2
	exit 1
fi

# QEMU sendkey name for one character of a US keyboard layout.
key_for() {
	local c=$1
	case "$c" in
	[a-z0-9]) echo "$c" ;;
	[A-Z]) echo "shift-${c,,}" ;;
	' ') echo spc ;;
	'-') echo minus ;;         '_') echo shift-minus ;;
	'=') echo equal ;;         '+') echo shift-equal ;;
	'[') echo bracket_left ;;  '{') echo shift-bracket_left ;;
	']') echo bracket_right ;; '}') echo shift-bracket_right ;;
	';') echo semicolon ;;     ':') echo shift-semicolon ;;
	"'") echo apostrophe ;;    '"') echo shift-apostrophe ;;
	'`') echo grave_accent ;;  '~') echo shift-grave_accent ;;
	'\') echo backslash ;;     '|') echo shift-backslash ;;
	',') echo comma ;;         '<') echo shift-comma ;;
	'.') echo dot ;;           '>') echo shift-dot ;;
	'/') echo slash ;;         '?') echo shift-slash ;;
	'!') echo shift-1 ;;       '@') echo shift-2 ;;
	'#') echo shift-3 ;;       '$') echo shift-4 ;;
	'%') echo shift-5 ;;       '^') echo shift-6 ;;
	'&') echo shift-7 ;;       '*') echo shift-8 ;;
	'(') echo shift-9 ;;       ')') echo shift-0 ;;
	*)
		echo "qemu-test.sh: no key for character '$c'" >&2
		return 1
		;;
	esac
}

# Types one line, then Enter unless the second argument is "no-enter".
# QEMU holds each sendkey for its hold time (30 ms here) and processes them
# one after another, so a long line written at once over a connection that
# then closes loses its tail and can leave Shift pressed. The keys are
# therefore paced over one connection that stays open until the last of
# them has been handled.
type_line() {
	local line=$1 enter=${2:-enter} i key keys=()
	for ((i = 0; i < ${#line}; i++)); do
		key=$(key_for "${line:i:1}") || return 1
		keys+=("$key")
	done
	{
		for key in "${keys[@]}"; do
			echo "sendkey $key 30"
			sleep 0.08
		done
		if [ "$enter" != no-enter ]; then
			echo "sendkey ret 30"
		fi
		sleep 1
	} | nc -U -q1 "$SOCK" >/dev/null
}

echo "QEMU PID $QEMU_PID, $MODE mode, waiting ${WAIT}s for the boot..."

if [ "$MODE" = syslinux ]; then
	# SeaBIOS and syslinux reach the boot: prompt within half a second, and
	# the prompt counts down only 1 s (TIMEOUT 10 in extlinux.conf). A
	# screendump takes about as long (nc waits 1 s before it closes), so
	# BOOT_LINE is typed first, its first key stopping the countdown, and
	# Enter follows the screendump of the typed line.
	sleep 0.5
	if [ -n "${BOOT_LINE:-}" ]; then
		type_line "$BOOT_LINE" no-enter || exit 1
		screendump boot-prompt
		mon "sendkey ret"
	else
		screendump boot-prompt
	fi
fi

sleep "$WAIT"
screendump tty1

if [ $# -gt 0 ]; then
	mon "sendkey ctrl-alt-f2"
	sleep 2
	# A fresh prompt line before the first command; an empty command line
	# does no harm, and without a debug shell nothing reads it.
	mon "sendkey ret"
	sleep 2
	for cmd in "$@"; do
		case "$cmd" in
		mon:*) mon "${cmd#mon:}" ;;
		*) type_line "$cmd" || exit 1 ;;
		esac
		sleep "${STEP_WAIT:-2}"
	done
	sleep "${FINAL_WAIT:-0}"
	screendump tty2
fi
