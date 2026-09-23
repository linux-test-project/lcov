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
#include <cstddef>
#include <deque>
#include <memory>
#include <string>
#include <string_view>
#include <type_traits>
#include <unordered_map>
#include <utility>
#include <vector>

#include "CountArith.hpp"

// ============================================================================
// The function family:  FunctionAlias, FunctionEntry, FunctionMap, and the call
// site records of one function.  One C++ class per pure-Perl type, as the rest
// of this layer has.
//
// What is here and what is not.  Everything which touches the representation is
// here;  every diagnostic, every count validation and every option-dependent
// policy stays in lcovutil.pm, which is the reference implementation and the
// oracle for this one.  So 'FunctionEntry::addAlias' is Perl (it normalizes the
// count and reports a bad one) over '_addAliasCount' here, which only mutates,
// and 'FunctionMap::define_function' is Perl over 'insert'/'registerName'/
// 'relocate' here.  The alternative -- reimplementing the messages in C++ --
// means two copies of text that tests compare against, and it is what made
// MCDCData.cpp's 'report_incompatible' the only C++-side message in this layer.
//
// Strings are interned (lcov::StringTable).  An alias name is a mangled C++
// symbol, routinely 100+ bytes, and an inline function defined in a header
// appears in every translation unit which includes it:  as a Perl hash key that
// is one SV per file, here it is one table entry for the run.  The callee symbol
// of a call site is the same string in the same sense, so it uses the same
// table.
// ============================================================================

namespace lcov
{

// ---------------------------------------------------------------------------
// Run-wide string table.
//
// Ids are dense uint32_t handles; id 0 is the empty string, so a zero id can
// also serve as "no value" for a field which is never legitimately empty (the
// TLA of a call site, for instance).  Nothing is ever removed:  the table is
// the run's set of symbol names, which only grows, and an id is therefore
// stable for the life of the process.  It is deliberately NOT part of any
// serialized form -- ids are process-local, so the wire format carries strings
// and the reader interns them again (see FunctionMap serialization in the XS
// layer).
//
// std::deque is what gives 'index_' something stable to point at:  its
// elements are never moved by a push_back, so a std::string_view into one
// stays valid, and the key of the index costs no second copy of the string.
// ---------------------------------------------------------------------------
class StringTable
{
public:
    static StringTable& instance();

    uint32_t intern(const char* s, std::size_t len);
    uint32_t intern(const std::string& s)
    {
        return intern(s.data(), s.size());
    }

    // The string for 'id'.  An unknown id is a caller bug, and returns the
    // empty string rather than throwing:  every id in a live object came from
    // intern() in this process.
    const std::string& str(uint32_t id) const;

    std::size_t size() const
    {
        return strings_.size();
    }

private:
    StringTable();

    std::deque<std::string>                        strings_;
    std::unordered_map<std::string_view, uint32_t> index_;
};

inline uint32_t intern(const std::string& s)
{
    return StringTable::instance().intern(s);
}

inline uint32_t intern(const char* s, std::size_t len)
{
    return StringTable::instance().intern(s, len);
}

inline const std::string& interned(uint32_t id)
{
    return StringTable::instance().str(id);
}

// ---------------------------------------------------------------------------
// Run-wide category (TLA) vocabulary.
//
// A differential report labels a coverpoint with a three-letter acronym -- GNC,
// UIC, EUB and a dozen others.  Interning those in the string table above costs
// a four byte id in every record which carries one;  an index into a table of
// nothing but categories costs one byte, and a call site is the highest volume
// record of this family.  Index 0 is "no category", so a zeroed record is an
// uncategorized one.
//
// Not a hard-coded list:  genhtml's '--show-details' remaps the categories, and
// nothing here should have to know the names it remaps them to.  It is bounded
// instead -- 255 distinct category names in one process is an order of magnitude
// past what any report uses, so the 256th is a caller bug rather than something
// to make room for.  Reporting it is the XS layer's job (this file raises no
// diagnostics), hence the out parameter rather than a throw.
//
// Like the string table, and for the same reason, an index is process-local and
// never appears in a serialized form:  two processes fill the table in whatever
// order their own data arrives in.
// ---------------------------------------------------------------------------
class CategoryTable
{
public:
    // one index is spent on "no category", so this is what fits in a uint8_t
    static const std::size_t MAX_CATEGORIES = 255;

    static CategoryTable& instance();

    // The index of this category name, adding it if it is new.  The empty
    // string is index 0.  A name which does not fit answers 0 as well, with
    // '*overflow' set:  the caller reports it.
    uint8_t index(const std::string& s, bool* overflow = nullptr);

    // The name of this index, or the empty string for 0 (and for an index which
    // was never handed out -- an unknown index is a caller bug, and answering
    // the empty string is what StringTable::str does with an unknown id).
    const std::string& str(uint8_t index) const;

    std::size_t size() const
    {
        return categories_.size();
    }

private:
    CategoryTable();

    std::deque<std::string>                       categories_;
    std::unordered_map<std::string_view, uint8_t> index_;
};

inline uint8_t category_index(const std::string& s, bool* overflow = nullptr)
{
    return CategoryTable::instance().index(s, overflow);
}

inline const std::string& category_string(uint8_t index)
{
    return CategoryTable::instance().str(index);
}

}    // namespace lcov

// ---------------------------------------------------------------------------
// Hooks the XS layer installs at BOOT time.
//
// 'callers_release' releases the Perl value a FunctionAlias holds as its
// callers list (see FunctionAlias::callers).  It is a hook rather than a direct
// SvREFCNT_dec so that this file and its implementation stay free of the Perl
// API and keep compiling standalone in the COVERAGE build.
// ---------------------------------------------------------------------------
namespace FunctionDataCallbacks
{
using ReleaseFn = void (*)(void*);
extern ReleaseFn callers_release;
}    // namespace FunctionDataCallbacks

// ============================================================================
// CallSite
//
// One call from the body of a function:  where it is, how many times it was
// taken, and the symbol it calls.  (line, column, ordinal, file) is the site's
// identity and is stored once -- the "<line>:<col>:<ord>[:<file>]" key string
// every Perl caller uses is derived from it, never stored beside it.
//
// A plain aggregate rather than a class with accessors:  it has no invariant to
// keep, it is not handed to Perl as an object (pure Perl has no call-site type
// either -- 'callSiteData' answers a list), and it is the highest-volume record
// of the family at roughly ten per function.
//
// Every field is as narrow as the data it holds allows, and they are ordered
// widest first, because sixteen bytes of the naive layout are padding and slack:
//
//   - the count is the one field which has to be 64 bits:  it is a coverage
//     count, and every other count in this layer is int64_t.
//   - the line and the column stay 32 bits.  A generated source file really does
//     reach seven-digit line numbers, and a machine-written one-line file makes
//     the column just as large.
//   - the ordinal is the index of a site among the sites at one exact
//     (line, column) of one function, which is 0 for essentially every site in
//     real code (see '_siteKey' in lcovutil.pm).  16 bits is four orders of
//     magnitude of headroom;  both implementations of the '_addCallSite'
//     primitive refuse to record more than that, so the limit is a property of
//     the data and not of the backend which happens to be loaded.
//   - the TLA is an index into lcov::CategoryTable and NOT an interned string
//     id:  there are a dozen or so category names in a report where there are
//     hundreds of thousands of symbol names.
//   - the file is the file the call is WRITTEN in, interned, and 0 -- which is
//     the interned empty string -- when that is the file the function is defined
//     in, which is very nearly every site.  It is part of the identity and not
//     payload:  an inline function defined in a header has one FunctionEntry per
//     translation unit which instantiated it, and the calls in its body are
//     written in the header while the calls in the function which inlined it are
//     written in the '.c' file.  See '_siteKey' in lcovutil.pm.
//     This is the field which takes the record from 24 bytes to 32, and it is
//     8 rather than 4 bytes of growth because of the alignment the count forces.
//   - the alias set is the set of the function's aliases which make the call
//     ('SITE_ALIASES' in lcovutil.pm), as the interned string of their sorted
//     names, and 0 -- undef -- for "every alias".  An interned string rather
//     than a table of sets because nearly every set contains only a single
//     element (itself), which is then an id the table holds already, and
//     because Perl hands down and reads back is that string.
//     It fits in the slack the file left, so it is free.
//   - the statement offset is the distance from the line the call is written on
//     to its multi-line statement leader, which is where its coverpoint
//     is allocated ('SITE_STATEMENT' in lcovutil.pm), and 0 for essentially
//     every site.  An offset rather than a line so that it fits in the last
//     byte of padding:  lcovutil.pm refuses a statement further away than
//     MAX_STATEMENT_OFFSET, so it is free too.
//     The alternative -- an index into a per-entry table of the handful of files
//     one function's sites are written in, in the one padding byte there is --
//     buys back those 8 bytes per site at the cost of a table, a translation on
//     every access, and a second thing to merge, clone and serialize.  Not worth
//     it:  the growth is only paid by a report captured with callgraph coverage.
// ============================================================================

struct CallSite {
    // The '-' of a 'FNC:' record -- the call is in the compiled code and its
    // count is not known -- held in the same field as a real count.  The same
    // value and for exactly the same reasons as BranchElement::DASH, whose
    // comment has them:  NOT INT64_MIN, because that is what a narrowing
    // conversion of an out-of-range, NaN or infinite double produces, and no
    // count arithmetic can land on it because lcov::add_sat keeps every result
    // in [0, MAX_COUNT].  Restated here rather than shared, because the two
    // record types have no header in common and the constant is one line.
    static const int64_t DASH = INT64_MIN + 1;

    int64_t  count   = 0;
    int32_t  line    = 0;
    int32_t  column  = 0;
    uint32_t callee  = 0;    // interned symbol name
    uint32_t file    = 0;    // interned name of the file the call is written in,
                             //   0 when that is the function's own file
    uint32_t aliases = 0;    // interned alias set, 0 == every alias
    uint16_t ordinal = 0;
    uint8_t  tla     = 0;    // lcov::CategoryTable index, 0 == undef (not a
                             //   differential report, or not categorized yet)
    int8_t statement = 0;    // statement line - line, 0 == the line itself
};

// 32 rather than the 40 the fields in declaration order would take.  Asserted
// because the whole point of the layout is the size:  a field added in the wrong
// place silently costs eight bytes in the highest volume record of the family.
static_assert(sizeof(CallSite) == 32, "CallSite has grown a padding hole");
// The container below moves whole runs of sites with a memmove.
static_assert(std::is_trivially_copyable<CallSite>::value,
              "CallSite must stay a plain aggregate");

// The union of two interned alias sets (see CallSite):  0, "every alias",
// absorbs the other side.
uint32_t alias_set_union(uint32_t mine, uint32_t yours);

// The largest ordinal a CallSite can hold.  Both '_addCallSite' primitives
// enforce it -- see the comment above.
const int32_t MAX_CALLSITE_ORDINAL = 0xffff;

// The furthest a CallSite's statement line may be from its leader -- see the
// comment above.  lcovutil.pm checks it before handing a line down.
const int32_t MAX_STATEMENT_OFFSET = 127;

// ============================================================================
// CallSiteList
//
// The call sites of one function, kept sorted by (line, column, ordinal, file):
// that is what makes 'sortedCallSiteKeys' free and a lookup a binary search over
// a contiguous block.  The file is compared as a string and not as an interned
// id, because the order is the order the records are written in and an id is
// whatever this process happened to hand out.
//
// A hand-rolled container rather than a std::vector because of what it costs
// when it is empty, which is the overwhelmingly common case -- most functions
// call nothing, and no function has call data at all unless the report was
// captured with callgraph coverage enabled.  A vector is three pointers, 24 bytes
// in every FunctionEntry ever built;  this is one pointer, with the size and the
// capacity in the heap block beside the sites.  Nothing is slower for it:
// reaching a site was already a load of the vector's data pointer followed by an
// indexed access, and it still is.
//
// The growth policy is 1.25x rather than a vector's 2x for the same reason, and
// the difference is not the second-order thing it looks like:  a vector holding
// eight sites has rounded its way to a block which fits eight and an object
// which costs 24, where this rounds to a block which fits eight and an object
// which costs 8.  A function has a handful of sites, so the reallocation this
// costs is a copy of a block small enough not to notice, and 'reserve' is there
// for the one caller which knows the count in advance (thaw).
// ============================================================================

class CallSiteList
{
public:
    CallSiteList() = default;
    ~CallSiteList();

    // Move-only, like everything else which owns storage here.  Nothing moves
    // one today -- a FunctionEntry is always held by a shared_ptr, so its own
    // defaulted move constructor is never used either -- but these are what
    // keep that constructor from being implicitly deleted.
    CallSiteList(CallSiteList&& o) noexcept;
    CallSiteList& operator=(CallSiteList&& o) noexcept;
    CallSiteList(const CallSiteList&)            = delete;
    CallSiteList& operator=(const CallSiteList&) = delete;

    std::size_t size() const;

    // Contiguous, so a pointer is the iterator:  begin()/end() are what make a
    // range-for and std::lower_bound work over this.
    CallSite*       begin();
    CallSite*       end();
    const CallSite* begin() const;
    const CallSite* end() const;

    // Room for exactly 'n' sites, if that is more than there is room for now.
    // Exact rather than rounded up:  the caller which uses this knows the final
    // count, and rounding would put back the slack this container exists to
    // avoid.
    void reserve(std::size_t n);

    // Insert before 'at', which must be a position in this list (end() to
    // append), and answer the site as it now sits in the block -- the insertion
    // may have moved everything.
    CallSite* insert(CallSite* at, const CallSite& site);
    void      push_back(const CallSite& site);
    void      erase(CallSite* at);

private:
    void grow(std::size_t needed);

    // The allocation is this header immediately followed by 'capacity' sites.
    // Both are 8 byte aligned, which is what CallSite needs, and the two
    // uint32_t are the same eight bytes a size and a capacity would cost in the
    // object -- here they are paid for only by a function which has sites.
    struct Header {
        uint32_t size;
        uint32_t capacity;
    };

    CallSite*       data();
    const CallSite* data() const;

    Header* block_ = nullptr;
};

static_assert(sizeof(CallSiteList) == sizeof(void*),
              "CallSiteList is meant to be one pointer");

// ============================================================================
// FunctionAlias
//
// One alias of one function: its name and its hit count.  A differential report
// replaces the count with a (count, TLA) pair, which pure Perl does by storing
// an arrayref in the count slot;  here the two live side by side with a flag,
// so that a frozen alias is plain data and no Perl value is reachable from it.
// ============================================================================

class FunctionAlias
{
public:
    // An alias is its name, so there is no default constructor:  the one place
    // which could want it is 'aliases_[name]', and an alias whose name is 0
    // rather than the key it was filed under is a bug waiting to happen.
    FunctionAlias() = delete;
    // 'count_defined' false is pure Perl's 'FunctionAlias->new($name, undef)',
    // which addAliasDifferential uses to make an alias whose count arrives with
    // the differential pair a moment later.
    FunctionAlias(uint32_t name, int64_t count, bool count_defined = true);

    // Move-only:  the callers handle is a Perl reference this object owns, and
    // copying it silently would double-release it.  A copy is made by naming
    // every field which survives it -- 'FunctionEntry::appendAliasRaw' here,
    // 'standalone_alias' in the XS layer -- and, as pure Perl's clone does,
    // neither carries the callers over:  a copy starts out unresolved.
    FunctionAlias(FunctionAlias&& o) noexcept;
    FunctionAlias& operator=(FunctionAlias&& o) noexcept;
    FunctionAlias(const FunctionAlias&)            = delete;
    FunctionAlias& operator=(const FunctionAlias&) = delete;
    ~FunctionAlias();

    uint32_t           name_id() const;
    const std::string& name() const;

    bool    is_differential() const;
    bool    has_count() const;
    int64_t count() const;

    // Whether this symbol has external linkage -- what the 'e' flag of an
    // 'FNA:' record asserts.  False means "not asserted" rather than
    // "internal", and the setter is set-only and idempotent, for the reasons
    // pure Perl's FunctionAlias::is_external / ::set_external spell out.
    // Unlike the callers, this IS part of the port:  it is a property of the
    // symbol, so it travels with the definition through a merge and a
    // serialization.
    bool is_external() const;
    void set_external();

    // Whether something this report cannot name called me -- the 'x' flag of
    // the same record -- and how many calls those sites made, which is the
    // number the flag carries.  Also part of the port, and for the same
    // reason:  it is the residue of a call site which could not be written, so
    // nothing can recompute it later.  See pure Perl's
    // FunctionAlias::has_external_callers and ::external_calls.
    // The count is NO_EXTERNAL_CALLS where there is no flag, and CallSite::DASH
    // where the flag is there and the count is not known;  add_external_calls
    // folds one more dropped site into it under the lattice a call site merge
    // uses.
    static const int64_t NO_EXTERNAL_CALLS = INT64_MIN;
    bool    has_external_callers() const;
    int64_t external_calls() const;
    void    add_external_calls(int64_t count);

    // The other names this alias represents, which
    // TraceFile::_collapseCallgraphAliases merged into it, each with its own
    // share of my count:  (interned name, count) pairs in no particular order,
    // and null for none -- which is every alias but a merged one, so the
    // pairs are allocated only where there are some.  Part of the port, for
    // the reason the 'x' count is:  nothing can recompute it.  add_merged
    // sums into a name already there, and ignores my own name, as pure Perl's
    // FunctionAlias::add_merged does.
    typedef std::vector<std::pair<uint32_t, int64_t>> MergedNames;
    const MergedNames* merged() const;
    void               add_merged(uint32_t name, int64_t count);
    void               add_merged(const MergedNames* names);

    void set_count(int64_t count);
    void set_count_undef();
    void add_count(int64_t count);

    // 0 when this is not a differential alias, or when its TLA is undef.
    uint32_t tla_id() const;
    void     set_tla(uint32_t tla);
    void     set_differential(int64_t count, bool count_defined, uint32_t tla);

    // ---- callers ------------------------------------------------------------
    // The call sites which called me:  derived, transient, parent-only, and
    // cross-file, so it is not part of the port.  It is held as an opaque
    // handle to a Perl value (an AV of [entry, line, column, ordinal, count]
    // rows), because a C++ version would be a graph of cross-file pointers
    // inside objects whose whole contract is that they serialize independently
    // -- and because the entries in it are kept alive by the Perl reference
    // count, exactly as they are in the pure-Perl implementation.
    //
    // null means "not resolved".  Serialization never carries it:  a thawed
    // alias is unresolved, which is the truth about it (TraceFile::serialize
    // refuses to run at all once the report is resolved).
    void* callers() const;
    // Takes ownership;  releases whatever was held before.
    void set_callers(void* handle);

private:
    void release_callers();

    uint32_t name_;
    bool     differential_;
    bool     count_defined_;
    bool     external_;
    uint32_t tla_;
    int64_t  count_;
    int64_t  external_calls_;
    std::unique_ptr<MergedNames> merged_;
    void*                        callers_;
};

// ============================================================================
// FunctionEntry
//
// All the aliases of one function -- the same function, perhaps templatized or
// cloned differently -- plus the call sites in its body.
//
// The aliases live in an unordered_map keyed by interned name.  Not a sorted
// vector, even though nearly every function has exactly one alias and a vector
// would save the map's overhead:  a Perl FunctionAlias object borrows a pointer
// into this container, and TraceFile::resolveCallSites holds one of those
// borrows for every symbol in the report while it walks every call site.  A
// vector reallocating on a later insert would invalidate all of them;
// unordered_map guarantees reference stability across insert and rehash.
//
// The file is held as an interned filename rather than as a pointer back to the
// owning FunctionMap, which is what pure Perl's MAP slot is.  Three reasons:
// genhtml creates entries which are not in any map (the differential clones of
// '_cloneFunctionEntry') and then serializes them, so a back pointer would
// either dangle or drag a whole FunctionMap through the fork;  a back pointer
// to the map an entry is stored in is a cycle for any refcounting scheme;  and
// nothing ever changes a FunctionMap's filename after it is constructed, so
// there is no state to keep in step.
// ============================================================================

class FunctionEntry
{
public:
    FunctionEntry(uint32_t name, uint32_t file, int32_t first, int32_t last,
                  bool has_last);

    // Move-only for the same reason FunctionAlias is:  the aliases it holds
    // are.  The copy is the XS layer's 'cloneWithEndLine', which builds a new
    // entry and appends the aliases it keeps;  nothing moves an entry, because
    // every entry lives in a shared_ptr.
    FunctionEntry(FunctionEntry&&) noexcept            = default;
    FunctionEntry& operator=(FunctionEntry&&) noexcept = default;
    FunctionEntry(const FunctionEntry&)                = delete;
    FunctionEntry& operator=(const FunctionEntry&)     = delete;

    // My name is one of my aliases:  it is set when I am built and re-elected by
    // 'choose_name' when that alias is removed, so there is no setter for it.
    uint32_t           name_id() const;
    const std::string& name() const;

    uint32_t           file_id() const;
    const std::string& filename() const;

    // The hit count across all my aliases.  A differential entry carries a TLA
    // beside it, as an alias does.
    int64_t  hit() const;
    void     set_hit(int64_t count);
    bool     is_differential() const;
    uint32_t tla_id() const;
    void     set_differential(int64_t count, uint32_t tla);
    // Recategorize:  genhtml rewrites the TLA of an already differential entry
    // when '--show-details' remaps the categories.  A non-differential entry has
    // nowhere to put it, and lcovutil.pm raises the die pure Perl raises.
    void set_tla(uint32_t tla);

    // Whether at least one call from my body went to a function outside the
    // boundary of the report -- what the 'c' flag of an 'FNL:' record asserts.
    // The per-function mirror of FunctionAlias::has_external_callers, and
    // set-only for the same reason:  the site the call was recorded at is gone,
    // so this is the only record that the call was made.  Pure Perl's
    // FunctionEntry::has_external_callees spells out which calls those are.
    bool has_external_callees() const;
    void set_external_callees();

    int32_t line() const;
    void    set_line(int32_t line);
    bool    has_end_line() const;
    int32_t end_line() const;
    // The unchecked mutator:  'set_end_line' in lcovutil.pm does the
    // end-before-start check and the diagnostic, then calls this.
    void set_end_line(int32_t line);
    void clear_end_line();

    // ---- aliases ------------------------------------------------------------

    std::size_t              numAliases() const;
    FunctionAlias*           alias(uint32_t name);
    std::vector<uint32_t>    aliasNames() const;

    // Add 'count' to the alias of this name, creating it if it is new, and
    // maintain both the aggregate count and the choice of representative name.
    // Returns true if this changed my coverage state, in the sense pure Perl's
    // addAlias means it:  a new alias, or one which was not hit and now is.
    bool addAliasCount(uint32_t name, int64_t count);

    // Make (or find) an alias and give it a differential (count, TLA) pair.
    // Returns false if the name is a pre-existing alias other than my own
    // representative name, which pure Perl treats as a caller bug.
    bool addAliasDifferential(uint32_t name, int64_t count, bool count_defined,
                              uint32_t tla);

    // Remove these aliases, adjusting the aggregate count and choosing a new
    // representative name if the old one went away.  Returns true if I still
    // have any alias left -- pure Perl's "this function still exists".
    // A name which is not an alias of mine is a caller bug:  it is reported
    // through 'missing' rather than ignored, and the caller raises the die
    // pure Perl raises.
    // The names also leave the alias set of every site, and a site which only
    // they made goes with them -- as pure Perl's removeAliases does.
    bool removeAliases(const std::vector<uint32_t>& names, uint32_t* missing);

    // Install an alias exactly as it was recorded, with no name election and no
    // adjustment of my aggregate count:  for thaw and for cloning, both of
    // which carry the name and the total they want separately.
    void appendAliasRaw(uint32_t name, int64_t count, bool count_defined,
                        bool differential, uint32_t tla,
                        bool    external       = false,
                        int64_t external_calls =
                            FunctionAlias::NO_EXTERNAL_CALLS,
                        const FunctionAlias::MergedNames* merged = nullptr);

    // ---- call sites ---------------------------------------------------------

    std::size_t numCallSites() const;
    std::size_t numCallSitesHit() const;

    const CallSiteList& callSites() const;

    // The ordinal is int32_t here, and in the mutators below, although a site
    // holds a uint16_t:  what Perl hands down is whatever was in the data, and a
    // lookup for an ordinal no site can hold has to miss rather than wrap into
    // one which can.
    // 'file' is the interned name of the file the call is written in, and 0 for
    // the site of a call written in the function's own file - see CallSite.
    // The const overload is the pair of the mutable one and is not reachable
    // from the XS layer:  every binding which looks a site up holds a mutable
    // entry, so overload resolution never picks it.
    CallSite*       findCallSite(int32_t line, int32_t column, int32_t ordinal,
                                 uint32_t file = 0);
    const CallSite* findCallSite(int32_t line, int32_t column, int32_t ordinal,
                                 uint32_t file = 0) const;

    // The sites at this exact (line, column), whatever file each is written in,
    // as [first, last):  contiguous, because the list is sorted by line and
    // column first.  For '_sitesAt' in lcovutil.pm, which a merge calls once
    // for every ordinal it has to resolve - so a function with thousands of
    // sites must not pay a pass over all of them each time.
    std::pair<CallSite*, CallSite*> callSitesAt(int32_t line, int32_t column);

    // The ordinal a site from another input calling 'callee' at this exact
    // (line, column) of 'file' takes here:  that of my site calling the same
    // callee there if I have one, and otherwise the lowest ordinal I do not use
    // there.  '_resolveOrdinal' in lcovutil.pm, which says why;  here so that a
    // location with a thousand callees - a template instantiated a thousand
    // ways - is a walk over ids and not a thousand Perl pairs per call.
    int32_t resolveOrdinal(int32_t line, int32_t column, uint32_t file,
                           uint32_t callee);

    // Add one site, or merge into the site already at this location.  Returns
    // 1 if my data changed (a new site, or one which was not taken and now is),
    // 0 if it did not, and -1 if a site is already here calling something else
    // -- which is the mismatch lcovutil.pm reports, so it is answered rather
    // than diagnosed here.  An ordinal past MAX_CALLSITE_ORDINAL answers -2,
    // which lcovutil.pm reports as the die pure Perl raises for it.
    // 'aliases' is the interned alias set of the call (see CallSite);  a site
    // which is already here takes the union of its set and this one.
    // 'statement' is the statement offset (see CallSite);  a site which is
    // already here and has none takes this one.
    int addCallSite(int32_t line, int32_t column, int32_t ordinal, int64_t count,
                    uint32_t callee, uint32_t file = 0, uint32_t aliases = 0,
                    int8_t statement = 0);

    // Drop the site at this location.  Returns true if there was one.
    bool removeCallSite(int32_t line, int32_t column, int32_t ordinal,
                        uint32_t file = 0);

    // Append a site with no merge and no ordering check, and make room for
    // 'n' of them first:  for thaw, which reads back a list this class wrote in
    // order and whose length it knows before it starts.
    void reserveCallSites(std::size_t n);
    void appendCallSiteRaw(const CallSite& site);

    // Aliases, for serialization and for anything which must visit them all.
    // A visitor rather than a container reference:  the container is an
    // implementation choice, and handing out a Perl copy of it is the mistake
    // MCDC_Block::groups() was.
    template <class F> void for_each_alias(F&& f)
    {
        for (auto& kv : aliases_)
            f(kv.first, kv.second);
    }
    template <class F> void for_each_alias(F&& f) const
    {
        for (const auto& kv : aliases_)
            f(kv.first, kv.second);
    }

private:
    // The alias name to represent the whole function:  the shortest, ties
    // broken lexically, with lambdas penalized so that a lambda is chosen only
    // when every alias is one.  Mirrors the arithmetic in pure Perl's addAlias
    // and removeAliases, which is why the penalty is spelled out rather than
    // folded into a comparison.
    static std::size_t name_rank(const std::string& name);
    void               choose_name();

    CallSite* find_site(int32_t line, int32_t column, int32_t ordinal,
                        uint32_t file);

    uint32_t name_;
    uint32_t file_;
    bool     differential_;
    bool     has_last_;
    bool     external_callees_;
    uint32_t tla_;
    int32_t  first_;
    int32_t  last_;
    int64_t  count_;

    std::unordered_map<uint32_t, FunctionAlias> aliases_;
    // Sorted by (line, column, ordinal);  every mutator preserves the order.
    CallSiteList calls_;
};

// ============================================================================
// FunctionMap
//
// The functions of one file, by start line and by name.
//
// Both maps hold a shared_ptr, which is what pure Perl's two references to the
// same blessed arrayref are:  'FunctionMap::difference' removes an entry from
// the line map and leaves the name map pointing at it, and that entry must stay
// alive and reachable by name.  A unique owner plus raw pointers would dangle
// there.
// ============================================================================

class FunctionMap
{
public:
    explicit FunctionMap(uint32_t file);

    uint32_t           file_id() const;
    const std::string& filename() const;

    std::vector<int32_t>  keylist() const;
    std::vector<uint32_t> list_functions() const;

    // The owning pointer, or a null one when there is no such entry.  A
    // reference to what is stored rather than a copy, so that a lookup costs no
    // reference count -- but a caller which hands the entry to Perl copies it,
    // because a Perl object which borrows an entry has to keep it alive (see the
    // identity cache in the XS layer).
    const std::shared_ptr<FunctionEntry>& findKey(int32_t line) const;
    const std::shared_ptr<FunctionEntry>& findName(uint32_t name) const;

    // Create an entry and store it under 'first'.  The caller has already
    // established that no entry is there (define_function does the diagnostics).
    const std::shared_ptr<FunctionEntry>& insert(uint32_t name, int32_t first,
                                                 int32_t last, bool has_last);

    void registerName(uint32_t name, FunctionEntry* entry);
    bool unregisterName(uint32_t name);
    bool removeKey(int32_t line);

    // Move an entry to a new start line, keeping it alive across the move.
    // Returns false if it is not in my line map under its current line.
    bool relocate(FunctionEntry* entry, int32_t line);

    // ---- totals -------------------------------------------------------------
    // 'merged' is '--filter function_alias' asking for one function per
    // location rather than one per alias;  lcovutil.pm reads the filter list
    // and passes the answer in.
    int64_t numFunc(bool merged) const;
    int64_t numHit(bool merged) const;

    std::pair<int64_t, int64_t> callgraph_found_and_hit() const;

    // ---- raw access, for serialization and iteration -------------------------

    const std::unordered_map<int32_t, std::shared_ptr<FunctionEntry>>&
    byLine() const
    {
        return byLine_;
    }
    const std::unordered_map<uint32_t, std::shared_ptr<FunctionEntry>>&
    byName() const
    {
        return byName_;
    }

    // Thaw support:  take a ready-made entry rather than build one.
    void insertEntry(int32_t line, std::shared_ptr<FunctionEntry> entry);
    void registerEntryName(uint32_t name, std::shared_ptr<FunctionEntry> entry);

private:
    uint32_t                                                   file_;
    std::unordered_map<int32_t, std::shared_ptr<FunctionEntry>> byLine_;
    std::unordered_map<uint32_t, std::shared_ptr<FunctionEntry>> byName_;
};

// When LCOV_XS_INLINE is defined, include the implementation file
// to make all methods inline
#ifdef LCOV_XS_INLINE
#include "FunctionData.cpp"
#endif
