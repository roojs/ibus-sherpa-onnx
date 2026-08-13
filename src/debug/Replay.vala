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
	 * Synced file→speaker→ASR Replay for a debug ''.wav''.
	 *
	 * Owns the GStreamer tee pipeline and {@link Feed}; feeds ASR via
	 * {@link IBSO.Transcriber.push}. Speaker plays ''.wav''; ASR uses the
	 * loaded {@link IBSO.Session} floats (''.f32'') paced by appsink.
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
		public IBSO.Transcriber transcriber { get; construct; }

		private Gst.Pipeline? pipeline = null;
		private ulong bus_id = 0;
		private Feed? feed = null;
		/** Live accept_waveform floats when ''.f32'' was loaded (or Session pcm). */
		private float[]? live_pcm = null;
		private int live_off = 0;

		public Replay(IBSO.Transcriber transcriber)
		{
			GLib.Object(transcriber: transcriber);
		}

		/**
		 * Play ''path'' and feed ASR in lockstep. Uses ''recorded'' when given,
		 * otherwise ''new Session.load(path)'' for sibling sidecars.
		 *
		 * @param path absolute mono 16 kHz WAV (speakers)
		 * @param recorded optional pre-loaded / sliced session; null → load from ''path''
		 */
		public void start(string path, IBSO.Session? recorded = null)
		{
			this.stop();
			var sess = recorded ?? new IBSO.Session.load(path);
			var n_chunks = (int) sess.chunk_n.length;
			int[]? sizes = null;
			if (n_chunks > 0) {
				sizes = new int[n_chunks];
				GLib.Memory.copy((void*) sizes, sess.chunk_n.data, n_chunks * sizeof(int));
			}
			this.feed = sizes != null ? new Feed(sizes) : null;
			var n_pcm = (int) sess.pcm.length;
			if (n_pcm > 0) {
				this.live_pcm = new float[n_pcm];
				GLib.Memory.copy((void*) this.live_pcm, sess.pcm.data, n_pcm * sizeof(float));
			} else {
				this.live_pcm = null;
			}
			this.live_off = 0;
			GLib.debug("#replay path=%s chunks=%d f32=%d endpoints=%u pending=%s", path,
				n_chunks, n_pcm, sess.endpoint_off.length,
				sess.pending != "" ? "yes" : "no");
			this.transcriber.begin_file(sess);

			try {
				this.pipeline = (Gst.Pipeline) Gst.parse_launch(
					"filesrc name=src ! wavparse ! audioconvert ! audioresample ! "
					+ "audio/x-raw,format=F32LE,channels=1,rate=16000 ! tee name=t "
					+ "t. ! queue ! autoaudiosink sync=true "
					+ "t. ! queue max-size-buffers=0 max-size-time=0 max-size-bytes=0 ! "
					+ "appsink name=sink emit-signals=true max-buffers=200 drop=false sync=true"
				);
			} catch (GLib.Error err) {
				GLib.warning("replay pipeline: %s", err.message);
				this.transcriber.cancel_file();
				this.feed = null;
				this.live_pcm = null;
				return;
			}
			this.pipeline.get_by_name("src").set("location", path);
			var sink = (Gst.App.Sink) this.pipeline.get_by_name("sink");
			sink.new_sample.connect(() => {
				var sample = sink.pull_sample();
				if (sample == null) {
					return Gst.FlowReturn.ERROR;
				}
				if (!this.transcriber.file_active) {
					return Gst.FlowReturn.OK;
				}
				var buffer = sample.get_buffer();
				if (buffer == null) {
					return Gst.FlowReturn.ERROR;
				}
				Gst.MapInfo map;
				if (!buffer.map(out map, Gst.MapFlags.READ)) {
					return Gst.FlowReturn.ERROR;
				}
				if (map.size >= sizeof(float)) {
					var n = (int) (map.size / sizeof(float));
					float[] samples;
					if (this.live_pcm != null) {
						n = int.min(n, this.live_pcm.length - this.live_off);
						samples = new float[n];
						for (var i = 0; i < n; i++) {
							samples[i] = this.live_pcm[this.live_off + i];
						}
						this.live_off += n;
					} else {
						samples = new float[n];
						GLib.Memory.copy((void*) samples, map.data, map.size);
					}
					if (this.feed != null) {
						this.feed.push(samples);
						float[]? slice;
						while ((slice = this.feed.take()) != null) {
							this.transcriber.push((owned) slice);
						}
					} else {
						this.transcriber.push((owned) samples);
					}
				}
				buffer.unmap(map);
				return Gst.FlowReturn.OK;
			});
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
				if (this.transcriber.file_active) {
					/* Only accept through saved chunk sizes — no leftover drain. */
					if (this.feed != null) {
						this.feed.finish();
						float[]? slice;
						while ((slice = this.feed.take()) != null) {
							this.transcriber.push((owned) slice);
						}
						this.feed = null;
					}
					this.live_pcm = null;
					this.transcriber.end_file();
				}
			});
			this.pipeline.set_state(Gst.State.PLAYING);
		}

		/**
		 * Cancel an in-progress Replay (no {@link IBSO.Transcriber.file_finished}).
		 */
		public void stop()
		{
			this.drop_pipeline();
			this.feed = null;
			this.live_pcm = null;
			this.live_off = 0;
			this.transcriber.cancel_file();
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
	}
}
