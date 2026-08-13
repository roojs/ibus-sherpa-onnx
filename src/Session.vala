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

namespace IBSO
{
	/**
	 * One listen-session buffer for debug recordings ({@link Transcriber}).
	 *
	 * Live: {@link Transcriber} accumulates PCM / chunks / endpoints when
	 * ''save'', then {@link flush} on stop. Replay / CLI: {@link Session.load}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * this.session.pcm.append_vals(samples, samples.length);
	 * this.session.chunk_n.append_val(samples.length);
	 * this.session.endpoint_off.append_val(this.session.accepted);
	 * var sess = this.session;
	 * this.session = new Session();
	 * sess.flush();
	 *
	 * var recorded = new Session.load(stem + ".wav");
	 * transcriber.begin_file(recorded);
	 * }}}
	 */
	public class Session : GLib.Object
	{
		/**
		 * Float PCM for the whole listen when recording is on (includes pauses).
		 */
		public GLib.Array<float> pcm = new GLib.Array<float>(false, false, (uint) sizeof(float));

		/**
		 * Sample counts per live ''accept_waveform'' (''.chunks'').
		 */
		public GLib.Array<int> chunk_n = new GLib.Array<int>(false, false, (uint) sizeof(int));

		/**
		 * Sample positions where live endpoint reset (''.endpoints'').
		 */
		public GLib.Array<int> endpoint_off = new GLib.Array<int>(false, false, (uint) sizeof(int));

		/** Samples accepted so far this listen. */
		public int accepted { get; set; default = 0; }

		/** Committed endpoint texts (newline between). */
		public string text { get; set; default = ""; }

		/** True while this listen should append PCM / chunks / endpoints. */
		public bool recording { get; set; default = false; }

		/** Wall time at listen start (debug file basename). */
		public GLib.DateTime? started { get; set; default = null; }

		/** Pending partial from stop(). */
		public string pending { get; set; default = ""; }

		/**
		 * Load a saved listen from sibling ''.f32'' / ''.chunks'' / ''.endpoints'' /
		 * ''.pending'' next to ''path'' (''.wav'' or stem). Missing sidecars leave
		 * the matching fields empty.
		 *
		 * @param path absolute ''.wav'' path or recording stem
		 */
		public Session.load(string path)
		{
			GLib.Object();
			var stem = path.has_suffix(".wav")
				? path.slice(0, path.length - 4)
				: path;

			try {
				uint8[] data;
				GLib.FileUtils.get_data(stem + ".f32", out data);
				if (data.length == 0 || data.length % (int) sizeof(float) != 0) {
					if (data.length > 0) {
						GLib.warning("debug f32 invalid: %s.f32 (%d bytes)", stem, data.length);
					}
				} else {
					var n = data.length / (int) sizeof(float);
					var samples = new float[n];
					GLib.Memory.copy((void*) samples, data, data.length);
					this.pcm.append_vals(samples, n);
				}
			} catch (GLib.Error err) {
			}

			try {
				uint8[] data;
				GLib.FileUtils.get_data(stem + ".chunks", out data);
				if (data.length == 0 || data.length % (int) sizeof(int) != 0) {
					if (data.length > 0) {
						GLib.warning("debug chunks invalid: %s.chunks (%d bytes)", stem, data.length);
					}
				} else {
					var n = data.length / (int) sizeof(int);
					var chunk_ns = new int[n];
					GLib.Memory.copy((void*) chunk_ns, data, data.length);
					for (var i = 0; i < n; i++) {
						var cn = chunk_ns[i];
						this.chunk_n.append_val(cn);
					}
				}
			} catch (GLib.Error err) {
			}

			try {
				uint8[] data;
				GLib.FileUtils.get_data(stem + ".endpoints", out data);
				if (data.length == 0 || data.length % (int) sizeof(int) != 0) {
					if (data.length > 0) {
						GLib.warning("debug endpoints invalid: %s.endpoints (%d bytes)", stem, data.length);
					}
				} else {
					var n = data.length / (int) sizeof(int);
					var offs = new int[n];
					GLib.Memory.copy((void*) offs, data, data.length);
					for (var i = 0; i < n; i++) {
						var off = offs[i];
						this.endpoint_off.append_val(off);
					}
				}
			} catch (GLib.Error err) {
			}

			try {
				string body;
				GLib.FileUtils.get_contents(stem + ".pending", out body);
				var text = body.strip();
				if (text != "") {
					this.pending = text;
				}
			} catch (GLib.Error err) {
			}
		}

		/**
		 * Merge {@link pending} into {@link text} and persist via
		 * {@link IBSO.Debug.Recording.save} on Idle (no-op if empty).
		 */
		public void flush()
		{
			var stop_pending = this.pending;
			if (this.pending != "") {
				if (this.text != "") {
					this.text += "\n";
				}
				this.text += this.pending;
				this.pending = "";
			}
			if (!this.recording && this.text == "" && this.pcm.length == 0) {
				return;
			}
			var samples = this.pcm.steal();
			/* Copy by Array.length — steal() has returned a byte-ish length for int[]
			 * (trailing zeros / garbage ints in ''.chunks''). */
			var n_chunks = (int) this.chunk_n.length;
			var chunk_ns = new int[n_chunks];
			if (n_chunks > 0) {
				GLib.Memory.copy((void*) chunk_ns, this.chunk_n.data,
					n_chunks * sizeof(int));
			}
			var n_ends = (int) this.endpoint_off.length;
			var endpoint_offs = new int[n_ends];
			if (n_ends > 0) {
				GLib.Memory.copy((void*) endpoint_offs, this.endpoint_off.data,
					n_ends * sizeof(int));
			}
			if (this.text == "" && samples.length == 0) {
				return;
			}
			var text = this.text;
			var started = this.started;
			GLib.Idle.add(() => {
				Debug.Recording.save(text, samples, chunk_ns, endpoint_offs, started, stop_pending);
				return GLib.Source.REMOVE;
			});
		}
	}
}
