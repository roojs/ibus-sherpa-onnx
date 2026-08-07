/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * UTF-8 wrappers over ICU uloc (thin pkg stub: icu-i18n.vapi).
 */

namespace Icu
{
	[CCode (cname = "U_FAILURE", cheader_filename = "unicode/utypes.h")]
	private static extern bool failure(int code);

	[CCode (cname = "uloc_getDisplayName", cheader_filename = "unicode/uloc.h")]
	private static extern int32 get_display_name_u(
		string locale_id,
		string? in_locale_id,
		[CCode (array_length = false)] uint16[] result,
		int32 max_result_size,
		ref int err);

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
