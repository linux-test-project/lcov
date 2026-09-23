#! /usr/bin/env bash

# '--callgraph-coverage' on data which has no call sites in it.
#
# This one is not knowable at option time - the request is legal and the answer
#   is a property of the data - so it is the 'empty' error, raised once, in the
#   parent, after the last merge and the last filter.  Three things about where
#   it goes are asserted here rather than left to the reader of the code:
#
#   - the condition is that *nothing anywhere* has a site, not that some file has
#     none.  A file with no call sites is entirely ordinary:  a header of inline
#     definitions, a leaf translation unit, a file whose functions were all
#     filtered out.  A check per file would fire on every report which has one.
#
#   - never in a child, never per chunk.  A worker which was handed a segment
#     with no calls in it has not discovered anything - the rest of the report
#     went to the other workers - so under '--parallel' the message still has to
#     appear exactly once, from the parent.
#
#   - ignoring it turns the metric off.  Otherwise every summary grows a callee
#     column reading 0/0 on a report where the metric was never measured, which
#     invites the reader to conclude the code makes no calls.
#
#   - the condition is "no callgraph information", not "no call site".  Resolving
#     a call whose far end is outside the boundary leaves a crossing rather than
#     a site, so a report can hold nothing but crossings:  it has no site, and it
#     does say which functions call out and which are called in.
#
# And it is checked after filtering, not before:  a report whose only call sites
#   were inside a function which '--erase-functions' removed is a report with no
#   call sites, and the user is owed the same message as if they had never been
#   captured.

source ../../common.tst

# This directory is shared with 'aliases.sh', which removes '*.info' and '*.log'
# as it starts, so run in a private subdirectory - as 'resolve.sh' does.
SRCDIR=`pwd`
if [ "x$COVER" != "x" ] ; then
    # a bare '--coverage' leaves COVER_DB relative to the invocation directory
    case "$COVER_DB" in
        /*) ;;
        *)  COVER_DB="$SRCDIR/$COVER_DB"
            export PYCOV_DB="${COVER_DB}_py"
            PERL_COVER_ARGS="-MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine,-silent,1 "
            COVER="perl $PERL_COVER_ARGS"
            ;;
    esac
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf empty.d
    exit 0
fi

rm -rf empty.d
mkdir empty.d
cd empty.d || exit 1
mkdir proj

LCOV_OPTS="$PARALLEL $PROFILE"

STATUS=0

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

EMPTY_MSG="--callgraph-coverage is enabled but no call-site data was found in any input file."

runCmd()
{
    # runCmd label command
    local label=$1
    eval "$2" > $label.log 2>&1
    RC=$?
    cat $label.log
}

expectFail()
{
    # expectFail label command
    #   the run fails with the one message, and says it exactly once - which is
    #   the assertion that matters under '--parallel'
    local label=$1
    runCmd $label "$2"
    if [ 0 == $RC ] ; then
        fail $label "expected a failure, but the command succeeded"
        return
    fi
    local n=`grep -c -F -e "ERROR: (empty) $EMPTY_MSG" $label.log`
    if [ 1 != "$n" ] ; then
        fail $label "expected the message once, found it $n times:" \
            `grep -E 'ERROR|WARNING' $label.log`
    fi
}

expectQuiet()
{
    # expectQuiet label command
    #   the run succeeds and says nothing about callgraph coverage:  this is the
    #   half which is easy to get wrong, and there are more ways to be here than
    #   to be in the failing case
    local label=$1
    runCmd $label "$2"
    if [ 0 != $RC ] ; then
        fail $label "the command failed:" `grep -E 'ERROR' $label.log`
        return
    fi
    if grep -q -F -e "$EMPTY_MSG" $label.log ; then
        fail $label "reported missing call data on data which has some"
    fi
}

expectWarn()
{
    # expectWarn label command
    local label=$1
    runCmd $label "$2"
    if [ 0 != $RC ] ; then
        fail $label "the command failed:" `grep -E 'ERROR' $label.log`
        return
    fi
    if ! grep -q -F -e "WARNING: (empty) $EMPTY_MSG" $label.log ; then
        fail $label "expected a warning saying '$EMPTY_MSG'"
    fi
}

cat >proj/a.c <<'EOF'
int helper(int x)
{
    return x + 1;
}

int caller(int n)
{
    return helper(n);
}
EOF

cat >proj/b.c <<'EOF'
int leaf(int x)
{
    return x * 2;
}
EOF

# one file with a call site..
cat >sites.info <<'EOF'
TN:empty
SF:proj/a.c
FNL:0,1,4
FNA:0,1,helper
FNL:1,6,9
FNA:1,1,caller
FNC:1,8,12,0,1,helper
FNF:2
FNH:2
FNCF:1
FNCH:1
DA:1,1
DA:3,1
DA:6,1
DA:8,1
LF:4
LH:4
end_of_record
EOF

# ..and one with none, which is what a leaf translation unit looks like
cat >nosites.info <<'EOF'
TN:empty
SF:proj/b.c
FNL:0,1,4
FNA:0,3,leaf
FNF:1
FNH:1
DA:1,3
DA:3,3
LF:2
LH:2
end_of_record
EOF

# the same file twice, to have a second site-less input for the parallel case
sed -e 's/proj\/b.c/proj\/c.c/' nosites.info > nosites2.info
cp proj/b.c proj/c.c

# A report which holds no site and is not empty:  what a run which resolved its
#   calls wrote after the far end of each of them turned out to be outside the
#   boundary.  Both halves of that are here - the 'c' on the function which
#   called out, and the 'x' on the alias which was called from outside - because
#   a report can carry either without the other
cat >crossings.info <<'EOF'
TN:empty
SF:proj/a.c
FNL:0c,6,9
FNA:0e,1,caller
FNF:1
FNH:1
FNCF:0
FNCH:0
DA:6,1
DA:8,1
LF:2
LH:2
end_of_record
SF:proj/b.c
FNL:0,1,4
FNA:0ex,3,leaf
FNF:1
FNH:1
FNCF:0
FNCH:0
DA:1,3
DA:3,3
LF:2
LH:2
end_of_record
EOF

# ..and the callee half on its own, so that reaching it does not depend on the
#   order the files are visited in
sed -n '/^SF:proj\/b.c/,/^end_of_record/p' crossings.info > called.tmp
( echo 'TN:empty' ; cat called.tmp ) > called.info
rm -f called.tmp

# ----------------------------------------------------------------------
echo "*** 1. nothing anywhere has a call site"
# ----------------------------------------------------------------------
expectFail lcov_empty \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph -a nosites.info -o empty.info"

expectFail genhtml_empty \
    "$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph -o html_empty nosites.info"

# '--list' and '--summary' report the same numbers as a write does, so they ask
#   the same question at the same point and have to give the same answer
expectFail list_empty \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --list nosites.info"

expectFail summary_empty \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --summary nosites.info"

# Two site-less inputs, in separate workers:  the message is still one message.
#   Each worker read a segment with no calls in it and has nothing to say about
#   the report as a whole - only the parent, after the merge, does
expectFail parallel_empty \
    "$COVER $LCOV_TOOL --parallel 0 $PROFILE --callgraph -a nosites.info -a nosites2.info -o empty2.info"

# ----------------------------------------------------------------------
echo "*** 2. ignoring it turns the metric off"
# ----------------------------------------------------------------------
expectWarn lcov_ignored \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph -a nosites.info -o ignored.info --ignore-errors empty"
if [ -f ignored.info ] ; then
    # not even the totals:  a run which was told the metric is off writes no
    #   record of it at all, rather than 'FNCF:0'
    if grep -q -E '^FNC' ignored.info ; then
        fail lcov_ignored "call records were written for a metric which is off:"
        grep -E '^FNC' ignored.info
    fi
    if ! grep -q -E '^FNA:0,3,leaf' ignored.info ; then
        fail lcov_ignored "the rest of the function data did not survive"
    fi
fi

expectWarn genhtml_ignored \
    "$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph -o html_ignored nosites.info --ignore-errors empty"
if [ ! -f html_ignored/index.html ] ; then
    fail genhtml_ignored "no report was written"
fi

# ----------------------------------------------------------------------
echo "*** 3. the cases which must not fire"
# ----------------------------------------------------------------------
# One file with sites and one without is the normal shape of a real report
expectQuiet mixed \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph -a sites.info -a nosites.info -o mixed.info"
if [ -f mixed.info ] ; then
    if ! grep -q -E '^FNC:1,8,12,0,1,helper' mixed.info ; then
        fail mixed "the call site did not survive the merge:"
        grep -E '^FNC' mixed.info
    fi
    # ..and the totals go to the file which has a measurement behind them and to
    #   no other.  'b.c' holds no site, nothing in the report calls the one
    #   function it defines, and neither of the boundary-crossing flags is on it:
    #   nothing here was measured about its calls, so 'FNCF:0' would be a claim
    #   the data does not support - the reader would take it for "this file makes
    #   no calls", which is not the same thing as "nobody looked"
    #   (FunctionMap::hasCallgraphData)
    if [ 1 != `grep -c -E '^FNCF:' mixed.info` ] ; then
        fail mixed "expected the call total in exactly one section:"
        grep -E '^(SF|FNCF|FNCH):' mixed.info
    fi
    if ! grep -q -E '^FNCF:1' mixed.info || grep -q -E '^FNCF:0' mixed.info ; then
        fail mixed "the wrong section carries the call total:"
        grep -E '^(SF|FNCF|FNCH):' mixed.info
    fi
fi

# ..and genhtml draws the same line.  'b.c's 'leaf' was entered three times and
#   nothing in the report calls it:  in a file whose calls were measured that
#   would say that its caller is outside the boundary of the report, which is
#   worth a page of its own.  Here it says nothing - the caller is as likely to
#   be 'b.c' itself, and no record of it was ever written - so the function has
#   nothing to show and the file gets neither call site page.  'a.c', which was
#   measured, keeps both of its own
expectQuiet mixed_html \
    "$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph -o html_mixed mixed.info"
for page in callers callees ; do
    if [ -f html_mixed/proj/b.c.$page.html ] ; then
        fail mixed_html \
            "a file whose calls were never measured grew a $page page"
    fi
    if [ ! -f html_mixed/proj/a.c.$page.html ] ; then
        fail mixed_html "the file which has call data lost its $page page"
    fi
done
for view in b.c.func.html b.c.gcov.html ; do
    if grep -q -E 'b\.c\.call(ers|ees)\.html' html_mixed/proj/$view ; then
        fail mixed_html "$view links to a call site page which does not exist"
    fi
done
# ..and nowhere does the report say of 'leaf' what it cannot know:  that the call
#   it received came from outside the callgraph boundary
if grep -q -F -e 'external callers only' html_mixed/proj/b.c.func.html ; then
    fail mixed_html "a function of an unmeasured file claims external callers"
fi

# ..and the same inputs without the option say nothing either way
expectQuiet nocallee \
    "$COVER $LCOV_TOOL $LCOV_OPTS -a nosites.info -o nocallee.info"

# Erasing the callee takes the call to it with it:  the report no longer
#   describes 'helper', so the call is a call out of the report like any other
#   and the default is to drop it.  Not the empty-data error, though, because
#   that is decided on the input - which did have the site
expectQuiet erase_other \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph -a sites.info -o erase_other.info --erase-functions helper"
if [ -f erase_other.info ] &&
   grep -q -E '^FNC:' erase_other.info ; then
    fail erase_other "the call to the erased function was kept:"
    grep -E '^FNC' erase_other.info
fi

# ..and what is left of the call is the 'c' flag on the leader of the function
#   which made it:  the edge is there, and the report cannot name its far end
if [ -f erase_other.info ] &&
   ! grep -q -E '^FNL:[0-9]+c,' erase_other.info ; then
    fail erase_other "the crossing the erasure created was not recorded:"
    grep -E '^FNL' erase_other.info
fi

# Reading that report back is the same question again, and has to get the same
#   answer:  no site in it, and not nothing in it.  A count of sites says
#   'empty' here, which would both report a measured file as unmeasured and -
#   because the flags are written only while the metric is on - drop the
#   crossings on the way out, so the report would decay a little every time it
#   was merged
for f in crossings called ; do
    expectQuiet ${f}_roundtrip \
        "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph -a $f.info -o ${f}_rt.info"
done
if [ -f crossings_rt.info ] ; then
    if ! grep -q -E '^FNL:0c,' crossings_rt.info ; then
        fail crossings_roundtrip "the caller's crossing did not survive:" \
            `grep -E '^FNL' crossings_rt.info`
    fi
    # a bare 'x' does not say how many calls came from outside, so whether
    #   any more did cannot be told, and there is no 'd'
    if ! grep -q -x -e 'FNA:0ex,3,leaf' crossings_rt.info ; then
        fail crossings_roundtrip "the callee's crossing did not survive:" \
            `grep -E '^FNA' crossings_rt.info`
    fi
fi
# ..and the callee half alone, which is the one the file order can hide
if [ -f called_rt.info ] && ! grep -q -x -e 'FNA:0ex,3,leaf' called_rt.info ; then
    fail called_roundtrip "the callee's crossing did not survive on its own:" \
        `grep -E '^FN' called_rt.info`
fi

# ----------------------------------------------------------------------
echo "*** 4. checked after filtering, not before"
# ----------------------------------------------------------------------
# The call sites of this report are all inside 'caller'.  Erasing it leaves a
#   report with none, which is the same situation as never having captured them
#   - so it is the same message, even though the input file did have call
#   records in it
expectFail erase_caller \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph -a sites.info -o erased.info --erase-functions caller"

# ----------------------------------------------------------------------
echo "*** 5. html2lcov, which recovers what the report shows"
# ----------------------------------------------------------------------
# The one converter which can support the metric:  its input is an lcov report,
#   so whatever the report shows is recoverable from it.  Which makes this the
#   same question as the report tools' - the user asked for a metric and the data
#   does not have it - and therefore the same answer, at the same point:  after
#   the filters, before the write.  What it must not do is write a metric which
#   measured nothing, and it must not report the flag as unsupported, because for
#   this tool it is not.
# '--save' is what makes this work at all:  html2lcov recovers the coverage from
#   the '.info' the report kept, which is exactly why this tool can support the
#   metric when the other converters cannot
runCmd rpt "$COVER $GENHTML_TOOL $LCOV_OPTS --function-coverage --save -o rpt nosites.info"
if [ 0 != $RC ] ; then
    fail rpt "could not generate the report to recover from"
fi

# '--no-branch-coverage' because the report was made with '--function-coverage'
#   and so has no branch data to recover:  branch coverage is on by default, and
#   the same check would otherwise fail this run on branches before it ever got
#   as far as the callgraph, which is what this case is about
expectFail html2lcov_empty \
    "$COVER $HTML2LCOV_TOOL rpt --source-directory proj -o recovered --callgraph --no-branch-coverage --ignore-errors unused"

# ..and ignoring it writes the '.info' with the metric off.  'empty' covers the
#   tool's own two uses of the class - an unchanged source tree produces no
#   udiff, and a report without branch data recovers none - so this run says
#   nothing about which one was ignored;  what it asserts is that no call records
#   were invented
expectWarn html2lcov_ignored \
    "$COVER $HTML2LCOV_TOOL rpt --source-directory proj -o recovered2 --callgraph --ignore-errors empty,unused"
if [ -f recovered2.info ] && grep -q -E '^FNC' recovered2.info ; then
    fail html2lcov_ignored "call records were written for a metric which is off:"
    grep -E '^FNC' recovered2.info
fi

# ..and the case which must not fire, which is the reason the tool has the option:
#   a report generated with the metric carries the call data, and recovering it
#   gives the records back
runCmd rpt_sites \
    "$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph --save -o rpt_sites sites.info"
if [ 0 != $RC ] ; then
    fail rpt_sites "could not generate the report to recover from"
fi

expectQuiet html2lcov_sites \
    "$COVER $HTML2LCOV_TOOL rpt_sites --source-directory proj -o recovered3 --callgraph --ignore-errors empty,unused"
if [ -f recovered3.info ] &&
   ! grep -q -F -e 'FNC:1,8,12,0,1,helper' recovered3.info ; then
    fail html2lcov_sites "the call site was not recovered from the report:"
    grep -E '^FNC' recovered3.info
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'empty' $LOCAL_COVERAGE 0
fi

exit $STATUS
