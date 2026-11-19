# Etap 6a — wersja pokazowa z szybszym bootem (branch `demo-fast-boot`)

Status: ✅ zamknięty 19.11.2026 (wersja v2b na prezentację)
Zakres commitów: `fd1dfee`..`3055ff3` (19.11.2026, branch `demo-fast-boot`
od `f19581b`; `main` bez zmian)

## Cel

Wersja beta na prezentację 19.11.2026 na Z570: start jak najszybszy, ale
przede wszystkim niezawodny. Punkt odniesienia: 46 s od Entera przy
`boot:` do menu (runda 1 Etapu 6). Plan: pomiar (runda A), jeden pakiet
zmian wybranych według pomiaru, QEMU, weryfikacja (runda B).

Decyzje autora na start: tylko ekran laptopa; wyjście z gry uruchamia grę
od nowa, a wyłącza tylko przycisk zasilania (łatka `cage` niepotrzebna);
zostaje obecny pendrive (drugi, Chipsbank 048d:1234, czytał wolniej).

## Co zrobiono

- `fd1dfee`: `osukiosk-session` po statusie 0 `cage` restartuje grę zamiast
  wyłączać (na Z570 przypadkowe wyjście kosztuje 17–18 s zamiast pełnego
  bootu).
- `86a2b99`: initramfs: szukanie pendrive'a co 0,2 s zamiast 2 s; rozmiar
  obrazu z `ls -ln` zamiast `wc -c` (BusyBox czytał cały obraz, ok. 2,6 s;
  **błąd jest też na `main`, od `6d00f26`**); `delay_use=0` na starcie;
  `max_sectors` 2048 na czas kopiowania z powrotem do domyślnego i ponowną
  próbą przy błędzie; `osukiosk.safeusb` wyłącza obie zmiany USB.
- `fa53c9c`: rootfs ZSTD poziom 22 zamiast XZ, `SQUASHFS_ZSTD`,
  `SQUASHFS_FILE_DIRECT`, `SQUASHFS_COMPILE_DECOMP_MULTI_PERCPU`. Obraz
  221,8 → 236,0 MiB, ale Mesa w `cage` 0,18 s zamiast 1,41 s, gra do menu
  9,9 s zamiast 14,3 s.
- `4d92878`: łatka kernela `board/osukiosk/patches/linux/0001-PCI-lift-a-2.5GT-s-restriction-only-on-an-active-link.patch`
  (`BR2_LINUX_KERNEL_PATCH`): kernel 6.18.48 przy każdym boocie retrenował
  pusty port PCH `00:1c.0` i czekał 2 s (`acpi_init` 2034 ms → 35 ms).
- `533aed1`: `QEMU_KERNEL` i `QEMU_BOOT_VFAT` w `qemu-test.sh` (porównania
  zapisanych buildów w trybie direct).
- `3055ff3`: nowy skill `boot-time`, uzupełnione `hardware-test-round` i
  `build-osukiosk-image` (skille na razie tylko na branchu).

## Decyzje

- **Zmiany tylko tam, gdzie pomiar pokazał koszt.** Odrzucone jako
  nieuzasadnione: `sync` w tle (0,08 s), rozgrzewanie plików, bez `ahci`
  (dysk gotowy równolegle), skrypty sieci i crond.
- **v2b to wersja na prezentację** (po rundzie B), bez dalszych zmian na
  pendrivie przed pokazem.
- Branch nie jest scalany z `main`. Co przenieść, decyduje autor (Etap 7).

## Co nie zadziałało / pułapki

- Pierwsza kopia logów rundy A trafiła przez pomyłkę w ścieżce do
  `../measurements/stage6-round1/home/…`: `copy-logs.sh` bierze folder
  względny wobec swojego katalogu.
- W QEMU Enter z `qemu-test.sh` otworzył menu i panel ACCOUNT, a
  przytrzymany Esc tylko cofnął menu. Wyjście wymaga trzech zwykłych Esc,
  potem przytrzymania.
- `sload.f2fs` nie nadpisuje pliku istniejącego w obrazie; nową wersję
  skryptu wgrywa się na świeżą kopię danych.

## Wyniki i weryfikacja (Z570)

Boot pomiarowy (`debug quiet printk.time=1 initcall_debug log_buf_len=4M`,
`demo.sh measure`), sekundy od startu kernela:

| Odcinek | Runda A (`e97d9a0`) | Runda B (v2b) |
|---|---|---|
| kernel do `/init` | 2,24 | 0,31 |
| `/init` → pendrive wykryty | 2,95 | 2,90 (enumeracja pendrive'a, sprzęt) |
| `delay_use` | 1,13 | 0,12 |
| pendrive gotowy → kopiowanie | 4,48 | 0,26 |
| kopiowanie | 11,54 (221 MiB, 19,2 MiB/s) | 10,13 (235 MiB, 23,2 MiB/s) |
| `switch_root` → sesja | 3,64 | 2,48 |
| `cage` → gra | 2,31 | 0,48 |
| gra → menu | 14,3 | 9,9 |
| **menu** | **42,7** | **26,7** |

- Stoper autora: **36 s od przycisku zasilania do menu** zamiast ok. 54 s
  (wcześniej 10 s do `boot:` z F12 plus 44 s). BIOS startuje teraz z USB HDD
  bez F12.
- Gra wraca po Esc sama po 17–18 s. Mapa z dźwiękiem, płynnie, jedna krótka
  ścinka na początku mapy (ładowanie i EBUSY, nie regresja).
- Przycisk zasilania i `poweroff` wyłączają czysto.
- Runda A `speed`: rozpakowywanie XZ 23,7 MiB/s (jeden dekompresor),
  pendrive 18,3–19,3 MiB/s bez względu na `read_ahead_kb`, z `max_sectors`
  2048 22,5–24,3 MiB/s.
- Narzędzia, dziennik zmian w drzewach builda, instrukcje rund i procedura
  powrotu na `main`: `../measurements/demo-fast-boot/README.md`.
- Zrzuty: `../screenshots/2026-11-19-demo-fast-boot/`.

## Co zostało / przeniesione dalej

- **Stan poza gitem:** drzewa builda są w stanie z brancha (defconfig z ZSTD
  i łatką, łatka PCIe nałożona ręcznie na
  `../buildroot/output/build/linux-6.18.48`). Przed buildem z `main`:
  `make osukiosk_main_defconfig`, `make linux-dirclean`,
  `make -C ../output-initramfs`, `make`. Pendrive ma v2b; wersja z `main` jest
  w `../images-main-e97d9a0/` (`update-stick.sh`).
- Do decyzji autora (Etap 7): które zmiany przenieść na `main`. Poprawka
  `wc -c` to błąd na `main`. Restart po wyjściu, `delay_use`, `max_sectors`
  i `safeusb` sprawdzono tylko z jednym pendrive'em.
- Na później: bez `ahci` (do 0,9 s), `i915.fastboot=1` (modeset ok. 1 s),
  squashfs prosto z pendrive'a (do menu czyta się 80 z 235 MiB), szybszy
  pendrive, intro i JIT gry.

## Gdzie trafiły trwałe ustalenia

- skill `boot-time` (na branchu): metoda pomiaru, odczyt osi czasu, koszty na
  Z570 i kandydaci.
- skill `hardware-test-round` (na branchu): fakty o BusyBox w skryptach
  rund, F2FS w QEMU, warianty buildów.

## Źródło

Treść commitów `fd1dfee`..`3055ff3`, `../measurements/demo-fast-boot/README.md`,
`../next-session-prompt.md` (19.11.2026).
