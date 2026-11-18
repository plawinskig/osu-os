# CLAUDE.md

Ten plik jest trwałym kontekstem projektu dla Claude Code. Czytaj go na początku
każdej sesji pracy nad tym repozytorium. Bieżący, roboczy stan prac (co jest
w toku, jaki jest aktualny blocker) znajduje się w `PROGRESS.md` — ten plik
jest świadomie krótki i tymczasowy, aktualizuj/nadpisuj go po zamknięciu
każdego etapu.

Pełna, szczegółowa narracja projektu (co próbowaliśmy, co nie zadziałało,
dlaczego podjęto dane decyzje) jest w `HISTORY.md`. To **nie jest** wymagana
lektura na każdej sesji — sięgnij po nią tylko wtedy, gdy potrzebujesz
głębszego kontekstu, którego nie dostarcza ani ten plik, ani `git log`
(commity sprzed wprowadzenia zasad niżej bywają lakoniczne, więc `HISTORY.md`
częściowo pełni rolę, którą docelowo powinien pełnić dobrze opisany `git log`
— nowe wydarzenia dokumentuj przez commity, nie przez dopisywanie do tego
pliku).

## Co to za projekt

Dedykowany, minimalistyczny system operacyjny "kiosk" (x86_64, Buildroot) do
bootowania z pendrive'a USB i uruchamiania gry osu!lazer na dowolnym sprzęcie
zdolnym tę grę odpalić — nie pod jeden konkretny model laptopa. Autor: student
informatyki, doświadczony w C++/Rust/Python, w trakcie nauki C. Preferuje
rozumieć "dlaczego", nie tylko "jak" — przy istotnych decyzjach technicznych
krótko uzasadniaj wybór, nie tylko wykonuj.

## Architektura

**Model: dwuetapowy boot do RAM ("two-stage rocket").** Initramfs (mały loader,
statycznie zaszyty w głównym kernelu przez `CONFIG_INITRAMFS_SOURCE`) montuje
partycję boot, kopiuje `rootfs.squashfs` do `tmpfs`, wykonuje `switch_root`.
Od tego momentu USB przestaje być wąskim gardłem — cały main system działa
z RAM-u.

**Uniwersalność sprzętowa ("Podejście B"), nie kernel pod jeden laptop.**
Drivery fundamentalne dla samego bootu (VFS, tmpfs, squashfs, overlayfs, ACPI,
SMP) są wbudowane na stałe (`=y`). Drivery specyficzne dla konkretnego sprzętu
(GPU, audio, storage, USB, input) są modułami (`=m`) ładowanymi dynamicznie
przez `eudev` na podstawie realnie wykrytego sprzętu — jak w Live USB dystrybucji
typu Ubuntu/Arch. **Wyjątek:** cokolwiek co musi działać już wewnątrz initramfs,
zanim `switch_root` się wykona (np. USB storage, FAT32, klawiatura do awaryjnego
shella), musi być wbudowane na stałe w GŁÓWNYM kernelu — initramfs nie ma
mechanizmu ładowania modułów z zewnątrz siebie. Aktualnie wbudowane (`=y`) z tego
powodu: rdzeń USB (`USB`, xHCI/EHCI + ich `*_PCI`, `USB_STORAGE`, `USB_HID`,
`HID_GENERIC`), FAT/VFAT + NLS, squashfs (z `SQUASHFS_XZ`), loop, `F2FS_FS`
(partycja danych). Potwierdzone na ASUS FX503VM: SATA/AHCI i inne moduły
ładują się już po `switch_root` przez coldplug (najpierw `mdev`, od Etapu 5
`eudev` — ten sam mechanizm modalias + kmod; podejście B działa).

**Read-Only rootfs + trwała partycja danych.** `rootfs.squashfs` jest z natury
RO i kopiowany do RAM — odporny na nagłą utratę zasilania. Osobna partycja
**F2FS** (label `OSUKIOSK_DATA`) trzyma to, co ma przetrwać restart: dane gry
(beatmapy, ustawienia, wyniki) i cache (m.in. shadery Mesy) w `/data/home`, czyli
`HOME` konta `kiosk` ustawiany przez sesję, logi sesji w `/data/log` i stan
miksera w `/data/alsa`. Bez tej partycji sesja trzyma ten stan na tmpfs
(`/run/osukiosk-data`) i startuje normalnie.
F2FS wybrany celowo — projektowany pod pamięci flash (log-structured, dobry
wear-leveling), pasuje pod wzorzec częstych małych zapisów (wynik po każdej
ukończonej mapie).

**Init: BusyBox init, nie systemd.** Płaski `/etc/inittab` main systemu żyje
w `board/osukiosk/rootfs-overlay/etc/inittab` (initramfs go nie używa — jego PID 1
to skrypt `initramfs-overlay/init`). Wpis `tty1::respawn:/usr/bin/osukiosk-session`
to nadzorca kiosku: init restartuje launcher przy każdym jego wyjściu. Łańcuch
sesji: `osukiosk-session` (root: katalogi, logi, zrzut uprawnień) → `cage -m last`
(jako `kiosk`) → `osukiosk-game` → osu!lazer. Sesja czeka na `cage`, który
zwraca kod wyjścia gry: 0 (gracz wyszedł z gry) oznacza `poweroff`, a inny kod
(crash) kończy skrypt, więc init robi respawn. Przycisk zasilania obsługuje
BusyBox `acpid` (wpis `::respawn`, akcja `/etc/acpi/PWRF/00000080` →
`poweroff`). Pierwszą linią `::shutdown` jest `osukiosk-stop-session`: init
wykonuje linie shutdown, zanim zabije resztę procesów, więc bez niej gra i log
sesji trzymałyby `/data`, a `rcK` (S41mountdata) nie odmontowałby jej czysto. Wpis
`tty2::respawn:/usr/bin/osukiosk-debug-shell` daje shell roota tylko z
`osukiosk.debug` albo `osukiosk.hold` w linii poleceń (etykiety `debug`/`hold` w
`extlinux.conf`); w zwykłym boocie śpi. Uwaga: BusyBox
init **nie** kończy działania przy braku wpisów `respawn` (jego pętla główna to
`while (1)`); bez tego wpisu system po prostu wisi bez sesji. Inittab main systemu
montuje `devtmpfs` na `/dev` jako pierwszy wpis `sysinit`, bo `/dev` w squashfs
jest pustym katalogiem, a `switch_root` nie przenosi montowań z initramfs.

**Bootloader: syslinux/extlinux, MBR** (nie GRUB, nie na razie czysty
UEFI-GPT — działa w trybie Legacy/CSM).

**Grafika/audio (Etap 5, zamknięty 6.11.2026):** brak DE, `seatd` + `cage` (kompozytor
kiosk na `wlroots`, jedna aplikacja pełnoekranowa) bezpośrednio na KMS/DRM,
priorytet: minimalny input lag i audio latency. Sway odpadł, bo w tym
Buildroocie wymaga systemd jako PID 1; Gamescope nie ma pakietu (wymagałby
własnego pakietu br2-external) — szczegóły w historii `PROGRESS.md` (Etap 5)
w gicie. Wybór
`cage` przeszedł mierzalną bramkę (Krok D, 5.11.2026). Na Z570 od wciśnięcia
do obrazu w grze bez vsync mija ok. 55 ms, z czego jedna klatka to
kolejkowanie w `cage`; największy rozrzut daje klawiatura laptopa, nie
kompozytor. Gamescope odpada także sprzętowo: wymaga Vulkana, a Intel Gen6
(HD 3000) nie ma w Mesie sterownika Vulkan. Mesa: Gallium `crocus` (Intel Gen4–7.5)
+ `iris` (Gen8+) + `llvmpipe` (programowy, dla QEMU); desktop OpenGL bez X11
daje libglvnd (`libOpenGL.so.0`). `cage -m last` pokazuje grę tylko na ostatnio
podłączonym wyjściu. Audio na start: sam ALSA (sterowniki kodeków HDA +
`snd-usb-audio` jako moduły), bez PipeWire (świadome uproszczenie
edukacyjne, PipeWire to rozszerzenie na później). Poziomy miksera: reguła
udev `90-alsa-restore.rules` + `S42alsa`, stan w `/data/alsa/asound.state`
zapisywany przy czystym wyłączeniu (bez pliku: domyślne poziomy ALSA).

**Gra (Etap 6, zamknięty 18.11.2026):** pakiet `package/osu-lazer` instaluje
oficjalne wydanie do `/opt/osu-lazer` w rootfs, więc gra też działa z RAM.
To AppImage z przypiętą wersją i sha256, rozpakowany przy buildzie bez
uruchamiania (`appimage-offset.sh` + `unsquashfs`), z `_REDISTRIBUTE = NO`.
Runtime .NET (self-contained), SDL3, BASS i FFmpeg są w paczce. Z systemu gra
bierze glibc, ICU, OpenSSL, libglvnd, Wayland, xkbcommon i ALSA (`select` w
`Config.in` pakietu); `BR2_STRIP_EXCLUDE_DIRS` chroni jej pliki przed stripem.
Wymaga GL 3.2 core (na HD 3000 `crocus` daje 3.3). `osukiosk-game` wyłącza
updater gry (`OSU_EXTERNAL_UPDATE_PROVIDER`) i wymusza Wayland. Bez sieci
beatmapy przychodzą przez `/data/import`: pliki `.osz`/`.olz` trafiają do gry
jako argumenty startu, a ona kasuje zaimportowane. Dane i logi gry leżą w
`/data/home/.local/share/osu`.

## Decyzje techniczne — nie podważaj bez dobrego powodu

- **C library: glibc**, nie musl — osu!lazer to aplikacja .NET (osu-framework
  na SDL) z natywnymi bibliotekami budowanymi pod glibc (np. własnościowy BASS
  do audio), ryzyko niestabilności natywnych bindingów na musl uznano za
  nieopłacalne.
- **Target Architecture Variant: generic x86-64** — celowo NIE konkretna
  mikroarchitektura (skylake/icelake itp.), złamałoby to uniwersalność.
- Initramfs budowany jako **osobna konfiguracja Buildroota** w osobnym
  katalogu wyjściowym (`../output-initramfs/`, obok `../buildroot/`, nie w nim;
  inny `.config` niż main system w `../buildroot/output/`) — to dwa niezależne
  drzewa configu tego samego źródła Buildroota. **Mylenie ich było już przyczyną
  realnego blockera w tym projekcie** — zawsze sprawdzaj, czy zmieniasz config
  kernela, który faktycznie się bootuje (main system, `board/osukiosk/linux.config`),
  czy config initramfsu (który generuje tylko `rootfs.cpio`, wchłaniany przez
  ten pierwszy — initramfs sam w sobie nigdy nie produkuje bootowalnego
  `bzImage`; w ogóle nie zawiera kernela). `CONFIG_INITRAMFS_SOURCE` w
  `linux.config` jest celowo ścieżką **względną**
  (`../../../../output-initramfs/images/rootfs.cpio`), nie bezwzględną —
  kbuild rozwiązuje tę ścieżkę względem katalogu budowy kernela
  (`buildroot/output/build/linux-<wersja>/`), a Buildrootowe `$(VAR)` (jak w
  `BR2_ROOTFS_OVERLAY` niżej) nie działa wewnątrz `linux.config`, bo to plik
  konsumowany przez odrębne, własne drzewo Kconfig kernela, nieznające
  symboli Buildroota. Ta ścieżka zakłada domyślne położenie katalogu
  wyjściowego Buildroota (bez własnego `O=`) i niezmienność powyższego
  sąsiedztwa katalogów.
- **Config kernela main systemu:** źródłem prawdy jest `board/osukiosk/linux.config`
  (savedefconfig), podłączony w `configs/osukiosk_main_defconfig` przez
  `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG`. Edytujesz ten plik, `make -C ../buildroot`
  regeneruje z niego `.config` kernela.
- Initramfs: linkowanie **"shared only"**, nie static — Buildroot blokuje pełny
  static link z glibc ze względu na NSS (`libnss_*.so` doładowywane
  dynamicznie nawet w binarkach pozornie statycznych). To ograniczenie glibc,
  nie do obejścia bez przejścia na musl.
- BusyBox `mount` (i w initramfs, i w main systemie) **nie wspiera flagi `-L`**
  (`FEATURE_MOUNT_LABEL` wyłączone) — `initramfs-overlay/init` identyfikuje
  partycję boot przez iterację po węzłach `/dev/sd*`/`/dev/nvme*`, a
  `S41mountdata` znajduje partycję danych przez `blkid` (etykieta
  `OSUKIOSK_DATA`) i montuje `mount -t f2fs`.
- **Rootfs main systemu jest read-only** (squashfs). Punkty montowania
  (np. `/data`) muszą istnieć w `rootfs-overlay` — pusty katalog zaznaczamy plikiem
  `.empty` (Buildroot kopiuje overlay przez `rsync --exclude .empty`, więc katalog
  powstaje, a plik nie trafia do targetu). `mkdir` w runtime na `/` nie zadziała.
  Zapisywalne są tylko tmpfs-y (`/run`, `/tmp`; `/var/log` i `/var/cache` to
  symlinki do `/tmp`) i `/data`. `/var/lib` jest niezapisywalny, dlatego
  `seedrng` trzyma ziarno w `/run/seedrng` (`rootfs-overlay/etc/default/seedrng`),
  a sesja kieruje `HOME` konta `kiosk` na `/data/home`.
- Label partycji FAT32 **ograniczony do 11 znaków** (limit specyfikacji) —
  obecny label to `OSUBOOT`.
- **Layout obrazu:** partycja boot 1 GiB FAT32 od 1 MiB (`align = 1M`, `-F 32`
  w `genimage-osukiosk.cfg`), dane F2FS 4 GiB. Dopóki layout się nie zmienia,
  pendrive aktualizuje się bez `dd` (podmiana `bzImage` i `rootfs.squashfs`).
- **Nagłówki toolchaina = kernel:** main ma `AS_KERNEL` (domyślne przy
  kernelu) z `BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_6_18`, initramfs (bez
  kernela) ma `BR2_KERNEL_HEADERS_6_18`. glibc nie może zakładać syscalli
  nowszych niż kernel. Przy podbiciu kernela podbij oba, co oznacza pełny
  rebuild toolchaina.
- **`board/osukiosk/post-build.sh`** usuwa z targetu clang, libclc i narzędzia
  SPIR-V. Mesa wciąga je jako pakiety targetu (iris → precomp compiler →
  OpenCL), ale w runtime ich nie używa (−41 MB squashfs).
- **`S10udevd` w overlayu** startuje `udevd --daemon`, który forkuje się
  dopiero po związaniu netlinka i wczytaniu reguł. Wersja Buildroota
  (`start-stop-daemon --background` i od razu `udevadm trigger`) gubiła
  zdarzenia coldplug: w QEMU z KVM jeden boot na cztery był bez modułów.
- **Domyślny governor `schedutil`** (runda governora, 18.11.2026): w grze
  działa tak samo jak `performance`, w menu jest chłodniej. `performance`
  zostaje wbudowany, przywraca go `osukiosk cpufreq.default_governor=performance`
  przy `boot:`.
- Cała customizacja Buildroota żyje w `osu-kiosk-external/` (mechanizm
  `br2-external`) — nigdy nie edytuj plików wewnątrz `../buildroot/` poza
  generowanymi artefaktami builda. Update Buildroota do nowszego tagu LTS nie
  może nadpisać naszej pracy.

## Zaparkowane na później — nie ruszać bez wyraźnej prośby

Sieć (Wi-Fi/Ethernet, do pobierania beatmap), obsługa tabletów graficznych
(OpenTabletDriver, HID Wacom/XP-Pen), NVIDIA proprietary driver, natywny
UEFI+GPT boot, druga "chirurgiczna" wersja systemu pod jeden konkretny laptop.

## Zasady pracy z Git — bezwzględnie obowiązujące

1. **Autor commituje własną, skonfigurowaną tożsamością Git.** Nie wymuszaj,
   nie zmieniaj, nie proponuj innego `user.name`/`user.email`.
2. **Nigdy nie dodawaj stopki `Co-Authored-By` ani podobnych automatycznych
   adnotacji** w treści commitów.
3. **Wiadomości commitów pisz po angielsku**, niezależnie od języka rozmowy
   w danej sesji.
4. **Claude NIGDY nie wykonuje `git commit`, `git push` ani żadnej innej
   operacji zmieniającej historię repozytorium (w tym `git rebase`,
   `git reset --hard`, force-push) bez wyraźnej, osobnej zgody autora
   wyrażonej w danej turze rozmowy.**
   - Polecenia typu "wdróż zmiany", "napraw X", "zbuduj obraz" to zgoda na
     **edycję plików i wykonywanie komend budujących/testujących** — to NIE
     jest zgoda na commit.
   - Domyślny tryb pracy: zaimplementuj zmianę, zatrzymaj się, opisz co
     zostało zrobione i poczekaj na jawne polecenie w stylu "zacommituj" /
     "commit it" / "git commit".
   - Nie czekaj z commitami "na koniec dużej sesji" — gdy autor da zgodę na
     commit, rób to na bieżąco, przy naturalnych, logicznych checkpointach
     (np. po zamknięciu jednego kroku), nie kumuluj wielu niepowiązanych
     zmian w jeden gigantyczny commit, chyba że autor poprosi inaczej.
5. **Format wiadomości commitu:**
   - **Pierwsza linia (tytuł):** zwięzłe streszczenie całości zmiany,
     obejmujące wszystkie zmodyfikowane pliki łącznie — nie tylko jeden
     z nich. Tryb rozkazujący, bez kropki na końcu, np.
     `Enable USB/FAT/HID drivers in main kernel config, fix initramfs mount fallback`.
   - **Pusta linia**, a następnie **osobny, krótki akapit dla każdego
     zmodyfikowanego pliku** — opisany tak, jakby ten plik był commitowany
     samodzielnie, w oderwaniu od reszty. Format:
     ```
     <Krótki tytuł całościowy zmiany>

     board/osukiosk/linux.config: enabled CONFIG_USB_HID, CONFIG_USB_STORAGE,
     CONFIG_VFAT_FS and related drivers as built-in (=y) instead of modules,
     since initramfs cannot load kernel modules before switch_root.

     board/osukiosk/initramfs-overlay/init: replaced label-based partition
     lookup (mount -L, unsupported by BusyBox mount) with iteration over
     /dev/sd* and /dev/nvme* device nodes.
     ```
   - Jeśli commit dotyczy jednego pliku, drugi akapit i tak zostaje (opisuje
     ten jeden plik) — konsekwencja formatu, nie wyjątek.

## Inne konwencje projektu

- Kod, komentarze w kodzie, nazwy plików/zmiennych: **angielski**.
- Rozmowa/wyjaśnienia w czacie: **polski** (chyba że autor poleci inaczej).
- Zawsze weryfikuj `/dev/sdX` przez `lsblk` bezpośrednio przed każdą komendą
  `dd` piszącą na fizyczny nośnik — operacja jest nieodwracalna. Nigdy nie
  odpalaj `dd` na urządzenie blokowe bez tej weryfikacji w tej samej turze;
  finalny `dd` na pendrive wykonuje autor, nie Claude (patrz skill
  `build-osukiosk-image`).
- Przy zmianie configu kernela zawsze rozróżniaj main system vs initramfs
  (patrz sekcja "Decyzje techniczne" wyżej).
- Po każdej zmianie flag kernela **weryfikuj `grep`-em efektywny** `.config`
  (`../buildroot/output/build/linux-6.18.48/.config`), nie tylko wpis w
  `linux.config`: Kconfig cicho cofa tristate-dzieci, gdy rodzic jest niższy
  (np. `USB_XHCI_HCD=y` przy `USB=m` kończy jako `m`). Ustawiaj więc rodzica
  pierwszy. Potem `make -C ../buildroot linux-update-defconfig` normalizuje
  `linux.config` do minimalnej postaci (dziedziczone domyślne flagi znikają).
- Do `git` nie trafiają artefakty builda: `board/osukiosk/bzImage`,
  `rootfs.squashfs`, `output/`, `*.img` są w `.gitignore`.
- Rundy na sprzęcie (Z570): narzędzia i wyniki leżą poza repo, w
  `../measurements/<runda>/` (spis w `../measurements/README.md`), a procedura
  jest w skillu `hardware-test-round`. Zrzuty ekranu z testów trafiają do
  `../screenshots/<data>-<temat>/` z krótkim `README.md`.

## Workflow builda i testu

Ścieżki i komendy w tym pliku są względne wobec katalogu repo
(`osu-kiosk-external/`), z którego się pracuje; `buildroot/` i `output-initramfs/`
są jego rodzeństwem (`../buildroot`, `../output-initramfs`).

1. **Initramfs** (tylko gdy zmienia się `initramfs-overlay/`): `make -C
   ../output-initramfs`. Usunięty plik overlayu zostaje w
   `../output-initramfs/target/` (overlay tylko kopiuje) — usuń go ręcznie i zrób
   `busybox-reinstall`. Potem obowiązkowo `make -C ../buildroot linux-rebuild`, żeby
   kernel wchłonął nowe `rootfs.cpio`.
2. **Main system:** `make -C ../buildroot` (kernel + moduły + `rootfs.squashfs`).
   Po edycji `configs/osukiosk_main_defconfig` najpierw `make -C ../buildroot
   osukiosk_main_defconfig` — **nie** `make defconfig`: ten bierze
   `BR2_DEFCONFIG` wyłącznie z linii poleceń i bez niego generuje `.config` z
   samych wartości domyślnych Buildroota (trafione raz w Etapie 5). Buildroot
   nie przebudowuje sam już zbudowanego pakietu po zmianie jego opcji (np.
   listy sterowników Mesy) — potrzebny `make -C ../buildroot <pakiet>-reconfigure`.
   Pakiet wyłączony w defconfigu zostawia swoje pliki w `../buildroot/output/target/`
   (trafiło się `S10mdev`, `swaybg`, `latency-probe`) — usuń je ręcznie przed `make`.
   Po buildzie `make -C ../buildroot savedefconfig` + `git diff configs/`: diff
   ma pokazać wyłącznie zamierzone linie (Kconfig potrafi po cichu wyciąć
   zależne opcje). Efektywny `.config` main systemu to `../buildroot/.config`
   (build bez `O=`), nie plik w `output/`.
   Własne pakiety mają metadane w `package/<nazwa>/`, podpięte przez
   `Config.in` i `external.mk` w katalogu głównym repo, a źródła w
   `src/<nazwa>/` (`_SITE_METHOD = local`). Po edycji źródła potrzebny jest
   `make -C ../buildroot <nazwa>-rebuild`, bo zwykły `make` nie zauważa zmian
   w lokalnym katalogu.
3. **Obraz:** skill `build-osukiosk-image`. Uwaga: `genimage` czyta pliki z
   `board/osukiosk/` (`--inputpath .`), więc `bzImage` i `rootfs.squashfs` kopiujemy
   tam (katalog `boot-files/` był nieużywany i zawierał tylko stare kopie —
   usunięty, nie odtwarzaj go). Krok
   `extlinux --install` wymaga `sudo` — uruchamia go autor. Gotowe skrypty dla
   autora leżą w katalogu skilla: `install-extlinux.sh` i `update-stick.sh`
   (aktualizacja pendrive'a bez `dd`).
4. **Test w QEMU przed pendrive'em:** `board/osukiosk/qemu-test.sh` (użycie i
   gotowe przykłady w nagłówku skryptu).
   - `direct <nazwa> [czekanie-s] [-- komendy…]` bootuje `bzImage`
     bezpośrednio (`boot.vfat` + rzadka kopia `data.img` jako dwa pendrive'y
     USB, log kernela na serialu); `syslinux <nazwa> …` bootuje cały
     `osukiosk.img` przez SeaBIOS + syslinux (`snapshot=on`), a `BOOT_LINE`
     wpisuje przy `boot:`. Komendy po `--` trafiają klawisz po klawiszu
     (`sendkey` przez monitor) do shella roota na tty2 (jest tylko z
     `osukiosk.debug` albo `osukiosk.hold`; `NO_DATA=1` bootuje bez pendrive'a
     z danymi). Zrzuty ekranu (PNG),
     log seriala i kopia danych lądują w gitignorowanym
     `board/osukiosk/qemu-artifacts/`; QEMU nigdy nie pisze do `data.img` ani
     `output/osukiosk.img`. Własne wywołania QEMU: gniazdo monitora po
     ścieżce względnej (limit 108 B).
   - QEMU działa z KVM (`-cpu host -smp 4`), 4 GiB RAM i `-vga virtio`. Sesja
     i gra renderują się przez llvmpipe (`kms_swrast`), więc widać całą sesję z
     grą. Na sprzęcie zostaje sprawdzić `crocus`, prawdziwe czasy i USB.
     `CMDLINE_EXTRA=osukiosk.debug` daje shell na tty2 obok gry, a
     `osukiosk.hold` sesję bez `cage`, z nietkniętymi logami poprzedniego
     bootu. Na sprzęcie to etykiety `debug` i `hold` przy `boot:`.
   - Emulowane audio (BASS potrzebuje urządzenia ALSA): `QEMU_EXTRA='-audiodev
     none,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0'`.
   - Koniec przebiegu (`quit`) działa na gościa jak wyrwanie zasilania: F2FS
     cofa `/data` do ostatniego checkpointu, przetrwa tylko to, co
     zsynchronizowane. Czyste wyłączenie dają: `poweroff` wpisany na tty2,
     wyjście z gry albo `mon:system_powerdown` (przycisk zasilania). QEMU
     kończy się wtedy sam.
   - Długie wyniki: pierwsza komenda `exec >/dev/ttyS0 2>&1` kieruje wyjście
     kolejnych do logu seriala (tryb `direct`); zrzut tty2 mieści 25 linii.
   - Tryb `direct` bierze `bzImage` prosto z `../buildroot/output/images/`, a
     rootfs z `output/boot.vfat`, więc zmianę samego kernela da się sprawdzić
     bez `genimage`.
   - Techniki prób (klawisze i kliknięcia w grze, pliki na `/data` bez roota
     przez `sload.f2fs`, zastępczy sysfs, druga głowica przez D-Bus) opisuje
     skill `hardware-test-round`.
