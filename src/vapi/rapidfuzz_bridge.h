/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Tiny C ABI over rapidfuzz::fuzz for Vala.
 */

#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Simple ratio (0–100). Returns 0 when below ''score_cutoff''.
 */
double rapidfuzz_ratio(const char *s1, const char *s2, double score_cutoff);

/**
 * Best ''fuzz::ratio'' of ''query'' vs ''choices''.
 *
 * Returns winning index, or -1 if none ≥ ''score_cutoff''.
 * On success writes the score (0–100) to ''out_score'' when non-NULL.
 */
int rapidfuzz_best_ratio(const char *query,
                         char **choices,
                         size_t n_choices,
                         double score_cutoff,
                         double *out_score);

#ifdef __cplusplus
}
#endif
