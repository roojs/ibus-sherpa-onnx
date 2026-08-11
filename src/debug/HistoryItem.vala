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
	 * One scanned recording under ''~/.cache/…/debug/YYYY-MM-DD/''.
	 *
	 * Owns read/write of the stem files (''.txt'', ''.wav'', ''.out.txt'', ratings).
	 *
	 * == Example ==
	 *
	 * {{{
	 * var item = new HistoryItem("2026-08-11", day_path, "130545");
	 * original_buf.set_text(item.text(), -1);
	 * item.write_output(…);
	 * }}}
	 */
	public class HistoryItem : GLib.Object
	{
		/** Path stem without extension (…/YYYY-MM-DD/HHMMSS). */
		public string stem { get; set; default = ""; }

		/** Weekday name (e.g. Wednesday). */
		public string weekday { get; set; default = ""; }

		/** 12-hour clock (e.g. 1:05 PM). */
		public string time { get; set; default = ""; }

		/** First line of the original ''.txt''. */
		public string preview { get; set; default = ""; }

		/**
		 * @param day YYYY-MM-DD
		 * @param day_path Absolute day directory
		 * @param stamp HHMMSS basename
		 */
		public HistoryItem(string day, string day_path, string stamp)
		{
			GLib.Object();
			this.stem = GLib.Path.build_filename(day_path, stamp);
			var when = this.parse_when(day, stamp);
			this.weekday = when != null ? when.format("%A") : day;
			this.time = when != null ? when.format("%l:%M %p").strip() : stamp;
			this.preview = this.text().split("\n")[0].strip();
		}

		/** ''file://'' URI for the ''.wav'' (playbin). */
		public string wav_uri()
		{
			return GLib.Filename.to_uri(this.stem + ".wav");
		}

		/** Float mono PCM from the ''.wav'' (S16LE → [-1, 1]). */
		public float[] samples()
		{
			var input = new GLib.DataInputStream(
				GLib.File.new_for_path(this.stem + ".wav").read()
			) {
				byte_order = GLib.DataStreamByteOrder.LITTLE_ENDIAN
			};
			input.skip(40);
			var nbytes = input.read_uint32();
			var n = (int) (nbytes / 2);
			var samples = new float[n];
			for (var i = 0; i < n; i++) {
				samples[i] = input.read_int16() / 32768.0f;
			}
			return samples;
		}

		/** Original committed text (''.txt''). */
		public string text()
		{
			string body;
			GLib.FileUtils.get_contents(this.stem + ".txt", out body);
			return body;
		}

		/** Last saved replay output (''.out.txt''). */
		public string output()
		{
			string body;
			GLib.FileUtils.get_contents(this.stem + ".out.txt", out body);
			return body;
		}

		/** Persist replay output. */
		public void write_output(string text)
		{
			GLib.FileUtils.set_contents(this.stem + ".out.txt", text);
		}

		/** Original 1–5 rating (''.rating''). */
		public int rating()
		{
			string body;
			GLib.FileUtils.get_contents(this.stem + ".rating", out body);
			return int.parse(body.strip());
		}

		/** Persist original rating. */
		public void write_rating(int n)
		{
			GLib.FileUtils.set_contents(this.stem + ".rating", "%d".printf(n));
		}

		/** Persist output rating. */
		public void write_output_rating(int n)
		{
			GLib.FileUtils.set_contents(this.stem + ".out.rating", "%d".printf(n));
		}

		/** Drop ''.out.rating'' before a fresh Replay. */
		public void clear_output_rating()
		{
			GLib.FileUtils.unlink(this.stem + ".out.rating");
		}

		/**
		 * Parse day + stamp into a local {@link GLib.DateTime}.
		 *
		 * @param day YYYY-MM-DD
		 * @param stamp HHMMSS
		 * @return datetime, or null if stamp is too short
		 */
		private GLib.DateTime? parse_when(string day, string stamp)
		{
			if (stamp.length < 6) {
				return null;
			}
			return new GLib.DateTime.local(
				int.parse(day.substring(0, 4)), int.parse(day.substring(5, 2)),
				int.parse(day.substring(8, 2)), int.parse(stamp.substring(0, 2)),
				int.parse(stamp.substring(2, 2)), int.parse(stamp.substring(4, 2)));
		}
	}
}
