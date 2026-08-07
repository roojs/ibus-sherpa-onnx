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
	 * Searchable {@link Adw.ComboRow} of ASR languages (ICU labels via thin icu-i18n.vapi).
	 *
	 * Stores ''general/language='' (catalog code). Search matches display names.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var lang = new RowComboLanguage(config, models);
	 * group.add(lang.row);
	 * lang.fill();
	 * }}}
	 */
	public class RowComboLanguage : Row
	{
		public Adw.ComboRow combo;
		private Gtk.StringList labels;
		private Gee.ArrayList<string> codes;
		private Models models;

		/**
		 * Emitted after the user picks a language (not during {@link fill}).
		 */
		public signal void changed(string code);

		/**
		 * @param config Settings object
		 * @param models Catalog (''languages'' KeyFile)
		 */
		public RowComboLanguage(Config config, Models models)
		{
			base(config, "language", "Language", "Spoken language for dictation");
			this.models = models;
			this.codes = new Gee.ArrayList<string>();
			this.labels = new Gtk.StringList(null);
			var ui = Intl.get_language_names()[0].replace("-", "_");
			foreach (var code in models.languages.get_groups()) {
				var tag = code;
				if (models.languages.has_key(code, "display")) {
					tag = models.languages.get_string(code, "display");
				}
				var loc = tag.replace("-", "_");
				var native = Icu.display_name(loc, loc);
				var gloss = Icu.display_name(loc, ui);
				var label = native;
				if (gloss != native) {
					label = "%s — %s".printf(native, gloss);
				}
				this.codes.add(code);
				this.labels.append(label);
			}
			this.combo = new Adw.ComboRow() {
				title = "Language",
				subtitle = "Spoken language for dictation",
				model = this.labels,
				enable_search = true
			};
			this.row = this.combo;
			this.combo.notify["selected"].connect(() => {
				if (this.loading || this.combo.selected == Gtk.INVALID_LIST_POSITION) {
					return;
				}
				var code = this.codes.get((int) this.combo.selected);
				this.config.key_file.set_string("general", this.key, code);
				this.config.save();
				this.changed(code);
			});
		}

		public override void fill()
		{
			this.loading = true;
			var selected = "";
			try {
				selected = this.config.key_file.get_string("general", this.key);
			} catch (GLib.Error err) {
			}
			if (selected == "") {
				selected = this.default_code();
				this.config.key_file.set_string("general", this.key, selected);
			}
			var idx = this.codes.index_of(selected);
			if (idx < 0) {
				idx = 0;
				this.config.key_file.set_string("general", this.key, this.codes.get(0));
			}
			this.combo.selected = idx;
			this.loading = false;
		}

		/**
		 * First desktop UI language that exists in the catalog, else ''en''.
		 */
		private string default_code()
		{
			foreach (var name in Intl.get_language_names()) {
				var base_tag = name.split(".")[0].replace("_", "-");
				var idx = this.codes.index_of(base_tag);
				if (idx >= 0) {
					return this.codes.get(idx);
				}
				var lang = base_tag.split("-")[0];
				var match = this.codes.first_match((code) => {
					return code == lang || code.has_prefix(lang + "-");
				});
				if (match != null) {
					return match;
				}
			}
			return "en";
		}
	}
}
