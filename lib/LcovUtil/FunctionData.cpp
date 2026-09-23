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

#include "FunctionData.hpp"

#include <algorithm>
#include <cstring>
#include <iterator>
#include <new>
#include <unordered_map>

// Conditional inline keyword - expands to 'inline' when LCOV_XS_INLINE is
// defined and this file is included into the XS translation unit.
#ifdef LCOV_XS_INLINE
#define LCOV_INLINE inline
#else
#define LCOV_INLINE
#endif

namespace FunctionDataCallbacks
{
LCOV_INLINE ReleaseFn callers_release = nullptr;
}

// ============================================================================
// StringTable
// ============================================================================

namespace lcov
{

LCOV_INLINE StringTable::StringTable()
{
    // Id 0 is the empty string, so that a zero id can double as "no value".
    strings_.emplace_back();
    index_.emplace(std::string_view(strings_.front()), 0u);
}

LCOV_INLINE StringTable& StringTable::instance()
{
    static StringTable table;
    return table;
}

LCOV_INLINE uint32_t StringTable::intern(const char* s, std::size_t len)
{
    std::string_view key(s, len);
    auto             it = index_.find(key);
    if (it != index_.end())
        return it->second;
    // The view goes into the index only after the string it names is in the
    // deque, whose elements a later push_back never moves.
    strings_.emplace_back(s, len);
    uint32_t id = static_cast<uint32_t>(strings_.size() - 1);
    index_.emplace(std::string_view(strings_.back()), id);
    return id;
}

LCOV_INLINE const std::string& StringTable::str(uint32_t id) const
{
    if (id >= strings_.size())
        // ids are only ever handed out by intern(), and a thaw re-interns the
        // strings rather than carrying raw ids, so no id is out of range
        return strings_.front(); // LCOV_UNREACHABLE_LINE - the empty string
    return strings_[id];
}

// ============================================================================
// CategoryTable
// ============================================================================

LCOV_INLINE CategoryTable::CategoryTable()
{
    // Index 0 is the empty string, which is "no category".
    categories_.emplace_back();
    index_.emplace(std::string_view(categories_.front()), uint8_t(0));
}

LCOV_INLINE CategoryTable& CategoryTable::instance()
{
    static CategoryTable table;
    return table;
}

LCOV_INLINE uint8_t CategoryTable::index(const std::string& s, bool* overflow)
{
    if (overflow)
        *overflow = false;
    auto it = index_.find(std::string_view(s));
    if (it != index_.end())
        return it->second;
    if (categories_.size() > MAX_CATEGORIES) {
        if (overflow)
            *overflow = true;
        return 0;
    }
    // As in StringTable::intern:  the view goes into the index only after the
    // deque holds the string it names.
    categories_.emplace_back(s);
    uint8_t idx = static_cast<uint8_t>(categories_.size() - 1);
    index_.emplace(std::string_view(categories_.back()), idx);
    return idx;
}

LCOV_INLINE const std::string& CategoryTable::str(uint8_t index) const
{
    if (index >= categories_.size())
        // as StringTable::str:  every index comes from category_index_str()
        return categories_.front(); // LCOV_UNREACHABLE_LINE - the empty string
    return categories_[index];
}

}    // namespace lcov

// ============================================================================
// FunctionAlias
// ============================================================================

LCOV_INLINE FunctionAlias::FunctionAlias(uint32_t name, int64_t count,
                                         bool count_defined)
    : name_(name), differential_(false), count_defined_(count_defined),
      external_(false), tla_(0), count_(count_defined ? count : 0),
      external_calls_(NO_EXTERNAL_CALLS), merged_(), callers_(nullptr)
{
}

LCOV_INLINE FunctionAlias::FunctionAlias(FunctionAlias&& o) noexcept
    : name_(o.name_), differential_(o.differential_),
      count_defined_(o.count_defined_), external_(o.external_), tla_(o.tla_),
      count_(o.count_), external_calls_(o.external_calls_),
      merged_(std::move(o.merged_)), callers_(o.callers_)
{
    o.callers_ = nullptr;
}

LCOV_INLINE FunctionAlias& FunctionAlias::operator=(FunctionAlias&& o) noexcept
{
    if (this != &o) {
        release_callers();
        name_          = o.name_;
        differential_  = o.differential_;
        count_defined_ = o.count_defined_;
        external_       = o.external_;
        tla_            = o.tla_;
        count_          = o.count_;
        external_calls_ = o.external_calls_;
        merged_         = std::move(o.merged_);
        callers_       = o.callers_;
        o.callers_     = nullptr;
    }
    return *this;
}

LCOV_INLINE FunctionAlias::~FunctionAlias()
{
    release_callers();
}

LCOV_INLINE void FunctionAlias::release_callers()
{
    if (callers_ && FunctionDataCallbacks::callers_release)
        FunctionDataCallbacks::callers_release(callers_);
    callers_ = nullptr;
}

LCOV_INLINE uint32_t FunctionAlias::name_id() const
{
    return name_;
}

LCOV_INLINE const std::string& FunctionAlias::name() const
{
    return lcov::interned(name_);
}

LCOV_INLINE bool FunctionAlias::is_differential() const
{
    return differential_;
}

LCOV_INLINE bool FunctionAlias::has_count() const
{
    return count_defined_;
}

LCOV_INLINE int64_t FunctionAlias::count() const
{
    return count_defined_ ? count_ : 0;
}

LCOV_INLINE bool FunctionAlias::is_external() const
{
    return external_;
}

LCOV_INLINE void FunctionAlias::set_external()
{
    // Set-only and idempotent:  two captures of one symbol cannot disagree
    // about its linkage, one of them may simply not have recorded it
    external_ = true;
}

LCOV_INLINE bool FunctionAlias::has_external_callers() const
{
    return NO_EXTERNAL_CALLS != external_calls_;
}

LCOV_INLINE const FunctionAlias::MergedNames* FunctionAlias::merged() const
{
    return merged_.get();
}

LCOV_INLINE void FunctionAlias::add_merged(uint32_t name, int64_t count)
{
    if (name == name_)
        return;
    if (!merged_)
        merged_.reset(new MergedNames());
    for (auto& m : *merged_) {
        if (m.first == name) {
            m.second = lcov::add_sat(m.second, count);
            return;
        }
    }
    merged_->emplace_back(name, count);
}

LCOV_INLINE void FunctionAlias::add_merged(const MergedNames* names)
{
    if (names)
        for (const auto& m : *names)
            add_merged(m.first, m.second);
}

LCOV_INLINE int64_t FunctionAlias::external_calls() const
{
    return external_calls_;
}

LCOV_INLINE void FunctionAlias::add_external_calls(int64_t count)
{
    // The flag is never cleared, for the reason it exists at all:  it is the
    // only record that a call site was there, so nothing may ever unsay it.
    // The count folds as CallSite counts merge:  an unknown one contributes
    // nothing to a known total, and only known counts add
    if (NO_EXTERNAL_CALLS == external_calls_ ||
        CallSite::DASH == external_calls_)
        external_calls_ = count;
    else if (CallSite::DASH != count)
        external_calls_ = lcov::add_sat(external_calls_, count);
}

LCOV_INLINE void FunctionAlias::set_count(int64_t count)
{
    // Pure Perl overwrites the count slot, so a differential alias stops being
    // one.  Counts are only mutated while merging and filtering, which happens
    // before a report can become differential, so this arm is the interesting
    // one and the reset is just fidelity.
    count_         = count;
    count_defined_ = true;
    differential_  = false;
    tla_           = 0;
}

LCOV_INLINE void FunctionAlias::set_count_undef()
{
    count_         = 0;
    count_defined_ = false;
    differential_  = false;
    tla_           = 0;
}

LCOV_INLINE void FunctionAlias::add_count(int64_t count)
{
    count_         = lcov::add_sat(this->count(), count);
    count_defined_ = true;
}

LCOV_INLINE uint32_t FunctionAlias::tla_id() const
{
    return differential_ ? tla_ : 0;
}

LCOV_INLINE void FunctionAlias::set_tla(uint32_t tla)
{
    tla_ = tla;
}

LCOV_INLINE void FunctionAlias::set_differential(int64_t count,
                                                 bool count_defined,
                                                 uint32_t tla)
{
    count_         = count_defined ? count : 0;
    count_defined_ = count_defined;
    tla_           = tla;
    differential_  = true;
}

LCOV_INLINE void* FunctionAlias::callers() const
{
    return callers_;
}

LCOV_INLINE void FunctionAlias::set_callers(void* handle)
{
    if (handle == callers_)
        return;
    release_callers();
    callers_ = handle;
}

// ============================================================================
// FunctionEntry
// ============================================================================

LCOV_INLINE FunctionEntry::FunctionEntry(uint32_t name, uint32_t file,
                                         int32_t first, int32_t last,
                                         bool has_last)
    : name_(name), file_(file), differential_(false), has_last_(has_last),
      external_callees_(false), tla_(0), first_(first),
      last_(has_last ? last : 0), count_(0)
{
}

LCOV_INLINE uint32_t FunctionEntry::name_id() const
{
    return name_;
}

LCOV_INLINE const std::string& FunctionEntry::name() const
{
    return lcov::interned(name_);
}

LCOV_INLINE uint32_t FunctionEntry::file_id() const
{
    return file_;
}

LCOV_INLINE const std::string& FunctionEntry::filename() const
{
    return lcov::interned(file_);
}

LCOV_INLINE int64_t FunctionEntry::hit() const
{
    return count_;
}

LCOV_INLINE void FunctionEntry::set_hit(int64_t count)
{
    count_        = count;
    differential_ = false;
    tla_          = 0;
}

LCOV_INLINE bool FunctionEntry::is_differential() const
{
    return differential_;
}

LCOV_INLINE uint32_t FunctionEntry::tla_id() const
{
    return differential_ ? tla_ : 0;
}

LCOV_INLINE void FunctionEntry::set_differential(int64_t count, uint32_t tla)
{
    count_        = count;
    tla_          = tla;
    differential_ = true;
}

LCOV_INLINE void FunctionEntry::set_tla(uint32_t tla)
{
    tla_ = tla;
}

LCOV_INLINE bool FunctionEntry::has_external_callees() const
{
    return external_callees_;
}

LCOV_INLINE void FunctionEntry::set_external_callees()
{
    // Set-only, as the flag of FunctionAlias::has_external_callers is and for
    // the same reason:  the call site it stands for is gone
    external_callees_ = true;
}

LCOV_INLINE int32_t FunctionEntry::line() const
{
    return first_;
}

LCOV_INLINE void FunctionEntry::set_line(int32_t line)
{
    first_ = line;
}

LCOV_INLINE bool FunctionEntry::has_end_line() const
{
    return has_last_;
}

LCOV_INLINE int32_t FunctionEntry::end_line() const
{
    return last_;
}

LCOV_INLINE void FunctionEntry::set_end_line(int32_t line)
{
    last_     = line;
    has_last_ = true;
}

LCOV_INLINE void FunctionEntry::clear_end_line()
{
    last_     = 0;
    has_last_ = false;
}

LCOV_INLINE std::size_t FunctionEntry::numAliases() const
{
    return aliases_.size();
}

LCOV_INLINE FunctionAlias* FunctionEntry::alias(uint32_t name)
{
    auto it = aliases_.find(name);
    return it == aliases_.end() ? nullptr : &it->second;
}

LCOV_INLINE std::vector<uint32_t> FunctionEntry::aliasNames() const
{
    std::vector<uint32_t> names;
    names.reserve(aliases_.size());
    for (const auto& kv : aliases_)
        names.push_back(kv.first);
    return names;
}

LCOV_INLINE std::size_t FunctionEntry::name_rank(const std::string& name)
{
    // The lambda penalty of pure Perl's addAlias:  a lambda name is ranked as
    // if it were 1000 characters longer, so it is chosen to represent the
    // function only when every alias is a lambda.
    std::size_t rank = name.size();
    if (name.find("{lambda(") != std::string::npos ||
        name.find(".lambda$") != std::string::npos)
        rank += 1000;
    return rank;
}

LCOV_INLINE void FunctionEntry::choose_name()
{
    // Mirrors pure Perl's FunctionEntry::preferredName:  the lowest rank wins,
    // ties broken lexically, so the result does not depend on the order
    // of the container
    const std::string* best = nullptr;
    uint32_t           id   = name_;
    for (const auto& kv : aliases_) {
        const std::string& candidate = lcov::interned(kv.first);
        if (!best || name_rank(candidate) < name_rank(*best) ||
            (name_rank(candidate) == name_rank(*best) && candidate < *best)) {
            best = &candidate;
            id   = kv.first;
        }
    }
    if (best)
        name_ = id;
}

LCOV_INLINE bool FunctionEntry::addAliasCount(uint32_t name, int64_t count)
{
    bool changed;
    auto it = aliases_.find(name);
    if (it != aliases_.end()) {
        FunctionAlias& alias = it->second;
        changed              = 0 == alias.count() && 0 != count;
        alias.add_count(count);
    } else {
        aliases_.emplace(name, FunctionAlias(name, count));
        changed = true;
        // Keep track of the shortest name as the function representative.
        const std::string& candidate = lcov::interned(name);
        const std::string& current   = lcov::interned(name_);
        std::size_t        crank     = name_rank(current);
        std::size_t        nrank     = name_rank(candidate);
        if (nrank < crank || (nrank == crank && candidate < current))
            name_ = name;
    }
    count_ = lcov::add_sat(count_, count);
    return changed;
}

LCOV_INLINE bool FunctionEntry::addAliasDifferential(uint32_t name,
                                                     int64_t count,
                                                     bool count_defined,
                                                     uint32_t tla)
{
    auto it = aliases_.find(name);
    if (it != aliases_.end()) {
        if (name != name_)
            return false;    // pure Perl dies:  "alias $name exists"
        it->second.set_differential(count, count_defined, tla);
        return true;
    }
    FunctionAlias alias(name, 0, false);
    alias.set_differential(count, count_defined, tla);
    aliases_.emplace(name, std::move(alias));
    return true;
}

// The names of an interned alias set - sorted and separated by a newline
//   'aliasSet' in lcovutil.pm.
static void split_alias_set(uint32_t set, std::vector<std::string_view>& names)
{
    const std::string& s = lcov::interned(set);
    std::size_t        at = 0;
    for (;;) {
        std::size_t nl = s.find('\n', at);
        if (nl == std::string::npos) {
            names.emplace_back(s.data() + at, s.size() - at);
            return;
        }
        names.emplace_back(s.data() + at, nl - at);
        at = nl + 1;
    }
}

static uint32_t join_alias_set(const std::vector<std::string_view>& names)
{
    std::string joined;
    for (std::size_t i = 0; i < names.size(); ++i) {
        if (i)
            joined += '\n';
        joined.append(names[i].data(), names[i].size());
    }
    return lcov::intern(joined);
}

LCOV_INLINE uint32_t alias_set_union(uint32_t mine, uint32_t yours)
{
    if (0 == mine || 0 == yours)
        return 0;
    if (mine == yours)
        return mine;
    // An aggregation meets the same pair of sets once per input -- one per
    // translation unit which instantiates a header template -- the set is as
    // large as the number of instantiations.  Split/join on every call
    // would be quadratic (not good).
    // The ids are interned for the life of the process, so the answer for
    //  a particular pair never changes
    static std::unordered_map<uint64_t, uint32_t> memo;
    const uint64_t key = mine < yours ?
                             (uint64_t(mine) << 32) | yours :
                             (uint64_t(yours) << 32) | mine;
    auto found = memo.find(key);
    if (found != memo.end())
        return found->second;
    std::vector<std::string_view> a, b, both;
    split_alias_set(mine, a);
    split_alias_set(yours, b);
    // both are sorted the same way as Perl's 'sort':  bytewise, the same
    // order as std::string_view compares in, so this is a merge
    std::set_union(a.begin(), a.end(), b.begin(), b.end(),
                   std::back_inserter(both));
    // one side holding the other is the common case, and needs no new string
    const uint32_t result = both.size() == a.size() ? mine :
                            both.size() == b.size() ? yours :
                                                      join_alias_set(both);
    memo.emplace(key, result);
    return result;
}

LCOV_INLINE bool FunctionEntry::removeAliases(
    const std::vector<uint32_t>& names, uint32_t* missing)
{
    bool rename = false;
    for (uint32_t name : names) {
        auto it = aliases_.find(name);
        if (it == aliases_.end()) {
            // pure Perl dies here, having already removed the earlier names;
            // the caller raises that die with this name in it.
            if (missing)
                *missing = name;
            return false;
        }
        count_ -= it->second.count();
        aliases_.erase(it);
        if (name == name_)
            rename = true;
    }
    if (rename && !aliases_.empty())
        choose_name();
    // ..and the calls those aliases made - see the header
    if (calls_.size() && !names.empty()) {
        std::vector<std::string> gone;
        gone.reserve(names.size());
        for (uint32_t name : names)
            gone.push_back(lcov::interned(name));
        std::vector<std::string_view> in, left;
        for (CallSite* s = calls_.begin(); s != calls_.end();) {
            if (0 == s->aliases) {
                ++s;
                continue;
            }
            in.clear();
            left.clear();
            split_alias_set(s->aliases, in);
            for (std::string_view n : in)
                if (std::find(gone.begin(), gone.end(), n) == gone.end())
                    left.push_back(n);
            if (left.size() == in.size()) {
                ++s;
            } else if (left.empty()) {
                calls_.erase(s);    // the next site is now at 's'
            } else {
                s->aliases = join_alias_set(left);
                ++s;
            }
        }
    }
    return !aliases_.empty();
}

LCOV_INLINE void FunctionEntry::appendAliasRaw(uint32_t name, int64_t count,
                                               bool count_defined,
                                               bool differential, uint32_t tla,
                                               bool     external,
                                               int64_t  external_calls,
                                               const FunctionAlias::MergedNames* merged)
{
    FunctionAlias alias(name, count, count_defined);
    if (differential)
        alias.set_differential(count, count_defined, tla);
    if (external)
        alias.set_external();
    if (FunctionAlias::NO_EXTERNAL_CALLS != external_calls)
        alias.add_external_calls(external_calls);
    alias.add_merged(merged);
    // insert_or_assign, not emplace:  a clone starts out with the seeded alias
    // of its own name, and this replaces it with the recorded one.
    auto it = aliases_.find(name);
    if (it == aliases_.end())
        aliases_.emplace(name, std::move(alias));
    else
        it->second = std::move(alias);
}

// ---- call sites -------------------------------------------------------------

LCOV_INLINE CallSiteList::~CallSiteList()
{
    ::operator delete(block_);
}

// LCOV_UNREACHABLE_START
// Both of these are here to keep 'FunctionEntry(FunctionEntry&&) = default'
// from being implicitly deleted, and nothing uses it:  every FunctionEntry is
// owned by a shared_ptr, so no entry - and therefore no site list - is ever
// moved.  If that changes, the report says so rather than quietly counting
// these as covered.
LCOV_INLINE CallSiteList::CallSiteList(CallSiteList&& o) noexcept :
    block_(o.block_)
{
    o.block_ = nullptr;
}

LCOV_INLINE CallSiteList& CallSiteList::operator=(CallSiteList&& o) noexcept
{
    if (this != &o) {
        ::operator delete(block_);
        block_   = o.block_;
        o.block_ = nullptr;
    }
    return *this;
}
// LCOV_UNREACHABLE_STOP

LCOV_INLINE CallSite* CallSiteList::data()
{
    // the sites sit immediately after the header:  see the layout comment on
    // CallSiteList::Header
    return block_ ? reinterpret_cast<CallSite*>(block_ + 1) : nullptr;
}

LCOV_INLINE const CallSite* CallSiteList::data() const
{
    return block_ ? reinterpret_cast<const CallSite*>(block_ + 1) : nullptr;
}

LCOV_INLINE std::size_t CallSiteList::size() const
{
    return block_ ? block_->size : 0;
}

LCOV_INLINE CallSite* CallSiteList::begin()
{
    return data();
}

LCOV_INLINE CallSite* CallSiteList::end()
{
    return data() + size();
}

LCOV_INLINE const CallSite* CallSiteList::begin() const
{
    return data();
}

LCOV_INLINE const CallSite* CallSiteList::end() const
{
    return data() + size();
}

LCOV_INLINE void CallSiteList::grow(std::size_t needed)
{
    if (block_ && needed <= block_->capacity)
        return;
    std::size_t count = size();
    Header*     fresh =
        static_cast<Header*>(::operator new(sizeof(Header) +
                                            needed * sizeof(CallSite)));
    fresh->size     = static_cast<uint32_t>(count);
    fresh->capacity = static_cast<uint32_t>(needed);
    if (count)
        std::memcpy(reinterpret_cast<CallSite*>(fresh + 1), data(),
                    count * sizeof(CallSite));
    ::operator delete(block_);
    block_ = fresh;
}

LCOV_INLINE void CallSiteList::reserve(std::size_t n)
{
    if (n)
        grow(n);
}

LCOV_INLINE CallSite* CallSiteList::insert(CallSite* at, const CallSite& site)
{
    std::size_t where = static_cast<std::size_t>(at - begin());
    std::size_t count = size();
    if (count == (block_ ? block_->capacity : 0))
        // 1.25x -- see the growth comment on the class
        grow(count + count / 4 + 1);
    CallSite* p = data() + where;
    if (where != count)
        std::memmove(p + 1, p, (count - where) * sizeof(CallSite));
    *p = site;
    ++block_->size;
    return p;
}

LCOV_INLINE void CallSiteList::push_back(const CallSite& site)
{
    insert(end(), site);
}

LCOV_INLINE void CallSiteList::erase(CallSite* at)
{
    std::size_t where = static_cast<std::size_t>(at - begin());
    std::size_t count = size();
    if (where + 1 != count)
        std::memmove(at, at + 1, (count - where - 1) * sizeof(CallSite));
    --block_->size;
}

namespace
{
inline bool site_before(const CallSite& s, int32_t line, int32_t column,
                        int32_t ordinal, uint32_t file)
{
    if (s.line != line)
        return s.line < line;
    if (s.column != column)
        return s.column < column;
    if (static_cast<int32_t>(s.ordinal) != ordinal)
        return static_cast<int32_t>(s.ordinal) < ordinal;
    // ..and last, the file the call is written in, as a string:  the order is
    // the order the 'FNC:' records are written in, and an interned id is
    // whatever this process happened to hand out.  Only reached by the handful
    // of sites which share a location with another, so the string compare costs
    // nothing in the ordinary case;  the id compare in front of it is there for
    // the ordinary case of two sites with the SAME file, which is much the
    // commonest way to get here.
    if (s.file == file)
        return false;
    return lcov::interned(s.file) < lcov::interned(file);
}

// Where a site with this identity belongs in the sorted list:  the first site
// which is not before it, which is either the site itself or the position to
// insert it at.
inline CallSite* site_position(CallSiteList& calls, int32_t line, int32_t column,
                               int32_t ordinal, uint32_t file)
{
    return std::lower_bound(calls.begin(), calls.end(), line,
                            [column, ordinal, file](const CallSite& s,
                                                    int32_t l) {
                                return site_before(s, l, column, ordinal, file);
                            });
}

inline bool site_is(const CallSite& s, int32_t line, int32_t column,
                    int32_t ordinal, uint32_t file)
{
    return s.line == line && s.column == column &&
           static_cast<int32_t>(s.ordinal) == ordinal && s.file == file;
}
}    // namespace

LCOV_INLINE CallSite* FunctionEntry::find_site(int32_t line, int32_t column,
                                               int32_t ordinal, uint32_t file)
{
    // An ordinal no site can hold is not a site of mine:  answering that
    // directly keeps the search below from having to think about the narrowing
    if (ordinal < 0 || ordinal > MAX_CALLSITE_ORDINAL)
        return nullptr;
    CallSite* it = site_position(calls_, line, column, ordinal, file);
    if (it != calls_.end() && site_is(*it, line, column, ordinal, file))
        return it;
    return nullptr;
}

LCOV_INLINE std::pair<CallSite*, CallSite*>
FunctionEntry::callSitesAt(int32_t line, int32_t column)
{
    // ordinal 0 in my own file is the first identity there can be at a
    // location:  the ordinal is compared before the file, and my own file is
    // the empty string, which sorts before every other
    CallSite* first = site_position(calls_, line, column, 0, 0);
    CallSite* last  = first;
    while (last != calls_.end() && last->line == line && last->column == column)
        ++last;
    return {first, last};
}

LCOV_INLINE int32_t FunctionEntry::resolveOrdinal(int32_t line, int32_t column,
                                                  uint32_t file, uint32_t callee)
{
    auto range = callSitesAt(line, column);
    for (const CallSite* s = range.first; s != range.second; ++s)
        if (s->file == file && s->callee == callee)
            return s->ordinal;
    // the sites of one file at one location are in ordinal order, so the first
    // gap is the lowest ordinal not in use
    int32_t ordinal = 0;
    for (const CallSite* s = range.first; s != range.second; ++s) {
        if (s->file != file)
            continue;
        if (static_cast<int32_t>(s->ordinal) > ordinal)
            break;
        ordinal = s->ordinal + 1;
    }
    return ordinal;
}

LCOV_INLINE std::size_t FunctionEntry::numCallSites() const
{
    return calls_.size();
}

LCOV_INLINE std::size_t FunctionEntry::numCallSitesHit() const
{
    // Counted rather than maintained, as pure Perl counts it:  a site's count
    // can change under merge, filtering or subtraction.
    // A site whose count is not known is never a site known to have been taken:
    // it is in numCallSites and not here, so a degraded capture understates the
    // rate rather than overstating it.
    std::size_t n = 0;
    for (const CallSite& s : calls_)
        if (CallSite::DASH != s.count && 0 != s.count)
            ++n;
    return n;
}

LCOV_INLINE const CallSiteList& FunctionEntry::callSites() const
{
    return calls_;
}

LCOV_INLINE CallSite* FunctionEntry::findCallSite(int32_t line, int32_t column,
                                                  int32_t ordinal, uint32_t file)
{
    return find_site(line, column, ordinal, file);
}

// LCOV_UNREACHABLE_START
// The pair of the mutable overload above, kept so a const entry can look a site
// up.  Nothing does:  every XS binding which looks one up holds a mutable entry,
// so overload resolution always picks the other one.
LCOV_INLINE const CallSite* FunctionEntry::findCallSite(int32_t line,
                                                        int32_t column,
                                                        int32_t ordinal,
                                                        uint32_t file) const
{
    return const_cast<FunctionEntry*>(this)->findCallSite(line, column, ordinal,
                                                          file);
}
// LCOV_UNREACHABLE_STOP

LCOV_INLINE int FunctionEntry::addCallSite(int32_t line, int32_t column,
                                           int32_t ordinal, int64_t count,
                                           uint32_t callee, uint32_t file,
                                           uint32_t aliases, int8_t statement)
{
    if (ordinal < 0 || ordinal > MAX_CALLSITE_ORDINAL)
        return -2;    // more sites at one location than a record can hold
    CallSite* it = site_position(calls_, line, column, ordinal, file);
    if (it != calls_.end() && site_is(*it, line, column, ordinal, file)) {
        if (it->callee != callee)
            return -1;    // same location, different target:  a mismatch
        // ..whatever the count says:  which aliases make the call is not
        // coverage data, so it does not make the site 'changed'
        it->aliases = alias_set_union(it->aliases, aliases);
        // ..and nor is the line its coverpoint is allocated to
        if (0 == it->statement)
            it->statement = statement;
        // The '-' lattice of BranchElement::merge:  unknown merged with anything
        // is that thing, and only a known count can be added to.  A mixed
        // capture where one unit knows the count and another does not therefore
        // resolves to the count, and never the other way round.
        if (CallSite::DASH == count)
            return 0;    // no new news
        if (CallSite::DASH == it->count) {
            it->count = count;
            return 0 != count ? 1 : 0;
        }
        bool changed = 0 == it->count && 0 != count;
        it->count    = lcov::add_sat(it->count, count);
        return changed ? 1 : 0;
    }
    CallSite site;
    site.count   = count;
    site.line    = line;
    site.column  = column;
    site.callee  = callee;
    site.file    = file;
    site.aliases = aliases;
    site.ordinal   = static_cast<uint16_t>(ordinal);
    site.statement = statement;
    calls_.insert(it, site);
    return 1;
}

LCOV_INLINE bool FunctionEntry::removeCallSite(int32_t line, int32_t column,
                                               int32_t ordinal, uint32_t file)
{
    CallSite* it = find_site(line, column, ordinal, file);
    if (!it)
        return false;
    calls_.erase(it);
    return true;
}

LCOV_INLINE void FunctionEntry::reserveCallSites(std::size_t n)
{
    calls_.reserve(n);
}

LCOV_INLINE void FunctionEntry::appendCallSiteRaw(const CallSite& site)
{
    calls_.push_back(site);
}

// ============================================================================
// FunctionMap
// ============================================================================

LCOV_INLINE FunctionMap::FunctionMap(uint32_t file) : file_(file)
{
}

LCOV_INLINE uint32_t FunctionMap::file_id() const
{
    return file_;
}

LCOV_INLINE const std::string& FunctionMap::filename() const
{
    return lcov::interned(file_);
}

LCOV_INLINE std::vector<int32_t> FunctionMap::keylist() const
{
    std::vector<int32_t> keys;
    keys.reserve(byLine_.size());
    for (const auto& kv : byLine_)
        keys.push_back(kv.first);
    return keys;
}

LCOV_INLINE std::vector<uint32_t> FunctionMap::list_functions() const
{
    std::vector<uint32_t> names;
    names.reserve(byName_.size());
    for (const auto& kv : byName_)
        names.push_back(kv.first);
    return names;
}

namespace
{
// The answer to a lookup which found nothing:  one shared null, so that
// findKey/findName can answer a reference.
const std::shared_ptr<FunctionEntry>& no_entry()
{
    static const std::shared_ptr<FunctionEntry> none;
    return none;
}
}    // namespace

LCOV_INLINE const std::shared_ptr<FunctionEntry>& FunctionMap::findKey(
    int32_t line) const
{
    auto it = byLine_.find(line);
    return it == byLine_.end() ? no_entry() : it->second;
}

LCOV_INLINE const std::shared_ptr<FunctionEntry>& FunctionMap::findName(
    uint32_t name) const
{
    auto it = byName_.find(name);
    return it == byName_.end() ? no_entry() : it->second;
}

LCOV_INLINE const std::shared_ptr<FunctionEntry>& FunctionMap::insert(
    uint32_t name, int32_t first, int32_t last, bool has_last)
{
    auto entry =
        std::make_shared<FunctionEntry>(name, file_, first, last, has_last);
    // Pure Perl's FunctionEntry::new seeds the alias of its own name with a
    // zero count -- "not hit, yet".
    entry->addAliasCount(name, 0);
    return byLine_[first] = std::move(entry);
}

LCOV_INLINE void FunctionMap::registerName(uint32_t name, FunctionEntry* entry)
{
    // The entry is one of mine, so its owning pointer is what goes into the
    // name map:  that is what keeps it alive if the line map later drops it
    // (FunctionMap::difference does exactly that).  An entry's start line is
    // its key in the line map -- 'insert' and 'relocate' are the only things
    // which set either, and they set both -- so this is a lookup rather than a
    // scan.
    auto it = byLine_.find(entry->line());
    if (it != byLine_.end() && it->second.get() == entry) {
        byName_[name] = it->second;
        return;
    }
    // Not in my line map:  there is no ownership to share, so the name map
    // borrows.  Unreachable from define_function, which registers the entry it
    // has just inserted, and kept non-owning rather than made an error so that
    // a caller which registers a standalone entry cannot double-free it.
    byName_[name] = std::shared_ptr<FunctionEntry>(entry, [](FunctionEntry*) {});
}

LCOV_INLINE bool FunctionMap::unregisterName(uint32_t name)
{
    return 0 != byName_.erase(name);
}

LCOV_INLINE bool FunctionMap::removeKey(int32_t line)
{
    return 0 != byLine_.erase(line);
}

LCOV_INLINE bool FunctionMap::relocate(FunctionEntry* entry, int32_t line)
{
    auto it = byLine_.find(entry->line());
    if (it == byLine_.end() || it->second.get() != entry)
        return false;
    std::shared_ptr<FunctionEntry> keep = it->second;
    byLine_.erase(it);
    entry->set_line(line);
    byLine_[line] = std::move(keep);
    return true;
}

LCOV_INLINE int64_t FunctionMap::numFunc(bool merged) const
{
    if (merged)
        return static_cast<int64_t>(byLine_.size());
    int64_t n = 0;
    for (const auto& kv : byLine_)
        n += static_cast<int64_t>(kv.second->numAliases());
    return n;
}

LCOV_INLINE int64_t FunctionMap::numHit(bool merged) const
{
    int64_t n = 0;
    for (const auto& kv : byLine_) {
        const FunctionEntry& entry = *kv.second;
        if (merged) {
            // Pure Perl tests the raw count slot, which in a differential
            // report holds a [count, tla] pair and is therefore always true.
            if (entry.is_differential() || entry.hit() > 0)
                ++n;
        } else {
            entry.for_each_alias([&n](uint32_t, const FunctionAlias& alias) {
                if (alias.count() > 0)
                    ++n;
            });
        }
    }
    return n;
}

LCOV_INLINE std::pair<int64_t, int64_t> FunctionMap::callgraph_found_and_hit() const
{
    int64_t found = 0;
    int64_t hit   = 0;
    for (const auto& kv : byLine_) {
        found += static_cast<int64_t>(kv.second->numCallSites());
        hit += static_cast<int64_t>(kv.second->numCallSitesHit());
    }
    return std::make_pair(found, hit);
}

LCOV_INLINE void FunctionMap::insertEntry(int32_t line,
                                          std::shared_ptr<FunctionEntry> entry)
{
    byLine_[line] = std::move(entry);
}

LCOV_INLINE void FunctionMap::registerEntryName(
    uint32_t name, std::shared_ptr<FunctionEntry> entry)
{
    byName_[name] = std::move(entry);
}
