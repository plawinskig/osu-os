# Etapy projektu osu!kiosk

Szczegółowy zapis każdego etapu: cel, zmiany z commitami, decyzje, porażki,
wyniki i odnośniki do pomiarów. Bieżący stan jest w `PROGRESS.md`,
trwała architektura i konwencje w `CLAUDE.md`.

| Etap | Plik | Daty | Commity | Status |
|---|---|---|---|---|
| 1 | `01-kernel-toolchain.md` | 4–6.09.2026 | `3bc3886`..`776316d` | ✅ |
| 2 | `02-two-stage-rootfs.md` | 9.09.2026 | `37ba9a6`, `1db338d` | ✅ |
| 3 | `03-image-layout.md` | 9–13.09.2026 | `96fa68d`, `d33e8db`, `7062e3a` | ✅ |
| 4 | `04-boot-end-to-end.md` | 12–22.09.2026 | `3e83b74`..`a496629` | ✅ |
| 5 | `05-graphics-audio-session.md` | 22.09–6.11.2026 | `c146c74`..`7f276db` | ✅ |
| 6 | `06-osu-lazer.md` | 12–18.11.2026 | `851b1a1`..`f19581b` | ✅ |
| 6a | `06a-demo-fast-boot.md` | 19.11.2026 | `fd1dfee`..`3055ff3` (branch `demo-fast-boot`) | ✅ pokaz |
| 7 | `07-new-features.md` | — | — | ⬜ |

## Jak prowadzić te pliki

- Plik bieżącego etapu aktualizuj po każdym zamkniętym kroku, decyzji albo
  blockerze, w tej samej turze co zmianę. Zakres commitów, wyniki i
  porażki dopisuj od razu, nie na koniec etapu.
- Po zamknięciu etapu plik jest zamrożony. Późniejsze poprawki faktów
  oznaczaj datą (np. „Poprawka 24.10.2026: …”).
- Nowy etap: nowy plik `NN-<temat>.md` (nazwa po angielsku, treść po
  polsku) według struktury istniejących plików i nowy wiersz w tabeli wyżej.
- Commity nadal opisują każdą zmianę per plik (zasady w `CLAUDE.md`). Plik
  etapu ich nie zastępuje: streszcza je, łączy z wynikami i zapisuje to,
  czego w commitach nie ma (odrzucone warianty, wyniki rund, decyzje autora).
- Pomiary, logi i zrzuty ekranu zostają poza repo, obok niego:
  `../measurements/<runda>/` (spis w `../measurements/README.md`) i
  `../screenshots/RRRR-MM-DD-<temat>/` (spis w `../screenshots/README.md`).
  Pliki etapów tylko do nich odsyłają. Ścieżki w plikach etapów są względne
  wobec katalogu repo (`osu-kiosk-external/`), tak jak w `CLAUDE.md`.

## Uwagi o historii gita

- Etapy 1–3 mają lakoniczne commity (styl `feat(...)`), a część binariów
  (`bzImage`, `rootfs.squashfs`) była wtedy commitowana. Ich opis
  pochodzi głównie z `HISTORY.md`, zamkniętej narracji do Etapu 4.
- 12.11.2026 historię przepisano (`git filter-branch`, usunięcie stopek
  `Co-Authored-By`). Stan sprzed przepisania wskazuje gałąź
  `backup/pre-trailer-removal` (`d34e07a`). Przepisane zostały commity od
  `45f7f28` (22.09) do `7f276db` (6.11), więc hashe z tego okresu w starych
  notatkach spoza repo mogą nie istnieć na `main`. Hashe w tych plikach są
  aktualne (po przepisaniu).
- Starsze wersje `PROGRESS.md` (zwłaszcza `dbc9db9`, Etap 5 z pełnymi
  krokami A–D) zawierają szczegóły, które streszczają pliki etapów:
  `git show dbc9db9:PROGRESS.md`.

## Źródła rekonstrukcji (19.11.2026)

Pliki 01–06a odtworzono z: treści wszystkich 67 commitów (`main` i
`demo-fast-boot`), `HISTORY.md`, wersji `PROGRESS.md` z commitów
`c1a942f`, `b8f4577`, `c146c74`, `0c4d0d0`, `014d046`, `1c12bd8`,
`f638b2b`, `c0fc037`, `dbc9db9`, `7f276db` i `96ab762`, oraz README rund
w `../measurements/` i katalogów w `../screenshots/`. Czego nie dało się
ustalić, jest oznaczone jako niepewne albo „do uzupełnienia przez autora”.
