#!/usr/bin/env bash
# Verify that the pure-Perl and C++ XS implementations of the coverage data
# classes support identical interfaces and produce identical results.
#
# xs6 of the former monolithic 'xs_test.sh' (see setup_common.sh).
# Covers: variable-argument callers; BranchData/MCDCData set operations;
# write_data batch accessors; keylist in scalar context; _checkCounts;
# MCDC_Block::is_compatible; the MCDC_Data union/intersect incompatible-record
# gate; remove() without the 'check' flag; append_mcdc; insertExpr undef count.
#
# Run with: make check, or tests/bin/runtests.py lcov/xs_test/xs6.sh

set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf xs6.d
    exit 0
fi

WORKDIR=xs6.d
source ./setup_common.sh

status=0

# ==============================================================================
# Variable-argument callers -- the real callers in geninfo/genhtml omit the
# optional trailing arguments.  These tests verify that the XS methods accept
# the shorter forms without a Usage croak.
# ==============================================================================

run_test "insertExpr without excluded arg (geninfo calling convention)" '
use lcovutil;
my $mb = MCDC_Block->new(10);
# 6 args after self -- excluded omitted, should default to false
$mb->insertExpr("f.c", 2, 1, 5, 0, "x");
my $e = $mb->expr(2, 0);
print $e->count(1), " ", $e->is_excluded(1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::union without filename arg" '
use lcovutil;
my $a = MCDC_Data->new();
my $mba = $a->new_mcdc(undef, 10);
$mba->insertExpr("f.c", 2, 1, 2, 0, "x", 0);
$a->close_mcdcBlock($mba);

my $b = MCDC_Data->new();
my $mbb = $b->new_mcdc(undef, 10);
$mbb->insertExpr("f.c", 2, 1, 3, 0, "x", 0);
$b->close_mcdcBlock($mbb);

# 2 args after self -- filename omitted
$a->union($b);
print $a->value(10)->expr(2, 0)->count(1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::intersect without filename arg" '
use lcovutil;
my $a = MCDC_Data->new();
for my $line (10, 20) {
    my $mb = $a->new_mcdc(undef, $line);
    $mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
    $a->close_mcdcBlock($mb);
}
my $b = MCDC_Data->new();
my $mb = $b->new_mcdc(undef, 10);
$mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
$b->close_mcdcBlock($mb);

# 2 args after self -- filename omitted
$a->intersect($b);
print defined($a->value(10)) ? "has10" : "no10",
      " ", defined($a->value(20)) ? "has20" : "no20";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::difference without filename arg" '
use lcovutil;
my $a = MCDC_Data->new();
for my $line (10, 20) {
    my $mb = $a->new_mcdc(undef, $line);
    $mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
    $a->close_mcdcBlock($mb);
}
my $b = MCDC_Data->new();
my $mb = $b->new_mcdc(undef, 10);
$mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
$b->close_mcdcBlock($mb);

# 2 args after self -- filename omitted
$a->difference($b);
print defined($a->value(10)) ? "has10" : "no10",
      " ", defined($a->value(20)) ? "has20" : "no20";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression differential TLA round-trip via set/count" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 0, 1, 0, "a", 0);
my @exprs = @{$mb->expressions(2)};
my $e = $exprs[0];
# Simulate a differential count with TLA "UNC"
$e->set(0, ["UNC", undef, 5]);
my $c = $e->count(0);
# Must return 3-element arrayref: [$tla, $base, $curr]
print ref($c) eq "ARRAY" && scalar(@$c) == 3 ? "ok3" : "bad",
      " tla=", $c->[0] // "undef",
      " base=", defined($c->[1]) ? "undef" : "def",
      " curr=", $c->[2] // "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression differential TLA Storable round-trip" '
use lcovutil;
use Storable qw(dclone);
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 0, 1, 0, "a", 0);
my $e = $mb->expressions(2)->[0];
$e->set(0, ["EUB", 3, 7]);
my $mb2 = dclone($mb);
my $e2 = $mb2->expressions(2)->[0];
my $c2 = $e2->count(0);
print ref($c2) eq "ARRAY" && scalar(@$c2) == 3 ? "ok3" : "bad",
      " tla=", $c2->[0] // "undef",
      " base=", $c2->[1] // "undef",
      " curr=", $c2->[2] // "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block totals with differential UNC count" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 0, 1, 0, "a", 0);
$mb->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
my @exprs = @{$mb->expressions(2)};
# sense 0: covered (curr=1); sense 1: UNC (curr=0)
$exprs[0]->set(0, ["CVG", undef, 1]);
$exprs[0]->set(1, ["UNC", undef, 0]);
my ($found, $hit) = $mb->totals(1);
print "found=$found hit=$hit";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block merge with differential TLA propagation" '
use lcovutil;
my $a = MCDC_Block->new(10);
$a->insertExpr("f.c", 2, 0, 1, 0, "a", 0);
my $b = MCDC_Block->new(10);
$b->insertExpr("f.c", 2, 0, 1, 0, "a", 0);
my @eb = @{$b->expressions(2)};
$eb[0]->set(0, ["UNC", undef, 0]);
$a->merge($b, "f.c");
my $c = $a->expressions(2)->[0]->count(0);
print ref($c) eq "ARRAY" && scalar(@$c) == 3 ? "ok3" : "bad",
      " tla=", $c->[0] // "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# Coverage-targeted tests for BranchData.cpp / MCDCData.cpp set-operation and
# differential paths that the earlier tests did not exercise.  Each drives a
# specific uncovered branch/line in the standalone-compiled C++ objects while
# still asserting XS == pure-Perl behaviour.
# ==============================================================================

# BranchLocation::codes(sorted) comparator tiebreak: two DISTINCT signatures of
# EQUAL length ("b" vs "e") force the size-equal branch into the string compare.
run_test "BranchLocation::codes sorted equal-length signatures (tiebreak)" '
use lcovutil;
my $loc = BranchLocation->new(10);
my $bb = BranchBlock->new();          # vanilla branch -> signature "b"
$bb->appendElement(BranchElement->new("1", 1));
my $eb = BranchBlock->new();          # exception branch -> signature "e"
$eb->appendElement(BranchElement->new("1", 1, undef, BranchElement::EXCEPT));
$loc->insertBlock($bb);
$loc->insertBlock($eb);
print join(",", $loc->codes(1));
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# BranchLocation::merge copy-additional-block: same code present in both, but
# "other" has MORE blocks for it, so the trailing block is copied in.
run_test "BranchLocation::merge copies extra block for shared code" '
use lcovutil;
my $mk = sub {
    my $n = shift;
    my $loc = BranchLocation->new(5);
    for (1 .. $n) {
        my $b = BranchBlock->new();
        $b->appendElement(BranchElement->new("1", 1));
        $loc->insertBlock($b);
    }
    return $loc;
};
my $self  = $mk->(1);
my $other = $mk->(2);
my $ch = $self->merge($other, "f.c");
print "changed=$ch blocks=", $self->numBlocks();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# BranchData::difference trailing-extras: self has 2 blocks for line/code,
# other has 1 -> drop the leading common block, keep the trailing extra.
run_test "BranchData::difference keeps trailing extra blocks" '
use lcovutil;
my $mk = sub {
    my $n = shift;
    my $bd = BranchData->new();
    for (1 .. $n) {
        my $b = BranchBlock->new();
        $b->appendElement(BranchElement->new("1", 1));
        $bd->insertBlock($b, 5);
    }
    return $bd;
};
my $self  = $mk->(2);
my $other = $mk->(1);
my $ch = $self->difference($other);
my $loc = $self->value(5);
print "changed=$ch line5_blocks=", (defined $loc ? $loc->numBlocks() : "gone");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# MCDC_Expression::set with arrayref [tla, base, undef]: base defined but curr
# UNDEF -> set_differential_opt curr-undef branch.
run_test "MCDC_Expression::set differential with undef curr" '
use lcovutil;
my $blk = MCDC_Block->new(7);
$blk->insertExpr("f.c", 2, 0, 3, 0, "expr0", 0);
my $e = $blk->expressions(2)->[0];
$e->set(0, ["UNC", 5, undef]);
my $c = $e->count(0);
print ref($c) eq "ARRAY" ? join(",", map { defined $_ ? $_ : "undef" } @$c) : $c;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# MCDC_Expression differential with TLA but neither base nor curr, round-tripped
# through dclone -> set_tla path on thaw.
run_test "MCDC_Expression::set differential TLA-only dclone (set_tla)" '
use lcovutil;
use Storable qw(dclone);
my $blk = MCDC_Block->new(9);
$blk->insertExpr("f.c", 2, 0, 4, 0, "e0", 0);
my $e = $blk->expressions(2)->[0];
$e->set(1, ["GNC", undef, undef]);
my $d = dclone($blk);
my $c = $d->expressions(2)->[0]->count(1);
print ref($c) eq "ARRAY" ? join(",", map { defined $_ ? $_ : "undef" } @$c) : $c;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# write_data - the '.info' writer's batch accessors
#
# 'TraceFile::write_info' calls these unconditionally on both classes, so a
# missing or divergent XS binding corrupts (or kills) every '.info' file
# written under XS.  Like render_data, the batch result must agree field for
# field with the scalar accessors it replaces, over every representation the
# fields can take.
# ==============================================================================

run_test "BranchElement::write_data agrees with scalar accessors" '
use lcovutil;
foreach my $type (BranchElement::VANILLA, BranchElement::EXCEPT,
                  BranchElement::FALLTHROUGH) {
    foreach my $taken (0, 3, "-") {
        foreach my $excl (0, 1) {
            foreach my $expr (undef, "a&&b", "7") {
                my $b = BranchElement->new("7", $taken, $expr, $type, $excl);
                my ($t, $id, $e, $sig, $ex) = $b->write_data();
                die("taken")    unless $t eq $b->data();
                die("id")       unless $id eq $b->id();
                die("sig")      unless $sig eq $b->signature();
                die("excluded") unless !$ex == !$b->is_excluded();
                # an expr equal to the id is stored as undef - so compare
                #   against expr(), not against what was passed in
                if (defined($b->expr())) {
                    die("expr") unless defined($e) && $e eq $b->expr();
                } else {
                    die("expr defined") if defined($e);
                }
            }
        }
    }
}
print "ok";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# The differential representation is reached only through genhtml, and
# write_data must ignore it entirely:  the '.info' writer emits the vanilla
# taken count, never the TLA.
run_test "BranchElement::write_data ignores differential data" '
use lcovutil;
my $b = BranchElement->new("2", 5, "x||y", BranchElement::EXCEPT, 0);
$b->set_differential("UNC", 1, 5);
my ($t, $id, $e, $sig, $ex) = $b->write_data();
print "taken=$t id=$id expr=$e sig=$sig excl=$ex differential=",
      $b->isDifferential() ? 1 : 0, "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression::write_data agrees with scalar accessors" '
use lcovutil;
# both senses, independently excluded, and independently zero/non-zero
foreach my $cf (0, 4) {
    foreach my $ct (0, 7) {
        foreach my $xf (0, 1) {
            foreach my $xt (0, 1) {
                my $blk = MCDC_Block->new(11);
                $blk->insertExpr("f.c", 2, 0, $cf, 0, "a&&b", $xf);
                $blk->insertExpr("f.c", 2, 1, $ct, 0, "a&&b", $xt);
                my $e = $blk->expr(2, 0);
                my ($f, $t, $ef, $et, $expr) = $e->write_data();
                die("countF")  unless $f == $e->count(0);
                die("countT")  unless $t == $e->count(1);
                die("exclF")   unless !$ef == !$e->is_excluded(0);
                die("exclT")   unless !$et == !$e->is_excluded(1);
                die("expr")    unless $expr eq $e->expression();
            }
        }
    }
}
print "ok";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Differential MC/DC counts are ARRAY refs [tla, base, curr], and write_data
# must hand them back in that shape - exactly as count($sense) does - rather
# than flattening or numifying them.
run_test "MCDC_Expression::write_data differential count shape" '
use lcovutil;
my $blk = MCDC_Block->new(13);
$blk->insertExpr("f.c", 2, 0, 3, 0, "p||q", 0);
my $e = $blk->expr(2, 0);
$e->set(1, ["UNC", 1, 2]);
my ($f, $t, $ef, $et, $expr) = $e->write_data();
print "false=$f trueref=", (ref($t) eq "ARRAY" ? "yes" : "no"),
      " true=", (ref($t) eq "ARRAY" ?
                 join(",", map({ defined $_ ? $_ : "undef" } @$t)) : $t),
      " exclF=$ef exclT=$et expr=$expr\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# base and curr are independently optional in a differential count (an undef
# base means "not in the baseline"), and write_data must preserve each as undef
# rather than defaulting it to 0.
run_test "MCDC_Expression::write_data differential undef base/curr" '
use lcovutil;
foreach my $pair ([undef, 2], [1, undef], [undef, undef]) {
    my $blk = MCDC_Block->new(17);
    $blk->insertExpr("f.c", 2, 0, 3, 0, "p||q", 0);
    my $e = $blk->expr(2, 0);
    $e->set(1, ["UNC", $pair->[0], $pair->[1]]);
    my ($f, $t, $ef, $et, $expr) = $e->write_data();
    die("not a ref") unless ref($t) eq "ARRAY";
    print join(",", map({ defined $_ ? $_ : "undef" } @$t)), " f=$f\n";
    # and the batch result must match the scalar accessor element for element
    my $c = $e->count(1);
    die("count shape") unless ref($c) eq "ARRAY" && scalar(@$c) == scalar(@$t);
    for my $i (0 .. $#$t) {
        die("elem $i") unless (defined($t->[$i]) == defined($c->[$i])) &&
            (!defined($t->[$i]) || $t->[$i] eq $c->[$i]);
    }
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# keylist in scalar context
#
# The pure-Perl bodies are 'return keys(%h)', which yields the key COUNT in
# scalar context.  lcovutil.pm relies on that at four sites which test a map
# for emptiness via 'scalar($map->keylist())'; a list-only XSUB returns the
# last key instead (and undef when the map is empty), so the emptiness test
# reads the wrong thing - silently for a non-empty map, and with an
# uninitialized-value warning for an empty one.
# ==============================================================================

run_test "keylist scalar context is the count (all four containers)" '
use lcovutil;
my $md = MapData->new();
$md->replace($_, 1) foreach ("a", "b", "c");
my $cd = CountData->new("f.c", $CountData::SORTED);
$cd->append($_, 1) foreach (10, 20);
my $bd = BranchData->new();
foreach my $line (5, 6, 7, 8) {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new(0, 1));
    $bd->insertBlock($bb, $line);
}
my $mc = MCDC_Data->new();
foreach my $line (30, 31, 32, 33, 34) {
    my $blk = $mc->new_mcdc(undef, $line);
    $blk->insertExpr("f.c", 2, 1, 1, 0, "e", 0);
}
foreach my $t ([$md, 3], [$cd, 2], [$bd, 4], [$mc, 5]) {
    my ($obj, $want) = @$t;
    my $n = scalar($obj->keylist());
    my @l = $obj->keylist();
    die(ref($obj) . " scalar=$n want=$want")   unless $n == $want;
    die(ref($obj) . " list=" . scalar(@l))     unless scalar(@l) == $want;
    # numeric comparison against 0 - the emptiness test lcovutil.pm makes -
    #   must not warn nor be satisfied by a non-empty map
    die(ref($obj) . " nonempty test")          if 0 == scalar($obj->keylist());
}
# and the empty case, which is what produced the uninitialized-value warning
foreach my $empty (MapData->new(), CountData->new("f.c", $CountData::SORTED),
                   BranchData->new(), MCDC_Data->new()) {
    my $n = scalar($empty->keylist());
    die(ref($empty) . " empty not defined") unless defined($n);
    die(ref($empty) . " empty=$n")          unless 0 == $n;
}
print "ok";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# _checkCounts - the always-on oracle
#
# 'TraceInfo::check_data' calls these on every '.info' read, so they are a live
# assertion that the incrementally-maintained found/hit still equal a full walk
# of the data - not a debug aid.  Both halves need coverage:  agreement on
# honest data (the path every read takes), and a die when the cache is
# deliberately corrupted (the path that catches a broken alias).
# ==============================================================================

run_test "_checkCounts passes on consistent data (all three containers)" '
use lcovutil;
my $cd = CountData->new("f.c", $CountData::SORTED);
$cd->append(10, 3);
$cd->append(11, 0);
$cd->append(10, 2);
$cd->remove(11);
$cd->_checkCounts();
my $bd = BranchData->new();
foreach my $line (5, 6) {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new(0, 1));
    $bb->appendElement(BranchElement->new(1, "-"));
    $bd->insertBlock($bb, $line);
}
# insertBlock deliberately leaves the cache alone - the reader inserts every
#   block for a section and then calls updateCounts once - so the totals only
#   become checkable after that.  'remove' is incremental, so it is exercised
#   after the recompute.
$bd->updateCounts();
$bd->remove(6);
$bd->_checkCounts();
my $mc = MCDC_Data->new();
my $blk = $mc->new_mcdc(undef, 20);
$blk->insertExpr("f.c", 2, 1, 5, 0, "a&&b", 0);
$blk->insertExpr("f.c", 2, 0, 0, 0, "a&&b", 0);
$mc->close_mcdcBlock($blk);
$mc->_checkCounts();
print "cd=", join(",", $cd->get_found_and_hit()),
      " bd=", join(",", $bd->get_found_and_hit()),
      " mc=", join(",", $mc->get_found_and_hit()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Now desynchronize the cache and confirm each _checkCounts notices.  Under XS
# the C++ object is the only copy of the totals, so they can only be driven
# apart through a mutator; the message text is compared after stripping the
# source location.
#
# For CountData that mutator is remove($key, $check, $retainElement=1), which
# subtracts the key from found/hit but leaves the entry in the map - i.e. the
# cache says one fewer line than a walk of the data finds.
run_error_test "CountData::_checkCounts detects a corrupted cache" '
use lcovutil;
my $cd = CountData->new("f.c", $CountData::SORTED);
$cd->append(10, 3);
$cd->append(11, 1);
$cd->remove(10, undef, 1);
$cd->_checkCounts();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "BranchData::_checkCounts detects a corrupted cache" '
use lcovutil;
my $bd = BranchData->new();
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new(0, 1));
$bd->insertBlock($bb, 5);
$bd->updateCounts();
$bd->adjust_counts(3, 0);
$bd->_checkCounts();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "MCDC_Data::_checkCounts detects a corrupted cache" '
use lcovutil;
my $mc = MCDC_Data->new();
my $blk = $mc->new_mcdc(undef, 20);
$blk->insertExpr("f.c", 2, 1, 5, 0, "a&&b", 0);
$mc->close_mcdcBlock($blk);
$mc->adjust_counts(0, 2);
$mc->_checkCounts();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# MCDC_Block::is_compatible
#
# 'is_compatible' is the gate MCDC_Data::union/intersect use to decide whether
# two blocks recorded for the same line describe the same decisions and may
# therefore be merged.  Two things make it easy to get wrong in opposite
# directions:  comparing group COUNTS or group SIZES rejects blocks that merely
# carry an extra group and accepts blocks whose shared expressions differ
# outright, while comparing expression text index-wise walks off the end of a
# shorter shared group.  Each case below is one cell of that matrix.
# ==============================================================================

# A group size present in only one block is not a conflict - merge() copies
# such a group in wholesale - so these must be compatible regardless of which
# side carries the extra group.
run_test "MCDC_Block::is_compatible extra group in argument" '
use lcovutil;
my $a = MCDC_Block->new(10);
$a->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
$a->insertExpr("f.c", 2, 1, 1, 1, "b", 0);
my $b = MCDC_Block->new(10);
$b->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
$b->insertExpr("f.c", 2, 1, 1, 1, "b", 0);
$b->insertExpr("f.c", 3, 1, 1, 0, "p", 0);
$b->insertExpr("f.c", 3, 1, 1, 1, "q", 0);
$b->insertExpr("f.c", 3, 1, 1, 2, "r", 0);
print $a->is_compatible($b) ? 1 : 0;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block::is_compatible extra group in self" '
use lcovutil;
my $a = MCDC_Block->new(10);
$a->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
$a->insertExpr("f.c", 2, 1, 1, 1, "b", 0);
$a->insertExpr("f.c", 3, 1, 1, 0, "p", 0);
$a->insertExpr("f.c", 3, 1, 1, 1, "q", 0);
$a->insertExpr("f.c", 3, 1, 1, 2, "r", 0);
my $b = MCDC_Block->new(10);
$b->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
$b->insertExpr("f.c", 2, 1, 1, 1, "b", 0);
print $a->is_compatible($b) ? 1 : 0;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Same line, same group size, DIFFERENT expression text:  the two files are
# describing different decisions, so merging would attribute counts to the
# wrong expression.  A size-only comparison would call these compatible.
run_test "MCDC_Block::is_compatible differing expression text" '
use lcovutil;
my $a = MCDC_Block->new(10);
$a->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
$a->insertExpr("f.c", 2, 1, 1, 1, "b", 0);
my $b = MCDC_Block->new(10);
$b->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
$b->insertExpr("f.c", 2, 1, 1, 1, "c", 0);
print $a->is_compatible($b) ? 1 : 0;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# A SHARED group of unequal length is incompatible:  merge() walks the two
# lists index-wise, so the longer side has expressions with nothing to merge
# against.  Pure Perl used to index off the end of the shorter list and die
# in expression() on undef.  Both orderings are checked.
run_test "MCDC_Block::is_compatible shared group shorter in argument" '
use lcovutil;
my $a = MCDC_Block->new(10);
$a->insertExpr("f.c", 2, 1, 1, 0, "aa", 0);
$a->insertExpr("f.c", 2, 1, 1, 1, "bb", 0);
my $b = MCDC_Block->new(10);
$b->insertExpr("f.c", 2, 1, 1, 0, "aa", 0);
print $a->is_compatible($b) ? 1 : 0;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block::is_compatible shared group longer in argument" '
use lcovutil;
my $a = MCDC_Block->new(10);
$a->insertExpr("f.c", 2, 1, 1, 0, "aa", 0);
my $b = MCDC_Block->new(10);
$b->insertExpr("f.c", 2, 1, 1, 0, "aa", 0);
$b->insertExpr("f.c", 2, 1, 1, 1, "bb", 0);
print $a->is_compatible($b) ? 1 : 0;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# MCDC_Data::union / ::intersect incompatible-record gate
#
# The XS union/intersect replace the pure-Perl subs wholesale, and they used to
# omit the is_compatible() check those subs perform - so XS silently merged
# MC/DC records that pure Perl rejects with ERROR_INCONSISTENT_DATA.  With the
# error ignored, both the warning text and the surviving (unmerged) counts are
# compared.
# ==============================================================================

run_test "MCDC_Data::union rejects an incompatible record" '
use lcovutil;
lcovutil::parse_ignore_errors("inconsistent");
sub blk {
    my ($line, @e) = @_;
    my $b = MCDC_Block->new($line);
    my $i = 0;
    foreach my $x (@e) {
        $b->insertExpr("f.c", scalar(@e), 1, 1, $i, $x, 0);
        $b->insertExpr("f.c", scalar(@e), 0, 1, $i, $x, 0);
        ++$i;
    }
    return $b;
}
my $x = MCDC_Data->new();
$x->append_mcdc(blk(10, "a", "b"), "f.c");
my $y = MCDC_Data->new();
$y->append_mcdc(blk(10, "p", "q"), "f.c");
my $changed = $x->union($y, "f.c");
# counts unchanged and expressions still mine:  nothing was merged
print "changed=$changed f/h=", join(",", $x->get_found_and_hit()),
      " expr=", $x->value(10)->expr(2, 0)->expression(),
      " cnt=", $x->value(10)->expr(2, 0)->count(1), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::intersect rejects an incompatible record" '
use lcovutil;
lcovutil::parse_ignore_errors("inconsistent");
sub blk {
    my ($line, @e) = @_;
    my $b = MCDC_Block->new($line);
    my $i = 0;
    foreach my $x (@e) {
        $b->insertExpr("f.c", scalar(@e), 1, 1, $i, $x, 0);
        $b->insertExpr("f.c", scalar(@e), 0, 1, $i, $x, 0);
        ++$i;
    }
    return $b;
}
my $x = MCDC_Data->new();
$x->append_mcdc(blk(10, "a", "b"), "f.c");
my $y = MCDC_Data->new();
$y->append_mcdc(blk(10, "p", "q"), "f.c");
my $changed = $x->intersect($y, "f.c");
print "changed=$changed f/h=", join(",", $x->get_found_and_hit()),
      " expr=", $x->value(10)->expr(2, 0)->expression(),
      " cnt=", $x->value(10)->expr(2, 0)->count(1), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# A shared group of unequal length reaches the same gate.  This case used to
# make pure Perl die inside is_compatible (and, with that fixed but the XS gate
# still missing, made XS merge where pure Perl warns).
run_test "MCDC_Data::union rejects a short shared group" '
use lcovutil;
lcovutil::parse_ignore_errors("inconsistent");
my $x = MCDC_Data->new();
my $bx = MCDC_Block->new(10);
$bx->insertExpr("f.c", 2, 1, 1, 0, "aa", 0);
$bx->insertExpr("f.c", 2, 1, 1, 1, "bb", 0);
$x->append_mcdc($bx, "f.c");
my $y = MCDC_Data->new();
my $by = MCDC_Block->new(10);
$by->insertExpr("f.c", 2, 1, 1, 0, "aa", 0);
$y->append_mcdc($by, "f.c");
print "changed=", $x->union($y, "f.c"),
      " f/h=", join(",", $x->get_found_and_hit()),
      " cnt=", $x->value(10)->expr(2, 0)->count(1), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# A merely-extra group IS compatible, so union must merge it in and pick up the
# new group's coverpoints.
run_test "MCDC_Data::union merges a compatible extra group" '
use lcovutil;
my $x = MCDC_Data->new();
my $bx = MCDC_Block->new(10);
$bx->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
$bx->insertExpr("f.c", 2, 1, 1, 1, "b", 0);
$x->append_mcdc($bx, "f.c");
my $y = MCDC_Data->new();
my $by = MCDC_Block->new(10);
$by->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
$by->insertExpr("f.c", 2, 1, 1, 1, "b", 0);
$by->insertExpr("f.c", 3, 1, 1, 0, "p", 0);
$by->insertExpr("f.c", 3, 1, 1, 1, "q", 0);
$by->insertExpr("f.c", 3, 1, 1, 2, "r", 0);
$x->append_mcdc($by, "f.c");
$x->_checkCounts();
print "f/h=", join(",", $x->get_found_and_hit()),
      " groups=", $x->value(10)->num_groups(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# MCDC_Block group storage
#
# Almost every MC/DC line carries exactly ONE group - one decision per line - so
# the XS side keeps that group inline and only allocates a map when a second
# group size turns up.  Pure Perl is a hash either way, so the two agree only if
# the transition is invisible:  a group added before the second one must keep its
# expressions, still accept new ones afterwards, and an MCDC_Expression already
# handed out to Perl must still refer to the same expression once the block has
# grown.  That last one is the case a reference-invalidating implementation would
# pass every other test and then corrupt data on.
# ==============================================================================

run_test "MCDC_Block second group size keeps the first group intact" '
use lcovutil;
my $blk = MCDC_Block->new(10);
$blk->insertExpr("f.c", 3, 0, 5, 0, "a", 0);
$blk->insertExpr("f.c", 3, 1, 7, 1, "b", 0);
# an expression handed to Perl BEFORE the block grows a second group
my $held = $blk->expr(3, 1);
print "one: groups=", $blk->num_groups(),
      " sizes=", join(",", map { defined($blk->expressions($_)) ?
                                 "$_:" . scalar(@{$blk->expressions($_)}) : ()
                              } 1 .. 4), "\n";
$blk->insertExpr("f.c", 2, 0, 9, 0, "x", 0);
$blk->insertExpr("f.c", 2, 1, 0, 1, "y", 0);
print "two: groups=", $blk->num_groups(),
      " sizes=", join(",", map { defined($blk->expressions($_)) ?
                                 "$_:" . scalar(@{$blk->expressions($_)}) : ()
                              } 1 .. 4), "\n";
print "held: ", $held->expression(), " gs=", $held->groupSize(),
      " idx=", $held->index(), " f=", $held->count(0),
      " t=", $held->count(1), "\n";
# the pre-existing group must still accept expressions after the promotion
$blk->insertExpr("f.c", 3, 0, 4, 2, "c", 0);
print "after append: ", join(" ", map { $_->expression() . "=" .
                                        $_->count(0) . "/" . $_->count(1) }
                             @{$blk->expressions(3)}), "\n";
print "totals=", join("/", $blk->totals()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# merge() is the other way a block gains a group:  a block which has one group
# must end up with both, and the copied group must be a COPY - mutating the
# source afterwards must not change the merged result.
run_test "MCDC_Block::merge copies a group into a one-group block" '
use lcovutil;
my $mine = MCDC_Block->new(10);
$mine->insertExpr("f.c", 2, 0, 1, 0, "a", 0);
$mine->insertExpr("f.c", 2, 1, 2, 1, "b", 0);
my $yours = MCDC_Block->new(10);
# the shared group must be the same length as mine -- an unequal shared group is
# the incompatible record the union/intersect gate above rejects
$yours->insertExpr("f.c", 2, 0, 3, 0, "a", 0);
$yours->insertExpr("f.c", 2, 1, 4, 1, "b", 0);
$yours->insertExpr("f.c", 3, 0, 5, 0, "p", 0);
print "changed=", $mine->merge($yours, "f.c"),
      " groups=", $mine->num_groups(), "\n";
# mutate the source group after the merge:  my copy must not follow
$yours->insertExpr("f.c", 3, 0, 100, 1, "p", 0);
print "mine: ", join(" ", map { my $s = $_;
                                $s . "[" .
                                join(",", map { $_->expression() . "=" .
                                                $_->count(0) . "/" .
                                                $_->count(1) }
                                     @{$mine->expressions($s)}) . "]" }
                     sort { $a <=> $b } (2, 3)), "\n";
print "totals=", join("/", $mine->totals()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# remove() without the 'check' flag
#
# Pure Perl dies ("<line> not found") when asked to remove a key it does not
# have:  the caller is asserting the key is present, so an absent key is a caller
# bug and must not be reported as a successful removal (or as "nothing removed").
# The XS side must propagate the C++ exception rather than swallowing it in a bare
# catch(...).  With the check flag an absent key is simply 0.
# ==============================================================================

run_error_test "BranchData::remove dies on an absent line" '
use lcovutil;
my $bd = BranchData->new();
$bd->remove(99);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "MCDC_Data::remove dies on an absent line" '
use lcovutil;
my $md = MCDC_Data->new();
$md->remove(99);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "remove with check flag tolerates an absent line" '
use lcovutil;
my $bd = BranchData->new();
my $md = MCDC_Data->new();
my $mp = MapData->new();
print "bd=", ($bd->remove(99, 1) ? 1 : 0),
      " md=", ($md->remove(99, 1) ? 1 : 0),
      " mp=", ($mp->remove("nosuchkey", 1) ? 1 : 0), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Removing a line that IS present must still subtract its totals and report
# success - i.e. the added absent-key throw did not disturb the normal path.
run_test "MCDC_Data::remove present line adjusts totals" '
use lcovutil;
my $md = MCDC_Data->new();
my $b = MCDC_Block->new(7);
$b->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
$b->insertExpr("f.c", 2, 0, 1, 0, "a", 0);
$md->append_mcdc($b, "f.c");
print "before=", join(",", $md->get_found_and_hit());
my $rc = $md->remove(7);
print " rc=", ($rc ? 1 : 0), " after=", join(",", $md->get_found_and_hit()),
      " value=", (defined($md->value(7)) ? "exists" : "gone"), "\n";
$md->_checkCounts();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# MCDC_Data::append_mcdc
#
# Two requirements, both easy to miss.  The totals update must be incremental:
# adding the whole appended block's totals when merging into a line the container
# already had double-counts every shared expression and drives FOUND/HIT above
# the truth, which then makes _checkCounts die.  And the block must be COPIED, not
# stored by reference, or mutating the caller's block after the append silently
# changes the recorded data.  These tests pin both down for both backends.
# ==============================================================================

run_test "MCDC_Data::append_mcdc twice on one line does not double-count" '
use lcovutil;
sub blk {
    my $b = MCDC_Block->new(10);
    $b->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
    $b->insertExpr("f.c", 2, 0, 1, 0, "a", 0);
    $b->insertExpr("f.c", 2, 1, 1, 1, "b", 0);
    $b->insertExpr("f.c", 2, 0, 1, 1, "b", 0);
    return $b;
}
my $d = MCDC_Data->new();
$d->append_mcdc(blk(), "f.c");
print "first=", join(",", $d->get_found_and_hit());
$d->append_mcdc(blk(), "f.c");
print " second=", join(",", $d->get_found_and_hit()), "\n";
# the cached totals must still match a full walk of the data
$d->_checkCounts();
# ... and the counts themselves must have accumulated
print "count=", $d->value(10)->expr(2, 0)->count(1), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::append_mcdc stores a copy, not an alias" '
use lcovutil;
my $d = MCDC_Data->new();
my $src = MCDC_Block->new(20);
$src->insertExpr("f.c", 2, 1, 1, 0, "p", 0);
$src->insertExpr("f.c", 2, 0, 1, 0, "p", 0);
$d->append_mcdc($src, "f.c");
# mutating the source afterwards must not touch what we recorded
$src->insertExpr("f.c", 2, 1, 99, 0, "p", 0);
print "stored=", $d->value(20)->expr(2, 0)->count(1),
      " f/h=", join(",", $d->get_found_and_hit()), "\n";
$d->_checkCounts();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# MCDC_Expression::set with an undefined count
#
# geninfo passes undef for "no count supplied, only the excluded flag matters".
# Pure Perl fell through to a numeric comparison against undef and emitted an
# "uninitialized value" warning that XS (which tests SvOK first) did not.
# ==============================================================================

run_test "insertExpr undef count on an existing slot is quiet" '
use lcovutil;
use warnings;
my $b = MCDC_Block->new(40);
$b->insertExpr("f.c", 2, 1, 1, 0, "a", 0);
$b->insertExpr("f.c", 2, 1, 1, 1, "b", 0);
# undef count, no excluded flag:  nothing changes, and no warning
$b->insertExpr("f.c", 2, 1, undef, 0, "a", 0);
print "count=", $b->expr(2, 0)->count(1);
# undef count with the excluded flag set:  only excluded changes
$b->insertExpr("f.c", 2, 1, undef, 1, "b", 1);
print " excl=", ($b->expr(2, 1)->is_excluded(1) ? 1 : 0),
      " cnt=", $b->expr(2, 1)->count(1), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# XS argument validation.
#
# Every XS accessor reaches its C++ object through an sv_to_<type>() helper that
# checks the invocant is a reference whose referent is an IV before treating that
# IV as a pointer.  Without those checks a class-method style call
# (Type::method($not_an_object)) would dereference a string or a small integer as
# a C++ object -- a segfault, not an error message.  There is nothing to compare
# against in pure Perl (a blessed arrayref just yields Perl's own "not an ARRAY
# reference" error), so these run under XS only; see run_xs_only_test.
#
# One case per distinct helper, each in both of its two failure modes:
#   - invocant is not a reference at all
#   - invocant is a reference, but its referent is not an IV
# plus the NULL-wrapper checks for MCDC_Block, which are reached with a
# reference to the integer 0.
# ==============================================================================

run_xs_only_test "XS accessors croak on a non-object invocant" '
use lcovutil;
my $str  = "notanIV";
my $zero = 0;
my @cases = (
    [ "MapData not a ref",         sub { MapData::value("x", "k") } ],
    [ "MapData not an IV",         sub { MapData::value(\$str, "k") } ],
    [ "CountData not a ref",       sub { CountData::value("x", 1) } ],
    [ "CountData not an IV",       sub { CountData::value(\$str, 1) } ],
    [ "BranchElement not a ref",   sub { BranchElement::count("x") } ],
    [ "BranchElement not an IV",   sub { BranchElement::count(\$str) } ],
    [ "BranchBlock not a ref",     sub { BranchBlock::idx("x") } ],
    [ "BranchBlock not an IV",     sub { BranchBlock::idx(\$str) } ],
    [ "BranchLocation not a ref",  sub { BranchLocation::line("x") } ],
    [ "BranchLocation not an IV",  sub { BranchLocation::line(\$str) } ],
    [ "BranchData not a ref",      sub { BranchData::found("x") } ],
    [ "BranchData not an IV",      sub { BranchData::found(\$str) } ],
    [ "MCDC_Block not a ref",      sub { MCDC_Block::line("x") } ],
    [ "MCDC_Block not an IV",      sub { MCDC_Block::line(\$str) } ],
    [ "MCDC_Data not a ref",       sub { MCDC_Data::found("x") } ],
    [ "MCDC_Data not an IV",       sub { MCDC_Data::found(\$str) } ],
    [ "MCDC_Expression not a ref", sub { MCDC_Expression::count("x", 0) } ],
    [ "MCDC_Expression not an IV", sub { MCDC_Expression::count(\$str, 0) } ],
    # groups() validates self itself (its own messages) before sv_to_mcdcblock
    [ "groups not a ref",          sub { MCDC_Block::groups("x") } ],
    [ "groups not an IV",          sub { MCDC_Block::groups(\$str) } ],
    # a ref to 0 passes both ref/IV checks and lands on the NULL-wrapper checks
    [ "groups NULL wrapper",       sub { MCDC_Block::groups(\$zero) } ],
    [ "insertExpr NULL wrapper",
      sub { MCDC_Block::insertExpr(\$zero, "f.c", 2, 0, 1, 0, "a") } ],
);
my $failed = 0;
for my $c (@cases) {
    my ($label, $code) = @$c;
    if (eval { $code->(); 1 }) {
        print "NOT REJECTED: $label\n";
        ++$failed;
    }
}
print $failed ? "FAILED $failed\n" : "all rejected\n";
exit($failed ? 1 : 0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }


if [ $status -eq 0 ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'xs_6' $LOCAL_COVERAGE
fi

exit $status
