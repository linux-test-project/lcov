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

echo lcov $LCOV_OPTS --capture --directory . --output-file baseline.info
lcov $LCOV_OPTS --capture --directory . --output-file baseline.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    exit 1
fi
gzip -c baseline.info > baseline.info.gz

echo lcov --capture --directory . --output-file baseline_nobranch.info
lcov --capture --directory . --output-file baseline_nobranch.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (2) failed"
    exit 1
fi
gzip -c baseline_nobranch.info > baseline_nobranch.info.gz
#genhtml baseline.info --output-directory ./baseline

echo gendiffcov $DIFFCOV_OPTS baseline.info --output-directory ./baseline
gendiffcov $DIFFCOV_OPTS baseline.info --output-directory ./baseline
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov baseline failed"
    exit 1
fi
# expect not to see differential categories...

echo lcov $LCOV_OPTS --filter branch,line --capture --directory . --output-file baseline-filter.info
lcov $LCOV_OPTS --filter branch,line --capture --directory . --output-file baseline-filter.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (3) failed"
    exit 1
fi
gzip -c baseline-filter.info > baseline-filter.info.gz
#genhtml baseline.info --output-directory ./baseline
echo gendiffcov $DIFFCOV_OPTS baseline-filter.info --output-directory ./baseline-filter
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
echo lcov $LCOV_OPTS --capture --directory . --output-file current.info
lcov $LCOV_OPTS --capture --directory . --output-file current.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (4) failed"
    exit 1
fi
gzip -c current.info > current.info.gz

#genhtml current.info --output-directory ./current
echo gendiffcov $DIFFCOV_OPTS current.info --output-directory ./current
gendiffcov $DIFFCOV_OPTS current.info --output-directory ./current
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov current failed"
    exit 1
fi

diff -u simple.cpp simple2.cpp | sed -e "s|simple2*\.cpp|$ROOT/test.cpp|g" > diff.txt

echo ${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors source -o ./noncode_differential ./current.info.gz
${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors source -o ./noncode_differential ./current.info.gz
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov noncode_differential failed"
    exit 1
fi
# expect to see non-code owners 'rupert.psmith' and 'pelham.wodehouse' in file annotations
FILE=`find noncode_differential -name test.cpp.gcov.html`
for owner in rupert.psmith pelham.wodehouse ; do
    grep $owner $FILE
    if [ 0 != $? ] ;then
        echo "ERROR: did not find $owner in noncode_differential annotations"
        exit 1
    fi
done

echo ${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source -o ./differential ./current.info
${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source -o ./differential ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov differential failed"
    exit 1
fi
# expect to not to see non-code owners 'rupert.psmith' and 'pelham.wodehose' in file annotations
FILE=`find differential -name test.cpp.gcov.html`
for owner in rupert.psmith pelham.wodehose ; do
    grep $owner $FILE
    if [ 1 != $? ] ;then
        echo "ERROR: found $owner in differential annotations"
        exit 1
    fi
done
# expect to see augustus.finknottle in owner table (100% coverage)
for owner in augustus.finknottle ; do
    grep $owner differential/index.html
    if [ 0 != $? ] ;then
        echo "ERROR: did not find $owner in differential owner summary"
        exit 1
    fi
done
for summary in Branch Line ; do
    grep "$summary coverage" differential/index.html
    if [ 0 != $? ] ;then
        echo "ERROR: did not find $summary in differential summary"
        exit 1
    fi
done


echo ${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --no-branch-coverage --baseline-file ./baseline_nobranch.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners --ignore-errors source -o ./differential_nobranch ./current.info
${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --no-branch-coverage --baseline-file ./baseline_nobranch.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners --ignore-errors source -o ./differential_nobranch ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov differential_nobranch failed"
    exit 1
fi
# should not be a branch table
# expect not to find 'augustus.finknottle' whose code is 100% covered in owner table
for owner in augustus.finknottle ; do
    grep $owner differential_nobranch/index.html
    if [ 1 != $? ] ;then
        echo "ERROR: found $owner in differential_nobranch owner summary"
        exit 1
    fi
done
for summary in Branch ; do
    grep "$summary coverage" differential_nobranch/index.html
    if [ 1 != $? ] ;then
        echo "ERROR: found $summary in differential_nobranch summary"
        exit 1
    fi
done


# and the inverse difference
diff -u simple2.cpp simple.cpp | sed -e "s|simple2*\.cpp|$ROOT/test.cpp|g" > diff_r.txt

echo gendiffcov $DIFFCOV_OPTS --baseline-file ./current.info --diff-file diff_r.txt -o ./reverse ./baseline.info.gz
gendiffcov $DIFFCOV_OPTS --baseline-file ./current.info --diff-file diff_r.txt -o ./reverse ./baseline.info.gz
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov branch failed"
    exit 1
fi

echo gendiffcov $DIFFCOV_OPTS --baseline-file ./current.info --diff-file diff_r.txt -o ./reverse_nobranch ./baseline_nobranch.info.gz
gendiffcov $DIFFCOV_OPTS --baseline-file ./current.info --diff-file diff_r.txt -o ./reverse_nobranch ./baseline_nobranch.info.gz
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov reverse_nobranch failed"
    exit 1
fi

echo ${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script annotate.sh -o ./no_owners ./current.info
${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script annotate.sh -o ./no_owners ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov no_owners failed"
    exit 1
fi
# expect to not find ownership summary table...
for summary in ownership ; do
    grep $summary no_owners/index.html
    if [ 1 != $? ] ;then
        echo "ERROR: found $summary in no_owners summary"
        exit 1
    fi
done

echo ${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt -o ./no_annotation ./current.info
${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt -o ./no_annotation ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov no_annotation failed"
    exit 1
fi
# expect to find differential TLAs - but don't expec ownership and date tables
for key in UNC LBC UIC UBC GBC GIC GNC CBC EUB ECB DUB DCB ; do
    grep $key no_annotation/index.html
    if [ 0 != $? ] ;then
        echo "ERROR: did not find $key in no_annotation summary"
        exit 1
    fi
done
for key in "date bins" "ownership bins" ; do
    grep "$key" no_annotation/index.html
    if [ 1 != $? ] ;then
        echo "ERROR: found $key in no_annotation summary"
        exit 1
    fi
done

echo ${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners -o ./no_baseline ./current.info
${LCOV_HOME}/bin/gendiffcov $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners -o ./no_baseline ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: gendiffcov no_baseline failed"
    exit 1
fi
# don't expect to find differential TLAs - but still expect ownership and date tables
for key in "date bins" "ownership bins" ; do
    grep "$key" no_baseline/index.html
    if [ 0 != $? ] ;then
        echo "ERROR: did not find $key in no_baseline summary"
        exit 1
    fi
done
for key in UNC LBC UIC UBC GBC GIC GNC CBC EUB ECB DUB DCB ; do
    grep $key no_baseline/index.html
    if [ 1 != $? ] ;then
        echo "ERROR: found $key in no_baseline summary"
        exit 1
    fi
done

echo "Tests passed"

