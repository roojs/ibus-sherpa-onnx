/*
 * Satisfies valac --pkg=icu-uc from dependency('icu-uc').
 * Public API is src/Icu.vala (UTF-8 display names).
 */

[CCode (cheader_filename = "unicode/uloc.h")]
namespace Icu
{
}
