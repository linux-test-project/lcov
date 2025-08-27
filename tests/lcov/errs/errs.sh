#!/bin/bash
set +x

source ../../common.tst

rm -f  *.log *.json dumper* *.out
rm -rf emptyDir

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

LCOV_OPTS="--branch $PARALLEL $PROFILE"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
    # and filter exception branches to avoid spurious differences for old compiler
    FILTER='--filter branch'
fi

status=0

for f in badFncLine badFncEndLine fncMismatch badBranchLine badLine ; do
    echo lcov $LCOV_OPTS --summary $f.info
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info 2>&1 | tee $f.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "failed to notice incorrect decl in $f"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    grep -E '(unexpected|mismatched) .*line' $f.log
    if [ 0 != $? ] ; then
        echo "missing error message"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi

    echo lcov $LCOV_OPTS --summary $f.info --ignore inconsistent,format
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info --ignore format,inconsistent 2>&1 | tee ${f}2.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "failed to ignore message ${f}2.log"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    # and print the data out again..
    echo lcov $LCOV_OPTS -o $f.out -a $f.info --ignore format,inconsistent
    $COVER $LCOV_TOOL $LCOV_OPTS -o $f.out -a $f.info --ignore format,inconsistent --msg-log $f{3}.log
    if [ 0 != $? ] ; then
        echo "failed to ignore message ${f}3.log"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi

done

for f in noFunc ; do
    echo lcov $LCOV_OPTS --summary $f.info
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info 2>&1 | tee $f.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "failed to notice incorrect decl in $f"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    grep -E 'unknown function' $f.log
    if [ 0 != $? ] ; then
        echo "missing error message"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi

    echo lcov $LCOV_OPTS --summary $f.info --ignore mismatch
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info --ignore mismatch 2>&1 | tee ${f}2.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "failed to ignore message ${f}2.log"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
done

for f in emptyFileRecord ; do
    echo lcov $LCOV_OPTS --summary $f.info
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info 2>&1 | tee $f.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "failed to notice incorrect decl in $f"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    grep -E 'unexpected empty file name' $f.log
    if [ 0 != $? ] ; then
        echo "missing error message"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi

    echo lcov $LCOV_OPTS --summary $f.info --ignore mismatch
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info --ignore format 2>&1 | tee ${f}2.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "failed to ignore message ${f}2.log"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
done


for f in exceptionBranch ; do
    echo lcov $LCOV_OPTS -a ${f}1.info -a ${f}2.info -o $f.out
    $COVER $LCOV_TOOL $LCOV_OPTS -a ${f}1.info -a ${f}2.info -o $f.out 2>&1 | tee $f.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "failed to notice incorrect decl in $f"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    grep -E 'mismatched exception tag' $f.log
    if [ 0 != $? ] ; then
        echo "missing error message"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    if [ -f $f.out ] ; then
        echo "should not have created file, on error"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi

    echo lcov $LCOV_OPTS -a ${f}1.info -a ${f}2.info --ignore mismatch -o ${f}2.log
    $COVER $LCOV_TOOL $LCOV_OPTS -a ${f}1.info -a ${f}2.info --ignore mismatch -o $f.log

    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "failed to ignore message ${f}2.log"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
done

mkdir -p emptyDir

echo lcov $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info
$COVER $LCOV_TOOL $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info 2>&1 | tee emptyDir.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "failed to notice empty dir"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit $status
    fi
fi
grep 'no files matching' emptyDir.log
if [ 0 != $? ] ; then
    echo "did not find expected empty dir message"
fi
echo lcov $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info --ignore empty
$COVER $LCOV_TOOL $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info --ignore empty 2>&1 | tee emptyDir2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "failed to ignore empty dir"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit $status
    fi
fi

# trigger error from unreadable directory
chmod ugo-rx emptyDir
echo lcov $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info
$COVER $LCOV_TOOL $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info 2>&1 | tee noRead.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "failed to notice unreadable"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit $status
    fi
fi
grep 'error in "find' noRead.log
if [ 0 != $? ] ; then
    echo "did not find expected unreadable dir message"
fi
echo lcov $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info --ignore utility,empty
$COVER $LCOV_TOOL $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info --ignore utility,empty 2>&1 | tee noRead2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "failed to ignore unreadable dir"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit $status
    fi
fi
chmod ugo+rx emptyDir

# data consistency errors:
#  - function marked 'hit' but no contained lines are hit
#  - function marked 'not hit' but some contained line is hit
#  - line marked 'hit' but no contained branches have been evaluated
#  - line marked 'not hit' but at least one contained branch has been evaluated
for i in funcNoLine lineNoFunc branchNoLine lineNoBranch ; do

    $COVER $LCOV_TOOL $LCOV_OPTS --summary $i.info 2>&1 | tee $i.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "failed to see error ${i}.log"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $i.info 2>&1 --ignore inconsistent | tee ${i}2.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "failed to ignore error ${i}2.log"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
done


if [ 0 == $status ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi

exit $status
