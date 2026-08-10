#!/usr/bin/env bash
# Verify that the pure-Perl and C++ XS implementations of the coverage data
# classes support identical interfaces and produce identical results.
#
# xs5 of the former monolithic 'xs_test.sh' (see setup_common.sh).
# Covers: additional BranchBlock, BranchLocation, BranchData::remove,
# MCDC_Block and MCDC_Expression coverage; the new MCDC XS paths.
#
# Run with: make check, or tests/bin/runtests.py lcov/xs_test/xs5.sh

set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf xs5.d
    exit 0
fi

WORKDIR=xs5.d
source ./setup_common.sh

status=0

# ==============================================================================
# BranchBlock -- additional coverage
# ==============================================================================

run_test "BranchBlock::idx after insertBlock assigns index" '
use lcovutil;
my $loc = BranchLocation->new(1);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 1));
$loc->insertBlock($bb);
print $bb->idx();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchBlock::appendElement EXCEPT and FALLTHROUGH signature chars" '
use lcovutil;
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 1));
$bb->appendElement(BranchElement->new("2", 0, undef, BranchElement::EXCEPT));
$bb->appendElement(BranchElement->new("3", 2, undef, BranchElement::FALLTHROUGH));
print $bb->signature();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchBlock::merge changed=0 (value+dash)" '
use lcovutil;
my $a = BranchBlock->new();
$a->appendElement(BranchElement->new("1", 3));
my $b = BranchBlock->new();
$b->appendElement(BranchElement->new("1", "-"));
my $changed = $a->merge($b, "f.c", 1);
print $changed, " ", $a->getElement(0)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchBlock::merge dash+value (changed=1)" '
use lcovutil;
my $a = BranchBlock->new();
$a->appendElement(BranchElement->new("1", "-"));
my $b = BranchBlock->new();
$b->appendElement(BranchElement->new("1", 5));
my $changed = $a->merge($b, "f.c", 1);
print $changed, " ", $a->getElement(0)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchBlock::merge excluded-mismatch warning (ignorable)" '
use lcovutil;
lcovutil::parse_ignore_errors("mismatch");
my $a = BranchBlock->new();
$a->appendElement(BranchElement->new("1", 3));
my $b = BranchBlock->new();
$b->appendElement(BranchElement->new("1", 2, undef, undef, 1));
$a->merge($b, "f.c", 5);
print $a->getElement(0)->is_excluded();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# The mismatch message is prefixed with the location, but only when there is one
# to report.  An undef filename (no location known) and an empty one (nothing
# useful to print) must both suppress the prefix rather than emit '"":5:'.
run_test "BranchBlock::merge mismatch location prefix (undef/empty/named)" '
use lcovutil;
lcovutil::parse_ignore_errors("mismatch");
$SIG{__WARN__} = sub { my $m = shift; $m =~ s/\s+/ /g; print "$m\n" };
foreach my $fn (undef, "", "f.c") {
    my $a = BranchBlock->new();
    $a->appendElement(BranchElement->new("1", 3, undef, undef, 1));
    my $b = BranchBlock->new();
    $b->appendElement(BranchElement->new("1", 2));
    $a->merge($b, $fn, 5);
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# merge() pairs elements up positionally, so it is only meaningful between two
# blocks describing the same decision:  a differing element count or signature
# means the caller matched up blocks that are not the same block, which is a
# hard error rather than something to merge as far as it goes.
run_error_test "BranchBlock::merge rejects a block with a different element count" '
use lcovutil;
my $a = BranchBlock->new();
$a->appendElement(BranchElement->new(0, 1));
$a->appendElement(BranchElement->new(1, 1));
my $b = BranchBlock->new();
$b->appendElement(BranchElement->new(0, 1));
$a->merge($b, "f.c", 1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "BranchBlock::merge rejects a block with a different signature" '
use lcovutil;
my $a = BranchBlock->new();
$a->appendElement(BranchElement->new(0, 1, undef, BranchElement::VANILLA));
my $b = BranchBlock->new();
$b->appendElement(BranchElement->new(0, 1, undef, BranchElement::EXCEPT));
$a->merge($b, "f.c", 1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# merge() answers "did anything change", not "how many things changed".  With
# more than one element changing in the same block, a running sum would report
# 2 (or 3) where the boolean contract - and pure Perl - report 1.
run_test "BranchBlock::merge returns a boolean, not a change count" '
use lcovutil;
foreach my $n (1, 2, 3) {
    my $a = BranchBlock->new();
    my $b = BranchBlock->new();
    foreach my $i (1 .. $n) {
        $a->appendElement(BranchElement->new("$i", 0));    # unhit ...
        $b->appendElement(BranchElement->new("$i", $i));   # ... becomes hit
    }
    print "n=$n changed=", $a->merge($b, "f.c", 1), "\n";
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Same boolean contract one level up, where BranchLocation::merge both merges an
# existing block (two elements, so two changes inside the one merge) and copies a
# block whose signature this location does not have.  Two distinct signatures per
# location, since two blocks of the SAME signature are by definition one block.
run_test "BranchLocation::merge returns a boolean, not a change count" '
use lcovutil;
sub mkblock {
    my ($type, @counts) = @_;
    my $blk = BranchBlock->new();
    my $id  = 0;
    $blk->appendElement(BranchElement->new($id++, $_, undef, $type))
        foreach (@counts);
    return $blk;
}
my $mine = BranchLocation->new(7);
$mine->insertBlock(mkblock(BranchElement::VANILLA, 0, 0));
my $yours = BranchLocation->new(7);
$yours->insertBlock(mkblock(BranchElement::VANILLA, 5, 6));   # both elements change
$yours->insertBlock(mkblock(BranchElement::EXCEPT, 7));       # signature I lack
print "changed=", $mine->merge($yours, "f.c"), " numBlocks=", $mine->numBlocks();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Elements are paired positionally within two blocks of identical signature, and
# the .info reader renumbers branch ids per block, so the ids at a given position
# can legitimately differ between two inputs.  Merging must still sum the counts;
# rejecting the pair would silently drop the incoming data.
run_test "BranchElement::merge sums counts when the ids differ" '
use lcovutil;
my $a = BranchBlock->new();
$a->appendElement(BranchElement->new("1", 4));
$a->appendElement(BranchElement->new("2", 0));
my $b = BranchBlock->new();
$b->appendElement(BranchElement->new("3", 6));   # different id, same type
$b->appendElement(BranchElement->new("4", 9));
print "sigs-equal=", ($a->signature() eq $b->signature() ? 1 : 0), "\n";
print "changed=", $a->merge($b, "f.c", 1), "\n";
print "counts=", $a->getElement(0)->count(), ",", $a->getElement(1)->count(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# A block ID is a subscript into the location block list, so it has a lower bound
# as well as an upper one.  An upper-bound-only test admits every negative id
# (even on an empty location) and then indexes from the END of the list, quietly
# handing back the wrong block.
run_test "BranchLocation::hasBlock rejects negative and out-of-range ids" '
use lcovutil;
my $loc = BranchLocation->new(5);
foreach my $n (1, 2) {
    my $blk = BranchBlock->new();
    $blk->appendElement(BranchElement->new("$n", $n * 10));
    $loc->insertBlock($blk);
}
my $empty = BranchLocation->new(9);
foreach my $id (-2, -1, 0, 1, 2) {
    printf "id=%2d populated=%d empty=%d\n", $id,
           ($loc->hasBlock($id) ? 1 : 0), ($empty->hasBlock($id) ? 1 : 0);
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# removeBlock identifies the block to drop by its idx, which is only meaningful
# within the location that assigned it.  Handing over a block belonging to some
# other location must be refused rather than silently removing whichever block
# happens to sit at that index here.
run_error_test "BranchLocation::removeBlock rejects a block from another location" '
use lcovutil;
my $bd  = BranchData->new();
sub mk {
    my ($type) = @_;
    my $blk = BranchBlock->new();
    $blk->appendElement(BranchElement->new(0, 1, undef, $type));
    return $blk;
}
my $loc = BranchLocation->new(3);
$loc->insertBlock(mk(BranchElement::VANILLA));
my $other = BranchLocation->new(4);
$other->insertBlock(mk(BranchElement::VANILLA));
my $foreign = mk(BranchElement::EXCEPT);
$other->insertBlock($foreign);      # gets idx 1, out of range in $loc
$loc->removeBlock($foreign, $bd);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "BranchLocation::getBlock negative id dies" '
use lcovutil;
my $loc = BranchLocation->new(5);
my $blk = BranchBlock->new();
$blk->appendElement(BranchElement->new("1", 3));
$loc->insertBlock($blk);
# -1 must NOT be accepted as "the last block"
$loc->getBlock(-1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# A block with no elements has an empty signature, so it would be invisible to
# codes()/getList() while still holding an id and being counted by numBlocks():
# the block list and the code map would disagree.  insertBlock must reject it.
run_error_test "BranchLocation::insertBlock rejects an element-less block" '
use lcovutil;
my $loc = BranchLocation->new(5);
$loc->insertBlock(BranchBlock->new());
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# insertBlock assigns the block its position and must publish that id back onto
# the caller-supplied block unconditionally.  A block whose idx is already
# non-zero is being inserted at a new position, so skipping the publish for it
# would leave the caller's block reporting its old position.
run_test "BranchLocation::insertBlock assigns idx over a pre-set one" '
use lcovutil;
my $bd  = BranchData->new();
my $loc = BranchLocation->new(5);
sub mk {
    my ($type) = @_;
    my $blk = BranchBlock->new();
    $blk->appendElement(BranchElement->new(0, 1, undef, $type));
    return $blk;
}
my $b1 = mk(BranchElement::VANILLA);
my $b2 = mk(BranchElement::EXCEPT);
$b2->setIdx(9);          # stale index from wherever this block came from
$loc->insertBlock($b1);
$loc->insertBlock($b2);
print "idx=", $b1->idx(), ",", $b2->idx(), " numBlocks=", $loc->numBlocks(),
      " codes=", join(",", sort $loc->codes()), "\n";
$loc->removeBlock($loc->getBlock(0), $bd);
print "after remove: numBlocks=", $loc->numBlocks(),
      " codes=", join(",", sort $loc->codes()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "BranchBlock::getElement out-of-bounds croak" '
use lcovutil;
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 1));
$bb->getElement(5);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchBlock Storable freeze/thaw (explicit)" '
use lcovutil;
use Storable qw(freeze thaw);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 8));
$bb->appendElement(BranchElement->new("2", 0));
my $cc = thaw(freeze($bb));
print ref($cc), " ", $cc->getElement(0)->count(), " ", $cc->getElement(1)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# BranchLocation -- additional coverage
# ==============================================================================

run_error_test "BranchLocation::getBlock out-of-bounds croak" '
use lcovutil;
my $loc = BranchLocation->new(10);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 1));
$loc->insertBlock($bb);
$loc->getBlock(5);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "BranchLocation::getList not-found croak" '
use lcovutil;
my $loc = BranchLocation->new(10);
$loc->getList("nosuchcode");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::removeBlock removes and renumbers" '
use lcovutil;
my $d = BranchData->new();
my $loc = BranchLocation->new(10);
my $bb0 = BranchBlock->new();
$bb0->appendElement(BranchElement->new("1", 1));
my $bb1 = BranchBlock->new();
$bb1->appendElement(BranchElement->new("2", 2));
my $bb2 = BranchBlock->new();
$bb2->appendElement(BranchElement->new("3", 3));
$loc->insertBlock($bb0);
$loc->insertBlock($bb1);
$loc->insertBlock($bb2);
$d->updateCounts();
$loc->removeBlock($bb1, $d);
# Verify: 2 blocks remain, idx 1 removed, idx 2 renumbered to 1
print $loc->numBlocks(), " ", $loc->getBlock(0)->idx(), " ", $loc->getBlock(1)->idx(), " ",
      ($loc->hasBlock(2) ? 1 : 0);  # idx 2 should no longer exist
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "BranchLocation::removeBlock unknown-id croak" '
use lcovutil;
my $d = BranchData->new();
my $loc = BranchLocation->new(10);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 1));
$bb->setIdx(99);
$loc->removeBlock($bb, $d);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation Storable freeze/thaw (explicit)" '
use lcovutil;
use Storable qw(freeze thaw);
my $loc = BranchLocation->new(7);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 4));
$loc->insertBlock($bb);
my $loc2 = thaw(freeze($loc));
print ref($loc2), " ", $loc2->line(), " ", $loc2->numBlocks(), " ",
      $loc2->getBlock(0)->getElement(0)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# BranchData -- remove() coverage (inherited-then-overridden BranchMap API)
# ==============================================================================

run_test "BranchData::remove (line present)" '
use lcovutil;
my $d = BranchData->new();
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 3));
$d->insertBlock($bb, 10);
$d->updateCounts();
my $r = $d->remove(10);
print $r, " ", defined($d->value(10)) ? "exists" : "gone";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchData::remove (line absent, check=true -- returns 0)" '
use lcovutil;
my $d = BranchData->new();
my $r = $d->remove(99, 1);
print $r;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchData::remove (line present, adjusts found/hit)" '
use lcovutil;
my $d = BranchData->new();
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 1));
$bb->appendElement(BranchElement->new("2", 0));
$d->insertBlock($bb, 10);
$d->updateCounts();
my $r = $d->remove(10);
print $r, " f=", $d->found(), " h=", $d->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchData Storable freeze/thaw (explicit)" '
use lcovutil;
use Storable qw(freeze thaw);
my $d = BranchData->new();
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 6));
$d->insertBlock($bb, 10);
$d->updateCounts();
my $d2 = thaw(freeze($d));
print ref($d2), " ", $d2->found(), " ", $d2->hit(), " ",
      $d2->value(10)->getBlock(0)->getElement(0)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# MCDC_Block -- additional coverage
# ==============================================================================

run_test "MCDC_Block::groups() returns hashref" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 1, 3, 0, "a", 0);
my $g = $mb->groups();
print ref($g);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block::expressions() not-found returns undef" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
my $v = $mb->expressions(99);
print defined($v) ? "defined" : "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Unlike expressions(), expr() names a single expression its caller believes in,
# so an unknown group or a bad index is a caller bug and is reported rather than
# answered with undef.  See xs4.sh for the negative-index and no-autovivification
# halves of the contract.
run_error_test "MCDC_Block::expr group-not-found dies" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
$mb->expr(99, 0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "MCDC_Block::expr idx-out-of-range dies" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
$mb->expr(2, 99);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block Storable freeze/thaw (explicit)" '
use lcovutil;
use Storable qw(freeze thaw);
my $mb = MCDC_Block->new(15);
$mb->insertExpr("f.c", 2, 1, 5, 0, "a", 0);
$mb->insertExpr("f.c", 2, 0, 3, 1, "b", 0);
my $mb2 = thaw(freeze($mb));
print ref($mb2), " ", $mb2->line(), " ", $mb2->expr(2, 0)->count(1), " ",
      $mb2->expr(2, 1)->count(0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# MCDC_Expression -- additional coverage
# ==============================================================================

run_test "MCDC_Expression::is_excluded sense=0" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 0, 3, 0, "a", 0);
my $e = $mb->expr(2, 0);
print $e->is_excluded(0), " ";
my $r1 = $e->set_excluded(0);
print $e->is_excluded(0), " r1=$r1";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression::set_excluded sense=0 second call returns 0" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 0, 1, 0, "x", 0);
my $e = $mb->expr(2, 0);
$e->set_excluded(0);
my $r2 = $e->set_excluded(0);
print $r2;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data Storable freeze/thaw (explicit)" '
use lcovutil;
use Storable qw(freeze thaw);
my $d = MCDC_Data->new();
my $mb = $d->new_mcdc(undef, 10);
$mb->insertExpr("f.c", 2, 1, 4, 0, "x", 0);
$mb->insertExpr("f.c", 2, 0, 2, 1, "y", 0);
$d->close_mcdcBlock($mb);
my $d2 = thaw(freeze($d));
print ref($d2), " ", $d2->found(), " ", $d2->hit(), " ",
      $d2->value(10)->expr(2, 0)->count(1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# MCDC new XS paths -- exercised for the first time now that insertExpr/merge/
# set/totals/set-operations are all in C++.
# ==============================================================================

run_test "MCDC_Expression::set direct call (scalar count)" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 0, 0, 0, "x", 0);
my $e = $mb->expr(2, 0);
my $r = $e->set(0, 5, 0);
print $r, " ", $e->count(0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression::set excluded=1 (changed=1)" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 0, 0, 0, "x", 0);
my $e = $mb->expr(2, 0);
my $r = $e->set(1, 0, 1);
print $r, " ", $e->is_excluded(1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression::set count=0 returns 0" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 1, 0, 0, "x", 0);
my $e = $mb->expr(2, 0);
my $r = $e->set(1, 0, 0);
print $r;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block::merge absent-group copied (new group added)" '
use lcovutil;
my $a = MCDC_Block->new(10);
$a->insertExpr("f.c", 2, 1, 1, 0, "x", 0);

my $b = MCDC_Block->new(10);
$b->insertExpr("f.c", 3, 1, 2, 0, "p", 0);
$b->insertExpr("f.c", 3, 0, 3, 1, "q", 0);

my $changed = $a->merge($b, "f.c");
print $changed, " ", $a->num_groups();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block::totals count_excluded=1" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 1, 5, 0, "a", 1);
$mb->insertExpr("f.c", 2, 0, 3, 1, "b", 0);
my ($f_no, $h_no)   = $mb->totals(0);
my ($f_yes, $h_yes) = $mb->totals(1);
print "$f_no $h_no | $f_yes $h_yes";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::_calculate_counts" '
use lcovutil;
my $d = MCDC_Data->new();
my $mb = $d->new_mcdc(undef, 10);
$mb->insertExpr("f.c", 2, 1, 3, 0, "x", 0);
$mb->insertExpr("f.c", 2, 0, 0, 1, "y", 0);
$d->close_mcdcBlock($mb);
$d->_calculate_counts();
print $d->found(), " ", $d->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::union new line copied (not just merged)" '
use lcovutil;
my $a = MCDC_Data->new();
my $mba = $a->new_mcdc(undef, 10);
$mba->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
$a->close_mcdcBlock($mba);

my $b = MCDC_Data->new();
my $mbb = $b->new_mcdc(undef, 20);
$mbb->insertExpr("f.c", 2, 1, 5, 0, "y", 0);
$b->close_mcdcBlock($mbb);

$a->union($b, "f.c");
print defined($a->value(10)) ? "has10" : "no10",
      " ", defined($a->value(20)) ? "has20" : "no20";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# MCDC_Data::union picks between maintaining the cached found/hit incrementally
# and one rescan at the end, on the same 2 * (your lines) > (my lines) threshold
# as BranchData::union (see the matching case in xs3.sh for the cost model).
# The cases below straddle the threshold for each shape of overlap; _checkCounts
# dies if the cached totals disagree with a fresh walk, so it carries the
# assertion, and the printed changed/found/hit must match between backends.
#
# The '+delta' cases rotate the counts so a shared line merges to a different
# value; that is the only way a shared-line merge is not a no-op, and hence the
# only way the incremental arm's found/hit delta is non-zero.
run_test "MCDC_Data::union incremental and rescan count paths agree" '
use lcovutil;
sub mk {
    my ($shift, @lines) = @_;
    my $d = MCDC_Data->new();
    foreach my $line (@lines) {
        my $mb = $d->new_mcdc(undef, $line);
        $mb->insertExpr("f.c", 2, 1, ($line + $shift) % 3, 0, "x", 0);
        $mb->insertExpr("f.c", 2, 0, $shift, 1, "y", 0);
        $d->close_mcdcBlock($mb);
    }
    return $d;
}
my @cases = (
    ["incremental, all new",      0, [1 .. 20], [50, 51]],
    ["incremental, all shared",   0, [1 .. 20], [3, 4]],
    ["incremental, shared+delta", 1, [1 .. 20], [3, 4]],
    ["incremental, mixed",        0, [1 .. 20], [3, 99]],
    ["incremental, mixed+delta",  1, [1 .. 20], [3, 99]],
    ["incremental, other empty",  0, [1 .. 10], []],
    ["rescan, all shared",        0, [1, 2],    [1, 2]],
    ["rescan, shared+delta",      1, [1, 2],    [1, 2]],
    ["rescan, mixed",             0, [1, 2],    [2, 3, 4]],
    ["rescan, self empty",        0, [],        [1, 2, 3]],
);
foreach my $case (@cases) {
    my ($name, $shift, $mine, $yours) = @$case;
    my $md      = mk(0, @$mine);
    my $changed = $md->union(mk($shift, @$yours), "f.c");
    $md->_checkCounts();       # dies unless cached found/hit match a fresh walk
    printf("%-26s changed=%d found=%d hit=%d lines=%d\n",
           $name, $changed, $md->found(), $md->hit(), scalar($md->keylist()));
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block STORABLE_thaw restores groups" '
use lcovutil;
use Storable qw(freeze thaw);
my $mb = MCDC_Block->new(7);
$mb->insertExpr("f.c", 2, 1, 4, 0, "a", 0);
$mb->insertExpr("f.c", 2, 0, 0, 1, "b", 0);
my $mb2 = thaw(freeze($mb));
print ref($mb2), " ", $mb2->line(), " ",
      $mb2->expr(2,0)->count(1), " ",
      $mb2->expr(2,1)->count(0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block insertExpr inconsistent expression warns (ignorable)" '
use lcovutil;
lcovutil::parse_ignore_errors("inconsistent");
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
$mb->insertExpr("f.c", 2, 1, 2, 0, "y", 0);
print $mb->expr(2,0)->expression();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block insertExpr non-contiguous index warns (ignorable)" '
use lcovutil;
lcovutil::parse_ignore_errors("format");
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
$mb->insertExpr("f.c", 2, 1, 5, 2, "z", 0);
print $mb->num_groups();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ------------------------------------------------------------------------------
# MCDC_Block differential expression counts
#
# insertExpr accepts a [$tla, $base, $curr] arrayref in place of a plain count
# (that is how genhtml feeds differential data back into a block).  base and curr
# are independently optional, and totals() must SKIP a differential expression
# whose 'curr' is undef -- it is not present in the current build, so it counts
# as neither found nor hit.  Exercise both half-defined shapes in one block so
# the skip arm and the "use curr" arm both run, and check count()/render_data()
# hand the arrayref back with the undef preserved as undef (not coerced to 0).
# ------------------------------------------------------------------------------
run_test "MCDC_Block differential counts: totals skips undef curr" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 1, ["GBC", 2, undef], 0, "a", 0);
$mb->insertExpr("f.c", 2, 0, ["GNC", undef, 5], 1, "b", 0);
my ($f, $h) = $mb->totals();
print "totals=$f/$h\n";
sub show { my $v = shift;
           return ref($v) eq "ARRAY"
               ? "[" . join(",", map { defined($_) ? $_ : "undef" } @$v) . "]"
               : (defined($v) ? $v : "undef"); }
foreach my $i (0, 1) {
    my $e = $mb->expr(2, $i);
    foreach my $s (0, 1) {
        my @rd = $e->render_data($s);
        print "  expr$i sense$s count=", show($e->count($s)),
              " rd_n=", scalar(@rd),
              " rd=[", join("|", map { show($_) } @rd), "]\n";
    }
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ------------------------------------------------------------------------------
# MCDC_Block groups() cache lifetime
#
# groups() hands back the block's OWN groups container -- the cached hashref
# under XS, the live hash under pure Perl -- so Perl code can reach in and
# rewrite it.  Nothing in lcov does, but because the XS destructor has to walk
# that structure to break the block <-> expression reference cycle (zeroing each
# expression wrapper's parent_sv before dropping the cache), a caller-corrupted
# cache must not be able to turn into a bad dereference during teardown.  Each
# case below replaces part of the returned structure with something of the wrong
# shape and then drops the block; surviving with the same output in both
# backends is the whole assertion.
#
# The final case is the other direction: a mutation that invalidates the cache
# while the block is still alive, so the cache is dropped WITHOUT zeroing
# parent_sv (the block, and hence every wrapper parent, is still valid) and then
# rebuilt on the next groups() call.
# ------------------------------------------------------------------------------
run_test "MCDC_Block groups() cache survives caller corruption" '
use lcovutil;
my @cases = (
    ["value not a ref",      sub { $_[0]->{2} = "notaref"; }],
    ["ref but not an AV",    sub { $_[0]->{2} = { a => 1 }; }],
    ["ref to a scalar",      sub { $_[0]->{2} = \"str"; }],
    ["array elem not a ref", sub { $_[0]->{2}[0] = 5; }],
    ["array elem ref to PV", sub { $_[0]->{2}[0] = \"string"; }],
    ["array elem ref to 0",  sub { my $z = 0; $_[0]->{2}[0] = \$z; }],
    ["array emptied",        sub { @{$_[0]->{2}} = (); }],
    ["key deleted",          sub { delete $_[0]->{2}; }],
);
foreach my $case (@cases) {
    my ($name, $mutate) = @$case;
    {
        my $mb = MCDC_Block->new(10);
        $mb->insertExpr("f.c", 2, 1, 3, 0, "a", 0);
        $mb->insertExpr("f.c", 2, 0, 4, 1, "b", 0);
        $mutate->($mb->groups());
        # $mb leaves scope here -- teardown walks the corrupted structure
    }
    print "survived: $name\n";
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block groups() cache dropped and rebuilt on mutation" '
use lcovutil;
my $mb = MCDC_Block->new(20);
$mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
my $g1 = $mb->groups();
print "before n=", scalar(@{$g1->{2}}), "\n";
$mb->insertExpr("f.c", 2, 1, 2, 1, "y", 0);   # structural change -> cache dropped
my $g2 = $mb->groups();                        # rebuilt
print "after n=", scalar(@{$g2->{2}}),
      " counts=", $g2->{2}[0]->count(1), ",", $g2->{2}[1]->count(1), "\n";
$mb->merge(MCDC_Block->new(20), "f.c");        # merge also invalidates
print "after merge n=", scalar(@{$mb->groups()->{2}}), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }


if [ $status -eq 0 ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'xs_5' $LOCAL_COVERAGE
fi

exit $status
