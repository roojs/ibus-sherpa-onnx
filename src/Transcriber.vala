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
	/** Mic appsink → {@link Capture.push}. */
	public delegate void MicPcm(owned float[] samples);

	/**
	 * Streaming ASR core: mic or pushed PCM → sherpa-onnx online transducer.
	 *
	 * Not constructed by callers — use {@link Capture}. Ops are protected;
	 * {@link Capture} is the public surface.
	 *
	 * Threads: appsink calls {@link Capture.push} via {@link on_mic_pcm}; one
	 * worker owns sherpa; Idle marshals text to main. No mutexes — queue + worker only.
	 *
	 * @since 0.2
	 */
	public class Transcriber : GLib.Object
	{
		private SherpaOnnx.OnlineRecognizer recognizer;
		private SherpaOnnx.OnlineStream stream;
		private Gst.Pipeline pipeline;
		private GLib.AsyncQueue<PcmChunk> audio_queue;
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
		 * Mic appsink PCM handler. {@link Capture} sets this to {@link Capture.push}
		 * so live mic shares the same path as Replay.
		 */
		protected MicPcm? on_mic_pcm;

		/** Directory with int8 ONNX + tokens.txt (set before {@link load}). */
		public string model_dir { get; set; default = ""; }

		/** Catalog pack id (IBus reuse checks); empty for CLI/GTK. */
		public string pack { get; set; default = ""; }

		/** Catalog language code; English codes skip stream option. */
		public string language { get; set; default = ""; }

		/** Prefs (''mute-speakers'', …); refreshed on focus. */
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
		 * Seconds of PCM accepted via {@link push} while not {@link listening}
		 * (Replay / CLI; worker updates).
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
		 * {@link flush} Idle finished (main loop). Replay / CLI await this.
		 */
		public signal void flushed();

		/**
		 * Load Nemotron online recognizer from {@link model_dir}.
		 *
		 * @throws GLib.IOError if recognizer, stream, or pipeline cannot be created
		 */
		protected void load_model() throws GLib.Error
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
					num_threads = 1,
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
				this.note_feed('R', null);
				this.recognizer.reset(this.stream);
				if (this.stream_language != "") {
					this.stream.set_option("language", this.stream_language);
				}
				this.hypothesis = "";
				this.partial_updates = 0;
				this.segment_start_us = GLib.get_monotonic_time();
				return;
			}

			if (chunk.session_end) {
				this.recognizer.reset(this.stream);
				if (this.stream_language != "") {
					this.stream.set_option("language", this.stream_language);
				}
				this.hypothesis = "";
				this.partial_updates = 0;
				return;
			}

			if (chunk.flush) {
				this.note_feed('F', null);
				/* Match listen stop(): commit stop partial when set, else
				 * current hypothesis — never input_finished() (changes the line). */
				var commit = chunk.flush_pending != "" ? chunk.flush_pending : this.hypothesis;
				var emit_done = chunk.flush_finished;
				GLib.Idle.add(() => {
					this.last_text = "";
					if (commit != "") {
						this.engine.on_endpoint(commit);
						this.endpoint(commit);
					}
					if (emit_done) {
						this.flushed();
					}
					return GLib.Source.REMOVE;
				});
				this.recognizer.reset(this.stream);
				if (this.stream_language != "") {
					this.stream.set_option("language", this.stream_language);
				}
				this.hypothesis = "";
				this.partial_updates = 0;
				return;
			}

			/* Queue is the gate: callers must not push when idle. Mic appsink
			 * checks {@link listening}; Replay/CLI own their feed lifecycle. */
			if (!this.listening && chunk.samples.length > 0) {
				this.feed_pos_s += chunk.samples.length / 16000.0;
			}
			this.note_feed('P', chunk.samples);
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
			/* Same feedlog stream as R/P/F — cut sample off for live vs Replay diff. */
			this.note_feed('E', null);
			var wall_s = (GLib.get_monotonic_time() - this.segment_start_us) / 1000000.0;
			var partials = this.partial_updates;
			GLib.Idle.add(() => {
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
		 * GStreamer appsink ''new-sample'': copy PCM and {@link push}.
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

			if (!this.listening) {
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
				if (this.on_mic_pcm != null) {
					this.on_mic_pcm((owned) samples);
				} else {
					this.queue_pcm((owned) samples);
				}
			}
			buffer.unmap(map);
			return Gst.FlowReturn.OK;
		}

		/**
		 * ASR worker hook before accept/reset/flush/endpoint (''.feedlog'').
		 * ''op'': ''R'' reset, ''P'' PCM (samples set), ''E'' endpoint cut, ''F'' flush.
		 *
		 * @param op feed marker
		 * @param samples PCM for ''P'', else null
		 */
		protected virtual void note_feed(char op, float[]? samples)
		{
		}

		/**
		 * Queue PCM for the ASR worker.
		 *
		 * @param samples mono float PCM (ownership taken)
		 */
		protected void queue_pcm(owned float[] samples)
		{
			this.audio_queue.push(new PcmChunk((owned) samples));
		}

		/**
		 * Queue a stream reset (before feeding PCM from Replay / CLI).
		 */
		protected void queue_reset()
		{
			this.feed_pos_s = 0.0;
			this.last_text = "";
			this.audio_queue.push(new PcmChunk.for_reset());
		}

		/**
		 * Queue a flush: commit ''pending'' (or current hypothesis), then
		 * {@link flushed}.
		 *
		 * @param pending stop partial to commit (may be empty)
		 */
		protected void queue_flush(string pending = "")
		{
			this.audio_queue.push(new PcmChunk.for_flush(pending, true));
		}

		/** Start mic capture (main loop). Idempotent. Caller queues {@link queue_reset} first. */
		protected void start_mic()
		{
			if (this.listening) {
				return;
			}
			this.listening = true;
			if (this.config.key_file.get_boolean("general", "mute-speakers")) {
				this.output_mute(true);
			}
			this.pipeline.set_state(Gst.State.PLAYING);
		}

		/**
		 * Stop mic capture only (main loop). Idempotent. Caller queues
		 * {@link queue_flush} / session end as needed.
		 */
		protected void stop_mic()
		{
			if (!this.listening) {
				return;
			}
			this.listening = false;
			this.pipeline.set_state(Gst.State.NULL);
			this.output_mute(false);
			this.last_text = "";
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
