#!/usr/bin/env bash
#
# Test suite for scripts/get_signature
#
# get_signature is a sample '--version-script' callback:  it prints the MD5 of
# a file, and compares two such version strings.  The hash is computed in
# process (Digest::MD5) rather than by forking 'md5sum', which has no shell to
# misparse a pathname and no dependency on a program a native Windows Perl does
# not have - so several of the tests below are about pathnames rather than
# about hashes.
#
# Tests:
#   1.  --help exits 0 and prints usage
#   2.  Unknown option exits 1 and prints usage
#   3.  No filename argument exits 1
#   4.  --compare with the wrong argument count exits 1
#   5.  --compare with equal version strings exits 0
#   6.  --compare with different version strings exits 1
#   7.  Missing file without --allow-missing: dies, and says which flag helps
#   8.  Missing file with --allow-missing: empty line, exit 0
#   9.  The signature of a text file is its MD5, and the exit status is 0
#  10.  The signature matches 'md5sum' - including for binary content
#  11.  A pathname containing a space is hashed, not split
#  12.  A pathname beginning with '>' is a filename, not a redirection

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

GET_SIGNATURE="$SCRIPT_DIR/get_signature"
if [ ! -x "$GET_SIGNATURE" ] ; then
    echo "get_signature script not found at '$GET_SIGNATURE'" >&2
    exit 1
fi
[ -n "$COVER" ] && GET_SIGNATURE="$COVER $GET_SIGNATURE"

PASS=0
FAIL=0

pass() { echo "PASS: $1" ; ((PASS++)) ; }
fail() { echo "FAIL: $1" ; ((FAIL++)) ; if [ "$KEEP_GOING" != 1 ] ; then exit 1 ; fi ; }

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# ---------------------------------------------------------------------------
# Helper: run get_signature, capture OUTPUT and RC
# ---------------------------------------------------------------------------
run_get_signature() {
    OUTPUT=$($GET_SIGNATURE "$@" 2>&1)
    RC=$?
}

# the MD5 of "hello\n" - the same string 'md5sum' prints for that content
HELLO_MD5=b1946ac92492d2347c6235b4d2611184

# ===========================================================================
# Tests 1-4: argument validation
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 1: --help exits 0 and prints usage
# ---------------------------------------------------------------------------
run_get_signature --help
if [ $RC -ne 0 ] ; then
    fail "Test 1 --help: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 1 --help: usage not in output; got: $OUTPUT"
else
    pass "Test 1: --help exits 0 and prints usage"
fi

# ---------------------------------------------------------------------------
# Test 2: unknown option exits 1 and prints usage
# ---------------------------------------------------------------------------
run_get_signature --no-such-option foo
if [ $RC -ne 1 ] ; then
    fail "Test 2 bad-option: expected exit 1, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 2 bad-option: usage not in output; got: $OUTPUT"
else
    pass "Test 2: unknown option rejected with usage"
fi

# ---------------------------------------------------------------------------
# Test 3: no filename argument exits 1
# ---------------------------------------------------------------------------
run_get_signature
if [ $RC -ne 1 ] ; then
    fail "Test 3 no-args: expected exit 1, got $RC"
else
    pass "Test 3: no filename argument rejected"
fi

# ---------------------------------------------------------------------------
# Test 4: --compare wants exactly three arguments
# ---------------------------------------------------------------------------
run_get_signature --compare old new
if [ $RC -ne 1 ] ; then
    fail "Test 4 compare-argc: expected exit 1, got $RC"
else
    pass "Test 4: --compare with two arguments rejected"
fi

# ===========================================================================
# Tests 5-6: --compare
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 5: equal version strings compare equal
# ---------------------------------------------------------------------------
run_get_signature --compare "$HELLO_MD5" "$HELLO_MD5" "$WORKDIR/anything.c"
if [ $RC -ne 0 ] ; then
    fail "Test 5 compare-same: expected exit 0, got $RC; output: $OUTPUT"
else
    pass "Test 5: --compare with equal version strings exits 0"
fi

# ---------------------------------------------------------------------------
# Test 6: different version strings do not
# ---------------------------------------------------------------------------
run_get_signature --compare "$HELLO_MD5" 0123456789abcdef "$WORKDIR/anything.c"
if [ $RC -ne 1 ] ; then
    fail "Test 6 compare-differ: expected exit 1, got $RC; output: $OUTPUT"
else
    pass "Test 6: --compare with different version strings exits 1"
fi

# ===========================================================================
# Tests 7-8: a file which is not there
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 7: no --allow-missing - the error names the flag which permits it
# ---------------------------------------------------------------------------
run_get_signature "$WORKDIR/no_such_file.c"
if [ $RC -eq 0 ] ; then
    fail "Test 7 missing: expected non-zero exit; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q "does not exist.*'--allow-missing'" ; then
    fail "Test 7 missing: expected the '--allow-missing' hint; got: $OUTPUT"
else
    pass "Test 7: a missing file is an error which names --allow-missing"
fi

# ---------------------------------------------------------------------------
# Test 8: --allow-missing - an empty version string, and success
# ---------------------------------------------------------------------------
run_get_signature --allow-missing "$WORKDIR/no_such_file.c"
if [ $RC -ne 0 ] ; then
    fail "Test 8 allow-missing: expected exit 0, got $RC; output: $OUTPUT"
elif [ -n "$OUTPUT" ] ; then
    fail "Test 8 allow-missing: expected no version, got: '$OUTPUT'"
else
    pass "Test 8: --allow-missing reports a missing file as an empty version"
fi

# ===========================================================================
# Tests 9-12: the signature itself
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 9: the MD5 of a text file
# ---------------------------------------------------------------------------
printf 'hello\n' > "$WORKDIR/hello.c"
run_get_signature "$WORKDIR/hello.c"
if [ $RC -ne 0 ] ; then
    fail "Test 9 md5: expected exit 0, got $RC; output: $OUTPUT"
elif [ "$OUTPUT" != "$HELLO_MD5" ] ; then
    fail "Test 9 md5: expected '$HELLO_MD5', got: '$OUTPUT'"
else
    pass "Test 9: the signature of a file is its MD5"
fi

# ---------------------------------------------------------------------------
# Test 10: the same string 'md5sum' prints - including for binary content
#   'Digest::MD5' hashes bytes, so the file has to be read in binary mode:  on
#   a platform which translates line endings, a text-mode read would hash
#   something other than what is on disk.
# ---------------------------------------------------------------------------
if ! which md5sum >/dev/null 2>&1 ; then
    echo "md5sum not available - skipping test 10"
else
    printf 'a\000b\r\n\r\nzz\n' > "$WORKDIR/binary.dat"
    EXPECT=$(md5sum "$WORKDIR/binary.dat" | awk '{print $1}')
    run_get_signature "$WORKDIR/binary.dat"
    if [ $RC -ne 0 ] ; then
        fail "Test 10 binary: expected exit 0, got $RC; output: $OUTPUT"
    elif [ "$OUTPUT" != "$EXPECT" ] ; then
        fail "Test 10 binary: expected '$EXPECT', got: '$OUTPUT'"
    else
        pass "Test 10: the signature matches md5sum, for binary content too"
    fi
fi

# ---------------------------------------------------------------------------
# Test 11: a pathname containing a space
#   The hash used to come from 'md5sum $pathname', handed to a shell:  an
#   unquoted path with a space in it became two file arguments, so md5sum
#   printed a hash of the wrong file (or an error) and the signature was
#   whatever the first field of that turned out to be.
# ---------------------------------------------------------------------------
mkdir -p "$WORKDIR/has dir"
printf 'hello\n' > "$WORKDIR/has dir/has name.c"
run_get_signature "$WORKDIR/has dir/has name.c"
if [ $RC -ne 0 ] ; then
    fail "Test 11 space-in-path: expected exit 0, got $RC; output: $OUTPUT"
elif [ "$OUTPUT" != "$HELLO_MD5" ] ; then
    fail "Test 11 space-in-path: expected '$HELLO_MD5', got: '$OUTPUT'"
else
    pass "Test 11: a pathname containing a space is hashed, not split"
fi

# ---------------------------------------------------------------------------
# Test 12: a pathname which begins with '>'
#   A leading '>' is a redirection to a shell, and would have been a mode to a
#   2-argument 'open':  it is neither - it is the first character of the name.
# ---------------------------------------------------------------------------
printf 'hello\n' > "$WORKDIR/>odd.c"
run_get_signature "$WORKDIR/>odd.c"
if [ $RC -ne 0 ] ; then
    fail "Test 12 leading-gt: expected exit 0, got $RC; output: $OUTPUT"
elif [ "$OUTPUT" != "$HELLO_MD5" ] ; then
    fail "Test 12 leading-gt: expected '$HELLO_MD5', got: '$OUTPUT'"
else
    pass "Test 12: a pathname beginning with '>' is treated as a filename"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ] ; then
    echo "Tests FAILED"
else
    echo "All get_signature tests passed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover ${COVER_DB} > cover.log 2>&1
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB}
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch
fi

[ $FAIL -eq 0 ]
