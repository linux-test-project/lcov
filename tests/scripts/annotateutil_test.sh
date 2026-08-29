#!/usr/bin/env bash
#
# Test suite for scripts/annotateutil.pm
#
# annotateutil.pm holds the parts of the '--annotate-script' callbacks which do
# not depend on the revision control tool:  the filesystem fallback for a file
# which is not in the repo, the two 'call_*' entry points the standalone
# callback scripts use, and the annotation cache in AnnotateBase.
#
# The tool-specific callbacks are tested through their own scripts (see
# gitblame_test.sh, p4annotate_test.sh);  these tests drive the shared code
# directly, with a stub subclass in place of a repository, so that a case like
# 'the version of a cached file has changed' is reachable at all.
#
# Tests:
#   1.  not_in_repo: a filename beginning with '>' is a filename, not a mode
#   2.  call_get_version: a file with no version prints an empty line
#   3.  call_annotate: the exit status is the callback's exit code, not its
#       wait status
#   4.  cache: an entry whose version still matches is reused
#   5.  cache: an entry whose version no longer matches is not reused
#   6.  cache: an entry is reused when neither side has a version at all

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

if [ ! -f "$SCRIPT_DIR/annotateutil.pm" ] ; then
    echo "annotateutil.pm not found in '$SCRIPT_DIR'" >&2
    exit 1
fi

# When coverage is active, $COVER is "perl -MDevel::Cover=... " so use it as
# the perl interpreter for the direct .pm invocations below.
PERL="${COVER:-perl}"
LCOV_LIB="$LCOV_HOME/lib"

PASS=0
FAIL=0

pass() { echo "PASS: $1" ; ((PASS++)) ; }
fail() { echo "FAIL: $1" ; ((FAIL++)) ; if [ "$KEEP_GOING" != 1 ] ; then exit 1 ; fi ; }

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# ---------------------------------------------------------------------------
# Stub callbacks:  a version callback whose answer is an environment variable,
# and an annotate callback which reports one line of text from another.  Both
# are read at call time, so a single process can annotate the same file twice
# and see a different repository each time - which is what the cache tests need.
# ---------------------------------------------------------------------------
cat > "$WORKDIR/stubversion.pm" << 'EOF'
package stubversion;

sub new
{
    my $class = shift;
    return bless([], $class);
}

sub extract_version
{
    # 'undef' - no version - when the variable is unset, not the empty string
    return $ENV{STUB_VERSION};
}

sub compare_version
{
    my ($self, $you, $me, $filename) = @_;
    return 0 if !defined($you) && !defined($me);
    return 1 if !defined($you) || !defined($me);
    return $you eq $me ? 0 : 1;
}

1;
EOF

cat > "$WORKDIR/stubannotate.pm" << 'EOF'
package stubannotate;

use annotateutil;
use base 'AnnotateBase';

sub annotate_callback
{
    my ($self, $filename, $version) = @_;
    return [$ENV{STUB_STATUS} || 0,
            [[$ENV{STUB_TEXT}, 'owner', undef, 'when', 'cl']], $version];
}

1;
EOF

# ---------------------------------------------------------------------------
# Helper: run a perl snippet with the stubs and the library on @INC
# ---------------------------------------------------------------------------
run_perl() {
    local script="$1" ; shift
    OUTPUT=$($PERL -I"$LCOV_LIB" -I"$SCRIPT_DIR" -I"$WORKDIR" -e "$script" \
             -- "$@" 2>&1)
    RC=$?
}

# ---------------------------------------------------------------------------
# Test 1: 'not_in_repo' opens the file it was given
#   A 2-argument 'open' reads the mode out of the filename, so a name which
#   begins with '>' opened the file for writing - truncating the source file
#   and annotating nothing.
# ---------------------------------------------------------------------------
GT="$WORKDIR/>odd.c"
printf 'first line\nsecond line\n' > "$GT"
# a relative name, so that the '>' is the first character of the string:  that
#   is where a 2-argument 'open' looks for the mode
run_perl 'use annotateutil;
          chdir($ARGV[0]) or die("chdir $ARGV[0]: $!");
          my @lines;
          annotateutil::not_in_repo($ARGV[1], \@lines);
          print(join("\n", map({ $_->[0] } @lines)), "\n");' "$WORKDIR" '>odd.c'
REMAINS=$(cat "$GT")
rm -f "$GT"
if [ $RC -ne 0 ] ; then
    fail "Test 1 leading-gt: expected exit 0, got $RC; output: $OUTPUT"
elif [ "$OUTPUT" != "first line
second line" ] ; then
    fail "Test 1 leading-gt: expected the file's two lines, got: '$OUTPUT'"
elif [ "$REMAINS" != "first line
second line" ] ; then
    fail "Test 1 leading-gt: the file was opened for writing: '$REMAINS'"
else
    pass "Test 1: a filename beginning with '>' is annotated, not truncated"
fi

# ---------------------------------------------------------------------------
# Test 2: 'call_get_version' with no version to report
#   A file need not have a version - an unversioned file is a normal answer,
#   and the consumer reads it as an empty line.  Printing the undef itself
#   warned about an uninitialized value, on stdout's line.
# ---------------------------------------------------------------------------
unset STUB_VERSION
run_perl 'use annotateutil qw(call_get_version);
          use stubversion;
          call_get_version("stubversion", $ARGV[0]);' "$WORKDIR/stubversion.pm"
if [ $RC -ne 0 ] ; then
    fail "Test 2 undef-version: expected exit 0, got $RC; output: $OUTPUT"
elif [ -n "$OUTPUT" ] ; then
    fail "Test 2 undef-version: expected an empty line, got: '$OUTPUT'"
else
    pass "Test 2: an unversioned file is reported as an empty version"
fi

# ---------------------------------------------------------------------------
# Test 3: 'call_annotate' reports the callback's exit code
#   '$status' is a wait status:  the exit code is in the high byte, and a
#   signal is in the low one.  'exit' keeps only the low 8 bits, so a tool
#   which exited 1 (wait status 256) used to leave the script exiting 0 -
#   reporting success for a failed annotation.
# ---------------------------------------------------------------------------
export STUB_TEXT='some line'
BAD=""
#          wait status : expected exit code
for pair in 0:0 256:1 512:2 2:1 ; do
    STATUS=${pair%%:*}
    EXPECT=${pair##*:}
    STUB_STATUS=$STATUS run_perl \
        'use annotateutil qw(call_annotate);
         use stubannotate;
         call_annotate("stubannotate", "stub", undef, undef, undef, undef,
                       $ARGV[0]);' "$WORKDIR/stubannotate.pm"
    if [ $RC -ne "$EXPECT" ] ; then
        BAD="$BAD status=$STATUS:expected-$EXPECT-got-$RC"
    elif [ "$OUTPUT" != "cl|owner|when|some line" ] ; then
        BAD="$BAD status=$STATUS:output='$OUTPUT'"
    fi
done
if [ -n "$BAD" ] ; then
    fail "Test 3 exit-status:$BAD"
else
    pass "Test 3: call_annotate exits with the callback's exit code"
fi

# ---------------------------------------------------------------------------
# Tests 4-6: the annotation cache
#   Each run annotates the same file twice in one process:  the first call
#   fills the cache, and the second is the one under test.  The stub reports
#   different text the second time, so the answer says which of the two ran -
#   the cache is only correct to reuse if the file is still at the version the
#   entry was stored for.
# ---------------------------------------------------------------------------
CACHE_SCRIPT='use lcovutil;
    use annotateutil;
    use stubversion;
    use stubannotate;
    my ($file, $cache) = @ARGV;
    $lcovutil::versionCallback = stubversion->new();
    my $obj = stubannotate->new("stub", $cache, undef, undef, undef);
    foreach my $text ("first text", "second text") {
        $ENV{STUB_TEXT} = $text;
        # the version cache is per file, and both calls are in one process
        %lcovutil::versionCache = ();
        my $v = $text eq "first text" ? $ENV{VERSION_ONE} : $ENV{VERSION_TWO};
        if (defined($v)) {
            $ENV{STUB_VERSION} = $v;
        } else {
            delete($ENV{STUB_VERSION});
        }
        my ($status, $lines) = $obj->annotate($file);
        print($lines->[0]->[0], "\n");
    }'

run_cache_test() {
    local file="$WORKDIR/cached.c"
    local cache="$WORKDIR/cache_dir"
    rm -rf "$cache"
    printf 'cached line\n' > "$file"
    run_perl "$CACHE_SCRIPT" "$file" "$cache"
}

# ---- Test 4: same version -> the stored annotation is reused
export VERSION_ONE=v1 VERSION_TWO=v1
run_cache_test
if [ $RC -ne 0 ] ; then
    fail "Test 4 cache-hit: expected exit 0, got $RC; output: $OUTPUT"
elif [ "$OUTPUT" != "first text
first text" ] ; then
    fail "Test 4 cache-hit: expected the cached annotation twice, got: '$OUTPUT'"
else
    pass "Test 4: a cache entry whose version still matches is reused"
fi

# ---- Test 5: the version changed -> the annotation is recomputed
export VERSION_ONE=v1 VERSION_TWO=v2
run_cache_test
if [ $RC -ne 0 ] ; then
    fail "Test 5 cache-stale: expected exit 0, got $RC; output: $OUTPUT"
elif [ "$OUTPUT" != "first text
second text" ] ; then
    fail "Test 5 cache-stale: stale annotation reused, got: '$OUTPUT'"
else
    pass "Test 5: a cache entry whose version no longer matches is not reused"
fi

# ---- Test 6: no version on either side -> nothing to compare, reuse it
unset VERSION_ONE VERSION_TWO
run_cache_test
if [ $RC -ne 0 ] ; then
    fail "Test 6 cache-unversioned: expected exit 0, got $RC; output: $OUTPUT"
elif [ "$OUTPUT" != "first text
first text" ] ; then
    fail "Test 6 cache-unversioned: expected the cached annotation twice, got: '$OUTPUT'"
else
    pass "Test 6: a cache entry is reused when neither side has a version"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ] ; then
    echo "Tests FAILED"
else
    echo "All annotateutil tests passed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover ${COVER_DB} > cover.log 2>&1
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB}
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch
fi

[ $FAIL -eq 0 ]
