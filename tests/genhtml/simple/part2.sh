#!/bin/bash
set +x

# ============================================================================
# part2 of the former monolithic 'simple' genhtml test (see setup_common.sh).
# Covers: the noncode_differential / differential_subset owner-table loop
# (vanilla/dark/flat), the named differential report, the linked-build
# (--build-dir / --elide-path) sequence, and the big differential option-combo
# loop (--show-details / --hier).
# ============================================================================

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    rm -rf part2.d
    exit 0
fi

if ! type "${CXX}" >/dev/null 2>&1 ; then
        echo "Missing tool: $CXX" >&2
        exit 2
fi

WORKDIR=part2.d
source ./setup_common.sh

status=0

# --------------------------------------------------------------------------
# noncode_differential / differential_subset owner-table loop
# --------------------------------------------------------------------------
for opt in "" --dark-mode --flat ; do
  outDir=./noncode_differential$opt
  echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_NOFRAME_OPTS $opt --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --show-noncode --ignore-errors source --simplified-colors -o $outDir ./current.info.gz $IGNORE $POPUP
  $COVER $GENHTML_TOOL $DIFFCOV_NOFRAME_OPTS $opt --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --show-noncode --ignore-errors source --simplified-colors -o $outDir ./current.info.gz $GENHTML_PORT --save $IGNORE $POPUP
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
  echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_NOFRAME_OPTS $opt --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --simplified-colors -o $outDir ./current.info.gz $IGNORE $POPUP --rc truncate_owner_table=top,directory --rc owner_table_entries=2 --include '*simple*'
  $COVER $GENHTML_TOOL $DIFFCOV_NOFRAME_OPTS $opt --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --show-noncode --ignore-errors source --simplified-colors -o $outDir ./current.info.gz $GENHTML_PORT --save $IGNORE $POPUP --rc truncate_owner_table=top,directory --include '*simple*' --rc owner_table_entries=2
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
  if [ -d $outDir/simple/index.html ] ; then
      FILES="$FILES $outDir/simple/index.html"
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
              echo "ERROR: unexpectedly found $owner in $outDir $FILE annotations"
              status=1
              if [ 0 == $KEEP_GOING ] ; then
                  exit 1
              fi
          fi
      done
  done # for each index file

done

# --------------------------------------------------------------------------
# named differential report
# --------------------------------------------------------------------------
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline_name.info --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --show-noncode --ignore-errors source --simplified-colors -o differential_named ./current_name.info.gz $IGNORE --description names.data --serialize differential_named/coverage.dat --missed
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline_name.info --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --show-noncode --ignore-errors source --simplified-colors -o differential_named ./current_name.info.gz $GENHTML_PORT $IGNORE --description names.data --serialize differential_named/coverage.dat --missed
if [ 0 != $? ] ; then
    echo "ERROR: genhtml differential testname failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# --------------------------------------------------------------------------
# --build-dir option, using linked build
# --------------------------------------------------------------------------
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

# --------------------------------------------------------------------------
# differential option-combo loop
# --------------------------------------------------------------------------
TEST_OPTS=$DIFFCOV_OPTS
EXT=""
for opt in "" "--show-details" "--hier"; do

    for o in "" $opt ; do
        OPTS="$TEST_OPTS $o"
        outdir=./differential${EXT}${o}
        outFile=differential${EXT}${o}.log
        echo ${LCOV_HOME}/bin/genhtml $OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source -o $outdir ./current.info $IGNORE $POPUP
        $COVER ${GENHTML_TOOL} $OPTS --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source -o $outdir ./current.info $GENHTML_PORT $IGNORE $POPUP  2>&1 | tee $outFile
        if [ 0 != ${PIPESTATUS[0]} ] ; then
            echo "ERROR: genhtml $outdir failed (2)"
            status=1
            if [ 0 == $KEEP_GOING ] ; then
                exit 1
            fi
        fi
        # expect to see non-zero deleted branch count
        for tla in DUB DCB ; do
            grep -E branch:.+${tla}:[1-9] $outFile
            if [ 0 != $? ] ; then
                echo "ERROR:  did not find expected $tla branches"
                status=1
                if [ 0 == $KEEP_GOING ] ; then
                    exit 1
                fi
            fi
            if [ "$ENABLE_MCDC" == '1' ] ; then
                grep -E mcdc:.+${tla}:1 $outFile
                if [ 0 != $? ] ; then
                    echo "ERROR:  did not find expected $tla branches"
                    status=1
                    if [ 0 == $KEEP_GOING ] ; then
                        exit 1
                    fi
                fi
            fi
        done

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
    generate_coverage 'simple_2' $LOCAL_COVERAGE 1
fi

exit $status
