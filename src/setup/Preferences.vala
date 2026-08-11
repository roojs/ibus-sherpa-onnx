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
	 * Preferences: General (Listening + Select model) and Debug tabs.
	 * Standalone {@link Adw.Window} — RooTerm ''Dialog.Preferences'' shell.
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
		private Adw.ActionRow browse_row;

		public Preferences(Gtk.Application app)
		{
			GLib.Object(
				application: app,
				title: "Sherpa ONNX Preferences",
				resizable: false,
				default_width: 720,
				default_height: 720
			);
			this.config = Config.load();
			this.download = new ModelDownload(this.models);

			var general = new Adw.PreferencesPage() {
				title = "General",
				icon_name = "preferences-system-symbolic"
			};
			var listening = new Adw.PreferencesGroup() { title = "Listening" };
			general.add(listening);
			this.add("hotkey", new RowKeySelect(this.config, "hotkey", "Toggle hotkey",
				"Click, then press a key combination"), listening);
			this.add("notifications", new RowSwitch(this.config, "notifications",
				"Desktop notifications", "Notify when listening starts or stops"), listening);
			this.add("preedit-animation", new RowSwitch(this.config, "preedit-animation",
				"Preedit listening animation", "Show . .. ... while waiting for speech"), listening);
			this.add("mute-speakers", new RowSwitch(this.config, "mute-speakers",
				"Mute speakers while listening", "Silence system audio output during dictation"), listening);

			var models = new Adw.PreferencesGroup() {
				title = "Select model",
				description = "Closing installs or switches to the selection"
			};
			general.add(models);
			var language = new RowComboLanguage(this.config, this.models);
			this.rows.set("language", language);
			models.add(language.row);
			var model = new RowSelectModel(this.config, this.download);
			this.rows.set("model", model);
			model.add_to(models);

			language.changed.connect((code) => {
				model.family = this.models.languages.get_string(code, "family");
				model.fill();
			});

			var debug_page = new Adw.PreferencesPage() {
				title = "Debug",
				icon_name = "applications-engineering-symbolic"
			};
			var debug_group = new Adw.PreferencesGroup() {
				title = "Debug recordings",
				description = "Save utterance audio and text under ~/.cache/ibus-sherpa-onnx/debug/"
			};
			debug_page.add(debug_group);
			var debug_sw = new RowSwitch(this.config, "debug-recordings",
				"Save debug recordings", "Record each committed utterance for later review");
			this.add("debug-recordings", debug_sw, debug_group);

			this.browse_row = new Adw.ActionRow() {
				title = "Browse recordings"
			};
			var browse_btn = new Gtk.Button.with_label("Browse…") {
				valign = Gtk.Align.CENTER
			};
			browse_btn.clicked.connect(() => {
				var win = new IBSO.Debug.Dialog(this);
				win.present();
			});
			this.browse_row.add_suffix(browse_btn);
			this.browse_row.set_activatable_widget(browse_btn);
			debug_group.add(this.browse_row);
			((RowSwitch) this.rows.get("debug-recordings")).sw.notify["active"].connect(() => {
				this.browse_row.visible =
					((RowSwitch) this.rows.get("debug-recordings")).sw.active;
			});

			var pages = new Adw.ViewStack();
			pages.add_titled(general, "general", "General");
			pages.add_titled(debug_page, "debug", "Debug");

			this.stack = new Gtk.Stack() {
				vhomogeneous = false,
				hhomogeneous = false
			};
			this.stack.add_named(pages, "prefs");
			this.stack.add_named(this.download, "download");
			this.stack.visible_child_name = "prefs";

			this.close_btn = new Gtk.Button.with_label("Close");
			this.close_btn.clicked.connect(() => {
				this.close();
			});
			var header = new Adw.HeaderBar() {
				show_start_title_buttons = false,
				show_end_title_buttons = false,
				title_widget = new Adw.ViewSwitcher() {
					stack = pages,
					policy = Adw.ViewSwitcherPolicy.WIDE
				}
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
				this.set_default_size(720, 720);
				this.resizable = false;
				return;
			}
			var nat = 0;
			this.stack.measure(Gtk.Orientation.VERTICAL, 720, null, out nat, null, null);
			this.set_default_size(720, int.max(nat + 52, 160));
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

		/** Reload rows from disk; language combo follows the active IBus engine. */
		public void fill()
		{
			this.config = Config.load();

			var id = "";
			var bus = new IBus.Bus();
			if (bus.is_connected()) {
				var eng = bus.get_global_engine();
				id = eng != null ? eng.get_name() : "";
			}
			if (id == "sherpa-onnx") {
				this.config.key_file.set_string("general", "language", "en");
			}
			if (id.has_prefix("sherpa-onnx-")) {
				this.config.key_file.set_string("general", "language",
					id.substring("sherpa-onnx-".length));
			}

			var model = (RowSelectModel) this.rows.get("model");
			var code = this.config.key_file.get_string("general", "language");
			model.family = this.models.languages.get_string(code, "family");
			foreach (var name in this.rows.get_keys()) {
				var row = this.rows.get(name);
				row.config = this.config;
				row.fill();
			}
			this.browse_row.visible =
				((RowSwitch) this.rows.get("debug-recordings")).sw.active;
		}

		private bool on_close_request()
		{
			if (this.download.busy || this.stack.visible_child_name == "download") {
				return true;
			}
			((RowKeySelect) this.rows.get("hotkey")).fill();

			var language = this.config.key_file.get_string("general", "language");
			var pack_id = ((RowSelectModel) this.rows.get("model")).current_id;
			if (pack_id != "") {
				this.config.packs.set_string("packs", language, pack_id);
				/* Bare engine id is ''en''; GNOME often uses that instead of en-GB. */
				if (language != "en" && language.has_prefix("en")) {
					this.config.packs.set_string("packs", "en", pack_id);
				}
			} else if (this.config.packs.has_group("packs")
					&& this.config.packs.has_key("packs", language)) {
				this.config.packs.remove_key("packs", language);
			}
			this.config.save();
			this.config.save_packs();

			if (!this.download.apply(pack_id)) {
				this.restart_ibus();
				return true;
			}
			this.show_page("download");
			return true;
		}

		/**
		 * Register the prefs language’s IBus engine as the active GNOME IME,
		 * ''ibus restart'', close.
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
		 * Add the engine for ''general/language='' to GNOME input sources and
		 * make it current (Settings groups it under that language).
		 */
		private void install()
		{
			var language = this.config.key_file.get_string("general", "language");
			var engine = language == "en" ? "sherpa-onnx" : "sherpa-onnx-" + language;
			this.install_setup_desktop(engine);
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
				if (typ == "ibus" && name == engine) {
					index = i;
				}
				i++;
			}
			if (index < 0) {
				builder.add("(ss)", "ibus", engine);
				index = i;
				settings.set_value("sources", builder.end());
			}
			/* ''current'' is ignored by modern GNOME; switch the live IBus engine. */
			var bus = new IBus.Bus();
			if (bus.is_connected()) {
				bus.set_global_engine(engine);
			}
		}

		/**
		 * GNOME Settings ⋯ resolves ''ibus-setup-&lt;engine&gt;.desktop''.
		 * Bare ''sherpa-onnx'' is packaged under ''/usr/share''; language
		 * engines get a copy in ''~/.local/share/applications/'' from the
		 * embedded template.
		 *
		 * @param engine IBus engine id (''sherpa-onnx-es-ES'', …)
		 */
		private void install_setup_desktop(string engine)
		{
			if (engine == "sherpa-onnx") {
				return;
			}
			try {
				var bytes = GLib.resources_lookup_data(
					"/ibus-setup-engine.desktop.in", GLib.ResourceLookupFlags.NONE);
				var text = ((string) bytes.get_data())
					.substring(0, (long) bytes.get_size())
					.replace("@ENGINE@", engine);
				var dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(), "applications");
				GLib.DirUtils.create_with_parents(dir, 0755);
				var path = GLib.Path.build_filename(dir,
					"ibus-setup-%s.desktop".printf(engine));
				GLib.FileUtils.set_contents(path, text);
			} catch (GLib.Error err) {
				GLib.warning("setup desktop %s: %s", engine, err.message);
			}
		}
	}
}
