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

- 🔷 Same miss on **live** and **Replay** (saved that day) → not mic-only; path is accept/decode/endpoint/reset (or the model).
- 🔷 Silence gap before that line ≈ **1.2s** (around rule2). Speech energy returns right as that gap ends.
- 🔷 First burst after the gap (“pair”-window) RMS ≈ following “Devices”-window — **not** an obvious quiet-onset / AGC story.

## CLI re-feed (2026-08-11 evening)

Default `--wav` now uses the same GStreamer Replay path as Browse; `--fast-transcribe` dumps the queue ASAP.

- 🔷 **Could not reproduce the drop** on current code: Replay and fast both say **“Getting pair new devices…”** for the post-pause line (0–12s, three Replay runs).
- 🔷 Live/old Replay text still says **“Devices…”** (no “pair”).
- 🔷 Short cold start `--from 6.4 --to 10` (fast) still said **“New devices…”** — onset-only can lose the first word; that is a different cut than the mid-listen case.

So: audio is on the WAV; today’s engine+Replay is not dropping “pair” on this clip the way the saved session did. Next: find what differed live that day (model pack, endpoint timing, or a since-changed code path), or catch a fresh live miss with `--debug` traces.

## Open (do not treat as settled)

- 💩 What made the **saved** live/Replay drop “pair” if re-Replay now keeps it.
- 💩 Whether “pair” was ever in a partial and then wiped on reset, vs never decoded (need a traced miss).
- 💩 Chunk / left-context behaviour of the **1120ms** Nemotron pack on a hard reset / cold onset.

## Fix direction (careful — no blunt re-feed)

**🚫** Do **not** re-inject the last ~1s of PCM after every endpoint. That double-feeds audio already given to `accept_waveform`, risks duplicate text, and papers over the real cut point.

If we must touch the stream:

- 🔷 **Cut only at a known read boundary** — e.g. samples not yet consumed past the endpoint decision, or an explicit slice start after the committed utterance — never a fuzzy “recent tail”.
- 🔷 **No double inject** — anything re-primed must be removed from the forward path (or never left on the forward path).
- 🔷 Prefer **small, deliberate padding** (e.g. a few ms of silence or model-required left context) over splicing real speech twice, if padding is what the pack needs.
- 🔷 Prove on 213338 Replay: Output line becomes **“pair devices…”** (or equivalent) without duplicating the previous line’s tail.

## Reproduced: “flow” drop (214954, UI Replay log → CLI)

UI Replay (`ibus-setup-sherpa-onnx.debug.log`, stem **214954**) chopped at:

- `#endpoint t=51.712` …chunk…
- `#endpoint t=56.192 text=We should be able to do a testable` ← **no “flow”**
- next speech `#partial t=58.368` Whereby…

Energy bump ~**55.8–56.2s** sits right at that endpoint (likely “flow”).

```bash
WAV=~/.cache/ibus-sherpa-onnx/debug/2026-08-11/214954.wav
MODEL=/usr/share/ibus-sherpa-onnx/models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-1120ms-int8-2026-04-25

# Same window as the UI miss → no “flow”
./build/sherpa-onnx-mic --debug --wav "$WAV" --from 51.7 --to 58 "$MODEL"
# → We should be able to do a testable

# A bit more audio after → “flow” appears
./build/sherpa-onnx-mic --debug --wav "$WAV" --from 50 --to 60 "$MODEL"
# → … testable flow whereby …
```

So this one **is** CLI-reproducible from the log splice times: endpoint commits **before** “flow” is in the text; stretching `--to` past the next phrase recovers the word.

## CLI / UI traces

- CLI: `./build/sherpa-onnx-mic --debug --wav …` → stderr + `sherpa-onnx-mic.debug.log`
- Browse Replay: `#replay` / `#partial` / `#endpoint` → `~/.cache/ibus-sherpa-onnx/ibus-setup-sherpa-onnx.debug.log`  
  After a UI run, say the stem time; use `#endpoint` `t=` values as `--from` / `--to` on the CLI.
