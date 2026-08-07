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

namespace IBus.SherpaOnnx
{
	/**
	 * IBus input-method engine for local speech dictation.
	 *
	 * Toggle hotkey (or panel property) starts/stops the mic. Partials →
	 * preedit; endpoints → {@link IBus.Engine.commit_text}. Listening state
	 * uses a normal IBus panel property (like Hangul/Pinyin mode).
	 *
	 * @since 0.3
	 */
	public class Engine : IBus.Engine
	{
		/** Process-wide recognizer + mic (set by {@link Application}). */
		public static Transcriber transcriber;

		/** Toggle accelerator string from settings (set by {@link Application}). */
		public static string hotkey = "Ctrl+Shift+Space";

		/** Toggle accelerator keysym (set by {@link Application}). */
		public static uint toggle_keyval = 0;

		/** Toggle accelerator modifiers (set by {@link Application}). */
		public static uint toggle_mods = 0;

		/** Desktop notifications on toggle (default off). */
		public static bool notifications_enabled = false;

		/** Animated preedit dots while listening before first partial (default on). */
		public static bool preedit_animation = true;

		private IBus.Property prop;
		private IBus.PropList props;
		private uint anim_source = 0;
		private int anim_phase = 0;
		private bool saw_partial = false;

		construct
		{
			this.prop = new IBus.Property(
				"listening", IBus.PropType.TOGGLE, new IBus.Text.from_string("Mic off"),
				"microphone-sensitivity-muted", new IBus.Text.from_string("Toggle speech dictation"),
				true, true, IBus.PropState.UNCHECKED, null
			);
			this.prop.set_symbol(new IBus.Text.from_string("voi"));
			this.props = new IBus.PropList();
			this.props.append(this.prop);

			Engine.transcriber.partial.connect((text) => {
				if (!Engine.transcriber.listening) {
					return;
				}
				this.saw_partial = true;
				this.stop_preedit_animation();
				// Do not gate on has_focus: GNOME often delivers our toggle with
				// has_focus=false while preedit/commit still work for this client.
				this.update_preedit_text(new IBus.Text.from_string(text), (uint) text.length, true);
			});
			Engine.transcriber.endpoint.connect((text) => {
				if (!Engine.transcriber.listening) {
					return;
				}
				this.saw_partial = false;
				this.commit_text(new IBus.Text.from_string(text + " "));
				this.hide_preedit_text();
				if (Engine.transcriber.listening) {
					this.start_preedit_animation();
				}
			});
		}

		public override void enable()
		{
			base.enable();
			this.register_properties(this.props);
			this.update_ui();
		}

		public override void property_activate(string prop_name, uint prop_state)
		{
			if (prop_name != "listening") {
				return;
			}
			this.toggle_listening();
		}

		public override bool process_key_event(uint keyval, uint keycode, uint state)
		{
			if ((state & IBus.ModifierType.RELEASE_MASK) != 0) {
				return false;
			}

			var mods = state & (IBus.ModifierType.CONTROL_MASK | IBus.ModifierType.SHIFT_MASK
				| IBus.ModifierType.MOD1_MASK | IBus.ModifierType.SUPER_MASK
				| IBus.ModifierType.META_MASK | IBus.ModifierType.HYPER_MASK);
			if (keyval == Engine.toggle_keyval && mods == Engine.toggle_mods) {
				this.toggle_listening();
				return true;
			}

			// Ctrl/Alt/Super combos: let the client handle (VTE Ctrl+C, etc.).
			var app_mods = state & (IBus.ModifierType.CONTROL_MASK | IBus.ModifierType.MOD1_MASK
				| IBus.ModifierType.SUPER_MASK | IBus.ModifierType.META_MASK
				| IBus.ModifierType.HYPER_MASK);
			if (app_mods != 0) {
				return false;
			}

			// Plain typing (Shift OK for capitals): forward so GNOME clients receive keys.
			this.forward_key_event(keyval, keycode, state);
			return true;
		}

		public override void disable()
		{
			if (Engine.transcriber.listening) {
				Engine.transcriber.stop();
			}
			this.update_ui();
		}

		private void toggle_listening()
		{
			if (Engine.transcriber.listening) {
				GLib.debug("toggle OFF (has_focus=%s)", this.has_focus.to_string());
				Engine.transcriber.stop();
			} else {
				GLib.debug("toggle ON (has_focus=%s)", this.has_focus.to_string());
				Engine.transcriber.start();
			}
			this.update_ui();
			this.maybe_notify_toggle();
		}

		/** Panel label/symbol + preedit hint from current mic state. */
		private void update_ui()
		{
			if (Engine.transcriber.listening) {
				this.prop.set_label(new IBus.Text.from_string("Listening…"));
				this.prop.set_symbol(new IBus.Text.from_string("…"));
				this.prop.set_icon("audio-input-microphone");
				this.prop.set_state(IBus.PropState.CHECKED);
				this.update_property(this.prop);
				this.saw_partial = false;
				this.start_preedit_animation();
				return;
			}

			this.stop_preedit_animation();
			this.saw_partial = false;
			this.prop.set_label(new IBus.Text.from_string("Mic off"));
			this.prop.set_symbol(new IBus.Text.from_string("voi"));
			this.prop.set_icon("microphone-sensitivity-muted");
			this.prop.set_state(IBus.PropState.UNCHECKED);
			this.hide_preedit_text();
			this.update_property(this.prop);
		}

		private void start_preedit_animation()
		{
			this.stop_preedit_animation();
			if (!Engine.preedit_animation) {
				var hint = "Listening…";
				this.update_preedit_text(new IBus.Text.from_string(hint), (uint) hint.length, true);
				return;
			}

			this.anim_phase = 0;
			this.show_anim_preedit();
			this.anim_source = GLib.Timeout.add(400, () => {
				if (!Engine.transcriber.listening || this.saw_partial) {
					this.anim_source = 0;
					return GLib.Source.REMOVE;
				}
				this.anim_phase = (this.anim_phase + 1) % 3;
				this.show_anim_preedit();
				return GLib.Source.CONTINUE;
			});
		}

		private void show_anim_preedit()
		{
			string dots;
			switch (this.anim_phase) {
			case 0:
				dots = ".";
				break;
			case 1:
				dots = "..";
				break;
			default:
				dots = "…";
				break;
			}
			this.update_preedit_text(new IBus.Text.from_string(dots), (uint) dots.length, true);
		}

		private void stop_preedit_animation()
		{
			if (this.anim_source == 0) {
				return;
			}
			GLib.Source.remove(this.anim_source);
			this.anim_source = 0;
		}

		private void maybe_notify_toggle()
		{
			if (!Engine.notifications_enabled) {
				return;
			}
			var app = GLib.Application.get_default();
			if (app == null) {
				return;
			}
			var note = new GLib.Notification("Sherpa ONNX");
			if (Engine.transcriber.listening) {
				note.set_body("Listening…");
			} else {
				note.set_body("Mic off");
			}
			app.send_notification("sherpa-onnx-listening", note);
		}
	}
}
