# Fedora package for the IBus sherpa-onnx speech engine.
#
# CI (and local) build after installing libsherpa-onnx-c-api(-devel) from
# https://github.com/roojs/sherpa-onnx/releases

Name:           ibus-sherpa-onnx
Version:        0.2.0
Release:        1%{?dist}
Summary:        IBus speech dictation engine using sherpa-onnx
License:        LGPLv3+
URL:            https://github.com/roojs/ibus-sherpa-onnx
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  vala
BuildRequires:  glib2-devel
BuildRequires:  ibus-devel
BuildRequires:  gstreamer1-devel
BuildRequires:  gstreamer1-plugins-base-devel
BuildRequires:  gtk4-devel
BuildRequires:  libadwaita-devel
BuildRequires:  libsoup3-devel
BuildRequires:  libarchive-devel
BuildRequires:  libicu-devel
BuildRequires:  libgee-devel
BuildRequires:  libsherpa-onnx-c-api-devel
BuildRequires:  chrpath

Requires:       ibus
Requires:       libsherpa-onnx-c-api
Requires:       gstreamer1-plugins-good
Requires:       gstreamer1-plugins-base
Requires:       gstreamer1-plugins-bad-free
Requires:       gstreamer1-plugin-pipewire
Requires:       polkit
Requires:       gtk3
Requires:       gtk4
Requires:       libadwaita
Requires:       libsoup3
Requires:       libarchive

%description
Local streaming speech-to-text as an IBus input method, powered by
sherpa-onnx (Nemotron online transducer).

Install this package, then run ibus-setup-sherpa-onnx to pick a model.
Preferences downloads/extracts the model, installs it under
/usr/share/ibus-sherpa-onnx/models/ via polkit, and activates the IME.

ASR model weights are not included (~440 MB); download via Preferences.

%prep
%autosetup -n %{name}-%{version}

%build
%meson
%meson_build

%install
%meson_install
# sherpa-onnx.pc injects -Wl,-rpath,/usr/lib; Fedora check-rpaths rejects that.
chrpath --delete %{buildroot}%{_libexecdir}/ibus-engine-sherpa-onnx || :
chrpath --delete %{buildroot}%{_libexecdir}/ibus-setup-sherpa-onnx || :

%postun
if [ "$1" -eq 0 ]; then
	echo "ibus-sherpa-onnx: run 'ibus restart' (or log out) so the session drops the engine."
fi

%files
%license debian/copyright
%doc README.md CHANGELOG
%{_libexecdir}/ibus-engine-sherpa-onnx
%{_libexecdir}/ibus-setup-sherpa-onnx
%{_libexecdir}/ibus-sherpa-onnx-install-model
%{_bindir}/ibus-setup-sherpa-onnx
%{_datadir}/ibus/component/sherpa-onnx.xml
%{_datadir}/applications/ibus-setup-sherpa-onnx.desktop
%{_datadir}/ibus-sherpa-onnx/
%{_datadir}/polkit-1/actions/org.roojs.ibus-sherpa-onnx.policy

%changelog
* Fri Aug 07 2026 Alan Knowles <alan@roojs.com> - 0.1.0-1
- Initial Fedora package.
