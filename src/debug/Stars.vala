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
	 * Horizontal 1–5 star control (toggle buttons).
	 *
	 * == Example ==
	 *
	 * {{{
	 * var stars = new Stars();
	 * stars.fill(4);
	 * stars.changed.connect((n) => { … });
	 * }}}
	 */
	public class Stars : Gtk.Box
	{
		/**
		 * True while {@link fill} is updating the toggles (ignore
		 * ''toggled'').
		 */
		private bool loading = false;

		private Gtk.ToggleButton[] buttons = {};

		/**
		 * Current rating: ''0'' unset, or ''1''–''5''.
		 */
		public int rating { get; private set; default = 0; }

		/**
		 * User picked a star (after UI update).
		 *
		 * @param rating ''1''–''5''
		 */
		public signal void changed(int rating);

		public Stars()
		{
			GLib.Object(
				orientation: Gtk.Orientation.HORIZONTAL,
				spacing: 2
			);
			for (var i = 1; i <= 5; i++) {
				var n = i;
				var btn = new Gtk.ToggleButton() {
					label = "★"
				};
				btn.toggled.connect(() => {
					if (this.loading || !btn.active) {
						return;
					}
					this.fill(n);
					this.changed(n);
				});
				this.buttons += btn;
				this.append(btn);
			}
		}

		/**
		 * Set rating and sync star toggles.
		 *
		 * @param rating ''0''–''5'' (clamped)
		 */
		public void fill(int rating)
		{
			this.loading = true;
			this.rating = int.min(5, int.max(0, rating));
			for (var i = 0; i < this.buttons.length; i++) {
				this.buttons[i].active = (i < this.rating);
			}
			this.loading = false;
		}
	}
}
