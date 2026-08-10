/**
 * Streaming mic → sherpa-onnx → stdout, or scripted accuracy check.
 *
 * Usage:
 *   sherpa-onnx-mic [--stats] [--language CODE] [model-dir]
 *   sherpa-onnx-mic --script FILE [--language CODE] [model-dir]
 *
 * ''--script'': text file, one expected utterance per line (''#'' / blank
 * skipped). Shows the line, listens until an endpoint, prints Heard and a
 * closeness score vs the script line. Mid-line pauses are kept (segments are
 * joined); a longer quiet settle is required before the next line.
 *
 * Default model-dir: ''~/.config/ibus-sherpa-onnx/model'' if ready, else the
 * tree under ''models/'' for the English 560 ms pack.
 */
int main(string[] args)
{
	Gst.init(ref args);

	var want_stats = false;
	var script_path = "";
	var language = "";
	var model_dir = "";
	for (var i = 1; i < args.length; i++) {
		if (args[i] == "--stats") {
			want_stats = true;
			continue;
		}
		if (args[i] == "--script") {
			i++;
			if (i >= args.length) {
				GLib.stderr.printf("--script needs a file path\n");
				return 1;
			}
			script_path = args[i];
			continue;
		}
		if (args[i] == "--language") {
			i++;
			if (i >= args.length) {
				GLib.stderr.printf("--language needs a catalog code (e.g. ja-JP)\n");
				return 1;
			}
			language = args[i];
			continue;
		}
		if (args[i].has_prefix("--")) {
			GLib.stderr.printf("Unknown option: %s\n", args[i]);
			return 1;
		}
		model_dir = args[i];
	}

	if (model_dir == "") {
		var link = GLib.Path.build_filename(
			GLib.Environment.get_user_config_dir(), "ibus-sherpa-onnx", "model");
		if (GLib.FileUtils.test(link, GLib.FileTest.IS_SYMLINK)
				|| GLib.FileUtils.test(link, GLib.FileTest.IS_DIR)) {
			model_dir = link;
			try {
				if (GLib.FileUtils.test(link, GLib.FileTest.IS_SYMLINK)) {
					model_dir = GLib.FileUtils.read_link(link);
				}
			} catch (GLib.FileError err) {
			}
		}
	}
	if (model_dir == "") {
		model_dir = "models/sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25";
	}

	if (language == "") {
		try {
			var conf = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "ibus-sherpa-onnx", "settings.ini");
			var key_file = new GLib.KeyFile();
			key_file.load_from_file(conf, GLib.KeyFileFlags.NONE);
			language = key_file.get_string("general", "language");
		} catch (GLib.Error err) {
			language = "en";
		}
	}

	var engine = new IBSO.Engine() {
		language = language
	};
	IBSO.Transcriber transcriber;
	try {
		transcriber = new IBSO.Transcriber(engine, IBSO.Config.load()) {
			model_dir = model_dir
		};
		transcriber.load();
	} catch (GLib.Error err) {
		GLib.stderr.printf("%s\n", err.message);
		return 1;
	}

	if (script_path != "") {
		string script_body;
		try {
			GLib.FileUtils.get_contents(script_path, out script_body);
		} catch (GLib.FileError err) {
			GLib.stderr.printf("%s\n", err.message);
			return 1;
		}
		string[] lines = {};
		foreach (var raw in script_body.split("\n")) {
			var line = raw.strip();
			if (line == "" || line.has_prefix("#")) {
				continue;
			}
			lines += line;
		}
		if (lines.length == 0) {
			GLib.stderr.printf("No utterances in %s\n", script_path);
			return 1;
		}

		GLib.stderr.printf("Script %s (%d lines). Model: %s  language=%s\n",
			script_path, lines.length, model_dir, language);
		/* Longer than engine rule2 (~1.2s) so mid-line pauses do not finish the line. */
		var settle_ms = 4000;
		GLib.stderr.printf(
			"Say each line; short pauses OK. Next line after ~%gs quiet. Ctrl+C aborts.\n",
			settle_ms / 1000.0);

		var sum_score = 0.0;
		var n_scored = 0;
		for (var i = 0; i < lines.length; i++) {
			var expected = lines[i];
			GLib.stderr.printf("\n[%d/%d] Say:\n  %s\n", i + 1, lines.length, expected);
			GLib.stdout.printf(">");
			GLib.stdout.flush();

			var got = "";
			var last_partial = "";
			var settle_id = (uint) 0;
			var utter = new GLib.MainLoop();
			var ep = transcriber.endpoint.connect((text) => {
				var piece = text.strip();
				if (piece == "") {
					return;
				}
				got = got == "" ? piece : got + " " + piece;
				last_partial = "";
				GLib.stdout.printf("\r> %s", got);
				GLib.stdout.flush();
				if (settle_id != 0) {
					GLib.Source.remove(settle_id);
				}
				settle_id = GLib.Timeout.add(settle_ms, () => {
					settle_id = 0;
					utter.quit();
					return GLib.Source.REMOVE;
				});
			});
			var part = transcriber.partial.connect((text) => {
				last_partial = text.strip();
				var show = got == "" ? last_partial : got + " " + last_partial;
				GLib.stdout.printf("\r> %s", show);
				GLib.stdout.flush();
				if (settle_id != 0) {
					GLib.Source.remove(settle_id);
				}
				settle_id = GLib.Timeout.add(settle_ms, () => {
					settle_id = 0;
					utter.quit();
					return GLib.Source.REMOVE;
				});
			});
			var quit = false;
			var sig = GLib.Unix.signal_add(GLib.ProcessSignal.INT, () => {
				quit = true;
				utter.quit();
				return GLib.Source.REMOVE;
			});
			transcriber.start();
			utter.run();
			transcriber.disconnect(ep);
			transcriber.disconnect(part);
			GLib.Source.remove(sig);
			if (settle_id != 0) {
				GLib.Source.remove(settle_id);
			}
			transcriber.stop();
			if (quit) {
				GLib.stderr.printf("\nAborted.\n");
				return 130;
			}
			if (last_partial != "") {
				got = got == "" ? last_partial : got + " " + last_partial;
			}

			GLib.stdout.printf("\nHeard:\n  %s\n", got);

			var a = expected.strip().down();
			var b = got.strip().down();
			while (a.contains("  ")) {
				a = a.replace("  ", " ");
			}
			while (b.contains("  ")) {
				b = b.replace("  ", " ");
			}
			var score = 0.0;
			if (a == b) {
				score = 100.0;
			} else if (a.char_count() == 0) {
				score = 0.0;
			} else {
				/* Character Levenshtein → closeness %% (Heard vs script line). */
				var an = a.char_count();
				var bn = b.char_count();
				var prev = new int[bn + 1];
				var cur = new int[bn + 1];
				for (var j = 0; j <= bn; j++) {
					prev[j] = j;
				}
				for (var ai = 1; ai <= an; ai++) {
					cur[0] = ai;
					var ca = a.get(a.index_of_nth_char(ai - 1));
					for (var bi = 1; bi <= bn; bi++) {
						var cb = b.get(b.index_of_nth_char(bi - 1));
						var cost = ca == cb ? 0 : 1;
						var del = prev[bi] + 1;
						var ins = cur[bi - 1] + 1;
						var sub = prev[bi - 1] + cost;
						var best = del < ins ? del : ins;
						cur[bi] = best < sub ? best : sub;
					}
					var swap = prev;
					prev = cur;
					cur = swap;
				}
				var dist = prev[bn];
				var denom = an > bn ? an : bn;
				score = denom > 0 ? 100.0 * (1.0 - (double) dist / denom) : 0.0;
				if (score < 0.0) {
					score = 0.0;
				}
			}
			sum_score += score;
			n_scored++;
			GLib.stderr.printf("Score: %.0f%%\n", score);
		}
		if (n_scored > 0) {
			GLib.stderr.printf("\nAverage: %.0f%%  (%d lines)\n", sum_score / n_scored, n_scored);
		}
		return 0;
	}

	GLib.stderr.printf("Listening (Ctrl+C to quit). Model: %s  language=%s%s\n",
		model_dir, language, want_stats ? " [stats]" : "");

	var segments = 0;
	var total_chars = 0;
	var total_tokens = 0;
	var total_audio_s = 0.0;
	var total_wall_s = 0.0;

	transcriber.partial.connect((text) => {
		GLib.stdout.printf("\r%s", text);
		GLib.stdout.flush();
	});
	transcriber.endpoint.connect((text) => {
		GLib.stdout.printf("\n");
		GLib.stdout.flush();
		if (!want_stats) {
			return;
		}
		segments++;
		var chars = text.char_count();
		total_chars += chars;
		total_tokens += transcriber.last_token_count;
		total_audio_s += transcriber.last_audio_s;
		total_wall_s += transcriber.last_wall_s;
		GLib.stderr.printf(
			"#seg %d  tokens=%d  chars=%d  audio=%.2fs  wall=%.2fs  partials=%d  rtf=%.2f\n",
			segments, transcriber.last_token_count, chars, transcriber.last_audio_s, transcriber.last_wall_s,
			transcriber.last_partial_count,
			transcriber.last_audio_s > 0.01 ? transcriber.last_wall_s / transcriber.last_audio_s : 0.0
		);
	});

	var loop = new GLib.MainLoop();
	GLib.Unix.signal_add(GLib.ProcessSignal.INT, () => {
		loop.quit();
		return GLib.Source.REMOVE;
	});

	transcriber.start();
	loop.run();
	transcriber.stop();
	GLib.stdout.printf("\n");

	if (want_stats && segments > 0) {
		GLib.stderr.printf("#total segments=%d  chars=%d  tokens=%d  audio=%.1fs  wall=%.1fs  avg_rtf=%.2f\n",
			segments, total_chars, total_tokens, total_audio_s, total_wall_s,
			total_audio_s > 0.01 ? total_wall_s / total_audio_s : 0.0
		);
	}

	return 0;
}
