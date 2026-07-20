# ============================================================================
# setup_common.sh -- shared setup for the split 'simple' genhtml tests.
#
# The original monolithic script.sh was split into part1.sh .. part4.sh so the
# ~48 genhtml invocations (the dominant cost) can run in parallel.  Each part
# runs in its own working directory (partN.d/simple) so the parts cannot
# collide on the fixed output filenames (baseline.info, current.info, ./select,
# ./differential*, ...) or on the shared 'test.cpp' symlink.
#
# This file is *sourced* by each part after it has sourced ../../common.tst.
# It creates and cd's into the part's private working directory, then produces
# the coverage inputs that (nearly) every part consumes:
#     baseline.info[.gz], baseline_orig.info, baseline_name.info,
#     baseline_nobranch.info[.gz], current.info[.gz], current_name.info.gz,
#     diff.txt, diff_r.txt, current_hacked.info, names.data
# plus the option variables and the GENHTML_PORT/LCOV_PORT portability flags.
#
# It performs NO assertions of its own beyond guarding against capture failure:
# the behavioural checks that used to live inline (comment round-trip, version
# mismatch handling, etc.) stay in the individual parts.
#
# Callers set WORKDIR (e.g. WORKDIR=part1.d) before sourcing.
# ============================================================================

if [ -z "$WORKDIR" ] ; then
    echo "setup_common.sh: WORKDIR not set" >&2
    exit 1
fi

# SRCDIR = the real test directory (where the source files and support scripts
# live); we are currently sitting in it because common.tst did ROOT=`pwd`.
SRCDIR=`pwd`

CRITERIA=${SCRIPT_DIR}/criteria
SELECT=${SCRIPT_DIR}/select.pm
HISTORY=${SCRIPT_DIR}/history.pm
UNREACHABLE=${SCRIPT_DIR}/unreach.pm

BASE_OPTS="--branch-coverage $PARALLEL $PROFILE"

# old version of gcc has inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent,category"
fi
if [ "${VER[0]}" -lt 9 ] ; then
    DERIVE='--rc derive_function_end_line=1'
elif [ "${VER[0]}" -ge 14 ] ; then
    ENABLE_MCDC=1
    BASE_OPTS="$BASE_OPTS --mcdc"
    # enable MCDC
    COVERAGE_OPTS="-fcondition-coverage"
fi
LCOV_OPTS="$EXTRA_GCOV_OPTS $BASE_OPTS --version-script $GET_VERSION $MD5_OPT --version-script --allow-missing"

if [ "$COVER" != '' ] ; then
    CAPTURE=$GENINFO_TOOL
else
    CAPTURE="$LCOV_TOOL --capture --directory"
fi

# 'annotation tooltip' override + owner-table popup options used across parts.
POPUP='--rc genhtml_annotate_tooltip=mytooltip'

# --------------------------------------------------------------------------
# Create and enter the private working directory.  It is named '<work>/simple'
# so the source file's parent-directory basename is 'simple', which is what the
# various '.../simple/index.html' path assertions expect.
# --------------------------------------------------------------------------
rm -rf "$SRCDIR/$WORKDIR"
mkdir -p "$SRCDIR/$WORKDIR/simple"
cd "$SRCDIR/$WORKDIR/simple" || exit 1

# Bring in the source and support files the tests reference by relative path.
# The compiled/annotated source files MUST be symlinks back to the real
# p4-controlled files (not copies): the whole test relies on the version-script
# (getp4version) returning the file's p4 revision so the 'VER:#1'->'VER:#2' sed
# hack can make baseline and current look like different versions.  A plain copy
# leaves the p4 workspace, so --allow-missing falls back to a timestamp that is
# identical for baseline and current, and the diff-consistency checks then fail.
ln -s "$SRCDIR/simple.cpp"            simple.cpp
ln -s "$SRCDIR/simple2.cpp"           simple2.cpp
ln -s "$SRCDIR/simple2.cpp.annotated" simple2.cpp.annotated
cp    "$SRCDIR/annotate.pl"           annotate.pl
# unreach.cpp is used only by the unreachable-branch test, which runs with NO
# version script -- so it does not need p4 identity.  It MUST be a real file in
# this working directory (not a symlink out to the p4 tree): genhtml
# canonicalizes the source path before calling the annotate script, and the
# per-test 'unreach.cpp.annotated' we create beside it must resolve next to the
# *canonical* source.  A symlink would push canonicalization back to the p4
# directory, where no matching '.annotated' exists.
cp    "$SRCDIR/unreach.cpp"           unreach.cpp

# ROOT/PARENT must reflect this working directory so that the paths embedded in
# diff.txt (=> $ROOT/test.cpp) match the SF: paths captured into current.info,
# and so --prefix $PARENT strips the right leading component.
ROOT=`pwd`
PARENT=`(cd .. ; pwd)`

DIFFCOV_NOFRAME_OPTS="$BASE_OPTS --demangle-cpp --prefix $PARENT --version-script $GET_VERSION $MD5_OPT --version-script --allow-missing"
DIFFCOV_OPTS="$DIFFCOV_NOFRAME_OPTS --frame"
DIFFCOV_NO_VERSION_OPTS="$BASE_OPTS --demangle-cpp --prefix $PARENT --frame"

setup_die() {
    echo "setup_common: $1" >&2
    exit 1
}

# --------------------------------------------------------------------------
# Baseline capture (from simple.cpp)
#
# NOTE: unlike the original monolithic script (which did 'cp simple.cpp
# test.cpp'), we symlink to the p4-controlled source so the version-script
# records a stable 'VER:#1'.  Both simple.cpp and simple2.cpp are p4 revision
# #1, so whichever source test.cpp points at when a part later runs a report,
# the on-disk version is #1 -- matching baseline_orig.info (#1) exactly.  The
# 'VER:#1'->'VER:#2' sed below then makes the *differential* baseline.info look
# like a different version than current.info (#1), which is what the diff-file
# consistency check requires.  This makes versioning order-independent, so any
# part can run any report without a capture-time/report-time mismatch.
# --------------------------------------------------------------------------
ln -s simple.cpp test.cpp
${CXX} --coverage $COVERAGE_OPTS test.cpp || setup_die "compile baseline failed"
./a.out

if [ "${VER[0]}" -lt 5 ] ; then
    EMPTY_BRANCH="--ignore empty"
fi

$COVER $CAPTURE . $LCOV_OPTS --output-file baseline.info $IGNORE --comment "this is the baseline" --memory 20 $EMPTY_BRANCH || setup_die "capture baseline failed"
cp baseline.info baseline_orig.info
# make the version number look different so the new diff file consistency
#  check will pass
sed -i -E 's/VER:(.+)$/VER:\1a/' baseline.info
gzip -c baseline.info > baseline.info.gz

# newer versions of gcc generate coverage data with full paths to sources in
#  '.' - whereas older versions have relative paths.  Detect and set the extra
#  flags that keep the tests portable across gcc versions.
grep './test.cpp' baseline.info
if [ 0 == $? ] ; then
    GENHTML_PORT='--elide-path-mismatch'
    LCOV_PORT='--substitute s#^[.]/#pwd/# --ignore unused'
fi

$COVER $CAPTURE . $LCOV_OPTS --output-file baseline_name.info --test-name myTest $IGNORE || setup_die "capture baseline_name failed"
sed -i -E 's/VER:(.+)$/VER:\1a/' baseline_name.info

# 'version-mismatched' variant of baseline used by the merge/filter checks
sed -e 's/VER:/VER:x/g' -e 's/ md5:/ md5:0/g' < baseline.info > baseline2.info

$COVER $CAPTURE . $LCOV_OPTS --output-file baseline_nobranch.info $IGNORE --rc memory=1024 || setup_die "capture baseline_nobranch failed"
sed -i -E 's/VER:(.+)$/VER:\1a/' baseline_nobranch.info
gzip -c baseline_nobranch.info > baseline_nobranch.info.gz

# --------------------------------------------------------------------------
# Current capture (from simple2.cpp, with added/removed code)
# --------------------------------------------------------------------------
rm -f test.cpp test.gcno test.gcda a.out
ln -s simple2.cpp test.cpp
${CXX} --coverage $COVERAGE_OPTS -DADD_CODE -DREMOVE_CODE test.cpp || setup_die "compile current failed"
./a.out
$COVER $CAPTURE . $LCOV_OPTS --output-file current.info $IGNORE || setup_die "capture current failed"
gzip -c current.info > current.info.gz

$COVER $CAPTURE . $LCOV_OPTS --output-file current_name.info.gz --test-name myTest $IGNORE || setup_die "capture current_name failed"

# --------------------------------------------------------------------------
# Diff files and derived inputs
# --------------------------------------------------------------------------
diff -u simple.cpp simple2.cpp | sed -e "s|simple2*\.cpp|$ROOT/test.cpp|g" > diff.txt
diff -u simple2.cpp simple.cpp | sed -e "s|simple2*\.cpp|$ROOT/test.cpp|g" > diff_r.txt

# make the version number look different so the new diff file consistency
#  check will pass
sed -E 's/VER:(.+)$/VER:\1a/' current.info > current_hacked.info

# description data used by several parts
cat > names.data <<EOF
TN:myTest
TD:faking some test data
# test empty description
TN:unusedTest
TD:
EOF

# leave test.cpp pointing at the 'current' source, which is what most tests
# expect on entry.
rm -f test.cpp
ln -s simple2.cpp test.cpp
