#!/usr/bin/env bash
#
# Test the 'xs' entry in the profile 'config' section.
#
# lcovutil loads the C++ XS extension when it is present and silently uses the
# pure-Perl implementation when it is not, so a run which is several times
# slower than expected looks no different from a fast one.  Record which
# implementation actually ran, so a profile can be interpreted:  1 for XS, 0 for
# pure Perl.

source ../../common.tst

# $LCOV comes from the test Makefile, so it is unset when this script is run
# standalone (notably ./profile.sh --coverage).  Fall back to the tool in
# $LCOV_HOME, under $COVER so a --coverage run instruments it.
if [ 'x' == "x$LCOV_TOOL" ] ; then
        LCOV_TOOL=${LCOV_HOME}/bin/lcov
fi
if [ 'x' == "x$LCOV" ] ; then
        LCOV="$COVER $LCOV_TOOL"
fi

INFO=profile_in.info

cat >$INFO <<'EOF'
TN:
SF:/dev/null
DA:1,1
DA:2,0
LF:2
LH:1
end_of_record
EOF

# Ask lcovutil which implementation it loads in this build.  Do this the same
# way the tools do - via the library - rather than assuming, since whether the
# extension was built at all depends on how lcov was installed.  This is a bare
# 'perl', not $COVER, so pass $PERL_COVER_ARGS explicitly to keep the load
# instrumented under --coverage;  it is empty otherwise.
# 'LCOV_PURE_PERL=' has to be cleared here for the same reason 'check_xs' clears
# it below:  the answer is what the default run will get, and that run is the one
# with the variable empty.  Inheriting a '1' from the environment - 'make check'
# runs the whole suite that way - would predict 0 for a run which loads XS.
EXPECT=$(LCOV_PURE_PERL= perl $PERL_COVER_ARGS -I"$LCOV_HOME/lib" \
        -e 'require lcovutil; print $lcovutil::XS_LOADED ? 1 : 0' 2>/dev/null)
if [[ "$EXPECT" != 0 && "$EXPECT" != 1 ]] ; then
        echo "Error: could not determine XS state from lcovutil (got '$EXPECT')"
        exit 1
fi
echo "expecting xs=$EXPECT"

# $1: expected value of config.xs, $2: profile file, $3..: extra lcov args.
# Set PURE_PERL=1 in the caller to run lcov with LCOV_PURE_PERL=1;  do not use an
# assignment prefix on the function call, whose scoping differs between bash
# versions, and do not use a subshell, which would swallow the exit below.
function check_xs()
{
        local expect=$1
        local prof=$2
        shift 2

        rm -f "$prof"
        # this minimal input has line data only, so the missing function and
        # branch coverpoints are expected rather than a problem
        LCOV_PURE_PERL=$PURE_PERL \
                $LCOV -a $INFO -o "${prof%.json}.info" --profile "$prof" \
                --ignore-errors empty "$@" > "${prof%.json}.log" 2>&1
        local rc=$?
        if [[ $rc -ne 0 ]] ; then
                echo "Error: lcov failed ($rc) writing $prof"
                cat "${prof%.json}.log"
                [[ $KEEP_GOING != 1 ]] && exit 1
                return
        fi
        if [[ ! -s "$prof" ]] ; then
                echo "Error: no profile written to $prof"
                [[ $KEEP_GOING != 1 ]] && exit 1
                return
        fi
        # The entry must be in the 'config' section, and must be the number 0 or
        # 1 - not a string, and not the empty/undef value a bare boolean would
        # serialize to.
        local got
        got=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
c = d.get("config")
if c is None:
    print("NO-CONFIG-SECTION")
elif "xs" not in c:
    print("NO-XS-ENTRY")
else:
    v = c["xs"]
    print(v if isinstance(v, int) and not isinstance(v, bool) else
          "NOT-AN-INT:%r" % (v,))
' "$prof")
        if [[ "$got" != "$expect" ]] ; then
                echo "Error: $prof: config.xs is '$got', expected '$expect'"
                [[ $KEEP_GOING != 1 ]] && exit 1
                return
        fi
        echo "$prof: config.xs = $got"
}

# whatever this build provides.  An empty LCOV_PURE_PERL is false to lcovutil,
# so this leaves the choice to the build.
PURE_PERL=
check_xs "$EXPECT" prof_default.json

# LCOV_PURE_PERL=1 forces the pure-Perl implementation, so the entry must read 0
# regardless of whether the extension is available.
PURE_PERL=1
check_xs 0 prof_pure.json

echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
        generate_coverage 'profile' $LOCAL_COVERAGE 0
fi

exit 0
