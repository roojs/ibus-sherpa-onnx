/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Tiny C ABI over rapidfuzz::fuzz for Vala.
 */

#include "rapidfuzz_bridge.h"

#include <rapidfuzz/fuzz.hpp>
#include <string>

extern "C" double rapidfuzz_ratio(const char *s1, const char *s2, double score_cutoff)
{
	if (s1 == nullptr || s2 == nullptr) {
		return 0.0;
	}
	return rapidfuzz::fuzz::ratio(std::string(s1), std::string(s2), score_cutoff);
}

extern "C" int rapidfuzz_best_ratio(const char *query,
                                    char **choices,
                                    size_t n_choices,
                                    double score_cutoff,
                                    double *out_score)
{
	if (query == nullptr || choices == nullptr || n_choices == 0) {
		return -1;
	}

	const std::string q(query);
	rapidfuzz::fuzz::CachedRatio<char> scorer(q);

	double best = 0.0;
	int best_i = -1;
	for (size_t i = 0; i < n_choices; i++) {
		if (choices[i] == nullptr) {
			continue;
		}
		/* Raise the cutoff to the best so far so weak candidates bail early. */
		const double cutoff = best_i >= 0 ? best : score_cutoff;
		const double score = scorer.similarity(std::string(choices[i]), cutoff);
		if (score >= score_cutoff && score >= best) {
			best = score;
			best_i = static_cast<int>(i);
		}
	}

	if (out_score != nullptr) {
		*out_score = best_i >= 0 ? best : 0.0;
	}
	return best_i;
}
