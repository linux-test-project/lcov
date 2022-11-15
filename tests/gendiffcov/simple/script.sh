#!/bin/sh
set +x

CLEAN_ONLY=0
COVER=

PARALLEL='--parallel 0'
PROFILE="--profile"
CXX='g++'
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

        --coverage )
            #COVER="perl -MDevel::Cover "
            COVER="perl -MDevel::Cover=-db,cover_db,-coverage,statement,branch,condition,subroutine "
            ;;

        --home | home )
            LCOV_HOME=$1
            shift
            if [ ! -f $LCOV_HOME/bin/lcov ] ; then
                echo "LCOV_HOME '$LCOV_HOME' does not exist"
                exit 1
            fi
            ;;

        --no-parallel )
            PARALLEL=''
            ;;

        --no-profile )
            PROFILE=''
            ;;

        --llvm )
            LLVM=1
            module load como/tools/llvm-gnu/11.0.0-1
            # seems to have been using same gcov version as gcc/4.8.3
            module load gcc/4.8.3
            #EXTRA_GCOV_OPTS="--gcov-tool '\"llvm-cov gcov\"'"
            CXX="clang++"
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
LCOV_HOME=`(cd ${LCOV_HOME} ; pwd)`

if [[ ! ( -d $LCOV_HOME/bin && -d $LCOV_HOME/lib && -x $LCOV_HOME/bin/genhtml && -f $LCOV_HOME/lib/lcovutil.pm ) ]] ; then
    echo "LCOV_HOME '$LCOV_HOME' seems not to be invalid"
    exit 1
fi

export PATH=${LCOV_HOME}/bin:${LCOV_HOME}/share:${PATH}
export MANPATH=${MANPATH}:${LCOV_HOME}/man

ROOT=`pwd`
PARENT=`(cd .. ; pwd)`
if [ -f $LCOV_HOME/bin/getp4version ] ; then
    GET_VERSION=$LCOV_HOME/bin/getp4version
else
    GET_VERSION=$LCOV_HOME/share/lcov/support-scripts/getp4version
fi

#PARALLEL=''
#PROFILE="''


LCOV_OPTS="$EXTRA_GCOV_OPTS --rc lcov_branch_coverage=1 --version-script $GET_VERSION $PARALLEL $PROFILE"
DIFFCOV_OPTS="--function-coverage --branch-coverage --highlight --demangle-cpp --frame --prefix $PARENT --version-script $GET_VERSION $PROFILE $PARALLEL"
#DIFFCOV_OPTS="--function-coverage --branch-coverage --highlight --demangle-cpp --frame"
#DIFFCOV_OPTS='--function-coverage --branch-coverage --highlight --demangle-cpp'

rm -f test.cpp *.gcno *.gcda a.out *.info *.info.gz diff.txt diff_r.txt diff_broken.txt *.log *.err *.json dumper* results.xlsx
rm -rf ./baseline ./current ./differential* ./reverse ./no_baseline ./no_annotation ./no_owners differential_nobranch reverse_nobranch baseline-filter* noncode_differential* broken mismatchPath elidePath ./cover_db ./criteria ./mismatched ./navigation

if [ "x$COVER" != 'x' ] ; then
    cover -delete
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

echo *

ln -s simple.cpp test.cpp
${CXX} --coverage test.cpp
./a.out

echo `which gcov`
echo `which lcov`

echo lcov $LCOV_OPTS --capture --directory . --output-file baseline.info
$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --directory . --output-file baseline.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    exit 1
fi
gzip -c baseline.info > baseline.info.gz

# test merge with differing version
sed -e 's/VER:/VER:x/g' < baseline.info > baseline2.info
$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --output merge.info -a baseline.info -a baseline2.info
if [ 0 == $? ] ; then
    echo "ERROR: merge with mismatched version did not fail"
    exit 1
fi
$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --ignore version --output merge2.info -a baseline.info -a baseline2.info
if [ 0 != $? ] ; then
    echo "ERROR: ignore error merge with mismatched version failed"
    exit 1
fi
# run genhtml with mismatched version
echo genhtml $DIFFCOV_OPTS baseline2.info --output-directory ./mismatched
$COVER $LCOV_HOME/bin/genhtml $DIFFCOV_OPTS baseline2.info --output-directory ./mismatched
if [ 0 == $? ] ; then
    echo "ERROR: genhtml with mismatched baseline did not fail"
    exit 1
fi



echo lcov $LCOV_OPTS --capture --directory . --output-file baseline_nobranch.info
$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --directory . --output-file baseline_nobranch.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (2) failed"
    exit 1
fi
gzip -c baseline_nobranch.info > baseline_nobranch.info.gz
#genhtml baseline.info --output-directory ./baseline

echo genhtml $DIFFCOV_OPTS baseline.info --output-directory ./baseline
$COVER $LCOV_HOME/bin/genhtml $DIFFCOV_OPTS baseline.info --output-directory ./baseline
if [ 0 != $? ] ; then
    echo "ERROR: genhtml baseline failed"
    exit 1
fi
# expect not to see differential categories...

echo lcov $LCOV_OPTS --filter branch,line --capture --directory . --output-file baseline-filter.info
$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --filter branch,line --capture --directory . --output-file baseline-filter.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (3) failed"
    exit 1
fi
gzip -c baseline-filter.info > baseline-filter.info.gz
#genhtml baseline.info --output-directory ./baseline
echo genhtml $DIFFCOV_OPTS baseline-filter.info --output-directory ./baseline-filter
$COVER $LCOV_HOME/bin/genhtml $DIFFCOV_OPTS baseline-filter.info --output-directory ./baseline-filter
if [ 0 != $? ] ; then
    echo "ERROR: genhtml baseline-filter failed"
    exit 1
fi

#genhtml baseline.info --dark --output-directory ./baseline
echo genhtml $DIFFCOV_OPTS --dark baseline-filter.info --output-directory ./baseline-filter-dark
$COVER $LCOV_HOME/bin/genhtml $DIFFCOV_OPTS --dark baseline-filter.info --output-directory ./baseline-filter-dark
if [ 0 != $? ] ; then
    echo "ERROR: genhtml baseline-filter-dark failed"
    exit 1
fi

export PWD=`pwd`
echo $PWD

rm -f test.cpp test.gcno test.gcda a.out
ln -s simple2.cpp test.cpp
${CXX} --coverage -DADD_CODE -DREMOVE_CODE test.cpp
./a.out
echo lcov $LCOV_OPTS --capture --directory . --output-file current.info
$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --directory . --output-file current.info
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (4) failed"
    exit 1
fi
gzip -c current.info > current.info.gz

#genhtml current.info --output-directory ./current
echo genhtml $DIFFCOV_OPTS --show-details current.info --output-directory ./current
$COVER $LCOV_HOME/bin/genhtml $DIFFCOV_OPTS current.info --show-details --output-directory ./current
if [ 0 != $? ] ; then
    echo "ERROR: genhtml current failed"
    exit 1
fi

diff -u simple.cpp simple2.cpp | sed -e "s|simple2*\.cpp|$ROOT/test.cpp|g" > diff.txt

for dark in "" --dark-mode ; do
  echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS $dark --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors source --simplified-colors -o ./noncode_differential$dark ./current.info.gz
  $COVER ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS $dark --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors source --simplified-colors -o ./noncode_differential$dark ./current.info.gz
  if [ 0 != $? ] ; then
      echo "ERROR: genhtml noncode_differential$dark failed"
      exit 1
  fi
  # expect to see non-code owners 'rupert.psmith' and 'pelham.wodehouse' in file annotations
  FILE=`find noncode_differential$dark -name test.cpp.gcov.html`
  for owner in rupert.psmith pelham.wodehouse ; do
      grep $owner $FILE
      if [ 0 != $? ] ;then
          echo "ERROR: did not find $owner in noncode_differential$dark annotations"
          exit 1
      fi
  done
done

# run with several different combinations of options - and see
#   if they do what we expect
TEST_OPTS=$DIFFCOV_OPTS
EXT=""
for opt in "" "--show-details" "--hier" ; do

    for o in "" $opt ; do
        OPTS="$TEST_OPTS $o"
        outdir=./differential${EXT}${o}
        echo ${LCOV_HOME}/bin/genhtml $OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source -o $outdir ./current.info
        $COVER ${LCOV_HOME}/bin/genhtml $OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source -o $outdir ./current.info
        if [ 0 != $? ] ; then
            echo "ERROR: genhtml $outdir failed"
            exit 1
        fi

        if [[ $OPTS =~ "show-details" ]] ; then
            found=0
        else
            found=1
        fi
        grep "show details" $outdir/simple/index.html
        # expect to find the string (0 return val) if flag is present
        if [ $found != $? ] ;then
            echo "ERROR: '--show-details' mismatch in $outdir"
            exit 1
        fi

        if [[ $OPTS =~ "hier" ]] ; then
            found=0
        else
            found=1
        fi
        # look for full path name (starting from '/') in the index.html file..
        #   we aren't sure where gcc is installed - so we aren't sure what
        #   path to look for
        # However - some compiler versions (e.g., gcc/10) don't find any
        #   coverage info in the system header files, so there is no
        #   hierarchical entry in the output HTML
        COUNT=`grep -c index.html\" $outdir/index.html`
        if [ $COUNT != 1 ] ; then
            grep "index.html\">/[^/]*/[^/]*/[^/]*/" $outdir/index.html
            #grep "/mtkoss/gcc" $outdir/index.html
            # expect to find the string (0 return val) if flag is NOT present
            if [ $found == $? ] ;then
                echo "ERROR: '--hierarchical' path mismatch in $outdir"
                exit 1
            fi
        else
            echo "only one directory in output"
        fi

        # expect to not to see non-code owners 'rupert.psmith' and 'pelham.wodehose' in file annotations
        FILE=`find $outdir -name test.cpp.gcov.html`
        for owner in rupert.psmith pelham.wodehose ; do
            grep $owner $FILE
            if [ 1 != $? ] ;then
                echo "ERROR: found $owner in $outdir annotations"
                exit 1
            fi
        done
        # expect to see augustus.finknottle in owner table (100% coverage)
        for owner in augustus.finknottle ; do
            grep $owner $outdir/index.html
            if [ 0 != $? ] ;then
                echo "ERROR: did not find $owner in $outdir owner summary"
                exit 1
            fi
        done
        for summary in Branch Line ; do
            grep "$summary coverage" $outdir/index.html
            if [ 0 != $? ] ;then
                echo "ERROR: did not find $summary in $outdir summary"
                exit 1
            fi
        done
    done
    TEST_OPTS="$TEST_OPTS $opt"
    EXT=${EXT}${opt}
done


echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --no-branch-coverage --baseline-file ./baseline_nobranch.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners --ignore-errors source -o ./differential_nobranch ./current.info
$COVER ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --no-branch-coverage --baseline-file ./baseline_nobranch.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners --ignore-errors source -o ./differential_nobranch ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: genhtml differential_nobranch failed"
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

echo genhtml $DIFFCOV_OPTS --baseline-file ./current.info --diff-file diff_r.txt -o ./reverse ./baseline.info.gz
$COVER $LCOV_HOME/bin/genhtml $DIFFCOV_OPTS --baseline-file ./current.info --diff-file diff_r.txt -o ./reverse ./baseline.info.gz
if [ 0 != $? ] ; then
    echo "ERROR: genhtml branch failed"
    exit 1
fi

echo genhtml $DIFFCOV_OPTS --baseline-file ./current.info --diff-file diff_r.txt -o ./reverse_nobranch ./baseline_nobranch.info.gz
$COVER $LCOV_HOME/bin/genhtml $DIFFCOV_OPTS --baseline-file ./current.info --diff-file diff_r.txt -o ./reverse_nobranch ./baseline_nobranch.info.gz
if [ 0 != $? ] ; then
    echo "ERROR: genhtml reverse_nobranch failed"
    exit 1
fi

echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script annotate.sh -o ./no_owners ./current.info
$COVER ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script annotate.sh -o ./no_owners ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: genhtml no_owners failed"
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

echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt -o ./no_annotation ./current.info
$COVER ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt -o ./no_annotation ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: genhtml no_annotation failed"
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

echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners -o ./no_baseline ./current.info
$COVER ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners -o ./no_baseline ./current.info
if [ 0 != $? ] ; then
    echo "ERROR: genhtml no_baseline failed"
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


echo "now some error checking and issue workaround tests..."

# - first, create a 'diff' file whose pathname is not quite right..
sed -e "s#/simple/test#/badPath/test#g" diff.txt > diff_broken.txt

# now run genhtml - expect to see an error:
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --simplified-colors -o ./broken ./current.info.gz
$COVER ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --simplified-colors -o ./broken ./current.info.gz > err.log 2>&1

if [ 0 == $? ] ; then
    echo "ERROR:  expected error but didn't see it"
    exit 1
fi

grep "Error: possible path inconsistency" err.log
if [ 0 != $? ] ; then
    echo "ERROR:  can't find expected error message"
    exit 1
fi


# now run genhtml - expect to see an warning:
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors path --simplified-colors -o ./mismatchPath ./current.info.gz
$COVER ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors path --simplified-colors -o ./mismatchPath ./current.info.gz > warn.log 2>&1

if [ 0 != $? ] ; then
    echo "ERROR:  expected warning but didn't see it"
    exit 1
fi

grep 'Warning: .* possible path inconsistency' warn.log
if [ 0 != $? ] ; then
    echo "ERROR:  can't find expected warning message"
    exit 1
fi

# now use the 'elide' feature to avoid the error
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --elide-path-mismatch --simplified-colors -o ./elidePath ./current.info.gz
$COVER ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --elide-path-mismatch --simplified-colors -o ./elidePath ./current.info.gz > elide.log 2>&1

if [ 0 != $? ] ; then
    echo "ERROR:  expected success but didn't see it"
    exit 1
fi

grep "has same basename" elide.log
if [ 0 != $? ] ; then
    echo "ERROR:  can't find expected warning message"
    exit 1
fi

# test 'coverage criteria' callback
#  we expect to fail - and to see error message - it coverage criteria not met
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --criteria ${LCOV_HOME}/bin/criteria -o $outdir ./current.info
$COVER ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --criteria ${LCOV_HOME}/bin/criteria -o criteria ./current.info > criteria.log 2> criteria.err
if [ 0 == $? ] ; then
    echo "ERROR: genhtml criteria should have failed but didn't"
    exit 1
fi

if [[ $OPTS =~ "show-details" ]] ; then
    found=0
else
    found=1
fi
grep "Failed coverage criteria" criteria.log
# expect to find the string (0 return val) if flag is present
if [ 0 != $? ] ;then
    echo "ERROR: 'criteria fail message is missing"
    exit 1
fi
for l in criteria.log criteria.err ; do
  grep "UNC + LBC + UIC != 0" $l
  # expect to find the string (0 return val) if flag is present
  if [ 0 != $? ] ;then
      echo "ERROR: 'criteria string is missing from $l"
      exit 1
  fi
done

# test '--show-navigation' option
# need "--ignore-unused for gcc/10.2.0 - which doesn't see code in its c++ headers
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all --show-navigation -o navigation --ignore unused --exclude '*/include/c++/*' ./current.info
$COVER ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners all --show-navigation -o navigation --ignore unused --exclude '*/include/c++/*' ./current.info > navigation.log 2> navigation.err

if [ 0 != $? ] ; then
    echo "ERROR: genhtml --show-navigation failed"
    exit 1
fi

HIT=`grep -c HIT.. navigation.log`
MISS=`grep -c MIS.. navigation.log`
if [[ $HIT != '3' || $MISS != '2' ]] ; then
    echo "ERROR: 'navigation counts are wrong: hit $HIT != 3 $MISS != 2"
    exit 1
fi
# look for unexpected naming in HTML
for tla in GNC UNC ; do
    grep "next $tla in" ./navigation/simple/test.cpp.gcov.html
    if [ 0 == $? ] ; then
        echo "ERROR: found unexpected tla $TLA in result"
        exit 1
    fi
done
# look for expected naming in HTML
for tla in HIT MIS ; do
    grep "next $tla in" ./navigation/simple/test.cpp.gcov.html
    if [ 0 != $? ] ; then
        echo "ERROR: did not find expected tla $TLA in result"
        exit 1
    fi
done


# test file substitution option
echo lcov $LCOV_OPTS --capture --directory . --output-file subst.info --substitute "s#${PWD}#pwd#g" --exclude '*/iostream'
$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --directory . --output-file subst.info --substitute "s#${PWD}#pwd#g" --exclude '*/iostream'
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    exit 1
fi
grep "pwd/test.cpp" subst.info
if [ 0 != $? ] ; then
    echo "ERROR: --substitute failed - not found in subst.info"
    exit 1
fi
grep "iostream" subst.info
if [ 0 == $? ] ; then
    echo "ERROR: --exclude failed - found in subst.info"
    exit 1
fi
grep "pwd/test.cpp" baseline.info
if [ 0 == $? ] ; then
    # substitution should not have happened in baseline.info
    echo "ERROR: --substitute failed - found in baseline.info"
    exit 1
fi

# gcc/10 doesn't see code in its c++ headers - test will fail..
COUNT=`grep -c SF: baseline.info`
if [ $COUNT != '1' ] ; then
    grep "iostream" baseline.info
    if [ 0 != $? ] ; then
        # exclude should not have happened in baseline.info
        echo "ERROR: --exclude failed - not found in baseline.info"
        exit 1
    fi
fi

# some error checks...
$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --output err1.info -a baseline.info -a baseline.info --substitute "s#xyz#pwd#g" --exclude 'foo'
if [ 0 == $? ] ; then
    echo "ERROR: lcov ran despite error"
    exit 1
fi

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --output unused.info -a baseline.info -a baseline.info --substitute "s#xyz#pwd#g" --exclude 'foo' --ignore unused
if [ 0 != $? ] ; then
    echo "ERROR: lcov failed despite suppression"
    exit 1
fi

# and generate a spreadsheet..check that we don't crash
SPREADSHEET=$LCOV_HOME/bin/spreadsheet.py
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

if [ "x$COVER" != "x" ] ; then
    cover
fi
