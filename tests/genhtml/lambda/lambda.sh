#!/bin/bash

# lambda function extents
set +x

source ../../common.tst
rm -rf *.txt* *.json dumper* report lambda *.gcda *.gcno *.info

clean_cover

if [[ 1 == "$CLEAN_ONLY" ]] ; then
    exit 0
fi

LCOV_OPTS="--branch $PARALLEL $PROFILE"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
    # and filter exception branches to avoid spurious differences for old compiler
    FILTER='--filter branch'

    # gcc older than 5 doesn't support lambda
    echo "Compiler version is too old - skipping lambda test"
    exit 0
fi

if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

${CXX} -o lambda --coverage lambda.cpp -std=c++1y

./lambda
if [ 0 != $? ] ; then
    echo "Error:  'lambda' returned error code"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -o lambda.info --capture -d . --demangle --rc derive_function_end_line=0
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


$COVER $GENHTML_TOOL $LCOV_OPTS -o report lambda.info --show-proportion
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from genhtml"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi
