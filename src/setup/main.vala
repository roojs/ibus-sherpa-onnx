/**
 * IBus Sherpa ONNX preferences (GNOME IME Preferences / component setup).
 *
 * {{{
 *   ./build/ibus-setup-sherpa-onnx
 * }}}
 */
int main(string[] args)
{
	Gst.init(ref args);
	var app = new Adw.Application(
		"org.roojs.ibus-setup-sherpa-onnx",
		GLib.ApplicationFlags.DEFAULT_FLAGS
	);
	app.activate.connect(() => {
		var win = app.active_window as Gtk.Window;
		if (win == null) {
			win = new IBSO.Setup.Preferences(app);
		}
		win.present();
	});
	return app.run(args);
}
