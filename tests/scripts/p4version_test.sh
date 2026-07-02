#!/usr/bin/env bash
#
# Test suite for scripts/getp4version and scripts/P4version.pm
#
# getp4version is a standalone Perl script; P4version.pm is its OO counterpart.
# All p4 sub-commands are intercepted by a fake 'p4' script placed at the
# front of PATH.  Each sub-command's output is controlled via env vars:
#
#   P4V_WORKSPACE  - local workspace directory (absolute path to temp dir)
#   P4V_HAVE_OUT   - output for "p4 have <file>" (getp4version tests)
#   P4V_OPENED_OUT - output for "p4 opened <file>" (getp4version tests)
#   P4V_NO_SUCH    - if non-empty, "p4 files" returns "- no such file" line
#
# For P4version.pm tests the fake p4 responds to have/where/opened using
# env vars P4V_HAVE_LINES, P4V_WHERE_LINE, P4V_OPENED_LINES.
#
# Tests:
#   --- getp4version standalone ---
#   1.  --help exits 0 and prints usage
#   2.  Unknown option exits 1 and prints usage
#   3.  --compare with wrong arg count (2 args) exits 1
#   4.  No filename arg exits 1
#   5.  File not found, no --allow-missing: dies with message
#   6.  File not found, --allow-missing: prints empty line, exits 0
#   7.  File in P4, p4 have gives #N: version = "#N"
#   8.  File in P4, p4 have gives no #N match: version = "\@head"
#   9.  File in P4, p4 opened shows edit: version has " edited " + mtime
#  10.  File in P4, p4 opened + --md5: version has " edited " + mtime + md5
#  11.  File in P4, --md5 no edit: version = "#N md5:HASH"
#  12.  File NOT in P4 (p4 files returns "no such file"): mtime only
#  13.  File NOT in P4, --md5: mtime + " md5:HASH"
#  14.  --compare md5: old has md5 and not @head/#N, new has md5, match -> exit 0
#  15.  --compare md5: old has md5, new has md5, differ -> exit 1
#  16.  --compare md5: old starts with @head -> skip md5, exact match -> exit 0
#  17.  --compare md5: old has md5, new has no md5 -> fall through exact -> exit 1
#  18.  --compare exact: strings equal -> exit 0
#  19.  --compare exact: strings differ -> exit 1
#   --- P4version.pm OO ---
#  20.  new() bad option -> returns undef (not script eq $0)
#  21.  new() --help -> returns undef
#  22.  new() depot arg is not a directory -> dies
#  23.  new() no depot arg: extract_version returns mtime for unlisted file
#  24.  new() with depot: file in hash, extract_version returns "#N"
#  25.  new() with depot: p4 have no #rev match -> version = "@head" (via #N branch since $2 always digits)
#  26.  new() with depot: file NOT in hash -> extract_version returns mtime
#  27.  new() with depot: --md5, file not in hash -> extract_version returns "md5:HASH"
#  28.  new() with depot, opened edit, no --local-edit: new() dies
#  29.  new() with depot, opened edit, --local-edit: version has " edited " + mtime
#  30.  new() with depot, opened integrate, --local-edit: version has " edited " + mtime
#  31.  new() with depot, opened add (new file), --local-edit: version = depot_path " edited " mtime
#  32.  new() with depot, opened delete (file not in hash): silently skipped
#  33.  new() with depot, --local-edit --md5: local edit version has "md5:"
#  34.  new() with depot, --allow-missing, extract missing file -> returns ''
#  35.  new() with depot, no --allow-missing, extract missing file -> dies
#  36.  new() with depot, --prefix: relative path prefixed before lookup
#  37.  compare_version: same strings -> 0 (false)
#  38.  compare_version: differ strings -> 1 (true)
#  39.  new() p4 have fails, empty hash -> goto done, obj defined, extract returns mtime

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

GETP4VERSION="$SCRIPT_DIR/getp4version"
if [ ! -x "$GETP4VERSION" ] ; then
    echo "getp4version script not found at '$GETP4VERSION'" >&2
    exit 1
fi
[ -n "$COVER" ] && GETP4VERSION="$COVER $GETP4VERSION"

LCOV_LIB="$LCOV_HOME/lib"

PASS=0
FAIL=0

pass() { echo "PASS: $1" ; ((PASS++)) ; }
fail() { echo "FAIL: $1" ; ((FAIL++)) ; if [ "$KEEP_GOING" != 1 ] ; then exit 1 ; fi ; }

# ---------------------------------------------------------------------------
# Install fake p4 at front of PATH
# ---------------------------------------------------------------------------
MOCKDIR=$(mktemp -d)
WORKSPACE=$(mktemp -d)
trap 'rm -rf "$MOCKDIR" "$WORKSPACE"' EXIT

# The fake p4 script handles both getp4version and P4version.pm invocations.
# For getp4version: uses P4V_NO_SUCH, P4V_HAVE_OUT, P4V_OPENED_OUT
# For P4version.pm: uses P4V_HAVE_LINES, P4V_WHERE_LINE, P4V_OPENED_LINES
cat > "$MOCKDIR/p4" << 'FAKEP4'
#!/usr/bin/env bash
SUBCMD="$1"; shift
case "$SUBCMD" in
    files)
        if [ -n "${P4V_NO_SUCH:-}" ]; then
            echo "$1 - no such file(s)."
        else
            echo "//depot/foo.c#3 - edit change 100 (text)"
        fi
        ;;
    have)
        if [ -n "${P4V_HAVE_LINES:-}" ]; then
            printf '%s\n' "${P4V_HAVE_LINES}"
        elif [ -n "${P4V_HAVE_OUT:-}" ]; then
            echo "$P4V_HAVE_OUT"
        fi
        ;;
    where)
        if [ -n "${P4V_WHERE_LINE:-}" ]; then
            echo "$P4V_WHERE_LINE"
        elif [ -n "${P4V_WORKSPACE:-}" ]; then
            echo "//depot/... //ws/... ${P4V_WORKSPACE}/..."
        fi
        ;;
    opened)
        if [ -n "${P4V_OPENED_LINES:-}" ]; then
            printf '%s\n' "${P4V_OPENED_LINES}"
        elif [ -n "${P4V_OPENED_OUT:-}" ]; then
            echo "$P4V_OPENED_OUT"
        fi
        ;;
    *)
        exit "${P4V_DEFAULT_EXIT:-1}"
        ;;
esac
exit "${P4V_SUBCOMMAND_EXIT:-0}"
FAKEP4
chmod +x "$MOCKDIR/p4"
export PATH="$MOCKDIR:$PATH"

# Workspace files for testing
TF1="$WORKSPACE/foo.c"
TF2="$WORKSPACE/bar.c"
echo "int main(){}" > "$TF1"
echo "// bar" > "$TF2"
MD5_TF1=$(md5sum "$TF1" | awk '{print $1}')

export P4V_WORKSPACE="$WORKSPACE"

# ---------------------------------------------------------------------------
# Helper: run getp4version, capture OUTPUT and RC
# ---------------------------------------------------------------------------
run_getp4version() {
    OUTPUT=$($GETP4VERSION "$@" 2>&1)
    RC=$?
}

# ---------------------------------------------------------------------------
# Helper: run a Perl snippet via P4version.pm; returns OUTPUT (combined stderr)
# ---------------------------------------------------------------------------
run_p4version_pl() {
    local pl_file="$1"; shift
    OUTPUT=$(perl -I"$SCRIPT_DIR" -I"$LCOV_LIB" "$pl_file" "$@" 2>&1)
    RC=$?
}

# ===========================================================================
# Tests 1-4: getp4version argument validation
# ===========================================================================

# Test 1: --help exits 0 and prints usage
run_getp4version --help
if [ $RC -ne 0 ] ; then
    fail "Test 1 --help: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 1 --help: usage not in output; got: $OUTPUT"
else
    pass "Test 1: --help exits 0 and prints usage"
fi

# Test 2: Unknown option exits 1 and prints usage
run_getp4version --bad-option "$TF1"
if [ $RC -ne 1 ] ; then
    fail "Test 2 bad-option: expected exit 1, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 2 bad-option: usage not in output"
else
    pass "Test 2: unknown option rejected with usage"
fi

# Test 3: --compare with wrong arg count (only 2 args after option) -> exit 1
run_getp4version --compare "#3" "#5"
if [ $RC -ne 1 ] ; then
    fail "Test 3 compare-wrong-args: expected exit 1, got $RC"
else
    pass "Test 3: --compare with wrong arg count rejected"
fi

# Test 4: No filename arg -> exit 1
run_getp4version
if [ $RC -ne 1 ] ; then
    fail "Test 4 no-args: expected exit 1, got $RC"
else
    pass "Test 4: no filename arg rejected"
fi

# ===========================================================================
# Tests 5-6: getp4version missing file handling
# ===========================================================================

# Test 5: File not found, no --allow-missing: dies with message
run_getp4version "$WORKSPACE/nonexistent.c"
if [ $RC -eq 0 ] ; then
    fail "Test 5 missing-no-flag: expected non-zero exit, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'allow-missing' ; then
    fail "Test 5 missing-no-flag: expected --allow-missing in message; got: $OUTPUT"
else
    pass "Test 5: missing file without --allow-missing gives useful error"
fi

# Test 6: File not found, --allow-missing: prints empty line, exits 0
run_getp4version --allow-missing "$WORKSPACE/nonexistent.c"
if [ $RC -ne 0 ] ; then
    fail "Test 6 allow-missing: expected exit 0, got $RC"
elif [ "$OUTPUT" != "" ] ; then
    fail "Test 6 allow-missing: expected empty output, got: '$OUTPUT'"
else
    pass "Test 6: --allow-missing with missing file exits 0 with empty output"
fi

# ===========================================================================
# Tests 7-11: getp4version file in P4
# ===========================================================================

# Test 7: File in P4, p4 have gives #N: version = "#N"
unset P4V_NO_SUCH P4V_OPENED_OUT P4V_SUBCOMMAND_EXIT
export P4V_HAVE_OUT="//depot/foo.c#3 - $TF1"
run_getp4version "$TF1"
if [ $RC -ne 0 ] ; then
    fail "Test 7 in-p4-rev: expected exit 0, got $RC"
elif [ "$OUTPUT" != "#3" ] ; then
    fail "Test 7 in-p4-rev: expected '#3', got: '$OUTPUT'"
else
    pass "Test 7: file in P4, p4 have gives #N -> version '#N'"
fi

# Test 8: File in P4, p4 have gives no #N: version = "\@head"
export P4V_HAVE_OUT="//depot/foo.c - no revision info"
run_getp4version "$TF1"
if [ $RC -ne 0 ] ; then
    fail "Test 8 in-p4-head: expected exit 0, got $RC"
elif [ "$OUTPUT" != '\@head' ] ; then
    fail "Test 8 in-p4-head: expected '\@head', got: '$OUTPUT'"
else
    pass "Test 8: file in P4, no #N in have output -> version '\@head'"
fi

# Test 9: File in P4, p4 opened shows edit: version has " edited " + mtime
export P4V_HAVE_OUT="//depot/foo.c#3 - $TF1"
export P4V_OPENED_OUT="//depot/foo.c#3 - edit default change (text)"
run_getp4version "$TF1"
if [ $RC -ne 0 ] ; then
    fail "Test 9 opened-edit: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -qF ' edited ' ; then
    fail "Test 9 opened-edit: expected ' edited ' in output; got: '$OUTPUT'"
else
    pass "Test 9: file in P4, opened edit -> version has ' edited ' + mtime"
fi

# Test 10: File in P4, opened + --md5: version has mtime AND md5
run_getp4version --md5 "$TF1"
if [ $RC -ne 0 ] ; then
    fail "Test 10 opened-edit-md5: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -qF ' edited ' ; then
    fail "Test 10 opened-edit-md5: expected ' edited ' in output; got: '$OUTPUT'"
elif ! echo "$OUTPUT" | grep -qF " md5:$MD5_TF1" ; then
    fail "Test 10 opened-edit-md5: expected md5 in output; got: '$OUTPUT'"
else
    pass "Test 10: file in P4, opened edit + --md5 -> version has mtime + md5"
fi

# Test 11: File in P4, --md5, no edit: "#N md5:HASH"
unset P4V_OPENED_OUT
export P4V_HAVE_OUT="//depot/foo.c#3 - $TF1"
run_getp4version --md5 "$TF1"
if [ $RC -ne 0 ] ; then
    fail "Test 11 in-p4-md5: expected exit 0, got $RC"
elif [ "$OUTPUT" != "#3 md5:$MD5_TF1" ] ; then
    fail "Test 11 in-p4-md5: expected '#3 md5:$MD5_TF1', got: '$OUTPUT'"
else
    pass "Test 11: file in P4 + --md5 -> '#N md5:HASH'"
fi

# ===========================================================================
# Tests 12-13: getp4version file NOT in P4
# ===========================================================================

# Test 12: File NOT in P4 (p4 files -> "no such file"): mtime only
export P4V_NO_SUCH=1
run_getp4version "$TF1"
if [ $RC -ne 0 ] ; then
    fail "Test 12 not-in-p4: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' ; then
    fail "Test 12 not-in-p4: expected ISO8601 mtime, got: '$OUTPUT'"
elif echo "$OUTPUT" | grep -qF 'md5:' ; then
    fail "Test 12 not-in-p4: unexpected md5 in output: '$OUTPUT'"
else
    pass "Test 12: file not in P4 -> mtime only"
fi

# Test 13: File NOT in P4, --md5: mtime + " md5:HASH"
run_getp4version --md5 "$TF1"
if [ $RC -ne 0 ] ; then
    fail "Test 13 not-in-p4-md5: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -qF " md5:$MD5_TF1" ; then
    fail "Test 13 not-in-p4-md5: expected md5 in output; got: '$OUTPUT'"
else
    pass "Test 13: file not in P4 + --md5 -> mtime + md5"
fi

# ===========================================================================
# Tests 14-19: getp4version --compare
# ===========================================================================
unset P4V_NO_SUCH P4V_HAVE_OUT P4V_OPENED_OUT

# Test 14: --compare md5 match (old has md5, not @head/#N prefix) -> exit 0
run_getp4version --md5 --compare "foo md5:$MD5_TF1" "foo md5:$MD5_TF1" "$TF1"
if [ $RC -ne 0 ] ; then
    fail "Test 14 compare-md5-same: expected exit 0, got $RC"
else
    pass "Test 14: --compare --md5 with matching md5 -> exit 0"
fi

# Test 15: --compare md5 differ -> exit 1
DIFF_MD5="aaaabbbbccccddddeeeeffffaaaabbbb"
run_getp4version --md5 --compare "foo md5:$MD5_TF1" "foo md5:$DIFF_MD5" "$TF1"
if [ $RC -ne 1 ] ; then
    fail "Test 15 compare-md5-diff: expected exit 1, got $RC"
else
    pass "Test 15: --compare --md5 with differing md5 -> exit 1"
fi

# Test 16: --compare with --md5, old starts @head -> bypass md5, exact match
run_getp4version --md5 --compare "@head md5:$MD5_TF1" "@head md5:$MD5_TF1" "$TF1"
if [ $RC -ne 0 ] ; then
    fail "Test 16 compare-head-bypass: expected exit 0, got $RC"
else
    pass "Test 16: --compare with old starting @head bypasses md5, exact match -> exit 0"
fi

# Test 17: --compare with --md5, old has md5 but new has no md5 -> fall through exact -> exit 1
run_getp4version --md5 --compare "foo md5:$MD5_TF1" "foo_no_md5_here" "$TF1"
if [ $RC -ne 1 ] ; then
    fail "Test 17 compare-new-no-md5: expected exit 1, got $RC"
else
    pass "Test 17: --compare old has md5, new has no md5 -> falls through to exact, exit 1"
fi

# Test 18: --compare exact, strings equal -> exit 0
run_getp4version --compare "#3" "#3" "$TF1"
if [ $RC -ne 0 ] ; then
    fail "Test 18 compare-exact-same: expected exit 0, got $RC"
else
    pass "Test 18: --compare exact match -> exit 0"
fi

# Test 19: --compare exact, strings differ -> exit 1
run_getp4version --compare "#3" "#5" "$TF1"
if [ $RC -ne 1 ] ; then
    fail "Test 19 compare-exact-diff: expected exit 1, got $RC"
else
    pass "Test 19: --compare exact differ -> exit 1"
fi

# ===========================================================================
# Tests 20-39: P4version.pm OO via inline Perl helper scripts
# ===========================================================================
# Each test writes a small .pl file to avoid shell-quoting issues, then
# invokes it via perl.

# ---------------------------------------------------------------------------
# Test 20: new() bad option -> undef (script ne $0 so returns undef not exit)
# ---------------------------------------------------------------------------
PL=$(mktemp --suffix=.pl)
cat > "$PL" << 'PLEOF'
use P4version;
# Pass a fake script name different from $0 so new() returns undef instead of exiting
my $obj = P4version->new('/fake/caller', '--bad-option');
print defined($obj) ? "defined\n" : "undef\n";
PLEOF
run_p4version_pl "$PL"
if echo "$OUTPUT" | grep -q 'undef' ; then
    pass "Test 20: P4version::new() bad option returns undef"
else
    fail "Test 20 bad-option: expected undef, got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 21: new() --help -> undef
# ---------------------------------------------------------------------------
PL=$(mktemp --suffix=.pl)
cat > "$PL" << 'PLEOF'
use P4version;
my $obj = P4version->new('/fake/caller', '--help');
print defined($obj) ? "defined\n" : "undef\n";
PLEOF
run_p4version_pl "$PL"
if echo "$OUTPUT" | grep -q 'undef' ; then
    pass "Test 21: P4version::new() --help returns undef"
else
    fail "Test 21 help: expected undef, got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 22: new() depot arg not a directory -> dies
# ---------------------------------------------------------------------------
PL=$(mktemp --suffix=.pl)
cat > "$PL" << 'PLEOF'
use P4version;
eval { P4version->new('/fake/caller', '/nonexistent/depot/path'); };
if ($@) { print "died: $@\n"; } else { print "no-die\n"; }
PLEOF
run_p4version_pl "$PL"
if echo "$OUTPUT" | grep -qi 'died\|not a directory' ; then
    pass "Test 22: P4version::new() with non-directory depot dies"
else
    fail "Test 22 bad-depot: expected die, got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 23: new() no depot: file not in any hash -> extract_version returns mtime
# ---------------------------------------------------------------------------
unset P4V_HAVE_LINES P4V_WHERE_LINE P4V_OPENED_LINES P4V_NO_SUCH
export P4V_HAVE_LINES=""   # empty -> no filehash entries
export P4V_SUBCOMMAND_EXIT=0

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my \$file = \$ARGV[0];
my \$obj = P4version->new(\$0);
if (defined \$obj) {
    my \$v = \$obj->extract_version(\$file);
    if (\$v =~ /^\d{4}-\d{2}-\d{2}T/) { print "mtime\n"; }
    else { print "version=\$v\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$TF1"
if echo "$OUTPUT" | grep -q 'mtime' ; then
    pass "Test 23: P4version no depot, file not in hash -> mtime"
else
    fail "Test 23 no-depot-mtime: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 24: new() with depot, file in hash -> extract_version returns "#N"
# ---------------------------------------------------------------------------
export P4V_HAVE_LINES="//depot/foo.c#3 - $TF1"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES=""

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$file) = @ARGV;
my \$obj = P4version->new(\$0, \$depot);
if (defined \$obj) {
    print \$obj->extract_version(\$file) . "\n";
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$TF1"
if [ "$OUTPUT" = "#3" ] ; then
    pass "Test 24: P4version with depot, file in hash -> '#3'"
else
    fail "Test 24 in-hash: expected '#3', got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 25: new() with depot, file NOT in hash -> extract_version returns mtime
# ---------------------------------------------------------------------------
export P4V_HAVE_LINES="//depot/bar.c#5 - $TF2"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES=""

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$file) = @ARGV;
my \$obj = P4version->new(\$0, \$depot);
if (defined \$obj) {
    my \$v = \$obj->extract_version(\$file);
    if (\$v =~ /^\d{4}-\d{2}-\d{2}T/) { print "mtime\n"; }
    else { print "version=\$v\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$TF1"
if echo "$OUTPUT" | grep -q 'mtime' ; then
    pass "Test 25: P4version with depot, file not in hash -> mtime"
else
    fail "Test 25 not-in-hash: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 26: new() with depot, --md5, file not in hash -> "md5:HASH"
# ---------------------------------------------------------------------------
export P4V_HAVE_LINES="//depot/bar.c#5 - $TF2"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES=""

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$file, \$md5) = @ARGV;
my \$obj = P4version->new(\$0, '--md5', \$depot);
if (defined \$obj) {
    my \$v = \$obj->extract_version(\$file);
    if (\$v eq "md5:\$md5") { print "ok\n"; }
    else { print "version=\$v\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$TF1" "$MD5_TF1"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 26: P4version --md5, file not in hash -> 'md5:HASH'"
else
    fail "Test 26 md5-not-in-hash: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 27: opened edit, no --local-edit -> new() dies
# ---------------------------------------------------------------------------
export P4V_HAVE_LINES="//depot/foo.c#3 - $TF1"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES="//depot/foo.c#3 - edit default change (text)"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot) = @ARGV;
eval { P4version->new(\$0, \$depot); };
if (\$@) { print "died\n"; } else { print "no-die\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE"
if echo "$OUTPUT" | grep -q 'died' ; then
    pass "Test 27: P4version opened edit without --local-edit -> dies"
else
    fail "Test 27 no-local-edit: expected die, got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 28: opened edit, --local-edit -> version has " edited "
# ---------------------------------------------------------------------------
export P4V_HAVE_LINES="//depot/foo.c#3 - $TF1"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES="//depot/foo.c#3 - edit default change (text)"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$file) = @ARGV;
my \$obj = P4version->new(\$0, '--local-edit', \$depot);
if (defined \$obj) {
    my \$v = \$obj->extract_version(\$file);
    if (\$v =~ / edited /) { print "has_edited\n"; }
    else { print "version=\$v\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$TF1"
if echo "$OUTPUT" | grep -q 'has_edited' ; then
    pass "Test 28: P4version opened edit + --local-edit -> version has ' edited '"
else
    fail "Test 28 local-edit: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 29: opened integrate, --local-edit -> version has " edited "
# ---------------------------------------------------------------------------
export P4V_HAVE_LINES="//depot/foo.c#3 - $TF1"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES="//depot/foo.c#3 - integrate change 42 (text)"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$file) = @ARGV;
my \$obj = P4version->new(\$0, '--local-edit', \$depot);
if (defined \$obj) {
    my \$v = \$obj->extract_version(\$file);
    if (\$v =~ / edited /) { print "has_edited\n"; }
    else { print "version=\$v\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$TF1"
if echo "$OUTPUT" | grep -q 'has_edited' ; then
    pass "Test 29: P4version opened integrate + --local-edit -> version has ' edited '"
else
    fail "Test 29 integrate: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 30: opened add (new file not in have), --local-edit -> version built
# ---------------------------------------------------------------------------
# bar.c is in have; foo.c is a new add (not in have output)
export P4V_HAVE_LINES="//depot/bar.c#5 - $TF2"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES="//depot/foo.c#1 - add default change (text)"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$file) = @ARGV;
my \$obj = P4version->new(\$0, '--local-edit', \$depot);
if (defined \$obj) {
    my \$v = \$obj->extract_version(\$file);
    if (\$v =~ / edited /) { print "has_edited\n"; }
    else { print "version=\$v\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$TF1"
if echo "$OUTPUT" | grep -q 'has_edited' ; then
    pass "Test 30: P4version opened add (new file) + --local-edit -> version has ' edited '"
else
    fail "Test 30 add-new: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 31: opened delete (file not in filehash, missing from workspace) -> skip
# ---------------------------------------------------------------------------
# foo.c is missing from workspace so it doesn't appear in filehash after 'next unless -e'
MISSING_FILE="$WORKSPACE/gone.c"  # does not exist
export P4V_HAVE_LINES="//depot/bar.c#5 - $TF2"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES="//depot/gone.c#3 - delete default change (text)"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$file) = @ARGV;
my \$obj = P4version->new(\$0, '--local-edit', \$depot);
if (defined \$obj) {
    my \$v = \$obj->extract_version(\$file);
    if (\$v =~ /^\d{4}-\d{2}-\d{2}T/) { print "mtime\n"; }
    else { print "version=\$v\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$TF2"
if echo "$OUTPUT" | grep -q 'mtime\|#5' ; then
    pass "Test 31: P4version opened delete on missing file -> silently skipped"
else
    fail "Test 31 delete-skip: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 32: --local-edit --md5: version uses md5 instead of mtime
# ---------------------------------------------------------------------------
export P4V_HAVE_LINES="//depot/foo.c#3 - $TF1"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES="//depot/foo.c#3 - edit default change (text)"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$file, \$md5) = @ARGV;
my \$obj = P4version->new(\$0, '--local-edit', '--md5', \$depot);
if (defined \$obj) {
    my \$v = \$obj->extract_version(\$file);
    if (index(\$v, "md5:\$md5") >= 0) { print "has_md5\n"; }
    else { print "version=\$v\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$TF1" "$MD5_TF1"
if echo "$OUTPUT" | grep -q 'has_md5' ; then
    pass "Test 32: P4version --local-edit --md5 -> version contains md5"
else
    fail "Test 32 local-edit-md5: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 33: extract_version --allow-missing, file doesn't exist -> returns ''
# ---------------------------------------------------------------------------
export P4V_HAVE_LINES="//depot/foo.c#3 - $TF1"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES=""

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$missing) = @ARGV;
my \$obj = P4version->new(\$0, '--allow-missing', \$depot);
if (defined \$obj) {
    my \$v = \$obj->extract_version(\$missing);
    if (!defined(\$v) || \$v eq '') { print "empty\n"; }
    else { print "version=\$v\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$WORKSPACE/nonexistent.c"
if echo "$OUTPUT" | grep -q 'empty' ; then
    pass "Test 33: extract_version --allow-missing for missing file -> empty string"
else
    fail "Test 33 allow-missing: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 34: extract_version without --allow-missing, missing file -> dies
# ---------------------------------------------------------------------------
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$missing) = @ARGV;
my \$obj = P4version->new(\$0, \$depot);
if (defined \$obj) {
    eval { \$obj->extract_version(\$missing); };
    if (\$@) { print "died\n"; }
    else { print "no-die\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$WORKSPACE/nonexistent.c"
if echo "$OUTPUT" | grep -q 'died' ; then
    pass "Test 34: extract_version without --allow-missing for missing file -> dies"
else
    fail "Test 34 missing-no-flag: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 35: extract_version --prefix, relative path -> prefixed + found in hash
# ---------------------------------------------------------------------------
export P4V_HAVE_LINES="//depot/foo.c#3 - $TF1"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES=""

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$prefix) = @ARGV;
my \$obj = P4version->new(\$0, "--prefix=\$prefix", \$depot);
if (defined \$obj) {
    my \$v = \$obj->extract_version("foo.c");
    print \$v . "\n";
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$WORKSPACE"
if [ "$OUTPUT" = "#3" ] ; then
    pass "Test 35: extract_version --prefix prepends prefix to relative path"
else
    fail "Test 35 prefix: expected '#3', got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 36: compare_version same strings -> 0 (false)
# ---------------------------------------------------------------------------
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$file) = @ARGV;
my \$obj = P4version->new(\$0, \$depot);
my \$r = \$obj->compare_version("#3", "#3", \$file);
print "same=\$r\n";
PLEOF
export P4V_HAVE_LINES="//depot/foo.c#3 - $TF1"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES=""
run_p4version_pl "$PL" "$WORKSPACE" "$TF1"
if echo "$OUTPUT" | grep -qE 'same=$|same=0' ; then
    pass "Test 36: compare_version same strings -> false (0 / empty)"
else
    fail "Test 36 compare-same: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 37: compare_version different strings -> 1 (true)
# ---------------------------------------------------------------------------
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$file) = @ARGV;
my \$obj = P4version->new(\$0, \$depot);
my \$r = \$obj->compare_version("#3", "#5", \$file);
print "diff=\$r\n";
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$TF1"
if echo "$OUTPUT" | grep -q 'diff=1' ; then
    pass "Test 37: compare_version different strings -> 1"
else
    fail "Test 37 compare-diff: got: '$OUTPUT'"
fi
rm -f "$PL"

# ---------------------------------------------------------------------------
# Test 38: p4 have fails + empty filehash -> goto done, obj defined, mtime returned
# ---------------------------------------------------------------------------
export P4V_SUBCOMMAND_EXIT=1   # make all p4 sub-commands exit 1 (have fails)
unset P4V_HAVE_LINES
export P4V_HAVE_LINES=""       # empty output + bad exit -> close fails, empty hash

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use lcovutil;
lcovutil::parse_ignore_errors("usage");
use P4version;
my (\$depot, \$file) = @ARGV;
my \$obj = P4version->new(\$0, \$depot);
if (defined \$obj) {
    my \$v = \$obj->extract_version(\$file);
    if (\$v =~ /^\d{4}-\d{2}-\d{2}T/) { print "mtime\n"; }
    else { print "version=\$v\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$TF1"
if echo "$OUTPUT" | grep -q 'mtime' ; then
    pass "Test 38: p4 have fails, empty hash -> goto done, obj defined, extract returns mtime"
else
    fail "Test 38 goto-done: got: '$OUTPUT'"
fi
rm -f "$PL"
unset P4V_SUBCOMMAND_EXIT

# ---------------------------------------------------------------------------
# Test 39: opened delete on file that IS in filehash -> skip (next), version unchanged
# ---------------------------------------------------------------------------
export P4V_SUBCOMMAND_EXIT=0
# foo.c is in filehash and has pending delete -> opened loop hits: file exists in hash
# and action eq 'delete' -> die("file exists 'add' state") path?
# Wait: re-reading P4version.pm line 182-184:
#   if (exists($filehash{$1})) {
#       die("$1: file exists 'add' state $3") if 'add' eq $3;  # only dies for 'add'
#       $data = $filehash{$1};
#   } elsif ('delete' eq $3) { next; }   # delete NOT in hash -> skip
# So delete on a file IN the hash: goes into the if-block (not the elsif),
# then hits the local_edit check. With local_edit=0 -> die.
# The elsif 'delete' next path: file NOT in hash. Test 31 covers that.
#
# Let's test delete in hash WITH --local-edit: version gets overwritten to "depot edited mtime"
export P4V_HAVE_LINES="//depot/foo.c#3 - $TF1"
export P4V_WHERE_LINE="//depot/... //ws/... $WORKSPACE/..."
export P4V_OPENED_LINES="//depot/foo.c#3 - delete default change (text)"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use P4version;
my (\$depot, \$file) = @ARGV;
my \$obj = P4version->new(\$0, '--local-edit', \$depot);
if (defined \$obj) {
    my \$v = \$obj->extract_version(\$file);
    if (\$v =~ / edited /) { print "has_edited\n"; }
    else { print "version=\$v\n"; }
} else { print "undef\n"; }
PLEOF
run_p4version_pl "$PL" "$WORKSPACE" "$TF1"
if echo "$OUTPUT" | grep -q 'has_edited' ; then
    pass "Test 39: opened delete on file in hash + --local-edit -> version has ' edited '"
else
    fail "Test 39 delete-in-hash: got: '$OUTPUT'"
fi
rm -f "$PL"

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
if [ $FAIL -ne 0 ] ; then
    echo "Tests FAILED"
else
    echo "All p4version tests passed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover ${COVER_DB}
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB}
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch
fi

[ $FAIL -eq 0 ]
