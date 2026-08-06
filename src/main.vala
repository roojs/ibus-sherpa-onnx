/**
 * Streaming mic STT PoC: GStreamer capture → sherpa-onnx → stdout.
 *
 * Usage:
 *   stt-poc [--stats] [model-dir]
 *
 * Default model-dir:
 *   models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25
 *
 * Fetch 1120ms (more accurate, higher latency):
 *   ./scripts/fetch-nemotron-model.sh 1120
 *   ./build/stt-poc --stats models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-1120ms-int8-2026-04-25
 */
int main (string[] args)
{
	Gst.init (ref args);

	var want_stats = false;
	var model_dir = "models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25";
	for (var i = 1; i < args.length; i++) {
		if (args[i] == "--stats") {
			want_stats = true;
			continue;
		}
		model_dir = args[i];
	}

	var saved_stderr = Posix.dup (Posix.STDERR_FILENO);
	var devnull = Posix.open ("/dev/null", Posix.O_WRONLY);
	if (saved_stderr >= 0 && devnull >= 0) {
		Posix.dup2 (devnull, Posix.STDERR_FILENO);
		Posix.close (devnull);
	}
	var recognizer = new SherpaOnnx.OnlineRecognizer (SherpaOnnx.OnlineRecognizerConfig () {
		feat_config = SherpaOnnx.FeatureConfig () {
			sample_rate = 16000,
			feature_dim = 80,
		},
		model_config = SherpaOnnx.OnlineModelConfig () {
			transducer = SherpaOnnx.OnlineTransducerModelConfig () {
				encoder = GLib.Path.build_filename (model_dir, "encoder.int8.onnx"),
				decoder = GLib.Path.build_filename (model_dir, "decoder.int8.onnx"),
				joiner = GLib.Path.build_filename (model_dir, "joiner.int8.onnx"),
			},
			tokens = GLib.Path.build_filename (model_dir, "tokens.txt"),
			num_threads = (int32) GLib.get_num_processors ().clamp (1, 4),
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
		Posix.dup2 (saved_stderr, Posix.STDERR_FILENO);
		Posix.close (saved_stderr);
	}

	if (recognizer == null) {
		GLib.stderr.printf ("Failed to create online recognizer (check model paths under %s)\n", model_dir);
		return 1;
	}

	var stream = recognizer.create_stream ();
	if (stream == null) {
		GLib.stderr.printf ("Failed to create online stream\n");
		return 1;
	}

	GLib.stderr.printf ("Listening (Ctrl+C to quit). Model: %s%s\n",
		model_dir, want_stats ? " [stats]" : "");

	Gst.Pipeline pipeline;
	try {
		pipeline = (Gst.Pipeline) Gst.parse_launch (
			"autoaudiosrc ! audioconvert ! audioresample ! "
			+ "audio/x-raw,format=F32LE,channels=1,rate=16000 ! "
			+ "appsink name=sink emit-signals=true max-buffers=10 drop=true sync=false"
		);
	} catch (GLib.Error err) {
		GLib.stderr.printf ("GStreamer pipeline failed: %s\n", err.message);
		return 1;
	}

	string[] last_text = {""};
	int64[] segment_start_us = {GLib.get_monotonic_time ()};
	int[] partial_updates = {0};
	int[] segments = {0};
	int[] total_chars = {0};
	int[] total_tokens = {0};
	double[] total_audio_s = {0.0};
	double[] total_wall_s = {0.0};

	var sink = (Gst.App.Sink) pipeline.get_by_name ("sink");
	sink.new_sample.connect (() => {
		var sample = sink.pull_sample ();
		if (sample == null) {
			return Gst.FlowReturn.ERROR;
		}

		var buffer = sample.get_buffer ();
		if (buffer == null) {
			return Gst.FlowReturn.ERROR;
		}

		Gst.MapInfo map;
		if (!buffer.map (out map, Gst.MapFlags.READ)) {
			return Gst.FlowReturn.ERROR;
		}

		if (map.size >= sizeof (float)) {
			var samples = new float[map.size / sizeof (float)];
			GLib.Memory.copy ((void*) samples, map.data, map.size);
			stream.accept_waveform (16000, samples);
		}
		buffer.unmap (map);

		while (recognizer.is_ready (stream) == 1) {
			recognizer.decode (stream);
		}

		var result = recognizer.get_result (stream);
		if (result.text != null && result.text != "" && result.text != last_text[0]) {
			last_text[0] = result.text;
			partial_updates[0]++;
			GLib.stdout.printf ("\r%s", result.text);
			GLib.stdout.flush ();
		}

		if (recognizer.is_endpoint (stream) != 1) {
			return Gst.FlowReturn.OK;
		}
		if (last_text[0] == "") {
			recognizer.reset (stream);
			return Gst.FlowReturn.OK;
		}

		GLib.stdout.printf ("\n");
		GLib.stdout.flush ();

		if (!want_stats) {
			last_text[0] = "";
			partial_updates[0] = 0;
			segment_start_us[0] = GLib.get_monotonic_time ();
			recognizer.reset (stream);
			return Gst.FlowReturn.OK;
		}

		var wall_s = (GLib.get_monotonic_time () - segment_start_us[0]) / 1000000.0;
		var audio_s = Math.fmax (0.0, 
			(result.timestamps != null && result.count > 0) ? result.timestamps[result.count - 1] - result.timestamps[0] : 0.0
		);
		segments[0]++;
		var chars = last_text[0].char_count ();
		total_chars[0] += chars;
		total_tokens[0] += (int) result.count;
		total_audio_s[0] += audio_s;
		total_wall_s[0] += wall_s;
		GLib.stderr.printf (
			"#seg %d  tokens=%d  chars=%d  audio=%.2fs  wall=%.2fs  partials=%d  rtf=%.2f\n",
			segments[0], (int) result.count, chars, audio_s, wall_s, partial_updates[0],
			audio_s > 0.01 ? wall_s / audio_s : 0.0
		);

		last_text[0] = "";
		partial_updates[0] = 0;
		segment_start_us[0] = GLib.get_monotonic_time ();
		recognizer.reset (stream);
		return Gst.FlowReturn.OK;
	});

	var loop = new GLib.MainLoop ();
	GLib.Unix.signal_add (GLib.ProcessSignal.INT, () => {
		loop.quit ();
		return GLib.Source.REMOVE;
	});

	pipeline.set_state (Gst.State.PLAYING);
	loop.run ();
	pipeline.set_state (Gst.State.NULL);
	GLib.stdout.printf ("\n");

	if (want_stats && segments[0] > 0) {
		GLib.stderr.printf ("#total segments=%d  chars=%d  tokens=%d  audio=%.1fs  wall=%.1fs  avg_rtf=%.2f\n",
			segments[0], total_chars[0], total_tokens[0], total_audio_s[0], total_wall_s[0],
			total_audio_s[0] > 0.01 ? total_wall_s[0] / total_audio_s[0] : 0.0
		);
	}

	return 0;
}
