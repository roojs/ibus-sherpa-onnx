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

namespace IBus.SherpaOnnx.Setup
{
	/**
	 * Single-page preferences: Listening (hotkey / notify / animation) and
	 * Select model. Standalone {@link Adw.Window} hosting an
	 * {@link Adw.PreferencesPage} — same shell as RooTerm ''Dialog.Preferences''.
	 *
	 * Close saves settings and asks {@link ModelDownload} to link or fetch.
	 * While fetching, the prefs page is replaced by the download status view
	 * (Cancel returns to editing).
	 */
	public class Preferences : Adw.Window
	{
		public Config config;
		public GLib.HashTable<string, Row> rows =
			new GLib.HashTable<string, Row>(GLib.str_hash, GLib.str_equal);

		private ModelDownload download = new ModelDownload();
		private Gtk.Stack stack;
		private Gtk.Button close_btn;

		public Preferences(Gtk.Application app)
		{
			Object(application: app, title: "Sherpa ONNX Preferences",
				resizable: false, default_width: 520, default_height: 560);
			this.config = Config.load();

			var page = new Adw.PreferencesPage();
			var listening = new Adw.PreferencesGroup() { title = "Listening" };
			page.add(listening);
			this.add("hotkey", new RowKeySelect(this.config, "hotkey", "Toggle hotkey",
				"Click, then press a key combination"), listening);
			this.add("notifications", new RowSwitch(this.config, "notifications",
				"Desktop notifications", "Notify when listening starts or stops"), listening);
			this.add("preedit-animation", new RowSwitch(this.config, "preedit-animation",
				"Preedit listening animation", "Show . … while waiting for speech"), listening);

			var models = new Adw.PreferencesGroup() {
				title = "Select model",
				description = "Closing installs or switches to the selection"
			};
			page.add(models);
			var model = new RowSelect(this.config, this.download);
			this.rows.set("model", model);
			model.add_to(models);

			this.stack = new Gtk.Stack();
			this.stack.add_named(page, "prefs");
			this.stack.add_named(this.download, "download");
			this.stack.visible_child_name = "prefs";

			this.close_btn = new Gtk.Button.with_label("Close");
			this.close_btn.clicked.connect(() => {
				this.close();
			});
			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false, show_end_title_buttons = false
			};
			header.pack_end(this.close_btn);
			var toolbar = new Adw.ToolbarView();
			toolbar.add_top_bar(header);
			toolbar.content = this.stack;
			this.content = toolbar;

			this.download.finished.connect((ok, message) => {
				if (!ok) {
					return;
				}
				GLib.Timeout.add(800, () => {
					this.destroy();
					return GLib.Source.REMOVE;
				});
			});
			this.download.cancelled.connect(() => {
				this.stack.visible_child_name = "prefs";
				this.close_btn.visible = true;
			});

			this.close_request.connect(this.on_close_request);
			this.fill();
		}

		/**
		 * Register a row by config key and add its widget to ''section''.
		 */
		public void add(string name, Row row, Adw.PreferencesGroup section)
		{
			this.rows.set(name, row);
			section.add(row.row);
		}

		/** Reload rows from disk. */
		public void fill()
		{
			this.config = Config.load();
			foreach (var name in this.rows.get_keys()) {
				var row = this.rows.get(name);
				row.config = this.config;
				row.fill();
			}
		}

		private bool on_close_request()
		{
			if (this.download.busy || this.stack.visible_child_name == "download") {
				return true;
			}
			((RowKeySelect) this.rows.get("hotkey")).fill();
			this.config.save();

			var chunk = ((RowSelect) this.rows.get("model")).selected_chunk();
			if (!this.download.apply(chunk)) {
				return false;
			}
			this.stack.visible_child_name = "download";
			this.close_btn.visible = false;
			return true;
		}
	}
}
