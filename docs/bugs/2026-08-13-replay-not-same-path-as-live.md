# Replay does not match live

**Status:** ⏳ investigating — `211741` checksums OK; CLI replay ≈ live; Browse Output differed  
**Reported:** 2026-08-13  
**Evidence:** `211741` (21:17)

## What we want

Save the listen. Play it back. Get the **same words** as live.

## `211741`

- `.feedlog` == rebuild from `.f32` + `.chunks` (bytes logged match sidecars).
- CLI `--fast-transcribe` twice: identical; words match live.
- CLI paced Replay: same as fast / live.
- Browse `.out.txt`: different chops (`But I'm still…` / `To be removed`).

## Time / non-audio in the path

**Transcriber (does not drive cuts):**

- `get_monotonic_time()` → only `last_wall_s` stats after a cut.
- `timeout_pop(100ms)` → wait for next queue item; does not change samples.
- `listening` → only `feed_pos_s` for UI.

**Sherpa `is_endpoint`:** uses **audio frame counts** (trailing blanks × frame shift), not wall clock. “1.2s silence” means frames in the stream, not `gettimeofday`.

**Replay.vala (does use wall clock):** paces `Capture.push` with `Timeout` / monotonic time so speakers stay in sync. Same bytes, different *when* they are pushed. On `211741` paced == fast; on some older clips they diverged.

**Also not pure audio:** `flush(pending)` can commit the Engine’s stop partial string (saved `.pending`), not only the current hypothesis.

## Injection schedule

Live stamps µs-since-first-op with each Session op. ''.chunks'' on disk is
`OP_STAMPED (-2)` then `(op, µs)` int32 pairs. Replay paces `feed_next` from
those µs when present (else 16 kHz duration). `.feedlog` `t=` still verifies
when the **worker** saw each accept.

## `220041` (~22:00)

- Checksums: identical (2680 lines).
- Ideal-16kHz Replay injection offsets differed (stalls / early first P).
- `.txt` ≠ Browse `.out.txt`.
- Re-test after stamped ''.chunks'' pacing with a **new** listen.

## Next

- New listen → Replay; compare chunk µs vs worker `.feedlog` `t=`.
- User ✅ when Browse Replay == `.txt`.
