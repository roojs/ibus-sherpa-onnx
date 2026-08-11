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
	 * Synced file→speaker→ASR Replay for a debug ''.wav'' (optional ''.chunks'').
	 *
	 * Owns the GStreamer tee pipeline and {@link Feed}; pushes PCM onto
	 * {@link IBSO.Transcriber.audio_queue}.
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

		public Replay(IBSO.Transcriber transcriber)
		{
			GLib.Object(transcriber: transcriber);
		}

		/**
		 * Play ''path'' and feed ASR in lockstep. When ''.chunks'' exists
		 * (or ''chunk_ns'' is passed), accept sizes match the live session.
		 *
		 * @param path absolute mono 16 kHz WAV
		 * @param chunk_ns optional live sizes; null → load sibling ''.chunks''
		 */
		public void start(string path, int[]? chunk_ns = null)
		{
			this.stop();
			var sizes = chunk_ns ?? Recording.load_chunks(path);
			this.feed = sizes != null && sizes.length > 0 ? new Feed(sizes) : null;
			GLib.debug("#replay path=%s chunks=%d", path, sizes != null ? sizes.length : 0);
			this.transcriber.file_feeding = true;
			this.transcriber.notify_replay_finished = true;
			this.transcriber.feed_pos_s = 0.0;
			this.transcriber.last_text = "";
			this.transcriber.audio_queue.push(new IBSO.Transcriber.PcmChunk.for_reset());

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
				this.transcriber.file_feeding = false;
				this.transcriber.notify_replay_finished = false;
				this.feed = null;
				return;
			}
			this.pipeline.get_by_name("src").set("location", path);
			var sink = (Gst.App.Sink) this.pipeline.get_by_name("sink");
			sink.new_sample.connect(() => {
				var sample = sink.pull_sample();
				if (sample == null) {
					return Gst.FlowReturn.ERROR;
				}
				if (!this.transcriber.file_feeding) {
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
					var samples = new float[map.size / sizeof(float)];
					GLib.Memory.copy((void*) samples, map.data, map.size);
					if (this.feed != null) {
						this.feed.push(samples);
						float[]? slice;
						while ((slice = this.feed.take()) != null) {
							this.transcriber.audio_queue.push(
								new IBSO.Transcriber.PcmChunk((owned) slice));
						}
					} else {
						this.transcriber.audio_queue.push(
							new IBSO.Transcriber.PcmChunk((owned) samples));
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
				if (this.transcriber.file_feeding) {
					if (this.feed != null) {
						this.feed.finish();
						float[]? slice;
						while ((slice = this.feed.take()) != null) {
							this.transcriber.audio_queue.push(
								new IBSO.Transcriber.PcmChunk((owned) slice));
						}
						this.feed = null;
					}
					this.transcriber.audio_queue.push(
						new IBSO.Transcriber.PcmChunk.for_flush());
				}
			});
			this.pipeline.set_state(Gst.State.PLAYING);
		}

		/**
		 * Cancel an in-progress Replay (no {@link IBSO.Transcriber.replay_finished}).
		 */
		public void stop()
		{
			this.transcriber.notify_replay_finished = false;
			this.drop_pipeline();
			this.feed = null;
			if (this.transcriber.file_feeding) {
				this.transcriber.file_feeding = false;
				this.transcriber.audio_queue.push(new IBSO.Transcriber.PcmChunk.for_reset());
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
	}
}
