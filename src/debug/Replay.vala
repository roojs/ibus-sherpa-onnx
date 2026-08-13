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
	 * Browse / CLI Replay: speakers play the ''.wav''; {@link IBSO.Session.feed_next}
	 * walks the Capture op log into ASR — same bytes and ops as live.
	 * When ''.chunks'' carries injection µs, feed is paced to those offsets.
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
		private IBSO.Session? session = null;
		private string wav_path = "";
		private int op_i = 0;
		private int pcm_off = 0;
		/** True while this Replay is feeding ASR. */
		private bool feeding = false;
		/** Wall-clock pacing: monotonic µs when feed started. */
		private int64 start_mono_us = 0;
		/** Fallback when chunks lack µs: audio already pushed at 16 kHz. */
		private int64 audio_us = 0;
		private uint timeout_id = 0;
		private ulong flushed_id = 0;

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
			this.session = recorded ?? new IBSO.Session.load(path);
			this.op_i = 0;
			this.pcm_off = 0;
			this.audio_us = 0;
			this.wav_path = path;
			this.flushed_id = this.transcriber.flushed.connect(() => {
				var stem = this.wav_path.slice(0, this.wav_path.length - 4);
				try {
					GLib.FileUtils.set_contents(stem + ".feedlog.replay",
						this.transcriber.feed_log);
				} catch (GLib.Error err) {
					GLib.warning("feedlog.replay: %s", err.message);
				}
			});
			GLib.debug("#replay path=%s ops=%u f32=%u times=%u pending=%s", path,
				this.session.chunk_n.length, this.session.pcm.length,
				this.session.chunk_t.length,
				this.session.pending != "" ? "yes" : "no");
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
				this.session = null;
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
			if (this.flushed_id != 0) {
				this.transcriber.disconnect(this.flushed_id);
				this.flushed_id = 0;
			}
			this.session = null;
			this.wav_path = "";
			this.op_i = 0;
			this.pcm_off = 0;
			this.audio_us = 0;
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
		 * Pace {@link IBSO.Session.feed_next} from stamped ''.chunks'' µs when
		 * present, else 16 kHz sample duration (older captures).
		 */
		private void tick()
		{
			if (!this.feeding || this.session == null) {
				return;
			}

			var use_times = this.session.chunk_t.length > 0
				&& this.session.chunk_t.length == this.session.chunk_n.length;

			while (this.feeding && this.session != null) {
				int64 due_off = -1;
				if (use_times && this.op_i < (int) this.session.chunk_t.length) {
					due_off = this.session.chunk_t.index(this.op_i);
				} else if (!use_times && this.audio_us > 0) {
					due_off = this.audio_us;
				}
				if (due_off >= 0) {
					var due = this.start_mono_us + due_off;
					var now = GLib.get_monotonic_time();
					if (now < due) {
						var delay_ms = (uint) int64.max(1, (due - now) / 1000);
						this.schedule_tick(delay_ms);
						return;
					}
				}

				var before_off = this.pcm_off;
				var more = this.session.feed_next(this.transcriber, ref this.op_i,
					ref this.pcm_off);
				var pushed = this.pcm_off - before_off;
				if (!use_times && pushed > 0) {
					this.audio_us += ((int64) pushed * 1000000) / 16000;
				}
				if (!more) {
					this.feeding = false;
					this.session = null;
					this.cancel_tick();
					return;
				}
				if (!use_times && pushed > 0) {
					var due = this.start_mono_us + this.audio_us;
					var now = GLib.get_monotonic_time();
					if (now < due) {
						var delay_ms = (uint) int64.max(1, (due - now) / 1000);
						this.schedule_tick(delay_ms);
						return;
					}
				}
			}
		}
	}
}
