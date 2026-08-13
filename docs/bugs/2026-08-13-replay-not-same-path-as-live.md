# Replay ASR path is not the same as live

**Status:** ⏳ wired — await fresh listen + Replay user ✅  
**Reported:** 2026-08-13  
**Package:** `ibus-sherpa-onnx` (Transcriber / Debug.Replay / CLI `--wav`)  
**Related plan:** `docs/plans/0.8-debug-recordings-replay.md` Phase C (purpose unmet)  
**Evidence:** `~/.cache/ibus-sherpa-onnx/debug/2026-08-13/001447.*` (live `.txt` ≠ fast Replay); `001737.*` matched on one CLI run but is not proof of one path

> Emoji legend: RooTerm `docs/guide-to-writing-plans.md`.  
> Process: RooTerm `docs/bug-fix-process.md`.

## Problem (observed)

- 🔷 **Requirement (stated repeatedly):** live listen and Replay must use the **same** accept → decode → endpoint → stop path. Only the PCM **source** may differ (mic vs saved floats).
- 🔷 **Actual:** Replay is a **second** path (`file_active`, forced `.endpoints` cuts, special `for_flush` / pending commit, separate Browse Transcriber). Live Output / `.txt` and Replay Output diverge.
- 🔷 Concrete (001447): live `.txt` starts `That would have interest` / `Of interest`; `--fast-transcribe` Replay starts `Out of interest` / `Um, out of interest` (and further line drift).
- 🔷 User has been correcting “same path” for days; agents kept adding sidecars / forks and claiming progress. Plan Phase C was marked ✔️ without user ✅.

## Expected vs actual

| | Expected | Actual |
|---|---|---|
| Cut policy | Same as live (`is_endpoint`) | File mode cuts only at saved `.endpoints`; ignores `is_endpoint` |
| Stop / tail | Same as live stop + pending | `for_flush` commits `.pending` or hypothesis; not `stop` / `session_end` |
| Worker gate | One “accepting” mode | `listening` **or** `file_active` branches throughout Idle / accept |
| Session on file run | Empty capture session (or none); Feed owns loaded PCM | `begin_file` **replaces** `transcriber.session` with loaded Session (endpoints/pending/pcm) |
| Outcome | Replay Output == live `.txt` for a faithful capture | Not guaranteed; paths differ by design today |

## Evidence (code — confirmed)

- ✔️ `Transcriber.processing_loop`: file cut fork

```vala
if (this.file_active && this.session.endpoint_off.length > 0) {
    /* forced cuts */
} else if (this.recognizer.is_endpoint(this.stream) != 1) {
    return;
}
```

- ✔️ Live: `start` / `stop(pending)` → mic + `session_end` → `Session.flush` (save). Replay: `begin_file` / `for_flush` → `file_finished` (no shared stop).
- ✔️ `Debug.Replay` + Dialog `ensure_transcriber`: **new** Transcriber in setup process, not the IBus engine instance that recorded (process boundary — OK for offline, but must still call the **same** worker logic).
- ✔️ Extra live-only gap: `start()` sets `listening` before worker `reset` sets `recording`; mic chunks can be **accepted without being written** to `.f32`/`.chunks` until reset runs.

## Root cause

- ✔️ **Not** “one more missing sidecar.” The defect is **architectural forking**: Replay was built as a parallel file-feed policy instead of “push the same PCM into the same listen pipeline.”
- 💩 ONNX non-determinism may still exist even on one path; that is secondary until the path fork is removed.
- 💩 Saving `.endpoints` / `.pending` for diagnostics is fine; **using them to drive a different cut/stop policy is not** (violates the stated requirement).

## Proposed fix

### Shape (settled 2026-08-13)

- ✔️ **One class** `Transcriber` with construct `save`: record sidecars when true; ASR-only when false. No subclass / no virtual stubs.
- ✔️ Mic and Replay both call `push`; cuts always `is_endpoint`; file feed via `begin_file` / `end_file` (pending on flush chunk).
- 🔷 Engine live: `new Transcriber(..., save: debug-recordings)`. Browse Replay / CLI: `save: false`.

### Must still hold

- ✔️ **One PCM path in `processing_loop`:** always `is_endpoint` (forced `.endpoints` fork removed).
- 🔷 File/mic differ only in **source** (appsink vs Feed) and whether `save` records — not in cut/stop logic.
- 🔷 **Acceptance:** new listen → Replay Output matches `.txt` word-for-word; user ✅. Phase C stays open until then.
- 🚫 Do not “fix” by emitting saved `.txt` lines while pretending to ASR.
- 🚫 Do not add FilePlan / more cut helpers.

## Attempts / changelog

- ✔️ Sidecars `.f32` / `.chunks` / `.endpoints` / `.pending`; `Session.load` / `begin_file` refactor — improved capture, **kept** the dual path.
- ✔️ Forced endpoints + pending flush made some fixtures match (e.g. older 233428, 001737 once) while **violating** “same path”; 001447 still diverges.
- ✔️ Agents repeatedly promised “one more fix”; no `docs/bugs/` ticket until 2026-08-13.
- ✔️ 2026-08-13: tried `Capture : Transcriber` + virtuals; folded back — one `Transcriber` + `save` (no naked base / no stub virtuals).
- ✔️ 2026-08-13: Engine/GTK/CLI/Dialog construct `Transcriber(save)`; Replay/CLI PCM via `push`; no forced endpoints.

## Next

- ⏳ Fresh listen + Replay; Output must match `.txt`; user ✅.
- ⏳ Plan `0.8` Phase C stays open until user ✅.
