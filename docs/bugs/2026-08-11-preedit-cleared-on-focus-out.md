# Preedit cleared on focus-out while listening (text lost)

**Status:** ⏳ open  
**Reported:** 2026-08-11  
**Package:** `ibus-sherpa-onnx` (engine — not prefs-specific)

> Emoji legend: RooTerm `docs/guide-to-writing-plans.md`.  
> Process: RooTerm `docs/bug-fix-process.md`.

## Problem

- 🔷 While listening, spoken text is shown only as **IBus preedit** until an endpoint/`commit_text`.
- 🔷 Any focus leave from the text field (click a button, another widget, etc.) causes the **client to drop preedit** without a commit.
- 🔷 The entry looks emptied; the utterance is gone. This happens in normal apps as well as Preferences — prefs mic only made it easy to see.
- 🔷 Unrelated to config / `RowMicText` stop UI (spinner soak does not clear the entry).

## Evidence (2026-08-11 prefs soak + engine log)

Setup (`ibus-setup-sherpa-onnx.debug.log`):

1. Start → `LISTENING` on `InputContext_16`.
2. Mic click → spinner / `STOPPING` only (no reset from prefs).
3. Entry content vanished from the user’s POV.

Engine (`ibus-sherpa-onnx.debug.log`), same window:

1. `listening ON (has_focus=false)`.
2. On mic click: `focus_out` / `focus_in` while **`listening=true`** — no commit logged.
3. ~7s later: `reset` → `listening OFF (has_focus=false)` — late stop; commit then still with `has_focus=false`.

`Engine.focus_out` today only logs; it does **not** commit pending preedit. GTK/IBus clears composition on focus leave.

## Root cause

- ✔️ Dictation output lives in **preedit** (`on_partial` → `update_preedit_text`).
- ✔️ `focus_out` while listening does not flush that preedit via `commit_text`.
- ✔️ Client drops preedit on focus change → **data loss**.
- ⏳ Secondary: logs show `has_focus=false` even after `focus_in` — may mean commits are unreliable even when we do call `commit_text`; needs a follow-up once flush-on-focus-out is in place.

## Hypotheses

1. ✔️ Preedit discarded on focus-out without engine commit (primary).
2. ⏳ `has_focus` never true in this factory path → `commit_text` may not reach the widget even after we flush.
3. ⏳ Related but opposite bug: [`2026-08-11-remaining-text-after-submit.md`](2026-08-11-remaining-text-after-submit.md) — `reset` **commits** leftover into the field after Post. Different trigger; same preedit/commit lifecycle.

## Proposed fix (needs approval)

On `focus_out`, **before** `base.focus_out()`, if listening and there is pending text (`saw_partial` / `transcriber.last_text`):

1. `commit_text` that pending string (same shape as stop-in-`update_listening`).
2. Clear preedit (`update_preedit_text` empty + `hide_preedit_text`).
3. Clear `saw_partial`; leave **listening on** (Phase A: focus churn must not kill the mic by itself).
4. Optionally restart the `...` animation if still listening and no new partial yet.

🚫 Do not paper over by copying preedit into the prefs entry outside IBus.  
🚫 Do not “fix” only Preferences.

### `Engine.vala` — `focus_out`

✔️ Applied (early-return when not listening / no partial).

## Conclusions (plain)

- Words only stick when recognition **finishes a phrase** (you see dots again after the words). That path already writes real text into the field. Stopping after that keeps those words.
- Mid-phrase draft was published with default **clear on focus loss**. IBus already supports **commit on focus loss** via `update_preedit_text_with_mode(..., PREEDIT_COMMIT)` — we were not using it.
- ✔️ Spoken drafts now use `PREEDIT_COMMIT`. Waiting dots stay `PREEDIT_CLEAR` so we do not insert `.` / `...` into the box.
- Manual `commit_text` in `focus_out` removed to avoid doubling; IBus owns the focus-loss commit.

## Next

- ⏳ Install/restart engine; soak leave-field mid-phrase — words should remain in the box.


## Attempts

- (prefs spinner soak only — confirmed entry clear is not from prefs `entry.text = ""` on stop)
- ✔️ `focus_out` flush pending preedit via `commit_text` (early return if `!listening || !saw_partial`)
