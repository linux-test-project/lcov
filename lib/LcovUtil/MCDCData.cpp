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

#include "MCDCData.hpp"
#include "BranchData.hpp"  // For BranchDataCallbacks::report_error
#include <algorithm>
#include <stdexcept>

#ifdef LCOV_XS_INLINE
#define LCOV_INLINE inline
#else
#define LCOV_INLINE
#endif

// Must match the id lcovutil.pm assigns to "mismatch" in its @lcovErrs array.
// Makefile.PL injects the authoritative value via -DLCOV_ERROR_MISMATCH=<id>.
// Refuse to guess a default: a missing define means the build bypassed
// Makefile.PL and would use a stale id, so fail the build instead.
#ifndef LCOV_ERROR_MISMATCH
#error "LCOV_ERROR_MISMATCH not defined -- build via Makefile.PL so error ids are derived from lcovutil.pm"
#endif
#ifndef LCOV_ERROR_INCONSISTENT
#error "LCOV_ERROR_INCONSISTENT not defined -- build via Makefile.PL so error ids are derived from lcovutil.pm"
#endif

// ============================================================================
// MCDC_Expression
// ============================================================================

LCOV_INLINE MCDC_Expression::MCDC_Expression()
    : group_size_(0), idx_(0), expr_()
{
    excluded_[0] = excluded_[1] = false;
    count_[0]    = count_[1]    = 0;
}

LCOV_INLINE MCDC_Expression::MCDC_Expression(int32_t group_size, int32_t idx, const std::string& expr)
    : group_size_(group_size), idx_(idx), expr_(expr)
{
    excluded_[0] = excluded_[1] = false;
    count_[0]    = count_[1]    = 0;
}

LCOV_INLINE MCDC_Expression::MCDC_Expression(const MCDC_Expression& o)
    : group_size_(o.group_size_), idx_(o.idx_), expr_(o.expr_)
{
    for (int s = 0; s < 2; ++s) {
        excluded_[s] = o.excluded_[s];
        count_[s]    = o.count_[s];
        diff_[s]     = o.diff_[s] ? std::make_unique<DiffData>(*o.diff_[s]) : nullptr;
    }
}

// Copy-assignment.  Declared (rather than deleted) so MCDC_Expression stays a
// regular value type, but nothing reaches it: the two places that assign to an
// existing vector slot both hand over an rvalue and so bind the defaulted MOVE
// assignment instead -- mcdcblock_read's 'vec[i] = mcdcexpr_read(r)' and
// MCDC_Block::merge's 'find_or_create_group(gs) = your_vec', which copy-
// CONSTRUCTS into a freshly created (capacity 0) vector.  Marked unreachable so
// that if some future caller copy-assigns an expression, lcov reports it rather
// than the line silently going from covered to not.
// LCOV_UNREACHABLE_START
LCOV_INLINE MCDC_Expression& MCDC_Expression::operator=(const MCDC_Expression& o)
{
    if (this != &o) {
        group_size_ = o.group_size_;
        idx_        = o.idx_;
        expr_       = o.expr_;
        for (int s = 0; s < 2; ++s) {
            excluded_[s] = o.excluded_[s];
            count_[s]    = o.count_[s];
            diff_[s]     = o.diff_[s] ? std::make_unique<DiffData>(*o.diff_[s]) : nullptr;
        }
    }
    return *this;
}
// LCOV_UNREACHABLE_STOP

LCOV_INLINE int32_t MCDC_Expression::groupSize() const { return group_size_; }
LCOV_INLINE int32_t MCDC_Expression::index() const { return idx_; }

LCOV_INLINE const std::string& MCDC_Expression::expression() const { return expr_; }

LCOV_INLINE bool MCDC_Expression::is_excluded(int sense) const { return excluded_[sense & 1]; }

LCOV_INLINE int64_t MCDC_Expression::count(int sense) const { return count_[sense & 1]; }

LCOV_INLINE int MCDC_Expression::set(int sense, int64_t count, bool excluded)
{
    int s = sense & 1;
    bool was_zero = (count_[s] == 0);
    bool was_excluded = excluded_[s];
    count_[s] = count;
    excluded_[s] = excluded;

    if ((was_zero && count != 0) || (!was_excluded && excluded))
        return 1;
    return 0;
}

LCOV_INLINE int MCDC_Expression::merge_sense(int sense, const MCDC_Expression& other)
{
    // Mirrors pure-Perl MCDC_Expression::set($sense, $other->count($sense),
    // $other_excluded): OR the excluded flag, accumulate counts, and copy
    // differential (tla/base/curr) data when 'other' is differential.
    int s = sense & 1;
    bool other_excluded = other.excluded_[s];
    bool new_excluded    = excluded_[s] || other_excluded;

    if (other.diff_[s]) {
        bool    curr_def  = other.hasCurr(s);
        int64_t new_count = curr_def ? other.curr(s) : count_[s];
        set(s, new_count, new_excluded);
        std::optional<int64_t> base_opt =
            other.hasBase(s) ? std::optional<int64_t>(other.base(s)) : std::nullopt;
        std::optional<int64_t> curr_opt =
            curr_def ? std::optional<int64_t>(other.curr(s)) : std::nullopt;
        set_differential_opt(s, other.tla(s), base_opt, curr_opt);
        return 1;
    }

    int64_t cnt = other.count_[s];
    if (cnt == 0 && !other_excluded)
        return 0;
    return set(s, count_[s] + cnt, new_excluded);
}

// ---- differential coverage support ------------------------------------------

LCOV_INLINE bool MCDC_Expression::isDifferential(int sense) const
{
    return diff_[sense & 1] != nullptr;
}

LCOV_INLINE const std::string& MCDC_Expression::tla(int sense) const
{
    static const std::string empty;
    int s = sense & 1;
    return diff_[s] ? diff_[s]->tla : empty;
}

LCOV_INLINE bool MCDC_Expression::hasBase(int sense) const
{
    int s = sense & 1;
    return diff_[s] && !diff_[s]->base_undef;
}

LCOV_INLINE bool MCDC_Expression::hasCurr(int sense) const
{
    int s = sense & 1;
    return diff_[s] && !diff_[s]->curr_undef;
}

LCOV_INLINE int64_t MCDC_Expression::base(int sense) const
{
    int s = sense & 1;
    return diff_[s] ? diff_[s]->base : 0;
}

LCOV_INLINE int64_t MCDC_Expression::curr(int sense) const
{
    int s = sense & 1;
    return diff_[s] ? diff_[s]->curr : 0;
}

LCOV_INLINE void MCDC_Expression::set_tla(int sense, std::string t)
{
    int s = sense & 1;
    if (!diff_[s])
        diff_[s] = std::make_unique<DiffData>();
    diff_[s]->tla = std::move(t);
}

LCOV_INLINE void MCDC_Expression::set_differential(int sense, std::string tla_val,
                                                    int64_t base, int64_t curr)
{
    int s = sense & 1;
    if (!diff_[s])
        diff_[s] = std::make_unique<DiffData>();
    diff_[s]->tla = std::move(tla_val);
    diff_[s]->base = base;
    diff_[s]->curr = curr;
    diff_[s]->base_undef = false;
    diff_[s]->curr_undef = false;
}

LCOV_INLINE void MCDC_Expression::set_differential_opt(int sense, std::string tla_val,
                                                        std::optional<int64_t> base,
                                                        std::optional<int64_t> curr)
{
    int s = sense & 1;
    if (!diff_[s])
        diff_[s] = std::make_unique<DiffData>();
    diff_[s]->tla = std::move(tla_val);
    if (base.has_value()) {
        diff_[s]->base = *base;
        diff_[s]->base_undef = false;
    } else {
        diff_[s]->base = 0;
        diff_[s]->base_undef = true;
    }
    if (curr.has_value()) {
        diff_[s]->curr = *curr;
        diff_[s]->curr_undef = false;
    } else {
        diff_[s]->curr = 0;
        diff_[s]->curr_undef = true;
    }
    /* diff_[s] is non-null now, so isDifferential(s) is true. */
}

// ============================================================================
// MCDC_Block
// ============================================================================

LCOV_INLINE MCDC_Block::MCDC_Block(int32_t line) : line_(line) {}

LCOV_INLINE int32_t MCDC_Block::line() const { return line_; }

// A block whose line key is a plain number - every block a C or C++ run
// produces - has no label at all, so there is nothing to hand back but a
// shared empty string.  Same pattern as BranchLocation::line_label().
LCOV_INLINE const std::string& MCDC_Block::line_label() const
{
    static const std::string empty;
    return line_label_ ? *line_label_ : empty;
}

// Unconditional:  see the note on BranchLocation::set_line_label -- every caller
// only reaches this for a real, non-empty label, so any other arm is dead code.
LCOV_INLINE void MCDC_Block::set_line_label(std::string label)
{
    line_label_ = std::make_unique<std::string>(std::move(label));
}

// Deep copy:  the label string and the group map are owned, so a copied block
// must get its own of each rather than sharing (or, for unique_ptr, refusing to
// compile).  MCDC_Data::append_mcdc and union_with both copy blocks by value.
LCOV_INLINE MCDC_Block::MCDC_Block(const MCDC_Block& o)
    : line_(o.line_), one_size_(o.one_size_), shape_(o.shape_),
      line_label_(o.line_label_ ? std::make_unique<std::string>(*o.line_label_)
                                : nullptr),
      one_group_(o.one_group_),
      many_(o.many_ ? std::make_unique<
                          std::unordered_map<int32_t,
                                             std::vector<MCDC_Expression>>>(
                          *o.many_)
                    : nullptr)
{
}

LCOV_INLINE std::size_t MCDC_Block::num_groups() const
{
    switch (shape_) {
        case Shape::EMPTY: return 0;
        case Shape::ONE:   return 1;
        default:           return many_->size();
    }
}

LCOV_INLINE std::vector<MCDC_Expression>* MCDC_Block::expressions(int32_t size)
{
    // const_cast rather than a second copy of the lookup:  the const overload
    // does exactly this search, and *this is non-const here so handing back a
    // mutable pointer to our own member is well defined.
    return const_cast<std::vector<MCDC_Expression>*>(
        static_cast<const MCDC_Block*>(this)->expressions(size));
}

LCOV_INLINE const std::vector<MCDC_Expression>*
MCDC_Block::expressions(int32_t size) const
{
    if (shape_ == Shape::ONE)
        return size == one_size_ ? &one_group_ : nullptr;
    if (shape_ == Shape::EMPTY)
        return nullptr;
    auto it = many_->find(size);
    return (it != many_->end()) ? &it->second : nullptr;
}

LCOV_INLINE std::vector<MCDC_Expression>&
MCDC_Block::find_or_create_group(int32_t size)
{
    if (shape_ == Shape::EMPTY) {
        shape_    = Shape::ONE;
        one_size_ = size;
        return one_group_;             // still empty from construction
    }
    if (shape_ == Shape::ONE) {
        if (size == one_size_)
            return one_group_;
        // Second distinct group size on one line:  promote.  Moving the vector
        // hands over its heap buffer, so any MCDC_Expression* the XS layer has
        // already handed to Perl still points at the same element - only the
        // vector object it lives in has moved.
        many_ = std::make_unique<
            std::unordered_map<int32_t, std::vector<MCDC_Expression>>>();
        (*many_)[one_size_] = std::move(one_group_);
        one_group_.clear();            // moved-from is valid but unspecified
        one_group_.shrink_to_fit();
        shape_ = Shape::MANY;
    }
    return (*many_)[size];
}

LCOV_INLINE MCDC_Expression* MCDC_Block::expr(int32_t group_size, int32_t idx)
{
    // There is no such thing as a legitimately missing expression:  the caller
    // (e.g. scripts/unreach.pm exclude_cond) names a group and an index that
    // its own annotation claims exist, so anything out of range is a bad
    // request and is thrown back rather than answered with a null the caller
    // would have to remember to check.  Matches pure-Perl MCDC_Block::expr.
    std::vector<MCDC_Expression>* found = expressions(group_size);
    if (!found)
        throw std::out_of_range("expr: unknown group size " +
                                std::to_string(group_size));
    auto& vec = *found;
    if (idx < 0 || static_cast<std::size_t>(idx) >= vec.size())
        throw std::out_of_range("expr: invalid expression index " +
                                std::to_string(idx) + " in group " +
                                std::to_string(group_size));
    return &vec[static_cast<std::size_t>(idx)];
}

LCOV_INLINE bool MCDC_Block::is_compatible(const MCDC_Block& you) const
{
    // Mirrors pure-Perl MCDC_Block::is_compatible, which compares the shared
    // groups by EXPRESSION TEXT -- not by group count or group size.
    //
    // A group size present in only one of the two blocks is not a conflict:
    // merge() copies such a group in wholesale, so the blocks still describe
    // the same decisions.  What makes two blocks incompatible is a shared
    // group whose expressions disagree, i.e. the same line/group describing a
    // different decision in each file -- the case the ERROR_INCONSISTENT_DATA
    // gate in MCDC_Data::union/intersect exists to reject.
    //
    // Comparing group counts instead would get both halves wrong: it would
    // reject compatible blocks that merely carry an extra group, and accept
    // blocks whose shared expressions differ outright -- merging MC/DC records
    // that pure Perl rejects.
    bool compatible = true;
    for_each_group([&](int32_t gs, const std::vector<MCDC_Expression>& mine) {
        if (!compatible)
            return;                    // already decided; nothing to undo
        const std::vector<MCDC_Expression>* yours = you.expressions(gs);
        if (!yours)
            return;
        // merge() walks the two lists index-wise, so unequal lengths leave my
        // trailing expressions with nothing to merge against.
        if (mine.size() != yours->size()) {
            compatible = false;
            return;
        }
        for (std::size_t i = 0; i < mine.size(); ++i)
            if (mine[i].expression() != (*yours)[i].expression()) {
                compatible = false;
                return;
            }
    });
    return compatible;
}

LCOV_INLINE std::pair<int64_t, int64_t> MCDC_Block::totals(bool count_excluded) const
{
    int64_t found = 0, hit = 0;
    for_each_group([&](int32_t gs, const std::vector<MCDC_Expression>& vec) {
        (void)gs;
        for (const auto& expr : vec) {
            for (int sense = 0; sense < 2; ++sense) {
                if (!count_excluded && expr.is_excluded(sense))
                    continue;
                int64_t cnt;
                if (expr.isDifferential(sense)) {
                    // differential number - report 'current'; skip if 'current'
                    // is undefined (matches pure-Perl MCDC_Block::totals).
                    if (!expr.hasCurr(sense))
                        continue;
                    cnt = expr.curr(sense);
                } else {
                    cnt = expr.count(sense);
                }
                ++found;
                if (cnt != 0)
                    ++hit;
            }
        }
    });
    return {found, hit};
}

LCOV_INLINE int MCDC_Block::merge(const MCDC_Block& you, const std::string& filename)
{
    // Mirrors pure-Perl MCDC_Block::merge: for each group of 'you', if we have
    // the same group size, merge expression-by-expression (reporting an
    // 'unreachable' mismatch when the excluded flags differ); otherwise copy
    // the whole group in (Storable::dclone equivalent -> plain value copy).
    int changed = 0;
    you.for_each_group([&](int32_t gs,
                           const std::vector<MCDC_Expression>& your_vec) {
        std::vector<MCDC_Expression>* found = expressions(gs);
        if (!found) {
            // Absent group:  create it and copy the whole thing in.  Creating it
            // first and assigning into it (rather than inserting a copy) keeps
            // find_or_create_group as the single place the shape changes.
            find_or_create_group(gs) = your_vec;
            changed = 1;
            return;
        }
        auto& my_vec = *found;
        std::size_t n = my_vec.size() < your_vec.size() ? my_vec.size()
                                                        : your_vec.size();
        for (std::size_t i = 0; i < n; ++i) {
            const MCDC_Expression& yours = your_vec[i];
            MCDC_Expression&       mine  = my_vec[i];
            for (int sense = 0; sense < 2; ++sense) {
                /* Check for excluded/unreachable mismatch (matches pure Perl).
                 * Element numbering is 1-based, matching the pure-Perl message. */
                if (mine.is_excluded(sense) != yours.is_excluded(sense)) {
                    /* Null arm precluded:  see BranchElement::merge -- the XS
                     * BOOT block installs report_error before any Perl caller
                     * can reach here. */
                    if (BranchDataCallbacks::report_error) {   // LCOV_EXCL_BR_LINE
                        std::string loc = filename + ":" + std::to_string(line_) + ":";
                        std::string sense_str = sense ? "true" : "false";
                        std::string msg = loc + "mismatched 'unreachable' tag for MC/DC element " +
                                         std::to_string(i + 1) + " of group " + std::to_string(gs) +
                                         " sense " + sense_str + ": '" +
                                         std::to_string(mine.is_excluded(sense)) + "' -> '" +
                                         std::to_string(yours.is_excluded(sense)) + "'.";
                        BranchDataCallbacks::report_error(LCOV_ERROR_MISMATCH, msg);
                    }
                }
                if (mine.merge_sense(sense, yours))
                    changed = 1;
            }
        }
    });
    return changed;
}

// ============================================================================
// MCDC_Data
// ============================================================================

LCOV_INLINE MCDC_Data::MCDC_Data() : found_(0), hit_(0) {}

LCOV_INLINE int64_t MCDC_Data::found() const { return found_; }
LCOV_INLINE int64_t MCDC_Data::hit() const { return hit_; }

LCOV_INLINE std::pair<int64_t, int64_t> MCDC_Data::get_found_and_hit() const
{
    return {found_, hit_};
}

LCOV_INLINE void MCDC_Data::adjust_counts(int64_t dFound, int64_t dHit)
{
    found_ += dFound;
    hit_   += dHit;
}

LCOV_INLINE MCDC_Block* MCDC_Data::value(int32_t line)
{
    auto it = data_.find(line);
    return (it != data_.end()) ? &it->second : nullptr;
}

LCOV_INLINE std::vector<int32_t> MCDC_Data::keylist() const
{
    std::vector<int32_t> keys;
    keys.reserve(data_.size());
    for (const auto& kv : data_) {
        keys.push_back(kv.first);
    }
    return keys;
}

LCOV_INLINE std::unordered_map<int32_t, MCDC_Block>& MCDC_Data::data() { return data_; }

LCOV_INLINE int MCDC_Data::append_mcdc(const MCDC_Block& block, const std::string& filename)
{
    // Update the cached found_/hit_ totals incrementally: only the single
    // affected line's block changes, so a full recalculate_counts() (which
    // rescans every block/expression/sense) would make an N-line append loop
    // O(N^2).  Add just this block's delta instead.
    int32_t line = block.line();
    auto it = data_.find(line);
    if (it == data_.end()) {
        auto [f, h] = block.totals(false);
        data_.emplace(line, block);
        found_ += f;
        hit_   += h;
        return 0;
    }
    auto [oldF, oldH] = it->second.totals(false);
    it->second.merge(block, filename);
    auto [newF, newH] = it->second.totals(false);
    found_ += newF - oldF;
    hit_   += newH - oldH;
    return 0;
}

LCOV_INLINE MCDC_Block* MCDC_Data::new_mcdc(int32_t line)
{
    auto [it, inserted] = data_.emplace(line, MCDC_Block(line));
    return &it->second;
}

LCOV_INLINE int MCDC_Data::remove(int32_t line, bool check)
{
    // Mirror pure-Perl MCDC_Data::remove: when the line is absent return 0
    // ("nothing removed"); when present subtract its found/hit totals, erase
    // it, and return 1 ("removed").  The sole caller -- the geninfo
    // "exclude MCDC" gate in lcovutil.pm -- logs the removal on a true return,
    // so the sense of the result matters.
    auto it = data_.find(line);
    if (it == data_.end()) {
        // With 'check' an absent line is simply "nothing removed".  Without it
        // the caller asserts the line is present, and pure Perl dies
        // ("<line> not found") rather than reporting a removal that never
        // happened -- so throw and let the XS boundary raise the same die.
        if (check)
            return 0;
        throw std::runtime_error(std::to_string(line) + " not found");
    }
    auto [f, h] = it->second.totals(false);
    found_ -= f;
    hit_   -= h;
    data_.erase(it);
    return 1;
}

// Mirrors the guard pure-Perl MCDC_Data::union/intersect wrap around merge():
// two blocks describing the same line but different decisions must not be
// merged - the counts would be attributed to the wrong expressions.  Report it
// through the same ignorable_error channel (message text matches pure Perl so
// tests and user-visible output agree) and leave my block untouched.
static void report_incompatible()
{
    /* Null arm precluded:  see BranchElement::merge -- the XS BOOT block installs
     * report_error before any Perl caller can reach here. */
    if (BranchDataCallbacks::report_error)   // LCOV_EXCL_BR_LINE
        BranchDataCallbacks::report_error(
            LCOV_ERROR_INCONSISTENT, "cannot merge inconsistent MC/DC record");
}

LCOV_INLINE int MCDC_Data::union_with(const MCDC_Data& other, const std::string& filename)
{
    // incremental vs. rescan - see BranchData::union_with for the cost model
    const bool rescan = 2 * other.data_.size() > data_.size();
    int changed       = 0;
    for (const auto& [line, block] : other.data_) {
        auto it = data_.find(line);
        if (it == data_.end()) {
            data_.emplace(line, block);
            // the copy is identical to yours, so its contribution to our
            //   cached found/hit is just your totals
            if (!rescan) {
                auto [f, h] = block.totals(false);
                adjust_counts(f, h);
            }
            changed = 1;
        } else if (it->second.is_compatible(block)) {
            // 'changed' is a boolean 'did anything change', not a count: see
            // the matching comment in pure-Perl MCDC_Data::union.
            if (rescan) {
                if (it->second.merge(block, filename))
                    changed = 1;
            } else {
                auto [oldFound, oldHit] = it->second.totals(false);
                const int changedHere   = it->second.merge(block, filename);
                auto [newFound, newHit] = it->second.totals(false);
                adjust_counts(newFound - oldFound, newHit - oldHit);
                if (changedHere)
                    changed = 1;
            }
        } else {
            report_incompatible();
        }
    }
    if (rescan)
        recalculate_counts();
    return changed;
}

LCOV_INLINE int MCDC_Data::intersect_with(const MCDC_Data& other, const std::string& filename)
{
    int changed = 0;
    std::vector<int32_t> to_remove;

    for (auto& [line, block] : data_) {
        auto it = other.data_.find(line);
        if (it == other.data_.end()) {
            to_remove.push_back(line);
            changed = 1;
        } else if (block.is_compatible(it->second)) {
            // boolean, not a count - see union_with
            if (block.merge(it->second, filename))
                changed = 1;
        } else {
            report_incompatible();
        }
    }

    for (int32_t line : to_remove) {
        data_.erase(line);
    }
    recalculate_counts();
    return changed;
}

LCOV_INLINE int MCDC_Data::difference_with(const MCDC_Data& other, const std::string& filename)
{
    (void)filename;
    int changed = 0;
    for (const auto& [line, block] : other.data_) {
        (void)block;
        if (data_.erase(line) > 0) {
            changed = 1;   // boolean, not a count - see union_with
        }
    }
    recalculate_counts();
    return changed;
}

LCOV_INLINE int MCDC_Data::difference_with(const MCDC_Data& other)
{
    return difference_with(other, "");
}

LCOV_INLINE void MCDC_Data::recalculate_counts()
{
    found_ = 0;
    hit_   = 0;
    for (const auto& [line, block] : data_) {
        (void)line;
        auto [f, h] = block.totals(false);
        found_ += f;
        hit_   += h;
    }
}
