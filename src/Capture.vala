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
	 * Public ASR entry: every op hits the {@link Session} recording log, then ASR.
	 *
	 * Callers construct this only — never {@link Transcriber}. When {@link save},
	 * {@link Session.recording} is on for a listen and ''.chunks'' / ''.f32'' /
	 * ''.pending'' mirror {@link push} / {@link reset} / {@link flush}. When save
	 * is false, Session methods no-op and only ASR runs.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var live = new Capture(engine, config, true);
	 * live.load();
	 * live.start();
	 * live.stop(pending);
	 *
	 * var replay = new Capture(engine, config, false);
	 * replay.load();
	 * replay.reset();
	 * replay.push(chunk);
	 * replay.flush(pending);
	 * }}}
	 */
	public class Capture : Transcriber
	{
		/**
		 * When true, listen {@link start} opens a recording {@link Session}.
		 * When false, Session log calls no-op.
		 */
		public bool save { get; construct; }

		/** Debug op / PCM log for the current listen (or idle empty session). */
		private Session session = new Session();

		/**
		 * @param engine owning engine (IBus or stub)
		 * @param config settings (already loaded)
		 * @param save record debug sidecars when true
		 */
		public Capture(Engine engine, Config config, bool save)
		{
			GLib.Object(
				engine: engine,
				config: config,
				save: save
			);
			this.language = engine.language;
			this.on_mic_pcm = this.push;
			this.endpoint.connect((text) => {
				this.session.record_endpoint(text);
			});
		}

		/**
		 * Clear the recording log, then load the recognizer.
		 *
		 * @throws GLib.Error if models / pipeline cannot be created
		 */
		public void load() throws GLib.Error
		{
			this.session = new Session();
			this.load_model();
		}

		/**
		 * Log PCM, then queue for ASR (mic appsink, Replay, CLI).
		 *
		 * @param samples mono float PCM (ownership taken)
		 */
		public void push(owned float[] samples)
		{
			this.session.record_pcm(samples);
			this.queue_pcm((owned) samples);
		}

		/**
		 * Log reset, then queue stream reset.
		 */
		public void reset()
		{
			this.session.record_reset();
			this.queue_reset();
		}

		/**
		 * Log flush + pending, then queue ASR flush.
		 *
		 * @param pending stop partial to commit (may be empty)
		 */
		public void flush(string pending = "")
		{
			this.session.record_flush(pending);
			this.queue_flush(pending);
		}

		/**
		 * Open a recording session when {@link save}, log reset, start mic.
		 */
		public void start()
		{
			this.session = this.save
				? new Session() {
					started = new GLib.DateTime.now_local(),
					recording = true
				}
				: new Session();
			this.reset();
			this.start_mic();
		}

		/**
		 * Stop mic, log flush, persist sidecars when this listen was recorded.
		 *
		 * @param pending unfinished partial from the engine (may be empty)
		 */
		public void stop(string pending = "")
		{
			if (!this.listening) {
				return;
			}
			var recorded = this.session.recording;
			this.stop_mic();
			this.flush(pending);
			if (recorded) {
				var sess = this.session;
				this.session = new Session();
				sess.flush();
			}
		}
	}
}
