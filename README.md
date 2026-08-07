# ibus-sherpa-onnx

Local streaming speech-to-text as an **IBus** input method, via **sherpa-onnx** (Nemotron).

## Demo

<video src="https://github.com/user-attachments/assets/02104d53-0d63-4204-8baa-2e6bfe6a7c2f" controls width="100%"></video>

## Install

Packages are on [GitHub Releases](https://github.com/roojs/ibus-sherpa-onnx/releases). You also need the sherpa runtime from [libsherpa-onnx releases](https://github.com/roojs/sherpa-onnx/releases).

### Debian / Ubuntu

Use **`dpkg -i`** for local `.deb` files (not `apt install …/path.deb`).

```bash
sudo dpkg -i libsherpa-onnx-c-api1_*.deb
sudo dpkg -i ibus-sherpa-onnx_*.deb
ibus-setup-sherpa-onnx
```

```bash
sudo dpkg -r ibus-sherpa-onnx   # uninstall
ibus restart                    # drop the running engine from the session
```

### Fedora

```bash
sudo dnf install ./libsherpa-onnx-c-api-*.x86_64.rpm
sudo dnf install ./ibus-sherpa-onnx-*.x86_64.rpm
ibus-setup-sherpa-onnx
```

Skip `*debuginfo*` / `*debugsource*` / `*-devel*` RPMs unless you are building from source.

```bash
sudo dnf remove ibus-sherpa-onnx
ibus restart
```

### After install

`ibus-setup-sherpa-onnx` downloads a speech model (~440 MB), installs it via polkit, makes Sherpa the active IME, and restarts IBus.

Focus a text field and toggle with **Ctrl+Shift+Space**. Super+Space switches away/back if you want.

Model weights are not in the package. Settings: `~/.config/ibus-sherpa-onnx/settings.ini`.

Build from source: **[BUILD.md](BUILD.md)**. Releases: edit **`CHANGELOG`**, then run **`scripts/release.sh`** (tags `vX.Y.Z` and pushes; CI builds `.deb` / `.rpm`).

## Artificial Intelligence Usage

This project was developed with the assistance of artificial intelligence.

- Product design and code design were done by the author
- AI’s main role was writing implementation for review
- Most of the coding was performed by AI
- Code was then reviewed, revised, and approved by the author
- Every line of application code was reviewed and approved by the author
- Limited exceptions apply mainly to the build system
