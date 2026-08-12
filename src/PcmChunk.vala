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
	 * }}}
	 */
	public class PcmChunk
	{
		public float[] samples;
		public bool reset;
		public bool flush;
		/** End of a mic listen: write debug session if armed, then reset. */
		public bool session_end;

		public PcmChunk(owned float[] samples)
		{
			this.samples = (owned) samples;
			this.reset = false;
			this.flush = false;
			this.session_end = false;
		}

		public PcmChunk.for_reset()
		{
			this.samples = {};
			this.reset = true;
			this.flush = false;
			this.session_end = false;
		}

		public PcmChunk.for_flush()
		{
			this.samples = {};
			this.reset = false;
			this.flush = true;
			this.session_end = false;
		}

		public PcmChunk.for_session_end()
		{
			this.samples = {};
			this.reset = false;
			this.flush = false;
			this.session_end = true;
		}
	}
}
