#!/bin/bash
set +x

CLEAN_ONLY=0
COVER=

PARALLEL='--parallel 0'
PROFILE="--profile"
LOCAL_COVERAGE=1
KEEP_GOING=0

#echo "CMD:  $0 $@"

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

        --keep-going | -k )
            KEEP_GOING=1
            ;;

        --coverage )
            if [[ "$1"x != 'x' && $1 != "-"*  ]] ; then
               COVER_DB=$1
               LOCAL_COVERAGE=0
               shift
            else
                COVER_DB='cover_db.dat'
            fi
            export PYCOV_DB="${COVER_DB}_py"
            COVER="perl -MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine,-silent,1 "
            PYCOVER="COVERAGE_FILE=$PYCOV_DB coverage run --branch --append"
            ;;

        --home | -home )
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

if [[ ! ( -d $LCOV_HOME/bin && -d $LCOV_HOME/lib && -x $LCOV_HOME/bin/genhtml && ( -f $LCOV_HOME/lib/lcovutil.pm || -f $LCOV_HOME/lib/lcov/lcovutil.pm ) ) ]] ; then
    echo "LCOV_HOME '$LCOV_HOME' seems not to be invalid"
    exit 1
fi

export PATH=${LCOV_HOME}/bin:${LCOV_HOME}/share:${PATH}
export MANPATH=${MANPATH}:${LCOV_HOME}/man

ROOT=`pwd`
PARENT=`(cd .. ; pwd)`
if [ -f $LCOV_HOME/scripts/getp4version ] ; then
    SCRIPT_DIR=$LCOV_HOME/scripts
else
    # running test from lcov install
    SCRIPT_DIR=$LCOV_HOME/share/lcov/support-scripts
    MD5_OPT='--version-script --md5'
fi
if [ 'x' == "x$GENHTML_TOOL" ] ; then
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    GENINFO_TOOL=${LCOV_HOME}/bin/geninfo
    SPREADSHEET_TOOL=${SCRIPT_DIR}/spreadsheet.py
fi

# is this git or P4?
git -C . rev-parse > /dev/null 2>&1
if [ 0 == $? ] ; then
    # this is git
    GET_VERSION=${SCRIPT_DIR}/gitversion.pm
    GET_VERSION_EXE=${SCRIPT_DIR}/gitversion
    ANNOTATE=${SCRIPT_DIR}/gitblame.pm
else
    GET_VERSION=${SCRIPT_DIR}/getp4version
    GET_VERSION_EXE=${SCRIPT_DIR}/getp4version
    ANNOTATE=${SCRIPT_DIR}/p4annotate.pm
fi
CRITERIA=${SCRIPT_DIR}/criteria
SELECT=${SCRIPT_DIR}/select.pm

#PARALLEL=''
#PROFILE="''


rm -f test.cpp *.gcno *.gcda a.out *.info *.info.gz diff.txt diff_r.txt diff_broken.txt *.log *.err *.json dumper* results.xlsx annotate.{cpp,exe} c d ./cover_db_py names.data linked.cpp linked_diff.txt *.msg
rm -rf ./baseline ./current ./differential* ./reverse ./diff_no_baseline ./no_baseline ./no_annotation ./no_owners differential_nobranch reverse_nobranch baseline-filter* noncode_differential* broken mismatchPath elidePath ./cover_db ./criteria* ./mismatched ./navigation differential_prop proportion ./annotate ./current-* ./current_prefix* select select2 html_report ./usage ./errOut ./noNames no_source linked linked_err linked_elide linked_dir failUnder expect_err expect recategorize

if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover -delete -db $COVER_DB
    rm -rf $PYCOV_DB
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type "${CXX}" >/dev/null 2>&1 ; then
        echo "Missing tool: $CXX" >&2
        exit 2
fi
1
if ! python3 -c "import xlsxwriter" >/dev/null 2>&1 ; then
        echo "Missing python module: xlsxwriter" >&2
        exit 2
fi

echo *

echo "COVER = '$COVER'"
echo "COVER_DB = '$COVER_DB'"
echo "PYCOVER = '$PYCOVER'"
echo "PYCOV_DB = '$PYCOV_DB'"

BASE_OPTS="--branch-coverage $PARALLEL $PROFILE"

echo `which gcov`
echo `which lcov`
# old version of gcc has inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent,category"
fi
if [ "${VER[0]}" -lt 9 ] ; then
    DERIVE='--rc derive_function_end_line=1'
elif [ "${VER[0]}" -ge 14 ] ; then
    ENABLE_MCDC=1
    BASE_OPTS="$BASE_OPTS --mcdc"
    # enable MCDC
    COVERAGE_OPTS="-fcondition-coverage"
fi
LCOV_OPTS="$EXTRA_GCOV_OPTS $BASE_OPTS --version-script $GET_VERSION $MD5_OPT --version-script --allow-missing"
DIFFCOV_NOFRAME_OPTS="$BASE_OPTS --demangle-cpp --prefix $PARENT --version-script $GET_VERSION $MD5_OPT --version-script --allow-missing"
#DIFFCOV_OPTS="--function-coverage --branch-coverage --demangle-cpp --frame"
#DIFFCOV_OPTS='--function-coverage --branch-coverage --demangle-cpp'
DIFFCOV_OPTS="$DIFFCOV_NOFRAME_OPTS --frame"

status=0
ln -s simple.cpp test.cpp
${CXX} --coverage $COVERAGE_OPTS test.cpp
./a.out



echo lcov $LCOV_OPTS --capture --directory . --output-file baseline.info $IGNORE --memory 20
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file baseline.info $IGNORE --comment "this is the baseline" --memory 20
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
cp baseline.info baseline_orig.info
# make the version number look different so the new diff file
#  consistency check will pass
sed -i -E 's/VER:#1/VER:#2/' baseline.info
gzip -c baseline.info > baseline.info.gz

# check that we wrote the comment that was expected...
head -1 baseline.info | grep -E '^#.+ the baseline$'
if [ 0 != $? ] ; then
    echo "ERROR: didn't write comment into capture"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# newer versions of gcc generate coverage data with full paths to sources
#   in '.' - whereas older versions have relative paths.
# In case of relative paths, need some additional genhtml flags to make
#   tests run the same way
grep './test.cpp' baseline.info
if [ 0 == $? ] ; then
    # found - need some flags
    GENHTML_PORT='--elide-path-mismatch'
    LCOV_PORT='--substitute s#./#pwd/# --ignore unused'
fi

echo lcov $LCOV_OPTS --capture --directory . --output-file baseline_name.info --test-name myTest $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file baseline_name.info --test-name myTest $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture with namefailed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# make the version number look different so the new diff file
#  consistency check will pass
sed -i -E 's/VER:#1/VER:#2/' baseline_name.info

# test merge with differing version
sed -e 's/VER:/VER:x/g' < baseline.info > baseline2.info
$COVER $LCOV_TOOL $LCOV_OPTS --output merge.info -a baseline.info -a baseline2.info $IGNORE
if [ 0 == $? ] ; then
    echo "ERROR: merge with mismatched version did not fail"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
$COVER $LCOV_TOOL $LCOV_OPTS --ignore version --output merge2.info -a baseline.info -a baseline2.info $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: ignore error merge with mismatched version failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# test filter with differing version
$COVER $LCOV_TOOL $LCOV_OPTS --output filt.info --filter branch,line -a baseline2.info $IGNORE
if [ 0 == $? ] ; then
    echo "ERROR: filter with mismatched version did not fail"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
$COVER $LCOV_TOOL $LCOV_OPTS --output filt.info --filter branch,line -a baseline2.info $IGNORE --ignore version
if [ 0 != $? ] ; then
    echo "ERROR: ignore error filter with mismatched version failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# run again with version script options passed in string
# test filter with differing version
$COVER $LCOV_TOOL $EXTRA_GCOV_OPTS $BASE_OPTS --version-script "$GET_VERSION_EXE --md5 --allow-missing" --output filt2.info --filter branch,line -a baseline2.info $IGNORE
if [ 0 == $? ] ; then
    echo "ERROR: filter with mismatched version did not fail 2"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ -e filt2.info ] ; then
    echo "ERROR: filter failed by still produced result"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
$COVER $LCOV_TOOL $EXTRA_GCOV_OPTS $BASE_OPTS --version-script "$GET_VERSION_EXE --md5  --allow-missing" --output filt2.info --filter branch,line -a baseline2.info $IGNORE --ignore version
if [ 0 != $? ] ; then
    echo "ERROR: ignore error filter with combined opts and mismatched version failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
diff filt.info filt2.info
if [ 0 != $? ] ; then
    echo "ERROR: string and separate args produced different result"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# test the 'fail under' flag
echo $LCOV_TOOL $LCOV_OPTS --output failUnder.info $IGNORE --capture -d . --ignore version --fail-under-lines 70
$COVER $LCOV_TOOL $LCOV_OPTS --output failUnder.info $IGNORE --capture -d . --ignore version --fail-under-lines 70
if [ 0 == $? ] ; then
    echo "ERROR: did not fail with low coverage"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ ! -f failUnder.info ] ; then
    echo "ERROR: did not write info file when failing"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo genhtml $DIFFCOV_OPTS $IGNORE failUnder.info --output-directory ./failUnder --fail-under-lines 70
$COVER $GENHTML_TOOL $DIFFCOV_OPTS $IGNORE failUnder.info --output-directory ./failUnder --fail-under-lines 70
if [ 0 == $? ] ; then
    echo "ERROR: genhtml did not fail with low coverage"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ ! -f failUnder/index.html ] ; then
    echo "ERROR: did not write HTML when failing"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# run genhtml with mismatched version
echo genhtml $DIFFCOV_OPTS baseline2.info --output-directory ./mismatched
$COVER $GENHTML_TOOL $DIFFCOV_OPTS baseline2.info --output-directory ./mismatched
if [ 0 == $? ] ; then
    echo "ERROR: genhtml with mismatched baseline did not fail"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo lcov $LCOV_OPTS --capture --directory . --output-file baseline_nobranch.info $IGNORE --rc memory=1024
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file baseline_nobranch.info $IGNORE --rc memory=1024
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (2) failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# make the version number look different so the new diff file
#  consistency check will pass
sed -i -E 's/VER:#1/VER:#2/' baseline_nobranch.info
gzip -c baseline_nobranch.info > baseline_nobranch.info.gz
#genhtml baseline.info --output-directory ./baseline

echo genhtml $DIFFCOV_OPTS baseline_orig.info --output-directory ./baseline $IGNORE --rc memory_percentage=50 --serialize ./baseline/coverage.dat
$COVER $GENHTML_TOOL $DIFFCOV_OPTS baseline_orig.info --output-directory ./baseline --save $IGNORE --rc memory_percentage=50 --serialize ./baseline/coverage.dat
if [ 0 != $? ] ; then
    echo "ERROR: genhtml baseline failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ ! -f ./baseline/coverage.dat ] ; then
    echo "ERROR: no serialized data found"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# expect not to see differential categories...

echo lcov $LCOV_OPTS --filter branch,line --capture --directory . --output-file baseline-filter.info $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --filter branch,line --capture --directory . --output-file baseline-filter.info $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (3) failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi

fi
gzip -c baseline-filter.info > baseline-filter.info.gz
#genhtml baseline.info --output-directory ./baseline
echo genhtml $DIFFCOV_OPTS baseline-filter.info --output-directory ./baseline-filter $IGNORE --missed
$COVER $GENHTML_TOOL $DIFFCOV_OPTS baseline-filter.info --output-directory ./baseline-filter $IGNORE --missed
if [ 0 != $? ] ; then
    echo "ERROR: genhtml baseline-filter failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

#genhtml baseline.info --dark --output-directory ./baseline
echo genhtml $DIFFCOV_OPTS --dark baseline-filter.info --output-directory ./baseline-filter-dark $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --dark baseline-filter.info --output-directory ./baseline-filter-dark $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: genhtml baseline-filter-dark failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

export PWD=`pwd`
echo $PWD

rm -f test.cpp test.gcno test.gcda a.out
ln -s simple2.cpp test.cpp
${CXX} --coverage $COVERAGE_OPTS -DADD_CODE -DREMOVE_CODE test.cpp
./a.out
echo lcov $LCOV_OPTS --capture --directory . --output-file current.info $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file current.info $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (4) failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
gzip -c current.info > current.info.gz

echo lcov $LCOV_OPTS --capture --directory . --output-file current_name.info.gz --test-name myTest $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file current_name.info.gz --test-name myTest $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (name) failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo '' > names.data
echo  -o noNames $DIFFCOV_OPTS $IGNORE --show-details --description names.data current_name.info.gz
$COVER $GENHTML_TOOL -o noNames $DIFFCOV_OPTS $IGNORE --show-details --description names.data current_name.info.gz
if [ 0 == $? ] ; then
    echo "ERROR: expected fail due to missing descriptions - but passed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo "TD: out of sequence" > names.data
echo genhtml -o noNames $DIFFCOV_OPTS $IGNORE --show-details --description names.data current_name.info.gz
$COVER $GENHTML_TOOL -o noNames $DIFFCOV_OPTS $IGNORE --show-details --description names.data current_name.info.gz
if [ 0 == $? ] ; then
    echo "ERROR: expected fail due to invalid sequence - but passed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# check that vanilla, flat, hierarchical work with and without prefix
cat > names.data <<EOF
TN:myTest
TD:faking some test data
# test empty description
TN:unusedTest
TD:
EOF

    now=`date`
for mode in '' '--flat' '--hierarchical' ; do
    echo genhtml $DIFFCOV_OPTS $mode --show-details current_name.info.gz --output-directory ./current$mode $IGNORE --description names.data
    $COVER $GENHTML_TOOL $mode $DIFFCOV_OPTS current_name.info.gz --show-details --output-directory ./current$mode $IGNORE --current-date "$now" --description names.data
    if [ 0 != $? ] ; then
        echo "ERROR: genhtml current $mode failed"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    # verify that the 'details' link is there:
    #   index.html file should refer to 'show details'
    if [ '' == "$mode" ] ; then
        FILE=./current/simple/index.html
    else
        FILE=./current$mode/index.html
    fi
    grep 'show details' $FILE
    if [ 0 != $? ] ; then
        echo "ERROR: no testcase 'details' link"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    # run again with prefix
    echo genhtml $DIFFCOV_OPTS $mode --show-details current_name.info.gz --output-directory ./current_prefix$mode $IGNORE --prefix `pwd`  --description names.data
    $COVER $GENHTML_TOOL $mode $DIFFCOV_OPTS current_name.info.gz --show-details --output-directory ./current_prefix$mode $IGNORE --prefix `pwd` --current-date "$now"  --description names.data
    if [ 0 != $? ] ; then
        echo "ERROR: genhtml current $mode --prefix failed"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    diff current$mode/index.html current_prefix$mode/index.html
    if [ 0 != $? ] ; then
        echo "ERROR: diff current $mode --prefix failed"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    # and content should be the same
    ls current$mode > c
    ls current_prefix$mode > d
    diff c d
    if [ 0 != $? ] ; then
        echo "ERROR: diff current $mode content differs"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

diff -u simple.cpp simple2.cpp | sed -e "s|simple2*\.cpp|$ROOT/test.cpp|g" > diff.txt

# change the default annotation tooltip so grep commands looking for
#  owner table entries doesn't match accidentally
#  No spaces to avoid escaping quote substitutions
#  No frames - so directory table link to first TLA in file are shown
POPUP='--rc genhtml_annotate_tooltip=mytooltip'
for opt in "" --dark-mode --flat ; do
  outDir=./noncode_differential$opt
  echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_NOFRAME_OPTS $opt --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors source --simplified-colors -o $outDir ./current.info.gz $IGNORE $POPUP
  $COVER $GENHTML_TOOL $DIFFCOV_NOFRAME_OPTS $opt --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors source --simplified-colors -o $outDir ./current.info.gz $GENHTML_PORT --save $IGNORE $POPUP
  if [ 0 != $? ] ; then
      echo "ERROR: genhtml $outdir failed (1)"
      status=1
      if [ 0 == $KEEP_GOING ] ; then
          exit 1
      fi
  fi

  #look for navigation links in index.html files
  if [ -f $outDir/simple/index.html ] ; then
      indexDir=$outDir/simple
  else
      # flat view - so the navigation links should be at top level
      indexDir=$outDir
  fi
  for f in $indexDir/index.html ; do
      grep -E 'href=.*#L[0-9]+.*Go to first ' $f
      if [ 0 != $? ] ; then
          status=1
          echo "ERROR:  no navigation links in $f"
          if [ 0 == $KEEP_GOING ] ; then
              exit 1
          fi
      fi
  done

  # expect to see non-code owners 'rupert.psmith' and 'pelham.wodehouse' in file annotations
  FILE=`find $outDir -name test.cpp.gcov.html`
  for owner in rupert.psmith pelham.wodehouse ; do
      grep $owner $FILE
      if [ 0 != $? ] ; then
          echo "ERROR: did not find $owner in $outDir annotations"
          status=1
          if [ 0 == $KEEP_GOING ] ; then
              exit 1
          fi
      fi
  done
  if [ "$opt"x == '--flat'x ] ; then

      # flat view don't expect to see index.html in subdir
      if [ -e $outDir/simple/index.html ] ; then
          echo "ERROR:  --flat should not write subdir index in $outDir"
          status=1
          if [ 0 == $KEEP_GOING ] ; then
              exit 1
          fi
      fi
      # expect to see path to source file in the indices
      for f in $outDir/index*.html ; do
          grep "simple/test.cpp" $f
          if [ 0 != $? ] ; then
              echo "ERROR: expected to see path in $f"
              status=1
              if [ 0 == $KEEP_GOING ] ; then
                  exit 1
              fi
          fi
      done
  fi

  outDir=./differential_subset$opt
  echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_NOFRAME_OPTS $opt --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --simplified-colors -o $outDir ./current.info.gz $IGNORE $POPUP --rc truncate_owner_table=top,directory --rc owner_table_entries=2 --include '*simple*'
  $COVER $GENHTML_TOOL $DIFFCOV_NOFRAME_OPTS $opt --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors source --simplified-colors -o $outDir ./current.info.gz $GENHTML_PORT --save $IGNORE $POPUP --rc truncate_owner_table=top,directory --include '*simple*' --rc owner_table_entries=2
  if [ 0 != $? ] ; then
      echo "ERROR: genhtml subset $outDir failed"
      status=1
      if [ 0 == $KEEP_GOING ] ; then
          exit 1
      fi
  fi
  # expect to see owners 'henry.cox' and 'roderick.glossop'
  # but not augustus.finknottle - who should have been truncated
  OUT='augustus.finknottle'
  FILES=$outDir/index.html
  if [ -d $outDir/simiple/index.html ] ; then
      FILES="$FILES $outDir/simiple/index.html"
  fi
  for FILE in $FILES ; do
      for owner in henry.cox roderick.glossop ; do
          grep $owner $FILE
          if [ 0 != $? ] ; then
              echo "ERROR: did not find $owner in $outDir $FILE annotations"
              status=1
              if [ 0 == $KEEP_GOING ] ; then
                  exit 1
              fi
          fi
      done
      # expect to see note about truncation in the table view
      grep '2 authors truncated' $FILE
      if [ 0 != $? ] ; then
          echo "ERROR: did not find truncation count in $FILE"
          status=1
          if [ 0 == $KEEP_GOING ] ; then
              exit 1
          fi
      fi

      for owner in augustus.finknottle ; do
          grep $owner $FILE
          if [ 0 == $? ] ; then
              echo "ERROR: unexpectedly found $owner in $outDir $FILEannotations"
              status=1
              if [ 0 == $KEEP_GOING ] ; then
                  exit 1
              fi
          fi
      done
  done # for each index file

done


# check that this works with test names
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline_name.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors source --simplified-colors -o differential_named ./current_name.info.gz $IGNORE --description names.data --serialize differential_named/coverage.dat
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline_name.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors source --simplified-colors -o differential_named ./current_name.info.gz $GENHTML_PORT $IGNORE --description names.data --serialize differential_named/coverage.dat
if [ 0 != $? ] ; then
    echo "ERROR: genhtml differential testname failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# test --build-dir option, using linked build
cp test.cpp linked.cpp
mkdir -p linked/build
(cd linked/build ; ln -s ../../linked.cpp )
for f in baseline current ; do
  cat ${f}.info | sed -e 's/test.cpp/linked\/build\/linked.cpp/' > linked_${f}.info
done
cat diff.txt | sed -e s/test.cpp/linked.cpp/ > linked_diff.txt

# note:  ignore version mismatch because copying file changed the
#  date - and so will cause a mismatch
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./linked_baseline.info --diff-file linked_diff.txt -o linked_err ./linked_current.info $IGNORE --ignore version
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./linked_baseline.info --diff-file linked_diff.txt -o linked_err ./linked_current.info $IGNORE --ignore version 2>&1 | tee linked.log
# should fail to find source files
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "expected genhtml to fail with linked build"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# check for diff file inconsistency message
grep -E 'version changed from .+ but file not found in' linked.log
if [ 0 != $? ] ; then
    echo "failed to find expected diff consistency message"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# run again - skipping that message - expect to hit path mismatch
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./linked_baseline.info --diff-file linked_diff.txt -o linked_err ./linked_current.info $IGNORE --ignore version,inconsistent
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./linked_baseline.info --diff-file linked_diff.txt -o linked_err ./linked_current.info $IGNORE --ignore version,inconsistent 2>&1 | tee linked2.log
# should fail to find source files
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "expected genhtml to fail with linked build (2)"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# check error message
grep "possible path inconsistency" linked2.log
if [ 0 != $? ] ; then
    echo "failed to find expected mismatch message"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# run again eliding mismatches..
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./linked_baseline.info --diff-file linked_diff.txt -o linked_elide ./linked_current.info $IGNORE --ignore version,inconsistent --elide-path
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./linked_baseline.info --diff-file linked_diff.txt -o linked_elide ./linked_current.info $IGNORE --elide-path --ignore version,inconsistent
# should pass
if [ 0 != $? ] ; then
    echo "expected genhtml --elide to pass"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ ! -f linked_elide/simple/linked/build/linked.cpp.gcov.html ] ; then
    echo "expected linked/elide output not found"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# run again with build dir
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./linked_baseline.info --diff-file linked_diff.txt -o linked_dir ./linked_current.info $IGNORE --build-dir linked --ignore version,inconsistent --rc scope_regexp=linked
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./linked_baseline.info --diff-file linked_diff.txt -o linked_dir ./linked_current.info $IGNORE --build-dir linked --ignore version,inconsistent --rc scope_regexp=linked
# should pass
if [ 0 != $? ] ; then
    echo "expected genhtml --build-dir to pass"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ ! -f linked_elide/simple/linked/build/linked.cpp.gcov.html ] ; then
    echo "expected linked/elide output not found"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# run with several different combinations of options - and see
#   if they do what we expect
TEST_OPTS=$DIFFCOV_OPTS
EXT=""
for opt in "" "--show-details" "--hier"; do

    for o in "" $opt ; do
        OPTS="$TEST_OPTS $o"
        outdir=./differential${EXT}${o}
        echo ${LCOV_HOME}/bin/genhtml $OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source -o $outdir ./current.info $IGNORE $POPUP
        $COVER ${GENHTML_TOOL} $OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source -o $outdir ./current.info $GENHTML_PORT $IGNORE $POPUP
        if [ 0 != $? ] ; then
            echo "ERROR: genhtml $outdir failed (2)"
            status=1
            if [ 0 == $KEEP_GOING ] ; then
                exit 1
            fi
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
            status=1
            if [ 0 == $KEEP_GOING ] ; then
                exit 1
            fi
        fi

        if [[ $OPTS =~ "hier" ]] ; then
            # we don't expect a hierarchical path - grep return code is nonzero
            code=0
        else
            code=1
        fi
        # look for full path name (starting from '/') in the index.html file..
        #   we aren't sure where gcc is installed - so we aren't sure what
        #   path to look for
        # However - some compiler versions (e.g., gcc/10) don't find any
        #   coverage info in the system header files, so there is no
        #   hierarchical entry in the output HTML
        COUNT=`grep -c index.html\" $outdir/index.html`
        if [ $COUNT != 1 ] ; then
            # look for at least 2 directory elements in the path name
            # name might include 'c++'
            grep -E '[a-zA-Z0-9_.-+]+/[a-zA-Z0-9_.-+]+/index.html\"[^>]*>' $outdir/index.html
            # expect to find the string (0 return val) if flag is NOT present
            if [ $code == $? ] ; then
                echo "ERROR: '--hierarchical' path mismatch in $outdir"
                status=1
                if [ 0 == $KEEP_GOING ] ; then
                    exit 1
                fi
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
                status=1
                if [ 0 == $KEEP_GOING ] ; then
                    exit 1
                fi
            fi
        done
        # expect to see augustus.finknottle in owner table (100% coverage)
        for owner in augustus.finknottle ; do
            grep $owner $outdir/index.html
            if [ 0 != $? ] ;then
                echo "ERROR: did not find $owner in $outdir owner summary"
                status=1
                if [ 0 == $KEEP_GOING ] ; then
                    exit 1
                fi
            fi
        done
        for summary in Branch Line ; do
            grep "$summary coverage" $outdir/index.html
            if [ 0 != $? ] ;then
                echo "ERROR: did not find $summary in $outdir summary"
                status=1
                if [ 0 == $KEEP_GOING ] ; then
                    exit 1
                fi
            fi
        done
    done
    TEST_OPTS="$TEST_OPTS $opt"
    EXT=${EXT}${opt}
done


echo genhtml $DIFFCOV_OPTS --no-branch-coverage --baseline-file ./baseline_nobranch.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners --ignore-errors source -o ./differential_nobranch ./current.info $IGNORE $POPUP
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --no-branch-coverage --baseline-file ./baseline_nobranch.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners --ignore-errors source -o ./differential_nobranch ./current.info $GENHTML_PORT $IGNORE $POPUP
if [ 0 != $? ] ; then
    echo "ERROR: genhtml differential_nobranch failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# should not be a branch table
# expect not to find 'augustus.finknottle' whose code is 100% covered in owner table
for owner in augustus.finknottle ; do
    grep $owner differential_nobranch/index.html
    if [ 1 != $? ] ;then
        echo "ERROR: found $owner in differential_nobranch owner summary"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done
for summary in Branch ; do
    grep "$summary coverage" differential_nobranch/index.html
    if [ 1 != $? ] ;then
        echo "ERROR: found $summary in differential_nobranch summary"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done


# with no sourceview
echo genhtml $DIFFCOV_OPTS --no-sourceview -branch-coverage --baseline-file ./baseline_nobranch.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners --ignore-errors source -o ./differential_nosource ./current.info $IGNORE $POPUP
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --no-sourceview --branch-coverage --baseline-file ./baseline_nobranch.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners --ignore-errors source -o ./differential_nosource ./current.info $GENHTML_PORT $IGNORE $POPUP
if [ 0 != $? ] ; then
    echo "ERROR: genhtml differential_nosource failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# should be no source directory..
if [ -e differential_nosource/simple/test.cpp.gcov.html ] ; then
    echo "expected no source..but found some"
fi

# check case that we have a diff file but no baseline
echo genhtml $DIFFCOV_OPTS ./current.info --diff-file diff.txt -o ./diff_no_baseline $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS ./current.info --diff-file diff.txt -o ./diff_no_baseline $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: genhtml diff_no_baseline failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# and the inverse difference
rm -f test.cpp
ln -s simple.cpp test.cpp
diff -u simple2.cpp simple.cpp | sed -e "s|simple2*\.cpp|$ROOT/test.cpp|g" > diff_r.txt

# make the version number look different so the new diff file
#  consistency check will pass
sed -E 's/VER:#1/VER:#2/' current.info > current_hacked.info

# will get MD5 mismatch unless we have the simple.cpp and simple.cpp files
# set up in the expected places
echo genhtml $DIFFCOV_OPTS --baseline-file ./current_hacked.info --diff-file diff_r.txt -o ./reverse ./baseline_orig.info $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --baseline-file ./current_hacked.info --diff-file diff_r.txt -o ./reverse ./baseline_orig.info $GENHTML_PORT $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: genhtml branch failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# just ignore the new diff file/version ID mismatch message -
# obviously, some of the inputs here are cobbled together rather than
# entirely generated by the numbers. Kind of painful to re-create everything
echo genhtml $DIFFCOV_OPTS --baseline-file ./current_hacked.info --diff-file diff_r.txt -o ./reverse_nobranch ./baseline_nobranch.info.gz $IGNORE --ignore inconsistent,version
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --baseline-file ./current_hacked.info --diff-file diff_r.txt -o ./reverse_nobranch ./baseline_nobranch.info.gz $GENHTML_PORT $IGNORE --ignore inconsistent,version
if [ 0 != $? ] ; then
    echo "ERROR: genhtml reverse_nobranch failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# point to 'new' file now...
rm -f test.cpp
ln -s simple2.cpp test.cpp

echo genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script ./annotate.sh -o ./no_owners ./current.info $IGNORE
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script ./annotate.sh -o ./no_owners ./current.info $GENHTML_PORT $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: genhtml no_owners failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# expect to not find ownership summary table...
for summary in ownership ; do
    grep $summary no_owners/index.html
    if [ 1 != $? ] ;then
        echo "ERROR: found $summary in no_owners summary"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
           exit 1
        fi
    fi
done

echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt -o ./no_annotation ./current.info $IGNORE --rc scope_regexp='test.cpp'
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff.txt -o ./no_annotation ./current.info $GENHTML_PORT $IGNORE --rc scope_regexp='test.cpp'
if [ 0 != $? ] ; then
    echo "ERROR: genhtml no_annotation failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# expect to find differential TLAs - but don't expect ownership and date tables
for key in UNC LBC UIC UBC GBC GIC GNC CBC EUB ECB DUB DCB ; do
    grep $key no_annotation/index.html
    if [ 0 != $? ] ;then
        echo "ERROR: did not find $key in no_annotation summary"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done
for key in "date bins" "ownership bins" ; do
    grep "$key" no_annotation/index.html
    if [ 1 != $? ] ; then
        echo "ERROR: found $key in no_annotation summary"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners -o ./no_baseline ./current.info $IGNORE
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --annotate-script `pwd`/annotate.sh --show-owners -o ./no_baseline ./current.info $GENHTML_PORT $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: genhtml no_baseline failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# don't expect to find differential TLAs - but still expect ownership and date tables
for key in "date bins" "ownership bins" ; do
    grep "$key" no_baseline/index.html
    if [ 0 != $? ] ;then
        echo "ERROR: did not find $key in no_baseline summary"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done
for key in UNC LBC UIC UBC GBC GIC GNC CBC EUB ECB DUB DCB ; do
    grep $key no_baseline/index.html
    if [ 1 != $? ] ;then
        echo "ERROR: found $key in no_baseline summary"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done


echo "now some error checking and issue workaround tests..."

# - first, create a 'diff' file whose pathname is not quite right..
sed -e "s#/simple/test#/badPath/test#g" diff.txt > diff_broken.txt

# now run genhtml - expect to see an error:
# skip new diff/version inconsistency message
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --simplified-colors -o ./broken ./current.info.gz $IGNORE --ignore inconsistent
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --simplified-colors -o ./broken ./current.info.gz $IGNORE --ignore inconsistent 2>&1 | tee err.log

if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR:  expected error but didn't see it"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

grep -i "Error: .* possible path inconsistency" err.log
if [ 0 != $? ] ; then
    echo "ERROR:  can't find expected error message"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# now run genhtml - expect to see an warning:
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors path --simplified-colors -o ./mismatchPath ./current.info.gz $IGNORE --ignore inconsistent
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --ignore-errors path --simplified-colors -o ./mismatchPath ./current.info.gz $IGNORE --ignore inconsistent 2>&1 | tee warn.log

if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR:  expected warning but didn't see it"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

grep -i 'Warning: .* possible path inconsistency' warn.log
if [ 0 != $? ] ; then
    echo "ERROR:  can't find expected warning message"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# now use the 'elide' feature to avoid the error
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --elide-path-mismatch --simplified-colors -o ./elidePath ./current.info.gz $IGNORE --ignore inconsistent
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff_broken.txt --annotate-script `pwd`/annotate.sh --show-owners all --show-noncode --elide-path-mismatch --simplified-colors -o ./elidePath ./current.info.gz $IGNORE --ignore inconsistent 2>&1 | tee elide.log

if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR:  expected success but didn't see it"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

grep "has same basename" elide.log
if [ 0 != $? ] ; then
    echo "ERROR:  can't find expected warning message"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# test criteria-related RC override errors:
for errs in 'criteria_callback_levels=dir,a' 'criteria_callback_data=foo' ; do
    echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --criteria $CRITERIA -o $outdir ./current.info --rc $errs $IGNORE
    $COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --criteria $CRITERIA -o criteria ./current.info $GENHTML_PORT --rc $errs $IGNORE > criteriaErr.log 2> criteriaErr.err
    if [ 0 == $? ] ; then
        echo "ERROR: genhtml criteria should have failed but didn't"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    grep -E "invalid '.+' value .+ expected" criteriaErr.err
    if [ 0 != $? ] ;then
        echo "ERROR: 'invalid criteria option message is missing"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done


# test 'coverage criteria' callback - both script and module
for mod in '' '.pm' ; do
    #  we expect to fail - and to see error message - it coverage criteria not met
    # ask for date and owner data - even though the callback doesn't use it
    echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --criteria $CRITERIA$mod -o criteria$mod ./current.info --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file $IGNORE
    $COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --criteria $CRITERIA$mod --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file -o criteria$mod ./current.info $GENHTML_PORT $IGNORE > criteria$mod.log 2> criteria$mod.err
    if [ 0 == $? ] ; then
        echo "ERROR: genhtml criteria should have failed but didn't"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    # signoff should pass...
    echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --criteria $CRITERIA$mod --criteria --signoff -o criteria_signoff$mod ./current.info --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file $IGNORE
    $COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --criteria $CRITERIA$mod --criteria --signoff --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file -o criteria_signoff$mod ./current.info $GENHTML_PORT $IGNORE > criteria_signoff$mod.log 2> criteria_signoff$mod.err
    if [ 0 != $? ] ; then
        echo "ERROR: genhtml criteria signoff should have passed but didn't"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    if [[ $OPTS =~ "show-details" ]] ; then
        found=0
    else
        found=1
    fi
    grep "Failed coverage criteria" criteria$mod.log
    # expect to find the string (0 return val) if flag is present
    if [ 0 != $? ] ;then
        echo "ERROR: 'criteria fail message not matched"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    for suffix in '' '_signoff' ; do
        if [ 'x' == "x$suffix" ] ; then
            SIGNOFF_ERR=0
        else
            # we don't expect to see error, if signoff
            SIGNOFF_ERR=1
        fi
        for l in criteria$suffix$mod.log criteria$suffix$mod.err ; do
            FOUND=0
            if [[ $l =~ "err" ]] ; then
                # don't expect to find message in stderr, if signoff
                FOUND=$SIGNOFF_ERR
            fi
            grep "UNC + LBC + UIC != 0" $l
            # expect to find the string (0 return val) if flag is present
            if [ $FOUND != $? ] ;then
                echo "ERROR: 'criteria string not matching in  $l"
                status=1
                if [ 0 == $KEEP_GOING ] ; then
                    exit 1
                fi
            fi
        done
    done
done


# test 'coverage criteria' callback
#  we expect to fail - and to see error message - it coverage criteria not met
# ask for date and owner data - even though the callback doesn't use it
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --criteria "$CRITERIA --signoff" -o $outdir ./current.info --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file $IGNORE
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --criteria "$CRITERIA --signoff" --rc criteria_callback_data=date,owner --rc criteria_callback_levels=top,file -o criteria ./current.info $GENHTML_PORT $IGNORE > signoff.log 2> signoff.err
if [ 0 != $? ] ; then
    echo "ERROR: genhtml criteria --signoff did not pass"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "UNC + LBC + UIC != 0" signoff.log
# expect to find the string (0 return val) if flag is present
if [ 0 != $? ] ; then
    echo "ERROR: 'criteria string is missing from signoff.log"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# check select script
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --select "$SELECT" --select --owner --select stanley.ukeridge current.info -o select $IGNORE --validate
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --select "$SELECT" --select --owner --select stanley.ukeridge current.info -o select $IGNORE --validate
if [ 0 != $? ] ; then
    echo "ERROR: genhtml select did not pass"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
FILE=`find select -name test.cpp.gcov.html`
for owner in roderick.glossop ; do #expect to filter these guys out
    grep $owner $FILE
    if [ 0 == $? ] ; then
        echo "ERROR: did not find $owner in select group"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done
COUNT=`grep -c 'ignored lines' $FILE`
if [ 0 != $? ] ; then
    echo "ERROR: did not find elided message"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ 2 != $COUNT ] ; then
    echo "ERROR: did not find elided messages"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# check select script
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --select "$SELECT" --select --owner --select not.there current.info -o select2 $IGNORE --valideate
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source --select "$SELECT" --select --owner --select not.there current.info -o select2 $IGNORE --validate
if [ 0 != $? ] ; then
    echo "ERROR: genhtml select did not pass"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

grep 'Coverage data table is empty' select2/index.html
if [ 0 != $? ] ; then
    echo "ERROR: did not find elided message"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

NAME=`(cd select2 ; ls *.html | grep -v -E '(cmdline|profile)')`
if [ "index.html" != "$NAME" ] ; then
    echo "ERROR: expected to find only one HTML file"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# test '--show-navigation' option
# need "--ignore-unused for gcc/10.2.0 - which doesn't see code in its c++ headers
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_NOFRAME_OPTS --annotate-script `pwd`/annotate.sh --show-owners all --show-navigation -o navigation --ignore unused --exclude '*/include/c++/*' ./current.info $IGNORE
$COVER ${GENHTML_TOOL} $DIFFCOV_NOFRAME_OPTS --annotate-script `pwd`/annotate.sh --show-owners all --show-navigation -o navigation --ignore unused --exclude '*/include/c++/*' $GENHTML_PORT ./current.info $IGNORE > navigation.log 2> navigation.err

if [ 0 != $? ] ; then
    echo "ERROR: genhtml --show-navigation failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

HIT=`grep -c HIT.. navigation.log`
MISS=`grep -c MIS.. navigation.log`
if [ "$ENABLE_MCDC" != '1' ] ; then
    EXPECT_MISS=2
    EXPECT_HIT=3
else
    # MC/DC included...
    EXPECT_MISS=3
    EXPECT_HIT=4
fi
if [[ $HIT != $EXPECT_HIT || $MISS != $EXPECT_MISS ]] ; then
    echo "ERROR: 'navigation counts are wrong: hit $HIT != $EXPECT_HIT $MISS != $EXPECT_MISS"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
#look for navigation links in index.html files
for f in navigation/simple/index.html ; do
    grep -E 'href=.*#L[0-9]+.*Go to first ' $f
    if [ 0 != $? ] ; then
        status=1
        echo "ERROR:  no navigation links in $f"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done
# look for unexpected naming in HTML
for tla in GNC UNC ; do
    grep "next $tla in" ./navigation/simple/test.cpp.gcov.html
    if [ 0 == $? ] ; then
        echo "ERROR: found unexpected tla $TLA in result"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done
# look for expected naming in HTML
for tla in HIT MIS ; do
    grep "next $tla in" ./navigation/simple/test.cpp.gcov.html
    if [ 0 != $? ] ; then
        echo "ERROR: did not find expected tla $TLA in result"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done


# test file substitution option
#  need to ignore the 'missing source' error which will happen when we try to
#  filter for exclude patterns - the file 'pwd/test.cpp' does not exist
echo lcov $LCOV_OPTS --capture --directory . --output-file subst.info --substitute "s#${PWD}#pwd#g" --exclude '*/iostream' --ignore source,source $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file subst.info --substitute "s#${PWD}#pwd#g" --exclude '*/iostream' --ignore source,source $LCOV_PORT $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "pwd/test.cpp" subst.info
if [ 0 != $? ] ; then
    echo "ERROR: --substitute failed - not found in subst.info"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "iostream" subst.info
if [ 0 == $? ] ; then
    echo "ERROR: --exclude failed - found in subst.info"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "pwd/test.cpp" baseline.info
if [ 0 == $? ] ; then
    # substitution should not have happened in baseline.info
    echo "ERROR: --substitute failed - found in baseline.info"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# gcc/10 doesn't see code in its c++ headers - test will fail..
COUNT=`grep -c SF: baseline.info`
if [ $COUNT != '1' ] ; then
    grep "iostream" baseline.info
    if [ 0 != $? ] ; then
        # exclude should not have happened in baseline.info
        echo "ERROR: --exclude failed - not found in baseline.info"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
fi

echo lcov $LCOV_OPTS --capture --directory . --output-file trivial.info --filter trivial,branch $IGNORE $DERIVE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file trivial.info --filter trivial,branch $IGNORE $DERIVE
if [ 0 == $? ] ; then
    BASELINE_COUNT=`grep -c FNL: baseline.info`
    TRIVIAL_COUNT=`grep -c FNL: trivial.info`
    # expect lower function count:  we should have removed 'static_initial...
    GENERATED=`grep -c _GLOBAL__ baseline.info`
    if [[ ( 0 != $GENERATED &&
            $TRIVIAL_COUNT -ge $BASELINE_COUNT ) ||
          ( 0 == $GENERATED &&
            $TRIVIAL_COUNT != $BASELINE_COUNT) ]] ; then
        echo "ERROR:  trivial filter failed"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
else
    echo "old version of gcc doesn't support trivial function filtering because no end line"
    # try to see if we can generate the data if we ignore unsupported...
    $COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file trivial.info --filter trivial,branch $IGNORE $DERIVE --ignore unsupported
    if [ 0 != $? ] ; then
        echo "ERROR: lcov --capture trivial failed after ignoring error"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
fi

# some error checks...
# use 'no_markers' flag so we won't see the filter message
echo $LCOV_TOOL $LCOV_OPTS --output err1.info -a current.info -a current.info --substitute "s#xyz#pwd#g" --exclude 'thisStringDoesNotMatch' --no-markers
$COVER $LCOV_TOOL $LCOV_OPTS --output err1.info -a current.info -a current.info --substitute "s#xyz#pwd#g" --exclude 'thisStringDoesNotMatch' --no-markers
if [ 0 == $? ] ; then
    echo "ERROR: lcov ran despite error"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo $LCOV_TOOL $LCOV_OPTS --output unused.info -a current.info -a current.info --substitute "s#xyz#pwd#g" --exclude 'thisStringDoesNotMatch' --ignore unused --no-markers $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --output unused.info -a current.info -a current.info --substitute "s#xyz#pwd#g" --exclude 'thisStringDoesNotMatch' --ignore unused --no-markers $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: lcov failed despite suppression"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# test function "coverpoint proportion" feature
grep -E 'FNL:[0-9]+,[0-9]+,[0-9]+' baseline.info
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

echo genhtml $DIFFCOV_OPTS current.info --output-directory ./proportion --show-proportion $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS current.info --output-directory ./proportion --show-proportion $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: genhtml current proportional failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# and then a differential report...
echo ${LCOV_HOME}/bin/genhtml $OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source -o ./differential_prop ./current.info --show-proportion $IGNORE
$COVER ${GENHTML_TOOL} $OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.sh --show-owners all --ignore-errors source -o ./differential_prop ./current.info --show-proportion $GENHTML_PORT $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: genhtml differential proportional failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# and see if we find the content we expected...
for test in proportion differential_prop ; do
    for s in "unexercised branches" "unexercised lines" ; do
        if [ 0 == $NO_END_LINE ] ; then
            for f in "" '-c' '-b' '-l' ; do
                NAME=$test/simple/test.cpp.func$f.html
                grep "sort table by $s" $NAME
                if [ 0 != $? ] ; then
                    echo "did not find col '$s' in $NAME"
                    status=1
                    if [ 0 == $KEEP_GOING ] ; then
                        exit 1
                    fi
                fi
            done
        else
            for f in "" '-c' ; do
                NAME=$test/simple/test.cpp.func$f.html
                grep "sort table by $s" $NAME
                if [ 0 == $? ] ; then
                    echo "unexpected col '$s' in $NAME"
                    status=1
                    if [ 0 == $KEEP_GOING ] ; then
                        exit 1
                    fi
                fi
            done
        fi
    done
done

# check error message if nothing annotated
cp simple.cpp annotate.cpp
${CXX} $COVERAGE_OPTS -o annotate.exe --coverage annotate.cpp
if [ 0 != $? ] ; then
    echo "annotate compile failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
./annotate.exe
if [ 0 != $? ] ; then
    echo "./annotate.exe failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo lcov $LCOV_OPTS --capture --directory . --output-file annotate.info $IGNORE --include "annotate.cpp"
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file annotate.info $IGNORE --include "annotate.cpp"
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture annotate failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo genhtml $DIFFCOV_OPTS --output-directory ./annotate --annotate $ANNOTATE annotate.info
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./annotate --annotate $ANNOTATE annotate.info
if [ 0 == $? ] ; then
    echo "ERROR: annotate with no annotation"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo genhtml $DIFFCOV_OPTS --output-directory ./annotate --annotate $ANNOTATE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./annotate --annotate $ANNOTATE --ignore annotate annotate.info
if [ 0 != $? ] ; then
    echo "ERROR: annotate with no annotation ignore did not pass"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# check nonexistent --rc option (note minus on '-memory_percentage')
echo genhtml $DIFFCOV_OPTS --output-directory ./errOut --rc -memory_percentage=50 baseline_orig.info $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./errOut --rc -memory_percentage=50 baseline_orig.info $IGNORE
if [ 0 == $? ] ; then
    echo "ERROR: incorrect RC option not caught"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# check --rc formatting
echo genhtml $DIFFCOV_OPTS --output-directory ./errOut --rc memory_percentage baseline_orig.info $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./errOut --rc memory_percentage baseline_orig.info $IGNORE
if [ 0 == $? ] ; then
    echo "ERROR: incorrect RC option not caught"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# skip both errors
# ignore version error which might happen if timestamp is included
echo genhtml $DIFFCOV_OPTS --output-directory ./usage --rc memory_percentage --rc -memory_percentage=50 baseline_orig.info --ignore usage,version
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./usage --rc memory_percentage --rc percent=5 baseline_orig.info --ignore usage,version $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: didn't ignore errors"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# skip both errors - but check total message count
echo genhtml $DIFFCOV_OPTS --output-directory ./expect_err --rc memory_percentage --rc -memory_percentage=50 baseline_orig.info --ignore usage,version --expect usage:1
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./expect_err --rc memory_percentage --rc percent=5 baseline_orig.info --ignore usage,version $IGNORE --expect usage:1 2>&1 | tee expect_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: didn't catch expect count error"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "ERROR:.*count.*'usage' constraint .+ is not true" expect_err.log

# now skip the count message too
echo genhtml $DIFFCOV_OPTS --output-directory ./expect --rc memory_percentage --rc -memory_percentage=50 baseline_orig.info --ignore usage,version,count --rc expect_message_count=usage:1 --msg-log
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --output-directory ./expect --rc memory_percentage --rc percent=5 baseline_orig.info --ignore usage,version,count $IGNORE --rc expect_message_count=usage:1 --msg-log 2>&1 | tee expect.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: didn't skip expect count error"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

grep -E "WARNING:.*count.*'usage' constraint .+ is not true" expect.msg
if [ 0 == $? ] ; then
    echo "ERROR: didn't find expected msg in log"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo $SPREADSHEET_TOOL -o results.xlsx `find . -name "*.json"`
eval $SPREADSHEET_TOOL -o results.xlsx `find . -name "*.json"`
if [ 0 != $? ] ; then
    status=1
    echo "ERROR:  spreadsheet generation failed"
    exit 1
fi

if [ 0 == $status ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] ; then
    echo "Generating coverage report"
    echo ${LCOV_HOME}/bin/py2lcov -o pycov.info --testname simple --version-script $GET_VERSION $PYCOV_DB
    ${LCOV_HOME}/bin/py2lcov -o pycov.info --testname simple --version-script $GET_VERSION $PYCOV_DB

    if [ 0 != $LOCAL_COVERAGE ] ; then
        cover $COVER_DB
        ${LCOV_HOME}/bin/perl2lcov -o perlcov.info --testname simple --version-script $GET_VERSION $COVER_DB
        ${LCOV_HOME}/bin/genhtml -o html_report perlcov.info pycov.info --branch --flat --show-navigation --show-proportion --version-script $GET_VERSION --annotate-script $ANNOTATE --parallel --ignore empty,usage
        echo "see HTML report 'html_report'"
    else
        echo cp pycov.info $COVER_DB/spreadsheet.info
        cp pycov.info $COVER_DB/spreadsheet.info
    fi
fi

exit $status
