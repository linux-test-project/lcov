#! /usr/bin/env bash

# Callgraph coverage in the text reports:  'lcov --list', 'lcov --summary', and the
# coverage criteria callbacks.
#
# The numbers here are the caller-side view - the call sites which the functions
#   of a file contain, which is what 'FNCF'/'FNCH' count - and not the sites which
#   target them.  See TraceInfo::callgraph_found and the two views described in the
#   '--callgraph-coverage' section of genhtml(1).
#
# Three things are asserted rather than left to the reader:
#
#   - a listing which was not asked for call data is unchanged, to the character.
#     The four existing metrics reserve their field widths whether or not they are
#     enabled - the filename column is sized against the sum - so a fifth pair
#     added the same way would silently take 11 characters of filename away from
#     every listing anyone has ever run.  The callee widths are therefore appended
#     only when the metric is on, and the test for that is that the filename
#     column is exactly as wide with the metric off as it is in a run which never
#     mentions it.
#
#   - a file which has functions but makes no calls lists as '-', not '0.0%'.
#     Zero of zero is not zero percent, and 'FNCF:0' is a fact about the file
#     rather than a missing measurement - see 'empty.sh', where the report-wide
#     version of the same distinction is the 'empty' error.
#
#   - the 'callgraph' key of the criteria callback data exists only when the metric
#     is on, unlike the four unconditional keys.  A criteria script which asks
#     about callgraph coverage on a report which was never asked to collect it must
#     therefore find nothing to check, rather than being told 0 of 0 and drawing
#     the obvious wrong conclusion.  Both supplied scripts have the option, and
#     both halves are checked for each: the script asking and the data answering.
#
# The two callbacks are different code:  genhtml builds its JSON from the
#   categorized SummaryInfo (per TLA, per bin), and lcov builds its own from the
#   TraceInfo totals.  So each is exercised through the tool which has it.

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
    rm -rf summary.d
    exit 0
fi

rm -rf summary.d
mkdir summary.d
cd summary.d || exit 1
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

runCmd()
{
    # runCmd label command
    local label=$1
    echo "$2" > $label.cmd
    eval "$2" > $label.log 2>&1
    RC=$?
    cat $label.log
}

checkLine()
{
    # checkLine label file line
    #   the line is matched whole - leading and trailing spaces included - which
    #   is the point when what is being checked is a column layout
    local label=$1
    local file=$2
    local line=$3
    if ! grep -q -x -F -e "$line" $file ; then
        fail $label "expected the line '$line' in $file:"
        cat $file
    fi
}

checkNoLine()
{
    # checkNoLine label file pattern
    local label=$1
    local file=$2
    local pattern=$3
    if grep -q -E -e "$pattern" $file ; then
        fail $label "did not expect '$pattern' in $file:"
        grep -E -e "$pattern" $file
    fi
}

# ----------------------------------------------------------------------
# The fixture
# ----------------------------------------------------------------------
# 'c.cpp' makes three calls, two of which happen, and one of its four functions
#   is never called.  'lib.cpp' has a function and no calls at all, which is what
#   a leaf translation unit or a header of inline definitions looks like:  it is
#   here for the '-' rate and because the totals have to add up across files
#   which do and do not have the metric's data.
cat >proj/c.cpp <<'EOF'
int helper(int x)
{
    return x + 1;
}

int other(int x)
{
    return x + 2;
}

int caller(int n)
{
    int t = helper(n);
    if (n > 1)
        t += other(n);
    return t;
}

int main()
{
    return caller(2) == 0;
}
EOF

cat >proj/lib.cpp <<'EOF'
int libfn(int x)
{
    return x * 2;
}
EOF

cat >curr.info <<EOF
TN:t1
SF:`pwd`/proj/c.cpp
FNL:0,1,4
FNA:0,3,helper
FNL:1,6,9
FNA:1,0,other
FNL:2,11,17
FNA:2,1,caller
FNL:3,19,22
FNA:3,1,main
FNC:2,13,13,0,1,helper
FNC:2,15,14,0,0,other
FNC:3,21,12,0,1,caller
FNF:4
FNH:3
FNCF:3
FNCH:2
DA:1,3
DA:3,3
DA:6,0
DA:8,0
DA:11,1
DA:13,1
DA:14,1
DA:15,0
DA:16,1
DA:19,1
DA:21,1
LF:11
LH:9
end_of_record
TN:t1
SF:`pwd`/proj/lib.cpp
FNL:0,1,4
FNA:0,3,libfn
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

# ----------------------------------------------------------------------
echo "*** 1. --list, with the metric on"
# ----------------------------------------------------------------------
runCmd list "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --list curr.info"
if [ 0 != $RC ] ; then
    fail list "lcov --list failed:" `grep -E 'ERROR' list.log`
fi
checkLine list list.log \
    '            |Lines       |Functions  |Callees     '
checkLine list list.log \
    'Filename    |Rate     Num|Rate    Num|Rate     Num'
# 2 of the 3 sites were taken..
checkLine list list.log 'c.cpp       |72.7%     11|75.0%     4|66.7%      3'
# ..and a file with functions and no calls is not 0% of anything
checkLine list list.log 'lib.cpp     | 100%      2| 100%     1|    -      0'
# ..and the total is over the sites of both files, not over the files which have
#   any:  3 sites found, in 2 source files
checkLine list list.log '      Total:|76.9%     13|80.0%     5|66.7%      3'

# ----------------------------------------------------------------------
echo "*** 2. --list, with the metric off"
# ----------------------------------------------------------------------
runCmd nolist "$COVER $LCOV_TOOL $LCOV_OPTS --list curr.info"
if [ 0 != $RC ] ; then
    fail nolist "lcov --list failed:" `grep -E 'ERROR' nolist.log`
fi
checkNoLine nolist nolist.log 'Callees'
checkLine nolist nolist.log 'Filename    |Rate     Num|Rate    Num'
checkLine nolist nolist.log 'c.cpp       |72.7%     11|75.0%     4'
# ..and the filename column - the one every existing listing would have paid for
#   an unconditional pair of callee columns out of - is the same width either way
LWIDE=`grep -F -e 'Filename    |' list.log | cut -d'|' -f1`
LNARROW=`grep -F -e 'Filename    |' nolist.log | cut -d'|' -f1`
if [ "$LWIDE" != "$LNARROW" ] ; then
    fail nolist "the filename column changed width when the metric was" \
        "turned off: '$LWIDE' vs '$LNARROW'"
fi

# ----------------------------------------------------------------------
echo "*** 3. --summary"
# ----------------------------------------------------------------------
runCmd summary "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --summary curr.info"
if [ 0 != $RC ] ; then
    fail summary "lcov --summary failed:" `grep -E 'ERROR' summary.log`
fi
checkLine summary summary.log '  source files: 2'
checkPattern summary summary.log '  callgraph\.+: 66\.7% \(2 of 3 callees\)'

runCmd nosummary "$COVER $LCOV_TOOL $LCOV_OPTS --summary curr.info"
if [ 0 != $RC ] ; then
    fail nosummary "lcov --summary failed:" `grep -E 'ERROR' nosummary.log`
fi
checkNoLine nosummary nosummary.log 'callee'
checkLine nosummary nosummary.log '  functions...: 80.0% (4 of 5 functions)'

# ----------------------------------------------------------------------
echo "*** 4. lcov's criteria callback"
# ----------------------------------------------------------------------
# 'threshold.pm --callgraph' reads the 'callgraph' key of the data lcov passes it.  The
#   check runs at the file level and at the top level, and both see the metric
THRESH="$SCRIPT_DIR/threshold.pm"
runCmd thresh_fail \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --summary curr.info --criteria-script $THRESH,--callgraph,90"
if [ 0 == $RC ] ; then
    fail thresh_fail "expected a criteria failure, but the command succeeded"
fi
checkLine thresh_fail thresh_fail.log '  top: "callgraph: 66.67 < 90.00"'
if ! grep -q -F -e 'c.cpp": "callgraph: 66.67 < 90.00"' thresh_fail.log ; then
    fail thresh_fail "the file-level check did not see the callgraph data:"
    cat thresh_fail.log
fi
# ..the file which makes no calls is not failed for it:  'threshold.pm' skips a
#   metric whose 'found' is zero, and it can only do that because the key says 0
if grep -q -F -e 'lib.cpp' thresh_fail.log ; then
    fail thresh_fail "a file with no call sites was failed on callgraph coverage:"
    grep -F -e 'lib.cpp' thresh_fail.log
fi

# ..and a threshold the report meets passes
runCmd thresh_pass \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --summary curr.info --criteria-script $THRESH,--callgraph,50"
if [ 0 != $RC ] ; then
    fail thresh_pass "expected the criteria to be met:" \
        `grep -E 'criteria' thresh_pass.log`
fi

# ..and the same script on the same data, with the metric off, has nothing to
#   check:  the key is absent, so the run passes rather than failing a 0 of 0
runCmd thresh_off \
    "$COVER $LCOV_TOOL $LCOV_OPTS --summary curr.info --criteria-script $THRESH,--callgraph,90"
if [ 0 != $RC ] ; then
    fail thresh_off "a callgraph threshold was applied to a run which was not" \
        "asked for call data:" `grep -E 'criteria' thresh_off.log`
fi
checkNoLine thresh_off thresh_off.log 'callee'

# ----------------------------------------------------------------------
echo "*** 5. genhtml's criteria callback"
# ----------------------------------------------------------------------
# The other callback, built from the categorized data rather than from the
#   totals:  'criteria.pm --callgraph' asks about the differential categories of the
#   call sites.  'other' is never called, so its site is UNC
CRITERIA="$SCRIPT_DIR/criteria.pm"
runCmd criteria \
    "$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph -o html curr.info --criteria-script $CRITERIA,--callgraph --rc criteria_callback_levels=top"
if [ 0 == $RC ] ; then
    fail criteria "expected a criteria failure, but the command succeeded"
fi
if ! grep -q -F -e 'callgraph: UNC + LBC + UIC != 0: 1 + 0 + 0' criteria.log ; then
    fail criteria "the callgraph categories were not checked:"
    cat criteria.log
fi

# ..and the script only looks at what it was asked to look at:  the same report,
#   the same data, no '--callgraph' for the script, and callgraph coverage is not
#   part of the criteria - which is also why the message has no type prefix at all
runCmd criteria_off \
    "$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph -o html_off curr.info --criteria-script $CRITERIA --rc criteria_callback_levels=top"
if [ 0 == $RC ] ; then
    fail criteria_off "expected a criteria failure, but the command succeeded"
fi
# (the report itself still counts and prints the metric - it was asked for - so
#   the assertion is about the criteria message, not about the word)
checkNoLine criteria_off criteria_off.log 'callgraph: UNC'

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'summary' $LOCAL_COVERAGE 0
fi

exit $STATUS
