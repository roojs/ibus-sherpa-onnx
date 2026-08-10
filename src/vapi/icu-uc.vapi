/*
 * Satisfies valac --pkg=icu-uc from dependency('icu-uc').
 * UTF-8 helpers live in Icu.vala (VAPI cannot hold Vala method bodies).
 */

[CCode (cheader_filename = "unicode/uloc.h")]
namespace Icu
{
	[CCode (cname = "U_FAILURE", cheader_filename = "unicode/utypes.h")]
	public static bool failure(int code);

	[CCode (cname = "uloc_getDisplayName", cheader_filename = "unicode/uloc.h")]
	public static int32 get_display_name_u(
		string locale_id,
		string? in_locale_id,
		[CCode (array_length = false)] uint16[] result,
		int32 max_result_size,
		ref int err);
}
