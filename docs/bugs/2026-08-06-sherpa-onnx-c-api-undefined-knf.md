# libsherpa-onnx-c-api: undefined `knf::*` at link and runtime

**Status:** ✔️ FIXED (packaging rebuilt/reinstalled) — await user ✅  
**Reported from:** `ibus-sherpa-onnx` Vala stdout PoC  
**Package:** `libsherpa-onnx-c-api1` / `-dev` `1.13.4-1`

## Problem

🔷 Consumers linking `pkg-config --libs sherpa-onnx` hit undefined `knf::*` at link time, and runtime `symbol lookup error` on `libsherpa-onnx-c-api.so`.

## Evidence (before)

- No `knf` in `NEEDED`; `libkaldi-native-fbank-core.so` in build tree had **0** dynamic exports
- Likely cause: `debian/cmake/kaldi-native-fbank.cmake` non-CACHE `set(BUILD_SHARED_LIBS OFF)` + hidden visibility

## Verification (after rebuild/reinstall)

✔️ `nm -D …/libsherpa-onnx-c-api.so | rg ' U .*knf'` → empty  
✔️ `meson setup build && ninja -C build` → links clean  
✔️ `./build/sherpa-onnx-mic` → prints `Listening … Model: models/sherpa-onnx-nemotron-…` (no symbol lookup error; Ctrl+C / timeout exits cleanly)

## Next

⏳ User ✅ if mic transcription looks good on a longer interactive run:

```bash
./build/sherpa-onnx-mic
```
