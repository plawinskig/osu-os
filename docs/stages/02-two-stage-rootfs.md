# Etap 2 — dwuetapowa architektura rootfs

Status: ✅ zamknięty (ok. 9.09.2026; pełny boot potwierdzony w Etapie 4)
Zakres commitów: `37ba9a6`, `1db338d` (9.09.2026, `main`)

## Cel

Boot w całości do RAM („dwustopniowa rakieta”): mały initramfs znajduje
pendrive, kopiuje `rootfs.squashfs` do tmpfs i robi `switch_root`. Od tej
chwili USB przestaje być wąskim gardłem.

## Co zrobiono

- `37ba9a6`: `configs/osukiosk_initramfs_defconfig`. Initramfs to osobna
  konfiguracja tego samego Buildroota z osobnym katalogiem wyjściowym
  (`make O=../output-initramfs BR2_EXTERNAL=../osu-kiosk-external ...`).
  - Toolchain glibc, linkowanie „shared only”.
  - Pakiety: tylko BusyBox.
  - System plików: `cpio` + gzip (szybka dekompresja wcześnie w boocie,
    nie rozmiar). Wynik `rootfs.cpio`: 5,4 MB.
- `1db338d`: `board/osukiosk/initramfs-overlay/init`, PID 1 initramfsu.
  Pierwsza wersja montowała partycję boot po etykiecie (`mount -L OSUBOOT`).
- Kernel main systemu wchłania `rootfs.cpio` przez
  `CONFIG_INITRAMFS_SOURCE`. Kolejność budowania: najpierw
  `output-initramfs`, potem `linux-rebuild` w głównym drzewie.

## Decyzje

- **„Shared only”, nie static:** Buildroot blokuje pełny static link z glibc
  przez NSS (`libnss_*.so` ładowane dynamicznie). Bez musl nie do obejścia.
- **Dwa niezależne drzewa configu jednego Buildroota** (main w
  `../buildroot/output/`, initramfs w `../output-initramfs/`).

## Co nie zadziałało

- **`mount -L`:** BusyBox `mount` jest zbudowany bez obsługi etykiet. `/init`
  przepisano na iterację po `/dev/sd*` i `/dev/nvme*` (`18cbd7a`,
  `b13f048`, 13.09, już w ramach Etapu 4).
- **Pomylone drzewa configu (najważniejsza lekcja projektu):** pierwsza
  próba naprawy „ślepego” initramfsu zmieniała config kernela w
  `output-initramfs`, a skrypt z `scripts/config` trafił dodatkowo w
  `linux-headers` zamiast w źródła kernela. Drzewo initramfsu nie produkuje
  bootowalnego kernela, tylko `rootfs.cpio`; bootuje się kernel main
  systemu. Rozstrzygnięte w Etapie 4.
- `CONFIG_INITRAMFS_SOURCE` był ścieżką bezwzględną do
  `/home/greggy/...`. Zmieniony na względną w Etapie 4 (`45f7f28`, 22.09).

## Wyniki i weryfikacja

- Działanie `switch_root` potwierdzone dopiero w Etapie 4. Wcześniejsze
  „zweryfikowane do `switch_root` na sprzęcie” z `HISTORY.md` nie miało
  pokrycia w ówczesnym kernelu (patrz Etap 3).

## Gdzie trafiły trwałe ustalenia

- `CLAUDE.md`: architektura „two-stage rocket”, decyzje o osobnym drzewie
  initramfsu, „shared only” i ścieżce `CONFIG_INITRAMFS_SOURCE`.

## Źródło

`HISTORY.md` („Etap 2”, „Bieżący blocker”), tytuły commitów, treść
`45f7f28`. Uwaga: schemat katalogów w `HISTORY.md` pokazuje
`buildroot/output-initramfs/`, a faktyczny układ to rodzeństwo
`../output-initramfs/`.
