/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * UTF-8 wrappers over ICU uloc (C decls in icu-uc.vapi).
 */

namespace Icu
{
	/**
	 * Locale display name as UTF-8 (''locale_id'' shown in ''in_locale_id'').
	 *
	 * Returns "" on failure. Pass the same id for both args for the endonym.
	 */
	public static string display_name(string locale_id, string? in_locale_id)
	{
		var buf = new uint16[256];
		int status = 0; /* U_ZERO_ERROR */
		var n = get_display_name_u(locale_id, in_locale_id, buf, buf.length, ref status);
		if (failure(status) || n <= 0) {
			return "";
		}
		try {
			return ((string16) buf).to_utf8(n);
		} catch (GLib.ConvertError err) {
			return "";
		}
	}
}
