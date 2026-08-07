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
	 * Growable composer TextView with a mic on the right (OLLMchat ChatInput
	 * pattern). Mic starts listening; Escape or typing requests stop.
	 *
	 * Height is owned by {@link scrolled}. While listening the mic hides and a
	 * spinner shows in the text-area overlay until transcript arrives.
	 *
	 * == Usage Examples ==
	 *
	 * === Start / stop chrome ===
	 *
	 * {{{
	 *   var input = new IBus.SherpaOnnx.ComposerInput();
	 *   input.mic_clicked.connect(() => { engine.start(); input.set_listening(true); });
	 *   input.stop_requested.connect(() => { engine.stop(); input.set_listening(false); });
	 * }}}
	 *
	 * @since 0.2
	 */
	public class ComposerInput : Gtk.Box
	{
		private Gtk.Button mic_button;
		private Gtk.Label placeholder;
		private Gtk.Spinner spinner;
		public ScrolledView scrolled { get; private set; }
		private Gtk.TextView text_view;
		private Gtk.TextBuffer buffer;
		private bool is_expanded = false;
		private bool syncing = false;
		private bool listening = false;

		/** Emitted when the user clicks the mic (start listening only). */
		public signal void mic_clicked();

		/**
		 * Emitted when listening should stop (Escape or a typed character).
		 */
		public signal void stop_requested();

		public ComposerInput()
		{
			Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
			this.hexpand = true;
			this.vexpand = false;
			this.add_css_class("chat-composer");

			this.scrolled = new ScrolledView() {
				hexpand = true,
				vexpand = false
			};
			this.scrolled.add_css_class("chat-composer-entry");
			this.buffer = new Gtk.TextBuffer(null);
			this.text_view = new Gtk.TextView.with_buffer(this.buffer) {
				wrap_mode = Gtk.WrapMode.WORD_CHAR,
				hexpand = true,
				vexpand = false,
				valign = Gtk.Align.FILL,
				top_margin = 4,
				bottom_margin = 4,
				left_margin = 6,
				right_margin = 6,
				tooltip_text = "Ctrl+Shift+Space to dictate, Escape to stop"
			};
			this.text_view.add_css_class("chat-composer-entry");
			this.text_view.add_css_class("chat-input-text");
			this.scrolled.set_child(this.text_view);

			this.placeholder = new Gtk.Label("Speak or type…") {
				halign = Gtk.Align.START,
				valign = Gtk.Align.CENTER,
				margin_start = 6,
				can_target = false
			};
			this.placeholder.add_css_class("dim-label");
			this.placeholder.add_css_class("chat-composer-placeholder");

			this.spinner = new Gtk.Spinner() {
				halign = Gtk.Align.START,
				valign = Gtk.Align.CENTER,
				margin_start = 8,
				can_target = false,
				visible = false,
				spinning = false
			};
			this.spinner.add_css_class("chat-composer-spinner");

			var overlay = new Gtk.Overlay() {
				hexpand = true,
				vexpand = false
			};
			overlay.set_child(this.scrolled);
			overlay.add_overlay(this.placeholder);
			overlay.add_overlay(this.spinner);
			overlay.set_measure_overlay(this.placeholder, false);
			overlay.set_measure_overlay(this.spinner, false);
			this.append(overlay);

			this.mic_button = new Gtk.Button.from_icon_name("audio-input-microphone-symbolic") {
				tooltip_text = "Start dictation",
				valign = Gtk.Align.FILL
			};
			this.mic_button.add_css_class("chat-composer-mic");
			this.mic_button.clicked.connect(() => {
				this.mic_clicked();
			});
			this.append(this.mic_button);
			this.scrolled.line_peer = this.mic_button;

			this.scrolled.lines_changed.connect((lines) => {
				if (this.listening) {
					this.placeholder.visible = false;
					this.spinner.visible = true;
					this.spinner.spinning = true;
				} else {
					this.placeholder.visible = lines == 0;
					this.spinner.visible = false;
					this.spinner.spinning = false;
				}
				if (lines == 1) {
					return;
				}
				if (lines == 0 && !this.is_expanded) {
					return;
				}
				if (lines == 0) {
					this.is_expanded = false;
					this.remove_css_class("is-expanded");
					return;
				}
				if (this.is_expanded) {
					return;
				}
				this.is_expanded = true;
				this.add_css_class("is-expanded");
			});

			var keys = new Gtk.EventControllerKey();
			keys.key_pressed.connect((keyval, keycode, state) => {
				if (!this.listening) {
					return false;
				}
				if (keyval == Gdk.Key.Escape) {
					this.stop_requested();
					return true;
				}
				/* Modifiers alone do not stop; printable / Enter does. */
				if (keyval == Gdk.Key.Shift_L || keyval == Gdk.Key.Shift_R
						|| keyval == Gdk.Key.Control_L || keyval == Gdk.Key.Control_R
						|| keyval == Gdk.Key.Alt_L || keyval == Gdk.Key.Alt_R
						|| keyval == Gdk.Key.Meta_L || keyval == Gdk.Key.Meta_R
						|| keyval == Gdk.Key.Super_L || keyval == Gdk.Key.Super_R
						|| keyval == Gdk.Key.Hyper_L || keyval == Gdk.Key.Hyper_R
						|| keyval == Gdk.Key.Caps_Lock || keyval == Gdk.Key.Num_Lock
						|| keyval == Gdk.Key.Scroll_Lock) {
					return false;
				}
				this.stop_requested();
				return false;
			});
			this.text_view.add_controller(keys);
		}

		/** Stripped composer text. */
		public string text()
		{
			Gtk.TextIter start_iter;
			Gtk.TextIter end_iter;
			this.buffer.get_start_iter(out start_iter);
			this.buffer.get_end_iter(out end_iter);
			return this.buffer.get_text(start_iter, end_iter, false).strip();
		}

		/**
		 * Hide mic and show text-area spinner while listening; reverse when
		 * stopped. Spinner stays until the first non-empty buffer update while
		 * listening (see {@link update_entry}).
		 *
		 * @param listening true after engine.start(), false after stop()
		 */
		public void set_listening(bool listening)
		{
			this.listening = listening;
			this.mic_button.visible = !listening;
			if (listening) {
				this.placeholder.visible = false;
				this.spinner.visible = true;
				this.spinner.spinning = true;
				return;
			}
			this.spinner.visible = false;
			this.spinner.spinning = false;
			this.placeholder.visible = this.buffer.get_char_count() == 0;
		}

		/**
		 * Apply text; chrome/placeholder follow later {@link ScrolledView.lines_changed}.
		 * Recursion: returns if syncing; holds syncing across buffer writes.
		 * On programmatic set: Idle.add({@link focus_idle}).
		 * While listening, hides the wait spinner once text is non-empty.
		 *
		 * @param text Full composer text
		 */
		public void update_entry(string text)
		{
			if (this.syncing) {
				return;
			}

			Gtk.TextIter cur_start;
			Gtk.TextIter cur_end;
			this.buffer.get_start_iter(out cur_start);
			this.buffer.get_end_iter(out cur_end);
			if (this.buffer.get_text(cur_start, cur_end, false) != text) {
				this.syncing = true;
				this.buffer.delete(ref cur_start, ref cur_end);
				this.buffer.insert(ref cur_start, text, -1);
				this.syncing = false;
			}
			if (this.listening && text.length > 0) {
				this.spinner.visible = false;
				this.spinner.spinning = false;
			}
			GLib.Idle.add(this.focus_idle);
		}

		/** Idle callback: wait until mapped, then focus TextView and caret at end. */
		public bool focus_idle()
		{
			if (!this.text_view.editable || !this.text_view.can_focus) {
				return false;
			}
			if (!this.text_view.get_mapped()) {
				return true;
			}
			if (this.scrolled.get_width() <= 0) {
				return true;
			}
			this.text_view.grab_focus();
			Gtk.TextIter end_iter;
			this.buffer.get_end_iter(out end_iter);
			this.buffer.place_cursor(end_iter);
			this.text_view.scroll_to_mark(this.buffer.get_insert(), 0.0, true, 0.0, 1.0);
			this.scrolled.queue_fit();
			return false;
		}
	}
}
