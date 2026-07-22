#!/bin/bash
set +x

source ../../common.tst

clean_cover

[[ ${CC} == *"clang"* ]] && LLVMCOV="--gcov-tool llvm-cov --gcov-tool gcov"

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

mkdir -p rundir
cd rundir
rm -rf *

# === TEST1 ===
mkdir -p test1

${CC} --coverage ../inputs/test1.c -o test1/test
./test1/test

$COVER $LCOV_TOOL $LLVMCOV -o test1.info --capture -d test1

COUNT=`grep -c FNA:0,1, test1.info`
if [ 3 != $COUNT ] ; then
    echo "TEST1 Error:  expected COUNT==2, found $COUNT"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# === TEST2 ===
mkdir -p test2

${CC} --coverage ../inputs/test2.cpp -o test2/test
./test2/test

$COVER $LCOV_TOOL $LLVMCOV -o test2.info --capture -d test2

COUNT=`grep -c FNA:0,1, test2.info`
if [ 2 != $COUNT ] ; then
    echo "TEST2 Error:  expected COUNT==2, found $COUNT"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


# === EPILOG ===

echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi
