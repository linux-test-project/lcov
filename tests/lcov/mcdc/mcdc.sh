#! /usr/bin/env bash

source ../../common.tst

rm -rf *.xml *.dat *.info *.jsn cover_one *_rpt *Test[123]* *.gcno *.gcda gccTest* llvmTest* twoTc*.log

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

# the fixtures below are C++, so it is ${CXX} which decides what they can be
# built with - and ${CXX} which the gcov capturing them has to match.  Asking
# ${CC} is close enough when both come from one 'module load' and wrong as soon
# as they do not.
IFS='.' read -r -a VER <<< `${CXX} -dumpversion`
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
    echo "clang++ -fprofile-instr-generate -fcoverage-mapping -fcoverage-mcdc -o $1 main.cpp test.cpp $2"
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
    echo "${CXX} --coverage -fcondition-coverage -o $NAME main.cpp test.cpp" \
         "$ARG"
    # runGcc exeName srcFile flags
    eval ${CXX} --coverage -fcondition-coverage -o $NAME main.cpp test.cpp $ARG
    if [ $? != 0 ] ; then
        echo "ERROR from ${CXX} $NAME"
        return 1
    fi
    ./$NAME
    echo "$GENINFO_TOOL -o $NAME.info --mcdc --branch $NAME-test.gcda $@"
    $COVER $GENINFO_TOOL -o $NAME.info --mcdc --branch $NAME-test.gcda $@ --ignore empty
    if [ $? != 0 ] ; then
        echo "ERROR from geninfo $NAME"
        return 1
    fi
    $COVER $GENHTML_TOOL --flat --branch --mcdc -o ${NAME}_rpt $NAME.info --ignore empty
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

#
# Two testcases carrying MC/DC data on the SAME line of the same file.
#
# Each emitted per-testcase MCDC: record must report that testcase's own count.
# This used to be wrong: the reader accumulated MC/DC records directly into the
# summary map and then deep-copied the summary into the per-testcase map, so the
# second (and every later) testcase was emitted with the running total instead
# of its own contribution -- e.g. 'tc2' reported 15 rather than 5.  The branch
# reader has always avoided this by accumulating into a scratch map; MC/DC now
# does the same.  Input is written here rather than captured from a compiler so
# the check runs regardless of MC/DC compiler support.
#
# Group 0 is tagged 'U' (unreachable/excluded) to also cover counting excluded
# senses: MCF/MCH must not include them.

cat > twoTc.info <<'EOF'
TN:tc1
SF:mcdcTwoTc.c
DA:10,5
DA:20,7
MCDC:10,U2,t,5,0,a&&b
MCDC:10,U2,f,0,0,a&&b
MCDC:10,2,t,3,1,a&&b
MCDC:10,2,f,1,1,a&&b
MCDC:20,2,t,7,0,c||d
MCDC:20,2,f,0,0,c||d
LF:2
LH:2
end_of_record
TN:tc2
SF:mcdcTwoTc.c
DA:10,5
DA:20,7
MCDC:10,U2,t,5,0,a&&b
MCDC:10,U2,f,0,0,a&&b
MCDC:10,2,t,3,1,a&&b
MCDC:10,2,f,1,1,a&&b
MCDC:20,2,t,7,0,c||d
MCDC:20,2,f,0,0,c||d
LF:2
LH:2
end_of_record
EOF

# 'mcdcTwoTc.c' does not exist on disk - we only care about the .info data
MCDC_IGNORE="--ignore source,inconsistent,unused,empty"

echo "$LCOV_TOOL -a twoTc.info -o twoTcOut.info --mcdc"
$COVER $LCOV_TOOL -a twoTc.info -o twoTcOut.info --mcdc $MCDC_IGNORE
if [ $? != 0 ] ; then
    echo "ERROR: lcov -a failed for the two-testcase MC/DC case"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# both testcases had identical input, so both sections must round-trip
#  unchanged - counts 5/3/1/7, NOT doubled
for TC in tc1 tc2 ; do
    SECTION=`awk -v tc="TN:$TC" '$0 == tc {p=1} p {print} /^end_of_record/ && p {exit}' twoTcOut.info`
    for EXPECT in 'MCDC:10,U2,t,5,0,a&&b' 'MCDC:10,U2,f,0,0,a&&b' \
                  'MCDC:10,2,t,3,1,a&&b'  'MCDC:10,2,f,1,1,a&&b'  \
                  'MCDC:20,2,t,7,0,c||d'  'MCDC:20,2,f,0,0,c||d' ; do
        echo "$SECTION" | grep -qxF "$EXPECT"
        if [ $? != 0 ] ; then
            echo "ERROR: testcase '$TC' is missing expected record '$EXPECT':"
            echo "$SECTION"
            STATUS=1
            if [ $KEEP_GOING == 0 ] ; then
                exit 1
            fi
        fi
    done
    # The MCF/MCH written into a section count every sense, excluded ones
    #  included - so all 6 senses here, 4 of them hit.  (The *summary* counts,
    #  checked below, do skip excluded senses.)
    for EXPECT in 'MCF:6' 'MCH:4' ; do
        echo "$SECTION" | grep -qxF "$EXPECT"
        if [ $? != 0 ] ; then
            echo "ERROR: testcase '$TC' is missing '$EXPECT':"
            echo "$SECTION"
            STATUS=1
            if [ $KEEP_GOING == 0 ] ; then
                exit 1
            fi
        fi
    done
done

# The summary counts come from MCDC_Block::totals(), which does NOT count
#  excluded senses: 6 senses - 2 excluded = 4 conditions, 3 of them hit.
echo "$LCOV_TOOL --summary twoTc.info --mcdc"
$COVER $LCOV_TOOL --summary twoTc.info --mcdc $MCDC_IGNORE 2>&1 | \
    tee twoTcSummary.log
grep -q '3 of 4 conditions' twoTcSummary.log
if [ $? != 0 ] ; then
    echo "ERROR: wrong summary condition count (excluded senses counted?)"
    cat twoTcSummary.log
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# --forget-test-names collapses both sections onto the empty testname, so the
#  two contributions legitimately DO accumulate: 5+5, 3+3, 1+1, 7+7
echo "$LCOV_TOOL -a twoTc.info -o twoTcMerged.info --mcdc --forget-test-names"
$COVER $LCOV_TOOL -a twoTc.info -o twoTcMerged.info --mcdc --forget-test-names \
    $MCDC_IGNORE
if [ $? != 0 ] ; then
    echo "ERROR: lcov -a --forget-test-names failed"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
COUNT=`grep -c '^TN:' twoTcMerged.info`
if [ 1 != "$COUNT" ] ; then
    echo "ERROR: expected a single testcase after --forget-test-names, got $COUNT"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for EXPECT in 'MCDC:10,U2,t,10,0,a&&b' 'MCDC:10,2,t,6,1,a&&b' \
              'MCDC:10,2,f,2,1,a&&b'   'MCDC:20,2,t,14,0,c||d' ; do
    grep -qxF "$EXPECT" twoTcMerged.info
    if [ $? != 0 ] ; then
        echo "ERROR: --forget-test-names output is missing '$EXPECT':"
        cat twoTcMerged.info
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

# Two testcases on DISJOINT MC/DC lines - correct before the fix, must stay so.
cat > twoTcDisjoint.info <<'EOF'
TN:tc1
SF:mcdcTwoTc.c
DA:10,5
MCDC:10,2,t,5,0,a&&b
MCDC:10,2,f,0,0,a&&b
LF:1
LH:1
end_of_record
TN:tc2
SF:mcdcTwoTc.c
DA:20,7
MCDC:20,2,t,7,0,c||d
MCDC:20,2,f,0,0,c||d
LF:1
LH:1
end_of_record
EOF

echo "$LCOV_TOOL -a twoTcDisjoint.info -o twoTcDisjointOut.info --mcdc"
$COVER $LCOV_TOOL -a twoTcDisjoint.info -o twoTcDisjointOut.info --mcdc \
    $MCDC_IGNORE
if [ $? != 0 ] ; then
    echo "ERROR: lcov -a failed for the disjoint-line MC/DC case"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for EXPECT in 'MCDC:10,2,t,5,0,a&&b' 'MCDC:20,2,t,7,0,c||d' ; do
    COUNT=`grep -cxF "$EXPECT" twoTcDisjointOut.info`
    # once in its own testcase section - and nowhere else
    if [ 1 != "$COUNT" ] ; then
        echo "ERROR: expected exactly one '$EXPECT' in the disjoint output, got $COUNT"
        cat twoTcDisjointOut.info
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

# A line whose MC/DC records are REVISITED later in the same section - the
#  records for line 10 are interrupted by line 20 and then resume.  The reader
#  must land back in the same block (so insertExpr checks consistency and the
#  counts accumulate once), rather than starting a second block for the line.
cat > twoTcRevisit.info <<'EOF'
TN:tc1
SF:mcdcTwoTc.c
DA:10,5
DA:20,7
MCDC:10,2,t,5,0,a&&b
MCDC:10,2,f,0,0,a&&b
MCDC:10,2,t,3,1,a&&b
MCDC:10,2,f,1,1,a&&b
MCDC:20,2,t,7,0,c||d
MCDC:20,2,f,0,0,c||d
MCDC:10,2,t,2,0,a&&b
MCDC:10,2,f,1,0,a&&b
LF:2
LH:2
end_of_record
EOF

echo "$LCOV_TOOL -a twoTcRevisit.info -o twoTcRevisitOut.info --mcdc"
$COVER $LCOV_TOOL -a twoTcRevisit.info -o twoTcRevisitOut.info --mcdc \
    $MCDC_IGNORE
if [ $? != 0 ] ; then
    echo "ERROR: lcov -a failed for the revisited-line MC/DC case"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# index 0 accumulates 5+2 and 0+1; index 1 is seen once, so it keeps 3/1
for EXPECT in 'MCDC:10,2,t,7,0,a&&b' 'MCDC:10,2,f,1,0,a&&b' \
              'MCDC:10,2,t,3,1,a&&b' 'MCDC:10,2,f,1,1,a&&b' \
              'MCDC:20,2,t,7,0,c||d' 'MCF:6' 'MCH:5' ; do
    grep -qxF "$EXPECT" twoTcRevisitOut.info
    if [ $? != 0 ] ; then
        echo "ERROR: revisited-line output is missing '$EXPECT':"
        cat twoTcRevisitOut.info
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

# Same shape, but the revisit changes the expression text - the consistency
#  check in insertExpr must still fire.
sed 's/,a&&b$/,x\&\&y/' twoTcRevisit.info | \
    sed '5,8s/,x&&y$/,a\&\&b/' > twoTcMismatch.info
echo "$LCOV_TOOL -a twoTcMismatch.info -o twoTcMismatchOut.info --mcdc"
$COVER $LCOV_TOOL -a twoTcMismatch.info -o twoTcMismatchOut.info --mcdc \
    --ignore source,unused,empty 2>&1 | tee twoTcMismatch.log
grep -q "MC/DC group 2 expression 0 changed from 'a&&b' to 'x&&y'" \
    twoTcMismatch.log
if [ $? != 0 ] ; then
    echo "ERROR: expected an inconsistent-expression message for the revisit"
    cat twoTcMismatch.log
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
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
