#!/bin/bash
set +x

source ../../common.tst

LCOV_OPTS="$PARALLEL $PROFILE"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
fi

rm -rf rundir

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

mkdir -p rundir
cd rundir

rm -Rf a b out
mkdir a b

echo 'int a (int x) { return x + 1; }' > a/a.c
echo 'int b (int x) { return x + 2;}' > b/b.c

( cd a ; ${CC} -c --coverage a.c -o a.o )
( cd b ; ${CC} -c --coverage b.c -o b.o )

$COVER $LCOV_TOOL -o out.info --capture --initial --no-external -d a -d b
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --initial"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

COUNT=`grep -c SF: out.info`
if [ 2 != $COUNT ] ; then
    echo "Error:  expected COUNT==2, found $COUNT"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $GENINFO_TOOL -o out2.info --initial --no-external a b
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from geninfo --initial"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

diff out.info out2.info
if [ 0 != $? ] ; then
    echo "Error:  expected identical geninfo output"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# old version of gcc doesn't encode path into .gcno file
#  so the case-insensitive compare is not required.
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -ge 9 ] ; then
    rm -rf B
    mv b B

    $COVER $GENINFO_TOOL -o out3.info --initial --no-external a B
    if [ 0 != $? ] ; then
        echo "Error:  unexpected error code from geninfo"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    COUNT=`grep -c SF: out3.info`
    if [ 1 != $COUNT ] ; then
        echo "Error:  expected COUNT==1, found $COUNT"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    # don't look for exclusions:  our filesystem isn't case-insensitive
    # and we will see a 'source' error
    $COVER $GENINFO_TOOL -o out4.info --initial --no-external a B --rc case_insensitive=1 --no-markers
    if [ 0 != $? ] ; then
        echo "Error:  expected error code from geninfo insensitive"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    diff out4.info out.info
    if [ 0 != $? ] ; then
        echo "Error:  expected identical case-insensitive output, found $COUNT"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
fi


echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi
