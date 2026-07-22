#!/bin/bash
set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    rm -rf part3.d
    exit 0
fi

# ===========================================================================
# Part 3 of the split msgtest.sh:
#   callback die() tests (version/resolve/per-callback), save/restore loops, unreach help, missingRestore, unused-src, inconsistent, epoch, highlight, subset
#
# Shared setup (compile + run test.cpp, capture initial.info/version.info)
# lives in setup_common.sh; this part runs in its own working directory
# (part3.d) so it cannot collide with the other parts.
# ===========================================================================
WORKDIR=part3.d
source ./setup_common.sh

# baseline date used by the differential reports below (was set inline in the
# original monolith; each part now needs its own).
NOW=`date`

# callback error testing
#  die() in 'extract' callback:
echo lcov $LCOV_OPTS --summary version.info --filter line --version-script ./genError.pm
$COVER $LCOV_TOOL $LCOV_OPTS --summary version.info --filter line --version-script ./genError.pm 2>&1 | tee extract_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov extract passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "extract_version.+ failed" extract_err.log
if [ 0 != $? ] ; then
    echo "ERROR: extract_version message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# pass 'extract' but die in check (need to check version in order to filter)
echo lcov $LCOV_OPTS --summary version.info --filter line --version-script ./genError.pm --version-script extract
$COVER $LCOV_TOOL $LCOV_OPTS --summary version.info --filter line --version-script ./genError.pm --version-script extract 2>&1 | tee extract_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov extract passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "compare_version.+ failed" extract_err.log
if [ 0 != $? ] ; then
    echo "ERROR: compare_version message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# pass 'extract' and 'compare' so neither callback dies, but compare_version
# RETURNS a non-zero (mismatch) status - distinct from the die() case above.
# This exercises the "callback reports mismatch" path (non-silent version
# check) rather than the exception path.
echo lcov $LCOV_OPTS --summary version.info --filter line --version-script ./genError.pm --version-script extract --version-script compare
$COVER $LCOV_TOOL $LCOV_OPTS --summary version.info --filter line --version-script ./genError.pm --version-script extract --version-script compare 2>&1 | tee compare_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov compare mismatch passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "revision control version mismatch" compare_err.log
if [ 0 != $? ] ; then
    echo "ERROR: compare_version mismatch message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# resolve
# apply substitution to ensure that the file is not found so the resolve callback
# is called
echo lcov $LCOV_OPTS --summary initial.info --rc case_insensitive=1 --filter branch --resolve ./genError.pm --substitute s/test.cpp/noSuchFile.cpp/i
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --rc case_insensitive=1 --filter branch --resolve ./genError.pm --substitute s/test.cpp/noSuchFile.cpp/i 2>&1 | tee resolve_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --summary resolve"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "resolve.+ failed" resolve_err.log
if [ 0 != $? ] ; then
    echo "ERROR: resolve message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

for callback in select annotate criteria simplify unreachable ; do

  echo genhtml $DIFFCOV_OPTS initial.info -o $callback --${callback}-script ./genError.pm
  $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o $callback --${callback}-script ./genError.pm 2>&1 | tee ${callback}_err.log
  if [ 0 == ${PIPESTATUS[0]} ] ; then
      echo "ERROR: genhtml $callback error passed by accident"
      if [ 0 == $KEEP_GOING ] ; then
          exit 1
      fi
  fi
  grep -E "${callback}.* failed" ${callback}_err.log
  if [ 0 != $? ] ; then
      echo "ERROR: $callback message"
      if [ 0 == $KEEP_GOING ] ; then
          exit 1
      fi
  fi
done

# check callback fails in save/restore/start/finalize callbacks
SKIP_ARG=''
for cb in start save restore finalize ; do
  echo genhtml $DIFFCOV_OPTS initial.info -o simplify_$cb --simplify-script ./parallelFail.pm$SKIP_ARG --parallel
  LCOV_FORCE_PARALLEL=1 $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o simplify_$cb --simplify-script ./parallelFail.pm$SKIP_ARG --parallel 2>&1 | tee simplify_${cb}_err.log
  if [ 0 == ${PIPESTATUS[0]} ] ; then
      echo "ERROR: genhtml simplify '$cb' passed by accident"
      if [ 0 == $KEEP_GOING ] ; then
          exit 1
      fi
  fi
  SKIP_ARG="$SKIP_ARG,$cb"
  grep -E "parallelFail->${cb}.* failed" simplify_${cb}_err.log
  if [ 0 != $? ] ; then
      echo "ERROR: $cb message"
      if [ 0 == $KEEP_GOING ] ; then
          exit 1
      fi
  fi
done

# test help message in 'unreach.pm'
echo genhtml $DIFFCOV_OPTS initial.info -o help --unreachable $SCRIPT_DIR/unreach.pm,--help --parallel $ignore
LCOV_FORCE_PARALLEL=1 $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o help --unreachable $SCRIPT_DIR/unreach.pm,--help --parallel $ignore 2>&1 | tee unreach_help.log

if [ 0 == ${PIPESTATUS[0]} ] ; then

    echo "ERROR: genhtml missing help message from unreach.pm"
    if [ 0 == $KEEP_GOING ] ; then
	exit 1
    fi
fi
grep "Both branch and MC/DC filtering" unreach_help.log
if [ 0 != $? ] ; then
    echo "ERROR: unreach help message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


for ignore in '' '--ignore package' ; do
    echo genhtml $DIFFCOV_OPTS initial.info -o missingRestore --simplify-script ./missingRestore.pm --parallel $ignore
    LCOV_FORCE_PARALLEL=1 $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o missingRestore --simplify-script ./missingRestore.pm --parallel $ignore 2>&1 | tee missingRestore.log
    status=${PIPESTATUS[0]}
    if [ '' == "$ignore" ] ; then
	if [ 0 == $status ] ; then
	    echo "ERROR: genhtml missing restore passed by accident"
	    if [ 0 == $KEEP_GOING ] ; then
		exit 1
	    fi
	fi
    else
	if [ 0 != $status ] ; then
	    echo "ERROR: genhtml ignore missing restore failed"
	    if [ 0 == $KEEP_GOING ] ; then
		exit 1
	    fi
	fi
    fi
    grep "implements 'save' but not 'restore'" missingRestore.log
    if [ 0 != $? ] ; then
	echo "ERROR: missingRestore message"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
done


echo genhtml $DIFFCOV_OPTS initial.info -o unused_src --source-dir ../..
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o unused_src --source-dir ../.. 2>&1 | tee src_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml source-dir error passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E -- '"--source-directory ../.." is unused' src_err.log
if [ 0 != $? ] ; then
    echo "ERROR: missing srcdir message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# inconsistent setting of branch filtering without enabling branch coverage
echo genhtml --filter branch --prefix $PARENT_VERSION $PROFILE initial.info -o inconsistent --rc treat_warning_as_error=1
$COVER $GENHTML_TOOL --filter branch --prefix $PARENT_VERSION $PROFILE initial.info -o inconsistent --rc treat_warning_as_error=1 2>&1 | tee inconsistent.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml inconsistent warning-as-error passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep 'ERROR: (usage) branch filter enabled but neither branch or condition coverage is enabled' inconsistent.log
if [ 0 != $? ] ; then
    echo "ERROR: missing inconsistency message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# when we treat warning as error, but ignore the message type
echo genhtml --filter branch --prefix $PARENT_VERSION $PROFILE initial.info -o inconsistent --rc treat_warning_as_error=1 --ignore usage
$COVER $GENHTML_TOOL --filter branch --prefix $PARENT_VERSION $PROFILE initial.info -o inconsistent --rc treat_warning_as_error=1 --ignore usage 2>&1 | tee inconsistent.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml inconsistent warning-as-error passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep 'WARNING: (usage) branch filter enabled but neither branch or condition coverage is enabled' inconsistent.log
if [ 0 != $? ] ; then
    echo "ERROR: missing inconsistency message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo genhtml --filter branch --prefix $PARENT_VERSION $PROFILE initial.info -o inconsistent
$COVER $GENHTML_TOOL --filter branch --prefix $PARENT_VERSION $PROFILE initial.info -o inconsistent 2>&1 | tee inconsistent2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml inconsistent warning-as-error failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep 'WARNING: (usage) branch filter enabled but neither branch or condition coverage is enabled' inconsistent2.log
if [ 0 != $? ] ; then
    echo "ERROR: missing inconsistency message 2"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# use jan1 1970 as epoch
echo SOURCE_DATE_EPOCH=0 genhtml $DIFFCOV_OPTS initial.info -o epoch
SOURCE_DATE_EPOCH=0 $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info --annotate $ANNOTATE_SCRIPT -o epoch 2>&1 | tee epoch.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: missed epoch error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "ERROR: \(inconsistent\) .+ 'SOURCE_DATE_EPOCH=0' .+ is older than annotate time" epoch.log
if [ 0 != $? ] ; then
    echo "ERROR: missing epoch"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# removed option
echo genhtml $DIFFCOV_OPTS initial.info -o highlight --highlight
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info --annotate $ANNOTATE_SCRIPT --highlight -o highlight 2>&1 | tee highlight.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: missed decprecated error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "Unknown option: highlight" highlight.log
if [ 0 != $? ] ; then
    echo "ERROR: missing highlight message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

for err in "--rc truncate_owner_table=top,x" "--rc owner_table_entries=abc" "--rc owner_table_entries=-1" ; do
    echo genhtml $DIFFCOV_OPTS initial.info -o subset --annotate $ANNOTATE_SCRIPT --baseline-file initial.info --show-owners $IGNORE_ANNOTATE
    $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o subset --annotate $ANNOTATE_SCRIPT --baseline-file initial.info --title 'subset' --header-title 'this is the header' --date-bins 1,5,22 --baseline-date "$NOW" --prefix x --no-prefix $err --show-owners $IGNORE_ANNOTATE
    if [ 0 == $? ] ; then
        echo "ERROR: genhtml $err unexpectedly passed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'message_3' $LOCAL_COVERAGE
fi

echo "Tests passed"
