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
	 * {@link Transcriber} that optionally records the PCM ingress for debug Replay.
	 *
	 * Base class is ASR only. This subclass owns debug {@link Session} save and
	 * file-feed control ({@link begin_file} / {@link end_file} / {@link cancel_file}).
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
	 * replay.begin_file(new Session.load(stem + ".wav"));
	 * replay.push(chunk);
	 * replay.end_file();
	 * }}}
	 */
	public class Capture : Transcriber
	{
		/**
		 * When true, record sidecars on the way through. When false, relay only
		 * (Replay / CLI / debug-recordings off).
		 */
		public bool save { get; construct; }

		/**
		 * Listen-session buffers when {@link save} is true (pcm, chunks,
		 * endpoints, text, pending). Flushed on {@link stop}.
		 */
		private Session session = new Session();

		/** True while Replay / CLI file feed is active (no mic). */
		private bool file_feed = false;

		/** Stop partial for {@link end_file} flush. */
		private string file_pending = "";

		/** Emit {@link Transcriber.file_finished} after end_file flush. */
		private bool emit_file_finished = false;

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
			this.endpoint.connect((text) => {
				if (!this.save || text.strip() == "") {
					return;
				}
				this.session.endpoint_off.append_val(this.session.accepted);
				if (this.session.text != "") {
					this.session.text += "\n";
				}
				this.session.text += text;
			});
		}

		/**
		 * Whether file feed is active (Replay / CLI).
		 *
		 * @return true after {@link begin_file} until {@link end_file} / cancel
		 */
		public override bool file_active {
			get {
				return this.file_feed;
			}
		}

		/**
		 * When {@link save} and listening, append pcm / chunk size / accepted,
		 * then queue for ASR. Otherwise pass-through.
		 *
		 * @param samples mono float PCM (ownership taken)
		 */
		public override void push(owned float[] samples)
		{
			if (this.save && this.listening && samples.length > 0) {
				var n = samples.length;
				this.session.pcm.append_vals(samples, n);
				this.session.chunk_n.append_val(n);
				this.session.accepted += n;
			}
			base.push((owned) samples);
		}

		/**
		 * Start mic. When {@link save}, opens a new recording {@link Session}
		 * before base so the first {@link push} is included.
		 */
		public override void start()
		{
			if (this.save) {
				this.session = new Session() {
					started = new GLib.DateTime.now_local(),
					recording = true
				};
			}
			base.start();
		}

		/**
		 * Stop mic. When {@link save}, merges pending into the session and
		 * flushes sidecars, then base stop.
		 *
		 * @param pending unfinished partial from the engine (may be empty)
		 */
		public override void stop(string pending = "")
		{
			if (!this.listening) {
				return;
			}
			if (this.save) {
				this.session.pending = pending.strip();
				var sess = this.session;
				this.session = new Session();
				sess.flush();
			}
			base.stop(pending);
		}

		/**
		 * Enter file-feed mode. Stores stop pending; PCM via {@link push}.
		 *
		 * @param from_disk loaded session (pending used; pcm/chunks for Feed)
		 */
		public override void begin_file(Session from_disk)
		{
			this.cancel_file();
			this.file_pending = from_disk.pending;
			this.file_feed = true;
			this.emit_file_finished = true;
			this.feed_pos_s = 0.0;
			this.last_text = "";
			this.audio_queue.push(new PcmChunk.for_reset());
		}

		/**
		 * Finish file feed: queue flush with pending, then {@link file_finished}.
		 */
		public override void end_file()
		{
			if (!this.file_feed) {
				return;
			}
			var pending = this.file_pending;
			var finished = this.emit_file_finished;
			this.file_pending = "";
			this.emit_file_finished = false;
			this.file_feed = false;
			this.audio_queue.push(new PcmChunk.for_flush(pending, finished));
		}

		/**
		 * Cancel an in-progress file feed without {@link file_finished}.
		 */
		public override void cancel_file()
		{
			this.emit_file_finished = false;
			this.file_pending = "";
			if (!this.file_feed) {
				return;
			}
			this.file_feed = false;
			this.audio_queue.push(new PcmChunk.for_reset());
		}
	}
}
