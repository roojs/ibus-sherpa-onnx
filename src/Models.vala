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
	 * Nemotron model catalog, readiness, and cleanup.
	 *
	 * Shared by the IBus engine and ''ibus-setup-sherpa-onnx''. Construct once
	 * and query — paths come from {@link user_config} / {@link system_prefix}
	 * plus {@link names}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var models = new Models();
	 * var dir = models.resolve();
	 * if (dir == "") {
	 *     GLib.critical("no model");
	 * }
	 * }}}
	 */
	public class Models : GLib.Object
	{
		/**
		 * Chunk sizes offered in prefs (ms), parallel to {@link names}.
		 */
		public int[] chunks = { 560, 1120 };

		/**
		 * Rough archive download sizes matching {@link chunks}.
		 */
		public string[] sizes = { "~430 MB", "~440 MB" };

		/**
		 * GitHub Content-Length for each {@link chunks} archive.
		 */
		public int64[] archive_bytes = { 463945051, 463945058 };

		/**
		 * Unpack dir / archive basename for each {@link chunks} entry.
		 */
		public string[] names = {
			"sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25",
			"sherpa-onnx-nemotron-speech-streaming-en-0.6b-1120ms-int8-2026-04-25"
		};

		/**
		 * Files required in a usable model tree.
		 */
		public string[] needed = {
			"encoder.int8.onnx",
			"decoder.int8.onnx",
			"joiner.int8.onnx",
			"tokens.txt"
		};

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
		 */
		public string checksums_dir;

		public Models()
		{
			this.user_config = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(),
				"ibus-sherpa-onnx");
			var system = GLib.Path.build_filename(this.system_prefix, "checksums");
			if (GLib.FileUtils.test(system, GLib.FileTest.IS_DIR)) {
				this.checksums_dir = system;
				return;
			}
			var local = GLib.Path.build_filename(GLib.Environment.get_current_dir(),
				"data", "checksums");
			this.checksums_dir = GLib.FileUtils.test(local, GLib.FileTest.IS_DIR) ? local : system;
		}

		/**
		 * True when ''dir'' has required files and a ''.sha256'' stamp matching
		 * the packaged digest. Pre-stamp installs with a full-sized encoder get
		 * a stamp written once (truncated trees fail the size gate).
		 *
		 * @param dir model tree path (resolved symlink target, not the link)
		 * @return true if the tree is safe to load
		 */
		public bool ready(string dir)
		{
			foreach (var name in this.needed) {
				if (!GLib.FileUtils.test(GLib.Path.build_filename(dir, name), GLib.FileTest.IS_REGULAR)) {
					return false;
				}
			}
			var tree = GLib.Path.get_basename(dir);
			var expect_path = GLib.Path.build_filename(this.checksums_dir, tree + ".sha256");
			if (!GLib.FileUtils.test(expect_path, GLib.FileTest.IS_REGULAR)) {
				return false;
			}
			var expected = "";
			try {
				var contents = "";
				GLib.FileUtils.get_contents(expect_path, out contents);
				expected = contents.strip().split_set(" \t\n", 2)[0];
			} catch (GLib.Error err) {
				return false;
			}
			if (expected == "") {
				return false;
			}
			var stamp = GLib.Path.build_filename(dir, ".sha256");
			if (GLib.FileUtils.test(stamp, GLib.FileTest.IS_REGULAR)) {
				try {
					var stamp_hash = "";
					GLib.FileUtils.get_contents(stamp, out stamp_hash);
					return stamp_hash.strip() == expected;
				} catch (GLib.Error err) {
					return false;
				}
			}
			try {
				var info = GLib.File.new_for_path(GLib.Path.build_filename(dir, "encoder.int8.onnx")).query_info(
					GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE);
				int64 min_bytes = tree.contains("-1120ms-") ? 1000L * 1024 * 1024 : 500L * 1024 * 1024;
				if (info.get_size() < min_bytes) {
					return false;
				}
			} catch (GLib.Error err) {
				return false;
			}
			try {
				GLib.FileUtils.set_contents(stamp, expected + "\n");
			} catch (GLib.Error err) {
				return false;
			}
			return true;
		}

		/**
		 * Active ready model: user ''model'' symlink, else auto-link the largest
		 * ready tree under system ''models/'' (user ''models/'' is download staging only).
		 *
		 * @return absolute model tree path, or "" if none is ready
		 */
		public string resolve()
		{
			var link = GLib.Path.build_filename(this.user_config, "model");
			if (GLib.File.new_for_path(link).query_file_type(GLib.FileQueryInfoFlags.NONE)
					== GLib.FileType.DIRECTORY) {
				var path = link;
				try {
					if (GLib.FileUtils.test(link, GLib.FileTest.IS_SYMLINK)) {
						path = GLib.FileUtils.read_link(link);
					}
				} catch (GLib.FileError err) {
				}
				if (this.ready(path)) {
					return path;
				}
			}

			var best = "";
			var best_bytes = (int64) 0;
			for (var i = 0; i < this.names.length; i++) {
				var candidate = GLib.Path.build_filename(this.system_prefix, "models", this.names[i]);
				if (!this.ready(candidate) || this.archive_bytes[i] <= best_bytes) {
					continue;
				}
				best_bytes = this.archive_bytes[i];
				best = candidate;
			}
			if (best == "") {
				return "";
			}
			GLib.DirUtils.create_with_parents(this.user_config, 0755);
			var link_file = GLib.File.new_for_path(link);
			try {
				if (link_file.query_exists()) {
					link_file.delete();
				}
				link_file.make_symbolic_link(best);
			} catch (GLib.Error err) {
				GLib.warning("auto-link model: %s", err.message);
				return best;
			}
			GLib.debug("Auto-linked %s -> %s", link, best);
			return best;
		}

		/**
		 * Remove an incomplete user unpack and truncated archive for ''chunk''.
		 *
		 * @param chunk chunk size in ms (0 is a no-op)
		 */
		public void discard_partial(int chunk)
		{
			if (chunk == 0) {
				return;
			}
			var name = "";
			int64 expect = 0;
			for (var i = 0; i < this.chunks.length; i++) {
				if (this.chunks[i] != chunk) {
					continue;
				}
				name = this.names[i];
				expect = this.archive_bytes[i];
				break;
			}
			if (name == "") {
				return;
			}
			var cache = GLib.Path.build_filename(GLib.Environment.get_user_cache_dir(),
				"ibus-sherpa-onnx", "download");
			var staged = GLib.Path.build_filename(cache, name);
			if (GLib.FileUtils.test(staged, GLib.FileTest.IS_DIR) && !this.ready(staged)) {
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
	}
}
