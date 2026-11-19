# Etap 6 — osu!lazer w sesji kiosku

Status: ✅ zamknięty 18.11.2026
Zakres commitów: `851b1a1`..`f19581b` (12–18.11.2026, `main`)
Sprzęt: QEMU z KVM (llvmpipe), Lenovo IdeaPad Z570

## Cel

Gra osu!lazer jako jedyny klient `cage`, z RAM, offline, z zachowaniem
kiosku: wyjście z gry i przycisk zasilania wyłączają czysto, crash
uruchamia sesję od nowa.

## Co zrobiono

### Krok A — fundament (12.11) — ✅ QEMU

- `851b1a1`: własny `S10udevd` w overlayu: `udevd --daemon` forkuje się
  dopiero po związaniu netlinka i wczytaniu reguł. Wersja Buildroota
  (`start-stop-daemon --background` i od razu `udevadm trigger`) gubiła
  zdarzenia coldplug: w QEMU z KVM jeden boot na cztery przetworzył 3 ze
  173 urządzeń i nie załadował modułów; po poprawce 6 z 6.
- `5f5cb11`: nagłówki toolchaina z kernela 6.18 (main) i przypięte 6.18
  (initramfs) zamiast 7.0. glibc nie może zakładać nowszego kernela.
- `1c6fff1`: libglvnd. Gra prosi SDL3 o OpenGL 3.2 core przez EGL i
  `libOpenGL.so.0`, którego Mesa bez GLX nie daje.
- `1ca2c66`: llvmpipe, `VIRTIO_PCI` i `DRM_VIRTIO_GPU` jako moduły, KVM i
  4 GiB w `qemu-test.sh`, `-vga virtio`. Od teraz w QEMU widać całą sesję z
  grą.
- `709a30e`: `post-build.sh` usuwa libclang, libclang-cpp, libLLVMSPIRVLib,
  narzędzia SPIR-V, diagtool, llvm-spirv i `/usr/share/clc` (Mesa ich nie
  używa w runtime). Squashfs: 104 → 51 MB.
- `6d00f26`: initramfs loguje rozmiar, czas i szybkość kopiowania rootfs.

### Krok B — nowy layout obrazu (12.11) — ✅ QEMU przez SeaBIOS i syslinux

- `876d898`: partycja boot 1 GiB FAT32 (`-F 32`) od 1 MiB (`align = 1M`),
  MBR jawnie. Zapas miejsca pozwala aktualizować pendrive bez `dd`
  (podmiana `bzImage` i `rootfs.squashfs`), `/data` zostaje.

### Krok C — gra (12.11) — ✅ QEMU

- `bea0d38`: pakiet `package/osu-lazer`: oficjalne wydanie
  `2026.1005.0-lazer` (AppImage z .NET 10, SDL3, BASS, FFmpeg, Realm),
  przypięte sha256, rozpakowane przy buildzie bez uruchamiania
  (`appimage-offset.sh` + host `unsquashfs`) do `/opt/osu-lazer`,
  `_REDISTRIBUTE = NO`, `BR2_STRIP_EXCLUDE_DIRS`. `Config.in` wybiera ICU,
  OpenSSL, libglvnd, alsa-lib, wayland, libxkbcommon. Squashfs 51 → 233 MB.
- `8e941c8`: `osukiosk-game` startuje grę z wyłączonym updaterem
  (`OSU_EXTERNAL_UPDATE_PROVIDER`) i SDL3 na Waylandzie. Pliki `.osz`/`.olz`
  z `/data/import` idą na linię poleceń; gra je importuje i kasuje.
- QEMU: 3 z 3 map zaimportowane, BASS działa, render przez llvmpipe,
  `kill -9` gry daje nową sesję.

### Krok D — zachowanie kiosku (12.11) — ✅ QEMU

- `e45e69e`: sesja czeka na `cage` (kod wyjścia gry): 0 → `poweroff`,
  inny → koniec skryptu i respawn. Przed decyzją zabija resztę procesów
  `kiosk` (osu! pozwala na jedną instancję). `osukiosk-stop-session` jako
  pierwsza linia `::shutdown`, przed `rcK`. BusyBox `acpid` (fragment
  `busybox.fragment`) i akcja przycisku zasilania `poweroff`.
- `2eeac4f`: `cage -m last`: gra tylko na ostatnio podłączonym monitorze.
- QEMU: wyjście z gry i `system_powerdown` wyłączają czysto (F2FS
  `unmount`), statusy 137/139/143 dają nową sesję, druga głowica virtio-vga
  przejmuje grę.

### Krok E — rundy na Z570 (12–18.11)

- Próba generalna w QEMU 12.11 (kreator Enterem, Ctrl+F11, `exit`, `check`,
  przycisk zasilania, wbudowana przeglądarka „Import files”).
- Extlinux zainstalowany 12.11, `dd` i runda 1 18.11 (obraz `2eeac4f`).
- Runda governora 18.11, decyzja: `e97d9a0` (`schedutil` domyślnie).
- `96ab762`: `PROGRESS.md` i `CLAUDE.md` po etapie, przykłady
  `qemu-test.sh` z grą.
- `f19581b`: skrypty `install-extlinux.sh` i `update-stick.sh` w skillu
  `build-osukiosk-image`, nowy skill `hardware-test-round`.

## Decyzje

- **Gra z oficjalnego AppImage**, nie budowana ze źródeł: .NET i natywne
  biblioteki w paczce, z systemu tylko glibc, ICU, OpenSSL, libglvnd,
  Wayland, xkbcommon, ALSA.
- **Wyjście z gry = wyłączenie, crash = restart.** (Na branchu pokazowym
  zmienione na restart także po wyjściu, patrz `06a-demo-fast-boot.md`.)
- **Domyślny governor `schedutil`** (decyzja autora 18.11, `e97d9a0`): w grze
  bez różnicy wobec `performance`, w menu chłodniej. `performance` zostaje
  wbudowany (`cpufreq.default_governor=performance` przy `boot:`).
- **Layout 1 GiB FAT32 od 1 MiB:** pendrive aktualizuje się bez `dd`, dopóki
  layout się nie zmienia.

## Co nie zadziałało

- **Wyścig udev przy coldplugu** (krok A): w QEMU co czwarty boot bez
  modułów; na sprzęcie oznaczałby boot bez grafiki i dźwięku.
- **Boot obrazu zawisł na „Booting from Hard Disk...”** (krok B): przy
  składaniu pominięto wpisanie `mbr.bin`, a nie wina layoutu.
- **Wyrwanie zasilania w QEMU** cofa `game.ini` do checkpointu F2FS, więc
  kreator wraca. Po czystym wyjściu już nie.
- **Panel ACCOUNT** otwiera się sam i zabiera pierwsze kliknięcie poza nim;
  litery trafiają do pola loginu.
- **`cage` pada przy wyjściu z gry z dwoma wyjściami** (runda 1): segfault w
  `libwayland-server`, status 139, respawn zamiast wyłączenia. Przyczyna:
  w `wl_display_destroy` `output_destroy` włącza pozostałe wyjście w
  zwolnionym `output_layout` (upstream `master` ma ten sam kod). Nienaprawione.
- **Gubione klatki EBUSY** (`Atomic commit failed: Device or resource busy`)
  na panelu, HDMI i w QEMU. Nienaprawione.
- **Dwa logi sesji:** restart w boocie 3 rundy 1 wypchnął logi bootów 1 i 2.

## Wyniki i weryfikacja (Z570)

- Runda 1 (18.11, obraz `2eeac4f`, `../measurements/stage6-round1/`):
  - od Entera przy `boot:` do kreatora 51 s, do menu 46 s: ok. 28 s do
    startu sesji (w tym 11,4 s kopiowania 221 MiB, 19,4 MiB/s), 4 s do
    startu gry, 14 s do menu (kolejne starty 15 i 10 s, pierwszy z importem
    20 s);
  - gra na HD 3000 przez `crocus` (OpenGL 3.3 core), dźwięk BASS na ALSA,
    mysz, import, filtrowanie listy map, wyjście z wyłączeniem, przycisk
    zasilania;
  - Draw na B no Revenge zwykle 105–121 fps przy limicie 120 (`Limit2x`),
    w drugiej połowie mapy 105–118 fps przy 8,3–9,5 ms;
  - monitor HDMI Acer VG242Y 1920x1080@60 działa, powrót na panel też;
    69 EBUSY w ok. 50 s na HDMI.
- Runda governora (18.11, `../measurements/stage6-governor/`, `gov.sh`):
  - w grze bez różnicy: Draw 120–121 fps przy 4,2–5,2 ms w obu, CPU ok.
    50%, wątki Draw/Update/Audio 52/64/16% rdzenia;
  - w menu `schedutil` schodzi do 0,8–1,6 GHz zamiast 1,8–2,2;
  - throttling pakietu od ok. 80 °C po 40–65 s gry, GPU dostaje
    1000–1050 zamiast 1100 MHz;
  - EBUSY 1,2–1,4/s przy Draw ≥ 40%, 0,01–0,04/s przy lekkim obciążeniu;
  - spadek Draw z rundy 1 się nie powtórzył (niewyjaśniony; laptop nie ma
    baterii).
- `rootfs.squashfs` 221 MiB, sama gra 310 MB przed kompresją.
- Zrzuty: `../screenshots/2026-11-12-stage6-step-{a,b,c,d}/`,
  `../screenshots/2026-11-12-stage6-step-e-qemu/`,
  `../screenshots/2026-11-18-stage6-round1-syslinux/`,
  `../screenshots/2026-11-18-stage6-governor-qemu/`.

## Co zostało / przeniesione dalej

W `PROGRESS.md` („Otwarte sprawy”): łatka `cage` przy dwóch wyjściach,
EBUSY, liczba logów sesji, throttling i spadek Draw, tryb względny myszy,
opóźnienie audio, tabela compose, układ klawiatury, powiększanie `/data`.
`output/osukiosk.img` jest z 12.11 (stary kernel); przed pełnym `dd` złożyć
od nowa. Kandydaci na Etap 7 w `PROGRESS.md`.

## Gdzie trafiły trwałe ustalenia

- `CLAUDE.md`: akapit „Gra (Etap 6)”, łańcuch sesji z wyłączaniem, decyzje
  (layout obrazu, nagłówki = kernel, `post-build.sh`, `S10udevd`,
  `schedutil`), QEMU z llvmpipe, odsyłacze do rund.
- skill `build-osukiosk-image`: aktualizacja bez `dd`, skrypty dla autora.
- skill `hardware-test-round`: procedura rund z Etapów 5 i 6.

## Źródło

Treść commitów `851b1a1`..`f19581b`, `PROGRESS.md` z `96ab762`, README w
`../measurements/stage6-round1/`, `../measurements/stage6-governor/` i
`../screenshots/2026-11-1*-stage6-*`.
