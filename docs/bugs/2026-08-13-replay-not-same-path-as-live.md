# Replay does not match live

**Status:** ⏳ investigating — stamped Replay still ≠ live on `082823`  
**Reported:** 2026-08-13  
**Evidence:** `211741` (21:17), `220041` (~22:00), `082823` (2026-08-14 08:28)

## 🚩 NEVER use `--fast-transcribe` / fast feed for this bug

**Fast feed deliberately overrides live injection sequencing and wall-clock
pacing.** It is a different path. Do **not** use it to judge whether Replay
matches live. Do **not** cite “fast == live” or “fast == paced” as evidence
here. The only valid comparison is:

**live listen → Browse/CLI paced Replay** (stamped `.chunks` µs when present).

---

## What we want

Save the listen. Play it back **with the same op sequence and the same
injection offsets**. Get the **same words** as live.

## `082823` (stamped; paced Replay only)

**Live `.txt`:**
```
So wooden gating a file exist check
On the um
Ipe uh be a good idea
```

**Browse `.out.txt`:**
```
So wooden gating a file exist check
The um content type
Uh be a good idea
```

| Check | Result |
| --- | --- |
| `.chunks` | `OP_STAMPED`; 1464 ops (R + 1462×P + F); PCM sum = `.f32` |
| `.feedlog` vs `.feedlog.replay` checksums / offs / sizes | **identical** (1464 lines) |
| Injection schedule | Replay paces from chunk µs |
| Worker `t=` vs stamp | **not the same** (see below) |
| Words | **differ** (middle + third lines) |

### Timing (paced path)

- **Live:** worker accept ≈ injection stamp (median lag ~0.05 ms), but at
  sample off `62720` the worker fell **~268 ms** behind, then burst-drained
  ~27 queued chunks in &lt;1 ms wall time.
- **Replay:** accept times sit **~13 ms early** vs stamps for most of the
  run (baseline skew: `start_mono_us` is taken before R is processed on the
  worker; feedlog `t=` is rebased at R accept). No matching 268 ms backlog
  burst.

**Pacing verdict:** ~13 ms early bias is **unlikely** to explain word
chops (was hundreds of ms before stamps). Injection/replay scheduling has
done about as much as it can — **same bytes into `accept_waveform`**. Look
further down.

## Where the chop actually lives

`Capture` is only: log → `queue_*`. It does **not** decide utterance cuts.

The cut is in `Transcriber.processing_loop` (same code live + Replay):

1. `accept_waveform` → `decode` while ready  
2. `get_result` → update `hypothesis`  
3. `is_endpoint` → if set, Idle-commit `hypothesis`, then `recognizer.reset`

That reset is **internal** (not a `.chunks` `OP_RESET`). Live `.endpoints`
for `082823`: sample offs `82880`, `136480`, `208320` (~5.18 / 8.53 /
13.02 s).

**Cut offs in feedlog (no new sidecar):** worker logs `E <off> t=…` on each
committed `is_endpoint` into `.feedlog` / `.feedlog.replay`. Diff those `E`
lines after a new listen + paced Replay. (`.endpoints` remains the live binary
sidecar; feedlog is the shared live/replay view.)

`listening` does **not** change the model path: only mic gate +
`feed_pos_s`. `Engine.on_partial` / `on_endpoint` no-op when not listening
(Browse Replay) — UI/IBus only, does not touch the stream.

So if words differ with identical feedlog hashes, either:

- `is_endpoint` / `get_result` are not stable for the same PCM sequence, or  
- something else mutates stream state between accepts (not seen in Capture).

## Time / non-audio (reference)

- Worker `timeout_pop(100ms)`: wait only; does not alter samples.  
- Sherpa endpoint rules: trailing **audio frames**, not wall clock.  
- `flush(pending)` can commit saved stop partial (`.pending`), not only
  current hypothesis.

## Older notes (kept for history)

### `211741`

- Checksums OK; Browse `.out.txt` differed. Earlier “CLI paced ≈ live”
  notes mixed with fast-path runs — **disregard fast-path claims**.

### `220041` (~22:00)

- Checksums identical; pre-stamp / ideal-16kHz pacing differed; `.txt` ≠
  `.out.txt`. Led to stamped `.chunks` work.

## Next

- New listen + paced Replay; diff `E` lines in `.feedlog` vs `.feedlog.replay`.  
- If cuts differ → instability in `is_endpoint` / decode for same PCM.  
- If cuts match but text differs → `get_result` drift (model / runtime).  
- Stop chasing ~13 ms Replay skew unless new evidence says otherwise.  
- User ✅ when paced Browse Replay == `.txt`.

## Design note (stamps / PCM log)

Prefer **optional debug fields on the in-memory session/op stream**, then
serialize what is already there — not packing/`OP_STAMPED` inject-at-write in
`Session.flush`. `E` in feedlog follows that idea (worker appends to the live
log buffer). Refactoring `.chunks` stamp packing the same way is follow-up.
