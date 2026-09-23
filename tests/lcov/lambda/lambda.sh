#!/bin/bash

# lambda function filtering, in java
# 'ignore_lambda_consistency', in C++:  the lambda in 'call_if.cpp' is never
#   called, but its line is hit - the line holds the call of 'call_if' too.
#   With the check enabled, that is an inconsistency;  with it disabled, the
#   line's count need not be the lambda's, and the lambda is left 'not hit'
set +x

source ../../common.tst

rm -rf *.txt* *.json dumper* report lambda *.gcda *.gcno *.info call_if *.log

clean_cover

if [[ 1 == "$CLEAN_ONLY" ]] ; then
    exit 0
fi

LCOV_OPTS="--branch $PARALLEL $PROFILE"

# lambda function on same line as function decl
$COVER $LCOV_TOOL $LCOV_OPTS -o filter.info -a 'lambda*.dat'
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# did the two get merged?
COUNT=`grep -c -E 'FNL:.+,319' filter.info`
if [ "$COUNT" != 1 ] ; then
    echo "ERROR: did not merge the lambda"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#did we get the right end line for toArrayOf?
grep -c -E 'FNL:.+,303,309' filter.info
if [ 0 != $? ] ; then
    echo "ERROR: computed wrong end line"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

STATUS=0
fail()
{
    echo "ERROR ($1): $2"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

# the hit count of the function which starts at line $2, in .info file $1
fnCount()
{
    awk -F'[:,]' -v line=$2 '
/^FNL:/ && $3 == line { idx[$2] = 1 }
/^FNA:/ && ($2 in idx) { print $3; exit }' $1
}

# capture label expected-exit(0 = success, 1 = failure) geninfo-args...
capture()
{
    local label=$1
    local status=$2
    shift 2
    $COVER $GENINFO_TOOL . --branch $PARALLEL $PROFILE -o $label.info \
        "$@" > $label.log 2>&1
    local rc=$?
    if [ $status == 0 -a $rc != 0 ] ; then
        cat $label.log
        fail $label "geninfo failed"
    elif [ $status != 0 -a $rc == 0 ] ; then
        fail $label "geninfo passed, but was expected to fail"
    fi
}

if ! type ${CXX} >/dev/null 2>&1 ; then
    fail call_if "missing tool: ${CXX}"
fi
${CXX} -std=c++11 --coverage -O0 -o call_if call_if.cpp || fail call_if 'compile'
./call_if

LINE_HIT="is not hit but line 5 is"
SUPPRESSED='call_if.cpp":5: lambda detected, consistency check suppressed'

# checked:  the line is hit, the lambda is not
capture strict 1 --rc ignore_lambda_consistency=0
if ! grep -q -F "$LINE_HIT." strict.log ; then
    fail strict "expected the lambda to be reported"
fi

# ..and if that is ignored, the lambda is marked 'hit'
capture fixed 0 --rc ignore_lambda_consistency=0 --ignore inconsistent
if ! grep -q -F "$LINE_HIT: function marked 'hit'" fixed.log ; then
    fail fixed "expected the lambda to be marked 'hit'"
fi
COUNT=`fnCount fixed.info 5`
if [ -z "$COUNT" -o "$COUNT" == 0 ] ; then
    fail fixed "lambda count '$COUNT', expected it to be hit"
fi

# not checked:  nothing is reported, and the lambda stays 'not hit'
capture loose 0 --rc ignore_lambda_consistency=1 -v
if grep -q -F "$LINE_HIT" loose.log ; then
    fail loose "lambda was reported"
fi
if ! grep -q -F "$SUPPRESSED" loose.log ; then
    fail loose "expected the check to be suppressed"
fi
COUNT=`fnCount loose.info 5`
if [ "$COUNT" != 0 ] ; then
    fail loose "lambda count '$COUNT', expected 0"
fi
if ! grep -q -E '^DA:5,[1-9]' loose.info ; then
    fail loose "expected line 5 to be hit"
fi

if [ 0 != $STATUS ] ; then
    echo "Tests failed"
    exit 1
fi
echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    generate_coverage 'lambda' $LOCAL_COVERAGE 0
fi
