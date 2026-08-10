#!/bin/bash
set +x

# ============================================================================
# part4 of the former monolithic 'simple' genhtml test (see setup_common.sh).
# Covers: criteria-callback (RC errors, script + module, signoff), the file
# --substitute / --exclude capture, the trivial-function filter, and the lcov
# error / --ignore-unused checks.
#
# The remaining scenarios of the original part4 (coverpoint proportion, empty
# annotate, --rc option-format errors, --ignore usage / --expect / --msg-log,
# unreachable branch/mcdc exclusions, diff-range inconsistency, --legend) live
# in part5.sh; the two were split at the point where their measured run times
# are roughly equal.
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
