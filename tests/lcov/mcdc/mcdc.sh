#! /usr/bin/env bash

source ../../common.tst

rm -rf *.xml *.dat *.info *.jsn cover_one *_rpt *Test[123]* *.gcno *.gcda gccTest* llvmTest*

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

# is this git or P4?
if [ 1 == "$USE_GIT" ] ; then
    # this is git
    GET_VERSION=${SCRIPT_DIR}/gitversion.pm
else
    GET_VERSION=${SCRIPT_DIR}/P4version.pm,--local-edit,--md5
fi


LCOV_OPTS="--branch-coverage $PARALLEL $PROFILE"

IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -ge 14 ] ; then
    ENABLE_MCDC=1
fi
IFS='.' read -r -a LLVM_VER <<< `clang -dumpversion`
if [ "${LLVM_VER[0]}" -ge 14 ] ; then
    ENABLE_LLVM=1
fi

STATUS=0

function runClang()
(
    # runClang exeName srcFile flags
    clang++ -fprofile-instr-generate -fcoverage-mapping -fcoverage-mcdc -o $1 main.cpp test.cpp $2
    if [ $? != 0 ] ; then
        echo "ERROR from clang++ $1"
        return 1
    fi
    ./$1
    llvm-profdata merge --sparse *.profraw -o $1.profdata
    if [ $? != 0 ] ; then
        echo "ERROR from llvm-profdata $1"
        return 1
    fi
    llvm-cov export -format=text -instr-profile=$1.profdata ./$1 > $1.jsn
    if [ $? != 0 ] ; then
        echo "ERROR from llvm-cov $1"
        return 1
    fi
    $COVER $LLVM2LCOV_TOOL --branch --mcdc -o $1.info $1.jsn --version-script $GET_VERSION
    if [ $? != 0 ] ; then
        echo "ERROR from llvm2lcov $1"
        return 1
    fi
    $COVER $GENHTML_TOOL --flat --branch --mcdc -o $1_rpt $1.info --version-script $GET_VERSION
    if [ $? != 0 ] ; then
        echo "ERROR from genhtml $1"
        return 1
    fi
    # run again, excluding 'main.cpp'
    $COVER $LLVM2LCOV_TOOL --branch --mcdc -o $1.excl.info $1.jsn --version-script $GET_VERSION --exclude '*/main.cpp'
    if [ $? != 0 ] ; then
        echo "ERROR from llvm2lcov --exclude $1"
        return 1
    fi
    COUNT=`grep -c SF: $1.excl.info`
    if [ 1 != "$COUNT" ] ; then
        echo "ERROR llvm2lcov --exclude $1 didn't work"
        return 1
    fi
    rm -f *.profraw *.profdata
)

function runGcc()
{
    NAME=$1
    shift
    ARG=$1
    shift
    # runGcc exeName srcFile flags
    eval g++ --coverage -fcondition-coverage -o $NAME main.cpp test.cpp $ARG
    if [ $? != 0 ] ; then
        echo "ERROR from g++ $NAME"
        return 1
    fi
    ./$NAME
    $COVER $GENINFO_TOOL -o $NAME.info --mcdc --branch $NAME-test.gcda $@
    if [ $? != 0 ] ; then
        echo "ERROR from geninfo $NAME"
        return 1
    fi
    $COVER $GENHTML_TOOL --flat --branch --mcdc -o ${NAME}_rpt $NAME.info
    if [ $? != 0 ] ; then
        echo "ERROR from genhtml $NAME"
        return 1
    fi
    rm -f *.gcda *.gcno
}


$COVER $LLVM2LCOV_TOOL --help
if [ 0 != $? ] ; then
    echo "ERROR: unexpected return code from --help"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LLVM2LCOV_TOOL --unknown_arg
if [ 0 == $? ] ; then
    echo "ERROR: expected return code from --help"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


if [ "$ENABLE_MCDC" == 1 ] ; then
    runGcc gccTest1
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    runGcc gccTest2 -DSENS1
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    runGcc gccTest3 -DSENS2
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    runGcc gccTest4 '-DSENS2 -DSIMPLE' --filter mcdc
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    # the MC/DC should have been filtered out - in favor of the branch
    COUNT=`grep -c MCDC gccTest4.info`
    if [ 0 != "$COUNT" ] ; then
        STATUS=1
        echo "filter error MC/DC"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    runGcc gccTest4a '-DSENS2 -DSIMPLE'
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    # the MC/DC shouldn't be filtered
    COUNT=`grep -c MCDC gccTest4a.info`
    if [ 0 == "$COUNT" ] ; then
        STATUS=1
        echo "filter error2 MC/DC"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    runGcc gccTest5 -DSENS2 --filter mcdc
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    # the MC/DC shouldn't have been filtered out
    COUNT=`grep -c MCDC gccTest5.info`
    if [ 0 == "$COUNT" ] ; then
        STATUS=1
        echo "MC/DC filter error"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
else
    echo "SKIPPING MC/DC tests:  ancient compiler"
fi

if [ "$ENABLE_LLVM" == 1 ] ; then
    runClang clangTest1
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    runClang clangTest2 -DSENS1
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    runClang clangTest3 -DSENS2
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
else
    echo "SKIPPING LLVM tests"
fi

if [ $STATUS == 0 ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi

exit $STATUS
