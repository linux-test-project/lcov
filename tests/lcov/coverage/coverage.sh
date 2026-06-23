#!/usr/bin/env bash
#
# Exercise un-covered code paths in bin/lcov:
#   - list() / get_prefix() / shorten_filename() / shorten_number()   (--list, --list-full-path, --no-list-full-path)
#   - remove_file_patterns()                                           (--remove)
#   - merge_traces()                                                   (--intersect, --subtract)
#   - create_package() / get_package() / package_capture()            (--to-package, --from-package --capture)
#   - no_compat_libtool / opt_no_list_full_path option normalisation   (--no-compat-libtool, --no-list-full-path)
#

set +x

source ../../common.tst

# FULLINFO/TARGETINFO are exported by common.mak / runtests.py; provide
# fallbacks for direct invocation (cd coverage/ && bash coverage.sh -v)
TOPDIR=$(cd ../../../tests && pwd)/
: ${FULLINFO:="${TOPDIR}full.info"}
: ${TARGETINFO:="${TOPDIR}target.info"}

# Clean up from any prior run (explicit names to avoid colliding with
# geninfo.sh which runs concurrently in the same directory)
rm -f list_default.log list_full.log list_nofull.log list_nocompat.log \
      remove.log intersect.log subtract.log \
      to_pkg.log from_pkg.log compile.log \
      capture_nodir.log capture_proc.log capture_foo.log \
      removed.info intersect.info subtract.info from_pkg.info \
      test_pkg.tgz

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

LCOV_OPTS="$PARALLEL $PROFILE"
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

# -----------------------------------------------------------------------
# 1. --list  (exercises list(), get_prefix(), shorten_filename(),
#             shorten_number(), shorten_rate())
# -----------------------------------------------------------------------

echo "=== Test 1: --list ==="
$COVER $LCOV_TOOL $LCOV_OPTS --list "$FULLINFO" \
    >list_default.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "lcov --list failed (rc=$RC)"
else
    # expect a table with Filename header and at least one data row
    if ! grep -q "Filename" list_default.log; then
        die "--list output missing 'Filename' header"
    fi
    pass
fi

# --list-full-path: bypass prefix stripping (exercises opt_list_full_path branch)
echo "=== Test 2: --list --list-full-path ==="
$COVER $LCOV_TOOL $LCOV_OPTS --list "$FULLINFO" --list-full-path \
    >list_full.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "lcov --list --list-full-path failed (rc=$RC)"
else
    pass
fi

# --no-list-full-path: exercises opt_no_list_full_path normalisation (line 254-257)
echo "=== Test 3: --list --no-list-full-path ==="
$COVER $LCOV_TOOL $LCOV_OPTS --list "$FULLINFO" --no-list-full-path \
    >list_nofull.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "lcov --list --no-list-full-path failed (rc=$RC)"
else
    pass
fi

# -----------------------------------------------------------------------
# 2. --no-compat-libtool  (exercises no_compat_libtool branch, lines 249-252)
#    Combine with --list so lcov actually does something useful.
# -----------------------------------------------------------------------

echo "=== Test 4: --list --no-compat-libtool ==="
$COVER $LCOV_TOOL $LCOV_OPTS --list "$FULLINFO" --no-compat-libtool \
    >list_nocompat.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "lcov --list --no-compat-libtool failed (rc=$RC)"
else
    pass
fi

# -----------------------------------------------------------------------
# 3. --remove  (exercises remove_file_patterns(), lines 1605-1617)
# -----------------------------------------------------------------------

echo "=== Test 5: --remove ==="
# Remove the www/list.c entry from the full tracefile
$COVER $LCOV_TOOL $LCOV_OPTS \
    --remove "$FULLINFO" "*/www/*" \
    --output-file removed.info \
    >remove.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "lcov --remove failed (rc=$RC)"
else
    # removed.info should still exist and should not contain www/list.c
    if [[ ! -s removed.info ]]; then
        die "--remove produced empty output"
    fi
    if grep -q "www/list.c" removed.info; then
        die "--remove did not remove www/list.c"
    fi
    pass
fi

# -----------------------------------------------------------------------
# 4. --intersect  (exercises merge_traces() INTERSECT, lines 1575-1601)
# -----------------------------------------------------------------------

echo "=== Test 6: --intersect ==="
# Intersect full.info with target.info (they share the same source files).
# -o precedes the bare positional tracefile arg (required by option parsing).
$COVER $LCOV_TOOL $LCOV_OPTS \
    --output-file intersect.info \
    --ignore inconsistent \
    "$FULLINFO" --intersect "$TARGETINFO" \
    >intersect.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "lcov --intersect failed (rc=$RC)"
else
    if [[ ! -s intersect.info ]]; then
        die "--intersect produced empty output"
    fi
    pass
fi

# -----------------------------------------------------------------------
# 5. --subtract  (exercises merge_traces() DIFFERENCE, lines 1575-1601)
# -----------------------------------------------------------------------

echo "=== Test 7: --subtract ==="
$COVER $LCOV_TOOL $LCOV_OPTS \
    --output-file subtract.info \
    --ignore inconsistent,empty \
    "$FULLINFO" --subtract "$TARGETINFO" \
    >subtract.log 2>&1
RC=$?
if [[ $RC -ne 0 ]]; then
    die "lcov --subtract failed (rc=$RC)"
else
    if [[ ! -s subtract.info ]]; then
        die "--subtract produced empty output"
    fi
    pass
fi

# -----------------------------------------------------------------------
# 6. --to-package / --from-package  (exercises create_package(),
#    get_package(), package_capture(), write_file(), read_file(),
#    count_package_data() - lines 974-1139, 1469-1507)
#
#    Strategy: build a tiny C program, generate .gcda files, then
#    package them with --to-package and re-capture with --from-package.
# -----------------------------------------------------------------------

echo "=== Test 8: --to-package / --from-package ==="

if ! type ${CC} >/dev/null 2>&1; then
    echo "SKIP: no C compiler found"
else
    PKGDIR=$(mktemp -d)
    trap 'rm -rf "$PKGDIR"' EXIT

    cat > "$PKGDIR/hello.c" << 'C_SOURCE'
#include <stdio.h>
int greet(const char *name) {
    printf("hello %s\n", name);
    return 0;
}
int main(void) {
    greet("world");
    return 0;
}
C_SOURCE

    # Compile with coverage instrumentation; build and run in $PKGDIR so
    # that .gcno and .gcda both land in the same directory.
    (cd "$PKGDIR" && ${CC} --coverage -o hello hello.c 2>../compile.log)
    if [[ $? -ne 0 ]]; then
        echo "SKIP: compiler does not support --coverage"
    else
        # Run to generate .gcda alongside .gcno
        (cd "$PKGDIR" && ./hello) >/dev/null 2>&1

        # Package the raw coverage data (.gcda) from $PKGDIR
        $COVER $LCOV_TOOL $LCOV_OPTS \
            --capture --directory "$PKGDIR" \
            --to-package test_pkg.tgz \
            >to_pkg.log 2>&1
        RC=$?
        if [[ $RC -ne 0 ]]; then
            die "lcov --to-package failed (rc=$RC)"
        else
            if [[ ! -s test_pkg.tgz ]]; then
                die "--to-package produced empty package"
            fi

            # Re-capture from the package; --base-directory points to where
            # the .gcno files live so geninfo can find them
            $COVER $LCOV_TOOL $LCOV_OPTS \
                --capture --from-package test_pkg.tgz \
                --base-directory "$PKGDIR" \
                --output-file from_pkg.info \
                >from_pkg.log 2>&1
            RC=$?
            if [[ $RC -ne 0 ]]; then
                die "lcov --from-package failed (rc=$RC)"
            else
                if [[ ! -s from_pkg.info ]]; then
                    die "--from-package produced empty .info file"
                fi
                pass
            fi
        fi
    fi
fi

# -----------------------------------------------------------------------
# 7. --capture without a directory or package (exercises setup_gkv(),
#    check_gkv_sys(), check_gkv_proc() - lines 1936-2057)
#
#    On a machine with no kernel gcov support these always fail with a
#    known error.  We verify the non-zero exit and the exact message.
# -----------------------------------------------------------------------

echo "=== Test 9: --capture (no kernel gcov, auto-detect) ==="
$COVER $LCOV_TOOL $LCOV_OPTS --capture \
    >capture_nodir.log 2>&1
RC=$?
if [[ $RC -eq 0 ]]; then
    die "--capture succeeded unexpectedly (expected non-zero)"
else
    if ! grep -q "no gcov kernel data found" capture_nodir.log; then
        die "--capture missing expected error 'no gcov kernel data found'"
    fi
    pass
fi

echo "=== Test 10: --capture --rc lcov_gcov_dir=/proc (user-specified /proc) ==="
$COVER $LCOV_TOOL $LCOV_OPTS --capture \
    --rc lcov_gcov_dir=/proc \
    >capture_proc.log 2>&1
RC=$?
if [[ $RC -eq 0 ]]; then
    die "--capture --rc lcov_gcov_dir=/proc succeeded unexpectedly"
else
    if ! grep -q "could not find gcov kernel data at /proc" capture_proc.log; then
        die "--capture --rc lcov_gcov_dir=/proc missing expected error message"
    fi
    pass
fi

echo "=== Test 11: --capture --rc lcov_gcov_dir=/foo (non-existent dir) ==="
$COVER $LCOV_TOOL $LCOV_OPTS --capture \
    --rc lcov_gcov_dir=/foo \
    >capture_foo.log 2>&1
RC=$?
if [[ $RC -eq 0 ]]; then
    die "--capture --rc lcov_gcov_dir=/foo succeeded unexpectedly"
else
    if ! grep -q "could not find gcov kernel data at /foo" capture_foo.log; then
        die "--capture --rc lcov_gcov_dir=/foo missing expected error message"
    fi
    pass
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
