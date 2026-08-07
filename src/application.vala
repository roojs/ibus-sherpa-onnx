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
	private static GLib.FileStream? debug_log_file = null;
	private static bool debug_log_in_progress = false;

	/** When true, debug-level messages go to stderr (file always receives them). */
	public static bool debug_on = false;

	/** When true, critical log messages abort via {@link GLib.error}. */
	public static bool debug_critical_enabled = false;

	/**
	 * Writes to ''~/.cache/ibus-sherpa-onnx/{app_id}.debug.log'' (and stderr when debug is on).
	 *
	 * Same pattern as RooTerm / OLLMchat ''ApplicationInterface.debug_log''.
	 *
	 * @param app_id log file basename stem
	 * @param in_domain GLib log domain (empty if unset)
	 * @param level log level flags
	 * @param message log message text
	 */
	public static void debug_log(string app_id, string in_domain, GLib.LogLevelFlags level, string message)
	{
		if (debug_log_in_progress) {
			return;
		}

		var timestamp = (new GLib.DateTime.now_local()).format("%H:%M:%S.%f");
		var should_output = debug_on || (level & GLib.LogLevelFlags.LEVEL_CRITICAL) != 0;
		if (should_output) {
			GLib.stderr.printf(timestamp + ": " + level.to_string() + " : " + in_domain + " : " + message + "\n");
		}

		if ((level & GLib.LogLevelFlags.LEVEL_CRITICAL) != 0 && debug_critical_enabled) {
			GLib.error("Critical warning: [" + in_domain + "] " + message);
		}

		debug_log_in_progress = true;
		if (debug_log_file == null) {
			var log_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_cache_dir(), "ibus-sherpa-onnx"
			);
			var log_file_path = GLib.Path.build_filename(log_dir, app_id + ".debug.log");
			if (!GLib.FileUtils.test(log_dir, GLib.FileTest.IS_DIR)) {
				GLib.DirUtils.create_with_parents(log_dir, 0755);
			}
			debug_log_file = GLib.FileStream.open(log_file_path, "w");
			if (debug_log_file == null) {
				GLib.stderr.printf("ERROR: FAILED TO OPEN DEBUG LOG FILE: Unable to open file stream\n");
				debug_log_in_progress = false;
				return;
			}
		}
		if (debug_log_file != null) {
			debug_log_file.puts(timestamp + ": " + level.to_string() + " : " + message + "\n");
			debug_log_file.flush();
		}
		debug_log_in_progress = false;
	}

	/**
	 * ''GLib.Application'' host for the Sherpa ONNX IBus engine.
	 *
	 * Model: ''~/.config/ibus-sherpa-onnx/model'' (dir or symlink). Prefs in
	 * ''~/.config/ibus-sherpa-onnx/settings.ini'' (KeyFile). ''--debug'' enables
	 * stderr logging.
	 *
	 * == Usage Examples ==
	 *
	 * === Fetch model then run unpackaged ===
	 *
	 * {{{
	 *   ./scripts/fetch-nemotron-model.sh
	 *   ./build/ibus-engine-sherpa-onnx --debug
	 * }}}
	 *
	 * @since 0.3
	 */
	public class Application : GLib.Application
	{
		public static bool opt_debug = false;
		public static bool opt_debug_critical = false;
		/** True when spawned by ibus-daemon (''--ibus''); skip register_component. */
		public static bool opt_ibus = false;

		private const GLib.OptionEntry[] options = {
			{ "ibus", 'i', 0, OptionArg.NONE, ref opt_ibus,
				"Executed by ibus-daemon (packaged component path)", null },
			{ "debug", 'd', 0, OptionArg.NONE, ref opt_debug, "Enable debug output", null },
			{ "debug-critical", 0, 0, OptionArg.NONE, ref opt_debug_critical,
				"Treat critical warnings as errors", null },
			{ null }
		};

		/**
		 * Create the application and install the debug log handler.
		 */
		public Application()
		{
			GLib.Object(
				application_id: "org.roojs.ibus-sherpa-onnx",
				flags: GLib.ApplicationFlags.DEFAULT_FLAGS | GLib.ApplicationFlags.NON_UNIQUE
			);
			this.add_main_option_entries(options);
			GLib.Log.set_default_handler((dom, lvl, msg) => {
				debug_log("ibus-sherpa-onnx", dom != null ? dom : "", lvl, msg);
			});
		}

		/**
		 * Apply ''--debug'' flags after options are parsed.
		 */
		public override void startup()
		{
			base.startup();
			debug_on = opt_debug;
			debug_critical_enabled = opt_debug_critical;
		}

		/**
		 * Load model, attach to ibus-daemon, hold the loop.
		 *
		 * With ''--ibus'' (packaged path): factory + {@link IBus.Bus.request_name}.
		 * Without: runtime {@link IBus.Bus.register_component} for unpackaged smoke tests.
		 */
		public override void activate()
		{
			var user_model = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "ibus-sherpa-onnx", "model"
			);
			var system_model = "/usr/share/ibus-sherpa-onnx/model";
			var model_dir = user_model;
			if (GLib.File.new_for_path(user_model).query_file_type(GLib.FileQueryInfoFlags.NONE)
					!= GLib.FileType.DIRECTORY) {
				model_dir = system_model;
			}
			if (GLib.File.new_for_path(model_dir).query_file_type(GLib.FileQueryInfoFlags.NONE)
					!= GLib.FileType.DIRECTORY) {
				GLib.critical(
					"No model at %s or %s — run fetch-nemotron-model.sh (or sudo for system)",
					user_model, system_model
				);
				GLib.Process.exit(1);
			}
			var stamp = GLib.Path.build_filename(model_dir, ".sha256");
			if (!GLib.FileUtils.test(stamp, GLib.FileTest.IS_REGULAR)) {
				GLib.critical(
					"Model at %s has no .sha256 stamp (incomplete or old install). Re-run fetch-nemotron-model.sh.",
					model_dir
				);
				GLib.Process.exit(1);
			}
			try {
				string stamp_hash;
				GLib.FileUtils.get_contents(stamp, out stamp_hash);
				var tree = model_dir;
				if (GLib.FileUtils.test(user_model, GLib.FileTest.IS_SYMLINK) && model_dir == user_model) {
					tree = GLib.FileUtils.read_link(user_model);
				}
				var base = GLib.Path.get_basename(tree);
				var expected = GLib.Path.build_filename("/usr/share/ibus-sherpa-onnx/checksums",
					base + ".sha256");
				if (!GLib.FileUtils.test(expected, GLib.FileTest.IS_REGULAR)) {
					GLib.critical("No packaged checksum for model %s", base);
					GLib.Process.exit(1);
				}
				string expect_hash;
				GLib.FileUtils.get_contents(expected, out expect_hash);
				if (stamp_hash.strip() != expect_hash.strip().split_set(" \t\n", 2)[0]) {
					GLib.critical("Model checksum mismatch at %s", model_dir);
					GLib.Process.exit(1);
				}
			} catch (GLib.Error err) {
				GLib.critical("Model checksum check failed: %s", err.message);
				GLib.Process.exit(1);
			}

			IBus.init();

			GLib.debug("Loading model: %s", model_dir);
			try {
				Engine.transcriber = new Transcriber(model_dir);
			} catch (GLib.Error err) {
				GLib.critical("%s", err.message);
				GLib.Process.exit(1);
			}

			Engine.config = Config.load();
			Engine.bind_hotkey();

			var bus = new IBus.Bus();
			if (!bus.is_connected()) {
				GLib.critical("Cannot connect to ibus-daemon");
				GLib.Process.exit(1);
			}
			bus.disconnected.connect(() => {
				this.release();
			});

			var factory = new IBus.Factory(bus.get_connection());
			factory.add_engine("sherpa-onnx", typeof(Engine));

			if (opt_ibus) {
				bus.request_name("org.roojs.IBus.SherpaOnnx", 0);
				GLib.debug("ibus mode: requested org.roojs.IBus.SherpaOnnx. Toggle=%s",
					Engine.config.key_file.get_string("general", "hotkey"));
				this.hold();
				return;
			}

			var component = new IBus.Component(
				"org.roojs.IBus.SherpaOnnx", "Sherpa ONNX", "0.1.0", "LGPL",
				"Alan Knowles <alan@roojs.com>",
				"https://github.com/roojs/gtk-speechtotext-poc",
				"", "ibus-sherpa-onnx"
			);
			component.add_engine((IBus.EngineDesc) GLib.Object.new(
				typeof(IBus.EngineDesc),
				"name", "sherpa-onnx",
				"longname", "Sherpa ONNX",
				"description", "Local speech-to-text dictation",
				"language", "en",
				"license", "LGPL",
				"author", "Alan Knowles <alan@roojs.com>",
				"icon", "",
				"layout", "us",
				"symbol", "voi"
			));
			if (!bus.register_component(component)) {
				GLib.critical("Failed to register IBus component");
				GLib.Process.exit(1);
			}
			GLib.debug("Registered sherpa-onnx (unpackaged). Toggle=%s",
				Engine.config.key_file.get_string("general", "hotkey"));
			this.hold();
		}
	}
}
