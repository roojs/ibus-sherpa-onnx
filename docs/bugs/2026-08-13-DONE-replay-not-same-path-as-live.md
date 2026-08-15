# Replay does not match live

**Status:** ✅ DONE (0.3.3) — product path uses PCM quiet chopper; sherpa `is_endpoint` ditched. Replay/debug recordings are compile-optional (`-Ddebug_recordings`).  
**Reported:** 2026-08-13  
**Best evidence:** recording `081216` (15 Aug morning)

## 🚩 Do not use `--fast-transcribe` for this bug

That mode ignores real timing on purpose. Only compare:

**speak live → save → Replay at recorded pace → compare words / cut marks.**

---

## Plain English — what we concluded

### 1. We are saving the right audio

Every little chunk of sound that went into the recogniser live is checksummed
in `.feedlog`. On Replay, those checksums match line-for-line.

**Conclusion:** Replay is not feeding different audio. Same sound, same order,
same chunk sizes.

### 2. The words differ because the “end of sentence” cuts differ

While you talk, the engine decides “that was a pause — commit this line and
start fresh.” We log each of those decisions as an `E` line (sample offset).

On `081216`, live and Replay cut at **different** places. So you get different
line breaks and different wording, even though the audio was the same.

**Conclusion:** The bug is in **when the engine chooses to cut**, not in
Capture/Replay failing to play the file back.

### 3. Replay is consistent with itself

We ran paced Replay twice on the same file (CLI). Both runs:

- same checksums as live  
- **same** `E` cuts as each other  
- **same** words as each other  
- **different** cuts/words from the original live listen  

**Conclusion:** It is not “the model randomly changes every time.”  
Replay, under its normal pacing, always does the same (wrong-vs-live) thing.  
Live did something different once, with the same audio bytes.

### 4. Why `is_endpoint` can say yes at different times (and what to fix)

`is_endpoint` is a **dumb threshold** on one number decode maintains:
**how many blank tokens in a row** (× frame size → “trailing silence”
seconds). It does not hear the mic and does not use wall-clock.

So if it answers differently with the same PCM, **decode’s blank counter
differed**. Same audio in is supposed to mean same blanks out; Replay×2
shows that path *can* be stable; live vs Replay shows under live conditions
those blank counts are **not** matching Replay’s. Saying “it told us
differently” is incomplete — the real statement is: **greedy blank/letter
choices after encode are not matching for the same PCM between live and
Replay.**

Also in *our* code: if `is_endpoint` is true but hypothesis is still empty,
we **`reset` without logging `E`**. That wipes encoder/decoder state and can
amplify an early blank mismatch into a whole different session after.

**Fix lanes (pick one; stop circling):**

1. Log blank count after every `decode` — see first live≠Replay divergence.  
2. **Tempted: ditch model `is_endpoint`** — **done in tree:** 
   `pcm_quiet_endpoint()` on PCM (~1.2 s below peak floor 0.02);
   `enable_endpoint = 0`. Re-test live → paced Replay; `E` should match.
3. Replay-only: force resets at live `E` offsets (debug aid).

### If we ditch `is_endpoint` (lane 2) — implemented

`pcm_quiet_endpoint()`: peak &lt; 0.02 accumulates; commit after ~1.2 s quiet.
Sherpa `enable_endpoint = 0`. Reinstall / new listen → paced Replay; diff `E`.

### 5. What we are not chasing anymore

- Tiny timing skew (~13 ms) between Replay and the saved timestamps  
- Model-blank `is_endpoint` as the split rule  
- More wording archaeology on each miss once `E` already disagrees  

---

## Next

- Install build; new listen → paced Replay; confirm `E` lines match.  
- Tune `QUIET_FLOOR` / `QUIET_SAMPLES` if splits feel early/late.

---

## What sherpa’s `IsEndpoint` actually does (source on disk)

From `/home/alan/git/sherpa-onnx/sherpa-onnx/csrc/endpoint.cc` +
`online-recognizer-transducer-nemo-impl.h`:

**The cut function itself is not random.** It only looks at three numbers
derived from the decode so far:

1. How much audio has been processed (frame count × 10 ms)  
2. How long the **trailing “blank” run** is (model kept saying “no new
   letter”)  
3. Our three rule thresholds  

“Silence” here does **not** mean mic energy or wall-clock pause. It means:
**the greedy decoder has been emitting blank tokens** for long enough, in
**audio frames**.

Our levers (set in `Transcriber.load_model`):

| Lever | Our value | Meaning |
| --- | --- | --- |
| `enable_endpoint` | on | cuts enabled |
| `rule1` trailing | **2.4 s** | cut after this much trailing blank even with little/no text |
| `rule2` trailing | **1.2 s** | cut after this much trailing blank once there is real text |
| `rule3` utterance | **300 s** | max length force-cut (effectively off for normal dictation) |
| `blank_penalty` | **0.8** | makes blanks *less* attractive in greedy search → changes how fast trailing blanks grow |
| `decoding_method` | greedy | token/blank choices |
| `num_threads` | 1 | ORT threads |

So if live and Replay feed the **same** audio but get **different** `E`
cuts, `IsEndpoint` is not “rolling dice” — the **inputs** to it differed
(different trailing-blank count and/or frames at the moment we asked). Those
inputs come from the neural net + greedy blank decisions. That is the layer
to explain next (why blanks diverge for the same PCM).

---

## Evidence snapshot (`081216`)

| | Live | Replay run 1 | Replay run 2 |
| --- | --- | --- | --- |
| Audio checksums | — | = live | = live |
| Cut marks (`E`) | A | B | B (= run 1, ≠ live) |
| Words | live `.txt` | ≠ live | = run 1 |

Cut offsets (samples):  
live `69760, 159360, 284800, …`  
replay `73440, 163040, 306400, …`

---

## Notes

- Trust feedlog `E` lines over `.endpoints` if they disagree slightly (logging
  race on live).  
- Prefer debug fields kept in memory then saved, rather than inventing extra
  sidecars or packing stamps only at write time (follow-up cleanup).
