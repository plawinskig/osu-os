# PROGRESS.md

Ten plik opisuje **bieżący, roboczy stan prac** — co jest zrobione, co jest
w toku, jaki jest aktualny blocker. Jest świadomie krótki i tymczasowy:
**nadpisuj go**, gdy zamykasz etap lub odblokowujesz problem. Nie dopisuj tu
historii ("wcześniej próbowaliśmy X, nie zadziałało") — to żyje w `git log`.
Stałą architekturę i konwencje trzymamy w `CLAUDE.md`, nie tutaj.

## Status etapów

- ✅ Etap 1 — kernel main systemu (odchudzony od `x86_64_defconfig`, dwie rundy
  code-review), toolchain (glibc, generic x86-64).
- ✅ Etap 2 — dwuetapowa architektura rootfs (initramfs jako osobny build
  Buildroota, `rootfs.cpio` wchłonięty przez główny kernel).
- ✅ Etap 3 — fizyczny layout pendrive'a (`genimage`, MBR, syslinux). Obraz
  bootuje się poprawnie na fizycznym sprzęcie (zweryfikowane na ASUS FX503VM).
- 🔧 Etap 4 — init głównego systemu (`inittab` z `respawn`, montowanie
  partycji DATA, placeholder `osukiosk-session`) — przygotowane, ale
  **zablokowane bugiem opisanym niżej**, nie potwierdzone end-to-end na
  fizycznym sprzęcie.
- ⏳ Etap 5 — stack graficzny (`seatd`, Sway/Gamescope, ALSA) — nierozpoczęty.

## Aktualny blocker

**Symptom:** na fizycznym sprzęcie (ASUS FX503VM) initramfs nie znajduje
pendrive'a i system spada do awaryjnego shella BusyBoksa; klawiatura tam nie
działa, więc nie da się nawet zdiagnozować sytuacji interaktywnie.

**Przyczyna:** GŁÓWNY kernel (`board/osukiosk/linux.config` — to ten, który
faktycznie się bootuje i wykonuje `/init`) ma sterowniki USB storage, FAT32 i
HID/klawiatury skompilowane jako moduły (`=m`) zamiast wbudowane (`=y`).
Initramfs nie ma mechanizmu ładowania modułów z zewnątrz siebie, więc jest
"ślepy i głuchy" na te podsystemy.

**Rozwiązanie (uzgodnione, do wykonania):** w `board/osukiosk/linux.config`
ustawić na `y`: `CONFIG_USB_HID`, `CONFIG_HID_GENERIC`, `CONFIG_I2C_HID_ACPI`,
`CONFIG_USB_XHCI_HCD`, `CONFIG_USB_EHCI_HCD`, `CONFIG_USB_STORAGE`,
`CONFIG_FAT_FS`, `CONFIG_VFAT_FS`, `CONFIG_NLS_CODEPAGE_437`,
`CONFIG_NLS_ISO8859_1`, `CONFIG_INPUT_KEYBOARD`, `CONFIG_KEYBOARD_ATKBD`.
Po zmianie: `olddefconfig` → `make` (pełny build main systemu, bez `O=`) →
skorzystać ze skilla `build-osukiosk-image` do złożenia i przekazania obrazu.

**Kryterium zamknięcia:** po wgraniu na pendrive i boot na ASUS FX503VM,
konsola pokazuje w pętli komunikaty `osukiosk-session: alive, PID ...`
(rosnący PID = dowód działania `respawn`) zamiast panica/awaryjnego shella.
Po potwierdzeniu — nadpisz tę sekcję statusem Etapu 5.
