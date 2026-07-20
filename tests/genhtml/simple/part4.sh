#!/bin/bash
set +x

# ============================================================================
# part4 of the former monolithic 'simple' genhtml test (see setup_common.sh).
# Covers: criteria-callback (RC errors, script + module, signoff), the file
# --substitute / --exclude capture, the trivial-function filter, lcov error /
# --ignore-unused checks, the coverpoint-proportion reports, the empty-annotate
# checks, the --rc option-format errors, --ignore usage / --expect / --msg-log,
# the unreachable branch/mcdc exclusions, and the diff-range inconsistency.
# ============================================================================

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    rm -rf part4.d
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

WORKDIR=part4.d
source ./setup_common.sh

status=0

# --------------------------------------------------------------------------
# criteria-related RC override errors
# --------------------------------------------------------------------------
for errs in 'criteria_callback_levels=dir,a' 'criteria_callback_data=foo' ; do
    echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --criteria $CRITERIA -o $outdir ./current.info --rc $errs $IGNORE
    $COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --criteria $CRITERIA -o criteria ./current.info $GENHTML_PORT --rc $errs $IGNORE > criteriaErr.log 2> criteriaErr.err
    if [ 0 == $? ] ; then
        echo "ERROR: genhtml criteria should have failed but didn't"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    grep -E "invalid '.+' value .+ expected" criteriaErr.err
    if [ 0 != $? ] ;then
        echo "ERROR: 'invalid criteria option message is missing"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

# --------------------------------------------------------------------------
# 'coverage criteria' callback - both script and module
# --------------------------------------------------------------------------
for mod in '' '.pm' ; do
    #  we expect to fail - and to see error message - it coverage criteria not met
    # ask for date and owner data - even though the callback doesn't use it
    echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --criteria $CRITERIA$mod -o criteria$mod ./current.info --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file $IGNORE
    $COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --criteria $CRITERIA$mod --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file -o criteria$mod ./current.info $GENHTML_PORT $IGNORE > criteria$mod.log 2> criteria$mod.err
    if [ 0 == $? ] ; then
        echo "ERROR: genhtml criteria should have failed but didn't"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    # signoff should pass...
    echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --criteria $CRITERIA$mod --criteria --signoff -o criteria_signoff$mod ./current.info --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file $IGNORE
    $COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --criteria $CRITERIA$mod --criteria --signoff --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file -o criteria_signoff$mod ./current.info $GENHTML_PORT $IGNORE > criteria_signoff$mod.log 2> criteria_signoff$mod.err
    if [ 0 != $? ] ; then
        echo "ERROR: genhtml criteria signoff should have passed but didn't"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    if [[ $OPTS =~ "show-details" ]] ; then
        found=0
    else
        found=1
    fi
    grep "Failed coverage criteria" criteria$mod.log
    # expect to find the string (0 return val) if flag is present
    if [ 0 != $? ] ;then
        echo "ERROR: 'criteria fail message not matched"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    for suffix in '' '_signoff' ; do
        if [ 'x' == "x$suffix" ] ; then
            SIGNOFF_ERR=0
        else
            # we don't expect to see error, if signoff
            SIGNOFF_ERR=1
        fi
        for l in criteria$suffix$mod.log criteria$suffix$mod.err ; do
            FOUND=0
            if [[ $l =~ "err" ]] ; then
                # don't expect to find message in stderr, if signoff
                FOUND=$SIGNOFF_ERR
            fi
            grep "UNC + LBC + UIC != 0" $l
            # expect to find the string (0 return val) if flag is present
            if [ $FOUND != $? ] ;then
                echo "ERROR: 'criteria string not matching in  $l"
                status=1
                if [ 0 == $KEEP_GOING ] ; then
                    exit 1
                fi
            fi
        done
    done
done

# test 'coverage criteria' callback
#  we expect to fail - and to see error message - it coverage criteria not met
# ask for date and owner data - even though the callback doesn't use it
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --criteria "$CRITERIA --signoff" -o $outdir ./current.info --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file $IGNORE
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --criteria "$CRITERIA --signoff" --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file -o criteria ./current.info $GENHTML_PORT $IGNORE > signoff.log 2> signoff.err
if [ 0 != $? ] ; then
    echo "ERROR: genhtml criteria --signoff did not pass"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "UNC + LBC + UIC != 0" signoff.log
# expect to find the string (0 return val) if flag is present
if [ 0 != $? ] ; then
    echo "ERROR: 'criteria string is missing from signoff.log"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# --------------------------------------------------------------------------
# file substitution option
#  need to ignore the 'missing source' error which will happen when we try to
#  filter for exclude patterns - the file 'pwd/test.cpp' does not exist
# --------------------------------------------------------------------------
export PWD=`pwd`
echo $CAPTURE . $LCOV_OPTS --output-file subst.info --substitute "s#${PWD}#pwd#g" --exclude '*/iostream' --ignore source,source $IGNORE $EMPTY_BRANCH
$COVER $CAPTURE . $LCOV_OPTS --output-file subst.info --substitute "s#${PWD}#pwd#g" --exclude '*/iostream' --ignore source,source $LCOV_PORT $IGNORE $EMPTY_BRANCH
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "pwd/test.cpp" subst.info
if [ 0 != $? ] ; then
    echo "ERROR: --substitute failed - not found in subst.info"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "iostream" subst.info
if [ 0 == $? ] ; then
    echo "ERROR: --exclude failed - found in subst.info"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "pwd/test.cpp" baseline.info
if [ 0 == $? ] ; then
    # substitution should not have happened in baseline.info
    echo "ERROR: --substitute failed - found in baseline.info"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# gcc/10 doesn't see code in its c++ headers - test will fail..
COUNT=`grep -c SF: baseline.info`
if [ $COUNT != '1' ] ; then
    grep "iostream" baseline.info
    if [ 0 != $? ] ; then
        # exclude should not have happened in baseline.info
        echo "ERROR: --exclude failed - not found in baseline.info"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
fi

# --------------------------------------------------------------------------
# trivial-function filter
# --------------------------------------------------------------------------
echo lcov $LCOV_OPTS --capture --directory . --output-file trivial.info --filter trivial,branch $IGNORE $DERIVE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file trivial.info --filter trivial,branch $IGNORE $DERIVE
if [ 0 == $? ] ; then
    BASELINE_COUNT=`grep -c FNL: baseline.info`
    TRIVIAL_COUNT=`grep -c FNL: trivial.info`
    # expect lower function count:  we should have removed 'static_initial...
    GENERATED=`grep -c _GLOBAL__ baseline.info`
    if [[ ( 0 != $GENERATED &&
            $TRIVIAL_COUNT -ge $BASELINE_COUNT ) ||
          ( 0 == $GENERATED &&
            $TRIVIAL_COUNT != $BASELINE_COUNT) ]] ; then
        echo "ERROR:  trivial filter failed"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
else
    echo "old version of gcc doesn't support trivial function filtering because no end line"
    # try to see if we can generate the data if we ignore unsupported...
    $COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file trivial.info --filter trivial,branch $IGNORE $DERIVE --ignore unsupported
    if [ 0 != $? ] ; then
        echo "ERROR: lcov --capture trivial failed after ignoring error"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
fi

# --------------------------------------------------------------------------
# some error checks...
# use 'no_markers' flag so we won't see the filter message
# --------------------------------------------------------------------------
echo $LCOV_TOOL $LCOV_OPTS --output err1.info -a current.info -a current.info --substitute "s#xyz#pwd#g" --exclude 'thisStringDoesNotMatch' --no-markers
$COVER $LCOV_TOOL $LCOV_OPTS --output err1.info -a current.info -a current.info --substitute "s#xyz#pwd#g" --exclude 'thisStringDoesNotMatch' --no-markers
if [ 0 == $? ] ; then
    echo "ERROR: lcov ran despite error"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo $LCOV_TOOL $LCOV_OPTS --output unused.info -a current.info -a current.info --substitute "s#xyz#pwd#g" --exclude 'thisStringDoesNotMatch' --ignore unused --no-markers $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --output unused.info -a current.info -a current.info --substitute "s#xyz#pwd#g" --exclude 'thisStringDoesNotMatch' --ignore unused --no-markers $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: lcov failed despite suppression"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

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
    generate_coverage 'simple_4' $LOCAL_COVERAGE 1
fi

exit $status
