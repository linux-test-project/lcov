#!/bin/bash
set +x

: ${USER:="$(id -u -n)"}

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    if [ -d part2.d ] ; then
        chmod -R u+rwx part2.d 2>/dev/null
        rm -rf part2.d
    fi
    exit 0
fi

# Shared setup: create part2.d, symlink sources, compile extract.cpp.
WORKDIR=part2.d
source ./setup_common.sh

# ---------------------------------------------------------------------------
# Prelude: reproduce the coverage inputs this part consumes.  Part 2 needs a
# runtime .gcda (so run a.out), plus 'external.info' (used by the GCOV_PREFIX
# diff and the missing-file filter) and 'internal.info' (used to compute the
# baseline DA count for the --no-markers check).
# ---------------------------------------------------------------------------
${CC} -c --coverage $COMPILE_OPTS unused.c
if [ 0 != $? ] ; then
    echo "Error:  unexpected error from gcc"
    if [ $KEEP_GOING == 0 ] ; then
	exit 1
    fi
fi

./a.out 1
if [ 0 != $? ] ; then
    echo "Error:  unexpected error return from a.out"
    exit 1
fi

# 'external.info' - vanilla capture (same recipe as part1)
$COVER $CAPTURE . $LCOV_OPTS -o external.info $FILTER $IGNORE --profile --history ./history.sh $EMPTY_BRANCH
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --capture (external)"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# 'internal.info' - no-external capture with the excl markers active
$COVER $CAPTURE . $LCOV_OPTS --no-external -o internal.info --rc lcov_excl_start=LCOV_EXCL_START_1 --rc lcov_excl_stop=LCOV_EXCL_STOP_1
if [ 0 != $? ] ; then
    echo "Error:  unexpected error from capture-internal"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# ===========================================================================
# Part 2: config-file RC options, --no-markers / region-overlap detection,
#         --omit-lines, checksum, 'unreachable' implementation, separate
#         build-dir / GCOV_PREFIX, missing-file filters, errs dir, spaces.
# (Corresponds to ~L469-1198 of the original monolithic extract.sh.)
# ===========================================================================

# test some config file options

# error message for missing env var in RC file
$COVER $LCOV_TOOL $IGNORE --capture -d . $LCOV_OPTS -o err1.info --config-file envVar.rc 2>&1 | tee err1.log
if [ ${PIPESTATUS[0]} == 0 ] ; then
    echo "expected 'ERROR_USAGE' - did not find"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# skip ignore error
$COVER $LCOV_TOOL $IGNORE --capture -d . $LCOV_OPTS -o ignore1.info --config-file envVar.rc --ignore usage
if [ 0 != $? ] ; then
    echo "expected to ignore 'ERROR_USAGE'"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

export ENV_IGNORE='empty'
# error message for missing env var in RC file
$COVER $LCOV_TOOL $IGNORE --capture -d . $LCOV_OPTS -o setVar.info --config-file envVar.rc
if [ 0 != $? ] ; then
    echo "expected to set var from env - but didn't"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# error message for missing env var in RC file
$COVER $LCOV_TOOL $IGNORE --capture -d . $LCOV_OPTS -o err2.info --config-file envErr.rc  2>&1 | tee err2.log
if [ ${PIPESTATUS[0]} == 0 ] ; then
    echo "expected missing value error - not found"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# ignore the error
$COVER $LCOV_TOOL $IGNORE --capture -d . $LCOV_OPTS -o ignore2.info --config-file envErr.rc --ignore format
if [ 0 != $? ] ; then
    echo "expected to ignore error - but didn't"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


# syntax error in 'geninfo_chunk_size'
$COVER $CAPTURE . $LCOV_OPTS --no-external -o rcOptBug $PARALLEL $PROFILE --rc "geninfo_chunk_size=a" --ignore unused 2>&1 | tee chunkErr.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  extract with RC chunk error didn't fail"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E "geninfo_chunk_size .+ is not recognized" chunkErr.log
if [ 0 != $? ] ; then
    echo "Error:  missing RC chunk message"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi



# workaround:  depending on compiler version, we see a coverpoint on the
#  close brace line (gcc/6 for example) or we don't (gcc/10 for example)
BRACE_LINE='^DA:36'
MARKER_LINES=`grep -v $BRACE_LINE internal.info | grep -c "^DA:"`

# check 'no-markers':  is the excluded line back?
$COVER $CAPTURE . $LCOV_OPTS --no-external -o nomarkers.info --no-markers
if [ $? != 0 ] ; then
    echo "error return from extract no-markers"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
NOMARKER_LINES=`grep -v $BRACE_LINE nomarkers.info | grep -c "^DA:"`
NOMARKER_BRANCHES=`grep -c "^BRDA:" nomarkers.info`
if [ $NOMARKER_LINES != '13' ] ; then
    echo "did not honor --no-markers expected 13 found $NOMARKER_LINES"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# check overlap detection for both exclude and unreachable attributes
for attrib in "excl" "unreachable" ; do
    # override excl region start/stop and look for error
    $COVER $CAPTURE . $LCOV_OPTS --no-external -o regionErr1.info --rc lcov_${attrib}_start=TEST_OVERLAP_START --rc lcov_${attrib}_stop=TEST_OVERLAP_END --msg-log
    if [ $? == 0 ] ; then
        echo "error expected overlap $attrib fail"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    grep -E 'overlapping exclude directives. Found TEST_OVERLAP_START at .+ but no matching TEST_OVERLAP_END for TEST_OVERLAP_START at line ' regionErr1.msg
    if [ 0 != $? ] ; then
        echo "error expected overlap message but didn't find"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    $COVER $CAPTURE . $LCOV_OPTS --no-external -o regionErr2.info --rc lcov_${attrib}_start=TEST_DANGLING_START --rc lcov_${attrib}_stop=TEST_DANGLING_END --msg-log
    if [ $? == 0 ] ; then
        echo "error expected dangling fail"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    grep -E 'unmatched TEST_DANGLING_START at line .+ saw EOF while looking for matching TEST_DANGLING_END' regionErr2.msg
    if [ 0 != $? ] ; then
        echo "error expected dangling message but didn't find"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    $COVER $CAPTURE . $LCOV_OPTS --no-external -o regionErr3.info --rc lcov_${attrib}_start=TEST_UNMATCHED_START --rc lcov_${attrib}_stop=TEST_UNMATCHED_END --msg-log
    if [ $? == 0 ] ; then
        echo "error expected unmatched fail"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    grep -E 'found TEST_UNMATCHED_END directive at line .+ without matching TEST_UNMATCHED_START' regionErr3.msg
    if [ 0 != $? ] ; then
        echo "error expected unmapted message but didn't find"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    # override excl_line start/stop - and make sure we didn't match
    $COVER $CAPTURE . $LCOV_OPTS --no-external -o ${attrib}.info --rc lcov_${attrib}_start=nomatch_start --rc lcov_${attrib}_stop=nomatch_end
    if [ $? != 0 ] ; then
        echo "error return from marker override"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    EXCL_LINES=`grep -v $BRACE_LINE ${attrib}.info | grep -c "^DA:"`
    if [ $EXCL_LINES != $NOMARKER_LINES ] ; then
        echo "did not honor marker override: expected $NOMARKER_LINES found $EXCL_LINES"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

# override excl_br line start/stop - and make sure we match match
$COVER $CAPTURE . $LCOV_OPTS --no-external -o exclbr.info --rc lcov_excl_br_start=TEST_BRANCH_START --rc lcov_excl_br_stop=TEST_BRANCH_STOP
if [ $? != 0 ] ; then
    echo "error return from branch marker override"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
EXCL_BRANCHES=`grep -c "^BRDA:" exclbr.info`

if [ $EXCL_BRANCHES -ge $NOMARKER_BRANCHES ] ; then
    echo "did not honor br marker override: expected $NOMARKER_BRANCHES to be larger than $EXCL_BRANCHES"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# override excl_br line start/stop - and make sure we match match
$COVER $CAPTURE . $LCOV_OPTS --no-external -o exclbrline.info --rc lcov_excl_br_line=TEST_BRANCH_LINE
if [ $? != 0 ] ; then
    echo "error return from branch line marker override"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
EXCL_LINE_BRANCHES=`grep -c "^BRDA:" exclbrline.info`

if [ $EXCL_LINE_BRANCHES != $EXCL_BRANCHES ] ; then
    echo "did not honor br line marker override: expected $EXCL_BRANCHES found $EXCL_LINE_BRANCHES"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# check to see if "--omit-lines" works properly...
$COVER $CAPTURE . $LCOV_OPTS --no-external --omit-lines '\s+std::string str.+' -o omit.info --rc lcov_excl_start=LCOV_EXCL_START_1 --rc lcov_excl_stop=LCOV_EXCL_STOP_1 2>&1 | tee omitLines.log

if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error code from lcov --omit"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

BRACE_LINE="DA:36"
# a bit of a hack:  gcc/10 doesn't put a DA entry on the closing brace
COUNT=`grep -v $BRACE_LINE omit.info | grep -c ^DA:`
if [ $COUNT != '11' ] ; then
    echo "expected 11 DA entries in 'omit.info' - found $COUNT"
    exit 1
fi

# check to see if "--omit-lines" works fails if no match
$COVER $CAPTURE . $LCOV_OPTS --no-external --omit-lines 'xyz\s+std::string str.+' -o omitErr.info

if [ 0 == $? ] ; then
    echo "Error:  did not see expected error code from lcov --omit"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $CAPTURE . $LCOV_OPTS --no-external --omit-lines 'xyz\s+std::string str.+' -o omitWarn.info --ignore unused --rc lcov_excl_start=LCOV_EXCL_START_1 --rc lcov_excl_stop=LCOV_EXCL_STOP_1

if [ 0 != $? ] ; then
    echo "Error:  unexpected expected error code from lcov --omit --ignore.."
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
COUNT=`grep -v $BRACE_LINE omitWarn.info | grep -c ^DA:`
if [ $COUNT != '12' ] ; then
    echo "expected 12 DA entries in 'omitWarn.info' - found $COUNT"
    exit 1
fi

# try again, with rc file instead
echo "omit_lines = ^std::string str.+\$" > testRC # no space at start ofline
echo "omit_lines = ^\\s+std::string str.+\$" >> testRC
#should fail due to no match...
$COVER $CAPTURE . $LCOV_OPTS --no-external --config-file testRC -o rc_omitErr.info

if [ 0 == $? ] ; then
    echo "Error:  did not see expected error code from lcov --config with bad omit"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
echo "ignore_errors = unused" >> testRC
echo "ignore_errors = empty" >> testRC

$COVER $CAPTURE . $LCOV_OPTS --no-external --config-file testRC -o rc_omitWarn.info --rc lcov_excl_start=LCOV_EXCL_START_1 --rc lcov_excl_stop=LCOV_EXCL_STOP_1

if [ 0 != $? ] ; then
    echo "Error:  saw unexpected error code from lcov --config with ignored bad omit"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
COUNT=`grep -v $BRACE_LINE  rc_omitWarn.info | grep -c ^DA:`
if [ $COUNT != '11' ] ; then
    echo "expected 11 DA entries in 'rc_omitWarn.info' - found $COUNT"
    exit 1
fi

# test with checksum..
$COVER $CAPTURE . $LCOV_OPTS --no-external -o checksum.info --checksum
if [ $? != 0 ] ; then
    echo "capture with checksum failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# read file with matching checksum...
$COVER $LCOV_TOOL $LCOV_OPTS --summary checksum.info --checksum
if [ $? != 0 ] ; then
    echo "summary with checksum failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
#munge the checksum in the output file
perl -i -pe 's/DA:6,1.+/DA:6,1,abcde/g' < checksum.info > mismatch.info
$COVER $LCOV_TOOL $LCOV_OPTS --summary mismatch.info --checksum
if [ $? == 0 ] ; then
    echo "summary with mismatched checksum expected to fail"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

perl -i -pe 's/DA:6,1.+/DA:6,1/g' < checksum.info > missing.info
$COVER $LCOV_TOOL $LCOV_OPTS --summary missing.info --checksum
if [ $? == 0 ] ; then
    echo "summary with missing checksum expected to fail"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# some tests for 'unreachable' implementation
$COVER $CAPTURE . $LCOV_OPTS --no-external -o unreachable.info --rc lcov_unreachable_start=LCOV_EXCL_START_1 --rc lcov_unreachable_stop=LCOV_EXCL_STOP_1 2>&1 | tee unreachableErr1.txt
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error from capture-internal"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep -E "\(unreachable\) .+ BRDA record in 'unreachable' region has non-zero hit count" unreachableErr1.txt
if [ 0 != $? ] ; then
    echo "Error:  didn't find expected unreachable DA record"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# exclude branch coverage and run again - to get to unreachable line error
NOBRANCH_OPT=${LCOV_OPTS/--branch-coverage}
$COVER $CAPTURE . $NOBRANCH_OPT --no-external -o unreachable.info --rc lcov_unreachable_start=LCOV_EXCL_START_1 --rc lcov_unreachable_stop=LCOV_EXCL_STOP_1 2>&1 | tee unreachableErr2.txt
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error from capture-internal"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep -E "\(unreachable\) .+ 'unreachable' line has non-zero hit count" unreachableErr2.txt
if [ 0 != $? ] ; then
    echo "Error:  didn't find expected unreachable DA record"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $CAPTURE . $LCOV_OPTS --no-external -o unreachable.info --rc lcov_unreachable_start=LCOV_EXCL_START_1 --rc lcov_unreachable_stop=LCOV_EXCL_STOP_1 --ignore unreachable 2>&1 | tee unreachableWarn1.txt
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error from capture-internal"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

COUNT=`grep -c -E "\(unreachable\) .+ 'unreachable' .+ has non-zero hit count" unreachableWarn1.txt`
if [ $COUNT != 2 ] ; then
    echo "Error:  didn't find expected 'unreachable warnings"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $CAPTURE . $LCOV_OPTS --no-external -o exclLine.info --rc lcov_excl_line=TEST_UNREACHABLE_LINE
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error from exclude line"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep DA:30 exclLine.info
if [ 0 == $? ] ; then
    echo "Error:  line exclusion didn't exclude"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


$COVER $CAPTURE . $LCOV_OPTS --no-external -o unreachLine.info --rc lcov_unreachable_line=TEST_UNREACHABLE_LINE --ignore unreachable
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error from unreachable_line"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep DA:30 unreachLine.info
if [ 0 != $? ] ; then
    echo "Error:  unreached line dropped by default"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -a unreachLine.info  --rc lcov_unreachable_line=TEST_UNREACHABLE_LINE --filter region --ignore unreachable --rc retain_unreachable_coverpoints_if_executed=0 -o removeUnreach.info
if [ 0 != $? ] ; then
    echo "Error:  lcov unreached failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep DA:30 removeUnreach.info
if [ 0 == $? ] ; then
    echo "Error:  unreached line not removed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $CAPTURE . $LCOV_OPTS --no-external -o unreachable.info --rc lcov_unreachable_line=TEST_UNREACH_FUNCTION 2>&1 | tee unreachableErr3.txt
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error from unreach function"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep -E '\(unreachable\) .+ function main is executed but was marked unreachable' unreachableErr3.txt
if [ 0 != $? ] ; then
    echo "Error:  didn't find expected unreachable function record"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E "\(unreachable\) .+ 'unreachable' line has non-zero hit count" unreachableErr3.txt
if [ 0 == $? ] ; then
    echo "Error:  found unexpected unreachable DA record (should have stopped at function)"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

if [ "${VER[0]}" -lt 9 ] ; then
    # explicitly remove the '..static_initialization_and_destruction...'
    #   function which appears with old compilers -
    # otherwise, the "function coveage enabled but no corresponding..."
    #   fails because that function appears in the data
    IGNORE_STATIC="--erase-function .*static.*"
fi

$COVER $LCOV_TOOL $LCOV_OPTS -a unreachLine.info  --rc lcov_unreachable_line=TEST_UNREACH_FUNCTION --filter region --ignore unreachable --rc retain_unreachable_coverpoints_if_executed=0 -o removeUnreachFunc.info --ignore empty $IGNORE_STATIC 2>&1 | tee unreachFunc.txt
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  lcov unreached failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E '\(unreachable\) .+ function main is executed but was marked unreachable' unreachFunc.txt
if [ 0 != $? ] ; then
    echo "Error:  expected unreached function message"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E "\(unreachable\) .+ 'unreachable' line has non-zero hit count" unreachFunc.txt
if [ 0 != $? ] ; then
    echo "Error:  didn't find expected unreachable DA warning"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E "\(empty\).+function coverage enabled but no corresponding coverpoints found." unreachFunc.txt
if [ 0 != $? ] ; then
    echo "Error:  didn't find expected empty function"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep FNA:0,1,main removeUnreachFunc.info
if [ 0 == $? ] ; then
    echo "Error:  expected function record to be removed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# check case when build dir and GCOV_PREFIX directory are not the same -
#  so .gcno and .gcda files are in different places
export DEPTH=0
BASE=`pwd`
while [ $BASE != '/' ] ; do
  echo $BASE
  BASE=`dirname $BASE`
  let DEPTH=$DEPTH+1
done
echo "found depth $DEPTH"
let STRIP=$DEPTH+2

mkdir -p separate/build
mkdir -p separate/run
mkdir -p separate/copy
( cd separate/build ; ${CXX} -std=c++1y $COMPILE_OPTS ../../extract.cpp )
cp separate/build/*.gcno separate/copy
# make unwritable - so we don't allow lcov to write temporaries
#  this emulates what happens when the build job is owned by one user,
#  the test job by another, and a third person is trying to create coverage reports
chmod ugo-w separate/build
chmod ugo-w separate/copy
if [ 0 != $? ] ; then
    echo "Error:  no .gcno files to copy"
    exit 1
fi

( cd separate/run ; GCOV_PREFIX=my/test GCOV_PREFIX_STRIP=$STRIP ../build/a.out 1 )
if [ 0 != $? ] ; then
    echo "Error:  execution failed"
    exit 1
fi
mkdir separate/run/my/test/no_read
chmod ugo-w separate/run
$COVER $CAPTURE separate/run/my/test $LCOV_OPTS --build-directory separate/build  -o separate.info $FILTER $IGNORE
if [ 0 != $? ] ; then
    echo "Error:  extract failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
$COVER $CAPTURE separate/run/my/test $LCOV_OPTS --build-directory separate/copy  -o copy.info $FILTER $IGNORE
if [ 0 != $? ] ; then
    echo "Error:  extract from copy failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# use --resolve-script instead - simply echo the right value of the gcno file
$COVER $CAPTURE  separate/run/my/test $LCOV_OPTS --resolve-script ./fakeResolve.sh --resolve-script separate/copy/*extract.gcno -o resolve.info $FILTER $IGNORE
if [ 0 != $? ] ; then
    echo "Error:  extract with resolve-script failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# captured data from GCOV_PREFIX result should be identical to vanilla build
for d in separate.info copy.info resolve.info ; do
    diff external.info $d
    if [ $? != 0 ] ; then
        echo "Error: unexpected GCOV_PREFIX result '$d'"
        exit 1
    fi
done


# trigger an error from an unreadable directory..
chmod ugo-rx separate/run/my/test/no_read
$COVER $CAPTURE separate/run/my/test $LCOV_OPTS --build-directory separate/copy -o unreadable.info $FILTER $IGNORE 2>&1 | tee err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected fail from unreadable dir"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep "error in 'find" err.log
if [ 0 != $? ] ; then
    echo "expected error not found"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $CAPTURE separate/run/my/test $LCOV_OPTS --build-directory separate/copy -o unreadable.info $FILTER $IGNORE --ignore utility 2>&1 | tee warn.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  extract from unreadable failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep "error in 'find" warn.log
if [ 0 != $? ] ; then
    echo "expected warning not found"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

chmod -R ug+rxw separate

if [ "${VER[0]}" -lt 9 ] ; then
    IGNORE_NO_FUNC="--ignore empty"
fi
# try filtering missing files
sed -e s/extract.cpp/notfound.cpp/ external.info > missing_file.info
$COVER $LCOV_TOOL $LCOV_OPTS -o removeMissing.info -a missing_file.info --filter missing $DERIVE_END $IGNORE_NO_FUNC
if [ 0 != $? ] ; then
    echo "filter missing failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E 'SF:.*notfound.cpp' removeMissing.info
if [ 0 == $? ] ; then
    echo "expected to remove missing file"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -o removeMissing_cb.info -a missing_file.info --filter missing --resolve-script brokenCallback.pm,live,missing $DERIVE_END $IGNORE_NO_FUNC
if [ 0 != $? ] ; then
    echo "filter missing callback failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E 'SF:.*notfound.cpp' removeMissing_cb.info
if [ 0 == $? ] ; then
    echo "expected to remove missing file"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -o removeMissing_cb2.info -a missing_file.info --filter missing --resolve-script brokenCallback.pm,live,present --ignore source $DERIVE_END $IGNORE_NO_FUNC
if [ 0 != $? ] ; then
    echo "filter missing callback failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E 'SF:.*notfound.cpp' removeMissing_cb2.info
if [ 0 != $? ] ; then
    echo "expected to keep file"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -o removeMissing_cb3.info -a missing_file.info --filter missing --resolve-script brokenCallback.pm,die --ignore callback $DERIVE_END $IGNORE_NO_FUNC 2>&1 | tee removeMissing.log
if [ ${PIPESTATUS[0]} != 0 ] ; then
    echo "filter missing callback failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E 'SF:.*notfound.cpp' removeMissing_cb3.info
if [ 0 == $? ] ; then
    echo "expected to remove file"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E 'resolve.*failed' removeMissing.log
if [ 0 != $? ] ; then
    echo "expected to find messages"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# try to produce some errors that were hit by user :-(
mkdir -p errs
rm -f errs/*
( cd errs ; ln -s ../*extract.gcda ; ln -s ../missing.gcno *extract.gcno )
$COVER $CAPTURE errs $LCOV_OPTS -o err1.info $FILTER $IGNORE --msg-log
if [ 0 == $? ] ; then
    echo "Error:  expected error code from lcov --capture"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep ERROR: err1.msg
if [ 0 != $? ] ; then
    echo "Error:  expected error message not found"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $CAPTURE errs $LCOV_OPTS -o err2.info $FILTER $IGNORE --initial --msg-log
if [ 0 == $? ] ; then
    echo "Error:  expected error code from lcov --capture --initial"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep ERROR: err2.msg
if [ 0 != $? ] ; then
    echo "Error:  expected error message 2 not found"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $CAPTURE errs $LCOV_OPTS -o err3.info $FILTER $IGNORE --initial --ignore path --msg-log err.3.msg
if [ 0 == $? ] ; then
    echo "Error:  expected error code from lcov --capture --initial --ignore"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep ERROR: err.3.msg
if [ 0 != $? ] ; then
    echo "Error:  expected error message 3 not found"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $CAPTURE errs $LCOV_OPTS -o err4.info $FILTER $IGNORE --initial --keep-going --msg-log
if [ 0 == $? ] ; then
    echo "Error:  expected error code from lcov --capture --initial --keep-going"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# test filename containing spaces
rm -rf ./mytest
mkdir -pv ./mytest
echo "int main(){}" > './mytest/main space.cpp'
( cd ./mytest ; ${CXX} -c  'main space.cpp' --coverage )

if [ 1 != "$NO_INITIAL_CAPTURE" ] ; then
    $COVER $CAPTURE mytest -i -o spaces.info
    if [ 0 != $? ] ; then
        echo "Error:  unexpected error from filename containing space"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    $COVER $LCOV_TOOL --list spaces.info
    if [ 0 != $? ] ; then
        echo "Error:  unable to list filename containing space"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    $COVER $GENHTML_TOOL -o spaces spaces.info
    if [ 0 != $? ] ; then
        echo "Error:  unable to generate HTML for filename containing space"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
fi


if [ "x$COVER" != "x" ] ; then
    generate_coverage 'extract_2' $LOCAL_COVERAGE
fi

echo "Tests passed"
