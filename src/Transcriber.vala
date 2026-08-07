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

namespace IBus.SherpaOnnx
{
	/**
	 * Streaming mic ASR: GStreamer capture → sherpa-onnx online transducer.
	 *
	 * Create loads the recognizer (slow). {@link start} / {@link stop} only
	 * flip the mic pipeline. Decode runs on the GStreamer thread;
	 * {@link partial} / {@link endpoint} always fire on the main loop via
	 * {@link GLib.Idle.add}.
	 *
	 * == Usage Examples ==
	 *
	 * === CLI stdout ===
	 *
	 * {{{
	 *   Gst.init(ref args);
	 *   var transcriber = new IBus.SherpaOnnx.Transcriber(model_dir, "ja-JP");
	 *   transcriber.partial.connect((t) => { stdout.printf("\r%s", t); stdout.flush(); });
	 *   transcriber.endpoint.connect((t) => { stdout.printf("\n"); stdout.flush(); });
	 *   transcriber.start();
	 * }}}
	 *
	 * @since 0.2
	 */
	public class Transcriber : GLib.Object
	{
		private global::SherpaOnnx.OnlineRecognizer recognizer;
		private global::SherpaOnnx.OnlineStream stream;
		private Gst.Pipeline pipeline;
		private string pending_partial = "";
		private bool partial_idle_queued = false;
		private int partial_updates = 0;
		private int64 segment_start_us = 0;
		private GLib.Mutex emit_lock;
		/** Stream ''language'' option; empty skips ''set_option'' (English-only packs). */
		private string stream_language = "";

		/** True while the capture pipeline is PLAYING. */
		public bool listening { get; private set; default = false; }

		/** Current unfinished hypothesis (empty when idle or after endpoint/stop). */
		public string last_text { get; private set; default = ""; }

		/** Token count from the last endpoint (for CLI --stats). */
		public int last_token_count { get; private set; default = 0; }

		/** Approx audio span (s) from last endpoint timestamps. */
		public double last_audio_s { get; private set; default = 0.0; }

		/** Wall time (s) for the last segment. */
		public double last_wall_s { get; private set; default = 0.0; }

		/** Partial updates counted in the last segment. */
		public int last_partial_count { get; private set; default = 0; }

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
		 * Load Nemotron online recognizer from ''model_dir'' (encoder/decoder/joiner/tokens).
		 *
		 * @param model_dir directory with int8 ONNX + tokens.txt
		 * @param language prefs ''general/language='' (catalog code); English codes skip stream option
		 * @throws GLib.IOError if recognizer, stream, or pipeline cannot be created
		 */
		public Transcriber(string model_dir, string language = "") throws GLib.Error
		{
			this.emit_lock = GLib.Mutex();
			this.segment_start_us = GLib.get_monotonic_time();
			if (language != "" && language != "en" && !language.has_prefix("en-")) {
				this.stream_language = language;
			}

			var saved_stderr = Posix.dup(Posix.STDERR_FILENO);
			var devnull = Posix.open("/dev/null", Posix.O_WRONLY);
			if (saved_stderr >= 0 && devnull >= 0) {
				Posix.dup2(devnull, Posix.STDERR_FILENO);
				Posix.close(devnull);
			}
			this.recognizer = new global::SherpaOnnx.OnlineRecognizer(global::SherpaOnnx.OnlineRecognizerConfig() {
				feat_config = global::SherpaOnnx.FeatureConfig() {
					sample_rate = 16000,
					feature_dim = 80,
				},
				model_config = global::SherpaOnnx.OnlineModelConfig() {
					transducer = global::SherpaOnnx.OnlineTransducerModelConfig() {
						encoder = GLib.Path.build_filename(model_dir, "encoder.int8.onnx"),
						decoder = GLib.Path.build_filename(model_dir, "decoder.int8.onnx"),
						joiner = GLib.Path.build_filename(model_dir, "joiner.int8.onnx"),
					},
					tokens = GLib.Path.build_filename(model_dir, "tokens.txt"),
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
					"Failed to create online recognizer (check model paths under %s)", model_dir);
			}

			this.stream = this.recognizer.create_stream();
			if (this.stream == null) {
				throw new GLib.IOError.FAILED("Failed to create online stream");
			}
			if (this.stream_language != "") {
				this.stream.set_option("language", this.stream_language);
			}

			/* webrtcdsp AGC (gain-control); echo-cancel off — no playback probe. */
			this.pipeline = (Gst.Pipeline) Gst.parse_launch(
				"autoaudiosrc ! audioconvert ! audioresample ! "
				+ "audio/x-raw,format=S16LE,layout=interleaved,channels=1,rate=16000 ! "
				+ "webrtcdsp gain-control=true echo-cancel=false ! "
				+ "audioconvert ! audioresample ! "
				+ "audio/x-raw,format=F32LE,channels=1,rate=16000 ! "
				+ "appsink name=sink emit-signals=true max-buffers=10 drop=true sync=false"
			);
			var sink = (Gst.App.Sink) this.pipeline.get_by_name("sink");
			sink.new_sample.connect(() => {
				return this.on_new_sample(sink);
			});
		}

		/**
		 * GStreamer appsink ''new-sample'': accept PCM, decode, Idle-marshal
		 * {@link partial} / {@link endpoint}. Runs on the streaming thread.
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
				this.stream.accept_waveform(16000, samples);
			}
			buffer.unmap(map);

			while (this.recognizer.is_ready(this.stream) == 1) {
				this.recognizer.decode(this.stream);
			}

			var result = this.recognizer.get_result(this.stream);
			if (result.text != null && result.text != "" && result.text != this.last_text) {
				this.last_text = result.text;
				this.partial_updates++;
				this.emit_lock.lock();
				this.pending_partial = result.text;
				var need_idle = !this.partial_idle_queued;
				if (need_idle) {
					this.partial_idle_queued = true;
				}
				this.emit_lock.unlock();
				if (need_idle) {
					GLib.Idle.add(() => {
						this.emit_lock.lock();
						var copy = this.pending_partial;
						this.partial_idle_queued = false;
						this.emit_lock.unlock();
						this.partial(copy);
						return GLib.Source.REMOVE;
					});
				}
			}

			if (this.recognizer.is_endpoint(this.stream) != 1) {
				return Gst.FlowReturn.OK;
			}
			if (this.last_text == "") {
				this.recognizer.reset(this.stream);
				if (this.stream_language != "") {
					this.stream.set_option("language", this.stream_language);
				}
				return Gst.FlowReturn.OK;
			}

			var commit = this.last_text;
			var wall_s = (GLib.get_monotonic_time() - this.segment_start_us) / 1000000.0;
			var audio_s = 0.0;
			if (result.timestamps != null && result.count > 0) {
				audio_s = Math.fmax(0.0, result.timestamps[result.count - 1] - result.timestamps[0]);
			}
			var tokens = (int) result.count;
			var partials = this.partial_updates;

			this.last_text = "";
			this.partial_updates = 0;
			this.segment_start_us = GLib.get_monotonic_time();
			this.recognizer.reset(this.stream);
			if (this.stream_language != "") {
				this.stream.set_option("language", this.stream_language);
			}

			GLib.Idle.add(() => {
				this.last_token_count = tokens;
				this.last_audio_s = audio_s;
				this.last_wall_s = wall_s;
				this.last_partial_count = partials;
				this.endpoint(commit);
				return GLib.Source.REMOVE;
			});
			return Gst.FlowReturn.OK;
		}

		/** Start mic capture (main loop). Idempotent if already listening. */
		public void start()
		{
			if (this.listening) {
				return;
			}
			this.last_text = "";
			this.partial_updates = 0;
			this.segment_start_us = GLib.get_monotonic_time();
			this.pipeline.set_state(Gst.State.PLAYING);
			this.listening = true;
		}

		/** Stop mic capture and reset the stream (main loop). Idempotent. */
		public void stop()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.pipeline.set_state(Gst.State.NULL);
			this.recognizer.reset(this.stream);
			if (this.stream_language != "") {
				this.stream.set_option("language", this.stream_language);
			}
			this.last_text = "";
			this.partial_updates = 0;
			this.emit_lock.lock();
			this.pending_partial = "";
			this.partial_idle_queued = false;
			this.emit_lock.unlock();
		}
	}
}
