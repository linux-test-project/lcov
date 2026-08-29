/*
 *   Copyright (c) MediaTek USA Inc., 2026
 *
 *   This program is free software;  you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or (at
 *   your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful, but
 *   WITHOUT ANY WARRANTY;  without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *   General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program;  if not, see
 *   <http://www.gnu.org/licenses/>.
 */

#pragma once

#include <cstdint>

// ---------------------------------------------------------------------------
// Arithmetic on '.info' count fields, shared by every count in this layer:
// line counts (CountData), branch taken counts (BranchElement), MC/DC
// sensitization counts (MCDC_Expression) and function call counts.
// ---------------------------------------------------------------------------

namespace lcov
{

/* The widest count a '.info' count field can carry.
 *
 * Every reader in this layer clamps to this value rather than overflowing, and
 * pure Perl clamps to the same value (lcovutil::MAX_COUNT), so which backend
 * produced a tracefile is not visible in the tracefile.  See the comment on
 * lcovutil::normalize_count for the whole of the shared contract. */
inline constexpr int64_t MAX_COUNT = INT64_MAX;

/* Saturating add, for merging two counts.
 *
 * Signed overflow is undefined behaviour rather than wraparound, so it cannot
 * be detected after the fact: the addition is tested against the headroom that
 * is left instead.
 *
 * Saturating rather than reporting an error is deliberate.  MAX_COUNT already
 * means "at least this much, and more than we can represent" wherever it is
 * stored, having been put there by the clamp on read; an aggregate which
 * reaches it carries exactly the same meaning, and the alternative -- failing a
 * merge of two tracefiles which were each individually acceptable -- is worse.
 *
 * Negative inputs cannot occur, because every reader rejects a negative count
 * before storing it, but they are folded to 0 rather than trusted.  A count
 * which is too small is still a count; a negative one is written to the '.info'
 * file as a negative number, which the reader then rejects, and for a branch it
 * can collide with the '-' (not evaluated) sentinel. */
inline int64_t add_sat(int64_t a, int64_t b) noexcept
{
    if (a < 0)
        a = 0;
    if (b < 0)
        b = 0;
    return (a > MAX_COUNT - b) ? MAX_COUNT : a + b;
}

}    // namespace lcov
