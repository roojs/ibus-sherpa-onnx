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

namespace IBus.SherpaOnnx.Setup
{
	/**
	 * Download or symlink a Nemotron streaming model chunk.
	 *
	 * A vertical box (label, progress, Cancel) shown instead of the prefs page
	 * while Soup download + libarchive extract runs. Paths and readiness come
	 * from {@link Models}.
	 */
	public class ModelDownload : Gtk.Box
	{
		/** Shared model metadata / readiness. */
		public Models models;

		/** True while download or extract is running. */
		public bool busy { get; private set; default = false; }

		private Gtk.Label status_label;
		private Gtk.ProgressBar status_bar;
		private Gtk.Button cancel_btn;
		private Soup.Session soup = new Soup.Session();
		private GLib.Cancellable cancellable = new GLib.Cancellable();
		private bool was_cancelled = false;
		private int pending_chunk = 0;
		private string pending_name = "";
		private string pending_system = "";
		private string archive_path = "";
		private int64 expect_bytes = 0;

		/**
		 * Pipeline finished. ''ok'' means a complete model is linked.
		 */
		public signal void finished(bool ok, string message);

		/**
		 * User cancelled; Preferences should return to the editing page.
		 */
		public signal void cancelled();

		public ModelDownload(Models models)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 12,
				valign: Gtk.Align.START, vexpand: false,
				margin_start: 24, margin_end: 24, margin_top: 24, margin_bottom: 24);
			this.models = models;
			this.soup.timeout = 0;
			this.status_label = new Gtk.Label("") {
				xalign = 0, wrap = false, hexpand = true,
				ellipsize = Pango.EllipsizeMode.END, single_line_mode = true
			};
			this.status_bar = new Gtk.ProgressBar() {
				hexpand = true, show_text = true
			};
			this.cancel_btn = new Gtk.Button.with_label("Cancel") {
				halign = Gtk.Align.END
			};
			this.cancel_btn.clicked.connect(() => {
				if (!this.busy) {
					if (this.status_label.label != "") {
						this.cancelled();
					}
					return;
				}
				this.was_cancelled = true;
				this.cancel_btn.sensitive = false;
				this.status_label.label = "Cancelling…";
				this.status_bar.pulse();
				this.status_bar.text = "";
				this.cancellable.cancel();
			});
			this.append(this.status_label);
			this.append(this.status_bar);
			this.append(this.cancel_btn);
		}

		/**
		 * Link an installed model, or start Soup download if missing.
		 *
		 * @return true if async work started (caller should show this widget)
		 */
		public bool apply(int chunk)
		{
			if (this.busy) {
				return true;
			}
			if (chunk == 0) {
				return false;
			}

			var name = "";
			int64 expect = 0;
			for (var i = 0; i < this.models.chunks.length; i++) {
				if (this.models.chunks[i] != chunk) {
					continue;
				}
				name = this.models.names[i];
				expect = this.models.archive_bytes[i];
				break;
			}
			var system_path = GLib.Path.build_filename(this.models.system_prefix, "models", name);
			var user_path = GLib.Path.build_filename(this.models.user_config, "models", name);
			if (this.models.ready(system_path)) {
				this.link(system_path);
				return false;
			}
			if (this.models.ready(user_path)) {
				this.link(user_path);
				return false;
			}

			this.busy = true;
			this.was_cancelled = false;
			this.pending_chunk = chunk;
			this.pending_name = name;
			this.pending_system = system_path;
			this.expect_bytes = expect;
			var cache = GLib.Path.build_filename(GLib.Environment.get_user_cache_dir(),
				"ibus-sherpa-onnx", "download");
			GLib.DirUtils.create_with_parents(cache, 0755);
			this.archive_path = GLib.Path.build_filename(cache, name + ".tar.bz2");
			this.cancel_btn.sensitive = true;
			this.status_label.label = "Downloading… 0 MB / ~%.0f MB".printf(expect / (1024.0 * 1024.0));
			this.status_bar.fraction = 0.0;
			this.status_bar.text = "0%";
			this.download_archive.begin();
			return true;
		}

		/**
		 * Soup GET {@link archive_path} from k2-fsa ''asr-models'' (''.partial'' resume).
		 */
		private async void download_archive()
		{
			if (GLib.FileUtils.test(this.archive_path, GLib.FileTest.IS_REGULAR)) {
				this.extract_archive();
				return;
			}
			this.cancellable = new GLib.Cancellable();
			try {
				int64 bytes_written = 0;
				if (GLib.FileUtils.test(this.archive_path + ".partial", GLib.FileTest.IS_REGULAR)) {
					bytes_written = GLib.File.new_for_path(this.archive_path + ".partial").query_info(
						GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE).get_size();
				}
				var msg = new Soup.Message("GET",
					"https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/%s.tar.bz2"
						.printf(this.pending_name));
				if (bytes_written > 0) {
					msg.request_headers.replace("Range", "bytes=%s-".printf(bytes_written.to_string()));
				}
				var input = yield this.soup.send_async(msg, GLib.Priority.DEFAULT, this.cancellable);
				if (msg.status_code != 200 && msg.status_code != 206) {
					throw new GLib.IOError.FAILED("HTTP %u", msg.status_code);
				}
				int64 total = (int64) msg.response_headers.get_content_length();
				if (msg.status_code == 206 && total > 0) {
					total += bytes_written;
				}
				if (total <= 0) {
					total = this.expect_bytes;
				}
				GLib.FileOutputStream out_stream;
				if (bytes_written > 0 && msg.status_code == 206) {
					out_stream = GLib.File.new_for_path(this.archive_path + ".partial").append_to(
						GLib.FileCreateFlags.NONE);
				} else {
					bytes_written = 0;
					out_stream = GLib.File.new_for_path(this.archive_path + ".partial").replace(
						null, false, GLib.FileCreateFlags.NONE);
				}
				var buf = new uint8[65536];
				int64 last_progress_us = 0;
				while (true) {
					var n = yield input.read_async(buf, GLib.Priority.DEFAULT, this.cancellable);
					if (n <= 0) {
						break;
					}
					out_stream.write(buf[0:n]);
					bytes_written += n;
					var now = GLib.get_monotonic_time();
					if (last_progress_us != 0 && now - last_progress_us < 250000) {
						continue;
					}
					last_progress_us = now;
					var use_total = total > 0 ? total : this.expect_bytes;
					if (use_total <= 0) {
						this.status_label.label = "Downloading… %.0f MB".printf(
							bytes_written / (1024.0 * 1024.0));
						this.status_bar.pulse();
						this.status_bar.text = "";
					} else {
						var frac = Math.fmin(1.0, (double) bytes_written / (double) use_total);
						this.status_bar.fraction = frac;
						this.status_bar.text = "%d%%".printf((int) (frac * 100.0));
						this.status_label.label = "Downloading… %.0f MB / ~%.0f MB".printf(
							bytes_written / (1024.0 * 1024.0), use_total / (1024.0 * 1024.0));
					}
				}
				out_stream.close();
				if (total > 0 && bytes_written != total) {
					throw new GLib.IOError.FAILED("size mismatch: got %s expected %s",
						bytes_written.to_string(), total.to_string());
				}
				GLib.File.new_for_path(this.archive_path + ".partial").move(
					GLib.File.new_for_path(this.archive_path), GLib.FileCopyFlags.OVERWRITE);
			} catch (GLib.Error err) {
				if (this.was_cancelled || err is GLib.IOError.CANCELLED) {
					this.complete("");
					return;
				}
				if (GLib.FileUtils.test(this.archive_path + ".partial", GLib.FileTest.IS_REGULAR)) {
					GLib.FileUtils.remove(this.archive_path + ".partial");
				}
				this.complete(err.message);
				return;
			}

			this.extract_archive();
		}

		/**
		 * Verify, unpack, stamp, and link on a worker thread.
		 *
		 * Worker queues Idle → {@link archive_progress} / {@link archive_done}
		 * on the main loop.
		 */
		private void extract_archive()
		{
			this.cancellable = new GLib.Cancellable();
			this.status_label.label = "Verifying archive…";
			this.status_bar.fraction = 0.0;
			this.status_bar.text = "0%";
			this.cancel_btn.sensitive = true;

			var expect_path = GLib.Path.build_filename(this.models.checksums_dir,
				this.pending_name + ".sha256");
			var expected = "";
			try {
				var contents = "";
				GLib.FileUtils.get_contents(expect_path, out contents);
				expected = contents.strip().split_set(" \t\n", 2)[0];
			} catch (GLib.Error err) {
				this.complete("Missing checksum: %s".printf(expect_path));
				return;
			}
			if (expected == "") {
				this.complete("Empty checksum: %s".printf(expect_path));
				return;
			}

			var dest_root = GLib.Path.build_filename(this.models.user_config, "models");
			var user_path = GLib.Path.build_filename(dest_root, this.pending_name);
			GLib.DirUtils.create_with_parents(dest_root, 0755);
			if (GLib.FileUtils.test(user_path, GLib.FileTest.IS_DIR) && !this.models.ready(user_path)) {
				try {
					string[] argv = { "rm", "-rf", user_path };
					GLib.Process.spawn_sync(null, argv, null, GLib.SpawnFlags.SEARCH_PATH,
						null, null, null, null);
				} catch (GLib.Error err) {
					this.complete(err.message);
					return;
				}
			}

			/* Thread capture: snapshot fields the worker must not race with apply/cancel. */
			var archive_path = this.archive_path;
			var expect_bytes = this.expect_bytes;
			var cancellable = this.cancellable;

			new GLib.Thread<void*>("model-extract", () => {
				/* Idle capture: error for main-loop archive_done. */
				var done_error = "";
				try {
					this.unpack_archive(archive_path, dest_root, user_path, expected,
						expect_bytes, cancellable);
				} catch (GLib.IOError.CANCELLED err) {
				} catch (GLib.Error err) {
					done_error = err.message;
				}
				GLib.Idle.add(() => {
					this.archive_done(done_error);
					return GLib.Source.REMOVE;
				});
				return null;
			});
		}

		/**
		 * Main-loop progress update (called from Idle).
		 */
		private void archive_progress(string label, double fraction)
		{
			this.status_label.label = label;
			this.status_bar.fraction = fraction;
			this.status_bar.text = "%d%%".printf((int) (fraction * 100.0));
		}

		/**
		 * Main-loop extract finish (called from Idle). Empty ''error'' is success.
		 */
		private void archive_done(string error)
		{
			if (this.was_cancelled || this.cancellable.is_cancelled()) {
				this.complete("");
				return;
			}
			if (error != "") {
				this.complete(error);
				return;
			}
			var user_path = GLib.Path.build_filename(this.models.user_config, "models",
				this.pending_name);
			if (!this.models.ready(user_path)) {
				this.complete("Extract finished but model is not ready");
				return;
			}
			this.busy = false;
			this.cancel_btn.sensitive = true;
			this.status_bar.fraction = 1.0;
			this.status_bar.text = "Done";
			this.status_label.label = "Model ready";
			this.link(user_path);
			this.finished(true, "");
		}

		/**
		 * SHA-256 verify + libarchive extract into ''dest_root'', then write ''.sha256''.
		 *
		 * Runs on a worker thread; progress via Idle → {@link archive_progress}.
		 */
		private void unpack_archive(
			string archive_path,
			string dest_root,
			string user_path,
			string expected,
			int64 expect_bytes,
			GLib.Cancellable cancellable
		) throws GLib.Error
		{
			var checksum = new GLib.Checksum(GLib.ChecksumType.SHA256);
			var stream = GLib.File.new_for_path(archive_path).read();
			var total = GLib.File.new_for_path(archive_path).query_info(
				GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE).get_size();
			var buf = new uint8[65536];
			var hashed = (int64) 0;
			var last_progress_us = (int64) 0;
			while (true) {
				if (cancellable.is_cancelled()) {
					throw new GLib.IOError.CANCELLED("cancelled");
				}
				var n = stream.read(buf);
				if (n <= 0) {
					break;
				}
				checksum.update(buf, n);
				hashed += n;
				var now = GLib.get_monotonic_time();
				if (last_progress_us != 0 && now - last_progress_us < 250000) {
					continue;
				}
				last_progress_us = now;
				/* Idle capture: marshal progress onto the main loop. */
				var progress_label = "Verifying… %.0f MB / %.0f MB".printf(
					hashed / (1024.0 * 1024.0), total / (1024.0 * 1024.0));
				var progress_fraction = total > 0
					? Math.fmin(1.0, (double) hashed / (double) total) : 0.0;
				GLib.Idle.add(() => {
					this.archive_progress(progress_label, progress_fraction);
					return GLib.Source.REMOVE;
				});
			}
			stream.close();
			if (checksum.get_string() != expected) {
				throw new GLib.IOError.FAILED("SHA-256 mismatch");
			}

			GLib.Idle.add(() => {
				this.archive_progress("Extracting…", 0.0);
				return GLib.Source.REMOVE;
			});

			var archive = new Archive.Read();
			archive.support_filter_all();
			archive.support_format_all();
			var extractor = new Archive.WriteDisk();
			extractor.set_options(Archive.ExtractFlags.TIME
				| Archive.ExtractFlags.PERM
				| Archive.ExtractFlags.SECURE_NODOTDOT
				| Archive.ExtractFlags.SECURE_SYMLINKS);
			extractor.set_standard_lookup();
			if (archive.open_filename(archive_path, 10240) != Archive.Result.OK) {
				throw new GLib.IOError.FAILED("Open archive: %s", archive.error_string());
			}

			unowned Archive.Entry entry;
			var last = Archive.Result.OK;
			last_progress_us = 0;
			while ((last = archive.next_header(out entry)) == Archive.Result.OK) {
				if (cancellable.is_cancelled()) {
					throw new GLib.IOError.CANCELLED("cancelled");
				}
				var path = entry.pathname();
				if (path == null || path == ""
						|| GLib.Path.is_absolute(path)
						|| path.has_prefix("../")
						|| path.contains("/../")
						|| path.has_suffix("/..")) {
					throw new GLib.IOError.FAILED("Unsafe path in archive");
				}
				entry.set_pathname(GLib.Path.build_filename(dest_root, path));
				if (extractor.write_header(entry) != Archive.Result.OK) {
					continue;
				}
				unowned uint8[] block;
				Archive.int64_t offset;
				while (archive.read_data_block(out block, out offset) == Archive.Result.OK) {
					if (extractor.write_data_block(block, offset) < 0) {
						throw new GLib.IOError.FAILED("Extract write: %s",
							extractor.error_string());
					}
				}
				extractor.finish_entry();
				var now = GLib.get_monotonic_time();
				if (last_progress_us != 0 && now - last_progress_us < 250000) {
					continue;
				}
				last_progress_us = now;
				var pos = (int64) archive.position_compressed();
				var use_total = expect_bytes > 0 ? expect_bytes : total;
				/* Idle capture: marshal progress onto the main loop. */
				var progress_label = "Extracting… %.0f MB / ~%.0f MB".printf(
					pos / (1024.0 * 1024.0), use_total / (1024.0 * 1024.0));
				var progress_fraction = use_total > 0
					? Math.fmin(1.0, (double) pos / (double) use_total) : 0.0;
				GLib.Idle.add(() => {
					this.archive_progress(progress_label, progress_fraction);
					return GLib.Source.REMOVE;
				});
			}
			archive.close();
			if (last != Archive.Result.EOF) {
				throw new GLib.IOError.FAILED("Extract: %s", archive.error_string());
			}
			GLib.FileUtils.set_contents(
				GLib.Path.build_filename(user_path, ".sha256"), expected + "\n");
		}

		/**
		 * End an unsuccessful pipeline. Empty ''message'' means user cancel;
		 * otherwise treat as an error and emit {@link finished}.
		 */
		private void complete(string message)
		{
			this.busy = false;
			this.cancel_btn.sensitive = true;
			this.models.discard_partial(this.pending_chunk);
			this.status_bar.fraction = 0.0;
			this.status_bar.text = "";
			this.status_label.label = message;
			if (message == "") {
				this.was_cancelled = false;
				this.cancelled();
				return;
			}
			this.finished(false, message);
		}

		private void link(string target)
		{
			GLib.DirUtils.create_with_parents(this.models.user_config, 0755);
			var link = GLib.File.new_for_path(GLib.Path.build_filename(this.models.user_config, "model"));
			try {
				if (link.query_exists()) {
					link.delete();
				}
				link.make_symbolic_link(target);
			} catch (GLib.Error err) {
				GLib.warning("symlink model: %s", err.message);
			}
		}
	}
}
