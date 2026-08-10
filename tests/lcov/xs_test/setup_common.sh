# ============================================================================
# setup_common.sh -- shared preamble for the split XS/pure-Perl equivalence
# tests (xs1.sh .. xs6.sh).
#
# The original monolithic xs_test.sh ran 233 perl fragments, each one twice
# (once XS, once with LCOV_PURE_PERL=1) -- and, under --coverage, each of those
# under Devel::Cover.  That is the entire cost of the test, and it was strictly
# serial.  The fragments share no state, so the file was split into six parts
# of ~39 fragments each which the harness runs in parallel.
#
# This file is *sourced* by each part after it has sourced ../../common.tst.
# It provides:
#     LCOV_HOME_PARENT, LCOVUTIL_PM   -- resolved paths
#     the XS_AVAILABLE preflight       -- 'exit 0' (skip) when XS is not built
#     strip_location                   -- normalizes die-message locations
#     run_test / run_error_test        -- the two fragment drivers
#
# Callers set WORKDIR (e.g. WORKDIR=xs1.d) before sourcing: each part runs in
# its own private directory so the parts cannot collide on the fixed coverage
# output names ('perlcov.info', 'html_report', a relative 'cover_db.dat') that
# generate_coverage writes into the current directory.
#
# Every part must set its own 'status=0' after sourcing this, and call
# generate_coverage with its own test name so the per-part Devel::Cover
# databases stay distinct.
# ============================================================================

if [ -z "$WORKDIR" ] ; then
    echo "setup_common.sh: WORKDIR not set" >&2
    exit 1
fi

# Resolve everything the fragments need to absolute paths BEFORE changing
# directory, then run from the part's own directory.  The fragments themselves
# reference nothing relative, so the directory only has to be unique.
LCOV_HOME_PARENT="$(cd "$LCOV_HOME" && pwd)"
LCOVUTIL_PM="$LCOV_HOME_PARENT/lib/lcovutil.pm"

# SRCDIR == the real test directory; we are sitting in it because common.tst
# did ROOT=`pwd`.
SRCDIR=`pwd`

# A bare '--coverage' leaves COVER_DB (and PYCOV_DB) relative to the invocation
# directory.  Anchor them to SRCDIR so they survive the cd below and so a
# subsequent '--clean' from the test directory finds them.
if [ "x$COVER" != "x" ] ; then
    case "$COVER_DB" in
        /*) ;;
        *)  COVER_DB="$SRCDIR/$COVER_DB"
            export PYCOV_DB="${COVER_DB}_py"
            PERL_COVER_ARGS="-MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine,-silent,1 "
            COVER="perl $PERL_COVER_ARGS"
            ;;
    esac
fi

if [ ! -f "$LCOVUTIL_PM" ] ; then
    echo "Error: cannot find $LCOVUTIL_PM" >&2
    exit 2
fi

# These tests select the backend per fragment - that is what they are for - so
# an inherited LCOV_PURE_PERL is not an instruction to them but an interference:
# it would make the "XS" leg of every comparison pure Perl too, so the parts
# would compare pure Perl with itself, the probe below would report XS as
# unavailable, and xs1..xs6 would silently skip.  'make check' does run the
# whole suite that way (see coverage.sh), so drop it here and let each fragment
# ask for what it wants.
unset LCOV_PURE_PERL

# Check whether the XS library is available; skip (pass) if not.
#
# A part which tests the load machinery itself rather than the classes it
# provides (xs7) has something to check either way, so it sets XS_OPTIONAL=1
# before sourcing and branches on $XS_AVAILABLE itself.
XS_AVAILABLE=$(perl -I"$LCOV_HOME_PARENT/lib" -e '
use lcovutil;
print $lcovutil::XS_LOADED ? "1" : "0";
' 2>/dev/null)
if [ "$XS_AVAILABLE" != "1" ] && [ "1" != "$XS_OPTIONAL" ] ; then
    echo "SKIP: XS library not available on this platform - pure-Perl only"
    exit 0
fi

# Enter the part's private working directory.  Nothing below depends on the
# directory contents; the point is that 'perlcov.info', 'html_report' and a
# relative Devel::Cover database land somewhere unique per part.
rm -rf "$SRCDIR/$WORKDIR"
mkdir -p "$SRCDIR/$WORKDIR"
cd "$SRCDIR/$WORKDIR" || exit 1

# ---- helper to run a perl fragment under both pure-perl and XS ----------------

run_test()
{
    local testname="$1"
    local perl_code="$2"

    local xs_out pure_out xs_rc pure_rc

    # $PERL_COVER_ARGS is empty unless --coverage was requested; when it is set
    # the fragments run under Devel::Cover so the lcovutil.pm lines they
    # exercise show up in this testcase's report.
    xs_out=$(perl $PERL_COVER_ARGS -I"$LCOV_HOME_PARENT/lib" -e "$perl_code" 2>&1)
    xs_rc=$?

    pure_out=$(LCOV_PURE_PERL=1 perl $PERL_COVER_ARGS -I"$LCOV_HOME_PARENT/lib" -e "$perl_code" 2>&1)
    pure_rc=$?

    if [ $xs_rc -ne 0 ] ; then
        echo "FAIL [$testname] XS exit=$xs_rc: $xs_out"
        return 1
    fi
    if [ $pure_rc -ne 0 ] ; then
        echo "FAIL [$testname] PurePerl exit=$pure_rc: $pure_out"
        return 1
    fi
    if [ "$xs_out" != "$pure_out" ] ; then
        echo "FAIL [$testname] outputs differ"
        echo "  XS      : $xs_out"
        echo "  PurePerl: $pure_out"
        return 1
    fi
    return 0
}

# run_xs_only_test NAME CODE
#   Runs CODE under XS only, expecting exit 0.
#
#   Use this ONLY for behaviour that has no pure-Perl counterpart to compare
#   against: the XS layer's defensive argument checks.  A blessed pure-Perl
#   object is an arrayref, so passing something that is not one just produces
#   whatever Perl's own "not an ARRAY reference" / "not a HASH reference" error
#   happens to be; the XS layer instead validates the invocant is a ref whose
#   referent is an IV and croaks with its own message.  There is no equivalence
#   to assert, only that the XS guard fires instead of dereferencing garbage --
#   so these must not go through run_test/run_error_test, which require the two
#   backends to agree.
run_xs_only_test()
{
    local testname="$1"
    local perl_code="$2"

    local out rc
    out=$(perl $PERL_COVER_ARGS -I"$LCOV_HOME_PARENT/lib" -e "$perl_code" 2>&1)
    rc=$?
    if [ $rc -ne 0 ] ; then
        echo "FAIL [$testname] XS exit=$rc: $out"
        return 1
    fi
    return 0
}

# Strip trailing "at <file> line <N>." from die messages so XS and pure-Perl
# source locations don't cause spurious mismatches.
strip_location() { sed 's/ at [^ ]* line [0-9][0-9]*\.//' ; }

# run_error_test NAME CODE
#   Runs CODE expecting non-zero exit in both XS and pure-Perl.
#   Compares stderr messages after stripping "at file line N." suffixes.
#   Use parse_ignore_errors to make ignorable errors non-fatal when you want
#   to check both the warning text AND surviving state in one snippet.
run_error_test()
{
    local testname="$1"
    local perl_code="$2"

    local xs_out pure_out xs_rc pure_rc

    # $PERL_COVER_ARGS is empty unless --coverage was requested; when it is set
    # the fragments run under Devel::Cover so the lcovutil.pm lines they
    # exercise show up in this testcase's report.
    xs_out=$(perl $PERL_COVER_ARGS -I"$LCOV_HOME_PARENT/lib" -e "$perl_code" 2>&1)
    xs_rc=$?

    pure_out=$(LCOV_PURE_PERL=1 perl $PERL_COVER_ARGS -I"$LCOV_HOME_PARENT/lib" -e "$perl_code" 2>&1)
    pure_rc=$?

    if [ $xs_rc -eq 0 ] ; then
        echo "FAIL [$testname] XS: expected non-zero exit, got 0"
        return 1
    fi
    if [ $pure_rc -eq 0 ] ; then
        echo "FAIL [$testname] PurePerl: expected non-zero exit, got 0"
        return 1
    fi
    local xs_clean pure_clean
    xs_clean=$(echo "$xs_out"   | strip_location)
    pure_clean=$(echo "$pure_out" | strip_location)
    if [ "$xs_clean" != "$pure_clean" ] ; then
        echo "FAIL [$testname] messages differ after stripping location"
        echo "  XS      : $xs_clean"
        echo "  PurePerl: $pure_clean"
        return 1
    fi
    return 0
}
