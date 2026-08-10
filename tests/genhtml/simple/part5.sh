#!/bin/bash
set +x

# ============================================================================
# part5 of the former monolithic 'simple' genhtml test (see setup_common.sh).
# Covers: the coverpoint-proportion reports, the empty-annotate checks, the
# --rc option-format errors, --ignore usage / --expect / --msg-log, the
# unreachable branch/mcdc exclusions, the diff-range inconsistency, and
# --legend.
#
# This is the second half of the original part4.sh (which also covered the
# criteria callback, --substitute/--exclude, the trivial-function filter and
# the lcov error checks -- those stay in part4.sh).  The two were split at the
# point where their measured run times are roughly equal.
# ============================================================================

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    rm -rf part5.d
    exit 0
fi

if ! type "${CXX}" >/dev/null 2>&1 ; then
        echo "Missing tool: $CXX" >&2
        exit 2
fi

if ! python3 -c "import xlsxwriter" >/dev/null 2>&1 ; then
        echo "Missing python module: xlsxwriter" >&2
        exit 2
fi

WORKDIR=part5.d
source ./setup_common.sh

status=0

# --------------------------------------------------------------------------
# function "coverpoint proportion" feature
# --------------------------------------------------------------------------
grep -E 'FNL:[0-9]+,[0-9]+,[0-9]+' baseline.info
NO_END_LINE=$?

if [ $NO_END_LINE == 0 ] ; then
    echo "----------------------"
    echo "   compiler version support start/end reporting"
    SUFFIX='_region'
else
    echo "----------------------"
    echo "   compiler version DOES NOT support start/end reporting"
    SUFFIX=''
fi

echo genhtml $DIFFCOV_OPTS current.info --output-directory ./proportion --show-proportion $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS current.info --output-directory ./proportion --show-proportion $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: genhtml current proportional failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# and then a differential report...
# NOTE: the original script reused a leftover $OPTS from the earlier
# differential option-combo loop here; that loop now lives in part2, so use
# $DIFFCOV_OPTS explicitly (branch coverage is required for the "unexercised
# branches" proportion column to appear).
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source -o ./differential_prop ./current.info --show-proportion $IGNORE
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source -o ./differential_prop ./current.info --show-proportion $GENHTML_PORT $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: genhtml differential proportional failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# and see if we find the content we expected...
for test in proportion differential_prop ; do
    for s in "unexercised branches" "unexercised lines" ; do
        if [ 0 == $NO_END_LINE ] ; then
            for f in "" '-c' '-b' '-l' ; do
                NAME=$test/simple/test.cpp.func$f.html
                grep "sort table by $s" $NAME
                if [ 0 != $? ] ; then
                    echo "did not find col '$s' in $NAME"
                    status=1
                    if [ 0 == $KEEP_GOING ] ; then
                        exit 1
                    fi
                fi
            done
        else
            for f in "" '-c' ; do
                NAME=$test/simple/test.cpp.func$f.html
                grep "sort table by $s" $NAME
                if [ 0 == $? ] ; then
                    echo "unexpected col '$s' in $NAME"
                    status=1
                    if [ 0 == $KEEP_GOING ] ; then
                        exit 1
                    fi
                fi
            done
        fi
    done
done

# --------------------------------------------------------------------------
# error message if nothing annotated
# --------------------------------------------------------------------------
cp simple.cpp annotate.cpp
${CXX} $COVERAGE_OPTS -o annotate.exe --coverage annotate.cpp
if [ 0 != $? ] ; then
    echo "annotate compile failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
./annotate.exe
if [ 0 != $? ] ; then
    echo "./annotate.exe failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo lcov $LCOV_OPTS --capture --directory . --output-file annotate.info $IGNORE --include "annotate.cpp"
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file annotate.info $IGNORE --include "annotate.cpp"
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture annotate failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo genhtml $DIFFCOV_OPTS --output-directory ./annotate --annotate $ANNOTATE,--log,ann.log annotate.info
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./annotate --annotate $ANNOTATE,--log,ann.log annotate.info
if [ 0 == $? ] ; then
    echo "ERROR: annotate with no annotation"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep 'annotate.cpp not in repo' ann.log
if [ 0 != $? ] ; then
    echo "Error:  expected message not in 'ann.log'"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo genhtml $DIFFCOV_OPTS --output-directory ./annotate --annotate $ANNOTATE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./annotate --annotate $ANNOTATE --ignore annotate annotate.info
if [ 0 != $? ] ; then
    echo "ERROR: annotate with no annotation ignore did not pass"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# --------------------------------------------------------------------------
# nonexistent / malformed --rc option errors
# --------------------------------------------------------------------------
# check nonexistent --rc option (note minus on '-memory_percentage')
echo genhtml $DIFFCOV_OPTS --output-directory ./errOut --rc -memory_percentage=50 baseline_orig.info $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./errOut --rc -memory_percentage=50 baseline_orig.info $IGNORE
if [ 0 == $? ] ; then
    echo "ERROR: incorrect RC option not caught"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# check --rc formatting
echo genhtml $DIFFCOV_OPTS --output-directory ./errOut --rc memory_percentage baseline_orig.info $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./errOut --rc memory_percentage baseline_orig.info $IGNORE
if [ 0 == $? ] ; then
    echo "ERROR: incorrect RC option not caught"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# skip both errors
# ignore version error which might happen if timestamp is included
echo genhtml $DIFFCOV_OPTS --output-directory ./usage --rc memory_percentage --rc -memory_percentage=50 baseline_orig.info --ignore usage,version
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./usage --rc memory_percentage --rc percent=5 baseline_orig.info --ignore usage,version $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: didn't ignore errors"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# skip both errors - but check total message count
echo genhtml $DIFFCOV_OPTS --output-directory ./expect_err --rc memory_percentage --rc -memory_percentage=50 baseline_orig.info --ignore usage,version --expect usage:1
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./expect_err --rc memory_percentage --rc percent=5 baseline_orig.info --ignore usage,version $IGNORE --expect usage:1 2>&1 | tee expect_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: didn't catch expect count error"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "ERROR:.*count.*'usage' constraint .+ is not true" expect_err.log

# now skip the count message too
echo genhtml $DIFFCOV_OPTS --output-directory ./expect --rc memory_percentage --rc -memory_percentage=50 baseline_orig.info --ignore usage,version,count --rc expect_message_count=usage:1 --msg-log
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./expect --rc memory_percentage --rc percent=5 baseline_orig.info --ignore usage,version,count $IGNORE --rc expect_message_count=usage:1 --msg-log 2>&1 | tee expect.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: didn't skip expect count error"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

grep -E "WARNING:.*count.*'usage' constraint .+ is not true" expect.msg
if [ 0 == $? ] ; then
    echo "ERROR: didn't find expected msg in log"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# --------------------------------------------------------------------------
# unreachable branch/mcdc exclusions
#  first:  move our somewhat faked source file containing the annotations
#     into place
# --------------------------------------------------------------------------
rm -f test.cpp unreach.cpp.annotated
ln -s unreach.cpp test.cpp
ln -s simple2.cpp.annotated unreach.cpp.annotated
# now generate a report - using the same coverage and diff data as other tests
#   this will work because we only care about line numbers - not their content
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_NO_VERSION_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source -o unreach ./current.info $IGNORE $POPUP --unreachable $UNREACHABLE
$COVER ${GENHTML_TOOL} $DIFFCOV_NO_VERSION_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source -o unreach ./current.info $GENHTML_PORT $IGNORE $POPUP  --unreachable $UNREACHABLE 2>&1 | tee unreach.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml unreach failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# now generate a vanilla report (not differential) with excluded coverpoints
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_NO_VERSION_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source -o unreach_vanilla ./current.info $IGNORE $POPUP --unreachable $UNREACHABLE
$COVER ${GENHTML_TOOL} $DIFFCOV_NO_VERSION_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source -o unreach_vanilla ./current.info $GENHTML_PORT $IGNORE $POPUP  --unreachable $UNREACHABLE 2>&1 | tee unreach.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml unreach vanilla failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

BRANCH_COUNT_MSG='Excluded 2 branches from 2 lines.'
if [ "${VER[0]}" -lt 5 ] ; then
    # gcc/4.8.3 is different...
    BRANCH_COUNT_MSG='Excluded 1 branches from 1 line.'
fi

for pat in 'Excluded 1 MC/DC condition from 1 line.' $BRANCH_COUNT_MSG ; do
    if [[ "$ENABLE_MCDC" == "1" || ! $pat =~ "MC/DC" ]] ; then
        grep "$pat" unreach.log
        if [ 0 != $? ] ; then
            echo "ERROR: did not find '$pat' in unreach.log"
            status=1
            if [ 0 == $KEEP_GOING ] ; then
                exit 1
            fi
        fi
    fi
done

INCONSISTENT_STATUS="ERROR"
if [ "${VER[0]}" -lt 5 ] ; then
    # gcc/4.8.3 inconsistent WRT function vs line coverpoint
    IGNORE_INCONSISTENT="--ignore inconsistent"
    INCONSISTENT_STATUS="WARNING"
fi

# --------------------------------------------------------------------------
# diff file which refers to out-of-range lines - to generate error message
# --------------------------------------------------------------------------
sed -E 's/22,24 \+23,23/32,34 \+33,33/' < diff.txt > diff_err.txt
# specify a source filter - so "ReadBaselineSource" will try to recreate
#   the file
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_NO_VERSION_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --baseline-file baseline.info --diff-file diff_err.txt -o diff_range ./current.info  --filter branch $IGNORE_INCONSISTENT
$COVER ${GENHTML_TOOL} $DIFFCOV_NO_VERSION_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --baseline-file baseline.info --diff-file diff_err.txt -o diff_range ./current.info --filter branch $IGNORE_INCONSISTENT 2>&1 | tee diff_range_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml diff range didn't error out"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "$INCONSISTENT_STATUS: .inconsistent.+: inconsistent diff data vs current source code: diff refers to 'current' line range" diff_range_err.log
if [ 0 != $? ] ; then
    echo "did not find expected range error"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

if [ "${VER[0]}" -lt 14 ] ; then
    # old gcc gets some line numbers wrong - so we need to ignore some
    #  out-of-range messages when we look for the one we want to check
    EXTRA_IGNORE="--ignore range"
fi

# now ignore the inconsistency and see if we generate the report
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_NO_VERSION_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --baseline-file baseline.info --diff-file diff_err.txt -o diff_range ./current.info --filter branch --ignore inconsistent $EXTRA_IGNORE
$COVER ${GENHTML_TOOL} $DIFFCOV_NO_VERSION_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --baseline-file baseline.info --diff-file diff_err.txt -o diff_range ./current.info --filter branch --ignore inconsistent $EXTRA_IGNORE 2>&1 | tee diff_range.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml diff range didn't ignore error"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "WARNING: .inconsistent.+: inconsistent diff data vs current source code: diff refers to 'current' line range" diff_range.log
if [ 0 != $? ] ; then
    echo "did not file expected range warning"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# --------------------------------------------------------------------------
# a diff whose last hunk is not at the end of the file.  A unified diff says
# nothing about the text after its last hunk - those lines are identical in the
# two versions - so the recreated baseline has to run to the end of the file.
# It used to stop at the last hunk, which left every exclusion marker after
# that point unseen and every baseline coverage point past it reported as an
# out-of-range line.
# The baseline here is the current source with one comment line changed, so the
# baseline coverage data is the current data (with the version hacked, which is
# what the diff consistency check wants) and the only hunk is at the top of a
# 45 line file.
# --------------------------------------------------------------------------
sed -e '4s|.*| * @date   Mon Apr 13 00:00:00 2020|' simple2.cpp > early_base.cpp
diff -u early_base.cpp simple2.cpp | \
    sed -e "s|early_base\.cpp|$ROOT/test.cpp|g" \
        -e "s|simple2\.cpp|$ROOT/test.cpp|g" > early_diff.txt
SRC_LINES=`awk 'END {print NR}' test.cpp`
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_NO_VERSION_OPTS --baseline-file current_hacked.info --diff-file early_diff.txt -o early ./current.info --filter branch
$COVER ${GENHTML_TOOL} $DIFFCOV_NO_VERSION_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --baseline-file current_hacked.info --diff-file early_diff.txt -o early ./current.info --filter branch $IGNORE_INCONSISTENT $EXTRA_IGNORE 2>&1 | tee early_diff.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml failed on a diff whose last hunk is not at EOF"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# any complaint that the file is shorter than it is means the baseline was
#   truncated.  Some old gcov versions invent line numbers past the end of the
#   file, so a message which reports the true length is not this bug and is
#   left alone.
grep -E "there are only [0-9]+ lines" early_diff.log | \
    grep -vE "there are only $SRC_LINES lines"
if [ 0 == $? ] ; then
    echo "ERROR: recreated baseline is shorter than $SRC_LINES lines"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# --legend: exercise the color-legend block in the page header (branch/MC/DC
# and rating legends).  genhtml_legend defaults off, so without this option the
# legend-generation code is never reached.  Use a plain source-view report;
# BASE_OPTS already enables branch (and MC/DC where supported) coverage so the
# branch/MC/DC legend rows are populated.
echo genhtml $DIFFCOV_OPTS --legend -o legend ./current.info
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --legend --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source,version -o legend ./current.info $GENHTML_PORT $IGNORE 2>&1 | tee legend.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml --legend failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -rl 'class="headerValueLeg"' legend/simple/test.cpp.gcov.html > /dev/null
if [ 0 != $? ] ; then
    echo "ERROR: --legend did not emit legend block"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo $SPREADSHEET_TOOL -o results.xlsx `find . -name "*.json"`
eval $SPREADSHEET_TOOL -o results.xlsx `find . -name "*.json"`
if [ 0 != $? ] ; then
    status=1
    echo "ERROR:  spreadsheet generation failed"
    exit 1
fi

if [ 0 == $status ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'simple_5' $LOCAL_COVERAGE 1
fi

exit $status
