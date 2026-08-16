# Preedit cleared on focus-out while listening (text lost)

**Status:** ✅ DONE / wont-pursue — `PREEDIT_COMMIT` on spoken drafts; user reports this almost never happens in practice (2026-08-16).  
**Reported:** 2026-08-11  
**Package:** `ibus-sherpa-onnx` (engine — not prefs-specific)

> Emoji legend: RooTerm `docs/guide-to-writing-plans.md`.  
> Process: RooTerm `docs/bug-fix-process.md`.

## Problem

- 🔷 While listening, spoken text is shown only as **IBus preedit** until an endpoint/`commit_text`.
- 🔷 Any focus leave from the text field (click a button, another widget, etc.) causes the **client to drop preedit** without a commit.
- 🔷 The entry looks emptied; the utterance is gone.

## What we shipped

- ✔️ Spoken drafts use `update_preedit_text_with_mode(..., PREEDIT_COMMIT)` so IBus turns the draft into real text on focus loss.
- ✔️ Waiting dots stay `PREEDIT_CLEAR` so `.` / `...` are not inserted.
- ✔️ Manual `commit_text` in `focus_out` removed (would double).

## Conclusions (plain)

- Mid-phrase loss on focus leave was real; COMMIT mode largely fixed it.
- ✔️ Closed 2026-08-16: residual cases are rare enough not to chase.
- Related opposite symptom (leftover after Post): [`2026-08-11-remaining-text-after-submit.md`](2026-08-11-remaining-text-after-submit.md) — still open; COMMIT-on-focus-loss may contribute.
