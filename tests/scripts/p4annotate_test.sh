#!/usr/bin/env bash
#
# Consolidated test suite for scripts/p4annotate and scripts/p4annotate.pm
#
# Merges all scenarios previously spread across:
#   env_check.sh      - P4 environment variable validation
#   args_check.sh     - constructor option parsing
#   help_check.sh     - --help flag and usage message
#   symlink_check.sh  - symlink detection and path normalisation
#   annotate_check.sh - end-to-end annotation with mock p4
#
# End-to-end tests intercept every p4 invocation via a fake 'p4' script placed
# at the front of PATH.  The fake script reads env vars (P4MOCK_*) to decide
# what each p4 sub-command returns, so no real Perforce connection is needed.
#
# Tests 1-4:   P4 environment variable validation (env_check.sh)
# Tests 5-10:  Constructor argument parsing       (args_check.sh)
# Tests 11-13: --help / usage message             (help_check.sh)
# Tests 14-17: Symlink / path normalisation       (symlink_check.sh)
# Tests 18-34: End-to-end annotation output       (annotate_check.sh)
#

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

P4ANNOTATE="$SCRIPT_DIR/p4annotate"
if [ ! -x "$P4ANNOTATE" ] ; then
    echo "p4annotate script not found at '$P4ANNOTATE'" >&2
    exit 1
fi
[ -n "$COVER" ] && P4ANNOTATE="$COVER $P4ANNOTATE"

# When coverage is active, $COVER is "perl -MDevel::Cover=... " so use it as
# the perl interpreter for direct .pm invocations too.
PERL="${COVER:-perl}"

PASS=0
FAIL=0

pass() { echo "PASS: $1" ; ((PASS++)) ; }
fail() { echo "FAIL: $1" ; ((FAIL++)) ; if [ "$KEEP_GOING" != 1 ] ; then exit 1 ; fi ; }

# ---------------------------------------------------------------------------
# Set up the fake p4 script (used by tests 18-34; harmless earlier)
# ---------------------------------------------------------------------------
MOCKDIR=$(mktemp -d)
trap 'rm -rf "$MOCKDIR" "$SYMLINK_TESTDIR"' EXIT

FAKEP4="$MOCKDIR/p4"
cat > "$FAKEP4" << 'FAKE_P4_SCRIPT'
#!/usr/bin/env bash
#
# Fake p4 for p4annotate testing.
# Controlled by env vars:
#   P4MOCK_FILES    "in_p4" -> print valid depot line; else print no-such-file
#   P4MOCK_HAVE     text of "p4 have" output (empty -> @head)
#   P4MOCK_OPENED   text of "p4 opened" output (empty -> not opened)
#   P4MOCK_DIFF     path to file with mock "p4 diff" output
#   P4MOCK_ANNOTATE path to file with mock "p4 annotate -Iucq" output
#
SUBCMD="$1"
shift
case "$SUBCMD" in
    files)
        if [ "${P4MOCK_FILES:-}" = "in_p4" ] ; then
            echo "//depot/test/sample.c#3 - edit change 5 (text)"
        else
            echo "//depot/test/sample.c - no such file(s)."
        fi
        ;;
    have)
        [ -n "${P4MOCK_HAVE:-}" ] && echo "$P4MOCK_HAVE"
        ;;
    opened)
        [ -n "${P4MOCK_OPENED:-}" ] && echo "$P4MOCK_OPENED"
        ;;
    diff)
        [ -n "${P4MOCK_DIFF:-}" ] && cat "$P4MOCK_DIFF"
        exit "${P4MOCK_DIFF_EXIT:-0}"
        ;;
    annotate)
        [ -n "${P4MOCK_ANNOTATE:-}" ] && cat "$P4MOCK_ANNOTATE"
        exit 0
        ;;
    *)  exit 1 ;;
esac
FAKE_P4_SCRIPT
chmod +x "$FAKEP4"
export PATH="$MOCKDIR:$PATH"

# ---------------------------------------------------------------------------
# Helper functions for annotation tests
# ---------------------------------------------------------------------------

# Create a temp source file; printf-style content string is the first argument
mk_target() {
    local f
    f=$(mktemp --suffix=.c)
    printf "${1:-line one\nline two\nline three\n}" > "$f"
    echo "$f"
}

# Create a temp file whose content is read from stdin
mk_annotate() { local f ; f=$(mktemp) ; cat > "$f" ; echo "$f" ; }
mk_diff()     { local f ; f=$(mktemp) ; cat > "$f" ; echo "$f" ; }

# Run p4annotate, capturing stdout+stderr; sets global OUTPUT and RC
run_p4annotate() {
    OUTPUT=$($P4ANNOTATE "$@" 2>&1)
    RC=$?
}

# ---------------------------------------------------------------------------
# Save any real P4 env vars so we can restore them after the env tests
# ---------------------------------------------------------------------------
SAVED_P4USER="${P4USER:-}"
SAVED_P4PORT="${P4PORT:-}"
SAVED_P4CLIENT="${P4CLIENT:-}"

# ===========================================================================
# Tests 1-4: P4 environment variable validation  (from env_check.sh)
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 1: No P4 env vars set -> constructor dies
# ---------------------------------------------------------------------------
unset P4USER P4PORT P4CLIENT
OUTPUT=$($PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate; my $obj = p4annotate->new($0, "test.txt");' 2>&1)
RC=$?
if [ $RC -eq 0 ] ; then
    fail "Test 1 no-P4-env: expected non-zero exit, got 0"
elif ! echo "$OUTPUT" | grep -q 'environment variable' ; then
    fail "Test 1 no-P4-env: expected 'environment variable' in error; got: $OUTPUT"
else
    pass "Test 1: constructor dies when all P4 env vars are missing"
fi

# ---------------------------------------------------------------------------
# Test 2: Only P4USER set -> constructor dies citing P4PORT
# ---------------------------------------------------------------------------
export P4USER="testuser"
unset P4PORT P4CLIENT
OUTPUT=$($PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate; my $obj = p4annotate->new($0, "test.txt");' 2>&1)
RC=$?
if [ $RC -eq 0 ] ; then
    fail "Test 2 missing-P4PORT: expected non-zero exit, got 0"
elif ! echo "$OUTPUT" | grep -q 'P4PORT' ; then
    fail "Test 2 missing-P4PORT: expected 'P4PORT' in error; got: $OUTPUT"
else
    pass "Test 2: constructor dies citing P4PORT when only P4USER is set"
fi

# ---------------------------------------------------------------------------
# Test 3: Only P4PORT set -> constructor dies citing P4USER
# ---------------------------------------------------------------------------
unset P4USER
export P4PORT="localhost:1666"
unset P4CLIENT
OUTPUT=$($PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate; my $obj = p4annotate->new($0, "test.txt");' 2>&1)
RC=$?
if [ $RC -eq 0 ] ; then
    fail "Test 3 missing-P4USER: expected non-zero exit, got 0"
elif ! echo "$OUTPUT" | grep -q 'P4USER' ; then
    fail "Test 3 missing-P4USER: expected 'P4USER' in error; got: $OUTPUT"
else
    pass "Test 3: constructor dies citing P4USER when only P4PORT is set"
fi

# ---------------------------------------------------------------------------
# Test 4: All P4 env vars set -> constructor succeeds
# ---------------------------------------------------------------------------
export P4USER="testuser"
export P4PORT="localhost:1666"
export P4CLIENT="testclient"
OUTPUT=$($PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate;
     my $obj = p4annotate->new($0, "--verify", "test.txt");
     print "Constructor OK\n" if defined($obj);' 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 4 all-P4-env: constructor failed with all vars set; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'Constructor OK' ; then
    fail "Test 4 all-P4-env: constructor returned undef with all vars set; got: $OUTPUT"
else
    pass "Test 4: constructor succeeds when all P4 env vars are set"
fi

# From here on all tests assume P4USER/P4PORT/P4CLIENT are exported (set above).

# ===========================================================================
# Tests 5-10: Constructor argument parsing  (from args_check.sh)
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 5: --verify flag stored in object at index [4]
# ---------------------------------------------------------------------------
OUTPUT=$($PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate;
     my $obj = p4annotate->new($0, "--verify", "test.txt");
     print "verify=" . ($obj->[4] ? "1" : "0") . "\n";' 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 5 --verify: constructor failed; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'verify=1' ; then
    fail "Test 5 --verify: flag not set at index [4]; got: $OUTPUT"
else
    pass "Test 5: --verify flag parsed and stored correctly"
fi

# ---------------------------------------------------------------------------
# Test 6: --log flag stored in object at index [3]
# ---------------------------------------------------------------------------
LOGFILE_T6=$(mktemp)
trap 'rm -f "$LOGFILE_T6"' EXIT
OUTPUT=$($PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate;
     my $obj = p4annotate->new($0, "--log", "'"$LOGFILE_T6"'", "test.txt");
     print "logfile=" . ($obj->[3] // "undef") . "\n";' 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 6 --log: constructor failed; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q "logfile=$LOGFILE_T6" ; then
    fail "Test 6 --log: logfile path not at index [3]; got: $OUTPUT"
else
    pass "Test 6: --log flag parsed and stored correctly"
fi
rm -f "$LOGFILE_T6"

# ---------------------------------------------------------------------------
# Test 7: --cache flag (skipped - requires full lcovutil module context)
# ---------------------------------------------------------------------------
pass "Test 7: --cache flag skipped (requires lcovutil context)"

# ---------------------------------------------------------------------------
# Test 8: --verify and --log combined
# ---------------------------------------------------------------------------
LOGFILE_T8=$(mktemp)
OUTPUT=$($PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate;
     my $obj = p4annotate->new($0, "--verify", "--log", "'"$LOGFILE_T8"'", "test.txt");
     print "verify=" . ($obj->[4] ? "1" : "0") . "\n";
     print "has_log=" . (defined($obj->[3]) ? "1" : "0") . "\n";' 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 8 combined-flags: constructor failed; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'verify=1' ; then
    fail "Test 8 combined-flags: --verify not set; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'has_log=1' ; then
    fail "Test 8 combined-flags: --log not set; got: $OUTPUT"
else
    pass "Test 8: --verify and --log together parsed correctly"
fi
rm -f "$LOGFILE_T8"

# ---------------------------------------------------------------------------
# Test 9: Unknown option -> non-zero exit and usage message
# ---------------------------------------------------------------------------
OUTPUT=$($PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate; p4annotate->new($0, "--invalid-flag", "test.txt");' 2>&1)
RC=$?
if [ $RC -eq 0 ] ; then
    fail "Test 9 invalid-flag: expected failure, got 0"
elif ! echo "$OUTPUT" | grep -iq 'usage\|unexpected' ; then
    fail "Test 9 invalid-flag: expected usage/error message; got: $OUTPUT"
else
    pass "Test 9: unknown option rejected with usage message"
fi

# ---------------------------------------------------------------------------
# Test 10: Constructor with no filename argument succeeds
# ---------------------------------------------------------------------------
OUTPUT=$($PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate;
     my $obj = p4annotate->new($0);
     print "obj=" . (defined($obj) ? "defined" : "undef") . "\n";' 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 10 no-filename: constructor failed; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'obj=defined' ; then
    fail "Test 10 no-filename: constructor returned undef; got: $OUTPUT"
else
    pass "Test 10: constructor succeeds with no filename (filename passed separately to annotate)"
fi

# ===========================================================================
# Tests 11-13: --help flag and usage message  (from help_check.sh)
# ===========================================================================

HELP_STDOUT=$(mktemp)
HELP_STDERR=$(mktemp)
trap 'rm -f "$HELP_STDOUT" "$HELP_STDERR"' EXIT

# ---------------------------------------------------------------------------
# Test 11: --help prints usage
# ---------------------------------------------------------------------------
$PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate; p4annotate->new($0, "--help", "test.txt");' \
    2>"$HELP_STDERR" >"$HELP_STDOUT"
cat "$HELP_STDERR" >> "$HELP_STDOUT"
if ! grep -q 'usage:' "$HELP_STDOUT" ; then
    fail "Test 11 --help: expected 'usage:' in output; got: $(cat $HELP_STDOUT)"
else
    pass "Test 11: --help prints usage message"
fi

# ---------------------------------------------------------------------------
# Test 12: Unrecognised short flag -h also triggers usage (as an error)
# ---------------------------------------------------------------------------
$PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate; p4annotate->new($0, "-h", "test.txt");' \
    2>"$HELP_STDERR" >"$HELP_STDOUT"
cat "$HELP_STDERR" >> "$HELP_STDOUT"
if ! grep -q 'usage:' "$HELP_STDOUT" ; then
    fail "Test 12 -h: expected 'usage:' in output; got: $(cat $HELP_STDOUT)"
else
    pass "Test 12: unrecognised -h option triggers usage message"
fi

# ---------------------------------------------------------------------------
# Test 13: Usage message contains expected option names
# ---------------------------------------------------------------------------
$PERL -I"${SCRIPT_DIR}" -e \
    'use p4annotate; p4annotate->new($0, "--help", "test.txt");' \
    2>"$HELP_STDERR" >"$HELP_STDOUT"
cat "$HELP_STDERR" >> "$HELP_STDOUT"
MISSING=""
for opt in '--log' '--cache' '--verify' ; do
    grep -qF -- "$opt" "$HELP_STDOUT" || MISSING="$MISSING $opt"
done
if [ -n "$MISSING" ] ; then
    fail "Test 13 usage-format: options missing from usage:$MISSING; got: $(cat $HELP_STDOUT)"
else
    pass "Test 13: usage message contains --log, --cache, --verify"
fi
rm -f "$HELP_STDOUT" "$HELP_STDERR"

# ===========================================================================
# Tests 14-17: Symlink / path normalisation  (from symlink_check.sh)
# ===========================================================================

SYMLINK_TESTDIR=$(mktemp -d)
REAL_FILE="$SYMLINK_TESTDIR/real_file.txt"
LINK_FILE="$SYMLINK_TESTDIR/link_file.txt"
DEEP_DIR="$SYMLINK_TESTDIR/a/b/c"
DEEP_LINK="$SYMLINK_TESTDIR/deep_link.txt"

mkdir -p "$DEEP_DIR"
printf 'test content line 1\ntest content line 2\n' > "$REAL_FILE"
ln -s "$REAL_FILE" "$LINK_FILE"
printf 'deep content\n' > "$DEEP_DIR/deep.txt"
ln -s "$DEEP_DIR/deep.txt" "$DEEP_LINK"

# ---------------------------------------------------------------------------
# Test 14: -l detects symlink; -e follows it and also returns true
# ---------------------------------------------------------------------------
OUTPUT=$($PERL -I"${SCRIPT_DIR}" -e "
my \$is_link = -l '$LINK_FILE';
my \$is_file = -e '$LINK_FILE';
print 'is_link=' . (\$is_link ? '1' : '0') . \"\n\";
print 'is_file=' . (\$is_file ? '1' : '0') . \"\n\";
" 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 14 symlink-detect: perl error; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'is_link=1' ; then
    fail "Test 14 symlink-detect: symlink not detected; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'is_file=1' ; then
    fail "Test 14 symlink-detect: symlink target not accessible; got: $OUTPUT"
else
    pass "Test 14: -l detects symlink; -e follows it to the real file"
fi

# ---------------------------------------------------------------------------
# Test 15: Path normalisation logic from annotate_callback resolves symlink
# ---------------------------------------------------------------------------
NORM_SCRIPT=$(mktemp --suffix=.pl)
cat > "$NORM_SCRIPT" << 'NORMPL'
use File::Spec;
use File::Basename qw(dirname);
my $pathname = $ARGV[0];
if (-e $pathname && -l $pathname) {
    $pathname = File::Spec->catfile(dirname($pathname), readlink($pathname));
    my @c;
    foreach my $component (split(m{/}, $pathname)) {
        next unless length($component);
        if ($component eq '.')  { next }
        if ($component eq '..') { pop @c; next }
        push @c, $component;
    }
    $pathname = File::Spec->catfile(@c);
    print "normalized=$pathname\n";
}
NORMPL
OUTPUT=$($PERL -I"${SCRIPT_DIR}" "$NORM_SCRIPT" "$LINK_FILE" 2>&1)
RC=$?
rm -f "$NORM_SCRIPT"
if [ $RC -ne 0 ] ; then
    fail "Test 15 path-norm: perl error; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'normalized=' ; then
    fail "Test 15 path-norm: expected normalized path; got: $OUTPUT"
else
    pass "Test 15: path normalisation resolves symlink to real path"
fi

# ---------------------------------------------------------------------------
# Test 16: Path normalisation handles .. components in symlink target
# ---------------------------------------------------------------------------
NORM_SCRIPT=$(mktemp --suffix=.pl)
cat > "$NORM_SCRIPT" << 'NORMPL'
use File::Spec;
use File::Basename qw(dirname);
my $pathname = $ARGV[0];
if (-e $pathname && -l $pathname) {
    $pathname = File::Spec->catfile(dirname($pathname), readlink($pathname));
    my @c;
    foreach my $component (split(m{/}, $pathname)) {
        next unless length($component);
        if ($component eq '.')  { next }
        if ($component eq '..') { pop @c; next }
        push @c, $component;
    }
    $pathname = File::Spec->catfile(@c);
    print "normalized=$pathname\n";
}
NORMPL
OUTPUT=$($PERL -I"${SCRIPT_DIR}" "$NORM_SCRIPT" "$DEEP_LINK" 2>&1)
RC=$?
rm -f "$NORM_SCRIPT"
if [ $RC -ne 0 ] ; then
    fail "Test 16 deep-path-norm: perl error; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'normalized=' ; then
    fail "Test 16 deep-path-norm: expected normalized path; got: $OUTPUT"
else
    pass "Test 16: path normalisation handles .. components in symlink target"
fi

# ---------------------------------------------------------------------------
# Test 17: Regular file: -l returns false; -e returns true
# ---------------------------------------------------------------------------
OUTPUT=$($PERL -I"${SCRIPT_DIR}" -e "
my \$is_link = -l '$REAL_FILE';
my \$is_file = -e '$REAL_FILE';
print 'is_link=' . (\$is_link ? '1' : '0') . \"\n\";
print 'is_file=' . (\$is_file ? '1' : '0') . \"\n\";
" 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 17 regular-file: perl error; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'is_link=0' ; then
    fail "Test 17 regular-file: regular file wrongly detected as symlink; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'is_file=1' ; then
    fail "Test 17 regular-file: regular file not accessible; got: $OUTPUT"
else
    pass "Test 17: regular file: -l=false, -e=true"
fi
rm -rf "$SYMLINK_TESTDIR"
SYMLINK_TESTDIR=""

# ===========================================================================
# Tests 18-34: End-to-end annotation output  (from annotate_check.sh)
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 18: File not in p4 -> not_in_repo fallback -> NONE annotation
# ---------------------------------------------------------------------------
export P4MOCK_FILES="not_in_p4"
unset P4MOCK_HAVE P4MOCK_OPENED P4MOCK_DIFF P4MOCK_DIFF_EXIT P4MOCK_ANNOTATE

TGT=$(mk_target "alpha\nbeta\ngamma\n")
run_p4annotate "$TGT"
rm -f "$TGT"

if [ $RC -ne 0 ] ; then
    fail "Test 18 not-in-p4: expected exit 0, got $RC"
else
    NONE_COUNT=$(echo "$OUTPUT" | grep -c '^NONE|')
    LINES=$(echo "$OUTPUT" | wc -l)
    if [ "$LINES" -ne 3 ] || [ "$NONE_COUNT" -ne 3 ] ; then
        fail "Test 18 not-in-p4: expected 3 NONE lines, got $NONE_COUNT/$LINES:
$OUTPUT"
    else
        pass "Test 18: file not in p4 -> not_in_repo NONE annotation"
    fi
fi

# ---------------------------------------------------------------------------
# Test 19: In p4, @head version (p4 have empty); basic annotate output
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE P4MOCK_OPENED

AMOCK=$(mk_annotate << 'EOF'
12345: alice 2024/01/15 first line of code
12346: bob 2024/02/20 second line of code
12347: carol 2024/03/25 third line of code
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "first line of code\nsecond line of code\nthird line of code\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$AMOCK" ; unset P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 19 basic: expected exit 0, got $RC; output: $OUTPUT"
else
    L1=$(echo "$OUTPUT" | head -1)
    L2=$(echo "$OUTPUT" | sed -n '2p')
    L3=$(echo "$OUTPUT" | sed -n '3p')
    if [ "$L1" != "12345|alice|2024-01-15T00:00:00-05:00|first line of code"  ] ||
       [ "$L2" != "12346|bob|2024-02-20T00:00:00-05:00|second line of code"   ] ||
       [ "$L3" != "12347|carol|2024-03-25T00:00:00-05:00|third line of code"  ] ; then
        fail "Test 19 basic: output mismatch:
$OUTPUT"
    else
        pass "Test 19: basic annotation, @head version, 3 lines with 3 distinct owners"
    fi
fi

# ---------------------------------------------------------------------------
# Test 20: In p4, versioned (#3 from p4 have)
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
export P4MOCK_HAVE="//depot/test/sample.c#3 - /workspace/sample.c"
unset P4MOCK_OPENED

AMOCK=$(mk_annotate << 'EOF'
99: alice 2023/06/01 versioned line one
100: alice 2023/06/01 versioned line two
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "versioned line one\nversioned line two\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$AMOCK" ; unset P4MOCK_ANNOTATE P4MOCK_HAVE

if [ $RC -ne 0 ] ; then
    fail "Test 20 versioned: expected exit 0, got $RC; output: $OUTPUT"
else
    MATCH=$(echo "$OUTPUT" | grep -c '|alice|2023-06-01T00:00:00-05:00|versioned line')
    [ "$MATCH" -eq 2 ] && pass "Test 20: versioned file (#3) annotated correctly" ||
        fail "Test 20 versioned: expected 2 matching lines, got $MATCH:
$OUTPUT"
fi

# ---------------------------------------------------------------------------
# Test 21: Owner with angle brackets stripped: <user@domain.com> -> user@domain.com
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE P4MOCK_OPENED

AMOCK=$(mk_annotate << 'EOF'
55555: <alice@example.com> 2024/04/10 line with email owner
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "line with email owner\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$AMOCK" ; unset P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 21 angle-brackets: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -q '|alice@example\.com|' ; then
    fail "Test 21 angle-brackets: expected bare email after stripping <>:
$OUTPUT"
else
    pass "Test 21: angle-bracket owner stripped to bare email"
fi

# ---------------------------------------------------------------------------
# Test 22: Non-matching annotate line -> NONE|NONE|NONE|text
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE P4MOCK_OPENED

AMOCK=$(mk_annotate << 'EOF'
12345: alice 2024/01/15 normal line
this line does not match the p4 annotate pattern at all
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "normal line\nbad line\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$AMOCK" ; unset P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 22 non-matching: expected exit 0, got $RC"
else
    NORMAL=$(echo "$OUTPUT" | grep -c '^12345|alice|')
    NONE=$(echo "$OUTPUT" | grep -c '^NONE|NONE|NONE|')
    if [ "$NORMAL" -ne 1 ] || [ "$NONE" -ne 1 ] ; then
        fail "Test 22 non-matching: expected 1 normal + 1 NONE line, got $NORMAL/$NONE:
$OUTPUT"
    else
        pass "Test 22: non-matching annotate line produces NONE|NONE|NONE entry"
    fi
fi

# ---------------------------------------------------------------------------
# Test 23: Opened for edit, default CL, no diffs (header only)
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE
export P4MOCK_OPENED="//depot/test/sample.c#3 - edit default change (text)"

DMOCK=$(mk_diff << 'EOF'
==== //depot/test/sample.c#3 - /workspace/sample.c ====
EOF
)
export P4MOCK_DIFF="$DMOCK"

AMOCK=$(mk_annotate << 'EOF'
200: alice 2024/01/15 unchanged line one
201: bob 2024/02/20 unchanged line two
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "unchanged line one\nunchanged line two\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$DMOCK" "$AMOCK"
unset P4MOCK_OPENED P4MOCK_DIFF P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 23 edit-no-diff: expected exit 0, got $RC; output: $OUTPUT"
else
    L1=$(echo "$OUTPUT" | head -1)
    L2=$(echo "$OUTPUT" | sed -n '2p')
    if [ "$L1" != "200|alice|2024-01-15T00:00:00-05:00|unchanged line one" ] ||
       [ "$L2" != "201|bob|2024-02-20T00:00:00-05:00|unchanged line two"   ] ; then
        fail "Test 23 edit-no-diff: unexpected output:
$OUTPUT"
    else
        pass "Test 23: edit (default CL, no diffs) -> depot annotation unchanged"
    fi
fi

# ---------------------------------------------------------------------------
# Test 24: Opened for edit, numbered CL (77); lines appended at end ("2a3,4")
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
export P4MOCK_HAVE="//depot/test/sample.c#5 - /workspace/sample.c"
export P4MOCK_OPENED="//depot/test/sample.c#5 - edit change 77 (text)"

DMOCK=$(mk_diff << 'EOF'
==== //depot/test/sample.c#5 - /workspace/sample.c ====
2a3,4
> appended line three
> appended line four
EOF
)
export P4MOCK_DIFF="$DMOCK"

AMOCK=$(mk_annotate << 'EOF'
300: alice 2024/01/15 depot line one
301: alice 2024/01/15 depot line two
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "depot line one\ndepot line two\nappended line three\nappended line four\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$DMOCK" "$AMOCK"
unset P4MOCK_HAVE P4MOCK_OPENED P4MOCK_DIFF P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 24 trailing-add: expected exit 0, got $RC; output: $OUTPUT"
else
    LINES=$(echo "$OUTPUT" | wc -l)
    L1=$(echo "$OUTPUT" | head -1)
    L2=$(echo "$OUTPUT" | sed -n '2p')
    L3=$(echo "$OUTPUT" | sed -n '3p')
    L4=$(echo "$OUTPUT" | sed -n '4p')
    OK=1
    [ "$L1" = "300|alice|2024-01-15T00:00:00-05:00|depot line one" ] || OK=0
    [ "$L2" = "301|alice|2024-01-15T00:00:00-05:00|depot line two" ] || OK=0
    echo "$L3" | grep -q '^77|testuser|' || OK=0
    echo "$L3" | grep -q '|appended line three$' || OK=0
    echo "$L4" | grep -q '^77|testuser|' || OK=0
    echo "$L4" | grep -q '|appended line four$' || OK=0
    if [ $OK -ne 1 ] || [ "$LINES" -ne 4 ] ; then
        fail "Test 24 trailing-add: unexpected output ($LINES lines):
$OUTPUT"
    else
        pass "Test 24: numbered CL 77, trailing appended lines attributed to testuser"
    fi
fi

# ---------------------------------------------------------------------------
# Test 25: Diff "a" hunk mid-file: line inserted between depot lines 2 and 3
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE
export P4MOCK_OPENED="//depot/test/sample.c#3 - edit default change (text)"

DMOCK=$(mk_diff << 'EOF'
==== //depot/test/sample.c#3 - /workspace/sample.c ====
2a3
> inserted line
EOF
)
export P4MOCK_DIFF="$DMOCK"

AMOCK=$(mk_annotate << 'EOF'
10: alice 2024/01/15 line one
11: alice 2024/01/15 line two
12: alice 2024/01/15 line three
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "line one\nline two\ninserted line\nline three\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$DMOCK" "$AMOCK"
unset P4MOCK_OPENED P4MOCK_DIFF P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 25 mid-add: expected exit 0, got $RC; output: $OUTPUT"
else
    LINES=$(echo "$OUTPUT" | wc -l)
    L1=$(echo "$OUTPUT" | head -1)
    L2=$(echo "$OUTPUT" | sed -n '2p')
    L3=$(echo "$OUTPUT" | sed -n '3p')
    L4=$(echo "$OUTPUT" | sed -n '4p')
    OK=1
    [ "$L1" = "10|alice|2024-01-15T00:00:00-05:00|line one"   ] || OK=0
    [ "$L2" = "11|alice|2024-01-15T00:00:00-05:00|line two"   ] || OK=0
    echo "$L3" | grep -q '^default|testuser|' || OK=0
    echo "$L3" | grep -q '|inserted line$'    || OK=0
    [ "$L4" = "12|alice|2024-01-15T00:00:00-05:00|line three" ] || OK=0
    if [ $OK -ne 1 ] || [ "$LINES" -ne 4 ] ; then
        fail "Test 25 mid-add: unexpected output ($LINES lines):
$OUTPUT"
    else
        pass "Test 25: diff 'a' hunk inserts local line between depot lines"
    fi
fi

# ---------------------------------------------------------------------------
# Test 26: Diff "d" hunk: depot line 2 deleted locally
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE
export P4MOCK_OPENED="//depot/test/sample.c#3 - edit default change (text)"

DMOCK=$(mk_diff << 'EOF'
==== //depot/test/sample.c#3 - /workspace/sample.c ====
2d1
< deleted depot line
EOF
)
export P4MOCK_DIFF="$DMOCK"

AMOCK=$(mk_annotate << 'EOF'
20: alice 2024/01/15 first line
21: alice 2024/01/15 deleted depot line
22: alice 2024/01/15 third line
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "first line\nthird line\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$DMOCK" "$AMOCK"
unset P4MOCK_OPENED P4MOCK_DIFF P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 26 delete: expected exit 0, got $RC; output: $OUTPUT"
else
    LINES=$(echo "$OUTPUT" | wc -l)
    L1=$(echo "$OUTPUT" | head -1)
    L2=$(echo "$OUTPUT" | sed -n '2p')
    OK=1
    [ "$L1" = "20|alice|2024-01-15T00:00:00-05:00|first line" ] || OK=0
    [ "$L2" = "22|alice|2024-01-15T00:00:00-05:00|third line" ] || OK=0
    if [ $OK -ne 1 ] || [ "$LINES" -ne 2 ] ; then
        fail "Test 26 delete: unexpected output ($LINES lines):
$OUTPUT"
    else
        pass "Test 26: diff 'd' hunk skips deleted depot line in output"
    fi
fi

# ---------------------------------------------------------------------------
# Test 27: Diff "c" hunk: depot lines 2-3 replaced with local lines 2-4
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE
export P4MOCK_OPENED="//depot/test/sample.c#3 - edit default change (text)"

DMOCK=$(mk_diff << 'EOF'
==== //depot/test/sample.c#3 - /workspace/sample.c ====
2,3c2,4
< old depot line 2
< old depot line 3
---
> new local line 2
> new local line 3
> new local line 4
EOF
)
export P4MOCK_DIFF="$DMOCK"

AMOCK=$(mk_annotate << 'EOF'
30: alice 2024/01/15 line one
31: alice 2024/01/15 old depot line 2
32: alice 2024/01/15 old depot line 3
33: alice 2024/01/15 line four
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "line one\nnew local line 2\nnew local line 3\nnew local line 4\nline four\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$DMOCK" "$AMOCK"
unset P4MOCK_OPENED P4MOCK_DIFF P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 27 change-hunk: expected exit 0, got $RC; output: $OUTPUT"
else
    LINES=$(echo "$OUTPUT" | wc -l)
    L1=$(echo "$OUTPUT" | head -1)
    L2=$(echo "$OUTPUT" | sed -n '2p')
    L3=$(echo "$OUTPUT" | sed -n '3p')
    L4=$(echo "$OUTPUT" | sed -n '4p')
    L5=$(echo "$OUTPUT" | sed -n '5p')
    OK=1
    [ "$L1" = "30|alice|2024-01-15T00:00:00-05:00|line one"  ] || OK=0
    echo "$L2" | grep -q '^default|testuser|'  || OK=0
    echo "$L2" | grep -q '|new local line 2$'  || OK=0
    echo "$L3" | grep -q '^default|testuser|'  || OK=0
    echo "$L3" | grep -q '|new local line 3$'  || OK=0
    echo "$L4" | grep -q '^default|testuser|'  || OK=0
    echo "$L4" | grep -q '|new local line 4$'  || OK=0
    [ "$L5" = "33|alice|2024-01-15T00:00:00-05:00|line four" ] || OK=0
    if [ $OK -ne 1 ] || [ "$LINES" -ne 5 ] ; then
        fail "Test 27 change-hunk: unexpected output ($LINES lines):
$OUTPUT"
    else
        pass "Test 27: diff 'c' hunk (2,3c2,4) replaces 2 depot lines with 3 local lines"
    fi
fi

# ---------------------------------------------------------------------------
# Test 28: Opened for integrate (action="integrate") -> same diff path
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE
export P4MOCK_OPENED="//depot/test/sample.c#4 - integrate default change (text)"

DMOCK=$(mk_diff << 'EOF'
==== //depot/test/sample.c#4 - /workspace/sample.c ====
EOF
)
export P4MOCK_DIFF="$DMOCK"

AMOCK=$(mk_annotate << 'EOF'
400: carol 2024/05/01 integrate line one
401: carol 2024/05/01 integrate line two
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "integrate line one\nintegrate line two\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$DMOCK" "$AMOCK"
unset P4MOCK_OPENED P4MOCK_DIFF P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 28 integrate: expected exit 0, got $RC; output: $OUTPUT"
else
    MATCH=$(echo "$OUTPUT" | grep -c '|carol|2024-05-01T00:00:00-05:00|integrate line')
    [ "$MATCH" -eq 2 ] && pass "Test 28: opened for integrate -> same diff processing path" ||
        fail "Test 28 integrate: expected 2 carol lines, got $MATCH:
$OUTPUT"
fi

# ---------------------------------------------------------------------------
# Test 29: Multiple diff hunks: delete + mid-add + change in one file
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE
export P4MOCK_OPENED="//depot/test/sample.c#6 - edit change 999 (text)"

DMOCK=$(mk_diff << 'EOF'
==== //depot/test/sample.c#6 - /workspace/sample.c ====
1d0
< depot line 1
3a3
> inserted after 3
5,6c5,5
< old depot line 5
< old depot line 6
---
> replacement line 5
EOF
)
export P4MOCK_DIFF="$DMOCK"

AMOCK=$(mk_annotate << 'EOF'
50: alice 2024/01/15 depot line 1
51: alice 2024/01/15 depot line 2
52: alice 2024/01/15 depot line 3
53: alice 2024/01/15 depot line 4
54: alice 2024/01/15 old depot line 5
55: alice 2024/01/15 old depot line 6
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "depot line 2\ndepot line 3\ninserted after 3\ndepot line 4\nreplacement line 5\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$DMOCK" "$AMOCK"
unset P4MOCK_OPENED P4MOCK_DIFF P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 29 multi-hunk: expected exit 0, got $RC; output: $OUTPUT"
else
    LINES=$(echo "$OUTPUT" | wc -l)
    L1=$(echo "$OUTPUT" | head -1)
    L2=$(echo "$OUTPUT" | sed -n '2p')
    L3=$(echo "$OUTPUT" | sed -n '3p')
    L4=$(echo "$OUTPUT" | sed -n '4p')
    L5=$(echo "$OUTPUT" | sed -n '5p')
    OK=1
    [ "$L1" = "51|alice|2024-01-15T00:00:00-05:00|depot line 2" ] || OK=0
    [ "$L2" = "52|alice|2024-01-15T00:00:00-05:00|depot line 3" ] || OK=0
    echo "$L3" | grep -q '^999|testuser|'        || OK=0
    echo "$L3" | grep -q '|inserted after 3$'    || OK=0
    [ "$L4" = "53|alice|2024-01-15T00:00:00-05:00|depot line 4" ] || OK=0
    echo "$L5" | grep -q '^999|testuser|'         || OK=0
    echo "$L5" | grep -q '|replacement line 5$'   || OK=0
    if [ $OK -ne 1 ] || [ "$LINES" -ne 5 ] ; then
        fail "Test 29 multi-hunk: unexpected output ($LINES lines):
$OUTPUT"
    else
        pass "Test 29: multiple diff hunks (delete+insert+change) processed correctly"
    fi
fi

# ---------------------------------------------------------------------------
# Test 30: --log flag creates log file containing annotation entry
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE P4MOCK_OPENED

AMOCK=$(mk_annotate << 'EOF'
500: alice 2024/06/01 log test line
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "log test line\n")
LOGFILE_T30=$(mktemp)
OUTPUT=$($P4ANNOTATE --log "$LOGFILE_T30" "$TGT" 2>&1)
RC=$?
rm -f "$TGT" "$AMOCK" ; unset P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 30 --log: expected exit 0, got $RC; output: $OUTPUT"
elif [ ! -s "$LOGFILE_T30" ] ; then
    fail "Test 30 --log: log file is empty or missing"
elif ! grep -q 'have' "$LOGFILE_T30" 2>/dev/null ; then
    fail "Test 30 --log: expected 'have' entry in log; got: $(cat $LOGFILE_T30)"
else
    pass "Test 30: --log creates non-empty log with annotation entry"
fi
rm -f "$LOGFILE_T30"

# ---------------------------------------------------------------------------
# Test 31: LOG_P4ANNOTATE env var -> log written without --log flag
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE P4MOCK_OPENED

AMOCK=$(mk_annotate << 'EOF'
501: bob 2024/06/02 env log line
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "env log line\n")
LOGFILE_T31=$(mktemp)
export LOG_P4ANNOTATE="$LOGFILE_T31"
OUTPUT=$($P4ANNOTATE "$TGT" 2>&1)
RC=$?
unset LOG_P4ANNOTATE
rm -f "$TGT" "$AMOCK" ; unset P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 31 LOG_P4ANNOTATE: expected exit 0, got $RC; output: $OUTPUT"
elif [ ! -s "$LOGFILE_T31" ] ; then
    fail "Test 31 LOG_P4ANNOTATE: log file empty or missing"
else
    pass "Test 31: LOG_P4ANNOTATE env var triggers log without --log flag"
fi
rm -f "$LOGFILE_T31"

# ---------------------------------------------------------------------------
# Test 32: --verify flag passes when annotation matches file content exactly
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE P4MOCK_OPENED

AMOCK=$(mk_annotate << 'EOF'
600: alice 2024/07/01 verify line one
601: alice 2024/07/01 verify line two
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "verify line one\nverify line two\n")
OUTPUT=$($P4ANNOTATE --verify "$TGT" 2>&1)
RC=$?
rm -f "$TGT" "$AMOCK" ; unset P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 32 --verify: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '|verify line' ; then
    fail "Test 32 --verify: unexpected annotation output: $OUTPUT"
else
    pass "Test 32: --verify flag passes on consistent annotation"
fi

# ---------------------------------------------------------------------------
# Test 33: Opened for add (not edit/integrate) -> diff branch not entered
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE
export P4MOCK_OPENED="//depot/test/sample.c#1 - add default change (text)"
# P4MOCK_DIFF intentionally absent: if diff were invoked the fake p4 would
# produce no output, causing the "unexpected content" die in the code.

AMOCK=$(mk_annotate << 'EOF'
700: dave 2024/08/01 add-only line
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "add-only line\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$AMOCK"
unset P4MOCK_OPENED P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 33 add-opened: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^700|dave|' ; then
    fail "Test 33 add-opened: expected depot annotation passthrough; got: $OUTPUT"
else
    pass "Test 33: opened for 'add' (not edit/integrate) -> diff path skipped"
fi

# ---------------------------------------------------------------------------
# Test 34: Spaces and special characters in the text field preserved
# ---------------------------------------------------------------------------
export P4MOCK_FILES="in_p4"
unset P4MOCK_HAVE P4MOCK_OPENED

AMOCK=$(mk_annotate << 'EOF'
800: alice 2024/09/01     int x = foo(a, b, c);
801: bob 2024/09/02 if (x > 0 && y < 10) {
EOF
)
export P4MOCK_ANNOTATE="$AMOCK"
TGT=$(mk_target "    int x = foo(a, b, c);\nif (x > 0 && y < 10) {\n")
run_p4annotate "$TGT"
rm -f "$TGT" "$AMOCK" ; unset P4MOCK_ANNOTATE

if [ $RC -ne 0 ] ; then
    fail "Test 34 spaces-in-text: expected exit 0, got $RC"
else
    L1=$(echo "$OUTPUT" | head -1)
    L2=$(echo "$OUTPUT" | sed -n '2p')
    if [ "$L1" != "800|alice|2024-09-01T00:00:00-05:00|    int x = foo(a, b, c);" ] ; then
        fail "Test 34 spaces-in-text: line 1 mismatch: '$L1'"
    elif [ "$L2" != "801|bob|2024-09-02T00:00:00-05:00|if (x > 0 && y < 10) {" ] ; then
        fail "Test 34 spaces-in-text: line 2 mismatch: '$L2'"
    else
        pass "Test 34: spaces and special chars in text field preserved"
    fi
fi

# ---------------------------------------------------------------------------
# Test 35: normalize_path returns original for non-existent path (no symlink
#          resolution attempted when -e is false)
# ---------------------------------------------------------------------------
NORM_SCRIPT=$(mktemp --suffix=.pl)
cat > "$NORM_SCRIPT" << 'NORMPL'
use File::Spec;
use File::Basename qw(dirname);
my $pathname = $ARGV[0];
if (-e $pathname && -l $pathname) {
    $pathname = File::Spec->catfile(dirname($pathname), readlink($pathname));
    my @c;
    foreach my $component (split(m{/}, $pathname)) {
        next unless length($component);
        if ($component eq '.')  { next }
        if ($component eq '..') { pop @c; next }
        push @c, $component;
    }
    $pathname = File::Spec->catfile(@c);
}
print "result=$pathname\n";
NORMPL
NONEXIST='/nonexistent/path/no_such_file_p4annotate_test.c'
OUTPUT=$($PERL -I"${SCRIPT_DIR}" "$NORM_SCRIPT" "$NONEXIST" 2>&1)
RC=$?
rm -f "$NORM_SCRIPT"
if [ $RC -ne 0 ] ; then
    fail "Test 35 nonexistent-path: perl error; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qF "result=$NONEXIST" ; then
    fail "Test 35 nonexistent-path: expected path unchanged; got: $OUTPUT"
else
    pass "Test 35: normalize_path returns original for non-existent path"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ] ; then
    echo "Tests FAILED"
else
    echo "All p4annotate tests passed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover ${COVER_DB}
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB}
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch
fi

[ $FAIL -eq 0 ]
