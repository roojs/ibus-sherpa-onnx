# ibus-sherpa-onnx

Talk into your microphone; text appears in the app you are using. Works offline on Linux (IBus + sherpa-onnx / Nemotron).

**Distro note:** These packages target **Ubuntu 25.04** (and similar). Older Ubuntu (e.g. 24.04) does not have the ONNX packages in the archive.

## Demo

<video src="https://github.com/user-attachments/assets/02104d53-0d63-4204-8baa-2e6bfe6a7c2f" controls width="100%"></video>

## Install on Ubuntu / Debian

Follow every step in order. Do not skip ahead.

### Step 1 — Install system packages

Open a terminal and run:

```bash
sudo apt update
sudo apt install \
  ibus \
  libonnxruntime1.21 \
  libgtk-4-1 \
  libadwaita-1-0 \
  libsoup-3.0-0 \
  libjson-glib-1.0-0 \
  libarchive13t64 \
  libibus-1.0-5 \
  libgstreamer1.0-0 \
  libgstreamer-plugins-base1.0-0 \
  gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad \
  gstreamer1.0-pipewire \
  pkexec \
  polkitd \
  libgtk-3-bin
```

Wait until that finishes with no errors before continuing.

### Step 2 — Download the speech library

1. Open this page in your browser:  
   https://github.com/roojs/sherpa-onnx/releases/latest
2. Scroll to **Assets**.
3. Click to download **exactly** this file:  
   `libsherpa-onnx-c-api1_1.13.4-roojs3_amd64.deb`
4. **Do not** download `libsherpa-onnx-c-api-dev_...`, `...dbgsym...`, or any `.ddeb`.
5. Save it in your **Downloads** folder.

### Step 3 — Download this input method

1. Open:  
   https://github.com/roojs/ibus-sherpa-onnx/releases/latest
2. Under **Assets**, download **exactly** this file:  
   `ibus-sherpa-onnx_0.1.0-1_amd64.deb`
3. Save it in the **same Downloads** folder.

You should now have **two** `.deb` files in Downloads.

### Step 4 — Install the two downloads (library first)

In the terminal:

```bash
cd ~/Downloads
sudo dpkg -i libsherpa-onnx-c-api1_1.13.4-roojs3_amd64.deb
sudo dpkg -i ibus-sherpa-onnx_0.1.0-1_amd64.deb
```

Both commands should finish without “dependency problems”.  
If either fails, go back to **Step 1** and make sure every package installed, then run Step 4 again.

### Step 5 — Choose a speech model (one-time setup)

```bash
ibus-setup-sherpa-onnx
```

A window opens. Pick a model and close the window.  
It downloads about **440 MB**, may ask for your password, turns Sherpa on as your input method, and restarts IBus.

### Step 6 — Use it

1. Click in any text field (browser, editor, chat, ...).
2. Press **Ctrl+Shift+Space** to start listening.
3. Speak.
4. Press **Ctrl+Shift+Space** again (or start typing) to stop.

**Super+Space** still switches between input methods if you have more than one.

---

## Install on Fedora

### Step 1 — Install system packages

```bash
sudo dnf install \
  ibus \
  onnxruntime \
  gtk3 \
  gtk4 \
  libadwaita \
  libsoup3 \
  json-glib \
  libarchive \
  gstreamer1-plugins-base \
  gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free \
  gstreamer1-plugin-pipewire \
  polkit
```

### Step 2 — Download the speech library

1. Open: https://github.com/roojs/sherpa-onnx/releases/latest  
2. Under **Assets**, download **exactly** this file:  
   `libsherpa-onnx-c-api-1.13.4-roojs3.fc44.x86_64.rpm`  
3. **Do not** download `...-devel...`, `...debuginfo...`, or `...debugsource...` files.  
4. Save in **Downloads**.

### Step 3 — Download this input method

1. Open: https://github.com/roojs/ibus-sherpa-onnx/releases/latest  
2. Download **exactly** this file:  
   `ibus-sherpa-onnx-0.1.0-1.fc44.x86_64.rpm`  
3. Save in **Downloads**.

### Step 4 — Install both (library first)

```bash
cd ~/Downloads
sudo dnf install ./libsherpa-onnx-c-api-1.13.4-roojs3.fc44.x86_64.rpm
sudo dnf install ./ibus-sherpa-onnx-0.1.0-1.fc44.x86_64.rpm
```

### Step 5 — Choose a speech model

```bash
ibus-setup-sherpa-onnx
```

### Step 6 — Use it

**Ctrl+Shift+Space** to start/stop listening in a text field.

---

## Uninstall

**Ubuntu / Debian:**

```bash
sudo dpkg -r ibus-sherpa-onnx
ibus restart
```

**Fedora:**

```bash
sudo dnf remove ibus-sherpa-onnx
ibus restart
```

(`ibus restart` clears the old engine from your current login session.)

---

## Notes

- Speech models are **not** inside the packages; the setup window downloads them.
- Settings: `~/.config/ibus-sherpa-onnx/settings.ini`.
- Building from source: [BUILD.md](BUILD.md).

## Artificial Intelligence Usage

This project was developed with the assistance of artificial intelligence.

- Product design and code design were done by the author
- AI’s main role was writing implementation for review
- Most of the coding was performed by AI
- Code was then reviewed, revised, and approved by the author
- Every line of application code was reviewed and approved by the author
- Limited exceptions apply mainly to the build system
