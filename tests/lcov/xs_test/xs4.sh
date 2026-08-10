#!/usr/bin/env bash
# Verify that the pure-Perl and C++ XS implementations of the coverage data
# classes support identical interfaces and produce identical results.
#
# xs4 of the former monolithic 'xs_test.sh' (see setup_common.sh).
# Covers: MCDC_Block; MCDC_Data (inherits BranchMap); additional MapData and
# BranchElement coverage.
#
# Run with: make check, or tests/bin/runtests.py lcov/xs_test/xs4.sh

set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf xs4.d
    exit 0
fi

WORKDIR=xs4.d
source ./setup_common.sh

status=0

# ==============================================================================
# MCDC_Block tests
# ==============================================================================

run_test "MCDC_Block::new + line" '
use lcovutil;
my $mb = MCDC_Block->new(30);
print ref($mb), " ", $mb->line(), " ", $mb->num_groups();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block::insertExpr + num_groups + expressions" '
use lcovutil;
my $mb = MCDC_Block->new(30);
$mb->insertExpr("f.c", 3, 1, 2, 0, "a", 0);
$mb->insertExpr("f.c", 3, 1, 1, 1, "b", 0);
$mb->insertExpr("f.c", 3, 0, 4, 2, "c", 0);
print $mb->num_groups(), " ", scalar(@{$mb->expressions(3)});
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# There is no such thing as a legitimately missing expression:  the caller names
# a group and an index its own annotation claims exist, so expr() dies on an
# unknown group size or an out-of-range index rather than returning undef.
# A negative index must not count back from the end of the group, and neither
# expr() nor expressions() may AUTOVIVIFY the group it was asked about -- an
# empty group created by a query would show up in num_groups() and the report.
run_test "MCDC_Block::expr dies on invalid index / unknown group size" '
use lcovutil;
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 1, 3, 0, "a", 0);
$mb->insertExpr("f.c", 2, 0, 7, 1, "b", 0);
foreach my $i (0, 1, 2, -1, -3) {
    my $e   = eval { $mb->expr(2, $i) };
    my $err = $@;
    $err =~ s/ at .* line \d+\.?\s*$//s if $err;
    print "expr(2,$i)=", ($err ? "DIED: $err" : $e->expression()), "\n";
}
my $e   = eval { $mb->expr(5, 0) };
my $err = $@;
$err =~ s/ at .* line \d+\.?\s*$//s if $err;
print "expr(5,0)=", ($err ? "DIED: $err" : $e->expression()), "\n";
print "groups-after-expr=", $mb->num_groups(), "\n";
print "expressions(5)=", (defined($mb->expressions(5)) ? "def" : "undef"), "\n";
print "groups-final=", $mb->num_groups(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block::totals" '
use lcovutil;
my $mb = MCDC_Block->new(30);
$mb->insertExpr("f.c", 2, 1, 3, 0, "a", 0);
$mb->insertExpr("f.c", 2, 0, 0, 1, "b", 0);
my ($f, $h) = $mb->totals();
print "$f $h";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block::is_compatible same groups" '
use lcovutil;
my $a = MCDC_Block->new(10);
$a->insertExpr("f.c", 2, 1, 1, 0, "x>0", 0);
$a->insertExpr("f.c", 2, 1, 2, 1, "y>0", 0);
my $b = MCDC_Block->new(10);
$b->insertExpr("f.c", 2, 0, 3, 0, "x>0", 0);
$b->insertExpr("f.c", 2, 0, 1, 1, "y>0", 0);
print $a->is_compatible($b);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block::merge" '
use lcovutil;
my $a = MCDC_Block->new(10);
$a->insertExpr("f.c", 2, 1, 2, 0, "x>0", 0);
$a->insertExpr("f.c", 2, 0, 0, 1, "y>0", 0);
my $b = MCDC_Block->new(10);
$b->insertExpr("f.c", 2, 1, 3, 0, "x>0", 0);
$b->insertExpr("f.c", 2, 0, 5, 1, "y>0", 0);
$a->merge($b, "f.c");
print $a->expr(2,0)->count(1), " ", $a->expr(2,1)->count(0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Merging expressions whose "unreachable"/excluded tags differ emits a
# (mismatch) warning; with the error ignored the merge still proceeds.  This
# exercises the MCDC_Block::merge mismatch-reporting arm (report_error callback
# in the XS path).
run_test "MCDC_Block::merge unreachable-tag mismatch warns" '
use lcovutil;
lcovutil::parse_ignore_errors("mismatch");
my $a = MCDC_Block->new(10);
$a->insertExpr("f.c", 2, 1, 2, 0, "x", 0);
$a->insertExpr("f.c", 2, 0, 0, 1, "y", 0);
my $b = MCDC_Block->new(10);
$b->insertExpr("f.c", 2, 1, 2, 0, "x", 1);
$b->insertExpr("f.c", 2, 0, 0, 1, "y", 0);
$a->merge($b, "f.c");
print "merged excl=", $a->expr(2,0)->is_excluded(0) ? 1 : 0;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block Storable dclone independence" '
use lcovutil;
use Storable qw(dclone);
my $mb = MCDC_Block->new(10);
$mb->insertExpr("f.c", 2, 1, 5, 0, "a", 0);
my $mb2 = dclone($mb);
$mb2->expr(2, 0)->set(1, 10, 0);
print $mb->expr(2, 0)->count(1), " ", $mb2->expr(2, 0)->count(1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# genhtml differential mode builds a "<<<N" line key for lines deleted in
# "current" (bin/genhtml ~3131) and constructs MCDC_Block->new($deleteKey).
# The non-numeric key must round-trip verbatim through line() without an
# "argument is not numeric" warning (pure-Perl stores $line as-is).
run_test "MCDC_Block::new + line non-numeric delete key" '
use lcovutil;
my $mb = MCDC_Block->new("<<<123");
print ref($mb), " ", $mb->line(), " ", $mb->num_groups();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Block non-numeric key Storable dclone" '
use lcovutil;
use Storable qw(dclone);
my $mb = MCDC_Block->new("<<<456");
$mb->insertExpr("f.c", 2, 1, 5, 0, "a", 0);
my $mb2 = dclone($mb);
print $mb->line(), " ", $mb2->line(), " ", $mb2->expr(2, 0)->count(1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# MCDC_Data tests (inherits BranchMap)
# ==============================================================================

run_test "MCDC_Data::new" '
use lcovutil;
my $d = MCDC_Data->new();
print ref($d), " ", $d->found(), " ", $d->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# adjust_counts applies signed deltas directly to the cached found/hit totals.
run_test "MCDC_Data::adjust_counts" '
use lcovutil;
my $d = MCDC_Data->new();
$d->adjust_counts(7, 2);
print $d->found(), " ", $d->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# remove() returns 1 when a block was removed and 0 when the line is absent
# (with check).  The XS path historically inverted these (0 removed / -1
# absent), which made the geninfo "exclude MCDC" gate log backwards.
run_test "MCDC_Data::remove return value" '
use lcovutil;
my $d = MCDC_Data->new();
my $mb = $d->new_mcdc(undef, 5);
$mb->insertExpr("f.c", 2, 1, 5, 0, "a", 0);
$mb->insertExpr("f.c", 2, 0, 3, 1, "b", 0);
$d->close_mcdcBlock($mb);
my $present = $d->remove(5, 1);
my $absent  = $d->remove(999, 1);
print "present=$present absent=$absent";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::new_mcdc creates MCDC_Block" '
use lcovutil;
my $d = MCDC_Data->new();
my $mb = $d->new_mcdc(undef, 15);
print ref($mb), " ", $mb->line();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::new_mcdc same line returns same obj" '
use lcovutil;
my $d = MCDC_Data->new();
my $mb1 = $d->new_mcdc(undef, 15);
my $mb2 = $d->new_mcdc(undef, 15);
print $mb1 == $mb2 ? "same" : "diff";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::close_mcdcBlock + found/hit" '
use lcovutil;
my $d = MCDC_Data->new();
my $mb = $d->new_mcdc(undef, 20);
$mb->insertExpr("f.c", 2, 1, 3, 0, "a", 0);
$mb->insertExpr("f.c", 2, 0, 0, 1, "b", 0);
$d->close_mcdcBlock($mb);
print $d->found(), " ", $d->hit();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::append_mcdc" '
use lcovutil;
my $d = MCDC_Data->new();
my $mb = MCDC_Block->new(25);
$mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
$mb->insertExpr("f.c", 2, 0, 1, 1, "y", 0);
$d->append_mcdc($mb);
print defined($d->value(25)) ? "found" : "missing";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::remove line" '
use lcovutil;
my $d = MCDC_Data->new();
my $mb = $d->new_mcdc(undef, 20);
$mb->insertExpr("f.c", 2, 1, 5, 0, "a", 0);
$mb->insertExpr("f.c", 2, 0, 3, 1, "b", 0);
$d->close_mcdcBlock($mb);
$d->remove(20);
print $d->found(), " ", defined($d->value(20)) ? "exists" : "gone";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::union" '
use lcovutil;
my $a = MCDC_Data->new();
my $mba = $a->new_mcdc(undef, 10);
$mba->insertExpr("f.c", 2, 1, 2, 0, "x", 0);
$mba->insertExpr("f.c", 2, 0, 0, 1, "y", 0);
$a->close_mcdcBlock($mba);

my $b = MCDC_Data->new();
my $mbb = $b->new_mcdc(undef, 10);
$mbb->insertExpr("f.c", 2, 1, 3, 0, "x", 0);
$mbb->insertExpr("f.c", 2, 0, 5, 1, "y", 0);
$b->close_mcdcBlock($mbb);

$a->union($b, "f.c");
my $merged = $a->value(10);
print $a->found(), " ", $a->hit(), " ",
      $merged->expr(2,0)->count(1), " ", $merged->expr(2,1)->count(0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::intersect common line kept" '
use lcovutil;
my $a = MCDC_Data->new();
for my $line (10, 20) {
    my $mb = $a->new_mcdc(undef, $line);
    $mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
    $mb->insertExpr("f.c", 2, 0, 1, 1, "y", 0);
    $a->close_mcdcBlock($mb);
}

my $b = MCDC_Data->new();
my $mb = $b->new_mcdc(undef, 10);
$mb->insertExpr("f.c", 2, 1, 2, 0, "x", 0);
$mb->insertExpr("f.c", 2, 0, 0, 1, "y", 0);
$b->close_mcdcBlock($mb);

$a->intersect($b, "f.c");
print defined($a->value(10)) ? "has10" : "no10",
      " ", defined($a->value(20)) ? "has20" : "no20";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data::difference" '
use lcovutil;
my $a = MCDC_Data->new();
for my $line (10, 20) {
    my $mb = $a->new_mcdc(undef, $line);
    $mb->insertExpr("f.c", 2, 1, 1, 0, "x", 0);
    $mb->insertExpr("f.c", 2, 0, 1, 1, "y", 0);
    $a->close_mcdcBlock($mb);
}

my $b = MCDC_Data->new();
my $mb = $b->new_mcdc(undef, 10);
$mb->insertExpr("f.c", 2, 1, 0, 0, "x", 0);
$mb->insertExpr("f.c", 2, 0, 0, 1, "y", 0);
$b->close_mcdcBlock($mb);

$a->difference($b, "f.c");
print defined($a->value(10)) ? "has10" : "no10",
      " ", defined($a->value(20)) ? "has20" : "no20";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "MCDC_Data Storable dclone independence" '
use lcovutil;
use Storable qw(dclone);
my $d = MCDC_Data->new();
my $mb = $d->new_mcdc(undef, 10);
$mb->insertExpr("f.c", 2, 1, 5, 0, "x", 0);
$mb->insertExpr("f.c", 2, 0, 0, 1, "y", 0);
$d->close_mcdcBlock($mb);
my $d2 = dclone($d);
$d2->value(10)->expr(2, 0)->set(1, 10, 0);
$d2->_calculate_counts();
print $d->value(10)->expr(2, 0)->count(1), " ",
      $d2->value(10)->expr(2, 0)->count(1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# MapData -- additional coverage
# ==============================================================================

run_test "MapData::remove (check=false, key absent -- silent success)" '
use lcovutil;
my $m = MapData->new();
my $r = $m->remove("nosuchkey");
print $r, " ", $m->entries();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# BranchElement -- additional coverage
# ==============================================================================

run_test "BranchElement::data() numeric path" '
use lcovutil;
my $b = BranchElement->new("1", 7);
print $b->data();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::exprString() when expr_is_id (returns undef string)" '
use lcovutil;
my $b = BranchElement->new("myid", 3, "myid");
print $b->exprString();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::set_tla (then verify with set_differential path)" '
use lcovutil;
my $b = BranchElement->new("1", 5);
$b->set_differential("UNC", 1, 2);
$b->set_tla("EUB");
print $b->tla();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::diff_count with defined values" '
use lcovutil;
my $b = BranchElement->new("1", 5);
$b->set_differential("UNC", 2, 7);
my ($base, $curr) = $b->diff_count();
print $base, " ", $curr;
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::set_differential with undef base and curr" '
use lcovutil;
my $b = BranchElement->new("1", 5);
$b->set_differential("GNC", undef, undef);
print($b->isDifferential() ? 1 : 0), " ", $b->tla();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# base and curr are independently optional: bin/genhtml cloneBlock calls
# set_differential($tla, undef, $count) where the undef base means "this block
# is not in the baseline at all".  An undef must survive as undef -- not become
# 0 -- through the accessors, render_data, and freeze/thaw, in both backends.
run_test "BranchElement::set_differential preserves undef base/curr" '
use lcovutil;
use Storable qw(freeze thaw);
foreach my $pair ([undef, undef], [3, undef], [undef, 7], [2, 9]) {
    my $b = BranchElement->new("1", 5);
    $b->set_differential("LBC", @$pair);
    my @dc  = $b->diff_count();
    my @rd  = $b->render_data();
    my @tdc = thaw(freeze($b))->diff_count();
    print "set(", join(",", map { defined($_) ? $_ : "undef" } @$pair),
          ") diff_count=[", join(",", map { defined($_) ? $_ : "undef" } @dc),
          "] rd_base=", (defined($rd[6]) ? $rd[6] : "undef"),
          " thawed=[", join(",", map { defined($_) ? $_ : "undef" } @tdc), "] ";
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# render_data() is the batch accessor bin/genhtml's source-view render loop
# uses instead of calling data/count/is_excluded/type_name/expr/tla/diff_count
# one at a time.  It must return exactly 7 values in a fixed order for every
# element -- differential or not -- and each value must agree with the scalar
# accessor it replaces, in both backends.
run_test "BranchElement::render_data non-differential" '
use lcovutil;
my $b = BranchElement->new("1", 5, "x>0", BranchElement::EXCEPT);
my @d = $b->render_data();
print "n=", scalar(@d), " [",
      join(",", map { defined($_) ? $_ : "undef" } @d), "]";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::render_data not-taken dash + excluded" '
use lcovutil;
my $b = BranchElement->new("2", "-", undef, BranchElement::FALLTHROUGH, 1);
my @d = $b->render_data();
print "n=", scalar(@d), " [",
      join(",", map { defined($_) ? $_ : "undef" } @d), "]";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::render_data differential" '
use lcovutil;
my $b = BranchElement->new("3", 7);
$b->set_differential("LBC", 4, 7);
my @d = $b->render_data();
print "n=", scalar(@d), " [",
      join(",", map { defined($_) ? $_ : "undef" } @d), "]";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::render_data differential, no counts" '
use lcovutil;
my $b = BranchElement->new("4", 0);
$b->set_differential("UNC", undef, undef);
my @d = $b->render_data();
print "n=", scalar(@d), " [",
      join(",", map { defined($_) ? $_ : "undef" } @d), "]";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# The batch path must not drift from the scalar accessors it replaces.
run_test "BranchElement::render_data agrees with scalar accessors" '
use lcovutil;
foreach my $type (BranchElement::VANILLA, BranchElement::EXCEPT,
                  BranchElement::FALLTHROUGH) {
    foreach my $taken (0, 3, "-") {
        foreach my $excl (0, 1) {
            foreach my $diff (0, 1) {
                my $b = BranchElement->new("7", $taken, "a&&b", $type, $excl);
                $b->set_differential("LBC", 2, 9) if $diff;
                my ($data, $count, $ex, $tn, $expr, $tla, $base) =
                    $b->render_data();
                die("data")     unless $data eq $b->data();
                die("count")    unless $count == $b->count();
                die("excluded") unless !$ex == !$b->is_excluded();
                die("type")     unless $tn eq $b->type_name();
                die("expr")     unless $expr eq $b->expr();
                if ($diff) {
                    die("tla")  unless $tla eq $b->tla();
                    die("base") unless $base == ($b->diff_count())[0];
                } else {
                    die("tla defined")  if defined($tla);
                    die("base defined") if defined($base);
                }
            }
        }
    }
}
print "ok";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement::merge excluded-mismatch warning (ignorable)" '
use lcovutil;
lcovutil::parse_ignore_errors("mismatch");
my $a = BranchElement->new("1", 3);
my $b = BranchElement->new("1", 2, undef, undef, 1);
$a->merge($b, "f.c", 10);
print $a->is_excluded();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement borrowed DESTROY is a no-op (no crash)" '
use lcovutil;
my $bb = BranchBlock->new();
$bb->appendElement(BranchElement->new("1", 5));
{
    my $borrowed = $bb->getElement(0);
    # $borrowed goes out of scope here -- must not delete the underlying impl
}
print $bb->getElement(0)->count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement Storable freeze/thaw (explicit)" '
use lcovutil;
use Storable qw(freeze thaw);
my $b = BranchElement->new("1", 9, "x>0");
my $c = thaw(freeze($b));
print ref($c), " ", $c->id(), " ", $c->count(), " ", $c->exprString();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "BranchElement Storable freeze/thaw with differential" '
use lcovutil;
use Storable qw(freeze thaw);
my $b = BranchElement->new("1", 5);
$b->set_differential("UNC", 0, 5);
my $c = thaw(freeze($b));
print ref($c), " ", $c->isDifferential(), " ", $c->tla();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "BranchElement validate_taken FORMAT error (fatal)" '
use lcovutil;
my $b = BranchElement->new("1", "notanumber");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "BranchElement validate_taken NEGATIVE error (fatal)" '
use lcovutil;
my $b = BranchElement->new("1", -5);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "BranchElement validate_taken EXCESSIVE error (fatal)" '
use lcovutil;
$lcovutil::excessive_count_threshold = 100;
my $b = BranchElement->new("1", 9999);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ------------------------------------------------------------------------------
# The differential accessors (tla, diff_count, set_tla) all require the element
# to have been made differential first -- set_differential() is the only way in.
# Calling any of them on a plain element must die identically in both backends.
#
# set_tla() is the one that could plausibly be written to just store the value:
# pure Perl would fill its TLA array slot while isDifferential() (which tests the
# array's length) stayed false, so a following tla() would die on the value just
# stored -- and XS, whose isDifferential() asks whether the differential payload
# is allocated, would answer true for the same call.  Both reject it instead;
# set_differential() is the way in.  bin/genhtml's TLA-remap loop is the only
# caller of set_tla and it reads tla() first, so the element is always already
# differential there.
# ------------------------------------------------------------------------------
run_error_test "BranchElement::tla on non-differential element dies" '
use lcovutil;
my $b = BranchElement->new("1", 5);
$b->tla();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "BranchElement::diff_count on non-differential element dies" '
use lcovutil;
my $b = BranchElement->new("1", 5);
$b->diff_count();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "BranchElement::set_tla on non-differential element dies" '
use lcovutil;
my $b = BranchElement->new("1", 5);
$b->set_tla("GBC");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# render_data() deliberately does NOT die on a non-differential element: it is
# the batch accessor and returns undef for the tla/base fields so the caller can
# decide.  Confirm that split in behaviour, and that a plain element still
# reports isDifferential() false after the failed set_tla above.
run_test "BranchElement::render_data non-differential yields undef tla/base" '
use lcovutil;
my $b = BranchElement->new("1", 5);
eval { $b->set_tla("GBC") };
print "isDiff=", ($b->isDifferential() ? 1 : 0);
my @d = $b->render_data();
print " n=", scalar(@d),
      " tla=", defined($d[5]) ? $d[5] : "undef",
      " base=", defined($d[6]) ? $d[6] : "undef";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }


if [ $status -eq 0 ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'xs_4' $LOCAL_COVERAGE
fi

exit $status
