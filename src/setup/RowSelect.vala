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
	 * Radio list for Nemotron chunk selection: None plus each size in
	 * {@link Models.chunks}. Selection is applied on prefs close via
	 * {@link ModelDownload.apply}, not written to {@link Config.key_file}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var model = new RowSelect(config, download);
	 * model.add_to(group);
	 * model.fill();
	 * }}}
	 */
	public class RowSelect : Row
	{
		private ModelDownload download;
		private Gtk.CheckButton none_btn;
		private Gtk.CheckButton[] chunk_btns;
		private Adw.ActionRow[] chunk_rows;

		/**
		 * Build None + chunk radio rows (not yet added to a group).
		 *
		 * @param config Settings object (unused for value; kept for Row API)
		 * @param download Install helper (uses {@link ModelDownload.models})
		 */
		public RowSelect(Config config, ModelDownload download)
		{
			base(config, "model", "None", "No model selected");
			this.download = download;
			this.none_btn = new Gtk.CheckButton();
			((Adw.ActionRow) this.row).add_prefix(this.none_btn);
			((Adw.ActionRow) this.row).set_activatable_widget(this.none_btn);

			var models = download.models;
			this.chunk_btns = new Gtk.CheckButton[models.chunks.length];
			this.chunk_rows = new Adw.ActionRow[models.chunks.length];
			for (var i = 0; i < models.chunks.length; i++) {
				var chunk = models.chunks[i];
				var system_dir = GLib.Path.build_filename(models.system_prefix,
					"models", models.names[i]);
				var subtitle = models.sizes[i] + (models.ready(system_dir)
					? " · installed"
					: " · needs downloading");
				var btn = new Gtk.CheckButton() { group = this.none_btn };
				this.chunk_btns[i] = btn;
				this.chunk_rows[i] = new Adw.ActionRow() {
					title = "%d ms".printf(chunk), subtitle = subtitle
				};
				this.chunk_rows[i].add_prefix(btn);
				this.chunk_rows[i].set_activatable_widget(btn);
			}
		}

		/**
		 * Add None and chunk rows to ''section''.
		 *
		 * @param section Preferences group for Select model
		 */
		public void add_to(Adw.PreferencesGroup section)
		{
			section.add(this.row);
			foreach (var chunk_row in this.chunk_rows) {
				section.add(chunk_row);
			}
		}

		/**
		 * Selected chunk ms, or 0 for None.
		 */
		public int selected_chunk()
		{
			if (this.none_btn.active) {
				return 0;
			}
			for (var i = 0; i < this.chunk_btns.length; i++) {
				if (this.chunk_btns[i].active) {
					return this.download.models.chunks[i];
				}
			}
			return 0;
		}

		public override void fill()
		{
			this.loading = true;
			var selected = 0;
			var models = this.download.models;
			try {
				var target = GLib.FileUtils.read_link(
					GLib.Path.build_filename(models.user_config, "model"));
				foreach (var chunk in models.chunks) {
					if (!target.contains("-%dms-".printf(chunk))) {
						continue;
					}
					selected = chunk;
					break;
				}
			} catch (GLib.FileError err) {
			}
			if (selected == 0) {
				this.none_btn.active = true;
				this.loading = false;
				return;
			}
			for (var i = 0; i < models.chunks.length; i++) {
				if (models.chunks[i] != selected) {
					continue;
				}
				this.chunk_btns[i].active = true;
				this.loading = false;
				return;
			}
			this.none_btn.active = true;
			this.loading = false;
		}
	}
}
