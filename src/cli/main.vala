/**
 * Streaming mic PoC: GStreamer capture → sherpa-onnx → stdout.
 *
 * Usage:
 *   sherpa-onnx-mic [--stats] [model-dir]
 *
 * Default model-dir:
 *   models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25
 *
 * Fetch 1120ms (more accurate, higher latency):
 *   ./scripts/fetch-nemotron-model.sh 1120
 *   ./build/sherpa-onnx-mic --stats models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-1120ms-int8-2026-04-25
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

	IBus.SherpaOnnx.Transcriber transcriber;
	try {
		transcriber = new IBus.SherpaOnnx.Transcriber (model_dir);
	} catch (GLib.Error err) {
		GLib.stderr.printf ("%s\n", err.message);
		return 1;
	}

	GLib.stderr.printf ("Listening (Ctrl+C to quit). Model: %s%s\n",
		model_dir, want_stats ? " [stats]" : "");

	var segments = 0;
	var total_chars = 0;
	var total_tokens = 0;
	var total_audio_s = 0.0;
	var total_wall_s = 0.0;

	transcriber.partial.connect ((text) => {
		GLib.stdout.printf ("\r%s", text);
		GLib.stdout.flush ();
	});
	transcriber.endpoint.connect ((text) => {
		GLib.stdout.printf ("\n");
		GLib.stdout.flush ();
		if (!want_stats) {
			return;
		}
		segments++;
		var chars = text.char_count ();
		total_chars += chars;
		total_tokens += transcriber.last_token_count;
		total_audio_s += transcriber.last_audio_s;
		total_wall_s += transcriber.last_wall_s;
		GLib.stderr.printf (
			"#seg %d  tokens=%d  chars=%d  audio=%.2fs  wall=%.2fs  partials=%d  rtf=%.2f\n",
			segments, transcriber.last_token_count, chars, transcriber.last_audio_s, transcriber.last_wall_s,
			transcriber.last_partial_count,
			transcriber.last_audio_s > 0.01 ? transcriber.last_wall_s / transcriber.last_audio_s : 0.0
		);
	});

	var loop = new GLib.MainLoop ();
	GLib.Unix.signal_add (GLib.ProcessSignal.INT, () => {
		loop.quit ();
		return GLib.Source.REMOVE;
	});

	transcriber.start ();
	loop.run ();
	transcriber.stop ();
	GLib.stdout.printf ("\n");

	if (want_stats && segments > 0) {
		GLib.stderr.printf ("#total segments=%d  chars=%d  tokens=%d  audio=%.1fs  wall=%.1fs  avg_rtf=%.2f\n",
			segments, total_chars, total_tokens, total_audio_s, total_wall_s,
			total_audio_s > 0.01 ? total_wall_s / total_audio_s : 0.0
		);
	}

	return 0;
}
