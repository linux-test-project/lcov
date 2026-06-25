#!/usr/bin/env bash
#
# Test suite for scripts/gitversion and scripts/gitversion.pm
#
# gitversion/gitversion.pm queries "git log --no-abbrev --oneline -1 <file>"
# to determine the version of a source file.  Tests use real git repos built
# in temp directories wherever git commands are required, and plain temp files
# for not-in-repo and argument-parsing scenarios.
#
# Note: the gitversion WRAPPER script does not expose --local-change (it is
# not in its GetOptions list).  Tests for CHECK_LOCAL_CHANGE therefore call
# gitversion.pm directly via "perl -I$SCRIPT_DIR".
#
# Tests:
#   1.  --help exits 0 and prints usage
#   2.  Bad option exits 1 and prints usage
#   3.  --compare with wrong arg count (2 args) exits 1
#   4.  --compare with wrong arg count (4 args) exits 1
#   5.  File does not exist, no --allow-missing -> die with hint
#   6.  File does not exist, --allow-missing -> exits 0, empty output
#   7.  File outside any git repo -> mtime timestamp (ISO 8601 format)
#   8.  File outside any git repo, --md5 -> mtime + " md5:<hash>"
#   9.  File in git repo (no --p4) -> "SHA <full-40-char-hash>"
#  10.  File in git repo, --md5 (no local change) -> SHA only (no md5)
#  11.  --p4 with git-p4 commit annotation -> "CL <number>"
#  12.  --p4 with no git-p4 annotation -> raw SHA (no "SHA " prefix)
#  13.  --prefix prepends path before resolving the file
#  14.  --compare same SHA -> exit 0
#  15.  --compare different SHA -> exit 1
#  16.  --compare --md5, both have md5, same hash -> exit 0
#  17.  --compare --md5, both have md5, different hash -> exit 1
#  18.  --compare --md5, old has md5 but new does not -> fall through, exit 1
#  19.  --compare --md5 --p4, old starts "CL" -> skip md5 branch, exact match
#  20.  --local-change (via .pm), file clean -> SHA only
#  21.  --local-change (via .pm), file has uncommitted edit -> "SHA ... edited <mtime>"
#  22.  --local-change --md5 (via .pm), file dirty -> "SHA ... edited <mtime> md5:<hash>"
#  23.  --local-change (via .pm), file clean -> no "edited" in output
#  24.  new() via .pm returns undef for bad option (not standalone)
#  25.  git log returns no output for file -> falls to not-in-git mtime path
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

GITVERSION="$SCRIPT_DIR/gitversion"
if [ ! -x "$GITVERSION" ] ; then
    echo "gitversion script not found at '$GITVERSION'" >&2
    exit 1
fi
[ -n "$COVER" ] && GITVERSION="$COVER $GITVERSION"

if ! which git >/dev/null 2>&1 ; then
    echo "git not available - skipping gitversion tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { echo "PASS: $1" ; ((PASS++)) ; }
fail() { echo "FAIL: $1" ; ((FAIL++)) ; if [ "$KEEP_GOING" != 1 ] ; then exit 1 ; fi ; }

# ---------------------------------------------------------------------------
# Helper: build a one-commit git repo; print "repodir sha"
# ---------------------------------------------------------------------------
make_one_commit_repo() {
    local d msg
    d=$(mktemp -d)
    msg="${1:-initial commit}"
    git -C "$d" init --quiet
    git -C "$d" config user.email "alice@example.com"
    git -C "$d" config user.name  "Alice"
    printf 'int main(void) { return 0; }\n' > "$d/f.c"
    git -C "$d" add f.c
    GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" \
    GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
        git -C "$d" commit --quiet -m "$msg"
    local sha
    sha=$(git -C "$d" rev-parse HEAD)
    echo "$d $sha"
}

# ===========================================================================
# Tests 1-4: Argument validation
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 1: --help exits 0 and prints usage
# ---------------------------------------------------------------------------
OUTPUT=$($GITVERSION --help 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 1 --help: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 1 --help: usage not in output; got: $OUTPUT"
else
    pass "Test 1: --help exits 0 and prints usage"
fi

# ---------------------------------------------------------------------------
# Test 2: Bad option exits 1 and prints usage
# ---------------------------------------------------------------------------
OUTPUT=$($GITVERSION --no-such-option /tmp/x 2>&1)
RC=$?
if [ $RC -ne 1 ] ; then
    fail "Test 2 bad-option: expected exit 1, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 2 bad-option: usage not in output"
else
    pass "Test 2: bad option exits 1 with usage"
fi

# ---------------------------------------------------------------------------
# Test 3: --compare with 2 positional args (need 3) -> exits 1
# ---------------------------------------------------------------------------
TF3=$(mktemp) ; echo "x" > "$TF3"
OUTPUT=$($GITVERSION --compare "v1" "v2" 2>&1)
RC=$?
rm -f "$TF3"
if [ $RC -ne 1 ] ; then
    fail "Test 3 compare-2args: expected exit 1, got $RC"
else
    pass "Test 3: --compare with 2 args rejected"
fi

# ---------------------------------------------------------------------------
# Test 4: --compare with 4 positional args -> exits 1
# ---------------------------------------------------------------------------
TF4=$(mktemp) ; echo "x" > "$TF4"
OUTPUT=$($GITVERSION --compare "v1" "v2" "$TF4" extra 2>&1)
RC=$?
rm -f "$TF4"
if [ $RC -ne 1 ] ; then
    fail "Test 4 compare-4args: expected exit 1, got $RC"
else
    pass "Test 4: --compare with 4 args rejected"
fi

# ===========================================================================
# Tests 5-8: File-existence and not-in-git paths
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 5: Non-existent file without --allow-missing -> die with hint
# ---------------------------------------------------------------------------
OUTPUT=$($GITVERSION /tmp/no_such_file_gitversion_test_xyz 2>&1)
RC=$?
if [ $RC -eq 0 ] ; then
    fail "Test 5 missing-no-flag: expected non-zero exit, got 0"
elif ! echo "$OUTPUT" | grep -q 'allow-missing\|does not exist' ; then
    fail "Test 5 missing-no-flag: expected hint in error; got: $OUTPUT"
else
    pass "Test 5: missing file without --allow-missing dies with hint"
fi

# ---------------------------------------------------------------------------
# Test 6: Non-existent file with --allow-missing -> exits 0, empty output
# ---------------------------------------------------------------------------
OUTPUT=$($GITVERSION --allow-missing /tmp/no_such_file_gitversion_test_xyz 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 6 allow-missing: expected exit 0, got $RC; output: $OUTPUT"
elif [ -n "$OUTPUT" ] ; then
    fail "Test 6 allow-missing: expected empty output, got: $OUTPUT"
else
    pass "Test 6: --allow-missing returns empty string for missing file"
fi

# ---------------------------------------------------------------------------
# Test 7: File not in any git repo -> ISO 8601 mtime timestamp
# ---------------------------------------------------------------------------
TF7=$(mktemp)
printf 'content\n' > "$TF7"
OUTPUT=$($GITVERSION "$TF7" 2>&1)
RC=$?
rm -f "$TF7"
if [ $RC -ne 0 ] ; then
    fail "Test 7 not-in-git: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$' ; then
    fail "Test 7 not-in-git: expected ISO 8601 timestamp, got: $OUTPUT"
else
    pass "Test 7: file not in git repo -> ISO 8601 mtime timestamp"
fi

# ---------------------------------------------------------------------------
# Test 8: File not in any git repo, --md5 -> mtime + " md5:<hash>"
# ---------------------------------------------------------------------------
TF8=$(mktemp)
printf 'content\n' > "$TF8"
OUTPUT=$($GITVERSION --md5 "$TF8" 2>&1)
RC=$?
rm -f "$TF8"
if [ $RC -ne 0 ] ; then
    fail "Test 8 not-in-git-md5: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qE '^[0-9]{4}-.*T.* md5:[0-9a-f]+$' ; then
    fail "Test 8 not-in-git-md5: expected 'mtime md5:<hash>', got: $OUTPUT"
else
    pass "Test 8: not-in-git with --md5 appends md5 to mtime"
fi

# ===========================================================================
# Tests 9-12: In-git SHA / --p4 paths
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 9: File in git repo, no flags -> "SHA <40-char-hash>"
# ---------------------------------------------------------------------------
read -r REPO9 SHA9 <<< "$(make_one_commit_repo 'initial')"
OUTPUT=$($GITVERSION "$REPO9/f.c" 2>&1)
RC=$?
rm -rf "$REPO9"
if [ $RC -ne 0 ] ; then
    fail "Test 9 sha: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qE '^SHA [0-9a-f]{40}$' ; then
    fail "Test 9 sha: expected 'SHA <40-char-hash>', got: $OUTPUT"
else
    pass "Test 9: in-git file -> 'SHA <full-hash>'"
fi

# ---------------------------------------------------------------------------
# Test 10: File in git repo, --md5, no local change -> SHA only (no md5)
#   --md5 only adds md5 when file is not-in-git OR has a local change.
#   In the clean git-tracked case the md5 flag has no effect on output.
# ---------------------------------------------------------------------------
read -r REPO10 SHA10 <<< "$(make_one_commit_repo 'initial')"
OUTPUT=$($GITVERSION --md5 "$REPO10/f.c" 2>&1)
RC=$?
rm -rf "$REPO10"
if [ $RC -ne 0 ] ; then
    fail "Test 10 sha-md5-clean: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qE '^SHA [0-9a-f]{40}$' ; then
    fail "Test 10 sha-md5-clean: expected 'SHA <hash>' (no md5 in clean git), got: $OUTPUT"
else
    pass "Test 10: in-git, --md5, no local change -> SHA only"
fi

# ---------------------------------------------------------------------------
# Test 11: --p4 with git-p4 annotation -> "CL <number>"
# ---------------------------------------------------------------------------
REPO11=$(mktemp -d)
git -C "$REPO11" init --quiet
git -C "$REPO11" config user.email "alice@example.com"
git -C "$REPO11" config user.name  "Alice"
printf 'v1\n' > "$REPO11/f.c"
git -C "$REPO11" add f.c
GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$REPO11" commit --quiet -m "base"
# Second commit with git-p4 annotation
printf 'v2\n' > "$REPO11/f.c"
git -C "$REPO11" add f.c
GIT_AUTHOR_DATE="2024-01-02T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-02T00:00:00+00:00" \
    git -C "$REPO11" commit --quiet -m \
    "$(printf 'update\n\ngit-p4: depot-paths = //depot/: change = 98765')"
OUTPUT=$($GITVERSION --p4 "$REPO11/f.c" 2>&1)
RC=$?
rm -rf "$REPO11"
if [ $RC -ne 0 ] ; then
    fail "Test 11 p4-cl: expected exit 0, got $RC; output: $OUTPUT"
elif [ "$OUTPUT" != "CL 98765" ] ; then
    fail "Test 11 p4-cl: expected 'CL 98765', got: $OUTPUT"
else
    pass "Test 11: --p4 with git-p4 annotation -> 'CL <number>'"
fi

# ---------------------------------------------------------------------------
# Test 12: --p4 with no git-p4 annotation -> raw SHA (no "SHA " prefix, no "CL ")
#   When git show -s finds no "git-p4:.+change = N" the version stays as the
#   raw SHA string set from git log (no "SHA " prefix is added in this branch).
# ---------------------------------------------------------------------------
read -r REPO12 SHA12 <<< "$(make_one_commit_repo 'no p4 annotation here')"
OUTPUT=$($GITVERSION --p4 "$REPO12/f.c" 2>&1)
RC=$?
rm -rf "$REPO12"
if [ $RC -ne 0 ] ; then
    fail "Test 12 p4-no-cl: expected exit 0, got $RC; output: $OUTPUT"
elif echo "$OUTPUT" | grep -q '^CL ' ; then
    fail "Test 12 p4-no-cl: unexpected 'CL' prefix; got: $OUTPUT"
elif echo "$OUTPUT" | grep -q '^SHA ' ; then
    fail "Test 12 p4-no-cl: unexpected 'SHA' prefix in --p4 no-annotation path; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qE '^[0-9a-f]{40}$' ; then
    fail "Test 12 p4-no-cl: expected raw 40-char SHA, got: $OUTPUT"
else
    pass "Test 12: --p4 with no annotation -> raw SHA (no prefix)"
fi

# ---------------------------------------------------------------------------
# Test 13: --prefix prepends path component before resolving the file
# ---------------------------------------------------------------------------
REPO13=$(mktemp -d)
git -C "$REPO13" init --quiet
git -C "$REPO13" config user.email "alice@example.com"
git -C "$REPO13" config user.name  "Alice"
mkdir -p "$REPO13/sub"
printf 'code\n' > "$REPO13/sub/g.c"
git -C "$REPO13" add sub/g.c
GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$REPO13" commit --quiet -m "add sub/g.c"
# Pass relative basename "g.c" with --prefix pointing at sub/
OUTPUT=$($GITVERSION --prefix "$REPO13/sub" g.c 2>&1)
RC=$?
rm -rf "$REPO13"
if [ $RC -ne 0 ] ; then
    fail "Test 13 prefix: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qE '^SHA [0-9a-f]{40}$' ; then
    fail "Test 13 prefix: expected 'SHA <hash>' after prefix join, got: $OUTPUT"
else
    pass "Test 13: --prefix prepends path, file resolved and versioned"
fi

# ===========================================================================
# Tests 14-19: compare_version branches
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 14: --compare same SHA -> exit 0 (no difference)
# ---------------------------------------------------------------------------
TF14=$(mktemp) ; echo "x" > "$TF14"
$GITVERSION --compare "SHA abc123" "SHA abc123" "$TF14" 2>&1
RC=$?
rm -f "$TF14"
[ $RC -eq 0 ] && pass "Test 14: --compare same SHA -> exit 0" ||
    fail "Test 14 compare-same: expected exit 0, got $RC"

# ---------------------------------------------------------------------------
# Test 15: --compare different SHA -> exit 1
# ---------------------------------------------------------------------------
TF15=$(mktemp) ; echo "x" > "$TF15"
$GITVERSION --compare "SHA abc123" "SHA xyz999" "$TF15" 2>&1
RC=$?
rm -f "$TF15"
[ $RC -eq 1 ] && pass "Test 15: --compare different SHA -> exit 1" ||
    fail "Test 15 compare-diff: expected exit 1, got $RC"

# ---------------------------------------------------------------------------
# Test 16: --compare --md5, both versions carry same md5 -> exit 0
#   Branch: MD5 set, old !~ /^SHA/, !P4, old =~ / md5:/, new =~ / md5:/ -> compare md5s
# ---------------------------------------------------------------------------
TF16=$(mktemp) ; echo "x" > "$TF16"
MD5_16=$(md5sum "$TF16" | awk '{print $1}')
$GITVERSION --md5 --compare \
    "2024-01-01T00:00:00+00:00 md5:${MD5_16}" \
    "2024-01-01T00:00:00+00:00 md5:${MD5_16}" \
    "$TF16" 2>&1
RC=$?
rm -f "$TF16"
[ $RC -eq 0 ] && pass "Test 16: --compare --md5 same md5 -> exit 0" ||
    fail "Test 16 md5-same: expected exit 0, got $RC"

# ---------------------------------------------------------------------------
# Test 17: --compare --md5, both versions carry different md5 -> exit 1
# ---------------------------------------------------------------------------
TF17=$(mktemp) ; echo "x" > "$TF17"
MD5_17=$(md5sum "$TF17" | awk '{print $1}')
$GITVERSION --md5 --compare \
    "2024-01-01T00:00:00+00:00 md5:${MD5_17}" \
    "2024-01-01T00:00:00+00:00 md5:DIFFERENTHASH" \
    "$TF17" 2>&1
RC=$?
rm -f "$TF17"
[ $RC -eq 1 ] && pass "Test 17: --compare --md5 different md5 -> exit 1" ||
    fail "Test 17 md5-diff: expected exit 1, got $RC"

# ---------------------------------------------------------------------------
# Test 18: --compare --md5, old has md5 but new does not -> fall through to
#   exact string match -> exit 1 (strings differ)
# ---------------------------------------------------------------------------
TF18=$(mktemp) ; echo "x" > "$TF18"
MD5_18=$(md5sum "$TF18" | awk '{print $1}')
$GITVERSION --md5 --compare \
    "2024-01-01T00:00:00+00:00 md5:${MD5_18}" \
    "2024-01-01T00:00:00+00:00" \
    "$TF18" 2>&1
RC=$?
rm -f "$TF18"
[ $RC -eq 1 ] && pass "Test 18: --compare --md5 old-has-md5 new-lacks-md5 -> fall-through exit 1" ||
    fail "Test 18 md5-no-new: expected exit 1, got $RC"

# ---------------------------------------------------------------------------
# Test 19: --compare --md5 --p4, old starts "CL" -> skip md5 branch, exact match
#   Condition: !P4 is false (P4 set) AND old =~ /^CL/ -> inner condition true
#   -> overall (old !~ /^CL/) part causes the whole MD5 block to be skipped.
# ---------------------------------------------------------------------------
TF19=$(mktemp) ; echo "x" > "$TF19"
MD5_19=$(md5sum "$TF19" | awk '{print $1}')
# Same CL number -> exact match -> exit 0
$GITVERSION --md5 --p4 --compare \
    "CL 12345 md5:${MD5_19}" \
    "CL 12345 md5:${MD5_19}" \
    "$TF19" 2>&1
RC_SAME=$?
# Different CL number -> exact match fails -> exit 1
$GITVERSION --md5 --p4 --compare \
    "CL 12345 md5:${MD5_19}" \
    "CL 99999 md5:${MD5_19}" \
    "$TF19" 2>&1
RC_DIFF=$?
rm -f "$TF19"
if [ $RC_SAME -ne 0 ] ; then
    fail "Test 19 p4-cl-same: expected exit 0, got $RC_SAME"
elif [ $RC_DIFF -ne 1 ] ; then
    fail "Test 19 p4-cl-diff: expected exit 1, got $RC_DIFF"
else
    pass "Test 19: --compare --md5 --p4 with CL prefix skips md5, uses exact match"
fi

# ===========================================================================
# Tests 20-25: CHECK_LOCAL_CHANGE and .pm new() edge cases (via perl -I)
# ===========================================================================

# Inline Perl helper that calls extract_version, printing the result.
# Usage:  perl_extract SCRIPT_DIR flags... -- filepath
perl_gitversion_extract() {
    local sdir="$1" ; shift
    local file="${@: -1}"   # last argument
    local flags=("${@:1:$#-1}")
    perl -I"$sdir" -e "
use gitversion;
my \$obj = gitversion->new(\"$sdir/gitversion\", $(printf '"%s",' "${flags[@]}") \"$file\");
if (defined \$obj) {
    print \$obj->extract_version(\"$file\") . \"\\n\";
} else {
    print \"undef\\n\";
}
" 2>&1
}

# ---------------------------------------------------------------------------
# Test 20: --local-change, file committed and clean -> SHA only, no "edited"
# ---------------------------------------------------------------------------
read -r REPO20 SHA20 <<< "$(make_one_commit_repo 'local-change-clean')"
OUTPUT=$(perl_gitversion_extract "$SCRIPT_DIR" "--local-change" "$REPO20/f.c")
RC=$?
rm -rf "$REPO20"
if [ $RC -ne 0 ] ; then
    fail "Test 20 local-clean: perl error; got: $OUTPUT"
elif echo "$OUTPUT" | grep -q 'edited' ; then
    fail "Test 20 local-clean: 'edited' should not appear for clean file; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qE '^SHA [0-9a-f]{40}$' ; then
    fail "Test 20 local-clean: expected 'SHA <hash>', got: $OUTPUT"
else
    pass "Test 20: --local-change on clean file -> SHA only"
fi

# ---------------------------------------------------------------------------
# Test 21: --local-change, file has uncommitted edit -> "SHA <hash> edited <mtime>"
# ---------------------------------------------------------------------------
read -r REPO21 SHA21 <<< "$(make_one_commit_repo 'local-change-dirty')"
echo "modified" > "$REPO21/f.c"   # local edit, not staged or committed
OUTPUT=$(perl_gitversion_extract "$SCRIPT_DIR" "--local-change" "$REPO21/f.c")
RC=$?
rm -rf "$REPO21"
if [ $RC -ne 0 ] ; then
    fail "Test 21 local-dirty: perl error; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q 'edited' ; then
    fail "Test 21 local-dirty: expected 'edited' in output; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qE '^SHA [0-9a-f]{40} edited ' ; then
    fail "Test 21 local-dirty: expected 'SHA <hash> edited <ts>', got: $OUTPUT"
else
    pass "Test 21: --local-change on dirty file -> 'SHA <hash> edited <mtime>'"
fi

# ---------------------------------------------------------------------------
# Test 22: --local-change --md5, dirty file -> "SHA ... edited <mtime> md5:<hash>"
# ---------------------------------------------------------------------------
read -r REPO22 SHA22 <<< "$(make_one_commit_repo 'local-change-md5')"
echo "modified" > "$REPO22/f.c"
OUTPUT=$(perl_gitversion_extract "$SCRIPT_DIR" "--local-change" "--md5" "$REPO22/f.c")
RC=$?
rm -rf "$REPO22"
if [ $RC -ne 0 ] ; then
    fail "Test 22 local-dirty-md5: perl error; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qE 'edited .* md5:[0-9a-f]+' ; then
    fail "Test 22 local-dirty-md5: expected 'edited <ts> md5:<hash>', got: $OUTPUT"
else
    pass "Test 22: --local-change --md5 on dirty file -> 'SHA ... edited <ts> md5:<hash>'"
fi

# ---------------------------------------------------------------------------
# Test 23: --local-change, file clean, no "edited" keyword at all
#   (Belt-and-suspenders: verifies no md5 either in clean case)
# ---------------------------------------------------------------------------
read -r REPO23 SHA23 <<< "$(make_one_commit_repo 'local-change-clean2')"
OUTPUT=$(perl_gitversion_extract "$SCRIPT_DIR" "--local-change" "--md5" "$REPO23/f.c")
RC=$?
rm -rf "$REPO23"
if [ $RC -ne 0 ] ; then
    fail "Test 23 local-clean-md5: perl error; got: $OUTPUT"
elif echo "$OUTPUT" | grep -q 'md5\|edited' ; then
    fail "Test 23 local-clean-md5: no md5 or edited for clean in-git file; got: $OUTPUT"
else
    pass "Test 23: --local-change --md5 on clean file -> SHA only (no md5, no edited)"
fi

# ---------------------------------------------------------------------------
# Test 24: gitversion.pm new() returns undef for bad option when not standalone
#   (When called as a module, not as $0, it returns undef rather than exiting)
# ---------------------------------------------------------------------------
OUTPUT=$(perl -I"$SCRIPT_DIR" -e '
use gitversion;
my $obj = gitversion->new("some_other_script", "--bad-flag", "/tmp/x");
print defined($obj) ? "defined" : "undef";
print "\n";
' 2>&1)
RC=$?
if echo "$OUTPUT" | grep -q 'undef' ; then
    pass "Test 24: new() returns undef for bad option when not standalone"
else
    fail "Test 24 new-undef: expected 'undef', got: $OUTPUT (exit $RC)"
fi

# ---------------------------------------------------------------------------
# Test 25: git log returns no output for the file (e.g. untracked file in
#   a git repo) -> falls through to not-in-git mtime path
# ---------------------------------------------------------------------------
REPO25=$(mktemp -d)
git -C "$REPO25" init --quiet
git -C "$REPO25" config user.email "alice@example.com"
git -C "$REPO25" config user.name  "Alice"
# Create and commit a different file; leave g.c untracked
printf 'other\n' > "$REPO25/other.c"
git -C "$REPO25" add other.c
GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$REPO25" commit --quiet -m "other file"
# g.c is untracked: git log returns nothing for it
printf 'untracked\n' > "$REPO25/g.c"
OUTPUT=$($GITVERSION "$REPO25/g.c" 2>&1)
RC=$?
rm -rf "$REPO25"
if [ $RC -ne 0 ] ; then
    fail "Test 25 untracked: expected exit 0, got $RC; output: $OUTPUT"
elif echo "$OUTPUT" | grep -qE '^SHA ' ; then
    fail "Test 25 untracked: untracked file should not produce SHA; got: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' ; then
    fail "Test 25 untracked: expected mtime timestamp for untracked file; got: $OUTPUT"
else
    pass "Test 25: untracked file in git repo -> falls through to mtime timestamp"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ] ; then
    echo "Tests FAILED"
else
    echo "All gitversion tests passed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover ${COVER_DB}
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB}
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch
fi

[ $FAIL -eq 0 ]
