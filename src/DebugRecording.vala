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
	 * Write one debug utterance under ''~/.cache/ibus-sherpa-onnx/debug/YYYY-MM-DD/''.
	 *
	 * Basename ''HHMMSS''. Audio is mono 16 kHz S16LE WAV; text is UTF-8.
	 */
	public class DebugRecording : GLib.Object
	{
		/**
		 * Persist committed text + PCM for one utterance (main loop / Idle).
		 *
		 * @param text committed transcript (non-empty)
		 * @param samples float mono PCM at 16 kHz (same as accept_waveform)
		 */
		public static void save(string text, float[] samples)
		{
			if (text == "" || samples.length == 0) {
				return;
			}

			var now = new GLib.DateTime.now_local();
			var day = GLib.Path.build_filename(GLib.Environment.get_user_cache_dir(), 
				"ibus-sherpa-onnx", "debug",now.format("%Y-%m-%d"));

			GLib.DirUtils.create_with_parents(day, 0755);

			var stem = GLib.Path.build_filename(day, now.format("%H%M%S"));
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
			}
		}

		/**
		 * Stream a mono PCM WAV (16-bit little-endian) from float samples in [-1, 1].
		 *
		 * @param path destination ''.wav''
		 * @param samples float mono PCM
		 * @param sample_rate e.g. 16000
		 */
		private static void write_wav_s16le(string path, float[] samples, int sample_rate)
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
