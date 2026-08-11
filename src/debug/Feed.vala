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
				if (need < 1) {
					this.index++;
					continue;
				}
				if (this.pending.length < need) {
					break;
				}
				var slice = new float[need];
				GLib.Memory.copy((void*) slice, this.pending.data, need * sizeof(float));
				this.pending.remove_range(0, need);
				this.index++;
				return slice;
			}
			if (this.eos && this.pending.length > 0) {
				var n = (int) this.pending.length;
				var left = new float[n];
				GLib.Memory.copy((void*) left, this.pending.data, n * sizeof(float));
				this.pending.set_size(0);
				return left;
			}
			return null;
		}
	}
}
