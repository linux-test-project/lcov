#!/usr/bin/env bash
# Verify that the pure-Perl and C++ XS implementations of the coverage data
# classes support identical interfaces and produce identical results.
#
# xs2 of the former monolithic 'xs_test.sh' (see setup_common.sh).
# Covers: CountData fatal error conditions; Storable freeze/thaw and
# store/retrieve round-trips; BranchElement; BranchBlock.
#
# Run with: make check, or tests/bin/runtests.py lcov/xs_test/xs2.sh

set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf xs2.d
    exit 0
fi

WORKDIR=xs2.d
source ./setup_common.sh

status=0


# --- fatal errors: process dies with matching message ---

run_error_test "CountData::append FORMAT error (fatal)" '
use lcovutil;
my $c = CountData->new("src/foo.c");
$c->append(42, "notanumber");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "CountData::append NEGATIVE error (fatal)" '
use lcovutil;
my $c = CountData->new("src/foo.c");
$c->append(7, -3);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "CountData::append EXCESSIVE_COUNT error (fatal)" '
use lcovutil;
$lcovutil::excessive_count_threshold = 100;
my $c = CountData->new("src/foo.c");
$c->append(99, 9999);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "CountData::remove missing key (fatal)" '
use lcovutil;
my $c = CountData->new("src/foo.c");
$c->remove(99);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# Storable freeze/thaw round-trip
# ==============================================================================

run_test "CountData Storable freeze/thaw" '
use lcovutil;
use Storable qw(freeze thaw);
my $c = CountData->new("s.c", 0);
$c->append(10, 5);
$c->append(20, 0);
$c->append(30, 3);
my $r = thaw(freeze($c));
print ref($r), " ", $r->filename(), " ", $r->found(), " ", $r->hit(),
      " ", $r->value(10), " ", $r->value(20), " ", $r->value(30);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MapData Storable freeze/thaw" '
use lcovutil;
use Storable qw(freeze thaw);
my $m = MapData->new();
$m->replace("x", "hello");
$m->replace("y", 42);
my $r = thaw(freeze($m));
print ref($r), " ", $r->value("x"), " ", $r->value("y"), " ", $r->entries();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData dclone independence" '
use lcovutil;
use Storable qw(dclone);
my $c = CountData->new("f");
$c->append(1, 3);
my $d = dclone($c);
$d->append(1, 10);
print $c->value(1), " ", $d->value(1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MapData dclone independence" '
use lcovutil;
use Storable qw(dclone);
my $m = MapData->new();
$m->replace("k", "orig");
my $d = dclone($m);
$d->replace("k", "copy");
print $m->value("k"), " ", $d->value("k");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# Storable store/retrieve round-trip (same-mode)
# ==============================================================================

TMPFILE=$(mktemp /tmp/xs_test_XXXXXX.dat)
trap "rm -f $TMPFILE" EXIT

STORABLE_STORE_CODE='
use lcovutil;
use Storable qw(store);
my $c = CountData->new("stored.c");
$c->append(1, 7);
$c->append(2, 0);
store($c, $ARGV[0]);
'

STORABLE_RETRIEVE_CODE='
use lcovutil;
use Storable qw(retrieve);
my $c = retrieve($ARGV[0]);
print ref($c), " ", $c->filename(), " ", $c->found(), " ", $c->hit(),
      " ", $c->value(1), " ", $c->value(2);
'

# XS store + retrieve
perl -I"$LCOV_HOME_PARENT/lib" -e "$STORABLE_STORE_CODE" -- "$TMPFILE" 2>/dev/null
if [ $? -ne 0 ] ; then
    echo "FAIL [store/XS]"
    status=1
    [ $KEEP_GOING == 0 ] && exit 1
fi

xs_ret=$(perl -I"$LCOV_HOME_PARENT/lib" -e "$STORABLE_RETRIEVE_CODE" -- "$TMPFILE" 2>/dev/null)
expected="CountData stored.c 2 1 7 0"
if [ "$xs_ret" != "$expected" ] ; then
    echo "FAIL [retrieve/XS]: got='$xs_ret' want='$expected'"
    status=1
    [ $KEEP_GOING == 0 ] && exit 1
fi

# PurePerl store + retrieve
LCOV_PURE_PERL=1 perl -I"$LCOV_HOME_PARENT/lib" -e "$STORABLE_STORE_CODE" -- "$TMPFILE" 2>/dev/null
if [ $? -ne 0 ] ; then
    echo "FAIL [store/PurePerl]"
    status=1
    [ $KEEP_GOING == 0 ] && exit 1
fi

pp_ret=$(LCOV_PURE_PERL=1 perl -I"$LCOV_HOME_PARENT/lib" -e "$STORABLE_RETRIEVE_CODE" -- "$TMPFILE" 2>/dev/null)
if [ "$pp_ret" != "$expected" ] ; then
    echo "FAIL [retrieve/PurePerl]: got='$pp_ret' want='$expected'"
    status=1
    [ $KEEP_GOING == 0 ] && exit 1
fi

# ==============================================================================
# BranchElement tests
# ==============================================================================

run_test "BranchElement::new basic" '
use lcovutil;
my $b = BranchElement->new("1", 5);
print ref($b), " ", $b->id(), " ", $b->count(), " ", $b->isTaken();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::new not-taken dash" '
use lcovutil;
my $b = BranchElement->new("2", "-");
print($b->isTaken() ? 1 : 0), " ", $b->count(), " ", $b->data();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::new zero taken" '
use lcovutil;
my $b = BranchElement->new("0", 0);
print($b->isTaken() ? 1 : 0), " ", $b->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::new with expr same as id" '
use lcovutil;
my $b = BranchElement->new("myid", 3, "myid");
my $e = defined($b->expr()) ? $b->expr() : "undef";
print $e;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::new with distinct expr" '
use lcovutil;
my $b = BranchElement->new("myid", 3, "x>0");
print $b->expr(), " ", $b->exprString();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::new type VANILLA" '
use lcovutil;
my $b = BranchElement->new("1", 1);
print $b->type(), " ", $b->type_name(), " ", $b->signature(), " ",
      ($b->is_exception() ? 1 : 0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::new type EXCEPT" '
use lcovutil;
my $b = BranchElement->new("1", 1, undef, BranchElement::EXCEPT);
print $b->type(), " ", $b->type_name(), " ", $b->signature(), " ",
      ($b->is_exception() ? 1 : 0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::new type FALLTHROUGH" '
use lcovutil;
my $b = BranchElement->new("1", 1, undef, BranchElement::FALLTHROUGH);
print $b->type(), " ", $b->type_name(), " ", $b->signature();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::new excluded" '
use lcovutil;
my $b = BranchElement->new("1", 1, undef, undef, 1);
print $b->is_excluded();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::set_excluded" '
use lcovutil;
my $b = BranchElement->new("1", 1);
my $r1 = $b->set_excluded();
my $r2 = $b->set_excluded();
print $b->is_excluded(), " r1=$r1 r2=$r2";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::isDifferential false" '
use lcovutil;
my $b = BranchElement->new("1", 5);
print($b->isDifferential() ? 1 : 0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::isDifferential true after push" '
use lcovutil;
my $b = BranchElement->new("1", 5);
$b->set_differential("UNC", 0, 5);
print($b->isDifferential() ? 1 : 0), " ", $b->tla();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::merge basic accumulation" '
use lcovutil;
my $a = BranchElement->new("1", 3);
my $b = BranchElement->new("1", 4);
my $changed = $a->merge($b, "f.c", 10);
print $changed, " ", $a->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::merge dash + value" '
use lcovutil;
my $a = BranchElement->new("1", "-");
my $b = BranchElement->new("1", 5);
my $changed = $a->merge($b, "f.c", 1);
print $changed, " ", $a->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::merge value + dash (no change)" '
use lcovutil;
my $a = BranchElement->new("1", 3);
my $b = BranchElement->new("1", "-");
my $changed = $a->merge($b, "f.c", 1);
print $changed, " ", $a->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Merging a differential element (that) into a non-differential one (self)
# must NOT make self differential: pure-Perl BranchElement::merge never copies
# tla/base/curr.  merge/union/intersect only run on RAW coverage during load;
# differential data is attached later (genhtml cloneBlock/set_differential) on
# freshly built blocks that are not re-merged.  Guards BranchData.cpp:139.
run_test "BranchElement::merge does not copy differential from that" '
use lcovutil;
my $a = BranchElement->new(0, 5);
my $b = BranchElement->new(0, 3);
$b->set_differential("UNC", 1, 2);
my $changed = $a->merge($b, "f.c", 10);
print "isDiff=", ($a->isDifferential ? 1 : 0), " count=", $a->count(),
      " changed=$changed";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement format error (non-numeric taken, ignored)" '
use lcovutil;
lcovutil::parse_ignore_errors("format");
my $b = BranchElement->new("1", "notanumber");
print "taken=", $b->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# A reference as TAKEN is the only way into the looks_like_number() arm of the
# shared TAKEN validation: undef returns early, a string (SvPOK) or a tied
# scalar (SvMAGICAL) goes down the grok_number() path, and an IV/NV already IS a
# number.  The stringification is overloaded so the reported value is stable
# across the two runs -- a plain ref would print its address, which differs.
run_test "BranchElement format error (reference taken, ignored)" '
use lcovutil;
package StableRef;
use overload q{""} => sub { "notanumber" }, fallback => 1;
package main;
lcovutil::parse_ignore_errors("format");
my $b = BranchElement->new("1", bless({}, "StableRef"));
print "taken=", $b->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# A negative branch ID.  No .info file contains one, but a Perl caller can pass
# one, and it is the only route to the sign-emitting arm of the integer-to-text
# conversion in the XS layer (an ID given as an IV rather than as a string skips
# SvPV entirely).  Passing the matching expr text also drives the
# "expr eq id" comparison against that conversion.
run_test "BranchElement negative integer id" '
use lcovutil;
my $b = BranchElement->new(-3, 5, "-3");
print "id=", $b->id(), " count=", $b->count(), " expr=[", $b->expr(), "]";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement negative error (ignored)" '
use lcovutil;
lcovutil::parse_ignore_errors("negative");
my $b = BranchElement->new("1", -5);
print "taken=", $b->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement excessive error (ignored, value kept)" '
use lcovutil;
$lcovutil::excessive_count_threshold = 100;
lcovutil::parse_ignore_errors("excessive");
my $b = BranchElement->new("1", 9999);
print "taken=", $b->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement Storable dclone" '
use lcovutil;
use Storable qw(dclone);
my $b = BranchElement->new("1", 7, "x>0");
my $c = dclone($b);
$c->merge(BranchElement->new("1", 3), "f.c", 1);
print ref($c), " ", $b->count(), " ", $c->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# BranchBlock tests
# ==============================================================================

run_test "BranchBlock::new + empty" '
use lcovutil;
my $bb = BranchBlock->new();
print ref($bb), " empty=", ($bb->empty() ? 1 : 0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchBlock::appendElement + signature + elements" '
use lcovutil;
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 3));
$bb->appendElement(BranchElement->new("2", 0));
print($bb->empty() ? 1 : 0), " ", $bb->signature(), " ", scalar(@{$bb->elements()});
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# appendNew builds the element in place instead of taking a finished one.
# TraceFile::_read_info is its only production caller, and in an XS process the
# XSUB shadows the pure-Perl sub, so neither implementation is reachable from
# the other; calling it directly is what covers both.
run_test "BranchBlock::appendNew + signature + elements" '
use lcovutil;
my $bb = BranchBlock->new();
$bb->appendNew(7, 3, "a>0", 0, 0);
$bb->appendNew(8, 0, "b>0", 1, 0);
$bb->appendNew(9, "-", "c>0", 2, 1);
my @e = @{$bb->elements()};
print $bb->signature(), " ", scalar(@e),
      " ids=", join(",", map { $_->id() } @e),
      " counts=", join(",", map { $_->count() } @e),
      " excl=", join(",", map { $_->is_excluded() ? 1 : 0 } @e);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchBlock::setIdx + idx" '
use lcovutil;
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 1));
$bb->setIdx(42);
print $bb->idx();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchBlock::getElement" '
use lcovutil;
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 5));
$bb->appendElement(BranchElement->new("2", 0));
print $bb->getElement(0)->id(), " ", $bb->getElement(1)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchBlock::merge" '
use lcovutil;
my $a = BranchBlock->new();
$a->appendElement(BranchElement->new("1", 3));
$a->appendElement(BranchElement->new("2", 0));
my $b = BranchBlock->new();
$b->appendElement(BranchElement->new("1", 2));
$b->appendElement(BranchElement->new("2", 4));
my $changed = $a->merge($b, "f.c", 10);
print $changed, " ", $a->getElement(0)->count(), " ", $a->getElement(1)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Merging blocks whose element count / signature differ is fatal.  The XS path
# throws a C++ std::runtime_error internally; the merge XSUB must convert it to
# a Perl die (croak) rather than letting it escape to terminate()/abort, so it
# matches the pure-Perl die("expected identical block").
run_error_test "BranchBlock::merge non-identical dies" '
use lcovutil;
my $a = BranchBlock->new();
$a->appendElement(BranchElement->new(0, 5, "e", 0));
my $b = BranchBlock->new();
$b->appendElement(BranchElement->new(0, 5, "e", 0));
$b->appendElement(BranchElement->new(1, 5, "e", 0));
$a->merge($b, "f.c", 10);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchBlock Storable dclone independence" '
use lcovutil;
use Storable qw(dclone);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 10));
my $cc = dclone($bb);
$cc->getElement(0)->merge(BranchElement->new("1", 5), "f.c", 1);
print $bb->getElement(0)->count(), " ", $cc->getElement(0)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }


if [ $status -eq 0 ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'xs_2' $LOCAL_COVERAGE
fi

exit $status
