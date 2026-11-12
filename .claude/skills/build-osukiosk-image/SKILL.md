---
name: build-osukiosk-image
description: Use whenever assembling or re-assembling the bootable osukiosk.img (after any change to bzImage, rootfs.squashfs, or data.img). Encodes the exact genimage + MBR + syslinux install procedure, including three ordering/naming pitfalls already hit once in this project. Trigger on requests like "zbuduj obraz", "złóż osukiosk.img", "przygotuj pendrive", or after rebuilding the kernel/rootfs.
---

# Building osukiosk.img

This procedure assembles the final bootable image from already-built artifacts
(`bzImage`, `rootfs.squashfs`, `data.img`). It does NOT rebuild Buildroot itself —
run `make` (main system) or the relevant kernel rebuild first if sources changed.

## Prerequisites — verify before starting

- `buildroot/output/images/bzImage` exists and is newer than the last image build
  (this is the MAIN system kernel with initramfs embedded via
  `CONFIG_INITRAMFS_SOURCE` — never confuse with any `bzImage` under
  `output-initramfs`, which is a different, non-bootable build).
- `buildroot/output/images/rootfs.squashfs` exists.
- `osu-kiosk-external/board/osukiosk/data.img` exists (F2FS, label
  `OSUKIOSK_DATA`). Only regenerate this if you intentionally want to wipe
  persistent data — normally it's reused across image rebuilds.

## Steps

1. **Stage boot files.** Copy `bzImage` and `rootfs.squashfs` from
   `buildroot/output/images/` into `osu-kiosk-external/board/osukiosk/`. That
   is the directory `genimage` reads through `--inputpath .` (step 3), next to
   `genimage-osukiosk.cfg`, `extlinux.conf` and `data.img`. Files referenced in
   `genimage-osukiosk.cfg` that are not physically present there fail with
   `stat() failed`, not a clearer error. Do NOT stage into a `boot-files/`
   directory: `genimage` never reads it, so anything copied there silently
   does not reach the image (the old `boot-files/` directory held only stale
   copies and was removed).

2. **Check the FAT volume label.** The boot partition label lives only in
   `genimage-osukiosk.cfg` (currently `OSUBOOT`) and must be **≤ 11
   characters** (FAT hard limit, FAT16 and FAT32 alike). Nothing looks the
   partition up by its label: the initramfs `/init` iterates over `/dev/sd*`
   and `/dev/nvme*n1p*`, mounts each candidate as vfat and boots from the
   first one that has `rootfs.squashfs` at its root. Changing the label
   therefore needs no initramfs rebuild.

3. **Run genimage:**
   ```bash
   cd osu-kiosk-external/board/osukiosk
   genimage --config genimage-osukiosk.cfg --outputpath output/ --inputpath .
   ```
   Then check that the image really contains the fresh files. `mtools` can
   read the intermediate `boot.vfat`; the two checksums per file must match:
   ```bash
   for f in bzImage rootfs.squashfs; do
       mcopy -i output/boot.vfat ::$f - | md5sum
       md5sum ../../../buildroot/output/images/$f
   done
   ```

4. **Install the MBR bootstrap code** (does not include the partition table —
   `bs=440 count=1` intentionally stops before it, which starts at byte 446):
   ```bash
   dd if=/usr/lib/syslinux/mbr/mbr.bin of=output/osukiosk.img bs=440 count=1 conv=notrunc
   ```

5. **Install extlinux on the FINAL image, not the intermediate `boot.vfat`.**
   This is the pitfall already hit once: `genimage` packs `boot.vfat` *into*
   `osukiosk.img`; running `extlinux --install` on the standalone `boot.vfat`
   file afterward has no effect on the actual image. Always loop-mount the
   assembled `.img`:
   ```bash
   sudo losetup -fP output/osukiosk.img     # note the loop device it reports, e.g. /dev/loop0
   sudo mount /dev/loopXp1 /mnt
   sudo extlinux --install /mnt
   sudo umount /mnt
   sudo losetup -d /dev/loopX
   ```
   **This step runs as root, and Claude cannot run it on its own**: `sudo`
   asks for a password that Claude's shell cannot enter. Claude writes the
   commands into a script (temporary mount point from `mktemp -d`,
   `losetup --find --show -P`, a `trap` that always unmounts and detaches the
   loop device, `sync` before that) and hands over a single line for the
   person to run with the `!` prefix: `! sudo bash <script>`. The warning
   `unable to obtain device geometry` printed by `extlinux` is harmless for
   an image file. Afterwards Claude verifies the result without root
   (partition 1 starts at 1 MiB, byte offset 1048576 or sector 2048, from
   `align = 1M` in `genimage-osukiosk.cfg`; confirm with
   `sfdisk -d output/osukiosk.img`):
   ```bash
   dd if=output/osukiosk.img bs=1 skip=$((1048576+3)) count=8 2>/dev/null   # OEM name: SYSLINUX (before step 5: mkfs.fat)
   mdir -a -i output/osukiosk.img@@1048576 ::                               # must list ldlinux.sys and ldlinux.c32
   ```

6. **Report the result** and hand off a `dd` command for the person to run
   themselves — Claude does not execute `dd` to a physical block device without
   the person first confirming the exact `/dev/sdX` via `lsblk` in that same
   turn. Provide the command with a reminder to double check. A stick that was
   flashed before is usually auto-mounted under `/media/<user>/`, so its
   partitions must be unmounted first:
   ```bash
   lsblk   # confirm the exact device — wrong choice destroys data irrecoverably
   sudo umount /dev/sdX1 /dev/sdX2   # only if lsblk shows them mounted
   sudo dd if=osu-kiosk-external/board/osukiosk/output/osukiosk.img of=/dev/sdX bs=4M status=progress conv=fsync
   ```

## Updating a flashed stick without dd

`dd` rewrites the whole stick, the data partition included, so beatmaps,
scores, settings and logs on `/data` are lost. It is needed only for the
first flash and whenever the partition layout in `genimage-osukiosk.cfg`
changes (a stick flashed before Stage 6 still has the old 256 MB boot
partition). While the layout stays the same, an update replaces just
`bzImage` and `rootfs.squashfs` on the boot partition (`OSUBOOT`, FAT32,
1 GiB) and leaves `/data` alone; steps 3 to 6 are then not needed at all.

This writes to the physical stick and needs root, so Claude writes a
script and hands over a single `! sudo bash <script>` line, as in step 5.
The script:
- finds the partition by its label (`blkid -L OSUBOOT`) and stops unless
  exactly one partition has that label and `lsblk -no TRAN` reports `usb`
  for its disk;
- mounts it on a `mktemp -d` mount point, with a `trap` that unmounts;
- copies each file under a temporary name first and then renames it, so
  an interrupted copy never leaves a half-written file under the name the
  bootloader or the initramfs looks for (the partition must have room for
  the old and the new `rootfs.squashfs` at the same time):
  ```bash
  cp buildroot/output/images/rootfs.squashfs "$mnt/rootfs.squashfs.new"
  mv "$mnt/rootfs.squashfs.new" "$mnt/rootfs.squashfs"   # the same for bzImage
  ```
- compares checksums with `buildroot/output/images/`, then runs `sync`.

## Common failure signature

If genimage succeeds but the resulting image doesn't boot or doesn't find the
boot partition, check in this order: (1) whether the boot partition holds
`rootfs.squashfs` at its root, which is what `/init` looks for (see step 2),
(2) whether step 5 was
run against the final `.img` and not the intermediate `boot.vfat`, (3) whether
`board/osukiosk/` actually contains the freshly rebuilt `bzImage` and
`rootfs.squashfs` (stale copies are a frequent silent-cause here; the
checksum comparison after step 3 catches it).
