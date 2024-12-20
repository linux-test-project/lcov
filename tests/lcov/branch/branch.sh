#!/bin/bash
set +x

source ../../common.tst

rm -rf *.gcda *.gcno a.out *.info* *.txt* *.json dumper* testRC *.gcov *.gcov.* no_macro* macro* total.*
if [ -d separate ] ; then
    chmod -R u+w separate
    rm -rf separate
fi

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

#use geninfo to capture - to collect coverage data
CAPTURE="$GENINFO_TOOL ."
#CAPTURE="$LCOV_TOOL --capture --directory ."

ROOT=`pwd`
PARENT=`(cd .. ; pwd)`

LCOV_OPTS="--branch $PARALLEL $PROFILE"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
fi

# filter exception branches to avoid spurious differences for old compiler
FILTER='--filter branch'


if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

${CXX} -std=c++1y --coverage branch.cpp -o no_macro
if [ 0 != $? ] ; then
    echo "Error:  unexpected error from gcc -o no_macro"
    exit 1
fi

./no_macro 1
if [ 0 != $? ] ; then
    echo "Error:  unexpected error return from no_macro"
    exit 1
fi

$COVER $CAPTURE $LCOV_OPTS . -o no_macro.info $FILTER $IGNORE --no-external
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --capture"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

COUNT=`grep -c BRDA: no_macro.info`
if [ $COUNT != 6 ] ; then
    echo "ERROR:  unexpected branch count in no_macro:  $COUNT (expected 6)"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

rm -f *.gcda *.gcno

${CXX} -std=c++1y --coverage branch.cpp -DMACRO -o macro
if [ 0 != $? ] ; then
    echo "Error:  unexpected error from gcc -o macro"
    exit 1
fi

./macro 1
if [ 0 != $? ] ; then
    echo "Error:  unexpected error return from macro"
    exit 1
fi

$COVER $CAPTURE $LCOV_OPTS -o macro.info $FILTER $IGNORE --no-external
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --capture"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

COUNT2=`grep -c BRDA: macro.info`
if [ $COUNT2 != 6 ] ; then
    echo "ERROR:  unexpected branch count in macro:  $COUNT2 (expected 6)"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -a no_macro.info -a macro.info -o total.info $IGNORE $FILTER
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --aggregate"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# in 'macro' test, older versions of gcc show 2 blocks on line 29, each with
#  newer gcc shows 1 block with 4 branches
# This output data format affects merging
grep -E BRDA:[0-9]+,0,3 macro.info
if [ $? == 0 ] ; then
    echo 'newer gcc found'
    EXPECT=12
else
    echo 'found old gcc result'
    EXPECT=8
fi

TOTAL=`grep -c BRDA: total.info`
if [ $TOTAL != $EXPECT ] ; then
    echo "ERROR:  unexpected branch count in total:  $TOTAL (expected $EXPECT)"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -a macro.info -a no_macro.info -o total2.info
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --aggregate (2)"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

TOTAL2=`grep -c BRDA: total2.info`
if [ $TOTAL2 != $EXPECT ] ; then
    echo "ERROR:  unexpected branch count in total2:  $TOTAL2 (expected $EXPECT)"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi
