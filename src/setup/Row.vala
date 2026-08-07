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
	 * Preferences row bound to one ''general'' key in {@link Config.key_file}.
	 *
	 * Composes an {@link Adw.PreferencesRow} (does not subclass
	 * {@link Adw.ActionRow}). Same pattern as RooTerm ''Dialog.Row''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var hotkey = new RowKeySelect(config, "hotkey", "Toggle hotkey", "...");
	 * group.add(hotkey.row);
	 * hotkey.fill();
	 * }}}
	 */
	public abstract class Row : GLib.Object
	{
		/**
		 * Widget to add to an {@link Adw.PreferencesGroup}.
		 */
		public Adw.PreferencesRow row;

		/**
		 * Settings this row edits.
		 */
		public Config config;

		/**
		 * Key under group ''general'' (e.g. ''hotkey'').
		 */
		public string key;

		/**
		 * True while {@link fill} is updating widgets (ignore control signals).
		 */
		public bool loading = false;

		/**
		 * @param config Settings object
		 * @param key KeyFile key under ''general''
		 * @param title Action row title
		 * @param subtitle Action row subtitle
		 */
		protected Row(Config config, string key, string title, string subtitle)
		{
			this.config = config;
			this.key = key;
			this.row = new Adw.ActionRow() {
				title = title,
				subtitle = subtitle
			};
		}

		/**
		 * Load the widget from {@link config}.{@link Config.key_file}.
		 */
		public abstract void fill();
	}
}
