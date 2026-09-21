# PROGRESS.md

Ten plik opisuje **bieżący, roboczy stan prac** — co jest zrobione, co jest
w toku, jaki jest aktualny blocker. Jest świadomie krótki i tymczasowy:
**nadpisuj go**, gdy zamykasz etap lub odblokowujesz problem. Nie dopisuj tu
historii ("wcześniej próbowaliśmy X, nie zadziałało") — to żyje w `git log`.
Stałą architekturę i konwencje trzymamy w `CLAUDE.md`, nie tutaj.

## Status etapów

- ✅ Etap 1 — kernel main systemu (odchudzony), toolchain (glibc, generic
  x86-64). Config kernela to `board/osukiosk/linux.config`, podłączony do
  Buildroota przez `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG`.
- ✅ Etap 2 — dwuetapowa architektura rootfs (initramfs jako osobny build
  Buildroota, `rootfs.cpio` wchłonięty przez główny kernel).
- ✅ Etap 3 — fizyczny layout pendrive'a (`genimage`, MBR, syslinux). Uwaga:
  wcześniejsze „zweryfikowane do `switch_root` na sprzęcie" nie miało pokrycia
  w ówczesnym kernelu; pełny łańcuch potwierdzono dopiero w Etapie 4.
- ✅ Etap 4 — boot end-to-end. Zweryfikowane na ASUS FX503VM (21.09.2026):
  bootloader → initramfs → `switch_root` → BusyBox init → pętla `respawn`
  `osukiosk-session` (PID rośnie) z `/data` zamontowanym jako F2FS `rw`.
  Zakres: baseline + 4 poprawki:
  - **Baseline:** `linux.config` podłączony do buildu, defconfigi
    zsynchronizowane z realnym configiem, binaria buildu wyjęte z gita.
  - **A — USB wbudowane w kernel:** `USB`, xHCI/EHCI (+ `*_PCI`),
    `USB_STORAGE`, `USB_HID`, `HID_GENERIC`, `I2C_HID_ACPI` (initramfs nie ładuje modułów).
  - **B — `SQUASHFS_XZ`:** rootfs jest kompresowany XZ, kernel miał tylko zlib.
  - **C — inittab main systemu:** przeniesiony do `rootfs-overlay/`, z
    `devtmpfs` na `/dev` i `respawn` sesji; usunięty martwy z initramfs.
  - **D — dane:** `F2FS_FS=y`, punkt montowania `/data` w overlayu,
    `S41mountdata` szuka partycji przez `blkid` (BusyBox `mount` nie ma `-L`)
    i odmontowuje ją na `stop`.
- ⏳ Etap 5 — stack graficzny (`seatd`, Sway/Gamescope, ALSA) — nierozpoczęty.

## Otwarte sprawy (na start Etapu 5)

- **RO rootfs:** `/var/lib` jest niezapisywalny (`seedrng: can't create
  directory '/var/lib/seedrng'`). Ścieżki zapisu (`/var/lib`, `/var/log` itd.)
  wymagają tmpfs lub symlinków, zanim dojdzie zapisujący się runtime (.NET, Sway).
- **`quiet` zdjęte z `extlinux.conf`** na czas testów Etapu 4 — do decyzji,
  czy przywrócić.
- **Szum w logu:** `F2FS-fs (sda): Magic Mismatch` z autodetekcji `mount` w
  `/init` (mount bez `-t` próbuje F2FS na całym dysku). Nieszkodliwe; da się
  wyciszyć przez `mount -t vfat` w `/init`.
- **`/init`:** pętla szukania pendrive'a trwa 10 s (wolniejszy sprzęt może
  potrzebować więcej), przy porażce brak diagnostyki (`/proc/partitions`,
  `dmesg`), komunikaty po polsku (konwencja: kod po angielsku).
- **Nagłówki toolchaina** (`BR2_KERNEL_HEADERS_7_0`, glibc `--enable-kernel=7.0`)
  są nowsze niż kernel 6.18.48. Nie blokuje bootu, ale glibc może zakładać
  syscalle nowsze niż 6.18 — rozważyć wyrównanie przed dociąganiem runtime .NET.
- **Skill `build-osukiosk-image`:** krok 1 każe kopiować pliki do `boot-files/`,
  a `genimage` czyta z `board/osukiosk/` — do poprawienia w `SKILL.md`.
- **Klawiatura w awaryjnym shellu** (objaw z ASUS-a przed poprawkami) nie była
  ponownie testowana po Etapie 4. Wewnętrzna klawiatura PS/2 miała sterowniki
  wbudowane od początku; jeśli nadal zawodzi, następny trop to `i8042.*`
  w `extlinux.conf`.
