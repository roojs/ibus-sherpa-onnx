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
		private Gtk.TextView output_view;
		private Gtk.Button replay_btn;
		private Gtk.Button stop_btn;
		private Gtk.Label match_label;
		private Gtk.Box stars_box;
		private Gtk.Box out_star_row;
		private Stars original_stars;
		private Stars output_stars;
		private HistoryItem? current;
		private IBSO.Transcriber? transcriber;
		private Replay? replay;
		private bool replaying;
		/** Committed endpoint texts for this Replay (newline between). */
		private string output_commits = "";

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
			this.stop_btn = new Gtk.Button.with_label("Stop") {
				halign = Gtk.Align.CENTER,
				sensitive = false
			};
			this.stop_btn.clicked.connect(this.on_stop);
			var replay_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				halign = Gtk.Align.CENTER
			};
			replay_row.append(this.replay_btn);
			replay_row.append(this.stop_btn);

			this.output_buf = new Gtk.TextBuffer(null);
			this.output_view = new Gtk.TextView.with_buffer(this.output_buf) {
				editable = false,
				wrap_mode = Gtk.WrapMode.WORD_CHAR,
				vexpand = true
			};
			var output_frame = new Gtk.Frame(null) {
				label = "Output",
				child = new Gtk.ScrolledWindow() {
					child = this.output_view,
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

			this.match_label = new Gtk.Label("") {
				xalign = 0,
				visible = false
			};

			var orig_star_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			orig_star_row.append(new Gtk.Label("Original") {
				width_chars = 8,
				xalign = 0
			});
			orig_star_row.append(this.original_stars);
			this.out_star_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			this.out_star_row.append(new Gtk.Label("Output") {
				width_chars = 8,
				xalign = 0
			});
			this.out_star_row.append(this.output_stars);

			this.stars_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6) {
				visible = false,
				margin_top = 8
			};
			this.stars_box.append(this.match_label);
			this.stars_box.append(orig_star_row);
			this.stars_box.append(this.out_star_row);

			var right = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				hexpand = true,
				vexpand = true,
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 12
			};
			right.append(original_frame);
			right.append(replay_row);
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
				this.stop_btn.sensitive = false;
				if (this.replay != null) {
					this.replay.stop();
				}
				return false;
			});
		}

		private void on_selected(HistoryItem? item)
		{
			this.replaying = false;
			this.output_commits = "";
			if (this.replay != null) {
				this.replay.stop();
			}
			this.current = item;
			this.stars_box.visible = false;
			this.match_label.visible = false;
			this.match_label.label = "";
			this.out_star_row.visible = true;
			this.original_buf.set_text("", -1);
			this.output_buf.set_text("", -1);
			this.original_stars.fill(0);
			this.output_stars.fill(0);
			this.replay_btn.sensitive = false;
			this.stop_btn.sensitive = false;
			if (item == null) {
				return;
			}
			this.replay_btn.sensitive = GLib.FileUtils.test(item.stem + ".wav",
				GLib.FileTest.IS_REGULAR);
			this.original_buf.set_text(item.text(), -1);
			this.output_buf.set_text(item.output(), -1);
		}

		private void on_stop()
		{
			if (!this.replaying) {
				return;
			}
			this.replaying = false;
			this.stop_btn.sensitive = false;
			if (this.current != null) {
				GLib.debug("#replay stopped stem=%s t=%.3f", this.current.stem,
					this.transcriber != null ? this.transcriber.feed_pos_s : 0.0);
			}
			if (this.replay != null) {
				this.replay.stop();
			}
			this.replay_btn.sensitive = this.current != null
				&& GLib.FileUtils.test(this.current.stem + ".wav", GLib.FileTest.IS_REGULAR);
		}

		private void on_replay()
		{
			if (this.current == null) {
				return;
			}
			this.output_buf.set_text("", -1);
			this.output_commits = "";
			this.output_stars.fill(0);
			this.match_label.visible = false;
			this.match_label.label = "";
			this.out_star_row.visible = true;
			this.stars_box.visible = false;
			this.current.clear_output_rating();
			this.replaying = true;
			this.replay_btn.sensitive = false;
			this.stop_btn.sensitive = true;

			this.ensure_transcriber();
			if (this.transcriber == null || this.replay == null) {
				this.replaying = false;
				this.replay_btn.sensitive = true;
				this.stop_btn.sensitive = false;
				return;
			}
			GLib.debug("#replay start stem=%s wav=%s model=%s",
				this.current.stem, this.current.stem + ".wav", this.transcriber.model_dir);
			this.replay.start(this.current.stem + ".wav");
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
				this.replay = null;
				return;
			}
			this.replay = new Replay(this.transcriber);
			this.transcriber.partial.connect((text) => {
				if (!this.replaying) {
					return;
				}
				GLib.debug("#partial t=%.3f text=%s", this.transcriber.feed_pos_s, text);
				if (this.output_commits == "") {
					this.output_buf.set_text(text, -1);
				} else {
					this.output_buf.set_text(this.output_commits + "\n" + text, -1);
				}
				Gtk.TextIter end;
				this.output_buf.get_end_iter(out end);
				this.output_buf.place_cursor(end);
				this.output_view.scroll_mark_onscreen(this.output_buf.get_insert());
			});
			this.transcriber.endpoint.connect((text) => {
				if (!this.replaying || text.strip() == "") {
					return;
				}
				GLib.debug("#endpoint t=%.3f text=%s", this.transcriber.feed_pos_s, text);
				if (this.output_commits != "") {
					this.output_commits += "\n";
				}
				this.output_commits += text;
				this.output_buf.set_text(this.output_commits, -1);
				Gtk.TextIter end;
				this.output_buf.get_end_iter(out end);
				this.output_buf.place_cursor(end);
				this.output_view.scroll_mark_onscreen(this.output_buf.get_insert());
			});
			this.transcriber.replay_finished.connect(() => {
				if (!this.replaying) {
					return;
				}
				this.replaying = false;
				this.replay_btn.sensitive = this.current != null;
				this.stop_btn.sensitive = false;
				if (this.current == null) {
					return;
				}
				if (this.output_commits != "") {
					this.output_buf.set_text(this.output_commits, -1);
				}
				Gtk.TextIter start, end;
				this.output_buf.get_bounds(out start, out end);
				var output = this.output_buf.get_text(start, end, false);
				this.current.write_output(output);
				var score = RapidFuzz.ratio(this.current.text().strip(), output.strip());
				GLib.debug("#replay finished stem=%s match=%.0f%%", this.current.stem, score);
				this.match_label.label = "Match: %.0f%%".printf(score);
				this.match_label.visible = true;
				this.out_star_row.visible = score < 100.0;
				this.stars_box.visible = true;
				this.original_stars.fill(this.current.rating());
			});
		}
	}
}
