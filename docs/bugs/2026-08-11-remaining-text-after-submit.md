# Remaining text after submit vs wiped on play

**Status:** ✅ OLLMchat play soak (2026-08-17, attempt 3). ⏳ Leftover after Post still open — do not re-apply **B**. 
**Reported:** 2026-08-11 (leftover after Post); play wipe 2026-08-17  
**Package:** `ibus-sherpa-onnx` (post-0.3.2 local; still current)

> Emoji legend: RooTerm `docs/guide-to-writing-plans.md`.  
> Process: RooTerm `docs/bug-fix-process.md`.

## Problem — two poles, one race

Same session, same engine, opposite field outcomes. Toggling `PREEDIT_COMMIT` vs `PREEDIT_CLEAR` on focus leave just swaps which pole we hit. This log is the paper trail so we do not re-apply a pole we already tried.

### Leftover after Post (🔷 2026-08-11)

- 🔷 While dictating, user presses **Post / send**.
- 🔷 Mic stops (client `reset`) — good.
- 🔷 Spoken fragment / preedit residue is **written back** into the emptied field.

### Wiped on play (🔷 2026-08-17)

- 🔷 OLLMchat: enter/dictate text, click **play** (send).
- 🔷 Composer should still hold the draft when `ChatInput.text()` runs (app clears **after** a successful send).
- 🔷 Actual: composer **empties**; `text().length == 0`; send does not fire.
- ✅ Attempt 3 soak (2026-08-17): play keeps the draft / send works. User: “fixed it for now.”

## Why they fight

- ℹ️ Spoken text lives in IBus **preedit** until endpoint / `commit_text` / focus-loss COMMIT.
- ℹ️ OLLMchat play is send. GTK4 `gtk_text_view_focus_out` calls `gtk_im_context_focus_out` on **mouse-press**. `ChatInput.clicked` reads the buffer on **mouse-release**. `reset` is deferred (`need_im_reset`) until a later buffer change.
- 🔷 We cannot see “this leave is Post” vs “this leave is play”.
- ℹ️ Client `reset` is still the closest “composition done” signal — but it runs **after** play needed the draft.
- ℹ️ `PREEDIT_COMMIT` on focus leave: play keeps the draft (IBus commits into the widget before `clicked`); Post can re-fill after the app cleared.
- ℹ️ `PREEDIT_CLEAR` on focus leave: no IBus auto-commit after Post; play **wipes** the draft before `clicked`.
- ℹ️ `reset` → `commit_text(pending)`: leftover if the app already cleared.
- ℹ️ `reset` → discard, no `commit_text`: no second inject after Post; does **not** save play, because `focus_out` already ran.

## Attempts — do not repeat

### 1. `PREEDIT_COMMIT` on spoken drafts (2026-08-11)

- ✔️ Shipped to stop losing mid-phrase on focus leave.
- ℹ️ Log: [`2026-08-11-DONE-preedit-cleared-on-focus-out.md`](2026-08-11-DONE-preedit-cleared-on-focus-out.md).
- ✔️ Closed 2026-08-16 as “almost never” — **wrong for OLLMchat play** (see soak below).
- 🔷 User then reported leftover after Post (this file).

### 2. A+B (✔️ applied 2026-08-16)

- 🔷 **A:** On `reset`, stop listening and **discard** pending — no `commit_text`. Explicit mic-off still commits.
- 🔷 **B:** Partials use `PREEDIT_CLEAR`. `focus_out` empties preedit with CLEAR **before** `base.focus_out()`.
- ✔️ In tree: `update_listening(..., commit_pending)`; `reset` passes `false`.
- 🔷 Soak 2026-08-17 **failed** on OLLMchat play (wipe).

### Soak evidence (2026-08-17)

- ℹ️ `~/.cache/ibus-sherpa-onnx/ibus-sherpa-onnx.debug.log` 08:25:21:
  - `focus_out: listening=true saw_partial=true` — **B** CLEARs the draft here (mouse-press).
  - ~800 ms later `reset: listening=true` → `listening OFF (commit_pending=false)` — **A**, after play already saw empty.

### 3. Focus-out COMMIT, then CLEAR (🔷 2026-08-17)

- 🔷 User: commit on `focus_out`, **then** clear — do not CLEAR first.
- ✔️ Applied: partials use `PREEDIT_COMMIT`. `focus_out` calls `base.focus_out()` first (IBus commits the draft into the widget). Then empty preedit with CLEAR / hide / `saw_partial = false`.
- ✔️ **A stays:** `reset` still discards (no `commit_text`). That is the “then clear” after play has read the buffer.
- ℹ️ GTK order already matches: mouse-press `focus_out` → mouse-release `clicked` → later `reset`.
- ℹ️ Expected play: press → COMMIT into buffer → CLEAR preedit → release → `text()` non-empty → send → app `update_entry("")` → `reset` discards.
- ℹ️ Expected Post: same COMMIT-then-CLEAR on leave; `reset` must not inject a second copy. Leftover can still return if the app **clears the field before** `focus_out` COMMIT lands — do not “fix” that by putting CLEAR **before** `base.focus_out()` (attempt 2 / play wipe).
- ✅ Play pole verified (2026-08-17).

🚫 Detect Post vs play per app.  
🚫 Keep listening across `reset` (abandoned in 0.6 Phase A).  
🚫 Re-apply **B** (CLEAR preedit **before** `base.focus_out()`) — that is the play wipe.  
🚫 Close focus-out loss as wont-pursue again without a soak on OLLMchat play.

## Next

- ✔️ A+B in `Engine.vala` (2026-08-16) — soak failed on play.
- ✔️ Attempt 3 in `Engine.vala` (2026-08-17) — COMMIT then CLEAR; `reset` discards.
- ✅ OLLMchat play soak (2026-08-17).
- 🔷 `⏳` Dictate → Post: field stays empty (no leftover inject). Do not “fix” leftover by re-applying **B**.
