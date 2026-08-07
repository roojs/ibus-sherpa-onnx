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
	 * Shares one process-wide {@link Transcriber}. A remappable toggle hotkey
	 * starts/stops the mic. Partials become preedit; endpoints
	 * {@link IBus.Engine.commit_text} into the focused client. Other keys
	 * pass through.
	 *
	 * == Usage Examples ==
	 *
	 * === Register from the engine process ===
	 *
	 * {{{
	 *   // Application sets asr + toggle_*, then:
	 *   factory.add_engine("sherpa-onnx", typeof(IBus.SherpaOnnx.Engine));
	 *   bus.register_component(component);
	 * }}}
	 *
	 * @since 0.3
	 */
	public class Engine : IBus.Engine
	{
		/** Process-wide recognizer + mic (set by {@link Application}). */
		public static Transcriber transcriber;

		/** Toggle accelerator keysym (set by {@link Application}). */
		public static uint toggle_keyval = 0;

		/** Toggle accelerator modifiers (set by {@link Application}). */
		public static uint toggle_mods = 0;

		construct
		{
			Engine.transcriber.partial.connect((text) => {
				if (!this.has_focus || !Engine.transcriber.listening) {
					return;
				}
				this.update_preedit_text(
					new IBus.Text.from_string(text), (uint) text.length, true
				);
			});
			Engine.transcriber.endpoint.connect((text) => {
				if (!this.has_focus) {
					return;
				}
				this.commit_text(new IBus.Text.from_string(text + " "));
				this.hide_preedit_text();
			});
		}

		/**
		 * Consume the toggle hotkey; pass every other key through.
		 *
		 * @param keyval keysym
		 * @param keycode hardware keycode
		 * @param state modifier / release bits ({@link IBus.ModifierType})
		 * @return true if consumed; false to pass through
		 */
		public override bool process_key_event(uint keyval, uint keycode, uint state)
		{
			if ((state & IBus.ModifierType.RELEASE_MASK) != 0) {
				return false;
			}

			var mods = state & (
				IBus.ModifierType.CONTROL_MASK
				| IBus.ModifierType.SHIFT_MASK
				| IBus.ModifierType.MOD1_MASK
				| IBus.ModifierType.SUPER_MASK
				| IBus.ModifierType.META_MASK
				| IBus.ModifierType.HYPER_MASK
			);
			if (keyval != Engine.toggle_keyval || mods != Engine.toggle_mods) {
				return false;
			}

			if (Engine.transcriber.listening) {
				Engine.transcriber.stop();
				this.hide_preedit_text();
				return true;
			}
			Engine.transcriber.start();
			return true;
		}

		/**
		 * Stop capture if the IME is disabled while listening.
		 */
		public override void disable()
		{
			if (!Engine.transcriber.listening) {
				return;
			}
			Engine.transcriber.stop();
			this.hide_preedit_text();
		}
	}
}
