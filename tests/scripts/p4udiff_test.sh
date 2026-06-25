#!/usr/bin/env bash
#
# Test suite for scripts/p4udiff
#
# p4udiff generates a unified diff between two Perforce changelists.
# All p4 sub-commands are intercepted by a fake 'p4' script placed at
# the front of PATH.  Each sub-command's output is controlled via env vars:
#
#   P4U_TOPDIR     - local sandbox directory (must exist; set per test)
#   P4U_BASE_CL    - base changelist number  (default 100)
#   P4U_CURR_CL    - current changelist number (default 200)
#   P4U_FILES_BASE - path to file with "p4 files @base" output
#   P4U_FILES_CURR - path to file with "p4 files @curr" output
#   P4U_FILES_SANDBOX - path to file with "p4 files" (no @CL) output
#   P4U_DIFF       - path to file with "p4 diff -du" output
#   P4U_PRINT      - path to file with "p4 print -q" output
#   P4U_OPENED     - path to file with "p4 opened" output
#   P4U_FSTAT_EXIT - exit code for "p4 fstat" (default 1)
#
# Tests:
#   1.  --help exits 1 and prints usage
#   2.  Unknown option exits 1 and prints usage
#   3.  Two positional args (too few) exits 1
#   4.  Four positional args (too many) exits 1
#   5.  Basic modified file: diff output with timestamp stripped
#   6.  Unchanged file in union emits "p4 diff" + "===" entry
#   7.  --no-unchanged suppresses the "===" entry
#   8.  Deleted file (base only): p4 print content with "-" prefix
#   9.  Added file (curr only), non-local: p4 print content with "+" prefix
#  10.  Added file (curr only), local file exists: reads from local file
#  11.  --exclude removes matching file from all output
#  12.  --include limits output to matching files
#  13.  Exclude wins over include when both match same file
#  14.  Comma-separated --exclude filters multiple patterns
#  15.  Comma-separated --include limits to multiple patterns
#  16.  -b accepted without error (parsed but not forwarded to p4 diff)
#  17.  curr_changelist="sandbox": p4 opened overlays curr file list
#  18.  Binary type file skipped (not text/symlink)
#  19.  Base file with "delete" action, not in curr: skipped silently
#  20.  Duplicate depot path in p4 files output: warning, second ignored
#  21.  Timestamp on "---" line stripped before path extraction
#  22.  File in diff but excluded: skip=1, no --- / +++ / hunk output

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

P4UDIFF="$SCRIPT_DIR/p4udiff"
if [ ! -x "$P4UDIFF" ] ; then
    echo "p4udiff script not found at '$P4UDIFF'" >&2
    exit 1
fi
[ -n "$COVER" ] && P4UDIFF="$COVER $P4UDIFF"

PASS=0
FAIL=0

pass() { echo "PASS: $1" ; ((PASS++)) ; }
fail() { echo "FAIL: $1" ; ((FAIL++)) ; if [ "$KEEP_GOING" != 1 ] ; then exit 1 ; fi ; }

# ---------------------------------------------------------------------------
# Install fake p4 at front of PATH
# ---------------------------------------------------------------------------
MOCKDIR=$(mktemp -d)
TOPDIR=$(mktemp -d)         # shared sandbox directory for most tests
trap 'rm -rf "$MOCKDIR" "$TOPDIR"' EXIT

export P4U_TOPDIR="$TOPDIR"
export P4U_BASE_CL=100
export P4U_CURR_CL=200

cat > "$MOCKDIR/p4" << 'FAKEP4'
#!/usr/bin/env bash
# Fake p4 for p4udiff testing.
SUBCMD="$1"; shift
case "$SUBCMD" in
    where)
        # Return depot/workspace/sandbox triple with /... suffix so the script
        # strips them and gets: depot_path=$P4U_TOPDIR sandbox_path=$P4U_TOPDIR
        echo "${P4U_TOPDIR}/... /workspace/test ${P4U_TOPDIR}/..."
        ;;
    files)
        # $1 is the path arg (e.g. /tmp/dir/...@100 or /tmp/dir/...)
        if [[ "$1" == *"@${P4U_BASE_CL:-100}" ]]; then
            [ -n "${P4U_FILES_BASE:-}" ] && cat "${P4U_FILES_BASE}"
        elif [[ "$1" == *"@${P4U_CURR_CL:-200}" ]]; then
            [ -n "${P4U_FILES_CURR:-}" ] && cat "${P4U_FILES_CURR}"
        else
            [ -n "${P4U_FILES_SANDBOX:-}" ] && cat "${P4U_FILES_SANDBOX}"
        fi
        ;;
    fstat)
        exit "${P4U_FSTAT_EXIT:-1}"
        ;;
    opened)
        [ -n "${P4U_OPENED:-}" ] && cat "${P4U_OPENED}"
        ;;
    diff)
        [ -n "${P4U_DIFF:-}" ] && cat "${P4U_DIFF}"
        exit "${P4U_DIFF_EXIT:-0}"
        ;;
    print)
        [ -n "${P4U_PRINT:-}" ] && cat "${P4U_PRINT}"
        ;;
    *)
        exit 1
        ;;
esac
exit 0
FAKEP4
chmod +x "$MOCKDIR/p4"
export PATH="$MOCKDIR:$PATH"

# ---------------------------------------------------------------------------
# Helper: create a temp file from stdin, print its path
# ---------------------------------------------------------------------------
mk_tmpfile() { local f; f=$(mktemp); cat > "$f"; echo "$f"; }

# ---------------------------------------------------------------------------
# Helper: run p4udiff, capture OUTPUT and RC
# ---------------------------------------------------------------------------
run_p4udiff() {
    OUTPUT=$($P4UDIFF "$@" 2>&1)
    RC=$?
}

# ===========================================================================
# Tests 1-4: Argument validation
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 1: --help exits 1 and prints usage
# ---------------------------------------------------------------------------
run_p4udiff --help "$TOPDIR" 100 200
if [ $RC -ne 1 ] ; then
    fail "Test 1 --help: expected exit 1, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 1 --help: usage not in output; got: $OUTPUT"
else
    pass "Test 1: --help exits 1 and prints usage"
fi

# ---------------------------------------------------------------------------
# Test 2: Unknown option exits 1 and prints usage
# ---------------------------------------------------------------------------
run_p4udiff --no-such-option "$TOPDIR" 100 200
if [ $RC -ne 1 ] ; then
    fail "Test 2 bad-option: expected exit 1, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 2 bad-option: usage not in output"
else
    pass "Test 2: unknown option rejected with usage"
fi

# ---------------------------------------------------------------------------
# Test 3: Two positional args (too few) exits 1
# ---------------------------------------------------------------------------
run_p4udiff "$TOPDIR" 100
if [ $RC -ne 1 ] ; then
    fail "Test 3 two-args: expected exit 1, got $RC"
else
    pass "Test 3: two positional args rejected"
fi

# ---------------------------------------------------------------------------
# Test 4: Four positional args (too many) exits 1
# ---------------------------------------------------------------------------
run_p4udiff "$TOPDIR" 100 200 extra
if [ $RC -ne 1 ] ; then
    fail "Test 4 four-args: expected exit 1, got $RC"
else
    pass "Test 4: four positional args rejected"
fi

# ===========================================================================
# Tests 5-22: Functional tests
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 5: Basic modified file -- timestamp on --- stripped, diff output correct
#
# Setup: foo.c in base (edit@100) and curr (edit@200).
# The union loop will NOT emit foo.c (--- processing removes it from %union).
# Output: stripped --- / +++ lines plus the hunk.
# ---------------------------------------------------------------------------
FB5=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
EOF
)
FC5=$(mk_tmpfile << EOF
$TOPDIR/foo.c#2 - edit change 200 (text)
EOF
)
# Diff has a timestamp on the --- line (must be stripped)
FD5=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/foo.c	2024-01-15 10:00:00.000 +0000" \
    "+++ $TOPDIR/foo.c" \
    "@@ -1 +1 @@" \
    "-old line" \
    "+new line" > "$FD5"

export P4U_FILES_BASE="$FB5"
export P4U_FILES_CURR="$FC5"
export P4U_DIFF="$FD5"
unset P4U_PRINT P4U_OPENED

run_p4udiff "$TOPDIR" 100 200
rm -f "$FB5" "$FC5" "$FD5"

if [ $RC -ne 0 ] ; then
    fail "Test 5 basic-diff: expected exit 0, got $RC; output: $OUTPUT"
else
    L1=$(echo "$OUTPUT" | head -1)
    L2=$(echo "$OUTPUT" | sed -n '2p')
    L3=$(echo "$OUTPUT" | sed -n '3p')
    OK=1
    # --- line must NOT have the timestamp
    [ "$L1" = "--- $TOPDIR/foo.c" ] || OK=0
    [ "$L2" = "+++ $TOPDIR/foo.c" ] || OK=0
    [ "$L3" = "@@ -1 +1 @@"        ] || OK=0
    [ $OK -eq 1 ] && pass "Test 5: basic diff with timestamp stripped" ||
        fail "Test 5 basic-diff: unexpected output:
$OUTPUT"
fi

# ---------------------------------------------------------------------------
# Test 6: Unchanged file -- emits "p4 diff ...#rev name" + "=== name" line
#
# Setup: foo.c changed (in diff), bar.c unchanged (not in diff).
# bar.c stays in %union with value 1 -> union loop emits === entry.
# ---------------------------------------------------------------------------
FB6=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
$TOPDIR/bar.c#3 - edit change 100 (text)
EOF
)
FC6=$(mk_tmpfile << EOF
$TOPDIR/foo.c#2 - edit change 200 (text)
$TOPDIR/bar.c#3 - edit change 200 (text)
EOF
)
FD6=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/foo.c" \
    "+++ $TOPDIR/foo.c" \
    "@@ -1 +1 @@" \
    "-old" \
    "+new" > "$FD6"

export P4U_FILES_BASE="$FB6"
export P4U_FILES_CURR="$FC6"
export P4U_DIFF="$FD6"
unset P4U_PRINT P4U_OPENED

run_p4udiff "$TOPDIR" 100 200
rm -f "$FB6" "$FC6" "$FD6"

if [ $RC -ne 0 ] ; then
    fail "Test 6 unchanged: expected exit 0, got $RC; output: $OUTPUT"
else
    if ! echo "$OUTPUT" | grep -qF -- "=== $TOPDIR/bar.c" ; then
        fail "Test 6 unchanged: expected '=== $TOPDIR/bar.c'; output:
$OUTPUT"
    elif ! echo "$OUTPUT" | grep -q "p4 diff $TOPDIR/bar.c#3" ; then
        fail "Test 6 unchanged: expected 'p4 diff' line for bar.c; output:
$OUTPUT"
    else
        pass "Test 6: unchanged file emits p4-diff header and === entry"
    fi
fi

# ---------------------------------------------------------------------------
# Test 7: --no-unchanged suppresses the === entry for unchanged file
# ---------------------------------------------------------------------------
FB7=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
$TOPDIR/bar.c#3 - edit change 100 (text)
EOF
)
FC7=$(mk_tmpfile << EOF
$TOPDIR/foo.c#2 - edit change 200 (text)
$TOPDIR/bar.c#3 - edit change 200 (text)
EOF
)
FD7=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/foo.c" \
    "+++ $TOPDIR/foo.c" \
    "@@ -1 +1 @@" \
    "-old" \
    "+new" > "$FD7"

export P4U_FILES_BASE="$FB7"
export P4U_FILES_CURR="$FC7"
export P4U_DIFF="$FD7"
unset P4U_PRINT P4U_OPENED

run_p4udiff --no-unchanged "$TOPDIR" 100 200
rm -f "$FB7" "$FC7" "$FD7"

if [ $RC -ne 0 ] ; then
    fail "Test 7 no-unchanged: expected exit 0, got $RC"
elif echo "$OUTPUT" | grep -qF '===' ; then
    fail "Test 7 no-unchanged: unexpected === entry; output: $OUTPUT"
else
    pass "Test 7: --no-unchanged suppresses === entry"
fi

# ---------------------------------------------------------------------------
# Test 8: Deleted file (in base, absent from curr)
#   union{f}==0 -> emits p4-diff header, index, --- file, +++ /dev/null,
#   @@ hunk with "-" prefixed lines from p4 print
# ---------------------------------------------------------------------------
FB8=$(mk_tmpfile << EOF
$TOPDIR/gone.c#2 - edit change 100 (text)
EOF
)
# curr: empty (file deleted)
FC8=$(mk_tmpfile << EOF
EOF
)
# diff: empty (no diff output for deleted file; handled by union loop)
FD8=$(mk_tmpfile << EOF
EOF
)
# p4 print output for gone.c#2
FP8=$(mk_tmpfile << EOF
line one
line two
EOF
)

export P4U_FILES_BASE="$FB8"
export P4U_FILES_CURR="$FC8"
export P4U_DIFF="$FD8"
export P4U_PRINT="$FP8"
unset P4U_OPENED

run_p4udiff "$TOPDIR" 100 200
rm -f "$FB8" "$FC8" "$FD8" "$FP8"

if [ $RC -ne 0 ] ; then
    fail "Test 8 deleted: expected exit 0, got $RC; output: $OUTPUT"
else
    OK=1
    echo "$OUTPUT" | grep -qF -- "--- $TOPDIR/gone.c"  || OK=0
    echo "$OUTPUT" | grep -qF -- "+++ /dev/null"        || OK=0
    echo "$OUTPUT" | grep -qF -- "@@ 1,2 0,0 @@"       || OK=0
    echo "$OUTPUT" | grep -qF -- "-line one"            || OK=0
    echo "$OUTPUT" | grep -qF -- "-line two"            || OK=0
    [ $OK -eq 1 ] && pass "Test 8: deleted file emits --- file +++ /dev/null with - prefixed content" ||
        fail "Test 8 deleted: unexpected output:
$OUTPUT"
fi
unset P4U_PRINT

# ---------------------------------------------------------------------------
# Test 9: Added file (in curr, absent from base) -- reads from p4 print
#   union{f}==2 -> "new file mode", index, --- /dev/null, +++ file,
#   @@ hunk with "+" prefixed lines from p4 print
# ---------------------------------------------------------------------------
# base: empty
FB9=$(mk_tmpfile << EOF
EOF
)
FC9=$(mk_tmpfile << EOF
$TOPDIR/new.c#1 - add change 200 (text)
EOF
)
FD9=$(mk_tmpfile << EOF
EOF
)
FP9=$(mk_tmpfile << EOF
int main(void) { return 0; }
EOF
)

export P4U_FILES_BASE="$FB9"
export P4U_FILES_CURR="$FC9"
export P4U_DIFF="$FD9"
export P4U_PRINT="$FP9"
unset P4U_OPENED

# new.c must NOT exist locally so p4udiff falls through to p4 print path
run_p4udiff "$TOPDIR" 100 200
rm -f "$FB9" "$FC9" "$FD9" "$FP9"

if [ $RC -ne 0 ] ; then
    fail "Test 9 added-p4print: expected exit 0, got $RC; output: $OUTPUT"
else
    OK=1
    echo "$OUTPUT" | grep -qF -- "new file mode"                  || OK=0
    echo "$OUTPUT" | grep -qF -- "--- /dev/null"                  || OK=0
    echo "$OUTPUT" | grep -qF -- "+++ $TOPDIR/new.c"              || OK=0
    echo "$OUTPUT" | grep -qF -- "@@ 0,0 1,1 @@"                 || OK=0
    echo "$OUTPUT" | grep -qF -- "+int main(void) { return 0; }" || OK=0
    [ $OK -eq 1 ] && pass "Test 9: added file emits new-file-mode + p4-print content" ||
        fail "Test 9 added-p4print: unexpected output:
$OUTPUT"
fi
unset P4U_PRINT

# ---------------------------------------------------------------------------
# Test 10: Added file, local file exists -- reads from local file (not p4 print)
# ---------------------------------------------------------------------------
LOCAL10="$TOPDIR/local_new.c"
printf 'local content line\n' > "$LOCAL10"

FB10=$(mk_tmpfile << EOF
EOF
)
FC10=$(mk_tmpfile << EOF
$TOPDIR/local_new.c#1 - add change 200 (text)
EOF
)
FD10=$(mk_tmpfile << EOF
EOF
)

export P4U_FILES_BASE="$FB10"
export P4U_FILES_CURR="$FC10"
export P4U_DIFF="$FD10"
unset P4U_PRINT P4U_OPENED

run_p4udiff "$TOPDIR" 100 200
rm -f "$FB10" "$FC10" "$FD10" "$LOCAL10"

if [ $RC -ne 0 ] ; then
    fail "Test 10 added-local: expected exit 0, got $RC; output: $OUTPUT"
else
    if ! echo "$OUTPUT" | grep -qF -- "+local content line" ; then
        fail "Test 10 added-local: expected '+local content line'; output:
$OUTPUT"
    else
        pass "Test 10: added local file read from filesystem not p4 print"
    fi
fi

# ---------------------------------------------------------------------------
# Test 11: --exclude removes matching file from all output
# ---------------------------------------------------------------------------
FB11=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
$TOPDIR/secret.c#1 - edit change 100 (text)
EOF
)
FC11=$(mk_tmpfile << EOF
$TOPDIR/foo.c#2 - edit change 200 (text)
$TOPDIR/secret.c#2 - edit change 200 (text)
EOF
)
FD11=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/foo.c" \
    "+++ $TOPDIR/foo.c" \
    "@@ -1 +1 @@" \
    "-old" \
    "+new" > "$FD11"

export P4U_FILES_BASE="$FB11"
export P4U_FILES_CURR="$FC11"
export P4U_DIFF="$FD11"
unset P4U_PRINT P4U_OPENED

run_p4udiff --exclude 'secret\.c' "$TOPDIR" 100 200
rm -f "$FB11" "$FC11" "$FD11"

if [ $RC -ne 0 ] ; then
    fail "Test 11 exclude: expected exit 0, got $RC"
elif echo "$OUTPUT" | grep -q 'secret\.c\|secret.c' ; then
    fail "Test 11 exclude: excluded 'secret.c' still appears; output:
$OUTPUT"
else
    pass "Test 11: --exclude removes matching file from all output"
fi

# ---------------------------------------------------------------------------
# Test 12: --include limits output to matching files only
# ---------------------------------------------------------------------------
FB12=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
$TOPDIR/bar.c#1 - edit change 100 (text)
EOF
)
FC12=$(mk_tmpfile << EOF
$TOPDIR/foo.c#2 - edit change 200 (text)
$TOPDIR/bar.c#1 - edit change 200 (text)
EOF
)
FD12=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/foo.c" \
    "+++ $TOPDIR/foo.c" \
    "@@ -1 +1 @@" \
    "-old" \
    "+new" > "$FD12"

export P4U_FILES_BASE="$FB12"
export P4U_FILES_CURR="$FC12"
export P4U_DIFF="$FD12"
unset P4U_PRINT P4U_OPENED

run_p4udiff --include 'foo\.c' "$TOPDIR" 100 200
rm -f "$FB12" "$FC12" "$FD12"

if [ $RC -ne 0 ] ; then
    fail "Test 12 include: expected exit 0, got $RC"
else
    if ! echo "$OUTPUT" | grep -q 'foo.c' ; then
        fail "Test 12 include: 'foo.c' not found; output: $OUTPUT"
    elif echo "$OUTPUT" | grep -q 'bar.c' ; then
        fail "Test 12 include: non-included 'bar.c' appears; output:
$OUTPUT"
    else
        pass "Test 12: --include limits output to matching files"
    fi
fi

# ---------------------------------------------------------------------------
# Test 13: Exclude wins over include when both match same file
# ---------------------------------------------------------------------------
FB13=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
$TOPDIR/bar.c#1 - edit change 100 (text)
EOF
)
FC13=$(mk_tmpfile << EOF
$TOPDIR/foo.c#2 - edit change 200 (text)
$TOPDIR/bar.c#2 - edit change 200 (text)
EOF
)
# diff only shows bar.c; foo.c is excluded so it must not appear in union
# and therefore not in the diff output either
FD13=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/bar.c" \
    "+++ $TOPDIR/bar.c" \
    "@@ -1 +1 @@" \
    "-old" \
    "+new" > "$FD13"

export P4U_FILES_BASE="$FB13"
export P4U_FILES_CURR="$FC13"
export P4U_DIFF="$FD13"
unset P4U_PRINT P4U_OPENED

# --include '\.c' matches both; --exclude 'foo\.c' matches only foo.c -> exclude wins for foo.c
run_p4udiff --include '\.c' --exclude 'foo\.c' "$TOPDIR" 100 200
rm -f "$FB13" "$FC13" "$FD13"

if [ $RC -ne 0 ] ; then
    fail "Test 13 excl-wins: expected exit 0, got $RC; output: $OUTPUT"
elif echo "$OUTPUT" | grep -q 'foo.c' ; then
    fail "Test 13 excl-wins: foo.c should be excluded; output: $OUTPUT"
else
    pass "Test 13: exclude wins over include when both match"
fi

# ---------------------------------------------------------------------------
# Test 14: Comma-separated --exclude filters both patterns
# ---------------------------------------------------------------------------
FB14=$(mk_tmpfile << EOF
$TOPDIR/alpha.c#1 - edit change 100 (text)
$TOPDIR/beta.c#1 - edit change 100 (text)
$TOPDIR/keep.c#1 - edit change 100 (text)
EOF
)
FC14=$(mk_tmpfile << EOF
$TOPDIR/alpha.c#2 - edit change 200 (text)
$TOPDIR/beta.c#2 - edit change 200 (text)
$TOPDIR/keep.c#2 - edit change 200 (text)
EOF
)
FD14=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/keep.c" \
    "+++ $TOPDIR/keep.c" \
    "@@ -1 +1 @@" \
    "-x" \
    "+y" > "$FD14"

export P4U_FILES_BASE="$FB14"
export P4U_FILES_CURR="$FC14"
export P4U_DIFF="$FD14"
unset P4U_PRINT P4U_OPENED

run_p4udiff --exclude 'alpha\.c,beta\.c' "$TOPDIR" 100 200
rm -f "$FB14" "$FC14" "$FD14"

if [ $RC -ne 0 ] ; then
    fail "Test 14 exclude-comma: expected exit 0, got $RC"
elif echo "$OUTPUT" | grep -qE 'alpha\.?c|beta\.?c' ; then
    fail "Test 14 exclude-comma: excluded files still appear; output:
$OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'keep.c' ; then
    fail "Test 14 exclude-comma: non-excluded 'keep.c' missing; output: $OUTPUT"
else
    pass "Test 14: comma-separated --exclude filters both patterns"
fi

# ---------------------------------------------------------------------------
# Test 15: Comma-separated --include limits to both patterns
# ---------------------------------------------------------------------------
FB15=$(mk_tmpfile << EOF
$TOPDIR/alpha.c#1 - edit change 100 (text)
$TOPDIR/beta.c#1 - edit change 100 (text)
$TOPDIR/other.c#1 - edit change 100 (text)
EOF
)
FC15=$(mk_tmpfile << EOF
$TOPDIR/alpha.c#2 - edit change 200 (text)
$TOPDIR/beta.c#2 - edit change 200 (text)
$TOPDIR/other.c#2 - edit change 200 (text)
EOF
)
FD15=$(mktemp)
# diff only touches alpha and beta; other is unchanged
printf '%s\n' \
    "--- $TOPDIR/alpha.c" \
    "+++ $TOPDIR/alpha.c" \
    "@@ -1 +1 @@" \
    "-a" \
    "+A" \
    "--- $TOPDIR/beta.c" \
    "+++ $TOPDIR/beta.c" \
    "@@ -1 +1 @@" \
    "-b" \
    "+B" > "$FD15"

export P4U_FILES_BASE="$FB15"
export P4U_FILES_CURR="$FC15"
export P4U_DIFF="$FD15"
unset P4U_PRINT P4U_OPENED

run_p4udiff --include 'alpha\.c,beta\.c' "$TOPDIR" 100 200
rm -f "$FB15" "$FC15" "$FD15"

if [ $RC -ne 0 ] ; then
    fail "Test 15 include-comma: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -q 'alpha.c' ; then
    fail "Test 15 include-comma: 'alpha.c' not found; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'beta.c' ; then
    fail "Test 15 include-comma: 'beta.c' not found; output: $OUTPUT"
elif echo "$OUTPUT" | grep -q 'other.c' ; then
    fail "Test 15 include-comma: non-included 'other.c' appears; output:
$OUTPUT"
else
    pass "Test 15: comma-separated --include limits to both patterns"
fi

# ---------------------------------------------------------------------------
# Test 16: -b accepted without error (parsed but not forwarded to p4 diff)
# ---------------------------------------------------------------------------
FB16=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
EOF
)
FC16=$(mk_tmpfile << EOF
$TOPDIR/foo.c#2 - edit change 200 (text)
EOF
)
FD16=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/foo.c" \
    "+++ $TOPDIR/foo.c" \
    "@@ -1 +1 @@" \
    "-old" \
    "+new" > "$FD16"

export P4U_FILES_BASE="$FB16"
export P4U_FILES_CURR="$FC16"
export P4U_DIFF="$FD16"
unset P4U_PRINT P4U_OPENED

run_p4udiff -b "$TOPDIR" 100 200
rm -f "$FB16" "$FC16" "$FD16"

if [ $RC -ne 0 ] ; then
    fail "Test 16 -b: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qF -- "--- $TOPDIR/foo.c" ; then
    fail "Test 16 -b: expected diff output; got: $OUTPUT"
else
    pass "Test 16: -b flag accepted without error"
fi

# ---------------------------------------------------------------------------
# Test 17: curr_changelist="sandbox" -- p4 opened overlays curr file list
#   Base: foo.c#1 (edit@100)
#   Curr (workspace, no @CL): foo.c#1 (edit@100) -- same revision present
#   Opened: foo.c opened for edit (overrides curr entry)
#   Diff (no curr CL in cmd): shows the change
# ---------------------------------------------------------------------------
FB17=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
EOF
)
# For sandbox curr, no @CL -- returns current workspace files
FS17=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
EOF
)
# p4 opened entry (overwrite=1, so it overrides the curr entry)
FO17=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 101 (text)
EOF
)
FD17=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/foo.c" \
    "+++ $TOPDIR/foo.c" \
    "@@ -1 +1 @@" \
    "-sandbox old" \
    "+sandbox new" > "$FD17"

export P4U_FILES_BASE="$FB17"
export P4U_FILES_SANDBOX="$FS17"
export P4U_OPENED="$FO17"
export P4U_DIFF="$FD17"
unset P4U_FILES_CURR P4U_PRINT

run_p4udiff "$TOPDIR" 100 sandbox
rm -f "$FB17" "$FS17" "$FO17" "$FD17"
unset P4U_FILES_SANDBOX P4U_OPENED

if [ $RC -ne 0 ] ; then
    fail "Test 17 sandbox: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qF -- "--- $TOPDIR/foo.c" ; then
    fail "Test 17 sandbox: expected diff output; got: $OUTPUT"
else
    pass "Test 17: sandbox changelist path -- p4 opened overlays curr list"
fi

# ---------------------------------------------------------------------------
# Test 18: Binary type file skipped (P4FileList::append skips binary)
# ---------------------------------------------------------------------------
FB18=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
$TOPDIR/image.png#1 - edit change 100 (binary)
EOF
)
FC18=$(mk_tmpfile << EOF
$TOPDIR/foo.c#2 - edit change 200 (text)
$TOPDIR/image.png#2 - edit change 200 (binary)
EOF
)
FD18=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/foo.c" \
    "+++ $TOPDIR/foo.c" \
    "@@ -1 +1 @@" \
    "-old" \
    "+new" > "$FD18"

export P4U_FILES_BASE="$FB18"
export P4U_FILES_CURR="$FC18"
export P4U_DIFF="$FD18"
unset P4U_PRINT P4U_OPENED

run_p4udiff "$TOPDIR" 100 200
rm -f "$FB18" "$FC18" "$FD18"

if [ $RC -ne 0 ] ; then
    fail "Test 18 binary: expected exit 0, got $RC; output: $OUTPUT"
elif echo "$OUTPUT" | grep -q 'image\.png\|image.png' ; then
    fail "Test 18 binary: binary file should be skipped; output:
$OUTPUT"
else
    pass "Test 18: binary type file skipped from file lists"
fi

# ---------------------------------------------------------------------------
# Test 19: Base file with "delete" action, not in curr -- skipped silently
#   The union loop condition: action =~ /delete/ && !(defined(c) && c->action !~ /delete/)
#   When base is delete and curr is absent -> skip (remove from curr, continue)
# ---------------------------------------------------------------------------
FB19=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
$TOPDIR/gone.c#5 - delete change 100 (text)
EOF
)
FC19=$(mk_tmpfile << EOF
$TOPDIR/foo.c#2 - edit change 200 (text)
EOF
)
FD19=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/foo.c" \
    "+++ $TOPDIR/foo.c" \
    "@@ -1 +1 @@" \
    "-old" \
    "+new" > "$FD19"

export P4U_FILES_BASE="$FB19"
export P4U_FILES_CURR="$FC19"
export P4U_DIFF="$FD19"
unset P4U_PRINT P4U_OPENED

run_p4udiff "$TOPDIR" 100 200
rm -f "$FB19" "$FC19" "$FD19"

if [ $RC -ne 0 ] ; then
    fail "Test 19 base-delete: expected exit 0, got $RC; output: $OUTPUT"
elif echo "$OUTPUT" | grep -q 'gone.c' ; then
    fail "Test 19 base-delete: base-deleted file appears in output; output:
$OUTPUT"
else
    pass "Test 19: base file with delete action silently skipped"
fi

# ---------------------------------------------------------------------------
# Test 20: Duplicate depot path in p4 files output -- warning, second ignored
# ---------------------------------------------------------------------------
FB20=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
$TOPDIR/foo.c#2 - edit change 100 (text)
EOF
)
FC20=$(mk_tmpfile << EOF
$TOPDIR/foo.c#3 - edit change 200 (text)
EOF
)
FD20=$(mktemp)
printf '%s\n' \
    "--- $TOPDIR/foo.c" \
    "+++ $TOPDIR/foo.c" \
    "@@ -1 +1 @@" \
    "-old" \
    "+new" > "$FD20"

export P4U_FILES_BASE="$FB20"
export P4U_FILES_CURR="$FC20"
export P4U_DIFF="$FD20"
unset P4U_PRINT P4U_OPENED

run_p4udiff "$TOPDIR" 100 200
rm -f "$FB20" "$FC20" "$FD20"

if [ $RC -ne 0 ] ; then
    fail "Test 20 duplicate: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qi 'WARNING\|warning\|skipping' ; then
    fail "Test 20 duplicate: expected warning about duplicate path; output:
$OUTPUT"
else
    pass "Test 20: duplicate depot path produces warning and second is ignored"
fi

# ---------------------------------------------------------------------------
# Test 21: Timestamp with sub-second and timezone on --- stripped correctly
#   "--- file  2024-01-15 10:00:00.123 -0800" -> "--- file"
# ---------------------------------------------------------------------------
FB21=$(mk_tmpfile << EOF
$TOPDIR/foo.c#1 - edit change 100 (text)
EOF
)
FC21=$(mk_tmpfile << EOF
$TOPDIR/foo.c#2 - edit change 200 (text)
EOF
)
FD21=$(mktemp)
# Both --- and +++ have timestamps separated by a tab (real p4 diff format).
# The script strips \s+<timestamp> from the end, leaving a clean path.
# Use echo to avoid shell printf treating "---" as flags.
echo "--- $TOPDIR/foo.c	2024-01-15 10:00:00.123 -0800" > "$FD21"
echo "+++ $TOPDIR/foo.c	2024-01-15 10:00:01.456 -0800" >> "$FD21"
echo "@@ -1 +1 @@"  >> "$FD21"
echo "-old"         >> "$FD21"
echo "+new"         >> "$FD21"

export P4U_FILES_BASE="$FB21"
export P4U_FILES_CURR="$FC21"
export P4U_DIFF="$FD21"
unset P4U_PRINT P4U_OPENED

run_p4udiff "$TOPDIR" 100 200
rm -f "$FB21" "$FC21" "$FD21"

if [ $RC -ne 0 ] ; then
    fail "Test 21 timestamp-strip: expected exit 0, got $RC; output: $OUTPUT"
else
    L1=$(echo "$OUTPUT" | head -1)
    L2=$(echo "$OUTPUT" | sed -n '2p')
    if [ "$L1" != "--- $TOPDIR/foo.c" ] ; then
        fail "Test 21 timestamp-strip: --- still has timestamp: '$L1'"
    elif [ "$L2" != "+++ $TOPDIR/foo.c" ] ; then
        fail "Test 21 timestamp-strip: +++ still has timestamp: '$L2'"
    else
        pass "Test 21: sub-second + timezone timestamp stripped from --- and +++"
    fi
fi

# ---------------------------------------------------------------------------
# Test 22: Base file with "delete" action but curr has it as "edit" -- the
#   condition (base->action =~ /delete/ && !(defined(c) && c->action !~ /delete/))
#   is FALSE when curr exists and is not delete -> file treated normally in union.
#   Result: foo.c should appear as modified (diff shows change), not silently skipped.
# ---------------------------------------------------------------------------
FB22=$(mk_tmpfile << EOF
$TOPDIR/foo.c#4 - delete change 100 (text)
EOF
)
# curr re-adds it as an edit (branch from delete)
FC22=$(mk_tmpfile << EOF
$TOPDIR/foo.c#5 - edit change 200 (text)
EOF
)
FD22=$(mktemp)
echo "--- $TOPDIR/foo.c" > "$FD22"
echo "+++ $TOPDIR/foo.c" >> "$FD22"
echo "@@ -1 +1 @@"        >> "$FD22"
echo "-deleted content"   >> "$FD22"
echo "+restored content"  >> "$FD22"

export P4U_FILES_BASE="$FB22"
export P4U_FILES_CURR="$FC22"
export P4U_DIFF="$FD22"
unset P4U_PRINT P4U_OPENED

run_p4udiff "$TOPDIR" 100 200
rm -f "$FB22" "$FC22" "$FD22"

if [ $RC -ne 0 ] ; then
    fail "Test 22 delete-then-edit: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'foo.c' ; then
    fail "Test 22 delete-then-edit: expected foo.c in output (delete+curr-edit); output: $OUTPUT"
else
    pass "Test 22: base-delete + curr-edit: file not skipped, appears in diff output"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ] ; then
    echo "Tests FAILED"
else
    echo "All p4udiff tests passed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover ${COVER_DB}
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB}
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch
fi

[ $FAIL -eq 0 ]
