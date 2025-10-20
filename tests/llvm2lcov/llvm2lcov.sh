#!/bin/bash
set +x

if [[ "x" == ${LCOV_HOME}x ]] ; then
    if [ -f ../../bin/lcov ] ; then
        LCOV_HOME=../..
    fi
fi

source ../common.tst

rm -rf test *.profraw *.profdata *.json *.info report

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

LCOV_OPTS="--branch-coverage $PARALLEL $PROFILE"

IFS='.' read -r -a LLVM_VER <<< `clang -dumpversion`
if [ "${LLVM_VER[0]}" -ge 18 ] ; then
    ENABLE_MCDC=1
    CLANG_FLAGS="-fcoverage-mcdc"
    MCDC_FLAG=--mcdc
fi


clang++ -fprofile-instr-generate -fcoverage-mapping $CLANG_FLAGS -o test main.cpp
if [ $? != 0 ] ; then
    echo "clang++ exec failed"
    exit 1
fi
./test
llvm-profdata merge --sparse *.profraw -o test.profdata
if [ $? != 0 ] ; then
    echo "llvm-profdata failed"
    exit 1
fi
llvm-cov export -format=text -instr-profile=test.profdata ./test > test.json
if [ $? != 0 ] ; then
    echo "llvm-cov failed"
    exit 1
fi

# disable function, branch and mcdc coverage
$COVER $LLVM2LCOV_TOOL --rc function_coverage=0 -o test.info test.json
if [ $? != 0 ] ; then
    echo "llvm2lcov failed"
    exit 1
fi

# disable mcdc coverage
$COVER $LLVM2LCOV_TOOL --branch -o test.info test.json
if [ $? != 0 ] ; then
    echo "llvm2lcov failed"
    exit 1
fi

if [ "$ENABLE_MCDC" == "1" ] ; then
    # disable branch coverage
    $COVER $LLVM2LCOV_TOOL --mcdc -o test.info test.json
    if [ $? != 0 ] ; then
	echo "llvm2lcov failed"
	exit 1
    fi
fi

$COVER $LLVM2LCOV_TOOL --branch $MCDC_FLAG -o test.info test.json
if [ $? != 0 ] ; then
    echo "llvm2lcov failed"
    exit 1
fi

# should be valid data to generate HTML
$COVER $GENHTML_TOOL --flat --branch $MCDC_FLAG -o report test.info
if [ $? != 0 ] ; then
    echo "genhtml failed"
    exit 1
fi

# run again, excluding 'main.cpp'
$COVER $LLVM2LCOV_TOOL --branch $MCDC_FLAG -o test.excl.info test.json --exclude '*/main.cpp'
if [ $? != 0 ] ; then
    echo "llvm2lcov --exclude failed"
    exit 1
fi

# should be 3 functions
N=`grep -c "FNA:" test.info`
if [ 3 != "$N" ] ; then
    echo "wrong number of functions"
    exit 1
fi

# look for expected location and function hit counts:
for d in \
    'FNL:[0-9],20,25' \
    'FNA:[0-9],2,_Z3fooc' \
    'FNL:[0-9],27,72' \
    'FNA:[0-9],1,main' \
    'FNL:[0-9],2,4' \
    'FNA:[0-9],1,main.cpp:_ZL3barv' \
    ; do
    grep -E $d test.info
    if [ 0 != $? ] ; then
        echo "did not find expected function data $d"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

# lines main.cpp:(31-42) should be hit
for line in $(seq 31 42) ; \
    do \
    grep -E "DA:$line,1" test.info
    if [ 0 != $? ] ; then
        echo "did not find expected hit on function line $line"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

# lines main.cpp:14, 45-48 should be 'not hit
for line in 14 45 46 47 48 ; do
    grep "DA:$line,0" test.info
    if [ 0 != $? ] ; then
        echo "did not find expected zero hit on function line $line"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

# lines main.cpp:30, 43, 51, 65 should be 'not instrumented
for line in 30 43 51 65 ; do
    grep "DA:$line" test.info
    if [ 0 == $? ] ; then
        echo "find unexpected instrumented line $line"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

# check lines total number
grep -E "LF:55$" test.info
if [ $? != 0 ] ; then
    echo "unexpected total number of lines"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# check lines hit number
grep -E "LH:50$" test.info
if [ $? != 0 ] ; then
    echo "unexpected hit number of lines"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# check that branches have right <branch> expressions
line=41
N=`grep -c "BRDA:$line," test.info`
if [ 2 != "$N" ] ; then
    echo "did not find expected branches on line $line"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "BRDA:$line,0,(i <= 0) == True,1" test.info
if [ 0 != $? ] ; then
    echo "did not find expected 'BRDA' entry on line $line"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "BRDA:$line,0,(i <= 0) == False,0" test.info
if [ 0 != $? ] ; then
    echo "did not find expected 'BRDA' entry on line $line"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# check that branches defined inside macros are instrumented right
# lines main.cpp:33, 36, 39, 44 should contain branches defined inside macros
for line in 33 36 39 44 ; do
    grep -E "BRDA:$line," test.info
    if [ 0 != $? ] ; then
        echo "did not find expected branches on line $line"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

if [ "${LLVM_VER[0]}" -ge 16 ] ; then
    # check branches total number
    grep -E "BRF:56$" test.info
    if [ $? != 0 ] ; then
	echo "unexpected total number of branches"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
    # check branches hit number
    grep -E "BRH:35$" test.info
    if [ $? != 0 ] ; then
	echo "unexpected hit number of branches"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
fi

# LLVM/21 and later generate JSON data files in the new format.
# So, these files should be processed differently.
if [ "${LLVM_VER[0]}" -ge 21 ] ; then
    # line main.cpp:70 should contain 2 groups of MC/DC entries
    line=70
    MCDC_1=`grep -c "MCDC:$line,2," test.info`
    MCDC_2=`grep -c "MCDC:$line,3," test.info`
    if [ 4 != "$MCDC_1" ] || [ 6 != "$MCDC_2" ] ; then
        echo "did not find expected MC/DC entries on line $line"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    # check that MC/DC entries have right <expressions>
    N=`grep -c "MCDC:40,2,[tf],0,1,'i <= 0' in 'BOOL(i > 0) ||        i <= 0)'" test.info`
    if [ 2 != "$N" ] ; then
        echo "did not find expected MC/DC entries on line 40"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    # check MC/DC defined in macros
    grep -E "MCDC:" test.excl.info
    if [ 0 == $? ] ; then
        echo "find unexpected MC/DC"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    for line in 33 36 39 ; do
        grep -E "MCDC:$line,[23],[tf]" test.info
        if [ 0 != $? ] ; then
            echo "did not find expected MC/DC on line $line"
            if [ 0 == $KEEP_GOING ] ; then
                exit 1
            fi
        fi
    done
    # check MC/DC total number
    grep -E "MCF:40$" test.info
    if [ $? != 0 ] ; then
        echo "unexpected total number of MC/DC entries"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    # check MC/DC hit number
    grep -E "MCH:10$" test.info
    if [ $? != 0 ] ; then
        echo "unexpected hit number of MC/DC entries"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
elif [ "$ENABLE_MCDC" == "1" ] ; then
    # line main.cpp:70 should contain 2 groups of MC/DC entries
    line=70
    MCDC_1=`grep -c "MCDC:$line,2," test.info`
    MCDC_2=`grep -c "MCDC:$line,3," test.info`
    if [ 4 != "$MCDC_1" ] || [ 6 != "$MCDC_2" ] ; then
        echo "did not find expected MC/DC entries on line $line"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    # check that MC/DC entries have right <expressions>
    N=`grep -c "MCDC:63,2,[tf],1,1,'i < 1' in 'a\[i\] && i < 1'" test.info`
    if [ 2 != "$N" ] ; then
        echo "did not find expected MC/DC entries on line 63"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    # check MC/DC defined in macros
    grep -E "MCDC:6,3,[tf]" test.excl.info
    if [ 0 != $? ] ; then
        echo "did not find expected MC/DC"
        if [ 0 == $KEEP_GOING ] ; then
        exit 1
        fi
    fi
    for m in \
        "MCDC:6,2,[tf]" \
        "MCDC:15,2,[tf]" \
        ; do
        grep -E $m test.info
        if [ 0 != $? ] ; then
            echo "did not find expected MC/DC"
            if [ 0 == $KEEP_GOING ] ; then
            exit 1
            fi
        fi
    done
    # check MC/DC total number
    grep -E "MCF:34$" test.info
    if [ $? != 0 ] ; then
        echo "unexpected total number of MC/DC entries"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    # check MC/DC hit number
    grep -E "MCH:10$" test.info
    if [ $? != 0 ] ; then
        echo "unexpected hit number of MC/DC entries"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
fi

# generate help message
$COVER ${EXEC_COVER} $LLVM2LCOV_TOOL --help
if [ 0 != $? ] ; then
    echo "llvm2lcov help failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# incorrect option
$COVER ${EXEC_COVER} $LLVM2LCOV_TOOL --unsupported
$COVER $LLVM2LCOV_TOOL --unsupported -o test.info test.json
if [ 0 == $? ] ; then
    echo "did not see incorrect option"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover ${COVER_DB}
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB} --ignore-errors inconsistent
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch --ignore-errors inconsistent
fi
