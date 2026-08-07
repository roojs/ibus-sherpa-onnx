# ibus-sherpa-onnx

Local streaming speech-to-text as an **IBus** input method, via **sherpa-onnx** (Nemotron).

## Demo

<video src="https://github.com/user-attachments/assets/21f1c392-2352-4e1a-8833-860ccb753cc4" controls width="100%"></video>

## Install

Use **`dpkg -i`** for local `.deb` files (not `apt install …/path.deb`).

1. Runtime from [libsherpa-onnx releases](https://github.com/roojs/sherpa-onnx/releases):

```bash
sudo dpkg -i libsherpa-onnx-c-api1_*.deb
```

2. This engine from [ibus-sherpa-onnx releases](https://github.com/roojs/ibus-sherpa-onnx/releases) (or a `.deb` you were given):

```bash
sudo dpkg -i ibus-sherpa-onnx_*.deb
```

3. Pick a speech model (downloads ~440 MB, installs via polkit, makes Sherpa the active IME, restarts IBus):

```bash
ibus-setup-sherpa-onnx
```

Focus a text field and toggle with **Ctrl+Shift+Space**. Super+Space switches away/back if you want.

```bash
sudo dpkg -r ibus-sherpa-onnx   # uninstall
```

Model weights are not in the `.deb`. Settings: `~/.config/ibus-sherpa-onnx/settings.ini`.

Build from source: **[BUILD.md](BUILD.md)**.

## Artificial Intelligence Usage

This project was developed with the assistance of artificial intelligence.

- Product design and code design were done by the author
- AI’s main role was writing implementation for review
- Most of the coding was performed by AI
- Code was then reviewed, revised, and approved by the author
- Every line of application code was reviewed and approved by the author
- Limited exceptions apply mainly to the build system
