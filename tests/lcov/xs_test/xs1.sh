#!/usr/bin/env bash
# Verify that the pure-Perl and C++ XS implementations of the coverage data
# classes support identical interfaces and produce identical results.
#
# xs1 of the former monolithic 'xs_test.sh' (see setup_common.sh).
# Covers: MapData; CountData; CountData non-fatal (ignored) error conditions.
#
# Run with: make check, or tests/bin/runtests.py lcov/xs_test/xs1.sh

set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf xs1.d
    exit 0
fi

WORKDIR=xs1.d
source ./setup_common.sh

status=0

# ==============================================================================
# MapData tests
# ==============================================================================

run_test "MapData::new + is_empty" '
use lcovutil;
my $m = MapData->new();
print $m->is_empty() ? "empty" : "not-empty";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MapData::append_if_unset (no overwrite)" '
use lcovutil;
my $m = MapData->new();
$m->append_if_unset("k", "v1");
$m->append_if_unset("k", "v2");
print $m->value("k");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MapData::replace" '
use lcovutil;
my $m = MapData->new();
$m->replace("k", "v1");
$m->replace("k", "v2");
print $m->value("k");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MapData::value (missing key)" '
use lcovutil;
my $m = MapData->new();
my $v = $m->value("nosuchkey");
print defined($v) ? "defined" : "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MapData::mapped" '
use lcovutil;
my $m = MapData->new();
$m->replace("k", "v");
print $m->mapped("k"), " ", $m->mapped("other");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MapData::entries + keylist" '
use lcovutil;
my $m = MapData->new();
$m->replace("b", 2);
$m->replace("a", 1);
$m->replace("c", 3);
print $m->entries(), " ", join(",", sort $m->keylist());
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MapData::remove (unconditional)" '
use lcovutil;
my $m = MapData->new();
$m->replace("k", "v");
my $r = $m->remove("k");
print $r, " ", $m->entries();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MapData::remove (check_is_present, key absent)" '
use lcovutil;
my $m = MapData->new();
my $r = $m->remove("nosuchkey", 1);
print $r;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MapData::is_empty after all removals" '
use lcovutil;
my $m = MapData->new();
$m->replace("a", 1);
$m->remove("a");
print $m->is_empty();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# CountData tests
# ==============================================================================

run_test "CountData::new + filename" '
use lcovutil;
my $c = CountData->new("src/foo.c");
print $c->filename();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::append new key" '
use lcovutil;
my $c = CountData->new("f");
my $ch = $c->append(10, 5);
print $ch, " ", $c->found(), " ", $c->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::append accumulate" '
use lcovutil;
my $c = CountData->new("f");
$c->append(10, 3);
$c->append(10, 4);
print $c->value(10), " ", $c->found(), " ", $c->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::append zero count (found not hit)" '
use lcovutil;
my $c = CountData->new("f");
my $ch = $c->append(5, 0);
print $ch, " ", $c->found(), " ", $c->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::append zero then nonzero (hit increments)" '
use lcovutil;
my $c = CountData->new("f");
$c->append(5, 0);
my $ch = $c->append(5, 2);
print $ch, " ", $c->found(), " ", $c->hit(), " ", $c->value(5);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::value missing key" '
use lcovutil;
my $c = CountData->new("f");
my $v = $c->value(99);
print defined($v) ? "defined" : "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::remove" '
use lcovutil;
my $c = CountData->new("f");
$c->append(1, 5);
$c->append(2, 0);
$c->remove(1);
print $c->found(), " ", $c->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::keylist + entries" '
use lcovutil;
my $c = CountData->new("f");
$c->append(3, 1);
$c->append(1, 2);
$c->append(2, 0);
print $c->entries(), " ", join(",", sort { $a <=> $b } $c->keylist());
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Under XS the line->count store is a vector kept sorted by line, not a hash,
# so insertion order is a correctness concern there in a way it is not for the
# pure-Perl hash: value() binary-searches, so an unsorted vector loses keys.  geninfo
# appends in increasing line order (the fast push_back path); these exercise
# the paths it does NOT take: strictly descending inserts, an update landing
# mid-vector, and inserts at the front and past the end.
run_test "CountData::append descending insertion order" '
use lcovutil;
my $c = CountData->new("f");
$c->append($_, $_ % 3) for reverse 1 .. 20;
$c->append(7, 5);      # update an existing key in the middle
$c->append(100, 1);    # insert past the end
$c->append(0, 0);      # insert before the front
my @k = sort { $a <=> $b } $c->keylist();
print "entries=", $c->entries(), " found=", $c->found(), " hit=", $c->hit(), "\n";
print join(",", map { "$_=" . $c->value($_) } @k);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::remove after out-of-order insertion" '
use lcovutil;
my $c = CountData->new("f");
$c->append($_, $_ % 2) for (9, 2, 7, 4, 1, 8, 3);
$c->remove(1);    # first key
$c->remove(9);    # last key
$c->remove(4);    # middle key
my @k = sort { $a <=> $b } $c->keylist();
print "found=", $c->found(), " hit=", $c->hit(), " entries=", $c->entries(), "\n";
print join(",", map { "$_=" . $c->value($_) } @k);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# NOTE: the coverage objects are deliberately NOT named $a/$b here -- those are
# the sort comparator globals, and shadowing them with a lexical makes
# sort { $a <=> $b } compare the objects instead of the keys.
run_test "CountData::union of out-of-order operands (interleaved keys)" '
use lcovutil;
my $ca = CountData->new("a");
$ca->append($_, 1) for (10, 3, 7, 1, 9);
my $cb = CountData->new("b");
$cb->append($_, 2) for (8, 3, 12, 1);
$ca->union($cb);
my @k = sort { $a <=> $b } $ca->keylist();
print "found=", $ca->found(), " hit=", $ca->hit(), "\n";
print join(",", map { "$_=" . $ca->value($_) } @k);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# The shared-key branch of the union merge: a key both sides hold, where self
# has 0 and other is non-zero, so the merge must bump hit as it combines them.
run_test "CountData::union shared key 0 + nonzero increments hit" '
use lcovutil;
my $ca = CountData->new("a");
$ca->append($_, 0) for (7, 2, 11);      # all zero, out of order
my $cb = CountData->new("b");
$cb->append($_, 4) for (11, 2);         # non-zero on two shared keys
$ca->union($cb);
my @k = sort { $a <=> $b } $ca->keylist();
print "found=", $ca->found(), " hit=", $ca->hit(), " ",
      join(",", map { "$_=" . $ca->value($_) } @k);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::intersect/difference of out-of-order operands" '
use lcovutil;
sub build { my $c = CountData->new("x"); $c->append($_, 1) for @_; return $c; }
my $cb = build(8, 3, 12, 1);
for my $op (qw(intersect difference)) {
    my $ca = build(10, 3, 7, 1, 9);
    $ca->$op($cb);
    my @k = sort { $a <=> $b } $ca->keylist();
    print "$op found=", $ca->found(), " hit=", $ca->hit(), " ",
          join(",", map { "$_=" . $ca->value($_) } @k), "\n";
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::union/intersect/difference with empty operand" '
use lcovutil;
sub build { my $c = CountData->new("x"); $c->append($_, 1) for @_; return $c; }
for my $op (qw(union intersect difference)) {
    my $ca = build(5, 2, 9);
    $ca->$op(CountData->new("empty"));
    my @k = sort { $a <=> $b } $ca->keylist();
    print "$op found=", $ca->found(), " hit=", $ca->hit(), " entries=", $ca->entries(),
          " [", join(",", map { "$_=" . $ca->value($_) } @k), "]\n";
}
my $e = CountData->new("empty");
$e->union(build(5, 2, 9));
print "empty-union found=", $e->found(), " keys=",
      join(",", sort { $a <=> $b } $e->keylist());
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::dclone round-trip after out-of-order insertion" '
use lcovutil;
use Storable;
my $c = CountData->new("f");
$c->append($_, $_ % 3) for (17, 4, 23, 1, 9, 100, 2);
my $cl = Storable::dclone($c);
my @k = sort { $a <=> $b } $cl->keylist();
print "found=", $cl->found(), " hit=", $cl->hit(), " entries=", $cl->entries(), "\n";
print join(",", map { "$_=" . $cl->value($_) } @k);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::get_found_and_hit" '
use lcovutil;
my $c = CountData->new("f");
$c->append(1, 3);
$c->append(2, 0);
$c->append(3, 1);
my ($f,$h) = $c->get_found_and_hit();
print "$f $h";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::union" '
use lcovutil;
my $a = CountData->new("a");
$a->append(1, 2);
$a->append(2, 0);
my $b = CountData->new("b");
$b->append(2, 3);
$b->append(3, 1);
$a->union($b);
print $a->found(), " ", $a->hit(), " ", $a->value(1), " ", $a->value(2), " ", $a->value(3);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::intersect" '
use lcovutil;
my $a = CountData->new("a");
$a->append(1, 2);
$a->append(2, 0);
$a->append(3, 1);
my $b = CountData->new("b");
$b->append(1, 1);
$b->append(3, 0);
$b->append(4, 5);
$a->intersect($b);
my $v2 = defined($a->value(2)) ? $a->value(2) : "undef";
my $v4 = defined($a->value(4)) ? $a->value(4) : "undef";
print $a->found(), " ", $a->hit(), " ", $a->value(1), " v2=$v2 v4=$v4 ", $a->value(3);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::difference" '
use lcovutil;
my $a = CountData->new("a");
$a->append(1, 5);
$a->append(2, 3);
$a->append(3, 0);
my $b = CountData->new("b");
$b->append(2, 1);
$a->difference($b);
my $v2 = defined($a->value(2)) ? $a->value(2) : "undef";
print $a->found(), " ", $a->hit(), " ", $a->value(1), " v2=$v2 ", $a->value(3);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::intersect hit-increment (0 then nonzero on shared key)" '
use lcovutil;
my $a = CountData->new("a");
$a->append(5, 0);
my $b = CountData->new("b");
$b->append(5, 4);
$a->intersect($b);
print $a->found(), " ", $a->hit(), " ", $a->value(5);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::intersect drops hit entry not in other" '
use lcovutil;
my $a = CountData->new("a");
$a->append(1, 7);
$a->append(2, 9);
my $b = CountData->new("b");
$b->append(1, 1);
$a->intersect($b);
my $v2 = defined($a->value(2)) ? $a->value(2) : "undef";
print $a->found(), " ", $a->hit(), " ", $a->value(1), " v2=$v2";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::difference drops hit entry (hit decrements)" '
use lcovutil;
my $a = CountData->new("a");
$a->append(1, 8);
$a->append(2, 0);
my $b = CountData->new("b");
$b->append(1, 1);
$b->append(2, 1);
$a->difference($b);
print $a->found(), " ", $a->hit(), " ", $a->entries();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::remove retainElement keeps key, adjusts counts" '
use lcovutil;
my $c = CountData->new("f");
$c->append(1, 5);
$c->append(2, 0);
my $r = $c->remove(1, undef, 1);
my $v1 = defined($c->value(1)) ? $c->value(1) : "undef";
print $r, " found=", $c->found(), " hit=", $c->hit(), " entries=", $c->entries(), " v1=$v1";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::remove check_is_present on present hit entry" '
use lcovutil;
my $c = CountData->new("f");
$c->append(3, 9);
my $r = $c->remove(3, 1);
print $r, " found=", $c->found(), " hit=", $c->hit(), " entries=", $c->entries();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::remove check_is_present on absent key (no-op)" '
use lcovutil;
my $c = CountData->new("f");
$c->append(1, 1);
my $r = $c->remove(99, 1);
print $r, " found=", $c->found(), " entries=", $c->entries();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::new with sortable" '
use lcovutil;
my $c = CountData->new("f", $CountData::SORTED);
$c->append(1, 1);
print $c->found();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# CountData error conditions -- same error, same message in XS and pure-Perl
# ==============================================================================

# --- non-fatal (ignored) errors: message text + surviving state both match ---

run_test "CountData::append FORMAT error (non-numeric, ignored)" '
use lcovutil;
lcovutil::parse_ignore_errors("format");
my $c = CountData->new("src/foo.c");
$c->append(42, "notanumber");
print "count=", $c->value(42) // "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::append NEGATIVE error (ignored)" '
use lcovutil;
lcovutil::parse_ignore_errors("negative");
my $c = CountData->new("src/foo.c");
$c->append(7, -3);
print "count=", $c->value(7) // "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::append EXCESSIVE_COUNT error (ignored)" '
use lcovutil;
$lcovutil::excessive_count_threshold = 100;
lcovutil::parse_ignore_errors("excessive");
my $c = CountData->new("src/foo.c");
$c->append(99, 9999);
print "count=", $c->value(99) // "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::append FORMAT error suppressErrMsg flag" '
use lcovutil;
my $c = CountData->new("src/foo.c");
$c->append(1, "bad", 1);
print "count=", $c->value(1) // "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::append NEGATIVE error suppressErrMsg flag" '
use lcovutil;
my $c = CountData->new("src/foo.c");
$c->append(1, -5, 1);
print "count=", $c->value(1) // "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "CountData::append EXCESSIVE_COUNT error suppressErrMsg flag" '
use lcovutil;
$lcovutil::excessive_count_threshold = 100;
my $c = CountData->new("src/foo.c");
$c->append(1, 9999, 1);
print "count=", $c->value(1) // "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

if [ $status -eq 0 ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'xs_1' $LOCAL_COVERAGE
fi

exit $status
