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
	 * Left-hand {@link Gtk.ColumnView} of debug recordings (newest first).
	 *
	 * Caps at 50 rows. Day directories already scanned are reused from
	 * {@link day_stamps} so fill does not re-Dir them.
	 */
	public class History : Gtk.Box
	{
		private const int MAX_ITEMS = 50;

		private GLib.ListStore store;
		private Gtk.SingleSelection selection;

		/** Cached HHMMSS stamps per YYYY-MM-DD (newest first). */
		private Gee.HashMap<string, Gee.ArrayList<string>> day_stamps;

		/**
		 * A row was selected (or selection cleared when ''item'' is null).
		 *
		 * @param item selected recording, or null
		 */
		public signal void selected(HistoryItem? item);

		public History()
		{
			GLib.Object(
				orientation: Gtk.Orientation.VERTICAL,
				hexpand: false,
				vexpand: true
			);
			this.set_size_request(320, -1);
			this.day_stamps = new Gee.HashMap<string, Gee.ArrayList<string>>();

			this.store = new GLib.ListStore(typeof(HistoryItem));
			this.selection = new Gtk.SingleSelection(this.store) {
				autoselect = false,
				can_unselect = true
			};
			this.selection.notify["selected-item"].connect(() => {
				this.selected(this.selection.selected_item as HistoryItem);
			});

			var factory = new Gtk.SignalListItemFactory();
			factory.setup.connect((f, obj) => {
				var when = new Gtk.Label("") {
					xalign = 0,
					ellipsize = Pango.EllipsizeMode.END
				};
				when.add_css_class("caption");
				var preview = new Gtk.Label("") {
					xalign = 0,
					ellipsize = Pango.EllipsizeMode.END
				};
				var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2) {
					margin_top = 6,
					margin_bottom = 6,
					margin_start = 8,
					margin_end = 8
				};
				box.append(when);
				box.append(preview);
				((Gtk.ListItem) obj).child = box;
			});
			factory.bind.connect((f, obj) => {
				var list_item = (Gtk.ListItem) obj;
				var item = list_item.item as HistoryItem;
				var box = (Gtk.Box) list_item.child;
				var when = (Gtk.Label) box.get_first_child();
				var preview = (Gtk.Label) when.get_next_sibling();
				if (item == null) {
					when.label = "";
					preview.label = "";
					return;
				}
				when.label = "%s %s".printf(item.weekday, item.time);
				preview.label = item.preview;
			});
			var view = new Gtk.ColumnView(this.selection) {
				hexpand = true,
				vexpand = true,
				show_column_separators = false,
				show_row_separators = true
			};
			view.append_column(new Gtk.ColumnViewColumn(null, factory) {
				expand = true
			});
			this.append(new Gtk.ScrolledWindow() {
				child = view,
				hexpand = true,
				vexpand = true
			});
			this.fill();
		}

		/** Rebuild rows from cache / disk (newest first, max {@link MAX_ITEMS}). */
		public void fill()
		{
			this.store.remove_all();
			var root = GLib.Path.build_filename(GLib.Environment.get_user_cache_dir(),
				"ibus-sherpa-onnx", "debug");
			if (!GLib.FileUtils.test(root, GLib.FileTest.IS_DIR)) {
				return;
			}

			try {
				var root_dir = GLib.Dir.open(root);
				string? day_name;
				var days = new Gee.ArrayList<string>();
				while ((day_name = root_dir.read_name()) != null) {
					if (day_name.length == 10) {
						days.add(day_name);
					}
				}
				days.sort((a, b) => -strcmp(a, b));
				foreach (var day in days) {
					if (this.store.n_items >= MAX_ITEMS) {
						return;
					}
					var day_path = GLib.Path.build_filename(root, day);
					if (!GLib.FileUtils.test(day_path, GLib.FileTest.IS_DIR)) {
						continue;
					}
					var stamps = this.stamps_for_day(day, day_path);
					foreach (var stamp in stamps) {
						if (this.store.n_items >= MAX_ITEMS) {
							return;
						}
						this.store.append(new HistoryItem(day, day_path, stamp));
					}
				}
			} catch (GLib.Error err) {
				GLib.warning("scan debug recordings: %s", err.message);
			}
		}

		/**
		 * Stamps for ''day'', from {@link day_stamps} or a one-time Dir scan.
		 *
		 * @param day YYYY-MM-DD
		 * @param day_path Absolute day directory
		 */
		private Gee.ArrayList<string> stamps_for_day(string day, string day_path) throws GLib.Error
		{
			if (this.day_stamps.has_key(day)) {
				return this.day_stamps.get(day);
			}
			var stamps = new Gee.ArrayList<string>();
			var day_dir = GLib.Dir.open(day_path);
			string? name;
			while ((name = day_dir.read_name()) != null) {
				if (!name.has_suffix(".txt") || name.has_suffix(".out.txt")) {
					continue;
				}
				stamps.add(name.substring(0, name.length - 4));
			}
			stamps.sort((a, b) => -strcmp(a, b));
			this.day_stamps.set(day, stamps);
			return stamps;
		}
	}
}
