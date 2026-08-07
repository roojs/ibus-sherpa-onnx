# Active language vs single model symlink

**Status:** ✅  
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
- 🔷 One-shot seed: current language from legacy symlink if unset.
- 🔷 Recreate `Transcriber` when pack/language engine changes; loading
  notification (always; not behind start/stop pref).
- 🔷 CLI left alone (still may use symlink / `--language`).

## Implemented

- ✔️ `Config`: `settings.ini` + `packs.ini` (`[packs] lang=pack_id`).
- ✔️ Prefs Close writes language → pack; `ModelDownload` no longer symlinks.
- ✔️ `Engine.ensure_transcriber` on enable / focus_in / listen-on.
- ✔️ Application one-shot symlink seed; `en-*` also seeds bare `en`.
- ✔️ Missing pack → notify (always); loading banner for model load.
- ✔️ Auto-pick installed family pack when language has no `packs.ini` row yet.
- ✔️ ✅ User: en-GB / es-ES / bare `sherpa-onnx` after `en=` / prefs setup.

## Rejected

- 🚫 Full multi-language migration story.
- 🚫 Relink-on-Close family hacks.
- 🚫 Keying `packs.ini` by model family (would share chunk across languages).
