# HISTORY.md

**Ten plik NIE jest wymaganą lekturą na każdej sesji** — `CLAUDE.md` go nie
wymusza. To jednorazowa, szczegółowa narracja: co robiliśmy, w jakiej
kolejności, co nie zadziałało i dlaczego, jakie poprawki naniesiono po drodze.
Czytaj go, gdy potrzebujesz zrozumieć *dlaczego* coś w projekcie wygląda tak,
a nie inaczej, a `git log` na to nie odpowiada (commity sprzed wprowadzenia
zasad z `CLAUDE.md` bywają lakoniczne). Nie aktualizuj tego pliku na bieżąco —
to zamknięty zapis przebiegu prac do pewnego momentu; nowe wydarzenia
dokumentuj przez dobrze opisane commity (patrz `CLAUDE.md`), a bieżący status
trzymaj w `PROGRESS.md`.

## Cel projektu

Budujemy dedykowany, minimalistyczny system operacyjny typu "kiosk" (x86_64, Buildroot),
którego jedynym zadaniem jest bootowanie z pendrive'a USB i uruchomienie gry **osu!lazer**
na dowolnym laptopie/PC zdolnym tę grę odpalić (nie pod jeden konkretny model sprzętu).

Autor projektu: student 3. roku informatyki, zna C++/Rust/Python, uczy się C, pracuje
w terminalu na Linux Mint. Preferuje głębokie wyjaśnienia "dlaczego", nie tylko gotowe
komendy. Rozmowa po polsku, kod/komentarze w plikach po angielsku.

### Kluczowe założenia architektoniczne

- **Uniwersalność sprzętowa ("Podejście B"):** kernel ma minimalny zestaw wbudowanych
  (`=y`) driverów fundamentalnych dla bootu, a sterowniki specyficzne dla konkretnego
  sprzętu (GPU, audio, storage, USB) są modułami (`=m`) ładowanymi dynamicznie przez
  `mdev` na podstawie realnie wykrytego sprzętu — dokładnie jak działają dystrybucje
  Live USB (Ubuntu Live, Arch ISO). **Świadomie odrzucony** został wariant "chirurgiczny"
  (kernel budowany pod jeden dokładny model laptopa) — to osobny projekt na przyszłość.
- **Boot w całości do RAM ("dwustopniowa rakieta"):** initramfs (mały loader) montuje
  partycję boot, kopiuje właściwy system (squashfs) do `tmpfs`, robi `switch_root`.
  Od tego momentu USB nie jest już wąskim gardłem transferu — cały main system działa
  z pamięci RAM.
- **Read-Only rootfs + trwała partycja danych:** główny system plików to squashfs
  (kompresowany, z natury RO), skopiowany do tmpfs — odporny na nagłą utratę zasilania.
  Osobna partycja **F2FS** (`OSUKIOSK_DATA`) trzyma wyłącznie beatmapy, ustawienia i
  wyniki — F2FS wybrany celowo jako filesystem projektowany pod pamięci flash
  (log-structured, dobry wear-leveling), odpowiedni pod częste małe zapisy (wynik po
  każdej ukończonej mapie).
- **Customowy, okrojony kernel** zoptymalizowany pod szybki boot — patrz sekcja
  "Stan configu kernela" niżej.
- **Brak DE.** Docelowo minimalny stack graficzny: `seatd` + Sway/Gamescope bezpośrednio
  na KMS/DRM (bez X jako pośrednika, jeśli się da) — priorytet to jak najniższy input
  lag i audio latency. **To jest Etap 5, jeszcze nie rozpoczęty.**
- **Init system:** BusyBox init (nie systemd) — świadomy wybór dla kiosku z jednym
  zadaniem, płaski `/etc/inittab`, pełna czytelność sekwencji bootu.

### Sprzęt referencyjny (developerski, NIE jedyny docelowy)

Laptop autora używany do developmentu/testów:
- CPU: Intel i5-1235U (12th Gen, Alder Lake-UP3)
- GPU: Intel Iris Xe (iGPU)
- Model: ThinkBook 16 G4+ IAP

Test fizyczny wykonywany też na: **ASUS FX503VM** (inny laptop — celowo, żeby
weryfikować uniwersalność sprzętową).

### Sprzęt/funkcje świadomie zaparkowane na później (NIE ruszać teraz)

- Sieć (Wi-Fi/Ethernet) — potrzebna docelowo do pobierania beatmap.
- Obsługa tabletów graficznych (OpenTabletDriver, HID Wacom/XP-Pen).
- NVIDIA proprietary driver.
- Natywny UEFI+GPT boot (obecnie używamy MBR + syslinux w trybie Legacy/CSM).
- Druga, "chirurgiczna" wersja systemu pod jeden konkretny laptop (statyczny kernel,
  bez modularności) — projekt na przyszłość, po dowiezieniu wersji uniwersalnej.

### Decyzje techniczne, które już zapadły i NIE powinny być podważane bez dobrego powodu

- **C library: glibc** (nie musl) — decyzja podjęta ze względu na osu!lazer jako
  aplikację .NET (Avalonia/Skia); ryzyko niestabilności natywnych bindingów na musl
  uznano za nieopłacalne względem oszczędności rozmiaru.
- **Init system: BusyBox init**, nie systemd.
- **/dev management: Dynamic using devtmpfs + mdev.**
- **Target Architecture Variant: generic x86-64** (celowo NIE wybrano konkretnego
  mikroarchitektury CPU jak "skylake"/"icelake" — złamałoby to uniwersalność).
- **Kompresja kernela: XZ** (do zweryfikowania czy faktycznie ustawione — patrz niżej).
- **Bootloader: syslinux/extlinux**, MBR (nie GRUB, nie na razie czysty UEFI-GPT).
- **Partycja BOOT: FAT32, label `OSUBOOT`** (nazwa skrócona z pierwotnego
  `OSUKIOSK_BOOT` — **13 znaków przekracza limit 11 znaków w FAT32**, stąd zmiana).
  UWAGA: label partycji danych to `OSUKIOSK_DATA` (11 znaków, mieści się — ale to
  akurat ext4/F2FS, gdzie ten limit nie obowiązuje w ten sam sposób; label pozostał
  bez zmian, tylko BOOT musiał być skrócony).

---

## Struktura repozytorium

```
osuos/
├── buildroot/                          # jedno drzewo źródłowe Buildroota
│   └── output-initramfs/               # OSOBNY katalog wyjściowy (O=) dla initramfs
│       └── build/linux-X.Y.Z/          # tu są źródła jądra initramfs (NIE linux-headers!)
├── osu-kiosk-external/                 # br2-external — cała nasza customizacja
│   ├── external.desc
│   ├── external.mk
│   ├── Config.in
│   ├── configs/
│   │   ├── osukiosk_main_defconfig         # Buildroot defconfig — main system (squashfs)
│   │   └── osukiosk_initramfs_defconfig    # Buildroot defconfig — initramfs (cpio)
│   └── board/osukiosk/
│       ├── linux.config                    # kernel defconfig — GŁÓWNY system
│       ├── rootfs-overlay/                 # pliki dokładane do MAIN systemu
│       │   ├── etc/inittab
│       │   ├── etc/init.d/S41mountdata
│       │   └── usr/bin/osukiosk-session
│       ├── initramfs-overlay/              # pliki dokładane do INITRAMFS
│       │   └── init                        # skrypt /init, PID 1 initramfs
│       ├── boot-files/                     # zawartość partycji BOOT przed genimage
│       │   ├── bzImage
│       │   ├── rootfs.squashfs
│       │   └── extlinux.conf
│       ├── genimage-osukiosk.cfg
│       └── data.img                        # surowy obraz F2FS partycji DATA (4GB)
```

**WAŻNA POPRAWKA WZGLĘDEM WCZEŚNIEJSZYCH INSTRUKCJI:** ścieżki `BR2_ROOTFS_OVERLAY`
w konfiguracji Buildroota muszą być podawane jako `../osu-kiosk-external/board/osukiosk/...`
(relatywnie do katalogu `buildroot/`, skąd odpalany jest `make`), NIE jako
`board/osukiosk/...` — ta druga forma powoduje, że Buildroot szuka overlayu wewnątrz
własnego drzewa i rzuca błędem.

---

## Co jest już zrobione i DZIAŁA (zweryfikowane na fizycznym sprzęcie)

### Etap 1 — Toolchain i kernel (main system)
- Buildroot: checkout na stabilnym tagu `2026.05.2` (świadomie pominięto `2026.08-rc`).
- Toolchain: `x86_64`, `glibc`, architektura generyczna (nie skylake/icelake).
- Kernel main systemu: wersja 6.18.48, budowany od `x86_64_defconfig` jako bazy,
  następnie mocno odchudzony w dwóch rundach code-review (patrz sekcja niżej —
  **stan configu kernela**).
- Zapisany jako `board/osukiosk/linux.config` (przez `make linux-savedefconfig`).

### Etap 2 — Dwuetapowa architektura rootfs
- **Initramfs** budowany jako **osobna konfiguracja Buildroota** w osobnym katalogu
  wyjściowym: `make O=../output-initramfs BR2_EXTERNAL=../osu-kiosk-external ...`
  — to ten sam Buildroot, inny `.config`/`defconfig`.
  - Toolchain initramfs: **glibc, linkowanie "shared only"** (NIE "static only" —
    Buildroot to zablokował ze względu na mechanizm NSS w glibc, który wymaga
    dynamicznie doładowywanych modułów `libnss_*.so` nawet w binarkach pozornie
    statycznych; to nie do obejścia bez zmiany libc na musl). Buildroot poprawnie
    spakował `ld-linux.so`+`libc.so` do `.cpio`.
  - Target packages: tylko BusyBox, nic więcej.
  - Filesystem: `cpio` + gzip (nie XZ — priorytet to szybkość dekompresji w bardzo
    wczesnej fazie bootu, nie rozmiar).
  - Wynikowy `rootfs.cpio`: **5.4 MB**.
- Skrypt `board/osukiosk/initramfs-overlay/init` (PID 1 initramfsu) — **ZOSTAŁ
  ZMODYFIKOWANY względem pierwotnej wersji, patrz sekcja "Bieżący problem" niżej.**
  Pierwotna wersja montowała partycję BOOT po etykiecie (`mount -L OSUBOOT`), ale
  to podejście napotkało blocker opisany niżej.
- Kernel main systemu wchłania gotowy `rootfs.cpio` initramfsu przez
  `CONFIG_INITRAMFS_SOURCE` (bezwzględna ścieżka do `../output-initramfs/images/rootfs.cpio`).
  **Kolejność budowania jest istotna:** najpierw pełny build `output-initramfs`,
  dopiero potem `make linux-rebuild` w głównym drzewie, żeby wchłonął świeży `.cpio`.

### Etap 3 — Fizyczny layout pendrive'a
- Partycjonowanie: **MBR** (nie GPT), boot w trybie Legacy/CSM.
- Partycja 1: `OSUBOOT`, FAT32, 256MB, bootable, zawiera `bzImage`, `rootfs.squashfs`,
  pliki syslinux/extlinux.
- Partycja 2: `OSUKIOSK_DATA`, F2FS, 4GB (rozmiar do dostosowania), zbudowana jako
  osobny raw image (`data.img`) przez `mkfs.f2fs -l OSUKIOSK_DATA data.img`, bo
  `genimage` nie generuje F2FS natywnie — jest tylko wstawiany jako gotowy plik.
- `genimage-osukiosk.cfg` składa całość w jeden `osukiosk.img`.
- **Trzy poprawki naniesione względem pierwotnych instrukcji (WAŻNE dla Claude Code,
  żeby nie powielić tych samych błędów):**
  1. Pliki źródłowe dla `genimage` (`bzImage` itd.) muszą fizycznie leżeć w
     `inputpath` wskazanym przy wywołaniu `genimage` (czyli w `board/osukiosk/boot-files/`)
     — trzeba je tam skopiować PRZED odpaleniem `genimage`, inaczej `stat() failed`.
  2. Label FAT32 ograniczony do 11 znaków — stąd `OSUBOOT`, nie `OSUKIOSK_BOOT`.
  3. Instalacja `extlinux --install` **musi być wykonana na finalnym, złożonym
     `osukiosk.img`**, nie na pośrednim pliku `boot.vfat` sprzed spakowania przez
     `genimage` (ten pośredni plik i tak trafia "do środka" `.img` i modyfikacja go
     osobno się nie propaguje). Poprawna procedura:
     ```bash
     sudo losetup -fP output/osukiosk.img   # np. zwróci /dev/loopX
     sudo mount /dev/loopXp1 /mnt
     sudo extlinux --install /mnt
     sudo umount /mnt
     sudo losetup -d /dev/loopX
     ```
  4. MBR bootstrap syslinux wgrywany osobno:
     `dd if=/usr/lib/syslinux/mbr/mbr.bin of=output/osukiosk.img bs=440 count=1 conv=notrunc`
- **Wynik: obraz bootuje się poprawnie na fizycznym ASUS FX503VM.** Bootloader
  wstaje, initramfs poprawnie wykonuje `switch_root`. To zweryfikowany, działający
  fundament.

### Etap 4 — Init głównego systemu (przygotowane, NIE jeszcze przetestowane end-to-end
z powodu blockera z Etapu 3/4 — patrz niżej)
- `rootfs-overlay/etc/inittab` — zawiera wpis `respawn` na `tty1` wołający
  `/usr/bin/osukiosk-session` (KRYTYCZNE dla stabilności: BusyBox init bez żadnego
  wpisu `respawn` kończy działanie po jednorazowym przejściu tabeli, co zabija PID 1
  i powoduje `kernel panic - not syncing: Attempted to kill init!` — to dokładnie
  ten błąd, który wystąpił przy pierwszym teście przed dodaniem `inittab`).
- `rootfs-overlay/etc/init.d/S41mountdata` — montuje partycję DATA po etykiecie
  (`mount -L OSUKIOSK_DATA`), numer `41` celowo umieszcza ten skrypt PO
  standardowych skryptach Buildroota inicjalizujących `/dev`/`mdev` w main systemie
  (main system ma OSOBNY, świeży `/dev` po `switch_root` — trzeba tam ponownie
  odpalić `mdev`, to się dzieje automatycznie przez domyślne skrypty Buildroota
  wcześniej w kolejności `S*`). Błąd montowania NIE zatrzymuje bootu (świadoma
  decyzja: brak persystencji to gorszy, ale akceptowalny stan, niż odmowa startu).
- `rootfs-overlay/usr/bin/osukiosk-session` — obecnie **placeholder diagnostyczny**:
  wypisuje PID, status mounta `/data`, śpi 10s, kończy się — ma za zadanie
  udowodnić, że mechanizm `respawn` działa (proces powinien się uruchamiać w pętli
  z rosnącym PID), zanim dołożymy prawdziwy Sway/Gamescope w Etapie 5.

---

## BIEŻĄCY BLOCKER — to jest pierwsze zadanie dla Claude Code

### Symptom
Na fizycznym sprzęcie (ASUS FX503VM) skrypt `/init` initramfsu **nie znajduje
pendrive'a** i system spada do awaryjnego shella BusyBoksa (`~ # _`). Dodatkowo
**klawiatura w tym shellu nie działa** — nie da się nawet zdiagnozować sytuacji
interaktywnie.

### Diagnoza (potwierdzona przez autora)
Kernel initramfsu (ten w `output-initramfs`, ODDZIELNY od głównego kernela — pamiętaj,
że initramfs ma swój własny build Buildroota) ma następujące podsystemy skompilowane
jako **moduły `=m`**, zamiast wbudowane `=y`:
- Obsługa USB Mass Storage, XHCI/EHCI (kontrolery USB)
- System plików FAT/VFAT + tablice kodowań (NLS)
- USB HID / klawiatura

To jest fundamentalny problem architektoniczny: **initramfs nie ma jeszcze
załadowanego żadnego systemu, z którego mógłby wziąć moduły `.ko`** — moduły w
Buildroocie lądują w rootfs głównego systemu (albo osobno w `/lib/modules/`
initramfsu, jeśli explicite je tam spakowano, co nie miało miejsca). Efekt: kernel
initramfsu dosłownie nie widzi USB ani FAT32, bo driverów tych funkcji nigdzie
nie ma wbudowanych na stałe — stąd "ślepy i głuchy" initramfs.

**Dodatkowy, drugorzędny problem:** pierwotny skrypt `/init` montował partycję
po etykiecie (`mount -L OSUBOOT`), ale **odchudzony `mount` z BusyBoksa w
initramfs NIE wspiera flagi `-L`** (to inne ograniczenie niż brak driverów —
dotyczy samego narzędzia userspace, nie kernela). Autor już to zaadresował,
przepisując `/init` tak, by iterował po `/dev/sd*` i `/dev/nvme*` zamiast polegać
na etykiecie — ta zmiana jest już w skrypcie, ale nie rozwiązuje głównego problemu
(braku driverów), bo iterowanie po `/dev/sd*` nic nie da, skoro te węzły w ogóle
się nie pojawią bez załadowanych driverów USB/storage.

### Nieudana próba naprawy
Autor próbował zautomatyzować zmianę configu kernela initramfsu skryptem bash
korzystającym z `scripts/config`, ale skrypt błędnie namierzył katalog źródłowy —
trafił w paczkę `linux-headers` zamiast we właściwy katalog build z pełnymi
źródłami jądra (`buildroot/output-initramfs/build/linux-X.Y.Z/`).

### Zadanie do wykonania (ROZSTRZYGNIĘTE — flagi idą do GŁÓWNEGO kernela, nie initramfsu)

**Rozstrzygnięcie architektoniczne:** initramfs (kernel budowany w `output-initramfs`)
sam w sobie **nie generuje bootowalnego `bzImage` używanego na pendrive** — jego
jedynym produktem końcowym jest `rootfs.cpio`. To **GŁÓWNY kernel** (ten z
`board/osukiosk/linux.config`, budowany w standardowym `buildroot/output/`)
wchłania ten `rootfs.cpio` przez `CONFIG_INITRAMFS_SOURCE`, trafia jako `bzImage`
na partycję `OSUBOOT`, faktycznie ładuje się na sprzęcie i **to on** wykonuje
`/init` jako PID 1. Zmiana configu kernela `output-initramfs` była więc ślepym
torem — te moduły nigdy nie miały prawa wpłynąć na to, co widzi initramfs
w praktyce. Poprzednia próba ze skryptem bash trafiającym w `linux-headers`
zamiast właściwych źródeł była błędem w tym samym duchu (zła lokalizacja), ale
nawet przy poprawnej lokalizacji wewnątrz `output-initramfs` efekt końcowy by
nie zadziałał — to nie ten kernel się bootuje.

**Krok 1 — zmiana configu GŁÓWNEGO kernela.** Otwórz konfigurację kernela main
systemu (`make linux-menuconfig` w standardowym drzewie `buildroot/`, bez `O=`,
lub bezpośrednio przez `scripts/config` w katalogu
`buildroot/output/build/linux-X.Y.Z/` — **NIE** `linux-headers-*`) i ustaw z `m`
na `y` (wbudowane na stałe) następujące flagi:
```
CONFIG_USB_HID
CONFIG_HID_GENERIC
CONFIG_I2C_HID_ACPI
CONFIG_USB_XHCI_HCD
CONFIG_USB_EHCI_HCD
CONFIG_USB_STORAGE
CONFIG_FAT_FS
CONFIG_VFAT_FS
CONFIG_NLS_CODEPAGE_437
CONFIG_NLS_ISO8859_1
CONFIG_INPUT_KEYBOARD
CONFIG_KEYBOARD_ATKBD
```
Po ręcznej zmianie przez `scripts/config --enable <FLAG>` odpal `make olddefconfig`
z poziomu katalogu źródeł jądra (albo `make linux-menuconfig` i po prostu zapisz
wyjście z TUI, co też wymusza rozwiązanie zależności) — Kconfig doliczy wymuszone
zależności tych flag (np. `USB_HID` może pociągać za sobą inne opcje `HID_*`).
Uwaga terminologiczna: `make linux-update-defconfig` **nie jest** poprawną komendą
Buildroota — właściwe narzędzia to `make linux-menuconfig` (interaktywnie) albo
`olddefconfig` po ręcznej edycji `scripts/config`, a do zapisania wyniku z powrotem
do repo projektu: `make linux-savedefconfig` + skopiowanie do `board/osukiosk/linux.config`.

**Krok 2 — przebudowa GŁÓWNEGO systemu:**
```bash
make
```
(zwykłe, pełne `make` w katalogu `buildroot/`, bez `O=`). Ponieważ initramfs
(`rootfs.cpio`) się nie zmienił, Buildroot powinien go ponownie wchłonąć bez
przebudowy tej części — zmieniamy tylko config głównego kernela, więc przebuduje
się on i wygeneruje nowy `bzImage` w `buildroot/output/images/`. **To jest ten
plik**, który trzeba skopiować do `boot-files/` w Kroku 3.

**Krok 3 — złożenie obrazu.** Użyj istniejących plików/procedury z
`osu-kiosk-external/board/osukiosk/`: skopiuj nowy `bzImage` z
`buildroot/output/images/bzImage` (GŁÓWNY build, nie `output-initramfs`) do
`boot-files/`,
uruchom `genimage` z `genimage-osukiosk.cfg`, wgraj MBR (`dd`), zainstaluj VBR
syslinuxa przez `losetup`+`extlinux --install` na finalnym `.img` (dokładna
procedura opisana w sekcji Etap 3 wyżej — trzymaj się jej, unikniesz powtórki
błędów już raz napotkanych).

**Krok 4 — przekazanie do testu.** Gdy obraz gotowy, podaj dokładną komendę
`dd` do wypalenia na pendrive (z przypomnieniem o weryfikacji `/dev/sdX` przez
`lsblk` PRZED wykonaniem — nadpisanie złego dysku jest nieodwracalne). Autor
przetestuje na ASUS FX503VM. Jeśli zobaczy działającą w pętli `osukiosk-session`
(rosnący PID, komunikat o statusie mounta `/data`) zamiast panica/awaryjnego
shella — blocker jest zamknięty.

---

## Co dalej po odblokowaniu (Etap 5 — jeszcze nierozpoczęty)

Po potwierdzeniu stabilnego bootu z działającą pętlą `respawn`, kolejny krok to
zbudowanie właściwego stacku graficznego w miejsce placeholdera
`osukiosk-session`:
- `seatd` (zamiast pełnego `logind`) do zarządzania dostępem do urządzeń wejścia/GPU.
- Sway lub Gamescope bezpośrednio na KMS/DRM (bez X, jeśli się uda) — priorytet:
  minimalny input lag.
- Audio: na start sam ALSA + `snd-usb-audio` (kernel-side, klasa USB Audio 1/2,
  plug-and-play) — bez PipeWire na razie (uproszczenie zaakceptowane przez autora
  dla celów edukacyjnych), pełny PipeWire routing to rozszerzenie na później.
- Docelowo: dociągnięcie/spakowanie runtime .NET dla osu!lazer (Avalonia) —
  największy pojedynczy konsument miejsca w rootfs, jeszcze nietknięty temat.
- Pomiar realnego czasu bootu (`dmesg` timestampy) i identyfikacja wąskich gardeł
  z twardymi danymi, zamiast dalszego "strzelania" przy odchudzaniu configu kernela.

---

## Stan configu kernela (main system) — po dwóch rundach code-review

Kernel main systemu (`board/osukiosk/linux.config`) przeszedł dwie rundy
odchudzania względem bazowego `x86_64_defconfig`. Usunięto m.in.: cały stack
VM guest (virtio/hypervisor), pełny netfilter/routing/NAT stack, SELinux jako
aktywny moduł, NFS/sieciowy root, nadmiarowe cgroups (VM/kontenery), legacy
PCMCIA/AGP/PATA, accounting/profiling (audit, kprobes, NUMA — jeden socket CPU
nie potrzebuje NUMA), PTP, hotplug PCI, legacy storage (ISO9660/CD-ROM, device-mapper,
software RAID, quota/autofs), HID quirki pod tablety/joysticki/gamepady
(świadomie zaparkowane). Włączono jawnie `CONFIG_RTC_HCTOSYS=y` (bez tego zegar
systemowy nie synchronizuje się z RTC płyty głównej — krytyczne dla poprawnych
timestampów zapisywanych wyników w `/data`). Kompresja kernela: **do zweryfikowania
czy `CONFIG_KERNEL_XZ=y` faktycznie jest ustawione** — przy ostatnim review nie było
pewności, czy to się zapisało poprawnie (symbol mógł zniknąć z `savedefconfig` jako
równy wartości domyślnej). Warto to sprawdzić przy okazji prac nad blockerem.

Decyzja: kernel main systemu NIE jest jeszcze "idealnie" odchudzony (świadomie
zatrzymano dalsze cięcia — malejące korzyści, rosnące ryzyko debugowania
niejasnych błędów). Dalsze cięcia zaplanowane dopiero po pomiarach realnego czasu
bootu w Etapie 5.

---

## Styl pracy oczekiwany przez autora

- Wyjaśniaj mechanizmy i "dlaczego", nie tylko podawaj komendy do przeklejenia
  (choć na etapie Claude Code z bezpośrednim dostępem do maszyny, priorytet
  przesuwa się bardziej w stronę realnego wykonania zadań — zachowaj jednak
  zwięzłe wyjaśnienia decyzji technicznych po drodze).
- Autor jest świadomym, technicznym rozmówcą — już kilkukrotnie samodzielnie
  wyłapał i poprawił błędy w instrukcjach (ścieżki overlayów, limit nazwy FAT32,
  kolejność `extlinux --install` względem `genimage`) — traktuj go jako
  kompetentnego partnera, nie osobę wymagającą upraszczania.
- Zawsze przypominaj o weryfikacji `/dev/sdX` przed każdą komendą `dd` na
  fizyczny nośnik — nieodwracalna operacja.
