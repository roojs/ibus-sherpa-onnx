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
				this.entry.sensitive = true;
				this.loading = true;
				this.entry.text = "";
				this.loading = false;
				this.entry.grab_focus();
				/* Focus must reach IBus before current_input_context updates. */
				GLib.Timeout.add(50, () => {
					var bus = new IBus.Bus();
					if (!bus.is_connected()) {
						this.trying = false;
						this.fill();
						this.entry.sensitive = false;
						this.prefs.banner("IBus is not running");
						return false;
					}
					var path = bus.current_input_context();
					if (path == null || path == "") {
						this.trying = false;
						this.fill();
						this.entry.sensitive = false;
						this.prefs.banner(
							"No input context — click the phrase field and try again");
						return false;
					}
					try {
						var ic = new IBus.InputContext(path, bus.get_connection());
						ic.property_activate("listening", IBus.PropState.CHECKED);
					} catch (GLib.Error err) {
						this.trying = false;
						this.fill();
						this.entry.sensitive = false;
						this.prefs.banner("Could not start listening");
						return false;
					}
					this.prefs.banner("");
					return false;
				});
			});
			((Adw.ActionRow) this.row).add_suffix(this.entry);
			((Adw.ActionRow) this.row).add_suffix(this.record);

			var focus = new Gtk.EventControllerFocus();
			focus.leave.connect(() => {
				if (!this.trying) {
					return;
				}
				this.trying = false;
				this.fill();
				this.entry.sensitive = false;
			});
			this.entry.add_controller(focus);
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
