# GNOME Settings ⋯ Preferences does nothing for language engines

**Status:** ✔️ DONE  

**Reported from:** Keyboard → Input Sources → ⋯ on secondary Sherpa engines  
**Package:** `ibus-sherpa-onnx` 0.2.0

## Problem

🔷 Bare `sherpa-onnx` opened Preferences from Settings. Language-specific
engines (`sherpa-onnx-es-ES`, `sherpa-onnx-en-GB`, …) showed ⋯ but choosing
Preferences did nothing.

## Evidence

- gnome-control-center resolves setup via `ibus-setup-%s.desktop` where `%s`
  is the IBus engine name (`cc_input_source_ibus_get_app_info`).
- We only ship `ibus-setup-sherpa-onnx.desktop`.
- `ibus-setup-sherpa-onnx-es-ES.desktop` etc. are missing; pinyin ships one
  desktop per engine (`ibus-setup-pinyin.desktop`, `ibus-setup-bopomofo.desktop`).
- Component `<setup>` paths are present for every engine — Settings does not
  use those for the ⋯ menu.

## What not to chase

🚫 GNOME Shell `keyboard.js` / `mru-sources` / `ibus engine` for this report.
🚫 Generating dozens of `.desktop` copies from meson/`awk`/python at build time.

## Fix (in tree)

✔️ On Preferences `install()`, write
`~/.local/share/applications/ibus-setup-<engine>.desktop` from GResource
template `resources/ibus-setup-engine.desktop.in` (`@ENGINE@` replaced).
Bare `sherpa-onnx` stays packaged under `/usr/share`.
