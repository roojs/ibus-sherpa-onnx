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

		private Models models = new Models();
		private ModelDownload download;
		private Gtk.Stack stack;
		private Gtk.Button close_btn;

		public Preferences(Gtk.Application app)
		{
			Object(application: app, title: "Sherpa ONNX Preferences",
				resizable: false, default_width: 520, default_height: 560);
			this.config = Config.load();
			this.download = new ModelDownload(this.models);

			var page = new Adw.PreferencesPage();
			var listening = new Adw.PreferencesGroup() { title = "Listening" };
			page.add(listening);
			this.add("hotkey", new RowKeySelect(this.config, "hotkey", "Toggle hotkey",
				"Click, then press a key combination"), listening);
			this.add("notifications", new RowSwitch(this.config, "notifications",
				"Desktop notifications", "Notify when listening starts or stops"), listening);
			this.add("preedit-animation", new RowSwitch(this.config, "preedit-animation",
				"Preedit listening animation", "Show . .. ... while waiting for speech"), listening);

			var models = new Adw.PreferencesGroup() {
				title = "Select model",
				description = "Closing installs or switches to the selection"
			};
			page.add(models);
			var model = new RowSelect(this.config, this.download);
			this.rows.set("model", model);
			model.add_to(models);

			this.stack = new Gtk.Stack() {
				vhomogeneous = false, hhomogeneous = false
			};
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
				this.restart_ibus();
			});
			this.download.cancelled.connect(() => {
				this.show_page("prefs");
			});

			this.close_request.connect(this.on_close_request);
			this.fill();
		}

		/**
		 * Switch stack page and resize the window to that page’s natural height.
		 */
		private void show_page(string name)
		{
			this.stack.visible_child_name = name;
			this.close_btn.visible = (name == "prefs");
			/* Non-homogeneous stack still leaves the old allocation; force a new default size. */
			this.resizable = true;
			if (name == "prefs") {
				this.set_default_size(520, 560);
			} else {
				var nat = 0;
				this.stack.measure(Gtk.Orientation.VERTICAL, 520, null, out nat, null, null);
				this.set_default_size(520, int.max(nat + 52, 160));
			}
			this.resizable = false;
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
				if (chunk != 0) {
					this.restart_ibus();
					return true;
				}
				return false;
			}
			this.show_page("download");
			return true;
		}

		/**
		 * Make Sherpa the active GNOME IME, ''ibus restart'', close.
		 */
		private void restart_ibus()
		{
			this.install();
			try {
				GLib.Process.spawn_async(null, { "ibus", "restart" }, null,
					GLib.SpawnFlags.SEARCH_PATH, null, null);
			} catch (GLib.Error err) {
				GLib.warning("ibus restart: %s", err.message);
			}
			this.destroy();
		}

		/**
		 * Install Sherpa as the active GNOME IME: add to input sources if needed
		 * and set ''current'' so the user does not hunt in Settings.
		 * Component XML still supplies language/layout (''en'' / ''us'').
		 */
		private void install()
		{
			var schema = GLib.SettingsSchemaSource.get_default().lookup(
				"org.gnome.desktop.input-sources", true);
			if (schema == null) {
				return;
			}
			var settings = new GLib.Settings.full(schema, null, null);
			if (schema.has_key("show-all-sources")) {
				settings.set_boolean("show-all-sources", true);
			}
			var builder = new GLib.VariantBuilder(new GLib.VariantType("a(ss)"));
			var index = -1, i = 0;
			string typ, name;
			var iter = settings.get_value("sources").iterator();
			while (iter.next("(ss)", out typ, out name)) {
				builder.add("(ss)", typ, name);
				if (typ == "ibus" && name == "sherpa-onnx") {
					index = i;
				}
				i++;
			}
			if (index < 0) {
				builder.add("(ss)", "ibus", "sherpa-onnx");
				index = i;
				settings.set_value("sources", builder.end());
			}
			settings.set_uint("current", (uint) index);
		}
	}
}
