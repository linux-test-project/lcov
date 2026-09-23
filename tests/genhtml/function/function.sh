#!/bin/bash
set +x

source ../../common.tst

rm -f test.cpp *.gcno *.gcda a.out *.info *.info.gz diff.txt diff_r.txt diff_broken.txt *.log *.err *.json dumper* results.xlsx *.diff *.txt template *gcov
rm -rf baseline_*call_current*call alias* no_alias* body.c body_base body_html shift.c shift_html

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
# '--ignore empty' for the same reason the captures above use it:  this source
#   has no branches in it, so the '--branch-coverage' asked for here finds no
#   coverpoints of that type and the read says so
DIFFCOV_OPTS="--filter line,branch,function --function-coverage --branch-coverage --demangle-cpp --frame --prefix $PARENT --version-script $GET_VERSION $PROFILE $PARALLEL --ignore empty"
#DIFFCOV_OPTS="--function-coverage --branch-coverage --demangle-cpp --frame"
#DIFFCOV_OPTS='--function-coverage --branch-coverage --demangle-cpp'


echo *

# $GCOV, not 'which gcov':  common.tst matched it to ${CC} - see there
echo $GCOV
echo `which lcov`

ln -s initial.cpp test.cpp
${CXX} --coverage -DCALL_FUNCTIONS test.cpp
./a.out


echo lcov $LCOV_OPTS --capture --directory . --output-file baseline_call.info --test-name myTest
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file baseline_call.info --test-name myTest --ignore empty
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
gzip -c baseline_call.info > baseline_call.info.gz

# run again - without version info:
echo lcov $LCOV_BASE --capture --directory . --output-file baseline_no_vers.info --test-name myTest
$COVER $LCOV_TOOL $LCOV_BASE --capture --directory . --output-file baseline_no_vers.info --test-name myTest --ignore empty
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

rm -f *.gcda *.gcno a.out

${CXX} --coverage test.cpp
./a.out

echo lcov $LCOV_OPTS --capture --directory . --output-file baseline_nocall.info --test-name myTest
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file baseline_nocall.info --test-name myTest --ignore empty
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (2) failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
gzip -c baseline_call.info > baseline_call.info.gz

export PWD=`pwd`
echo $PWD

rm -f test.cpp *.gcno *.gcda a.out
ln -s current.cpp test.cpp
${CXX} --coverage -DADD_CODE -DREMOVE_CODE -DCALL_FUNCTIONS test.cpp
./a.out
echo lcov $LCOV_OPTS --capture --directory . --output-file current_call.info
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file current_call.info --ignore empty
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (3) failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
gzip -c current_call.info > current_call.info.gz

rm -f *.gcda *.gcno a.out

${CXX} --coverage -DADD_CODE -DREMOVE_CODE test.cpp
./a.out
echo lcov $LCOV_OPTS --capture --directory . --output-file current_nocall.info
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file current_nocall.info --ignore empty
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (4) failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
gzip -c current_nocall.info > current_nocall.info.gz
rm -f *.gcda *.gcno

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
	# ignore version mismatch which might happen due to network delays
        echo genhtml -o $OUT $DIFFCOV_OPTS --baseline-file ${base}.info --diff-file diff.txt ${curr}.info --ignore inconsistent,version --save
        $COVER $GENHTML_TOOL -o $OUT $DIFFCOV_OPTS --baseline-file ${base}.info --diff-file diff.txt ${curr}.info --elide-path --ignore inconsistent,version --save
        if [ $? != 0 ] ; then
            echo "genhtml $OUT failed"
            if [ 0 == $KEEP_GOING ] ; then
                exit 1
            fi
        fi
        grep 'coverFn"' -A 1 $OUT/function/test.cpp.func.html > $OUT.txt

        diff -b $OUT.txt ${OUT}${SUFFIX}.gold | tee $OUT.diff

        if [ ${PIPESTATUS[0]} != 0 ] ; then
	    UPDATE=0
	    #UPDATE=1
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
$COVER $LCOV_TOOL $LCOV_OPTS --capture --demangle --directory . --output-file template.info --no-external --branch-coverage --test-name myTest --ignore empty
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
    $COVER $GENHTML_TOOL -o $outdir $opt $DIFFCOV_OPTS  template.info --show-proportion
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

# Whether a function body changed is decided by the diff:  a line of source
#   code inserted into the function, or deleted from it.  An unchanged line is
#   no change even if only one version has a coverpoint on it - 'f', whose
#   closing brace has one in the current data alone - and neither is an
#   inserted line which is not code - the comment in 'g'.  'h' has a line of
#   code inserted and 'k' one deleted.  A line of a multi-line statement is
#   code, though only the statement's first line has a coverpoint:  'm' has
#   one inserted and 'n' one deleted.  None of them is executed
mkdir -p body_base
cat > body_base/body.c <<'EOF'
int f(void)
{
  return 0;
}
int g(void)
{
  return 1;
}
int h(void)
{
  return 2;
}
int k(void)
{
  (void)0;
  return 3;
}
int m(void)
{
  return 4 +
         5;
}
int n(void)
{
  return 6 +
         7 +
         8;
}
EOF
cat > body.c <<'EOF'
int f(void)
{
  return 0;
}
int g(void)
{
  /* a comment */
  return 1;
}
int h(void)
{
  (void)0;
  return 2;
}
int k(void)
{
  return 3;
}
int m(void)
{
  return 4 +
         9 +
         5;
}
int n(void)
{
  return 6 +
         8;
}
EOF
BODY=`pwd`/body.c
diff -u body_base/body.c body.c | sed -e "s#^\(---\|+++\) [^\t]*#\1 $BODY#" > body_diff.txt
cat > body_base.info <<EOF
TN:
SF:$BODY
FNL:0,1,4
FNA:0,0,f
FNL:1,5,8
FNA:1,0,g
FNL:2,9,12
FNA:2,0,h
FNL:3,13,17
FNA:3,0,k
FNL:4,18,22
FNA:4,0,m
FNL:5,23,28
FNA:5,0,n
FNF:6
FNH:0
DA:1,0
DA:3,0
DA:5,0
DA:7,0
DA:9,0
DA:11,0
DA:13,0
DA:15,0
DA:16,0
DA:18,0
DA:20,0,,21
DA:23,0
DA:25,0,,27
LF:13
LH:0
end_of_record
EOF
cat > body_curr.info <<EOF
TN:
SF:$BODY
FNL:0,1,4
FNA:0,0,f
FNL:1,5,9
FNA:1,0,g
FNL:2,10,14
FNA:2,0,h
FNL:3,15,18
FNA:3,0,k
FNL:4,19,24
FNA:4,0,m
FNL:5,25,29
FNA:5,0,n
FNF:6
FNH:0
DA:1,0
DA:3,0
DA:4,0
DA:5,0
DA:8,0
DA:10,0
DA:12,0
DA:13,0
DA:15,0
DA:17,0
DA:19,0
DA:21,0,,23
DA:25,0
DA:27,0,,28
LF:14
LH:0
end_of_record
EOF
rm -rf body_html
$COVER $GENHTML_TOOL -o body_html --function-coverage -v \
    --baseline-file body_base.info --diff-file body_diff.txt body_curr.info \
    > body_html.log 2>&1
if [ 0 != $? ] ; then
    cat body_html.log
    echo "ERROR: genhtml body_html failed"
    exit 1
fi
for f in h k m n ; do
    if ! grep -q -E "(^|[^a-z_])$f body at $BODY:[0-9]+ is changed" body_html.log ; then
        echo "ERROR: expected '$f' body to be changed"
        BODY_FAIL=1
    fi
done
for f in f g ; do
    if grep -q -E "(^|[^a-z_])$f body at" body_html.log ; then
        echo "ERROR: expected '$f' body not to be changed"
        BODY_FAIL=1
    fi
done
if ! grep -q '^    function: UNC:4 UBC:2$' body_html.log ; then
    echo "ERROR: expected 'function: UNC:4 UBC:2'"
    BODY_FAIL=1
fi
if [ -n "$BODY_FAIL" ] && [ 0 == $KEEP_GOING ] ; then
    exit 1
fi

# The two versions are the same source, but the baseline data puts each
#   function start on its return type line and the current data on its
#   declarator line - as two compilers may.  'r' and 's' are paired with
#   the baseline function of the same name:  CBC and UBC.  'u' and 't' have
#   no name in common, so they stay a deleted and an added function.  No
#   function start line has a line coverpoint
cat > shift.c <<'EOF'
int
r(void)
{
  return 0;
}
int
s(void)
{
  return 1;
}
int
t(void)
{
  return 2;
}
EOF
SHIFT=`pwd`/shift.c
: > shift_diff.txt
cat > shift_base.info <<EOF
TN:
SF:$SHIFT
FNL:0,1,5
FNA:0,3,r
FNL:1,6,10
FNA:1,0,s
FNL:2,11,15
FNA:2,0,u
FNF:3
FNH:1
DA:4,3
DA:9,0
DA:14,0
LF:3
LH:1
end_of_record
EOF
sed -e 's/^FNL:0,1,/FNL:0,2,/' -e 's/^FNL:1,6,/FNL:1,7,/' \
    -e 's/^FNL:2,11,/FNL:2,12,/' -e 's/,u$/,t/' shift_base.info > shift_curr.info
rm -rf shift_html
$COVER $GENHTML_TOOL -o shift_html --function-coverage -v --ignore empty \
    --baseline-file shift_base.info --diff-file shift_diff.txt \
    shift_curr.info > shift_html.log 2>&1
if [ 0 != $? ] ; then
    cat shift_html.log
    echo "ERROR: genhtml shift_html failed"
    exit 1
fi
for f in 'r .*:1 is paired with the function at line 2' \
         's .*:6 is paired with the function at line 7' \
         '^    function: UIC:1 UBC:1 CBC:1 EUB:1$' ; do
    if ! grep -q -E "$f" shift_html.log ; then
        echo "ERROR: expected '$f'"
        SHIFT_FAIL=1
    fi
done
if grep -q 'u .*is paired' shift_html.log ; then
    echo "ERROR: expected 'u' not to be paired"
    SHIFT_FAIL=1
fi
if [ -n "$SHIFT_FAIL" ] && [ 0 == $KEEP_GOING ] ; then
    exit 1
fi


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
