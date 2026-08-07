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
	 * {@link ModelDownload.chunks}. Selection is applied on prefs close via
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
		 * @param download Model list + install helper
		 */
		public RowSelect(Config config, ModelDownload download)
		{
			base(config, "model", "None", "No model selected");
			this.download = download;
			this.none_btn = new Gtk.CheckButton();
			((Adw.ActionRow) this.row).add_prefix(this.none_btn);
			((Adw.ActionRow) this.row).set_activatable_widget(this.none_btn);

			this.chunk_btns = new Gtk.CheckButton[download.chunks.length];
			this.chunk_rows = new Adw.ActionRow[download.chunks.length];
			for (var i = 0; i < download.chunks.length; i++) {
				var chunk = download.chunks[i];
				var dir = "sherpa-onnx-nemotron-speech-streaming-en-0.6b-%dms-int8-2026-04-25".printf(chunk);
				var system_dir = GLib.Path.build_filename("/usr/share/ibus-sherpa-onnx/models", dir);
				var user_dir = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(),
					"ibus-sherpa-onnx", "models", dir);
				var subtitle = download.sizes[i];
				if (download.ready(system_dir) || download.ready(user_dir)) {
					subtitle += " · installed";
				}
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
					return this.download.chunks[i];
				}
			}
			return 0;
		}

		public override void fill()
		{
			this.loading = true;
			var selected = 0;
			var model = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(),
				"ibus-sherpa-onnx", "model");
			try {
				var target = GLib.FileUtils.read_link(model);
				foreach (var chunk in this.download.chunks) {
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
			for (var i = 0; i < this.download.chunks.length; i++) {
				if (this.download.chunks[i] != selected) {
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
