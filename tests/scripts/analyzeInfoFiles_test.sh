#!/usr/bin/env bash
#
# Test suite for scripts/analyzeInfoFiles
#
# The tool compares a set of .info files which are supposed to describe the same
# code base, and reports every contiguous region of lines which some of them call
# code and others do not.  It had no test at all, and the checks below are the
# first ones:  each of them is a case where the tool used to report a clean
# comparison - exit 0, nothing printed - of two inputs which do disagree.  A
# silent false 'consistent' is the worst answer this tool can give, because the
# whole point of running it is to be told that something differs.
#
# Tests:
#   1.  consistent inputs report nothing and exit 0
#   2.  a disagreement on the last line of the file is reported
#   3.  a disagreement past line 99, with no source file to measure
#   4.  a source filename containing shell metacharacters is not a shell command
#   5.  a list file entry containing '#' is a filename, not a comment
#   6.  --all, --compact, --sort and --verbose presentation
#   7.  a source file missing from one .info file, with and without --drop
#   8.  a version mismatch is reported instead of the line data being compared,
#       and a version of '0' is a version
#   9.  --help, and the invalid-argument path, which are the two arms of one 'if'

set +x

if [[ "x" == "${LCOV_HOME}x" ]] ; then
    if [ -f ../../bin/lcov ] ; then
        LCOV_HOME=../..
    fi
fi
source ../common.tst

if [ -z "$SCRIPT_DIR" ] ; then
    echo "SCRIPT_DIR not set" >&2
    exit 1
fi

ANALYZE=$SCRIPT_DIR/analyzeInfoFiles
if [ ! -f "$ANALYZE" ] ; then
    echo "analyzeInfoFiles not found in '$SCRIPT_DIR'" >&2
    exit 1
fi

# When coverage is active, $COVER is "perl -MDevel::Cover=... " so use it as the
#   interpreter rather than relying on the script's own '#!' line
PERL="${COVER:-perl}"

# Every run below has its working directory in $WORKDIR, so a relative
#   Devel::Cover database - which is what 'common.tst' asks for unless
#   '--coverage <db>' named one itself - would be written there and then taken
#   away with it by the trap.  Spell it absolutely, so that '--coverage' reports
#   what this test covered
if [ "x$COVER" != 'x' ] && [ "${COVER_DB#/}" == "$COVER_DB" ] ; then
    PERL="${PERL/-db,$COVER_DB,/-db,$(pwd)/$COVER_DB,}"
fi

if [ "$CLEAN_ONLY" == 1 ] ; then
    rm -f *.log
    exit 0
fi

PASS=0
FAIL=0

pass() { echo "PASS: $1" ; PASS=$((PASS + 1)) ; }
fail() { echo "FAIL: $1" ; FAIL=$((FAIL + 1)) ;
         if [ "$KEEP_GOING" != 1 ] ; then exit 1 ; fi ; }

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# ---------------------------------------------------------------------------
# Helpers
#
# write_info <path> <sourcename> [<version>] -- <line> <line> ...
#   a one-file .info with a 'DA:<line>,1' for each line named
#
# analyze [options...] -- runs the tool in $WORKDIR and captures its output.
#   The tool prints a compile-time 'Smartmatch is experimental' warning (see the
#   '~~' in Region::buildCodeKey), so the checks below look for what is expected
#   rather than asserting that nothing else was printed
# ---------------------------------------------------------------------------
write_info()
{
    local path=$1 ; shift
    local src=$1 ; shift
    local version=$1 ; shift
    local sep=$1 ; shift
    {
        echo "TN:"
        echo "SF:$src"
        if [ "x$version" != 'x' ] ; then
            echo "VER:$version"
        fi
        local found=0
        local hit=0
        for line in "$@" ; do
            echo "DA:$line,1"
            found=$((found + 1))
            hit=$((hit + 1))
        done
        echo "LF:$found"
        echo "LH:$hit"
        echo "end_of_record"
    } > "$path"
}

analyze()
{
    OUTPUT=$( cd "$WORKDIR" && $PERL "$ANALYZE" "$@" 2>&1 )
    RC=$?
}

# analyze_split [options...] -- as 'analyze', but keeps the two streams apart in
#   $OUT and $ERR.  Test 9 is about which stream the usage text goes to, so it
#   cannot use the combined capture above
analyze_split()
{
    OUT=$( cd "$WORKDIR" && $PERL "$ANALYZE" "$@" 2>"$WORKDIR/stderr.txt" )
    RC=$?
    ERR=$(cat "$WORKDIR/stderr.txt")
}

# ---------------------------------------------------------------------------
# Test 1: two .info files which agree about every line
#   The baseline for everything below:  when the answer really is 'consistent',
#   it is exit 0 with no region printed
# ---------------------------------------------------------------------------
printf 'line1\nline2\nline3\nline4\n' > "$WORKDIR/src.c"
write_info "$WORKDIR/same_a.info" "$WORKDIR/src.c" '' -- 1 2 3 4
write_info "$WORKDIR/same_b.info" "$WORKDIR/src.c" '' -- 1 2 3 4

analyze same_a.info same_b.info
if [ $RC != 0 ] ; then
    fail "Test 1 consistent: expected exit 0, got $RC; output: $OUTPUT"
elif echo "$OUTPUT" | grep -q 'not code' ; then
    fail "Test 1 consistent: reported a region: $OUTPUT"
else
    pass "Test 1: identical inputs are reported consistent"
fi

# ---------------------------------------------------------------------------
# Test 2: the disagreement is on the last line of the source file
#   The scan ran 'for (my $lineNo = 1; $lineNo < $numLines; ...)' over a
#   $numLines which is the last line of the file, not one past it, so the last
#   line was never given to either group - and a file whose only difference is
#   there compared clean
# ---------------------------------------------------------------------------
write_info "$WORKDIR/last_a.info" "$WORKDIR/src.c" '' -- 1 2 3 4
write_info "$WORKDIR/last_b.info" "$WORKDIR/src.c" '' -- 1 2 3

analyze last_a.info last_b.info
if [ $RC == 0 ] ; then
    fail "Test 2 last line: expected a non-zero exit; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^4 : 4:' ; then
    fail "Test 2 last line: did not report line 4 as a region: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'not code:  1' ; then
    fail "Test 2 last line: did not name the file which lacks the line: $OUTPUT"
else
    pass "Test 2: a disagreement on the last line is reported"
fi

# ---------------------------------------------------------------------------
# Test 3: no source file, and a line number past 99
#   With no file to measure, the line count comes from the data itself - the
#   largest line number any of the inputs mentions.  That was a string sort, and
#   "9" sorts after "100", so a file whose highest line is 100 was measured as
#   ending at whichever of its line numbers happens to sort last.  Every line
#   past that point then went unexamined
# ---------------------------------------------------------------------------
write_info "$WORKDIR/big_a.info" "$WORKDIR/absent.c" '' -- 1 2 3 100
write_info "$WORKDIR/big_b.info" "$WORKDIR/absent.c" '' -- 1 2 3

analyze big_a.info big_b.info
if [ $RC == 0 ] ; then
    fail "Test 3 no source: expected a non-zero exit; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^100 : 100:' ; then
    fail "Test 3 no source: did not report line 100 as a region: $OUTPUT"
else
    pass "Test 3: a disagreement past line 99 is found with no source file"
fi

# ---------------------------------------------------------------------------
# Test 4: the source filename is a string out of a .info file
#   The line count used to come from a 'wc -l $srcfile' subprocess.  The name is
#   whatever the 'SF:' record says, so the shell re-parsed it:  a name with a
#   space in it counted some other file, and a name containing a command
#   substitution ran it.  The name below is legal on this filesystem and is
#   created for real, so the only way 'injected.txt' can appear is if something
#   executed the 'touch' - and the region has to be reported either way
# ---------------------------------------------------------------------------
INJECT_SRC='$(touch injected.txt)x.c'
printf 'line1\nline2\nline3\nline4\n' > "$WORKDIR/$INJECT_SRC"
write_info "$WORKDIR/inj_a.info" "$INJECT_SRC" '' -- 1 2 3 4
write_info "$WORKDIR/inj_b.info" "$INJECT_SRC" '' -- 1 2 3

analyze inj_a.info inj_b.info
if [ -f "$WORKDIR/injected.txt" ] ; then
    fail "Test 4 injection: the source filename was executed as a shell command"
    rm -f "$WORKDIR/injected.txt"
elif ! echo "$OUTPUT" | grep -q '^4 : 4:' ; then
    fail "Test 4 injection: did not report line 4 as a region: $OUTPUT"
else
    pass "Test 4: a source filename is not passed through a shell"
fi

# ---------------------------------------------------------------------------
# Test 5: an argument which is not a .info file is a list of .info files
#   Blank lines and comments are skipped, and the comment pattern was
#   unanchored:  '\s*#' matches a '#' anywhere in the line, so any .info file
#   with a '#' in its name was silently dropped from the list.  Dropping one of
#   two inputs leaves nothing to compare, which this tool reports as success
# ---------------------------------------------------------------------------
cp "$WORKDIR/last_a.info" "$WORKDIR/a#1.info"
printf '# a comment\n\na#1.info\nlast_b.info\n' > "$WORKDIR/list.txt"

analyze list.txt
if [ $RC == 0 ] ; then
    fail "Test 5 list file: expected a non-zero exit; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^  0: a#1.info$' ; then
    fail "Test 5 list file: the name with a '#' in it was dropped: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^  1: last_b.info$' ; then
    fail "Test 5 list file: did not read the second name: $OUTPUT"
elif echo "$OUTPUT" | grep -q ': # a comment$' ; then
    fail "Test 5 list file: read a comment line as a filename: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^4 : 4:' ; then
    fail "Test 5 list file: did not report line 4 as a region: $OUTPUT"
else
    pass "Test 5: a '#' in a filename does not make the line a comment"
fi

# ---------------------------------------------------------------------------
# Test 6: the presentation options
#   --all reports the regions everybody agrees about as well, --compact prints
#   the per-file vote key instead of the name lists, --sort orders the regions by
#   size and --verbose prints .info file names rather than their indices
# ---------------------------------------------------------------------------
analyze --all --verbose last_a.info last_b.info
if [ $RC == 0 ] ; then
    fail "Test 6 --all: expected a non-zero exit; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^1 : 3:  3 lines$' ; then
    fail "Test 6 --all: did not report the region both files agree on: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'last_a.info' ; then
    fail "Test 6 --verbose: printed indices rather than names: $OUTPUT"
else
    pass "Test 6a: --all reports unanimous regions, --verbose names the files"
fi

analyze --all --compact --sort last_a.info last_b.info
if [ $RC == 0 ] ; then
    fail "Test 6 --compact: expected a non-zero exit; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^1 : 3:  11  3 lines$' ; then
    fail "Test 6 --compact: no vote key for the unanimous region: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^4 : 4:  1_  1 line$' ; then
    fail "Test 6 --compact: no vote key for the region which differs: $OUTPUT"
else
    # --sort is largest first, so the 3-line region has to precede the 1-line one
    FIRST=$(echo "$OUTPUT" | grep -E '^[0-9]+ : [0-9]+:' | head -1)
    if [ "${FIRST#1 : 3:}" == "$FIRST" ] ; then
        fail "Test 6 --sort: the larger region is not first: $FIRST"
    else
        pass "Test 6b: --compact prints the vote key, --sort orders by size"
    fi
fi

# ---------------------------------------------------------------------------
# Test 7: a source file which only one of the .info files mentions
#   Reported as missing, and then dropped from the comparison unless --drop says
#   to compare the .info files which do have it
# ---------------------------------------------------------------------------
printf 'other1\nother2\n' > "$WORKDIR/other.c"
cp "$WORKDIR/last_a.info" "$WORKDIR/extra_a.info"
{
    echo "TN:"
    echo "SF:$WORKDIR/other.c"
    echo "DA:1,1"
    echo "LF:1"
    echo "LH:1"
    echo "end_of_record"
} >> "$WORKDIR/extra_a.info"

analyze --keep-going extra_a.info last_b.info
if [ $RC == 0 ] ; then
    fail "Test 7 missing: expected a non-zero exit; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'Files missing from .info data' ; then
    fail "Test 7 missing: did not report the missing source file: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q "other.c" ; then
    fail "Test 7 missing: did not name the missing source file: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^4 : 4:' ; then
    fail "Test 7 missing: did not go on to compare the file both contain: $OUTPUT"
else
    pass "Test 7: a source file missing from one .info file is reported"
fi

# ---------------------------------------------------------------------------
# Test 8: the same source file at two different versions
#   There is nothing to learn from comparing line data across versions, so the
#   mismatch is reported and the line comparison for that file is skipped.
#   Skipping it used to mean skipping the .info file's entry for the source
#   altogether, so the next check concluded that the file the tool had just
#   printed two versions of is not in that .info file at all - which it then
#   reported as a second, contradictory, error and (by default) used as the
#   reason to drop the source from the rest of the run.  The two versions are
#   also named:  one arm of the message identified its .info file by index and
#   the other by name, so the pair could not be read as a pair
# ---------------------------------------------------------------------------
write_info "$WORKDIR/ver_a.info" "$WORKDIR/src.c" v1 -- 1 2 3 4
write_info "$WORKDIR/ver_b.info" "$WORKDIR/src.c" v2 -- 1 2 3

analyze --keep-going ver_a.info ver_b.info
if [ $RC == 0 ] ; then
    fail "Test 8 version: expected a non-zero exit; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'version mismatch' ; then
    fail "Test 8 version: did not report the version mismatch: $OUTPUT"
elif echo "$OUTPUT" | grep -q '^4 : 4:' ; then
    fail "Test 8 version: compared line data across versions anyway: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'ver_a.info: v1$' ; then
    fail "Test 8 version: named the first .info file by index: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'ver_b.info: v2$' ; then
    fail "Test 8 version: did not name the second .info file: $OUTPUT"
elif echo "$OUTPUT" | grep -q 'missing from .info data' ; then
    fail "Test 8 version: also called the file missing from an input: $OUTPUT"
else
    pass "Test 8a: a version mismatch is reported instead of the line data"
fi

# ..and a version whose text is '0'.  'VER:0' is a version like any other; the
#   arm which prints it tested it for truth rather than for definedness, so a
#   file at version '0' was reported as having no version - which is what the
#   other .info file here really does have, so the message claimed a mismatch
#   between two versions it printed identically
write_info "$WORKDIR/ver_c.info" "$WORKDIR/src.c" 0 -- 1 2 3 4
write_info "$WORKDIR/ver_d.info" "$WORKDIR/src.c" '' -- 1 2 3

analyze --keep-going ver_c.info ver_d.info
if [ $RC == 0 ] ; then
    fail "Test 8 zero version: expected a non-zero exit; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'ver_c.info: 0$' ; then
    fail "Test 8 zero version: a version of '0' printed as no version: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'ver_d.info: undef$' ; then
    fail "Test 8 zero version: the file with no version is not 'undef': $OUTPUT"
else
    pass "Test 8b: a version whose text is '0' is a version"
fi

# ---------------------------------------------------------------------------
# Test 9: --help, and the same usage text reached the other way
#   Both are arms of one 'if': '--help' is a request, so the summary line and the
#   usage go to stdout and the exit status is 0, while an option which cannot be
#   parsed is a failure, so the usage goes to stderr, the summary line is not
#   printed at all and the status is non-zero.  Nothing else in this file passes
#   an option the tool does not have or asks it for its usage, so neither arm ran
# ---------------------------------------------------------------------------
analyze_split --help
if [ $RC != 0 ] ; then
    fail "Test 9 --help: expected exit 0, got $RC; output: $OUT"
elif ! echo "$OUT" | grep -q '^Check for consistency in set of .info files$' ; then
    fail "Test 9 --help: no summary line on stdout: $OUT"
elif ! echo "$OUT" | grep -q '^Usage:$' ; then
    fail "Test 9 --help: no usage text on stdout: $OUT"
elif ! echo "$OUT" | grep -q -- '--sort              : sort by region size' ; then
    fail "Test 9 --help: the usage text does not list the options: $OUT"
elif echo "$ERR" | grep -q 'Usage:' ; then
    fail "Test 9 --help: a request for the usage wrote it to stderr: $ERR"
else
    pass "Test 9a: --help writes the usage to stdout and exits 0"
fi

# '-h' is the same option
analyze_split -h
if [ $RC != 0 ] ; then
    fail "Test 9 -h: expected exit 0, got $RC; output: $OUT"
elif ! echo "$OUT" | grep -q '^Usage:$' ; then
    fail "Test 9 -h: no usage text on stdout: $OUT"
else
    pass "Test 9b: '-h' is '--help'"
fi

analyze_split --no-such-option same_a.info same_b.info
if [ $RC == 0 ] ; then
    fail "Test 9 bad option: expected a non-zero exit; stderr: $ERR"
elif ! echo "$ERR" | grep -q 'invalid argument:' ; then
    fail "Test 9 bad option: did not say the argument was invalid: $ERR"
elif ! echo "$ERR" | grep -q '^Usage:$' ; then
    fail "Test 9 bad option: no usage text on stderr: $ERR"
elif [ "x$OUT" != 'x' ] ; then
    fail "Test 9 bad option: wrote to stdout: $OUT"
elif echo "$ERR" | grep -q '^Check for consistency in set of .info files$' ; then
    fail "Test 9 bad option: printed the summary line on the error path: $ERR"
else
    pass "Test 9c: an unparsable option writes the usage to stderr and fails"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ] ; then
    echo "Tests FAILED"
else
    echo "All analyzeInfoFiles tests passed"
fi

if [ "x$COVER" != "x" ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover ${COVER_DB} > cover.log 2>&1
    # '--ignore inconsistent' for the same reason 'generate_coverage' in
    #   'common.tst' passes it:  Devel::Cover reports a subroutine on the line of
    #   an empty stub and no statement there, which the .info consistency check
    #   rejects
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB} --ignore inconsistent
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch
fi

[ $FAIL -eq 0 ]
