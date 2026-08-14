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

namespace IBSO.Debug
{
	/**
	 * Write one debug listen session under
	 * ''~/.cache/ibus-sherpa-onnx/debug/YYYY-MM-DD/''.
	 *
	 * Basename ''HHMMSS'' from listen start. ''.wav'' is mono 16 kHz S16LE for
	 * speakers; ''.f32'' is the live float ''accept_waveform'' PCM (Replay ASR);
	 * ''.chunks'' is LE int32 ops (optionally {@link IBSO.Session.OP_STAMPED}
	 * + (op, µs) pairs); ''.endpoints'' is LE int32 sample positions where live
	 * reset after ''is_endpoint''; ''.pending'' is the listen-stop partial;
	 * ''.feedlog'' is recognizer accept lines (''R''/''P''/''E''/''F''; ''E'' =
	 * endpoint cut sample off — also in ''.feedlog.replay''); ''.txt'' is UTF-8.
	 */
	public class Recording : GLib.Object
	{
		/**
		 * Persist session text + PCM + live chunk sizes + endpoint offsets (Idle).
		 *
		 * @param text committed transcripts for the listen (may be empty)
		 * @param samples float mono PCM at 16 kHz (same as accept_waveform)
		 * @param chunk_ns ''.chunks'' wire words (plain ops or stamped pairs)
		 * @param endpoint_offs sample positions of live endpoint resets
		 * @param started wall time at listen start (basename); null → now
		 * @param stop_pending listen-stop partial (written to ''.pending'')
		 * @param feedlog recognizer accept checksums (''.feedlog''; may be empty)
		 */
		public static void save(
			string text,
			float[] samples,
			int[] chunk_ns,
			int[] endpoint_offs,
			GLib.DateTime? started = null,
			string stop_pending = "",
			string feedlog = ""
		)
		{
			/* Skip empty transcripts — silence-only listens clutter Browse.
			 * Comment out if we ever need to debug “heard nothing” captures. */
			if (text.strip() == "") {
				return;
			}
			if (samples.length == 0) {
				return;
			}

			var ended = new GLib.DateTime.now_local();
			var stem_time = started ?? ended;
			var day = GLib.Path.build_filename(
				GLib.Environment.get_user_cache_dir(),
				"ibus-sherpa-onnx",
				"debug",
				ended.format("%Y-%m-%d")
			);

			GLib.DirUtils.create_with_parents(day, 0755);

			var stem = GLib.Path.build_filename(day, stem_time.format("%H%M%S"));
			try {
				GLib.FileUtils.set_contents(stem + ".txt", text);
			} catch (GLib.Error err) {
				GLib.warning("debug recording text: %s", err.message);
				return;
			}
			try {
				write_wav_s16le(stem + ".wav", samples, 16000);
			} catch (GLib.Error err) {
				GLib.warning("debug recording wav: %s", err.message);
				GLib.FileUtils.unlink(stem + ".txt");
				return;
			}
			/* Same floats the worker passed to accept_waveform (not S16 round-trip). */
			var f32 = GLib.FileStream.open(stem + ".f32", "wb");
			if (f32 == null) {
				GLib.warning("debug recording f32: open failed");
			} else {
				f32.write((uint8[]) samples);
			}
			var chunks = GLib.FileStream.open(stem + ".chunks", "wb");
			if (chunks == null) {
				GLib.warning("debug recording chunks: open failed");
			} else if (chunk_ns.length > 0) {
				/* FileStream.write → fwrite(ptr, size, nmemb). Cast int[]→uint8[]
				 * sets nmemb to byte length; size must stay 1 (not sizeof(int)),
				 * or the file is 4× too long and the tail is heap garbage. */
				chunks.write((uint8[]) chunk_ns);
			}
			var ends = GLib.FileStream.open(stem + ".endpoints", "wb");
			if (ends == null) {
				GLib.warning("debug recording endpoints: open failed");
			} else if (endpoint_offs.length > 0) {
				ends.write((uint8[]) endpoint_offs);
			}
			if (stop_pending != "") {
				try {
					GLib.FileUtils.set_contents(stem + ".pending", stop_pending);
				} catch (GLib.Error err) {
					GLib.warning("debug recording pending: %s", err.message);
				}
			}
			if (feedlog.strip() != "") {
				try {
					GLib.FileUtils.set_contents(stem + ".feedlog", feedlog);
				} catch (GLib.Error err) {
					GLib.warning("debug recording feedlog: %s", err.message);
				}
			}
		}

		/**
		 * Restrict live chunk sizes to a sample window ''[i0, i1)'' (CLI --from/--to).
		 *
		 * @param chunk_ns full-session sample counts
		 * @param i0 first sample index (inclusive)
		 * @param i1 end sample index (exclusive)
		 * @return chunk sizes covering only that window (may be empty)
		 */
		public static int[] slice_chunks(int[] chunk_ns, int i0, int i1)
		{
			var buf = new GLib.Array<int>(false, false, (uint) sizeof(int));
			if (i1 <= i0) {
				return new int[0];
			}
			var pos = 0;
			foreach (var n in chunk_ns) {
				var a = int.max(pos, i0);
				var b = int.min(pos + n, i1);
				if (b > a) {
					var len = b - a;
					buf.append_val(len);
				}
				pos += n;
				if (pos >= i1) {
					break;
				}
			}
			var result = new int[buf.length];
			if (buf.length > 0) {
				GLib.Memory.copy((void*) result, buf.data, buf.length * sizeof(int));
			}
			return result;
		}

		/**
		 * Stream a mono PCM WAV (16-bit little-endian) from float samples in [-1, 1].
		 *
		 * @param path destination ''.wav''
		 * @param samples float mono PCM
		 * @param sample_rate e.g. 16000
		 */
		public static void write_wav_s16le(string path, float[] samples, int sample_rate)
			throws GLib.Error
		{
			var out = new GLib.DataOutputStream(
				GLib.File.new_for_path(path).replace(null, false, GLib.FileCreateFlags.REPLACE_DESTINATION)
			) {
				byte_order = GLib.DataStreamByteOrder.LITTLE_ENDIAN
			};

			out.put_string("RIFF");
			out.put_uint32(36 + (uint32) (samples.length * 2));
			out.put_string("WAVE");
			out.put_string("fmt ");
			out.put_uint32(16);
			out.put_uint16(1);
			out.put_uint16(1);
			out.put_uint32((uint32) sample_rate);
			out.put_uint32((uint32) (sample_rate * 2));
			out.put_uint16(2);
			out.put_uint16(16);
			out.put_string("data");
			out.put_uint32((uint32) (samples.length * 2));

			for (var i = 0; i < samples.length; i++) {
				out.put_int16((int16) Math.roundf(Math.fminf(1.0f, Math.fmaxf(-1.0f, samples[i])) * 32767.0f));
			}
			out.close();
		}
	}
}
