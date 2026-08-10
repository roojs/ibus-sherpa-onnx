/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace IBSO.Setup
{
	/**
	 * Phrase row: label on the left, {@link Gtk.Entry} + mic on the right.
	 * Entry stays insensitive until the mic is pressed; failures show on
	 * {@link Preferences} banner. Try-out text is not saved; the phrase is
	 * restored on focus leave. Bound to a KeyFile string under ''general''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var stop = new RowMicText(prefs, config, "voice-stop", "Stop");
	 * group.add(stop.row);
	 * stop.fill();
	 * }}}
	 */
	public class RowMicText : Row
	{
		public Gtk.Entry entry;
		public Gtk.Button record;
		public Preferences prefs;

		/** True while a mic try-out is in progress (do not save spoken text). */
		private bool trying = false;

		/**
		 * True between mic click and IBus activate finishing — ignore focus
		 * leave while focus moves from the button onto the entry.
		 */
		private bool arming = false;

		/** IBus context path we activated, or null if not started. */
		private string? listen_path = null;

		/**
		 * @param prefs Preferences window (banner / status)
		 * @param config Settings object
		 * @param key String key under ''general''
		 * @param title Action row title (left label)
		 */
		public RowMicText(Preferences prefs, Config config, string key, string title)
		{
			base(config, key, title, "");
			this.prefs = prefs;
			this.entry = new Gtk.Entry() {
				valign = Gtk.Align.CENTER,
				sensitive = false,
				width_chars = 32,
				max_width_chars = 32,
				hexpand = false
			};
			this.entry.changed.connect(() => {
				if (this.loading || this.trying) {
					return;
				}
				this.config.key_file.set_string("general", this.key, this.entry.text);
				this.config.save();
			});
			this.record = new Gtk.Button.from_icon_name("audio-input-microphone-symbolic") {
				valign = Gtk.Align.CENTER,
				tooltip_text = "Clear, focus, and toggle listening"
			};
			this.record.add_css_class("flat");
			this.record.clicked.connect(() => {
				this.prefs.banner("");
				this.trying = true;
				this.arming = true;
				this.listen_path = null;
				this.entry.sensitive = true;
				this.loading = true;
				this.entry.text = "";
				this.loading = false;
				this.entry.grab_focus();
				/*
				 * Wait for the entry to become the IBus current input context.
				 * Ignore focus leave while arming (button → entry).
				 */
				GLib.Timeout.add(500, () => {
					this.start_listening();
					return false;
				});
			});
			((Adw.ActionRow) this.row).add_suffix(this.entry);
			((Adw.ActionRow) this.row).add_suffix(this.record);

			var focus = new Gtk.EventControllerFocus();
			focus.leave.connect(() => {
				if (!this.trying || this.arming) {
					return;
				}
				this.trying = false;
				this.arming = false;
				var path = this.listen_path;
				this.listen_path = null;
				if (path != null && path != "") {
					try {
						var bus = new IBus.Bus();
						if (bus.is_connected()) {
							var ic = new IBus.InputContext(path, bus.get_connection());
							ic.property_activate("listening", IBus.PropState.UNCHECKED);
						}
					} catch (GLib.Error err) {
						GLib.debug("mic try-out stop: %s", err.message);
					}
				}
				this.prefs.banner("");
				/*
				 * sensitive=false must not run during focus-leave — GtkText
				 * warns it missed focus-out (cursor blink cleanup).
				 */
				GLib.Idle.add(() => {
					this.fill();
					this.entry.sensitive = false;
					return false;
				});
			});
			this.entry.add_controller(focus);
		}

		/**
		 * After mic arming delay: IBus checks, then ''listening'' activate.
		 */
		private void start_listening()
		{
			this.arming = false;
			if (!this.trying) {
				return;
			}
			var bus = new IBus.Bus();
			if (!bus.is_connected()) {
				this.trying = false;
				this.prefs.banner("IBus is not running");
				GLib.Idle.add(() => {
					this.fill();
					this.entry.sensitive = false;
					return false;
				});
				return;
			}
			var eng = bus.get_global_engine();
			var eng_name = eng != null ? eng.get_name() : "";
			if (eng_name != "sherpa-onnx" && !eng_name.has_prefix("sherpa-onnx-")) {
				this.trying = false;
				this.prefs.banner("Active engine is “" + eng_name + "”, not Sherpa");
				GLib.Idle.add(() => {
					this.fill();
					this.entry.sensitive = false;
					return false;
				});
				return;
			}
			var path = bus.current_input_context();
			if (path == null || path == "") {
				this.trying = false;
				this.prefs.banner("No IBus input context for this field");
				GLib.Idle.add(() => {
					this.fill();
					this.entry.sensitive = false;
					return false;
				});
				return;
			}
			try {
				var ic = new IBus.InputContext(path, bus.get_connection());
				GLib.debug("calling listening activate key=%s engine=%s ic=%s entry_is_focus=%s entry_has_focus=%s",
					this.key, eng_name, path, this.entry.is_focus().to_string(), this.entry.has_focus.to_string());
				ic.property_activate("listening", IBus.PropState.CHECKED);
				this.listen_path = path;
				GLib.debug("listening activate returned ok ic=%s", path);
			} catch (GLib.Error err) {
				this.trying = false;
				this.prefs.banner("Could not start listening (" + err.message + ")");
				GLib.Idle.add(() => {
					this.fill();
					this.entry.sensitive = false;
					return false;
				});
				return;
			}
		}

		public override void fill()
		{
			this.loading = true;
			try {
				this.entry.text = this.config.key_file.get_string("general", this.key);
			} catch (GLib.KeyFileError err) {
				this.entry.text = "";
			}
			this.loading = false;
		}
	}
}
