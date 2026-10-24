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
#             the boot: prompt.
#
#   After <boot-wait-s> (default 60) tty1 is screendumped. Each
#   tty2-command is then typed key by key, through the QEMU monitor, into
#   the tty2 root shell (inittab askfirst), and tty2 is screendumped last.
#
# Environment:
#   CMDLINE_EXTRA  extra kernel parameters, direct mode (e.g. osukiosk.hold)
#   BOOT_LINE      line typed at the syslinux boot: prompt, syslinux mode
#   QEMU_EXTRA     extra QEMU arguments, split on whitespace
#   STEP_WAIT      seconds to wait after each typed tty2 command (default 2)
#   FINAL_WAIT     extra seconds before the tty2 screendump (default 0)
#   FRESH_DATA=1   start direct mode from a new copy of data.img; by default
#                  the copy is reused, so /data/log written in one run can be
#                  read in the next one (e.g. a normal run, then a hold run)
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
#   the next run.
# - The kernel has no virtio-gpu driver, so on a normal boot cage waits
#   about 10 s for a KMS device, exits with "Found 0 GPUs" and init
#   respawns the session.
#
# Examples (from the repository root):
#   # Smoke test: boot to the session, screendump tty1.
#   board/osukiosk/qemu-test.sh direct smoke
#
#   # Diagnosis without cage taking over the console: hold mode + tty2.
#   CMDLINE_EXTRA=osukiosk.hold board/osukiosk/qemu-test.sh direct hold 60 -- \
#       'cat /proc/cmdline' 'tail -n 8 /data/log/cage.log'
#
#   # cage without a GPU: headless output, the guest's real keyboard through
#   # libinput, pixman renderer. The second command is typed into foot
#   # inside cage, the third one back into the tty2 shell.
#   CMDLINE_EXTRA=osukiosk.hold STEP_WAIT=5 board/osukiosk/qemu-test.sh direct kbd 60 -- \
#       'su -s /bin/sh kiosk -c "export XDG_RUNTIME_DIR=/run/user/900 LANG=C.UTF-8 WLR_BACKENDS=headless,libinput WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman; cage -- foot /bin/sh 2>/data/log/cage-kbd.log & sleep 10; kill \$!"' \
#       'touch /run/user/900/typed-ok' \
#       'ls -l /run/user/900/typed-ok'
#
#   # Emulated Intel HDA sound card.
#   CMDLINE_EXTRA=osukiosk.hold \
#   QEMU_EXTRA='-audiodev none,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0' \
#       board/osukiosk/qemu-test.sh direct audio 60 -- 'aplay -l'
#
#   # Full boot through syslinux, parameters typed at boot:.
#   BOOT_LINE='osukiosk osukiosk.hold' board/osukiosk/qemu-test.sh syslinux sys 50 -- \
#       'cat /proc/cmdline'

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
	require data.img "the F2FS data partition template"
	DATA=$ART/data.img
	if [ "${FRESH_DATA:-0}" = 1 ] || [ ! -e "$DATA" ]; then
		cp --sparse=always data.img "$DATA" || exit 1
		echo "data: fresh copy of data.img"
	else
		echo "data: reusing $DATA (FRESH_DATA=1 for a new copy)"
	fi
	BOOT_ARGS=(
		-kernel "$KERNEL"
		-append "console=tty1 console=ttyS0 loglevel=7 ${CMDLINE_EXTRA:-}"
		-drive "file=output/boot.vfat,if=none,id=usbboot,format=raw,snapshot=on"
		-device usb-storage,drive=usbboot
		-drive "file=$DATA,if=none,id=usbdata,format=raw"
		-device usb-storage,drive=usbdata
	)
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

# QEMU_EXTRA is split on whitespace on purpose: it carries several options.
# shellcheck disable=SC2086
qemu-system-x86_64 -m 2048 \
	-device virtio-gpu-pci \
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

# Types one line, then Enter. QEMU holds each sendkey for its hold time
# (30 ms here) and processes them one after another, so a long line written
# at once over a connection that then closes loses its tail and can leave
# Shift pressed. The keys are therefore paced over one connection that stays
# open until the last of them has been handled.
type_line() {
	local line=$1 i key keys=()
	for ((i = 0; i < ${#line}; i++)); do
		key=$(key_for "${line:i:1}") || return 1
		keys+=("$key")
	done
	{
		for key in "${keys[@]}"; do
			echo "sendkey $key 30"
			sleep 0.08
		done
		echo "sendkey ret 30"
		sleep 1
	} | nc -U -q1 "$SOCK" >/dev/null
}

echo "QEMU PID $QEMU_PID, $MODE mode, waiting ${WAIT}s for the boot..."

if [ "$MODE" = syslinux ]; then
	# The boot: prompt stays up for 3 s (TIMEOUT 30 in extlinux.conf);
	# SeaBIOS and syslinux get there well within the first second, and the
	# first typed key stops the countdown.
	sleep 0.5
	screendump boot-prompt
	if [ -n "${BOOT_LINE:-}" ]; then
		type_line "$BOOT_LINE" || exit 1
	fi
fi

sleep "$WAIT"
screendump tty1

if [ $# -gt 0 ]; then
	mon "sendkey ctrl-alt-f2"
	sleep 2
	# askfirst: "Please press Enter to activate this console."
	mon "sendkey ret"
	sleep 2
	for cmd in "$@"; do
		type_line "$cmd" || exit 1
		sleep "${STEP_WAIT:-2}"
	done
	sleep "${FINAL_WAIT:-0}"
	screendump tty2
fi
