# ibus-sherpa-onnx

Vala proof-of-concept: local streaming speech-to-text via **sherpa-onnx** (Nemotron).

**Main path (in progress):** an **IBus** input-method engine so dictation goes into the focused app — see [`docs/plans/0.3-vala-ibus-sherpa-onnx.md`](docs/plans/0.3-vala-ibus-sherpa-onnx.md).

**Also available:** CLI stdout demo (`src/cli/`), and a **sideline** GTK composer window (`src/gtk/`).

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
./build/ibus-engine-sherpa-onnx      # IBus engine (needs ~/.config/ibus-sherpa-onnx/model)
./build/sherpa-onnx-mic              # sideline stdout CLI (src/cli/)
./build/sherpa-onnx-gtk              # sideline GTK composer demo (src/gtk/)
```

Model for the IBus engine (directory or symlink):

```bash
mkdir -p ~/.config/ibus-sherpa-onnx
ln -sfn "$PWD/models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25" \
  ~/.config/ibus-sherpa-onnx/model
```

Optional longer-context model (same size, higher latency, often more accurate):

```bash
./scripts/fetch-nemotron-model.sh 1120
./build/sherpa-onnx-mic models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-1120ms-int8-2026-04-25
```

Debian packaging / GNOME input-source install is plan 0.3 Phase 3.

## Plans

- Stage 1 (stdout): [`docs/plans/0.1-vala-sherpa-stdout-poc.md`](docs/plans/0.1-vala-sherpa-stdout-poc.md)
- Stage 2 (GTK composer sideline): [`docs/plans/0.2-vala-gtk-composer.md`](docs/plans/0.2-vala-gtk-composer.md)
- Stage 3 (IBus engine — main path): [`docs/plans/0.3-vala-ibus-sherpa-onnx.md`](docs/plans/0.3-vala-ibus-sherpa-onnx.md)

## Artificial Intelligence Usage

This project was developed with the assistance of artificial intelligence.

- Product design and code design were done by the author
- AI’s main role was writing implementation for review
- Most of the coding was performed by AI
- Code was then reviewed, revised, and approved by the author
- Every line of application code was reviewed and approved by the author
- Limited exceptions apply mainly to the build system
