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
	 * Queue item for the ASR worker: PCM, or reset / flush / session_end.
	 *
	 * == Example ==
	 *
	 * {{{
	 * audio_queue.push(new PcmChunk((owned) samples));
	 * audio_queue.push(new PcmChunk.for_reset());
	 * audio_queue.push(new PcmChunk.for_flush(pending, true));
	 * }}}
	 */
	public class PcmChunk
	{
		public float[] samples;
		public bool reset;
		public bool flush;
		/** End of a mic listen: reset the stream. */
		public bool session_end;
		/** Stop partial for {@link flush} (from {@link Transcriber.flush}). */
		public string flush_pending;
		/** Emit {@link Transcriber.flushed} after this flush. */
		public bool flush_finished;

		public PcmChunk(owned float[] samples)
		{
			this.samples = (owned) samples;
			this.reset = false;
			this.flush = false;
			this.session_end = false;
			this.flush_pending = "";
			this.flush_finished = false;
		}

		public PcmChunk.for_reset()
		{
			this.samples = {};
			this.reset = true;
			this.flush = false;
			this.session_end = false;
			this.flush_pending = "";
			this.flush_finished = false;
		}

		/**
		 * @param pending stop partial to commit (may be empty)
		 * @param finished emit {@link Transcriber.flushed} after Idle
		 */
		public PcmChunk.for_flush(string pending = "", bool finished = true)
		{
			this.samples = {};
			this.reset = false;
			this.flush = true;
			this.session_end = false;
			this.flush_pending = pending;
			this.flush_finished = finished;
		}

		public PcmChunk.for_session_end()
		{
			this.samples = {};
			this.reset = false;
			this.flush = false;
			this.session_end = true;
			this.flush_pending = "";
			this.flush_finished = false;
		}
	}
}
