# Etap 3 — fizyczny layout pendrive'a

Status: ✅ zamknięty (ok. 13.09.2026; boot end-to-end dopiero w Etapie 4)
Zakres commitów: `96fa68d` (9.09), `d33e8db`, `7062e3a` (13.09.2026, `main`)

## Cel

Jeden obraz `osukiosk.img` do wypalenia na pendrive: partycja boot z
kernelem, rootfs i bootloaderem oraz trwała partycja danych.

## Co zrobiono

- `96fa68d`: konfiguracja bootu i obrazu (`extlinux.conf`,
  `genimage-osukiosk.cfg`).
- MBR (nie GPT), boot w trybie Legacy/CSM, syslinux/extlinux.
- Partycja 1 `OSUBOOT`: 256 MB, bootowalna, `bzImage`, `rootfs.squashfs`,
  pliki syslinux.
- Partycja 2 `OSUKIOSK_DATA`: F2FS 4 GB. `genimage` nie tworzy F2FS, więc
  powstaje osobno (`mkfs.f2fs -l OSUKIOSK_DATA data.img`) i jest wstawiana
  jako gotowy plik.
- `d33e8db`, `7062e3a` (13.09): do gita trafiły zbudowane `rootfs.squashfs`
  i `bzImage`. Usunięte z indeksu w Etapie 4 (`c04c3d2`).

## Decyzje

- **syslinux + MBR**, nie GRUB i nie UEFI+GPT (UEFI zaparkowany).
- **Etykieta `OSUBOOT`:** FAT32 pozwala na 11 znaków, a `OSUKIOSK_BOOT` ma 13.
- **F2FS na dane:** projektowany pod flash (log-structured, wear-leveling),
  pasuje do częstych małych zapisów (wynik po każdej mapie).

## Co nie zadziałało (poprawki autora względem pierwotnych instrukcji)

1. `genimage` czyta pliki z `inputpath`; bez skopiowania ich tam przed
   uruchomieniem kończy się `stat() failed`. (Katalog `boot-files/` okazał
   się później zbędny, bo `genimage` czyta z `board/osukiosk/`; usunięty w
   `3f0fb4d`, 21.09.)
2. Etykieta FAT32 ograniczona do 11 znaków.
3. `extlinux --install` trzeba wykonać na złożonym `osukiosk.img` (przez
   `losetup -fP`), nie na pośrednim `boot.vfat`.
4. Kod MBR syslinuxa wgrywa się osobno:
   `dd if=/usr/lib/syslinux/mbr/mbr.bin of=output/osukiosk.img bs=440 count=1 conv=notrunc`.

## Wyniki i weryfikacja

- `HISTORY.md` podaje, że obraz bootował na ASUS FX503VM aż do `switch_root`.
  **Poprawka 21.09.2026 (`b8f4577`):** ówczesny kernel miał sterowniki USB i
  FAT jako moduły, więc initramfs nie mógł widzieć pendrive'a; to twierdzenie
  nie miało pokrycia. Pełny łańcuch potwierdzono w Etapie 4.

## Co zostało / przeniesione dalej

- Partycja boot była w praktyce FAT16 (`mkfs` wybiera FAT16 przy 256 MB),
  przy typie MBR `0x0C` (FAT32 LBA). Wykryte w Etapie 5, naprawione w
  Etapie 6 (`876d898`: 1 GiB, `-F 32`).
- Partycja 1 zaczynała się w sektorze 1. Od Etapu 6 partycje zaczynają się
  na granicach 1 MiB.

## Gdzie trafiły trwałe ustalenia

- skill `build-osukiosk-image`: procedura składania obrazu, extlinux, MBR.
- `CLAUDE.md`: limit etykiety FAT32, layout obrazu.

## Źródło

`HISTORY.md` („Etap 3”), tytuły commitów, treść `c04c3d2`, `3f0fb4d`,
`876d898` i `PROGRESS.md` z `b8f4577`.
