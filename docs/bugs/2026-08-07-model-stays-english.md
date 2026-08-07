# Active language vs single model symlink

**Status:** ✔️ DONE  
**Reported from:** Multiple languages / packs; one symlink for all  
**Package:** `ibus-sherpa-onnx` 0.2.0

> Emoji legend: RooTerm `docs/guide-to-writing-plans.md` (Discussion style).  
> Process: RooTerm `docs/bug-fix-process.md`.

## Problem

- 🔷 Softlink `~/.config/ibus-sherpa-onnx/model` was OK for one pack.
- 🔷 With two (and later more) model families, flipping language does not
  change which weights load.

## Proposed fix (user direction)

- 🔷 `packs.ini` holds pack choice **per language** (`[packs] es-ES=nemo-ml-1120`).
- 🔷 `settings.ini` stays ''general'' only (hotkey / language / …).
- 🔷 Engine resolves model dir from `packs.ini` — not the symlink.
- 🔷 Prefs read/write `packs.ini` for the language combo.
- 🔷 One-shot seed: current language from legacy symlink if `pack=` unset.
- 🔷 Recreate `Transcriber` when pack changes; “Loading speech model…”
  notification, withdrawn when done.
- 🔷 CLI left alone (still may use symlink / `--language`).

## Implemented

- ✔️ `Config`: `settings.ini` + `packs.ini`; load file then default missing keys
  (no group/key copy loop).
- ✔️ `Models.pack_dir` / `pack_id_for_dir`.
- ✔️ Prefs Close writes `packs.ini`; `ModelDownload` no longer symlinks.
- ✔️ `Engine.ensure_transcriber` on enable / listen-on.
- ✔️ Application one-shot symlink seed into `packs.ini` for current language.

## Still open

- 💩 ⏳ Missing / not-installed `pack=` — still `notify_no_model` only.

## Rejected

- 🚫 Full multi-language migration story.
- 🚫 Relink-on-Close family hacks.
