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
#include <string>
#include <unordered_map>
#include <vector>
#include <utility>
#include <optional>
#include <memory>

// ============================================================================
// MCDC_Expression
//
// Value type representing one expression slot within an MC/DC group.
// Each expression tracks two senses (false=0, true=1): a hit count and an
// excluded flag per sense.
// ============================================================================

class MCDC_Expression {
public:
    MCDC_Expression();
    MCDC_Expression(int32_t group_size, int32_t idx, const std::string& expr);

    // ---- accessors ----------------------------------------------------------

    int32_t groupSize() const;
    int32_t index()     const;

    const std::string& expression() const;

    bool is_excluded(int sense) const;

    int64_t count(int sense) const;

    // Set count and excluded flag for one sense.
    // Returns 1 if a coverage-state change occurred (0->nonzero count, or
    // excluded flag transitioned false->true); 0 otherwise.
    int set(int sense, int64_t count, bool excluded);

    // Merge one sense of 'other' into this expression, mirroring pure-Perl
    // MCDC_Expression::set($sense, $other->count($sense), $other_excluded):
    // the excluded flag is OR-ed in, counts accumulate, and differential
    // data (tla/base/curr) is copied when 'other' is differential on 'sense'.
    // Returns 1 if a coverage-state change occurred, 0 otherwise.
    int merge_sense(int sense, const MCDC_Expression& other);

    // ---- differential coverage support (parallel to BranchElement) -----------

    bool isDifferential(int sense) const;
    const std::string& tla(int sense) const;

    bool hasBase(int sense) const;
    bool hasCurr(int sense) const;
    int64_t base(int sense) const;
    int64_t curr(int sense) const;

    void set_tla(int sense, std::string t);
    void set_differential(int sense, std::string tla_val, int64_t base, int64_t curr);
    void set_differential_opt(int sense, std::string tla_val,
                              std::optional<int64_t> base, std::optional<int64_t> curr);

    // Value semantics: per-sense differential data lives behind owning pointers
    // that are deep-copied, so a copied expression owns its own DiffData.
    MCDC_Expression(const MCDC_Expression& o);
    MCDC_Expression& operator=(const MCDC_Expression& o);
    MCDC_Expression(MCDC_Expression&&) noexcept = default;
    MCDC_Expression& operator=(MCDC_Expression&&) noexcept = default;
    ~MCDC_Expression() = default;

private:
    struct DiffData {
        std::string tla;
        int64_t base = 0;
        int64_t curr = 0;
        bool base_undef = true;
        bool curr_undef = true;
    };

    int32_t     group_size_;
    int32_t     idx_;
    std::string expr_;
    bool        excluded_[2];
    int64_t     count_[2];
    // Non-null only for a differential sense; absent for the common
    // non-differential expression (was two always-present std::optional<DiffData>
    // plus a redundant is_differential_ flag).
    std::unique_ptr<DiffData> diff_[2];
};

// ============================================================================
// MCDC_Block
//
// Value type representing all MC/DC expression data for a single source line.
// Expressions are partitioned into groups keyed by group_size; within each
// group the vector is indexed by the expression's idx field.
// ============================================================================

class MCDC_Block {
public:
    explicit MCDC_Block(int32_t line);

    // ---- accessors ----------------------------------------------------------

    int32_t line() const;

    // Original Perl-supplied line value when it is NOT a plain integer.
    // Pure-Perl MCDC_Block stores $line verbatim, so a differential
    // "deleted line" key such as "<<<123" must round-trip through line().
    // Empty string means "use the numeric line_"; set only on the rare
    // non-numeric path.
    const std::string& line_label() const;
    void set_line_label(std::string label);

    // Number of distinct group sizes present.
    std::size_t num_groups() const;

    // Pointer to the expression vector for the given group size, or nullptr.
    std::vector<MCDC_Expression>* expressions(int32_t size);
    const std::vector<MCDC_Expression>* expressions(int32_t size) const;

    // The expression vector for 'size', creating an empty one if this block has
    // no such group yet.  This is the ONE mutator that can add a group, so it is
    // the only place the EMPTY -> ONE -> MANY promotion happens.  Note that an
    // empty group is observable state and not the same as no group at all:
    // pure Perl's 'push @{$groups->{$size}}, ...' autovivifies, so a lookup of
    // an unknown size leaves a group behind, and num_groups() must agree.
    std::vector<MCDC_Expression>& find_or_create_group(int32_t size);

    // Visit every (group size, expression vector) pair, in unspecified order.
    // A visitor rather than a map reference:  in the ONE shape there is no map
    // to hand out, and building one per call would undo the whole point.  The
    // order is unspecified and no caller may rely on it:  in the MANY shape it is
    // a hash table's arbitrary order, and pure Perl iterates a hash;  the two
    // callers that need
    // a stable order (serialization, and the 'groups' XSUB's Perl hash) are
    // order-insensitive by construction.
    template <class F> void for_each_group(F&& f)
    {
        if (shape_ == Shape::MANY) {
            for (auto& kv : *many_)
                f(kv.first, kv.second);
        } else if (shape_ == Shape::ONE) {
            f(one_size_, one_group_);
        }
    }
    template <class F> void for_each_group(F&& f) const
    {
        if (shape_ == Shape::MANY) {
            for (const auto& kv : *many_)
                f(kv.first, kv.second);
        } else if (shape_ == Shape::ONE) {
            f(one_size_, one_group_);
        }
    }

    // Pointer to the expression at (group_size, idx).  Never null:  an unknown
    // group size or an out-of-range index is a caller bug, so it throws
    // std::out_of_range rather than returning something to be checked.
    MCDC_Expression* expr(int32_t group_size, int32_t idx);

    // True iff this block and 'you' have the same group structure (same sizes
    // and same per-group vector lengths), making them safe to merge.
    bool is_compatible(const MCDC_Block& you) const;

    // Aggregate (found, hit) over all expression/sense pairs.
    // When count_excluded is false, pairs flagged as excluded are skipped.
    std::pair<int64_t, int64_t> totals(bool count_excluded = false) const;

    // Merge 'you' into this block.
    // Returns 1 if any change occurred, 0 otherwise.
    int merge(const MCDC_Block& you, const std::string& filename);

    // Value semantics: the rare line label and the rare second group both live
    // behind owning pointers that are deep-copied, so a copied block gets its
    // own rather than sharing.  Mirrors BranchElement::DiffData.
    MCDC_Block(const MCDC_Block& o);
    MCDC_Block(MCDC_Block&&) noexcept = default;
    MCDC_Block& operator=(MCDC_Block&&) noexcept = default;
    ~MCDC_Block() = default;

private:
    // How the groups are stored.  Every real MC/DC line has exactly one group
    // size - one decision per line - and an unordered_map costs a bucket array,
    // a node allocation and ~150 bytes to hold a single vector, so the ONE case
    // is stored inline and MANY is the only shape that allocates a map at all.
    enum class Shape : uint8_t {
        EMPTY = 0,   // no group
        ONE   = 1,   // exactly one group size:  one_size_ / one_group_
        MANY  = 2,   // two or more:  *many_ holds all of them, one_group_ empty
    };

    int32_t line_;
    // Meaningful only in the ONE shape.
    int32_t one_size_ = 0;
    Shape   shape_    = Shape::EMPTY;
    // Set only for a non-numeric line key, which no C or C++ run produces at
    // all:  out of line behind a pointer so the normal case pays 8 bytes rather
    // than the 32 an always-materialized std::string costs.  Null and
    // empty both mean "use line_"; line_label() hands back a shared empty
    // string for either.
    std::unique_ptr<std::string> line_label_;
    std::vector<MCDC_Expression> one_group_;
    std::unique_ptr<std::unordered_map<int32_t, std::vector<MCDC_Expression>>> many_;
};

// ============================================================================
// MCDC_Data
//
// Container for all MC/DC blocks in one coverage data set.
// Maintains cached found_/hit_ totals; call recalculate_counts() (private)
// after any structural change.
// ============================================================================

class MCDC_Data {
public:
    MCDC_Data();

    // Append a fully-formed block.  If a block for the same line already
    // exists the two are merged (filename is used for merge error locations);
    // otherwise the block is inserted as-is.  Returns 0 on success.
    int append_mcdc(const MCDC_Block& block, const std::string& filename);

    // Create and register a new empty block for 'line'.
    // Returns a pointer to the newly created block (owned by this object).
    MCDC_Block* new_mcdc(int32_t line);

    // Remove the block at 'line'.  Mirrors pure-Perl MCDC_Data::remove:
    // returns 1 if a block was removed, 0 if the line was absent.
    int remove(int32_t line, bool check = false);

    // ---- totals -------------------------------------------------------------

    int64_t found() const;
    int64_t hit()   const;

    std::pair<int64_t, int64_t> get_found_and_hit() const;

    // Apply signed deltas to the cached found/hit totals.
    void adjust_counts(int64_t dFound, int64_t dHit);

    // ---- lookup -------------------------------------------------------------

    // Pointer to the block at 'line', or nullptr if not present.
    MCDC_Block* value(int32_t line);

    // All line keys present in this container.
    std::vector<int32_t> keylist() const;

    // ---- set operations (return count of blocks affected) -------------------

    // The filename only locates mismatch diagnostics, and merge() needs it, so
    // it is threaded through rather than defaulted:  there is deliberately no
    // filename-less overload of union_with/intersect_with, because the XS
    // binding always supplies a string (empty when the Perl caller omitted the
    // argument) and such an overload would be unreachable.  Mirrors BranchData.

    // Union: merge compatible blocks; copy absent blocks from 'other'.
    // Returns number of changes detected.
    int union_with(const MCDC_Data& other, const std::string& filename);

    // Intersect: retain only lines present in both; merge counts where present.
    // Lines absent in 'other' are removed.  Returns number of changes detected.
    int intersect_with(const MCDC_Data& other, const std::string& filename);

    // Difference: remove lines that appear in 'other'.
    // Returns number of lines removed.  Difference never merges two blocks - it
    // only drops them - so it raises no mismatch diagnostic and has no use for a
    // filename;  its binding calls the short form, and the long form exists so a
    // caller which has a filename in hand does not have to know that.
    int difference_with(const MCDC_Data& other, const std::string& filename);
    int difference_with(const MCDC_Data& other); // filename defaults to ""

    // ---- raw map access -----------------------------------------------------

    std::unordered_map<int32_t, MCDC_Block>&       data();

    // Recompute cached found_/hit_ totals from the current blocks.  Needed
    // after populating data_ directly (e.g. STORABLE_thaw).
    void recalculate_counts();

private:
    std::unordered_map<int32_t, MCDC_Block> data_;
    int64_t found_;
    int64_t hit_;
};

// When LCOV_XS_INLINE is defined, include the implementation file
// to make all methods inline
#ifdef LCOV_XS_INLINE
#include "MCDCData.cpp"
#endif
