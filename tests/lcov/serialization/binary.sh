#!/usr/bin/env bash
set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

# Test binary serialization for CountData
echo "Testing CountData binary serialization..."

# Check if XS is loaded
perl -I$LCOV_HOME/lib/LcovUtil/blib/lib -I$LCOV_HOME/lib/LcovUtil/blib/arch -e '
use LcovUtil;
unless ($LcovUtil::XS_LOADED) {
    print "SKIP: XS not loaded\n";
    exit 77;  # Skip test
}
'
RES=$?
if [ $RES == 77 ] ; then
    echo "Skipping test - XS not available"
    exit 0
fi

# The serializer's integer encoding must not depend on <endian.h>:  that header
# is glibc's, and this library is expected to build on macOS, on the BSDs and
# under MSVC as well.  The byte order on the wire is asserted below; this is
# the source-level half of the same requirement, and it is checked here because
# the compile itself cannot be: libstdc++'s own headers include <endian.h>
# transitively, so poisoning the name proves nothing.
SERIALIZER=${LCOV_HOME}/lib/LcovUtil/BinarySerializer.hpp
if [ ! -f "$SERIALIZER" ] ; then
    echo "cannot find $SERIALIZER"
    exit 1
fi
# the comments in that file name the macros in order to say not to use them,
# so look at the code with the comments taken out
if perl -0777 -pe 's{/\*.*?\*/}{}gs ; s{//[^\n]*}{}g' "$SERIALIZER" |
    grep -n -E 'endian\.h|htole(16|32|64)|le(16|32|64)toh|htobe(16|32|64)|be(16|32|64)toh' ; then
    echo "BinarySerializer.hpp must not use glibc's byte-order macros"
    exit 1
fi
echo "PASS: serializer does not depend on <endian.h>"

# Run serialization tests
perl $PERL_COVER_ARGS -I$LCOV_HOME/lib/LcovUtil/blib/lib -I$LCOV_HOME/lib/LcovUtil/blib/arch - <<'EOF'
use strict;
use warnings;
use LcovUtil;
use Storable;
use Scalar::Util;

unless ($LcovUtil::XS_LOADED) {
    print "XS not loaded - skipping test\n";
    exit 0;
}

# Test 1: Direct binary serialization
my $data = CountData->new("test.c", 1);
$data->append(10, 5);
$data->append(20, 10);
$data->append(30, 0);
$data->append(100, 999);

my ($f, $h) = $data->get_found_and_hit();
die "Test setup failed: wrong found/hit\n" unless $f == 4 && $h == 3;

if ($data->can('serialize_binary')) {
    my $binary = $data->serialize_binary();
    my $restored = CountData->deserialize_binary($binary);

    my ($f2, $h2) = $restored->get_found_and_hit();
    die "Direct serialization failed: found/hit mismatch\n" unless $f2 == 4 && $h2 == 3;
    die "Direct serialization failed: line 10\n" unless $restored->value(10) == 5;
    die "Direct serialization failed: line 20\n" unless $restored->value(20) == 10;
    die "Direct serialization failed: line 30\n" unless $restored->value(30) == 0;
    die "Direct serialization failed: line 100\n" unless $restored->value(100) == 999;

    print "PASS: Direct binary serialization\n";
} else {
    die "serialize_binary method not available\n";
}

# Test 2: Storable freeze/thaw
my $frozen = Storable::freeze($data);
my $thawed = Storable::thaw($frozen);

my ($f3, $h3) = $thawed->get_found_and_hit();
die "Storable failed: found/hit mismatch\n" unless $f3 == 4 && $h3 == 3;
die "Storable failed: line 10\n" unless $thawed->value(10) == 5;
die "Storable failed: line 20\n" unless $thawed->value(20) == 10;
die "Storable failed: line 30\n" unless $thawed->value(30) == 0;
die "Storable failed: line 100\n" unless $thawed->value(100) == 999;

print "PASS: Storable serialization\n";

# Test 3: Binary format is smaller
my $binary_size = length($data->serialize_binary());
print "Binary size: $binary_size bytes\n";
print "Storable size: ", length($frozen), " bytes\n";

die "Binary serialization not smaller than Storable\n" unless $binary_size <= length($frozen);

# Test 4: Empty CountData round-trips (num_entries == 0 path)
{
    my $empty = CountData->new("empty.c", 0);
    my $restored = CountData->deserialize_binary($empty->serialize_binary());
    my ($f, $h) = $restored->get_found_and_hit();
    die "Empty round-trip failed: found/hit\n" unless $f == 0 && $h == 0;
    print "PASS: Empty CountData round-trip\n";
}

# Test 4b: the integers on the wire are little-endian, whatever the host is.
# The encoding is written out a byte at a time rather than through <endian.h>,
# so this is what pins the format down:  every multi-byte field is least
# significant byte first, and the values come back unchanged.
{
    my $LINE = 0x01020304;
    # a 5-byte count, built by hand rather than written as a literal: a hex
    #   constant wider than 32 bits warns, and one wider than 53 bits would
    #   not survive Perl's numeric conversion exactly
    my $COUNT = 0x04050607 * 256 + 0x08;    # 0x04_05_06_07_08
    my $endian = CountData->new("endian.c", 0);
    $endian->append($LINE, $COUNT);
    my $bin = $endian->serialize_binary();

    die "version field is not little-endian: " .
        unpack("H*", substr($bin, 4, 4)) . "\n"
        unless substr($bin, 4, 4) eq "\x01\x00\x00\x00";

    # [MAGIC:4][VERSION:4][FNLEN:4][FILENAME:N][SORTABLE:4][FOUND:8][HIT:8]
    #   [NUM_ENTRIES:4] then NUM_ENTRIES * [LINE:4][COUNT:8]
    my $ent_off = 4 + 4 + 4 + length("endian.c") + 4 + 8 + 8 + 4;
    die "line field is not little-endian: " .
        unpack("H*", substr($bin, $ent_off, 4)) . "\n"
        unless substr($bin, $ent_off, 4) eq "\x04\x03\x02\x01";
    die "count field is not little-endian: " .
        unpack("H*", substr($bin, $ent_off + 4, 8)) . "\n"
        unless substr($bin, $ent_off + 4, 8) eq
        "\x08\x07\x06\x05\x04\x00\x00\x00";

    my $rt = CountData->deserialize_binary($bin);
    my $v = $rt->value($LINE);
    die "little-endian round-trip lost the value\n" unless defined($v);
    die "little-endian round-trip: $v != $COUNT\n" unless $v == $COUNT;
    print "PASS: wire format is little-endian and round-trips\n";
}

# Test 5: Malformed input is rejected (exercises BinaryReader error paths).
# Each case must die/croak rather than silently succeed.  These drive the
# "Buffer underrun" / "Invalid magic" / bad-version paths in the C++ reader
# and the exception-to-croak wrapper in countdata_deserialize_binary.
my $good = $data->serialize_binary();

sub expect_die {
    my ($label, $bytes) = @_;
    my $ok = eval { CountData->deserialize_binary($bytes); 1 };
    if ($ok) {
        die "Malformed input NOT rejected: $label\n";
    }
    print "PASS: rejected malformed input ($label)\n";
}

# a) Empty string -> underrun while reading the 4-byte magic (read_bytes).
expect_die("empty buffer", "");

# b) Wrong magic number -> verify_magic mismatch throw.
my $bad_magic = $good;
substr($bad_magic, 0, 4) = "XXXX";
expect_die("bad magic", $bad_magic);

# c) Correct magic but unsupported version (version field = 2) -> version croak.
#    Header layout: [MAGIC:4]["CDAT"][VERSION:4 LE uint32].
my $bad_ver = "CDAT" . pack("V", 2) . substr($good, 8);
expect_die("unsupported version", $bad_ver);

# d) Valid header but truncated mid-record -> underrun in read_string/read_i*.
#    Keep only magic+version+2 bytes so the filename length read underruns.
expect_die("truncated header", substr($good, 0, 10));

# e) Declared filename length larger than remaining bytes -> read_string underrun.
#    magic + version + huge length, then nothing.
my $huge_len = "CDAT" . pack("V", 1) . pack("V", 0xFFFFFFF);
expect_die("oversized string length", $huge_len);

# e2) The largest length the field can hold.  The reader compares the length
#     against the space that is left rather than adding it to the read pointer:
#     the sum is undefined behaviour past the end of the buffer, and wraps
#     outright where a pointer is no wider than the length (a 32-bit build),
#     which would let this through instead of rejecting it.
expect_die("maximal string length",
           "CDAT" . pack("V", 1) . pack("V", 0xFFFFFFFF) . "abcd");

# f) Complete header through the filename, but truncated before the 4-byte
#    "sortable" field -> underrun in read_i32.
#    Layout so far: [MAGIC:4][VERSION:4][FNLEN:4][FILENAME:N] then read_i32.
#    $data was built with filename "test.c" (6 bytes), so 4+4+4+6 = 18 bytes.
my $fname_len = length("test.c");
my $through_fname = 4 + 4 + 4 + $fname_len;
expect_die("truncated before sortable (read_i32)", substr($good, 0, $through_fname));

# g) Header + sortable present, but truncated before the 8-byte "found"
#    field -> underrun in read_i64.
expect_die("truncated before found (read_i64)", substr($good, 0, $through_fname + 4));

# Test 6: out-of-order entries in the stream are re-sorted on read.
# The XS CountData keeps line->count in a vector sorted by line, and its
# find() binary-searches, so the sort order is a load-bearing invariant.
# serialize_binary() walks that sorted vector, so a stream this build produced
# is always already in order and the reader takes its append fast path -- the
# re-sort fallback is only reachable by handing deserialize_binary() a stream
# whose entry records are permuted, which is what this does.  Without the
# fallback, value() would miss keys that binary search cannot reach.
#
# Entry-array layout, after [MAGIC:4][VERSION:4][FNLEN:4][FILENAME:N]:
#   [SORTABLE:4][FOUND:8][HIT:8][NUM_ENTRIES:4] then NUM_ENTRIES * 12 bytes
#   of [LINE:4 LE i32][COUNT:8 LE i64].
{
    my $src = CountData->new("resort.c", 0);
    $src->append($_, $_) for (1, 5, 9, 12, 20);    # ascending: stored in order
    my $bin = $src->serialize_binary();

    my $hdr_len  = 4 + 4 + 4 + length("resort.c") + 4 + 8 + 8;
    my $n        = unpack("V", substr($bin, $hdr_len, 4));
    die "unexpected entry count $n\n" unless $n == 5;
    my $ent_off  = $hdr_len + 4;

    my @records = map { substr($bin, $ent_off + $_ * 12, 12) } 0 .. $n - 1;
    # reverse the entry records -> strictly descending line order on the wire
    my $permuted = substr($bin, 0, $ent_off) . join("", reverse @records);
    die "permutation changed the length\n" unless length($permuted) == length($bin);
    die "permutation was a no-op\n" if $permuted eq $bin;

    my $rt = CountData->deserialize_binary($permuted);
    die "resort: entries " . $rt->entries() . "\n" unless $rt->entries() == 5;
    for my $line (1, 5, 9, 12, 20) {
        my $v = $rt->value($line);
        die "resort: line $line unreachable after permuted read\n"
            unless defined($v);
        die "resort: line $line value $v != $line\n" unless $v == $line;
    }
    # iteration must come back sorted, which is what callers rely on
    my $keys = join(",", $rt->keylist());
    die "resort: keylist not sorted: $keys\n" unless $keys eq "1,5,9,12,20";
    my ($rf, $rh) = $rt->get_found_and_hit();
    die "resort: found/hit $rf/$rh\n" unless $rf == 5 && $rh == 5;
    print "PASS: out-of-order binary entries are re-sorted on read\n";
}

# ---------------------------------------------------------------------------
# MapData STORABLE_freeze/thaw.
#
# MapData is the one class whose freeze does NOT emit the compact binary format:
# its values are arbitrary Perl SVs, so it pushes an empty tag plus a plain
# hashref (hence its thaw reads the data at ST(3) rather than ST(2)).  The thaw
# therefore validates the shape of what it is handed, and -- as with the binary
# classes -- must not release the object it is thawing into until the
# replacement exists, because those validation croaks longjmp out of the XSUB.
# ---------------------------------------------------------------------------
{
    my $target = MapData->new();
    $target->append_if_unset('keep', 'original');

    for my $case ( [ "not a reference", 'notaref' ],
                   [ "not a hashref",   [ 1, 2 ] ] ) {
        my ($label, $payload) = @$case;
        die "MapData STORABLE_thaw accepted $label\n"
            if eval { $target->STORABLE_thaw(0, '', $payload); 1 };
        # The croak must have left the original contents untouched, and the
        # object must still be safe to use and to destroy.
        my @keys = $target->keylist();
        die "MapData STORABLE_thaw ($label) clobbered the target (@keys)\n"
            unless scalar(@keys) == 1 && $keys[0] eq 'keep';
        die "MapData STORABLE_thaw ($label) lost the value\n"
            unless $target->value('keep') eq 'original';
        print "PASS: MapData STORABLE_thaw rejected $label\n";
    }

    # Success path onto an already-initialized object: the old contents are
    # released and replaced, not merged.
    my $source = MapData->new();
    $source->append_if_unset('fresh', 'value');
    $target->STORABLE_thaw(0, $source->STORABLE_freeze(0));
    my @keys = $target->keylist();
    die "MapData STORABLE_thaw reuse: keys (@keys)\n"
        unless scalar(@keys) == 1 && $keys[0] eq 'fresh';
    die "MapData STORABLE_thaw reuse: value\n"
        unless $target->value('fresh') eq 'value';
    print "PASS: MapData STORABLE_thaw onto an initialized object\n";

    # And the ordinary Storable round-trip still works.
    my $rt = Storable::thaw(Storable::freeze($source));
    die "MapData Storable round-trip\n" unless $rt->value('fresh') eq 'value';
    print "PASS: MapData Storable round-trip\n";
}

# ---------------------------------------------------------------------------
# BranchData binary serialization (flat buffer replaces the nested AV/HV tree)
# ---------------------------------------------------------------------------
if (BranchData->can('serialize_binary')) {
    my $bd  = BranchData->new();
    my $loc = $bd->findOrCreate(10);
    my $blk = BranchBlock->new();
    $blk->appendElement(BranchElement->new(0, 5, undef, 0, 0));
    $blk->appendElement(BranchElement->new(1, 0, undef, 0, 0));
    $loc->insertBlock($blk);
    $bd->updateCounts();
    my ($bf, $bh) = $bd->get_found_and_hit();
    die "BranchData setup: wrong found/hit ($bf/$bh)\n" unless $bf == 2 && $bh == 1;

    # Direct binary round-trip
    my $rt = BranchData->deserialize_binary($bd->serialize_binary());
    my ($rf, $rh) = $rt->get_found_and_hit();
    die "BranchData binary: found/hit mismatch ($rf/$rh)\n" unless $rf == 2 && $rh == 1;
    die "BranchData binary: lost location 10\n" unless defined $rt->value(10);
    print "PASS: BranchData direct binary\n";

    # Storable round-trip (drives the XS STORABLE_freeze/thaw hooks -- the
    # actual parallel-merge IPC path).
    my $bthaw = Storable::thaw(Storable::freeze($bd));
    my ($sf, $sh) = $bthaw->get_found_and_hit();
    die "BranchData Storable: found/hit mismatch ($sf/$sh)\n" unless $sf == 2 && $sh == 1;
    print "PASS: BranchData Storable\n";

    # Empty BranchData round-trips (num_locations == 0 path)
    my $empty = BranchData->new();
    my ($ef, $eh) = BranchData->deserialize_binary($empty->serialize_binary())
        ->get_found_and_hit();
    die "BranchData empty: found/hit ($ef/$eh)\n" unless $ef == 0 && $eh == 0;
    print "PASS: BranchData empty round-trip\n";

    # Multi-block location round-trip.  Reading a location pre-sizes its block
    # vector to the stored count before inserting, so the fill must not depend
    # on the reserve being exact and every block must land at its own dense
    # index (idx == position) with its signature registered.
    {
        my $mbd = BranchData->new();
        for my $i (0 .. 9) {
            my $bb = BranchBlock->new();
            # i+1 elements -> ten distinct signatures
            $bb->appendElement(BranchElement->new($_, 1, undef, 0, 0))
                for 0 .. $i;
            $mbd->insertBlock($bb, 7);
        }
        $mbd->updateCounts();
        my ($mf, $mh) = $mbd->get_found_and_hit();

        for my $how ('binary', 'Storable') {
            my $got = $how eq 'binary' ?
                BranchData->deserialize_binary($mbd->serialize_binary()) :
                Storable::thaw(Storable::freeze($mbd));
            my $mloc = $got->value(7);
            die "multi-block $how: lost location 7\n" unless defined $mloc;
            die "multi-block $how: numBlocks " . $mloc->numBlocks() . "\n"
                unless $mloc->numBlocks() == 10;
            my ($gf, $gh) = $got->get_found_and_hit();
            die "multi-block $how: found/hit $gf/$gh != $mf/$mh\n"
                unless $gf == $mf && $gh == $mh;
            for my $i (0 .. 9) {
                my $b = $mloc->getBlock($i);
                die "multi-block $how: block $i idx " . $b->idx() . "\n"
                    unless $b->idx() == $i;
                die "multi-block $how: block $i has " .
                    scalar(@{$b->elements()}) . " elements\n"
                    unless scalar(@{$b->elements()}) == $i + 1;
            }
            my @mcodes = $mloc->codes();
            die "multi-block $how: " . scalar(@mcodes) . " codes (@mcodes)\n"
                unless scalar(@mcodes) == 10;
            print "PASS: BranchData multi-block location round-trip ($how)\n";
        }
    }

    # Bad magic is rejected
    my $bgood = $bd->serialize_binary();
    my $bbad  = $bgood;
    substr($bbad, 0, 4) = "XXXX";
    die "BranchData bad magic NOT rejected\n"
        if eval { BranchData->deserialize_binary($bbad); 1 };
    print "PASS: BranchData rejected bad magic\n";

    # Correct magic but a version this build does not know.  Distinct from bad
    # magic: the reader gets far enough to read the version field, so this drives
    # the explicit version croak rather than verify_magic's throw.  The wire
    # format is deliberately not portable across builds, so rejecting an
    #  unknown version is the contract, not a nicety.
    #   Header layout: [MAGIC:4]["BDAT"][VERSION:4 LE uint32].
    my $bver = "BDAT" . pack("V", 2) . substr($bgood, 8);
    die "BranchData unsupported version NOT rejected\n"
        if eval { BranchData->deserialize_binary($bver); 1 };
    print "PASS: BranchData rejected unsupported version\n";

    # STORABLE_thaw must not free the object it is thawing INTO before the new
    # value exists.  A malformed payload makes the deserializer croak, and croak
    # longjmps out of the XSUB -- so a 'delete' placed ahead of the deserialize
    # would leave a dangling pointer in the object with its IV flag still set, and
    # the eventual DESTROY would free it a second time (SIGSEGV).  After the croak
    # the object must still hold its ORIGINAL contents and be safe to destroy.
    {
        my $victim = BranchData->new();
        $victim->findOrCreate(1234);
        my $bad = "XXXX" . substr($bgood, 4);
        die "BranchData STORABLE_thaw accepted bad magic\n"
            if eval { $victim->STORABLE_thaw(0, "tag", $bad); 1 };
        my @keys = $victim->keylist();
        die "BranchData STORABLE_thaw croak clobbered the target (@keys)\n"
            unless scalar(@keys) == 1 && $keys[0] == 1234;
        print "PASS: BranchData survives a croaking STORABLE_thaw\n";
    }

    # The success path of that same hook: thawing onto an ALREADY-initialized
    # object must release the old wrapper and adopt the new contents (this is
    # what Storable::thaw does to the fresh-but-constructed object it allocates).
    {
        my $target = BranchData->new();
        $target->findOrCreate(1);
        my $source = BranchData->new();
        $source->findOrCreate(4242);
        $target->STORABLE_thaw(0, $source->STORABLE_freeze(0));
        my @keys = $target->keylist();
        die "BranchData STORABLE_thaw reuse: keys (@keys)\n"
            unless scalar(@keys) == 1 && $keys[0] == 4242;
        print "PASS: BranchData STORABLE_thaw onto an initialized object\n";
    }

    # -----------------------------------------------------------------------
    # Differential BranchElement round-trip.
    #
    # In the normal pipeline this code path is never reached during
    # serialization: differential data (TLA + [base,curr]) is attached by
    # genhtml's report-categorization stage (set_differential in bin/genhtml),
    # which builds a throwaway BranchLocation graph that is consumed directly
    # to emit HTML and is never serialized.  Every object that DOES get
    # serialized -- the base/current BranchData feeding the parallel-merge IPC
    # and the Storable::dclone in genhtml's current_branch/baseline_branch --
    # is in its pre-differential form, so isDifferential() is false at every
    # freeze point.  The isDifferential() branch in branchelement_write /
    # branchelement_read is therefore effectively dead in production; these
    # assertions exist to exercise and prove the codec correct regardless.
    {
        my $dbd  = BranchData->new();
        my $dloc = $dbd->findOrCreate(20);
        my $dblk = BranchBlock->new();
        my $de   = BranchElement->new(0, 7, undef, 0, 0);
        # tla + [base,curr]: mark this element as differential coverage data
        $de->set_differential('GBC', 3, 7);
        $dblk->appendElement($de);
        $dloc->insertBlock($dblk);
        $dbd->updateCounts();

        die "differential setup: element not differential\n"
            unless $de->isDifferential();

        # Direct binary round-trip must preserve differential state, tla, and
        # the [base,curr] pair.
        my $drt  = BranchData->deserialize_binary($dbd->serialize_binary());
        my ($dblk2) = $drt->value(20)->blocks();
        my $de2     = $dblk2->getElement(0);
        die "differential binary: lost differential flag\n"
            unless $de2->isDifferential();
        die "differential binary: tla mismatch (" . $de2->tla() . ")\n"
            unless $de2->tla() eq 'GBC';
        my ($db, $dc) = $de2->diff_count();
        die "differential binary: diff_count mismatch ($db/$dc)\n"
            unless $db == 3 && $dc == 7;
        print "PASS: BranchData differential direct binary\n";

        # Storable round-trip (the XS STORABLE_freeze/thaw hooks) must agree.
        my $dstor = Storable::thaw(Storable::freeze($dbd));
        my ($sblk) = $dstor->value(20)->blocks();
        my $se     = $sblk->getElement(0);
        die "differential Storable: lost differential flag\n"
            unless $se->isDifferential();
        die "differential Storable: tla mismatch (" . $se->tla() . ")\n"
            unless $se->tla() eq 'GBC';
        my ($sb, $sc) = $se->diff_count();
        die "differential Storable: diff_count mismatch ($sb/$sc)\n"
            unless $sb == 3 && $sc == 7;
        print "PASS: BranchData differential Storable\n";
    }
} else {
    print "SKIP: BranchData->serialize_binary not available\n";
}

# ---------------------------------------------------------------------------
# MCDC_Data binary serialization
# ---------------------------------------------------------------------------
if (MCDC_Data->can('serialize_binary')) {
    my $md = MCDC_Data->new();
    my $mb = $md->new_mcdc(undef, 42);
    $mb->insertExpr("f.c", 2, 0, 3, 0, "a && b");
    $mb->insertExpr("f.c", 2, 1, 0, 0, "a && b");
    $mb->insertExpr("f.c", 2, 0, 1, 1, "c || d");
    $mb->insertExpr("f.c", 2, 1, 2, 1, "c || d");

    # Binary and Storable round-trips must agree with each other on totals and
    # on per-expression counts.
    my $bin  = MCDC_Data->deserialize_binary($md->serialize_binary());
    my $stor = Storable::thaw(Storable::freeze($md));
    my ($binf, $binh)   = $bin->get_found_and_hit();
    my ($storf, $storh) = $stor->get_found_and_hit();
    die "MCDC_Data binary vs Storable totals differ: bin=($binf/$binh) stor=($storf/$storh)\n"
        unless $binf == $storf && $binh == $storh;
    print "PASS: MCDC_Data binary/Storable totals agree ($binf/$binh)\n";

    my $be = $bin->value(42)->expr(2, 0);
    my $se = $stor->value(42)->expr(2, 0);
    die "MCDC_Data expr count(0) differ\n" unless $be->count(0) == $se->count(0);
    die "MCDC_Data expr count(1) differ\n" unless $be->count(1) == $se->count(1);
    print "PASS: MCDC_Data per-expression counts agree\n";

    # Empty MCDC_Data round-trips
    my $mempty = MCDC_Data->new();
    my ($mef, $meh) = MCDC_Data->deserialize_binary($mempty->serialize_binary())
        ->get_found_and_hit();
    die "MCDC_Data empty: found/hit ($mef/$meh)\n" unless $mef == 0 && $meh == 0;
    print "PASS: MCDC_Data empty round-trip\n";

    # Malformed input.  Same three cases as CountData above, on the MCDC reader:
    # bad magic and a truncated stream both surface as C++ exceptions the XSUB
    # converts to a croak, while a correct magic with an unknown version reaches
    # the explicit version croak.
    my $mgood = $md->serialize_binary();
    for my $case ( [ "bad magic",   "XXXX" . substr($mgood, 4) ],
                   [ "truncated",   substr($mgood, 0, 10) ],
                   [ "unsupported version",
                     "MDAT" . pack("V", 2) . substr($mgood, 8) ] ) {
        my ($label, $bytes) = @$case;
        die "MCDC_Data $label NOT rejected\n"
            if eval { MCDC_Data->deserialize_binary($bytes); 1 };
        print "PASS: MCDC_Data rejected $label\n";
    }

    # STORABLE_thaw must build the replacement before releasing what it is
    # thawing into -- see the BranchData note above.  Croak, then confirm the
    # target is intact and destroys cleanly.
    {
        my $victim = MCDC_Data->new();
        $victim->new_mcdc(undef, 1234);
        die "MCDC_Data STORABLE_thaw accepted bad magic\n"
            if eval { $victim->STORABLE_thaw(0, "tag", "XXXX" . substr($mgood, 4)); 1 };
        my @keys = $victim->keylist();
        die "MCDC_Data STORABLE_thaw croak clobbered the target (@keys)\n"
            unless scalar(@keys) == 1 && $keys[0] == 1234;
        print "PASS: MCDC_Data survives a croaking STORABLE_thaw\n";
    }

    # ...and the success path onto an already-initialized object.
    {
        my $target = MCDC_Data->new();
        $target->new_mcdc(undef, 1);
        my $source = MCDC_Data->new();
        $source->new_mcdc(undef, 4242);
        $target->STORABLE_thaw(0, $source->STORABLE_freeze(0));
        my @keys = $target->keylist();
        die "MCDC_Data STORABLE_thaw reuse: keys (@keys)\n"
            unless scalar(@keys) == 1 && $keys[0] == 4242;
        print "PASS: MCDC_Data STORABLE_thaw onto an initialized object\n";
    }

    # -----------------------------------------------------------------------
    # Differential MCDC_Expression round-trip.
    #
    # As with BranchData above, this path is effectively dead in production:
    # differential MC/DC data (a per-sense [tla, base, curr] triple) is only
    # produced by genhtml's report-categorization stage (via insertExpr with
    # an arrayref count), on a throwaway graph rendered straight to HTML and
    # never serialized.  Everything that IS serialized -- the base/current
    # MCDC_Data behind the parallel-merge IPC and genhtml's Storable::dclone --
    # is pre-differential, so isDifferential(sense) is false at every freeze
    # point and the isDifferential() branch in mcdcexpr_write / mcdcexpr_read
    # is never hit.  These assertions exercise and verify that branch anyway.
    #
    # Passing the count as [tla, base, curr] is exactly how bin/genhtml drives
    # insertExpr for differential data; it routes through mcdcexpr_set's
    # arrayref path, which calls set_differential_opt on the C++ expression.
    {
        my $dmd = MCDC_Data->new();
        my $dmb = $dmd->new_mcdc(undef, 99);
        # sense 0 and sense 1 both carry a differential [tla, base, curr] triple
        $dmb->insertExpr("f.c", 1, 0, ['GBC', 2, 5], 0, "a && b");
        $dmb->insertExpr("f.c", 1, 1, ['UNC', 0, 3], 0, "a && b");

        my $dbin  = MCDC_Data->deserialize_binary($dmd->serialize_binary());
        my $dstor = Storable::thaw(Storable::freeze($dmd));

        # Totals must agree between binary and Storable paths.
        my ($dbinf, $dbinh)   = $dbin->get_found_and_hit();
        my ($dstorf, $dstorh) = $dstor->get_found_and_hit();
        die "MCDC differential totals differ: bin=($dbinf/$dbinh) stor=($dstorf/$dstorh)\n"
            unless $dbinf == $dstorf && $dbinh == $dstorh;

        # Per-sense differential payload must survive the binary round-trip.
        # count($sense) returns [tla, base, curr] for differential expressions.
        my $dbe = $dbin->value(99)->expr(1, 0);
        my $c0  = $dbe->count(0);
        my $c1  = $dbe->count(1);
        die "MCDC differential binary: sense 0 not an arrayref\n"
            unless ref($c0) eq 'ARRAY';
        die "MCDC differential binary: sense 0 mismatch (@$c0)\n"
            unless $c0->[0] eq 'GBC' && $c0->[1] == 2 && $c0->[2] == 5;
        die "MCDC differential binary: sense 1 mismatch (@$c1)\n"
            unless $c1->[0] eq 'UNC' && $c1->[1] == 0 && $c1->[2] == 3;
        print "PASS: MCDC_Data differential direct binary\n";

        # And the Storable (XS STORABLE_freeze/thaw) path must match it.
        my $dse  = $dstor->value(99)->expr(1, 0);
        my $sc0  = $dse->count(0);
        my $sc1  = $dse->count(1);
        die "MCDC differential Storable: sense 0 mismatch (@$sc0)\n"
            unless ref($sc0) eq 'ARRAY' &&
                   $sc0->[0] eq 'GBC' && $sc0->[1] == 2 && $sc0->[2] == 5;
        die "MCDC differential Storable: sense 1 mismatch (@$sc1)\n"
            unless ref($sc1) eq 'ARRAY' &&
                   $sc1->[0] eq 'UNC' && $sc1->[1] == 0 && $sc1->[2] == 3;
        print "PASS: MCDC_Data differential Storable\n";
    }
} else {
    print "SKIP: MCDC_Data->serialize_binary not available\n";
}

# ---------------------------------------------------------------------------
# Per-object STORABLE hook regression (bare dclone).
#
# geninfo's read path does Storable::dclone() on a bare MCDC_Block (and the
# parallel-merge IPC likewise clones bare BranchElement/BranchBlock objects).
# dclone recurses directly into the PER-OBJECT STORABLE_freeze/thaw hooks --
# NOT the flattened top-level container hook that serialize_binary uses -- so
# these objects must round-trip on their own.  A freeze that pushes a single
# binary scalar lands it at ST(2), so a thaw that reads ST(3) instead would croak
# "missing frozen data".  This exercises that exact path.
if (MCDC_Block->can('new_mcdc') || BranchBlock->can('new')) {
    use Storable qw(dclone);

    # Bare BranchElement dclone
    my $be = BranchElement->new(0, 5, undef, 0, 0);
    my $bec = dclone($be);
    die "bare BranchElement dclone: count mismatch\n"
        unless $bec->count() == 5;
    print "PASS: bare BranchElement dclone\n";

    # Bare BranchBlock (with elements) dclone
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new(0, 3, undef, 0, 0));
    $bb->appendElement(BranchElement->new(1, 0, undef, 0, 0));
    my $bbc = dclone($bb);
    die "bare BranchBlock dclone: element count\n"
        unless $bbc->getElement(0)->count() == 3 &&
               $bbc->getElement(1)->count() == 0;
    print "PASS: bare BranchBlock dclone\n";

    # Bare MCDC_Block dclone -- this is the exact object geninfo clones per
    # coverpoint (lcovutil.pm testcase_mcdc()->append_mcdc(dclone(...))).
    my $md = MCDC_Data->new();
    my $mb = $md->new_mcdc(undef, 7);
    $mb->insertExpr("f.c", 2, 0, 3, 0, "a && b");
    $mb->insertExpr("f.c", 2, 1, 0, 0, "a && b");
    my $mbc = dclone($mb);
    die "bare MCDC_Block dclone: line mismatch\n"
        unless $mbc->line() == 7;
    my $ec = $mbc->expr(2, 0);
    die "bare MCDC_Block dclone: lost expression\n" unless defined $ec;
    print "PASS: bare MCDC_Block dclone\n";
}

print "All tests PASSED\n";
exit 0;
EOF

if [[ $? != 0 && $KEEP_GOING != 1 ]] ; then
    echo "Binary serialization test failed"
    exit 1
fi

echo "Binary serialization test completed successfully"
exit 0
