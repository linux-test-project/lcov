#!/usr/bin/env bash
# Verify that the pure-Perl and C++ XS implementations of the function data
# classes support identical interfaces and produce identical results.
#
# xs8 covers the function family - FunctionAlias, FunctionEntry, FunctionMap -
# which the other parts do not touch:  they were pure Perl only until the C++
# implementation was added, so this part is the equivalence proof for it.
# Covers: define_function and the location/name maps; the alias name election
# (shortest name, lambda penalty, lexical tie-break); call sites, their counts,
# their differential categories and their removal; end-line policy; the
# differential [count, tla] representation of both an entry and an alias;
# cloneWithEndLine; callers; union/intersect/difference/remove; entry identity
# across relocation; the Storable (fork IPC / dclone) round trip of a map, an
# entry and an alias; and the error paths of all three classes.
#
# Run with: make check, or tests/bin/runtests.py lcov/xs_test/xs8.sh

set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf xs8.d
    exit 0
fi

WORKDIR=xs8.d
source ./setup_common.sh

status=0

# ==============================================================================
# FunctionMap:  the two maps, and the entry both of them reach
#
# A FunctionMap indexes its entries twice - by start line and by every name the
# entry answers to - and the two indexes must reach the *same* entry, not two
# copies of one:  TraceInfo::_fixFunction de-duplicates with refaddr, so a
# backend which handed out a fresh wrapper per lookup would make one function
# look like several.
# ==============================================================================

run_test "FunctionMap::define_function - both indexes reach one entry" '
use lcovutil;
use Scalar::Util qw(refaddr);
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
print $map->filename(), " ", $f->name(), " ", $f->file(), " ",
      $f->line(), "..", $f->end_line(), " aliases=", $f->numAliases(), "\n";
print "byKey=", (refaddr($map->findKey(10)) == refaddr($f) ? 1 : 0),
      " byName=", (refaddr($map->findName("main")) == refaddr($f) ? 1 : 0),
      " returned=", (refaddr($map->define_function("main", 10, 20)) ==
                     refaddr($f) ? 1 : 0), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# An entry is reached through its map, but it does not depend on the map:  a
# reference to it keeps it alive, which is what a pure-Perl reference does and
# what the XS backend has to reproduce.  Both of these are real patterns -
# 'dclone($map)->findKey($line)' frees the clone at the end of the statement,
# and 'remove' drops an entry the caller still holds in a loop variable.
run_test "FunctionEntry outlives the map it came from" '
use lcovutil;
use Storable qw(dclone);
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addAlias("main", 3);
$f->addCallSite(12, 4, 0, 3, "ab");
$f->setCallSiteTla(12, 4, 0, undef, "GBC");
my $chained = dclone($map)->findKey(10);
print $chained->name(), " ", $chained->file(), " ", $chained->line(), "..",
      $chained->end_line(), " hit=", $chained->hit(), " tla=",
      $chained->callSiteTla(12, 4, 0), " alias=",
      $chained->alias("main")->count(), "\n";
my $held;
{
    my $scoped = dclone($map);
    $held = $scoped->findKey(10);
}
print $held->name(), " sites=", $held->numCallSites(), " tla=",
      $held->callSiteTla(12, 4, 0), " hit=", $held->hit(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry outlives its removal from the map" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addAlias("main", 3);
$f->addCallSite(12, 4, 0, 3, "ab");
$map->remove($f);
print "keys=", scalar($map->keylist()), " names=",
      scalar($map->list_functions()), "\n";
print $f->name(), " ", $f->line(), " hit=", $f->hit(), " sites=",
      $f->numCallSites(), " alias=", $f->alias("main")->count(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap::define_function - undef end line" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, undef);
print defined($f->end_line()) ? "defined" : "undef", "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap - lookups which find nothing" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
print defined($map->findKey(999)) ? 1 : 0,
      defined($map->findName("nosuch")) ? 1 : 0,
      defined($f->alias("nosuch")) ? 1 : 0,
      scalar($f->callSiteData("1:2:3")), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap - keylist/list_functions/valuelist in both contexts" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addAlias("_Z4mainv", 1);
$map->define_function("bar", 30, 40);
print join(",", sort({ $a <=> $b } $map->keylist())), " ",
      join(",", sort($map->list_functions())), " ",
      join(",", sort(map({ $_->name() } $map->valuelist()))), "\n";
print "scalar keylist=", scalar($map->keylist()),
      " list_functions=", scalar($map->list_functions()),
      " valuelist=", scalar(my @v = $map->valuelist()),
      " aliasNames=", scalar($f->aliasNames()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap::numFunc/numHit - merged and per alias" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addAlias("main", 3);
$f->addAlias("_Z4mainv", 0);
my $g = $map->define_function("bar", 30, 40);
print $map->numFunc(0), "/", $map->numHit(0), " ",
      $map->numFunc(1), "/", $map->numHit(1), " ",
      join("/", $map->get_found_and_hit()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap::add_count accumulates through the name map" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addAlias("main", 3);
$map->add_count("main", 4);
print $f->hit(), " ", $f->alias("main")->count(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap::add_count of an unknown name is ignorable" '
use lcovutil;
lcovutil::parse_ignore_errors("mismatch");
$SIG{__WARN__} = sub { my $m = shift; $m =~ s/\s+/ /g; print "$m\n" };
my $map = FunctionMap->new("foo.c");
$map->add_count("nosuch", 4);
print "survived ", scalar($map->keylist()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# The alias name election
#
# The name an entry reports is the shortest of its aliases, with a lambda name
# penalized so that a real symbol always wins over the compiler's name for a
# lambda, and ties broken lexically so the choice does not depend on the order
# the aliases arrived in (which, in a parallel run, is not deterministic).
# ==============================================================================

run_test "FunctionEntry::addAlias - shortest alias name wins" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("_Z3fooIiEvT_", 10, 20);
$f->addAlias("_Z3fooIdEvT_", 1);
$f->addAlias("ab", 2);
print $f->name(), " ", $f->numAliases(), " ", $f->hit(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::addAlias - a lambda name loses to a longer symbol" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("longishFunctionName", 10, 20);
$f->addAlias("a{lambda(int)#1}", 1);
$f->addAlias("b.lambda$0", 1);
print $f->name(), "\n";
my $g = $map->define_function("x{lambda(int)#1}", 30, 40);
$g->addAlias("plainName", 1);
print $g->name(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::addAlias - equal length ties break lexically" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("bbb", 10, 20);
$f->addAlias("aaa", 1);
$f->addAlias("ccc", 1);
print $f->name(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::addAlias - what counts as a change" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
# a new alias is a change; the first hit of a zero-count alias is a change;
#   more counts on an alias which was already hit is not
print 0 + $f->addAlias("other", 0), 0 + $f->addAlias("other", 0),
      0 + $f->addAlias("other", 3), 0 + $f->addAlias("other", 3), "\n";
print $f->alias("other")->count(), " ", $f->hit(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::removeAliases re-elects the name" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("_Z3fooIiEvT_", 10, 20);
$f->addAlias("ab", 5);
$f->addAlias("cdef", 7);
print $f->name(), " ", $f->hit(), "\n";
print 0 + !!$f->removeAliases("ab"), " ", $f->name(), " ", $f->hit(), " ",
      join(",", sort($f->aliasNames())), "\n";
print 0 + !!$f->removeAliases("cdef", "_Z3fooIiEvT_"), " ",
      $f->numAliases(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "FunctionEntry::removeAliases rejects an unknown alias" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->removeAliases("nosuch");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::isLambda" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
print 0 + !!$map->define_function("main", 10, 20)->isLambda(),
      0 + !!$map->define_function("a{lambda(int)#1}", 30, 40)->isLambda(),
      0 + !!$map->define_function("b.lambda$0", 50, 60)->isLambda(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# End line
#
# set_end_line is a policy on top of the raw mutator:  an end line before the
# start line is an inconsistency to report, not a value to store.
# ==============================================================================

run_test "FunctionEntry::set_end_line - applied, then rejected" '
use lcovutil;
lcovutil::parse_ignore_errors("inconsistent");
$SIG{__WARN__} = sub { my $m = shift; $m =~ s/\s+/ /g; print "$m\n" };
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 30, undef);
$f->set_end_line(35);
print "end=", $f->end_line(), "\n";
$f->set_end_line(3);
print "end=", $f->end_line(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# _setEndLine is the unchecked mutator that policy sits on:  an undef line
# clears the end line, which is the state an entry is in when the data does not
# say where the function ends.
run_test "FunctionEntry::_setEndLine - undef clears the end line" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 30, 40);
print "end=", $f->end_line(), "\n";
$f->_setEndLine(undef);
print "end=", defined($f->end_line()) ? $f->end_line() : "undef", "\n";
$f->_setEndLine(45);
print "end=", $f->end_line(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap::define_function - mismatched end line is ignorable" '
use lcovutil;
lcovutil::parse_ignore_errors("inconsistent");
$SIG{__WARN__} = sub { my $m = shift; $m =~ s/\s+/ /g; print "$m\n" };
my $map = FunctionMap->new("foo.c");
$map->define_function("main", 10, 20);
$map->define_function("second", 10, 25);
print "end=", $map->findKey(10)->end_line(), " names=",
      join(",", sort($map->list_functions())), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# Relocation
#
# A second definition of a known name on an earlier line moves the entry to the
# lower line - and the entry must survive the move as itself:  everything which
# already holds it (a resolved call site, genhtml's own tables) keeps pointing
# at it, and both indexes must still agree.
# ==============================================================================

run_test "FunctionMap::define_function relocates and keeps entry identity" '
use lcovutil;
use Scalar::Util qw(refaddr);
lcovutil::parse_ignore_errors("inconsistent");
$SIG{__WARN__} = sub { my $m = shift; $m =~ s/\s+/ /g; print "$m\n" };
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("f", 20, 25);
$f->addAlias("f", 1);
my $again = $map->define_function("f", 15, 25);
print "line=", $f->line(), " keys=",
      join(",", sort({ $a <=> $b } $map->keylist())), "\n";
print "same=", (refaddr($again) == refaddr($f) ? 1 : 0),
      " byKey=", (refaddr($map->findKey(15)) == refaddr($f) ? 1 : 0),
      " byName=", (refaddr($map->findName("f")) == refaddr($f) ? 1 : 0),
      " hit=", $f->hit(), "\n";
# a later definition does not move it back up
$map->define_function("f", 40, 25);
print "line=", $f->line(), " keys=",
      join(",", sort({ $a <=> $b } $map->keylist())), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# set_line is the raw mutator relocation is built on - FunctionMap::_relocate
# moves its own index and then moves the entry - and it answers the line it set.
# On an entry which is in no map, which is what cloneWithEndLine hands back,
# there is no index to keep in step and it is simply the start line.
run_test "FunctionEntry::set_line" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
my $c = $f->cloneWithEndLine(1, 1);
print "line=", $c->line(), " end=", $c->end_line(), "\n";
print "returned=", $c->set_line(5), "\n";
print "line=", $c->line(), " end=", $c->end_line(), " name=", $c->name(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# Call sites
#
# One site per (line, column, ordinal) in the calling function, holding the
# count and the name of the callee.
# ==============================================================================

run_test "FunctionEntry::addCallSite - new sites, and what they answer" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
print 0 + $f->addCallSite(12, 4, 0, 1, "ab"),
      0 + $f->addCallSite(12, 9, 0, 0, "cd"),
      0 + $f->addCallSite(13, 1, 1, 5, "printf"), "\n";
print $f->numCallSites(), "/", $f->numCallSitesHit(), " ",
      join(",", $f->sortedCallSiteKeys()), " scalar=",
      scalar($f->callSiteKeys()), "\n";
foreach my $key ($f->sortedCallSiteKeys()) {
    my ($line, $col, $ord, $count, $callee) = $f->callSiteData($key);
    print "  $line:$col:$ord $callee $count ",
          defined($f->callSiteTla($line, $col, $ord)) ? "tla" : "undef", "\n";
}
print join("/", $map->get_callgraph_found_and_hit()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::addCallSite - merging into an existing site" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
# a repeat of a site which was taken is not a change; the first hit of a site
#   which was not taken is
print 0 + $f->addCallSite(12, 4, 0, 1, "ab"),
      0 + $f->addCallSite(12, 4, 0, 2, "ab"),
      0 + $f->addCallSite(12, 9, 0, 0, "cd"),
      0 + $f->addCallSite(12, 9, 0, 0, "cd"),
      0 + $f->addCallSite(12, 9, 0, 7, "cd"), "\n";
print join(",", map({ ($f->callSiteData($_))[3] } $f->sortedCallSiteKeys())),
      " ", $f->numCallSites(), "/", $f->numCallSitesHit(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::addCallSite - the unknown count" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
# "-" is the count of a call the compiler recorded and gcov produced no arc for.
#   It is a third state and not a number:  stored as itself, answered as itself,
#   and never a hit - which is what the C++ side needs its own sentinel for,
#   since a count is an int64 there and "-" is a string here
print 0 + $f->addCallSite(12, 4, 0, "-", "ab"),
      0 + $f->addCallSite(12, 9, 0, 1, "cd"), "\n";
print join(",", map({ ($f->callSiteData($_))[3] } $f->sortedCallSiteKeys())),
      " ", $f->numCallSites(), "/", $f->numCallSitesHit(), " ",
      join("/", $map->get_callgraph_found_and_hit()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::addCallSite - merging an unknown count" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
# The merge is a lattice with "unknown" at the bottom:  a measurement absorbs it
#   in either order, because one capture having a count for the call is all it
#   takes to know there was a call there to count.  Unknown twice stays unknown,
#   and a merge which only replaces the unknown with a zero is not a change
$f->addCallSite(12, 4, 0, "-", "ab");
$f->addCallSite(13, 4, 0, 5, "cd");
$f->addCallSite(14, 4, 0, "-", "ef");
$f->addCallSite(15, 4, 0, "-", "gh");
print 0 + $f->addCallSite(12, 4, 0, 7, "ab"),
      0 + $f->addCallSite(13, 4, 0, "-", "cd"),
      0 + $f->addCallSite(14, 4, 0, "-", "ef"),
      0 + $f->addCallSite(15, 4, 0, 0, "gh"), "\n";
print join(",", map({ ($f->callSiteData($_))[3] } $f->sortedCallSiteKeys())),
      " ", $f->numCallSites(), "/", $f->numCallSitesHit(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::_sitesAt - the sites at one location" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
# what a merge looks an ordinal up in:  the sites at exactly this line and
#   column of exactly this file, in ordinal order whatever order they were
#   added in - and not the neighbours on either side, nor the site of the same
#   location in an "#include"d file
$f->addCallSite(12, 4, 2, 1, "cd");
$f->addCallSite(12, 4, 0, 1, "ab");
$f->addCallSite(12, 4, 1, 1, "cd", "inc.h");
$f->addCallSite(12, 3, 0, 1, "ef");
$f->addCallSite(12, 5, 0, 1, "gh");
$f->addCallSite(13, 4, 0, 1, "ij");
foreach my $file (undef, "inc.h") {
    print defined($file) ? $file : "own", ":",
          join(",", map({ "$_->[0]=$_->[1]" } $f->_sitesAt(12, 4, $file))),
          "\n";
}
print "none:", scalar(my @none = $f->_sitesAt(11, 4)), "\n";
# ..and the ordinal a merge gives a site from another input there:  the one
#   my call to the same callee has, else the lowest gap - here 1, between the
#   0 and the 2, and in the "#include"d file 0, under its 1.  Nothing at a
#   location is ordinal 0, and a callee called only from elsewhere is no help
print join(",", $f->_resolveOrdinal(12, 4, undef, "cd"),
                $f->_resolveOrdinal(12, 4, undef, "xy"),
                $f->_resolveOrdinal(12, 4, "inc.h", "cd"),
                $f->_resolveOrdinal(12, 4, "inc.h", "ab"),
                $f->_resolveOrdinal(11, 4, undef, "ab"),
                $f->_resolveOrdinal(12, 3, undef, "gh")), "\n";
$f->addCallSite(12, 4, 1, 1, "xy");
print "full:", $f->_resolveOrdinal(12, 4, undef, "zz"), "\n";
# ..and a removal - which is what intersect and subtract do after a merge has
#   asked - is seen by the next question:  the gap it leaves is the lowest
#   free ordinal, the second call to a callee answers for it once the first
#   is gone, and a location left with no site has none
$f->addCallSite(12, 4, 3, 1, "cd");
$f->addCallSite(12, 4, 5, 1, "ab");
$f->_removeSite("12:4:2");
print "gap:", $f->_resolveOrdinal(12, 4, undef, "zz"), ",",
      $f->_resolveOrdinal(12, 4, undef, "cd"), "\n";
$f->_removeSite("12:4:3");
$f->_removeSite("12:3:0");
$f->_removeSite("12:4:1:inc.h");
print "gone:", $f->_resolveOrdinal(12, 4, undef, "cd"), ",",
      $f->_resolveOrdinal(12, 4, undef, "ab"), ",",
      scalar(my @l = $f->_sitesAt(12, 3)), ",",
      scalar(my @i = $f->_sitesAt(12, 4, "inc.h")), " ",
      join(",", map({ "$_->[0]=$_->[1]" } $f->_sitesAt(12, 4))), "\n";
# ..and a merge which needed to resolve an ordinal does not leave the pure
#   Perl index behind on either side:  a capture parent merges thousands of
#   functions and must not keep a second copy of each one it has merged.
#   The XS entries have no index, so this reads 0 there by construction
my $g = $map->define_function("other", 30, 40);
$g->addCallSite(12, 4, 0, 1, "zz");
$g->addCallSite(12, 4, 1, 1, "ab");
my $indexed = sub {
    my $e = shift;
    return $lcovutil::XS_LOADED ? 0 :
        defined($e->[FunctionEntry::SITES_AT]) ? 1 : 0;
};
$f->unionCallSites($g);
my $left = $indexed->($f);
print "union:", join(",", map({ "$_->[0]=$_->[1]" } $f->_sitesAt(12, 4))),
      " index=$left\n";
# both sides indexed going in, as they are after a lookup
$g->_sitesAt(12, 4);
$f->intersectCallSites($g);
$left = $indexed->($f) . $indexed->($g);
print "intersect:",
      join(",", map({ "$_->[0]=$_->[1]" } $f->_sitesAt(12, 4))),
      " index=$left\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::addCallSite - two callees at one location" '
use lcovutil;
lcovutil::parse_ignore_errors("mismatch");
$SIG{__WARN__} = sub { my $m = shift; $m =~ s/\s+/ /g; print "$m\n" };
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addCallSite(12, 4, 0, 1, "ab");
# same location, different target:  the first is kept and both are named
print "changed=", 0 + $f->addCallSite(12, 4, 0, 3, "cd"), "\n";
my ($line, $col, $ord, $count, $callee) = $f->callSiteData("12:4:0");
print "$callee $count\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::addCallSite - the file the call is written in" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
# A call written in an "#include"d fragment belongs to the function which
#   included it and is located in the other file, so the file is part of the
#   site identity rather than payload beside it:  these two sites share a
#   line, a column and an ordinal and are distinct.
print 0 + $f->addCallSite(12, 4, 0, 1, "ab"),
      0 + $f->addCallSite(12, 4, 0, 3, "cd", "inc.h"), "\n";
# ..and the callers own file is normalized away, so one site cannot be stored
#   under two keys depending on which producer added it
print 0 + $f->addCallSite(12, 4, 0, 1, "ab", "foo.c"), "\n";
print $f->numCallSites(), "/", $f->numCallSitesHit(), " ",
      join(",", $f->sortedCallSiteKeys()), "\n";
foreach my $key ($f->sortedCallSiteKeys()) {
    my ($line, $col, $ord, $count, $callee, $file) = $f->callSiteData($key);
    print "  $line:$col:$ord $callee $count ",
          defined($file) ? $file : "here", "\n";
}
# the category is keyed by the same four things
$f->setCallSiteTla(12, 4, 0, "inc.h", "GBC");
print "tla=", defined($f->callSiteTla(12, 4, 0, "inc.h")) ?
          $f->callSiteTla(12, 4, 0, "inc.h") : "undef",
      " here=", defined($f->callSiteTla(12, 4, 0)) ? "set" : "undef", "\n";
# and it survives the fork IPC round trip with the site
use Storable qw(dclone);
my $e = dclone($map)->findKey(10);
my ($l, $c, $o, $n, $callee, $file) = $e->callSiteData("12:4:0:inc.h");
print "thawed $callee $n ", $file, " tla=", $e->callSiteTla(12, 4, 0, "inc.h"),
      " ", $e->numCallSites(), "/", $e->numCallSitesHit(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::_removeSite" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addCallSite(12, 4, 0, 1, "ab");
$f->addCallSite(13, 1, 0, 1, "cd");
$f->addCallSite(14, 1, 0, 1, "ef");
# the first of three, then the last of the two which are left:  the site
#   container keeps its sites in order, so removing from the middle and
#   removing from the end are not the same edit
print 0 + !!$f->_removeSite("12:4:0"), 0 + !!$f->_removeSite("12:4:0"),
      " left=", $f->numCallSites(), " ",
      join(",", $f->sortedCallSiteKeys()), "\n";
print 0 + !!$f->_removeSite("14:1:0"), " left=", $f->numCallSites(), " ",
      join(",", $f->sortedCallSiteKeys()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry - an entry with no call sites at all" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
# the site container is not allocated until the first site is added, which
#   must not make any of these answer differently in kind.  scalar() of
#   sortedCallSiteKeys is deliberately not asked:  sort in scalar context is
#   undefined in Perl itself
print $f->numCallSites(), $f->numCallSitesHit(),
      scalar($f->callSiteKeys()), scalar(my @k = $f->sortedCallSiteKeys()),
      defined($f->callSiteTla(1, 2, 3)) ? 1 : 0, " ",
      join("/", $map->get_callgraph_found_and_hit()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry - call site ordinals and source order" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
# f(g(), g()) folds two calls onto one (line, column):  the ordinal is what
#   keeps them apart, and the sort is numeric per field, not string
$f->addCallSite(9, 12, 1, 1, "g");
$f->addCallSite(9, 12, 0, 2, "g");
$f->addCallSite(9, 3, 0, 3, "f");
$f->addCallSite(100, 1, 0, 4, "h");
print join(" ", $f->sortedCallSiteKeys()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::addCallSite - an ordinal a call site cannot hold" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
# the ordinal is the one field of a call site with a limit, so the limit is
#   part of the data rather than of the backend:  both implementations of the
#   _addCallSite primitive refuse the same ordinals, and the message comes
#   from the one copy of the policy in lcovutil.pm
foreach my $ord (65535, 65536, -1) {
    my $rc = eval { $f->addCallSite(12, 4, $ord, 1, "ab") };
    if (defined($rc)) {
        print "ord $ord: rc=", 0 + $rc, "\n";
    } else {
        my $err = $@;
        chomp($err);
        $err =~ s/ at \S+ line \d+\.$//;
        print "ord $ord: $err\n";
    }
}
# nothing was recorded for the two it refused, and neither can be found
print "sites=", $f->numCallSites(), " ",
      join(",", $f->sortedCallSiteKeys()), "\n";
print "found=", scalar(my @d = $f->callSiteData("12:4:65536")),
      " tla=", defined($f->callSiteTla(12, 4, 65536)) ? 1 : 0,
      " removed=", 0 + !!$f->_removeSite("12:4:65536"), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# The differential category of a call site is held as an index into a small
# vocabulary rather than as a string, which is what makes it one byte of the
# record.  The vocabulary is bounded, and only the XS implementation has one:
# pure Perl stores the string itself, so there is nothing to compare against.
run_xs_only_test "the call site category vocabulary is bounded" '
use lcovutil;
exit(0) unless $lcovutil::XS_LOADED;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addCallSite(12, 4, 0, 1, "ab");
my $accepted = 0;
foreach my $i (1 .. 300) {
    my $tla = sprintf("T%03d", $i);
    last unless eval { $f->setCallSiteTla(12, 4, 0, undef, $tla); 1 };
    ++$accepted;
}
die("expected the vocabulary to fill up, accepted $accepted categories")
    unless 255 == $accepted;
die("expected the last accepted category to have stuck")
    unless "T255" eq $f->callSiteTla(12, 4, 0);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# Differential data
#
# genhtml replaces the count of an entry, of an alias, and of a call site with
# a [count, tla] pair once it has categorized them.  Every reader of a count
# has to keep working, so the pair is reached through the same accessors.
# ==============================================================================

run_test "FunctionEntry::setCountDifferential and set_tla" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $real = $map->define_function("main", 10, 20);
$real->addAlias("main", 3);
print 0 + !!$real->is_differential(), " ",
      defined($real->tla()) ? "tla" : "undef", " ", $real->hit(), "\n";
# a fresh entry holding the pair, which is what _cloneFunctionEntry in genhtml
#   builds for a differential table
my $de = FunctionEntry->new($real->name(), $map, $real->line(),
                            $real->end_line());
$de->setCountDifferential([$real->hit(), "GNC"]);
print 0 + !!$de->is_differential(), " ", $de->tla(), " ",
      ref($de->hit()) ? join(",", @{$de->hit()}) : $de->hit(), "\n";
$de->set_tla("GIC");
print $de->tla(), " ",
      ref($de->hit()) ? join(",", @{$de->hit()}) : $de->hit(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::addAliasDifferential" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $de = FunctionEntry->new("main", $map, 10, 20);
$de->setCountDifferential([7, "GNC"]);
# the name of the entry is already an alias, so it is set rather than added
$de->addAliasDifferential("main", [3, "GIC"]);
$de->addAliasDifferential("_Z4mainv", [4, "UNC"]);
$de->addAliasDifferential("neverHit", [undef, "UBC"]);
foreach my $name (sort($de->aliasNames())) {
    my $a = $de->alias($name);
    my ($wn, $wc) = $a->write_data();
    print "  $name diff=", 0 + !!$a->is_differential(), " count=",
          defined($a->count()) ? $a->count() : "undef", " tla=", $a->tla(),
          " wd=$wn/", defined($wc) ? $wc : "undef", "\n";
}
$de->alias("_Z4mainv")->set_tla("GBC");
print $de->alias("_Z4mainv")->tla(), " ", $de->numAliases(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "FunctionEntry::addAliasDifferential rejects an existing alias" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addAlias("other", 1);
$f->addAliasDifferential("other", [1, "GNC"]);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::setCallSiteTla" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addCallSite(12, 4, 0, 3, "ab");
$f->addCallSite(13, 1, 0, 0, "cd");
$f->setCallSiteTla(12, 4, 0, undef, "GBC");
print defined($f->callSiteTla(12, 4, 0)) ? $f->callSiteTla(12, 4, 0) : "undef",
      " ",
      defined($f->callSiteTla(13, 1, 0)) ? $f->callSiteTla(13, 1, 0) : "undef",
      "\n";
# the TLA is appended to the site rather than replacing its count, so every
#   other reader of the site sees one shape
my ($line, $col, $ord, $count, $callee) = $f->callSiteData("12:4:0");
print "$line:$col:$ord $callee $count ", $f->numCallSites(), "/",
      $f->numCallSitesHit(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "FunctionEntry::setCallSiteTla rejects an unknown site" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addCallSite(12, 4, 0, 3, "ab");
$f->setCallSiteTla(99, 1, 0, undef, "GBC");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "FunctionEntry::set_tla on non-differential data" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
$map->define_function("main", 10, 20)->set_tla("GNC");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "FunctionAlias::set_tla on non-differential data" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
$map->define_function("main", 10, 20)->alias("main")->set_tla("GNC");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "FunctionEntry::setCountDifferential rejects a bad pair" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
$map->define_function("main", 10, 20)->setCountDifferential([1]);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "FunctionAlias::set_differential rejects a non-array" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
$map->define_function("main", 10, 20)->alias("main")->set_differential(1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "FunctionEntry::new rejects a map which is not one" '
use lcovutil;
FunctionEntry->new("main", "foo.c", 10, 20);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# FunctionAlias on its own
#
# genhtml builds standalone aliases (and standalone entries) for its
# differential tables, so neither type may depend on being inside a map.
# ==============================================================================

run_test "FunctionAlias standalone - count, clone, differential" '
use lcovutil;
my $a = FunctionAlias->new("sym", 7);
print $a->name(), " ", $a->count(), " resolved=", 0 + !!$a->is_resolved(),
      " diff=", 0 + !!$a->is_differential(), "\n";
$a->add_count(3);
my $b = $a->clone();
$b->set_count(undef);
print $a->count(), " ", $b->name(), " ",
      defined($b->count()) ? $b->count() : "undef", "\n";
$a->set_differential([$a->count(), "GNC"]);
print $a->count(), " ", $a->tla(), " ", 0 + !!$a->is_differential(), "\n";
# a clone of a differential alias shares the pair, as the flat hash it
#   replaced did
my $c = $a->clone();
print $c->count(), " ", $c->tla(), " ", 0 + !!$c->is_differential(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# The 'e' and 'x' letters of an 'FNA:' record are facts about the symbol:  'e'
# says it has external linkage, 'x' that a call to it came from outside the
# boundary, and carries the number of calls made from there where that is
# known.  The writer asks for them together with the count, through
# write_data;  'flags' is the same answer on its own, and the two must agree.
run_test "FunctionAlias::flags and write_data - the FNA: flag letters" '
use lcovutil;
my $a = FunctionAlias->new("sym", 7);
print "none=[", $a->flags(), "]\n";
$a->set_external();
print "external=[", $a->flags(), "] is_external=",
      0 + !!$a->is_external(), "\n";
print "uncalled=", $a->external_calls(), "\n";
$a->add_external_calls("-");
print "both=[", $a->flags(), "] has_external_callers=",
      0 + !!$a->has_external_callers(), " calls=",
      defined($a->external_calls()) ? $a->external_calls() : "undef", "\n";
# a known count replaces the unknown one, and known counts add
$a->add_external_calls(3);
$a->add_external_calls("-");
$a->add_external_calls(2);
print "counted=[", $a->flags(), "] calls=", $a->external_calls(), "\n";
my ($wn, $wc, $wf) = $a->write_data();
print "wd=$wn/$wc/[$wf]\n";
# set-only and idempotent, as both setters promise
$a->set_external();
print "again=[", $a->flags(), "]\n";
# ..and a copy carries both letters and the count, because they are facts
# about the symbol rather than about the report the copy is for
print "clone=[", $a->clone()->flags(), "]\n";
# ..as does a copy made by freezing and thawing, which is how an alias
# crosses the fork
use Storable;
print "dclone=[", Storable::dclone($a)->flags(), "]\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionEntry::cloneWithEndLine" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("_Z3fooIiEvT_", 30, 40);
$f->addAlias("ab", 5);
$f->addAlias("cd", 0);
my $withAliases = $f->cloneWithEndLine(1, 1);
print $withAliases->name(), " ", $withAliases->line(), "..",
      $withAliases->end_line(), " hit=", $withAliases->hit(), " ",
      join(",", sort($withAliases->aliasNames())), "\n";
my $noEnd = $f->cloneWithEndLine(0, 1);
print defined($noEnd->end_line()) ? "defined" : "undef", " hit=",
      $noEnd->hit(), "\n";
my $bare = $f->cloneWithEndLine(1);
print $bare->numAliases(), " hit=", $bare->hit(), " ",
      join(",", sort($bare->aliasNames())), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# callers - the derived direction
#
# The caller side is the stored one; TraceFile::resolveCallSites walks it to
# give each alias its list of callers.  An unresolved alias dies rather than
# answering an empty list:  a missing metric which dies is debuggable, one
# which reads 0/0 is not.
# ==============================================================================

run_error_test "FunctionAlias::callers before resolution" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
$map->define_function("main", 10, 20)->alias("main")->callers();
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "FunctionAlias::add_caller before resolution" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->alias("main")->add_caller($f, 12, 4, 0, 1);
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionAlias::clear_callers/add_caller/callers" '
use lcovutil;
use Scalar::Util qw(refaddr);
my $map = FunctionMap->new("foo.c");
my $main = $map->define_function("main", 10, 20);
$main->addCallSite(12, 4, 0, 3, "ab");
my $ab = $map->define_function("ab", 30, 40);
my $alias = $ab->alias("ab");
$alias->clear_callers();
print "resolved=", 0 + !!$alias->is_resolved(), " callers=",
      scalar($alias->callers()), " num=", $alias->numCallers(), "\n";
$alias->add_caller($main, 12, 4, 0, 3);
my @callers = $alias->callers();
my ($entry, $line, $col, $ord, $count) = @{$callers[0]};
print $entry->name(), " $line:$col:$ord $count same=",
      (refaddr($entry) == refaddr($main) ? 1 : 0), " num=",
      $alias->numCallers(), " scalar=", scalar($alias->callers()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# Set operations
# ==============================================================================

run_test "FunctionMap::union" '
use lcovutil;
my $m1 = FunctionMap->new("foo.c");
my $f = $m1->define_function("main", 10, 20);
$f->addAlias("main", 3);
$f->addCallSite(12, 4, 0, 1, "ab");
my $m2 = FunctionMap->new("foo.c");
my $g = $m2->define_function("main", 10, 20);
$g->addAlias("main", 4);
$g->addAlias("_Z4mainv", 0);
$g->addCallSite(12, 4, 0, 2, "ab");
$g->addCallSite(13, 1, 0, 5, "cd");
my $h = $m2->define_function("bar", 30, 40);
$h->addAlias("bar", 1);
print "changed=", 0 + !!$m1->union($m2), "\n";
foreach my $key (sort({ $a <=> $b } $m1->keylist())) {
    my $e = $m1->findKey($key);
    print "  $key ", $e->name(), " hit=", $e->hit(), " [",
          join(",", map({ $_ . "=" . $e->alias($_)->count() }
                        sort($e->aliasNames()))), "] sites=",
          join(",", map({ $_ . "=" . ($e->callSiteData($_))[3] }
                        $e->sortedCallSiteKeys())), "\n";
}
print join("/", $m1->get_found_and_hit()), " ",
      join("/", $m1->get_callgraph_found_and_hit()), " ",
      join(",", sort($m1->list_functions())), "\n";
# a union with nothing new changes nothing
print "changed=", 0 + !!$m1->union($m2), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap::union - mismatched entry at one line is ignorable" '
use lcovutil;
lcovutil::parse_ignore_errors("inconsistent");
$SIG{__WARN__} = sub { my $m = shift; $m =~ s/\s+/ /g; print "$m\n" };
my $m1 = FunctionMap->new("foo.c");
$m1->define_function("main", 10, 20)->addAlias("main", 1);
my $m2 = FunctionMap->new("bar.c");
$m2->define_function("other", 10, 20)->addAlias("other", 1);
$m1->union($m2);
print join(",", sort($m1->list_functions())), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap::intersect" '
use lcovutil;
my $m1 = FunctionMap->new("foo.c");
my $f = $m1->define_function("main", 10, 20);
$f->addAlias("main", 3);
$f->addAlias("onlyMine", 1);
$f->addCallSite(12, 4, 0, 1, "ab");
$f->addCallSite(99, 1, 0, 1, "zz");
my $dropped = $m1->define_function("gone", 30, 40);
$dropped->addAlias("gone", 1);
my $m2 = FunctionMap->new("foo.c");
my $g = $m2->define_function("main", 10, 20);
$g->addAlias("main", 4);
$g->addCallSite(12, 4, 0, 2, "ab");
print "changed=", 0 + !!$m1->intersect($m2), "\n";
print join(",", sort({ $a <=> $b } $m1->keylist())), " ",
      join(",", sort($m1->list_functions())), "\n";
my $e = $m1->findKey(10);
print $e->name(), " hit=", $e->hit(), " sites=",
      join(",", map({ $_ . "=" . ($e->callSiteData($_))[3] }
                    $e->sortedCallSiteKeys())), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap::intersect - no common alias drops the entry" '
use lcovutil;
my $m1 = FunctionMap->new("foo.c");
my $f = $m1->define_function("main", 10, 20);
$f->addAlias("main", 3);
my $m2 = FunctionMap->new("foo.c");
$m2->define_function("other", 10, 20)->addAlias("other", 1);
print "changed=", 0 + !!$m1->intersect($m2), " keys=",
      join(",", $m1->keylist()), " names=",
      join(",", sort($m1->list_functions())), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap::difference" '
use lcovutil;
my $m1 = FunctionMap->new("foo.c");
my $f = $m1->define_function("main", 10, 20);
$f->addAlias("main", 3);
$f->addAlias("onlyMine", 1);
$f->addCallSite(12, 4, 0, 1, "ab");
$f->addCallSite(99, 1, 0, 1, "zz");
my $only = $m1->define_function("mineToo", 30, 40);
$only->addAlias("mineToo", 1);
my $m2 = FunctionMap->new("foo.c");
my $g = $m2->define_function("main", 10, 20);
$g->addAlias("main", 4);
$g->addCallSite(12, 4, 0, 2, "ab");
print "changed=", 0 + !!$m1->difference($m2), "\n";
print join(",", sort({ $a <=> $b } $m1->keylist())), "\n";
my $e = $m1->findKey(10);
print $e->name(), " [", join(",", sort($e->aliasNames())), "] sites=",
      join(",", $e->sortedCallSiteKeys()), "\n";
# nothing in common:  nothing changes
my $m3 = FunctionMap->new("foo.c");
$m3->define_function("elsewhere", 70, 80)->addAlias("elsewhere", 1);
print "changed=", 0 + !!$m1->difference($m3), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap::difference - every alias in common drops the entry" '
use lcovutil;
my $m1 = FunctionMap->new("foo.c");
$m1->define_function("main", 10, 20)->addAlias("main", 3);
my $m2 = FunctionMap->new("foo.c");
$m2->define_function("main", 10, 20)->addAlias("main", 4);
print "changed=", 0 + !!$m1->difference($m2), " keys=",
      join(",", $m1->keylist()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "FunctionMap::remove" '
use lcovutil;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addAlias("_Z4mainv", 1);
$map->define_function("bar", 30, 40)->addAlias("bar", 1);
$map->remove($f);
print join(",", $map->keylist()), " ",
      join(",", sort($map->list_functions())), " ",
      join("/", $map->get_found_and_hit()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_error_test "FunctionMap::remove rejects a non-entry" '
use lcovutil;
FunctionMap->new("foo.c")->remove("main");
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# ==============================================================================
# Serialization
#
# The XS backend replaces the generic Storable encoding of Perl with its own
# compact binary format, so the fork IPC hand-off and dclone have to be checked
# directly:  a map, an entry outside any map, and an alias outside any entry.
# ==============================================================================

run_test "Storable round trip of a FunctionMap" '
use lcovutil;
use Storable qw(dclone);
use Scalar::Util qw(refaddr);
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addAlias("main", 3);
$f->addCallSite(12, 4, 0, 1, "ab");
$f->addCallSite(13, 1, 1, 0, "printf");
my $t = $map->define_function("_Z3fooIiEvT_", 30, undef);
$t->addAlias("ab", 5);
$t->addAlias("a{lambda(int)#1}", 0);
$map->define_function("ab", 30, undef);
my $c = dclone($map);
print ref($c), " ", $c->filename(), " ", $c->numFunc(0), "/", $c->numHit(0),
      " ", $c->numFunc(1), "/", $c->numHit(1), " ",
      join("/", $c->get_callgraph_found_and_hit()), "\n";
foreach my $key (sort({ $a <=> $b } $c->keylist())) {
    my $e = $c->findKey($key);
    print "  $key ", $e->name(), " ", $e->file(), " end=",
          defined($e->end_line()) ? $e->end_line() : "undef", " hit=",
          $e->hit(), " [",
          join(",", map({ $_ . "=" . $e->alias($_)->count() }
                        sort($e->aliasNames()))), "] sites=",
          join(",", map({ $_ . "=" . ($e->callSiteData($_))[4] }
                        $e->sortedCallSiteKeys())), "\n";
}
# the name map has to come back too, and still reach the same entries
print join(",", sort($c->list_functions())), " ab=",
      (refaddr($c->findName("ab")) == refaddr($c->findKey(30)) ? 1 : 0), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "Storable round trip of a FunctionMap with site TLAs" '
use lcovutil;
use Storable qw(dclone);
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addCallSite(12, 4, 0, 3, "ab");
$f->addCallSite(13, 1, 0, 0, "cd");
$f->setCallSiteTla(12, 4, 0, undef, "GBC");
my $e = dclone($map)->findKey(10);
print defined($e->callSiteTla(12, 4, 0)) ? $e->callSiteTla(12, 4, 0) : "undef",
      " ",
      defined($e->callSiteTla(13, 1, 0)) ? $e->callSiteTla(13, 1, 0) : "undef",
      " ", $e->numCallSites(), "/", $e->numCallSitesHit(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "Storable round trip of a FunctionMap with an unknown site count" '
use lcovutil;
use Storable qw(dclone);
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addCallSite(12, 4, 0, "-", "ab");
$f->addCallSite(13, 1, 0, 2, "cd");
# the wire format carries a count, so the unknown has to survive as the unknown
#   and not as whatever an int64 sentinel reads back as
my $e = dclone($map)->findKey(10);
print join(",", map({ ($e->callSiteData($_))[3] } $e->sortedCallSiteKeys())),
      " ", $e->numCallSites(), "/", $e->numCallSitesHit(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# 'difference' drops an entry from the line map but leaves the name map
#   holding it, so the wire format has to carry an entry which only a name
#   reaches.  'valuelist' is the line map's view, in scalar context too
run_test "Storable round trip of a FunctionMap after difference" '
use lcovutil;
use Storable qw(dclone);
my $m1 = FunctionMap->new("foo.c");
$m1->define_function("main", 10, 20)->addAlias("main", 3);
$m1->define_function("bar", 30, 40)->addAlias("bar", 1);
my $m2 = FunctionMap->new("foo.c");
$m2->define_function("main", 10, 20)->addAlias("main", 4);
$m1->difference($m2);
my $c = dclone($m1);
print "keys=", join(",", $c->keylist()), " names=",
      join(",", sort($c->list_functions())), " main=",
      $c->findName("main")->line(), " valuelist=", scalar($c->valuelist()),
      "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# Storable only ever thaws into a fresh object, but 'STORABLE_thaw' can be
#   called directly on a live one:  what that object owns is replaced, and an
#   entry handed out by a map is refused - it is the object the map's identity
#   cache returns for every later lookup, so replacing it would change the map
run_xs_only_test "STORABLE_thaw onto initialized function objects" '
use lcovutil;
exit(0) unless $lcovutil::XS_LOADED;
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("main", 10, 20);
$f->addAlias("main", 3);
my $g = $map->define_function("bar", 30, 40);
$g->addAlias("bar", 5);
my $frozen = $g->STORABLE_freeze(0);
my $stand = $f->cloneWithEndLine(1, 1);
$stand->STORABLE_thaw(0, $frozen);
die "standalone entry: " . $stand->name() . "\n"
    unless $stand->name() eq "bar" && $stand->line() == 30;
die "thawed into an entry owned by a map\n"
    if eval { $f->STORABLE_thaw(0, $frozen); 1 };
die "unexpected message: $@" unless $@ =~ /owned by a FunctionMap/;
die "the map lost its entry\n"
    unless $map->findKey(10)->name() eq "main" && $map->findKey(10)->hit() == 3;
my $alias = $stand->alias("bar");
$alias->STORABLE_thaw(0, $map->findKey(10)->alias("main")->STORABLE_freeze(0));
die "alias: " . $alias->name() . "\n"
    unless $alias->name() eq "main" && $alias->count() == 3;
my $other = FunctionMap->new("other.c");
$other->define_function("baz", 1, 2);
$other->STORABLE_thaw(0, $map->STORABLE_freeze(0));
die "map: " . $other->filename() . "\n"
    unless $other->filename() eq "foo.c" &&
    join(",", sort($other->list_functions())) eq "bar,main";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "Storable round trip of a standalone FunctionEntry" '
use lcovutil;
use Storable qw(dclone);
my $map = FunctionMap->new("foo.c");
my $f = $map->define_function("_Z3fooIiEvT_", 30, 40);
$f->addAlias("ab", 5);
my $stand = $f->cloneWithEndLine(1, 1);
my $c = dclone($stand);
print ref($c), " ", $c->name(), " ", $c->file(), " ", $c->line(), "..",
      $c->end_line(), " hit=", $c->hit(), " [",
      join(",", map({ $_ . "=" . $c->alias($_)->count() }
                    sort($c->aliasNames()))), "]\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "Storable round trip of a differential FunctionEntry" '
use lcovutil;
use Storable qw(dclone);
my $map = FunctionMap->new("foo.c");
my $de = FunctionEntry->new("main", $map, 10, 20);
$de->setCountDifferential([7, "GNC"]);
$de->addAliasDifferential("main", [3, "GIC"]);
$de->addAliasDifferential("neverHit", [undef, "UBC"]);
my $c = dclone($de);
print ref($c), " diff=", 0 + !!$c->is_differential(), " tla=", $c->tla(),
      " hit=", ref($c->hit()) ? join(",", map({ defined($_) ? $_ : "undef" }
                                              @{$c->hit()})) : $c->hit(), "\n";
foreach my $name (sort($c->aliasNames())) {
    my $a = $c->alias($name);
    print "  $name diff=", 0 + !!$a->is_differential(), " count=",
          defined($a->count()) ? $a->count() : "undef", " tla=", $a->tla(),
          "\n";
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_test "Storable round trip of a standalone FunctionAlias" '
use lcovutil;
use Storable qw(dclone freeze thaw);
my $a = FunctionAlias->new("sym", 7);
my $c = dclone($a);
print ref($c), " ", $c->name(), " ", $c->count(), " diff=",
      0 + !!$c->is_differential(), " resolved=", 0 + !!$c->is_resolved(), "\n";
$a->set_differential([9, "GNC"]);
my $d = thaw(freeze($a));
print $d->name(), " ", $d->count(), " ", $d->tla(), " diff=",
      0 + !!$d->is_differential(), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

# The map helpers which define_function and difference use, called with the
# arguments those callers never pass:  an entry the map does not own, an
# undefined call site key - and the stale name which 'difference' leaves
# behind, which define_function then fails to relocate.
run_test "FunctionMap helpers on entries and keys the map does not own" '
use lcovutil;
local $SIG{__WARN__} = sub { };
my $m1 = FunctionMap->new("foo.c");
my $m2 = FunctionMap->new("bar.c");
my $f  = $m1->define_function("f", 10, 20);
my $g  = $m2->define_function("g", 50, 60);
print "relocate foreign=", $m1->_relocate($g, 5), " line=", $g->line(), "\n";
# ..including one which starts on the line one of my own entries does
my $k = $m2->define_function("k", 10, 12);
print "relocate foreign same line=", $m1->_relocate($k, 30), " line=",
      $k->line(), " own=", $f->line(), " keys=",
      join(",", sort { $a <=> $b } $m1->keylist()), "\n";
$m1->_registerName("g", $g);
print "registered=", $m1->findName("g")->name(), " line=",
      $m1->findName("g")->line(), " keys=",
      join(",", sort { $a <=> $b } $m1->keylist()), "\n";
print "relocate own=", $m1->_relocate($f, 7), " line=", $f->line(), "\n";
print "remove undef=", $f->_removeSite(undef), " data=",
      scalar(my @d = $f->callSiteData(undef)), "\n";
my $a = FunctionMap->new("foo.c");
my $b = FunctionMap->new("foo.c");
$a->define_function("h", 10, 20);
$b->define_function("h", 10, 20);
$a->difference($b);
@lcovutil::suppress_function_patterns = (qr/^h$/);
my $h = $a->define_function("h", 5, 20);
print "stale=", (defined($h) ? $h->line() : "undef"), " keys=",
      join(",", $a->keylist()), "\n";
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

run_xs_only_test "STORABLE_thaw of a truncated function payload" '
use lcovutil;
exit(0) unless $lcovutil::XS_LOADED;
my $map = FunctionMap->new("foo.c");
my $stand = FunctionEntry->new("lone", $map, 1, 2);
for my $obj ($stand->alias("lone"), $stand, FunctionMap->new("x.c")) {
    my $p = ref($obj);
    # past the magic and the version, but not the payload
    my $cut = substr($obj->STORABLE_freeze(0), 0, 9);
    die "$p thawed a truncated payload\n"
        if eval { $obj->STORABLE_thaw(0, $cut); 1 };
    die "unexpected message: $@"
        unless $@ =~ /^$p binary deserialization failed/;
}
' || { status=1; [ $KEEP_GOING == 0 ] && exit 1; }

if [ $status -eq 0 ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'xs_8' $LOCAL_COVERAGE
fi

exit $status
