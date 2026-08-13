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
	 * Browse / CLI Replay: speakers play the ''.wav''; ASR walks the
	 * saved Capture op log (''.chunks'' + ''.f32'' + ''.pending'') into
	 * {@link IBSO.Capture.reset} / {@link IBSO.Capture.push} /
	 * {@link IBSO.Capture.flush} — same bytes and ops as live.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var replay = new Replay(transcriber);
	 * replay.start(stem + ".wav");
	 * // … later …
	 * replay.stop();
	 * }}}
	 */
	public class Replay : GLib.Object
	{
		public IBSO.Capture transcriber { get; construct; }

		private Gst.Pipeline? pipeline = null;
		private ulong bus_id = 0;
		/** Saved ''.f32'' floats (ownership for this Replay). */
		private float[]? pcm = null;
		/** Saved ''.chunks'' ops (positive push sizes, {@link IBSO.Session.OP_RESET}, {@link IBSO.Session.OP_FLUSH}). */
		private int[]? ops = null;
		private int op_i = 0;
		private int pcm_off = 0;
		/** True while this Replay is feeding ASR. */
		private bool feeding = false;
		/** Stop partial from the loaded session (passed to {@link IBSO.Capture.flush}). */
		private string pending = "";
		/** Wall-clock pacing: monotonic µs when feed started. */
		private int64 start_mono_us = 0;
		/** Audio time already pushed (µs at 16 kHz). */
		private int64 audio_us = 0;
		private uint timeout_id = 0;

		public Replay(IBSO.Capture transcriber)
		{
			GLib.Object(transcriber: transcriber);
		}

		/**
		 * Play ''path'' on speakers and feed ASR from the Capture op log.
		 * Uses ''recorded'' when given, otherwise ''new Session.load(path)''.
		 *
		 * @param path absolute mono 16 kHz WAV (speakers)
		 * @param recorded optional pre-loaded / sliced session; null → load from ''path''
		 */
		public void start(string path, IBSO.Session? recorded = null)
		{
			this.stop();
			var sess = recorded ?? new IBSO.Session.load(path);
			var n_ops = (int) sess.chunk_n.length;
			if (n_ops > 0) {
				this.ops = new int[n_ops];
				GLib.Memory.copy((void*) this.ops, sess.chunk_n.data, n_ops * sizeof(int));
			} else {
				this.ops = null;
			}
			var n_pcm = (int) sess.pcm.length;
			if (n_pcm > 0) {
				this.pcm = new float[n_pcm];
				GLib.Memory.copy((void*) this.pcm, sess.pcm.data, n_pcm * sizeof(float));
			} else {
				this.pcm = null;
			}
			this.op_i = 0;
			this.pcm_off = 0;
			this.audio_us = 0;
			this.pending = sess.pending;
			GLib.debug("#replay path=%s ops=%d f32=%d pending=%s", path,
				n_ops, n_pcm, this.pending != "" ? "yes" : "no");
			this.feeding = true;
			this.start_mono_us = GLib.get_monotonic_time();

			try {
				this.pipeline = (Gst.Pipeline) Gst.parse_launch(
					"filesrc name=src ! wavparse ! audioconvert ! audioresample ! "
					+ "audio/x-raw,format=F32LE,channels=1,rate=16000 ! "
					+ "autoaudiosink sync=true"
				);
			} catch (GLib.Error err) {
				GLib.warning("replay pipeline: %s", err.message);
				this.feeding = false;
				this.ops = null;
				this.pcm = null;
				return;
			}
			this.pipeline.get_by_name("src").set("location", path);
			var bus = this.pipeline.get_bus();
			bus.add_signal_watch();
			this.bus_id = bus.message.connect((b, message) => {
				if (message.type != Gst.MessageType.EOS
						&& message.type != Gst.MessageType.ERROR) {
					return;
				}
				if (message.type == Gst.MessageType.ERROR) {
					GLib.Error err;
					string dbg;
					message.parse_error(out err, out dbg);
					GLib.warning("replay: %s (%s)", err.message, dbg);
				}
				this.drop_pipeline();
			});
			this.pipeline.set_state(Gst.State.PLAYING);
			this.schedule_tick(0);
		}

		/**
		 * Cancel an in-progress Replay (no {@link flushed} from Capture).
		 */
		public void stop()
		{
			this.cancel_tick();
			this.drop_pipeline();
			this.ops = null;
			this.pcm = null;
			this.op_i = 0;
			this.pcm_off = 0;
			this.audio_us = 0;
			this.pending = "";
			if (this.feeding) {
				this.feeding = false;
				this.transcriber.reset();
			}
		}

		/** Disconnect bus and null the pipeline (shared by stop / EOS). */
		private void drop_pipeline()
		{
			if (this.pipeline == null) {
				return;
			}
			var bus = this.pipeline.get_bus();
			if (this.bus_id != 0) {
				bus.disconnect(this.bus_id);
				this.bus_id = 0;
			}
			bus.remove_signal_watch();
			this.pipeline.set_state(Gst.State.NULL);
			this.pipeline = null;
		}

		private void cancel_tick()
		{
			if (this.timeout_id != 0) {
				GLib.Source.remove(this.timeout_id);
				this.timeout_id = 0;
			}
		}

		private void schedule_tick(uint delay_ms)
		{
			this.cancel_tick();
			this.timeout_id = GLib.Timeout.add(delay_ms, () => {
				this.timeout_id = 0;
				this.tick();
				return GLib.Source.REMOVE;
			});
		}

		/**
		 * Walk ''.chunks'' in order: reset / push / flush. Push ops are paced
		 * to 16 kHz wall time so Output tracks the speakers.
		 */
		private void tick()
		{
			if (!this.feeding) {
				return;
			}

			/* No op log: one reset, then fixed-size pushes from ''.f32'', then flush. */
			if (this.ops == null || this.ops.length == 0) {
				if (this.pcm == null || this.pcm.length == 0) {
					this.finish_feed(true);
					return;
				}
				if (this.pcm_off == 0) {
					this.transcriber.reset();
				}
				var chunk = 1600; /* 100 ms @ 16 kHz */
				while (this.pcm_off < this.pcm.length) {
					var due = this.start_mono_us + this.audio_us;
					var now = GLib.get_monotonic_time();
					if (now < due) {
						var delay_ms = (uint) int64.max(1, (due - now) / 1000);
						this.schedule_tick(delay_ms);
						return;
					}
					var cn = int.min(chunk, this.pcm.length - this.pcm_off);
					this.push_slice(cn);
				}
				this.finish_feed(true);
				return;
			}

			while (this.op_i < this.ops.length) {
				var cn = this.ops[this.op_i];
				if (cn == IBSO.Session.OP_RESET) {
					this.op_i++;
					this.transcriber.reset();
					continue;
				}
				if (cn == IBSO.Session.OP_FLUSH) {
					this.op_i++;
					this.finish_feed(true);
					return;
				}
				if (cn <= 0) {
					this.op_i++;
					continue;
				}
				if (this.pcm == null || this.pcm_off >= this.pcm.length) {
					this.op_i++;
					continue;
				}
				var due = this.start_mono_us + this.audio_us;
				var now = GLib.get_monotonic_time();
				if (now < due) {
					var delay_ms = (uint) int64.max(1, (due - now) / 1000);
					this.schedule_tick(delay_ms);
					return;
				}
				cn = int.min(cn, this.pcm.length - this.pcm_off);
				this.op_i++;
				this.push_slice(cn);
			}

			/* Older captures: no OP_FLUSH in ''.chunks''. */
			this.finish_feed(true);
		}

		private void push_slice(int cn)
		{
			var slice = new float[cn];
			for (var i = 0; i < cn; i++) {
				slice[i] = this.pcm[this.pcm_off + i];
			}
			this.pcm_off += cn;
			this.audio_us += ((int64) cn * 1000000) / 16000;
			this.transcriber.push((owned) slice);
		}

		/**
		 * End ASR feed; optionally {@link IBSO.Capture.flush} (EOS path).
		 * Speakers may still be draining — pipeline is left until EOS / stop.
		 */
		private void finish_feed(bool do_flush)
		{
			this.cancel_tick();
			if (!this.feeding) {
				return;
			}
			this.feeding = false;
			this.ops = null;
			this.pcm = null;
			if (do_flush) {
				this.transcriber.flush(this.pending);
			}
			this.pending = "";
		}
	}
}
