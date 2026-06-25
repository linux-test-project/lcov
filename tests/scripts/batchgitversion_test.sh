#!/usr/bin/env bash
#
# Test suite for scripts/batchGitVersion.pm
#
# batchGitVersion.pm builds a blob-SHA database from "git ls-tree -r HEAD" and
# "git submodule foreach", then answers extract_version / compare_version queries
# against that database.
#
# Tests use real git repos built in temp directories; for sub-command injection
# tests a fake 'git' is placed at the front of PATH.
#
# Tests:
#   --- standalone invocation via call_get_version ---
#   1.  --help exits 0 and prints verbose usage
#   2.  Bad option exits 1 and prints short usage
#   3.  Basic: file in repo -> "BLOB <sha>"
#   --- OO new() argument validation ---
#   4.  Bad option to new() returns undef (non-standalone)
#   5.  --help to new() returns undef (non-standalone)
#   --- extract_version branches ---
#   6.  File found via prefix stripping -> "BLOB <sha>"
#   7.  File found directly (no prefix) -> "BLOB <sha>"
#   8.  File not in DB, exists on disk -> mtime (ISO8601)
#   9.  File not in DB, exists on disk, --md5 -> mtime + " md5:<hash>"
#  10.  File not in DB, not on disk, --allow-missing -> empty string
#  11.  File not in DB, not on disk, no --allow-missing -> dies
#  --- --prepend option ---
#  12.  --prepend prefix/path: DB keys are prepend/file -> lookup via prepend/file
#  --- --token option ---
#  13.  --token SHA overrides the default BLOB token in version string
#  --- --repo option / cwd fallback ---
#  14.  No --repo: uses getcwd() as repo root
#  --- compare_version branches ---
#  15.  compare_version same BLOB strings -> 0 (false)
#  16.  compare_version different BLOB strings -> 1 (true)
#  17.  compare_version --md5, old has md5 (no BLOB prefix), both same -> 0
#  18.  compare_version --md5, old has md5, new has md5, differ -> 1
#  19.  compare_version --md5, old starts BLOB (not md5 branch) -> exact match
#  20.  compare_version --md5, old has md5 but new has none -> fall through, 1
#  --- verbose output ---
#  21.  -v prints verbose extract_version trace to stdout
#  22.  -v during new() prints "enter/exit submodule" for submodule entries
#  23.  -v countdown truncation: only first N files printed then " ..."
#  --- submodule handling ---
#  24.  File in submodule: key is subname/file -> "BLOB <sha>"
#  25.  Unexpected ls-tree line (main scan) -> message to stderr, obj still built
#  26.  Unexpected submodule foreach line -> message to stderr, obj still built

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

BGV="$SCRIPT_DIR/batchGitVersion.pm"
if [ ! -f "$BGV" ] ; then
    echo "batchGitVersion.pm not found at '$BGV'" >&2
    exit 1
fi

# When coverage is active, $COVER is "perl -MDevel::Cover=... " so use it as
# the perl interpreter for all .pm invocations to collect coverage data.
PERL="${COVER:-perl}"

if ! which git >/dev/null 2>&1 ; then
    echo "git not available - skipping batchGitVersion tests"
    exit 0
fi

PASS=0
FAIL=0

pass() { echo "PASS: $1" ; ((PASS++)) ; }
fail() { echo "FAIL: $1" ; ((FAIL++)) ; if [ "$KEEP_GOING" != 1 ] ; then exit 1 ; fi ; }

# ---------------------------------------------------------------------------
# Helper: build a minimal one-commit git repo with foo.c committed.
# Prints "repodir sha" where sha is the blob sha of foo.c.
# ---------------------------------------------------------------------------
make_repo() {
    local d
    d=$(mktemp -d)
    git -C "$d" init --quiet
    git -C "$d" config user.email "test@example.com"
    git -C "$d" config user.name "Test"
    echo "int main(){}" > "$d/foo.c"
    echo "// bar" > "$d/bar.c"
    git -C "$d" add foo.c bar.c
    git -C "$d" commit --quiet -m "initial"
    local sha
    sha=$(git -C "$d" ls-tree HEAD foo.c | awk '{print $3}')
    echo "$d $sha"
}

# ---------------------------------------------------------------------------
# Helper: run a Perl script against batchGitVersion.pm
# ---------------------------------------------------------------------------
run_pl() {
    local pl_file="$1"; shift
    OUTPUT=$($PERL -I"$SCRIPT_DIR" "$pl_file" "$@" 2>&1)
    RC=$?
}

# ---------------------------------------------------------------------------
# Helper: build a repo with a fake git that injects custom ls-tree output.
# Sets MOCKDIR and installs it at front of PATH.
# Caller must: export PATH="$MOCKDIR:$PATH" before use and restore after.
# ---------------------------------------------------------------------------
install_fake_git() {
    MOCKDIR=$(mktemp -d)
    cat > "$MOCKDIR/git" << ENDSCRIPT
#!/usr/bin/env bash
if [[ "\$*" == *"ls-tree"*"HEAD"* ]] && [[ "\$*" != *"submodule"* ]]; then
    ${BGV_LSTREE_CMD:-true}
    exit 0
elif [[ "\$*" == *"submodule"*"foreach"* ]]; then
    ${BGV_SUBMOD_CMD:-true}
    exit 0
else
    /usr/bin/git "\$@"
fi
ENDSCRIPT
    chmod +x "$MOCKDIR/git"
}

# ===========================================================================
# Build a shared test repo used for most tests
# ===========================================================================
read -r REPODIR FOO_SHA <<< "$(make_repo)"
MD5_FOO=$(md5sum "$REPODIR/foo.c" | awk '{print $1}')
trap 'rm -rf "$REPODIR"' EXIT

# ===========================================================================
# Tests 1-2: standalone invocation via call_get_version
# ===========================================================================

# Test 1: --help exits 0 and prints verbose usage
OUTPUT=$($PERL -I"$SCRIPT_DIR" "$BGV" --help "$REPODIR/foo.c" 2>&1); RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 1 --help: expected exit 0, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 1 --help: usage not in output"
elif ! echo "$OUTPUT" | grep -qi 'allow-missing' ; then
    fail "Test 1 --help: verbose help text not in output"
else
    pass "Test 1: standalone --help exits 0 with verbose usage"
fi

# Test 2: bad option exits 1 with short usage
OUTPUT=$($PERL -I"$SCRIPT_DIR" "$BGV" --bad-option "$REPODIR/foo.c" 2>&1); RC=$?
if [ $RC -ne 1 ] ; then
    fail "Test 2 bad-option: expected exit 1, got $RC"
elif ! echo "$OUTPUT" | grep -qi 'usage' ; then
    fail "Test 2 bad-option: usage not in output"
else
    pass "Test 2: standalone bad option exits 1 with short usage"
fi

# Test 3: basic standalone - file in repo -> "BLOB <sha>"
OUTPUT=$($PERL -I"$SCRIPT_DIR" "$BGV" "--repo=$REPODIR" "$REPODIR/foo.c" 2>&1); RC=$?
if [ $RC -ne 0 ] ; then
    fail "Test 3 basic: expected exit 0, got $RC"
elif [ "$OUTPUT" != "BLOB $FOO_SHA" ] ; then
    fail "Test 3 basic: expected 'BLOB $FOO_SHA', got: '$OUTPUT'"
else
    pass "Test 3: standalone invocation returns BLOB sha for committed file"
fi

# ===========================================================================
# Tests 4-5: OO new() argument validation
# ===========================================================================

# Test 4: bad option to new() returns undef
PL=$(mktemp --suffix=.pl)
cat > "$PL" << 'PLEOF'
use batchGitVersion;
my $obj = batchGitVersion->new('/fake/script', '--bad-option');
print defined($obj) ? "defined\n" : "undef\n";
PLEOF
run_pl "$PL"
if echo "$OUTPUT" | grep -q 'undef' ; then
    pass "Test 4: new() with bad option returns undef"
else
    fail "Test 4 bad-option-oo: expected undef, got: '$OUTPUT'"
fi
rm -f "$PL"

# Test 5: --help to new() returns undef
PL=$(mktemp --suffix=.pl)
cat > "$PL" << 'PLEOF'
use batchGitVersion;
my $obj = batchGitVersion->new('/fake/script', '--help');
print defined($obj) ? "defined\n" : "undef\n";
PLEOF
run_pl "$PL"
if echo "$OUTPUT" | grep -q 'undef' ; then
    pass "Test 5: new() with --help returns undef"
else
    fail "Test 5 help-oo: expected undef, got: '$OUTPUT'"
fi
rm -f "$PL"

# ===========================================================================
# Tests 6-11: extract_version branches
# ===========================================================================

# Test 6: file found via prefix stripping -> "BLOB <sha>"
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my (\$repo, \$sha) = @ARGV;
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo");
if (defined \$obj) {
    my \$v = \$obj->extract_version("\$repo/foo.c");
    print \$v eq "BLOB \$sha" ? "ok\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$REPODIR" "$FOO_SHA"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 6: extract_version finds file via prefix stripping -> BLOB sha"
else
    fail "Test 6 prefix-strip: got: '$OUTPUT'"
fi
rm -f "$PL"

# Test 7: file found directly in DB (no prefix needed) -> "BLOB <sha>"
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my (\$repo, \$sha) = @ARGV;
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo");
if (defined \$obj) {
    my \$v = \$obj->extract_version("foo.c");
    print \$v eq "BLOB \$sha" ? "ok\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$REPODIR" "$FOO_SHA"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 7: extract_version finds file directly in DB (no prefix) -> BLOB sha"
else
    fail "Test 7 direct-lookup: got: '$OUTPUT'"
fi
rm -f "$PL"

# Test 8: file not in DB, exists on disk -> mtime (ISO8601)
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo");
if (defined \$obj) {
    my \$tmpfile = "\$repo/untracked.c";
    open(my \$fh, '>', \$tmpfile); print \$fh "x\n"; close \$fh;
    my \$v = \$obj->extract_version(\$tmpfile);
    unlink \$tmpfile;
    print \$v =~ /^\d{4}-\d{2}-\d{2}T/ ? "mtime\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$REPODIR"
if echo "$OUTPUT" | grep -q 'mtime' ; then
    pass "Test 8: file not in DB, exists on disk -> mtime returned"
else
    fail "Test 8 not-in-db-mtime: got: '$OUTPUT'"
fi
rm -f "$PL"

# Test 9: file not in DB, exists on disk, --md5 -> mtime + " md5:<hash>"
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo", "--md5");
if (defined \$obj) {
    my \$tmpfile = "\$repo/untracked2.c";
    open(my \$fh, '>', \$tmpfile); print \$fh "x\n"; close \$fh;
    my \$v = \$obj->extract_version(\$tmpfile);
    unlink \$tmpfile;
    print \$v =~ / md5:/ ? "has_md5\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$REPODIR"
if echo "$OUTPUT" | grep -q 'has_md5' ; then
    pass "Test 9: file not in DB, exists on disk, --md5 -> mtime + md5"
else
    fail "Test 9 not-in-db-md5: got: '$OUTPUT'"
fi
rm -f "$PL"

# Test 10: file not in DB, not on disk, --allow-missing -> empty string
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo", "--allow-missing");
if (defined \$obj) {
    my \$v = \$obj->extract_version("\$repo/nonexistent.c");
    print \$v eq '' ? "empty\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$REPODIR"
if echo "$OUTPUT" | grep -q '^empty$' ; then
    pass "Test 10: file not in DB, missing, --allow-missing -> empty string"
else
    fail "Test 10 allow-missing: got: '$OUTPUT'"
fi
rm -f "$PL"

# Test 11: file not in DB, not on disk, no --allow-missing -> dies
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo");
if (defined \$obj) {
    eval { \$obj->extract_version("\$repo/nonexistent.c"); };
    print \$@ ? "died\n" : "no-die\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$REPODIR"
if echo "$OUTPUT" | grep -q 'died' ; then
    pass "Test 11: file not in DB, missing, no --allow-missing -> dies"
else
    fail "Test 11 missing-die: got: '$OUTPUT'"
fi
rm -f "$PL"

# ===========================================================================
# Test 12: --prepend
# ===========================================================================

# Test 12: --prepend path prepends to all DB keys; lookup via prepend/file
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my (\$repo, \$sha) = @ARGV;
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo", "--prepend=/build/src");
if (defined \$obj) {
    my \$v = \$obj->extract_version("/build/src/foo.c");
    print \$v eq "BLOB \$sha" ? "ok\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$REPODIR" "$FOO_SHA"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 12: --prepend stores keys as prepend/file, lookup via prepend/file"
else
    fail "Test 12 prepend: got: '$OUTPUT'"
fi
rm -f "$PL"

# ===========================================================================
# Test 13: --token override
# ===========================================================================

# Test 13: --token SHA uses SHA instead of BLOB as the token prefix
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my (\$repo, \$sha) = @ARGV;
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo", "--token=SHA");
if (defined \$obj) {
    my \$v = \$obj->extract_version("foo.c");
    print \$v eq "SHA \$sha" ? "ok\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$REPODIR" "$FOO_SHA"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 13: --token SHA changes version prefix from BLOB to SHA"
else
    fail "Test 13 token: got: '$OUTPUT'"
fi
rm -f "$PL"

# ===========================================================================
# Test 14: no --repo uses getcwd()
# ===========================================================================

# Test 14: without --repo, new() falls back to getcwd(); chdir to repo first
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
use Cwd qw(chdir);
my (\$repo, \$sha) = @ARGV;
chdir(\$repo) or die "chdir: \$!";
my \$obj = batchGitVersion->new(\$0);   # no --repo
if (defined \$obj) {
    my \$v = \$obj->extract_version("\$repo/foo.c");
    print \$v eq "BLOB \$sha" ? "ok\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$REPODIR" "$FOO_SHA"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 14: without --repo, new() uses getcwd() as repo root"
else
    fail "Test 14 cwd-fallback: got: '$OUTPUT'"
fi
rm -f "$PL"

# ===========================================================================
# Tests 15-20: compare_version branches
# ===========================================================================

# Test 15: compare_version same BLOB strings -> 0 (false)
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo");
my \$r = \$obj->compare_version("BLOB abc", "BLOB abc", "\$repo/foo.c");
print !defined(\$r) || !\$r ? "ok\n" : "diff=\$r\n";
PLEOF
run_pl "$PL" "$REPODIR"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 15: compare_version same BLOB strings -> 0 (false)"
else
    fail "Test 15 compare-same: got: '$OUTPUT'"
fi
rm -f "$PL"

# Test 16: compare_version different BLOB strings -> 1 (true)
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo");
my \$r = \$obj->compare_version("BLOB abc", "BLOB def", "\$repo/foo.c");
print \$r ? "ok\n" : "same\n";
PLEOF
run_pl "$PL" "$REPODIR"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 16: compare_version different BLOB strings -> 1 (true)"
else
    fail "Test 16 compare-diff: got: '$OUTPUT'"
fi
rm -f "$PL"

# Test 17: compare_version --md5, old has md5 (no BLOB prefix), both same -> 0
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my (\$repo, \$md5) = @ARGV;
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo", "--md5");
my \$ver = "2024-01-01T00:00:00Z md5:\$md5";
my \$r = \$obj->compare_version(\$ver, \$ver, "\$repo/foo.c");
print !defined(\$r) || !\$r ? "ok\n" : "diff=\$r\n";
PLEOF
run_pl "$PL" "$REPODIR" "$MD5_FOO"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 17: compare_version --md5 same md5 -> 0 (match)"
else
    fail "Test 17 md5-same: got: '$OUTPUT'"
fi
rm -f "$PL"

# Test 18: compare_version --md5, old has md5, new has md5, differ -> 1
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my (\$repo, \$md5) = @ARGV;
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo", "--md5");
my \$old = "2024-01-01T00:00:00Z md5:\$md5";
my \$new = "2024-01-01T00:00:00Z md5:different000";
my \$r = \$obj->compare_version(\$new, \$old, "\$repo/foo.c");
print \$r ? "ok\n" : "same\n";
PLEOF
run_pl "$PL" "$REPODIR" "$MD5_FOO"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 18: compare_version --md5 differing md5 -> 1 (mismatch)"
else
    fail "Test 18 md5-diff: got: '$OUTPUT'"
fi
rm -f "$PL"

# Test 19: compare_version --md5, old starts BLOB -> bypass md5 branch, exact match
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo", "--md5");
my \$ver = "BLOB sha123 md5:abc";
my \$r = \$obj->compare_version(\$ver, \$ver, "\$repo/foo.c");
print !defined(\$r) || !\$r ? "ok\n" : "diff=\$r\n";
PLEOF
run_pl "$PL" "$REPODIR"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 19: compare_version --md5 old starts BLOB -> exact match, no md5 branch"
else
    fail "Test 19 blob-bypass-md5: got: '$OUTPUT'"
fi
rm -f "$PL"

# Test 20: compare_version --md5, old has md5 but new has none -> fall through, 1
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my (\$repo, \$md5) = @ARGV;
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo", "--md5");
my \$old = "2024-01-01T00:00:00Z md5:\$md5";
my \$new = "2024-01-01T00:00:00Z_no_md5_here";
my \$r = \$obj->compare_version(\$new, \$old, "\$repo/foo.c");
print \$r ? "ok\n" : "same\n";
PLEOF
run_pl "$PL" "$REPODIR" "$MD5_FOO"
if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 20: compare_version --md5 old has md5 but new does not -> fall through, 1"
else
    fail "Test 20 md5-new-missing: got: '$OUTPUT'"
fi
rm -f "$PL"

# ===========================================================================
# Tests 21-23: verbose output
# ===========================================================================

# Test 21: -v prints extract_version trace (prefix check / match / found)
PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my (\$repo, \$sha) = @ARGV;
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo", "-v");
if (defined \$obj) {
    my \$v = \$obj->extract_version("\$repo/foo.c");
    print \$v eq "BLOB \$sha" ? "ok\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$REPODIR" "$FOO_SHA"
if ! echo "$OUTPUT" | grep -q '^ok$' ; then
    fail "Test 21 verbose: version wrong; got: '$OUTPUT'"
elif ! echo "$OUTPUT" | grep -qF 'check prefix' ; then
    fail "Test 21 verbose: expected 'check prefix' trace in output"
elif ! echo "$OUTPUT" | grep -qF '.. found' ; then
    fail "Test 21 verbose: expected '.. found' trace in output"
else
    pass "Test 21: -v prints extract_version prefix trace"
fi
rm -f "$PL"

# Test 22: -v during new() with submodule prints "enter submodule" / "exit submodule"
MOCKDIR=$(mktemp -d)
cat > "$MOCKDIR/git" << 'ENDGIT'
#!/usr/bin/env bash
if [[ "$*" == *"ls-tree"*"HEAD"* ]] && [[ "$*" != *"submodule"* ]]; then
    echo "100644 blob mainsha main.c"
    echo "160000 commit subsha sub"
    exit 0
elif [[ "$*" == *"submodule"*"foreach"* ]]; then
    echo "Entering 'sub'"
    echo "100644 blob subfilesha file.c"
    echo "done"
    exit 0
fi
ENDGIT
chmod +x "$MOCKDIR/git"
FAKEREPO=$(mktemp -d)
export PATH="$MOCKDIR:$PATH"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo", "-v");
if (defined \$obj) { print "defined\n"; } else { print "undef\n"; }
PLEOF
run_pl "$PL" "$FAKEREPO"
export PATH="${PATH#$MOCKDIR:}"
rm -rf "$MOCKDIR" "$FAKEREPO"
rm -f "$PL"

if echo "$OUTPUT" | grep -qF 'enter submodule sub' && \
   echo "$OUTPUT" | grep -qF 'exit submodule sub' ; then
    pass "Test 22: -v prints 'enter/exit submodule' during new()"
else
    fail "Test 22 verbose-submodule: expected enter/exit in output; got: '$OUTPUT'"
fi

# Test 23: -v countdown truncation: after N files prints " ..."
MOCKDIR=$(mktemp -d)
cat > "$MOCKDIR/git" << 'ENDGIT'
#!/usr/bin/env bash
if [[ "$*" == *"ls-tree"*"HEAD"* ]] && [[ "$*" != *"submodule"* ]]; then
    echo "160000 commit subsha sub"
    exit 0
elif [[ "$*" == *"submodule"*"foreach"* ]]; then
    echo "Entering 'sub'"
    echo "100644 blob sha1 file1.c"
    echo "100644 blob sha2 file2.c"
    echo "100644 blob sha3 file3.c"
    echo "done"
    exit 0
fi
ENDGIT
chmod +x "$MOCKDIR/git"
FAKEREPO=$(mktemp -d)
export PATH="$MOCKDIR:$PATH"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
# verbose=1: number=2, countdown=2*1=2 -> prints 2 files then " ..."
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo", "-v");
if (defined \$obj) { print "defined\n"; } else { print "undef\n"; }
PLEOF
run_pl "$PL" "$FAKEREPO"
export PATH="${PATH#$MOCKDIR:}"
rm -rf "$MOCKDIR" "$FAKEREPO"
rm -f "$PL"

if echo "$OUTPUT" | grep -qF ' ...' ; then
    pass "Test 23: -v countdown truncation prints ' ...' after N stored entries"
else
    fail "Test 23 countdown: expected ' ...' in output; got: '$OUTPUT'"
fi

# ===========================================================================
# Tests 24-26: submodule handling
# ===========================================================================

# Test 24: file in submodule -> DB key is "subname/file" -> "BLOB <sha>"
MOCKDIR=$(mktemp -d)
cat > "$MOCKDIR/git" << 'ENDGIT'
#!/usr/bin/env bash
if [[ "$*" == *"ls-tree"*"HEAD"* ]] && [[ "$*" != *"submodule"* ]]; then
    echo "100644 blob mainsha main.c"
    echo "160000 commit subsha sub"
    exit 0
elif [[ "$*" == *"submodule"*"foreach"* ]]; then
    echo "Entering 'sub'"
    echo "100644 blob subfilesha subfile.c"
    echo "done"
    exit 0
fi
ENDGIT
chmod +x "$MOCKDIR/git"
FAKEREPO=$(mktemp -d)
export PATH="$MOCKDIR:$PATH"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo");
if (defined \$obj) {
    my \$v = \$obj->extract_version("sub/subfile.c");
    print \$v eq "BLOB subfilesha" ? "ok\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$FAKEREPO"
export PATH="${PATH#$MOCKDIR:}"
rm -rf "$MOCKDIR" "$FAKEREPO"
rm -f "$PL"

if echo "$OUTPUT" | grep -q '^ok$' ; then
    pass "Test 24: file in submodule found as 'subname/file' -> BLOB sha"
else
    fail "Test 24 submodule-lookup: got: '$OUTPUT'"
fi

# Test 25: unexpected main ls-tree line -> printed to stderr, obj still built
MOCKDIR=$(mktemp -d)
cat > "$MOCKDIR/git" << 'ENDGIT'
#!/usr/bin/env bash
if [[ "$*" == *"ls-tree"*"HEAD"* ]] && [[ "$*" != *"submodule"* ]]; then
    echo "100644 blob goodsha known.c"
    echo "totally unexpected line format"
    exit 0
elif [[ "$*" == *"submodule"*"foreach"* ]]; then
    exit 0
fi
ENDGIT
chmod +x "$MOCKDIR/git"
FAKEREPO=$(mktemp -d)
export PATH="$MOCKDIR:$PATH"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo");
if (defined \$obj) {
    my \$v = \$obj->extract_version("known.c");
    print \$v eq "BLOB goodsha" ? "ok\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$FAKEREPO"
export PATH="${PATH#$MOCKDIR:}"
rm -rf "$MOCKDIR" "$FAKEREPO"
rm -f "$PL"

if ! echo "$OUTPUT" | grep -qF 'unexpected git ls-tree entry' ; then
    fail "Test 25 unexpected-lstree: expected warning on stderr; got: '$OUTPUT'"
elif ! echo "$OUTPUT" | grep -q '^ok$' ; then
    fail "Test 25 unexpected-lstree: good entry not found; got: '$OUTPUT'"
else
    pass "Test 25: unexpected main ls-tree line -> stderr warning, obj still built"
fi

# Test 26: unexpected submodule foreach line -> stderr warning, obj still built
MOCKDIR=$(mktemp -d)
cat > "$MOCKDIR/git" << 'ENDGIT'
#!/usr/bin/env bash
if [[ "$*" == *"ls-tree"*"HEAD"* ]] && [[ "$*" != *"submodule"* ]]; then
    echo "160000 commit subsha sub"
    exit 0
elif [[ "$*" == *"submodule"*"foreach"* ]]; then
    echo "Entering 'sub'"
    echo "100644 blob goodsha sub/known.c"
    echo "unexpected submodule line"
    echo "done"
    exit 0
fi
ENDGIT
chmod +x "$MOCKDIR/git"
FAKEREPO=$(mktemp -d)
export PATH="$MOCKDIR:$PATH"

PL=$(mktemp --suffix=.pl)
cat > "$PL" << PLEOF
use batchGitVersion;
my \$repo = \$ARGV[0];
my \$obj = batchGitVersion->new(\$0, "--repo=\$repo");
if (defined \$obj) {
    my \$v = \$obj->extract_version("sub/sub/known.c");
    print \$v eq "BLOB goodsha" ? "ok\n" : "got=\$v\n";
} else { print "undef\n"; }
PLEOF
run_pl "$PL" "$FAKEREPO"
export PATH="${PATH#$MOCKDIR:}"
rm -rf "$MOCKDIR" "$FAKEREPO"
rm -f "$PL"

if ! echo "$OUTPUT" | grep -qF 'unexpected git ls-tree entry' ; then
    fail "Test 26 unexpected-submod: expected warning on stderr; got: '$OUTPUT'"
elif ! echo "$OUTPUT" | grep -q '^ok$' ; then
    fail "Test 26 unexpected-submod: good entry not found; got: '$OUTPUT'"
else
    pass "Test 26: unexpected submodule foreach line -> stderr warning, obj still built"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
if [ $FAIL -ne 0 ] ; then
    echo "Tests FAILED"
else
    echo "All batchGitVersion tests passed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover ${COVER_DB}
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB}
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch
fi

[ $FAIL -eq 0 ]
