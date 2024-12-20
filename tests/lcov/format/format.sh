#!/bin/bash
set +x

# test various errors in .info data

source ../../common.tst

LCOV_OPTS="--branch $PARALLEL $PROFILE"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
    # and filter exception branches to avoid spurious differences for old compiler
    FILTER='--filter branch'
fi

rm -rf *.gcda *.gcno a.out out.info out2.info *.txt* *.json dumper* testRC *.gcov *.gcov.* *.log

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

$COVER $LCOV_TOOL $LCOV_OPTS --summary format.info 2>&1 | tee err1.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected error from lcov --summary but didn't see it"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
ERRS=`grep -c 'ERROR: (negative)' err1.log`
if [ "$ERRS" != 1 ] ; then
    echo "didn't see expected 'negative' error"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS --summary format.info --ignore negative 2>&1 | tee err2.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected error from lcov --summary negative but didn't see it"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
ERRS=`grep -c 'ERROR: (format)' err2.log`
if [ "$ERRS" != 1 ] ; then
    echo "didn't see expected 'format' error"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -o out.info -a format.info --ignore format,negative 2>&1 | tee warn.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error from lcov -add"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for type in format negative ; do
    COUNT=`grep -c "WARNING: ($type)" warn.log`
    if [ "$COUNT" != 3 ] ; then
        echo "didn't see expected '$type' warnings: $COUNT"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    # and look for the summary count:
    grep "$type: 3" warn.log
    if [ 0 != $? ] ; then
        echo "didn't see Type summary count"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done


# the file we wrote should be clean
$COVER $LCOV_TOOL $LCOV_OPTS --summary out.info
if [ 0 != $? ] ; then
    echo "Error:  unexpected error from lcov --summary"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

rm -f out2.info
# test excessive count messages
$COVER $LCOV_TOOL $LCOV_OPTS -o out2.info -a format.info --ignore format,format,negative,negative --rc excessive_count_threshold=1000000 2>&1 | tee excessive.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected excessive hit count message"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep "ERROR: (excessive) Unexpected excessive hit count" excessive.log
if [ 0 != $? ] ; then
    echo "Error:  expected excessive hit count message but didn't find it"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
if [ -e out2.info ] ; then
    echo "Error: expected error to terminate processing - but out2.info generated"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# check that --keep-going works as expected
$COVER $LCOV_TOOL $LCOV_OPTS -o out2.info -a format.info --ignore format,format,negative,negative --rc excessive_count_threshold=1000000 --keep-going 2>&1 | tee keepGoing.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected excessive hit count message"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep "ERROR: (excessive) Unexpected excessive hit count" excessive.log
if [ 0 != $? ] ; then
    echo "Error:  expected excessive hit count message but didn't find it"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
if [ ! -e out2.info ] ; then
    echo "Error: expected --keep-going to continue execution - but out2.info not found"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
diff out.info out2.info
if [ 0 != $? ] ; then
    echo "Error: mismatched output generated"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -o out.info -a format.info --ignore format,format,negative,negative,excessive --rc excessive_count_threshold=1000000 2>&1 | tee warnExcessive.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected to warn"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
COUNT=`grep -c -E 'WARNING: \(excessive\) Unexpected excessive .+ count' warnExcessive.log`
if [ $COUNT -lt 3 ] ; then
    echo "Error:  unexpectedly found only $COUNT messages"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi
