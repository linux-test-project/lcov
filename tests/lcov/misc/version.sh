#!/usr/bin/env bash
#
# Copyright IBM Corp. 2020
#
# Test lcov --version
#

source ../../common.tst

# $LCOV comes from the test Makefile, so it is unset when this script is run
# standalone (notably ./version.sh --coverage).  Fall back to the tool in
# $LCOV_HOME, under $COVER so a --coverage run instruments it.
if [ 'x' == "x$LCOV_TOOL" ] ; then
        LCOV_TOOL=${LCOV_HOME}/bin/lcov
fi
if [ 'x' == "x$LCOV" ] ; then
        LCOV="$COVER $LCOV_TOOL"
fi

STDOUT=version_stdout.log
STDERR=version_stderr.log

$LCOV --version 2> >(grep -v Devel::Cover: > ${STDERR}) >${STDOUT}
RC=$?
cat "${STDOUT}" "${STDERR}"

# Exit code must be zero
if [[ $RC -ne 0 && $KEEP_GOING != 1 ]] ; then
        echo "Error: Non-zero lcov exit code $RC"
        exit 1
fi

# There must be output on stdout
if [[ ! -s "${STDOUT}" ]] ; then
        echo "Error: Missing output on standard output"
        exit 1
fi

# There must not be any output on stderr
if [[ -s "${STDERR}" && $COVER == '' ]] ; then
        echo "Error: Unexpected output on standard error"
        exit 1
fi

# lcovutil.pm finds get_version.sh via $tool_dir, which is the directory of the
# tool that loaded it.  That is bin/ for the tools above, but not when lcovutil
# is loaded as a plain library - by a diagnostic one-liner, or by
# lib/LcovUtil/Makefile.PL when it derives the error ids.  In that case
# $tool_dir is the caller's directory, so the module has to look beside its own
# file as well.  Check that the version still resolves and that nothing is
# written to stderr:  getting this wrong left $VERSION empty and printed
# 'get_version.sh: No such file or directory' on every build.

LIBDIR="$LCOV_HOME/lib"
LIBOUT=version_lib_stdout.log
LIBERR=version_lib_stderr.log

# For 'perl -e', $FindBin::RealBin is the current directory, so the check is only
# meaningful if get_version.sh is not sitting here.  Assert that rather than
# chdir'ing away:  $PERL_COVER_ARGS names the Devel::Cover db by a relative path,
# which a chdir would break.  $PERL_COVER_ARGS keeps the load instrumented under
# --coverage and is empty otherwise;  this is a bare 'perl' rather than $COVER
# because the -I has to be ours.
if [ -e ./get_version.sh ] ; then
        echo "Error: unexpected get_version.sh in the test directory"
        exit 1
fi
perl $PERL_COVER_ARGS -I"$LIBDIR" \
        -e 'require lcovutil; print "$lcovutil::VERSION\n"' \
        2> >(grep -v Devel::Cover: > ${LIBERR}) >${LIBOUT}
RC=$?
cat "${LIBOUT}" "${LIBERR}"

if [[ $RC -ne 0 ]] ; then
        echo "Error: loading lcovutil.pm as a library failed ($RC)"
        [[ $KEEP_GOING != 1 ]] && exit 1
fi

# The version reported when loaded as a library must match what the tool
# reports - not merely be non-empty.
TOOL_VERSION=$(grep -o 'LCOV version .*' "${STDOUT}" | sed -e 's/LCOV version //')
LIB_VERSION=$(cat "${LIBOUT}")
if [[ -z "$LIB_VERSION" ]] ; then
        echo "Error: lcovutil.pm reported an empty version when used as a library"
        [[ $KEEP_GOING != 1 ]] && exit 1
elif [[ "$LIB_VERSION" != "$TOOL_VERSION" ]] ; then
        echo "Error: version mismatch: tool '$TOOL_VERSION' vs library '$LIB_VERSION'"
        [[ $KEEP_GOING != 1 ]] && exit 1
fi

if [[ -s "${LIBERR}" && $COVER == '' ]] ; then
        echo "Error: unexpected stderr when loading lcovutil.pm as a library:"
        cat "${LIBERR}"
        [[ $KEEP_GOING != 1 ]] && exit 1
fi

# When neither candidate directory holds the script, the version is simply
# unknown:  report it as empty, and still say nothing on stderr.  This is what an
# incomplete install looks like, so provoke it with a copy of lcovutil.pm that
# has no bin/ beside it.
NOBINDIR=nobin.d
NOBINERR=version_nobin_stderr.log
rm -rf $NOBINDIR
mkdir -p $NOBINDIR/lib
cp "$LIBDIR"/lcovutil.pm $NOBINDIR/lib/
perl $PERL_COVER_ARGS -I"$NOBINDIR/lib" \
        -e 'require lcovutil; print "[$lcovutil::VERSION]\n"' \
        2> >(grep -v Devel::Cover: > ${NOBINERR}) >version_nobin_stdout.log
RC=$?
cat version_nobin_stdout.log "${NOBINERR}"

if [[ $RC -ne 0 ]] ; then
        echo "Error: loading lcovutil.pm without a bin/ directory failed ($RC)"
        [[ $KEEP_GOING != 1 ]] && exit 1
fi
if [[ "$(cat version_nobin_stdout.log)" != '[]' ]] ; then
        echo "Error: expected an empty version with no get_version.sh, got:"
        cat version_nobin_stdout.log
        [[ $KEEP_GOING != 1 ]] && exit 1
fi
if [[ -s "${NOBINERR}" && $COVER == '' ]] ; then
        echo "Error: unexpected stderr with no get_version.sh:"
        cat "${NOBINERR}"
        [[ $KEEP_GOING != 1 ]] && exit 1
fi
# leave $NOBINDIR in place ('make clean' removes it):  under --coverage,
# Devel::Cover needs the source file to still exist when the report is generated.

# Same check for the real second caller:  Makefile.PL loads lcovutil.pm to
# derive the error ids, and must not emit the missing-script message either.
# Run it in a scratch copy so we do not perturb the built extension's Makefile.
if [ -f "$LCOV_HOME/lib/LcovUtil/Makefile.PL" ] ; then
        PLERR=version_makefilepl_stderr.log
        rm -rf mpl.d
        mkdir -p mpl.d/lib/LcovUtil
        cp "$LCOV_HOME"/lib/lcovutil.pm mpl.d/lib/
        cp "$LCOV_HOME"/lib/LcovUtil/* mpl.d/lib/LcovUtil/ 2>/dev/null
        mkdir -p mpl.d/bin
        cp "$LCOV_HOME"/bin/get_version.sh mpl.d/bin/
        # deliberately NOT under $PERL_COVER_ARGS:  instrumenting Makefile.PL
        # puts an entry in the Devel::Cover db that perl2lcov rejects with
        # 'unable to process Makefile.PL without statement data'.  The lcovutil
        # load this triggers is already covered by the probes above;  what is
        # being checked here is only what Makefile.PL writes to stderr.
        ( cd mpl.d/lib/LcovUtil && perl Makefile.PL ) >/dev/null 2>"${PLERR}"
        if grep -q 'get_version.sh' "${PLERR}" ; then
                echo "Error: Makefile.PL reported a missing get_version.sh:"
                cat "${PLERR}"
                [[ $KEEP_GOING != 1 ]] && exit 1
        fi
        # leave mpl.d in place for the same reason as $NOBINDIR above
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
        generate_coverage 'version' $LOCAL_COVERAGE 0
fi

exit 0
