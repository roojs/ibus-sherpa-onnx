# Building ibus-sherpa-onnx

Local Meson/Ninja build, Debian packaging (`dpkg-buildpackage`), and what GitHub Actions publishes on `v*` tags.

**Distro note:** Build against Ubuntu **25.04 (Plucky)** or similar — `libonnxruntime` and the [roojs/sherpa-onnx](https://github.com/roojs/sherpa-onnx/releases) `.deb`s target that generation. Noble (24.04) lacks those ONNX packages in the archive.

## Dependencies

### Build tools

```bash
sudo apt-get install -y \
  build-essential \
  valac \
  meson \
  ninja-build \
  pkg-config \
  debhelper \
  devscripts \
  fakeroot
```

### Libraries (dev)

From `meson.build` / `debian/control`:

```bash
sudo apt-get install -y \
  libglib2.0-dev \
  libibus-1.0-dev \
  libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev \
  libgtk-4-dev \
  libadwaita-1-dev \
  libsoup-3.0-dev \
  libarchive-dev \
  libonnxruntime-dev
```

### Runtime GStreamer plugins (mic)

Needed to *run* the engine / CLI mic demos (also listed as package `Depends`):

```bash
sudo apt-get install -y \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-base \
  gstreamer1.0-pipewire \
  gstreamer1.0-pulseaudio
```

(`pipewire` **or** `pulseaudio` plugin is enough at package install time.)

Preferences installs models into `/usr/share/…` via polkit (`pkexec` / `polkitd`) — already in the package `Depends`.

### sherpa-onnx (not in the Ubuntu archive)

Download from [roojs/sherpa-onnx releases](https://github.com/roojs/sherpa-onnx/releases):

```bash
sudo dpkg -i libsherpa-onnx-c-api1_*.deb libsherpa-onnx-c-api-dev_*.deb
```

`pkg-config --exists sherpa-onnx` should succeed after that. Runtime package alone is enough to *run* a built engine; `-dev` is required to *compile*.

## Build (developer tree)

```bash
meson setup build
ninja -C build
```

Binaries under `build/`:

| Binary | Packaged? | Role |
| --- | --- | --- |
| `ibus-engine-sherpa-onnx` | yes | IBus engine |
| `ibus-setup-sherpa-onnx` | yes | Preferences / model download |
| `sherpa-onnx-mic` | no | CLI mic → stdout smoke test |
| `sherpa-onnx-gtk` | no | GTK composer demo |

Install into a prefix (optional; for day-to-day prefer the `.deb`):

```bash
ninja -C build install   # honor DESTDIR / --prefix from meson setup
```

Model weights are **not** built or installed by Meson. Use Preferences, or:

```bash
./scripts/fetch-nemotron-model.sh
```

## Debian package

Packaging lives in `debian/` (`debhelper` + Meson via `debian/rules`). Source package name: **`ibus-sherpa-onnx`**.

```bash
# From the repo root, with build-deps + sherpa -dev already installed:
dpkg-buildpackage -us -uc -b
```

Produces `../ibus-sherpa-onnx_*.deb` (and related `.buildinfo` / `.changes`). Install with **`dpkg -i`**, not `apt install …/path.deb`:

```bash
sudo dpkg -i ../ibus-sherpa-onnx_*.deb
```

What the `.deb` ships (see `meson.build` `install:`):

- `/usr/libexec/ibus-engine-sherpa-onnx`
- `/usr/libexec/ibus-setup-sherpa-onnx`
- IBus component XML, setup `.desktop`, fetch script, checksums, empty `models/` dir

Sideline demos (`sherpa-onnx-mic`, `sherpa-onnx-gtk`) are **not** in the package.

Uninstall:

```bash
sudo dpkg -r ibus-sherpa-onnx
```

## GitHub Actions

[`.github/workflows/release.yml`](.github/workflows/release.yml) builds the `.deb` in an `ubuntu:25.04` container:

- On **`v*`** tags: build, upload artifact, publish GitHub Release assets
- **`workflow_dispatch`**: build + artifact only (no release unless tagged)

CI installs archive build-deps, pulls `libsherpa-onnx` `.deb`s from `roojs/sherpa-onnx`, then runs `dpkg-buildpackage -us -uc -b`.

RPM packaging is not set up yet.

## Quick checklist

1. Plucky-class host (or matching container)
2. apt build tools + `-dev` packages above
3. `libsherpa-onnx-c-api1` + `-dev` via `dpkg -i`
4. `meson setup build && ninja -C build` **or** `dpkg-buildpackage -us -uc -b`
5. Install engine `.deb`, fetch/select a model, `ibus restart`
