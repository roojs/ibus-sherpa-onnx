# Remaining text in the field after dictate + Post / button

**Status:** ⏳ open — frequent in real use (2026-08-16)  
**Reported:** 2026-08-11  
**Package:** `ibus-sherpa-onnx` (post-0.3.2 local; still current)

> Emoji legend: RooTerm `docs/guide-to-writing-plans.md`.  
> Process: RooTerm `docs/bug-fix-process.md`.

## Problem

- 🔷 While dictating into a text field, user often presses a **Post / send / action button**.
- 🔷 After that, **leftover text remains in the input** (spoken fragment or preedit residue) more often than expected.
- 🔷 Mic usually stops (client `reset`) — good — but something still **writes into the field after** the app cleared / submitted.

## Mechanism (two inject paths)

Post / send typically does some mix of: read field → clear → `reset` IC → move focus (button).

1. **`focus_out` + `PREEDIT_COMMIT`**  
   Spoken drafts are published with `PreeditFocusMode.COMMIT`. On focus leave, IBus itself turns that draft into committed text in the widget. If the app already cleared the field for Post, that auto-commit **re-fills** it.

2. **`reset` → stop → `commit_text`**  
   `Engine.reset` still calls `update_listening(false)`, which **commits** `pending` when `saw_partial`:

```vala
if (this.transcriber != null && this.transcriber.listening) {
    this.update_listening(false, false);
}
base.reset();
```

   If `reset` runs while `saw_partial` is still true (before `focus_out` cleared it), we inject again after clear.

Either path alone can leave residue; together they race with the app’s clear.

Related closed bug: [`2026-08-11-DONE-preedit-cleared-on-focus-out.md`](2026-08-11-DONE-preedit-cleared-on-focus-out.md) — we added COMMIT to stop *losing* drafts on focus leave. That fix fights Post leftover.

## Product tension

| Goal | Behaviour |
|------|-----------|
| Don’t lose mid-phrase when clicking away | Keep / use `PREEDIT_COMMIT` |
| Don’t leave crumbs after Post | Don’t inject on focus leave / `reset` |

We cannot see “this focus leave is a Post” vs “user clicked another widget”. Client `reset` is the closest “composition done / submit churn” signal IBus gives us.

## Proposed fix (needs approval)

**A+B (✔️ applied 2026-08-16):**

**A:** On `reset`, **stop listening and discard** pending — clear/hide preedit, **no** `commit_text`. Keep commit-on-stop for explicit mic-off (hotkey, panel, voice-stop, Escape / typing interrupt).

**B:** Spoken drafts use `PREEDIT_CLEAR`; on `focus_out` while listening, empty preedit with `CLEAR` before `base.focus_out()` so IBus does not auto-commit. Accept rare mid-phrase vanish on accidental focus leave.

🚫 Do not try to detect “Post” per app.  
🚫 Do not keep listening across `reset` (already abandoned in 0.6 Phase A).

## Next

- ✔️ A+B chosen (2026-08-16).
- ✔️ Implemented: `update_listening(..., commit_pending)`; `reset` passes false; `focus_out` clears with `PREEDIT_CLEAR`; partials use `CLEAR`.
- ⏳ Soak: dictate → Post while still listening (partial on screen) — field should stay empty after send; mic off.

## Attempts

- (none yet — log opened from user report; mechanism clarified 2026-08-16)
- ✔️ A+B in `Engine.vala` (2026-08-16) — awaiting user soak
