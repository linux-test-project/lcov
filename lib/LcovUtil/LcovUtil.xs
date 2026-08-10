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

/*
 * LcovUtil.xs -- C++ acceleration for the lcovutil coverage-data classes:
 * MapData, CountData, BranchElement, BranchBlock, BranchLocation, BranchData,
 * MCDC_Block, MCDC_Expression, and MCDC_Data.
 *
 * Each is a blessed scalar whose inner IV points to a C++ object (or a
 * wrapper around one); the XS methods operate directly on that object.  The
 * classes mirror their pure-Perl counterparts in lcovutil.pm exactly,
 * including STORABLE_freeze/thaw hooks.  These hooks use a compact binary wire
 * format that is NOT interchangeable with the pure-Perl Storable layout;
 * serialized data is only ever read back by the same build within one run
 * (parallel-merge IPC, Storable::dclone), so no cross-build portability is
 * required.  TraceFile::deserialize guards against an accidental cross-build
 * read and reports ERROR_FORMAT.
 */

#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

#include <string>
#include <unordered_map>
#include <vector>
#include <algorithm>
#include <stdexcept>
#include <climits>
#include <optional>
#include <utility>
#include "BranchData.hpp"
#include "MCDCData.hpp"
#include "BinarySerializer.hpp"

/* -------------------------------------------------------------------------
 * MapData
 *
 * Pure-Perl: blessed hashref  {}
 * XS: blessed scalar ref to a C++ object pointer (IV/ptr trick).
 *
 * We store the C++ object as an opaque pointer inside the Perl object.
 * The Perl object is blessed into "MapData".
 * ------------------------------------------------------------------------- */

struct MapData_impl {
    // key -> arbitrary SV* (reference-counted)
    std::unordered_map<std::string, SV*> data;

    ~MapData_impl() {
        for (auto& kv : data) {
            SvREFCNT_dec(kv.second);
        }
    }
};

/* -------------------------------------------------------------------------
 * CountData
 *
 * Pure-Perl: blessed arrayref  [{}, sortable, found, hit, filename]
 * Slots: HASH=0, SORTABLE=1, FOUND=2, HIT=3, FILENAME=4
 * ------------------------------------------------------------------------- */

struct CountData_impl {
    /* line -> count, held in a vector kept sorted by line rather than a hash.
     * Line counts are the highest-volume structure in a capture, so the layout
     * dominates memory: 16 contiguous bytes per entry here, against a hash node
     * plus bucket slot plus one allocation per line.
     *
     * The runtime trade is favourable in practice even though a point lookup
     * goes O(1) average -> O(log n): geninfo appends in increasing line order,
     * so the common insert is an amortized O(1) push_back; the dominant
     * scan/merge paths get contiguous access instead of a pointer chase; and
     * iteration now comes out sorted, which is what every caller already
     * wanted (lcovutil.pm sorts keylist() at five sites).
     *
     * Order is an invariant, not an accident -- every mutator below preserves
     * it, because find() binary-searches. */
    typedef std::vector<std::pair<int, long long> > Map;

    Map         data;
    int         sortable;
    long long   found;
    long long   hit;
    std::string filename;

    CountData_impl(const std::string& fn, int s)
        : sortable(s), found(0), hit(0), filename(fn) {}

    static bool key_less(const std::pair<int, long long>& e, int k) {
        return e.first < k;
    }

    /* Iterator to key k, or data.end() if absent. */
    Map::iterator find(int k) {
        Map::iterator it = std::lower_bound(data.begin(), data.end(), k, key_less);
        return (it != data.end() && it->first == k) ? it : data.end();
    }

    /* Insert a key known to be absent, keeping the vector sorted.  The
     * append-at-the-end case is checked first because it is the one geninfo
     * takes for nearly every line it parses. */
    Map::iterator insert_new(int k, long long v) {
        if (data.empty() || data.back().first < k) {
            data.push_back(std::make_pair(k, v));
            return data.end() - 1;
        }
        Map::iterator it =
            std::lower_bound(data.begin(), data.end(), k, key_less);
        return data.insert(it, std::make_pair(k, v));
    }
};

/* =========================================================================
 * Helper: extract C++ pointer from a blessed reference
 * ========================================================================= */

static MapData_impl* sv_to_mapdata(SV* sv) {
    if (!sv || !SvROK(sv))
        croak("MapData: not a reference");
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        croak("MapData: invalid object (not IV)");
    return (MapData_impl*)(intptr_t)SvIV(inner);
}

static CountData_impl* sv_to_countdata(SV* sv) {
    if (!sv || !SvROK(sv))
        croak("CountData: not a reference");
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        croak("CountData: invalid object (not IV)");
    return (CountData_impl*)(intptr_t)SvIV(inner);
}

/* =========================================================================
 * Storable freeze/thaw helpers (called from XS STORABLE_freeze/thaw subs)
 * ========================================================================= */

/* Freeze MapData into a Perl hashref: {key => value, ...}
 * Values are arbitrary SVs (already Perl values).
 */
static SV* mapdata_freeze(MapData_impl* impl) {
    HV* hv = newHV();
    for (auto& kv : impl->data) {
        SvREFCNT_inc(kv.second);
        hv_store(hv, kv.first.c_str(), kv.first.size(), kv.second, 0);
    }
    return newRV_noinc((SV*)hv);
}

/* Thaw MapData from a hashref */
static MapData_impl* mapdata_thaw(SV* frozen) {
    if (!SvROK(frozen))
        croak("MapData STORABLE_thaw: expected reference");
    HV* hv = (HV*)SvRV(frozen);
    if (SvTYPE((SV*)hv) != SVt_PVHV)
        croak("MapData STORABLE_thaw: expected hashref");

    MapData_impl* impl = new MapData_impl();
    hv_iterinit(hv);
    HE* entry;
    while ((entry = hv_iternext(hv)) != NULL) {
        STRLEN klen;
        const char* key = HePV(entry, klen);
        SV* val = HeVAL(entry);
        SvREFCNT_inc(val);
        impl->data[std::string(key, klen)] = val;
    }
    return impl;
}

/* =========================================================================
 * Binary Serialization
 *
 * Binary format for CountData (version 1):
 *   [MAGIC:4]     'CDAT'
 *   [VERSION:4]   uint32 = 1
 *   [FILENAME_LEN:4] [FILENAME:N]
 *   [SORTABLE:4]  int32
 *   [FOUND:8]     int64
 *   [HIT:8]       int64
 *   [NUM_ENTRIES:4] uint32
 *   [ENTRY:12] x num_entries
 *      [KEY:4]    int32 (line number)
 *      [VALUE:8]  int64 (count)
 *
 * Total size: ~32 bytes header + filename_len + (12 x num_entries)
 * ========================================================================= */

/* Serialize CountData to binary format */
static SV* countdata_serialize_binary(CountData_impl* impl) {
    using namespace lcov_binary;
    BinaryWriter w;

    // Estimate size and reserve
    size_t est_size = 32 + impl->filename.size() + (impl->data.size() * 12);
    w.reserve(est_size);

    // Header
    w.write_bytes("CDAT", 4);
    w.write_u32(1);  // version

    // Metadata
    w.write_string(impl->filename);
    w.write_i32(impl->sortable);
    w.write_i64(impl->found);
    w.write_i64(impl->hit);

    // Entries
    w.write_u32(static_cast<uint32_t>(impl->data.size()));
    for (const auto& kv : impl->data) {
        w.write_i32(kv.first);
        w.write_i64(kv.second);
    }

    // Return as Perl scalar (byte string)
    const std::vector<uint8_t>& buf = w.data();
    return newSVpvn(reinterpret_cast<const char*>(buf.data()), buf.size());
}

/* Deserialize CountData from binary format */
static CountData_impl* countdata_deserialize_binary(const uint8_t* data, size_t len) {
    using namespace lcov_binary;

    try {
        BinaryReader r(data, len);

        // Verify magic and version
        r.verify_magic("CDAT");
        uint32_t version = r.read_u32();
        if (version != 1) {
            croak("CountData: unsupported binary version %u", version);
        }

        // Read metadata
        std::string filename = r.read_string();
        int32_t sortable = r.read_i32();
        int64_t found = r.read_i64();
        int64_t hit = r.read_i64();

        // Create object
        CountData_impl* impl = new CountData_impl(filename, sortable);
        impl->found = found;
        impl->hit = hit;

        // Read entries
        uint32_t num_entries = r.read_u32();
        impl->data.reserve(num_entries);

        /* serialize_binary() walks the sorted vector, so the stream is already
         * in increasing line order and each entry appends.  Do not assume it:
         * a stream is only ever read back by the same build, but sorting a
         * nearly-sorted vector once is far cheaper than losing the invariant
         * find() depends on. */
        bool sorted = true;
        for (uint32_t i = 0; i < num_entries; ++i) {
            int32_t key = r.read_i32();
            int64_t value = r.read_i64();
            if (!impl->data.empty() && impl->data.back().first >= key)
                sorted = false;
            impl->data.push_back(std::make_pair((int)key, (long long)value));
        }
        if (!sorted) {
            std::sort(impl->data.begin(), impl->data.end());
            impl->data.erase(std::unique(impl->data.begin(), impl->data.end(),
                                         [](const std::pair<int, long long>& a,
                                            const std::pair<int, long long>& b) {
                                             return a.first == b.first;
                                         }),
                             impl->data.end());
        }

        return impl;

    } catch (const std::exception& e) {
        croak("CountData binary deserialization failed: %s", e.what());
    }

    // Unreachable, but silence compiler warning
    return nullptr; /* LCOV_UNREACHABLE_LINE */
}

/* =========================================================================
 * BranchData binary serialization
 *
 * Flat little-endian buffer -- the single serialization format for branch
 * data, carrying every field without allocating a Perl SV per element.  All
 * Storable freeze/thaw hooks (the top-level BranchData container AND the
 * per-object BranchElement/BranchBlock/BranchLocation hooks) route through
 * these read/write helpers, so both the parallel-merge IPC hand-off and the
 * per-object serialization of a differentiated graph avoid the generic
 * Storable object walk.  Serialized data never crosses between a pure-Perl and
 * an XS build within one run, so this single binary format suffices.
 *
 * Format (version 1):
 *   [MAGIC:4]   'BDAT'
 *   [VERSION:4] uint32 = 1
 *   [FOUND:8]   int64      (informational; recomputed on thaw)
 *   [HIT:8]     int64
 *   [NUM_LOC:4] uint32
 *     per location:
 *       [MAPKEY:4]   int32   (data_ map key)
 *       [LOC_LINE:4] int32   (BranchLocation::line())
 *       [LABEL:str]          (line_label(); empty => plain numeric line)
 *       [NUM_BLK:4]  uint32  (blocks in blocks(false) order)
 *         per block:
 *           [NUM_ELEM:4] uint32
 *             per element:
 *               [ID:4]    int32
 *               [TAKEN:8] int64   (DASH == INT64_MIN sentinel preserved)
 *               [EXPR:str]
 *               [TYPE:1]  uint8
 *               [EXCL:1]  uint8
 *               [DIFF:1]  uint8
 *               if DIFF:
 *                 [TLA:str][BASE:8 int64][CURR:8 int64]
 * ========================================================================= */

static void branchelement_write(lcov_binary::BinaryWriter& w, const BranchElement* e) {
    w.write_i32(e->id());
    w.write_i64(e->data());          /* taken; DASH sentinel round-trips */
    w.write_string(e->expr());
    w.write_u8(static_cast<uint8_t>(e->type()));
    w.write_u8(e->isExcluded() ? 1 : 0);
    /* Differential elements (TLA + [base,curr]) are produced by genhtml's
     * report-categorization stage (set_differential(), bin/genhtml cloneBlock)
     * and then serialized when the parallel workers hand a differentiated
     * BranchLocation graph back to the parent.  That per-object serialization
     * routes through this same binary codec (BranchElement::STORABLE_freeze ->
     * branchelement_write), so this arm is live -- heavily exercised in the
     * genhtml differential tests, and directly by
     * tests/lcov/serialization/binary.sh.  The top-level BranchData container
     * serialization (parallel-merge IPC, Storable::dclone) runs on
     * pre-differential data, so its elements simply take the else-branch. */
    if (e->isDifferential()) {
        w.write_u8(1);
        w.write_string(e->tla());
        /* base and curr are independently optional (an undef base means "not in
         * the baseline"), so each carries its own presence flag rather than
         * being flattened to 0. */
        w.write_u8(e->hasBase() ? 1 : 0);
        w.write_i64(e->base());
        w.write_u8(e->hasCurr() ? 1 : 0);
        w.write_i64(e->curr());
    } else {
        w.write_u8(0);
    }
}

static BranchElement branchelement_read(lcov_binary::BinaryReader& r) {
    int32_t id = r.read_i32();
    int64_t taken = r.read_i64();
    std::string expr = r.read_string();
    BranchElement::Type type = static_cast<BranchElement::Type>(r.read_u8());
    bool excluded = r.read_u8() != 0;
    BranchElement e(id, taken, std::move(expr), type, excluded);
    /* Reads the differential flag written by branchelement_write.  Live for
     * the per-object serialization of a differentiated graph (see the note in
     * branchelement_write). */
    if (r.read_u8()) {
        std::string tla = r.read_string();
        bool has_base = r.read_u8() != 0;
        int64_t base  = r.read_i64();
        bool has_curr = r.read_u8() != 0;
        int64_t curr  = r.read_i64();
        e.set_differential(std::move(tla),
                           has_base ? std::optional<int64_t>(base) : std::nullopt,
                           has_curr ? std::optional<int64_t>(curr) : std::nullopt);
    }
    return e;
}

static void branchblock_write(lcov_binary::BinaryWriter& w, const BranchBlock* b) {
    const auto& elems = b->elements();
    w.write_u32(static_cast<uint32_t>(elems.size()));
    for (const auto& e : elems)
        branchelement_write(w, &e);
}

static BranchBlock branchblock_read(lcov_binary::BinaryReader& r) {
    /* idx is auto-assigned by BranchLocation::insertBlock and the signature is
     * derived from the elements on demand, so neither is stored. */
    BranchBlock b;
    uint32_t n = r.read_u32();
    b.reserveElements(n);
    for (uint32_t i = 0; i < n; ++i)
        b.appendElement(branchelement_read(r));
    return b;
}

static void branchlocation_write(lcov_binary::BinaryWriter& w, BranchLocation* loc) {
    w.write_i32(loc->line());
    w.write_string(loc->line_label());
    std::vector<BranchBlock*> blocks = loc->blocks(false);
    w.write_u32(static_cast<uint32_t>(blocks.size()));
    for (BranchBlock* b : blocks)
        branchblock_write(w, b);
}

/* Symmetric with branchlocation_write.  The map key (present in the BranchData
 * container stream) is NOT part of a location's own payload, so it is read by
 * the caller, not here -- matching branchlocation_write, which does not emit it. */
static BranchLocation branchlocation_read(lcov_binary::BinaryReader& r) {
    int32_t loc_line = r.read_i32();
    std::string label = r.read_string();
    BranchLocation loc(loc_line);
    if (!label.empty())
        loc.set_line_label(std::move(label));
    uint32_t nblk = r.read_u32();
    loc.reserveBlocks(nblk);
    for (uint32_t bi = 0; bi < nblk; ++bi)
        loc.insertBlock(branchblock_read(r));
    return loc;
}

static SV* branchdata_serialize_binary(BranchData* bd) {
    using namespace lcov_binary;
    BinaryWriter w;

    w.write_bytes("BDAT", 4);
    w.write_u32(1);
    auto [found, hit] = bd->get_found_and_hit();
    w.write_i64(found);
    w.write_i64(hit);

    auto& data = bd->data();
    w.write_u32(static_cast<uint32_t>(data.size()));
    for (auto& kv : data) {
        w.write_i32(kv.first);
        branchlocation_write(w, &kv.second);
    }

    const std::vector<uint8_t>& buf = w.data();
    return newSVpvn(reinterpret_cast<const char*>(buf.data()), buf.size());
}

static BranchData* branchdata_deserialize_binary(const uint8_t* data, size_t len) {
    using namespace lcov_binary;

    try {
        BinaryReader r(data, len);
        r.verify_magic("BDAT");
        uint32_t version = r.read_u32();
        if (version != 1)
            croak("BranchData: unsupported binary version %u", version);

        (void)r.read_i64();   /* found -- recomputed below */
        (void)r.read_i64();   /* hit */

        BranchData* bd = new BranchData();
        uint32_t nloc = r.read_u32();
        for (uint32_t i = 0; i < nloc; ++i) {
            int32_t key = r.read_i32();
            bd->data().try_emplace(key, branchlocation_read(r));
        }
        bd->updateCounts();
        return bd;

    } catch (const std::exception& e) {
        croak("BranchData binary deserialization failed: %s", e.what());
    }
    return nullptr;
}

/* =========================================================================
 * MCDC_Data binary serialization
 *
 * Same idea as BranchData: a single flat-buffer format used by every Storable
 * hook (the MCDC_Data container and the per-object MCDC_Block hook alike).
 * Per-sense differential data preserves the independent base/curr "defined"
 * flags so the round trip is lossless.
 *
 * Format (version 1):
 *   [MAGIC:4]   'MDAT'
 *   [VERSION:4] uint32 = 1
 *   [FOUND:8][HIT:8]        (informational; recomputed on thaw)
 *   [NUM_BLK:4] uint32
 *     per block:
 *       [MAPKEY:4]   int32
 *       [BLK_LINE:4] int32
 *       [LABEL:str]
 *       [NUM_GRP:4]  uint32
 *         per group:
 *           [GROUP_SIZE:4] int32
 *           [NUM_EXPR:4]   uint32
 *             per expr:
 *               [GS:4][IDX:4][EXPR:str][EXCL0:1][EXCL1:1]
 *               per sense (0,1):
 *                 [IS_DIFF:1]
 *                 if diff: [TLA:str][HAS_BASE:1][BASE:8][HAS_CURR:1][CURR:8]
 *                 else:    [COUNT:8 int64]
 * ========================================================================= */

static void mcdcexpr_write(lcov_binary::BinaryWriter& w, const MCDC_Expression* e) {
    w.write_i32(e->groupSize());
    w.write_i32(e->index());
    w.write_string(e->expression());
    w.write_u8(e->is_excluded(0) ? 1 : 0);
    w.write_u8(e->is_excluded(1) ? 1 : 0);
    for (int s = 0; s < 2; ++s) {
        /* Like branchelement_write's isDifferential() arm, this branch is live
         * for the per-object serialization of a differentiated graph: a
         * per-sense [tla, base, curr] is attached by genhtml's report-
         * categorization stage (insertExpr with an arrayref count) and then
         * serialized when the differentiated MCDC_Block is handed back via
         * MCDC_Block::STORABLE_freeze -> mcdcblock_write -> mcdcexpr_write.  The
         * top-level MCDC_Data container serialization (parallel-merge IPC,
         * Storable::dclone) runs on pre-differential data, taking the else-arm.
         * Both arms are exercised by tests/lcov/serialization/binary.sh. */
        if (e->isDifferential(s)) {
            w.write_u8(1);
            w.write_string(e->tla(s));
            bool hb = e->hasBase(s), hc = e->hasCurr(s);
            w.write_u8(hb ? 1 : 0);
            w.write_i64(hb ? e->base(s) : 0);
            w.write_u8(hc ? 1 : 0);
            w.write_i64(hc ? e->curr(s) : 0);
        } else {
            w.write_u8(0);
            w.write_i64(e->count(s));
        }
    }
}

static MCDC_Expression mcdcexpr_read(lcov_binary::BinaryReader& r) {
    int32_t gs = r.read_i32();
    int32_t idx = r.read_i32();
    std::string expr = r.read_string();
    bool excl[2];
    excl[0] = r.read_u8() != 0;
    excl[1] = r.read_u8() != 0;
    MCDC_Expression e(gs, idx, expr);
    for (int s = 0; s < 2; ++s) {
        /* Reads the per-sense differential flag written by mcdcexpr_write.
         * Live for the per-object serialization of a differentiated graph (see
         * the note in mcdcexpr_write). */
        if (r.read_u8()) {
            std::string tla = r.read_string();
            bool has_base = r.read_u8() != 0;
            int64_t base = r.read_i64();
            bool has_curr = r.read_u8() != 0;
            int64_t curr = r.read_i64();
            /* Seed the count from 'curr' when defined. */
            e.set(s, has_curr ? curr : 0, excl[s]);
            if (has_base && has_curr)
                e.set_differential(s, tla, base, curr);
            else
                e.set_tla(s, tla);
        } else {
            int64_t count = r.read_i64();
            e.set(s, count, excl[s]);
        }
    }
    return e;
}

static void mcdcblock_write(lcov_binary::BinaryWriter& w, const MCDC_Block* b) {
    w.write_i32(b->line());
    w.write_string(b->line_label());
    w.write_u32(static_cast<uint32_t>(b->num_groups()));
    b->for_each_group([&](int32_t gs,
                          const std::vector<MCDC_Expression>& exprs) {
        w.write_i32(gs);
        w.write_u32(static_cast<uint32_t>(exprs.size()));
        for (const auto& e : exprs)
            mcdcexpr_write(w, &e);
    });
}

static MCDC_Block* mcdcblock_read(lcov_binary::BinaryReader& r) {
    int32_t line = r.read_i32();
    std::string label = r.read_string();
    MCDC_Block* block = new MCDC_Block(line);
    if (!label.empty())
        block->set_line_label(std::move(label));
    uint32_t ng = r.read_u32();
    for (uint32_t g = 0; g < ng; ++g) {
        int32_t gs = r.read_i32();
        uint32_t ne = r.read_u32();
        auto& vec = block->find_or_create_group(gs);
        vec.resize(ne);
        for (uint32_t i = 0; i < ne; ++i)
            vec[i] = mcdcexpr_read(r);
    }
    return block;
}

static SV* mcdcdata_serialize_binary(MCDC_Data* md) {
    using namespace lcov_binary;
    BinaryWriter w;

    w.write_bytes("MDAT", 4);
    w.write_u32(1);
    auto [found, hit] = md->get_found_and_hit();
    w.write_i64(found);
    w.write_i64(hit);

    auto& data = md->data();
    w.write_u32(static_cast<uint32_t>(data.size()));
    for (auto& kv : data) {
        w.write_i32(kv.first);
        mcdcblock_write(w, &kv.second);
    }

    const std::vector<uint8_t>& buf = w.data();
    return newSVpvn(reinterpret_cast<const char*>(buf.data()), buf.size());
}

static MCDC_Data* mcdcdata_deserialize_binary(const uint8_t* data, size_t len) {
    using namespace lcov_binary;

    try {
        BinaryReader r(data, len);
        r.verify_magic("MDAT");
        uint32_t version = r.read_u32();
        if (version != 1)
            croak("MCDC_Data: unsupported binary version %u", version);

        (void)r.read_i64();   /* found -- recomputed below */
        (void)r.read_i64();   /* hit */

        MCDC_Data* md = new MCDC_Data();
        uint32_t nblk = r.read_u32();
        for (uint32_t i = 0; i < nblk; ++i) {
            int32_t key = r.read_i32();
            MCDC_Block* block = mcdcblock_read(r);
            md->data().try_emplace(key, std::move(*block));
            delete block;
        }
        md->recalculate_counts();
        return md;

    } catch (const std::exception& e) {
        croak("MCDC_Data binary deserialization failed: %s", e.what());
    }
    return nullptr;
}

/* =========================================================================
 * BranchElement, BranchBlock, BranchLocation
 * C++ structs accessed via IV pointer (same pattern as MapData/CountData).
 * ========================================================================= */

/* BranchElement -- value type, copyable, no heap-allocated Perl SVs.
 * id and expr are stored as std::string so the struct can live directly
 * inside BranchBlock::elements (a vector<BranchElement>).
 * No Perl IV scalar is allocated per element during storage.
 *
 * taken_str retains the original string form for Storable round-trips and
 * for the data() / isTaken() accessors that pure-Perl callers rely on.
 */
/* Extract the C++ pointer from a BranchElement SV.
 * Clears the borrowed-tag bit (bit 1) before casting. */
static BranchElement* sv_to_branchelement(SV* sv) {
    if (!sv || !SvROK(sv))
        croak("BranchElement: not a reference");
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        croak("BranchElement: invalid object (not IV)");
    return (BranchElement*)((intptr_t)SvIV(inner) & ~(intptr_t)1);
}

/* Returns true when this SV is a borrowed (non-owning) wrapper.
 * The lsb of the IV is set to 1 for borrowed wrappers. */
static bool branchelement_is_borrowed(SV* sv) {
    if (!sv || !SvROK(sv))
        return false;
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        return false;
    return ((intptr_t)SvIV(inner) & 1) != 0;
}

static bool branchblock_is_borrowed(SV* sv) {
    if (!sv || !SvROK(sv))
        return false;
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        return false;
    return ((intptr_t)SvIV(inner) & 1) != 0;
}

static BranchBlock* sv_to_branchblock(SV* sv) {
    if (!sv || !SvROK(sv))
        croak("BranchBlock: not a reference");
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        croak("BranchBlock: invalid object (not IV)");
    return (BranchBlock*)((intptr_t)SvIV(inner) & ~(intptr_t)1);
}

static bool branchlocation_is_borrowed(SV* sv) {
    if (!sv || !SvROK(sv))
        return false;
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        return false;
    return ((intptr_t)SvIV(inner) & 1) != 0;
}

static BranchLocation* sv_to_branchlocation(SV* sv) {
    if (!sv || !SvROK(sv))
        croak("BranchLocation: not a reference");
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        croak("BranchLocation: invalid object (not IV)");
    return (BranchLocation*)((intptr_t)SvIV(inner) & ~(intptr_t)1);
}

static SV* make_branchelement_sv(BranchElement* impl, const char* klass) {
    SV* inner = newSViv((IV)(intptr_t)impl);
    SV* self  = newRV_noinc(inner);
    sv_bless(self, gv_stashpv(klass, GV_ADD));
    return self;
}

static SV* make_branchblock_sv(BranchBlock* impl, const char* klass) {
    SV* inner = newSViv((IV)(intptr_t)impl);
    SV* self  = newRV_noinc(inner);
    sv_bless(self, gv_stashpv(klass, GV_ADD));
    return self;
}

static SV* make_branchlocation_sv(BranchLocation* impl, const char* klass) {
    SV* inner = newSViv((IV)(intptr_t)impl);
    SV* self  = newRV_noinc(inner);
    sv_bless(self, gv_stashpv(klass, GV_ADD));
    return self;
}

/* iv_to_buf: decimal text for an IV, written into 'buf' (at least 24 bytes)
 * and returned as a pointer to its first character.  SvPV() on an integer SV
 * would instead make that SV grow a string buffer of its own - a malloc for
 * every 'BRDA:' record, since the reader hands the branch index in as a fresh
 * integer each time. */
static const char* iv_to_buf(IV v, char* buf, size_t bufsz, STRLEN& len)
{
    char* end = buf + bufsz;
    char* p   = end;
    /* negate through UV, so IV_MIN does not overflow */
    UV u = (v < 0) ? (UV)(-(v + 1)) + 1 : (UV)v;
    do {
        *--p = (char)('0' + (u % 10));
        u /= 10;
    } while (u);
    if (v < 0)
        *--p = '-';
    len = (STRLEN)(end - p);
    return p;
}

/* branch_id_text: the branch ID as bytes - for the '$expr eq $id' test in
 * BranchElement::new, and for the error messages below.  Returns NULL for an
 * undefined ID. */
static const char* branch_id_text(SV* id, char* buf, size_t bufsz, STRLEN& len)
{
    len = 0;
    if (!SvOK(id))
        return NULL;
    if (SvIOK(id) && !SvPOK(id))
        return iv_to_buf(SvIVX(id), buf, bufsz, len);
    return SvPV(id, len);
}

/* report_taken_error: hand one bad TAKEN value to lcovutil::report_format_error,
 * exactly as pure-Perl BranchElement::new does. */
static void report_taken_error(const char* err_name, SV* taken_sv,
                               const char* id_text, STRLEN id_len)
{
    dSP;
    SV* errType     = get_sv(err_name, 0);
    std::string loc = "branch ";
    if (id_text)
        loc.append(id_text, id_len);
    ENTER; SAVETMPS; PUSHMARK(SP);
    XPUSHs(errType ? errType : &PL_sv_undef);
    XPUSHs(sv_2mortal(newSVpvs("taken")));
    XPUSHs(taken_sv);
    XPUSHs(sv_2mortal(newSVpv(loc.c_str(), (STRLEN)loc.size())));
    PUTBACK; call_pv("lcovutil::report_format_error", G_DISCARD);
    FREETMPS; LEAVE;
}

/* excessive_taken: the '$c > $lcovutil::excessive_count_threshold' test. */
static void check_excessive_taken(double cnt_nv, SV* taken_sv,
                                  const char* id_text, STRLEN id_len)
{
    SV* thresh = get_sv("lcovutil::excessive_count_threshold", 0);
    if (thresh && SvOK(thresh) && cnt_nv > SvNV(thresh))
        report_taken_error("lcovutil::ERROR_EXCESSIVE_COUNT", taken_sv,
                           id_text, id_len);
}

/* validate_taken: shared TAKEN validation for BranchElement::new().
 * Matches pure-Perl behaviour:  '-' is "not evaluated", a non-number is an
 * ERROR_FORMAT and a negative count an ERROR_NEGATIVE (both then counting as
 * zero), and a count over the threshold is an ERROR_EXCESSIVE_COUNT which is
 * otherwise kept.
 *
 * 'looks_like_number' here is the perlapi function of that name - which is what
 * Scalar::Util::looks_like_number is a thin wrapper over - rather than a
 * call_pv() into Perl:  this runs once per branch coverpoint, so the call
 * overhead of reaching Perl to ask dominated the check itself.  Better still,
 * for the ordinary case of a non-negative integer written as text, grok_number()
 * both answers the question and hands back the value, so the digits are walked
 * once instead of three times (looks_like_number, then SvNV, then a double to
 * integer conversion). */
static long long validate_taken(const char* id_text, STRLEN id_len,
                                SV* taken_sv, bool& is_dash_out)
{
    is_dash_out = false;
    if (!SvOK(taken_sv))
        return 0;

    STRLEN      tlen = 0;
    const char* ts   = NULL;
    if (SvPOK(taken_sv) || SvMAGICAL(taken_sv)) {
        ts = SvPV(taken_sv, tlen);
        if (tlen == 1 && ts[0] == '-') { is_dash_out = true; return 0; }

        UV        uv;
        const int numtype = grok_number(ts, tlen, &uv);
        if (numtype == IS_NUMBER_IN_UV) {
            /* a plain non-negative integer which fits a UV:  no sign, no
             * fraction or exponent, no trailing junk, not Inf/NaN */
            check_excessive_taken((double)uv, taken_sv, id_text, id_len);
            return (uv > (UV)LLONG_MAX) ? LLONG_MAX : (long long)uv;
        }
        if (!numtype || (numtype & IS_NUMBER_TRAILING)) {
            report_taken_error("lcovutil::ERROR_FORMAT", taken_sv,
                               id_text, id_len);
            return 0;
        }
        /* negative, fractional or huge - fall through to the general path */
    } else if (!looks_like_number(taken_sv)) {
        report_taken_error("lcovutil::ERROR_FORMAT", taken_sv,
                           id_text, id_len);
        return 0;
    }

    double cnt_nv = SvNV(taken_sv);
    if (cnt_nv < 0.0) {
        report_taken_error("lcovutil::ERROR_NEGATIVE", taken_sv,
                           id_text, id_len);
        return 0;
    }
    check_excessive_taken(cnt_nv, taken_sv, id_text, id_len);
    return (cnt_nv >= (double)LLONG_MAX) ? LLONG_MAX : (long long)cnt_nv;
}

/* build_branchelement: the body of BranchElement::new(), as a value which the
 * caller either moves onto the heap (BranchElement::new) or straight into a
 * block's element vector (BranchBlock::appendNew).  'expr', 'type' and
 * 'excluded' may be NULL, for the short forms of that call. */
static BranchElement build_branchelement(SV* id, SV* taken, SV* expr,
                                         SV* type, SV* excluded)
{
    char        idbuf[24];
    STRLEN      id_len  = 0;
    const char* id_text = branch_id_text(id, idbuf, sizeof(idbuf), id_len);

    /* Parse ID.  Non-numeric IDs are rare (only in tests) and become 0. */
    int32_t id_int = 0;
    if (id_text) {
        if (SvIOK(id) && !SvPOK(id)) {
            id_int = (int32_t)SvIVX(id);
        } else {
            try {
                id_int = std::stoi(std::string(id_text, id_len));
            } catch (const std::exception&) {
                id_int = 0;
            }
        }
    }

    /* Parse EXPR.  An expression equal to the ID means "no expression" - the
     * '.info' writer emits the index there when there is nothing else. */
    std::string expr_str;
    if (expr && SvOK(expr)) {
        STRLEN      exlen;
        const char* exs = SvPV(expr, exlen);
        if (!(id_text && id_len == exlen && memcmp(id_text, exs, exlen) == 0))
            expr_str.assign(exs, exlen);
    }

    /* Parse TYPE */
    BranchElement::Type type_enum = BranchElement::VANILLA;
    if (type && SvOK(type)) {
        IV type_val = SvIV(type);
        if (type_val == 1)
            type_enum = BranchElement::EXCEPT;
        else if (type_val == 2)
            type_enum = BranchElement::FALLTHROUGH;
    }

    /* Parse EXCLUDED */
    bool excl = (excluded && SvOK(excluded) && SvTRUE(excluded));

    /* Validate taken count */
    bool      is_dash   = false;
    long long taken_int = validate_taken(id_text, id_len, taken, is_dash);
    int64_t   taken_val = is_dash ? BranchElement::DASH : taken_int;

    return BranchElement(id_int, taken_val, std::move(expr_str), type_enum,
                         excl);
}

/* Helper: make a Perl BranchElement SV for a copy of an element stored
 * inside a BranchBlock::elements vector.  DESTROY on the wrapper
 * MUST NOT delete the impl, because the vector owns it.
 *
 * Borrowed pointers are only valid until the owning vector reallocates
 * (appendElement growth); callers must not hold a borrow across an
 * append to the same block.
 *
 * We use a sentinel: when the inner IV has bit 1 set, DESTROY is a no-op.
 * Encoding: store (intptr_t)e | 1.  sv_to_branchelement clears bit 1. */
static SV* borrow_branchelement(BranchElement* e, const char* klass) {
    IV tagged = (IV)((intptr_t)e | 1);
    SV* inner = newSViv(tagged);
    SV* rv    = newRV_noinc(inner);
    sv_bless(rv, gv_stashpv(klass, GV_ADD));
    return rv;
}

static SV* borrow_branchblock(BranchBlock* blk, const char* klass) {
    IV tagged = (IV)((intptr_t)blk | 1);
    SV* inner = newSViv(tagged);
    SV* rv    = newRV_noinc(inner);
    sv_bless(rv, gv_stashpv(klass, GV_ADD));
    return rv;
}


/* =========================================================================
 * MCDC C++ structs and helpers
 *
 * MCDC_Expression is the single C++ value type stored inside an
 * MCDC_Block's groups.  Differential counts (when $count is an arrayref in
 * Perl) are represented per-sense as is_differential[s]=true + diff[s].
 * ========================================================================= */

/* Forward declaration -- MCDC_Block_wrapper::_destroy_groups_sv needs this. */
struct MCDC_Expression_wrapper;

/* MCDC_Block_wrapper -- Perl glue around a single C++ MCDC_Block.
 *
 * The wrapper holds NO coverage data of its own; all expression/group data
 * lives in exactly one C++ MCDC_Block (the single class for this type).  A
 * wrapper either OWNS its block (created by MCDC_Block->new / thaw) or
 * BORROWS a pointer into an MCDC_Data's data_ map (value() / new_mcdc()).
 * std::unordered_map guarantees pointer/reference stability of its elements
 * across insert and rehash -- only the erased element's pointer is
 * invalidated -- so borrowing &data_[line] is safe for the life of that entry.
 * Borrowing (rather than copying) is what makes mutations through value()/
 * new_mcdc() -- e.g. set_excluded() from the unreach callback -- persist in
 * storage, matching pure Perl.
 *
 * parent_sv: borrowed (not ref-counted) SV* of this block's Perl wrapper;
 *   set by make_mcdcblock_sv / STORABLE_thaw; used by MCDC_Expression::parent().
 * groups_sv: cached blessed-HV returned by groups(); built lazily, valid
 *   until any mutation (insertExpr, merge absorb).  We own refcnt=1 on it.
 *
 * Reference-cycle handling:
 *   Expression wrappers in groups_sv hold strong refs to parent_sv
 *   (owns_parent=true) so any wrapper that escapes groups_sv (e.g. copied
 *   into a Perl @blocks array by genhtml) keeps the parent alive.  The
 *   resulting cycle (wrapper -> groups_sv -> expr -> parent_sv -> SV wrapping
 *   wrapper) is broken explicitly in the destructor: before calling
 *   SvREFCNT_dec on groups_sv we walk every expr wrapper in it, release its
 *   parent_sv refcount, and zero parent_sv so any surviving wrapper returns
 *   undef instead of a dangling pointer. */
struct MCDC_Block_wrapper {
    MCDC_Block* block;      /* the single C++ data object */
    bool        owned;      /* true -> delete block in destructor */
    SV*         parent_sv;  /* borrowed backref to blessed RV; for expr parent() */
    SV*         groups_sv;  /* cached groups HV (refcnt owned by wrapper) */

    MCDC_Block_wrapper(MCDC_Block* b, bool own)
        : block(b), owned(own), parent_sv(nullptr), groups_sv(nullptr) {}

    ~MCDC_Block_wrapper() {
        _destroy_groups_sv();  /* zeros parent_sv in all wrappers before freeing */
        if (owned)
            delete block;
    }

    IV   line() const { return (IV)block->line(); }

    void invalidate_groups_cache() {
        _drop_groups_sv();     /* just frees groups_sv; block still alive, parent_sv valid */
    }

    /* Defined out-of-line after MCDC_Expression_wrapper (forward-declared above) */
    void _destroy_groups_sv();   /* called from destructor: zeros parent_sv then frees */
    void _drop_groups_sv();      /* called from mutation: frees without zeroing */
};

static MCDC_Block_wrapper* sv_to_mcdcblock(SV* sv) {
    if (!sv || !SvROK(sv))
        croak("MCDC_Block: not a reference");
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        croak("MCDC_Block: invalid object (not IV)");
    return (MCDC_Block_wrapper*)(intptr_t)SvIV(inner);
}

/* Bless a wrapper (owning or borrowing) as a Perl MCDC_Block and set its
 * parent backref.  The wrapper pointer is stored directly in the inner IV;
 * ownership of the underlying block is tracked by wrapper->owned. */
static SV* make_mcdcblock_sv(MCDC_Block_wrapper* w, const char* klass) {
    SV* inner = newSViv((IV)(intptr_t)w);
    SV* rv    = newRV_noinc(inner);
    sv_bless(rv, gv_stashpv(klass, GV_ADD));
    w->parent_sv = rv;   /* borrowed -- no extra refcount */
    return rv;
}

/* MCDC_Expression is a borrowed view into a group slot of an MCDC_Block. */

struct MCDC_Expression_wrapper {
    MCDC_Expression* expr;
    SV*  parent_sv;   /* ref-counted back to MCDC_Block, or nullptr if weak */
    bool owns_parent; /* true -> holds a refcount on parent_sv */
};

static MCDC_Expression_wrapper* sv_to_mcdcexpr_wrapper(SV* sv) {
    if (!sv || !SvROK(sv))
        croak("MCDC_Expression: not a reference");
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        croak("MCDC_Expression: invalid object (not IV)");
    return (MCDC_Expression_wrapper*)(intptr_t)SvIV(inner);
}

/* Create a Perl MCDC_Expression SV that borrows its data from a block slot.
 * owns_parent=true  -> holds a refcount on parent_sv (normal case).
 * owns_parent=false -> does not increment parent_sv refcount (used when the
 *   expression is stored inside the block's groups_sv cache, to avoid a
 *   reference cycle that would make the block immortal). */
static SV* make_mcdcexpr_sv(MCDC_Expression* e, SV* parent_sv,
                              const char* klass, bool owns_parent = true) {
    MCDC_Expression_wrapper* w = new MCDC_Expression_wrapper();
    w->expr         = e;
    w->parent_sv    = parent_sv;
    w->owns_parent  = owns_parent;
    if (owns_parent)
        SvREFCNT_inc(parent_sv);
    SV* inner = newSViv((IV)(intptr_t)w);
    SV* rv    = newRV_noinc(inner);
    sv_bless(rv, gv_stashpv(klass, GV_ADD));
    return rv;
}

/* _destroy_groups_sv -- called from ~MCDC_Block_wrapper only.
 * The block is being freed.  Walk every expression wrapper still inside
 * groups_sv: release its parent_sv refcount and zero parent_sv so any
 * surviving wrapper (escaped into a Perl @blocks array etc.) returns undef
 * from parent() rather than a dangling pointer.  Then drop groups_sv. */
void MCDC_Block_wrapper::_destroy_groups_sv() {
    if (!groups_sv)
        return;
    if (SvROK(groups_sv)) {
        HV* ghv = (HV*)SvRV(groups_sv);
        if (SvTYPE((SV*)ghv) == SVt_PVHV) {
            hv_iterinit(ghv);
            HE* he;
            while ((he = hv_iternext(ghv)) != nullptr) {
                SV* earrv = HeVAL(he);
                if (!earrv || !SvROK(earrv))
                    continue;
                AV* earr = (AV*)SvRV(earrv);
                if (SvTYPE((SV*)earr) != SVt_PVAV)
                    continue;
                IV n = av_len(earr) + 1;
                for (IV i = 0; i < n; ++i) {
                    SV** ep = av_fetch(earr, (SSize_t)i, 0);
                    if (!ep || !*ep || !SvROK(*ep))
                        continue;
                    SV* inner = SvRV(*ep);
                    if (!SvIOK(inner))
                        continue;
                    MCDC_Expression_wrapper* w =
                        (MCDC_Expression_wrapper*)(intptr_t)SvIV(inner);
                    if (!w)
                        continue;
                    if (w->owns_parent && w->parent_sv)
                        SvREFCNT_dec(w->parent_sv);
                    w->parent_sv   = nullptr;
                    w->owns_parent = false;
                }
            }
        }
    }
    SvREFCNT_dec(groups_sv);
    groups_sv = nullptr;
}

/* _drop_groups_sv -- called from invalidate_groups_cache (mutation, block alive).
 * The block is still live; parent_sv remains valid in all escaped wrappers.
 * Just drop the refcount on the old groups_sv -- do NOT zero parent_sv. */
void MCDC_Block_wrapper::_drop_groups_sv() {
    if (!groups_sv)
        return;
    SvREFCNT_dec(groups_sv);
    groups_sv = nullptr;
}

/* set() logic for MCDC_Expression -- mirrors pure-Perl MCDC_Expression::set().
 * Returns 1 if a coverage-state change occurred. */
static int mcdcexpr_set(MCDC_Expression* e, int sense, SV* count_sv,
                         bool excluded_flag)
{
    int s = sense ? 1 : 0;
    int changed = 0;

    /* Handle excluded flag */
    bool was_excluded = e->is_excluded(s);
    bool new_excluded = was_excluded || excluded_flag;

    if (!SvOK(count_sv)) {
        /* undef count -> just update excluded if changed */
        if (excluded_flag && !was_excluded) {
            e->set(s, e->count(s), true);
            return 1;
        }
        return 0;
    }

    if (SvROK(count_sv) && SvTYPE(SvRV(count_sv)) == SVt_PVAV) {
        /* arrayref differential count: [$tla, $base, $curr] (pure-Perl format) */
        AV* arr = (AV*)SvRV(count_sv);
        SV** tp = av_fetch(arr, 0, 0);
        SV** bp = av_fetch(arr, 1, 0);
        SV** cp = av_fetch(arr, 2, 0);

        std::string tla = (tp && *tp && SvOK(*tp)) ? std::string(SvPV_nolen(*tp)) : "";
        long long base = 0, curr = 0;
        bool base_undef = true, curr_undef = true;

        if (bp && *bp && SvOK(*bp)) { base = SvIV(*bp); base_undef = false; }
        if (cp && *cp && SvOK(*cp)) { curr = SvIV(*cp); curr_undef = false; }

        /* For differential, we reconstruct: if curr is defined, use it; else keep old count */
        long long new_count = curr_undef ? e->count(s) : curr;
        e->set(s, new_count, new_excluded);

        /* Set differential data with optional base/curr */
        std::optional<int64_t> base_opt = base_undef ? std::nullopt : std::optional<int64_t>(base);
        std::optional<int64_t> curr_opt = curr_undef ? std::nullopt : std::optional<int64_t>(curr);
        e->set_differential_opt(s, tla, base_opt, curr_opt);
        return 1;
    }

    /* Simple count */
    long long cnt = SvIV(count_sv);
    long long old_count = e->count(s);
    if (cnt == 0 && !excluded_flag)
        return changed;

    long long new_count = old_count + cnt;
    changed = e->set(s, new_count, new_excluded);
    return changed;
}


/* MCDC_Data_wrapper -- Perl glue around a single C++ MCDC_Data.
 *
 * Blessed as a scalar ref whose inner IV points here.  Besides the one C++
 * data object it keeps a per-instance cache mapping line -> the blessed
 * MCDC_Block wrapper SV previously handed out for that line.  The cache gives
 * value()/new_mcdc() Perl-level object identity (repeat calls for the same
 * line return the *same* blessed ref, matching pure Perl) and avoids
 * re-blessing on every lookup.  Cached block wrappers BORROW a pointer into
 * data_'s map entry; we hold one refcount on each cached SV. */
struct MCDC_Data_wrapper {
    MCDC_Data* data;
    std::unordered_map<int32_t, SV*> cache;

    MCDC_Data_wrapper() : data(new MCDC_Data()) {}
    explicit MCDC_Data_wrapper(MCDC_Data* d) : data(d) {}

    ~MCDC_Data_wrapper() {
        clear_cache();
        delete data;
    }

    void clear_cache() {
        for (auto& kv : cache)
            if (kv.second)
                SvREFCNT_dec(kv.second);
        cache.clear();
    }

    void uncache(int32_t line) {
        auto it = cache.find(line);
        if (it != cache.end()) {
            if (it->second)
                SvREFCNT_dec(it->second);
            cache.erase(it);
        }
    }
};

static MCDC_Data_wrapper* sv_to_mcdcdata(SV* sv) {
    if (!sv || !SvROK(sv))
        croak("MCDC_Data: not a reference");
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        croak("MCDC_Data: invalid object (not IV)");
    return (MCDC_Data_wrapper*)(intptr_t)SvIV(inner);
}

/* Return the cached MCDC_Block wrapper SV for 'line', or create one that
 * borrows &data_[line] (which must exist), cache it, and return it.  The
 * returned SV has had its refcount incremented for the caller. */
static SV* mcdcdata_block_sv(MCDC_Data_wrapper* w, int32_t line, MCDC_Block* blk) {
    auto it = w->cache.find(line);
    if (it != w->cache.end())
        return SvREFCNT_inc(it->second);

    MCDC_Block_wrapper* bw = new MCDC_Block_wrapper(blk, false); /* borrowed */
    SV* rv = make_mcdcblock_sv(bw, "MCDC_Block");
    SvREFCNT_inc(rv);               /* one ref for the cache */
    w->cache[line] = rv;
    return rv;                      /* one ref for the caller */
}

/* =========================================================================
 * BranchData_wrapper -- Perl glue around a single C++ BranchData.
 *
 * Scalar-ref representation: the inner IV holds the wrapper pointer.  All
 * coverage data lives in one C++ BranchData; the wrapper adds only a per-line
 * cache of the
 * blessed BranchLocation SVs it has handed out, so that repeated value()/
 * findOrCreate() calls for the same line return the SAME Perl object (object
 * identity), matching pure Perl.  BranchLocation wrappers borrow &data_[line]
 * (unordered_map guarantees element-pointer stability across insert/rehash),
 * so mutations through them persist in storage.
 * ========================================================================= */
struct BranchData_wrapper {
    BranchData* data;
    std::unordered_map<int32_t, SV*> cache;   /* line -> borrowed BranchLocation SV (refcnt owned) */

    BranchData_wrapper() : data(new BranchData()) {}
    explicit BranchData_wrapper(BranchData* d) : data(d) {}

    ~BranchData_wrapper() { clear_cache(); delete data; }

    void clear_cache() {
        for (auto& kv : cache)
            if (kv.second)
                SvREFCNT_dec(kv.second);
        cache.clear();
    }

    void uncache(int32_t line) {
        auto it = cache.find(line);
        if (it != cache.end()) {
            if (it->second)
                SvREFCNT_dec(it->second);
            cache.erase(it);
        }
    }
};

static BranchData_wrapper* sv_to_branchdata(SV* sv) {
    if (!sv || !SvROK(sv))
        croak("BranchData: not a reference");
    SV* inner = SvRV(sv);
    if (!SvIOK(inner))
        croak("BranchData: invalid object (not IV)");
    return (BranchData_wrapper*)(intptr_t)SvIV(inner);
}

/* Return the cached BranchLocation SV for 'line', or create one that borrows
 * &data_[line] (which must exist), cache it, and return it.  The returned SV
 * has had its refcount incremented for the caller. */
static SV* branchdata_location_sv(BranchData_wrapper* w, int32_t line,
                                   BranchLocation* loc) {
    auto it = w->cache.find(line);
    if (it != w->cache.end())
        return SvREFCNT_inc(it->second);

    SV* inner = newSViv((IV)((intptr_t)loc | 1));   /* borrowed pointer tag */
    SV* rv    = newRV_noinc(inner);
    sv_bless(rv, gv_stashpv("BranchLocation", GV_ADD));
    SvREFCNT_inc(rv);               /* one ref for the cache */
    w->cache[line] = rv;
    return rv;                      /* one ref for the caller */
}

/* =========================================================================
 * XS definitions
 * ========================================================================= */

MODULE = LcovUtil    PACKAGE = LcovUtil

PROTOTYPES: DISABLE

BOOT:
{
    /* Register C++ callback for reporting errors from BranchElement::merge */
    BranchDataCallbacks::report_error = [](int error_code, const std::string& message) {
        /* Only call Perl functions if we have a valid interpreter context.
         * During parallel/forked processing, child processes may not have
         * full Perl context, so skip the callback to avoid crashes.
         *
         * Not reachable from a test:  every merge that can report an error runs
         * with a live interpreter (that is who called into the XS layer), and
         * PL_dirty is only set once global destruction has begun, by which point
         * no coverage data is being merged.  The guard exists to keep a stray
         * late/forked call from calling into a torn-down interpreter. */
        if (!PL_curinterp || PL_dirty)
            return;   /* LCOV_UNREACHABLE_LINE */

        dSP;
        ENTER; SAVETMPS; PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSViv(error_code)));
        XPUSHs(sv_2mortal(newSVpv(message.c_str(), message.size())));
        PUTBACK;
        call_pv("lcovutil::ignorable_error", G_DISCARD);
        FREETMPS; LEAVE;
    };
}

# ----------------------------------------------------------------------------
# MapData
# ----------------------------------------------------------------------------

MODULE = LcovUtil    PACKAGE = MapData

SV*
new(klass)
    char* klass
  CODE:
    MapData_impl* impl = new MapData_impl();
    SV* inner = newSViv((IV)(intptr_t)impl);
    SV* self  = newRV_noinc(inner);
    sv_bless(self, gv_stashpv(klass, GV_ADD));
    RETVAL = self;
  OUTPUT:
    RETVAL

void
DESTROY(self)
    SV* self
  CODE:
    if (SvROK(self) && SvIOK(SvRV(self))) {
        MapData_impl* impl = (MapData_impl*)(intptr_t)SvIV(SvRV(self));
        if (impl) {
            delete impl;
            SvIV_set(SvRV(self), 0);
        }
    }

int
is_empty(self)
    SV* self
  CODE:
    MapData_impl* impl = sv_to_mapdata(self);
    RETVAL = impl->data.empty() ? 1 : 0;
  OUTPUT:
    RETVAL

SV*
append_if_unset(self, key, data)
    SV* self
    SV* key
    SV* data
  CODE:
    MapData_impl* impl = sv_to_mapdata(self);
    std::string k = SvPV_nolen(key);
    auto it = impl->data.find(k);
    if (it == impl->data.end()) {
        SvREFCNT_inc(data);
        impl->data[k] = data;
    }
    SvREFCNT_inc(self);
    RETVAL = self;
  OUTPUT:
    RETVAL

SV*
replace(self, key, data)
    SV* self
    SV* key
    SV* data
  CODE:
    MapData_impl* impl = sv_to_mapdata(self);
    std::string k = SvPV_nolen(key);
    auto it = impl->data.find(k);
    if (it != impl->data.end()) {
        SvREFCNT_dec(it->second);
        it->second = data;
    } else {
        impl->data[k] = data;
    }
    SvREFCNT_inc(data);
    SvREFCNT_inc(self);
    RETVAL = self;
  OUTPUT:
    RETVAL

SV*
value(self, key)
    SV* self
    SV* key
  CODE:
    MapData_impl* impl = sv_to_mapdata(self);
    std::string k = SvPV_nolen(key);
    auto it = impl->data.find(k);
    if (it == impl->data.end()) {
        RETVAL = &PL_sv_undef;
        SvREFCNT_inc(RETVAL);
    } else {
        RETVAL = it->second;
        SvREFCNT_inc(RETVAL);
    }
  OUTPUT:
    RETVAL

int
remove(self, key, ...)
    SV* self
    SV* key
  CODE:
    MapData_impl* impl = sv_to_mapdata(self);
    std::string k = SvPV_nolen(key);
    // $check_is_present is optional (items>=3 means it was passed)
    bool check = (items >= 3) && SvOK(ST(2));
    auto it = impl->data.find(k);
    if (!check || it != impl->data.end()) {
        if (it != impl->data.end()) {
            SvREFCNT_dec(it->second);
            impl->data.erase(it);
        }
        RETVAL = 1;
    } else {
        RETVAL = 0;
    }
  OUTPUT:
    RETVAL

int
mapped(self, key)
    SV* self
    SV* key
  CODE:
    MapData_impl* impl = sv_to_mapdata(self);
    std::string k = SvPV_nolen(key);
    RETVAL = (impl->data.find(k) != impl->data.end() &&
              SvOK(impl->data.find(k)->second)) ? 1 : 0;
  OUTPUT:
    RETVAL

void
keylist(self)
    SV* self
  PPCODE:
    MapData_impl* impl = sv_to_mapdata(self);
    /* Context-aware, exactly like the pure-Perl 'return keys(%h)' body this
     * mirrors:  in scalar context yield the key COUNT, not the last key.
     * lcovutil.pm asks 'scalar($map->keylist())' at four sites to test a map
     * for emptiness; a list-only XSUB there returns whichever key happened to
     * come last (and undef for an empty map), so the emptiness test silently
     * read the wrong thing under XS. */
    if (GIMME_V == G_SCALAR) {
        XPUSHs(sv_2mortal(newSViv((IV)impl->data.size())));
        XSRETURN(1);
    }
    for (auto& kv : impl->data) {
        XPUSHs(sv_2mortal(newSVpv(kv.first.c_str(), kv.first.size())));
    }

int
entries(self)
    SV* self
  CODE:
    MapData_impl* impl = sv_to_mapdata(self);
    RETVAL = (int)impl->data.size();
  OUTPUT:
    RETVAL

# Storable hooks for MapData
# freeze returns ("", $hashref) -- tag string + data ref
void
STORABLE_freeze(self, cloning)
    SV* self
    SV* cloning
  PPCODE:
    MapData_impl* impl = sv_to_mapdata(self);
    /* push: tag string (empty), then a hashref of the data */
    XPUSHs(sv_2mortal(newSVpvs("")));
    XPUSHs(sv_2mortal(mapdata_freeze(impl)));

void
STORABLE_thaw(self, cloning, tag, ...)
    SV* self
    SV* cloning
    SV* tag
  CODE:
    /* items >= 4 means the data ref was passed as ST(3) */
    SV* arg = (items >= 4) ? ST(3) : &PL_sv_undef;
    /* Storable may double-wrap the ref */
    SV* frozen = (SvROK(arg) && SvROK(SvRV(arg))) ? SvRV(arg) : arg;
    SV* inner = SvRV(self);
    /* Build the replacement BEFORE releasing the old one.  mapdata_thaw()
     * croaks on a malformed payload, and croak() longjmps out of this XSUB --
     * so a 'delete' placed above it would leave a dangling pointer in 'inner'
     * with SvIOK still set, which DESTROY would then free a second time. */
    MapData_impl* new_impl = mapdata_thaw(frozen);
    if (SvIOK(inner))
        delete (MapData_impl*)(intptr_t)SvIV(inner);   /* nullptr-safe */
    sv_setiv(inner, (IV)(intptr_t)new_impl);

# ----------------------------------------------------------------------------
# CountData
# ----------------------------------------------------------------------------

MODULE = LcovUtil    PACKAGE = CountData

SV*
new(klass, filename, ...)
    char* klass
    SV* filename
  CODE:
    std::string fn = SvPV_nolen(filename);
    int sortable = (items >= 3 && SvOK(ST(2))) ? SvIV(ST(2)) : 0;
    CountData_impl* impl = new CountData_impl(fn, sortable);
    SV* inner = newSViv((IV)(intptr_t)impl);
    SV* self  = newRV_noinc(inner);
    sv_bless(self, gv_stashpv(klass, GV_ADD));
    RETVAL = self;
  OUTPUT:
    RETVAL

void
DESTROY(self)
    SV* self
  CODE:
    if (SvROK(self) && SvIOK(SvRV(self))) {
        CountData_impl* impl = (CountData_impl*)(intptr_t)SvIV(SvRV(self));
        if (impl) {
            delete impl;
            SvIV_set(SvRV(self), 0);
        }
    }

SV*
filename(self)
    SV* self
  CODE:
    CountData_impl* impl = sv_to_countdata(self);
    RETVAL = newSVpv(impl->filename.c_str(), 0);
  OUTPUT:
    RETVAL

int
append(self, key, count, ...)
    SV* self
    SV* key
    SV* count
  CODE:
    CountData_impl* impl = sv_to_countdata(self);
    int k = SvIV(key);
    // suppressErrMsg: items>=4 and SvOK(ST(3))
    bool suppress = (items >= 4) && SvOK(ST(3));

    long long cnt;
    /* Call lcovutil::report_format_error with exactly the same arguments as
     * the pure-Perl CountData::append, so error messages are identical.
     * Location strings intentionally replicate the pure-Perl quoting quirks:
     *   FORMAT:          'line "' . filename . ":$key\""
     *   NEGATIVE/EXCESS: 'line '  . filename . ":$key\""  (no leading quote)
     */
    /* Replicate Scalar::Util::looks_like_number by calling it via Perl */
    bool looks_like_num = false;
    {
        dSP;
        ENTER; SAVETMPS; PUSHMARK(SP);
        XPUSHs(count);
        PUTBACK;
        int nret = call_pv("Scalar::Util::looks_like_number", G_SCALAR);
        SPAGAIN;
        SV* ret = (nret > 0) ? POPs : &PL_sv_undef;
        looks_like_num = SvOK(ret) && SvTRUE(ret);
        PUTBACK;
        FREETMPS; LEAVE;
    }

    if (!SvOK(count) || !looks_like_num) {
        if (!suppress) {
            dSP;
            SV* errType = get_sv("lcovutil::ERROR_FORMAT", 0);
            std::string loc = std::string("line \"") + impl->filename + ":" + std::to_string(k) + "\"";
            ENTER; SAVETMPS; PUSHMARK(SP);
            XPUSHs(errType ? errType : &PL_sv_undef);
            XPUSHs(sv_2mortal(newSVpvs("hit")));
            XPUSHs(count);
            XPUSHs(sv_2mortal(newSVpv(loc.c_str(), 0)));
            PUTBACK;
            call_pv("lcovutil::report_format_error", G_DISCARD);
            FREETMPS; LEAVE;
        }
        cnt = 0;
    } else {
        /* Use NV (double) for sign and threshold comparisons to avoid
         * signed overflow when the value is a large float like "1.0e+19".
         * SvIV("1.0e+19") would overflow long long and appear negative.
         * Saturate to LLONG_MAX so stored value stays non-negative. */
        double cnt_nv = SvNV(count);
        if (cnt_nv >= (double)LLONG_MAX)
            cnt = LLONG_MAX;
        else if (cnt_nv <= (double)LLONG_MIN)
            cnt = 0;
        else
            cnt = (long long)cnt_nv;
        if (cnt_nv < 0.0) {
            if (!suppress) {
                dSP;
                SV* errType = get_sv("lcovutil::ERROR_NEGATIVE", 0);
                std::string loc = std::string("line ") + impl->filename + ":" + std::to_string(k) + "\"";
                ENTER; SAVETMPS; PUSHMARK(SP);
                XPUSHs(errType ? errType : &PL_sv_undef);
                XPUSHs(sv_2mortal(newSVpvs("hit")));
                XPUSHs(count);
                XPUSHs(sv_2mortal(newSVpv(loc.c_str(), 0)));
                PUTBACK;
                call_pv("lcovutil::report_format_error", G_DISCARD);
                FREETMPS; LEAVE;
            }
            cnt = 0;
        } else {
            SV* thresh = get_sv("lcovutil::excessive_count_threshold", 0);
            if (!suppress && thresh && SvOK(thresh) && cnt_nv > (double)SvIV(thresh)) {
                dSP;
                SV* errType = get_sv("lcovutil::ERROR_EXCESSIVE_COUNT", 0);
                std::string loc = std::string("line ") + impl->filename + ":" + std::to_string(k) + "\"";
                ENTER; SAVETMPS; PUSHMARK(SP);
                XPUSHs(errType ? errType : &PL_sv_undef);
                XPUSHs(sv_2mortal(newSVpvs("hit")));
                XPUSHs(count);
                XPUSHs(sv_2mortal(newSVpv(loc.c_str(), 0)));
                PUTBACK;
                call_pv("lcovutil::report_format_error", G_DISCARD);
                FREETMPS; LEAVE;
            }
        }
    }

    int changed = 0;
    auto it = impl->find(k);
    if (it == impl->data.end()) {
        changed = 1;
        impl->insert_new(k, cnt);
        impl->found++;
        if (cnt > 0)
            impl->hit++;
    } else {
        long long current = it->second;
        if (cnt > 0 && current == 0) {
            impl->hit++;
            changed = 1;
        }
        it->second = current + cnt;
    }
    RETVAL = changed;
  OUTPUT:
    RETVAL

SV*
value(self, key)
    SV* self
    SV* key
  CODE:
    CountData_impl* impl = sv_to_countdata(self);
    int k = SvIV(key);
    auto it = impl->find(k);
    if (it == impl->data.end()) {
        RETVAL = &PL_sv_undef;
        SvREFCNT_inc(RETVAL);
    } else {
        RETVAL = newSViv(it->second);
    }
  OUTPUT:
    RETVAL

int
remove(self, key, ...)
    SV* self
    SV* key
  CODE:
    CountData_impl* impl = sv_to_countdata(self);
    int k = SvIV(key);
    bool check = (items >= 3) && SvOK(ST(2));
    bool retain = (items >= 4) && SvOK(ST(3));
    auto it = impl->find(k);
    if (!check || it != impl->data.end()) {
        if (it == impl->data.end())
            croak("%d not found", k);
        impl->found--;
        if (it->second > 0)
            impl->hit--;
        if (!retain)
            impl->data.erase(it);
        RETVAL = 1;
    } else {
        RETVAL = 0;
    }
  OUTPUT:
    RETVAL

IV
found(self)
    SV* self
  CODE:
    RETVAL = (IV)sv_to_countdata(self)->found;
  OUTPUT:
    RETVAL

IV
hit(self)
    SV* self
  CODE:
    RETVAL = (IV)sv_to_countdata(self)->hit;
  OUTPUT:
    RETVAL

void
keylist(self)
    SV* self
  PPCODE:
    CountData_impl* impl = sv_to_countdata(self);
    /* Context-aware, exactly like the pure-Perl 'return keys(%h)' body this
     * mirrors:  in scalar context yield the key COUNT, not the last key.
     * lcovutil.pm asks 'scalar($map->keylist())' at four sites to test a map
     * for emptiness; a list-only XSUB there returns whichever key happened to
     * come last (and undef for an empty map), so the emptiness test silently
     * read the wrong thing under XS. */
    if (GIMME_V == G_SCALAR) {
        XPUSHs(sv_2mortal(newSViv((IV)impl->data.size())));
        XSRETURN(1);
    }
    for (auto& kv : impl->data) {
        XPUSHs(sv_2mortal(newSViv(kv.first)));
    }

int
entries(self)
    SV* self
  CODE:
    RETVAL = (int)sv_to_countdata(self)->data.size();
  OUTPUT:
    RETVAL

void
_checkCounts(self)
    SV* self
  CODE:
    /* Mirrors pure-Perl CountData::_checkCounts: assert the cached found/hit
     * still equal a full walk of the data.  'append' and 'remove' maintain
     * them incrementally, so a map mutated twice - which is what an aliased
     * summary treated as an independent object produces - drifts silently.
     * Line data is the case this catches most quietly: a count merged twice is
     * still 'hit', so every rate still reads right and only the count is
     * wrong.  TraceInfo::check_data runs this unconditionally on every
     * '.info' read, so it must do real work under XS as well. */
    CountData_impl* cd = sv_to_countdata(self);
    long long found = 0, hit = 0;
    for (CountData_impl::Map::const_iterator it = cd->data.begin();
         it != cd->data.end(); ++it) {
        ++found;
        if (it->second > 0)
            ++hit;
    }
    if (cd->found != found || cd->hit != hit)
        croak("invalid line counts for %s: found:%" IVdf "->%" IVdf
              ", hit:%" IVdf "->%" IVdf,
              cd->filename.c_str(),
              (IV)cd->found, (IV)found, (IV)cd->hit, (IV)hit);

int
union(self, other, ...)
    SV* self
    SV* other
  CODE:
    CountData_impl* s = sv_to_countdata(self);
    CountData_impl* o = sv_to_countdata(other);
    int changed = 0;
    /* Both sides are sorted by line, so this is a linear merge into a fresh
     * vector rather than a per-key search-and-insert -- inserting into the
     * middle of the target would be O(n) memmove per new key. */
    CountData_impl::Map merged;
    merged.reserve(s->data.size() + o->data.size());
    auto si = s->data.begin(), send = s->data.end();
    auto oi = o->data.begin(), oend = o->data.end();
    while (si != send || oi != oend) {
        if (oi == oend || (si != send && si->first < oi->first)) {
            merged.push_back(*si);
            ++si;
        } else if (si == send || oi->first < si->first) {
            changed = 1;
            merged.push_back(*oi);
            s->found++;
            if (oi->second > 0)
                s->hit++;
            ++oi;
        } else {
            long long cur = si->second;
            if (oi->second > 0 && cur == 0) {
                s->hit++;
                changed = 1;
            }
            merged.push_back(std::make_pair(si->first, cur + oi->second));
            ++si;
            ++oi;
        }
    }
    s->data.swap(merged);
    RETVAL = changed;
  OUTPUT:
    RETVAL

int
intersect(self, other, ...)
    SV* self
    SV* other
  CODE:
    CountData_impl* s = sv_to_countdata(self);
    CountData_impl* o = sv_to_countdata(other);
    int changed = 0;
    /* Sorted-merge compaction in place: keys present in both are updated and
     * kept, keys only in self are dropped.  Writing surviving entries forward
     * over the vector avoids the erase-per-key memmove the hash version paid
     * as a second pass, and keeps the sort invariant by construction. */
    auto out = s->data.begin();
    auto si = s->data.begin(), send = s->data.end();
    auto oi = o->data.begin(), oend = o->data.end();
    while (si != send) {
        while (oi != oend && oi->first < si->first)
            ++oi;
        if (oi != oend && oi->first == si->first) {
            long long cur = si->second;
            long long add = oi->second;
            if (add > 0 && cur == 0) {
                s->hit++;
                changed = 1;
            }
            *out = std::make_pair(si->first, cur + add);
            ++out;
        } else {
            /* only in self -- drop it, adjusting the cached totals */
            changed = 1;
            s->found--;
            if (si->second > 0)
                s->hit--;
        }
        ++si;
    }
    s->data.erase(out, s->data.end());
    RETVAL = changed;
  OUTPUT:
    RETVAL

int
difference(self, other, ...)
    SV* self
    SV* other
  CODE:
    CountData_impl* s = sv_to_countdata(self);
    CountData_impl* o = sv_to_countdata(other);
    int changed = 0;
    /* Mirror of intersect(): keep the keys NOT present in other, compacting
     * forward through the sorted vector. */
    auto out = s->data.begin();
    auto si = s->data.begin(), send = s->data.end();
    auto oi = o->data.begin(), oend = o->data.end();
    while (si != send) {
        while (oi != oend && oi->first < si->first)
            ++oi;
        if (oi != oend && oi->first == si->first) {
            changed = 1;
            s->found--;
            if (si->second > 0)
                s->hit--;
        } else {
            *out = *si;
            ++out;
        }
        ++si;
    }
    s->data.erase(out, s->data.end());
    RETVAL = changed;
  OUTPUT:
    RETVAL

void
get_found_and_hit(self)
    SV* self
  PPCODE:
    CountData_impl* impl = sv_to_countdata(self);
    XPUSHs(sv_2mortal(newSViv(impl->found)));
    XPUSHs(sv_2mortal(newSViv(impl->hit)));

# Binary serialization methods for CountData
SV*
serialize_binary(self)
    SV* self
  CODE:
    CountData_impl* impl = sv_to_countdata(self);
    RETVAL = countdata_serialize_binary(impl);
  OUTPUT:
    RETVAL

SV*
deserialize_binary(klass, data_sv)
    char* klass
    SV* data_sv
  CODE:
    STRLEN len;
    const uint8_t* data = (const uint8_t*)SvPVbyte(data_sv, len);
    CountData_impl* impl = countdata_deserialize_binary(data, len);
    SV* inner = newSViv((IV)(intptr_t)impl);
    SV* self  = newRV_noinc(inner);
    sv_bless(self, gv_stashpv(klass, GV_ADD));
    RETVAL = self;
  OUTPUT:
    RETVAL

# ============================================================================
# BranchElement, BranchBlock, BranchLocation, MCDC_Block, MCDC_Expression,
# BranchData, MCDC_Data
#
# Each class is a blessed scalar whose inner IV holds a pointer to a C++
# object (or a wrapper around one); the XS methods operate directly on that
# C++ object.  There is no Perl-side AV/HV holding the coverage data, so
# Storable serialization is NOT automatic: each class provides explicit
# STORABLE_freeze/thaw XSUBs that emit a compact binary wire format, read back
# only by the same build within one run.
# ============================================================================

# ---------------------------------------------------------------------------
# BranchElement -- C++ struct behind IV pointer
# ---------------------------------------------------------------------------

MODULE = LcovUtil    PACKAGE = BranchElement

SV*
new(klass, id, taken, ...)
    char* klass
    SV*   id
    SV*   taken
  CODE:
    /* new($class, $id, $taken, $expr, $type, $excluded) */
    BranchElement* impl = new BranchElement(
        build_branchelement(id, taken,
                            (items >= 4) ? ST(3) : NULL,
                            (items >= 5) ? ST(4) : NULL,
                            (items >= 6) ? ST(5) : NULL));

    RETVAL = make_branchelement_sv(impl, klass);
  OUTPUT:
    RETVAL

void
DESTROY(self)
    SV* self
  CODE:
    if (!branchelement_is_borrowed(self)) {
        BranchElement* impl = sv_to_branchelement(self);
        SvIV_set(SvRV(self), 0);
        delete impl;
    }

int
isTaken(self)
    SV* self
  CODE:
    RETVAL = sv_to_branchelement(self)->isTaken() ? 1 : 0;
  OUTPUT:
    RETVAL

SV*
id(self)
    SV* self
  CODE:
    BranchElement* impl = sv_to_branchelement(self);
    std::string id_str = std::to_string(impl->id());
    RETVAL = newSVpv(id_str.c_str(), id_str.size());
  OUTPUT:
    RETVAL

SV*
data(self)
    SV* self
  CODE:
    BranchElement* impl = sv_to_branchelement(self);
    if (impl->data() == BranchElement::DASH)
        RETVAL = newSVpvs("-");
    else
        RETVAL = newSViv(impl->data());
  OUTPUT:
    RETVAL

SV*
count(self)
    SV* self
  CODE:
    BranchElement* impl = sv_to_branchelement(self);
    RETVAL = newSViv(impl->count());
  OUTPUT:
    RETVAL

SV*
expr(self)
    SV* self
  CODE:
    BranchElement* impl = sv_to_branchelement(self);
    const std::string& expr_str = impl->expr();
    if (expr_str.empty()) { RETVAL = &PL_sv_undef; SvREFCNT_inc(RETVAL); }
    else
        RETVAL = newSVpv(expr_str.c_str(), expr_str.size());
  OUTPUT:
    RETVAL

SV*
exprString(self)
    SV* self
  CODE:
    BranchElement* impl = sv_to_branchelement(self);
    std::string expr_str = impl->exprString();
    RETVAL = newSVpv(expr_str.c_str(), expr_str.size());
  OUTPUT:
    RETVAL

IV
type(self)
    SV* self
  CODE:
    RETVAL = static_cast<IV>(sv_to_branchelement(self)->type());
  OUTPUT:
    RETVAL

SV*
type_name(self)
    SV* self
  CODE:
    IV t = static_cast<IV>(sv_to_branchelement(self)->type());
    if (t == 0)
        RETVAL = newSVpvs("");
    else if (t == 1)
        RETVAL = newSVpvs("exception");
    else
        RETVAL = newSVpvs("fallthrough");
  OUTPUT:
    RETVAL

SV*
signature(self)
    SV* self
  CODE:
    char sig = sv_to_branchelement(self)->signature();
    RETVAL = newSVpvn(&sig, 1);
  OUTPUT:
    RETVAL

int
is_exception(self)
    SV* self
  CODE:
    RETVAL = sv_to_branchelement(self)->isException() ? 1 : 0;
  OUTPUT:
    RETVAL

IV
is_excluded(self)
    SV* self
  CODE:
    RETVAL = sv_to_branchelement(self)->isExcluded() ? 1 : 0;
  OUTPUT:
    RETVAL

int
set_excluded(self)
    SV* self
  CODE:
    BranchElement* impl = sv_to_branchelement(self);
    if (impl->isExcluded()) { RETVAL = 0; }
    else { impl->setExcluded(true); RETVAL = 1; }
  OUTPUT:
    RETVAL

int
isDifferential(self)
    SV* self
  CODE:
    RETVAL = sv_to_branchelement(self)->isDifferential() ? 1 : 0;
  OUTPUT:
    RETVAL

SV*
tla(self)
    SV* self
  CODE:
    BranchElement* impl = sv_to_branchelement(self);
    if (!impl->isDifferential())
        croak("unexpected tla() call with non-differential data");
    const std::string& tla_str = impl->tla();
    RETVAL = newSVpv(tla_str.c_str(), tla_str.size());
  OUTPUT:
    RETVAL

void
diff_count(self)
    SV* self
  PPCODE:
    BranchElement* impl = sv_to_branchelement(self);
    if (!impl->isDifferential())
        croak("unexpected diff_count() call with non-differential data");
    /* base and curr are independently optional -- see BranchData.hpp. */
    if (impl->hasBase())
        XPUSHs(sv_2mortal(newSViv(impl->base())));
    else
        XPUSHs(sv_2mortal(newSV(0)));
    if (impl->hasCurr())
        XPUSHs(sv_2mortal(newSViv(impl->curr())));
    else
        XPUSHs(sv_2mortal(newSV(0)));

void
set_tla(self, tla)
    SV* self
    SV* tla
  CODE:
    BranchElement* impl = sv_to_branchelement(self);
    /* Same precondition as tla() -- see the note on pure-Perl
     * BranchElement::set_tla.  A TLA only means something on a differential
     * element, and lazily making the element differential here would report
     * isDifferential() true where pure Perl (whose isDifferential() tests the
     * array's length) reports false, so reject it in both instead. */
    if (!impl->isDifferential())
        croak("unexpected set_tla() call with non-differential data");
    STRLEN len; const char* s = SvPV(tla, len);
    impl->set_tla(std::string(s, len));

void
set_differential(self, tla, base, curr)
    SV* self
    SV* tla
    SV* base
    SV* curr
  CODE:
    BranchElement* impl = sv_to_branchelement(self);
    STRLEN len; const char* s = SvPV(tla, len);
    /* An undef base means "not in the baseline" (bin/genhtml cloneBlock) and
     * must stay undef, as it does in pure Perl -- not become 0. */
    impl->set_differential(std::string(s, len),
                           SvOK(base) ? std::optional<int64_t>(SvIV(base)) : std::nullopt,
                           SvOK(curr) ? std::optional<int64_t>(SvIV(curr)) : std::nullopt);

int
merge(self, that, ...)
    SV* self
    SV* that
  CODE:
    /* merge($self, $that, $filename, $line) */
    {
        BranchElement* s = sv_to_branchelement(self);
        BranchElement* t = sv_to_branchelement(that);
        const char* filename = (items >= 3 && SvOK(ST(2))) ? SvPV_nolen(ST(2)) : "";
        IV line = (items >= 4) ? SvIV(ST(3)) : 0;

        /* Use C++ merge method - mismatch check is done in C++ via callback */
        RETVAL = s->merge(*t, filename, line);
    }
  OUTPUT:
    RETVAL

# Storable hooks
void
STORABLE_freeze(self, cloning)
    SV* self
    SV* cloning
  PPCODE:
    /* Single flat binary scalar (no data refs) -- same wire strategy as the
     * BranchData container hook.  branchelement_write handles differential
     * elements, so post-categorization objects round-trip too. */
    BranchElement* impl = sv_to_branchelement(self);
    lcov_binary::BinaryWriter w;
    branchelement_write(w, impl);
    const std::vector<uint8_t>& buf = w.data();
    XPUSHs(sv_2mortal(newSVpvn(reinterpret_cast<const char*>(buf.data()), buf.size())));

void
STORABLE_thaw(self, cloning, serialized, ...)
    SV* self
    SV* cloning
    SV* serialized
  CODE:
    /* Storable's thaw contract is STORABLE_thaw(self, cloning, serialized, @refs).
     * Our freeze hook pushes a SINGLE flat binary scalar and no data refs, so the
     * frozen bytes arrive as the `serialized` argument at ST(2) -- NOT ST(3).
     * (MapData reads ST(3) only because its freeze pushes two items: an empty tag
     * at ST(2) plus a data ref at ST(3).)  Reading ST(3) -- or requiring items>=4
     * -- would croak "missing frozen data" whenever these per-object hooks fire
     * directly, e.g. Storable::dclone() of a bare MCDC_Block/BranchElement, which
     * recurses into the per-object hook rather than the flattened container hook
     * that geninfo's top-level serialize uses. */
    if (items < 3)
        croak("STORABLE_thaw: missing frozen data");
    STRLEN len;
    const uint8_t* data = (const uint8_t*)SvPVbyte(serialized, len);
    lcov_binary::BinaryReader r(data, len);
    BranchElement* impl = new BranchElement(branchelement_read(r));
    SvIV_set(SvRV(self), (IV)(intptr_t)impl);
    SvIOK_on(SvRV(self));

void
render_data(self)
    SV* self
  PPCODE:
    /* Batch accessor for the genhtml source-view render loop, which otherwise
     * makes 8+ separate XSUB calls per branch element (data, is_excluded,
     * count, type_name, expr, and for differential data tla + diff_count).
     * One crossing instead of eight, on a path executed once per rendered
     * branch -- i.e. millions of times on a large report.
     *
     * Returns a flat list, always the same arity and order:
     *   (data, count, is_excluded, type_name, expr, tla, base_count)
     * where data mirrors data() ('-' or an integer), expr is undef when the
     * element has none, and tla/base_count are undef for non-differential
     * elements.  A flat list rather than a hash or AV keeps this allocation-free
     * beyond the returned scalars themselves.
     *
     * Every field is read through the SAME C++ accessor the scalar XSUB uses,
     * so the batch and scalar paths cannot drift apart. */
    BranchElement* impl = sv_to_branchelement(self);
    EXTEND(SP, 7);

    /* data() */
    if (impl->data() == BranchElement::DASH)
        PUSHs(sv_2mortal(newSVpvs("-")));
    else
        PUSHs(sv_2mortal(newSViv(impl->data())));

    /* count() */
    PUSHs(sv_2mortal(newSViv(impl->count())));

    /* is_excluded() */
    PUSHs(sv_2mortal(newSViv(impl->isExcluded() ? 1 : 0)));

    /* type_name() -- same mapping as the type_name XSUB */
    {
        IV t = static_cast<IV>(impl->type());
        if (t == 0)
            PUSHs(sv_2mortal(newSVpvs("")));
        else if (t == 1)
            PUSHs(sv_2mortal(newSVpvs("exception")));
        else
            PUSHs(sv_2mortal(newSVpvs("fallthrough")));
    }

    /* expr() -- undef when empty, matching the expr XSUB */
    {
        const std::string& e = impl->expr();
        if (e.empty())
            PUSHs(&PL_sv_undef);
        else
            PUSHs(sv_2mortal(newSVpv(e.c_str(), e.size())));
    }

    /* tla() and the base half of diff_count(), or undef/undef.
     * The scalar tla()/diff_count() XSUBs croak on non-differential data;
     * here the caller asks for everything at once and decides, so report
     * absence as undef instead. */
    if (impl->isDifferential()) {
        const std::string& tla_str = impl->tla();
        PUSHs(sv_2mortal(newSVpv(tla_str.c_str(), tla_str.size())));
        if (impl->hasBase())
            PUSHs(sv_2mortal(newSViv(impl->base())));
        else
            PUSHs(&PL_sv_undef);
    } else {
        PUSHs(&PL_sv_undef);
        PUSHs(&PL_sv_undef);
    }
    XSRETURN(7);

void
write_data(self)
    SV* self
  PPCODE:
    /* Batch accessor for the '.info' writer, which needs every field of every
     * element it emits and otherwise makes six separate XSUB calls per BRDA
     * record (data, id, expr, signature, and is_excluded twice).  One crossing
     * instead of six, on a path executed once per written branch.
     *
     * Returns a flat list, always the same arity and order:
     *   ($taken, $id, $expr, $signature, $excluded)
     * matching MCDC_Expression::write_data and the pure-Perl
     * BranchElement::write_data exactly.
     *
     * Every field is read through the SAME C++ accessor the scalar XSUB uses,
     * so the batch and scalar paths cannot drift apart. */
    BranchElement* impl = sv_to_branchelement(self);
    EXTEND(SP, 5);

    /* data() -- '-' or an integer */
    if (impl->data() == BranchElement::DASH)
        PUSHs(sv_2mortal(newSVpvs("-")));
    else
        PUSHs(sv_2mortal(newSViv(impl->data())));

    /* id() -- stringified, as the id XSUB returns it */
    {
        std::string id_str = std::to_string(impl->id());
        PUSHs(sv_2mortal(newSVpv(id_str.c_str(), id_str.size())));
    }

    /* expr() -- undef when empty, matching the expr XSUB */
    {
        const std::string& e = impl->expr();
        if (e.empty())
            PUSHs(&PL_sv_undef);
        else
            PUSHs(sv_2mortal(newSVpv(e.c_str(), e.size())));
    }

    /* signature() -- 'b' / 'e' / 'f' */
    {
        char sig = impl->signature();
        PUSHs(sv_2mortal(newSVpvn(&sig, 1)));
    }

    /* is_excluded() */
    PUSHs(sv_2mortal(newSViv(impl->isExcluded() ? 1 : 0)));
    XSRETURN(5);

# ---------------------------------------------------------------------------
# BranchBlock -- C++ struct behind IV pointer
# ---------------------------------------------------------------------------

MODULE = LcovUtil    PACKAGE = BranchBlock

SV*
new(klass)
    char* klass
  CODE:
    BranchBlock* impl = new BranchBlock();
    RETVAL = make_branchblock_sv(impl, klass);
  OUTPUT:
    RETVAL

void
DESTROY(self)
    SV* self
  CODE:
    if (!branchblock_is_borrowed(self)) {
        BranchBlock* impl = sv_to_branchblock(self);
        SvIV_set(SvRV(self), 0);
        delete impl;
    }

SV*
idx(self)
    SV* self
  CODE:
    BranchBlock* impl = sv_to_branchblock(self);
    RETVAL = newSViv(impl->idx());
  OUTPUT:
    RETVAL

SV*
signature(self)
    SV* self
  CODE:
    BranchBlock* impl = sv_to_branchblock(self);
    const std::string& sig = impl->signature();
    RETVAL = newSVpv(sig.c_str(), sig.size());
  OUTPUT:
    RETVAL

int
empty(self)
    SV* self
  CODE:
    RETVAL = sv_to_branchblock(self)->elements().empty() ? 1 : 0;
  OUTPUT:
    RETVAL

SV*
elements(self)
    SV* self
  CODE:
    BranchBlock* impl = sv_to_branchblock(self);
    AV* av = newAV();
    const std::vector<BranchElement>& elems = impl->elements();
    for (size_t i = 0; i < elems.size(); ++i)
        av_push(av, borrow_branchelement(const_cast<BranchElement*>(&elems[i]), "BranchElement"));
    RETVAL = newRV_noinc((SV*)av);
  OUTPUT:
    RETVAL

SV*
getElement(self, idx)
    SV* self
    IV  idx
  CODE:
    BranchBlock* impl = sv_to_branchblock(self);
    const std::vector<BranchElement>& elems = impl->elements();
    if (idx < 0 || (size_t)idx >= elems.size())
        croak("index out of range");
    RETVAL = borrow_branchelement(const_cast<BranchElement*>(&elems[(size_t)idx]), "BranchElement");
  OUTPUT:
    RETVAL

void
setIdx(self, idx)
    SV* self
    SV* idx
  CODE:
    sv_to_branchblock(self)->setIdx(SvIV(idx));

void
appendElement(self, element)
    SV* self
    SV* element
  CODE:
    BranchBlock* impl = sv_to_branchblock(self);
    BranchElement* e  = sv_to_branchelement(element);
    impl->appendElement(*e);

void
appendNew(self, id, taken, expr, type, excluded)
    SV* self
    SV* id
    SV* taken
    SV* expr
    SV* type
    SV* excluded
  CODE:
    /* appendElement(BranchElement->new(...)) in one step - see the pure-Perl
     * BranchBlock::appendNew.  Reading a '.info' file appends every branch
     * coverpoint and keeps none of the elements, so going through
     * BranchElement::new costs a heap object plus a blessed SV wrapper per
     * record which are copied into the block's vector and immediately thrown
     * away again.  Here the element is built as a value and moved straight in. */
    BranchBlock* impl = sv_to_branchblock(self);
    impl->appendElement(
        build_branchelement(id, taken, expr, type, excluded));

int
merge(self, you, ...)
    SV* self
    SV* you
  CODE:
    /* merge($self, $you, $filename, $line) */
    BranchBlock* s = sv_to_branchblock(self);
    BranchBlock* y = sv_to_branchblock(you);
    const char* filename = (items >= 3 && SvOK(ST(2))) ? SvPV_nolen(ST(2)) : "";
    IV line = (items >= 4) ? SvIV(ST(3)) : 0;

    /* C++ merge() throws std::runtime_error("expected identical block") on a
     * size/signature mismatch.  Let that escape and it reaches the C++ runtime
     * as an uncaught exception -> terminate()/abort, which Perl cannot trap.
     * Convert it to croak() so it surfaces as a normal Perl die, matching the
     * pure-Perl BranchBlock::merge die("expected identical block"). */
    try {
        RETVAL = s->merge(*y, filename, line);
    } catch (const std::exception& e) {
        croak("%s", e.what());
    }
  OUTPUT:
    RETVAL

# Storable hooks
void
STORABLE_freeze(self, cloning)
    SV* self
    SV* cloning
  PPCODE:
    BranchBlock* impl = sv_to_branchblock(self);
    lcov_binary::BinaryWriter w;
    branchblock_write(w, impl);
    const std::vector<uint8_t>& buf = w.data();
    XPUSHs(sv_2mortal(newSVpvn(reinterpret_cast<const char*>(buf.data()), buf.size())));

void
STORABLE_thaw(self, cloning, serialized, ...)
    SV* self
    SV* cloning
    SV* serialized
  CODE:
    /* Storable's thaw contract is STORABLE_thaw(self, cloning, serialized, @refs).
     * Our freeze hook pushes a SINGLE flat binary scalar and no data refs, so the
     * frozen bytes arrive as the `serialized` argument at ST(2) -- NOT ST(3).
     * (MapData reads ST(3) only because its freeze pushes two items: an empty tag
     * at ST(2) plus a data ref at ST(3).)  Reading ST(3) -- or requiring items>=4
     * -- would croak "missing frozen data" whenever these per-object hooks fire
     * directly, e.g. Storable::dclone() of a bare MCDC_Block/BranchElement, which
     * recurses into the per-object hook rather than the flattened container hook
     * that geninfo's top-level serialize uses. */
    if (items < 3)
        croak("STORABLE_thaw: missing frozen data");
    STRLEN len;
    const uint8_t* data = (const uint8_t*)SvPVbyte(serialized, len);
    lcov_binary::BinaryReader r(data, len);
    BranchBlock* impl = new BranchBlock(branchblock_read(r));
    SvIV_set(SvRV(self), (IV)(intptr_t)impl);
    SvIOK_on(SvRV(self));

# ---------------------------------------------------------------------------
# BranchLocation -- C++ struct behind IV pointer
# ---------------------------------------------------------------------------

MODULE = LcovUtil    PACKAGE = BranchLocation

SV*
new(klass, line)
    char* klass
    SV*   line
  CODE:
    /* Pure Perl stores $line verbatim; preserve a non-numeric key (e.g. the
     * differential "deleted line" marker "<<<123") so line() round-trips it,
     * and avoid SvIV() on it (which would warn "isn't numeric"). */
    bool numeric = (!line || looks_like_number(line));
    BranchLocation* impl = new BranchLocation(numeric ? (int32_t)SvIV(line) : 0);
    if (line && SvOK(line) && !numeric) {
        STRLEN llen; const char* lstr = SvPV(line, llen);
        impl->set_line_label(std::string(lstr, llen));
    }
    RETVAL = make_branchlocation_sv(impl, klass);
  OUTPUT:
    RETVAL

void
DESTROY(self)
    SV* self
  CODE:
    if (!branchlocation_is_borrowed(self)) {
        BranchLocation* impl = sv_to_branchlocation(self);
        SvIV_set(SvRV(self), 0);
        delete impl;
    }

SV*
line(self)
    SV* self
  CODE:
    {
        BranchLocation* impl = sv_to_branchlocation(self);
        const std::string& label = impl->line_label();
        RETVAL = label.empty() ? newSViv(impl->line())
                               : newSVpvn(label.c_str(), label.size());
    }
  OUTPUT:
    RETVAL

int
containsCode(self, code)
    SV* self
    SV* code
  CODE:
    BranchLocation* impl = sv_to_branchlocation(self);
    STRLEN len; const char* cstr = SvPV(code, len);
    RETVAL = impl->containsCode(std::string(cstr, len)) ? 1 : 0;
  OUTPUT:
    RETVAL

int
hasBlock(self, id)
    SV* self
    IV  id
  CODE:
    BranchLocation* impl = sv_to_branchlocation(self);
    RETVAL = impl->hasBlock(id) ? 1 : 0;
  OUTPUT:
    RETVAL

IV
numBlocks(self)
    SV* self
  CODE:
    RETVAL = (IV)sv_to_branchlocation(self)->numBlocks();
  OUTPUT:
    RETVAL

SV*
getBlock(self, id)
    SV* self
    IV  id
  CODE:
    BranchLocation* impl = sv_to_branchlocation(self);
    try {
        BranchBlock& block = impl->getBlock(id);
        /* Borrowed reference:  the block is owned by BranchLocation's block vector
         * and the borrow is only valid until that vector reallocates (insertBlock)
         * or renumbers (removeBlock). */
        RETVAL = borrow_branchblock(&block, "BranchBlock");
    } catch (const std::out_of_range& e) {
        croak("getBlock: unknown block %d", (int)id);
    }
  OUTPUT:
    RETVAL

SV*
getList(self, code)
    SV* self
    SV* code
  CODE:
    BranchLocation* impl = sv_to_branchlocation(self);
    STRLEN len; const char* cstr = SvPV(code, len);
    std::string code_str(cstr, len);
    if (!impl->containsCode(code_str))
        croak("%s not found", cstr);
    const std::vector<int32_t>& positions = impl->getList(code_str);
    AV* av = newAV();
    for (int32_t id : positions) {
        BranchBlock& block = impl->getBlock(id);
        /* Borrowed reference:  the block lives in BranchLocation's block vector */
        av_push(av, borrow_branchblock(&block, "BranchBlock"));
    }
    RETVAL = newRV_noinc((SV*)av);
  OUTPUT:
    RETVAL

void
blocks(self, ...)
    SV* self
  PPCODE:
    BranchLocation* impl = sv_to_branchlocation(self);
    int do_sort = (items >= 2 && SvOK(ST(1)) && SvTRUE(ST(1))) ? 1 : 0;
    /* Pure Perl is 'return @$list', so scalar context yields the COUNT.  A
     * bare PPCODE list-push would instead leave the last block on the stack --
     * a silent XS-vs-pure divergence for any caller that says
     * 'scalar($loc->blocks())' or uses the result in numeric context.  All
     * current callers are list context; answer the count anyway so they agree. */
    if (GIMME_V == G_SCALAR) {
        XPUSHs(sv_2mortal(newSViv((IV)impl->numBlocks())));
        XSRETURN(1);
    }
    std::vector<BranchBlock*> block_ptrs = impl->blocks(do_sort);
    for (BranchBlock* blk : block_ptrs) {
        /* Borrowed reference:  the blocks live in BranchLocation's block vector */
        /* Borrowed SVs should be mortal so Perl cleans up the SV wrapper (not the underlying object) */
        SV* blksv = borrow_branchblock(blk, "BranchBlock");
        XPUSHs(sv_2mortal(blksv));
    }

void
codes(self, ...)
    SV* self
  PPCODE:
    BranchLocation* impl = sv_to_branchlocation(self);
    int do_sort = (items >= 2 && SvOK(ST(1)) && SvTRUE(ST(1))) ? 1 : 0;
    /* Scalar context must be the count, matching pure Perl's 'return @keys'
     * -- see the note in blocks() above. */
    if (GIMME_V == G_SCALAR) {
        XPUSHs(sv_2mortal(newSViv((IV)impl->numCodes())));
        XSRETURN(1);
    }
    std::vector<std::string> code_list = impl->codes(do_sort);
    for (const std::string& code : code_list)
        XPUSHs(sv_2mortal(newSVpv(code.c_str(), code.size())));

void
insertBlock(self, branchBlock, ...)
    SV* self
    SV* branchBlock
  CODE:
    BranchLocation* impl = sv_to_branchlocation(self);
    BranchBlock*    blk  = sv_to_branchblock(branchBlock);

    /* insertBlock appends, so the id it assigns is the pre-insertion block
     * count -- the same '$#$list + 1' pure-Perl insertBlock computes. */
    size_t old_count = impl->numBlocks();

    /* Rejects an element-less block ('unexpected empty block'), as pure Perl
     * does.  The message is copied out and croaked after the handler has run:
     * croak longjmps, so raising it from inside the catch would skip the
     * exception object's destructor. */
    std::string err;
    try {
        impl->insertBlock(*blk);
    } catch (const std::out_of_range& ex) {
        err = ex.what();
    }
    if (!err.empty())
        croak("%s", err.c_str());

    /* insertBlock() took a COPY, so it set the idx on that copy;  publish the
     * assigned id back to the caller's block, exactly as pure-Perl insertBlock
     * does with '$branchBlock->setIdx($blockIdx)'.  Unconditionally:  a block
     * whose idx is already non-zero is being re-inserted at a new position, and
     * skipping the publish would leave it reporting its OLD position. */
    blk->setIdx((int32_t)old_count);

void
removeBlock(self, block, branchData)
    SV* self
    SV* block
    SV* branchData
  CODE:
    BranchLocation* impl = sv_to_branchlocation(self);
    BranchBlock*    blk  = sv_to_branchblock(block);
    IV id = blk->idx();

    /* Call branchData->removeBranches($block) BEFORE removing block from C++ container.
     * removeBranches needs to access $block->elements(), which will be invalid after removal. */
    {
        dSP; ENTER; SAVETMPS; PUSHMARK(SP);
        XPUSHs(branchData);
        XPUSHs(block);
        PUTBACK; call_method("removeBranches", G_DISCARD);
        FREETMPS; LEAVE;
    }

    /* Now remove the block from the location - this handles index management and code map */
    try {
        impl->removeBlock(id, nullptr);
    } catch (const std::out_of_range& e) {
        croak("%s", e.what());
    }

void
totals(self, ...)
    SV* self
  PPCODE:
    /* Without this XSUB the pure-Perl BranchLocation::totals runs in both
     * backends: under XS it crosses back into the XS layer once per block
     * (blocks(), elements()) and twice per element (is_excluded(), count()),
     * roughly a dozen crossings to answer two integers.  Doing the walk in C++
     * collapses that to one.  MCDC_Block::totals already had an XSUB; this
     * closes the asymmetry. */
    bool count_excluded = (items >= 2 && SvOK(ST(1)) && SvTRUE(ST(1)));
    auto p = sv_to_branchlocation(self)->totals(count_excluded);
    XPUSHs(sv_2mortal(newSViv((IV)p.first)));
    XPUSHs(sv_2mortal(newSViv((IV)p.second)));

int
hasHitElement(self, ...)
    SV* self
  CODE:
    bool count_excluded = (items >= 2 && SvOK(ST(1)) && SvTRUE(ST(1)));
    RETVAL = sv_to_branchlocation(self)->hasHitElement(count_excluded) ? 1 : 0;
  OUTPUT:
    RETVAL

int
merge(self, that, filename)
    SV* self
    SV* that
    SV* filename
  CODE:
    BranchLocation* impl = sv_to_branchlocation(self);
    BranchLocation* that_impl = sv_to_branchlocation(that);
    std::string fname;
    if (SvOK(filename)) {
        STRLEN len;
        const char* s = SvPV(filename, len);
        fname = std::string(s, len);
    }
    RETVAL = impl->merge(*that_impl, fname);
  OUTPUT:
    RETVAL

# Storable hooks
void
STORABLE_freeze(self, cloning)
    SV* self
    SV* cloning
  PPCODE:
    BranchLocation* impl = sv_to_branchlocation(self);
    lcov_binary::BinaryWriter w;
    branchlocation_write(w, impl);
    const std::vector<uint8_t>& buf = w.data();
    XPUSHs(sv_2mortal(newSVpvn(reinterpret_cast<const char*>(buf.data()), buf.size())));

void
STORABLE_thaw(self, cloning, serialized, ...)
    SV* self
    SV* cloning
    SV* serialized
  CODE:
    /* Storable's thaw contract is STORABLE_thaw(self, cloning, serialized, @refs).
     * Our freeze hook pushes a SINGLE flat binary scalar and no data refs, so the
     * frozen bytes arrive as the `serialized` argument at ST(2) -- NOT ST(3).
     * (MapData reads ST(3) only because its freeze pushes two items: an empty tag
     * at ST(2) plus a data ref at ST(3).)  Reading ST(3) -- or requiring items>=4
     * -- would croak "missing frozen data" whenever these per-object hooks fire
     * directly, e.g. Storable::dclone() of a bare MCDC_Block/BranchElement, which
     * recurses into the per-object hook rather than the flattened container hook
     * that geninfo's top-level serialize uses. */
    if (items < 3)
        croak("STORABLE_thaw: missing frozen data");
    STRLEN len;
    const uint8_t* data = (const uint8_t*)SvPVbyte(serialized, len);
    lcov_binary::BinaryReader r(data, len);
    BranchLocation* impl = new BranchLocation(branchlocation_read(r));
    SvIV_set(SvRV(self), (IV)(intptr_t)impl);
    SvIOK_on(SvRV(self));

# ---------------------------------------------------------------------------
# MCDC_Block  -- MCDC_Block_wrapper around a single C++ MCDC_Block
# ---------------------------------------------------------------------------

MODULE = LcovUtil    PACKAGE = MCDC_Block

SV*
new(klass, line)
    char* klass
    SV*   line
  CODE:
    /* Owning wrapper: it allocates and will delete the C++ block.
     * Pure Perl stores $line verbatim; preserve a non-numeric key (e.g. the
     * differential "deleted line" marker "<<<123") so line() round-trips it,
     * and avoid SvIV() on it (which would warn "isn't numeric"). */
    bool numeric = (!line || looks_like_number(line));
    MCDC_Block* blk = new MCDC_Block(numeric ? (int32_t)SvIV(line) : 0);
    if (line && SvOK(line) && !numeric) {
        STRLEN llen; const char* lstr = SvPV(line, llen);
        blk->set_line_label(std::string(lstr, llen));
    }
    MCDC_Block_wrapper* w = new MCDC_Block_wrapper(blk, true);
    RETVAL = make_mcdcblock_sv(w, klass);
  OUTPUT:
    RETVAL

void
DESTROY(self)
    SV* self
  CODE:
    if (SvROK(self) && SvIOK(SvRV(self))) {
        MCDC_Block_wrapper* w = (MCDC_Block_wrapper*)(intptr_t)SvIV(SvRV(self));
        if (w) {
            delete w; SvIV_set(SvRV(self), 0);
        }
    }

SV*
line(self)
    SV* self
  CODE:
    {
        MCDC_Block* blk = sv_to_mcdcblock(self)->block;
        const std::string& label = blk->line_label();
        RETVAL = label.empty() ? newSViv(blk->line())
                               : newSVpvn(label.c_str(), label.size());
    }
  OUTPUT:
    RETVAL

SV*
groups(self)
    SV* self
  CODE:
    /* Return a cached HV so that callers using while(each(%{$block->groups}))
     * always get the same hash -- if we built a new one on each call, 'each'
     * would restart from the beginning every iteration (infinite loop).
     * Cache is invalidated by insertExpr, merge, and STORABLE_thaw.
     *
     * Expression wrappers hold strong refs (owns_parent=true) to parent_sv so
     * that any wrapper that escapes groups_sv (e.g. into a Perl @blocks array)
     * keeps the block wrapper alive.  The reference cycle this creates is
     * broken explicitly in MCDC_Block_wrapper::_destroy_groups_sv() which zeros
     * each wrapper's parent_sv before dropping groups_sv's refcount. */

    /* Validate self before dereferencing */
    if (!self || !SvROK(self))
        croak("groups: self is not a reference");
    SV* inner = SvRV(self);
    if (!SvIOK(inner))
        croak("groups: self is not an IV");

    MCDC_Block_wrapper* w = sv_to_mcdcblock(self);
    if (!w)
        croak("groups: NULL wrapper");

    /* CRITICAL: groups_sv may contain uninitialized garbage. The constructor
       initializes it to nullptr, but other creation paths (STORABLE_thaw) may not.
       Never access groups_sv unless it's non-null - checking its value when it's
       garbage causes heap corruption. */
    bool need_rebuild = (w->groups_sv == nullptr);

    if (need_rebuild) {
        /* Use self (the current method receiver) as canon_parent.
         * self is alive for the duration of this call, and owns_parent=true
         * keeps it alive as long as any expression wrapper survives. */
        SV* canon_parent = self;
        HV* ghv = newHV();
        w->block->for_each_group([&](int32_t gs,
                                     std::vector<MCDC_Expression>& exprs) {
            std::string ks = std::to_string(gs);
            AV* earr = newAV();
            for (size_t i = 0; i < exprs.size(); ++i) {
                MCDC_Expression* ep = &exprs[i];
                SV* esv = make_mcdcexpr_sv(ep, canon_parent, "MCDC_Expression",
                                            true);  /* owns_parent=true */
                av_push(earr, esv);
            }
            hv_store(ghv, ks.c_str(), ks.size(), newRV_noinc((SV*)earr), 0);
        });
        w->groups_sv = newRV_noinc((SV*)ghv);
    }
    RETVAL = SvREFCNT_inc(w->groups_sv);
  OUTPUT:
    RETVAL

IV
num_groups(self)
    SV* self
  CODE:
    RETVAL = (IV)sv_to_mcdcblock(self)->block->num_groups();
  OUTPUT:
    RETVAL

SV*
expressions(self, size)
    SV* self
    IV  size
  CODE:
    MCDC_Block_wrapper* w = sv_to_mcdcblock(self);
    std::vector<MCDC_Expression>* vec = w->block->expressions((int32_t)size);
    if (!vec) {
        RETVAL = SvREFCNT_inc(&PL_sv_undef);
    } else {
        AV* earr = newAV();
        for (size_t i = 0; i < vec->size(); ++i) {
            MCDC_Expression* ep = &(*vec)[i];
            av_push(earr, make_mcdcexpr_sv(ep, self, "MCDC_Expression"));
        }
        RETVAL = newRV_noinc((SV*)earr);
    }
  OUTPUT:
    RETVAL

SV*
expr(self, groupSize, idx)
    SV* self
    IV  groupSize
    IV  idx
  CODE:
    MCDC_Block_wrapper* w = sv_to_mcdcblock(self);
    /* expr() throws on an unknown group size or an out-of-range index -- there
     * is no such thing as a legitimately missing expression, so this reports
     * the bad request instead of returning undef.  The message is copied out
     * and croaked after the handler has run:  croak longjmps, so raising it
     * from inside the catch would skip the exception object's destructor. */
    std::string err;
    MCDC_Expression* e = NULL;
    try {
        e = w->block->expr((int32_t)groupSize, (int32_t)idx);
    } catch (const std::out_of_range& ex) {
        err = ex.what();
    }
    if (!err.empty())
        croak("%s", err.c_str());
    RETVAL = make_mcdcexpr_sv(e, self, "MCDC_Expression");
  OUTPUT:
    RETVAL

void
insertExpr(self, filename, groupSize, sense, count, idx, expr_str, ...)
    SV* self
    SV* filename
    IV  groupSize
    IV  sense
    SV* count
    IV  idx
    SV* expr_str
  CODE:
    /* excluded is optional (8th arg, index 7); defaults to false */
    bool excluded_flag = (items >= 8 && SvOK(ST(7)) && SvTRUE(ST(7)));
    MCDC_Block_wrapper* w = sv_to_mcdcblock(self);
    if (!w) {
        croak("insertExpr: NULL wrapper pointer");
    }
    /* Autovivifies the group, exactly as pure Perl's
       'push @{$self->[GROUPS]{$groupSize}}' does.  The reference stays valid for
       the rest of this XSUB:  find_or_create_group is the only call here that
       can change the block's shape, and it is called once. */
    auto& vec = w->block->find_or_create_group((int32_t)groupSize);
    STRLEN elen; const char* es = SvOK(expr_str) ? SvPV(expr_str, elen) : "";
    std::string estr(es, SvOK(expr_str) ? elen : 0);
    if ((size_t)idx < vec.size()) {
        /* existing slot -- check expression consistency */
        const std::string& old_expr = vec[(size_t)idx].expression();
        if (old_expr != estr) {
            dSP; ENTER; SAVETMPS; PUSHMARK(SP);
            SV* errType = get_sv("lcovutil::ERROR_INCONSISTENT_DATA", 0);
            std::string msg = "\"" +
                std::string(SvOK(filename) ? SvPV_nolen(filename) : "") +
                "\":" + std::to_string(w->line()) +
                ": MC/DC group " + std::to_string(groupSize) +
                " expression " + std::to_string(idx) +
                " changed from '" + old_expr +
                "' to '" + estr + "'";
            XPUSHs(errType ? errType : &PL_sv_undef);
            XPUSHs(sv_2mortal(newSVpv(msg.c_str(), msg.size())));
            PUTBACK; call_pv("lcovutil::ignorable_error", G_DISCARD);
            FREETMPS; LEAVE;
        }
    } else {
        /* new slot -- validate contiguity */
        if ((size_t)idx != vec.size()) {
            dSP; ENTER; SAVETMPS; PUSHMARK(SP);
            SV* errType = get_sv("lcovutil::ERROR_FORMAT", 0);
            std::string msg = "\"" +
                std::string(SvOK(filename) ? SvPV_nolen(filename) : "") +
                "\":" + std::to_string(w->line()) +
                ": MC/DC group " + std::to_string(groupSize) +
                ": non-contiguous expression '" + std::to_string(idx) +
                "' found - should be '" + std::to_string(vec.size()) + "'.";
            XPUSHs(errType ? errType : &PL_sv_undef);
            XPUSHs(sv_2mortal(newSVpv(msg.c_str(), msg.size())));
            PUTBACK; call_pv("lcovutil::ignorable_error", G_DISCARD);
            FREETMPS; LEAVE;
        }
        vec.push_back(MCDC_Expression((int32_t)groupSize, (int32_t)idx, estr));
    }
    /* Structural change -- any escaped expr wrappers point into 'vec', which may
       have reallocated; drop the cached groups HV so it is rebuilt on next use. */
    w->invalidate_groups_cache();
    if ((size_t)idx < vec.size())
        mcdcexpr_set(&vec[(size_t)idx], (int)sense, count, excluded_flag);

void
totals(self, ...)
    SV* self
  PPCODE:
    bool count_excluded = (items >= 2 && SvOK(ST(1)) && SvTRUE(ST(1)));
    auto p = sv_to_mcdcblock(self)->block->totals(count_excluded);
    XPUSHs(sv_2mortal(newSViv((IV)p.first)));
    XPUSHs(sv_2mortal(newSViv((IV)p.second)));

int
is_compatible(self, you)
    SV* self
    SV* you
  CODE:
    RETVAL = sv_to_mcdcblock(self)->block->is_compatible(
                 *sv_to_mcdcblock(you)->block) ? 1 : 0;
  OUTPUT:
    RETVAL

int
merge(self, you, filename)
    SV* self
    SV* you
    SV* filename
  CODE:
    {
        MCDC_Block_wrapper* w = sv_to_mcdcblock(self);
        std::string fn;
        if (SvOK(filename)) {
            STRLEN len; const char* s = SvPV(filename, len);
            fn = std::string(s, len);
        }
        RETVAL = w->block->merge(*sv_to_mcdcblock(you)->block, fn);
        if (RETVAL)
            w->invalidate_groups_cache();
    }
  OUTPUT:
    RETVAL

void
STORABLE_freeze(self, cloning)
    SV* self
    SV* cloning
  PPCODE:
    lcov_binary::BinaryWriter bw;
    mcdcblock_write(bw, sv_to_mcdcblock(self)->block);
    const std::vector<uint8_t>& buf = bw.data();
    XPUSHs(sv_2mortal(newSVpvn(reinterpret_cast<const char*>(buf.data()), buf.size())));

void
STORABLE_thaw(self, cloning, serialized, ...)
    SV* self
    SV* cloning
    SV* serialized
  CODE:
    /* Storable's thaw contract is STORABLE_thaw(self, cloning, serialized, @refs).
     * Our freeze hook pushes a SINGLE flat binary scalar and no data refs, so the
     * frozen bytes arrive as the `serialized` argument at ST(2) -- NOT ST(3).
     * (MapData reads ST(3) only because its freeze pushes two items: an empty tag
     * at ST(2) plus a data ref at ST(3).)  Reading ST(3) -- or requiring items>=4
     * -- would croak "missing frozen data" whenever these per-object hooks fire
     * directly, e.g. Storable::dclone() of a bare MCDC_Block/BranchElement, which
     * recurses into the per-object hook rather than the flattened container hook
     * that geninfo's top-level serialize uses. */
    if (items < 3)
        croak("STORABLE_thaw: missing frozen data");
    STRLEN len;
    const uint8_t* data = (const uint8_t*)SvPVbyte(serialized, len);
    lcov_binary::BinaryReader r(data, len);
    /* Owning wrapper around the freshly-thawed C++ block. */
    MCDC_Block_wrapper* w = new MCDC_Block_wrapper(mcdcblock_read(r), true);
    SvIV_set(SvRV(self), (IV)(intptr_t)w);
    SvIOK_on(SvRV(self));
    w->parent_sv = self;

# ---------------------------------------------------------------------------
# MCDC_Expression  -- wrapper around MCDC_Expression (owned by MCDC_Block)
# ---------------------------------------------------------------------------

MODULE = LcovUtil    PACKAGE = MCDC_Expression

void
DESTROY(self)
    SV* self
  CODE:
    if (SvROK(self) && SvIOK(SvRV(self))) {
        MCDC_Expression_wrapper* w =
            (MCDC_Expression_wrapper*)(intptr_t)SvIV(SvRV(self));
        if (w) {
            if (w->owns_parent && w->parent_sv)
                SvREFCNT_dec(w->parent_sv);
            delete w;
            SvIV_set(SvRV(self), 0);
        }
    }

SV*
parent(self)
    SV* self
  CODE:
    MCDC_Expression_wrapper* w = sv_to_mcdcexpr_wrapper(self);
    if (!w->parent_sv) { RETVAL = &PL_sv_undef; SvREFCNT_inc(RETVAL); }
    else
        RETVAL = SvREFCNT_inc(w->parent_sv);
  OUTPUT:
    RETVAL

IV
groupSize(self)
    SV* self
  CODE:
    RETVAL = (IV)sv_to_mcdcexpr_wrapper(self)->expr->groupSize();
  OUTPUT:
    RETVAL

IV
index(self)
    SV* self
  CODE:
    RETVAL = (IV)sv_to_mcdcexpr_wrapper(self)->expr->index();
  OUTPUT:
    RETVAL

SV*
expression(self)
    SV* self
  CODE:
    const std::string& e = sv_to_mcdcexpr_wrapper(self)->expr->expression();
    RETVAL = newSVpv(e.c_str(), e.size());
  OUTPUT:
    RETVAL

IV
is_excluded(self, sense)
    SV* self
    IV  sense
  CODE:
    RETVAL = sv_to_mcdcexpr_wrapper(self)->expr->is_excluded(sense ? 1 : 0) ? 1 : 0;
  OUTPUT:
    RETVAL

int
set_excluded(self, sense)
    SV* self
    IV  sense
  CODE:
    MCDC_Expression* e = sv_to_mcdcexpr_wrapper(self)->expr;
    int s = sense ? 1 : 0;
    bool was_excluded = e->is_excluded(s);
    if (was_excluded) { RETVAL = 0; }
    else { e->set(s, e->count(s), true); RETVAL = 1; }
  OUTPUT:
    RETVAL

SV*
count(self, ...)
    SV* self
  CODE:
    MCDC_Expression* e = sv_to_mcdcexpr_wrapper(self)->expr;
    IV sense = (items >= 2 && SvOK(ST(1))) ? SvIV(ST(1)) : 0;
    int s = sense ? 1 : 0;
    if (e->isDifferential(s)) {
        /* Return [$tla, $base, $curr] -- mirrors pure-Perl format */
        AV* arr = newAV();
        const std::string& tla_str = e->tla(s);
        av_push(arr, newSVpv(tla_str.c_str(), tla_str.size()));

        /* base and curr can be independently defined or undef */
        if (e->hasBase(s)) {
            av_push(arr, newSViv(e->base(s)));
        } else {
            av_push(arr, newSV(0));  /* undef base */
        }
        if (e->hasCurr(s)) {
            av_push(arr, newSViv(e->curr(s)));
        } else {
            av_push(arr, newSV(0));  /* undef curr */
        }
        RETVAL = newRV_noinc((SV*)arr);
    } else {
        RETVAL = newSViv(e->count(s));
    }
  OUTPUT:
    RETVAL

int
set(self, sense, count, ...)
    SV* self
    IV  sense
    SV* count
  CODE:
    bool excl = (items >= 4 && SvOK(ST(3)) && SvTRUE(ST(3)));
    RETVAL = mcdcexpr_set(sv_to_mcdcexpr_wrapper(self)->expr,
                          (int)sense, count, excl);
  OUTPUT:
    RETVAL

void
write_data(self)
    SV* self
  PPCODE:
    /* Batch accessor for the '.info' writer, which emits both senses of every
     * expression and otherwise makes six separate XSUB calls per expression
     * (count, is_excluded and expression, twice over).  One crossing instead
     * of six.
     *
     * Returns a flat list, always the same arity and order:
     *   ($count_false, $count_true, $excluded_false, $excluded_true, $expr)
     * The counts mirror count($sense) exactly: an ARRAY ref [tla, base, curr]
     * for differential data, otherwise a plain integer.
     *
     * Every field is read through the SAME C++ accessor the scalar XSUB uses,
     * so the batch and scalar paths cannot drift apart. */
    MCDC_Expression* e = sv_to_mcdcexpr_wrapper(self)->expr;
    EXTEND(SP, 5);

    /* count(0) then count(1) -- identical construction to the count XSUB */
    for (int s = 0; s <= 1; ++s) {
        if (e->isDifferential(s)) {
            AV* arr = newAV();
            const std::string& tla_str = e->tla(s);
            av_push(arr, newSVpv(tla_str.c_str(), tla_str.size()));
            if (e->hasBase(s))
                av_push(arr, newSViv(e->base(s)));
            else
                av_push(arr, newSV(0));
            if (e->hasCurr(s))
                av_push(arr, newSViv(e->curr(s)));
            else
                av_push(arr, newSV(0));
            PUSHs(sv_2mortal(newRV_noinc((SV*)arr)));
        } else {
            PUSHs(sv_2mortal(newSViv(e->count(s))));
        }
    }

    /* is_excluded(0) then is_excluded(1) */
    PUSHs(sv_2mortal(newSViv(e->is_excluded(0) ? 1 : 0)));
    PUSHs(sv_2mortal(newSViv(e->is_excluded(1) ? 1 : 0)));

    /* expression() */
    {
        const std::string& ex = e->expression();
        PUSHs(sv_2mortal(newSVpv(ex.c_str(), ex.size())));
    }
    XSRETURN(5);

void
render_data(self, sense)
    SV* self
    IV  sense
  PPCODE:
    /* Batch accessor for the genhtml MC/DC source-view render loop, which
     * otherwise makes 5 XSUB calls per (expression, sense): count, expression,
     * is_excluded, plus parent() and num_groups() -- and parent() allocates an
     * SV and bumps a refcount purely to ask the block a question whose answer
     * is the same for every expression in it.
     *
     * Returns a flat list, always the same arity and order:
     *   (count, expression, is_excluded, multi_group)
     * count mirrors count($sense) exactly: an ARRAY ref [tla, base, curr] for
     * differential data, otherwise a plain integer.  multi_group is
     * parent()->num_groups() > 1, read straight off the borrowed parent block
     * without materializing a Perl object for it.
     *
     * Every field is read through the SAME C++ accessor the scalar XSUB uses,
     * so the batch and scalar paths cannot drift apart. */
    MCDC_Expression_wrapper* w = sv_to_mcdcexpr_wrapper(self);
    MCDC_Expression* e = w->expr;
    int s = sense ? 1 : 0;
    EXTEND(SP, 4);

    /* count($sense) -- identical construction to the count XSUB */
    if (e->isDifferential(s)) {
        AV* arr = newAV();
        const std::string& tla_str = e->tla(s);
        av_push(arr, newSVpv(tla_str.c_str(), tla_str.size()));
        if (e->hasBase(s))
            av_push(arr, newSViv(e->base(s)));
        else
            av_push(arr, newSV(0));
        if (e->hasCurr(s))
            av_push(arr, newSViv(e->curr(s)));
        else
            av_push(arr, newSV(0));
        PUSHs(sv_2mortal(newRV_noinc((SV*)arr)));
    } else {
        PUSHs(sv_2mortal(newSViv(e->count(s))));
    }

    /* expression() */
    {
        const std::string& ex = e->expression();
        PUSHs(sv_2mortal(newSVpv(ex.c_str(), ex.size())));
    }

    /* is_excluded($sense) */
    PUSHs(sv_2mortal(newSViv(e->is_excluded(s) ? 1 : 0)));

    /* parent()->num_groups() > 1, without building the parent's Perl object.
     * parent_sv is zeroed when the owning block is destroyed, so a surviving
     * stale wrapper reports 0 groups rather than dereferencing a dangling
     * pointer -- the same defensive behaviour as the parent() XSUB returning
     * undef. */
    {
        bool multi = false;
        if (w->parent_sv) {
            MCDC_Block_wrapper* bw = sv_to_mcdcblock(w->parent_sv);
            if (bw && bw->block)
                multi = (bw->block->num_groups() > 1);
        }
        PUSHs(sv_2mortal(newSViv(multi ? 1 : 0)));
    }
    XSRETURN(4);

# ---------------------------------------------------------------------------
# BranchData  (extends BranchMap)
#
# Note: the abstract BranchMap base has no XS presence.  Its pure-Perl methods
# (lcovutil.pm) operate on the arrayref [DATA,FOUND,HIT] representation and are
# only inherited in LCOV_PURE_PERL mode.  Under XS, BranchData and MCDC_Data
# are backed by C++ objects (self = blessed scalar holding a C++ pointer) and
# override *every* base method, so no BranchMap XSUB is ever reachable -- the
# representations are incompatible.
# ---------------------------------------------------------------------------

MODULE = LcovUtil    PACKAGE = BranchData

SV*
new(klass)
    char* klass
  CODE:
    /* Scalar-ref wrapper around a single C++ BranchData (no AV, no
     * compatibility slots, no per-object empty hashes). */
    BranchData_wrapper* w = new BranchData_wrapper();
    SV* inner = newSViv((IV)(intptr_t)w);
    SV* rv    = newRV_noinc(inner);
    sv_bless(rv, gv_stashpv(klass, GV_ADD));
    RETVAL = rv;
  OUTPUT:
    RETVAL

void
DESTROY(self)
    SV* self
  CODE:
    if (SvROK(self) && SvIOK(SvRV(self))) {
        delete (BranchData_wrapper*)(intptr_t)SvIV(SvRV(self));   /* nullptr-safe */
        SvIV_set(SvRV(self), 0);
    }

IV
found(self)
    SV* self
  CODE:
    RETVAL = sv_to_branchdata(self)->data->found();
  OUTPUT:
    RETVAL

IV
hit(self)
    SV* self
  CODE:
    RETVAL = sv_to_branchdata(self)->data->hit();
  OUTPUT:
    RETVAL

void
get_found_and_hit(self)
    SV* self
  PPCODE:
    auto [f, h] = sv_to_branchdata(self)->data->get_found_and_hit();
    XPUSHs(sv_2mortal(newSViv(f)));
    XPUSHs(sv_2mortal(newSViv(h)));

void
adjust_counts(self, dFound, dHit)
    SV* self
    SV* dFound
    SV* dHit
  CODE:
    sv_to_branchdata(self)->data->adjust_counts((int64_t)SvIV(dFound),
                                                 (int64_t)SvIV(dHit));

SV*
value(self, lineNo)
    SV* self
    SV* lineNo
  CODE:
    BranchData_wrapper* w = sv_to_branchdata(self);
    int32_t line = (int32_t)SvIV(lineNo);
    BranchLocation* loc = w->data->value(line);
    if (loc) {
        RETVAL = branchdata_location_sv(w, line, loc);
    } else {
        RETVAL = SvREFCNT_inc(&PL_sv_undef);
    }
  OUTPUT:
    RETVAL

void
keylist(self)
    SV* self
  PPCODE:
    std::vector<int32_t> keys = sv_to_branchdata(self)->data->keylist();
    /* Context-aware, exactly like the pure-Perl 'return keys(%h)' body this
     * mirrors:  in scalar context yield the key COUNT, not the last key.
     * lcovutil.pm asks 'scalar($map->keylist())' at four sites to test a map
     * for emptiness; a list-only XSUB there returns whichever key happened to
     * come last (and undef for an empty map), so the emptiness test silently
     * read the wrong thing under XS. */
    if (GIMME_V == G_SCALAR) {
        XPUSHs(sv_2mortal(newSViv((IV)keys.size())));
        XSRETURN(1);
    }
    for (int32_t k : keys) {
        XPUSHs(sv_2mortal(newSViv(k)));
    }

int
remove(self, line, ...)
    SV* self
    SV* line
  CODE:
    BranchData_wrapper* w = sv_to_branchdata(self);
    int32_t lineNo = (int32_t)SvIV(line);
    w->uncache(lineNo);   /* drop any borrowed location wrapper for this line */
    bool check = (items >= 3) && SvOK(ST(2)) && SvTRUE(ST(2));
    /* An absent line without 'check' is a caller error that pure Perl dies on;
     * propagate it as a croak.  Swallowing the exception and returning 0
     * instead would report a removal that never happened. */
    try {
        RETVAL = w->data->remove(lineNo, check) ? 1 : 0;
    } catch (const std::exception& e) {
        croak("%s", e.what());
    }
  OUTPUT:
    RETVAL

SV*
findOrCreate(self, line)
    SV* self
    SV* line
  CODE:
    BranchData_wrapper* w = sv_to_branchdata(self);
    int32_t lineNo = (int32_t)SvIV(line);
    BranchLocation& loc = w->data->findOrCreate(lineNo);
    RETVAL = branchdata_location_sv(w, lineNo, &loc);
  OUTPUT:
    RETVAL

void
insertBlock(self, branchBlock, line)
    SV* self
    SV* branchBlock
    SV* line
  CODE:
    /* Route through findOrCreate + BranchLocation::insertBlock so the block's
     * auto-assigned idx is synced back to the passed Perl object (that logic
     * lives in the XS BranchLocation::insertBlock).  Mirrors the pure-Perl
     * BranchData::insertBlock, but without a Perl-level method dispatch. */
    BranchData_wrapper* w = sv_to_branchdata(self);
    int32_t lineNo = (int32_t)SvIV(line);
    SV* loc_sv = branchdata_location_sv(w, lineNo, &w->data->findOrCreate(lineNo));
    dSP;
    ENTER; SAVETMPS; PUSHMARK(SP);
    XPUSHs(sv_2mortal(loc_sv));
    XPUSHs(branchBlock);
    PUTBACK;
    call_method("insertBlock", G_DISCARD);
    FREETMPS; LEAVE;

void
removeBranches(self, block)
    SV* self
    SV* block
  CODE:
    /* Mirrors pure-Perl BranchData::removeBranches: subtract this block's
     * elements from the running found/hit totals (hit only for taken ones). */
    BranchData_wrapper* w = sv_to_branchdata(self);
    BranchBlock* blk = sv_to_branchblock(block);
    w->data->removeBranches(*blk);

void
updateCounts(self)
    SV* self
  CODE:
    sv_to_branchdata(self)->data->updateCounts();

void
_checkCounts(self)
    SV* self
  CODE:
    /* Mirrors pure-Perl BranchData::_checkCounts: assert the cached found/hit
     * still equal what a full walk of the data says they should be.  The
     * cached values are maintained incrementally (adjust_counts, remove, and
     * the incremental arms of the set operations), so any path which mutates
     * the same map twice drives them away from the truth silently.
     * TraceInfo::check_data runs this unconditionally on every '.info' read,
     * so it is a live oracle for the incremental bookkeeping -- not a debug
     * aid.  It must therefore do real work under XS too; a no-op here would
     * leave the XS backend with no equivalent check at all. */
    BranchData* bd = sv_to_branchdata(self)->data;
    int64_t found = 0, hit = 0;
    for (const auto& entry : bd->data()) {
        if (entry.second.line() != entry.first)
            croak("lost track of line");   /* LCOV_UNREACHABLE_LINE */
        std::pair<int64_t, int64_t> t = entry.second.totals();
        found += t.first;
        hit   += t.second;
    }
    if (bd->found() != found || bd->hit() != hit)
        croak("invalid counts: found:%" IVdf "->%" IVdf ", hit:%" IVdf "->%" IVdf,
              (IV)bd->found(), (IV)found, (IV)bd->hit(), (IV)hit);

int
union(self, other, ...)
    SV* self
    SV* other
  CODE:
    BranchData_wrapper* sw = sv_to_branchdata(self);
    BranchData_wrapper* ow = sv_to_branchdata(other);
    /* union($self, $info, $filename) -- the filename only labels mismatch
     * diagnostics, but it has to be threaded through:  under 'lcov -a' the file
     * and line are the only clue which input disagreed.  Pure-Perl
     * BranchData::union passes $filename down to BranchElement::merge; do the
     * same. */
    std::string filename;
    if (items >= 3 && SvOK(ST(2))) {
        STRLEN len;
        const char* s = SvPV(ST(2), len);
        filename = std::string(s, len);
    }
    RETVAL = sw->data->union_with(*ow->data, filename);
    if (RETVAL)   /* structural change -- invalidate borrows */
        sw->clear_cache();
  OUTPUT:
    RETVAL

int
intersect(self, other, ...)
    SV* self
    SV* other
  CODE:
    BranchData_wrapper* sw = sv_to_branchdata(self);
    BranchData_wrapper* ow = sv_to_branchdata(other);
    /* see the note on union() above */
    std::string filename;
    if (items >= 3 && SvOK(ST(2))) {
        STRLEN len;
        const char* s = SvPV(ST(2), len);
        filename = std::string(s, len);
    }
    RETVAL = sw->data->intersect_with(*ow->data, filename);
    if (RETVAL)
        sw->clear_cache();
  OUTPUT:
    RETVAL

int
difference(self, other, ...)
    SV* self
    SV* other
  CODE:
    BranchData_wrapper* sw = sv_to_branchdata(self);
    BranchData_wrapper* ow = sv_to_branchdata(other);
    /* difference never merges elements, so it raises no mismatch diagnostic and
     * has no use for a filename;  accept and ignore one for call compatibility
     * with union()/intersect() and with pure-Perl BranchData::difference. */
    RETVAL = sw->data->difference_with(*ow->data);
    if (RETVAL)
        sw->clear_cache();
  OUTPUT:
    RETVAL

# Binary serialization: flat little-endian buffer instead of a nested Perl
# AV/HV tree.  This is the payload used by the parallel-merge IPC hand-off, so
# avoiding the generic-Storable object walk is a direct speedup on large DBs.
SV*
serialize_binary(self)
    SV* self
  CODE:
    RETVAL = branchdata_serialize_binary(sv_to_branchdata(self)->data);
  OUTPUT:
    RETVAL

SV*
deserialize_binary(klass, data_sv)
    char* klass
    SV* data_sv
  CODE:
    STRLEN len;
    const uint8_t* data = (const uint8_t*)SvPVbyte(data_sv, len);
    BranchData* bd = branchdata_deserialize_binary(data, len);
    BranchData_wrapper* w = new BranchData_wrapper(bd);
    SV* inner = newSViv((IV)(intptr_t)w);
    SV* self  = newRV_noinc(inner);
    sv_bless(self, gv_stashpv(klass, GV_ADD));
    RETVAL = self;
  OUTPUT:
    RETVAL

SV*
STORABLE_freeze(self, cloning)
    SV* self
    SV* cloning
  PPCODE:
    /* Emit the binary buffer as the single serialized scalar; no data refs. */
    BranchData_wrapper* w = sv_to_branchdata(self);
    XPUSHs(sv_2mortal(branchdata_serialize_binary(w->data)));

void
STORABLE_thaw(self, cloning, serialized, ...)
    SV* self
    SV* cloning
    SV* serialized
  CODE:
    STRLEN len;
    const uint8_t* data = (const uint8_t*)SvPVbyte(serialized, len);

    /* Deserialize BEFORE releasing the old wrapper: a malformed payload makes
     * branchdata_deserialize_binary() croak, and croak() longjmps out of this
     * XSUB -- so deleting first would leave a dangling pointer in 'inner' with
     * SvIOK still set, which DESTROY would then free a second time. */
    BranchData* bd = branchdata_deserialize_binary(data, len);
    BranchData_wrapper* w = new BranchData_wrapper(bd);

    /* Delete old wrapper if present ('delete' is nullptr-safe) */
    SV* inner = SvRV(self);
    if (SvIOK(inner))
        delete (BranchData_wrapper*)(intptr_t)SvIV(inner);

    sv_setiv(inner, (IV)(intptr_t)w);
    SvIOK_on(inner);

# ---------------------------------------------------------------------------
# MCDC_Data  -- MCDC_Data_wrapper (scalar ref) around a single C++ MCDC_Data
# ---------------------------------------------------------------------------

MODULE = LcovUtil    PACKAGE = MCDC_Data

SV*
new(klass)
    char* klass
  CODE:
    MCDC_Data_wrapper* w = new MCDC_Data_wrapper();
    SV* inner = newSViv((IV)(intptr_t)w);
    SV* rv    = newRV_noinc(inner);
    sv_bless(rv, gv_stashpv(klass, GV_ADD));
    RETVAL = rv;
  OUTPUT:
    RETVAL

void
DESTROY(self)
    SV* self
  CODE:
    if (SvROK(self) && SvIOK(SvRV(self))) {
        delete (MCDC_Data_wrapper*)(intptr_t)SvIV(SvRV(self));   /* nullptr-safe */
        SvIV_set(SvRV(self), 0);
    }

IV
found(self)
    SV* self
  CODE:
    RETVAL = sv_to_mcdcdata(self)->data->found();
  OUTPUT:
    RETVAL

IV
hit(self)
    SV* self
  CODE:
    RETVAL = sv_to_mcdcdata(self)->data->hit();
  OUTPUT:
    RETVAL

void
get_found_and_hit(self)
    SV* self
  PPCODE:
    auto [f, h] = sv_to_mcdcdata(self)->data->get_found_and_hit();
    XPUSHs(sv_2mortal(newSViv(f)));
    XPUSHs(sv_2mortal(newSViv(h)));

void
adjust_counts(self, dFound, dHit)
    SV* self
    SV* dFound
    SV* dHit
  CODE:
    sv_to_mcdcdata(self)->data->adjust_counts((int64_t)SvIV(dFound),
                                               (int64_t)SvIV(dHit));

SV*
value(self, lineNo)
    SV* self
    SV* lineNo
  CODE:
    MCDC_Data_wrapper* w = sv_to_mcdcdata(self);
    int32_t line = (int32_t)SvIV(lineNo);
    MCDC_Block* blk = w->data->value(line);
    if (blk) {
        /* Borrow a wrapper into the stored block (cached for object identity)
         * so mutations through it -- e.g. set_excluded from the unreach
         * callback -- persist in storage, matching pure Perl. */
        RETVAL = mcdcdata_block_sv(w, line, blk);
    } else {
        RETVAL = SvREFCNT_inc(&PL_sv_undef);
    }
  OUTPUT:
    RETVAL

void
keylist(self)
    SV* self
  PPCODE:
    std::vector<int32_t> keys = sv_to_mcdcdata(self)->data->keylist();
    /* Context-aware, exactly like the pure-Perl 'return keys(%h)' body this
     * mirrors:  in scalar context yield the key COUNT, not the last key.
     * lcovutil.pm asks 'scalar($map->keylist())' at four sites to test a map
     * for emptiness; a list-only XSUB there returns whichever key happened to
     * come last (and undef for an empty map), so the emptiness test silently
     * read the wrong thing under XS. */
    if (GIMME_V == G_SCALAR) {
        XPUSHs(sv_2mortal(newSViv((IV)keys.size())));
        XSRETURN(1);
    }
    for (int32_t k : keys) {
        XPUSHs(sv_2mortal(newSViv(k)));
    }

int
remove(self, line, ...)
    SV* self
    SV* line
  CODE:
    MCDC_Data_wrapper* w = sv_to_mcdcdata(self);
    int32_t lineNo = (int32_t)SvIV(line);
    bool check = (items >= 3) && SvOK(ST(2)) && SvTRUE(ST(2));
    w->uncache(lineNo);   /* drop any borrowed block wrapper for this line */
    /* An absent line without 'check' is a caller error that pure Perl dies on;
     * turn the C++ exception into the same die rather than reporting a removal
     * that never happened. */
    try {
        RETVAL = w->data->remove(lineNo, check);
    } catch (const std::exception& e) {
        croak("%s", e.what());
    }
  OUTPUT:
    RETVAL

SV*
new_mcdc(self, fileData, line)
    SV* self
    SV* fileData
    IV  line
  CODE:
    /* Return the block stored for 'line', creating an empty one if absent
     * (matching pure-Perl MCDC_Data::new_mcdc).  The returned wrapper borrows
     * a pointer into the data_ map and is cached so repeat calls for the same
     * line return the SAME Perl object. */
    MCDC_Data_wrapper* w = sv_to_mcdcdata(self);
    MCDC_Block* blk = w->data->new_mcdc((int32_t)line);
    RETVAL = mcdcdata_block_sv(w, (int32_t)line, blk);
  OUTPUT:
    RETVAL

void
append_mcdc(self, mcdc, ...)
    SV* self
    SV* mcdc
  CODE:
    /* Mirrors pure-Perl MCDC_Data::append_mcdc: merge into the existing block
     * for this line, or store a copy of the given block.  The passed wrapper
     * owns its own C++ block, so we copy it into our map. */
    MCDC_Data_wrapper* w = sv_to_mcdcdata(self);
    MCDC_Block_wrapper* bw = sv_to_mcdcblock(mcdc);
    std::string filename;
    if (items >= 3 && SvOK(ST(2))) {
        STRLEN len; const char* s = SvPV(ST(2), len);
        filename = std::string(s, len);
    }
    int32_t line = (int32_t)bw->line();
    w->uncache(line);
    w->data->append_mcdc(*bw->block, filename);

void
close_mcdcBlock(self, mcdc)
    SV* self
    SV* mcdc
  CODE:
    /* Mirrors pure-Perl MCDC_Data::close_mcdcBlock: the block is already stored
     * (it was handed out by new_mcdc and populated in place); just fold its
     * raw per-sense totals into the cached found/hit counts. */
    MCDC_Data_wrapper* w = sv_to_mcdcdata(self);
    MCDC_Block_wrapper* bw = sv_to_mcdcblock(mcdc);
    int64_t found = 0, hit = 0;
    bw->block->for_each_group([&](int32_t gs,
                                  const std::vector<MCDC_Expression>& exprs) {
        (void)gs;
        for (const auto& e : exprs) {
            found += 2;
            if (e.count(0) != 0)
                ++hit;
            if (e.count(1) != 0)
                ++hit;
        }
    });
    w->data->adjust_counts(found, hit);

void
_calculate_counts(self)
    SV* self
  CODE:
    /* Recompute cached totals from the stored blocks (matches pure Perl). */
    sv_to_mcdcdata(self)->data->recalculate_counts();

void
_checkCounts(self)
    SV* self
  CODE:
    /* Mirrors pure-Perl MCDC_Data::_checkCounts -- see the BranchData XSUB of
     * the same name for why this has to do real work rather than be a no-op. */
    MCDC_Data* md = sv_to_mcdcdata(self)->data;
    int64_t found = 0, hit = 0;
    for (const auto& entry : md->data()) {
        if (entry.second.line() != entry.first)
            croak("lost track of line");   /* LCOV_UNREACHABLE_LINE */
        std::pair<int64_t, int64_t> t = entry.second.totals();
        found += t.first;
        hit   += t.second;
    }
    if (md->found() != found || md->hit() != hit)
        croak("invalid MC/DC counts: found:%" IVdf "->%" IVdf
              ", hit:%" IVdf "->%" IVdf,
              (IV)md->found(), (IV)found, (IV)md->hit(), (IV)hit);

int
union(self, info, ...)
    SV* self
    SV* info
  CODE:
    MCDC_Data_wrapper* mw = sv_to_mcdcdata(self);
    MCDC_Data_wrapper* ow = sv_to_mcdcdata(info);
    mw->clear_cache();   /* structural change -- invalidate borrowed wrappers */
    std::string filename;
    if (items >= 3 && SvOK(ST(2))) {
        STRLEN len;
        const char* s = SvPV(ST(2), len);
        filename = std::string(s, len);
    }
    RETVAL = mw->data->union_with(*ow->data, filename);
  OUTPUT:
    RETVAL

int
intersect(self, info, ...)
    SV* self
    SV* info
  CODE:
    MCDC_Data_wrapper* mw = sv_to_mcdcdata(self);
    MCDC_Data_wrapper* ow = sv_to_mcdcdata(info);
    mw->clear_cache();
    std::string filename;
    if (items >= 3 && SvOK(ST(2))) {
        STRLEN len;
        const char* s = SvPV(ST(2), len);
        filename = std::string(s, len);
    }
    RETVAL = mw->data->intersect_with(*ow->data, filename);
  OUTPUT:
    RETVAL

int
difference(self, info, ...)
    SV* self
    SV* info
  CODE:
    MCDC_Data_wrapper* mw = sv_to_mcdcdata(self);
    MCDC_Data_wrapper* ow = sv_to_mcdcdata(info);
    mw->clear_cache();
    /* difference never merges blocks, so it raises no mismatch diagnostic and
     * has no use for a filename;  accept and ignore one for call compatibility
     * with union()/intersect() and with pure-Perl MCDC_Data::difference. */
    RETVAL = mw->data->difference_with(*ow->data);
  OUTPUT:
    RETVAL

# Binary serialization: see the BranchData equivalents above.  Used by the
# parallel-merge IPC hand-off to skip the generic-Storable object walk.
SV*
serialize_binary(self)
    SV* self
  CODE:
    RETVAL = mcdcdata_serialize_binary(sv_to_mcdcdata(self)->data);
  OUTPUT:
    RETVAL

SV*
deserialize_binary(klass, data_sv)
    char* klass
    SV* data_sv
  CODE:
    STRLEN len;
    const uint8_t* data = (const uint8_t*)SvPVbyte(data_sv, len);
    MCDC_Data* md = mcdcdata_deserialize_binary(data, len);
    MCDC_Data_wrapper* w = new MCDC_Data_wrapper(md);
    SV* inner = newSViv((IV)(intptr_t)w);
    SV* self  = newRV_noinc(inner);
    sv_bless(self, gv_stashpv(klass, GV_ADD));
    RETVAL = self;
  OUTPUT:
    RETVAL

SV*
STORABLE_freeze(self, cloning)
    SV* self
    SV* cloning
  PPCODE:
    MCDC_Data_wrapper* w = sv_to_mcdcdata(self);
    XPUSHs(sv_2mortal(mcdcdata_serialize_binary(w->data)));

void
STORABLE_thaw(self, cloning, serialized, ...)
    SV* self
    SV* cloning
    SV* serialized
  CODE:
    STRLEN len;
    const uint8_t* data = (const uint8_t*)SvPVbyte(serialized, len);

    /* Deserialize BEFORE releasing the old wrapper: a malformed payload makes
     * mcdcdata_deserialize_binary() croak, and croak() longjmps out of this
     * XSUB -- so deleting first would leave a dangling pointer in 'inner' with
     * SvIOK still set, which DESTROY would then free a second time. */
    MCDC_Data* md = mcdcdata_deserialize_binary(data, len);
    MCDC_Data_wrapper* w = new MCDC_Data_wrapper(md);

    /* Delete old wrapper if present ('delete' is nullptr-safe) */
    SV* inner = SvRV(self);
    if (SvIOK(inner))
        delete (MCDC_Data_wrapper*)(intptr_t)SvIV(inner);

    sv_setiv(inner, (IV)(intptr_t)w);
    SvIOK_on(inner);
