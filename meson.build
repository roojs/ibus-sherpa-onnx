project(
  'ibus-sherpa-onnx',
  ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 1.0.0',
  default_options: [
    'warning_level=1',
    'buildtype=debugoptimized',
  ],
)

glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
gio_unix_dep = dependency('gio-unix-2.0')
gst_dep = dependency('gstreamer-1.0')
gst_app_dep = dependency('gstreamer-app-1.0')
sherpa_dep = dependency('sherpa-onnx')
ibus_dep = dependency('ibus-1.0')
m_dep = meson.get_compiler('c').find_library('m')

# Hand-written binding: src/sherpa-onnx.vapi (satisfies --pkg from sherpa_dep).
add_project_arguments(
  '--vapidir=' + meson.current_source_dir() / 'src',
  language: 'vala',
)

# Main product: IBus engine (entry: src/main.vala).
executable(
  'ibus-engine-sherpa-onnx',
  [
    'src/main.vala',
    'src/application.vala',
    'src/engine.vala',
    'src/transcriber.vala',
  ],
  dependencies: [
    glib_dep,
    gobject_dep,
    gio_unix_dep,
    gst_dep,
    gst_app_dep,
    sherpa_dep,
    ibus_dep,
    m_dep,
  ],
  vala_args: [
    '--pkg=posix',
  ],
  install: false,
)

# Sideline: CLI stdout mic smoke test.
executable(
  'sherpa-onnx-mic',
  [
    'src/cli/main.vala',
    'src/transcriber.vala',
  ],
  dependencies: [
    glib_dep,
    gobject_dep,
    gio_unix_dep,
    gst_dep,
    gst_app_dep,
    sherpa_dep,
    m_dep,
  ],
  vala_args: [
    '--pkg=posix',
  ],
  install: false,
)

gtk_dep = dependency('gtk4')
adw_dep = dependency('libadwaita-1')

# Sideline: GTK composer demo.
executable(
  'sherpa-onnx-gtk',
  [
    'src/gtk/gtk_main.vala',
    'src/gtk/ComposerInput.vala',
    'src/gtk/ScrolledView.vala',
    'src/transcriber.vala',
  ],
  dependencies: [
    glib_dep,
    gobject_dep,
    gio_unix_dep,
    gst_dep,
    gst_app_dep,
    sherpa_dep,
    gtk_dep,
    adw_dep,
    m_dep,
  ],
  vala_args: [
    '--pkg=posix',
  ],
  install: false,
)
