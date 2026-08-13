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
	 * Live: {@link Capture} logs {@link Capture.push} / {@link Capture.reset} /
	 * {@link Capture.flush} into this buffer, then {@link flush} on stop.
	 * Replay / CLI: {@link Session.load}, then {@link feed} / {@link feed_next}
	 * into Capture — same bytes and ops.
	 *
	 * == Example ==
	 *
	 * {{{
	 * this.session.record_pcm(samples);
	 * var sess = this.session;
	 * this.session = new Session();
	 * sess.flush();
	 *
	 * var recorded = new Session.load(stem + ".wav");
	 * recorded.feed(capture);
	 * }}}
	 */
	public class Session : GLib.Object
	{
		/**
		 * Float PCM for the whole listen when recording is on (includes pauses).
		 */
		public GLib.Array<float> pcm = new GLib.Array<float>(false, false, (uint) sizeof(float));

		/**
		 * Sample counts / control ops per live ingress (''.chunks'').
		 * Positive = {@link Capture.push} size; {@link OP_RESET} / {@link OP_FLUSH}
		 * mark {@link Capture.reset} / {@link Capture.flush}.
		 */
		public GLib.Array<int> chunk_n = new GLib.Array<int>(false, false, (uint) sizeof(int));

		/** ''.chunks'' sentinel: {@link Capture.reset}. */
		public const int OP_RESET = 0;

		/** ''.chunks'' sentinel: {@link Capture.flush} (see {@link pending}). */
		public const int OP_FLUSH = -1;

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
		 * Checksums of Capture reset / push / flush (''.feedlog''), filled while
		 * {@link recording}.
		 */
		public string feedlog_body { get; set; default = ""; }

		/**
		 * Log a {@link Capture.push} of ''n'' samples (no-op if not {@link recording}).
		 *
		 * @param n sample count (must be &gt; 0)
		 */
		public void record_push(int n)
		{
			if (!this.recording || n <= 0) {
				return;
			}
			this.chunk_n.append_val(n);
			this.accepted += n;
		}

		/**
		 * Append PCM and a push op (no-op if not {@link recording}).
		 *
		 * @param samples mono float PCM
		 */
		public void record_pcm(float[] samples)
		{
			if (!this.recording || samples.length == 0) {
				return;
			}
			var n = samples.length;
			this.pcm.append_vals(samples, n);
			this.record_push(n);
		}

		/** Log a {@link Capture.reset} (no-op if not {@link recording}). */
		public void record_reset()
		{
			if (!this.recording) {
				return;
			}
			var op = OP_RESET;
			this.chunk_n.append_val(op);
		}

		/**
		 * Log a {@link Capture.flush} and store ''pending'' (no-op if not recording).
		 *
		 * @param pending stop partial (may be empty)
		 */
		public void record_flush(string pending)
		{
			if (!this.recording) {
				return;
			}
			this.pending = pending;
			var op = OP_FLUSH;
			this.chunk_n.append_val(op);
		}

		/**
		 * Log a committed endpoint line (no-op if not {@link recording}).
		 *
		 * @param text endpoint transcript
		 */
		public void record_endpoint(string text)
		{
			if (!this.recording || text.strip() == "") {
				return;
			}
			this.endpoint_off.append_val(this.accepted);
			if (this.text != "") {
				this.text += "\n";
			}
			this.text += text;
		}

		/**
		 * Walk this session’s op log into ''capture'' in order: {@link OP_RESET} →
		 * {@link Capture.reset}, positive → {@link Capture.push} from {@link pcm},
		 * {@link OP_FLUSH} → {@link Capture.flush}({@link pending}). No pacing —
		 * callers that need realtime (Browse speakers) pace around
		 * {@link feed_next}.
		 *
		 * @param capture ASR target (usually ''save: false'')
		 */
		public void feed(Capture capture)
		{
			var op_i = 0;
			var pcm_off = 0;
			while (this.feed_next(capture, ref op_i, ref pcm_off)) {
			}
		}

		/**
		 * Apply the next op from {@link chunk_n}. Returns false when the log is
		 * finished (flush issued or no more ops).
		 *
		 * @param capture ASR target
		 * @param op_i index into {@link chunk_n} (updated)
		 * @param pcm_off sample offset into {@link pcm} (updated)
		 * @return true if more ops may remain
		 */
		public bool feed_next(Capture capture, ref int op_i, ref int pcm_off)
		{
			var n_ops = (int) this.chunk_n.length;
			if (n_ops == 0) {
				/* Older captures: no ''.chunks'' — one reset, whole ''.f32'', flush. */
				if (op_i > 0) {
					return false;
				}
				op_i = 1;
				capture.reset();
				var n = (int) this.pcm.length;
				if (n > 0) {
					var slice = new float[n];
					for (var i = 0; i < n; i++) {
						slice[i] = this.pcm.index(i);
					}
					pcm_off = n;
					capture.push((owned) slice);
				}
				capture.flush(this.pending);
				return false;
			}

			while (op_i < n_ops) {
				var cn = this.chunk_n.index(op_i);
				op_i++;
				if (cn == OP_RESET) {
					capture.reset();
					return true;
				}
				if (cn == OP_FLUSH) {
					capture.flush(this.pending);
					return false;
				}
				if (cn <= 0) {
					continue;
				}
				var left = (int) this.pcm.length - pcm_off;
				if (left <= 0) {
					continue;
				}
				cn = int.min(cn, left);
				var slice = new float[cn];
				for (var i = 0; i < cn; i++) {
					slice[i] = this.pcm.index(pcm_off + i);
				}
				pcm_off += cn;
				capture.push((owned) slice);
				return true;
			}

			/* Older captures: ops without OP_FLUSH. */
			capture.flush(this.pending);
			return false;
		}

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

			try {
				string body;
				GLib.FileUtils.get_contents(stem + ".feedlog", out body);
				if (body.strip() != "") {
					this.feedlog_body = body;
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
			var feedlog = this.feedlog_body;
			GLib.Idle.add(() => {
				Debug.Recording.save(text, samples, chunk_ns, endpoint_offs, started,
					stop_pending, feedlog);
				return GLib.Source.REMOVE;
			});
		}
	}
}
