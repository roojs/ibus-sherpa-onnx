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
	 * Fetch or symlink a Nemotron streaming model chunk.
	 *
	 * A vertical box (label, progress, Cancel) shown instead of the prefs page
	 * while a fetch runs. Download progress is bytes on disk vs an expected
	 * archive size; extract phase is labeled from the fetch script.
	 */
	public class ModelDownload : Gtk.Box
	{
		/** Known chunk sizes offered in prefs (ms). */
		public int[] chunks = { 560, 1120 };

		/** Rough download sizes matching {@link chunks}. */
		public string[] sizes = { "~430 MB", "~440 MB" };

		/** Files that must exist for a model tree to be usable. */
		public string[] needed = { "encoder.int8.onnx", "tokens.txt" };

		/** True while a fetch subprocess is running. */
		public bool busy { get; private set; default = false; }

		private Gtk.Label status_label;
		private Gtk.ProgressBar status_bar;
		private Gtk.Button cancel_btn;
		private GLib.Subprocess proc;
		private GLib.DataInputStream stdout_reader;
		private bool have_proc = false;
		private uint pulse_id = 0;
		private bool was_cancelled = false;
		private string pending_dir = "";
		private string pending_system = "";
		private string archive_path = "";
		private int64 expect_bytes = 0;
		private bool extracting = false;

		/**
		 * Fetch finished. ''ok'' means a complete model is linked.
		 */
		public signal void finished(bool ok, string message);

		/**
		 * User cancelled; Preferences should return to the editing page.
		 */
		public signal void cancelled();

		public ModelDownload()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 12,
				valign: Gtk.Align.CENTER,
				margin_start: 24, margin_end: 24, margin_top: 24, margin_bottom: 24);
			this.status_label = new Gtk.Label("") {
				xalign = 0, wrap = true, hexpand = true
			};
			this.status_bar = new Gtk.ProgressBar() {
				hexpand = true, show_text = true
			};
			this.cancel_btn = new Gtk.Button.with_label("Cancel") {
				halign = Gtk.Align.END
			};
			this.cancel_btn.clicked.connect(() => {
				this.cancel();
			});
			this.append(this.status_label);
			this.append(this.status_bar);
			this.append(this.cancel_btn);
		}

		/**
		 * True when ''dir'' has every {@link needed} file and a ''.sha256'' stamp
		 * matching the packaged checksum for that tree. No stamp → not ready.
		 */
		public bool ready(string dir)
		{
			foreach (var name in this.needed) {
				if (!GLib.FileUtils.test(GLib.Path.build_filename(dir, name), GLib.FileTest.IS_REGULAR)) {
					return false;
				}
			}
			var stamp = GLib.Path.build_filename(dir, ".sha256");
			if (!GLib.FileUtils.test(stamp, GLib.FileTest.IS_REGULAR)) {
				return false;
			}
			var base = GLib.Path.get_basename(dir);
			var expected = GLib.Path.build_filename("/usr/share/ibus-sherpa-onnx/checksums",
				base + ".sha256");
			if (!GLib.FileUtils.test(expected, GLib.FileTest.IS_REGULAR)) {
				expected = GLib.Path.build_filename(GLib.Environment.get_current_dir(),
					"data", "checksums", base + ".sha256");
			}
			if (!GLib.FileUtils.test(expected, GLib.FileTest.IS_REGULAR)) {
				return false;
			}
			try {
				string stamp_hash;
				string expect_hash;
				GLib.FileUtils.get_contents(stamp, out stamp_hash);
				GLib.FileUtils.get_contents(expected, out expect_hash);
				return stamp_hash.strip() == expect_hash.strip().split_set(" \t\n", 2)[0];
			} catch (GLib.Error err) {
				return false;
			}
		}

		/**
		 * Link an installed model, or start a fetch if missing.
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

			var dir = "sherpa-onnx-nemotron-speech-streaming-en-0.6b-%dms-int8-2026-04-25".printf(chunk);
			var system_path = GLib.Path.build_filename("/usr/share/ibus-sherpa-onnx/models", dir);
			var user_path = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(),
				"ibus-sherpa-onnx", "models", dir);
			if (this.ready(system_path)) {
				this.link(system_path);
				return false;
			}
			if (this.ready(user_path)) {
				this.link(user_path);
				return false;
			}

			this.busy = true;
			this.was_cancelled = false;
			this.have_proc = false;
			this.extracting = false;
			this.pending_dir = dir;
			this.pending_system = system_path;
			this.archive_path = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(),
				"ibus-sherpa-onnx", "models", dir + ".tar.bz2");
			// GitHub release Content-Length for these archives (~442.4 MiB).
			this.expect_bytes = (chunk == 1120) ? (int64) 463945058 : (int64) 463945051;
			this.cancel_btn.sensitive = true;
			this.status_label.label = "Downloading… 0 MB / ~%.0f MB".printf(
				this.expect_bytes / (1024.0 * 1024.0));
			this.status_bar.fraction = 0.0;
			this.status_bar.text = "0%";

			this.pulse_id = GLib.Timeout.add(250, () => {
				if (!this.busy) {
					this.pulse_id = 0;
					return GLib.Source.REMOVE;
				}
				if (this.extracting) {
					this.status_label.label = "Extracting…";
					this.status_bar.pulse();
					this.status_bar.text = "";
					return GLib.Source.CONTINUE;
				}
				var size = (int64) 0;
				try {
					var info = GLib.File.new_for_path(this.archive_path).query_info(
						GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE);
					size = info.get_size();
				} catch (GLib.Error err) {
				}
				if (size <= 0) {
					this.status_label.label = "Downloading… (starting)";
					this.status_bar.pulse();
					this.status_bar.text = "";
					return GLib.Source.CONTINUE;
				}
				var frac = (double) size / (double) this.expect_bytes;
				if (frac > 0.99) {
					frac = 0.99;
				}
				this.status_bar.fraction = frac;
				this.status_bar.text = "%d%%".printf((int) (frac * 100.0));
				this.status_label.label = "Downloading… %.0f MB / ~%.0f MB".printf(
					size / (1024.0 * 1024.0), this.expect_bytes / (1024.0 * 1024.0));
				return GLib.Source.CONTINUE;
			});

			var script = "/usr/share/ibus-sherpa-onnx/fetch-nemotron-model.sh";
			if (!GLib.FileUtils.test(script, GLib.FileTest.IS_EXECUTABLE)) {
				script = GLib.Path.build_filename(GLib.Environment.get_current_dir(),
					"scripts", "fetch-nemotron-model.sh");
			}
			string[] argv = { script, chunk.to_string() };
			try {
				var launcher = new GLib.SubprocessLauncher(
					GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_MERGE);
				this.proc = launcher.spawnv(argv);
				this.have_proc = true;
				this.stdout_reader = new GLib.DataInputStream(this.proc.get_stdout_pipe());
				this.read_stdout();
				this.proc.wait_async.begin(null, this.wait_async);
			} catch (GLib.Error err) {
				if (this.pulse_id != 0) {
					GLib.Source.remove(this.pulse_id);
					this.pulse_id = 0;
				}
				this.busy = false;
				this.status_label.label = err.message;
				this.status_bar.fraction = 0.0;
				this.status_bar.text = "";
				this.finished(false, err.message);
			}
			return true;
		}

		/**
		 * Abort the fetch and emit {@link cancelled}.
		 */
		public void cancel()
		{
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
			if (this.have_proc) {
				this.proc.force_exit();
			}
		}

		/** Remove truncated archive / unpack for the in-flight chunk. */
		private void discard_partial()
		{
			if (this.pending_dir == "") {
				return;
			}
			var models = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(),
				"ibus-sherpa-onnx", "models");
			var dir = GLib.Path.build_filename(models, this.pending_dir);
			if (GLib.FileUtils.test(dir, GLib.FileTest.IS_DIR) && !this.ready(dir)) {
				try {
					string[] argv = { "rm", "-rf", dir };
					GLib.Process.spawn_sync(null, argv, null, GLib.SpawnFlags.SEARCH_PATH,
						null, null, null, null);
				} catch (GLib.Error err) {
					GLib.warning("cleanup model dir: %s", err.message);
				}
			}
			if (this.archive_path != "" && GLib.FileUtils.test(this.archive_path, GLib.FileTest.IS_REGULAR)) {
				var size = (int64) 0;
				try {
					var info = GLib.File.new_for_path(this.archive_path).query_info(
						GLib.FileAttribute.STANDARD_SIZE, GLib.FileQueryInfoFlags.NONE);
					size = info.get_size();
				} catch (GLib.Error err) {
				}
				if (size < this.expect_bytes * 9 / 10) {
					GLib.FileUtils.remove(this.archive_path);
				}
			}
		}

		private void read_stdout()
		{
			this.stdout_reader.read_line_async.begin(GLib.Priority.DEFAULT, null, (obj, res) => {
				try {
					var line = this.stdout_reader.read_line_async.end(res);
					if (line == null) {
						return;
					}
					if (line.has_prefix("Unpacking")) {
						this.extracting = true;
						this.status_label.label = "Extracting…";
						this.status_bar.text = "";
					} else if (line.has_prefix("Downloading")) {
						this.extracting = false;
					} else if (line.has_prefix("Done:") || line.has_prefix("Model already")
							|| line.has_prefix("User model") || line.has_prefix("System model")) {
						this.status_label.label = line;
					}
					this.read_stdout();
				} catch (GLib.Error err) {
				}
			});
		}

		private void wait_async(GLib.Object? obj, GLib.AsyncResult res)
		{
			try {
				this.proc.wait_async.end(res);
			} catch (GLib.Error err) {
				GLib.warning("fetch: %s", err.message);
			}
			if (this.pulse_id != 0) {
				GLib.Source.remove(this.pulse_id);
				this.pulse_id = 0;
			}
			this.busy = false;
			this.have_proc = false;
			this.cancel_btn.sensitive = true;
			if (this.was_cancelled) {
				this.was_cancelled = false;
				this.discard_partial();
				this.status_label.label = "";
				this.status_bar.text = "";
				this.cancelled();
				return;
			}
			var installed = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(),
				"ibus-sherpa-onnx", "models", this.pending_dir);
			if (!this.ready(installed) && !this.ready(this.pending_system)) {
				this.discard_partial();
				this.status_label.label = "Download failed. Run the fetch script from a terminal.";
				this.status_bar.fraction = 0.0;
				this.status_bar.text = "";
				this.finished(false, this.status_label.label);
				return;
			}
			this.link(this.ready(this.pending_system) ? this.pending_system : installed);
			this.status_label.label = "Model ready. Restart the IME if it was running.";
			this.status_bar.fraction = 1.0;
			this.status_bar.text = "100%";
			this.finished(true, this.status_label.label);
		}

		private void link(string target)
		{
			var link_dir = GLib.Path.build_filename(GLib.Environment.get_user_config_dir(),
				"ibus-sherpa-onnx");
			GLib.DirUtils.create_with_parents(link_dir, 0755);
			var link = GLib.File.new_for_path(GLib.Path.build_filename(link_dir, "model"));
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
