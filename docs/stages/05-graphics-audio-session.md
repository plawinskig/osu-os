# Etap 5 — grafika, audio i docelowa sesja kiosku

Status: ✅ zamknięty 6.11.2026
Zakres commitów: `c146c74`..`7f276db` (22.09–6.11.2026, `main`)
Sprzęt: QEMU, ASUS FX503VM (tylko krok B), Lenovo IdeaPad Z570 (od 24.10)

## Cel

Minimalny stack graficzny bez DE na KMS/DRM i audio na ALSA, z priorytetem
na niski input lag, oraz docelowa sesja kiosku, w której zmieści się gra.
Plan z 22.09 (`c146c74`): kroki A–E, każdy z własną bramką.

## Decyzje

- **Kompozytor `cage`, nie Sway** (`014d046`, 22.09). W Buildroocie
  2026.05.2 `BR2_PACKAGE_SWAY` wymaga `BR2_PACKAGE_SYSTEMD`, a ten systemd
  jako PID 1, co koliduje z BusyBox init. `cage` (wlroots) nie zależy od
  systemd i lepiej pasuje do jednej aplikacji pełnoekranowej. Ostatecznie
  potwierdzony pomiarem w kroku D. Gamescope odpada: brak pakietu w
  Buildroocie i wymóg Vulkana, którego HD 3000 (Gen6) w Mesie nie ma.
- **`eudev`, nie `mdev`** (`014d046`). wlroots wymaga `BR2_PACKAGE_HAS_UDEV`,
  a bez systemd spełnia to tylko eudev. Coldplug modułów działa tym samym
  mechanizmem modalias + kmod.
- **Sesja jako konto `kiosk`, nie root** (`c146c74`, `0c4d0d0`). Najmniejsze
  uprawnienia, `seatd` ma sens tylko dla klienta bez roota, a przyszła sieć
  oznacza parsowanie nieufnych beatmap. uid/gid 900 przypięte na stałe (pliki
  na `/data`), grupy `video` (gniazdo `seatd` z `S70seatd -g video`) i `audio`.
- **Root zablokowany** (`2e6db79`, 24.10). Przy pustym haśle i
  `/bin/busybox` z bitem setuid `su` z sesji `kiosk` dawało roota bez hasła.
- **Sprzęt testowy Z570 zamiast ASUS-a** (24.10). ASUS FX503VM nie pokazuje
  iGPU Intela na PCI (tylko NVIDIA, UEFI bez przełącznika grafiki), a
  nouveau i sterownik NVIDIA świadomie odrzucono.
- **`cage` zostaje bez zmian** (decyzja autora 5.11, krok D).
- **Domyślny governor `performance`** (`2154026`, 6.11). Zmieniony w Etapie 6.

## Co zrobiono

### Krok A — `seatd` i konto `kiosk` (22.09) — ✅ QEMU

- `0c4d0d0`: `BR2_PACKAGE_SEATD`, `BR2_PACKAGE_SEATD_DAEMON`; pakiet sam
  instaluje `S70seatd`, więc bez własnego skryptu. `users-table.txt` z kontem
  `kiosk`. `S41mountdata` robi nierekurencyjne `chown kiosk:kiosk` i
  `chmod 0700` na `/data`.
- Bramka w QEMU: `seatd` żyje, `/run/seatd.sock` z grupą `video`, `kiosk` ma
  zapis, `/data` to `kiosk:kiosk 0700`.

### Krok B — minimalna sesja `cage` (22.09–24.10) — ✅ Z570 24.10

- `014d046`: `cage`, eudev, Mesa z `iris` (wymaga `MESA3D_LLVM`),
  `BR2_TOOLCHAIN_BUILDROOT_CXX`. Sesja: `XDG_RUNTIME_DIR=/run/user/900`,
  `su` do `kiosk`, `exec cage`.
- `cdf027c`: pierwszy skrypt QEMU (`run-qemu-smoketest.sh`).
- `1c12bd8` (24.10): `crocus` obok `iris`, `foot` zamiast `swaybg`,
  DejaVu Mono, `xkeyboard-config`, locale `C.UTF-8`, alsa-utils, tymczasowy
  pakiet diagnostyczny (niżej).
- `f638b2b`: zawsze widoczny prompt `boot:` (3 s).
- `c0fc037`, `4226078`: `board/osukiosk/qemu-test.sh` z trybami `direct` i
  `syslinux` (komendy na tty2 przez `sendkey`, zrzuty PNG), zamiast
  smoke testu, który pisał prosto do `data.img`.
- `2d209f6`: `CLAUDE.md` po zmianach (cage, eudev, uzasadnienie glibc,
  pułapka `make defconfig`).
- Bramka na Z570: prompt w `foot`, stabilny PID `cage`, w logu
  `EGL driver name: crocus`, `Mesa Intel(R) HD Graphics 3000 (SNB GT2)`,
  `LVDS-1: Modesetting with 1366x768 @ 60.042 Hz`.

### Krok C — ALSA i kodeki HDA (24.10) — ✅ Z570 24.10

- `1c12bd8`: w kernelu był `snd-hda-intel`, ale żaden sterownik kodeka, więc
  na żadnej maszynie nie było urządzenia PCM. Dodane jako moduły: Realtek
  (Z570: ALC272 → `snd-hda-codec-alc662`), HDMI, Conexant.
- Wynik: `autoconfig for ALC272`, HDMI `pcm=3`, `speaker-test` słyszalny z
  sesji `kiosk`. USB audio niepotwierdzone na sprzęcie.

### Krok D — pomiar input lag `cage` (4–5.11) — ✅ Z570, `cage` zostaje

- `def9296`: kroki `mon:<komenda>` w `qemu-test.sh` (pojedyncze klawisze,
  przyciski myszy, zrzuty).
- `c56de3d`: pakiet `latency-probe` (pierwszy pakiet tego br2-external,
  `src/` + `package/`, `_SITE_METHOD = local`): klient `wl_shm` przełączający
  ekran czarny/biały i mierzący czas od zdarzenia w kernelu do
  `wp_presentation`; tryby `idle`, `mailbox` (gra bez vsync), `vsync`;
  odniesienie bez kompozytora `latency-probe-vt` (DECSCNM na tty2).
- `dbc9db9`: wyniki i decyzja w `PROGRESS.md` (pełny opis metody:
  `git show dbc9db9:PROGRESS.md`).
- Warunki: LVDS 60,042 Hz, `performance` 2,2 GHz, klawiatura PS/2, mysz
  SteelSeries Rival 110 (1 kHz), N = 30 na przebieg.
- Programowo, kernel → prezentacja, mediana (runda 1 / runda 2):
  `idle` 12,4 / 10,7 ms, `mailbox` 25,3 / 27,4 ms, `vsync` 43,4 / 41,9 ms.
  Zgodne z modelem: `cage` renderuje tuż po vblanku, więc gotowa klatka
  czeka jedno odświeżenie; rozrzut to sama faza 60 Hz, bez jittera `cage`.
  `schedutil` i mysz nic nie zmieniają.
- Kamera (Pixel 10, 239,69 kl./s, stuknięcia długopisem), od dobicia
  klawisza do zmiany obrazu, mediana: konsola 27 ms, `idle` 45, `mailbox` 55,
  `vsync` 71 ms. Klawiatura laptopa ok. 15–18 ms ±6 ms: największy rozrzut w
  łańcuchu, niezależny od kompozytora. Panel nie dokłada opóźnienia.
- Decyzja: 55 ms bez vsync jest akceptowalne. Łatka `cage` (render przed
  vblankiem, ok. −14 ms) nie usunęłaby rozrzutu klawiatury.

### Krok E — docelowa sesja (6.11) — ✅ Z570 6.11

- `2154026`: domyślny governor `performance`. Z `userspace` CPU bez HWP
  stały na minimum (Z570: 800 MHz zamiast 2,2 GHz).
- `24ef23d`: finalny `osukiosk-session`: `HOME=/data/home` (działa cache
  shaderów Mesy), fallback na tmpfs bez `/data`, ograniczone logi
  (`session.log`, `session.log.1`, zrzut `dmesg`, `sync`), `chvt 1`,
  `osukiosk-game` jako jedyny klient `cage` (na razie `foot`).
  `osukiosk-debug-shell` na tty2 tylko z `osukiosk.debug`/`osukiosk.hold`.
  Etykiety `debug` i `hold` w `extlinux.conf`, `quiet` z powrotem, prompt 1 s.
- `9be8bf9`: mikser: reguła udev `90-alsa-restore.rules` i `S42alsa`, stan w
  `/data/alsa/asound.state` zapisywany przy czystym wyłączeniu, `--no-ucm`.
- `45cd9fd`: ziarno `seedrng` w `/run/seedrng`.
- `6f63746`: `latency-probe` poza defconfigiem (pakiet zostaje w drzewie).
- `6523974`: `qemu-test.sh` zna etykiety debug, `NO_DATA=1`.
- `7f276db`: zamknięcie etapu w `PROGRESS.md` i `CLAUDE.md`.

## Tymczasowy pakiet diagnostyczny (24.10–6.11)

Z570 nie ma konsoli szeregowej ani sieci, więc na czas kroków B–D:
`tty2::askfirst` z shellem roota, `cage -s`, logi `cage` i `dmesg` na
`/data/log`, prompt `boot:` 3 s, parametr `osukiosk.hold` (bez `cage`, bo
`seatd` przypina nowego klienta do aktywnego VT i pętla crashy przejmowała
tty2). W kroku E zastąpiony trybami `debug` i `hold`.

## Co nie zadziałało

- **Sway** wymaga systemd (wyżej).
- **Bez C++ w toolchainie** Kconfig po cichu wyciął całą gałąź graficzną
  (`BR2_INSTALL_LIBSTDCPP` niewidoczny), bez błędu. Toolchain trzeba było
  przebudować ręcznie (`host-gcc-final-dirclean`, `gcc-final-dirclean`).
- **Stare pliki w `output/target/`:** po przejściu na eudev został
  `S10mdev`, po zamianie klienta `swaybg`. Buildroot nie usuwa plików
  wyłączonych pakietów; trzeba je usuwać ręcznie.
- **ASUS FX503VM bez iGPU:** `cage` dochodził do próby KMS i kończył się
  („Found 0 GPUs” było też w QEMU, bo kernel nie miał virtio-gpu).
- **Tylko `iris`:** loader Mesy mapuje HD 3000 na `crocus`; bez niego
  renderer GLES2 wlroots nie startuje. Znalezione przed testem na Z570.
  Zmiana listy sterowników wymaga `mesa3d-reconfigure`.
- **Pierwszy boot na Z570: pętla `respawn` przez `swaybg`.** `cage`
  implementuje tylko `xdg-shell`, a `swaybg` potrzebuje layer-shell, więc
  kończył się i zabierał ze sobą `cage`. Zastąpiony przez `foot`.
- **Bez keymapy `cage` ignoruje klawiaturę** (także przełączanie VT):
  dodany `xkeyboard-config`. Bez locale UTF-8 `foot` pokazywał błąd.
- **Prompt `boot:` z `PROMPT 0`** pojawia się tylko z Shiftem, który na Z570
  nie działał: `PROMPT 1`.
- **F2FS po twardym `quit` w QEMU** wrócił do ostatniego checkpointu i
  zgubił logi sesji. Stąd `sync` w sesji i wyłączanie przez `poweroff`.
- **`poweroff` w `foot`** dawał „Operation not permitted” (wpisany jako
  `kiosk`); działa z tty2.
- **`make defconfig` bez `BR2_DEFCONFIG`** wygenerował `.config` z samych
  wartości domyślnych Buildroota. Właściwe: `make osukiosk_main_defconfig`.

## Wyniki i weryfikacja

- Runda kontrolna kroku E na Z570 (6.11), `step-e.sh`: boot 1 `check` same
  OK (governor `performance` ok. 2195 MHz, `HOME` na `/data/home`, cache
  Mesy, `crocus`, `cage` bez `-s`), Ctrl+Alt+F2 nic nie robi, `exit` w `foot`
  daje nową sesję po ok. 2 s; boot 2 `debug`: Master −20 → −12 dB, `poweroff`
  zapisał stan; boot 3: −12 dB odtworzone z `/data`.
- Pomiary i narzędzia: `../measurements/stage5-step-d/` (sonda, nagrania,
  analiza), `../measurements/stage5-step-e/` (`step-e.sh`, `upload-round.sh`,
  `copy-logs.sh`, szablony QEMU).
- Zrzuty: `../screenshots/2026-10-24-qemu-verify/` (kroki B i C),
  `../screenshots/2026-11-04-stage5-step-d/`,
  `../screenshots/2026-11-06-stage5-step-e/` (QEMU i zdjęcia z Z570).

## Co zostało / przeniesione dalej

Do Etapu 6: nagłówki toolchaina 7.0 przy kernelu 6.18, `performance` czy
`schedutil` z grą, czyste wyłączanie bez shella (wyjście z gry, `acpid`),
`cage -m extend` przy dwóch monitorach, rosnący `session.log`, brak tabeli
compose (`/usr/share/X11/locale`), LLVM/Clang w targecie (ok. 208 MB),
partycja boot FAT16. Wszystkie poza compose zamknięto w Etapie 6.

## Gdzie trafiły trwałe ustalenia

- `CLAUDE.md`: akapit „Grafika/audio”, łańcuch sesji i tryb `debug`/`hold`
  w „Init”, pułapki workflow (C++, stare pliki, `make defconfig`,
  `-reconfigure`, savedefconfig + `git diff`), QEMU.
- skill `hardware-test-round` (powstał w `f19581b`, Etap 6) uogólnia
  procedurę rund z kroków D i E.

## Źródło

Treść commitów `c146c74`..`7f276db`, `PROGRESS.md` z `c146c74`, `0c4d0d0`,
`014d046`, `1c12bd8`, `c0fc037`, `dbc9db9`, `7f276db`, README w
`../measurements/stage5-*` i `../screenshots/2026-1*-stage5-*`.
