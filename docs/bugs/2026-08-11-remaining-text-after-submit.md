# Remaining text in the field after dictate + Post / button

**Status:** ⏳ open  
**Reported:** 2026-08-11  
**Package:** `ibus-sherpa-onnx` (post-0.3.2 local)

> Emoji legend: RooTerm `docs/guide-to-writing-plans.md`.  
> Process: RooTerm `docs/bug-fix-process.md`.

## Problem

- 🔷 While dictating into a text field, user often presses a **Post / send / action button**.
- 🔷 After that, **leftover text remains in the input** (spoken fragment or preedit residue) more often than expected.
- 🔷 Suspected link to **`Engine.reset`** behaviour from Phase A focus testing — unsure whether the “ignore reset / keep mic” experiment was fully walked back.

## Current code (evidence)

- `Engine.reset` **still stops listening** when on:

```vala
if (this.transcriber != null && this.transcriber.listening) {
    this.update_listening(false, false);
}
base.reset();
```

- `update_listening(false)` **commits** any partial that had been shown (`saw_partial` → `commit_text(pending + " ")`), then clears preedit.
- Plan `0.6` Phase A now records: ignoring reset was **abandoned**; **`reset` stops listening again** (✔️). So stop-on-reset is intentional in the plan, not an unreverted experiment.
- That still explains leftover text: client Post → `reset` → stop → **commit leftover partial into the field** after (or while) the app clears/submits.

## Hypotheses

1. ⏳ Post triggers `reset` while listening → commit-on-stop leaves the last partial in the buffer (most likely).
2. ⏳ Preedit (`.` / partial) not fully cleared on some clients even after `hide_preedit_text`.
3. ⏳ Race: app clears the field, then our commit lands after.

## Next

- ⏳ Reproduce with engine debug log: confirm `reset` → `listening OFF` + commit around Post.
- ⏳ Decide product rule: on `reset`, **discard** pending partial instead of commit; or stop without commit when reset is “submit churn”.
- 🚫 Do not add defensive null checks to hide the symptom.

## Attempts

- (none yet — log opened from user report)
