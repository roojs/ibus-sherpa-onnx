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
	 * Reassemble appsink PCM into saved live ''accept_waveform'' sizes.
	 *
	 * Pending PCM lives in a {@link GLib.Array} (bulk ''append_vals'' /
	 * ''g_array_remove_range''). Vala’s ''remove_range'' returns an owned
	 * ''G[]'' that is wrong for ''float'' — peel with ''Memory.copy'' +
	 * ''_remove_range'' instead. Gee is not used here (no bulk front peel
	 * for float, and the engine/CLI targets do not link gee-0.8).
	 */
	public class Feed : GLib.Object
	{
		private int[] sizes;
		private int index;
		private GLib.Array<float> pending = new GLib.Array<float>(false, false, (uint) sizeof(float));
		private bool eos;

		public Feed(int[] chunk_ns)
		{
			this.sizes = chunk_ns;
			this.index = 0;
		}

		public void push(float[] samples)
		{
			this.pending.append_vals(samples, samples.length);
		}

		public void finish()
		{
			this.eos = true;
		}

		public float[]? take()
		{
			while (this.index < this.sizes.length) {
				var need = this.sizes[this.index];
				if (this.pending.length < need) {
					break;
				}
				this.index++;
				var slice = new float[need];
				Memory.copy(slice, this.pending.data, need * sizeof(float));
				this.pending._remove_range(0, need);
				return slice;
			}
			if (this.eos && this.pending.length > 0) {
				var n = this.pending.length;
				var slice = new float[n];
				Memory.copy(slice, this.pending.data, n * sizeof(float));
				this.pending._remove_range(0, n);
				return slice;
			}
			return null;
		}
	}
}
