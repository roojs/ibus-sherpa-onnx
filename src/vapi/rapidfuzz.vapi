/*
 * Hand-written binding for src/vapi/rapidfuzz_bridge.{h,cpp}
 * (rapidfuzz-cpp is header-only C++; no upstream Vala VAPI).
 */

[CCode (cheader_filename = "rapidfuzz_bridge.h", lower_case_cprefix = "rapidfuzz_")]
namespace RapidFuzz
{
	/**
	 * Simple ratio (0–100). Returns 0 when below ''score_cutoff''.
	 */
	public static double ratio(string s1, string s2, double score_cutoff = 0.0);

	/**
	 * Best ratio of ''query'' vs ''choices''.
	 *
	 * Returns winning index, or -1 if none ≥ ''score_cutoff''.
	 */
	public static int best_ratio(
		string query,
		[CCode (array_length_pos = 2.1, array_null_terminated = false)] string[] choices,
		double score_cutoff,
		out double score);
}
