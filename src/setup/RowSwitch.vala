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
	 * Boolean {@link Gtk.Switch} suffix on an {@link Adw.ActionRow} for a
	 * KeyFile bool under ''general''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var notify = new RowSwitch(config, "notifications", "Desktop notifications", "…");
	 * group.add(notify.row);
	 * notify.fill();
	 * }}}
	 */
	public class RowSwitch : Row
	{
		public Gtk.Switch sw;

		/**
		 * @param config Settings object
		 * @param key Bool key under ''general''
		 * @param title Action row title
		 * @param subtitle Action row subtitle
		 */
		public RowSwitch(Config config, string key, string title, string subtitle)
		{
			base(config, key, title, subtitle);
			this.sw = new Gtk.Switch() {
				valign = Gtk.Align.CENTER
			};
			this.sw.notify["active"].connect(() => {
				if (this.loading) {
					return;
				}
				this.config.key_file.set_boolean("general", this.key, this.sw.active);
				this.config.save();
			});
			((Adw.ActionRow) this.row).add_suffix(this.sw);
			((Adw.ActionRow) this.row).set_activatable_widget(this.sw);
		}

		public override void fill()
		{
			this.loading = true;
			try {
				this.sw.active = this.config.key_file.get_boolean("general", this.key);
			} catch (GLib.KeyFileError err) {
				this.sw.active = false;
			}
			this.loading = false;
		}
	}
}
