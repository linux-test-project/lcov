#!/bin/bash

set +x

source ../../common.tst

rm -rf out1.info out2.info *.log

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

LCOV_OPTS="--mcdc --branch"

$COVER $LCOV_TOOL $LCOV_OPTS --summary in.info 2>&1 | tee summary.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo 'lcov --summary failed'
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep '2 of 2 branches' summary.log
if [ 0 != $? ] ; then
    echo "didn't find expected branch count"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep '2 of 2 conditions' summary.log
if [ 0 != $? ] ; then
    echo "didn't find expected MCDC count"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -a in.info -o out1.info
for key in BRDA MCDC ; do
    COUNT=`grep -c $key out1.info`
    if [ $COUNT != 4 ] ; then
	echo "didn't find expected $key count 4: (found $COUNT)"
	if [ $KEEP_GOING == 0 ] ; then
            exit 1
	fi
    fi
done

$COVER $LCOV_TOOL $LCOV_OPTS -a in.info -forget-test-names -o out2.info
for key in BRDA MCDC ; do
    COUNT=`grep -c $key out2.info`
    if [ $COUNT != 2 ] ; then
	echo "didn't find expected $key count 2: (found $COUNT)"
	if [ $KEEP_GOING == 0 ] ; then
            exit 1
	fi
    fi
done

if [ "x$COVER" != "x" ] ; then
    generate_coverage names $LOCAL_COVERAGE
fi

echo "Tests passed"

