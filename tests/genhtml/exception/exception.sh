#! /usr/bin/env bash

source ../../common.tst

rm -rf *.xml *.dat *.info *.jsn cover_one *_rpt *.gcno *.gcda \
   both no_throw throw both_llvm diff1 diff2 


clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

# is this git or P4?
if [ 1 == "$USE_P4" ] ; then
    GET_VERSION=${SCRIPT_DIR}/P4version.pm,--local-edit,--md5
else
    # this is git
    GET_VERSION=${SCRIPT_DIR}/gitversion.pm
fi


LCOV_OPTS="--branch-coverage $PARALLEL $PROFILE"

IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -ge 14 ] ; then
    ENABLE_MCDC_GCC=1
    LCOV_MCDC_GCC='--mcdc'
    MCDC_FLAGS_GCC=-fcondition-coverage
fi
if [ "${VER[0]}" -lt 5 ] ; then
    # gcc/4 generates inconsistent branch/line coverage info
    EXTRA_IGNORE='--ignore inconsistent'
fi
IFS='.' read -r -a LLVM_VER <<< `clang -dumpversion`
if [ "${LLVM_VER[0]}" -ge 14 ] ; then
    ENABLE_LLVM=1
    MCDC_FLAGS_LLVM='-fcoverage-mcdc -fcoverage-mapping'
    LCOV_MCDC_LLVM='--mcdc'
fi

STATUS=0

function runClang()
(
    TEST=$1
    shift
    FLAGS=$1
    shift
    # runClang exeName srcFile flags
    echo "clang++ -fprofile-instr-generate -fcoverage-mapping $MCDC_FLAGS_LLVM -o $TEST main.cpp test.cpp $FLAGS"
    clang++ -fprofile-instr-generate $MCDC_FLAGS_LLVM -o $TEST exception.cpp -lstdc++ $FLAGS
    if [ $? != 0 ] ; then
        echo "ERROR from clang++ $TEST $FLAGS"
        return 1
    fi
    ./$TEST
    llvm-profdata merge --sparse *.profraw -o $TEST.profdata
    if [ $? != 0 ] ; then
        echo "ERROR from llvm-profdata $TEST"
        return 1
    fi
    llvm-cov export -format=text -instr-profile=$TEST.profdata ./$TEST > $TEST.jsn
    if [ $? != 0 ] ; then
        echo "ERROR from llvm-cov $TEST"
        return 1
    fi
    $COVER $LLVM2LCOV_TOOL --branch $LCOV_MCDC_LLVM -o ${TEST}.info $TEST.jsn --version-script $GET_VERSION --include exception.cpp
    if [ $? != 0 ] ; then
        echo "ERROR from llvm2lcov $TEST"
        return 1
    fi
    $COVER $GENHTML_TOOL --flat --branch $LCOV_MCDC_LLVM -o ${TEST}_rpt ${TEST}.info --version-script $GET_VERSION
    if [ $? != 0 ] ; then
        echo "ERROR from genhtml $1"
        return 1
    fi
    rm -f *.profraw *.profdata
)

function runGcc()
{
    TEST=$1
    shift
    FLAGS=$1
    shift

    rm -f *.gcda *.gcno

    echo "g++ --coverage $MCDC_FLAGS_GCC -o $TEST exception.cpp $FLAGS"
    # runGcc exeName srcFile flags
    eval g++ --coverage $MCDC_FLAGS_GCC -o $TEST exception.cpp $FLAGS
    if [ $? != 0 ] ; then
        echo "ERROR from g++ $TEST $FLAGS"
        return 1
    fi
    ./$TEST
    echo "$GENINFO_TOOL -o $TEST.info $LCOV_MCDC_GCC --branch . $EXTRA_IGNORE"
    $COVER $GENINFO_TOOL -o $TEST.info $LCOV_MCDC_GCC --branch . $EXTRA_IGNORE
    if [ $? != 0 ] ; then
        echo "ERROR from geninfo $TEST"
        return 1
    fi
    $COVER $GENHTML_TOOL --flat --branch $LCOV_MCDC_GCC -o ${TEST}_rpt $TEST.info
    if [ $? != 0 ] ; then
        echo "ERROR from genhtml $TEST"
        return 1
    fi
    rm -f *.gcda *.gcno
}

runGcc both "-DNO_THROW -DDO_THROW"
if [ $? != 0 ] ; then
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
[[ `grep BRF both.info` =~ ([0-9]+)$ ]]
BRF=${BASH_REMATCH[1]}
[[ `grep BRH both.info` =~ ([0-9]+)$ ]]
BRH=${BASH_REMATCH[1]}

runGcc no_throw "-DNO_THROW"
if [ $? != 0 ] ; then
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
[[ `grep BRF no_throw.info` =~ ([0-9]+)$ ]]
BRF_no=${BASH_REMATCH[1]}  # 10
[[ `grep BRH no_throw.info` =~ ([0-9]+)$ ]]
BRH_no=${BASH_REMATCH[1]}  # 3

runGcc throw "-DDO_THROW"
if [ $? != 0 ] ; then
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
[[ `grep BRF throw.info` =~ ([0-9]+)$ ]]
BRF_th=${BASH_REMATCH[1]}  # 14
[[ `grep BRH throw.info` =~ ([0-9]+)$ ]]
BRH_th=${BASH_REMATCH[1]}  # 5

bf=$(($BRF_no + $BRF_th))
bh=$(($BRH_no + $BRH_th))
if [ "$bf" != "$BRF" ] ; then
    echo "unexpected BRF total: found $bf expected $BRF"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
    
fi
if [ "$bh" != "$BRH" ] ; then
    echo "unexpected BRH total: found $bh expected $BRH"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
    
fi

# merge 'throw' into 'no_throw'
$COVER $LCOV_TOOL -o merge1.info -a no_throw.info -a throw.info --branch $LCOV_MCDC_GCC
if [ $? != 0 ] ; then
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for pat in "BRF:$BRF" "BRH:$BRH" ; do
    grep $pat merge1.info
    if [ 0 != $? ] ; then
	echo "failed merge1: expected $pat found `grep BR $merge1.info`"
	STATUS=1
	if [ $KEEP_GOING == 0 ] ; then
            exit 1
	fi
    fi
done

# merge 'no_throw' into 'throw'
$COVER $LCOV_TOOL -o merge2.info -a throw.info -a no_throw.info --branch $LCOV_MCDC_GCC
if [ $? != 0 ] ; then
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for pat in "BRF:$BRF" "BRH:$BRH" ; do
    grep $pat merge2.info
    if [ 0 != $? ] ; then
	echo "failed merge1: $pat found `grep BR merge2.info`"
	STATUS=1
	if [ $KEEP_GOING == 0 ] ; then
            exit 1
	fi
    fi
done

# differential report
$COVER $GENHTML_TOOL -o diff1 --baseline-file throw.info no_throw.info $LCOV_MCDC_GCC --branch
if [ $? != 0 ] ; then
    echo "failed genhtml 1"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $GENHTML_TOOL -o diff2 --baseline-file no_throw.info throw.info $LCOV_MCDC_GCC --branch
if [ $? != 0 ] ; then
    echo "failed genhtml 2"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


if [ "$ENABLE_LLVM" == 1 ] ; then
    runClang both_llvm "-DDO_THROW -DNO_THROW"
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
