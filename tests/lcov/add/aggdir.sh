#!/usr/bin/env bash
set +x

# ============================================================================
# 'lcov --add-tracefile <directory>', which looks for the tracefiles under the
#   directory with a forked 'find'.  The interesting part is the command line
#   it builds for it, and what it makes of the answer:
#
#   - the directory and the name pattern used to be written into that command
#     line inside a bare pair of single quotes.  A single quote in either of
#     them - and the directory name is whatever the user called it, while the
#     pattern comes from lcovrc - ended the quoting and handed the rest of the
#     name to the shell.
#   - the list of paths 'find' printed was split on whitespace, so a tracefile
#     whose name contains a space arrived as two names, neither of which is a
#     file.
#
# The cases:
#   1. a directory whose name contains a quote
#   2. a tracefile whose name contains a space
#   3. a pattern which contains a quote
# ============================================================================

source ../../common.tst

# $LCOV_TOOL is set by the test Makefile;  fall back to the tool in $LCOV_HOME
# when this script is run standalone (notably ./aggdir.sh --coverage)
if [ 'x' == "x$LCOV_TOOL" ] ; then
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
fi

rm -f agg_*.log agg_*.info one.c two.c three.c
rm -rf "q'dir" spacedir patdir

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

STATUS=0

fail()
{
    # $1 = scenario label, $2.. = what went wrong
    local label=$1
    shift
    echo "ERROR ($label): $*"
    STATUS=1
    if [ "$KEEP_GOING" == 0 ] ; then
        exit 1
    fi
}

# a two-line source file $1, and a tracefile $2 which describes it.  The
#   source has to be there:  a filter which needs to read it is enabled by the
#   lcovrc this suite runs with.  The data is line coverage only, so the
#   missing function and branch coverpoints are expected rather than a problem -
#   hence the '--ignore-errors empty' each case passes
mksource()
{
    cat > "$1" <<'EOF'
int f(int a)
{ return a; }
EOF
    cat > "$2" <<EOF
TN:
SF:$PWD/$1
DA:1,1
DA:2,0
LF:2
LH:1
end_of_record
EOF
}

# $1 = label, $2 = the aggregate lcov wrote, $3 = the source file it should
#   have found data for
check_merged()
{
    if ! grep -F -q -e "SF:$PWD/$3" $2 ; then
        cat $2
        fail $1 "no data for '$3' in the aggregate"
    fi
}

# ----------------------------------------------------------------------
echo "*** 1. a directory whose name contains a quote"
# ----------------------------------------------------------------------
QDIR="q'dir"
mkdir -p "$QDIR"
mksource one.c "$QDIR/plain.info"
$COVER $LCOV_TOOL -a "$QDIR" -o agg_quote.info --ignore-errors empty \
    > agg_quote.log 2>&1
if [ 0 != $? ] ; then
    cat agg_quote.log
    fail quote "--add-tracefile failed for a directory named \"$QDIR\""
fi
check_merged quote agg_quote.info one.c

# ----------------------------------------------------------------------
echo "*** 2. a tracefile whose name contains a space"
# ----------------------------------------------------------------------
# 'find' prints one path per line, so a space in a path is just a character -
#   but only if the answer is read that way
mkdir -p spacedir
mksource two.c 'spacedir/a b.info'
$COVER $LCOV_TOOL -a spacedir -o agg_space.info --ignore-errors empty \
    > agg_space.log 2>&1
if [ 0 != $? ] ; then
    cat agg_space.log
    fail space "--add-tracefile failed for a tracefile named 'a b.info'"
fi
check_merged space agg_space.info two.c
if grep -F -q -e 'is not a readable file' agg_space.log ; then
    cat agg_space.log
    fail space "the path was split on the space in its name"
fi

# ----------------------------------------------------------------------
echo "*** 3. a pattern which contains a quote"
# ----------------------------------------------------------------------
# the pattern is a configuration setting rather than something the user types
#   on the command line, so it is no more predictable than the file names it
#   is there to match
mkdir -p patdir
mksource three.c "patdir/it's.info"
$COVER $LCOV_TOOL -a patdir --rc "info_file_pattern=*'*.info" \
    -o agg_pattern.info --ignore-errors empty > agg_pattern.log 2>&1
if [ 0 != $? ] ; then
    cat agg_pattern.log
    fail pattern "--add-tracefile failed for a pattern containing a quote"
fi
check_merged pattern agg_pattern.info three.c

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'aggdir' $LOCAL_COVERAGE 0
fi

exit $STATUS
