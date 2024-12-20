#!/bin/bash
set +x

source ../../common.tst

#PARALLEL=''
#PROFILE="''

rm -f *.cpp *.gcno *.gcda a.out *.info *.log *.json dumper* *.annotated annotate.sh
rm -rf ./vanilla ./annotated ./annotateErr ./annotated2 ./annotateErr2 ./range ./filter ./cover_db annotated_nofunc

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type "${CXX}" >/dev/null 2>&1 ; then
        echo "Missing tool: $CXX" >&2
        exit 2
fi

LCOV_OPTS="$EXTRA_GCOV_OPTS --branch-coverage $PARALLEL $PROFILE"
DIFFCOV_OPTS="--function-coverage --branch-coverage --demangle-cpp --frame --prefix $PARENT $PROFILE $PARALLEL"


echo *

# filename was all upper case
ln -s ../simple/simple2.cpp test.cpp
ln -s ../simple/simple2.cpp.annotated test.cpp.annotated
ln -s ../simple/annotate.sh .

${CXX} --coverage test.cpp
./a.out

echo `which gcov`
echo `which lcov`

# old gcc version generates inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
fi

echo lcov $LCOV_OPTS --capture --directory . --output-file current.info --no-external $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file current.info --no-external $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# add an out-of-range line to the coverage data
perl munge.pl current.info > munged.info
# remove a line which has a branch:  create branch with no corresponding line
#   LLVM seems to generate this kind of inconsistent data, at times
perl munge2.pl current.info > munged2.info

echo genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all -o annotateErr ./munged.info
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all -o annotateErr ./munged.info 2>&1 | tee err.log
if [ 0 == ${[PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml did not return error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "ERROR.*? contains only .+? lines but coverage data refers to line" err.log
if [ 0 != $? ] ; then
    echo "did not find expected range error message in err.log"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all -o annotated --ignore range ./munged.info
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all -o annotated ./munged.info --ignore range 2>&1 | tee annotate.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml annotated failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# expect to see generated function labels
for label in 'BEGIN' 'END' ; do
    grep -E "$label: function .+outOfRangeFnc" annotated/synthesize/test.cpp.gcov.html
    if [ 0 != $? ] ; then
        echo "ERROR: genhtml didn't generate function $label label"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

echo genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all -o annotated_nofunc --no-function-coverage --ignore range ./munged.info
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all -o annotated_nofunc --no-function-coverage ./munged.info --ignore range 2>&1 | tee annotate.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml annotated_nofunc failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# should not be generated..
grep -E "function .+outOfRangeFnc" annotated_nofunc/synthesize/test.cpp.gcov.html
if [ 0 == $? ] ; then
    echo "ERROR: genhtml should not have generated function label"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo genhtml $DIFFCOV_OPTS -o vanilla --ignore range ./munged.info
$COVER $GENHTML_TOOL $DIFFCOV_OPTS -o vanilla --ignore range ./munged.info  2>&1 | tee vanilla.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml vanilla failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

for log in annotate.log vanilla.log ; do
   grep -E "WARNING.*? contains only .+? lines but coverage data refers to line" $log
   if [ 0 != $? ] ; then
       echo "did not find expected synthesize warning message in log"
       if [ 0 == $KEEP_GOING ] ; then
           exit 1
       fi
   fi
done

for dir in annotated vanilla ; do
   grep -E "not long enough" $dir/synthesize/test.cpp.gcov.html
   if [ 0 != $? ] ; then
       echo "did not find expected synthesize warning message in HTML"
       if [ 0 == $KEEP_GOING ] ; then
           exit 1
       fi
   fi
done

echo genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all -o annotateErr2 ./munged2.info
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all -o annotateErr2 ./munged2.info 2>&1 | tee err2.log
if [ 0 == ${[PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml did not return error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "ERROR.*? has branchcov but no linecov data" err2.log
if [ 0 != $? ] ; then
    echo "did not find expected inconsistent error message in err2.log"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all -o annotated2 --ignore inconsistent ./munged2.info
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all -o annotated2 ./munged2.info --ignore inconsistent 2>&1 | tee annotate2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml annotated failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "WARNING.*? has branchcov but no linecov data" annotate2.log
if [ 0 != $? ] ; then
    echo "did not find expected inconsistent error message in annotate2.log"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo lcov $LCOV_OPTS --ignore range -o range.info -a ./munged.info --filter branch
$COVER $LCOV_TOOL $LCOV_OPTS  --ignore range -o range.info -a ./munged.info --filter branch 2>&1 | tee range.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --ignore range failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
COUNT1=`grep -c -i "warning: .*range.* unknown.* line .* there are only" range.log`
if [ 1 != $COUNT1 ] ; then
    echo "Missing expected warning: expected 1 found $COUNT1"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo lcov $LCOV_OPTS --ignore range -o range.info -a ./munged.info --filter branch --rc warn_once_per_file=0
$COVER $LCOV_TOOL $LCOV_OPTS  --ignore range -o range.info -a ./munged.info --filter branch --rc warn_once_per_file=0 --comment 'insert a comment' 2>&1 | tee range2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --ignore range2 failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
COUNT2=`grep -c -i "warning: .*range.* unknown.* line .* there are only" range2.log`
if [ 2 != $COUNT2 ] ; then
    echo "Expected 2 messages found $COUNT2"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo lcov $LCOV_OPTS -o filter.info --filter range -a ./munged.info --filter branch
$COVER $LCOV_TOOL $LCOV_OPTS -o filter.info --filter range -a ./munged.info --filter branch 2>&1 | tee filter.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --filter range failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -i "warning: .*range.* unknown line .* there are only" filter.log
if [ 0 == $? ] ; then
    echo "Found unexpected warning"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo "Tests passed"

if [ "x$COVER" != "x" ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover $COVER_DB
    $PERL2LCOV_TOOL -o perlcov.info $COVER_DB
    $GENHTML_TOOL -o coverage perlcov.info
fi
