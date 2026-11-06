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
  24.10–6.11.2026). Podsumowanie niżej, szczegóły kroków A–E w historii
  tego pliku w gicie.
- ⏳ Etap 6 — gra (osu!lazer na .NET) w sesji: nie rozpoczęty, zakres do
  ustalenia. Notatki startowe niżej.

## Etap 5 — podsumowanie

- **Sesja:** `tty1::respawn` → `osukiosk-session` (root: `XDG_RUNTIME_DIR`,
  katalogi na `/data`, logi, zrzut uprawnień) → `cage` (jako `kiosk`,
  `seatd` mediuje dostęp do GPU i wejścia) → `osukiosk-game` (miejsce na
  grę, dziś placeholder `foot`). Wyjście albo crash klienta kończy `cage`, a
  `init` uruchamia sesję od nowa (Z570: nowa sesja po ok. 2 s).
- **Kompozytor `cage`:** Sway wymaga systemd jako PID 1, Gamescope wymaga
  Vulkana, którego HD 3000 nie ma. Krok D (pomiar kamerą 240 kl./s): od
  wciśnięcia do obrazu ok. 55 ms w grze bez vsync, 71 ms z vsync. `cage`
  dokłada jedną klatkę kolejkowania bez własnego jittera, a największy
  rozrzut daje klawiatura laptopa (ok. 15–18 ms ±6 ms). Dane:
  `../measurements/stage5-step-d/`.
- **Grafika:** Mesa `crocus` (Gen4–7.5) i `iris` (Gen8+). Na Z570 jest
  akceleracja przez `crocus` (GLES 3.0), a cache shaderów działa w
  `~/.cache/mesa_shader_cache`.
- **Audio:** ALSA, kodeki HDA (Realtek, Conexant, HDMI) i `snd-usb-audio`
  jako moduły. Mikser obsługuje reguła udev `90-alsa-restore.rules` razem z
  `S42alsa`. Stan leży w `/data/alsa/asound.state` i zapisuje się przy
  czystym wyłączeniu. Bez pliku obowiązują domyślne poziomy ALSA (Master
  −20 dB, wyjścia włączone; na Z570 słyszalne i w porządku).
- **CPU:** domyślny governor to `performance`. Wcześniej `userspace` trzymał
  CPU bez HWP na minimum (Z570: 800 MHz). Nadpisanie przy `boot:`:
  `osukiosk cpufreq.default_governor=schedutil`.
- **Trwałe ścieżki:** `HOME=/data/home` dla `kiosk`, `/data/log`,
  `/data/alsa`. Bez `/data` stan trafia na tmpfs (`/run/osukiosk-data`), a
  sesja startuje normalnie. `seedrng` trzyma ziarno w `/run/seedrng`.
- **Boot:** `quiet`, prompt `boot:` przez 1 s, etykiety `debug` i `hold`
  (patrz „Tryb diagnostyczny”).

## Sprzęt testowy — Lenovo IdeaPad Z570

- i3-2330M (Sandy Bridge, 2 rdzenie / 4 wątki, bez HWP i turbo: zegar
  2,2 GHz, sterownik `intel_cpufreq` w trybie passive), 7,7 GiB RAM.
- Intel HD 3000 (`8086:0116`, `i915` + `crocus`) obok NVIDIA GT 520M bez
  sterownika (Optimus). Panel LVDS 1366×768 @ 60,042 Hz jest podpięty do
  Intela.
- Tylko USB 2.0. HDA: Realtek ALC272 (`snd-hda-codec-alc662`) i HDMI
  CougarPoint. Klawiatura wbudowana jest na PS/2.
- Boot: pendrive w port USB 2.0, F12 → USB HDD (legacy). Prompt `boot:`
  łapie się Spacją wciśniętą zaraz po wyborze w F12. Zainstalowany na
  dysku Parrot (UEFI) zostaje nietknięty: initramfs nie widzi dysku, a main
  system montuje tylko partycję `OSUKIOSK_DATA`.
- ASUS FX503VM odpada w testach grafiki: jego iGPU nie jest widoczny w
  systemie (na PCI jest tylko NVIDIA).

## Tryb diagnostyczny (`debug` / `hold`)

- Przy `boot:` (1 s, pierwszy klawisz zatrzymuje odliczanie) wpisz
  etykietę:
  - `debug`: shell roota na tty2 bez hasła (Ctrl+Alt+F2), `cage -s`
    (przełączanie VT), komunikaty kernela na ekranie;
  - `hold`: jak `debug`, ale sesja nie startuje `cage` i nie rusza logów
    poprzedniego bootu.

  Parametry wpisane po etykiecie są dopisywane do linii poleceń kernela.
  Na partycji FAT pendrive'a można ustawić `DEFAULT debug` bez rebuilda.
- Zwykły boot nie ma shella (wrapper `osukiosk-debug-shell` śpi) ani
  przełączania VT. Fizyczny dostęp i tak daje roota (`rdinit=/bin/sh` przy
  `boot:`), więc to kwestia wygody, a nie granica bezpieczeństwa.
- Logi sesji są zawsze w `/data/log`:
  - `session.log`: stderr `su`, `cage` i klienta w bieżącej sesji;
  - `session.log.1`: poprzednia sesja, np. ta, która padła;
  - `dmesg.txt`: zrzut z chwili startu sesji.

  Zgranie na host: `sudo bash ../measurements/stage5-step-e/copy-logs.sh`.
  `dd` nadpisuje partycję danych, więc logi trzeba zabrać przed nim.
- F2FS zachowuje tylko to, co trafiło do checkpointu (co ≤ 60 s) albo
  dostało `fsync`. Sesja robi `sync` po rotacji logów, więc log poprzedniej
  sesji przetrwa wyrwanie zasilania, a log bieżącej tylko do ostatniego
  checkpointu. Czyste wyłączenie to dziś wyłącznie `poweroff` na tty2 w
  trybie debug, który zapisuje też stan miksera.
- Podmiana sesji bez rebuilda (tryb `debug` albo `hold`):
  `cp /usr/bin/osukiosk-session /run/s`, `vi /run/s`,
  `mount --bind /run/s /usr/bin/osukiosk-session`, potem
  `kill $(pidof cage)` (w `hold`: `kill $(pidof sleep)`) i `init` uruchamia
  kopię. Sesja sama robi `chvt 1`, więc nowy `cage` nie przejmie tty2.
  BusyBox nie ma `pkill`, `timeout` ani `logread`; syslog jest w
  `/var/log/messages` (tmpfs).
- Znane, nieszkodliwe wpisy w `session.log`:
  - `Failed to disable CRTC` i `Atomic commit failed: Permission denied` przy
    przełączaniu VT;
  - asercja `wlr_backend_finish` przy `poweroff` (init zabija `seatd`);
  - `failed to instantiate compose table` z `foot` (patrz „Otwarte sprawy”).
- Narzędzia rund sprzętowych (poza repo, szablony na kolejne rundy):
  - `../measurements/stage5-step-d/`: sonda, nagrania, analiza;
  - `../measurements/stage5-step-e/`: `step-e.sh`, `upload-round.sh`,
    `copy-logs.sh`.

  Sonda `latency-probe` (`package/`, `src/`) zostaje w drzewie poza
  defconfigiem: `BR2_PACKAGE_LATENCY_PROBE=y` przywraca ją do ponownych
  pomiarów.

## Etap 6 (gra) — notatki startowe

- Grę uruchamia `/usr/bin/osukiosk-game`, wywoływany przez `cage` jako
  `kiosk`, bez roota. `HOME=/data/home`, więc dane gry (`~/.local/share/osu`)
  i cache trafią na `/data`.
- Renderować bez vsync: w `cage` to ok. 25 ms od kernela do prezentacji
  zamiast 43 ms (Krok D).
- Do poważnego grania zewnętrzna klawiatura USB 1000 Hz prawdopodobnie
  zmniejszy i opóźnienie, i rozrzut wejścia.
- Niezmierzone: mysz 125 Hz. Rival 110 ma natywnie 1 kHz, więc
  `usbhid.mousepoll=1` nic dla niej nie zmienia.

## Otwarte sprawy

Na etap z grą:
- **Nagłówki toolchaina** (`BR2_KERNEL_HEADERS_7_0`, glibc
  `--enable-kernel=7.0`) są nowsze niż kernel 6.18.48. Boot to nie
  przeszkadza, ale glibc może zakładać syscalle nowsze niż 6.18. Wyrównać
  przed dociąganiem runtime .NET; wymaga to pełnego rebuilda toolchaina.
- **`performance` vs `schedutil` z grą:** porównać ciepło i hałas z czasem
  klatki pod realnym obciążeniem. W Kroku D sonda dwa razy zmierzyła na
  cpu0 tylko 1,5 i 2,0 GHz mimo `performance` (przyczyna nieznana:
  głębokie C-states albo dławienie przez kontroler laptopa, np. na
  baterii). W rundzie Kroku E wszystkie rdzenie pokazały ok. 2195 MHz.
- **Czyste wyłączanie bez shella:** dziś wyjście klienta oznacza respawn,
  a danych chronią checkpointy F2FS i `fsync` aplikacji. Możliwe drogi:
  wyjście z gry kodem 0 → `poweroff` albo przycisk zasilania przez `acpid`
  (dziś wyłączony w BusyBox). Od tego zależy też zapis stanu miksera poza
  trybem debug.
- **`cage -m extend`** (domyślne) rozciąga grę na panel i zewnętrzny monitor
  naraz. Rozważyć `-m last` albo wybór wyjścia.
- **`session.log`** rośnie przez całą sesję, jeśli gra dużo pisze na stderr.
- **Tabela compose:** `foot` zgłasza `failed to instantiate compose table`,
  bo `/usr/share/X11/locale` nie ma w obrazie, więc dead keys nie działają.
  Sprawdzić wpisywanie tekstu w grze (SDL też używa xkbcommon).
- **LLVM/Clang w targecie:** `libLLVM` 87 MB, `libclang-cpp` 77 MB i
  `libclang` 44 MB. Łańcuch `iris` → `MESA3D_NEEDS_PRECOMP_COMPILER` →
  `MESA3D_OPENCL` wciąga clang do targetu, choć `libgallium` linkuje tylko
  `libLLVM`. Kandydat do odchudzenia przy pomiarach RAM i bootu z grą.

Przy zmianie layoutu obrazu (offset 1M, UEFI):
- **Partycja boot to w praktyce FAT16** (`mkfs` wybiera FAT16 przy
  256 MB), a typ w MBR to `0x0C` (FAT32 LBA). Boot działa na ASUS-ie i
  Z570. Ujednolicić (`-F 32` przez `extraargs` w `genimage-osukiosk.cfg`
  albo typ `0x0E`).
