# Builds latency-probe natively ("make") or under Buildroot, which passes
# CC, CFLAGS, LDFLAGS and PKG_CONFIG for the target, plus WAYLAND_SCANNER
# and WAYLAND_PROTOCOLS_DIR (see package/latency-probe/latency-probe.mk).

PKG_CONFIG ?= pkg-config
WAYLAND_SCANNER ?= wayland-scanner
WAYLAND_PROTOCOLS_DIR ?= $(shell $(PKG_CONFIG) --variable=pkgdatadir wayland-protocols)

CFLAGS ?= -O2
# Kept apart from CFLAGS: Buildroot passes CFLAGS on the make command line,
# which would silently override a "CFLAGS +=" here. -Wno-unused-parameter:
# Wayland listener callbacks have fixed signatures, and most handlers
# ignore most of their arguments.
ALL_CFLAGS = -std=c11 -Wall -Wextra -Wno-unused-parameter \
	$(shell $(PKG_CONFIG) --cflags wayland-client) $(CFLAGS)
LDLIBS = $(shell $(PKG_CONFIG) --libs wayland-client)

XDG_SHELL_XML = $(WAYLAND_PROTOCOLS_DIR)/stable/xdg-shell/xdg-shell.xml
PRESENTATION_TIME_XML = $(WAYLAND_PROTOCOLS_DIR)/stable/presentation-time/presentation-time.xml

GENERATED_HEADERS = xdg-shell-client-protocol.h presentation-time-client-protocol.h
GENERATED_SOURCES = xdg-shell-protocol.c presentation-time-protocol.c

all: latency-probe

latency-probe: latency-probe.c $(GENERATED_SOURCES) $(GENERATED_HEADERS)
	$(CC) $(ALL_CFLAGS) $(LDFLAGS) -o $@ latency-probe.c $(GENERATED_SOURCES) $(LDLIBS)

xdg-shell-client-protocol.h: $(XDG_SHELL_XML)
	$(WAYLAND_SCANNER) client-header $< $@

xdg-shell-protocol.c: $(XDG_SHELL_XML)
	$(WAYLAND_SCANNER) private-code $< $@

presentation-time-client-protocol.h: $(PRESENTATION_TIME_XML)
	$(WAYLAND_SCANNER) client-header $< $@

presentation-time-protocol.c: $(PRESENTATION_TIME_XML)
	$(WAYLAND_SCANNER) private-code $< $@

clean:
	rm -f latency-probe $(GENERATED_HEADERS) $(GENERATED_SOURCES)

.PHONY: all clean
