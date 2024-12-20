#!/bin/bash
set +x

source ../../common.tst

rm -f test.cpp *.gcno *.gcda a.out *.info *.info.gz diff.txt diff_r.txt diff_broken.txt *.log *.err *.json dumper* results.xlsx *.diff *.txt template *gcov
rm -rf baseline_*call_current*call alias* no_alias*

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type "${CXX}" >/dev/null 2>&1 ; then
        echo "Missing tool: $CXX" >&2
        exit 2
fi

if ! python3 -c "import xlsxwriter" >/dev/null 2>&1 ; then
        echo "Missing python module: xlsxwriter" >&2
        exit 2
fi

#PARALLEL=''
#PROFILE="''

# filter out the compiler-generated _GLOBAL__sub_... symbol
LCOV_BASE="$EXTRA_GCOV_OPTS --branch-coverage $PARALLEL $PROFILE --no-external --ignore unused,unsupported --erase-function .*GLOBAL.*"
VERSION_OPTS="--version-script $GET_VERSION"
LCOV_OPTS="$LCOV_BASE $VERSION_OPTS"
DIFFCOV_OPTS="--filter line,branch,function --function-coverage --branch-coverage --demangle-cpp --frame --prefix $PARENT --version-script $GET_VERSION $PROFILE $PARALLEL"
#DIFFCOV_OPTS="--function-coverage --branch-coverage --demangle-cpp --frame"
#DIFFCOV_OPTS='--function-coverage --branch-coverage --demangle-cpp'


echo *

echo `which gcov`
echo `which lcov`

ln -s initial.cpp test.cpp
${CXX} --coverage -DCALL_FUNCTIONS test.cpp
./a.out


echo lcov $LCOV_OPTS --capture --directory . --output-file baseline_call.info --test-name myTest
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file baseline_call.info --test-name myTest
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
gzip -c baseline_call.info > baseline_call.info.gz

# run again - without version info:
echo lcov $LCOV_BASE --capture --directory . --output-file baseline_no_vers.info --test-name myTest
$COVER $LCOV_TOOL $LCOV_BASE --capture --directory . --output-file baseline_no_vers.info --test-name myTest
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture no version failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep VER: baseline_no_vers.info
if [ 0 == $? ] ; then
    echo "ERROR: lcov contains version info"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# insert the version info
echo lcov $VERSION_OPTS --rc compute_file_version=1 --add-tracefile baseline_no_vers.info --output-file baseline_vers.info
$COVER $LCOV_TOOL $VERSION_OPTS --rc compute_file_version=1 --add-tracefile baseline_no_vers.info --output-file baseline_vers.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov insert version failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
diff baseline_vers.info baseline_call.info
if [ 0 != $? ] ; then
    echo "ERROR: data differs after version insert"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

rm -f test.gcno test.gcda a.out

${CXX} --coverage test.cpp
./a.out

echo lcov $LCOV_OPTS --capture --directory . --output-file baseline_nocall.info --test-name myTest
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file baseline_nocall.info --test-name myTest
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (2) failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
gzip -c baseline_call.info > baseline_call.info.gz

export PWD=`pwd`
echo $PWD

rm -f test.cpp test.gcno test.gcda a.out
ln -s current.cpp test.cpp
${CXX} --coverage -DADD_CODE -DREMOVE_CODE -DCALL_FUNCTIONS test.cpp
./a.out
echo lcov $LCOV_OPTS --capture --directory . --output-file current_call.info
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file current_call.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (3) failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
gzip -c current_call.info > current_call.info.gz

rm -f test.gcno test.gcda a.out
${CXX} --coverage -DADD_CODE -DREMOVE_CODE test.cpp
./a.out
echo lcov $LCOV_OPTS --capture --directory . --output-file current_nocall.info
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file current_nocall.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (4) failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
gzip -c current_nocall.info > current_nocall.info.gz


diff -u initial.cpp current.cpp | perl -pi -e "s#(initial|current)*\.cpp#$ROOT/test.cpp#g" > diff.txt

if [ $? != 0 ] ; then
    echo "diff failed"
    exit 1
fi

#check for end line markers - if present then check for whole-function
#categorization
grep -E 'FNL:[0-9]+,[0-9]+,[0-9]+' baseline_call.info
NO_END_LINE=$?

if [ $NO_END_LINE == 0 ] ; then
    echo "----------------------"
    echo "   compiler version support start/end reporting"
    SUFFIX='_region'
else
    echo "----------------------"
    echo "   compiler version DOES NOT support start/end reporting"
    SUFFIX=''
fi

for base in baseline_call baseline_nocall ; do
    for curr in current_call current_nocall ; do
        OUT=${base}_${curr}
        echo genhtml -o $OUT $DIFFCOV_OPTS --baseline-file ${base}.info --diff-file diff.txt ${curr}.info --ignore inconsistent
        $COVER $GENHTML_TOOL -o $OUT $DIFFCOV_OPTS --baseline-file ${base}.info --diff-file diff.txt ${curr}.info --elide-path --ignore inconsistent
        if [ $? != 0 ] ; then
            echo "genhtml $OUT failed"
            if [ 0 == $KEEP_GOING ] ; then
                exit 1
            fi
        fi
        grep 'coverFn"' -A 1 $OUT/function/test.cpp.func.html > $OUT.txt

        diff -b $OUT.txt ${OUT}${SUFFIX}.gold | tee $OUT.diff

        if [ ${PIPESTATUS[0]} != 0 ] ; then
            if [ $UPDATE != 0 ] ; then
                echo "update $out"
                cp $OUT.txt ${OUT}${SUFFIX}.gold
            else
                echo "diff $OUT failed - see $OUT.diff"
                exit 1
            fi
        else
            rm $OUT.diff
        fi
    done
done

# test function alias suppression
rm *.gcda *.gcno
${CXX} --coverage -std=c++11 -o template template.cpp
./template
echo lcov $LCOV_OPTS --capture --directory . --demangle --output-file template.info --no-external --branch-coverage --test-name myTest
$COVER $LCOV_TOOL $LCOV_OPTS --capture --demangle --directory . --output-file template.info --no-external --branch-coverage --test-name myTest
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
COUNT=`grep -c FNA: template.info`
if [ 4 != $COUNT ] ; then
    echo "ERROR: expected 4 FNA - found $COUNT"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

for opt in '' '--forget-test-names' ; do
    outdir="alias$opt"
    echo genhtml -o $outdir $opt $DIFFCOV_OPTS template.info --show-proportion
    $COVER $GENHTML_TOOL -o $outdir $pt $DIFFCOV_OPTS  template.info --show-proportion
    if [ $? != 0 ] ; then
        echo "genhtml $outdir failed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    #expect 5 entries in 'func' list (main, leader, 3 aliases
    COUNT=`grep -c 'coverFnAlias"' $outdir/function/template.cpp.func.html`
    if [ 3 != $COUNT ] ; then
        echo "ERROR: expected 3 aliases - found $COUNT"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    outdir="no_alias$opt"
    # suppress aliases
    echo genhtml -o $outdir $opt $DIFFCOV_OPTS template.info --show-proportion --suppress-alias
    $COVER $GENHTML_TOOL -o $outdir $opt $DIFFCOV_OPTS  template.info --show-proportion --suppress-alias
    if [ $? != 0 ] ; then
        echo "genhtml $outdir failed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    #expect 2 entries in 'func' list
    COUNT=`grep -c 'coverFn"' $outdir/function/template.cpp.func.html`
    if [ 2 != $COUNT ] ; then
        echo "ERROR: expected 2 functions - found $COUNT"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    COUNT=`grep -c 'coverFnAlias"' $outdir/function/template.cpp.func.html`
    if [ 0 != $COUNT ] ; then
        echo "ERROR: expected zero aliases - found $COUNT"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done


# and generate a spreadsheet..check that we don't crash
SPREADSHEET=$LCOV_HOME/scripts/spreadsheet.py
if [ ! -f $SPREADSHEET ] ; then
    SPREADSHEET=$LCOV_HOME/share/lcov/support-scripts/spreadsheet.py
fi
if [ -f $SPREADSHEET ] ; then
    $SPREADSHEET -o results.xlsx `find . -name "*.json"`
    if [ 0 != $? ] ; then
        echo "ERROR:  spreadsheet generation failed"
        exit 1
    fi
else
    echo "Did not find $SPREADSHEET to run test"
    exit 1
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover
fi
