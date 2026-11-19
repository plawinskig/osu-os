---
name: hardware-test-round
description: Use when preparing, running or analysing a test round on the physical test laptop (Lenovo Z570) with the osu!kiosk pendrive - round tools in ../measurements/<round>/ (a BusyBox script on /data, upload and copy-logs scripts), a rehearsal in QEMU, the hand-off steps for the author, and the analysis of the logs copied back. Trigger on "runda na Z570", "przygotuj rundę", "narzędzia rundy", "copy-logs", "zmierz na sprzęcie", or whenever an image verified in QEMU is ready for hardware.
---

# Test rounds on the Z570

In a round the author boots the pendrive on the Z570 and follows numbered
steps. In a `debug` boot he runs a script from `/data` on tty2, and at the
end he copies the logs back to the build host with sudo. Claude prepares
the tools, rehearses them in QEMU, writes the hand-off and analyses the
logs. Claude never runs sudo, `dd` or anything else on the physical stick
itself.

## Layout (outside the repository)

`/home/greggy/Repos/osuos/measurements/<round>/` (index:
`../measurements/README.md`):
- `<script>.sh`: BusyBox ash. It lives on the data partition and runs as
  `sh /data/<script>.sh <step>` as root on tty2.
  - Messages are Polish without diacritics, because the tty2 font lacks
    them.
  - Check lines read `OK`/`BLAD <what>`, followed by a summary line.
  - The output also goes to `/data/log/<name>.txt`.
  - The last line says `Nastepny krok: ...`.
- `upload-round.sh` (sudo):
  - finds `OSUKIOSK_DATA` by label (exactly one, on a USB disk) and
    unmounts desktop automounts;
  - mounts it rw and installs with `install -o 900 -g 900 -m 0644`
    (uid/gid 900 is the kiosk account), then runs `cmp` and `sync`;
  - unmounts it and also unmounts `OSUBOOT`.
- `copy-logs.sh [folder]` (sudo):
  - reads from the automount or mounts read-only;
  - copies with `cp -a` `/data/log`, `/data/alsa`, the game's logs, its
    `framework.ini`/`game.ini` and in-game screenshots, plus listings;
  - ends with a verdict: `asound.state` newer than `dmesg.txt` means that
    the last boot ended with a clean shutdown.

  Give a new folder name for every copy (e.g. `logs-boot4`), because the
  default `logs/` is overwritten. The folder is relative to the script's
  own directory: a name, or `../<round>/<name>` for another round's
  folder, never an absolute path. An absolute path ends up nested under
  the script's folder, with parents that only root can remove (hit on
  19.11.2026).
- `README.md`, with the sections Przebieg rundy, Narzędzia, Próba (QEMU),
  Instrukcja rundy (the exact hand-off) and Wynik na Z570 (results, then
  analysis).
- `qemu/`: rehearsal helpers.

Templates:
- `stage5-step-e`: a check round.
- `stage6-round1`: three boots with the game and `step6.sh check`.
- `stage6-governor`: `gov.sh start/stop`, a background sampler (CPU, GPU
  clocks, temperatures, game threads, throttling, cut to the play of a
  map), `qemu/fake-sys.sh`.
- `demo-fast-boot`: a boot timeline (`demo.sh measure`) and read paths
  (`demo.sh speed`), `upload-demo.sh` (only the script, no beatmaps),
  `build-variant.sh`, `qemu/` (A/B runs, boot partition images, files out
  of the data copy). The method is the skill `boot-time`.

## What the scripts can rely on

- **BusyBox 1.38 in the image:**
  - missing: `stat`, `pkill`, `timeout`, `logread`; `readlink` takes one
    file;
  - present: `date -r`, `test -nt` (in seconds), `setsid`, `chvt`, `pidof`,
    `awk`, `tee`, `df`, `du`;
  - ash supports `local`, `$(( a ? b : c ))` and `${12}`. Write
    `read -r x 2> /dev/null < file`, with the `2>` before the `<`, so that
    a missing file stays silent;
  - `$( )` forks, so a sampler running every second sets variables instead;
  - `wc -c` reads every byte (BusyBox has no shortcut for files): take a
    size from `ls -ln`, e.g. `set -- $(ls -ln "$f"); size=$5`;
  - `date` has whole seconds only (no `%N`); for a sub-second wall clock,
    wait for the second to change, then read `/proc/uptime`;
  - `sleep` takes fractions (`sleep 0.2`), in the initramfs too, whose
    BusyBox has no `stat` either;
  - a process's start time is field 22 of `/proc/<pid>/stat`, counted
    after the `) ` that closes the name, in hundredths of a second since
    boot.
- **Kernel messages** have timestamps only with `printk.time=1` on the
  command line (typed after the label at `boot:`).
- **Data partition:** `/data` (F2FS).
  - `/data/log`: `session.log`, `session.log.1` and `dmesg.txt`, written
    and synced when a session starts;
  - `/data/alsa/asound.state`: saved only by a clean shutdown;
  - game data: `/data/home/.local/share/osu`, logs in
    `logs/<epoch>.runtime.log` and the like (times in UTC).
- **Game log lines:**
  - `GL Renderer:`, `GL Version:`, `BASS initialised`,
    `Imported N of M beatmaps`, `entered MainMenu`;
  - a play runs from `entered SoloPlayer#N` to `suspended SoloPlayer#N
    (waiting on SoloResultsScreen` or `exit from SoloPlayer#N` (with
    autoplay the screen is `ReplayPlayer`);
  - a clean exit logs `Host execution state changed to Stopped`, and the
    power button `Unknown SDL key: SDL_SCANCODE_POWER`.
- **`session.log`:** the first line is the date (UTC). cage lines carry the
  time since cage started. The session logs `cage exited with status N`
  and `the game was closed, powering off`. Every session restart rotates
  the logs.
- **Game threads in `/proc/<pid>/task/*/comm`:** `Draw (GameThrea`,
  `Update (GameThr`, `Audio (GameThre`. Threads that a thread starts
  inherit its name, so BASS's threads count under Audio. Match on the
  prefix and count deltas per thread.
- **The Z570:** see the hardware section of `PROGRESS.md`. There is no
  RAPL (`CONFIG_POWERCAP` is off) and no `coretemp`; temperatures come from
  the ACPI zones and `x86_pkg_temp`, the GPU clock from i915's
  `gt_act_freq_mhz` and `gt_cur_freq_mhz`.

## Rehearsal in QEMU

- `board/osukiosk/qemu-test.sh direct` with `CMDLINE_EXTRA=osukiosk.debug`
  and the HDA card (CLAUDE.md, workflow 4) runs the session and the game
  through llvmpipe.
- **Files onto `/data` without root:**
  - back up the data copy first:
    `cp --sparse=always board/osukiosk/qemu-artifacts/data.img <scratch>/`;
  - then `sload.f2fs -f <dir> board/osukiosk/qemu-artifacts/data.img`;
  - never run it on `board/osukiosk/data.img`;
  - `sload.f2fs` never overwrites a file already in the image: load a new
    version of a script into a fresh copy (the backup) or under a new
    name.
- **Files back out without root:** `fsck.f2fs --dry-run -t <image>` gives
  the inode, and `echo y | dump.f2fs -i <inode> <image>` writes the file
  to `./lost_found/` under the name it was created with (`session.log.1`
  comes out as `session.log`). `demo-fast-boot/qemu/data-get.sh` does it
  for one file by name.
- **Build variants:** on branch `demo-fast-boot`, `QEMU_KERNEL` and
  `QEMU_BOOT_VFAT` boot a saved pair in direct mode;
  `demo-fast-boot/qemu/make-vfat.sh` makes the boot partition image.
- **What QEMU lacks** (cpufreq, thermal zones, i915 clocks): give the
  script an override root for `/sys` (`GOV_SYS=`) and build a fake tree,
  e.g. `stage6-governor/qemu/fake-sys.sh`.
- **One typed command:** put the test sequence in a script on `/data` and
  type it after `exec >/dev/ttyS0 2>&1`. `chvt 1; sleep N; chvt 2` lets
  the game run in between, and a final `poweroff` ends cleanly with
  everything in the serial log. Lines typed while tty1 is active go to the
  game, so do not type during the `chvt 1` part.
- **Keys and clicks in the game:**
  - keys go through `mon:sendkey`: the first-run wizard needs Enter five
    times;
  - holding Esc for 3 s in the menu exits the game (`mon:sendkey esc
    3000`). In a normal run the script's own Enter first opens the menu
    buttons and the ACCOUNT panel, and a held Esc then only steps back,
    so send three plain Esc first. On main the machine then powers off;
    on `demo-fast-boot` the game starts again;
  - exact clicks go through usb-tablet + QMP (`stage6-round1/qemu/drive.sh`).
- **A second monitor:** QEMU's D-Bus display and `SetUIInfo` (see the
  Stage 6 step D screenshots README).
- **A clean shutdown, proven from the host:** `fsck.f2fs --dry-run` on a
  copy of the data image shows `checkpoint state ... unmount`.
- **Host tests:** use the host's BusyBox as `sh`, through a folder of
  symlinks to `/usr/bin/busybox` put first in `PATH`, with overrides for
  `/data` and `/run` (`GOV_DATA`, `GOV_RUN`).

## The hand-off

- Numbered steps, each labelled with its machine ("Na tym komputerze" /
  "Na Z570"), one command block per step, and how each step ends (by
  itself, `poweroff`, the power button, a line the script prints).
- Then what to send: stopwatch times, photos of tty2, notes.
- Sudo scripts whose output Claude should see get the `!` prefix.
- `dd` only by the author, after `lsblk`.
- The same text goes into the README section "Instrukcja rundy".
- The author may run steps ahead (extlinux and `dd` before the OK). Check
  afterwards without root, e.g. md5 of the files on the automounted
  `OSUBOOT` against the build.
- Photos of tty2 are only a backup: the scripts save their output on
  `/data`, and `copy-logs.sh` brings it back. Read the copied logs before
  calling a photo unreadable or asking for anything to be retyped, and
  look where the copy actually went before saying it is missing.
- **Measurements the author can take:**
  - the stopwatch from Enter at `boot:` to the menu;
  - osu!'s overlay, Ctrl+F11 (the `Draw` row: fps and ms per frame,
    where the ms leave out the wait for the frame limiter). He records it
    with a phone and sends a summary; the timeline form with timestamps
    ("format 2") is the one that can be lined up with samples;
  - subjective notes.
- Keep runs that are compared alike. The time in song select before a map
  heats the laptop (the package throttles at about 80 °C), so ask for the
  same routine in each boot and a cool-down between boots.

## Analysis

- The `copy-logs.sh` verdict first. Then split the samples into menu, map
  and after the map, using the play window from the game's log.
- Count `Atomic commit failed` lines per phase from `session.log`
  (date line + cage time) and relate them to load.
- Write the results into the README's "Wynik na Z570" (a table and
  conclusions), screenshots into `../screenshots/<date>-<topic>/` with a
  Polish README, and the state into `PROGRESS.md` when a stage closes.
- A decision that belongs to the author is put as one concrete question:
  the measured numbers, what each answer leads to, and whether it
  applies to every machine.
