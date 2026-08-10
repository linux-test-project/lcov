#!/usr/bin/env bash
set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf *.dat *.log *.pl *.info html_report
    exit 0
fi

# ---------------------------------------------------------------------------
# Cross-format (XS <-> pure-Perl) serialization guard.
#
# The XS acceleration layer and the pure-Perl implementation serialize the
# coverage classes incompatibly.  A file written by one build and read by the
# other must NOT blow up with a cryptic internal Storable error; instead
# TraceFile::deserialize (via lcovutil::deserialize_checked) must raise
# ERROR_FORMAT and tell the user to flip LCOV_PURE_PERL.
#
# This test drives both directions and both failure modes:
#   * mode A  -- cross-format Storable::retrieve dies INSIDE retrieve.  This is
#                what a real whole-TraceFile read does, because a TraceFile
#                always carries hook-bearing CountData/MapData leaves whose
#                cross-format thaw blows up.
#   * mode B  -- retrieve SUCCEEDS SILENTLY (every serialized leaf is a class
#                without a STORABLE hook, e.g. a pure-Perl BranchData, which is
#                just a blessed arrayref) and the mismatch is only caught
#                afterwards by deserialize_checked()'s ref-shape probe.  A real
#                TraceFile never reaches mode B, so to exercise it we hand-build
#                a minimal TraceFile-shaped structure whose one probed leaf is a
#                hookless BranchData.
# ---------------------------------------------------------------------------

BLIB="-I$LCOV_HOME/lib/LcovUtil/blib/lib -I$LCOV_HOME/lib/LcovUtil/blib/arch"
INC="$BLIB -I$LCOV_HOME/lib"

# Is XS even available?  If not, cross-format testing is meaningless (both
# "modes" would be pure-Perl); skip cleanly.
perl $INC -e 'use LcovUtil; exit($LcovUtil::XS_LOADED ? 0 : 1);'
if [ $? != 0 ] ; then
    echo "Skipping test - XS not available"
    exit 0
fi

# Writer: build a TraceFile and serialize it.  With arg 'branchonly', populate
# ONLY branch data (BranchData has no STORABLE hook in pure-Perl) to exercise
# the silent-success mode-B path.
cat > writer.pl <<'EOF'
use strict; use warnings;
use Scalar::Util;
use lcovutil;
my ($file, $mode) = @ARGV;
my $tf = TraceFile->new();
my $ti = $tf->data("foo.c");
if (defined($mode) && $mode eq 'branchonly') {
    my $loc = $ti->sumbr()->findOrCreate(1);
    my $blk = BranchBlock->new();
    $blk->appendElement(BranchElement->new(0, 3, undef, 0, 0));
    $loc->insertBlock($blk);
    $ti->sumbr()->updateCounts();
} else {
    $ti->sum()->append(1, 5);
    $ti->sum()->append(2, 0);
}
$tf->serialize($file);
print "wrote $file (XS_LOADED=", ($lcovutil::XS_LOADED // 0), ")\n";
EOF

# Reader: deserialize with ERROR_FORMAT made non-fatal so we can observe the
# emitted message (which goes to stderr) and keep going.
cat > reader.pl <<'EOF'
use strict; use warnings;
use Scalar::Util;
use lcovutil;
$lcovutil::stop_on_error = 0;
my ($file) = @ARGV;
my $tf = eval { TraceFile->deserialize($file) };
print "reader XS_LOADED=", ($lcovutil::XS_LOADED // 0), "\n";
if ($@) { print "reader: deserialize threw (expected on mismatch)\n"; }
elsif (!defined $tf) { print "reader: deserialize returned undef\n"; }
else { print "reader: deserialize OK ref=", ref($tf), "\n"; }
EOF

# Mode-B writer: hand-build the minimal structure that _first_coverage_leaf()
# walks -- $tf->[FILES=0]{name}->[LINE_DATA=4][0] -- and put a HOOKLESS leaf
# (a pure-Perl BranchData, which is just a blessed arrayref with no
# STORABLE_freeze) at that slot.  With no hook in the stream, a cross-format
# Storable::retrieve rebuilds the arrayref verbatim and SUCCEEDS, so the reader
# reaches deserialize_checked()'s ref-shape probe (mode B) instead of dying
# inside retrieve (mode A).  Must be written by the pure-Perl build.
cat > writer_modeb.pl <<'EOF'
use strict; use warnings;
use Storable;
use lcovutil;
my ($file) = @ARGV;
die "writer_modeb must run pure-Perl\n" if $lcovutil::XS_LOADED;
my $bd    = BranchData->new();          # hookless blessed arrayref
my $entry = [];
$entry->[4] = [$bd];                    # TraceInfo::LINE_DATA slot 0 = leaf
my $tf = [];
$tf->[0] = {'foo.c' => $entry};         # TraceFile::FILES
bless $tf, 'TraceFile';
Storable::store($tf, $file);
print "wrote $file (XS_LOADED=", ($lcovutil::XS_LOADED // 0), ")\n";
EOF

FAIL=0

check_mismatch() {
    # $1: log file, $2: expected hint substring, $3: label
    local log=$1 hint=$2 label=$3
    if ! grep -q 'ERROR: (format)' "$log" ; then
        echo "FAIL ($label): no ERROR_FORMAT emitted"
        cat "$log"
        FAIL=1
        return
    fi
    if ! grep -q "$hint" "$log" ; then
        echo "FAIL ($label): expected hint '$hint' not found"
        cat "$log"
        FAIL=1
        return
    fi
    echo "PASS ($label): ERROR_FORMAT with correct hint"
}

# --- Direction 1: XS writes, pure-Perl reads (mode A) ----------------------
# The reader here is the pure-Perl process, so the hint tells it to leave
# LCOV_PURE_PERL set (the file was written by XS).
perl $PERL_COVER_ARGS $INC writer.pl xs_full.dat > /dev/null 2>&1
LCOV_PURE_PERL=1 perl $PERL_COVER_ARGS $INC reader.pl xs_full.dat > d1.log 2>&1
check_mismatch d1.log 'LCOV_PURE_PERL unset' "XS-written, pure-Perl read"

# --- Direction 2: pure-Perl writes, XS reads (mode A) ----------------------
# The reader here is the XS process, so the hint tells it to set
# LCOV_PURE_PERL=1 (the file was written by pure-Perl).
LCOV_PURE_PERL=1 perl $PERL_COVER_ARGS $INC writer.pl pp_full.dat > /dev/null 2>&1
perl $PERL_COVER_ARGS $INC reader.pl pp_full.dat > d2.log 2>&1
check_mismatch d2.log 'LCOV_PURE_PERL=1' "pure-Perl-written, XS read"

# --- Direction 2b: pure-Perl writes branch-only TraceFile, XS reads --------
# Still mode A (the TraceFile's CountData/MapData leaves carry hooks), but
# confirms the guard also fires for a branch-only payload.
LCOV_PURE_PERL=1 perl $PERL_COVER_ARGS $INC writer.pl pp_branch.dat branchonly > /dev/null 2>&1
perl $PERL_COVER_ARGS $INC reader.pl pp_branch.dat > d3.log 2>&1
check_mismatch d3.log 'LCOV_PURE_PERL=1' "pure-Perl branch-only, XS read"

# --- Mode B: pure-Perl writes a hookless-leaf payload, XS reads ------------
# This is the ONLY case that reaches deserialize_checked()'s ref-shape probe:
# retrieve succeeds silently (no STORABLE hook in the stream), then the probe
# sees a blessed non-SCALAR leaf under an XS build and reports ERROR_FORMAT.
LCOV_PURE_PERL=1 perl $PERL_COVER_ARGS $INC writer_modeb.pl pp_modeb.dat > /dev/null 2>&1
perl $PERL_COVER_ARGS $INC reader.pl pp_modeb.dat > d4.log 2>&1
check_mismatch d4.log 'not in the expected XS binary format' "mode B (hookless leaf, XS read)"
# and it must carry the correct flip hint too
if ! grep -q 'LCOV_PURE_PERL=1' d4.log ; then
    echo "FAIL (mode B): expected 'LCOV_PURE_PERL=1' hint not found"
    cat d4.log
    FAIL=1
fi

# --- Mode B probe with nothing to probe: an empty TraceFile ------------------
# The ref-shape probe is best-effort: a payload with no coverage leaf at all
# tells it nothing about which implementation wrote the file, so it must report
# "no opinion" and let the deserialize succeed rather than guessing.  An empty
# TraceFile -- what "lcov -a" of a file with no records produces -- is exactly
# that payload: TraceFile-shaped, FILES present but empty, so the probe walks
# off the end of the (zero) entries.
perl $PERL_COVER_ARGS $INC -e 'use lcovutil; TraceFile->new()->serialize("xs_empty.dat");' \
    > /dev/null 2>&1
perl $PERL_COVER_ARGS $INC reader.pl xs_empty.dat > d5.log 2>&1
if grep -q 'ERROR: (format)' d5.log || ! grep -q 'deserialize OK' d5.log ; then
    echo "FAIL (empty TraceFile): guard fired on a payload with no coverage leaf"
    cat d5.log
    FAIL=1
else
    echo "PASS (empty TraceFile): probe finds no leaf and does not guess"
fi

# --- Sanity: same-mode round-trips must NOT trip the guard -----------------
perl $PERL_COVER_ARGS $INC reader.pl xs_full.dat > same_xs.log 2>&1
if grep -q 'ERROR: (format)' same_xs.log || \
   ! grep -q 'deserialize OK' same_xs.log ; then
    echo "FAIL (same-mode XS): guard fired on a consistent file"
    cat same_xs.log
    FAIL=1
else
    echo "PASS (same-mode XS): consistent file round-trips cleanly"
fi

LCOV_PURE_PERL=1 perl $PERL_COVER_ARGS $INC reader.pl pp_full.dat > same_pp.log 2>&1
if grep -q 'ERROR: (format)' same_pp.log || \
   ! grep -q 'deserialize OK' same_pp.log ; then
    echo "FAIL (same-mode pure-Perl): guard fired on a consistent file"
    cat same_pp.log
    FAIL=1
else
    echo "PASS (same-mode pure-Perl): consistent file round-trips cleanly"
fi

if [[ $FAIL != 0 && $KEEP_GOING != 1 ]] ; then
    echo "Cross-format serialization test failed"
    exit 1
fi

echo "Cross-format serialization test completed successfully"
if [ "x$COVER" != "x" ] ; then
    generate_coverage 'format.sh' $LOCAL_COVERAGE
fi
exit 0
