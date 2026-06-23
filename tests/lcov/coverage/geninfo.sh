#!/usr/bin/env bash
#
# Exercise un-covered code paths in bin/geninfo.
#
# Tests are grouped by the geninfo code region exercised:
#
#   Tests 1-2   : --help / --version  (print_usage)
#   Test  3     : no directory argument  (lines 461-463)
#   Test  4     : non-existent directory  (find_files error, lines 926-935)
#   Test  5     : bad --gcov-tool path  (lines 316-323)
#   Test  6     : invalid geninfo_intermediate value  (lines 358-360)
#   Test  7     : --no-compat-libtool normalisation  (lines 291-293)
#   Test  8     : --tempdir option  (lines 283-288)
#   Test  9     : --no-recursion  (lines 454-458)
#   Test  10    : --rc geninfo_adjust_testname=1  (lines 438-441)
#   Test  11    : --rc geninfo_intermediate=1 explicit  (line 349-350)
#   Test  12    : unsupported file extension  (lines 988-995)
#   Tests 13-15 : --compat mode handling  (lines 4075-4165: parse_compat_modes,
#                  compat_name, is_compat)
#   Test  16    : --no-markers with --filter conflict  (lines 413-416)
#   Test  17    : --initial capture (process_graphfile - lines 3149-3268)
#

set +x

source ../../common.tst

# Clean up from any prior run (explicit names to avoid colliding with
# coverage.sh which runs concurrently in the same directory)
rm -f help.log version.log nodir.log nosuchdir.log badtool.log \
      badintermediate.log nocompat.log tempdir.log norecurse.log \
      adjusttest.log intermediate1.log badext.log \
      compat_libtool.log compat_hammer.log compat_unknown.log \
      nomarkers_filter.log initial.log compile.log \
      nocompat.info tempdir.info norecurse.info adjusttest.info \
      intermediate1.info compat_libtool.info compat_hammer.info \
      initial.info
rm -rf srcdir

clean_cover

if [[ 1 == $CLEAN_ONLY ]]; then
    exit 0
fi

# $PROFILE contains '--profile', an optional-string flag (:s in GetOptions)
# that silently consumes the next bare token as its output filename.  Using
# '--profile=' (with explicit '=') forces GetOptions to treat the value as the
# empty string, preventing it from consuming any subsequent positional arg.
GI_PRE="$PARALLEL"
GI_POST="${PROFILE:+${PROFILE}=}"

PASS=0
FAIL=0

die() {
    echo "Error: $*" >&2
    if [[ $KEEP_GOING != 1 ]]; then
        exit 1
    fi
    FAIL=$((FAIL + 1))
}

pass() {
    PASS=$((PASS + 1))
}

# Build a minimal instrumented program once; reused across tests that need
# real .gcda/.gcno files.
if ! type ${CC} >/dev/null 2>&1; then
    echo "SKIP: no C compiler (${CC}) found - skipping tests that require .gcda/.gcno"
    HAVE_CC=0
else
    HAVE_CC=1
    mkdir -p srcdir
    cat > srcdir/hello.c << 'C_SOURCE'
int add(int a, int b) { return a + b; }
int main(void) { return add(1,2) != 3; }
C_SOURCE
    (cd srcdir && ${CC} --coverage -o hello hello.c 2>../compile.log && ./hello)
    if [[ $? -ne 0 ]]; then
        echo "SKIP: compilation or execution failed - skipping .gcda/.gcno tests"
        HAVE_CC=0
    fi
fi

# Detect gcov format capabilities, matching geninfo's get_gcov_capabilities()
# heuristic (scan gcov --help for short option flags).
#
# GCOV_HAS_INTERMEDIATE: gcov supports -i (text intermediate format, gcov >= 4.9)
# GCOV_HAS_JSON:         gcov supports -j (JSON intermediate format, gcov >= 9)
#
# --initial with intermediate mode only works correctly when gcov uses JSON
# format (gcov >= 9).  With text intermediate format (gcov 4.9-8.x), gcov
# produces no output for .gcno-only runs, causing --initial to fail.
# Without any intermediate support (gcov < 4.9), geninfo reads the .gcno
# directly via its own parser and --initial works fine.
GCOV_HELP=$(gcov --help 2>&1)
GCOV_HAS_INTERMEDIATE=0
GCOV_HAS_JSON=0
echo "$GCOV_HELP" | grep -qE '^\s+-i[, ]' && GCOV_HAS_INTERMEDIATE=1
echo "$GCOV_HELP" | grep -qE '^\s+-j[, ]' && GCOV_HAS_JSON=1

# --initial works with: no intermediate (gcov < 4.9) or JSON intermediate (gcov >= 9)
# --initial breaks with: text intermediate only (gcov 4.9-8.x)
GCOV_INITIAL_WORKS=0
if [[ $GCOV_HAS_INTERMEDIATE -eq 0 || $GCOV_HAS_JSON -eq 1 ]]; then
    GCOV_INITIAL_WORKS=1
fi

# -----------------------------------------------------------------------
# Test 1: --help
# -----------------------------------------------------------------------
echo "=== Test 1: --help ==="
$COVER $GENINFO_TOOL $GI_PRE --help $GI_POST >help.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "geninfo --help failed (rc=$RC)"
elif ! grep -q "Usage: geninfo" help.log; then
    die "--help output missing 'Usage: geninfo'"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 2: --version
# -----------------------------------------------------------------------
echo "=== Test 2: --version ==="
$COVER $GENINFO_TOOL $GI_PRE --version $GI_POST >version.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "geninfo --version failed (rc=$RC)"
elif ! grep -q "LCOV version" version.log; then
    die "--version output missing 'LCOV version'"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 3: no directory argument  (exercises "No directory specified" path)
# -----------------------------------------------------------------------
echo "=== Test 3: no directory ==="
$COVER $GENINFO_TOOL $GI_PRE $GI_POST >nodir.log 2>&1
RC=$?
if [[ $RC -eq 0 ]]; then
    die "geninfo with no args unexpectedly succeeded"
elif ! grep -q "No directory specified" nodir.log; then
    die "geninfo no-args missing 'No directory specified'"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 4: non-existent directory
# -----------------------------------------------------------------------
echo "=== Test 4: non-existent directory ==="
$COVER $GENINFO_TOOL $GI_PRE -o /dev/null $GI_POST /no/such/dir >nosuchdir.log 2>&1
RC=$?
if [[ $RC -eq 0 ]]; then
    die "geninfo /no/such/dir unexpectedly succeeded"
elif ! grep -q "cannot read /no/such/dir" nosuchdir.log; then
    die "missing expected error for non-existent dir"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 5: bad --gcov-tool path
# -----------------------------------------------------------------------
echo "=== Test 5: bad --gcov-tool path ==="
$COVER $GENINFO_TOOL $GI_PRE --gcov-tool /no/such/gcov -o /dev/null $GI_POST . \
    >badtool.log 2>&1
RC=$?
if [[ $RC -eq 0 ]]; then
    die "geninfo --gcov-tool /no/such/gcov unexpectedly succeeded"
elif ! grep -q "cannot access gcov tool '/no/such/gcov'" badtool.log; then
    die "missing expected error for bad gcov-tool path"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 6: invalid geninfo_intermediate value
# -----------------------------------------------------------------------
echo "=== Test 6: invalid geninfo_intermediate ==="
$COVER $GENINFO_TOOL $GI_PRE --rc geninfo_intermediate=invalid \
    -o /dev/null $GI_POST . >badintermediate.log 2>&1
RC=$?
if [[ $RC -eq 0 ]]; then
    die "geninfo invalid intermediate unexpectedly succeeded"
elif ! grep -q "invalid value for geninfo_intermediate" badintermediate.log; then
    die "missing expected error for bad geninfo_intermediate"
else
    pass
fi

# -----------------------------------------------------------------------
# Remaining tests require a compiled program with .gcda/.gcno files.
# -----------------------------------------------------------------------
if [[ $HAVE_CC -eq 0 ]]; then
    echo "Skipping tests 7-17 (no C compiler)"
    echo ""
    echo "Results: $PASS passed, $FAIL failed (11 skipped)"
    exit $([[ $FAIL -gt 0 ]])
fi

# -----------------------------------------------------------------------
# Test 7: --no-compat-libtool  (exercises opt_no_compat_libtool normalisation)
# -----------------------------------------------------------------------
echo "=== Test 7: --no-compat-libtool ==="
$COVER $GENINFO_TOOL $GI_PRE --no-compat-libtool \
    -o nocompat.info $GI_POST srcdir >nocompat.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "geninfo --no-compat-libtool failed (rc=$RC)"
elif [[ ! -s nocompat.info ]]; then
    die "--no-compat-libtool produced empty .info"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 8: --tempdir  (exercises tempdirname, lines 283-288)
# -----------------------------------------------------------------------
echo "=== Test 8: --tempdir ==="
MYTMPDIR=$(mktemp -d)
$COVER $GENINFO_TOOL $GI_PRE --tempdir "$MYTMPDIR" \
    -o tempdir.info $GI_POST srcdir >tempdir.log 2>&1
RC=$?
rm -rf "$MYTMPDIR"
if [[ $RC -ne 0 ]]; then
    die "geninfo --tempdir failed (rc=$RC)"
elif [[ ! -s tempdir.info ]]; then
    die "--tempdir produced empty .info"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 9: --no-recursion  (exercises no_recursion/maxdepth, lines 454-458)
# -----------------------------------------------------------------------
echo "=== Test 9: --no-recursion ==="
$COVER $GENINFO_TOOL $GI_PRE --no-recursion \
    -o norecurse.info $GI_POST srcdir >norecurse.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "geninfo --no-recursion failed (rc=$RC)"
elif [[ ! -s norecurse.info ]]; then
    die "--no-recursion produced empty .info"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 10: --rc geninfo_adjust_testname=1  (exercises lines 438-441)
# -----------------------------------------------------------------------
echo "=== Test 10: geninfo_adjust_testname=1 ==="
$COVER $GENINFO_TOOL $GI_PRE --rc geninfo_adjust_testname=1 -t mytest \
    -o adjusttest.info $GI_POST srcdir >adjusttest.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "geninfo --rc geninfo_adjust_testname=1 failed (rc=$RC)"
elif [[ ! -s adjusttest.info ]]; then
    die "geninfo_adjust_testname produced empty .info"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 11: --rc geninfo_intermediate=1  (exercises explicit-1 branch, line 349)
# Requires gcov >= 4.9 which added the -i (intermediate format) flag.
# -----------------------------------------------------------------------
echo "=== Test 11: geninfo_intermediate=1 ==="
if [[ $GCOV_HAS_INTERMEDIATE -eq 0 ]]; then
    echo "SKIP: gcov does not support intermediate format (-i flag)"
    pass
else
    $COVER $GENINFO_TOOL $GI_PRE --rc geninfo_intermediate=1 \
        -o intermediate1.info $GI_POST srcdir >intermediate1.log 2>&1
    RC=$?
    if [[ $RC -ne 0 ]]; then
        die "geninfo --rc geninfo_intermediate=1 failed (rc=$RC)"
    elif [[ ! -s intermediate1.info ]]; then
        die "geninfo_intermediate=1 produced empty .info"
    else
        pass
    fi
fi

# -----------------------------------------------------------------------
# Test 12: unsupported file extension  (exercises lines 988-995)
# -----------------------------------------------------------------------
echo "=== Test 12: unsupported file extension ==="
TMPF=$(mktemp /tmp/tXXXX.txt)
$COVER $GENINFO_TOOL $GI_PRE -o /dev/null $GI_POST "$TMPF" >badext.log 2>&1
RC=$?
rm -f "$TMPF"
if [[ $RC -eq 0 ]]; then
    die "geninfo with .txt file unexpectedly succeeded"
elif ! grep -q "has unsupported extension" badext.log; then
    die "missing 'unsupported extension' error for .txt file"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 13: --compat libtool=on  (exercises parse_compat_modes enabling)
# -----------------------------------------------------------------------
echo "=== Test 13: --compat libtool=on ==="
$COVER $GENINFO_TOOL $GI_PRE --compat libtool=on \
    -o compat_libtool.info $GI_POST srcdir >compat_libtool.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "geninfo --compat libtool=on failed (rc=$RC)"
elif ! grep -q "Enabling compatibility mode 'libtool'" compat_libtool.log; then
    die "missing 'Enabling compatibility mode libtool' message"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 14: --compat hammer=on  (exercises hammer mode path)
# -----------------------------------------------------------------------
echo "=== Test 14: --compat hammer=on ==="
$COVER $GENINFO_TOOL $GI_PRE --compat hammer=on \
    -o compat_hammer.info $GI_POST srcdir >compat_hammer.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "geninfo --compat hammer=on failed (rc=$RC)"
elif ! grep -q "Enabling compatibility mode 'hammer'" compat_hammer.log; then
    die "missing 'Enabling compatibility mode hammer' message"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 15: --compat unknown=on  (exercises unknown mode error in parse_compat_modes)
# -----------------------------------------------------------------------
echo "=== Test 15: --compat unknown=on ==="
$COVER $GENINFO_TOOL $GI_PRE --compat unknown=on \
    -o /dev/null $GI_POST srcdir >compat_unknown.log 2>&1
RC=$?
if [[ $RC -eq 0 ]]; then
    die "geninfo --compat unknown=on unexpectedly succeeded"
elif ! grep -q "Unknown compatibility mode 'unknown'" compat_unknown.log; then
    die "missing 'Unknown compatibility mode' error"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 16: --no-markers with --filter  (exercises conflict check, lines 413-416)
# -----------------------------------------------------------------------
echo "=== Test 16: --no-markers with --filter ==="
$COVER $GENINFO_TOOL $GI_PRE --no-markers --filter branch \
    -o /dev/null $GI_POST srcdir >nomarkers_filter.log 2>&1
if ! grep -q "use new '--filter' option or old '--no-markers' - not both" \
        nomarkers_filter.log; then
    die "missing '--no-markers'/'--filter' conflict error"
else
    pass
fi

# -----------------------------------------------------------------------
# Test 17: --initial  (exercises process_graphfile, lines 3149-3268)
# Works with gcov < 4.9 (no intermediate: reads .gcno directly) and
# gcov >= 9 (JSON intermediate: gcov handles .gcno-only runs correctly).
# Fails with gcov 4.9-8.x (text intermediate: gcov produces no output
# for .gcno-only capture).
# -----------------------------------------------------------------------
echo "=== Test 17: --initial ==="
if [[ $GCOV_INITIAL_WORKS -eq 0 ]]; then
    echo "SKIP: gcov text intermediate format does not support --initial (.gcno-only) capture"
    pass
else
    $COVER $GENINFO_TOOL $GI_PRE --initial \
        -o initial.info $GI_POST srcdir >initial.log 2>&1
    RC=$?
    if [[ $RC -ne 0 ]]; then
        die "geninfo --initial failed (rc=$RC)"
    elif [[ ! -s initial.info ]]; then
        die "--initial produced empty .info"
    elif ! grep -q "^DA:" initial.info; then
        die "--initial .info has no DA: records"
    else
        pass
    fi
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 && $KEEP_GOING != 1 ]]; then
    exit 1
fi

exit 0
