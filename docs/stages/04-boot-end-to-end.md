# Etap 4 — boot end-to-end

Status: ✅ zamknięty 21.09.2026 (poprawki po zamknięciu do 22.09.2026)
Zakres commitów: `3e83b74`..`a496629` (12–22.09.2026, `main`)

## Cel

Pełny łańcuch na prawdziwym sprzęcie: bootloader → initramfs →
`switch_root` → BusyBox init → nadzorowana sesja (placeholder w pętli
`respawn`) z zamontowaną partycją danych.

## Co zrobiono

Przygotowanie (12–13.09):
- `3e83b74`: `inittab` i launcher sesji (trafiły do overlayu initramfsu,
  a powinny do main systemu, poprawione w `86d5daa`).
- `18cbd7a`, `b13f048`: szukanie pendrive'a w `/init` przez iterację po
  `/dev/sd*` i `/dev/nvme*` zamiast `mount -L`.

Sesja 21.09 (blocker i zamknięcie):
- `82a4e47`, `771f3b3`, `c1a942f`: `HISTORY.md` i `PROGRESS.md` w repo.
- `836f4f5`: zdjęte `quiet` z `extlinux.conf` na czas debugowania.
- **Baseline** `a460ceb`: `linux.config` zastąpiony savedefconfigiem
  faktycznie budowanego kernela (bez AUDIT, NUMA, KPROBES, HOTPLUG_PCI, MD/DM,
  QUOTA, ISO9660) i podłączony przez `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG`.
  Ścieżki overlayów przez `$(BR2_EXTERNAL_OSUKIOSK_PATH)`.
- `c04c3d2`: `bzImage` i `rootfs.squashfs` wyjęte z gita (`.gitignore`).
- **A** `f785d14`: `USB`, xHCI/EHCI, `USB_STORAGE`, `I2C_HID_ACPI` wbudowane
  (`=y`). Initramfs nie ładuje modułów, więc nie widział pendrive'a.
- **B** `dd0b7bb`: `SQUASHFS_XZ`. Rootfs był XZ, kernel znał tylko zlib
  („Filesystem uses xz compression. This is not supported”).
- **C** `86d5daa`: `inittab` main systemu w `rootfs-overlay/`: `devtmpfs` na
  `/dev` jako pierwszy wpis (pusty `/dev` w squashfs, `switch_root` nie
  przenosi montowań), bez remountu roota, `respawn` sesji na tty1. Martwy
  `inittab` usunięty z initramfsu.
- **D** `484cbc8`: `F2FS_FS=y`; `S41mountdata` szuka partycji przez `blkid`
  (etykieta `OSUKIOSK_DATA`) i montuje `mount -t f2fs`, odmontowuje na
  `stop`; punkt montowania `/data` z markerem `.empty`.
- `b8f4577`: zamknięcie etapu w `PROGRESS.md`.
- `3f0fb4d`: skill `build-osukiosk-image` w repo, poprawiony krok 1 (pliki do
  `board/osukiosk/`, nie do `boot-files/`).
- `6b90d20`: `CLAUDE.md` w repo, ścieżki względne.

Poprawki 22.09:
- `45f7f28`: `CONFIG_INITRAMFS_SOURCE` względny
  (`../../../../output-initramfs/images/rootfs.cpio`). kbuild rozwiązuje go
  względem katalogu budowy kernela; `$(BR2_...)` nie działa w `linux.config`.
- `a496629`: `/init` montuje boot jako `vfat` (koniec szumu „F2FS Magic
  Mismatch”), komunikaty po angielsku, przy porażce `/proc/partitions` i
  ogon `dmesg` przed shellem, szukanie wydłużone z 10 s do 30 s.

## Decyzje

- **Sterowniki potrzebne przed `switch_root` muszą być wbudowane w kernel
  main systemu.** Initramfs nie ma mechanizmu ładowania modułów. To
  doprecyzowanie „Podejścia B”.
- **Błąd montowania `/data` nie zatrzymuje bootu** (brak trwałości jest
  gorszy, ale akceptowalny).

## Co nie zadziałało

- **Kernel panic „Attempted to kill init!”** przy pierwszym teście: BusyBox
  init bez wpisu `respawn` przechodził tabelę i kończył się (tak opisuje
  `HISTORY.md`). Uwaga z `CLAUDE.md`: pętla główna BusyBox init to
  `while (1)`, więc dokładna przyczyna panika jest niepewna; skutecznym
  lekarstwem był `inittab` w main systemie.
- **„Ślepy” initramfs** (bez USB i FAT, klawiatura w awaryjnym shellu nie
  działała): flagi zmieniano najpierw w złym drzewie (`output-initramfs`,
  a skrypt trafił w `linux-headers`). Bootuje się kernel main systemu.
- **Kconfig cicho cofa dzieci:** `USB_XHCI_HCD=y` przy `USB=m` kończy jako
  `m`. Rodzica trzeba ustawić pierwszego i sprawdzać efektywny `.config`.
- **Weryfikacja przez hash `bzImage` jest bezużyteczna:** kernel wbudowuje
  licznik buildu i datę. `45f7f28` sprawdzono przez wypakowanie initramfsu z
  `bzImage` i porównanie bajt w bajt z `rootfs.cpio`.

## Wyniki i weryfikacja

- **ASUS FX503VM, 21.09.2026:** bootloader → initramfs → `switch_root` →
  BusyBox init → pętla `respawn` `osukiosk-session` (rosnący PID), `/data`
  zamontowane jako F2FS `rw`.
- `a496629`: QEMU, ścieżka sukcesu i wymuszona porażka (bez USB storage,
  30 s, diagnostyka przed `exec sh`).

## Co zostało / przeniesione dalej

Do Etapu 5:
- `/var/lib` niezapisywalny (`seedrng`) → `45cd9fd` (6.11).
- `quiet` zdjęte → przywrócone w `24ef23d` (6.11).
- nagłówki toolchaina 7.0 przy kernelu 6.18 → `5f5cb11` (Etap 6).
- klawiatura w awaryjnym shellu → sprawdzona na Z570 24.10 (`rdinit=/bin/sh`,
  PS/2 i USB działają).

## Gdzie trafiły trwałe ustalenia

- `CLAUDE.md`: wyjątek od Podejścia B (wbudowane USB, FAT, squashfs, loop,
  F2FS), dwa drzewa configu, względny `CONFIG_INITRAMFS_SOURCE`, BusyBox bez
  `mount -L`, read-only rootfs i `.empty`, weryfikacja efektywnego `.config`.
- skill `build-osukiosk-image`.

## Źródło

Treść commitów od `836f4f5`, `HISTORY.md` („Etap 4”, „Bieżący blocker”),
`PROGRESS.md` z `b8f4577` i `c146c74`.
