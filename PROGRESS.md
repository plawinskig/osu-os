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
- ⏳ Etap 5 — stack graficzny (`seatd`, `cage`, ALSA) — **w toku: Kroki A,
  B i C zamknięte (B i C na Lenovo IdeaPad Z570, 24.10.2026); zostają D
  (pomiar input lag) i E (właściwa sesja)** (patrz „Sprzęt testowy” i
  „Plan Etapu 5” niżej).

## Sprzęt testowy Etapu 5 — Lenovo IdeaPad Z570

- **Dlaczego nie ASUS FX503VM:** iGPU Intela nie jest tam w ogóle
  eksponowany systemowi (na PCI tylko NVIDIA `10de`, UEFI bez opcji trybu
  grafiki), a `nouveau`/sterownik NVIDIA świadomie odrzucono (`CLAUDE.md`,
  „Zaparkowane”). ASUS zostaje poza testami fizycznymi Etapu 5.
- **Z570 — potwierdzone rozpoznaniem z Parrota (24.10.2026):** i3-2330M
  (Sandy Bridge, HM65), 7,7 GiB RAM, BIOS `45CN38WW`; Intel HD Graphics 3000
  `8086:0116` z `i915`, a Mesa na Parrocie (25.0.7) używa na nim `crocus` —
  zgodnie z mapowaniem loadera; obok NVIDIA GT 520M `10de:1050` (Optimus —
  panel LVDS 1366×768 60 Hz jest na Intelu, u nas NVIDIA bez sterownika);
  tylko USB 2.0 (2× EHCI); HDA `8086:1c20` z kodekiem **Realtek ALC272**
  (`10ec:0272`, subsystem `17aa:6016`, moduł `snd_hda_codec_alc662`) +
  Intel CougarPoint HDMI (`8086:2805`) — nie Conexant, jak sugerowały
  źródła o bliźniaczym G570; Wi-Fi Intel N 1000 i Ethernet RTL810xE (sieć
  zaparkowana). **Parrot bootuje w UEFI** — patrz „Boot”.
- **Rozpoznanie przed pierwszym bootem** — lekcja z ASUS-a: fakty sprzętowe
  przed cyklem build → dd → boot. Na Z570 jest zainstalowany Parrot OS
  (Debian), więc rozpoznanie robimy na nim, bez live USB: `sudo lspci -nnk`
  (iGPU `8086:0116|0126` z `i915`), tryb firmware (`/sys/firmware/efi` —
  pendrive wymaga legacy BIOS/CSM), kodek z `/proc/asound/card*/codec#*`,
  sterownik Mesy (`inxi -Gxx`/`glxinfo -B`/log Xorg), `lsusb -t`, `free -h`,
  `dmidecode`. Wynik: ✅ bramka 0 zaliczona (iGPU widoczny z `i915`, kodek
  zidentyfikowany, nasz build ma aliasy `hdaudio:v10EC0272` i
  `hdaudio:v80862805`) — szczegóły w punkcie wyżej.
- **Instalacja Parrota zostaje nietknięta:** initramfs nie widzi wewnętrznego
  dysku (`SATA_AHCI=m`, a initramfs nie ładuje modułów), a main system
  montuje tylko partycję z labelem `OSUKIOSK_DATA` (`blkid` w
  `S41mountdata`).
- **Boot:** pendrive w port USB 2.0, F12 (albo przycisk Novo) → USB HDD; w
  BIOS (F2) USB Legacy włączone. Jeśli BIOS nie wystartuje syslinuxa:
  partycja 1 zaczyna się w sektorze 1 (`sfdisk -d`: `start=1`), czego
  heurystyki emulacji USB-HDD starszych BIOS-ów mogą nie znieść — fallback:
  `offset = 1M` w `genimage-osukiosk.cfg` + offsety weryfikacji w skillu.
  **Tryb bootu:** Parrot jest zainstalowany w UEFI, a pendrive (MBR +
  syslinux) wymaga legacy. Najpierw F12 — część IdeaPadów z tej epoki sama
  wybiera tryb po tablicy partycji (MBR → legacy); jeśli pendrive'a nie ma
  na liście, w BIOS (F2, zakładka Boot) tryb „Legacy Support” (odwracalne,
  Parrot potrzebuje UEFI). Ostateczność: kernel ma `EFI_STUB`, więc
  `bzImage` jako `\EFI\BOOT\BOOTX64.EFI` dałby boot UEFI — ale natywny UEFI
  jest zaparkowany w `CLAUDE.md`, więc to decyzja autora.
- **Wariant z NVIDIA:** dGPU bez sterownika zostaje zasilone (brak runtime
  PM) — więcej ciepła i poboru, nie blokuje.

## Plan Etapu 5 — Kroki A-E

Rozbicie analogiczne do Etapu 4: małe, testowalne kroki, każdy z własną
bramką, commit dopiero po zamknięciu kroku i wyraźnej zgodzie w danej
turze (zasady z `CLAUDE.md`).

### Decyzje wiążące dla całego etapu (nie do ponownego roztrząsania bez nowego argumentu)

- **Kompozytor: `cage`, nie Sway.** Pierwotny wybór (Sway jako baseline)
  okazał się niewykonalny bez porzucenia BusyBox init: w Buildroocie
  2026.05.2 `BR2_PACKAGE_SWAY` ma twarde `depends on BR2_PACKAGE_SYSTEMD`
  (sway.mk hardkoduje `-Dsd-bus-provider=libsystemd`, brak w drzewie
  pakietu `basu` jako lżejszej alternatywy), a `BR2_PACKAGE_SYSTEMD` ma
  z kolei `depends on BR2_INIT_SYSTEMD` — czyli systemd jako PID 1, nie
  tylko biblioteka. Bezpośrednia kolizja z architekturą z `CLAUDE.md`.
  `cage` (`package/cage/Config.in`) to również gotowy pakiet Buildroota
  oparty o `wlroots`, ale **bez żadnej zależności od systemd**
  (`CAGE_DEPENDENCIES = host-pkgconf wlroots`) — i semantycznie lepiej
  pasuje do kiosku z jedną grą pełnoekranową niż i3-podobny tiling WM.
  Gamescope jako warunkowa furtka pozostaje nieaktualne (nadal brak
  pakietu w Buildroocie, nadal wymagałby własnego br2-external). Krok D
  niżej to mierzalna bramka decyzyjna (pomiar input lag) przed uznaniem
  `cage` za ostateczny wybór.
- **Device management: `eudev`, nie `mdev`.** `wlroots` (ciągnięty przez
  `cage`) ma `depends on BR2_PACKAGE_HAS_UDEV`, w tym Buildroocie
  spełnialne bez systemd tylko przez `eudev`
  (`BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV`, wykluczający wybór w
  Kconfig względem `_MDEV`). Zweryfikowane w QEMU i na fizycznym ASUS-ie:
  `eudev` poprawnie coldplaguje inne sterowniki PCI (ahci, nvme,
  snd_hda_intel) tym samym mechanizmem modalias+kmod co wcześniej mdev —
  kolejność startu (`S10udevd` w miejscu `S10mdev`, ten sam priorytet)
  nie wymagała ręcznej zmiany. **Pułapka napotkana przy tej zmianie:**
  stary plik `/etc/init.d/S10mdev` z poprzedniego builda (sprzed
  przełączenia configu) został w `output/target/` mimo wyłączenia mdev w
  Kconfig — Buildroot nie usuwa automatycznie plików zainstalowanych
  przez wcześniejsze buildy przy zmianie configu. Naprawa: ręczne
  usunięcie pliku + `make busybox-reinstall`, ten sam wzorzec co już
  udokumentowany dla `output-initramfs/target/` w sekcji workflow.
- **Sesja kiosku: dedykowany użytkownik `kiosk`, nie root.** Uzasadnienie:
  (1) zasada najmniejszych uprawnień z globalnych zasad kodowania autora;
  (2) `seatd` ma sens wyłącznie jako mediator dostępu do sprzętu dla
  procesu bez roota — trzymanie sesji jako root czyni go martwym elementem
  architektury; (3) konkretne przyszłe ryzyko już wpisane w `CLAUDE.md`
  jako "zaparkowane na później" — sieć do pobierania beatmap oznacza w
  przyszłości parsowanie nieufnej zawartości przez proces gry; granicę
  uprawnień taniej ustalić teraz (etap wciąż mały) niż przerabiać później.
  `seatd` nadal startuje jako usługa systemowa spod roota (mediator musi
  mieć uprawnienia, klient — nie); zrzucenie uprawnień dzieje się wewnątrz
  `osukiosk-session`, tuż przed uruchomieniem `cage`. **Zastrzeżenie:**
  uprawnienia partycji `/data` (dziś montowanej i używanej jako root w
  `S41mountdata`) trzeba dopasować, żeby `kiosk` mógł tam zapisywać wyniki
  — nie zakładać, że zadziała bez zmian; zweryfikować to jako część bramki
  Kroku A/B.

### ✅ Krok A — seatd + użytkownik `kiosk`

- `configs/osukiosk_main_defconfig`: `BR2_PACKAGE_SEATD=y`,
  `BR2_PACKAGE_SEATD_DAEMON=y` (jedyne dwa potrzebne symbole — `Config.in`
  seatd ma tylko trzy w ogóle, trzeci to fallback bez daemona, nieużywany
  tu), `BR2_ROOTFS_USERS_TABLES` wskazujący na nowy
  `board/osukiosk/users-table.txt`.
- **Brak własnego skryptu startowego.** Pakiet `seatd` sam instaluje
  działający `/etc/init.d/S70seatd`, gdy `BR2_PACKAGE_SEATD_DAEMON=y` i
  aktywny jest init BusyBoksa (tak jak tu) — pisanie odpowiednika
  `S41mountdata` byłoby zbędnym duplikatem. Ten gotowy skrypt uruchamia
  daemona z twardo wpisaną flagą `-g video`, **nie** grupą `seat`, którą
  tworzy `SEATD_USERS` w `seatd.mk` (grupa `seat` w praktyce nie jest
  używana przez żaden domyślny mechanizm startowy — zweryfikowane
  bezpośrednio w źródle pakietu). `kiosk` dołącza więc do `video` (już
  istniejącej w szkielecie Buildroota, potrzebnej też w Kroku B do
  `/dev/dri`), nie do `seat`.
- `board/osukiosk/users-table.txt` (nowy plik, mechanizm
  `BR2_ROOTFS_USERS_TABLES` + `mkusers`): konto `kiosk`, uid/gid **900**
  jawnie przypięte (nie auto — `mkusers` ostrzega, że auto-ID mogą się
  przesunąć między rebuildami przy zmianie zestawu pakietów), bez
  logowania, grupy dodatkowe `video,audio`.
- `S41mountdata`: po udanym mount, nierekurencyjny `chown kiosk:kiosk` +
  `chmod 0700` na `/data` (niefatalne przy błędzie, tym samym `warn()` co
  reszta skryptu) — domyka zastrzeżenie o uprawnieniach `/data` z sekcji
  "Decyzje wiążące" wyżej.
- **Bramka zweryfikowana w QEMU** (boot bezpośredni, `bzImage` +
  `boot.vfat`/`data.img` jako dwa osobne urządzenia USB): `seatd` żyje
  (stabilny PID), `/run/seatd.sock` istnieje z grupą `video`, `kiosk`
  faktycznie ma do niego dostęp zapisu, `/data` zamontowane i
  `kiosk:kiosk 0700`. Zero `WARNING`/`FATAL`/panic w logu.
  `/etc/passwd`/`/etc/group` sprawdzone pod kątem kolizji na 900 — brak
  (auto-przydzielona grupa `seat` wylądowała na 101).

### ✅ Krok B — minimalna sesja `cage`, fizyczny sprzęt — **zaliczony na Z570 (24.10.2026)**

- Zaimplementowane: `cage`, `foot` + DejaVu Mono (klient testowy — zamiast
  `swaybg`, patrz niżej), `mesa3d` z driverami Intel `crocus`
  (Gen4–7.5) i `iris` (Gen8+; `iris` wymaga `BR2_PACKAGE_MESA3D_LLVM`),
  `eudev` zamiast `mdev` w defconfigu. Po drodze doszła jeszcze jedna wymagana flaga,
  nieprzewidziana w pierwotnym planie: `BR2_TOOLCHAIN_BUILDROOT_CXX=y` —
  bez obsługi C++ w toolchainie Kconfig po cichu usuwał całą gałąź
  graficzną z `.config` (bez błędu), bo `BR2_INSTALL_LIBSTDCPP` był
  niewidoczny. Toolchain zbudowany wcześniej (bez C++) trzeba było
  ręcznie przebudować (`host-gcc-final-dirclean` + `gcc-final-dirclean`)
  — sama zmiana Kconfig tego nie wymusza.
- `usr/bin/osukiosk-session`: placeholder podmieniony — `XDG_RUNTIME_DIR`
  na `/run/user/900` (już istniejące tmpfs, żadnych nowych punktów
  montowania nie trzeba było dodawać), zrzut uprawnień do `kiosk` przez
  `su -s /bin/sh kiosk -c ...`, `exec cage -- foot /bin/sh` (na czas
  testów fizycznych z `-s` i logami — patrz pakiet diagnostyczny niżej).
- **Zweryfikowane w QEMU** (virtio-gpu, tani wstępny test): brak crashy,
  `seatd`+`libseat`+`cage` integrują się poprawnie aż do próby KMS
  ("Found 0 GPUs" tam jest oczekiwane — ten kernel ma tylko `i915`, nie
  `virtio-gpu`).
- **ASUS FX503VM:** `seatd`/`libseat`/`cage` integrują się identycznie jak
  w QEMU (seat otwarty, sesja libseat załadowana), ale iGPU Intela nie jest
  eksponowany (patrz „Sprzęt testowy”); `i915.ko`, `modules.alias` i
  `eudev --enable-kmod` potwierdzone obecne i poprawne, więc to nie defekt
  configu.
- **`crocus` — dodany pod Z570, znalezione przed testem, nie na sprzęcie:**
  Mesa była zbudowana tylko z `iris`, a loader Mesy mapuje HD 3000
  (`0x0116`/`0x0126`) na `crocus` (`src/loader/pci_id_driver_map.h`). Bez
  niego renderer GLES2 w wlroots pada, a tryb `auto` wlroots 0.20 nie spada
  na `pixman`, gdy istnieje render node (`render/wlr_renderer.c`) — `cage`
  kończyłby się w pętli `respawn`. Zmiana listy sterowników wymaga
  `make mesa3d-reconfigure`: Buildroot nie przebudowuje sam zbudowanego już
  pakietu po zmianie jego opcji.
- **Pierwszy boot na Z570 (24.10): pętla `respawn` przez klienta testowego,
  nie przez GPU.** `cage` 0.3.0 implementuje tylko `xdg-shell` (bez
  `wlr-layer-shell`), a `swaybg` bez `zwlr_layer_shell_v1` od razu kończy się
  błędem „Missing a required Wayland interface” — `cage` kończy się razem z
  nim i `init` restartuje sesję (ekran miga, `pidof cage` pusty). Na ASUS-ie
  i w QEMU niewidoczne, bo `cage` nigdy nie dochodził do startu klienta.
  `swaybg` zastąpiony przez `foot` (zwykły klient `xdg-shell`, przyda się
  też w Kroku D); stary `/usr/bin/swaybg` usunięty ręcznie z
  `output/target/`.
- **Znalezione w QEMU przed kolejnym bootem na Z570** (`cage` z backendem
  `headless` i rendererem `pixman`, klient `foot`): brakowało
  `xkeyboard-config`, a `cage` bez keymapy pomija klawiaturę (`seat.c`:
  „Unable to configure keyboard”) — na sprzęcie nie dałoby się pisać ani
  przełączyć VT. Dodany `BR2_PACKAGE_XKEYBOARD_CONFIG` (bez X11 — jego
  zależności od X są warunkowe). Brakowało też locale UTF-8 (`foot`
  pokazywał baner błędu): `BR2_GENERATE_LOCALE="C.UTF-8"` + `LANG=C.UTF-8`
  w sesji (przyda się też grze).
- **Dlaczego fizyczny sprzęt, nie QEMU:** KMS/DRM na wirtualnym GPU QEMU to
  inna ścieżka kodu niż realny iGPU Intela. QEMU może posłużyć jedynie jako
  tani, wstępny test "czy `cage` w ogóle nie pada natychmiast" pod
  `virtio-gpu`, przed zużyciem cyklu bootowania na docelowym sprzęcie —
  co ten krok właśnie potwierdził, że nie wystarcza samo w sobie.
- **Bramka ✅ (Z570, 24.10.2026):** prompt shella w `foot` na ekranie,
  wpisywane znaki widoczne, stabilny PID `cage` (wg autora), a w
  `/data/log/cage.log`: `EGL driver name: crocus`, `Using OpenGL ES 3.0
  Mesa 26.1.2`, `GL renderer: Mesa Intel(R) HD Graphics 3000 (SNB GT2)`,
  `LVDS-1: Modesetting with 1366x768 @ 60.042 Hz` — akceleracja przez
  `crocus`, nie software'owy fallback. Ctrl+Alt+F2 (`cage -s`) przełącza
  na shell roota na tty2.
- Nieszkodliwe wpisy w `cage.log`: `Failed to create //.cache for shader
  cache (Read-only file system)` (patrz „Otwarte sprawy”); `Atomic commit
  failed: Permission denied` przy przełączeniu VT (commit w trakcie
  odbierania DRM mastera przez `seatd`); asercja w `wlr_backend_finish`
  przy `poweroff` (`init` zabija `seatd`, `cage` pada przy sprzątaniu).

### ✅ Krok C — ALSA + kodeki HDA + `snd-usb-audio`, fizyczny sprzęt — **zaliczony na Z570 (24.10.2026)**

- **Znalezione przy przeglądzie configu (dotyczyło każdej maszyny):**
  efektywny `.config` kernela miał `SND_HDA_INTEL=m`, ale żadnego sterownika
  kodeka (nawet `SND_HDA_GENERIC`) — kontroler by się zbindował, ale bez
  żadnego urządzenia PCM. Kernel 6.18 przeniósł HDA do `sound/hda/codecs/`;
  Realtek i HDMI są tam podzielone na pod-moduły ukryte za `EXPERT` z
  `default y`, więc dziedziczą `m` od rodzica.
- `linux.config`: `SND_HDA_CODEC_REALTEK=m` (Z570: ALC272 →
  `snd-hda-codec-alc662`), `SND_HDA_CODEC_HDMI=m` (Z570: CougarPoint HDMI →
  `snd-hda-codec-intelhdmi`), `SND_HDA_CODEC_CONEXANT=m` (druga
  najczęstsza rodzina w laptopach; Z570 jej nie używa — dodana, zanim
  rozpoznanie pokazało Realteka, zostaje jako moduł zgodny z Podejściem B);
  `SND_HDA_GENERIC` dochodzi przez `select`. Inne rodziny (IDT, Analog,
  VIA, Cirrus, Creative) — gdy trafi się maszyna, która ich potrzebuje.
- Defconfig: `alsa-utils` z `aplay`, `amixer`, `speaker-test` (żadne z nich
  nie ma `default y`; `alsactl` i `alsamixer` są domyślne, `alsa-lib`
  dochodzi przez `select`).
- **Bramka:** `aplay -l` widzi analog (Realtek ALC272) + HDMI, po podłączeniu też
  USB audio; słyszalny `speaker-test -c 2 -t wav` na głośnikach, słuchawkach
  i USB; `kiosk` (grupa `audio`) widzi te same urządzenia. Kontrolki HDA
  startują wyciszone (`amixer -c 0 sset Master 80% unmute`).
- **Wynik ✅ (Z570, 24.10.2026):** `dmesg`: `snd_hda_codec_alc662
  hdaudioC0D0: autoconfig for ALC272` (głośnik `0x14`, słuchawki `0x21`,
  mikrofony `0x18`/`0x19`) i wejście `HDA Intel PCH HDMI/DP,pcm=3`;
  `speaker-test` słyszalny (wg autora, z sesji `kiosk` w `foot`). USB audio
  nie zostało potwierdzone. Przed tym samym testem w QEMU (emulowany Intel
  HDA) potwierdzony autoload kodeka przez eudev i `/dev/snd/*` z grupą
  `audio`.

### Tymczasowy pakiet diagnostyczny (DEV ONLY — decyzja o usunięciu w Kroku E)

Laptop nie ma konsoli szeregowej ani sieci, a getty jest wyłączone, więc na
czas fizycznych testów Etapu 5:
- `inittab`: `tty2::askfirst:-/bin/sh` — root shell bez hasła po
  Ctrl+Alt+F2 i Enterze.
- `osukiosk-session`: `cage -s` (przełączanie VT); stderr `cage` →
  `/data/log/cage.log`, `dmesg` → `/data/log/dmesg.txt`, oba nadpisywane
  przy każdym respawnie; fallback `/run/osukiosk-log`, gdy `/data` nie jest
  zamontowane.
- `osukiosk.hold` w cmdline (przy `boot:` wpisać `osukiosk osukiosk.hold`):
  sesja nie startuje `cage`. Potrzebne, bo `seatd`
  przypina nowego klienta do aktualnie aktywnego VT (`seatd/seat.c`) — przy
  pętli crashy każdy respawn przejmowałby tty2 razem z shellem.
- Podmiana sesji bez rebuilda: `cp /usr/bin/osukiosk-session /run/s`, `vi`,
  `mount --bind /run/s /usr/bin/osukiosk-session`, `chvt 1; kill $(pidof
  cage)` (najpierw `chvt 1` — inaczej nowy `cage` wyląduje na tty2). BusyBox
  nie ma `pkill` ani `timeout`.
- **F2FS zachowuje tylko to, co trafiło do checkpointu** (albo dostało
  `fsync`) — wykryte w QEMU: twarde `quit` zgubiło wszystkie logi sesji
  (następne montowanie wróciło do tego samego checkpointu `22e19b01`). Stąd
  `sync` po zrzucie `dmesg` w sesji (utrwala zrzut i pełny `cage.log` z
  poprzedniego respawnu), a na sprzęcie wyłączanie przez `poweroff` na tty2
  albo Ctrl+Alt+Del w trybie tekstowym (czyste odmontowanie `/data`), nie
  przytrzymaniem przycisku. Oba pliki zaczynają się od `date`, żeby odróżnić
  log z bieżącego bootu od pozostałości po poprzednim.
- Odczyt logów na hoście wymaga `sudo` (`/data` to `kiosk:kiosk 0700`);
  logi trzeba zabrać przed kolejnym `dd`, który nadpisuje partycję danych.

### Krok D — bramka decyzyjna: pomiar input lag `cage`, fizyczny sprzęt

Konkretna, mierzalna metoda, nie subiektywne wrażenie:
- Nagranie telefonem w slow-motion (120fps+) jednoczesnego fizycznego
  naciśnięcia klawisza/kliknięcia i widocznej reakcji na ekranie (prosty
  program testowy zmieniający kolor/pole po wejściu, albo migający kursor
  terminala).
- Zliczenie klatek między wejściem a reakcją, przeliczenie na ms (klatki ÷
  fps nagrania).
- Wynik = decyzja: `cage` zostaje ostatecznym wyborem, albo przechodzimy do
  (osobno planowanego) etapu budowy własnego pakietu Gamescope dla
  Buildroota. Docelowy próg akceptowalności ustala się w momencie
  wykonania tego kroku (subiektywna ocena grywalności rhythm game przez
  autora, nie coś do wymyślenia z góry w tym planie).
- Ten krok nie generuje commitu sam w sobie (pomiar/decyzja, nie zmiana
  kodu) — wynik dopisać do tej sekcji `PROGRESS.md`.

### Krok E — właściwy `osukiosk-session`, fizyczny sprzęt

- Zastąp placeholder finalną logiką: `cage` + docelowe miejsce na
  uruchomienie gry (`seatd` jest już osobnym serwisem: `S70seatd`).
- Decyzja o pakiecie diagnostycznym (shell na tty2 do usunięcia, `-s`
  raczej też, logi: trwały i ograniczony wariant albo out) oraz przywracanie
  stanu miksera (`alsactl`; stan na RO rootfs czy na `/data`).
- **Poza zakresem Etapu 5:** faktyczna instalacja/uruchomienie osu!lazer
  (.NET runtime) — to naturalny następny etap; dopiero tam aktualna staje
  się rozbieżność nagłówków toolchaina 7.0 vs kernel 6.18 (patrz "Otwarte
  sprawy" niżej).
- **Bramka:** `respawn` w `inittab` nadal działa jako siatka bezpieczeństwa
  (crash sesji graficznej = restart przez init, jak dziś placeholder).

### Krytyczne pliki tego etapu

- `configs/osukiosk_main_defconfig` — pakiety (seatd, cage, foot + dejavu,
  mesa3d+crocus+iris, eudev, alsa-utils).
- `board/osukiosk/linux.config` — sterowniki kodeków HDA.
- `board/osukiosk/rootfs-overlay/usr/bin/osukiosk-session` — sesja.
- `board/osukiosk/rootfs-overlay/etc/inittab` — respawn sesji, tymczasowy
  shell na tty2.

## Domknięte w tej sesji (24.10.2026)

- **Sprzęt testowy:** Lenovo IdeaPad Z570 zamiast ASUS-a (patrz wyżej).
- **Przełączanie VT z `cage` potwierdzone na Z570:** Ctrl+Alt+F2 → tty2
  (root shell) → `poweroff` działa. Wcześniejsze „Operation not permitted”
  wzięło się z `poweroff` wpisanego w `foot`, czyli jako `kiosk`.
- **Root zablokowany (`# BR2_TARGET_ENABLE_ROOT_LOGIN is not set`):** wcześniej
  root miał puste hasło (`root::`), a `/bin/busybox` jest instalowany jako
  `4755` (`BUSYBOX_PERMISSIONS`), więc `su` z sesji `kiosk` dawał roota bez
  hasła — to unieważniało granicę uprawnień, dla której powstało konto
  `kiosk` (przyszłe parsowanie nieufnych beatmap). Teraz root ma `*` (hook
  `target-finalize` w `skeleton-init-common.mk`). Shell na tty2 działa dalej
  (`askfirst` uruchamia go `init` jako root, bez logowania), przejście
  root → `kiosk` w `osukiosk-session` też.

## Otwarte sprawy (odłożone do Etapu 5, świadomie)

- **RO rootfs:** `/var/lib` jest niezapisywalny (`seedrng: can't create
  directory '/var/lib/seedrng'`). Ścieżki zapisu (`/var/lib`, `/var/log` itd.)
  wymagają tmpfs lub symlinków, zanim dojdzie zapisujący się runtime (.NET, `cage`).
- **`quiet` zdjęte z `extlinux.conf`** na czas testów Etapu 4 — decyzja o
  przywróceniu odłożona do końca całego Etapu 5, bez ruszania teraz.
- **Nagłówki toolchaina** (`BR2_KERNEL_HEADERS_7_0`, glibc `--enable-kernel=7.0`)
  są nowsze niż kernel 6.18.48. Nie blokuje bootu, ale glibc może zakładać
  syscalle nowsze niż 6.18 — rozważyć wyrównanie przed dociąganiem runtime .NET.
- **Klawiatura w awaryjnym shellu** (objaw z ASUS-a przed poprawkami) nie była
  ponownie testowana po Etapie 4. Wewnętrzna klawiatura PS/2 miała sterowniki
  wbudowane od początku; do zweryfikowania na Z570: przy `boot:` wpisać
  `osukiosk rdinit=/bin/sh` → pisanie na PS/2 i USB (albo wyjęcie
  pendrive'a tuż po starcie kernela → po 30 s `/init` spada do `exec sh`).
- **Brak cache shaderów Mesy:** `kiosk` ma `HOME=/`, więc Mesa próbuje
  `//.cache` na RO rootfs i wyłącza cache („Failed to create //.cache for
  shader cache”) — każdy start kompiluje shadery od nowa. Dla `cage` bez
  znaczenia; dla gry warto przed Krokiem E ustawić `XDG_CACHE_HOME` (albo
  `MESA_SHADER_CACHE_DIR`) na katalog na `/data`.
- **Partycja boot to w praktyce FAT16** (`lsblk -f`: `FAT16`; `mkfs` przy
  256 MB wybiera FAT16), a typ w MBR to `0x0C` (FAT32 LBA), `CLAUDE.md` też
  mówi o FAT32. Boot działa na ASUS-ie i Z570; ujednolicić przy okazji
  (`-F 32` przez `extraargs` w `genimage-osukiosk.cfg` albo typ `0x0E`).
- **LLVM/Clang w targecie:** `libLLVM` 87 MB + `libclang-cpp` 77 MB +
  `libclang` 44 MB — `iris` → `MESA3D_NEEDS_PRECOMP_COMPILER` →
  `MESA3D_OPENCL` wciąga clang do targetu, choć `libgallium` linkuje tylko
  `libLLVM`. `rootfs.squashfs` mieści się w 256 MB partycji boot i w RAM,
  więc nie blokuje; kandydat do odchudzenia przy pomiarach bootu/RAM.
