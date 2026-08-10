#!/usr/bin/env bash
# Verify how lcovutil.pm chooses between the C++ XS backend and the pure-Perl
# reference implementation, and that it says which one it got.
#
# xs7 of the split 'xs_test' (see setup_common.sh).  Where xs1..xs6 compare the
# two implementations of the coverage data classes, this part tests the
# *loading* of the extension:
#   - $lcovutil::XS_LOADED and $lcovutil::XS_LOAD_ERROR agree with what was
#     asked for, in both directions
#   - the fallback to pure Perl stays silent (exit 0, nothing on stderr) when
#     the extension cannot be loaded at all, but records the reason
#   - an older C++ runtime ahead of the real one on LD_LIBRARY_PATH does not
#     stop the extension from loading
#
# The last check is what the C++ runtime handling in lib/LcovUtil/Makefile.PL
# buys.  Without it, running under a toolchain older than the one which built the
# extension - 'module load gcc/9' puts gcc/9's lib64 ahead of ours on
# LD_LIBRARY_PATH - makes XSLoader::load fail on a missing GLIBCXX_* version,
# and the silent fallback then turns an unusable extension into nothing more
# visible than a run that is several times slower than it should be.
#
# Run with: make check, or tests/bin/runtests.py lcov/xs_test/xs7.sh

set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf xs7.d
    exit 0
fi

WORKDIR=xs7.d
# this part has something to check whether or not the extension is built
XS_OPTIONAL=1
source ./setup_common.sh

status=0

fail()
{
    echo "$1"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
}

# check_silent FILE MESSAGE
#   Complain unless FILE holds no diagnostics.  Under --coverage the probes run
#   with -MDevel::Cover, which writes its own progress notes ("Deleting old
#   coverage for changed file ...") to stderr:  that is the harness talking, not
#   the code under test, so it does not count against silence.
check_silent()
{
    local noise
    noise=`grep -v '^Devel::Cover:' "$1"`
    if [ -n "$noise" ] ; then
        echo "$noise"
        fail "$2"
    fi
}

# Print "<XS_LOADED>|<XS_LOAD_ERROR>" so one probe can check both, and so an
# unexpected error message ends up in the log verbatim.
PROBE='require lcovutil;
       printf("%d|%s", $lcovutil::XS_LOADED ? 1 : 0, $lcovutil::XS_LOAD_ERROR);'

# --------------------------------------------------------------------------
# XS requested (the default) - expect the extension, and no complaint
# --------------------------------------------------------------------------
if [ "1" == "$XS_AVAILABLE" ] ; then
    OUT=`perl $PERL_COVER_ARGS -I"$LCOV_HOME_PARENT/lib" -e "$PROBE" 2> xs.err`
    RC=$?
    if [ 0 != $RC ] || [ '1|' != "$OUT" ] ; then
        fail "ERROR: expected XS backend and no load error, got rc=$RC '$OUT'"
    fi
    check_silent xs.err "ERROR: unexpected stderr while loading lcovutil.pm"
else
    echo "NOTE: XS extension not built - skipping the XS-requested check"
fi

# --------------------------------------------------------------------------
# pure Perl requested - expect no extension, and still no complaint:  an
# explicit LCOV_PURE_PERL is not a failed load, so there is nothing to report
# --------------------------------------------------------------------------
OUT=`LCOV_PURE_PERL=1 perl $PERL_COVER_ARGS -I"$LCOV_HOME_PARENT/lib" \
        -e "$PROBE" 2> pure.err`
RC=$?
if [ 0 != $RC ] || [ '0|' != "$OUT" ] ; then
    fail "ERROR: expected pure-Perl backend and no load error, got rc=$RC '$OUT'"
fi
check_silent pure.err \
    "ERROR: unexpected stderr while loading lcovutil.pm (LCOV_PURE_PERL)"

# --------------------------------------------------------------------------
# extension not reachable at all - expect a silent fallback which still knows
# why.  lcovutil.pm looks for the extension in 'LcovUtil/blib' beside itself,
# so a copy of it in an empty directory (with nothing else on the include path)
# finds nothing to load.
#
# NOTE: deliberately NOT run under $PERL_COVER_ARGS.  Devel::Cover attributes
# lines to the file they were loaded from, so instrumenting the copy would add
# a second 'lcovutil.pm' - under this test's working directory - to the
# coverage report.  The lines this exercises are the same ones the two probes
# above already cover; what is being checked here is the behaviour.
# --------------------------------------------------------------------------
mkdir -p iso
cp "$LCOVUTIL_PM" iso/lcovutil.pm
# 'unset' in a subshell rather than 'env -u': -u is a GNU extension that not
# every env(1) has.
OUT=`(unset PERL5LIB ; perl -I iso -e "$PROBE") 2> iso.err`
RC=$?
if [ 0 != $RC ] ; then
    cat iso.err
    fail "ERROR: missing XS extension should fall back, not fail (rc=$RC)"
fi
ERR=${OUT#0|}
if [ "0|$ERR" != "$OUT" ] || [ -z "$ERR" ] ; then
    fail "ERROR: expected pure-Perl fallback with a recorded reason, got '$OUT'"
else
    echo "recorded load error: $ERR"
fi
check_silent iso.err "ERROR: fallback to pure Perl should be silent"

# --------------------------------------------------------------------------
# an older C++ runtime earlier on the library search path must not stop the
# extension from loading
#
# This is what the C++ runtime handling in lib/LcovUtil/Makefile.PL buys, and
# the property is checked directly instead of by inspecting the object: build a
# stand-in 'libstdc++.so.6' which exports nothing, put it on LD_LIBRARY_PATH,
# and require that the extension still loads.  An extension linked against the
# C++ runtime with no DT_RPATH binds to the stand-in and fails; one linked with
# -static-libstdc++ ignores it; one with a DT_RPATH finds the real library first
# (DT_RPATH is searched before LD_LIBRARY_PATH, DT_RUNPATH after it - which is
# why Makefile.PL asks for the older tag).  So this accepts either fix and
# rejects an unprotected build, without needing 'readelf' or knowing which fix
# was applied.
#
# The stand-in only has to carry the right soname, so a C compiler is enough;
# skip when there is none, as the other compile-based tests here do.  Note that
# a platform where Makefile.PL could apply neither fix - it warns in that case -
# fails here.  That is deliberate: the resulting build silently runs several
# times slower than it should, and a test which stayed quiet about it would be
# no use.
#
# Not run under $PERL_COVER_ARGS: Devel::Cover writes progress notes to stderr,
# which is folded into the output being matched here, and this exercises the
# same lcovutil.pm lines as the first check above.
# --------------------------------------------------------------------------
CC=${CC:-gcc}
if [ "1" != "$XS_AVAILABLE" ] ; then
    echo "NOTE: XS extension not built - skipping the C++ runtime check"
elif ! type ${CC} >/dev/null 2>&1 ; then
    echo "NOTE: no C compiler (${CC}) - skipping the C++ runtime check"
else
    mkdir -p fakecxx
    echo 'int lcov_nothing(void) { return 0; }' > fakecxx/empty.c
    if ! ${CC} -shared -fPIC fakecxx/empty.c -o fakecxx/libstdc++.so.6 \
              -Wl,-soname,libstdc++.so.6 2> fakecxx/build.err ; then
        cat fakecxx/build.err
        echo "NOTE: cannot build a stand-in libstdc++.so.6 - skipping the C++ runtime check"
    else
        # Strip NULs: when the extension is present but unusable, the recorded
        # reason is a dynamic-loader message, and perl separates the location it
        # appends to such a message from the message itself with a NUL.  Nothing
        # else here can produce one, and leaving it in only makes the shell warn
        # about it while reporting the real failure.
        OUT=`LD_LIBRARY_PATH="$PWD/fakecxx${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
                perl -I"$LCOV_HOME_PARENT/lib" -e "$PROBE" 2>&1 | tr -d '\000'`
        if [ '1|' != "$OUT" ] ; then
            echo "$OUT"
            echo "       the extension did not load with an unrelated 'libstdc++.so.6' ahead of"
            echo "       the real one on LD_LIBRARY_PATH, so it will also fail to load under any"
            echo "       toolchain older than the one which built it - and lcov will fall back to"
            echo "       pure Perl without saying so.  See the C++ runtime handling in"
            echo "       lib/LcovUtil/Makefile.PL."
            fail "ERROR: XS library is not independent of the C++ runtime on LD_LIBRARY_PATH"
        fi
    fi
fi

if [ $status -eq 0 ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'xs_7' $LOCAL_COVERAGE
fi

exit $status
