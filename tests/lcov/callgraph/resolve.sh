#! /usr/bin/env bash

# Call site data:  the caller-side store, and the callee-side view derived
# from it.
#
# A call site lives on the FunctionEntry which contains it, keyed by its
#   (line, column, ordinal) within that file - so it merges, filters and
#   serializes exactly like a branch or an MC/DC group, and removing a function
#   or a whole file removes its call sites with it, with no cross-file step.
#   The other direction - "which sites called me" - is what the callgraph metric
#   reports, and it is *derived*:  'TraceFile::resolveCallSites' rebuilds it
#   from scratch, after the last merge and the last filter, and nothing merges,
#   serializes or incrementally maintains it.
#
# That makes the ordering an obligation rather than a convention, so it is
#   asserted here as behavior:  reaching 'callers()' before resolution must
#   die and must not answer an empty list, because a metric which dies is
#   debuggable and one which quietly reads 0/0 is not - and handing a resolved
#   report to 'serialize' must die too, since the derived direction holds
#   references from one file's data into another's and Storable would follow
#   them across the fork.
#
# The library is exercised directly, as in 'tests/lcov/xs_test':  these are
#   properties of the containers rather than of any driver, and the '.info'
#   records which carry them are 'format.sh'.  Each fragment runs
#   once, under whichever backend the run selected - the function classes are
#   pure Perl in both, and 'make check' runs the whole suite each way.

set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf resolve.d
    exit 0
fi

# Resolve everything to absolute paths before changing directory:  this test
# shares its directory with 'aliases.sh', so it runs in a private subdirectory
# and the fixed coverage output names ('perlcov.info', 'html_report') cannot
# collide with that test's.
SRCDIR=`pwd`
if [ -f "$LCOV_HOME/lib/lcovutil.pm" ] ; then
    PERLLIB="$LCOV_HOME/lib"
else
    PERLLIB="$LCOV_HOME/lib/lcov"
fi
if [ ! -f "$PERLLIB/lcovutil.pm" ] ; then
    echo "Error: cannot find lcovutil.pm under $LCOV_HOME"
    exit 1
fi

# A bare '--coverage' leaves COVER_DB relative to the invocation directory:
# anchor it so it survives the 'cd' below and so '--clean' still finds it.
if [ "x$COVER" != "x" ] ; then
    case "$COVER_DB" in
        /*) ;;
        *)  COVER_DB="$SRCDIR/$COVER_DB"
            export PYCOV_DB="${COVER_DB}_py"
            PERL_COVER_ARGS="-MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine,-silent,1 "
            COVER="perl $PERL_COVER_ARGS"
            ;;
    esac
fi

rm -rf resolve.d
mkdir resolve.d
cd resolve.d || exit 1

STATUS=0
COUNT=0

fail()
{
    # $1 = scenario label, $2.. = what went wrong
    local label=$1
    shift
    echo "ERROR ($label): $*"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

runFragment()
{
    # runFragment code
    #   run one perl fragment against the library, leaving its exit code in
    #   $RC, its stdout in $OUT and its stderr in file $ERR.  Under
    #   '--coverage' $PERL_COVER_ARGS is set, so the lcovutil.pm lines the
    #   fragment reaches land in this testcase's report
    COUNT=$(expr $COUNT + 1)
    ERR=stderr_$COUNT.log
    OUT=`perl $PERL_COVER_ARGS -I "$PERLLIB" -e "$1" 2>$ERR`
    RC=$?
}

check()
{
    # check label expected code
    #   the fragment prints exactly 'expected' and warns about nothing
    local label=$1
    local expect=$2
    runFragment "$3"
    if [ 0 != $RC ] ; then
        fail $label "fragment exited $RC:" `cat $ERR`
        return
    fi
    if [ -s $ERR ] ; then
        fail $label "unexpected message:" `cat $ERR`
        return
    fi
    if [ "$OUT" != "$expect" ] ; then
        fail $label "expected '$expect' but got '$OUT'"
    fi
}

checkWarn()
{
    # checkWarn label expected message code
    #   the fragment prints exactly 'expected' and warns about 'message':  the
    #   surviving state of an ignored error is as much a part of the contract
    #   as the message is
    local label=$1
    local expect=$2
    local message=$3
    runFragment "$4"
    if [ 0 != $RC ] ; then
        fail $label "fragment exited $RC:" `cat $ERR`
        return
    fi
    if ! grep -q -F -e "$message" $ERR ; then
        fail $label "expected a warning about '$message' but got:" `cat $ERR`
        return
    fi
    if [ "$OUT" != "$expect" ] ; then
        fail $label "expected '$expect' but got '$OUT'"
    fi
}

checkDie()
{
    # checkDie label message code
    #   the fragment fails, saying 'message'
    local label=$1
    local message=$2
    runFragment "$3"
    if [ 0 == $RC ] ; then
        fail $label "expected a failure, but the fragment printed '$OUT'"
        return
    fi
    if ! grep -q -F -e "$message" $ERR ; then
        fail $label "expected a failure saying '$message' but got:" `cat $ERR`
    fi
}

# Every fragment starts with this:  the constructors the library does not
# provide, and the two renderings the expectations are written in.
PRELUDE='
use lcovutil;

sub addFn
{
    # one function in one file of a TraceFile, as a FunctionEntry
    my ($trace, $file, $name, $start, $end) = @_;
    return $trace->data($file)->func()->define_function($name, $start, $end);
}

sub yn
{
    # a "changed" flag as 1 or 0:  false is whatever the boolean expression
    #   which computed it returned, which is the empty string - the addAlias
    #   idiom, since these flags are only ever tested
    return $_[0] ? 1 : 0;
}

sub sites
{
    # every call site of a FunctionEntry, in source order, as
    #   line:column:ordinal=count->callee
    my $entry = shift;
    my @s;
    foreach my $key ($entry->sortedCallSiteKeys()) {
        my ($l, $c, $o, $n, $callee) = $entry->callSiteData($key);
        push(@s, "$l:$c:$o=$n" . "->" . $callee);
    }
    return @s ? join(" ", @s) : "-";
}

sub callers
{
    # every call site which called a FunctionAlias, as
    #   file:caller@line:column:ordinal=count - sorted, because
    #   resolveCallSites walks the report in hash order
    my $alias = shift;
    my @c;
    foreach my $caller ($alias->callers()) {
        my ($entry, $l, $c, $o, $n) = @$caller;
        push(@c, $entry->file() . ":" . $entry->name() . "\@$l:$c:$o=$n");
    }
    return @c ? join(" ", sort(@c)) : "-";
}

sub cls
{
    # how the callers of one FunctionAlias relate to the calls it received, as
    #   class:calls-from-elsewhere:external:deduced - with "-" for a number
    #   which cannot be computed.  See lcovutil::classify_callers
    return join(":",
                map({ defined($_) ? $_ : "-" }
                    lcovutil::classify_callers($_[0])));
}
'

# ----------------------------------------------------------------------
# FunctionEntry::addCallSite and the accessors over it
# ----------------------------------------------------------------------

check 'one_site' '1 1 12:5:0=3->foo' "$PRELUDE"'
my $t = TraceFile->new();
my $e = addFn($t, "a.c", "caller", 10, 20);
my $changed = $e->addCallSite(12, 5, 0, 3, "foo");
print yn($changed), " ", $e->numCallSites(), " ", sites($e);
'

# The CALLS slot is undef until the first site is added - which it never is for
# a report captured without call data - so every accessor has to answer for an
# entry which has none.
check 'no_sites' '0 0 0 -' "$PRELUDE"'
my $t = TraceFile->new();
my $e = addFn($t, "a.c", "caller", 10, 20);
my @keys = $e->callSiteKeys();
my @data = $e->callSiteData("12:5:0");
print $e->numCallSites(), " ", scalar(@keys), " ", scalar(@data), " ", sites($e);
'

check 'unknown_site' '1 0' "$PRELUDE"'
my $t = TraceFile->new();
my $e = addFn($t, "a.c", "caller", 10, 20);
$e->addCallSite(12, 5, 0, 3, "foo");
my @data = $e->callSiteData("12:5:1");
print $e->numCallSites(), " ", scalar(@data);
'

# A site added twice sums, and reports "changed" the way addAlias does it:
# for a site which was not taken and now is, and not for one which was taken
# already.
check 'sum_counts' '1 1 0 12:5:0=6->foo' "$PRELUDE"'
my $t = TraceFile->new();
my $e = addFn($t, "a.c", "caller", 10, 20);
my $first  = $e->addCallSite(12, 5, 0, 0, "foo");
my $hit    = $e->addCallSite(12, 5, 0, 4, "foo");
my $again  = $e->addCallSite(12, 5, 0, 2, "foo");
print yn($first), " ", yn($hit), " ", yn($again), " ", sites($e);
'

# The key is (line, column, ordinal) and it sorts numerically in each field:
# as strings, column 40 would sort before column 7.
check 'source_order' '9:7:0=1->m 9:40:0=2->h 12:5:0=3->g 12:5:1=4->g2 12:9:0=5->k' \
    "$PRELUDE"'
my $t = TraceFile->new();
my $e = addFn($t, "a.c", "caller", 8, 20);
$e->addCallSite(12, 5, 0, 3, "g");
$e->addCallSite(9, 40, 0, 2, "h");
$e->addCallSite(12, 5, 1, 4, "g2");
$e->addCallSite(12, 9, 0, 5, "k");
$e->addCallSite(9, 7, 0, 1, "m");
print sites($e);
'

# Two different callees at one key means the two inputs were built from
# different source:  name both, and keep the first.
checkDie 'mismatch' \
    "call site 12:5:0 in 'caller' calls 'foo' but also 'bar'" "$PRELUDE"'
my $t = TraceFile->new();
my $e = addFn($t, "a.c", "caller", 10, 20);
$e->addCallSite(12, 5, 0, 3, "foo");
$e->addCallSite(12, 5, 0, 1, "bar");
print "not reached";
'

checkWarn 'mismatch_ignored' '0 1 12:5:0=3->foo' \
    "call site 12:5:0 in 'caller' calls 'foo' but also 'bar'" "$PRELUDE"'
lcovutil::parse_ignore_errors("mismatch");
my $t = TraceFile->new();
my $e = addFn($t, "a.c", "caller", 10, 20);
$e->addCallSite(12, 5, 0, 3, "foo");
my $changed = $e->addCallSite(12, 5, 0, 1, "bar");
print yn($changed), " ", $e->numCallSites(), " ", sites($e);
'

# ----------------------------------------------------------------------
# the three set operations, on the entry
# ----------------------------------------------------------------------

check 'union' '1 12:5:0=3->f 13:1:0=0->g 14:1:0=5->h' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $yours = addFn($t, "b.c", "yours", 10, 20);
$mine->addCallSite(12, 5, 0, 1, "f");
$mine->addCallSite(13, 1, 0, 0, "g");
$yours->addCallSite(12, 5, 0, 2, "f");
$yours->addCallSite(14, 1, 0, 5, "h");
my $changed = $mine->unionCallSites($yours);
print yn($changed), " ", sites($mine);
'

# Merging a site which was taken in both is not a change in the addAlias
# sense, but the counts still sum.
check 'union_no_change' '0 12:5:0=3->f' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $yours = addFn($t, "b.c", "yours", 10, 20);
$mine->addCallSite(12, 5, 0, 1, "f");
$yours->addCallSite(12, 5, 0, 2, "f");
my $changed = $mine->unionCallSites($yours);
print yn($changed), " ", sites($mine);
'

check 'union_empty' '0 12:5:0=1->f 0 -' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $empty = addFn($t, "b.c", "empty", 10, 20);
$mine->addCallSite(12, 5, 0, 1, "f");
my $keep = $mine->unionCallSites($empty);
my $both = $empty->unionCallSites(addFn($t, "c.c", "other", 10, 20));
print yn($keep), " ", sites($mine), " ", yn($both), " ", sites($empty);
'

# Two inputs need not agree on the ordinal.  A template instantiated in two
# translation units, an inline shared by two objects, a comdat:  the two
# definitions are aliases of one entry and so share one call site list, and each
# unit numbered the sites at a location from zero.  The ordinal says which of the
# calls at a location this is and is not a name, so the merge matches by callee
# and keeps the pair instead of calling it a conflict.
check 'union_renumber' '0 12:15:0=9->f 12:15:1=6->g' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $yours = addFn($t, "b.c", "yours", 10, 20);
$mine->addCallSite(12, 15, 0, 1, "f");
$mine->addCallSite(12, 15, 1, 2, "g");
$yours->addCallSite(12, 15, 0, 4, "g");
$yours->addCallSite(12, 15, 1, 8, "f");
my $changed = $mine->unionCallSites($yours);
print yn($changed), " ", sites($mine);
'

# A callee I do not have at this location at all is a call I do not have:  it
# takes the lowest ordinal not in use, so that it is a site of its own and the
# ordinals stay dense.
check 'union_new_ordinal' '1 12:15:0=1->f 12:15:1=4->g 12:15:2=3->h' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $yours = addFn($t, "b.c", "yours", 10, 20);
$mine->addCallSite(12, 15, 0, 1, "f");
$mine->addCallSite(12, 15, 2, 3, "h");
$yours->addCallSite(12, 15, 0, 4, "g");
my $changed = $mine->unionCallSites($yours);
print yn($changed), " ", sites($mine);
'

check 'intersect' '1 12:5:0=4->f' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $yours = addFn($t, "b.c", "yours", 10, 20);
$mine->addCallSite(12, 5, 0, 1, "f");
$mine->addCallSite(13, 1, 0, 2, "g");
$yours->addCallSite(12, 5, 0, 3, "f");
$yours->addCallSite(14, 1, 0, 4, "h");
my $changed = $mine->intersectCallSites($yours);
print yn($changed), " ", sites($mine);
'

check 'intersect_no_change' '0 12:5:0=3->f' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $yours = addFn($t, "b.c", "yours", 10, 20);
$mine->addCallSite(12, 5, 0, 1, "f");
$yours->addCallSite(12, 5, 0, 2, "f");
my $changed = $mine->intersectCallSites($yours);
print yn($changed), " ", sites($mine);
'

# Nothing in common leaves me with nothing - but the function itself stays:
# a function with no call sites is not a function with no hits.
check 'intersect_empty' '1 - 0 -' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $empty = addFn($t, "b.c", "empty", 10, 20);
$mine->addCallSite(12, 5, 0, 1, "f");
my $lost = $mine->intersectCallSites($empty);
my $none = $empty->intersectCallSites($mine);
print yn($lost), " ", sites($mine), " ", yn($none), " ", sites($empty);
'

# ..and the intersection matches by callee for the same reason:  a site we both
# have is one we both have, however the two inputs numbered it.
check 'intersect_renumber' '0 12:15:0=9->f 12:15:1=6->g' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $yours = addFn($t, "b.c", "yours", 10, 20);
$mine->addCallSite(12, 15, 0, 1, "f");
$mine->addCallSite(12, 15, 1, 2, "g");
$yours->addCallSite(12, 15, 0, 4, "g");
$yours->addCallSite(12, 15, 1, 8, "f");
my $changed = $mine->intersectCallSites($yours);
print yn($changed), " ", sites($mine);
'

# Two calls to one callee at one location are two calls:  a location where you
# call it once and I call it twice is a location we have one call in common at.
check 'intersect_multiplicity' '1 12:15:0=5->f' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $yours = addFn($t, "b.c", "yours", 10, 20);
$mine->addCallSite(12, 15, 0, 1, "f");
$mine->addCallSite(12, 15, 1, 2, "f");
$yours->addCallSite(12, 15, 0, 4, "f");
my $changed = $mine->intersectCallSites($yours);
print yn($changed), " ", sites($mine);
'

check 'subtract' '1 13:1:0=2->g' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $yours = addFn($t, "b.c", "yours", 10, 20);
$mine->addCallSite(12, 5, 0, 1, "f");
$mine->addCallSite(13, 1, 0, 2, "g");
$yours->addCallSite(12, 5, 0, 3, "f");
$yours->addCallSite(14, 1, 0, 4, "h");
my $changed = $mine->subtractCallSites($yours);
print yn($changed), " ", sites($mine);
'

check 'subtract_disjoint' '0 12:5:0=1->f 0 -' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "mine", 10, 20);
my $yours = addFn($t, "b.c", "yours", 10, 20);
my $empty = addFn($t, "c.c", "empty", 10, 20);
$mine->addCallSite(12, 5, 0, 1, "f");
$yours->addCallSite(14, 1, 0, 4, "h");
my $kept = $mine->subtractCallSites($yours);
my $none = $empty->subtractCallSites($mine);
print yn($kept), " ", sites($mine), " ", yn($none), " ", sites($empty);
'

# ----------------------------------------------------------------------
# the same three operations, reached through FunctionMap:  'lcov -a',
# '--intersect' and '--subtract' see the entries only through these
# ----------------------------------------------------------------------

# The aliases are identical and not hit in either map, so the only thing which
# can report a change here is the call site data.
check 'map_union' '1 12:5:0=3->f 14:1:0=5->h' "$PRELUDE"'
my $m1 = FunctionMap->new("a.c");
my $m2 = FunctionMap->new("a.c");
$m1->define_function("f", 10, 20)->addCallSite(12, 5, 0, 1, "f");
my $other = $m2->define_function("f", 10, 20);
$other->addCallSite(12, 5, 0, 2, "f");
$other->addCallSite(14, 1, 0, 5, "h");
my $changed = $m1->union($m2);
print yn($changed), " ", sites($m1->findKey(10));
'

check 'map_intersect' '1 12:5:0=3->f' "$PRELUDE"'
my $m1 = FunctionMap->new("a.c");
my $m2 = FunctionMap->new("a.c");
my $mine = $m1->define_function("f", 10, 20);
$mine->addCallSite(12, 5, 0, 1, "f");
$mine->addCallSite(13, 1, 0, 7, "g");
$m2->define_function("f", 10, 20)->addCallSite(12, 5, 0, 2, "f");
my $changed = $m1->intersect($m2);
print yn($changed), " ", sites($m1->findKey(10));
'

# 'difference' drops a function whose every alias is also in the other map, so
# the entry only survives - and its call sites only matter - when it has an
# alias of its own.
check 'map_difference' '1 f2 13:1:0=7->g' "$PRELUDE"'
my $m1 = FunctionMap->new("a.c");
my $m2 = FunctionMap->new("a.c");
my $mine = $m1->define_function("f", 10, 20);
$mine->addAlias("f2", 0);
$mine->addCallSite(12, 5, 0, 1, "f");
$mine->addCallSite(13, 1, 0, 7, "g");
$m2->define_function("f", 10, 20)->addCallSite(12, 5, 0, 2, "f");
my $changed = $m1->difference($m2);
my $entry = $m1->findKey(10);
print yn($changed), " ", join(",", sort($entry->aliasNames())), " ", sites($entry);
'

# ----------------------------------------------------------------------
# TraceFile::resolveCallSites
# ----------------------------------------------------------------------

check 'resolve_same_file' '0 1 0 1 1 a.c:caller@12:5:0=3' "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
my $callee = addFn($t, "a.c", "callee", 30, 40);
$caller->addCallSite(12, 5, 0, 3, "callee");
my $before = $callee->alias("callee")->is_resolved() ? 1 : 0;
my ($resolved, $unresolved) = $t->resolveCallSites();
my $alias = $callee->alias("callee");
print "$before $resolved $unresolved ", $alias->is_resolved() ? 1 : 0, " ",
      $alias->numCallers(), " ", callers($alias);
'

check 'resolve_cross_file' '2 0 a.c:caller@12:5:0=3 b.c:other@7:1:0=4' "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
my $other = addFn($t, "b.c", "other", 5, 9);
my $callee = addFn($t, "c.c", "callee", 30, 40);
$caller->addCallSite(12, 5, 0, 3, "callee");
$other->addCallSite(7, 1, 0, 4, "callee");
my ($resolved, $unresolved) = $t->resolveCallSites();
print "$resolved $unresolved ", callers($callee->alias("callee"));
'

# A call to something the report does not describe - the treatment printf gets -
# is dropped:  it cannot say anything about whether the functions this report
# describes were exercised, so it is not counted on its caller either.  The
# callee side of every other function is still resolved, so it answers an empty
# list rather than dying.
check 'resolve_external' '0 0 1 - -' "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
$caller->addCallSite(12, 5, 0, 3, "printf");
my ($resolved, $unresolved) = $t->resolveCallSites();
my $alias = $caller->alias("caller");
print "$resolved $unresolved ", $alias->is_resolved() ? 1 : 0, " ",
      callers($alias), " ", sites($caller);
'

# ..and what is left of the dropped call is the 'c' flag on the function which
# made it:  the edge is there and the report cannot name its far end.  The count
# of the site does not come into that, so the site here was never taken and the
# flag is the same one a taken call leaves.
check 'resolve_external_flag' '0 0 1 -' "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
$caller->addCallSite(12, 5, 0, 0, "printf");
my ($resolved, $unresolved) = $t->resolveCallSites();
print "$resolved $unresolved ", $caller->has_external_callees() ? 1 : 0, " ",
      sites($caller);
'

# The removal is by callee name, wherever the call is written:  two callers in
# two files call the same absent name and both sites go, while a call in one of
# those callers to a name the report does define stays.  So the pass is seen to
# visit more than one function and to leave the rest of a function's sites alone
check 'resolve_external_erased' '1 0 - 13:5:0=4->kept' "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
my $other = addFn($t, "b.c", "other", 5, 9);
my $kept = addFn($t, "a.c", "kept", 30, 40);
$caller->addCallSite(12, 5, 0, 3, "gone");
$caller->addCallSite(13, 5, 0, 4, "kept");
$other->addCallSite(7, 1, 0, 5, "gone");
print join(" ", $t->resolveCallSites()), " ", sites($other), " ",
      sites($caller);
'

# A symbol which more than one file defines - a static function - resolves to
# the definition in the calling file, and is ambiguous from anywhere else.
# Three definitions, not two:  the second one is what puts the symbol into the
# by-file index, and the third has to find it already there.
# The call from 'd.c', which defines no 'helper' at all, is the one which cannot
# be resolved:  no candidate is recorded as having external linkage, which is
# what data captured without it looks like.  Said out loud, because it is a
# caller the callee page should have listed and does not.
# Four definitions rather than three, so that the candidate list the message
# prints is one longer than it prints in full:  the answer is one of them and
# only the reader knows which, but a name a hundred files define must not paste a
# hundred paths into a warning.
checkWarn 'resolve_duplicated' '2 1 a.c:caller@12:5:0=3 - c.c:far@12:5:0=9' \
    "none of them is recorded as having external linkage (capture with '--callgraph-coverage' using gcc 14 or later to record it).  The candidates are: a.c, b.c, c.c, ..." \
    "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
my $mine = addFn($t, "a.c", "helper", 30, 40);
my $yours = addFn($t, "b.c", "helper", 30, 40);
my $theirs = addFn($t, "c.c", "helper", 30, 40);
addFn($t, "e.c", "helper", 30, 40);
my $far = addFn($t, "c.c", "far", 10, 20);
my $stranger = addFn($t, "d.c", "stranger", 10, 20);
$caller->addCallSite(12, 5, 0, 3, "helper");
$far->addCallSite(12, 5, 0, 9, "helper");
$stranger->addCallSite(12, 5, 0, 1, "helper");
my ($resolved, $unresolved) = $t->resolveCallSites();
print "$resolved $unresolved ", callers($mine->alias("helper")), " ",
      callers($yours->alias("helper")), " ", callers($theirs->alias("helper"));
'

# ----------------------------------------------------------------------
# external linkage:  which definition a cross-file call resolves to
# ----------------------------------------------------------------------

# The asymmetric shape, which is what C actually looks like:  one global
# definition plus an unrelated 'static' of the same name in some third file.
# A call from a file which defines no function of that name MUST have gone to
# one with external linkage - a static is unreachable from outside the file
# which defines it - so the static candidate is excluded outright and the one
# external candidate is the answer.  Without the linkage this was ambiguous and
# the global lost its whole callers table.
check 'resolve_linkage_asymmetric' '1 0 b.c:h@5:10:0=4 -' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "f", 30, 40);
my $theirs = addFn($t, "c.c", "f", 30, 40);
my $h = addFn($t, "b.c", "h", 3, 8);
$mine->alias("f")->set_external();
$h->addCallSite(5, 10, 0, 4, "f");
my ($resolved, $unresolved) = $t->resolveCallSites();
print "$resolved $unresolved ", callers($mine->alias("f")), " ",
      callers($theirs->alias("f"));
'

# The rule is additive:  it only ever decides a site which had no answer, so a
# call from a file which DOES define the name still resolves to its own
# definition, even though another candidate is external.
check 'resolve_linkage_prefers_own_file' '1 0 - c.c:g@5:10:0=4' "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "f", 30, 40);
my $theirs = addFn($t, "c.c", "f", 30, 40);
my $g = addFn($t, "c.c", "g", 3, 8);
$mine->alias("f")->set_external();
$g->addCallSite(5, 10, 0, 4, "f");
my ($resolved, $unresolved) = $t->resolveCallSites();
print "$resolved $unresolved ", callers($mine->alias("f")), " ",
      callers($theirs->alias("f"));
'

# Exactly one external candidate, or none of them is the answer.  Two files
# claiming external linkage for one name cannot both be right in one program - no
# such program links - so this is either a report over more than one program or a
# contradiction in the data, rather than a shape to guess at:  it stays unresolved
# and says so.
# What it says is the point of this assertion:  the other unresolvable shape is
# the missing assertion, whose advice is to capture again, and that advice would
# be wrong here - the bit is recorded, twice.  Both messages name the candidate
# files, because the answer is one of them and only the reader knows which.
checkWarn 'resolve_linkage_ambiguous' '0 1 - -' \
    "and 2 of them are recorded as having external linkage - at most one definition of a name can have it in a program which links, so this data covers more than one program, or the linkage records disagree.  The candidates are: a.c, c.c." \
    "$PRELUDE"'
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "f", 30, 40);
my $theirs = addFn($t, "c.c", "f", 30, 40);
my $h = addFn($t, "b.c", "h", 3, 8);
$mine->alias("f")->set_external();
$theirs->alias("f")->set_external();
$h->addCallSite(5, 10, 0, 4, "f");
my ($resolved, $unresolved) = $t->resolveCallSites();
print "$resolved $unresolved ", callers($mine->alias("f")), " ",
      callers($theirs->alias("f"));
'

# Linkage is a property of the symbol, not of the run which captured it, so it
# travels with the definition through a merge:  two captures of the same code,
# only one of which recorded the bit, must agree about it afterwards.  Set-only
# and idempotent, so there is nothing to reconcile in either direction.
check 'linkage_merges' '1 1 1 1' "$PRELUDE"'
my $mine = FunctionMap->new("a.c");
my $yours = FunctionMap->new("a.c");
$mine->define_function("f", 30, 40)->alias("f")->set_external();
$yours->define_function("f", 30, 40);
my $before = $yours->findName("f")->alias("f")->is_external() ? 1 : 0;
$yours->union($mine);
$mine->union($yours);
print 1 - $before, " ", $yours->findName("f")->alias("f")->is_external() ? 1 : 0,
      " ", $mine->findName("f")->alias("f")->is_external() ? 1 : 0, " ",
      $mine->findName("f")->alias("f")->clone()->is_external() ? 1 : 0;
'

# ----------------------------------------------------------------------
# calls whose own call site is gone:  removal, and what it leaves behind
# ----------------------------------------------------------------------

# Removing a file takes its call sites with it - and a call one of them made is
# a fact about the *callee*, which the report may well be keeping.  There is
# nothing left to name the site with afterwards, so what is recorded is only
# that such a call happened, and how many calls the site made:  the 'x' flag of
# the callee's 'FNA:' record and its count, which are
# FunctionAlias::has_external_callers and FunctionAlias::external_calls.  'TraceFile::remove' is the one funnel
# every in-memory removal goes through ('--exclude', '--no-external',
# 'lcov --remove' of an already-read report), so the note is taken there, in the
# last moment the sites exist;  the reader takes the same note for a section it
# skips, and 'format.sh' is where that is asserted through the drivers.
#
# The note is applied in 'resolveCallSites' rather than at once, because the
# callee's file may not have been read yet:  a parallel read gives each worker a
# run of sections, so the removed caller and its callee can be in different
# chunks, and a flag which depended on that partitioning would differ between a
# serial and a forked run of the same input.

# The plain shape:  the only site which called this function is in a file which
# was removed, so the callee's page can say it was called and cannot say from
# where.  The call is in its execution count either way, and the flag counts
# the 4 calls the removed site made, so none of them is left to be deduced.
check 'remove_notes_call' '1 - 2:4:4:0' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
my $t = TraceFile->new();
my $callee = addFn($t, "a.c", "f", 30, 40);
$callee->addAlias("f", 4);
my $caller = addFn($t, "b.c", "g", 3, 8);
$caller->addCallSite(5, 10, 0, 4, "f");
$t->remove("b.c");
$t->resolveCallSites();
my $alias = $callee->alias("f");
print yn($alias->has_external_callers()), " ", callers($alias), " ", cls($alias);
'

# Why the flag has to exist at all:  the sites which are still in the report
# account for every call the callee received, so nothing in the arithmetic can
# show that one more call came from outside it.  The flag says so, and counts
# the one call the removed site made;  the surviving sites already spent the
# execution count, so there is nothing left over to be deduced.
check 'remove_flag_outranks_arithmetic' '1 a.c:h@12:5:0=4 3:0:1:0' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
my $t = TraceFile->new();
my $callee = addFn($t, "a.c", "f", 30, 40);
$callee->addAlias("f", 4);
my $inside = addFn($t, "a.c", "h", 10, 20);
$inside->addCallSite(12, 5, 0, 4, "f");
my $caller = addFn($t, "b.c", "g", 3, 8);
$caller->addCallSite(5, 10, 0, 1, "f");
$t->remove("b.c");
$t->resolveCallSites();
my $alias = $callee->alias("f");
print yn($alias->has_external_callers()), " ", callers($alias), " ", cls($alias);
'

# Whether a removed site was taken does not decide whether there is a flag:  the
# flag says that a boundary crossing edge exists, and not that the edge was
# taken.  So a removed file whose calls were never taken records the crossing
# exactly as the taken call of the scenario above does.  Its count is the sum of
# the removed sites' counts, where a '-' beside a known count adds nothing, as it
# does to a site count:  here 0.
check 'remove_untaken_sites' '1 a.c:h@12:5:0=3 3:0:0:0' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
my $t = TraceFile->new();
my $callee = addFn($t, "a.c", "f", 30, 40);
$callee->addAlias("f", 3);
my $inside = addFn($t, "a.c", "h", 10, 20);
$inside->addCallSite(12, 5, 0, 3, "f");
my $caller = addFn($t, "b.c", "g", 3, 8);
$caller->addCallSite(5, 10, 0, 0, "f");
$caller->addCallSite(6, 10, 0, "-", "f");
$t->remove("b.c");
$t->resolveCallSites();
my $alias = $callee->alias("f");
print yn($alias->has_external_callers()), " ", callers($alias), " ", cls($alias);
'

# The surviving site and the removed one together account for 3 of the 5 calls
# the callee received, so the other 2 are deduced:  the flag and the deduction
# are both made, and each has its own count.
check 'remove_partial' '1 3:3:1:2' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
my $t = TraceFile->new();
my $callee = addFn($t, "a.c", "f", 30, 40);
$callee->addAlias("f", 5);
my $inside = addFn($t, "a.c", "h", 10, 20);
$inside->addCallSite(12, 5, 0, 2, "f");
my $caller = addFn($t, "b.c", "g", 3, 8);
$caller->addCallSite(5, 10, 0, 1, "f");
$t->remove("b.c");
$t->resolveCallSites();
my $alias = $callee->alias("f");
print yn($alias->has_external_callers()), " ", cls($alias);
'

# A removed site whose count is not known leaves the flag without one - a bare
# 'x' - and then how many of the calls the surviving sites do not account for
# came from the removed site cannot be told:  the deduced count is undecidable,
# where the scenario above could compute it.
check 'remove_unknown_count' '1 - x 3:2:-:-' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
my $t = TraceFile->new();
my $callee = addFn($t, "a.c", "f", 30, 40);
$callee->addAlias("f", 4);
my $inside = addFn($t, "a.c", "h", 10, 20);
$inside->addCallSite(12, 5, 0, 2, "f");
my $caller = addFn($t, "b.c", "g", 3, 8);
$caller->addCallSite(5, 10, 0, "-", "f");
$t->remove("b.c");
$t->resolveCallSites();
my $alias = $callee->alias("f");
my $calls = $alias->external_calls();
print yn($alias->has_external_callers()), " ", defined($calls) ? $calls : "-",
      " ", $alias->flags(), " ", cls($alias);
'

# A call to a name the removed file defines itself went to that definition - the
# rule every site is resolved by - and that definition is being removed too, so
# there is no surviving callee for it to be a fact about.  Nothing is noted:
# otherwise an unrelated definition of the same name in another file would
# answer for the call once the file which owned it was gone, and would be
# reported as called by something that never called it.
check 'remove_own_definition' '0 0:0:0:0' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "f", 30, 40);
$mine->addAlias("f", 0);
$mine->alias("f")->set_external();
my $theirs = addFn($t, "b.c", "f", 30, 40);
$theirs->addAlias("f", 4);
my $caller = addFn($t, "b.c", "g", 3, 8);
$caller->addCallSite(5, 10, 0, 4, "f");
$t->remove("b.c");
$t->resolveCallSites();
my $alias = $mine->alias("f");
print yn($alias->has_external_callers()), " ", cls($alias);
'

# Removal can happen after a resolution, so the note is not consumed by the pass
# which applies it:  the next pass has to reach the same conclusion, and the
# caller which was listed before the removal must be gone from the list after
# it.
check 'remove_after_resolve' '1 b.c:g@5:10:0=4 -' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
my $t = TraceFile->new();
my $callee = addFn($t, "a.c", "f", 30, 40);
$callee->addAlias("f", 4);
my $caller = addFn($t, "b.c", "g", 3, 8);
$caller->addCallSite(5, 10, 0, 4, "f");
$t->resolveCallSites();
my $before = callers($callee->alias("f"));
$t->remove("b.c");
$t->resolveCallSites();
print yn($callee->alias("f")->has_external_callers()), " $before ",
      callers($callee->alias("f"));
'

# The ordinary shape of a call out of the report - a library function, or a
# translation unit which was never captured - has no callee here to carry a
# flag, and neither has a name several files define and the linkage does not
# choose between.  Both are silent:  there is no one alias for the flag to go
# on, nothing the user could do about it, and no site left to report as
# unresolved either.
check 'remove_callee_not_in_report' '0 0' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
my $t = TraceFile->new();
addFn($t, "a.c", "unrelated", 30, 40);
my $caller = addFn($t, "b.c", "g", 3, 8);
$caller->addCallSite(5, 10, 0, 4, "printf");
$t->remove("b.c");
my ($resolved, $unresolved) = $t->resolveCallSites();
print "$resolved $unresolved";
'

check 'remove_callee_ambiguous' '0 0 0 0' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "f", 30, 40);
my $theirs = addFn($t, "c.c", "f", 30, 40);
my $caller = addFn($t, "b.c", "g", 3, 8);
$caller->addCallSite(5, 10, 0, 4, "f");
$t->remove("b.c");
my ($resolved, $unresolved) = $t->resolveCallSites();
print "$resolved $unresolved ", yn($mine->alias("f")->has_external_callers()),
      " ", yn($theirs->alias("f")->has_external_callers());
'

# ..and it is resolved by exactly the rule a surviving site is resolved by, so
# the linkage decides it:  a call from a file which defines no function of that
# name went to the one definition which is reachable from outside its own file,
# and the unrelated static of the same name is not it.
check 'remove_resolves_by_linkage' '1 0' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
my $t = TraceFile->new();
my $mine = addFn($t, "a.c", "f", 30, 40);
$mine->addAlias("f", 4);
$mine->alias("f")->set_external();
my $theirs = addFn($t, "c.c", "f", 30, 40);
$theirs->addAlias("f", 0);
my $caller = addFn($t, "b.c", "g", 3, 8);
$caller->addCallSite(5, 10, 0, 4, "f");
$t->remove("b.c");
$t->resolveCallSites();
print yn($mine->alias("f")->has_external_callers()), " ",
      yn($theirs->alias("f")->has_external_callers());
'

# The note is part of the report, so a merge keeps both sides of it:  the callee
# can be in a file only the other side has - which is the whole reason the note
# is not applied where it is taken - and the operation does not matter, since
# the call was made whether or not this operation keeps the file it was made
# from.  The count comes with it.
check 'remove_note_merges' 'union=1:4 intersect=1:4' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
sub scenario
{
    my ($label, $op) = @_;
    my $yours = TraceFile->new();
    addFn($yours, "a.c", "f", 30, 40)->addAlias("f", 4);
    my $caller = addFn($yours, "b.c", "g", 3, 8);
    $caller->addCallSite(5, 10, 0, 4, "f");
    $yours->remove("b.c");
    my $mine = TraceFile->new();
    my $callee = addFn($mine, "a.c", "f", 30, 40);
    $callee->addAlias("f", 4);
    $mine->merge_tracefile($yours, $op);
    $mine->resolveCallSites();
    return "$label=" . yn($callee->alias("f")->has_external_callers()) . ":" .
        $callee->alias("f")->external_calls();
}
print join(" ", scenario("union", TraceInfo::UNION()),
                scenario("intersect", TraceInfo::INTERSECT()));
'

# ..and it crosses the fork with the report, for the same reason:  a worker
# which read the removed caller sends the note back to the parent, which is
# where the callee's flag is set.
check 'remove_note_serializes' '1:4' "$PRELUDE"'
$lcovutil::callgraph_coverage = 1;
my $t = TraceFile->new();
my $caller = addFn($t, "b.c", "g", 3, 8);
$caller->addCallSite(5, 10, 0, 4, "f");
$t->remove("b.c");
$t->serialize("noted.dat");
my $child = TraceFile->deserialize("noted.dat");
my $parent = TraceFile->new();
my $callee = addFn($parent, "a.c", "f", 30, 40);
$callee->addAlias("f", 4);
$parent->merge_tracefile($child, TraceInfo::UNION());
$parent->resolveCallSites();
print yn($callee->alias("f")->has_external_callers()), ":",
      $callee->alias("f")->external_calls();
'

# The count of the flag merges as the counts of the sites it stands for would
# have:  known counts add, an unknown one beside a known one adds nothing, and
# only a flag which is unknown on every side stays unknown.  A side with no flag
# contributes nothing, and the flag of the result is set if either side's is.
check 'external_calls_merge' \
    'union=x5,x3,x,x2,none intersect=x5,x3,x,x2,none' "$PRELUDE"'
sub scenario
{
    my ($op, $mine, $yours) = @_;
    my $m = FunctionMap->new("a.c");
    my $y = FunctionMap->new("a.c");
    my $fm = $m->define_function("f", 30, 40);
    my $fy = $y->define_function("f", 30, 40);
    $fm->alias("f")->add_external_calls($mine) if defined($mine);
    $fy->alias("f")->add_external_calls($yours) if defined($yours);
    $op eq "union" ? $m->union($y) : $m->intersect($y);
    my $flags = $m->findName("f")->alias("f")->flags();
    return $flags eq "" ? "none" : $flags;
}
print join(" ",
    map({
            my $op = $_;
            "$op=" .
            join(",",
                 scenario($op, 2, 3), scenario($op, "-", 3),
                 scenario($op, "-", "-"), scenario($op, undef, 2),
                 scenario($op, undef, undef));
    } ("union", "intersect")));
'

# A deduced caller is recomputed from the merged data rather than merged as a
# flag, so a tracefile which lacked the call sites of another deduces calls
# which the merge with that other then accounts for:  'partial' is the callee's
# file alone, and 'complete' adds the file its 4 calls came from.  A call which
# no merged tracefile has a site for stays deduced:  'uninstrumented' adds a
# callee entered 3 more times and a file with a site for 1 of them.
check 'deduced_merge' 'partial=2:4:0:4 complete=1:0:0:0 uninstrumented=3:2:0:2' \
    "$PRELUDE"'
my $mine = TraceFile->new();
my $callee = addFn($mine, "a.c", "f", 30, 40);
$callee->addAlias("f", 4);
$mine->resolveCallSites();
my $partial = cls($callee->alias("f"));
my $yours = TraceFile->new();
addFn($yours, "b.c", "g", 3, 8)->addCallSite(5, 10, 0, 4, "f");
$mine->merge_tracefile($yours, TraceInfo::UNION());
$mine->resolveCallSites();
my $complete = cls($callee->alias("f"));
my $other = TraceFile->new();
addFn($other, "a.c", "f", 30, 40)->addAlias("f", 3);
addFn($other, "c.c", "k", 3, 8)->addCallSite(5, 10, 0, 1, "f");
$mine->merge_tracefile($other, TraceInfo::UNION());
$mine->resolveCallSites();
print "partial=$partial complete=$complete uninstrumented=",
      cls($mine->data("a.c")->func()->findName("f")->alias("f"));
'

# ----------------------------------------------------------------------
# how the callers of a callee relate to the calls it actually received
# ----------------------------------------------------------------------

# Every site in the report which named this symbol is on its caller list by now,
# with the file it is in and the count it was taken:  those we know exactly.
# What cannot be known is who made the REST of the calls - the symbol was
# entered more often than the sites account for - so the classification is
# "which of the two kinds of caller does this function have", with the
# unattributable remainder as a count.  Derived from data the report already
# carries, so it needs no record of its own and is right after any merge.
#
# 0 = never called, 1 = every call accounted for, 2 = called, and by nothing
# here, 3 = both, 4 = an unknown site count makes it undecidable.
check 'classify_callers' \
    'none=0:0:0:0 internal=1:0:0:0 external=2:3:0:3 both=3:3:0:3 undecidable=4:-:0:- overcount=1:0:0:0 dash_accounted=1:0:0:0 dash_short=4:-:0:-' \
    "$PRELUDE"'
sub scenario
{
    # one callee with the given execution count, called from one caller at the
    #   given per-site counts
    my ($label, $calleeCount, @siteCounts) = @_;
    my $t = TraceFile->new();
    my $callee = addFn($t, "a.c", "callee", 30, 40);
    $callee->addAlias("callee", $calleeCount);
    my $caller = addFn($t, "a.c", "caller", 10, 20);
    my $ordinal = 0;
    $caller->addCallSite(12, 5, $ordinal++, $_, "callee") foreach (@siteCounts);
    $t->resolveCallSites();
    return "$label=" . cls($callee->alias("callee"));
}
print join(" ",
    # entered zero times:  nothing called it, so a "-" among its sites was
    #   taken zero times too and there is nothing undecidable about it
    scenario("none", 0),
    scenario("internal", 3, 3),
    # the shape of "main", of a call through a function pointer, and of a caller
    #   in a translation unit which was never captured
    scenario("external", 3),
    scenario("both", 5, 2),
    scenario("undecidable", 5, "-"),
    # more calls recorded than entries:  not diagnosed, since a merge of runs
    #   which disagree can produce it, and everything is accounted for either way
    scenario("overcount", 2, 5),
    # a "-" beside sites which already account for every entry decides nothing
    scenario("dash_accounted", 3, 3, "-"),
    scenario("dash_short", 5, 2, "-"));
'

# Resolution starts by forgetting every caller, so it can run again after
# anything which invalidates the report instead of patching what it built.
check 'resolve_idempotent' '1 0 1 1 0 1 a.c:caller@12:5:0=3' "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
my $callee = addFn($t, "a.c", "callee", 30, 40);
$caller->addCallSite(12, 5, 0, 3, "callee");
my ($r1, $u1) = $t->resolveCallSites();
my $first = $callee->alias("callee")->numCallers();
my ($r2, $u2) = $t->resolveCallSites();
my $alias = $callee->alias("callee");
print "$r1 $u1 $first $r2 $u2 ", $alias->numCallers(), " ", callers($alias);
'

# The caller side is one entry, but the callee side is one alias:  a call names
# the symbol it calls, and the other aliases of that same function are not
# called by it.
check 'resolve_alias' '1 0 1 a.c:caller@12:5:0=3 0 -' "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
my $callee = addFn($t, "a.c", "t<int>", 30, 40);
$callee->addAlias("t<char>", 0);
$caller->addCallSite(12, 5, 0, 3, "t<char>");
my ($resolved, $unresolved) = $t->resolveCallSites();
print "$resolved $unresolved ", $callee->alias("t<char>")->numCallers(), " ",
      callers($callee->alias("t<char>")), " ",
      $callee->alias("t<int>")->numCallers(), " ",
      callers($callee->alias("t<int>"));
'

# One location with more than one callee:  a virtual call dispatches to
# whichever override the object has, so the site is keyed (line, column,
# ordinal) with the callee as payload, and resolution has to attribute each
# ordinal to its own callee - one caller each, with that target's own count.
check 'resolve_multi_target' '2 0 1 a.c:dispatch@6:15:0=5 1 a.c:dispatch@6:15:1=0' \
    "$PRELUDE"'
my $t = TraceFile->new();
my $dispatch = addFn($t, "a.c", "dispatch", 4, 7);
my $base = addFn($t, "a.c", "B::f", 1, 1);
my $derived = addFn($t, "a.c", "D::f", 2, 2);
$dispatch->addCallSite(6, 15, 0, 5, "B::f");
$dispatch->addCallSite(6, 15, 1, 0, "D::f");
my ($resolved, $unresolved) = $t->resolveCallSites();
print "$resolved $unresolved ", $base->alias("B::f")->numCallers(), " ",
      callers($base->alias("B::f")), " ",
      $derived->alias("D::f")->numCallers(), " ",
      callers($derived->alias("D::f"));
'

# The same shape with the targets in one FunctionEntry, which is what a call in
# a template body looks like:  one definition, one entry, an alias per
# instantiation - and the callee side is held per alias, so the two targets of
# the one site are two separate views of the same entry.  Both are called from
# the one place, which is what 'collapse_callgraph_alias' merges, so the
# aliases are kept apart here (see 'collapse.sh').
check 'resolve_multi_alias' '2 0 1 a.c:caller@12:5:0=3 1 a.c:caller@12:5:1=4' \
    "$PRELUDE"'
$lcovutil::collapse_callgraph_alias = 0;
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
my $callee = addFn($t, "a.c", "t<int>", 30, 40);
$callee->addAlias("t<char>", 0);
$caller->addCallSite(12, 5, 0, 3, "t<int>");
$caller->addCallSite(12, 5, 1, 4, "t<char>");
my ($resolved, $unresolved) = $t->resolveCallSites();
print "$resolved $unresolved ", $callee->alias("t<int>")->numCallers(), " ",
      callers($callee->alias("t<int>")), " ",
      $callee->alias("t<char>")->numCallers(), " ",
      callers($callee->alias("t<char>"));
'

# ----------------------------------------------------------------------
# the summary counts:  found and hit, at each of the three levels
# ----------------------------------------------------------------------

# "Hit" is counted from the sites rather than maintained beside them, because a
# count can change under merge, filtering or subtraction - so it is asked of the
# data every time, and asking an entry which has no sites has to answer 0 and
# not die.
check 'entry_totals' '3 2 0 0' "$PRELUDE"'
my $t = TraceFile->new();
my $e = addFn($t, "a.c", "caller", 10, 20);
my $none = addFn($t, "a.c", "leaf", 30, 40);
$e->addCallSite(12, 5, 0, 3, "f");
$e->addCallSite(12, 9, 0, 0, "g");
$e->addCallSite(13, 1, 0, 1, "h");
print $e->numCallSites(), " ", $e->numCallSitesHit(), " ",
      $none->numCallSites(), " ", $none->numCallSitesHit();
'

# The per-file totals are the sum over the functions of the file, which is what
# 'FNCF'/'FNCH' are - so a file whose functions have no sites is 0/0 rather than
# absent, and no resolution is needed to compute either:  both are caller-side.
check 'map_totals' '4 2' "$PRELUDE"'
my $m = FunctionMap->new("a.c");
my $f = $m->define_function("f", 10, 20);
my $g = $m->define_function("g", 30, 40);
$m->define_function("leaf", 50, 60);
$f->addCallSite(12, 5, 0, 3, "x");
$f->addCallSite(12, 9, 0, 0, "y");
$g->addCallSite(33, 1, 0, 7, "z");
$g->addCallSite(34, 1, 0, 0, "w");
my ($found, $hit) = $m->get_callgraph_found_and_hit();
print "$found $hit";
'

# ..and the TraceInfo accessors, which are what every summary and the '.info'
# writer go through, are that pair for the file's own functions.  A file with no
# functions at all still answers.
check 'trace_totals' '2 1 0 0' "$PRELUDE"'
my $t = TraceFile->new();
my $e = addFn($t, "a.c", "caller", 10, 20);
$e->addCallSite(12, 5, 0, 3, "f");
$e->addCallSite(12, 9, 0, 0, "g");
my $empty = $t->data("b.c");
print $t->data("a.c")->callgraph_found(), " ", $t->data("a.c")->callgraph_hit(), " ",
      $empty->callgraph_found(), " ", $empty->callgraph_hit();
'

# ----------------------------------------------------------------------
# the ordering obligations, as behavior
# ----------------------------------------------------------------------

checkDie 'callers_unresolved' \
    "the call sites of 'callee' have not been resolved" "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
my $callee = addFn($t, "a.c", "callee", 30, 40);
$caller->addCallSite(12, 5, 0, 3, "callee");
print $callee->alias("callee")->is_resolved() ? "resolved " : "unresolved ";
print callers($callee->alias("callee"));
'

checkDie 'add_caller_unresolved' \
    "cannot add a caller of 'callee' before resolving" "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
my $callee = addFn($t, "a.c", "callee", 30, 40);
$callee->alias("callee")->add_caller($caller, 12, 5, 0, 3);
print "not reached";
'

# The caller side is the wire format precisely so that a resolved report never
# has to cross a fork:  it holds references from one file into another, and a
# worker would send back a copy of half the report.
check 'serialize_unresolved' 'wrote' "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
$caller->addCallSite(12, 5, 0, 3, "printf");
$t->serialize("unresolved.dat");
print -s "unresolved.dat" ? "wrote" : "empty";
'

checkDie 'serialize_resolved' \
    'internal error: call sites were resolved before serialization' "$PRELUDE"'
my $t = TraceFile->new();
my $caller = addFn($t, "a.c", "caller", 10, 20);
$caller->addCallSite(12, 5, 0, 3, "printf");
$t->resolveCallSites();
$t->serialize("resolved.dat");
print "not reached";
'

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'resolve' $LOCAL_COVERAGE 0
fi

exit $STATUS
