project(
  'gtk-speechtotext-poc',
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
m_dep = meson.get_compiler('c').find_library('m')

# Hand-written binding: src/sherpa-onnx.vapi (satisfies --pkg from sherpa_dep).
add_project_arguments(
  '--vapidir=' + meson.current_source_dir() / 'src',
  language: 'vala',
)

executable(
  'stt-poc',
  [
    'src/main.vala',
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
