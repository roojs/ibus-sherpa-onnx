# ibus-sherpa-onnx

Local streaming speech-to-text as an **IBus** input method, via **sherpa-onnx** (Nemotron).

Plan: [`docs/plans/0.3-vala-ibus-sherpa-onnx.md`](docs/plans/0.3-vala-ibus-sherpa-onnx.md).

## Demo

<video src="https://github.com/user-attachments/assets/21f1c392-2352-4e1a-8833-860ccb753cc4" controls width="100%"></video>

## Install

Use **`dpkg -i`** for local `.deb` files (not `apt install …/path.deb`).

1. [libsherpa-onnx](https://github.com/roojs/sherpa-onnx/releases) runtime:

```bash
sudo dpkg -i libsherpa-onnx-c-api1_*.deb
```

2. This engine (after build, the package is `../ibus-sherpa-onnx_*.deb`):

```bash
sudo dpkg -i ../ibus-sherpa-onnx_*.deb

# User install (default): ~/.config/ibus-sherpa-onnx/model
./scripts/fetch-nemotron-model.sh
# Or system-wide: sudo ./scripts/fetch-nemotron-model.sh
#   → /usr/share/ibus-sherpa-onnx/model

ibus restart

gsettings set org.gnome.desktop.input-sources sources \
  "[('xkb', 'us'), ('ibus', 'sherpa-onnx')]"
```

Switch to **Sherpa ONNX** (Super+Space), focus a text field, toggle with **Ctrl+Shift+Space**.

```bash
sudo dpkg -r ibus-sherpa-onnx   # uninstall
```

Model weights are not in the `.deb` (~440 MB). Fetch chooses the tree by euid (user config vs `/usr/share/…`) and sets the `model` symlink — no path env vars. Prefs: `~/.config/ibus-sherpa-onnx/settings.ini` (hotkey, notifications, preedit-animation).

## Build from source

Build-deps from the archive still use apt; the resulting package is installed with dpkg as above.

```bash
sudo apt-get install -y \
  valac meson ninja-build pkg-config debhelper devscripts \
  libibus-1.0-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-base \
  gstreamer1.0-pulseaudio gstreamer1.0-pipewire \
  libonnxruntime1.21 libonnxruntime-dev

sudo dpkg -i libsherpa-onnx-c-api1_*.deb libsherpa-onnx-c-api-dev_*.deb
meson setup build && ninja -C build
dpkg-buildpackage -us -uc -b   # → ../ibus-sherpa-onnx_*.deb
```

Sideline demos (not packaged): `./build/sherpa-onnx-mic`, `./build/sherpa-onnx-gtk`.

GitHub Actions builds the `.deb` on `v*` tags (`.github/workflows/release.yml`). RPM later.

## Plans

- [`0.1-vala-sherpa-stdout-poc.md`](docs/plans/0.1-vala-sherpa-stdout-poc.md)
- [`0.2-vala-gtk-composer.md`](docs/plans/0.2-vala-gtk-composer.md)
- [`0.3-vala-ibus-sherpa-onnx.md`](docs/plans/0.3-vala-ibus-sherpa-onnx.md)
- [`0.4-prefs-feedback-models.md`](docs/plans/0.4-prefs-feedback-models.md) — prefs, listening feedback, system model download

## Artificial Intelligence Usage

This project was developed with the assistance of artificial intelligence.

- Product design and code design were done by the author
- AI’s main role was writing implementation for review
- Most of the coding was performed by AI
- Code was then reviewed, revised, and approved by the author
- Every line of application code was reviewed and approved by the author
- Limited exceptions apply mainly to the build system
