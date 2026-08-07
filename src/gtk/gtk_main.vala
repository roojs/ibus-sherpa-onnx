/**
 * Sideline GTK composer + mic STT hello world (see docs/plans/0.3 for IBus).
 *
 * Usage:
 *   stt-gtk-poc [model-dir]
 *
 * Default model-dir:
 *   models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25
 *
 * Mic or Ctrl+Shift+Space starts listening; Escape or typing stops.
 */
int main (string[] args)
{
	Gst.init (ref args);

	var model_dir = "models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25";
	for (var i = 1; i < args.length; i++) {
		if (args[i].has_prefix ("-")) {
			continue;
		}
		model_dir = args[i];
	}

	var app = new Adw.Application ("com.roojs.stt-gtk-poc", GLib.ApplicationFlags.DEFAULT_FLAGS);
	app.activate.connect (() => {
		var css = new Gtk.CssProvider ();
		css.load_from_path ("data/style.css");
		Gtk.StyleContext.add_provider_for_display (
			Gdk.Display.get_default (),
			css,
			Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
		);

		SttPoc.SttEngine engine;
		try {
			engine = new SttPoc.SttEngine (model_dir);
		} catch (GLib.Error err) {
			var fail = new Adw.ApplicationWindow (app) {
				title = "STT PoC",
				default_width = 420,
				default_height = 120
			};
			fail.set_content (new Gtk.Label (err.message) {
				wrap = true,
				margin_top = 16,
				margin_bottom = 16,
				margin_start = 16,
				margin_end = 16
			});
			fail.present ();
			return;
		}

		var window = new Adw.ApplicationWindow (app) {
			title = "STT PoC",
			default_width = 520,
			default_height = 200
		};

		var header = new Adw.HeaderBar ();
		var toolbar = new Adw.ToolbarView ();
		toolbar.add_top_bar (header);

		var input = new SttPoc.ComposerInput ();
		input.scrolled.max_height = 160;

		/* Committed utterances + active partial (main loop only). */
		string[] committed = {""};
		string[] active = {""};

		input.mic_clicked.connect (() => {
			if (engine.listening) {
				return;
			}
			var existing = input.text ();
			committed[0] = existing.length > 0 ? existing + " " : "";
			active[0] = "";
			engine.start ();
			input.set_listening (true);
		});
		input.stop_requested.connect (() => {
			if (!engine.listening) {
				return;
			}
			engine.stop ();
			input.set_listening (false);
		});

		var start_action = new GLib.SimpleAction ("start-listen", null);
		start_action.activate.connect (() => {
			if (engine.listening) {
				return;
			}
			var existing = input.text ();
			committed[0] = existing.length > 0 ? existing + " " : "";
			active[0] = "";
			engine.start ();
			input.set_listening (true);
		});
		app.add_action (start_action);
		app.set_accels_for_action ("app.start-listen", { "<Control><Shift>space" });

		engine.partial.connect ((text) => {
			active[0] = text;
			input.update_entry (committed[0] + active[0]);
		});
		engine.endpoint.connect ((text) => {
			committed[0] = committed[0] + text + " ";
			active[0] = "";
			input.update_entry (committed[0]);
		});

		window.close_request.connect (() => {
			engine.stop ();
			return false;
		});

		var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
			valign = Gtk.Align.CENTER,
			hexpand = true,
			vexpand = true
		};
		box.append (input);
		toolbar.set_content (box);
		window.set_content (toolbar);
		window.present ();
		GLib.Idle.add (input.focus_idle);
	});
	return app.run (args);
}
