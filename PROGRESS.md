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
- ⏳ Etap 5 — stack graficzny (`seatd`, Sway, ALSA) — nierozpoczęty. Plan
  wysokopoziomowy (Kroki A-E) i dwie wiążące decyzje — patrz sekcja
  "Plan Etapu 5" niżej.

## Plan Etapu 5 — Kroki A-E

Rozbicie analogiczne do Etapu 4: małe, testowalne kroki, każdy z własną
bramką, commit dopiero po zamknięciu kroku i wyraźnej zgodzie w danej
turze (zasady z `CLAUDE.md`).

### Decyzje wiążące dla całego etapu (nie do ponownego roztrząsania bez nowego argumentu)

- **Kompozytor: Sway jako baseline, Gamescope jako warunkowa furtka.**
  Buildroot ma gotowy pakiet `sway` (+ `seatd`, `mesa3d`, `wayland`,
  `libdrm`), ale **nie ma** pakietu `gamescope` — dodanie go wymagałoby
  własnego pakietu br2-external (Vulkan, wlroots i reszta zależności),
  osobnego, sporego kawałka pracy. Krok D niżej to mierzalna bramka
  decyzyjna (pomiar input lag) przed uznaniem wyboru za ostateczny.
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
  `osukiosk-session`, tuż przed uruchomieniem Swaya. **Zastrzeżenie:**
  uprawnienia partycji `/data` (dziś montowanej i używanej jako root w
  `S41mountdata`) trzeba dopasować, żeby `kiosk` mógł tam zapisywać wyniki
  — nie zakładać, że zadziała bez zmian; zweryfikować to jako część bramki
  Kroku A/B.

### Krok A — seatd + użytkownik `kiosk` (QEMU: czy w ogóle startuje)

- Włącz `seatd` w `configs/osukiosk_main_defconfig` (dokładne symbole
  Kconfig do ustalenia przy implementacji — `grep` po
  `buildroot/package/seatd/Config.in`).
- Nowy skrypt startowy w `rootfs-overlay/etc/init.d/` (wzorem
  `S41mountdata` — angielskie komentarze tłumaczące "dlaczego").
- Dodaj użytkownika `kiosk` (bez logowania) + niezbędne grupy: do gniazda
  `seatd` (dokładna nazwa/mechanizm z dokumentacji pakietu, do ustalenia
  przy implementacji) i `audio` (węzły ALSA tworzone przez `mdev`).
- **Bramka:** `seatd` startuje, nie crash-looppuje, trzyma gniazdo; `kiosk`
  może się podłączyć z odpowiednimi uprawnieniami. Testowalne w QEMU (nie
  wymaga realnego GPU do samego uruchomienia).

### Krok B — minimalna sesja Sway, fizyczny sprzęt (ASUS)

- Włącz `sway`, `mesa3d` (driver Intel — `CONFIG_DRM_I915=m` już w
  kernelu), `wayland`, `libdrm` w defconfigu.
- Podmień placeholder `usr/bin/osukiosk-session` na uruchomienie
  minimalnego Swaya (bez osu!lazer — celowo osobny, mniejszy krok do
  przetestowania w izolacji).
- Po drodze rozwiąż faktycznie napotkane błędy zapisu (`/var/lib`,
  `XDG_RUNTIME_DIR`, `/run/user/<uid>` itp.) przez tmpfs/symlinki w
  `rootfs-overlay` — dokładny zestaw ścieżek poznamy z rzeczywistych
  komunikatów błędów, nie z góry (YAGNI: nie twórz z góry wszystkich
  możliwych punktów montowania).
- **Dlaczego fizyczny sprzęt, nie QEMU:** KMS/DRM na wirtualnym GPU QEMU to
  inna ścieżka kodu niż realny iGPU Intela. QEMU może posłużyć jedynie jako
  tani, wstępny test "czy Sway w ogóle nie pada natychmiast" pod
  `virtio-gpu`, przed zużyciem cyklu bootowania na ASUS-ie.
- **Bramka:** kompozytor widoczny na realnym ekranie ASUS-a, bez pętli
  restartów przez `respawn` (obserwacja ekranu + log z konsoli szeregowej).

### Krok C — ALSA + `snd-usb-audio`, fizyczny sprzęt

- Kernel już ma `CONFIG_SND_USB_AUDIO=m`, `CONFIG_SND_HDA_INTEL=m`,
  `CONFIG_SOUND=y`/`CONFIG_SND=y` — prawdopodobnie brakuje tylko userspace
  (`alsa-lib`, `alsa-utils`) w defconfigu.
- **Bramka:** `aplay -l` widzi urządzenia (wbudowane HDA + podłączone USB
  audio), realne odtworzenie krótkiego testowego dźwięku na obu.

### Krok D — bramka decyzyjna: pomiar input lag Sway, fizyczny sprzęt

Konkretna, mierzalna metoda, nie subiektywne wrażenie:
- Nagranie telefonem w slow-motion (120fps+) jednoczesnego fizycznego
  naciśnięcia klawisza/kliknięcia i widocznej reakcji na ekranie (prosty
  program testowy zmieniający kolor/pole po wejściu, albo migający kursor
  terminala).
- Zliczenie klatek między wejściem a reakcją, przeliczenie na ms (klatki ÷
  fps nagrania).
- Wynik = decyzja: Sway zostaje ostatecznym wyborem, albo przechodzimy do
  (osobno planowanego) etapu budowy własnego pakietu Gamescope dla
  Buildroota. Docelowy próg akceptowalności ustala się w momencie
  wykonania tego kroku (subiektywna ocena grywalności rhythm game przez
  autora, nie coś do wymyślenia z góry w tym planie).
- Ten krok nie generuje commitu sam w sobie (pomiar/decyzja, nie zmiana
  kodu) — wynik dopisać do tej sekcji `PROGRESS.md`.

### Krok E — właściwy `osukiosk-session`, fizyczny sprzęt

- Zastąp placeholder finalną logiką: `seatd` (jeśli nie jest już osobnym
  serwisem init) + Sway + docelowe miejsce na uruchomienie gry.
- **Poza zakresem Etapu 5:** faktyczna instalacja/uruchomienie osu!lazer
  (.NET runtime) — to naturalny następny etap; dopiero tam aktualna staje
  się rozbieżność nagłówków toolchaina 7.0 vs kernel 6.18 (patrz "Otwarte
  sprawy" niżej).
- **Bramka:** `respawn` w `inittab` nadal działa jako siatka bezpieczeństwa
  (crash sesji graficznej = restart przez init, jak dziś placeholder).

### Krytyczne pliki tego etapu

- `configs/osukiosk_main_defconfig` — nowe pakiety (seatd, sway, mesa3d,
  wayland, libdrm, alsa-lib, alsa-utils).
- `board/osukiosk/rootfs-overlay/etc/init.d/` — nowy skrypt startowy
  `seatd` (wzorem `S41mountdata`).
- `board/osukiosk/rootfs-overlay/usr/bin/osukiosk-session` — zastąpienie
  placeholdera.
- `board/osukiosk/rootfs-overlay/etc/inittab` — już gotowe (respawn,
  devtmpfs), prawdopodobnie bez zmian.

## Domknięte w tej sesji (22.09.2026)

- **Portable `linux.config`:** `CONFIG_INITRAMFS_SOURCE` był zaszytą ścieżką
  bezwzględną (`/home/greggy/...`) — zmieniony na ścieżkę względną
  (`../../../../output-initramfs/images/rootfs.cpio`), odporną na maszynę/
  użytkownika. Zweryfikowane: embedded initramfs identyczny bajt-w-bajt ze
  źródłowym `rootfs.cpio`, `linux-update-defconfig` nie odzyskuje starej
  ścieżki, pełny boot w QEMU. Uwaga na przyszłość: porównanie hashy `bzImage`
  przed/po **nie** jest ważną miarą — kernel wbudowuje własny licznik
  buildu, więc `bzImage` jest z natury nie-reprodukowalny między buildami
  niezależnie od zmian configu.
- **`/init`:** `mount -t vfat` zamiast autodetekcji (koniec szumu "F2FS Magic
  Mismatch"), komunikaty po angielsku, diagnostyka (`/proc/partitions` +
  ogon `dmesg`) przy porażce przed `exec sh`, pętla szukania pendrive'a
  wydłużona z 10 s do 30 s (stałe `RETRY_COUNT`/`RETRY_SLEEP` na górze
  skryptu). Zweryfikowane w QEMU osobno dla ścieżki sukcesu i dla wymuszonej
  porażki (boot bez USB-storage).
- **Skill `build-osukiosk-image`** (nieaktualny wpis usunięty stąd): problem
  z `boot-files/` był już naprawiony w commicie `3f0fb4d` z poprzedniej
  sesji — `PROGRESS.md` po prostu tego nie odnotował.

## Otwarte sprawy (odłożone do Etapu 5, świadomie)

- **RO rootfs:** `/var/lib` jest niezapisywalny (`seedrng: can't create
  directory '/var/lib/seedrng'`). Ścieżki zapisu (`/var/lib`, `/var/log` itd.)
  wymagają tmpfs lub symlinków, zanim dojdzie zapisujący się runtime (.NET, Sway).
- **`quiet` zdjęte z `extlinux.conf`** na czas testów Etapu 4 — decyzja o
  przywróceniu odłożona do końca całego Etapu 5, bez ruszania teraz.
- **Nagłówki toolchaina** (`BR2_KERNEL_HEADERS_7_0`, glibc `--enable-kernel=7.0`)
  są nowsze niż kernel 6.18.48. Nie blokuje bootu, ale glibc może zakładać
  syscalle nowsze niż 6.18 — rozważyć wyrównanie przed dociąganiem runtime .NET.
- **Klawiatura w awaryjnym shellu** (objaw z ASUS-a przed poprawkami) nie była
  ponownie testowana po Etapie 4. Wewnętrzna klawiatura PS/2 miała sterowniki
  wbudowane od początku; do zweryfikowania przy najbliższym fizycznym boocie
  (naturalnie razem z Krokiem B Etapu 5), nie jako osobna wyprawa.
