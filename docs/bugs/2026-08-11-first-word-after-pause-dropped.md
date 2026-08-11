# First word after pause dropped

**Status:** ⏳ open — **diagnose before splice**  
**Reported:** 2026-08-11  
**Package:** `ibus-sherpa-onnx` (engine / Transcriber)  
**Evidence:** `~/.cache/ibus-sherpa-onnx/debug/2026-08-11/213338.{wav,txt,out.txt}`

> Emoji legend: RooTerm `docs/guide-to-writing-plans.md`.  
> Process: RooTerm `docs/bug-fix-process.md`.

## Problem (observed)

- 🔷 After a mid-listen pause, the **first word of the next phrase** can be missing from both live commit and Replay.
- 🔷 Concrete (213338): after the first pause the WAV has speech that should read **“pair devices over Wi Fi…”**; original `.txt` and Replay `.out.txt` both start that line with **“Devices…”** — no leading **“pair”**.
- 🔷 User also reports the same class of miss for short onsets like **“now”** after quiet.

## Facts so far (213338)

- 🔷 Same miss on **live** and **Replay** → not mic-only; path is accept/decode/endpoint/reset (or the model).
- 🔷 Silence gap before that line ≈ **1.2s** (around rule2). Speech energy returns right as that gap ends.
- 🔷 First burst after the gap (“pair”-window) RMS ≈ following “Devices”-window — **not** an obvious quiet-onset / AGC story.

## Open (do not treat as settled)

- 💩 Exact sample index where endpoint fired vs where “pair” begins — need a traced Replay (log endpoint time + result text), not a guessed timeline.
- 💩 Whether “pair” was ever in a partial and then wiped on reset, vs never decoded.
- 💩 Whether the model alone drops it even **without** our reset (e.g. feed the post-pause slice as a fresh stream).
- 💩 Chunk / left-context behaviour of the **1120ms** Nemotron pack on a hard reset.

## Fix direction (careful — no blunt re-feed)

**🚫** Do **not** re-inject the last ~1s of PCM after every endpoint. That double-feeds audio already given to `accept_waveform`, risks duplicate text, and papers over the real cut point.

If we must touch the stream:

- 🔷 **Cut only at a known read boundary** — e.g. samples not yet consumed past the endpoint decision, or an explicit slice start after the committed utterance — never a fuzzy “recent tail”.
- 🔷 **No double inject** — anything re-primed must be removed from the forward path (or never left on the forward path).
- 🔷 Prefer **small, deliberate padding** (e.g. a few ms of silence or model-required left context) over splicing real speech twice, if padding is what the pack needs.
- 🔷 Prove on 213338 Replay: Output line becomes **“pair devices…”** (or equivalent) without duplicating the previous line’s tail.

## Next checks

Build CLI: `meson setup build -Dcli=true && ninja -C build sherpa-onnx-mic`

```bash
WAV=~/.cache/ibus-sherpa-onnx/debug/2026-08-11/213338.wav
MODEL=/usr/share/ibus-sherpa-onnx/models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-1120ms-int8-2026-04-25

# Full file — expect “Devices…” without “pair” after first endpoint
./build/sherpa-onnx-mic --debug --wav "$WAV" --stats "$MODEL" 2>full.trace | tee full.out

# Around the miss
./build/sherpa-onnx-mic --debug --wav "$WAV" --from 5 --to 12 "$MODEL" 2>mid.trace | tee mid.out

# Fresh stream on post-pause only (no prior utterance)
./build/sherpa-onnx-mic --debug --wav "$WAV" --from 6.4 --to 10 "$MODEL" 2>onset.trace | tee onset.out
```

Compare: does onset-only recover “pair”? Does full-file still drop it after the first endpoint? That answers “reset/context” vs “model never hears pair” **before** any splice/padding fix.

With `--debug`, `GLib.debug` traces (`#chunk` / `#partial` / `#endpoint`) go to stderr (and always to `~/.cache/ibus-sherpa-onnx/sherpa-onnx-mic.debug.log`).
