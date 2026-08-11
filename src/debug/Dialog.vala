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

namespace IBSO.Debug
{
	/**
	 * Browse saved debug recordings: history list, original, replay, output, stars.
	 */
	public class Dialog : Adw.Window
	{
		private History history;
		private Gtk.TextBuffer original_buf;
		private Gtk.TextBuffer output_buf;
		private Gtk.Button replay_btn;
		private Gtk.Box stars_box;
		private Stars original_stars;
		private Stars output_stars;
		private HistoryItem? current;
		private Gst.Element? player;
		private ulong player_bus_id;
		private IBSO.Transcriber? transcriber;
		private bool play_done;
		private bool asr_done;
		private bool replaying;

		/**
		 * @param parent Preferences window
		 */
		public Dialog(Gtk.Window parent)
		{
			GLib.Object(
				transient_for: parent,
				modal: true,
				title: "Debug recordings",
				default_width: 900,
				default_height: 600
			);

			this.history = new History();
			this.history.selected.connect(this.on_selected);

			this.original_buf = new Gtk.TextBuffer(null);
			var original_view = new Gtk.TextView.with_buffer(this.original_buf) {
				editable = false,
				wrap_mode = Gtk.WrapMode.WORD_CHAR,
				vexpand = true
			};
			var original_frame = new Gtk.Frame(null) {
				label = "Original text",
				child = new Gtk.ScrolledWindow() {
					child = original_view,
					min_content_height = 100
				}
			};

			this.replay_btn = new Gtk.Button.with_label("Replay through engine") {
				halign = Gtk.Align.CENTER,
				sensitive = false
			};
			this.replay_btn.clicked.connect(this.on_replay);

			this.output_buf = new Gtk.TextBuffer(null);
			var output_view = new Gtk.TextView.with_buffer(this.output_buf) {
				editable = false,
				wrap_mode = Gtk.WrapMode.WORD_CHAR,
				vexpand = true
			};
			var output_frame = new Gtk.Frame(null) {
				label = "Output",
				child = new Gtk.ScrolledWindow() {
					child = output_view,
					min_content_height = 100
				}
			};

			this.original_stars = new Stars();
			this.output_stars = new Stars();
			this.original_stars.changed.connect((n) => {
				this.current.write_rating(n);
			});
			this.output_stars.changed.connect((n) => {
				this.current.write_output_rating(n);
			});

			var orig_star_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			orig_star_row.append(new Gtk.Label("Original") {
				width_chars = 8,
				xalign = 0
			});
			orig_star_row.append(this.original_stars);
			var out_star_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			out_star_row.append(new Gtk.Label("Output") {
				width_chars = 8,
				xalign = 0
			});
			out_star_row.append(this.output_stars);

			this.stars_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6) {
				visible = false,
				margin_top = 8
			};
			this.stars_box.append(orig_star_row);
			this.stars_box.append(out_star_row);

			var right = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				hexpand = true,
				vexpand = true,
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 12
			};
			right.append(original_frame);
			right.append(this.replay_btn);
			right.append(output_frame);
			right.append(this.stars_box);

			var paned = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			paned.append(this.history);
			paned.append(new Gtk.Separator(Gtk.Orientation.VERTICAL));
			paned.append(right);

			var toolbar = new Adw.ToolbarView();
			toolbar.add_top_bar(new Adw.HeaderBar());
			toolbar.content = paned;
			this.content = toolbar;

			this.close_request.connect(() => {
				this.replaying = false;
				this.stop_player();
				this.play_done = false;
				this.asr_done = false;
				return false;
			});
		}

		private void on_selected(HistoryItem? item)
		{
			this.replaying = false;
			this.stop_player();
			this.play_done = false;
			this.asr_done = false;
			this.current = item;
			this.stars_box.visible = false;
			this.original_buf.set_text("", -1);
			this.output_buf.set_text("", -1);
			this.original_stars.fill(0);
			this.output_stars.fill(0);
			this.replay_btn.sensitive = false;
			if (item == null) {
				return;
			}
			this.replay_btn.sensitive = GLib.FileUtils.test(item.stem + ".wav",
				GLib.FileTest.IS_REGULAR);
			this.original_buf.set_text(item.text(), -1);
			this.output_buf.set_text(item.output(), -1);
		}

		private void on_replay()
		{
			if (this.current == null) {
				return;
			}
			this.replaying = false;
			this.stop_player();
			this.output_buf.set_text("", -1);
			this.output_stars.fill(0);
			this.current.clear_output_rating();
			this.play_done = false;
			this.asr_done = false;
			this.replaying = true;
			this.replay_btn.sensitive = false;

			this.ensure_transcriber();
			if (this.transcriber != null) {
				this.transcriber.feed_wav(this.current.samples());
			} else {
				this.asr_done = true;
			}

			this.player = Gst.ElementFactory.make("playbin", "debug-replay");
			this.player.set("uri", this.current.wav_uri());
			var bus = this.player.get_bus();
			bus.add_signal_watch();
			this.player_bus_id = bus.message.connect((b, message) => {
				if (message.type == Gst.MessageType.EOS || message.type == Gst.MessageType.ERROR) {
					this.stop_player();
					this.play_done = true;
					this.maybe_finish_replay();
				}
			});
			this.player.set_state(Gst.State.PLAYING);
		}

		/**
		 * Load {@link Transcriber} once from current prefs/pack (lazy on first Replay).
		 */
		private void ensure_transcriber()
		{
			if (this.transcriber != null) {
				return;
			}
			var config = IBSO.Config.load();
			var models = new IBSO.Models();
			var language = config.key_file.get_string("general", "language");
			var pack = "";
			try {
				pack = config.packs.get_string("packs", language);
			} catch (GLib.Error err) {
			}
			var model_dir = "";
			if (pack != "") {
				try {
					var name = models.packs.get_string(pack, "name");
					var dir = GLib.Path.build_filename(models.system_prefix, "models", name);
					if (GLib.FileUtils.test(GLib.Path.build_filename(dir, ".sha256"),
							GLib.FileTest.IS_REGULAR)) {
						model_dir = dir;
					}
				} catch (GLib.Error err) {
				}
			}
			if (model_dir == "") {
				GLib.warning("debug replay: no model for language %s", language);
				return;
			}
			var engine = new IBSO.Engine() {
				language = language
			};
			try {
				this.transcriber = new IBSO.Transcriber(engine, config) {
					model_dir = model_dir,
					pack = pack
				};
				this.transcriber.load();
			} catch (GLib.Error err) {
				GLib.warning("debug replay load: %s", err.message);
				this.transcriber = null;
				return;
			}
			this.transcriber.partial.connect((text) => {
				if (!this.replaying) {
					return;
				}
				this.output_buf.set_text(text, -1);
			});
			this.transcriber.endpoint.connect((text) => {
				if (!this.replaying) {
					return;
				}
				this.output_buf.set_text(text, -1);
				this.asr_done = true;
				this.maybe_finish_replay();
			});
		}

		private void maybe_finish_replay()
		{
			if (!this.replaying || !this.play_done || !this.asr_done) {
				return;
			}
			this.replaying = false;
			this.replay_btn.sensitive = this.current != null;
			if (this.current == null) {
				return;
			}
			Gtk.TextIter start, end;
			this.output_buf.get_bounds(out start, out end);
			this.current.write_output(this.output_buf.get_text(start, end, false));
			this.stars_box.visible = true;
			this.original_stars.fill(this.current.rating());
		}

		private void stop_player()
		{
			if (this.player == null) {
				return;
			}
			var bus = this.player.get_bus();
			if (this.player_bus_id != 0) {
				bus.disconnect(this.player_bus_id);
				this.player_bus_id = 0;
			}
			bus.remove_signal_watch();
			this.player.set_state(Gst.State.NULL);
			this.player = null;
		}
	}
}
