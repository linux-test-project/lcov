#!/bin/bash

# lambda function filtering, in java
set +x

source ../../common.tst

rm -rf *.txt* *.json dumper* report lambda *.gcda *.gcno *.info

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


echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi
