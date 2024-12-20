#!/bin/bash

# test relative path usage
set +x

source ../../common.tst

rm -rf *.txt* *.json dumper* relative

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
fi

if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

$COVER $GENHTML_TOOL $LCOV_OPTS -o relative relative.info --ignore source,source --synthesize
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from genhtml"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

for dir in lib src lib/src ; do
    if [ -e relative/$dir/$dir ] ; then
        echo "Error: unexpected duplicated path to '$dir'"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

for f in lib lib/other_class.dart.gcov.html lib/src lib/src/sample_class.dart.gcov.html ; do
    if [ ! -e relative/$f ] ; then
        echo "Error: can't find '$f'"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done


echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi
