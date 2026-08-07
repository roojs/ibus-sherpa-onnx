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
	 * User prefs in ''~/.config/ibus-sherpa-onnx/settings.ini''.
	 *
	 * Shared by the IBus engine and ''ibus-setup-sherpa-onnx''. Values live in
	 * {@link key_file} under group ''general''; {@link save} writes that file
	 * to {@link path}.
	 */
	public class Config : GLib.Object
	{
		/**
		 * Absolute path to ''settings.ini''.
		 */
		public string path;

		/**
		 * In-memory settings (group ''general'': ''hotkey'', ''notifications'',
		 * ''preedit-animation'').
		 */
		public GLib.KeyFile key_file;

		public Config()
		{
			this.path = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(),
				"ibus-sherpa-onnx", "settings.ini");
			this.key_file = new GLib.KeyFile();
			this.key_file.set_string("general", "hotkey", "Ctrl+Shift+Space");
			this.key_file.set_boolean("general", "notifications", false);
			this.key_file.set_boolean("general", "preedit-animation", true);
		}

		/**
		 * Load from disk onto constructor defaults (file keys overlay ''general'').
		 */
		public static Config load()
		{
			var config = new Config();
			if (!GLib.FileUtils.test(config.path, GLib.FileTest.IS_REGULAR)) {
				return config;
			}
			try {
				var disk = new GLib.KeyFile();
				disk.load_from_file(config.path, GLib.KeyFileFlags.NONE);
				foreach (var key in disk.get_keys("general")) {
					config.key_file.set_value("general", key, disk.get_value("general", key));
				}
			} catch (GLib.Error err) {
				GLib.debug("settings.ini: %s", err.message);
			}
			return config;
		}

		/** Write {@link key_file} to {@link path}. */
		public void save()
		{
			var dir = GLib.Path.get_dirname(this.path);
			GLib.DirUtils.create_with_parents(dir, 0755);
			try {
				this.key_file.save_to_file(this.path);
			} catch (GLib.Error err) {
				GLib.warning("save settings: %s", err.message);
			}
		}
	}
}
