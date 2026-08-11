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
	 * User prefs under ''~/.config/ibus-sherpa-onnx/''.
	 *
	 * ''settings.ini'' — group ''general'' (hotkey, notifications, language, …).  
	 * ''packs.ini'' — group ''packs'': language code → model pack id.
	 */
	public class Config : GLib.Object
	{
		/**
		 * Absolute path to ''settings.ini''.
		 */
		public string path;

		/**
		 * Absolute path to ''packs.ini''.
		 */
		public string packs_path;

		/**
		 * ''settings.ini'' (''general'' only).
		 */
		public GLib.KeyFile key_file;

		/**
		 * ''packs.ini'' (''[packs] en-GB=nemo-en-1120'', …).
		 */
		public GLib.KeyFile packs;

		/**
		 * Fired after ''settings.ini'' is written by {@link save}.
		 */
		public signal void changed();

		public Config()
		{
			var dir = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(),
				"ibus-sherpa-onnx");
			this.path = GLib.Path.build_filename(dir, "settings.ini");
			this.packs_path = GLib.Path.build_filename(dir, "packs.ini");
			this.key_file = new GLib.KeyFile();
			this.packs = new GLib.KeyFile();
		}

		/**
		 * Load both files from disk; fill missing ''general'' defaults.
		 */
		public static Config load()
		{
			var config = new Config();
			try {
				if (GLib.FileUtils.test(config.path, GLib.FileTest.IS_REGULAR)) {
					config.key_file.load_from_file(config.path, GLib.KeyFileFlags.NONE);
				}
			} catch (GLib.Error err) {
				GLib.debug("settings.ini: %s", err.message);
			}
			/* has_key() throws if the group is missing — seed [general] on clean install. */
			if (!config.key_file.has_group("general")) {
				config.key_file.set_string("general", "hotkey", "Ctrl+Shift+Space");
				config.key_file.set_boolean("general", "notifications", false);
				config.key_file.set_boolean("general", "preedit-animation", true);
				config.key_file.set_boolean("general", "mute-speakers", true);
				config.key_file.set_boolean("general", "debug-recordings", false);
				config.key_file.set_boolean("general", "voice-commands", true);
				config.key_file.set_string("general", "language", "en");
			}
			if (!config.key_file.has_key("general", "hotkey")) {
				config.key_file.set_string("general", "hotkey", "Ctrl+Shift+Space");
			}
			if (!config.key_file.has_key("general", "notifications")) {
				config.key_file.set_boolean("general", "notifications", false);
			}
			if (!config.key_file.has_key("general", "preedit-animation")) {
				config.key_file.set_boolean("general", "preedit-animation", true);
			}
			if (!config.key_file.has_key("general", "mute-speakers")) {
				config.key_file.set_boolean("general", "mute-speakers", true);
			}
			if (!config.key_file.has_key("general", "debug-recordings")) {
				config.key_file.set_boolean("general", "debug-recordings", false);
			}
			if (!config.key_file.has_key("general", "voice-commands")) {
				config.key_file.set_boolean("general", "voice-commands", true);
			}
			if (!config.key_file.has_key("general", "language")) {
				config.key_file.set_string("general", "language", "en");
			}

			var id = GLib.Environment.get_os_info(GLib.OsInfoKey.ID);
			var voice_prefix = "okay linux";
			if (id != null && id != "" && id != "linux") {
				voice_prefix = "okay " + id;
			}
			if (!config.key_file.has_key("general", "voice-paragraph")) {
				config.key_file.set_string("general", "voice-paragraph",
					voice_prefix + " paragraph");
			}
			if (!config.key_file.has_key("general", "voice-line-break")) {
				config.key_file.set_string("general", "voice-line-break",
					voice_prefix + " line break");
			}
			if (!config.key_file.has_key("general", "voice-stop")) {
				config.key_file.set_string("general", "voice-stop",
					voice_prefix + " stop");
			}

			try {
				if (GLib.FileUtils.test(config.packs_path, GLib.FileTest.IS_REGULAR)) {
					config.packs.load_from_file(config.packs_path, GLib.KeyFileFlags.NONE);
				}
			} catch (GLib.Error err) {
				GLib.debug("packs.ini: %s", err.message);
			}
			return config;
		}

		/** Write ''settings.ini''. */
		public void save()
		{
			var dir = GLib.Path.get_dirname(this.path);
			GLib.DirUtils.create_with_parents(dir, 0755);
			try {
				this.key_file.save_to_file(this.path);
			} catch (GLib.Error err) {
				GLib.warning("save settings: %s", err.message);
			}
			this.changed();
		}

		/** Write ''packs.ini''. */
		public void save_packs()
		{
			var dir = GLib.Path.get_dirname(this.packs_path);
			GLib.DirUtils.create_with_parents(dir, 0755);
			try {
				this.packs.save_to_file(this.packs_path);
			} catch (GLib.Error err) {
				GLib.warning("save packs: %s", err.message);
			}
		}

		/**
		 * Parse ''general/hotkey'' into keyval + mods (same rules as the engine).
		 * No silent default — returns false if missing or unparsable.
		 */
		public bool hotkey(out uint keyval, out IBus.ModifierType mods)
		{
			keyval = 0;
			mods = (IBus.ModifierType) 0;
			string hotkey;
			try {
				hotkey = this.key_file.get_string("general", "hotkey");
			} catch (GLib.KeyFileError err) {
				return false;
			}
			if (hotkey == "") {
				return false;
			}
			IBus.accelerator_parse(hotkey, out keyval, out mods);
			if (keyval == 0) {
				var normalized = hotkey.replace("Ctrl+", "Control+").replace("ctrl+", "Control+");
				var plus = normalized.last_index_of_char('+');
				if (plus >= 0) {
					normalized = normalized.substring(0, plus + 1) + normalized.substring(plus + 1).down();
				}
				var kv = (uint) 0;
				var md = (uint) 0;
				if (!IBus.key_event_from_string(normalized, out kv, out md)) {
					return false;
				}
				keyval = kv;
				mods = (IBus.ModifierType) md;
			}
			return keyval != 0;
		}

		/**
		 * One-shot: flatten legacy group layouts into ''[packs] lang=id''; if
		 * the active language has no entry, seed it from the ''model'' symlink.
		 *
		 * @param models pack catalog + config/system paths
		 */
		public void seed_pack_from_symlink(Models models)
		{
			var dirty = false;
			foreach (var group in this.packs.get_groups()) {
				if (group == "packs") {
					continue;
				}
				try {
					var old = this.packs.get_string(group, "pack");
					if (old == "") {
						continue;
					}
					if (models.languages.has_group(group)) {
						try {
							if (this.packs.get_string("packs", group) != "") {
								this.packs.remove_group(group);
								dirty = true;
								continue;
							}
						} catch (GLib.Error err) {
						}
						this.packs.set_string("packs", group, old);
					} else {
						var lang = this.key_file.get_string("general", "language");
						var fam = models.languages.get_string(lang, "family");
						if (fam == group) {
							try {
								if (this.packs.get_string("packs", lang) != "") {
									this.packs.remove_group(group);
									dirty = true;
									continue;
								}
							} catch (GLib.Error err) {
							}
							this.packs.set_string("packs", lang, old);
						}
					}
					this.packs.remove_group(group);
					dirty = true;
				} catch (GLib.Error err) {
				}
			}
			if (dirty) {
				this.save_packs();
			}

			var lang = this.key_file.get_string("general", "language");
			try {
				if (this.packs.get_string("packs", lang) != "") {
					return;
				}
			} catch (GLib.Error err) {
			}

			var link = GLib.Path.build_filename(models.user_config, "model");
			var path = "";
			try {
				if (GLib.FileUtils.test(link, GLib.FileTest.IS_SYMLINK)) {
					path = GLib.FileUtils.read_link(link);
				} else if (GLib.FileUtils.test(link, GLib.FileTest.IS_DIR)) {
					path = link;
				}
			} catch (GLib.FileError err) {
			}
			if (path == "") {
				return;
			}

			var base_name = GLib.Path.get_basename(path);
			foreach (var pack_id in models.packs.get_groups()) {
				try {
					if (models.packs.get_string(pack_id, "name") != base_name) {
						continue;
					}
					var dir = GLib.Path.build_filename(models.system_prefix, "models", base_name);
					if (!GLib.FileUtils.test(GLib.Path.build_filename(dir, ".sha256"),
							GLib.FileTest.IS_REGULAR)) {
						return;
					}
					this.packs.set_string("packs", lang, pack_id);
					if (lang != "en" && lang.has_prefix("en")) {
						this.packs.set_string("packs", "en", pack_id);
					}
					this.save_packs();
					GLib.debug("Seeded packs.ini packs/%s=%s from legacy symlink", lang, pack_id);
					return;
				} catch (GLib.Error err) {
				}
			}
		}
	}
}
