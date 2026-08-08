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
	 * Radio list of model packs from {@link Models.packs}.
	 *
	 * Set {@link family} to match ''languages.ini''; each pack row binds
	 * ''visible'' with a transform (''family == pack_family''). Selection is
	 * applied on prefs close via {@link ModelDownload.apply}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var model = new RowSelectModel(config, download);
	 * model.add_to(group);
	 * model.family = "nemotron-en";
	 * model.fill();
	 * }}}
	 */
	public class RowSelectModel : Row
	{
		/**
		 * Active model family (''nemotron-en'' / ''nemotron-3.5-ml'').
		 */
		public string family { get; set; default = ""; }

		/**
		 * Selected pack id, or "" for None.
		 */
		public string current_id { get; private set; default = ""; }

		private ModelDownload download;
		private Gtk.CheckButton none_btn;
		private Gee.HashMap<string, Gtk.CheckButton> buttons;
		private Gee.ArrayList<Adw.ActionRow> option_rows;
		/** ''family:chunk'' → pack id (filled once when rows are built). */
		private Gee.HashMap<string, string> id_by_family_chunk;
		/** Last selected chunk size (560 / 1120); kept across family changes. */
		private int chunk = 0;

		/**
		 * @param config Settings object (Row API)
		 * @param download Install helper (uses {@link ModelDownload.models})
		 */
		public RowSelectModel(Config config, ModelDownload download)
		{
			base(config, "model", "None", "No model selected");
			this.download = download;
			this.buttons = new Gee.HashMap<string, Gtk.CheckButton>();
			this.option_rows = new Gee.ArrayList<Adw.ActionRow>();
			this.id_by_family_chunk = new Gee.HashMap<string, string>();
			this.none_btn = new Gtk.CheckButton();
			((Adw.ActionRow) this.row).add_prefix(this.none_btn);
			((Adw.ActionRow) this.row).set_activatable_widget(this.none_btn);
			this.none_btn.notify["active"].connect(() => {
				if (!this.none_btn.active) {
					return;
				}
				this.current_id = "";
			});
			this.notify["family"].connect(() => {
				if (this.current_id != "") {
					var pack_family = this.download.models.packs.get_string(this.current_id, "family");
					if (pack_family == this.family) {
						return;
					}
				}
				if (this.chunk > 0) {
					var key = "%s:%d".printf(this.family, this.chunk);
					if (this.id_by_family_chunk.has_key(key)) {
						this.select_id(this.id_by_family_chunk.get(key));
						return;
					}
				}
				this.none_btn.active = true;
			});

			var models = download.models;
			foreach (var pack_id in models.packs.get_groups()) {
				var name = models.packs.get_string(pack_id, "name");
				var chunk = models.packs.get_integer(pack_id, "chunk");
				var bytes = models.packs.get_int64(pack_id, "archive_bytes");
				var pack_family = models.packs.get_string(pack_id, "family");
				var system_dir = GLib.Path.build_filename(models.system_prefix, "models", name);
				var installed = GLib.FileUtils.test(
					GLib.Path.build_filename(system_dir, ".sha256"), GLib.FileTest.IS_REGULAR);
				var subtitle = "~%.0f MB".printf(bytes / (1024.0 * 1024.0))
					+ (installed ? " · installed" : " · needs downloading");
				this.id_by_family_chunk.set("%s:%d".printf(pack_family, chunk), pack_id);
				this.add_option(pack_id, chunk, subtitle, pack_family);
			}
		}

		/**
		 * Add None and pack rows to ''section''.
		 */
		public void add_to(Adw.PreferencesGroup section)
		{
			section.add(this.row);
			foreach (var option_row in this.option_rows) {
				section.add(option_row);
			}
		}

		public override void fill()
		{
			this.loading = true;
			var selected = "";
			try {
				var language = this.config.key_file.get_string("general", "language");
				selected = this.config.packs.get_string("packs", language);
			} catch (GLib.Error err) {
			}
			this.select_id(selected);
			this.loading = false;
		}

		private void add_option(string id, int chunk, string subtitle, string pack_family)
		{
			var btn = new Gtk.CheckButton() { group = this.none_btn };
			var option_row = new Adw.ActionRow() {
				title = "%d ms".printf(chunk),
				subtitle = subtitle
			};
			option_row.add_prefix(btn);
			option_row.set_activatable_widget(btn);
			btn.notify["active"].connect(() => {
				if (!btn.active) {
					return;
				}
				this.current_id = id;
				this.chunk = chunk;
			});
			this.bind_property("family", option_row, "visible", BindingFlags.SYNC_CREATE,
				(binding, from_value, ref to_value) => {
					to_value.set_boolean(from_value.get_string() == pack_family);
					return true;
				});
			this.buttons.set(id, btn);
			this.option_rows.add(option_row);
		}

		private void select_id(string id)
		{
			if (id == "") {
				this.none_btn.active = true;
				return;
			}
			if (!this.buttons.has_key(id)) {
				this.none_btn.active = true;
				return;
			}
			this.buttons.get(id).active = true;
		}
	}
}
