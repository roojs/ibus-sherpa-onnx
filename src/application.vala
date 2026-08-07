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
	 * Model path is ''~/.config/ibus-sherpa-onnx/model'' — a directory, or a symlink
	 * to one. Toggle hotkey: ''~/.config/ibus-sherpa-onnx/hotkey''. ''--debug'' enables
	 * stderr logging (RooTerm / OLLMchat pattern).
	 *
	 * == Usage Examples ==
	 *
	 * === Point config at a fetched model ===
	 *
	 * {{{
	 *   mkdir -p ~/.config/ibus-sherpa-onnx
	 *   ln -sfn "$PWD/models/sherpa-onnx-nemotron-…" ~/.config/ibus-sherpa-onnx/model
	 *   ./build/ibus-engine-sherpa-onnx --debug
	 * }}}
	 *
	 * @since 0.3
	 */
	public class Application : GLib.Application
	{
		public static bool opt_debug = false;
		public static bool opt_debug_critical = false;

		private const GLib.OptionEntry[] options = {
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
		 * Load model, register the IBus component, hold the loop.
		 */
		public override void activate()
		{
			var model_dir = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "ibus-sherpa-onnx", "model"
			);
			var model_file = GLib.File.new_for_path(model_dir);
			if (model_file.query_file_type(GLib.FileQueryInfoFlags.NONE) != GLib.FileType.DIRECTORY) {
				GLib.critical("%s must be a model directory or a symlink to one", model_dir);
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

			var hotkey = "Ctrl+Shift+Space";
			var hotkey_path = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "ibus-sherpa-onnx", "hotkey"
			);
			try {
				string contents;
				GLib.FileUtils.get_contents(hotkey_path, out contents);
				if (contents.strip() != "") {
					hotkey = contents.strip();
				}
			} catch (GLib.Error err) {
				GLib.debug("No hotkey file at %s; using default", hotkey_path);
			}

			var keyval = (uint) 0;
			var accel_mods = (IBus.ModifierType) 0;
			IBus.accelerator_parse(hotkey, out keyval, out accel_mods);
			if (keyval == 0) {
				var normalized = hotkey.replace("Ctrl+", "Control+").replace("ctrl+", "Control+");
				var plus = normalized.last_index_of_char('+');
				if (plus >= 0) {
					normalized = normalized.substring(0, plus + 1) + normalized.substring(plus + 1).down();
				}
				var kv = (uint) 0;
				var md = (uint) 0;
				if (IBus.key_event_from_string(normalized, out kv, out md)) {
					keyval = kv;
					accel_mods = (IBus.ModifierType) md;
				}
			}
			if (keyval == 0) {
				IBus.accelerator_parse("<Control><Shift>space", out keyval, out accel_mods);
				GLib.warning("Could not parse hotkey '%s'; using Control+Shift+space", hotkey);
			}
			Engine.toggle_keyval = keyval;
			Engine.toggle_mods = (uint) accel_mods;

			var bus = new IBus.Bus();
			if (!bus.is_connected()) {
				GLib.critical("Cannot connect to ibus-daemon");
				GLib.Process.exit(1);
			}

			var factory = new IBus.Factory(bus.get_connection());
			factory.add_engine("sherpa-onnx", typeof(Engine));

			var component = new IBus.Component(
				"org.roojs.IBus.SherpaOnnx", "Sherpa ONNX", "0.1.0", "LGPL",
				"Alan Knowles <alan@roojs.com>", "https://github.com/roojs/ibus-sherpa-onnx",
				"", "ibus-sherpa-onnx"
			);
			component.add_engine(new IBus.EngineDesc(
				"sherpa-onnx", "Sherpa ONNX", "Local speech-to-text dictation (PoC)",
				"en", "LGPL", "Alan Knowles <alan@roojs.com>", "", "us"
			));
			if (!bus.register_component(component)) {
				GLib.critical("Failed to register IBus component");
				GLib.Process.exit(1);
			}

			GLib.debug("Registered sherpa-onnx. Toggle=%s", hotkey);
			this.hold();
		}
	}
}
