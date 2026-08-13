# Replay ASR path is not the same as live

**Status:** ⏳ Session.feed wired — await fresh listen (post `num_threads=1` install) + Replay user ✅  
**Reported:** 2026-08-13  
**Package:** `ibus-sherpa-onnx` (Capture / Session / Debug.Replay / CLI `--wav`)  
**Related plan:** `docs/plans/0.8-debug-recordings-replay.md` Phase C (purpose unmet)  
**Evidence:** `091746` Browse ~85% (extra mid-endpoint + grafted `.pending`); `091821` Browse 100% / CLI op-feed ~71% (mid-endpoints); `091956` 100%

> Emoji legend: RooTerm `docs/guide-to-writing-plans.md`.  
> Process: RooTerm `docs/bug-fix-process.md`.

## Design (non-negotiable)

- 🔷 **Session** is the whole listen: live `Capture` logs ops into it; `Session.flush` writes sidecars; `Session.load` reads them back.
- 🔷 **Replay** = `Session.feed` / `feed_next` into `Capture` — same bytes, same op order (`0` reset / `n` push / `-1` flush). Speakers may play `.wav` in parallel; they must not redefine ASR chunking.
- 🔷 CLI `--fast-transcribe` and Browse Replay share that feed. No second ASR policy.

## Problem (observed)

- 🔷 Live listen and Replay must share accept → decode → endpoint → flush. Only the PCM **source** may differ.
- 🔷 85%/71% matches mean extra `is_endpoint` cuts on replay, then `flush(.pending)` re-emits live’s stop text → duplicated lines (not “close enough”).
- 💩 Some fixtures were recorded **before** engine install that set `num_threads=1` (was `1..4`). Re-ASR with 1 thread can cut differently than multi-thread live. Acceptance needs a **new** listen on the current binary.

## Expected vs actual

| | Expected | Actual (when wrong) |
|---|---|---|
| Ops | `Session.feed` → Capture only | Older Browse used wav tee + Feed |
| Cuts | Same `is_endpoint` as live | Extra mid-endpoints on some replays |
| Stop | `flush(pending)` as live stop | Same call, but after divergent cuts → grafted full pending |
| Outcome | Replay Output == live `.txt` | 85–100% RapidFuzz; not guaranteed |

## Proposed fix

### Shape (settled)

- ✔️ `Capture : Transcriber` (`save` on/off). Live + Replay call `reset` / `push` / `flush`.
- ✔️ `Session.feed` / `feed_next` — single op-log walker. Browse Replay paces `feed_next`; CLI `--fast-transcribe` calls `feed`.
- 🔷 **Acceptance:** new listen on current engine → Replay Output matches `.txt`; user ✅.

### Must still hold

- 🚫 Do not fake Output from saved `.txt`.
- 🚫 Do not drive cuts from `.endpoints`.
- 🚫 Do not keep a second CLI op loop beside `Session.feed`.

## Attempts / changelog

- ✔️ Forced `.endpoints` / dual `file_active` path — rejected.
- ✔️ Capture + sidecars; Browse still used Feed/wav for ASR — fixed to op log.
- ✔️ 2026-08-13: `Session.feed` / `feed_next`; CLI fast + Replay both use it.

## Next

- ⏳ Reinstall setup/engine if needed; **new** listen; Replay; user ✅.
- ⏳ Plan `0.8` Phase C stays open until user ✅.
