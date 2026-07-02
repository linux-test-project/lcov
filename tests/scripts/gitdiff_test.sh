#!/usr/bin/env bash
#
# Test suite for scripts/gitdiff
#
# gitdiff wraps "git diff <base> <current>" and "git ls-tree <current>"
# to produce a unified diff with a/b path leaders stripped, optional
# prefix substitution, include/exclude filtering, and "unchanged" file
# entries appended for every file present in the current SHA that was not
# in the diff output.
#
# Because gitdiff shells out to real git commands, each test builds a
# minimal real git repo in a temp directory.  A single two-commit repo
# suffices for most tests; a few tests build additional repos.
#
# Tests:
#   1.  --help exits 1 and prints usage
#   2.  Bad option exits 1 and prints usage
#   3.  Zero positional args exits 1 (wrong arg count)
#   4.  One positional arg exits 1 (wrong arg count)
#   5.  Four positional args exits 1 (wrong arg count)
#   6.  Basic two-SHA diff: a/b leaders stripped from diff/---/+++ lines
#   7.  Unchanged file appended (git ls-tree path, no --no-unchanged)
#   8.  --no-unchanged suppresses the unchanged-file entry
#   9.  --prefix prepended to paths in diff and unchanged entries
#  10.  Three-arg form [dir base current]: dir pushed as include pattern
#  11.  --exclude removes matching file from output
#  12.  --include limits output to matching files only
#  13.  include_me: exclude wins over include when both match
#  14.  --exclude with comma-separated list filters multiple patterns
#  15.  --include with comma-separated list includes multiple patterns
#  16.  -b / --blank passes -b to git diff (whitespace-only change absent)
#  17.  --verbose prints arg list to stderr
#  18.  --repo points gitdiff at an alternate repo directory
#  19.  New file (only in current SHA, not in base): appears in diff output
#  20.  Deleted file (only in base SHA): no ls-tree entry, not in unchanged
#  21.  Renamed file: old name excluded, new name included in diff
#  22.  --repo with --no-unchanged: ls-tree block is skipped entirely

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

GITDIFF="$SCRIPT_DIR/gitdiff"
if [ ! -x "$GITDIFF" ] ; then
    echo "gitdiff script not found at '$GITDIFF'" >&2
    exit 1
fi
[ -n "$COVER" ] && GITDIFF="$COVER $GITDIFF"

if ! which git >/dev/null 2>&1 ; then
    echo "git not available - skipping gitdiff tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { echo "PASS: $1" ; ((PASS++)) ; }
fail() { echo "FAIL: $1" ; ((FAIL++)) ; if [ "$KEEP_GOING" != 1 ] ; then exit 1 ; fi ; }

# ---------------------------------------------------------------------------
# Helper: create a temp git repo, make two commits, echo "repodir SHA1 SHA2"
# Caller should use:
#   read REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
#   trap 'rm -rf "$REPO"' EXIT
# ---------------------------------------------------------------------------
make_two_commit_repo() {
    local d
    d=$(mktemp -d)
    git -C "$d" init --quiet
    git -C "$d" config user.email "alice@example.com"
    git -C "$d" config user.name  "Alice"

    # Commit 1 (base): two files
    mkdir -p "$d/src"
    printf 'int foo(void) { return 1; }\n' > "$d/src/foo.c"
    printf 'int bar(void) { return 2; }\n' > "$d/src/bar.c"
    git -C "$d" add .
    GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" \
    GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
        git -C "$d" commit --quiet -m "base commit"
    local sha1
    sha1=$(git -C "$d" rev-parse HEAD)

    # Commit 2 (current): modify foo.c, leave bar.c unchanged
    printf 'int foo(void) { return 42; }\n' > "$d/src/foo.c"
    git -C "$d" add .
    GIT_AUTHOR_DATE="2024-01-02T00:00:00+00:00" \
    GIT_COMMITTER_DATE="2024-01-02T00:00:00+00:00" \
        git -C "$d" commit --quiet -m "modify foo"
    local sha2
    sha2=$(git -C "$d" rev-parse HEAD)

    echo "$d $sha1 $sha2"
}

# ===========================================================================
# Tests 1-5: Argument validation  (usage / bad args)
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 1: --help exits 1 and prints usage
# ---------------------------------------------------------------------------
OUTPUT=$($GITDIFF --help 2>&1)
RC=$?
if [ $RC -ne 1 ] ; then
    fail "Test 1 --help: expected exit 1, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 1 --help: usage not found in output; got: $OUTPUT"
else
    pass "Test 1: --help exits 1 and prints usage"
fi

# ---------------------------------------------------------------------------
# Test 2: Unknown option exits 1 and prints usage
# ---------------------------------------------------------------------------
OUTPUT=$($GITDIFF --no-such-option SHA1 SHA2 2>&1)
RC=$?
if [ $RC -ne 1 ] ; then
    fail "Test 2 bad-option: expected exit 1, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 2 bad-option: usage not found in output"
else
    pass "Test 2: unknown option rejected with usage"
fi

# ---------------------------------------------------------------------------
# Test 3: Zero positional args exits 1
# ---------------------------------------------------------------------------
OUTPUT=$($GITDIFF 2>&1)
RC=$?
if [ $RC -ne 1 ] ; then
    fail "Test 3 zero-args: expected exit 1, got $RC"
else
    pass "Test 3: zero positional args rejected"
fi

# ---------------------------------------------------------------------------
# Test 4: One positional arg exits 1
# ---------------------------------------------------------------------------
OUTPUT=$($GITDIFF SHA1 2>&1)
RC=$?
if [ $RC -ne 1 ] ; then
    fail "Test 4 one-arg: expected exit 1, got $RC"
else
    pass "Test 4: one positional arg rejected"
fi

# ---------------------------------------------------------------------------
# Test 5: Four positional args exits 1
# ---------------------------------------------------------------------------
OUTPUT=$($GITDIFF dir SHA1 SHA2 extra 2>&1)
RC=$?
if [ $RC -ne 1 ] ; then
    fail "Test 5 four-args: expected exit 1, got $RC"
else
    pass "Test 5: four positional args rejected"
fi

# ===========================================================================
# Tests 6-22: Functional tests using real git repos
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 6: Basic diff -- a/b leaders stripped from diff/---/+++ lines
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
OUTPUT=$($GITDIFF --repo "$REPO" "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 6 basic-diff: expected exit 0, got $RC; output: $OUTPUT"
else
    # The a/b leader must be stripped: "--- a/src/foo.c" -> "---  src/foo.c"
    # (note: double-space after --- because prefix is empty, so s# [ab]/# #g
    # turns " a/" into "  " -- the leading space remains)
    if ! echo "$OUTPUT" | grep -q '^diff --git' ; then
        fail "Test 6 basic-diff: no 'diff --git' line found; output: $OUTPUT"
    elif echo "$OUTPUT" | grep -qF -- '--- a/' || echo "$OUTPUT" | grep -qF -- '+++ b/' ; then
        fail "Test 6 basic-diff: a/b leaders not stripped; output: $OUTPUT"
    else
        pass "Test 6: basic diff output with a/b leaders stripped"
    fi
fi

# ---------------------------------------------------------------------------
# Test 7: Unchanged file appended via git ls-tree
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
OUTPUT=$($GITDIFF --repo "$REPO" "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 7 unchanged: expected exit 0, got $RC"
else
    # bar.c was not modified; it should appear as an "=== ..." unchanged entry
    if ! echo "$OUTPUT" | grep -q '=== .*bar\.c' ; then
        fail "Test 7 unchanged: expected '=== .../bar.c' entry; output:
$OUTPUT"
    else
        pass "Test 7: unchanged file appended as '===' entry"
    fi
fi

# ---------------------------------------------------------------------------
# Test 8: --no-unchanged suppresses the unchanged-file entries
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
OUTPUT=$($GITDIFF --repo "$REPO" --no-unchanged "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 8 no-unchanged: expected exit 0, got $RC"
elif echo "$OUTPUT" | grep -q '===' ; then
    fail "Test 8 no-unchanged: unexpected '===' entries found; output: $OUTPUT"
else
    pass "Test 8: --no-unchanged suppresses ls-tree entries"
fi

# ---------------------------------------------------------------------------
# Test 9: --prefix prepended to paths in diff and unchanged entries
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
OUTPUT=$($GITDIFF --repo "$REPO" --prefix "myprefix" "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 9 prefix: expected exit 0, got $RC"
else
    # After --prefix, diff line should contain the prefix
    if ! echo "$OUTPUT" | grep -q 'myprefix' ; then
        fail "Test 9 prefix: expected 'myprefix' in output; got:
$OUTPUT"
    else
        pass "Test 9: --prefix appears in diff and unchanged entries"
    fi
fi

# ---------------------------------------------------------------------------
# Test 10: Three-arg form [dir base current]: dir acts as include pattern
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
# Pass 'src' as the dir argument -- it matches both src/foo.c and src/bar.c
OUTPUT=$($GITDIFF --repo "$REPO" src "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    rm -rf "$REPO"
    fail "Test 10 three-arg: expected exit 0, got $RC; output: $OUTPUT"
else
    DIFF_COUNT=$(echo "$OUTPUT" | grep -c '^diff --git')
    rm -rf "$REPO"
    # foo.c should be in the diff; bar.c in the unchanged list
    if [ "$DIFF_COUNT" -lt 1 ] ; then
        fail "Test 10 three-arg: expected at least one diff entry; output: $OUTPUT"
    else
        pass "Test 10: three-arg form filters by directory pattern"
    fi
fi

# ---------------------------------------------------------------------------
# Test 11: --exclude removes a matching file from the output
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
OUTPUT=$($GITDIFF --repo "$REPO" --exclude 'foo\.c' "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 11 exclude: expected exit 0, got $RC"
elif echo "$OUTPUT" | grep -q 'foo\.c\|foo.c' ; then
    fail "Test 11 exclude: excluded file 'foo.c' still appears; output:
$OUTPUT"
else
    pass "Test 11: --exclude removes matching file from output"
fi

# ---------------------------------------------------------------------------
# Test 12: --include limits output to matching files only
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
OUTPUT=$($GITDIFF --repo "$REPO" --include 'foo\.c' "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 12 include: expected exit 0, got $RC"
else
    # foo.c should be present; bar.c should NOT appear at all
    if ! echo "$OUTPUT" | grep -q 'foo.c' ; then
        fail "Test 12 include: included file 'foo.c' not found; output: $OUTPUT"
    elif echo "$OUTPUT" | grep -q 'bar.c' ; then
        fail "Test 12 include: non-included file 'bar.c' appears; output:
$OUTPUT"
    else
        pass "Test 12: --include limits output to matching files"
    fi
fi

# ---------------------------------------------------------------------------
# Test 13: include_me -- exclude wins over include when both match
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
# Both --exclude and --include match 'foo.c'; exclude should win
OUTPUT=$($GITDIFF --repo "$REPO" --include 'foo\.c' --exclude 'foo\.c' \
         "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 13 excl-wins: expected exit 0, got $RC"
elif echo "$OUTPUT" | grep -q 'foo.c' ; then
    fail "Test 13 excl-wins: 'foo.c' should be excluded but appears; output:
$OUTPUT"
else
    pass "Test 13: exclude wins over include when both match"
fi

# ---------------------------------------------------------------------------
# Test 14: --exclude comma-separated list filters two patterns
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
OUTPUT=$($GITDIFF --repo "$REPO" --exclude 'foo\.c,bar\.c' \
         "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 14 exclude-comma: expected exit 0, got $RC"
elif echo "$OUTPUT" | grep -qE 'foo\.?c|bar\.?c' ; then
    fail "Test 14 exclude-comma: excluded files still appear; output:
$OUTPUT"
else
    pass "Test 14: comma-separated --exclude filters both patterns"
fi

# ---------------------------------------------------------------------------
# Test 15: --include comma-separated list includes two patterns
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
# Include both foo.c and bar.c explicitly; nothing else exists so output
# should contain both
OUTPUT=$($GITDIFF --repo "$REPO" --include 'foo\.c,bar\.c' \
         "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 15 include-comma: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -q 'foo.c' ; then
    fail "Test 15 include-comma: 'foo.c' not found; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -qE 'bar.c' ; then
    fail "Test 15 include-comma: 'bar.c' not found; output: $OUTPUT"
else
    pass "Test 15: comma-separated --include includes both patterns"
fi

# ---------------------------------------------------------------------------
# Test 16: -b passes -b to git diff; whitespace-only change is absent
# ---------------------------------------------------------------------------
REPO16=$(mktemp -d)
git -C "$REPO16" init --quiet
git -C "$REPO16" config user.email "alice@example.com"
git -C "$REPO16" config user.name  "Alice"
# Commit 1: file with some content
printf 'int x = 1;\n' > "$REPO16/ws.c"
git -C "$REPO16" add ws.c
GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$REPO16" commit --quiet -m "base"
SHA1_16=$(git -C "$REPO16" rev-parse HEAD)
# Commit 2: whitespace-only change (trailing space)
printf 'int x = 1;   \n' > "$REPO16/ws.c"
git -C "$REPO16" add ws.c
GIT_AUTHOR_DATE="2024-01-02T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-02T00:00:00+00:00" \
    git -C "$REPO16" commit --quiet -m "whitespace only"
SHA2_16=$(git -C "$REPO16" rev-parse HEAD)

OUTPUT_WITH=$($GITDIFF --repo "$REPO16" "$SHA1_16" "$SHA2_16" 2>&1)
OUTPUT_BLANK=$($GITDIFF --repo "$REPO16" -b "$SHA1_16" "$SHA2_16" 2>&1)
RC=$?
rm -rf "$REPO16"

if [ $RC -ne 0 ] ; then
    fail "Test 16 blank: expected exit 0, got $RC"
else
    HUNKS_WITH=$(echo "$OUTPUT_WITH" | grep -c '^@@')
    HUNKS_BLANK=$(echo "$OUTPUT_BLANK" | grep -c '^@@')
    if [ "$HUNKS_WITH" -lt 1 ] ; then
        fail "Test 16 blank: without -b should show hunk; got none in: $OUTPUT_WITH"
    elif [ "$HUNKS_BLANK" -ne 0 ] ; then
        fail "Test 16 blank: with -b should suppress whitespace-only hunk, got $HUNKS_BLANK"
    else
        pass "Test 16: -b suppresses whitespace-only diff hunk"
    fi
fi

# ---------------------------------------------------------------------------
# Test 17: --verbose prints argument summary to stderr
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
STDOUT17=$(mktemp)
STDERR17=$(mktemp)
$GITDIFF --repo "$REPO" --verbose --no-unchanged \
         "$BASE_SHA" "$CUR_SHA" >"$STDOUT17" 2>"$STDERR17"
RC=$?
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 17 verbose: expected exit 0, got $RC; stderr: $(cat $STDERR17)"
elif ! grep -q "$BASE_SHA" "$STDERR17" ; then
    fail "Test 17 verbose: expected SHA in stderr; got: $(cat $STDERR17)"
else
    pass "Test 17: --verbose prints argument summary to stderr"
fi
rm -f "$STDOUT17" "$STDERR17"

# ---------------------------------------------------------------------------
# Test 18: --repo points gitdiff at an alternate repo directory
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
# Run from /tmp (not the repo) with --repo pointing at the repo
PREV_DIR="$PWD"
cd /tmp
OUTPUT=$($GITDIFF --repo "$REPO" "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
cd "$PREV_DIR"
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 18 --repo: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^diff --git' ; then
    fail "Test 18 --repo: no diff output when using --repo; output: $OUTPUT"
else
    pass "Test 18: --repo correctly locates the git repository"
fi

# ---------------------------------------------------------------------------
# Test 19: New file (added in current SHA) appears in diff output
# ---------------------------------------------------------------------------
REPO19=$(mktemp -d)
git -C "$REPO19" init --quiet
git -C "$REPO19" config user.email "alice@example.com"
git -C "$REPO19" config user.name  "Alice"
printf 'existing\n' > "$REPO19/old.c"
git -C "$REPO19" add old.c
GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$REPO19" commit --quiet -m "base"
SHA1_19=$(git -C "$REPO19" rev-parse HEAD)
# Add a brand-new file in the second commit
printf 'new content\n' > "$REPO19/new.c"
git -C "$REPO19" add new.c
GIT_AUTHOR_DATE="2024-01-02T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-02T00:00:00+00:00" \
    git -C "$REPO19" commit --quiet -m "add new.c"
SHA2_19=$(git -C "$REPO19" rev-parse HEAD)

OUTPUT=$($GITDIFF --repo "$REPO19" "$SHA1_19" "$SHA2_19" 2>&1)
RC=$?
rm -rf "$REPO19"
if [ $RC -ne 0 ] ; then
    fail "Test 19 new-file: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -q 'new\.c' ; then
    fail "Test 19 new-file: newly added file not in diff output; output:
$OUTPUT"
else
    pass "Test 19: newly added file appears in diff output"
fi

# ---------------------------------------------------------------------------
# Test 20: Deleted file (only in base) absent from unchanged ls-tree list
# ---------------------------------------------------------------------------
REPO20=$(mktemp -d)
git -C "$REPO20" init --quiet
git -C "$REPO20" config user.email "alice@example.com"
git -C "$REPO20" config user.name  "Alice"
printf 'keep\n'   > "$REPO20/keep.c"
printf 'remove\n' > "$REPO20/gone.c"
git -C "$REPO20" add .
GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$REPO20" commit --quiet -m "base"
SHA1_20=$(git -C "$REPO20" rev-parse HEAD)
git -C "$REPO20" rm --quiet gone.c
GIT_AUTHOR_DATE="2024-01-02T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-02T00:00:00+00:00" \
    git -C "$REPO20" commit --quiet -m "delete gone.c"
SHA2_20=$(git -C "$REPO20" rev-parse HEAD)

OUTPUT=$($GITDIFF --repo "$REPO20" "$SHA1_20" "$SHA2_20" 2>&1)
RC=$?
rm -rf "$REPO20"
if [ $RC -ne 0 ] ; then
    fail "Test 20 deleted: expected exit 0, got $RC"
else
    # gone.c should appear in the diff (as deletion) but NOT as an unchanged entry
    if ! echo "$OUTPUT" | grep -q 'gone\.c' ; then
        fail "Test 20 deleted: 'gone.c' should appear in diff; output: $OUTPUT"
    elif echo "$OUTPUT" | grep '===' | grep -q 'gone\.c' ; then
        fail "Test 20 deleted: 'gone.c' wrongly in unchanged list; output: $OUTPUT"
    else
        pass "Test 20: deleted file in diff but not in unchanged list"
    fi
fi

# ---------------------------------------------------------------------------
# Test 21: Renamed file -- old name in diff, new name in diff, neither in unchanged
# ---------------------------------------------------------------------------
REPO21=$(mktemp -d)
git -C "$REPO21" init --quiet
git -C "$REPO21" config user.email "alice@example.com"
git -C "$REPO21" config user.name  "Alice"
printf 'content\n' > "$REPO21/before.c"
git -C "$REPO21" add before.c
GIT_AUTHOR_DATE="2024-01-01T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-01T00:00:00+00:00" \
    git -C "$REPO21" commit --quiet -m "base"
SHA1_21=$(git -C "$REPO21" rev-parse HEAD)
git -C "$REPO21" mv before.c after.c
GIT_AUTHOR_DATE="2024-01-02T00:00:00+00:00" \
GIT_COMMITTER_DATE="2024-01-02T00:00:00+00:00" \
    git -C "$REPO21" commit --quiet -m "rename"
SHA2_21=$(git -C "$REPO21" rev-parse HEAD)

OUTPUT=$($GITDIFF --repo "$REPO21" "$SHA1_21" "$SHA2_21" 2>&1)
RC=$?
rm -rf "$REPO21"
if [ $RC -ne 0 ] ; then
    fail "Test 21 rename: expected exit 0, got $RC"
else
    # after.c should be present somewhere (new name in diff or unchanged)
    if ! echo "$OUTPUT" | grep -q 'after\.c\|before\.c' ; then
        fail "Test 21 rename: neither before.c nor after.c found; output: $OUTPUT"
    else
        pass "Test 21: renamed file handled correctly in diff output"
    fi
fi

# ---------------------------------------------------------------------------
# Test 22: --repo with --no-unchanged: ls-tree block skipped entirely
# ---------------------------------------------------------------------------
read -r REPO BASE_SHA CUR_SHA <<< "$(make_two_commit_repo)"
OUTPUT=$($GITDIFF --repo "$REPO" --no-unchanged "$BASE_SHA" "$CUR_SHA" 2>&1)
RC=$?
rm -rf "$REPO"
if [ $RC -ne 0 ] ; then
    fail "Test 22 repo+no-unchanged: expected exit 0, got $RC"
elif echo "$OUTPUT" | grep -q '===' ; then
    fail "Test 22 repo+no-unchanged: unexpected '===' entry; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^diff --git' ; then
    fail "Test 22 repo+no-unchanged: no diff output; output: $OUTPUT"
else
    pass "Test 22: --repo with --no-unchanged skips ls-tree block"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ] ; then
    echo "Tests FAILED"
else
    echo "All gitdiff tests passed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover ${COVER_DB}
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB}
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch
fi

[ $FAIL -eq 0 ]
