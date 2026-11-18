#!/bin/bash
# Installs extlinux (syslinux) into the boot partition of the assembled
# image board/osukiosk/output/osukiosk.img: step 5 of the
# build-osukiosk-image skill, needed after every genimage run. It needs
# root, so the author runs it:
#
#   sudo bash .claude/skills/build-osukiosk-image/install-extlinux.sh
#
# Claude checks the result afterwards without root: the OEM name SYSLINUX
# at byte 1048576 + 3, and ldlinux.sys and ldlinux.c32 in the partition
# (SKILL.md, step 5). extlinux's "unable to obtain device geometry" is
# harmless for an image file.
set -euo pipefail

# .claude/skills/build-osukiosk-image -> the repository root
REPO="$(realpath "$(dirname "$(realpath "$0")")/../../..")"
IMG="$REPO/board/osukiosk/output/osukiosk.img"
[ -f "$IMG" ] || {
	echo "install-extlinux: $IMG not found, run genimage first" >&2
	exit 1
}

MNT="$(mktemp -d)"
LOOPDEV=""

cleanup() {
	if mountpoint -q "$MNT" 2>/dev/null; then
		umount "$MNT"
	fi
	if [ -n "$LOOPDEV" ]; then
		losetup -d "$LOOPDEV" 2>/dev/null || true
	fi
	rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

LOOPDEV="$(losetup --find --show -P "$IMG")"
echo "Loop device: $LOOPDEV"
mount "${LOOPDEV}p1" "$MNT"
extlinux --install "$MNT"
sync
echo "extlinux installed."
