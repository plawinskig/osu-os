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
przez `mdev` na podstawie realnie wykrytego sprzętu — jak w Live USB dystrybucji
typu Ubuntu/Arch. **Wyjątek:** cokolwiek co musi działać już wewnątrz initramfs,
zanim `switch_root` się wykona (np. USB storage, FAT32, klawiatura do awaryjnego
shella), musi być wbudowane na stałe w GŁÓWNYM kernelu — initramfs nie ma
mechanizmu ładowania modułów z zewnątrz siebie. Aktualnie wbudowane (`=y`) z tego
powodu: rdzeń USB (`USB`, xHCI/EHCI + ich `*_PCI`, `USB_STORAGE`, `USB_HID`,
`HID_GENERIC`), FAT/VFAT + NLS, squashfs (z `SQUASHFS_XZ`), loop, `F2FS_FS`
(partycja danych). Potwierdzone na ASUS FX503VM: SATA/AHCI i inne moduły
ładują się już po `switch_root` przez coldplug `mdev` (podejście B działa).

**Read-Only rootfs + trwała partycja danych.** `rootfs.squashfs` jest z natury
RO i kopiowany do RAM — odporny na nagłą utratę zasilania. Osobna partycja
**F2FS** (label `OSUKIOSK_DATA`) trzyma wyłącznie beatmapy, ustawienia i wyniki.
F2FS wybrany celowo — projektowany pod pamięci flash (log-structured, dobry
wear-leveling), pasuje pod wzorzec częstych małych zapisów (wynik po każdej
ukończonej mapie).

**Init: BusyBox init, nie systemd.** Płaski `/etc/inittab` main systemu żyje
w `board/osukiosk/rootfs-overlay/etc/inittab` (initramfs go nie używa — jego PID 1
to skrypt `initramfs-overlay/init`). Wpis `tty1::respawn:/usr/bin/osukiosk-session`
to nadzorca kiosku: init restartuje launcher przy każdym jego wyjściu. Uwaga: BusyBox
init **nie** kończy działania przy braku wpisów `respawn` (jego pętla główna to
`while (1)`); bez tego wpisu system po prostu wisi bez sesji. Inittab main systemu
montuje `devtmpfs` na `/dev` jako pierwszy wpis `sysinit`, bo `/dev` w squashfs
jest pustym katalogiem, a `switch_root` nie przenosi montowań z initramfs.

**Bootloader: syslinux/extlinux, MBR** (nie GRUB, nie na razie czysty
UEFI-GPT — działa w trybie Legacy/CSM).

**Grafika/audio (docelowo, jeszcze nie zaimplementowane):** brak DE,
`seatd` + Sway/Gamescope bezpośrednio na KMS/DRM, priorytet: minimalny input
lag i audio latency. Audio na start: sam ALSA + `snd-usb-audio`, bez PipeWire
(świadome uproszczenie edukacyjne, PipeWire to rozszerzenie na później).

## Decyzje techniczne — nie podważaj bez dobrego powodu

- **C library: glibc**, nie musl — osu!lazer to aplikacja .NET (Avalonia/Skia),
  ryzyko niestabilności natywnych bindingów na musl uznano za nieopłacalne.
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
  regeneruje z niego `.config` kernela. `CONFIG_INITRAMFS_SOURCE` wskazuje
  na `../output-initramfs/images/rootfs.cpio`, ale w samym `linux.config` jest to
  ścieżka bezwzględna, zależna od maszyny.
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
  Znane skutki: `/var/lib` niezapisywalny (patrz PROGRESS.md).
- Label partycji FAT32 **ograniczony do 11 znaków** (limit specyfikacji) —
  obecny label to `OSUBOOT`.
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
3. **Obraz:** skill `build-osukiosk-image`. Uwaga: `genimage` czyta pliki z
   `board/osukiosk/` (`--inputpath .`), więc `bzImage` i `rootfs.squashfs` kopiujemy
   tam (katalog `boot-files/` był nieużywany i zawierał tylko stare kopie —
   usunięty, nie odtwarzaj go). Krok
   `extlinux --install` wymaga `sudo` — uruchamia go autor.
4. **Test w QEMU przed pendrive'em** (`qemu-system-x86_64`, `snapshot=on` chroni
   obraz): boot bezpośredni `-kernel ../buildroot/output/images/bzImage -append
   "console=tty1 console=ttyS0 loglevel=7"` + `-device qemu-xhci -device
   usb-storage,drive=…` daje log na serialu; sesja na `tty1` widoczna przez
   `screendump` z monitora. Pełny boot przez syslinux: ten sam obraz bez `-kernel`,
   z `bootindex=0` na urządzeniu USB (cmdline z `extlinux.conf`). Ścieżka gniazda
   monitora musi być krótsza niż 108 B (użyj ścieżki względnej).
