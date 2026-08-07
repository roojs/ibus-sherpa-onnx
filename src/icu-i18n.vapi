/*
 * Satisfies valac --pkg=icu-i18n from dependency('icu-i18n').
 * Public API is src/Icu.vala (UTF-8 display names).
 */

[CCode (cheader_filename = "unicode/uloc.h")]
namespace Icu
{
}
