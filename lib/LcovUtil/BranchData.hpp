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
#include <map>
#include <vector>
#include <optional>
#include <utility>
#include <memory>
#include <algorithm>
#include <climits>
#include <stdexcept>
#include <functional>

// ---------------------------------------------------------------------------
// Error reporting callback
// ---------------------------------------------------------------------------
namespace BranchDataCallbacks {
    /* Callback for reporting mismatch errors from C++ to Perl */
    extern std::function<void(int error_code, const std::string& message)> report_error;
}

// ---------------------------------------------------------------------------
// BranchElement
// ---------------------------------------------------------------------------
class BranchData;  // forward declaration

class BranchElement {
public:
    enum Type { VANILLA = 0, EXCEPT = 1, FALLTHROUGH = 2 };

    static const int64_t DASH = INT64_MIN;

    BranchElement() = default;
    BranchElement(int32_t id, int64_t taken, std::string expr, Type type,
                  bool excluded = false);

    int32_t id()    const noexcept;
    int64_t data()  const noexcept;
    int64_t count() const noexcept;
    bool isTaken() const noexcept;

    const std::string& expr() const noexcept;
    std::string exprString() const;

    Type type() const noexcept;
    char signature() const noexcept;

    bool isException() const noexcept;
    bool isExcluded()  const noexcept;
    void setExcluded(bool v) noexcept;

    bool isDifferential() const noexcept;
    const std::string& tla() const noexcept;

    // 'base'/'curr' are independently optional:  bin/genhtml cloneBlock passes
    // an undef base to mean "this block is not in the baseline at all", and
    // pure Perl stores that undef verbatim, so the XS side must too rather than
    // flattening it to 0.  Mirrors MCDC_Expression::DiffData.
    bool hasBase() const noexcept;
    bool hasCurr() const noexcept;
    int64_t base() const noexcept;
    int64_t curr() const noexcept;

    void set_tla(std::string t);
    void set_differential(std::string tla_val, std::optional<int64_t> base,
                          std::optional<int64_t> curr);

    int merge(const BranchElement& that, const std::string& /*filename*/,
              int32_t /*line*/);

    // Value semantics: differential data lives behind an owning pointer that is
    // deep-copied, so a copied element gets its own DiffData rather than sharing.
    BranchElement(const BranchElement& o);
    BranchElement(BranchElement&&) noexcept = default;
    BranchElement& operator=(BranchElement&&) noexcept = default;
    ~BranchElement() = default;

private:
    // Differential coverage data (TLA + optional [base,curr] pair).  Absent
    // (null diff_) for the overwhelmingly common non-differential element, so
    // the normal path pays a single pointer instead of two std::optionals.
    struct DiffData {
        std::string tla;
        int64_t     base       = 0;
        int64_t     curr       = 0;
        bool        base_undef = true;
        bool        curr_undef = true;
    };

    int32_t     id_       = 0;
    int64_t     taken_    = DASH;
    std::string expr_;
    Type        type_     = VANILLA;
    bool        excluded_ = false;
    std::unique_ptr<DiffData> diff_;
};


// ---------------------------------------------------------------------------
// BranchBlock
// ---------------------------------------------------------------------------
class BranchBlock {
public:
    BranchBlock() = default;

    int32_t idx()          const noexcept;
    void    setIdx(int32_t v) noexcept;

    // The concatenated per-element signature characters, e.g. "bb" or "be".
    // DERIVED from elements_ on each call rather than stored:  it is one
    // character per element, so recomputing it is a walk of a vector that the
    // caller has usually just walked anyway, while caching it cost 32 bytes of
    // std::string in an object that exists at least once per branch line.
    // Returned by value;  it fits std::string's inline buffer at every block
    // size these files contain, so no allocation is made either way.
    std::string signature() const;

    const std::vector<BranchElement>& elements() const noexcept;

    void appendElement(BranchElement elem);

    // Pre-size the element vector when the count is known (e.g. deserialization),
    // so appendElement does not reallocate mid-fill.
    void reserveElements(size_t n);

    int merge(const BranchBlock& you, const std::string& filename,
              int32_t line);

private:
    int32_t                    idx_ = 0;
    std::vector<BranchElement> elements_;
};


// ---------------------------------------------------------------------------
// BranchLocation
// ---------------------------------------------------------------------------
class BranchLocation {
public:
    explicit BranchLocation(int32_t line);

    int32_t line() const noexcept;

    // Original Perl-supplied line value when it is NOT a plain integer.
    // Pure-Perl BranchLocation stores $line verbatim, so a differential
    // "deleted line" key such as "<<<123" must round-trip through line().
    // Empty string means "use the numeric line_"; set only on the rare
    // non-numeric path.
    const std::string& line_label() const noexcept;
    void set_line_label(std::string label);

    bool containsCode(const std::string& code) const;

    bool hasBlock(int32_t id) const;

    size_t numBlocks() const noexcept;

    // Pre-size the block vector when the count is known (e.g. deserialization),
    // so insertBlock does not reallocate mid-fill.
    void reserveBlocks(size_t n);

    BranchBlock& getBlock(int32_t id);
    const BranchBlock& getBlock(int32_t id) const;

    // The ids of the blocks whose signature is 'code', in ascending id order.
    // By value:  the list is built by scanning blocks_, so there is nothing
    // stored to hand a reference to, and BranchLocation::merge needs a copy it
    // can iterate while mutating anyway (see the note at its call site).
    std::vector<int32_t> getList(const std::string& code) const;

    void insertBlock(BranchBlock block);

    void removeBlock(int32_t id, BranchData* /*bd*/ = nullptr);

    std::vector<BranchBlock*> blocks(bool sorted = false);

    std::vector<std::string> codes(bool sorted = false) const;

    // Count of distinct signatures, without materializing the code list.
    size_t numCodes() const;

    std::pair<int64_t, int64_t> totals(bool count_excluded = false) const;

    // Is any element on this line evaluated at least once?  Short-circuits on
    // the first hit, where totals() must visit every element to build a count
    // the caller then reduces to this one bit.
    bool hasHitElement(bool count_excluded = false) const;

    int merge(const BranchLocation& that, const std::string& filename);

    // Value semantics: the rare line label lives behind an owning pointer that
    // is deep-copied, so a copied location gets its own string rather than
    // sharing one.  Mirrors BranchElement::DiffData.
    BranchLocation(const BranchLocation& o);
    BranchLocation(BranchLocation&&) noexcept = default;
    BranchLocation& operator=(BranchLocation&&) noexcept = default;
    ~BranchLocation() = default;

private:
    int32_t line_ = 0;
    // Set only for a non-numeric line key, which no C or C++ run produces at
    // all:  out of line behind a pointer so the normal case pays 8 bytes rather
    // than the 32 an always-materialized std::string costs.  Null and
    // empty both mean "use line_"; line_label() hands back a shared empty
    // string for either.
    std::unique_ptr<std::string> line_label_;
    // Blocks by idx.  The idx space is dense 0..size()-1 by construction:
    // insertBlock always assigns the next free index and removeBlock decrements
    // every idx above the one it drops, so a block's idx IS its position here
    // and getBlock() is O(1) into an array with no node allocation and no
    // pointer chase.
    //
    // Invariant maintained by every mutator: blocks_[i].idx() == i.
    // Note: storing by value for performance. Perl variables passed to insertBlock
    // won't see idx updates from removeBlock renumbering. Use getBlock() for current state.
    //
    // There is deliberately no signature -> ids index beside this.  Every
    // question one could answer is already answered by the vector - the code is
    // the block's own signature() and the id is its subscript - and such an
    // index costs ~280 bytes per branch line of duplicated state to maintain.
    // See BranchLocation::codes().
    std::vector<BranchBlock>                             blocks_;
};


// ---------------------------------------------------------------------------
// BranchData
// ---------------------------------------------------------------------------
class BranchData {
public:
    BranchData() = default;

    int64_t found() const noexcept;
    int64_t hit()   const noexcept;
    std::pair<int64_t, int64_t> get_found_and_hit() const noexcept;

    // Apply signed deltas to the cached found/hit totals.
    void adjust_counts(int64_t dFound, int64_t dHit) noexcept;

    std::unordered_map<int32_t, BranchLocation>&       data()       noexcept;

    BranchLocation* value(int32_t line);

    std::vector<int32_t> keylist() const;

    BranchLocation& findOrCreate(int32_t line);

    void removeBranches(const BranchBlock& block);

    bool remove(int32_t line, bool check = false);

    void updateCounts();

    // The filename is only used to locate mismatch diagnostics ('"f.c":10:
    // mismatched unreachable tag...'), exactly as the pure-Perl BranchData
    // union/intersect/difference pass $filename down to BranchElement::merge.
    // It must be threaded through rather than defaulted:  under 'lcov -a' the
    // file and line are the only clue which input disagreed.  There is
    // deliberately no filename-less overload of these two - the XS binding
    // always supplies a string (empty when the Perl caller omitted the
    // argument), so an overload taking only 'other' would be unreachable.
    int union_with(const BranchData& other, const std::string& filename);

    int intersect_with(const BranchData& other, const std::string& filename);

    // difference, in contrast, never merges two elements - it only drops blocks
    // - so it raises no mismatch diagnostic and has no use for a filename.  Its
    // binding calls the short form;  the long form exists so a caller which has
    // a filename in hand does not have to know that.
    int difference_with(const BranchData& other, const std::string& filename);
    int difference_with(const BranchData& other); // filename defaults to ""

private:
    std::unordered_map<int32_t, BranchLocation> data_;
    int64_t found_ = 0;
    int64_t hit_   = 0;
};

// When LCOV_XS_INLINE is defined, include the implementation file
// to make all methods inline
#ifdef LCOV_XS_INLINE
#include "BranchData.cpp"
#endif
