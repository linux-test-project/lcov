#!/usr/bin/env bash
set +x

# ============================================================================
# 'lcov --zerocounters', which deletes the '.da'/'.gcda' files under a
#   directory.  It finds them with a forked 'find', and the interesting part is
#   the command line it builds for it:
#
#   - the directory used to be written into that command line inside a pair of
#     double quotes.  A double-quoted string is still expanded by the shell, so
#     a '$', a backquote or a backslash in a directory name was interpreted
#     rather than passed on, and a double quote in the name ended the quoting
#     altogether.
#   - whether 'find' worked was decided by '$?' and then reported as '$!' - the
#     errno of the last failed syscall, which has nothing to do with the
#     command which just ran, and which is empty if nothing has failed.
#
# The cases:
#   1. a directory whose name contains a quote and a '$'
#   2. 'find' exits with an error status
#   3. the error is ignorable:  '--ignore utility' carries on
# ============================================================================

source ../../common.tst

# $LCOV_TOOL is set by the test Makefile;  fall back to the tool in $LCOV_HOME
# when this script is run standalone (notably ./zerocounters.sh --coverage)
if [ 'x' == "x$LCOV_TOOL" ] ; then
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
fi

rm -f zc_*.log
rm -rf fakefind zc_dir 'q$x'"'"'dir'

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

# every one of these has to name the command it ran and what became of it
check_utility_error()
{
    # $1 = label, $2 = log, $3.. = strings which must appear
    local label=$1 log=$2
    shift 2
    for pattern in 'ERROR: (utility)' 'unable to find .gcda/.da files' \
        'find ' "$@" ; do
        if ! grep -F -q -e "$pattern" $log ; then
            cat $log
            fail $label "message does not mention: $pattern"
        fi
    done
}

# ----------------------------------------------------------------------
echo "*** 1. a directory whose name the shell would rewrite"
# ----------------------------------------------------------------------
# a single quote, a '$' naming a variable which is not set, and a
#   subdirectory:  the name itself, the reference the shell would expand to
#   nothing, and the recursion into it all have to survive being handed to a
#   shell.  The files need no contents:  '--zerocounters' only unlinks them
QDIR='q$x'"'"'dir'
mkdir -p "$QDIR/sub"
touch "$QDIR/a.gcda" "$QDIR/sub/b.gcda" "$QDIR/old.da" "$QDIR/keep.txt"
$COVER $LCOV_TOOL --zerocounters -d "$QDIR" > zc_quote.log 2>&1
if [ 0 != $? ] ; then
    cat zc_quote.log
    fail quote "--zerocounters failed for a directory named \"$QDIR\""
fi
for f in "$QDIR/a.gcda" "$QDIR/sub/b.gcda" "$QDIR/old.da" ; do
    if [ -f "$f" ] ; then
        fail quote "'$f' was not deleted"
    fi
done
# and nothing else was:  'find' was asked for two patterns, not for everything
if [ ! -f "$QDIR/keep.txt" ] ; then
    fail quote "'$QDIR/keep.txt' was deleted"
fi

# ----------------------------------------------------------------------
echo "*** 2. 'find' exits with an error status"
# ----------------------------------------------------------------------
# there is no shortage of ways for a real 'find' to fail;  shadow it with one
#   which always does.  The command goes through a shell, which is what
#   reports the status - so a 'find' the OS kills arrives here as 128 plus the
#   signal, and the signal arm of the report is reachable only if the shell
#   itself is the process which was killed
mkdir -p fakefind
cat > fakefind/find <<'EOF'
#!/bin/sh
echo "find: cannot search" >&2
exit 2
EOF
chmod +x fakefind/find
mkdir -p zc_dir
touch zc_dir/c.gcda
PATH="`pwd`/fakefind:$PATH" $COVER $LCOV_TOOL --zerocounters -d zc_dir \
    > zc_status.log 2>&1
if [ 0 == $? ] ; then
    cat zc_status.log
    fail status "a 'find' which exits 2 should not have been accepted"
fi
check_utility_error status zc_status.log 'returned non-zero exit status 2'
# the old report was 'Error return code ...: $!', which for a command that ran
#   and failed says nothing at all
if grep -F -q -e 'Error return code' zc_status.log ; then
    fail status "the exit status was reported as an errno"
fi

# ----------------------------------------------------------------------
echo "*** 3. the failure is ignorable"
# ----------------------------------------------------------------------
# 'find' told us nothing, so there is nothing to delete - but the user asked
#   for the run to continue, and it does
PATH="`pwd`/fakefind:$PATH" $COVER $LCOV_TOOL --zerocounters -d zc_dir \
    --ignore-errors utility > zc_ignore.log 2>&1
if [ 0 != $? ] ; then
    cat zc_ignore.log
    fail ignore "'--ignore-errors utility' did not carry on"
fi
grep -F -q -e 'WARNING: (utility)' zc_ignore.log ||
    fail ignore "the ignored failure was not reported as a warning"
if [ ! -f zc_dir/c.gcda ] ; then
    fail ignore "a file 'find' never named was deleted"
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'zerocounters' $LOCAL_COVERAGE 0
fi

exit $STATUS
