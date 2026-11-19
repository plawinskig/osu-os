---
name: boot-time
description: Use when measuring or shortening the kiosk's boot time (power button or boot prompt to the game's main menu) on the Lenovo Z570 or in QEMU - the boot timeline tool (demo.sh measure and speed), the measure boot line, what each segment of the timeline means, QEMU A/B runs of saved builds, what branch demo-fast-boot already fixed and what is left. Trigger on "czas startu", "szybszy boot", "zmierz boot", "oś czasu bootu", "printk.time", "initcall_debug", or after any change to the initramfs, the kernel config, the rootfs compression or the init scripts.
---

# Boot time: measuring and shortening it

Worked out in the demo session of 18–19.11.2026 (branch `demo-fast-boot`,
round folder `/home/greggy/Repos/osuos/measurements/demo-fast-boot/`, whose
README has every number below and the full analysis). The general round
procedure (tools on `/data`, hand-off, analysis) is the skill
`hardware-test-round`; this one adds what is specific to boot time.

## Where things stand

Z570, seconds from kernel start (stopwatch adds about 1 s for syslinux
loading `bzImage`):

| Segment | e97d9a0 (main) | v2b (`demo-fast-boot`) |
|---|---|---|
| kernel to `/init` | 2.24 | 0.31 |
| `/init` to pendrive detected | 2.95 | 2.90 |
| usb-storage `delay_use` | 1.13 | 0.12 |
| pendrive ready to copy start | 4.48 | 0.26 |
| copy of the image to RAM | 11.54 (221 MiB, 19.2 MiB/s) | 10.13 (235 MiB, 23.2 MiB/s) |
| switch_root to session | 3.64 | 2.48 |
| session to cage | 0.08 | 0.08 |
| cage to game | 2.31 | 0.48 |
| game to menu | 14.3 | 9.9 |
| **menu** | **42.7** | **26.7** |

v2b reaches the menu 36 s after the power button, with the BIOS booting
USB HDD first (set on the Z570 on 19.11.2026). It lives on branch
`demo-fast-boot` (commits `fd1dfee`..`533aed1`), not on main: which of its
changes go to main is the author's decision.

## Tools

In the round folder (outside the repository):
- `demo.sh` (BusyBox ash, on `/data`, root on tty2):
  - `measure`, in a measure boot once the menu shows: the timeline below,
    image and pendrive bytes read, the slowest initcalls and module inits;
    saved to `/data/log/demo-measure.txt` and `/data/log/demo-dmesg.txt`;
  - `speed`, in a `hold` boot: squashfs decompression (one file, two at
    once) and pendrive reads at several `read_ahead_kb` values and with
    `max_sectors` 2048, with `/data` remounted read-only; saved to
    `/data/log/demo-speed.txt`.
- `upload-demo.sh` (sudo): only `demo.sh` onto `/data`; also compares the
  boot files on `OSUBOOT` with `../../images-main-e97d9a0/MD5SUMS` (point it
  at the current baseline when that changes).
- `build-variant.sh <name> [reconfigure|rebuild|none]`: initramfs, kernel,
  main system, then the pair in `../../images-demo/<name>/` for
  `update-stick.sh` and for QEMU.
- `qemu/make-vfat.sh`, `qemu/qemu-ab.sh`, `qemu/data-get.sh`,
  `qemu/results/` (see "QEMU A/B").
- Logs back: `../stage6-round1/copy-logs.sh <name>`, a name relative to
  that script's folder (e.g. `../demo-fast-boot/logs-c`), never an
  absolute path.

## Measuring on the Z570

- Type at `boot:` (Space first stops the 1 s countdown):
  `debug quiet printk.time=1 initcall_debug log_buf_len=4M`
  - `printk.time=1`: timestamps; the kernel has no `CONFIG_PRINTK_TIME`;
  - `initcall_debug`: duration of every initcall, module init (i915 is
    one) and PCI fixup, with names (`KALLSYMS` is on);
  - `log_buf_len=4M`: `initcall_debug` overflows the default 256 KiB
    buffer;
  - `quiet`: the console stays as quiet as in a normal boot, since
    printing to it costs time;
  - `debug`: the root shell on tty2; the only other difference from a
    normal boot is `cage -s`.
- Stopwatch from Enter at `boot:` to the menu, and from the power button
  (BIOS POST is about 7 s). Stopwatch minus the menu's uptime is the
  bootloader's share.
- `sh /data/demo.sh measure` right after the menu shows; `speed` needs a
  separate `hold` boot.
- Every segment has its own mechanism, so one bundle of changes per round
  still shows the effect of each change. Normal boots with a stopwatch
  plus one measure boot make a round.

## Reading the timeline

- start → `Run /init`: kernel init. PCI fixups over 10 ms are logged even
  without `initcall_debug` ("... took N usecs").
- `Run /init` → pendrive detected: USB enumeration. The stick 090c:1000
  alone needs 2.3 s to answer its descriptor after a port reset (the host
  sees the same), so this is the stick, not the laptop.
- detected → responds: usb-storage `delay_use`.
- ready → found → copy start: the initramfs search loop. The copy start is
  computed back from the copy's own duration, so anything between the copy
  and its log line lands here (once a `wc -c` of 2.6 s).
- switch_root → session: rcS. Process starts mark the scripts: syslogd
  S01, udevd S10 (coldplug and settle follow), crond S50 (coldplug,
  S41mountdata and S42alsa are done), seatd S70, acpid means rcS is done.
- session → cage: `dmesg.txt` and `sync`. cage → game: cage's own start
  (Mesa/EGL load and modeset times are in its log).
- `~` lines come from the game's log, which has whole seconds: each is a
  lower bound, the event happened within the following second, so the
  first game log line can sort before earlier events.
- "Obraz w RAM: przeczytane X MiB": compressed bytes read from the image up
  to the menu (80 of 235 MiB in v2b), the most that squashfs straight from
  the stick would read.

## QEMU A/B

1. Save each build: `build-variant.sh <name> …` (or copy the pair into
   `../../images-demo/<name>/`).
2. `qemu/make-vfat.sh <pair dir> <scratchpad>/boot-<name>.vfat`.
3. `qemu/qemu-ab.sh <name> <bzImage> <vfat> 2`: measure boots with
   `demo.sh measure`, timelines in `qemu/results/`. It needs
   `QEMU_KERNEL`/`QEMU_BOOT_VFAT` in `qemu-test.sh` (branch
   `demo-fast-boot`) and `demo.sh` on QEMU's data copy; `sload.f2fs` never
   overwrites, so load a new version into a fresh copy.

QEMU shows the direction only: its CPU decompresses XZ about twice as fast
as the Z570's (45.6 against 23.7 MiB/s), its USB sticks answer at once, it
has no PCIe quirk, and the game's times are whole seconds. e97d9a0 reached
the menu in 13.8–15.6 s there, v2b in 7.6–8.8 s.

## What was found and fixed on demo-fast-boot

| Cost on the Z570 | Fix (commit) |
|---|---|
| 2.0 s: kernel 6.18.48 retrains the empty PCIe root port 00:1c.0 ("removing 2.5GT/s downstream link speed restriction", "retraining failed") | kernel patch: lift the restriction only on an active link (`4d92878`) |
| 2.6 s: BusyBox `wc -c` reads the whole image byte by byte to size it (a bug on main since `6d00f26`) | size from `ls -ln` (`86a2b99`) |
| 1.9 s: the stick is looked for every 2 s | every 0.2 s (`86a2b99`) |
| 1.1 s: usb-storage `delay_use` | set to 0 from `/init`, before the stick is probed (`86a2b99`) |
| 2 s of copying: 120 KiB transfers | `max_sectors` 2048 for the copy only (`86a2b99`) |
| about 7–8 s: XZ squashfs decompression at 23.7 MiB/s, one decompressor | zstd level 22 rootfs (+7% size), `SQUASHFS_FILE_DIRECT`, per-CPU decompressors (`fa53c9c`) |

`osukiosk.safeusb` typed after the label at `boot:` turns off the two
stick tweaks: an in-place fallback if a stick does not cope with them.
Measured not worth changing: `sync` at session start (0.08 s), prewarming
files (unneeded with zstd), the network and crond scripts.

## Left for later

- The stick: a faster one cuts the 2.3 s enumeration and the copy (the
  second stick at hand, Chipsbank 048d:1234, enumerates in 0.12 s but read
  13.5–18.6 MiB/s on the host).
- squashfs straight from the stick instead of copying it to RAM (an
  architecture change).
- About 0.9 s of udev settle and blkid before `/data` is mounted, partly the
  internal disk's partitions: not loading `ahci`.
- About 1 s of i915 modeset during coldplug: `i915.fastboot=1`, which can be
  tried at `boot:` without a rebuild.
- The game's 9.9 s: a 3 s intro, JIT (osu! is not ReadyToRun),
  `DOTNET_TieredPGO=0` untested.
- About 1 s for syslinux to load the 10.7 MB `bzImage` through the BIOS.

## Rules

- Measure before optimizing: decompression looked cheap until `speed`
  measured it, and `wc -c` was found only through the timeline.
- Every risky boot-path change gets an in-place fallback (a switch at
  `boot:`) and a saved rollback pair (`../../images-main-<hash>/` with
  `MD5SUMS`), restored with `update-stick.sh <dir>`.
- QEMU first, then the Z570; never change the stick right before a
  presentation.
