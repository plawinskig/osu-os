# PROGRESS.md

Ten plik opisuje **bieżący, roboczy stan prac** — co jest zrobione, co jest
w toku, jaki jest aktualny blocker. Jest świadomie krótki i tymczasowy:
**nadpisuj go**, gdy zamykasz etap lub odblokowujesz problem. Nie dopisuj tu
historii ("wcześniej próbowaliśmy X, nie zadziałało") — to żyje w `git log`.
Stałą architekturę i konwencje trzymamy w `CLAUDE.md`, nie tutaj.

## Status etapów

- ✅ Etap 1 — kernel main systemu (odchudzony), toolchain (glibc, generic
  x86-64).
- ✅ Etap 2 — dwuetapowa architektura rootfs (initramfs jako osobny build
  Buildroota, `rootfs.cpio` wchłonięty przez główny kernel).
- ✅ Etap 3 — fizyczny layout pendrive'a (`genimage`, MBR, syslinux).
- ✅ Etap 4 — boot end-to-end (ASUS FX503VM, 21.09.2026).
- ✅ Etap 5 — grafika, audio i docelowa sesja kiosku (Lenovo Z570,
  24.10–6.11.2026).
- ✅ Etap 6 — osu!lazer w sesji kiosku (12–18.11.2026). Podsumowanie niżej,
  szczegóły w commitach `851b1a1`..`e97d9a0`.
- ⏳ Etap 7 — nowe funkcje: nie rozpoczęty, zakres do wyboru z autorem
  (kandydaci na końcu pliku).

## Etap 6 — podsumowanie

- **Gra:** pakiet `osu-lazer` rozpakowuje przy buildzie oficjalne wydanie
  (`2026.1005.0-lazer`) do `/opt/osu-lazer` w rootfs, więc gra też działa z
  RAM. Na Z570 renderuje przez `crocus` (OpenGL 3.3 core), dźwięk idzie
  przez BASS na ALSA.
- **Zachowanie kiosku:**
  - wyjście z gry (kod 0) wyłącza komputer;
  - crash gry albo `cage` uruchamia sesję od nowa;
  - krótkie wciśnięcie przycisku zasilania (`acpid`) czysto wyłącza;
  - beatmapy bez sieci przychodzą przez `/data/import`;
  - przy kilku monitorach gra jest tylko na ostatnio podłączonym
    (`cage -m last`).
- **Obraz:** partycja boot ma 1 GiB FAT32 od 1 MiB. Pendrive z tym układem
  aktualizuje się bez `dd` (`update-stick.sh` w skillu
  `build-osukiosk-image`), a `/data` zostaje.
- **Kernel i toolchain:**
  - nagłówki toolchaina z kernela 6.18;
  - domyślny governor `schedutil` (`e97d9a0`, po rundzie governora);
  - llvmpipe i virtio-gpu, żeby w QEMU było widać całą sesję z grą.
- **Rozmiar:** `post-build.sh` usuwa clang, libclc i narzędzia SPIR-V
  (−41 MB squashfs). `rootfs.squashfs` ma 221 MiB, z czego sama gra to
  310 MB przed kompresją.

Wyniki na Z570 (szczegóły i analizy w `../measurements/stage6-round1/` i
`../measurements/stage6-governor/`):
- Od Entera przy `boot:` do menu gry mija 46 s, a przy pierwszym starcie z
  importem i kreatorem 51 s. Te 46 s to:
  - ok. 28 s do startu sesji, w tym 11,4 s kopiowania rootfs do RAM
    (221 MiB, 19,4 MiB/s);
  - 4 s do startu gry;
  - 14 s od startu gry do menu (kolejne starty: 15, 14 i 10 s, pierwszy z
    importem 20 s).
- Draw na B no Revenge [Normal] trzyma 120–121 fps przy limicie 120
  (`Limit2x`, panel 60 Hz), 4,2–5,2 ms na klatkę.
- Wyjście z gry i przycisk zasilania wyłączają czysto w kilka sekund.
- Governor: w grze bez różnicy, bo `schedutil` i tak trzyma maksimum. W menu
  `schedutil` schodzi do 0,8–1,6 GHz zamiast 1,8–2,2.
- Monitor HDMI (Acer VG242Y, 1920x1080@60) działa, powrót na panel po
  odłączeniu też. Dwa błędy opisane w „Otwartych sprawach”.

## Sprzęt testowy — Lenovo IdeaPad Z570

- i3-2330M (Sandy Bridge, 2 rdzenie / 4 wątki, 0,8–2,2 GHz, bez HWP i
  turbo, `intel_cpufreq` w trybie passive), 7,7 GiB RAM.
- Intel HD 3000 (`8086:0116`, `i915` + `crocus`, 650–1100 MHz) obok NVIDIA
  GT 520M bez sterownika (Optimus). Panel LVDS 1366×768 @ 60,042 Hz, wyjścia
  VGA i HDMI (1080p maksymalnie 60 Hz).
- Bez baterii, zawsze na zasilaczu.
- Pakiet zaczyna throttling przy ok. 80 °C, po 40–65 s gry. Liczniki rdzeni
  stoją, a GPU dostaje 1000–1050 zamiast zadanych 1100 MHz.
- Tylko USB 2.0 (EHCI). Pendrive (090c:1000) czyta 19,4 MiB/s. HDA: Realtek
  ALC272 i HDMI CougarPoint. Klawiatura wbudowana na PS/2, przycisk
  zasilania to `event2`.
- Boot: pendrive w port USB 2.0, F12 → USB HDD (legacy). Prompt `boot:`
  łapie się Spacją wciśniętą zaraz po wyborze w F12. Parrot na dysku zostaje
  nietknięty.
- ASUS FX503VM odpada w testach grafiki: jego iGPU nie jest widoczny w
  systemie.

## Tryb diagnostyczny (`debug` / `hold`)

- Przy `boot:` (1 s, pierwszy klawisz zatrzymuje odliczanie) wpisz
  etykietę:
  - `debug`: shell roota na tty2 bez hasła (Ctrl+Alt+F2), `cage -s`
    (przełączanie VT), komunikaty kernela na ekranie;
  - `hold`: jak `debug`, ale sesja nie startuje `cage` i nie rusza logów
    poprzedniego bootu.

  Parametry wpisane po etykiecie są dopisywane do linii poleceń kernela,
  np. `debug printk.time=1` (znaczniki czasu w dmesg) albo
  `osukiosk cpufreq.default_governor=performance`. Na partycji FAT
  pendrive'a można ustawić `DEFAULT debug` bez rebuilda.
- Czyste wyłączenie: wyjście z gry, przycisk zasilania albo `poweroff` na
  tty2. Tylko ono zapisuje stan miksera (`/data/alsa/asound.state`).
- Logi sesji (`/data/log`):
  - `session.log`: stderr `su`, `cage` i gry w bieżącej sesji. Pierwsza
    linia to data (UTC), a czasy w liniach `cage` liczą się od jego startu;
  - `session.log.1`: poprzednia sesja. Każdy restart sesji przesuwa logi,
    więc jeden crash wypycha log poprzedniego bootu;
  - `dmesg.txt`: zrzut z chwili startu sesji, z czasem kopiowania rootfs.
- Logi gry: `/data/home/.local/share/osu/logs/<sekunda-startu>.runtime.log`
  (i `database`, `input`, `performance`…), czasy w UTC.
- Zgranie na host: `sudo bash ../measurements/stage6-round1/copy-logs.sh
  [folder]`. Każde kopiowanie rób do nowego folderu, bo domyślny `logs/`
  zostałby nadpisany. `dd` kasuje partycję danych, więc logi trzeba zabrać
  przed nim.
- F2FS zachowuje tylko to, co trafiło do checkpointu (co ≤ 60 s) albo
  dostało `fsync`. Log poprzedniej sesji przetrwa wyrwanie zasilania, a log
  bieżącej tylko do ostatniego checkpointu.
- Podmiana sesji bez rebuilda (tryb `debug` albo `hold`):
  - `cp /usr/bin/osukiosk-session /run/s`, potem `vi /run/s`;
  - `mount --bind /run/s /usr/bin/osukiosk-session`;
  - `kill $(pidof cage)` (w `hold`: `kill $(pidof sleep)`), a `init`
    uruchomi kopię.

  BusyBox nie ma `pkill`, `timeout`, `stat` ani `logread`. Syslog jest w
  `/var/log/messages` (tmpfs).
- Znane, nieszkodliwe wpisy:
  - `session.log`:
    - `Failed to disable CRTC` i `Atomic commit failed: Permission denied`
      przy przełączaniu VT;
    - `couldn't find a Compose file for locale "C.UTF-8"`;
  - log gry:
    - `Got zero displays from SDL` przy przełączeniu VT albo zmianie
      wyjścia;
    - `Failed to grab keyboard` i `Failed to enable relative mode` (`cage`
      nie ma tych protokołów);
    - `wayland cannot position non-popup windows`;
    - błędy sieci.

  Szkodliwy jest za to `Atomic commit failed: Device or resource busy`
  (patrz „Otwarte sprawy”).
- Rundy sprzętowe: skill `hardware-test-round`, narzędzia i wyniki w
  `../measurements/` (spis w `README.md` tamże).

## Otwarte sprawy (odłożone, do podjęcia osobno)

- **`cage` pada przy wyjściu z gry, gdy są podłączone dwa wyjścia**
  (`-m last`).
  - Skutek: segfault w `libwayland-server`, status 139 i respawn zamiast
    wyłączenia, czyli z monitorem wyjście z gry uruchamia grę od nowa.
  - Przyczyna: w trakcie `wl_display_destroy` `output_destroy` włącza
    pozostałe wyjście w zwolnionym już `output_layout`. Upstream `master`
    ma ten sam kod.
  - Poprawka: w `output_destroy` pominąć `output_layout_remove` i ponowne
    włączanie, gdy `server->terminated`. Łatka w br2-external, test w QEMU
    na dwóch głowicach (D-Bus `SetUIInfo`) z przytrzymanym Esc.
  - Szczegóły: `../measurements/stage6-round1/README.md`.
- **Gubione klatki w `cage` (EBUSY):** `Atomic commit failed: Device or
  resource busy`.
  - Częstość: 1,2–1,7/s przy dużym obciążeniu (Draw ≥ 40%), prawie zero
    przy lekkim. Zdarza się na panelu, na HDMI i w QEMU (virtio-gpu).
  - Do sprawdzenia: `WLR_SCENE_DISABLE_DIRECT_SCANOUT=1`,
    `WLR_DRM_NO_ATOMIC=1`, log debug wlroots.
  - `../measurements/stage6-governor/gov.sh` liczy te błędy w czasie mapy.
- **Logi sesji:** trzymamy tylko dwa, więc restart sesji wypycha log
  poprzedniego bootu. Trzymać więcej albo log na boot.
- **Throttling przy ok. 80 °C** i niewyjaśniony spadek Draw z rundy 1
  (105–118 fps przy 8,3–9,5 ms). W rundzie governora było 4,2–5,2 ms, a
  bateria odpada, bo laptop jej nie ma. Hipoteza: nagrzanie po 25 min gry.
- **Odłożone z planu Etapu 6:**
  - tryb względny myszy i więzienie kursora (`cage` nie ma
    pointer-constraints);
  - opóźnienie audio (dmix, offset w osu!);
  - tabela compose;
  - układ klawiatury w `cage`;
  - powiększanie `/data` do rozmiaru pendrive'a.
- **`output/osukiosk.img` jest z 12.11** (stary kernel z `performance`).
  Pendrive ma już kernel `e97d9a0` wgrany bez `dd`. Przed następnym pełnym
  `dd` trzeba złożyć obraz od nowa (skill `build-osukiosk-image`).

## Etap 7 — kandydaci (wybór z autorem)

Pozycje z „Zaparkowane na później” w `CLAUDE.md` ruszamy tylko na wyraźną
prośbę autora.
- Natywny boot UEFI + GPT (zaparkowane): nowsze laptopy bez CSM nie
  uruchomią dziś obrazu.
- Sieć, najpierw Ethernet, potem Wi-Fi (zaparkowane): pobieranie beatmap,
  logowanie w osu!.
- Tablety graficzne (zaparkowane): OpenTabletDriver albo sterowniki HID w
  kernelu.
- Tryb względny myszy: łatka pointer-constraints i relative-pointer do
  `cage`.
- Szybszy boot: pomiar z `printk.time=1`, mniej skryptów startowych,
  szybszy start gry.
- Układ klawiatury (`XKB_DEFAULT_LAYOUT`) i tabela compose.
- Powiększanie `/data` przy pierwszym starcie.
- Opóźnienie audio (ALSA bez dmix, kalibracja).
