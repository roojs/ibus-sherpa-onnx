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
	 * ''.chunks'' is LE int32 sample counts per accept; ''.endpoints'' is LE
	 * int32 sample positions where live reset after ''is_endpoint''; ''.txt'' is UTF-8.
	 */
	public class Recording : GLib.Object
	{
		/**
		 * Persist session text + PCM + live chunk sizes + endpoint offsets (Idle).
		 *
		 * @param text committed transcripts for the listen (may be empty)
		 * @param samples float mono PCM at 16 kHz (same as accept_waveform)
		 * @param chunk_ns sample count per accept_waveform during the listen
		 * @param endpoint_offs sample positions of live endpoint resets
		 * @param started wall time at listen start (basename); null → now
		 */
		public static void save(
			string text,
			float[] samples,
			int[] chunk_ns,
			int[] endpoint_offs,
			GLib.DateTime? started = null
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
		}

		/**
		 * Load live ''accept_waveform'' sizes from a sibling ''.chunks'' file.
		 *
		 * @param wav_path path ending in ''.wav'' (or a stem); ''.chunks'' is derived
		 * @return little-endian int32 sample counts, or null if missing / invalid
		 */
		public static int[]? load_chunks(string wav_path)
		{
			var chunks_path = wav_path.has_suffix(".wav")
				? wav_path.slice(0, wav_path.length - 4) + ".chunks"
				: wav_path + ".chunks";
			uint8[] data;
			try {
				GLib.FileUtils.get_data(chunks_path, out data);
			} catch (GLib.Error err) {
				return null;
			}
			if (data.length == 0 || data.length % (int) sizeof(int) != 0) {
				GLib.warning("debug chunks invalid: %s (%d bytes)", chunks_path, data.length);
				return null;
			}
			var n = data.length / (int) sizeof(int);
			var chunk_ns = new int[n];
			GLib.Memory.copy((void*) chunk_ns, data, data.length);
			return chunk_ns;
		}

		/**
		 * Load live float PCM from a sibling ''.f32'' (same samples as accept_waveform).
		 *
		 * @param wav_path path ending in ''.wav'' (or a stem)
		 * @return float mono 16 kHz, or null if missing / invalid
		 */
		public static float[]? load_pcm(string wav_path)
		{
			var f32_path = wav_path.has_suffix(".wav")
				? wav_path.slice(0, wav_path.length - 4) + ".f32"
				: wav_path + ".f32";
			uint8[] data;
			try {
				GLib.FileUtils.get_data(f32_path, out data);
			} catch (GLib.Error err) {
				return null;
			}
			if (data.length == 0 || data.length % (int) sizeof(float) != 0) {
				GLib.warning("debug f32 invalid: %s (%d bytes)", f32_path, data.length);
				return null;
			}
			var n = data.length / (int) sizeof(float);
			var samples = new float[n];
			GLib.Memory.copy((void*) samples, data, data.length);
			return samples;
		}

		/**
		 * Load live endpoint sample offsets from a sibling ''.endpoints'' file.
		 *
		 * @param wav_path path ending in ''.wav'' (or a stem)
		 * @return LE int32 positions after accept where live reset, or null
		 */
		public static int[]? load_endpoints(string wav_path)
		{
			var path = wav_path.has_suffix(".wav")
				? wav_path.slice(0, wav_path.length - 4) + ".endpoints"
				: wav_path + ".endpoints";
			uint8[] data;
			try {
				GLib.FileUtils.get_data(path, out data);
			} catch (GLib.Error err) {
				return null;
			}
			if (data.length == 0 || data.length % (int) sizeof(int) != 0) {
				GLib.warning("debug endpoints invalid: %s (%d bytes)", path, data.length);
				return null;
			}
			var n = data.length / (int) sizeof(int);
			var offs = new int[n];
			GLib.Memory.copy((void*) offs, data, data.length);
			return offs;
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
