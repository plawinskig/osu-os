# Etap 1 — toolchain i kernel main systemu

Status: ✅ zamknięty (wrzesień 2026, przed 9.09)
Zakres commitów: `3bc3886`..`776316d` (4–6.09.2026, `main`)

## Cel

Toolchain Buildroota i odchudzony kernel x86_64 pod uniwersalny kiosk
bootowany z pendrive'a: sterowniki fundamentalne dla bootu wbudowane,
sterowniki konkretnego sprzętu jako moduły („Podejście B”, jak w
dystrybucjach Live USB).

## Co zrobiono

- `3bc3886` (4.09): szkielet br2-external `osu-kiosk-external/`.
- `e696f98`, `19d9bc7` (4.09): bazowy modularny config kernela x86_64, potem
  odchudzony i utwardzony.
- `776316d` (6.09): `configs/osukiosk_main_defconfig`.
- Buildroot: stabilny tag `2026.05.2` (świadomie pominięty `2026.08-rc`).
- Toolchain: x86_64, glibc, wariant generic x86-64.
- Kernel 6.18.48, start od `x86_64_defconfig`, dwie rundy przeglądu. Usunięto
  m.in.: stack gościa VM (virtio, hypervisor), netfilter, routing i NAT,
  SELinux jako aktywny moduł, NFS i root sieciowy, nadmiarowe cgroups,
  PCMCIA, AGP, PATA, audit, kprobes, NUMA, PTP, hotplug PCI, ISO9660,
  device-mapper, software RAID, quota, autofs, quirki HID tabletów i
  gamepadów. Jawnie włączony `CONFIG_RTC_HCTOSYS=y` (zegar z RTC, potrzebny
  do poprawnych dat wyników na `/data`).

## Decyzje

- **glibc, nie musl.** osu!lazer to aplikacja .NET z natywnymi bibliotekami
  budowanymi pod glibc (m.in. własnościowy BASS). Pierwotne uzasadnienie
  („Avalonia/Skia”) było błędne; poprawione 24.10.2026 w `2d209f6`
  (osu-framework na SDL + BASS).
- **Generic x86-64**, nie konkretna mikroarchitektura: inaczej obraz nie
  ruszy na starszych CPU.
- **BusyBox init, nie systemd:** kiosk z jednym zadaniem, płaski
  `inittab`, czytelna sekwencja bootu. Ta decyzja wymusiła później `cage`
  zamiast Sway (Etap 5).
- **Dalsze cięcie kernela wstrzymane:** malejące korzyści, rosnące ryzyko
  trudnych błędów. Kolejne zmiany tylko na podstawie pomiarów bootu.
- Świadomie zaparkowane: sieć, tablety graficzne, sterownik NVIDIA,
  natywny UEFI+GPT, wersja „chirurgiczna” pod jeden laptop.

## Co nie zadziałało / zastrzeżenia

- **Plik `board/osukiosk/linux.config` w repo nie odpowiadał budowanemu
  kernelowi.** Odchudzony config żył tylko w drzewie builda, a defconfig
  używał configu z drzewa kernela. Naprawione w Etapie 4 (`a460ceb`,
  21.09): savedefconfig realnego configu i
  `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG`.
- `CONFIG_KERNEL_XZ` (kompresja kernela): w czasie przeglądu nie było
  pewności, czy się zapisał. **Sprawdzone 19.11.2026:** nie zapisał się.
  `board/osukiosk/linux.config` nie ma żadnej opcji `CONFIG_KERNEL_*`, a
  efektywny `../buildroot/output/build/linux-6.18.48/.config` ma
  `CONFIG_KERNEL_GZIP=y` i `# CONFIG_KERNEL_XZ is not set`. Kernel jest więc
  od początku kompresowany gzipem. Decyzja „XZ” z `HISTORY.md` nigdy nie
  weszła w życie; czy wracać do niej (mniejszy `bzImage`, wolniejsza
  dekompresja), to pytanie do pomiarów bootu.

## Wyniki i weryfikacja

- Brak osobnej weryfikacji na sprzęcie w tym etapie. Pełny łańcuch bootu
  potwierdzono dopiero w Etapie 4 (ASUS FX503VM, 21.09.2026).

## Gdzie trafiły trwałe ustalenia

- `CLAUDE.md`: „Decyzje techniczne — nie podważaj bez dobrego powodu”
  (glibc, generic x86-64), „Zaparkowane na później”.

## Źródło

`HISTORY.md` (sekcje „Etap 1” i „Stan configu kernela”) i tytuły commitów
(bez treści). Lista usuniętych opcji pochodzi z `HISTORY.md` i treści
`a460ceb`. Dokładna data zamknięcia etapu nieznana.
