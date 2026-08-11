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
	 * {@link Preferences} banner. Bound to a KeyFile string under ''general''.
	 *
	 * Mic starts listening (AT-SPI toggle hotkey). Leaving the entry while
	 * listening (including mic click): short wait, then save and lock.
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
		/** Mic / listening state for this phrase field. */
		private enum Mic
		{
			/** Entry insensitive, saved phrase shown. */
			IDLE,
			/** Mic clicked; waiting for focus + hotkey. */
			ARMING,
			/** Listening. */
			LISTENING
		}

		public Gtk.Entry entry;
		public Gtk.Button record;
		public Preferences prefs;

		private Mic mic = Mic.IDLE;

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
			this.config.changed.connect(() => {
				this.row.visible = this.config.key_file.get_boolean("general", "voice-commands");
			});
			this.row.visible = this.config.key_file.get_boolean("general", "voice-commands");
			this.entry = new Gtk.Entry() {
				valign = Gtk.Align.CENTER,
				sensitive = false,
				width_chars = 32,
				max_width_chars = 32,
				hexpand = false
			};
			this.entry.changed.connect(() => {
				if (this.loading || this.mic != Mic.IDLE) {
					return;
				}
				this.config.key_file.set_string("general", this.key, this.entry.text);
				this.config.save();
			});
			this.record = new Gtk.Button.from_icon_name("audio-input-microphone-symbolic") {
				valign = Gtk.Align.CENTER,
				tooltip_text = "Dictate your preferred command"
			};
			this.record.add_css_class("flat");
			this.record.clicked.connect(() => {
				GLib.debug("key=%s mic=%s", this.key, this.mic.to_string());
				if (this.mic != Mic.IDLE) {
					return;
				}
				this.prefs.banner("");
				/* ---- START ---- */
				uint keyval;
				IBus.ModifierType mods;
				if (!this.config.hotkey(out keyval, out mods)) {
					this.prefs.banner("Set a valid toggle hotkey under General first");
					return;
				}
				this.mic = Mic.ARMING;
				this.entry.sensitive = true;
				this.loading = true;
				this.entry.text = "";
				this.loading = false;
				this.entry.grab_focus();
				/* Delay so the entry owns focus before we send the hotkey. */
				GLib.Timeout.add(500, () => {
					this.start_listening(keyval, mods);
					return false;
				});
			});
			((Adw.ActionRow) this.row).add_suffix(this.entry);
			((Adw.ActionRow) this.row).add_suffix(this.record);

			var focus = new Gtk.EventControllerFocus();
			focus.leave.connect(() => {
				GLib.debug("key=%s mic=%s", this.key, this.mic.to_string());
				/* ---- STOP (left entry while listening, e.g. mic click) ---- */
				if (this.mic != Mic.LISTENING) {
					return;
				}
				GLib.Timeout.add(300, () => {
					this.mic = Mic.IDLE;
					this.config.key_file.set_string("general", this.key, this.entry.text);
					this.config.save();
					this.entry.sensitive = false;
					GLib.debug("key=%s mic=%s", this.key, this.mic.to_string());
					return false;
				});
			});
			this.entry.add_controller(focus);
		}

		/**
		 * After mic arming delay: IBus checks, then send the toggle hotkey.
		 */
		private void start_listening(uint keyval, IBus.ModifierType mods)
		{
			if (this.mic != Mic.ARMING) {
				return;
			}
			this.entry.grab_focus();
			var bus = new IBus.Bus();
			if (!bus.is_connected()) {
				this.mic = Mic.IDLE;
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
				this.mic = Mic.IDLE;
				this.prefs.banner("Active engine is “" + eng_name + "”, not Sherpa");
				GLib.Idle.add(() => {
					this.fill();
					this.entry.sensitive = false;
					return false;
				});
				return;
			}
			if (!this.toggle_hotkey(keyval, mods)) {
				this.mic = Mic.IDLE;
				this.prefs.banner("Could not send the toggle hotkey");
				GLib.Idle.add(() => {
					this.fill();
					this.entry.sensitive = false;
					return false;
				});
				return;
			}
			this.mic = Mic.LISTENING;
			GLib.debug("key=%s mic=%s", this.key, this.mic.to_string());
		}

		/**
		 * Send ''keyval''+''mods'' via AT-SPI (LOCKMODIFIERS + SYM).
		 *
		 * @return false if AT-SPI failed
		 */
		private bool toggle_hotkey(uint keyval, IBus.ModifierType mods)
		{
			if (!Atspi.is_initialized()) {
				Atspi.init();
			}
			long lock = 0;
			if ((mods & IBus.ModifierType.SHIFT_MASK) != 0) {
				lock |= (1 << Atspi.ModifierType.SHIFT);
			}
			if ((mods & IBus.ModifierType.CONTROL_MASK) != 0) {
				lock |= (1 << Atspi.ModifierType.CONTROL);
			}
			if ((mods & IBus.ModifierType.MOD1_MASK) != 0) {
				lock |= (1 << Atspi.ModifierType.ALT);
			}
			if ((mods & IBus.ModifierType.SUPER_MASK) != 0
					|| (mods & IBus.ModifierType.META_MASK) != 0
					|| (mods & IBus.ModifierType.HYPER_MASK) != 0) {
				lock |= (1 << Atspi.ModifierType.META);
			}
			GLib.debug("keyval=0x%x ibus_mods=0x%x atspi_lock=0x%lx",
				keyval, (uint) mods, lock);
			try {
				if (lock != 0) {
					Atspi.generate_keyboard_event(lock, null, Atspi.KeySynthType.LOCKMODIFIERS);
				}
				Atspi.generate_keyboard_event((long) keyval, null, Atspi.KeySynthType.SYM);
				if (lock != 0) {
					Atspi.generate_keyboard_event(lock, null, Atspi.KeySynthType.UNLOCKMODIFIERS);
				}
			} catch (GLib.Error err) {
				GLib.debug("%s", err.message);
				return false;
			}
			return true;
		}

		public override void fill()
		{
			this.loading = true;
			try {
				this.entry.text = this.config.key_file.get_string("general", this.key);
			} catch (GLib.KeyFileError err) {
				this.entry.text = "";
			}
			this.row.visible = this.config.key_file.get_boolean("general", "voice-commands");
			this.loading = false;
		}
	}
}
