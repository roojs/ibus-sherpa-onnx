project(
  'ibus-sherpa-onnx',
  ['c', 'vala'],
  version: '0.2.0',
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
gnome = import('gnome')

catalog_resources = gnome.compile_resources(
  'ibus-sherpa-onnx-resources',
  'resources/gresources.xml',
  source_dir: 'resources',
  c_name: 'ibus_sherpa_onnx_resources',
)

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
    'src/Application.vala',
    'src/Engine.vala',
    'src/Transcriber.vala',
    'src/Config.vala',
    'src/Models.vala',
    catalog_resources,
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
  install: true,
  install_dir: get_option('libexecdir'),
)

install_data(
  'data/sherpa-onnx.xml',
  install_dir: get_option('datadir') / 'ibus' / 'component',
)

install_data(
  'scripts/cli-fetch-nemotron-model.sh',
  install_dir: get_option('datadir') / 'ibus-sherpa-onnx',
  install_mode: 'rwxr-xr-x',
)

libexec_abs = get_option('prefix') / get_option('libexecdir')

install_data(
  'scripts/install-model.sh',
  rename: 'ibus-sherpa-onnx-install-model',
  install_dir: get_option('libexecdir'),
  install_mode: 'rwxr-xr-x',
)

policy_conf = configuration_data()
policy_conf.set('LIBEXECDIR', libexec_abs)
configure_file(
  input: 'data/polkit/org.roojs.ibus-sherpa-onnx.policy.in',
  output: 'org.roojs.ibus-sherpa-onnx.policy',
  configuration: policy_conf,
  install: true,
  install_dir: get_option('datadir') / 'polkit-1' / 'actions',
)

install_data(
  'data/checksums/sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25.sha256',
  'data/checksums/sherpa-onnx-nemotron-speech-streaming-en-0.6b-1120ms-int8-2026-04-25.sha256',
  install_dir: get_option('datadir') / 'ibus-sherpa-onnx' / 'checksums',
)

# Sideline: CLI stdout mic smoke test (off by default; not packaged).
if get_option('cli')
  executable(
    'sherpa-onnx-mic',
    [
      'src/cli/main.vala',
      'src/Transcriber.vala',
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
endif

gtk_dep = dependency('gtk4')
adw_dep = dependency('libadwaita-1')
soup_dep = dependency('libsoup-3.0')
archive_dep = dependency('libarchive')
# Hand-written binding: src/icu-i18n.vapi + src/Icu.vala (UTF-8 API).
icu_dep = dependency('icu-i18n')
gee_dep = dependency('gee-0.8')

# IBus Preferences / component <setup> (RooTerm Dialog naming: Preferences, Row*).
executable(
  'ibus-setup-sherpa-onnx',
  [
    'src/setup/main.vala',
    'src/Config.vala',
    'src/Models.vala',
    'src/Icu.vala',
    'src/setup/Row.vala',
    'src/setup/RowKeySelect.vala',
    'src/setup/RowSwitch.vala',
    'src/setup/RowSelectModel.vala',
    'src/setup/RowComboLanguage.vala',
    'src/setup/ModelDownload.vala',
    'src/setup/Preferences.vala',
    catalog_resources,
  ],
  dependencies: [
    glib_dep,
    gobject_dep,
    gio_unix_dep,
    gtk_dep,
    adw_dep,
    soup_dep,
    archive_dep,
    icu_dep,
    gee_dep,
    ibus_dep,
    m_dep,
  ],
  install: true,
  install_dir: get_option('libexecdir'),
)

# PATH wrapper → gtk-launch (activation token); real binary stays in libexec.
install_data(
  'scripts/ibus-setup-sherpa-onnx',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

install_data(
  'data/ibus-setup-sherpa-onnx.desktop',
  install_dir: get_option('datadir') / 'applications',
)

install_emptydir(get_option('datadir') / 'ibus-sherpa-onnx' / 'models')

# Sideline: GTK composer demo (off by default; not packaged).
if get_option('gtk_demo')
  executable(
    'sherpa-onnx-gtk',
    [
      'src/gtk/main.vala',
      'src/gtk/ComposerInput.vala',
      'src/gtk/ScrolledView.vala',
      'src/Transcriber.vala',
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
endif
