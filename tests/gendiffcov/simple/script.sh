#!/bin/sh
set +x

CLEAN_ONLY=0
LCOV_HOME=

while [ $# -gt 0 ] ; do

    OPT=$1
    shift
    case $OPT in

        --clean | clean )
            CLEAN_ONLY=1
            ;;

        -v | --verbose | verbose )
            set -x
            ;;
        
        --home | home )
            LCOV_HOME=$1
            shift
            if [ ! -f $LCOV_HOME/bin/lcov ] ; then
                echo "LCOV_HOME '$LCOV_HOME' does not exist"
                exit 1
            fi
            ;;
        
        * )
            echo "Error: unexpected option '$OPT'"
            exit 1
            ;;
    esac
done

if [[ "x" == ${LCOV_HOME}x ]] ; then 
       if [ -f ../../../bin/lcov ] ; then
           LCOV_HOME=../../..
       else
           LCOV_HOME=../../../../releng/coverage/lcov
       fi
fi

export PATH=${LCOV_HOME}/bin:${LCOV_HOME}/share:${PATH}
export MANPATH=${MANPATH}:${LCOV_HOME}/man

ROOT=`pwd`

LCOV_OPTS='--rc lcov_branch_coverage=1'
DIFFCOV_OPTS='--function-coverage --branch-coverage --highlight --demangle-cpp --frame --show-details'
#DIFFCOV_OPTS='--function-coverage --branch-coverage --highlight --demangle-cpp'

rm -f test.cpp test.gcno test.gcda a.out *.info *.info.gz diff.txt diff_r.txt 
rm -rf ./baseline ./current ./differential ./reverse ./no_baseline ./no_annotation ./no_owners differential_nobranch reverse_nobranch baseline-filter noncode_differential

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

echo *

ln -s simple.cpp test.cpp
g++ --coverage test.cpp
./a.out

lcov $LCOV_OPTS --capture --directory . --output-file baseline.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    exit 1
fi
gzip -c baseline.info > baseline.info.gz

lcov --capture --directory . --output-file baseline_nobranch.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (2) failed"
    exit 1
fi
gzip -c baseline_nobranch.info > baseline_nobranch.info.gz
#genhtml baseline.info --output-directory ./baseline
gendiffcov $DIFFCOV_OPTS baseline.info --output-directory ./baseline
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov baseline failed"
    exit 1
fi

lcov $LCOV_OPTS --filter branch,line --capture --directory . --output-file baseline-filter.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (3) failed"
    exit 1
fi
gzip -c baseline-filter.info > baseline-filter.info.gz
#genhtml baseline.info --output-directory ./baseline
gendiffcov $DIFFCOV_OPTS baseline-filter.info --output-directory ./baseline-filter
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov baseline-filter failed"
    exit 1
fi

export PWD=`pwd`
echo $PWD

rm -f test.cpp test.gcno test.gcda a.out
ln -s simple2.cpp test.cpp
g++ --coverage -DADD_CODE -DREMOVE_CODE test.cpp
./a.out
lcov $LCOV_OPTS --capture --directory . --output-file current.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (4) failed"
    exit 1
fi
gzip -c current.info > current.info.gz

#genhtml current.info --output-directory ./current
gendiffcov $DIFFCOV_OPTS current.info --output-directory ./current
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov current failed"
    exit 1
fi

diff -u simple.cpp simple2.cpp | sed -e "s|simple2*\.cpp|$ROOT/test.cpp|g" > diff.txt

${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors source -o ./noncode_differential ./current.info.gz
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov noncode_differential failed"
    exit 1
fi

${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source -o ./differential ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov differential failed"
    exit 1
fi

${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline_nobranch.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source -o ./differential_nobranch ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov differential_nobranch failed"
    exit 1
fi

# and the inverse difference
diff -u simple2.cpp simple.cpp | sed -e "s|simple2*\.cpp|$ROOT/test.cpp|g" > diff_r.txt

gendiffcov $DIFFCOV_OPTS --baseline-file ./current.info --diff-file diff_r.txt -o ./reverse ./baseline.info.gz
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov branch failed"
    exit 1
fi

gendiffcov $DIFFCOV_OPTS --baseline-file ./current.info --diff-file diff_r.txt -o ./reverse_nobranch ./baseline_nobranch.info.gz
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov reverse_nobranch failed"
    exit 1
fi

${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script annotate.sh -o ./no_owners ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov no_owners failed"
    exit 1
fi

${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt -o ./no_annotation ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov no_annotation failed"
    exit 1
fi

${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners -o ./no_baseline ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov no_baseline failed"
    exit 1
fi
