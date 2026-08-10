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

#include "BranchData.hpp"

// Conditional inline keyword - expands to 'inline' when LCOV_XS_INLINE is defined
#ifdef LCOV_XS_INLINE
#define LCOV_INLINE inline
#else
#define LCOV_INLINE
#endif

// ---------------------------------------------------------------------------
// Error reporting callback
// ---------------------------------------------------------------------------
namespace BranchDataCallbacks {
    std::function<void(int, const std::string&)> report_error = nullptr;
}

// Error codes must match the ids lcovutil.pm assigns from its @lcovErrs array.
// Makefile.PL loads lcovutil.pm and injects the authoritative value as
// -DLCOV_ERROR_MISMATCH=<id>.  We refuse to guess a default: if the define is
// absent the build was not driven through Makefile.PL and would silently use a
// stale id, so fail loudly instead.
#ifndef LCOV_ERROR_MISMATCH
#error "LCOV_ERROR_MISMATCH not defined -- build via Makefile.PL so error ids are derived from lcovutil.pm"
#endif
static const int ERROR_MISMATCH = LCOV_ERROR_MISMATCH;

// ---------------------------------------------------------------------------
// BranchElement
// ---------------------------------------------------------------------------

LCOV_INLINE BranchElement::BranchElement(int32_t id, int64_t taken, std::string expr, Type type,
                                          bool excluded)
    : id_(id), taken_(taken), expr_(std::move(expr)), type_(type), excluded_(excluded)
{}

LCOV_INLINE BranchElement::BranchElement(const BranchElement& o)
    : id_(o.id_), taken_(o.taken_), expr_(o.expr_), type_(o.type_), excluded_(o.excluded_),
      diff_(o.diff_ ? std::make_unique<DiffData>(*o.diff_) : nullptr)
{}


LCOV_INLINE int32_t BranchElement::id() const noexcept { return id_; }
LCOV_INLINE int64_t BranchElement::data() const noexcept { return taken_; }
LCOV_INLINE int64_t BranchElement::count() const noexcept {
    return (taken_ == DASH || taken_ < 0) ? 0 : taken_;
}
LCOV_INLINE bool BranchElement::isTaken() const noexcept {
    return taken_ != DASH && taken_ >= 0;
}

LCOV_INLINE const std::string& BranchElement::expr() const noexcept { return expr_; }
LCOV_INLINE std::string BranchElement::exprString() const {
    return expr_.empty() ? "undef" : expr_;
}

LCOV_INLINE BranchElement::Type BranchElement::type() const noexcept { return type_; }

LCOV_INLINE char BranchElement::signature() const noexcept {
    switch (type_) {
        case EXCEPT:      return 'e';
        case FALLTHROUGH: return 'f';
        default:          return 'b';
    }
}

LCOV_INLINE bool BranchElement::isException() const noexcept { return type_ == EXCEPT; }
LCOV_INLINE bool BranchElement::isExcluded() const noexcept { return excluded_; }
LCOV_INLINE void BranchElement::setExcluded(bool v) noexcept { excluded_ = v; }

LCOV_INLINE bool BranchElement::isDifferential() const noexcept { return diff_ != nullptr; }
LCOV_INLINE const std::string& BranchElement::tla() const noexcept {
    static const std::string empty;
    return diff_ ? diff_->tla : empty;
}

LCOV_INLINE void BranchElement::set_tla(std::string t) {
    // Precondition: the element is already differential (set_differential).  The
    // set_tla XSUB enforces it, matching pure-Perl BranchElement::set_tla, so
    // this never fires from Perl.  Throwing rather than allocating diff_ lazily
    // is deliberate:  a lazy allocation would make isDifferential() true on an
    // element pure Perl leaves non-differential.
    if (!diff_)
        throw std::logic_error("BranchElement::set_tla: not differential");  // LCOV_UNREACHABLE_LINE
    diff_->tla = std::move(t);
}

LCOV_INLINE void BranchElement::set_differential(std::string tla_val,
                                                 std::optional<int64_t> base,
                                                 std::optional<int64_t> curr) {
    if (!diff_)
        diff_ = std::make_unique<DiffData>();
    diff_->tla        = std::move(tla_val);
    diff_->base_undef = !base.has_value();
    diff_->curr_undef = !curr.has_value();
    diff_->base       = base.value_or(0);
    diff_->curr       = curr.value_or(0);
}

LCOV_INLINE bool BranchElement::hasBase() const noexcept {
    return diff_ && !diff_->base_undef;
}
LCOV_INLINE bool BranchElement::hasCurr() const noexcept {
    return diff_ && !diff_->curr_undef;
}
LCOV_INLINE int64_t BranchElement::base() const noexcept {
    return diff_ ? diff_->base : 0;
}
LCOV_INLINE int64_t BranchElement::curr() const noexcept {
    return diff_ ? diff_->curr : 0;
}

LCOV_INLINE int BranchElement::merge(const BranchElement& that, const std::string& filename,
                                      int32_t line) {
    // Deliberately NO id_ != that.id_ check: pure-Perl BranchElement::merge has
    //   none, and merging the counts regardless is what it does.  Elements are
    //   only ever paired up positionally within two blocks of identical
    //   signature (BranchBlock::merge), and the .info reader re-derives branch
    //   ids contiguously from zero per block, so a real input cannot present a
    //   mismatched pair here.  Rejecting a mismatched pair instead would
    //   silently drop 'that' element's counts for anyone calling this directly
    //   with hand-built elements.
    int changed = 0;

    /* Check for excluded/unreachable mismatch (matches pure Perl lines 4290-4304) */
    if (excluded_ != that.excluded_) {
        /* The null arm is precluded, not merely untested:  these sources are only
         * ever built into the XS module (BranchData.hpp #includes this file), and
         * its BOOT block installs report_error unconditionally before any Perl
         * code can reach a merge.  So the callback cannot be null here, and the
         * check stays only to keep the file compilable/usable standalone. */
        if (BranchDataCallbacks::report_error) {   // LCOV_EXCL_BR_LINE
            std::string loc = filename.empty() ? "" : ("\"" + filename + "\":" + std::to_string(line) + ": ");
            std::string msg = loc + "mismatched 'unreachable' tag for branch id " +
                             std::to_string(id_) + ", " + std::to_string(that.id_) +
                             ": '" + std::to_string(excluded_) + "' -> '" +
                             std::to_string(that.excluded_) + "'";
            BranchDataCallbacks::report_error(ERROR_MISMATCH, msg);
        }
        /* Set self to excluded */
        changed = excluded_ != 1;
        excluded_ = true;
    }

    if (that.taken_ == DASH) {
        /* nothing - no new data */
    } else if (taken_ == DASH) {
        taken_  = that.taken_;
        /* changed=1 if we went from dash (uninstrumented) to non-zero (hit) */
        changed = (that.taken_ != 0) ? 1 : 0;
    } else {
        if (taken_ == 0 && that.taken_ != 0)
            changed = 1;
        taken_ += that.taken_;
    }
    if (that.excluded_)
        excluded_ = true;
    /* Deliberately do NOT copy differential (tla/base/curr) data from 'that':
     * pure-Perl BranchElement::merge (lcovutil.pm) never does.  merge/union/
     * intersect only ever run on RAW coverage during load; differential data
     * is attached later, at the genhtml annotate-for-display phase (cloneBlock
     * / set_differential), on freshly built blocks that are never re-merged.
     * Asserted by xs_test "BranchElement::merge does not copy differential". */
    return changed;
}

// ---------------------------------------------------------------------------
// BranchBlock
// ---------------------------------------------------------------------------

LCOV_INLINE int32_t BranchBlock::idx() const noexcept { return idx_; }
LCOV_INLINE void BranchBlock::setIdx(int32_t v) noexcept { idx_ = v; }

LCOV_INLINE std::string BranchBlock::signature() const {
    std::string sig;
    sig.reserve(elements_.size());
    for (const auto& elem : elements_)
        sig += elem.signature();
    return sig;
}

LCOV_INLINE const std::vector<BranchElement>& BranchBlock::elements() const noexcept { return elements_; }

LCOV_INLINE void BranchBlock::appendElement(BranchElement elem) {
    elements_.push_back(std::move(elem));
}

LCOV_INLINE void BranchBlock::reserveElements(size_t n) { elements_.reserve(n); }

LCOV_INLINE int BranchBlock::merge(const BranchBlock& you, const std::string& filename,
                                    int32_t line) {
    if (elements_.size() != you.elements_.size() ||
        signature() != you.signature())
        throw std::runtime_error("expected identical block");
    int changed = 0;
    for (size_t i = 0; i < elements_.size(); ++i) {
        // 'changed' is a boolean 'did anything change', matching pure-Perl
        //   BranchBlock::merge's '$changed = 1 if ...'.  Summing the per-element
        //   results instead would report 2 where pure Perl reports 1 whenever
        //   two elements of the block both change, and no caller uses the
        //   magnitude.
        if (elements_[i].merge(you.elements_[i], filename, line) > 0)
            changed = 1;
    }
    return changed;
}

// ---------------------------------------------------------------------------
// BranchLocation
// ---------------------------------------------------------------------------

LCOV_INLINE BranchLocation::BranchLocation(int32_t line) : line_(line) {}

LCOV_INLINE BranchLocation::BranchLocation(const BranchLocation& o)
    : line_(o.line_),
      line_label_(o.line_label_ ? std::make_unique<std::string>(*o.line_label_)
                                : nullptr),
      blocks_(o.blocks_) {}

LCOV_INLINE int32_t BranchLocation::line() const noexcept { return line_; }

LCOV_INLINE const std::string& BranchLocation::line_label() const noexcept {
    // A single empty string for every unlabelled location, so the accessor can
    // keep returning a reference now that the label is out of line.
    static const std::string empty;
    return line_label_ ? *line_label_ : empty;
}

LCOV_INLINE void BranchLocation::set_line_label(std::string label) {
    // Unconditional:  every caller (BranchLocation::new and the deserializer)
    // already tests the label and only calls this for a real, non-empty one, so
    // an empty-label or already-labelled arm here would be dead code.  A
    // hypothetical empty label would still read back correctly - line_label()
    // hands back the stored empty string rather than the shared one - it would
    // just cost an allocation nothing currently makes.
    line_label_ = std::make_unique<std::string>(std::move(label));
}

LCOV_INLINE bool BranchLocation::containsCode(const std::string& code) const {
    // Derived from blocks_, which already holds every block's signature -- see
    // the note on why there is no signature index in codes() below.
    for (const auto& block : blocks_)
        if (block.signature() == code)
            return true;
    return false;
}

LCOV_INLINE size_t BranchLocation::numBlocks() const noexcept { return blocks_.size(); }

LCOV_INLINE void BranchLocation::reserveBlocks(size_t n) { blocks_.reserve(n); }

LCOV_INLINE bool BranchLocation::hasBlock(int32_t id) const {
    /* Pure Perl: $#{$self->[INDEX]} >= $id.  idx IS the position, so a valid
     * id is any in-range subscript of the dense block vector. */
    return id >= 0 && static_cast<size_t>(id) < blocks_.size();
}

LCOV_INLINE BranchBlock& BranchLocation::getBlock(int32_t id) {
    if (!hasBlock(id))
        throw std::out_of_range("BranchLocation::getBlock: id not found");
    return blocks_[id];
}

LCOV_INLINE const BranchBlock& BranchLocation::getBlock(int32_t id) const {
    // The const overload is only reached from merge/union_with/intersect_with,
    // which walk ids they just read out of the other location's own block list,
    // so the id is always in range.  Perl never binds this overload -- the
    // getBlock XSUB takes a non-const BranchLocation* and pre-checks hasBlock().
    if (!hasBlock(id))
        throw std::out_of_range("BranchLocation::getBlock: id not found");  // LCOV_UNREACHABLE_LINE
    return blocks_[id];
}

LCOV_INLINE std::vector<int32_t> BranchLocation::getList(const std::string& code) const {
    std::vector<int32_t> ids;
    // Ascending id order, which a forward scan of blocks_ gives for free:
    // blocks_[i].idx() == i, so the subscript IS the id.
    for (size_t i = 0; i < blocks_.size(); ++i)
        if (blocks_[i].signature() == code)
            ids.push_back(static_cast<int32_t>(i));
    // Every internal caller guards with containsCode() first (BranchLocation::
    // merge, BranchData::union_with, BranchData::intersect_with) or iterates
    // codes() of the very location it then queries; the getList XSUB likewise
    // croaks on an unknown code before getting here.
    if (ids.empty())
        throw std::out_of_range("BranchLocation::getList: code not found");  // LCOV_UNREACHABLE_LINE
    return ids;
}

LCOV_INLINE void BranchLocation::insertBlock(BranchBlock block) {
    std::string sig = block.signature();  /* Copy, don't hold reference across move */

    /* An element-less block has an empty signature, so it would be invisible to
     * codes()/getList() while still occupying an id and being counted by
     * numBlocks() -- so numBlocks() and the code-keyed walks would disagree
     * about how many blocks this location has.  Pure-Perl insertBlock dies on it
     * ('unexpected empty block'); reject it here too rather than storing a
     * block no code-driven traversal can reach. */
    if (sig.empty())
        throw std::out_of_range("unexpected empty block");

    /* ALWAYS auto-assign new ID like pure Perl does */
    /* Pure Perl: $blockIdx = $#$list + 1; -- i.e. append at the end, which for
     * the dense vector is just its new size. */
    int32_t id = static_cast<int32_t>(blocks_.size());
    block.setIdx(id);

    blocks_.push_back(std::move(block));
}

LCOV_INLINE void BranchLocation::removeBlock(int32_t id, BranchData* /*bd*/) {
    if (!hasBlock(id)) {
        throw std::out_of_range("remove:  unknown block ID '" + std::to_string(id) + "'");
    }

    /* Pure Perl splices the block out and renumbers the tail.  With a dense
     * vector that is exactly a single erase: the shift moves each surviving
     * block down one slot, and setIdx re-establishes blocks_[i].idx() == i.
     * There is no code index to repair -- the signature lookups read blocks_
     * itself, so dropping the block drops its code with it. */
    blocks_.erase(blocks_.begin() + id);
    for (size_t i = static_cast<size_t>(id); i < blocks_.size(); ++i)
        blocks_[i].setIdx(static_cast<int32_t>(i));
}

LCOV_INLINE std::vector<BranchBlock*> BranchLocation::blocks(bool sorted) {
    std::vector<BranchBlock*> result;
    result.reserve(blocks_.size());
    for (auto& block : blocks_)
        result.push_back(&block);
    if (sorted) {
        /* Key each block with its signature once, rather than deriving it up to
         * three times per comparison. */
        std::vector<std::pair<std::string, BranchBlock*>> keyed;
        keyed.reserve(result.size());
        for (BranchBlock* blk : result)
            keyed.emplace_back(blk->signature(), blk);
        std::sort(keyed.begin(), keyed.end(),
                  [](const std::pair<std::string, BranchBlock*>& a,
                     const std::pair<std::string, BranchBlock*>& b) {
                      if (a.first.size() != b.first.size())
                          return a.first.size() < b.first.size();
                      int c = a.first.compare(b.first);
                      if (c != 0)
                          return c < 0;
                      return a.second->idx() < b.second->idx();
                  });
        for (size_t i = 0; i < keyed.size(); ++i)
            result[i] = keyed[i].second;
    }
    return result;
}

LCOV_INLINE std::vector<std::string> BranchLocation::codes(bool sorted) const {
    // The distinct block signatures, in first-appearance (i.e. block id) order.
    //
    // Derived, not stored.  A signature -> ids table beside blocks_ would hold
    // exactly ONE key on 99.6% of real branch lines and cost ~280 bytes per line
    // to do it, while every answer it could give is already in blocks_: the
    // signature is the block's own, and blocks_[i].idx() == i gives the id.
    //
    // With sorted=0 the order is block order, and no caller may depend on any
    // particular one: pure Perl keys the equivalent set with a Perl hash, whose
    // iteration order is randomized per process.  Every caller outside this file
    // passes sorted=1 (bin/genhtml:2874,2996,3047 and lcovutil.pm's
    // intersect/difference); BranchLocation::merge is the one unsorted caller
    // and treats the result as a set.
    std::vector<std::string> result;
    result.reserve(blocks_.size());
    for (const auto& block : blocks_) {
        std::string sig = block.signature();
        if (std::find(result.begin(), result.end(), sig) == result.end())
            result.push_back(std::move(sig));
    }
    if (sorted) {
        std::sort(result.begin(), result.end(),
                  [](const std::string& a, const std::string& b) {
                      if (a.size() != b.size())
                          return a.size() < b.size();
                      return a < b;
                  });
    }
    return result;
}

LCOV_INLINE size_t BranchLocation::numCodes() const {
    // The count of distinct signatures, without materializing the code list:
    // a block's signature is new iff no earlier block carries it.  Quadratic
    // in the number of blocks on one line, which is 1 on 99.2% of real branch
    // lines and 4 in the worst line observed.
    size_t n = 0;
    for (size_t i = 0; i < blocks_.size(); ++i) {
        const std::string sig = blocks_[i].signature();
        bool seen = false;
        for (size_t j = 0; j < i && !seen; ++j)
            seen = blocks_[j].signature() == sig;
        if (!seen)
            ++n;
    }
    return n;
}

LCOV_INLINE std::pair<int64_t, int64_t> BranchLocation::totals(bool count_excluded) const {
    int64_t found = 0, hit = 0;
    for (const auto& block : blocks_) {
        for (const auto& elem : block.elements()) {
            if (!count_excluded && elem.isExcluded())
                continue;
            // Every non-excluded branch element is 'found', including ones with
            // a '-'/DASH taken count (branch present but not evaluated, e.g.
            // due to short-circuit).  Match pure Perl BranchMap::totals which
            // does ++found unconditionally, then ++hit if (0 != count).
            // (count() maps DASH -> 0, so a '-' branch is found but not hit.)
            ++found;
            // hit means the branch was actually taken at least once.
            // Note: isTaken() is true even for a zero count (it only
            // distinguishes '-'/DASH), so it must NOT be used here.
            if (elem.count() != 0)
                ++hit;
        }
    }
    return {found, hit};
}

LCOV_INLINE bool BranchLocation::hasHitElement(bool count_excluded) const {
    // Same element filter and same 'hit' test as totals() above, but answers
    // the first hit rather than counting them all.
    for (const auto& block : blocks_) {
        for (const auto& elem : block.elements()) {
            if (!count_excluded && elem.isExcluded())
                continue;
            if (elem.count() != 0)
                return true;
        }
    }
    return false;
}

LCOV_INLINE int BranchLocation::merge(const BranchLocation& that, const std::string& filename) {
    int changed = 0;
    // Match pure Perl logic: merge by signature (code), not by block ID
    for (const auto& code : that.codes(false)) {
        const std::vector<int32_t> your_list = that.getList(code);
        if (containsCode(code)) {
            // We have this signature - merge blocks in order.
            // The id list is a SNAPSHOT taken before the loop, and has to be:
            // the 'else' arm below calls insertBlock, so re-deriving the list
            // mid-loop would see blocks this very loop had just appended.  Pure
            // Perl takes the same snapshot -- it captures $#$myList before any
            // block is appended -- and getList() returning by value makes that
            // the only thing it can do.
            const std::vector<int32_t> my_list = getList(code);
            for (size_t idx = 0; idx < your_list.size(); ++idx) {
                int32_t your_id = your_list[idx];
                const BranchBlock& your_block = that.getBlock(your_id);
                if (idx < my_list.size()) {
                    // Merge into existing block at same index.
                    // 'changed' is a boolean, as in pure-Perl
                    //   BranchLocation::merge -- see BranchBlock::merge above.
                    int32_t my_id = my_list[idx];
                    if (getBlock(my_id).merge(your_block, filename, line_))
                        changed = 1;
                } else {
                    // Copy additional block
                    BranchBlock copy = your_block;
                    insertBlock(std::move(copy));
                    changed = 1;
                }
            }
        } else {
            // We don't have this signature - copy all blocks
            for (int32_t your_id : your_list) {
                BranchBlock copy = that.getBlock(your_id);
                insertBlock(std::move(copy));
                changed = 1;
            }
        }
    }
    return changed;
}

// ---------------------------------------------------------------------------
// BranchData
// ---------------------------------------------------------------------------

LCOV_INLINE int64_t BranchData::found() const noexcept { return found_; }
LCOV_INLINE int64_t BranchData::hit() const noexcept { return hit_; }
LCOV_INLINE std::pair<int64_t, int64_t> BranchData::get_found_and_hit() const noexcept {
    return {found_, hit_};
}
LCOV_INLINE void BranchData::adjust_counts(int64_t dFound, int64_t dHit) noexcept {
    found_ += dFound;
    hit_   += dHit;
}

LCOV_INLINE std::unordered_map<int32_t, BranchLocation>& BranchData::data() noexcept { return data_; }

LCOV_INLINE BranchLocation* BranchData::value(int32_t line) {
    auto it = data_.find(line);
    return (it != data_.end()) ? &it->second : nullptr;
}

LCOV_INLINE std::vector<int32_t> BranchData::keylist() const {
    std::vector<int32_t> keys;
    keys.reserve(data_.size());
    for (const auto& [k, v] : data_) { (void)v; keys.push_back(k); }
    std::sort(keys.begin(), keys.end());
    return keys;
}

LCOV_INLINE BranchLocation& BranchData::findOrCreate(int32_t line) {
    auto it = data_.find(line);
    if (it == data_.end()) {
        auto [ins, ok] = data_.emplace(line, BranchLocation(line));
        (void)ok;
        return ins->second;
    }
    return it->second;
}

LCOV_INLINE void BranchData::removeBranches(const BranchBlock& block) {
    for (const auto& e : block.elements()) {
        --found_;
        if (e.count() != 0)
            --hit_;
    }
}

LCOV_INLINE bool BranchData::remove(int32_t line, bool check) {
    // Mirror pure-Perl BranchMap::remove: if check_if_present is set and the
    // line is absent, do nothing and return false.  Otherwise subtract the
    // line's found/hit totals from the running counts, erase it, return true.
    auto it = data_.find(line);
    if (check && it == data_.end())
        return false;
    // Without 'check' the caller asserts the line is present:  pure Perl dies
    // ("<line> not found") rather than reporting a removal that never
    // happened, so throw and let the XS boundary turn it into the same die.
    if (it == data_.end())
        throw std::runtime_error(std::to_string(line) + " not found");
    auto [f, h] = it->second.totals(false);
    found_ -= f;
    hit_ -= h;
    data_.erase(it);
    return true;
}

LCOV_INLINE void BranchData::updateCounts() {
    found_ = 0; hit_ = 0;
    for (const auto& [line, loc] : data_) {
        auto [f, h] = loc.totals(false);
        found_ += f; hit_ += h;
    }
}

LCOV_INLINE int BranchData::union_with(const BranchData& other,
                                       const std::string& filename) {
    // Mirror pure-Perl BranchData::union (lcovutil.pm), including its choice
    // between maintaining the cached found/hit incrementally and rebuilding it
    // once at the end.  Keeping the cache up to date costs, per line you bring,
    // about two totals() walks of that line - one before the merge and one
    // after, since merge() reports only whether something changed and not by
    // how much.  Rebuilding it from scratch afterwards instead costs one
    // totals() walk per line *I* hold.  Neither is always cheaper, and the
    // choice can be made before doing any work:
    //   - accumulating many files into one growing map (lcov -a f1 ... -aN)
    //     is the case a blanket rescan makes quadratic in the total number of
    //     lines;  there the incremental cost is a rounding error.
    //   - merging two maps that cover the same lines touches everything I hold
    //     anyway, so the single rescan is the cheaper of the two.
    const bool rescan = 2 * other.data_.size() > data_.size();
    int changed       = 0;
    for (const auto& [line, loc] : other.data_) {
        auto it = data_.find(line);
        if (it == data_.end()) {
            data_.emplace(line, loc);
            // the copy is identical to yours, so its contribution to our
            //   cached found/hit is just your totals
            if (!rescan) {
                auto [f, h] = loc.totals(false);
                adjust_counts(f, h);
            }
            changed = 1;
        } else if (rescan) {
            if (it->second.merge(loc, filename))
                changed = 1;
        } else {
            auto [oldFound, oldHit] = it->second.totals(false);
            const int changedHere   = it->second.merge(loc, filename);
            auto [newFound, newHit] = it->second.totals(false);
            adjust_counts(newFound - oldFound, newHit - oldHit);
            if (changedHere)
                changed = 1;
        }
    }
    if (rescan && changed)
        updateCounts();
    return changed;
}

LCOV_INLINE int BranchData::intersect_with(const BranchData& other,
                                           const std::string& filename) {
    // Mirror pure-Perl BranchData::intersect (lcovutil.pm).
    // Intersection is per-line AND per-code (block signature): keep only the
    // blocks whose signature is present in BOTH locations, merging the common
    // ones.  A location-level merge() would be UNION semantics and wrongly
    // retain blocks present only in 'self'.
    int changed = 0;
    // Snapshot line keys: we erase from data_ while iterating.
    std::vector<int32_t> lines;
    lines.reserve(data_.size());
    for (const auto& [line, loc] : data_) { (void)loc; lines.push_back(line); }

    for (int32_t line : lines) {
        auto oit = other.data_.find(line);
        if (oit == other.data_.end()) {
            // my line not found in your data - remove it
            data_.erase(line);
            changed = 1;
            continue;
        }
        BranchLocation& myLoc         = data_.at(line);
        const BranchLocation& yourLoc = oit->second;

        BranchLocation replace(line);
        int changedHere = 0;
        for (const auto& code : myLoc.codes(true)) {  // sorted, like codes(1)
            if (yourLoc.containsCode(code)) {
                const auto& myList   = myLoc.getList(code);
                const auto& yourList = yourLoc.getList(code);
                size_t idx = 0;
                for (size_t yi = 0; yi < yourList.size(); ++yi) {
                    if (idx >= myList.size())
                        break;
                    int32_t my_id = myList[idx++];
                    // Merge in place, exactly like pure Perl mutating $mine.
                    // The summed counts must persist on the live block so they
                    // survive even when changedHere stays 0 (no block dropped)
                    // and we therefore keep the original location unchanged.
                    BranchBlock& mine = myLoc.getBlock(my_id);
                    if (mine.merge(yourLoc.getBlock(yourList[yi]), filename, line))
                        changedHere = 1;
                    replace.insertBlock(mine);  // copy of the mutated block
                }
            } else {
                // code present only in self - drop all these blocks
                changedHere = 1;
            }
        }
        if (changedHere) {
            changed = 1;
            data_.erase(line);
            if (replace.numBlocks() != 0)
                data_.emplace(line, std::move(replace));
        }
    }
    updateCounts();
    return changed;
}

LCOV_INLINE int BranchData::difference_with(const BranchData& other) {
    return difference_with(other, "");
}

LCOV_INLINE int BranchData::difference_with(const BranchData& other,
                                            const std::string& filename) {
    // 'filename' is accepted for interface symmetry with union_with/
    // intersect_with (and with MCDC_Data), but difference only ever DROPS
    // blocks - it never merges two elements - so there is no mismatch
    // diagnostic here that would need a location.
    (void)filename;
    // Mirror pure-Perl BranchData::difference (lcovutil.pm).
    // Difference is per-line AND per-code (block signature):
    //   - if a line is absent in 'other', keep it entirely;
    //   - for a code present in 'other', drop the leading common blocks and
    //     keep only the trailing extra blocks;
    //   - for a code absent in 'other', keep all its blocks.
    // Note that a whole-line erase would be wrong: it would discard blocks that
    // have no counterpart in 'other'.
    int changed = 0;
    std::vector<int32_t> lines;
    lines.reserve(data_.size());
    for (const auto& [line, loc] : data_) { (void)loc; lines.push_back(line); }

    for (int32_t line : lines) {
        auto oit = other.data_.find(line);
        if (oit == other.data_.end())
            continue;  // keep everything on this line
        BranchLocation& myLoc         = data_.at(line);
        const BranchLocation& yourLoc = oit->second;

        BranchLocation replace(line);
        int changedHere = 0;
        for (const auto& code : myLoc.codes(true)) {  // sorted, like codes(1)
            const auto& myList = myLoc.getList(code);
            if (yourLoc.containsCode(code)) {
                size_t yourCount = yourLoc.getList(code).size();
                changedHere = 1;
                // ignore the leading common blocks; keep the trailing extras
                for (size_t idx = yourCount; idx < myList.size(); ++idx)
                    replace.insertBlock(myLoc.getBlock(myList[idx]));  // copy
            } else {
                // code not present in 'other' - keep all these blocks
                for (int32_t my_id : myList)
                    replace.insertBlock(myLoc.getBlock(my_id));  // copy
            }
        }
        if (changedHere) {
            changed = 1;
            data_.erase(line);
            if (replace.numBlocks() != 0)
                data_.emplace(line, std::move(replace));
        }
    }
    updateCounts();
    return changed;
}
