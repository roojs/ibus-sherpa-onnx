# gtk-speechtotext-poc

Vala proof-of-concept: local streaming speech-to-text via **sherpa-onnx** (Nemotron). Speak into the mic; the transcript prints on **stdout** (partials on one line, a newline when an endpoint fires).

## Demo

<video src="https://github.com/user-attachments/assets/21f1c392-2352-4e1a-8833-860ccb753cc4" controls width="100%"></video>

## What you need

1. **apt packages** (build this PoC + run it; includes sherpa’s runtime dep ONNX Runtime):

```bash
sudo apt-get install -y \
  valac meson ninja-build pkg-config \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-base \
  gstreamer1.0-pulseaudio gstreamer1.0-pipewire \
  libonnxruntime1.21 libonnxruntime-dev
```

2. **sherpa-onnx `.deb`s** from [roojs/sherpa-onnx releases](https://github.com/roojs/sherpa-onnx/releases) — install both:

- `libsherpa-onnx-c-api1`
- `libsherpa-onnx-c-api-dev`

```bash
sudo apt install ./libsherpa-onnx-c-api1_*.deb ./libsherpa-onnx-c-api-dev_*.deb
```

3. **ASR model weights** (~440 MB download / ~630 MB on disk) — via the script below. The `560ms` / `1120ms` names are chunk latency, not download size.

## Build & run

```bash
./scripts/fetch-nemotron-model.sh   # default: 560 ms chunk
meson setup build && ninja -C build
./build/stt-poc
```

Optional longer-context model (same size, higher latency, often more accurate):

```bash
./scripts/fetch-nemotron-model.sh 1120
./build/stt-poc models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-1120ms-int8-2026-04-25
```

## Plan

See [`docs/plans/0.1-vala-sherpa-stdout-poc.md`](docs/plans/0.1-vala-sherpa-stdout-poc.md).
