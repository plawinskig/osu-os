#!/bin/bash
# Updates a flashed osu!kiosk pendrive without dd (build-osukiosk-image
# skill, "Updating a flashed stick without dd"): replaces bzImage and
# rootfs.squashfs on its boot partition (label OSUBOOT, FAT32) and leaves
# the data partition (/data) and the bootloader alone. Only for a stick
# with the current layout (1 GiB FAT32 at 1 MiB); a layout change needs
# the full dd. Needs root, so the author runs it; it leaves the whole
# pendrive unmounted, ready to unplug.
#
#   sudo bash .claude/skills/build-osukiosk-image/update-stick.sh [image-dir]
#
# image-dir holds the two files and defaults to buildroot/output/images
# next to the repository. Another folder brings back a saved pair, e.g. a
# copy of the last working build.
set -euo pipefail

# .claude/skills/build-osukiosk-image -> the repository root
REPO="$(realpath "$(dirname "$(realpath "$0")")/../../..")"
IMAGES="$(realpath "${1:-$REPO/../buildroot/output/images}")"
FILES=(bzImage rootfs.squashfs)

die() {
	echo "update-stick: $*" >&2
	exit 1
}

for file in "${FILES[@]}"; do
	[ -f "$IMAGES/$file" ] || die "$IMAGES/$file not found"
done

# The pendrive's partition with the given label: exactly one, on a USB
# disk, so that a loop device of osukiosk.img or another disk never gets
# written by mistake. No blkid cache: it can list a stick that is gone.
find_partition() {
	local label=$1 devices disk

	mapfile -t devices < <(blkid -c /dev/null -t "LABEL=$label" -o device || true)
	[ "${#devices[@]}" = 1 ] ||
		die "expected one partition labelled $label, found ${#devices[@]}: ${devices[*]:-none} - is the pendrive plugged in?"
	disk="$(lsblk -no PKNAME "${devices[0]}")"
	[ "$(lsblk -dno TRAN "/dev/$disk")" = usb ] ||
		die "${devices[0]} ($label) is not on a USB disk"
	echo "${devices[0]}"
}

MNT=""
cleanup() {
	if [ -n "$MNT" ]; then
		umount "$MNT" 2>/dev/null || true
		rmdir "$MNT" 2>/dev/null || true
	fi
}
trap cleanup EXIT

# Unmounts every mount of a device, e.g. a desktop automount.
unmount_all() {
	while findmnt -n --source "$1" > /dev/null; do
		umount "$1"
	done
}

DEV="$(find_partition OSUBOOT)"
unmount_all "$DEV"
MNT="$(mktemp -d)"
mount -t vfat "$DEV" "$MNT"

# Each new file is written next to the old one first, so the partition
# needs room for both at the same time.
need_kib=0
for file in "${FILES[@]}"; do
	need_kib=$((need_kib + $(stat -c %s "$IMAGES/$file") / 1024 + 1))
done
free_kib="$(df -k --output=avail "$MNT" | tail -n 1)"
[ "$free_kib" -ge "$need_kib" ] ||
	die "$DEV has $free_kib KiB free, the new files need $need_kib KiB"

# A copy under a temporary name, then a rename: an interrupted copy never
# leaves a half-written file under the name that syslinux or the
# initramfs looks for.
for file in "${FILES[@]}"; do
	cp "$IMAGES/$file" "$MNT/$file.new"
	sync
	mv "$MNT/$file.new" "$MNT/$file"
done
sync
umount "$MNT"

# Mounted again, read-only: the comparison reads the stick, not what the
# copy left in memory.
mount -o ro -t vfat "$DEV" "$MNT"
for file in "${FILES[@]}"; do
	cmp "$IMAGES/$file" "$MNT/$file"
	echo "update-stick: $file on the stick == $IMAGES/$file ($(md5sum < "$MNT/$file" | cut -d' ' -f1))"
done
ls -l "$MNT"
umount "$MNT"
rmdir "$MNT"
MNT=""

# The data partition may be automounted as well.
if DATA_DEV="$(find_partition OSUKIOSK_DATA 2>/dev/null)"; then
	unmount_all "$DATA_DEV"
fi
echo "update-stick: the pendrive is unmounted and can be unplugged"
