#!/usr/bin/env bash
#
# Test suite for scripts/gitblame and scripts/gitblame.pm
#
# Each test calls $SCRIPT_DIR/gitblame with various inputs and checks expected
# output.  A local git repo is set up in a temp directory so we can exercise
# the git-blame parsing path without relying on an existing repo.
#
# Tests cover:
#   1.  --help flag exits 0 and prints usage
#   2.  Unknown option exits non-zero and prints usage
#   3.  Too many positional args exits non-zero
#   4.  Non-existent file exits non-zero
#   5.  File not in any git repo (fallback to filesystem annotation)
#   6.  Single-commit git repo: basic output format
#   7.  Empty email owner -> "unknown@nowhere.com"
#   8.  "dot" / "at" substitution in email field
#   9.  Domain filtering: internal users abbreviated, external -> "External"
#  10.  --abbrev flag: custom abbreviation pattern
#  11.  Multiple --abbrev patterns applied in order
#  12.  --abbrev caching: same owner on multiple lines uses cached result
#  13.  --verify flag succeeds on consistent repo
#  14.  --log flag: log file written and contains expected content
#  15.  Multi-author file: two different commit hashes, two different owners
#  16.  --p4 flag: CL extracted from git-p4 commit log comment
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

GITBLAME="$SCRIPT_DIR/gitblame"
if [ ! -x "$GITBLAME" ] ; then
    echo "gitblame script not found at '$GITBLAME'" >&2
    exit 1
fi
# Prepend coverage wrapper when active (same pattern used by other test scripts)
[ -n "$COVER" ] && GITBLAME="$COVER $GITBLAME"

# Require git
if ! which git >/dev/null 2>&1 ; then
    echo "git not available - skipping gitblame tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { echo "PASS: $1" ; ((PASS++)) ; }
fail() { echo "FAIL: $1" ; ((FAIL++)) ; if [ "$KEEP_GOING" != 1 ] ; then exit 1 ; fi ; }

#
# Helper: create a fresh git repo in a new temp directory.
# Prints the directory path; caller captures it and is responsible for cleanup.
#
make_git_repo() {
    local d
    d=$(mktemp -d)
    git -C "$d" init --quiet
    git -C "$d" config user.email "alice@mediatek.com"
    git -C "$d" config user.name  "Alice"
    echo "$d"
}

#
# Helper: commit staged changes with a fixed date so output is deterministic.
# Usage: fixed_commit <repodir> <message> [<date>]
#
fixed_commit() {
    local repo="$1" msg="$2" dt="${3:-2024-01-10 08:00:00 +0000}"
    GIT_AUTHOR_DATE="$dt" GIT_COMMITTER_DATE="$dt" \
        git -C "$repo" commit --quiet -m "$msg"
}

# -----------------------------------------------------------------------
# Test 1: --help exits 0 and prints usage to stderr
# -----------------------------------------------------------------------
OUTPUT=$($GITBLAME --help 2>&1)
RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 1 --help: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -q 'usage:' ; then
    fail "Test 1 --help: usage message not found in output"
else
    pass "Test 1: --help exits 0 and prints usage"
fi

# -----------------------------------------------------------------------
# Test 2: unknown option exits non-zero and prints usage
# -----------------------------------------------------------------------
OUTPUT=$($GITBLAME --no-such-option /tmp/file 2>&1)
RC=$?
if [ $RC -eq 0 ] ; then
    fail "Test 2 bad option: expected non-zero exit, got 0"
elif ! echo "$OUTPUT" | grep -q 'usage:' ; then
    fail "Test 2 bad option: usage message not found in output"
else
    pass "Test 2: unknown option rejected with usage"
fi

# -----------------------------------------------------------------------
# Test 3: too many positional args (domain + extra + file) exits non-zero
# -----------------------------------------------------------------------
TMP3=$(mktemp)
echo "x" > "$TMP3"
OUTPUT=$($GITBLAME example.com extra_arg "$TMP3" 2>&1)
RC=$?
rm -f "$TMP3"
if [ $RC -eq 0 ] ; then
    fail "Test 3 too many args: expected non-zero exit, got 0"
elif ! echo "$OUTPUT" | grep -q 'usage:' ; then
    fail "Test 3 too many args: usage message not found"
else
    pass "Test 3: too many positional args rejected"
fi

# -----------------------------------------------------------------------
# Test 4: non-existent file exits non-zero
# -----------------------------------------------------------------------
OUTPUT=$($GITBLAME /tmp/does_not_exist_gitblame_test_xyz 2>&1)
RC=$?
if [ $RC -eq 0 ] ; then
    fail "Test 4 nonexistent: expected non-zero exit, got 0"
elif ! echo "$OUTPUT" | grep -q 'expected readable file' ; then
    fail "Test 4 nonexistent: expected 'expected readable file' in error"
else
    pass "Test 4: nonexistent file produces error"
fi

# -----------------------------------------------------------------------
# Test 5: file not in git repo (fallback to filesystem annotation)
#   Output format: NONE|<user>|<timestamp>|<text>
#   - no semicolon/full-email field because 'full' is undef in not_in_repo
# -----------------------------------------------------------------------
TMP5=$(mktemp)
printf 'alpha\nbeta\ngamma\n' > "$TMP5"
OUTPUT=$($GITBLAME "$TMP5" 2>&1)
RC=$?
rm -f "$TMP5"
if [ $RC -ne 0 ] ; then
    fail "Test 5 not-in-repo: expected exit 0, got $RC"
else
    # Every line should be NONE|owner|timestamp|text (no semicolon for full email)
    LINES=$(echo "$OUTPUT" | wc -l)
    NONE_COUNT=$(echo "$OUTPUT" | grep -c '^NONE|')
    SEMI_COUNT=$(echo "$OUTPUT" | grep -c ';')   # should be 0 (no full-email)
    if [ "$LINES" -ne 3 ] || [ "$NONE_COUNT" -ne 3 ] ; then
        fail "Test 5 not-in-repo: expected 3 NONE lines, got $NONE_COUNT of $LINES"
    elif [ "$SEMI_COUNT" -ne 0 ] ; then
        fail "Test 5 not-in-repo: unexpected semicolon (full-email) in output"
    else
        pass "Test 5: not-in-repo fallback produces NONE|owner|ts|text lines"
    fi
fi

# -----------------------------------------------------------------------
# Test 6: basic git-blame output format
#   Format: <hash>|<email>;<email>|<timestamp>|<text>
# -----------------------------------------------------------------------
REPO6=$(make_git_repo)
printf 'line one\nline two\nline three\n' > "$REPO6/sample.c"
git -C "$REPO6" add sample.c
fixed_commit "$REPO6" "initial" "2023-05-15 10:00:00 -0800"

OUTPUT=$($GITBLAME "$REPO6/sample.c" 2>&1)
RC=$?
rm -rf "$REPO6"
if [ $RC -ne 0 ] ; then
    fail "Test 6 basic: expected exit 0, got $RC"
else
    # Each line: <hash>|alice@mediatek.com;alice@mediatek.com|2023-05-15T10:00:00-08:00|line N
    LINES=$(echo "$OUTPUT" | wc -l)
    MATCH=$(echo "$OUTPUT" | grep -c '|alice@mediatek\.com;alice@mediatek\.com|2023-05-15T10:00:00-08:00|line ')
    if [ "$LINES" -ne 3 ] || [ "$MATCH" -ne 3 ] ; then
        fail "Test 6 basic: unexpected output (got $MATCH/3 matching lines of $LINES total):
$OUTPUT"
    else
        pass "Test 6: basic git-blame output format correct"
    fi
fi

# -----------------------------------------------------------------------
# Test 7: empty email owner becomes "unknown@nowhere.com"
# -----------------------------------------------------------------------
REPO7=$(make_git_repo)
git -C "$REPO7" config user.email ""
printf 'only line\n' > "$REPO7/empty.c"
git -C "$REPO7" add empty.c
fixed_commit "$REPO7" "empty email" "2024-03-01 12:00:00 +0000"

OUTPUT=$($GITBLAME "$REPO7/empty.c" 2>&1)
RC=$?
rm -rf "$REPO7"
if [ $RC -ne 0 ] ; then
    fail "Test 7 empty email: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -q 'unknown@nowhere\.com' ; then
    fail "Test 7 empty email: expected 'unknown@nowhere.com' in output, got: $OUTPUT"
else
    pass "Test 7: empty email replaced with unknown@nowhere.com"
fi

# -----------------------------------------------------------------------
# Test 8: "dot" / "at" substitution in email field
#   Email "alice dot jones at example dot com" -> "alice.jones@example.com"
# -----------------------------------------------------------------------
REPO8=$(make_git_repo)
git -C "$REPO8" config user.email "alice dot jones at example dot com"
printf 'test line\n' > "$REPO8/dots.c"
git -C "$REPO8" add dots.c
fixed_commit "$REPO8" "dot-at email" "2024-03-01 12:00:00 +0000"

OUTPUT=$($GITBLAME "$REPO8/dots.c" 2>&1)
RC=$?
rm -rf "$REPO8"
if [ $RC -ne 0 ] ; then
    fail "Test 8 dot/at: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -q 'alice\.jones@example\.com' ; then
    fail "Test 8 dot/at: expected 'alice.jones@example.com', got: $OUTPUT"
else
    pass "Test 8: 'dot'/'at' substitution in email produces correct address"
fi

# -----------------------------------------------------------------------
# Test 9: domain filtering
#   internal user (alice@mediatek.com) -> abbreviated to "alice"
#   external user (bob@other.org)      -> replaced with "External"
# -----------------------------------------------------------------------
REPO9=$(make_git_repo)
printf 'alice line 1\nalice line 2\n' > "$REPO9/mixed.c"
git -C "$REPO9" add mixed.c
fixed_commit "$REPO9" "alice commit" "2023-05-15 10:00:00 -0800"

# Bob adds a line in a second commit
git -C "$REPO9" config user.email "bob@other.org"
git -C "$REPO9" config user.name  "Bob"
printf 'alice line 1\nalice line 2\nbob line 3\n' > "$REPO9/mixed.c"
GIT_AUTHOR_DATE="2023-06-20 14:30:00 +0530" GIT_COMMITTER_DATE="2023-06-20 14:30:00 +0530" \
    git -C "$REPO9" commit --quiet -a -m "bob adds line"

OUTPUT=$($GITBLAME 'mediatek\.com' "$REPO9/mixed.c" 2>&1)
RC=$?
rm -rf "$REPO9"
if [ $RC -ne 0 ] ; then
    fail "Test 9 domain: expected exit 0, got $RC"
else
    ALICE=$(echo "$OUTPUT" | grep -c '^[^|]*|alice;alice@mediatek\.com|')
    EXTERNAL=$(echo "$OUTPUT" | grep -c '^[^|]*|External;bob@other\.org|')
    if [ "$ALICE" -ne 2 ] ; then
        fail "Test 9 domain: expected 2 alice lines, got $ALICE:
$OUTPUT"
    elif [ "$EXTERNAL" -ne 1 ] ; then
        fail "Test 9 domain: expected 1 External line, got $EXTERNAL:
$OUTPUT"
    else
        pass "Test 9: domain filtering abbreviates internal, labels external"
    fi
fi

# -----------------------------------------------------------------------
# Test 10: --abbrev flag custom substitution
# -----------------------------------------------------------------------
REPO10=$(make_git_repo)
printf 'line one\nline two\n' > "$REPO10/abbrev.c"
git -C "$REPO10" add abbrev.c
fixed_commit "$REPO10" "abbrev test" "2024-01-10 08:00:00 +0000"

OUTPUT=$($GITBLAME '--abbrev=s/\@mediatek\.com$//' "$REPO10/abbrev.c" 2>&1)
RC=$?
rm -rf "$REPO10"
if [ $RC -ne 0 ] ; then
    fail "Test 10 --abbrev: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -q '|alice;alice@mediatek\.com|' ; then
    fail "Test 10 --abbrev: expected abbreviated 'alice' with full 'alice@mediatek.com', got:
$OUTPUT"
else
    pass "Test 10: --abbrev strips domain suffix from owner"
fi

# -----------------------------------------------------------------------
# Test 11: multiple --abbrev patterns applied in sequence
#   Pattern 1: strip @mediatek.com -> "alice"
#   Pattern 2: strip anything remaining -> no-op when pattern 1 matched
# -----------------------------------------------------------------------
REPO11=$(make_git_repo)
git -C "$REPO11" config user.email "bob@other.org"
git -C "$REPO11" config user.name  "Bob"
printf 'bob line\n' > "$REPO11/multi.c"
git -C "$REPO11" add multi.c
fixed_commit "$REPO11" "multi abbrev" "2024-01-10 08:00:00 +0000"

# Pattern 1 won't match bob@other.org; pattern 2 changes to "External"
OUTPUT=$($GITBLAME \
    '--abbrev=s/\@mediatek\.com$//' \
    '--abbrev=s/^[^@]+\@.+$/External/' \
    "$REPO11/multi.c" 2>&1)
RC=$?
rm -rf "$REPO11"
if [ $RC -ne 0 ] ; then
    fail "Test 11 multi-abbrev: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -q '|External;bob@other\.org|' ; then
    fail "Test 11 multi-abbrev: expected 'External' owner, got:
$OUTPUT"
else
    pass "Test 11: multiple --abbrev patterns applied in sequence"
fi

# -----------------------------------------------------------------------
# Test 12: abbrev caching - same owner on many lines resolved only once
#   (functional: all lines have same abbreviated owner)
# -----------------------------------------------------------------------
REPO12=$(make_git_repo)
printf 'a\nb\nc\nd\ne\n' > "$REPO12/cached.c"
git -C "$REPO12" add cached.c
fixed_commit "$REPO12" "cache test" "2024-01-10 08:00:00 +0000"

OUTPUT=$($GITBLAME '--abbrev=s/\@mediatek\.com$//' "$REPO12/cached.c" 2>&1)
RC=$?
rm -rf "$REPO12"
if [ $RC -ne 0 ] ; then
    fail "Test 12 caching: expected exit 0, got $RC"
else
    # All 5 lines should have abbreviated owner "alice"
    ALICE=$(echo "$OUTPUT" | grep -c '|alice;alice@mediatek\.com|')
    if [ "$ALICE" -ne 5 ] ; then
        fail "Test 12 caching: expected 5 alice lines, got $ALICE"
    else
        pass "Test 12: abbrev caching - all 5 lines have same abbreviated owner"
    fi
fi

# -----------------------------------------------------------------------
# Test 13: --verify flag succeeds when annotation matches file exactly
# -----------------------------------------------------------------------
REPO13=$(make_git_repo)
printf 'verify line 1\nverify line 2\n' > "$REPO13/verify.c"
git -C "$REPO13" add verify.c
fixed_commit "$REPO13" "verify test" "2024-01-10 08:00:00 +0000"

OUTPUT=$($GITBLAME --verify "$REPO13/verify.c" 2>&1)
RC=$?
rm -rf "$REPO13"
if [ $RC -ne 0 ] ; then
    fail "Test 13 --verify: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '|verify line ' ; then
    fail "Test 13 --verify: unexpected output:
$OUTPUT"
else
    pass "Test 13: --verify flag passes on consistent repo"
fi

# -----------------------------------------------------------------------
# Test 14: --log flag creates log file with expected content
# -----------------------------------------------------------------------
REPO14=$(make_git_repo)
printf 'log test line\n' > "$REPO14/log.c"
git -C "$REPO14" add log.c
fixed_commit "$REPO14" "log test" "2024-01-10 08:00:00 +0000"

LOGFILE14=$(mktemp)
$GITBLAME --log "$LOGFILE14" "$REPO14/log.c" > /dev/null 2>&1
RC=$?
rm -rf "$REPO14"

if [ $RC -ne 0 ] ; then
    fail "Test 14 --log: expected exit 0, got $RC"
elif [ ! -s "$LOGFILE14" ] ; then
    fail "Test 14 --log: log file is empty"
elif ! grep -q 'gitblame' "$LOGFILE14" ; then
    fail "Test 14 --log: log file missing 'gitblame' entry"
else
    pass "Test 14: --log creates non-empty log file with tool name"
fi
rm -f "$LOGFILE14"

# -----------------------------------------------------------------------
# Test 15: multi-author file - two distinct commit hashes and owners
# -----------------------------------------------------------------------
REPO15=$(make_git_repo)
printf 'alice line 1\nalice line 2\n' > "$REPO15/two.c"
git -C "$REPO15" add two.c
fixed_commit "$REPO15" "alice commit" "2023-01-01 09:00:00 +0000"

git -C "$REPO15" config user.email "carol@mediatek.com"
git -C "$REPO15" config user.name  "Carol"
printf 'alice line 1\nalice line 2\ncarol line 3\n' > "$REPO15/two.c"
GIT_AUTHOR_DATE="2024-06-01 15:00:00 +0000" GIT_COMMITTER_DATE="2024-06-01 15:00:00 +0000" \
    git -C "$REPO15" commit --quiet -a -m "carol adds line"

OUTPUT=$($GITBLAME "$REPO15/two.c" 2>&1)
RC=$?
rm -rf "$REPO15"
if [ $RC -ne 0 ] ; then
    fail "Test 15 multi-author: expected exit 0, got $RC"
else
    ALICE=$(echo "$OUTPUT" | grep -c 'alice@mediatek\.com')
    CAROL=$(echo "$OUTPUT" | grep -c 'carol@mediatek\.com')
    # Extract unique hashes (field 1 before first |)
    HASHES=$(echo "$OUTPUT" | cut -d'|' -f1 | sort -u | wc -l)
    if [ "$ALICE" -ne 2 ] || [ "$CAROL" -ne 1 ] ; then
        fail "Test 15 multi-author: wrong owner counts (alice=$ALICE carol=$CAROL):
$OUTPUT"
    elif [ "$HASHES" -ne 2 ] ; then
        fail "Test 15 multi-author: expected 2 distinct commit hashes, got $HASHES"
    else
        pass "Test 15: multi-author file produces distinct hashes and owners"
    fi
fi

# -----------------------------------------------------------------------
# Test 16: --p4 flag - CL extracted from git-p4 commit log comment
#   The p4 code path triggers on non-root commits (root commits get a "^"
#   prefix on the hash in git-blame output which breaks "git show -s ^hash").
#   We create a two-commit repo so the second commit's hash has no ^ prefix.
#   The second commit message contains "git-p4: ... change = 99887".
#   Annotated output should use "99887" instead of the git SHA for that line.
# -----------------------------------------------------------------------
REPO16=$(make_git_repo)
printf 'first line\n' > "$REPO16/p4.c"
git -C "$REPO16" add p4.c
fixed_commit "$REPO16" "initial (no p4 info)" "2022-01-01 10:00:00 +0000"

# Second commit (non-root, no ^ prefix in blame) with git-p4 CL annotation
printf 'first line\np4 added line\n' > "$REPO16/p4.c"
GIT_AUTHOR_DATE="2022-11-01 11:00:00 +0000" GIT_COMMITTER_DATE="2022-11-01 11:00:00 +0000" \
    git -C "$REPO16" commit --quiet -a -m \
        "$(printf 'add p4 line\n\ngit-p4: depot-paths = //depot/main/: change = 99887')"

OUTPUT=$($GITBLAME --p4 "$REPO16/p4.c" 2>&1)
RC=$?
rm -rf "$REPO16"
if [ $RC -ne 0 ] ; then
    fail "Test 16 --p4: expected exit 0, got $RC; output: $OUTPUT"
elif ! echo "$OUTPUT" | grep -q '^99887|' ; then
    fail "Test 16 --p4: expected p4 CL '99887' as commit field, got:
$OUTPUT"
else
    pass "Test 16: --p4 extracts CL number from git-p4 commit message"
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ] ; then
    exit 1
fi
echo "All gitblame tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover ${COVER_DB}
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB}
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch
fi

[ $FAIL -eq 0 ]
