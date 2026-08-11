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
	 * Streaming mic ASR: GStreamer capture → sherpa-onnx online transducer.
	 *
	 * {{{
	 *   var t = new Transcriber(engine) {
	 *     model_dir = dir,
	 *     pack = pack
	 *   };
	 *   t.load();
	 * }}}
	 *
	 * CLI/GTK pass the stub {@link Engine}. Also emits {@link partial} /
	 * {@link endpoint} for signal clients.
	 * {@link load} is slow; {@link start} / {@link stop} only flip the mic.
	 *
	 * Threads: appsink pushes PCM (or a reset) onto {@link GLib.AsyncQueue};
	 * one worker owns sherpa accept/decode/reset; Idle marshals text to main.
	 * No mutexes — queue + worker ownership only.
	 *
	 * @since 0.2
	 */
	public class Transcriber : GLib.Object
	{
		/** Queue item: PCM for the worker, or {@link PcmChunk.for_reset} / flush. */
		public class PcmChunk
		{
			public float[] samples;
			public bool reset;
			public bool flush;
			/** End of a mic listen: write debug session if armed, then reset. */
			public bool session_end;

			public PcmChunk(owned float[] samples)
			{
				this.samples = (owned) samples;
				this.reset = false;
				this.flush = false;
				this.session_end = false;
			}

			public PcmChunk.for_reset()
			{
				this.samples = {};
				this.reset = true;
				this.flush = false;
				this.session_end = false;
			}

			public PcmChunk.for_flush()
			{
				this.samples = {};
				this.reset = false;
				this.flush = true;
				this.session_end = false;
			}

			public PcmChunk.for_session_end()
			{
				this.samples = {};
				this.reset = false;
				this.flush = false;
				this.session_end = true;
			}
		}

		private SherpaOnnx.OnlineRecognizer recognizer;
		private SherpaOnnx.OnlineStream stream;
		private Gst.Pipeline pipeline;
		/** PCM / control items for the ASR worker (mic, Replay, CLI --wav). */
		public GLib.AsyncQueue<PcmChunk> audio_queue { get; private set; }
		private bool worker_running = false;
		/** Worker-only current hypothesis (main reads {@link last_text} via Idle). */
		private string hypothesis = "";
		private int partial_updates = 0;
		private int64 segment_start_us = 0;
		/** Stream ''language'' option; empty skips ''set_option'' (English-only packs). */
		private string stream_language = "";

		/** True while we muted the default sink for this listen session. */
		private bool output_mute_held = false;

		/**
		 * Worker-only PCM for the whole listen when debug-recordings is on.
		 * Kept across ASR endpoints (includes mid-session silence).
		 */
		private GLib.Array<float> session_pcm = new GLib.Array<float>(false, false, (uint) sizeof(float));
		/**
		 * Worker-only sample counts per {@link SherpaOnnx.OnlineStream.accept_waveform}
		 * during the listen (same order as live feed). Written to ''.chunks''.
		 */
		private GLib.Array<int> session_chunk_n = new GLib.Array<int>(false, false, (uint) sizeof(int));
		/** Worker-only committed texts for this listen (newline between). */
		private string session_text = "";
		private bool session_recording = false;
		/** Wall time at {@link start}; basename for debug files. */
		private GLib.DateTime? session_started = null;
		/** Pending partial committed on stop (main → worker via session_end). */
		private string session_pending = "";

		/**
		 * True while debug Replay / CLI file feed is active (no mic).
		 * Main / CLI / {@link IBSO.Debug.Replay} sets; worker clears after flush.
		 */
		public bool file_feeding { get; set; default = false; }

		/** Emit {@link replay_finished} after the worker flush Idle. */
		public bool notify_replay_finished { get; set; default = false; }

		/** Directory with int8 ONNX + tokens.txt (set before {@link load}). */
		public string model_dir { get; set; default = ""; }

		/** Catalog pack id (IBus reuse checks); empty for CLI/GTK. */
		public string pack { get; set; default = ""; }

		/** Catalog language code; English codes skip stream option. */
		public string language { get; set; default = ""; }

		/** Prefs (''mute-speakers'', ''debug-recordings'', …); refreshed on focus. */
		public Config config { get; set construct; }

		/** Owning engine (IBus or CLI/GTK stub). */
		public unowned Engine engine { get; construct; }

		/** True while the capture pipeline is PLAYING. */
		public bool listening { get; private set; default = false; }

		/** Current unfinished hypothesis (main loop; updated from Idle). */
		public string last_text { get; set; default = ""; }

		/** Token count from the last endpoint (for CLI --stats). */
		public int last_token_count { get; private set; default = 0; }

		/** Approx audio span (s) from last endpoint timestamps. */
		public double last_audio_s { get; private set; default = 0.0; }

		/** Wall time (s) for the last segment. */
		public double last_wall_s { get; private set; default = 0.0; }

		/** Partial updates counted in the last segment. */
		public int last_partial_count { get; private set; default = 0; }

		/**
		 * Seconds of file PCM accepted so far during file feed / Replay
		 * (worker updates; CLI reads on Idle signals).
		 */
		public double feed_pos_s { get; set; default = 0.0; }

		/**
		 * Live hypothesis changed (main loop).
		 *
		 * @param text current partial transcript
		 */
		public signal void partial(string text);

		/**
		 * Endpoint fired; segment text is final for this utterance (main loop).
		 *
		 * @param text committed transcript for the segment
		 */
		public signal void endpoint(string text);

		/**
		 * File feed finished (flush Idle). Browse Replay and CLI --wav.
		 * Main loop.
		 */
		public signal void replay_finished();

		/**
		 * @param engine owning engine (IBus or stub)
		 * @param config settings (already loaded)
		 */
		public Transcriber(Engine engine, Config config)
		{
			GLib.Object(
				engine: engine,
				config: config
			);
			this.language = engine.language;
		}

		/**
		 * Load Nemotron online recognizer from {@link model_dir}.
		 *
		 * @throws GLib.IOError if recognizer, stream, or pipeline cannot be created
		 */
		public void load() throws GLib.Error
		{
			this.segment_start_us = GLib.get_monotonic_time();
			this.stream_language = "";
			if (this.language != "" && this.language != "en" && !this.language.has_prefix("en-")) {
				this.stream_language = this.language;
			}

			var saved_stderr = Posix.dup(Posix.STDERR_FILENO);
			var devnull = Posix.open("/dev/null", Posix.O_WRONLY);
			if (saved_stderr >= 0 && devnull >= 0) {
				Posix.dup2(devnull, Posix.STDERR_FILENO);
				Posix.close(devnull);
			}
			this.recognizer = new SherpaOnnx.OnlineRecognizer(SherpaOnnx.OnlineRecognizerConfig() {
				feat_config = SherpaOnnx.FeatureConfig() {
					sample_rate = 16000,
					feature_dim = 80,
				},
				model_config = SherpaOnnx.OnlineModelConfig() {
					transducer = SherpaOnnx.OnlineTransducerModelConfig() {
						encoder = GLib.Path.build_filename(this.model_dir, "encoder.int8.onnx"),
						decoder = GLib.Path.build_filename(this.model_dir, "decoder.int8.onnx"),
						joiner = GLib.Path.build_filename(this.model_dir, "joiner.int8.onnx"),
					},
					tokens = GLib.Path.build_filename(this.model_dir, "tokens.txt"),
					num_threads = (int32) GLib.get_num_processors().clamp(1, 4),
					provider = "cpu",
				},
				decoding_method = "greedy_search",
				blank_penalty = 0.8f,
				enable_endpoint = 1,
				rule1_min_trailing_silence = 2.4f,
				rule2_min_trailing_silence = 1.2f,
				rule3_min_utterance_length = 300.0f,
			});
			if (saved_stderr >= 0) {
				Posix.dup2(saved_stderr, Posix.STDERR_FILENO);
				Posix.close(saved_stderr);
			}

			if (this.recognizer == null) {
				throw new GLib.IOError.FAILED(
					"Failed to create online recognizer (check model paths under %s)", this.model_dir);
			}

			this.stream = this.recognizer.create_stream();
			if (this.stream == null) {
				throw new GLib.IOError.FAILED("Failed to create online stream");
			}
			if (this.stream_language != "") {
				this.stream.set_option("language", this.stream_language);
			}

			this.audio_queue = new GLib.AsyncQueue<PcmChunk>();

			/* No webrtcdsp AGC: onset after silence was over-amplified. Back-pressure
			 * via drop=false instead of silently discarding mic buffers. */
			this.pipeline = (Gst.Pipeline) Gst.parse_launch(
				"autoaudiosrc ! audioconvert ! audioresample ! "
				+ "audio/x-raw,format=F32LE,channels=1,rate=16000 ! "
				+ "appsink name=sink emit-signals=true max-buffers=200 drop=false sync=false"
			);
			var sink = (Gst.App.Sink) this.pipeline.get_by_name("sink");
			sink.new_sample.connect(() => {
				return this.on_new_sample(sink);
			});

			this.worker_running = true;
			new GLib.Thread<void>("sherpa-asr", () => {
				while (this.worker_running) {
					this.processing_loop();
				}
			});
		}

		/**
		 * One ASR worker iteration: pop queue, decode, Idle-marshal UI.
		 */
		private void processing_loop()
		{
			var chunk = this.audio_queue.timeout_pop(100000);
			if (chunk == null) {
				return;
			}

			if (chunk.reset) {
				this.recognizer.reset(this.stream);
				if (this.stream_language != "") {
					this.stream.set_option("language", this.stream_language);
				}
				this.hypothesis = "";
				this.partial_updates = 0;
				this.segment_start_us = GLib.get_monotonic_time();
				this.session_pcm.set_size(0);
				this.session_chunk_n.set_size(0);
				this.session_text = "";
				this.session_recording = this.listening && !this.file_feeding
					&& this.config.key_file.get_boolean("general", "debug-recordings");
				return;
			}

			if (chunk.session_end) {
				this.flush_session_recording();
				this.recognizer.reset(this.stream);
				if (this.stream_language != "") {
					this.stream.set_option("language", this.stream_language);
				}
				this.hypothesis = "";
				this.partial_updates = 0;
				this.session_recording = false;
				return;
			}

			if (chunk.flush) {
				this.stream.input_finished();
				while (this.recognizer.is_ready(this.stream) == 1) {
					this.recognizer.decode(this.stream);
				}
				var result = this.recognizer.get_result(this.stream);
				var commit = result.text != "" ? result.text : this.hypothesis;
				var finished = this.notify_replay_finished;
				this.notify_replay_finished = false;
				this.file_feeding = false;
				GLib.Idle.add(() => {
					this.last_text = "";
					if (commit != "") {
						this.engine.on_endpoint(commit);
						this.endpoint(commit);
					}
					if (finished) {
						this.replay_finished();
					}
					return GLib.Source.REMOVE;
				});
				this.recognizer.reset(this.stream);
				if (this.stream_language != "") {
					this.stream.set_option("language", this.stream_language);
				}
				this.hypothesis = "";
				this.partial_updates = 0;
				this.session_pcm.set_size(0);
				this.session_chunk_n.set_size(0);
				this.session_text = "";
				this.session_recording = false;
				return;
			}

			/* After stop(), drain leftover mic chunks into the session buffer only. */
			if (this.session_recording && chunk.samples.length > 0) {
				this.session_pcm.append_vals(chunk.samples, chunk.samples.length);
			}

			if (!this.listening && !this.file_feeding) {
				return;
			}

			if (this.file_feeding && chunk.samples.length > 0) {
				this.feed_pos_s += chunk.samples.length / 16000.0;
			}

			if (this.session_recording && chunk.samples.length > 0) {
				this.session_chunk_n.append_val(chunk.samples.length);
			}
			this.stream.accept_waveform(16000, chunk.samples);
			while (this.recognizer.is_ready(this.stream) == 1) {
				this.recognizer.decode(this.stream);
			}

			var result = this.recognizer.get_result(this.stream);
			if (result.text != "" && result.text != this.hypothesis) {
				this.hypothesis = result.text;
				this.partial_updates++;
				var copy = result.text;
				GLib.Idle.add(() => {
					if (!this.listening && !this.file_feeding) {
						return GLib.Source.REMOVE;
					}
					this.last_text = copy;
					this.engine.on_partial(copy);
					this.partial(copy);
					return GLib.Source.REMOVE;
				});
			}

			if (this.recognizer.is_endpoint(this.stream) != 1) {
				return;
			}

			if (this.hypothesis == "") {
				this.recognizer.reset(this.stream);
				if (this.stream_language != "") {
					this.stream.set_option("language", this.stream_language);
				}
				this.hypothesis = "";
				this.partial_updates = 0;
				this.segment_start_us = GLib.get_monotonic_time();
				return;
			}

			var commit = this.hypothesis;
			if (this.session_recording) {
				if (this.session_text != "") {
					this.session_text += "\n";
				}
				this.session_text += commit;
			}
			var wall_s = (GLib.get_monotonic_time() - this.segment_start_us) / 1000000.0;
			var partials = this.partial_updates;
			GLib.Idle.add(() => {
				if (!this.listening && !this.file_feeding) {
					return GLib.Source.REMOVE;
				}
				this.last_token_count = (int) result.count;
				this.last_audio_s = 0.0;
				if (result.timestamps != null && result.count > 0) {
					this.last_audio_s = Math.fmax(0.0, result.timestamps[result.count - 1] - result.timestamps[0]);
				}
				this.last_wall_s = wall_s;
				this.last_partial_count = partials;
				this.last_text = "";
				this.engine.on_endpoint(commit);
				this.endpoint(commit);
				return GLib.Source.REMOVE;
			});

			this.recognizer.reset(this.stream);
			if (this.stream_language != "") {
				this.stream.set_option("language", this.stream_language);
			}
			this.hypothesis = "";
			this.partial_updates = 0;
			this.segment_start_us = GLib.get_monotonic_time();
		}

		/**
		 * Write buffered listen-session PCM + text (worker). Disk I/O on Idle.
		 */
		private void flush_session_recording()
		{
			var pending = this.session_pending;
			this.session_pending = "";
			if (pending != "") {
				if (this.session_text != "") {
					this.session_text += "\n";
				}
				this.session_text += pending;
			}
			if (!this.session_recording && this.session_text == "" && this.session_pcm.length == 0) {
				return;
			}
			var pcm = this.session_pcm.steal();
			var chunk_ns = this.session_chunk_n.steal();
			var text = this.session_text;
			var started = this.session_started;
			this.session_text = "";
			this.session_started = null;
			this.session_recording = false;
			if (text == "" && pcm.length == 0) {
				return;
			}
			GLib.Idle.add(() => {
				Debug.Recording.save(text, pcm, chunk_ns, started);
				return GLib.Source.REMOVE;
			});
		}

		/**
		 * GStreamer appsink ''new-sample'': copy PCM onto {@link audio_queue} only.
		 * Decode runs on {@link processing_loop}.
		 *
		 * @param sink appsink that emitted the sample
		 * @return flow result for the appsink
		 */
		private Gst.FlowReturn on_new_sample(Gst.App.Sink sink)
		{
			var sample = sink.pull_sample();
			if (sample == null) {
				return Gst.FlowReturn.ERROR;
			}

			if (!this.listening && !this.file_feeding) {
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
				this.audio_queue.push(new PcmChunk((owned) samples));
			}
			buffer.unmap(map);
			return Gst.FlowReturn.OK;
		}

		/** Start mic capture (main loop). Idempotent if already listening. */
		public void start()
		{
			if (this.listening) {
				return;
			}
			this.last_text = "";
			this.session_pending = "";
			this.session_started = new GLib.DateTime.now_local();
			this.listening = true;
			this.audio_queue.push(new PcmChunk.for_reset());
			if (this.config.key_file.get_boolean("general", "mute-speakers")) {
				this.output_mute(true);
			}
			this.pipeline.set_state(Gst.State.PLAYING);
		}

		/**
		 * Stop mic capture and queue a session flush + stream reset (main loop).
		 * Idempotent.
		 *
		 * @param pending unfinished partial to include in the debug ''.txt'' (may be empty)
		 */
		public void stop(string pending = "")
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.pipeline.set_state(Gst.State.NULL);
			this.output_mute(false);
			this.session_pending = pending.strip();
			this.last_text = "";
			/* Keep the queue so the worker can flush session_pcm, then reset. */
			this.audio_queue.push(new PcmChunk.for_session_end());
		}

		/**
		 * Mute or restore the default Pulse/PipeWire sink for this listen session.
		 * Unmute only if we muted earlier ({@link output_mute_held}).
		 *
		 * 💩 ''pactl'' spawn — nasty; revisit (libpulse or similar). Our GStreamer
		 * pipeline is capture-only and cannot silence system playback.
		 */
		private void output_mute(bool mute)
		{
			if (mute == this.output_mute_held) {
				return;
			}
			try {
				int status;
				Process.spawn_command_line_sync(
					"pactl set-sink-mute @DEFAULT_SINK@ %d".printf(mute ? 1 : 0),
					null, null, out status);
				if (status != 0) {
					return;
				}
			} catch (GLib.Error err) {
				GLib.debug("mute: %s", err.message);
				return;
			}
			this.output_mute_held = mute;
		}
	}
}
