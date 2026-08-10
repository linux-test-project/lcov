#!/usr/bin/env bash
# Verify that the pure-Perl and C++ XS implementations of the coverage data
# classes support identical interfaces and produce identical results.
#
# xs3 of the former monolithic 'xs_test.sh' (see setup_common.sh).
# Covers: BranchLocation; BranchData (inherits BranchMap); MCDC_Expression.
#
# Run with: make check, or tests/bin/runtests.py lcov/xs_test/xs3.sh

set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf xs3.d
    exit 0
fi

WORKDIR=xs3.d
source ./setup_common.sh

status=0

# ==============================================================================
# BranchLocation tests
# ==============================================================================

run_test "BranchLocation::new + line" '
use lcovutil;
my $loc = BranchLocation->new(42);
print ref($loc), " ", $loc->line(), " ", $loc->numBlocks();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::insertBlock + hasBlock + numBlocks" '
use lcovutil;
my $loc = BranchLocation->new(10);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 3));
$loc->insertBlock($bb);
print $loc->numBlocks(), " ", ($loc->hasBlock(0) ? 1 : 0), " ",
      ($loc->hasBlock(1) ? 1 : 0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::getBlock + idx assignment" '
use lcovutil;
my $loc = BranchLocation->new(10);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 5));
$loc->insertBlock($bb);
my $blk = $loc->getBlock(0);
print ref($blk), " ", $blk->idx();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::containsCode + getList" '
use lcovutil;
my $loc = BranchLocation->new(10);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 5));
$loc->insertBlock($bb);
my $sig = $bb->signature();
print($loc->containsCode($sig) ? 1 : 0), " ",
      ($loc->containsCode("zzz") ? 1 : 0),
      " ", scalar(@{$loc->getList($sig)});
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Several blocks on one line CAN share a signature -- gcc emits two 2-way
# branches on one line as two blocks whose signature is "bb" each -- and that is
# the case which distinguishes a code list from a block list:  codes() must
# report the signature once however many blocks carry it, scalar(codes()) must
# agree with that count, and getList() must name every one of them in ascending
# id order.  Removing one of the duplicates must leave the remaining ids
# renumbered but still ascending, and dropping the LAST block of a signature is
# what makes that signature disappear from codes() altogether.
run_test "BranchLocation duplicate signatures: getList, codes, numCodes" '
use lcovutil;
my $branches = BranchData->new();
# two blocks of signature "bb" (2 elements), one of "b" (1 element)
for my $n (2, 1, 2) {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new($_, $_ + 1)) for 1 .. $n;
    $branches->insertBlock($bb, 11);
}
$branches->updateCounts();
my $loc = $branches->value(11);
sub report {
    my ($tag) = @_;
    print "$tag numBlocks=", $loc->numBlocks(),
          " numCodes=", scalar($loc->codes()),
          " codes=", join(",", $loc->codes(1)), "\n";
    for my $c ($loc->codes(1)) {
        print "  $c -> ",
              join(",", map { $_->idx() } @{$loc->getList($c)}), "\n";
    }
}
report("initial");
# drop the first of the two "bb" blocks:  the second must renumber down to 1
$loc->removeBlock($loc->getBlock(0), $branches);
report("after removing one duplicate");
# and now the last one, which is what removes "bb" from the code list
my @bb = @{$loc->getList("bb")};
$loc->removeBlock($bb[0], $branches);
report("after removing the last duplicate");
print "containsCode(bb)=", ($loc->containsCode("bb") ? 1 : 0),
      " containsCode(b)=", ($loc->containsCode("b") ? 1 : 0), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::codes unsorted" '
use lcovutil;
my $loc = BranchLocation->new(1);
for my $n (1..3) {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new($n, $n));
    $loc->insertBlock($bb);
}
my @c = sort $loc->codes(0);
print join(",", @c);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::codes sorted" '
use lcovutil;
my $loc = BranchLocation->new(1);
# create blocks with signatures of different lengths: "bbb", "bb", "b"
for my $n (3, 2, 1) {
    my $bb = BranchBlock->new();
    for my $i (1..$n) {
        $bb->appendElement(BranchElement->new($i, $i));
    }
    $loc->insertBlock($bb);
}
my @c = $loc->codes(1);
print join(",", @c);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::blocks unsorted" '
use lcovutil;
my $loc = BranchLocation->new(1);
for my $n (1..3) {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new($n, $n));
    $loc->insertBlock($bb);
}
my @blks = $loc->blocks();
print scalar(@blks), " ", join(" ", map { $_->idx() } @blks);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::blocks sorted" '
use lcovutil;
my $loc = BranchLocation->new(1);
# block 0: sig "bbb", block 1: sig "bb", block 2: sig "b"
for my $n (3, 2, 1) {
    my $bb = BranchBlock->new();
    for my $i (1..$n) {
        $bb->appendElement(BranchElement->new($i, $i));
    }
    $loc->insertBlock($bb);
}
my @blks = $loc->blocks(1);
print join(",", map { length($_->signature()) } @blks);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# blocks(1) sorts by signature LENGTH first, then by signature CONTENT, then by
# idx.  The "blocks sorted" case above only varies the length, so it never gets
# past the first comparison.  Here every signature is the same length, which
# forces the content compare, and two blocks share a signature outright, which
# forces the idx tiebreak.  Insertion order is deliberately not sorted order.
run_test "BranchLocation::blocks sorted equal-length signatures (tiebreak)" '
use lcovutil;
my $loc = BranchLocation->new(1);
my @sigs = (
    [BranchElement::VANILLA, BranchElement::FALLTHROUGH],   # "bf"
    [BranchElement::VANILLA, BranchElement::EXCEPT],        # "be"
    [BranchElement::VANILLA, BranchElement::FALLTHROUGH],   # "bf" -- duplicate
    [BranchElement::EXCEPT,  BranchElement::VANILLA],       # "eb"
);
my $n = 0;
foreach my $types (@sigs) {
    my $bb = BranchBlock->new();
    my $i = 0;
    foreach my $t (@$types) {
        $bb->appendElement(BranchElement->new($n * 10 + $i, 1, undef, $t));
        ++$i;
    }
    $loc->insertBlock($bb);
    ++$n;
}
print "unsorted: ", join(" ", map { $_->signature() . "/" . $_->idx() }
                                  $loc->blocks()), "\n";
print "sorted:   ", join(" ", map { $_->signature() . "/" . $_->idx() }
                                  $loc->blocks(1)), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# BranchLocation::totals takes an optional count_excluded flag; with it false an
# excluded element contributes to neither found nor hit.  Call it both ways
# directly, AND via BranchData::updateCounts, which is the caller that always
# passes false: updateCounts reaches the C++ totals() from inside C++, without
# the XSUB argument decoding in between, so the two routes can disagree about
# what "no flag given" means.
run_test "BranchLocation::totals skips excluded unless count_excluded" '
use lcovutil;
sub mkblock {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new("1", 3));                   # found + hit
    $bb->appendElement(BranchElement->new("2", 0));                   # found only
    $bb->appendElement(BranchElement->new("3", 9, undef, undef, 1));  # excluded
    return $bb;
}
my $loc = BranchLocation->new(5);
$loc->insertBlock(mkblock());
my ($f0, $h0) = $loc->totals();
my ($f1, $h1) = $loc->totals(1);
print "direct default=$f0/$h0 with_excluded=$f1/$h1\n";

my $d = BranchData->new();
$d->insertBlock(mkblock(), 5);
$d->updateCounts();
print "updateCounts found=", $d->found(), " hit=", $d->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::totals" '
use lcovutil;
my $loc = BranchLocation->new(5);
my $bb1 = BranchBlock->new();
$bb1->appendElement(BranchElement->new("1", 3));
$bb1->appendElement(BranchElement->new("2", 0));
$loc->insertBlock($bb1);
my $bb2 = BranchBlock->new();
$bb2->appendElement(BranchElement->new("1", 1));
$loc->insertBlock($bb2);
my ($f, $h) = $loc->totals();
print "$f $h";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ------------------------------------------------------------------------------
# hasHitElement is the short-circuiting form of "0 != (totals($ce))[1]": it stops
# at the first hit element instead of counting every element on the line.
# _checkConsistency asks exactly that question once per branch line, so the two
# must never disagree -- hence the table below drives both over the same shapes
# and prints the comparison.  What the shapes are for:
#   - hit/unhit ORDER decides whether the short circuit fires on the first
#     element or the last, so both orders appear.
#   - an EXCLUDED hit is the case where the count_excluded flag flips the answer:
#     with the flag false that hit is invisible, so hasHitElement must say 0
#     even though a hit element exists.
#   - a DASH ('-') count means "branch present, never evaluated": found but not
#     hit, so it must not satisfy the predicate.
#   - two blocks, not one, because the walk is nested (blocks then elements) and
#     an early return has to escape both loops.
run_test "BranchLocation::hasHitElement agrees with totals hit count" '
use lcovutil;
my @shapes = (
    ["empty location",       []],
    ["single unhit",         [["1", 0, 0]]],
    ["single hit",           [["1", 3, 0]]],
    ["unhit then hit",       [["1", 0, 0], ["2", 7, 0]]],
    ["hit then unhit",       [["1", 7, 0], ["2", 0, 0]]],
    ["only excluded is hit", [["1", 0, 0], ["2", 9, 1]]],
    ["excluded hit + plain", [["1", 5, 1], ["2", 0, 0]]],
    ["all excluded, hit",    [["1", 4, 1]]],
    ["dash only",            [["1", "-", 0]]],
    ["dash then hit",        [["1", "-", 0], ["2", 2, 0]]],
);
foreach my $shape (@shapes) {
    my ($name, $elements) = @$shape;
    foreach my $nblocks (1, 2) {
        my $loc = BranchLocation->new(5);
        foreach my $b (1 .. $nblocks) {
            next unless @$elements;    # insertBlock rejects an empty block
            my $bb = BranchBlock->new();
            foreach my $e (@$elements) {
                $bb->appendElement(
                    BranchElement->new($e->[0], $e->[1], undef, undef, $e->[2]));
            }
            $loc->insertBlock($bb);
        }
        foreach my $countExcluded (0, 1) {
            my ($f, $h) = $loc->totals($countExcluded);
            my $predicate = $loc->hasHitElement($countExcluded) ? 1 : 0;
            printf("%-22s blocks=%d excl=%d totals=%d/%d hasHit=%d %s\n",
                   $name, $nblocks, $countExcluded, $f, $h, $predicate,
                   $predicate == (0 != $h ? 1 : 0) ? "agree" : "DISAGREE");
        }
    }
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Both methods take the flag as an optional trailing argument, so the XSUBs
# decode it themselves rather than getting Perl'"'"'s own truthiness.  "00" and
# "0.0" are TRUE strings in Perl even though they look numerically zero, and an
# absent argument is not the same as an explicit undef -- an XSUB that used
# SvIV() or checked only items>=2 would get these wrong.  The location holds one
# plain hit and one excluded hit, so the flag visibly changes both answers.
run_test "BranchLocation::totals/hasHitElement count_excluded argument forms" '
use lcovutil;
my $loc = BranchLocation->new(5);
my $bb  = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 3));                     # plain hit
$bb->appendElement(BranchElement->new("2", 8, undef, undef, 1));    # excluded hit
$loc->insertBlock($bb);
print "no-arg      totals=", join("/", $loc->totals()),
      " hasHit=", ($loc->hasHitElement() ? 1 : 0), "\n";
foreach my $arg (undef, 0, "", "0", "00", 1, "x", "0.0") {
    printf("arg=%-7s totals=%-5s hasHit=%d\n",
           defined($arg) ? "\"$arg\"" : "undef",
           join("/", $loc->totals($arg)),
           $loc->hasHitElement($arg) ? 1 : 0);
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# totals() is a list-returning XSUB now (PPCODE), where pure Perl is
# "return ($found, $hit)".  A PPCODE body that just pushes both values would
# leave the LAST one on the stack in scalar context -- so scalar($loc->totals())
# would silently answer the hit count under XS and the same under pure Perl only
# by coincidence.  Pin down scalar context and list-slice indexing explicitly.
run_test "BranchLocation::totals in scalar and slice context" '
use lcovutil;
my $loc = BranchLocation->new(5);
my $bb  = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 3));
$bb->appendElement(BranchElement->new("2", 0));
$loc->insertBlock($bb);
my @list   = $loc->totals();
my $scalar = $loc->totals();
print "list=(", join(",", @list), ") scalar=$scalar",
      " found_slice=", ($loc->totals())[0],
      " hit_slice=", ($loc->totals(1))[1], "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# getList() on a code (block signature) that is not present is fatal in both
# backends (pure-Perl die "$code not found"; XS throws out_of_range converted
# to a Perl die).
run_error_test "BranchLocation::getList missing code dies" '
use lcovutil;
my $loc = BranchLocation->new(1);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new(0, 1));
$loc->insertBlock($bb);
$loc->getList("zzz");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::merge" '
use lcovutil;
my $a = BranchLocation->new(10);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 3));
$a->insertBlock($bb);

my $b = BranchLocation->new(10);
my $bb2 = BranchBlock->new();
$bb2->appendElement(BranchElement->new("1", 4));
$b->insertBlock($bb2);

$a->merge($b, "f.c");
print $a->numBlocks(), " ", $a->getBlock(0)->getElement(0)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation Storable dclone" '
use lcovutil;
use Storable qw(dclone);
my $loc = BranchLocation->new(7);
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 9));
$loc->insertBlock($bb);
my $loc2 = dclone($loc);
$loc2->getBlock(0)->getElement(0)->merge(BranchElement->new("1", 1), "f.c", 7);
print $loc->getBlock(0)->getElement(0)->count(), " ",
      $loc2->getBlock(0)->getElement(0)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# genhtml differential mode builds a "<<<N" line key for lines deleted in
# "current" (bin/genhtml ~2935) and constructs BranchLocation->new($deleteKey).
# The non-numeric key must round-trip verbatim through line() without an
# "argument is not numeric" warning (pure-Perl stores $line as-is).
run_test "BranchLocation::new + line non-numeric delete key" '
use lcovutil;
my $loc = BranchLocation->new("<<<123");
print ref($loc), " ", $loc->line();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation non-numeric key Storable dclone" '
use lcovutil;
use Storable qw(dclone);
my $loc = BranchLocation->new("<<<456");
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 9));
$loc->insertBlock($bb);
my $loc2 = dclone($loc);
print $loc->line(), " ", $loc2->line(), " ", $loc2->numBlocks();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# removeBlock has to do two things at once, and only the first is exercised by
# removing the last block: drop the block, and DECREMENT the idx of every block
# after it, so that a block's idx is still its position and getList() still
# reports the right ids.  Removing a MIDDLE block out of more than two, with
# every block carrying a distinct signature, is the case that covers both -- and
# every surviving block must still be reachable by its new id afterwards.
run_test "BranchLocation::removeBlock middle block renumbers idx" '
use lcovutil;
my $branches = BranchData->new();
# block i gets i+1 elements, so the four blocks have four distinct signatures
for my $i (0 .. 3) {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new($_, ($_ % 2))) for 0 .. $i;
    $branches->insertBlock($bb, 42);
}
$branches->updateCounts();
my $loc = $branches->value(42);
print "before blocks=", $loc->numBlocks(),
      " idx=", join(",", map { $_->idx() } $loc->blocks()),
      " codes=", join(",", sort $loc->codes()), "\n";
my ($f, $h) = $branches->get_found_and_hit();
print "before f/h=$f/$h\n";
my @blks = $loc->blocks();
$loc->removeBlock($blks[1], $branches);
print "after blocks=", $loc->numBlocks(),
      " idx=", join(",", map { $_->idx() } $loc->blocks()),
      " codes=", join(",", sort $loc->codes()), "\n";
for my $c (sort $loc->codes()) {
    print "  siglen ", length($c), " -> idx ",
          join(",", map { $_->idx() } @{$loc->getList($c)}), "\n";
}
my ($f2, $h2) = $branches->get_found_and_hit();
print "after f/h=$f2/$h2\n";
for my $i (0 .. $loc->numBlocks() - 1) {
    my $b = $loc->getBlock($i);
    print "  getBlock($i) idx=", $b->idx(),
          " nelem=", scalar(@{$b->elements()}), "\n";
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::removeBlock first block, then last" '
use lcovutil;
my $branches = BranchData->new();
for my $i (0 .. 2) {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new($_, 1)) for 0 .. $i;
    $branches->insertBlock($bb, 7);
}
$branches->updateCounts();
my $loc = $branches->value(7);
my @blks = $loc->blocks();
$loc->removeBlock($blks[0], $branches);        # first: renumbers everything
print "after-first blocks=", $loc->numBlocks(),
      " idx=", join(",", map { $_->idx() } $loc->blocks()), "\n";
@blks = $loc->blocks();
$loc->removeBlock($blks[-1], $branches);       # last: renumbers nothing
print "after-last blocks=", $loc->numBlocks(),
      " idx=", join(",", map { $_->idx() } $loc->blocks()),
      " codes=", join(",", sort $loc->codes()), "\n";
my ($f, $h) = $branches->get_found_and_hit();
print "f/h=$f/$h\n";
# removing the only remaining block empties the location
@blks = $loc->blocks();
$loc->removeBlock($blks[0], $branches);
print "empty blocks=", $loc->numBlocks(),
      " codes=[", join(",", $loc->codes()), "]\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchLocation::removeBlock then insertBlock reuses freed idx" '
use lcovutil;
my $branches = BranchData->new();
for my $i (0 .. 2) {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new($_, 1)) for 0 .. $i;
    $branches->insertBlock($bb, 3);
}
$branches->updateCounts();
my $loc = $branches->value(3);
my @blks = $loc->blocks();
$loc->removeBlock($blks[1], $branches);
# insertBlock auto-assigns max(idx)+1, so after a removal the next block must
# land at the compacted end rather than colliding with a renumbered block
my $extra = BranchBlock->new();
$extra->appendElement(BranchElement->new($_, 1)) for 0 .. 6;
$loc->insertBlock($extra);
print "blocks=", $loc->numBlocks(),
      " idx=", join(",", map { $_->idx() } $loc->blocks()), "\n";
print "reachable=", join(",",
    map { $loc->getBlock($_)->idx() } 0 .. $loc->numBlocks() - 1), "\n";
print "codes=", join(",", map { length($_) } sort $loc->codes()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Iterate-and-remove, the shape ExceptionBranchFilter::removeBranches uses.  A
# BranchBlock handed to Perl by blocks()/getBlock() is, under XS, a BORROWED
# pointer into the location container -- removeBlock mutates that container, so
# any handle taken before the removal is stale afterwards.  The filter therefore
# walks by position and re-fetches each block, and must not advance the position
# when it removed the block at it (the tail shifted down).  Getting this wrong is
# not a crash-only failure: it can also silently report nElems=0 for blocks that
# should have survived -- i.e. drop live branch coverage.  Pure Perl holds real
# block references and is immune, so it is the oracle.
run_test "iterate-and-remove blocks by position (removeBranches shape)" '
use lcovutil;
my $branches = BranchData->new();
# 5 blocks on one line; blocks 0 and 2 are all-exception, so they get removed,
# which forces two renumberings in the middle of the walk.
for my $i (0 .. 4) {
    my $type = ($i == 0 || $i == 2) ? 1 : 0;
    my $bb   = BranchBlock->new();
    $bb->appendElement(BranchElement->new($_, 1, undef, $type, 0)) for 0 .. 1;
    $branches->insertBlock($bb, 10);
}
$branches->updateCounts();
my $loc = $branches->value(10);
my ($f0, $h0) = $branches->get_found_and_hit();
print "start blocks=", $loc->numBlocks(), " f/h=$f0/$h0\n";
my $pos = 0;
while ($pos < $loc->numBlocks()) {
    my $blk    = $loc->getBlock($pos);
    my $elems  = $blk->elements();
    my $nElems = 0;
    my $count  = 0;
    foreach my $br (@$elems) {
        next if $br->is_excluded();
        ++$nElems;
        if ($br->is_exception()) {
            next unless $br->set_excluded();
            ++$count;
        }
    }
    print "  visit pos=$pos idx=", $blk->idx(),
          " nElems=$nElems count=$count\n";
    my $removed = 0;
    if (0 == $nElems - $count) {
        $loc->removeBlock($blk, $branches);
        $removed = 1;
    }
    ++$pos unless $removed;
}
my ($f, $h) = $branches->get_found_and_hit();
print "end blocks=", $loc->numBlocks(), " f/h=$f/$h\n";
for my $i (0 .. $loc->numBlocks() - 1) {
    my $b = $loc->getBlock($i);
    print "  survivor pos=$i idx=", $b->idx(),
          " nelem=", scalar(@{$b->elements()}), "\n";
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# blocks()/codes() are list-returning, and pure Perl implements them as
# 'return @list' -- so SCALAR context yields the COUNT.  The XS side pushes a
# list onto the stack, which in scalar context would otherwise leave the LAST
# item there instead (a block object, or a signature string like "b"), so
# anything doing scalar()/numeric comparison would silently disagree between
# the two backends.  Every current caller is list context; this pins the
# scalar behaviour so it stays equivalent.
#
# Only the UNSORTED form is asserted.  Pure Perl implements the sorted form as
# 'return sort {...} @list', and perl explicitly documents sort's return value
# in scalar context as undefined (it yields empty here); XS answers the count.
# Matching documented-undefined behaviour is not worth a wrapper on a hot path,
# so scalar($loc->blocks(1)) is deliberately left unspecified -- pass a sort
# flag only in list context.
run_test "BranchLocation::blocks/codes scalar context is the count" '
use lcovutil;
my $branches = BranchData->new();
for my $i (0 .. 2) {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new($_, 1)) for 0 .. $i;
    $branches->insertBlock($bb, 5);
}
my $loc = $branches->value(5);
my @l = $loc->blocks();
print "list=", scalar(@l), "\n";
my $nblocks = $loc->blocks();
my $ncodes  = $loc->codes();
print "scalar blocks=$nblocks codes=$ncodes\n";
# numeric use must not warn or compare against a stringified object/signature
print "numeric ok=", (($nblocks == 3 && $ncodes == 3) ? 1 : 0), "\n";
# the sorted form still returns the full list in list context
print "sorted list=", scalar(my @s = $loc->blocks(1)), " ",
      scalar(my @sc = $loc->codes(1)), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# BranchLocation::merge has two arms per signature: merge-in-order when we
# already have the code, and copy-all-blocks when we do not.  The second arm
# calls insertBlock, which appends to the very code_map entry the first arm
# reads through, so both must be exercised -- here in one union, by giving
# 'other' one code we share and one we do not.
run_test "BranchLocation::merge copies blocks for an unseen code" '
use lcovutil;
my $x = BranchData->new();
my $y = BranchData->new();
# 2-element block: a code both sides have
for my $bd ($x, $y) {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new($_, 1)) for 0 .. 1;
    $bd->insertBlock($bb, 5);
}
# 3-element blocks: a code only $y has
for my $i (0 .. 1) {
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new($_, 1)) for 0 .. 2;
    $y->insertBlock($bb, 5);
}
$x->updateCounts();
$y->updateCounts();
$x->union($y);
my $loc = $x->value(5);
print "blocks=", $loc->numBlocks(),
      " idx=", join(",", map { $_->idx() } $loc->blocks()),
      " codelen=", join(",", map { length($_) } sort $loc->codes()), "\n";
for my $c (sort $loc->codes()) {
    print "  siglen ", length($c), " -> idx ",
          join(",", map { $_->idx() } @{$loc->getList($c)}), "\n";
}
my ($f, $h) = $x->get_found_and_hit();
print "f/h=$f/$h\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# BranchData tests (inherits BranchMap)
# ==============================================================================

run_test "BranchData::new" '
use lcovutil;
my $d = BranchData->new();
print ref($d), " ", $d->found(), " ", $d->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchData::findOrCreate new line" '
use lcovutil;
my $d = BranchData->new();
my $loc = $d->findOrCreate(10);
print ref($loc), " ", $loc->line();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchData::findOrCreate same line returns same obj" '
use lcovutil;
my $d = BranchData->new();
my $loc1 = $d->findOrCreate(10);
my $loc2 = $d->findOrCreate(10);
print $loc1 == $loc2 ? "same" : "diff";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchData::insertBlock + found/hit" '
use lcovutil;
my $d = BranchData->new();
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 3));
$bb->appendElement(BranchElement->new("2", 0));
$d->insertBlock($bb, 5);
my $bb2 = BranchBlock->new();
$bb2->appendElement(BranchElement->new("1", 0));
$d->insertBlock($bb2, 5);
$d->updateCounts();
my ($f, $h) = $d->get_found_and_hit();
print "$f $h";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchData::remove line" '
use lcovutil;
my $d = BranchData->new();
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 5));
$d->insertBlock($bb, 10);
$d->updateCounts();
$d->remove(10);
print $d->found(), " ", $d->hit(), " ", defined($d->value(10)) ? "exists" : "gone";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchData::union" '
use lcovutil;
my $a = BranchData->new();
my $bba = BranchBlock->new();
$bba->appendElement(BranchElement->new("1", 3));
$a->insertBlock($bba, 5);
$a->updateCounts();

my $b = BranchData->new();
my $bbb = BranchBlock->new();
$bbb->appendElement(BranchElement->new("1", 4));
$b->insertBlock($bbb, 5);
$b->updateCounts();

$a->union($b, "f.c");
my $loc = $a->value(5);
print $a->found(), " ", $a->hit(), " ",
      $loc->getBlock(0)->getElement(0)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchData::intersect common line kept" '
use lcovutil;
my $a = BranchData->new();
my $bba = BranchBlock->new();
$bba->appendElement(BranchElement->new("1", 2));
$a->insertBlock($bba, 5);
my $bba2 = BranchBlock->new();
$bba2->appendElement(BranchElement->new("1", 1));
$a->insertBlock($bba2, 9);
$a->updateCounts();

my $b = BranchData->new();
my $bbb = BranchBlock->new();
$bbb->appendElement(BranchElement->new("1", 1));
$b->insertBlock($bbb, 5);
$b->updateCounts();

$a->intersect($b, "f.c");
print $a->found(), " ", defined($a->value(9)) ? "has9" : "no9",
      " ", defined($a->value(5)) ? "has5" : "no5";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchData::difference" '
use lcovutil;
my $a = BranchData->new();
my $bba = BranchBlock->new();
$bba->appendElement(BranchElement->new("1", 2));
$a->insertBlock($bba, 5);
my $bba2 = BranchBlock->new();
$bba2->appendElement(BranchElement->new("1", 1));
$a->insertBlock($bba2, 9);
$a->updateCounts();

my $b = BranchData->new();
my $bbb = BranchBlock->new();
$bbb->appendElement(BranchElement->new("1", 1));
$b->insertBlock($bbb, 5);
$b->updateCounts();

$a->difference($b, "f.c");
print defined($a->value(5)) ? "has5" : "no5",
      " ", defined($a->value(9)) ? "has9" : "no9";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# difference() where a line survives because only SOME of its blocks match the
# other set: line 5 has two distinct-signature blocks here but the other set
# has only the single-element signature, so the two-element block is retained.
# Exercises the disjoint-code arm of BranchData::difference_with.
run_test "BranchData::difference disjoint code retains block" '
use lcovutil;
my $a = BranchData->new();
my $b1 = BranchBlock->new(); $b1->appendElement(BranchElement->new("1", 2));
$a->insertBlock($b1, 5);
my $b2 = BranchBlock->new();
$b2->appendElement(BranchElement->new("1", 1));
$b2->appendElement(BranchElement->new("2", 1));
$a->insertBlock($b2, 5);
$a->updateCounts();
my $b = BranchData->new();
my $b3 = BranchBlock->new(); $b3->appendElement(BranchElement->new("1", 1));
$b->insertBlock($b3, 5);
$b->updateCounts();
$a->difference($b, "f.c");
my $loc = $a->value(5);
print defined($loc) ? "has5" : "no5", " nblk=", $loc ? $loc->numBlocks() : 0;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# union() has two arms per line: merge into an existing location, or -- when the
# line is absent from self -- take a copy of the other side's location whole.
# The "BranchData::union" case above only exercises the merge arm (both sides
# hold line 5); this one uses disjoint lines so only the copy arm runs, and
# checks the copied location contributes its found/hit.
run_test "BranchData::union of disjoint lines copies location" '
use lcovutil;
sub mk {
    my ($line, $count) = @_;
    my $bd = BranchData->new();
    my $bb = BranchBlock->new();
    $bb->appendElement(BranchElement->new("1", $count));
    $bd->insertBlock($bb, $line);
    $bd->updateCounts();
    return $bd;
}
my $ba = mk(10, 1);
my $changed = $ba->union(mk(20, 5), "f.c");
print "changed=$changed keys=", join(",", sort { $a <=> $b } $ba->keylist()),
      " found=", $ba->found(), " hit=", $ba->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# union() maintains the cached found/hit one of two ways, chosen up front from
# the relative sizes of the two maps: incrementally (per line brought in) when
# the incoming map is small next to the accumulator, or with a single rescan of
# everything afterwards when it is not.  The threshold is
# 2 * (your lines) > (my lines), so the cases below straddle it: 2 incoming
# lines against 20 held picks incremental, and equal-sized maps pick rescan.
# Each shape (all-new lines, all-shared lines, a mix) has to come out with the
# same found/hit and the same 0/1 'changed' either way, so _checkCounts -- which
# dies if the cached totals disagree with a fresh walk -- is the real assertion.
#
# 'shifted' rebuilds the same lines with the counts rotated, so a shared line
# merges to a different value: that is the only way the incremental arm reaches
# its "the merge changed something" case, and the only way its found/hit delta
# is non-zero.  Without it every shared-line merge is a no-op.
run_test "BranchData::union incremental and rescan count paths agree" '
use lcovutil;
sub mk {
    my ($shift, @lines) = @_;
    my $bd = BranchData->new();
    foreach my $line (@lines) {
        my $bb = BranchBlock->new();
        $bb->appendElement(BranchElement->new("1", ($line + $shift) % 3));
        $bb->appendElement(BranchElement->new("2", $shift));
        $bd->insertBlock($bb, $line);
    }
    $bd->updateCounts();
    return $bd;
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
    my $bd      = mk(0, @$mine);
    my $changed = $bd->union(mk($shift, @$yours), "f.c");
    $bd->_checkCounts();       # dies unless cached found/hit match a fresh walk
    printf("%-26s changed=%d found=%d hit=%d lines=%d\n",
           $name, $changed, $bd->found(), $bd->hit(), scalar($bd->keylist()));
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# intersect() is per-line AND per-code: a line the two sides share can still end
# up with NO surviving blocks if they share no signature.  When that happens the
# replacement location is empty and the line must be erased outright rather than
# re-inserted as an empty location.  Here self holds signature "b" and other
# holds "e" for the same line.
run_test "BranchData::intersect drops line whose codes all differ" '
use lcovutil;
my $ba = BranchData->new();
my $b1 = BranchBlock->new();
$b1->appendElement(BranchElement->new("1", 3));                       # sig "b"
$ba->insertBlock($b1, 7);
$ba->updateCounts();

my $bb = BranchData->new();
my $b2 = BranchBlock->new();
$b2->appendElement(BranchElement->new("1", 3, undef, BranchElement::EXCEPT));
$bb->insertBlock($b2, 7);                                             # sig "e"
$bb->updateCounts();

my $changed = $ba->intersect($bb, "f.c");
print "changed=$changed keys=[", join(",", sort { $a <=> $b } $ba->keylist()),
      "] line7=", (defined($ba->value(7)) ? "exists" : "gone"),
      " found=", $ba->found(), " hit=", $ba->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# adjust_counts applies signed deltas directly to the cached found/hit totals
# (used by callback scripts like unreach.pm).
run_test "BranchData::adjust_counts" '
use lcovutil;
my $d = BranchData->new();
$d->adjust_counts(5, 3);
print $d->found(), " ", $d->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchData Storable dclone independence" '
use lcovutil;
use Storable qw(dclone);
my $d = BranchData->new();
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 5));
$d->insertBlock($bb, 10);
$d->updateCounts();
my $d2 = dclone($d);
$d2->value(10)->getBlock(0)->getElement(0)->merge(
    BranchElement->new("1", 3), "f.c", 10);
$d2->updateCounts();
print $d->value(10)->getBlock(0)->getElement(0)->count(), " ",
      $d2->value(10)->getBlock(0)->getElement(0)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# MCDC_Expression tests
# ==============================================================================

run_test "MCDC_Expression::new via MCDC_Block::insertExpr" '
use lcovutil;
my $mb = MCDC_Block->new(20);
$mb->insertExpr("f.c", 2, 1, 3, 0, "a>0", 0);
my $e = $mb->expr(2, 0);
print ref($e), " gs=", $e->groupSize(), " idx=", $e->index(),
      " expr=", $e->expression();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression::count + set" '
use lcovutil;
my $mb = MCDC_Block->new(20);
$mb->insertExpr("f.c", 2, 1, 3, 0, "a>0", 0);
$mb->insertExpr("f.c", 2, 0, 5, 0, "a>0", 0);
my $e = $mb->expr(2, 0);
print $e->count(1), " ", $e->count(0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression::count with no sense arg (defaults to 0)" '
use lcovutil;
my $mb = MCDC_Block->new(20);
$mb->insertExpr("f.c", 2, 0, 7, 0, "x", 0);
my $e = $mb->expr(2, 0);
print $e->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression::is_excluded + set_excluded" '
use lcovutil;
my $mb = MCDC_Block->new(20);
$mb->insertExpr("f.c", 2, 1, 0, 0, "a", 0);
my $e = $mb->expr(2, 0);
print $e->is_excluded(1), " ";
my $r1 = $e->set_excluded(1);
my $r2 = $e->set_excluded(1);
print $e->is_excluded(1), " r1=$r1 r2=$r2";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# render_data(sense) is the batch accessor bin/genhtml's MC/DC render loop uses
# instead of count/expression/is_excluded plus parent()->num_groups().  It must
# return 4 values, and the 4th ("does the parent block have >1 group") must
# match what the parent reports.
run_test "MCDC_Expression::render_data single group" '
use lcovutil;
my $mb = MCDC_Block->new(20);
$mb->insertExpr("f.c", 2, 1, 3, 0, "a>0", 0);
my $e = $mb->expr(2, 0);
foreach my $sense (0, 1) {
    my @d = $e->render_data($sense);
    print "sense=$sense n=", scalar(@d), " [",
          join(",", map { defined($_) ? $_ : "undef" } @d), "] ";
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression::render_data multiple groups + excluded" '
use lcovutil;
my $mb = MCDC_Block->new(20);
$mb->insertExpr("f.c", 2, 1, 3, 0, "a>0", 0);
$mb->insertExpr("f.c", 3, 1, 4, 0, "b>0", 0);
print "groups=", $mb->num_groups(), " ";
foreach my $gs (2, 3) {
    my $e = $mb->expr($gs, 0);
    $e->set_excluded(0) if $gs == 3;
    my @d = $e->render_data(0);
    print "gs=$gs n=", scalar(@d), " [",
          join(",", map { defined($_) ? $_ : "undef" } @d), "] ";
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression::render_data differential count" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 0, 1, 0, "a", 0);
my $e = $mb->expressions(2)->[0];
$e->set(0, ["LBC", 3, 0]);
my ($count, $expr, $excl, $multi) = $e->render_data(0);
print "isarray=", (ref($count) eq "ARRAY" ? 1 : 0),
      " n=", (ref($count) eq "ARRAY" ? scalar(@$count) : 0),
      " [", join(",", map { defined($_) ? $_ : "undef" } @$count), "]",
      " expr=$expr excl=$excl multi=$multi";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression::render_data agrees with scalar accessors" '
use lcovutil;
my $mb = MCDC_Block->new(20);
$mb->insertExpr("f.c", 2, 1, 3, 0, "a>0", 0);
$mb->insertExpr("f.c", 4, 0, 5, 0, "b>0", 1);
foreach my $gs (2, 4) {
    my $e = $mb->expr($gs, 0);
    foreach my $sense (0, 1) {
        my ($count, $expr, $excl, $multi) = $e->render_data($sense);
        my $ref = $e->count($sense);
        if (ref($ref) eq "ARRAY") {
            die("count array") unless join(",", map { $_ // q() } @$count) eq
                join(",", map { $_ // q() } @$ref);
        } else {
            die("count") unless $count == $ref;
        }
        die("expr")  unless $expr eq $e->expression();
        die("excl")  unless !$excl == !$e->is_excluded($sense);
        die("multi") unless !$multi == !($e->parent()->num_groups() > 1);
    }
}
print "ok";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Expression::parent" '
use lcovutil;
my $mb = MCDC_Block->new(20);
$mb->insertExpr("f.c", 2, 1, 3, 0, "a>0", 0);
my $e = $mb->expr(2, 0);
print $e->parent() == $mb ? "same" : "diff";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }


if [ $status -eq 0 ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'xs_3' $LOCAL_COVERAGE
fi

exit $status
