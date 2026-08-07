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
	 * Nemotron catalog ({@link packs} / {@link languages} KeyFiles) and cleanup.
	 *
	 * Catalog data is embedded GResource KeyFiles — read fields with the usual
	 * {@link GLib.KeyFile} getters. A tree is usable when it has a local
	 * ''.sha256'' stamp (written after download verify).
	 */
	public class Models : GLib.Object
	{
		/**
		 * Embedded ''resources/models.ini'' (pack groups).
		 */
		public GLib.KeyFile packs;

		/**
		 * Embedded ''resources/languages.ini'' (language groups).
		 */
		public GLib.KeyFile languages;

		/**
		 * ''~/.config/ibus-sherpa-onnx'' (user models + active symlink).
		 */
		public string user_config;

		/**
		 * Packaged prefix (''/usr/share/ibus-sherpa-onnx'').
		 */
		public string system_prefix = "/usr/share/ibus-sherpa-onnx";

		/**
		 * Directory of packaged ''*.sha256'' digests (system or checkout).
		 * Only used by prefs download verify until that switches to GitHub asset digest.
		 */
		public string checksums_dir;

		public Models()
		{
			this.user_config = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(),
				"ibus-sherpa-onnx");
			var system = GLib.Path.build_filename(this.system_prefix, "checksums");
			if (GLib.FileUtils.test(system, GLib.FileTest.IS_DIR)) {
				this.checksums_dir = system;
			} else {
				var local = GLib.Path.build_filename(GLib.Environment.get_current_dir(),
					"data", "checksums");
				this.checksums_dir = GLib.FileUtils.test(local, GLib.FileTest.IS_DIR) ? local : system;
			}
			this.packs = new GLib.KeyFile();
			this.languages = new GLib.KeyFile();
			this.packs.load_from_bytes(
				GLib.resources_lookup_data("/models.ini", GLib.ResourceLookupFlags.NONE),
				GLib.KeyFileFlags.NONE);
			this.languages.load_from_bytes(
				GLib.resources_lookup_data("/languages.ini", GLib.ResourceLookupFlags.NONE),
				GLib.KeyFileFlags.NONE);
		}

		/**
		 * Remove an incomplete user unpack and truncated archive for ''pack_id''.
		 */
		public void discard_partial(string pack_id)
		{
			if (pack_id == "") {
				return;
			}
			var name = this.packs.get_string(pack_id, "name");
			var expect = this.packs.get_int64(pack_id, "archive_bytes");
			var cache = GLib.Path.build_filename(GLib.Environment.get_user_cache_dir(),
				"ibus-sherpa-onnx", "download");
			var staged = GLib.Path.build_filename(cache, name);
			if (GLib.FileUtils.test(staged, GLib.FileTest.IS_DIR)
					&& !GLib.FileUtils.test(GLib.Path.build_filename(staged, ".sha256"),
						GLib.FileTest.IS_REGULAR)) {
				try {
					string[] argv = { "rm", "-rf", staged };
					GLib.Process.spawn_sync(null, argv, null, GLib.SpawnFlags.SEARCH_PATH,
						null, null, null, null);
				} catch (GLib.Error err) {
					GLib.warning("cleanup staged model: %s", err.message);
				}
			}
			var archive = GLib.Path.build_filename(cache, name + ".tar.bz2");
			if (GLib.FileUtils.test(archive + ".partial", GLib.FileTest.IS_REGULAR)) {
				GLib.FileUtils.remove(archive + ".partial");
			}
			if (!GLib.FileUtils.test(archive, GLib.FileTest.IS_REGULAR)) {
				return;
			}
			int64 size = 0;
			try {
				var info = GLib.File.new_for_path(archive).query_info(
					GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE);
				size = info.get_size();
			} catch (GLib.Error err) {
			}
			if (size < expect * 9 / 10) {
				GLib.FileUtils.remove(archive);
			}
		}

		/**
		 * Add one {@link IBus.EngineDesc} per catalog language to ''component''.
		 *
		 * @param component IBus component (unpackaged registration)
		 */
		public void register_engines(IBus.Component component)
		{
			foreach (var code in this.languages.get_groups()) {
				var engine_id = code == "en" ? "sherpa-onnx" : "sherpa-onnx-" + code;
				var longname = code == "en" ? "Sherpa ONNX" : "Sherpa ONNX (" + code + ")";
				var layout = "us";
				var parts = code.split("-", 2);
				if (parts.length >= 2) {
					layout = parts[1].down();
					if (parts[1] == "AR") {
						layout = "ara";
					}
					if (parts[1] == "IN") {
						layout = "in";
					}
				}
				/* ''ro-RO'' → ''ro-v''; ''en-US'' → ''en-us-v''. */
				var tag = code.down().split("-", 2);
				var symbol = tag[0] + "-v";
				if (tag.length >= 2 && tag[0] != tag[1]) {
					symbol = tag[0] + "-" + tag[1] + "-v";
				}
				component.add_engine((IBus.EngineDesc) GLib.Object.new(
					typeof(IBus.EngineDesc),
					"name", engine_id,
					"longname", longname,
					"description", "Local speech-to-text dictation",
					"language", code.split("-")[0],
					"license", "LGPL",
					"author", "Alan Knowles <alan@roojs.com>",
					"icon", "",
					"layout", layout,
					"symbol", symbol,
					"setup", "/usr/bin/ibus-setup-sherpa-onnx"
				));
			}
		}
	}
}
