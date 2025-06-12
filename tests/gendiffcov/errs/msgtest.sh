#!/bin/bash
set +x

source ../../common.tst

rm -f test.cpp *.gcno *.gcda a.out *.info *.log *.json diff.txt loop*.rc markers.err*
rm -rf select criteria annotate empty unused_src scriptErr scriptFixed epoch inconsistent highlight etc mycache cacheFail expect subset context labels sortTables

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type "${CXX}" >/dev/null 2>&1 ; then
        echo "Missing tool: $CXX" >&2
        exit 2
fi

SELECT_SCRIPT=$SCRIPT_DIR/select.pm
CRITERIA_SCRIPT=$SCRIPT_DIR/criteria.pm
GITBLAME_SCRIPT=$SCRIPT_DIR/gitblame.pm
GITVERSION_SCRIPT=$SCRIPT_DIR/gitversion.pm
P4VERSION_SCRIPT=$SCRIPT_DIR/P4version.pm

if [ 1 == "$USE_GIT" ] ; then
    # this is git
    VERSION_SCRIPT=${SCRIPT_DIR}/gitversion.pm
    ANNOTATE_SCRIPT=${SCRIPT_DIR}/gitblame.pm
else
    VERSION_SCRIPT=${SCRIPT_DIR}/getp4version
    ANNOTATE_SCRIPT=${SCRIPT_DIR}/p4annotate.pm
fi


# filter out the compiler-generated _GLOBAL__sub_... symbol
LCOV_BASE="$EXTRA_GCOV_OPTS --branch-coverage $PARALLEL $PROFILE --no-external --ignore unused,unsupported --erase-function .*GLOBAL.*"
LCOV_OPTS="$LCOV_BASE"
DIFFCOV_OPTS="--filter line,branch,function --function-coverage --branch-coverage --demangle-cpp --prefix $PARENT_VERSION $PROFILE "


# old version of gcc has inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    # can't get branch coverpoints in 'initial' mode, with ancient GCC
    IGNORE="--ignore usage"
elif [ "${VER[0]}" -ge 14 ] ; then
    ENABLE_MCDC=1
    BASE_OPTS="$BASE_OPTS --mcdc"
    # enable MCDC
    COVERAGE_OPTS="-fcondition-coverage"
fi

echo `which gcov`
echo `which lcov`

ln -s ../simple/simple.cpp test.cpp
${CXX} --coverage test.cpp
./a.out

# some warnings..
echo lcov $LCOV_OPTS --capture --directory .  --initial --all --output-file initial.info --test-name myTest $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --initial --all --output-file initial.info --test-name myTest $IGNORE 2>&1 | tee initial_all.log
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -- "'--all' ignored" initial_all.log
if [ 0 != $? ] ; then
    echo "ERROR: missing ignore message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# need data for version error message checking as well
echo lcov $LCOV_OPTS --capture --directory .  --output-file version.info --test-name myTest --version-script $SCRIPT_DIR/getp4version
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory .  --output-file version.info --test-name myTest --version-script $SCRIPT_DIR/getp4version | tee version.log
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# help message
for T in "$GENHTML_TOOL" "$LCOV_TOOL" "$GENINFO_TOOL" ; do
    echo  "'$T' --help"
    $COVER $T --help
    if [ 0 != $? ] ; then
        echo "unsuccessful $T help"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    echo  "'$T' --noSuchOppt"
    $COVER $T --noSuchOpt
    if [ 0 == $? ] ; then
        echo "didn't catch missing opt"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

# generate some usage errors..
echo lcov $LCOV_OPTS --list initial.info --initial
$COVER $LCOV_TOOL $LCOV_OPTS --list initial.info --initial 2>&1 | tee initial_warn.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --list failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "'--initial' is ignored" initial_warn.log
if [ 0 != $? ] ; then
    echo "ERROR: missing ignore message 2"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# invalid syntax test:
cp initial.info badRecord.info
echo "MDCD:0,1,t,1,1,abc" >> badRecord.info
echo lcov $LCOV_OPTS --summary badRecord.info --msg-log badRecord.log
$COVER $LCOV_TOOL $LCOV_OPTS --summary badRecord.info --msg-log badRecord.log
if [ 0 == $? ] ; then
    echo "ERROR: missing format message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep 'unexpected .info file record' badRecord.log
if [ 0 != $? ] ; then
    echo "ERROR: failed to find format message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo lcov $LCOV_OPTS --summary initial.info --prune
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --prune 2>&1 | tee prune_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --summary 3 failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep 'prune-tests has effect' prune_err.log
if [ 0 != $? ] ; then
    echo "ERROR: missing ignore message 2"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo lcov $LCOV_OPTS --summary initial.info --prune --ignore usage
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --prune --ignore usgae 2>&1 | tee prune_warn.log

echo lcov $LCOV_OPTS --capture -d . -o build.info --build-dir x/y
$COVER $LCOV_TOOL $LCOV_OPTS --capture -d . -o build.info --build-dir x/y 2>&1 | tee build_dir_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --list failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "'x/y' is not a directory" build_dir_err.log
if [ 0 != $? ] ; then
    echo "ERROR: missing build dir message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo geninfo $LCOV_OPTS --no-markers --filter branch . -o usage1.info --msg-log markers.err
$GENINFO_TOOL $LCOV_OPTS --no-markers --filter branch . -o usage1.info --msg-log markers.err
if [ 0 == $? ] ; then
    echo "ERROR: expected usage error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "use new '--filter' option or old" markers.err
if [ 0 != $? ] ; then
    echo "ERROR: didint find usage error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo lcov $LCOV_OPTS --summary initial.info --config-file noSuchFile --ignore usage
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --config-file noSuchFile --ignore usgae 2>&1 | tee err_missing.log
grep "cannot read configuration file 'noSuchFile'" err_missing.log
if [ 0 != $? ] ; then
    echo "ERROR: missing config file message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# loop in config file inclusion
echo "config_file = loop1.rc" > loop1.rc
echo lcov $LCOV_OPTS --summary initial.info --config-file loop1.rc --ignore usage
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --config-file loop1.rc --ignore usage 2>&1 | tee err_selfloop.log
grep "config file inclusion loop" err_selfloop.log
if [ 0 != $? ] ; then
    echo "ERROR: missing config file message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo "config_file = loop3.rc" > loop2.rc
echo 'config_file = $ENV{PWD}/loop2.rc' > loop3.rc
echo lcov $LCOV_OPTS --summary initial.info --config-file loop2.rc --ignore usage
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --config-file loop2.rc --ignore usage 2>&1 | tee err_loop.log
grep "config file inclusion loop" err_loop.log
if [ 0 != $? ] ; then
    echo "ERROR: missing config file message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo lcov $LCOV_OPTS --capture -d . -o build.info --build-dir $LCOV_HOME
$COVER $LCOV_TOOL $LCOV_OPTS --capture -d . -o build.info --build-dir $LCOV_HOME 2>&1 | tee build_dir_unused.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --list failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "\"--build-directory .* is unused" build_dir_unused.log
if [ 0 != $? ] ; then
    echo "ERROR: missing build dir unused message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo lcov $LCOV_OPTS --summary initial.info --rc memory_percentage=-10
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --rc memory_percentage=-10 2>&1 | tee mem_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --summary 4 failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "memory_percentage '-10' " mem_err.log
if [ 0 != $? ] ; then
    echo "ERROR: missing percent message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo lcov $LCOV_OPTS --summary initial.info --rc memory_percentage=-10 --ignore usage
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --rc memory_percentage=-10 --ignore usage 2>&1 | tee mem_warn.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov memory usage failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo genhtml $DIFCOV_OPTS initial.info -o select --select-script $SELECT_SCRIPT --select-script -x
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o select --select-script $SELECT_SCRIPT --select-script -x 2>&1 | tee script_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml select passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "unable to create callback from" script_err.log
if [ 0 != $? ] ; then
    echo "ERROR: missing script message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


for arg in "--select-script $SELECT_SCRIPT,--range,0:10" \
               "--criteria-script $CRITERIA_SCRIPT,--signoff" \
               "--annotate-script $ANNOTATE_SCRIPT" \
               "--annotate-script $GITBLAME_SCRIPT,mediatek.com,--p4" \
               "--annotate-script $GITBLAME_SCRIPT,--p4" \
               "--annotate-script $GITBLAME_SCRIPT" \
               " --ignore version --version-script $GITVERSION_SCRIPT,--md5,--p4" \
           ; do
    echo genhtml $DIFCOV_OPTS initial.info -o scriptErr ${arg},-x
    $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o scriptErr ${arg},-x 2>&1 | tee script_err.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "ERROR: genhtml scriptErr passed by accident"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    grep "unable to create callback from" script_err.log
    if [ 0 != $? ] ; then
        echo "ERROR: missing script message"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    # run again  without error
    echo genhtml $DIFCOV_OPTS initial.info -o scriptFixed ${arg}
    $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o scriptFixed ${arg} --ignore annotate 2>&1 | tee script_err.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "ERROR: genhtml scriptFixed failed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

echo genhtml $DIFCOV_OPTS initial.info -o sortTables --sort
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o sortTables --sort 2>&1 | tee sort.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml --sort failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "is deprecated and will be removed" sort.log
if [ 0 != $? ] ; then
    echo "ERROR: missing --sort message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo genhtml $DIFCOV_OPTS initial.info -o p4err --version-script $P4VERSION_SCRIPT,-x
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o p4err --version-script $P4VERSION_SCRIPT,-x 2>&1 | tee p4err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml select passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "unable to create callback from" p4err.log
if [ 0 != $? ] ; then
    echo "ERROR: missing script message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo genhtml $DIFCOV_OPTS initial.info -o select --select-script ./select.sh --rc compute_file_version=1
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o select --select-script ./select.sh  --rc compute_file_version=1 2>&1 | tee select_scr.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml compute_version failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ 0 != $? ] ; then
    echo "ERROR: trivial select failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "'compute_file_version=1' option has no effect" select_scr.log
if [ 0 != $? ] ; then
    echo "ERROR: missing script message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

if [ $IS_GIT == 0 ] && [ $IS_P4 == 0 ] ; then
    IGNORE_ANNOTATE='--ignore annotate'
fi

# and again, as a differential report with annotation
NOW=`date`
rm -rf mycache
echo genhtml $DIFCOV_OPTS initial.info -o select --select-script ./select.sh --annotate $ANNOTATE_SCRIPT,--cache,mycache --baseline-file initial.info $IGNORE_ANNOTATE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o select --select-script ./select.sh --annotate $ANNOTATE_SCRIPT,--cache,mycache --baseline-file initial.info --title 'selectExample' --header-title 'this is the header' --date-bins 1,5,22 --baseline-date "$NOW" --prefix x --no-prefix  $IGNORE_ANNOTATE 2>&1 | tee select_scr.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml cache failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

if [ ! -d mycache ] ; then
    echo "did not create 'mycache'"
fi

#break the cached data - cause corruption error
for i in `find mycache -type f` ; do
    echo $i
    echo xyz > $i
done
# have to ignore version mismatch becaure p4annotate also computes version
echo genhtml $DIFCOV_OPTS initial.info -o cacheFail --select-script ./select.sh --annotate $ANNOTATE_SCRIPT,--cache,mycache --baseline-file initial.info --ignore version $IGNORE_ANNOTATE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o cacheFail --select-script ./select.sh --annotate $ANNOTATE_SCRIPT,--cache,mycache --baseline-file initial.info --title 'selectExample' --header-title 'this is the header' --date-bins 1,5,22 --baseline-date "$NOW" --prefix x --no-prefix --ignore version $IGNORE_ANNOTATE 2>&1 | tee cacheFail.log

if [ '' == $IGNORE_ANNOTATE ] ; then
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "ERROR: genhtml corrupt deserialize failed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    grep -E "corrupt.*unable to deserialize" cacheFail.log
    if [ 0 != $? ] && [ '' == $IGNORE_ANNOTATE ]; then
        echo "ERROR: failed to find cache corruption"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
fi

# make cache file unreadable
find mycache -type f -exec chmod ugo-r {} \;
echo genhtml $DIFCOV_OPTS initial.info -o cacheFail --select-script ./select.sh --annotate $ANNOTATE_SCRIPT,--cache,mycache --baseline-file initial.info $IGNORE_ANNOTATE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o cacheFail --select-script ./select.sh --annotate $ANNOTATE_SCRIPT,--cache,mycache --baseline-file initial.info --title 'selectExample' --header-title 'this is the header' --date-bins 1,5,22 --baseline-date "$NOW" --prefix x $IGNORE_ANNOTATE --no-prefix 2>&1 | tee cacheFail2.log

if [ '' == $IGNORE_ANNOTATE ] ; then
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "ERROR: genhtml unreadable cache failed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    grep -E "callback.*can't open" cacheFail2.log
    if [ 0 != $? ] ; then
        echo "ERROR: failed to find cache error"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
fi

# differential report with empty diff file
touch diff.txt
echo genhtml $DIFCOV_OPTS initial.info -o empty --diff diff.txt --annotate $ANNOTATE_SCTIPT --baseline-file initial.info
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o empty --diff diff.txt --annotate $ANNOTATE_SCRIPT --baseline-file initial.info 2>&1 | tee empty_diff.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml did not fail empty diff eheck"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "'diff' data file diff.txt contains no differences" empty_diff.log
if [ 0 != $? ] ; then
    echo "ERROR: missing empty message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# insensitive flag with case-sensitive substitute expr
#   - this will trigger multiple usage messages, but we set the max count
#     to 1 (one) - to also trigger a 'count exceeded' message.
echo lcov $LCOV_OPTS --summary initial.info --substitute 's#aBc#AbC#' --substitute 's@XyZ#xyz#i' --rc case_insensitive=1 --ignore source --rc max_message_count=1
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --substitute 's#aBc#AbC#' --rc case_insensitive=1 --ignore source --rc max_message_count=1 2>&1 | tee insensitive.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --summary insensitive"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep " --substitute pattern 's#aBc#AbC#' does not seem to be case insensitive" insensitive.log
if [ 0 != $? ] ; then
    echo "ERROR: missing insensitive message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep " (count) max_message_count=1 reached for 'usage' messages: no more will be reported." insensitive.log
if [ 0 != $? ] ; then
    echo "ERROR: missing max count message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# callback error testing
#  die() in 'extract' callback:
echo lcov $LCOV_OPTS --summary version.info --filter line--version-script ./genError.pm
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

for callback in select annotate criteria ; do

  echo genhtml $DIFCOV_OPTS initial.info -o $callback --${callback}-script ./genError.pm
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

echo genhtml $DIFCOV_OPTS initial.info -o unused_src --source-dir ../..
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

# deprecated messages
echo genhtml $DIFFCOV_OPTS initial.info -o highlight --highlight
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info --annotate $ANNOTATE_SCRIPT --highlight -o highlight 2>&1 | tee highlight.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: missed decprecated error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "ERROR: \(deprecated\) .*option .+ has been removed" highlight.log
if [ 0 != $? ] ; then
    echo "ERROR: missing highlight message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

mkdir -p etc
echo "genhtml_highlight = 1" > etc/lcovrc
echo genhtml $DIFFCOV_OPTS initial.info -o highlight --config-file LCOV_HOME/etc/lcovrc $IGNORE_ANNOTATE
LCOV_HOME=. $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info --annotate $ANNOTATE_SCRIPT -o highlight $IGNORE_ANNOTATE 2>&1 | tee highlight2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: deprecated error was fatal"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "WARNING: \(deprecated\) .+ deprecated and ignored" highlight2.log
if [ 0 != $? ] ; then
    echo "ERROR: missing decrecated message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

for err in "--rc truncate_owner_table=top,x" "--rc owner_table_entries=abc" "--rc owner_table_entries=-1" ; do
    echo genhtml $DIFCOV_OPTS initial.info -o subset --annotate $ANNOTATE_SCRIPT --baseline-file initial.info --show-owners $IGNORE_ANNOTATE
    $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o subset --annotate $ANNOTATE_SCRIPT --baseline-file initial.info --title 'subset' --header-title 'this is the header' --date-bins 1,5,22 --baseline-date "$NOW" --prefix x --no-prefix $err --show-owners $IGNORE_ANNOTATE
    if [ 0 == $? ] ; then
        echo "ERROR: genhtml $err unexpectedly passed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done


# test error checks for --expect-message-count expressions
for expr in "malformed" "noSuchMsg:%C<5" "inconsistent:%c<5" 'inconsistent:%C<$x' 'inconsistent:0,inconsistent:2' ; do

    $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o expect --annotate $ANNOTATE_SCRIPT --baseline-file initial.info --title 'subset' --header-title 'this is the header' --date-bins 1,5,22 --baseline-date "$NOW" --prefix x --no-prefix --expect-message $expr --show-owners $IGNORE_ANNOTATE
    if [ 0 == $? ] ; then
        echo "ERROR: genhtml $expr unexpectedly passed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o expect --annotate $ANNOTATE_SCRIPT --baseline-file initial.info --title 'subset' --header-title 'this is the header' --date-bins 1,5,22 --baseline-date "$NOW" --prefix x --no-prefix --expect-message $expr --show-owners --ignore usage $IGNORE_ANNOTATE
    if [ 0 != $? ] ; then
        echo "ERROR: genhtml $expr with ignore unexpectedly failed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

# slightly more complicated case...hack a bit so that 'expect' eval fails
#  in summary callback
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o context --annotate $ANNOTATE_SCRIPT --baseline-file initial.info --title 'context' --header-title 'this is the header' --date-bins 1,5,22 --baseline-date "$NOW" --prefix x --no-prefix --context-script ./MsgContext.pm --expect-message 'usage:MsgContext::test(%C)' --show-owners --ignore callback $IGNORE_ANNOTATE 2>&1 | tee expect.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml context with ignore unexpectedly failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "WARNING: .*callback.* evaluation of .+ failed" expect.log
if [ 0 != $? ] ; then
    echo "ERROR: didn't find expected callback message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# generate error for case that number of date labels doesn't match
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o labels --annotate $ANNOTATE_SCRIPT --baseline-file initial.info --title 'context' --header-title 'this is the header' --date-bins 1,5,22 --date-labels a,b,c,d,e --baseline-date "$NOW" --msg-log labels.log $IGNORE_ANNOTATE
if [ 0 == $? ] ; then
    echo "ERROR: genhtml --date-labels didn't fail"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "ERROR: .*usage.* expected number of 'age' labels to match" labels.log
if [ 0 != $? ] ; then
    echo "ERROR: didn't find expected labels message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

if [ "$ENABLE_MCDC" != 1 ] ; then
    $COVER $GENINFO_TOOL . -o mccd --mcdc-coverage $LCOV_OPTS --msg-log mcdc_errs.log
    if [ 0 == $? ] ; then
        echo "ERROR: no error for unsupported MC/DC"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    
    grep -E "MC/DC coverage enabled .* does not support the .* option" mcdc_errs.log
    if [ 0 != $? ] ; then
        echo "ERROR: didn't find expected MCDC error"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

fi

$COVER $LCOV_TOOL -o err.info -a mcdc_errs.dat --mcdc-coverage $LCOV_OPTS --msg-log mcdc_expr.log --ignore format,inconsistent,source
if [ 0 != $? ] ; then
    echo "ERROR: didn't ignore MC/DC errors"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "MC/DC group .* expression .* changed from" mcdc_expr.log
if [ 0 != $? ] ; then
    echo "ERROR: did not see MC/DC expression error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "MC/DC group .* non-contiguous expression .* found" mcdc_expr.log
if [ 0 != $? ] ; then
    echo "ERROR: did not see MC/DC contiguous error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "unexpected line number .* in condition data record .*" mcdc_expr.log
if [ 0 != $? ] ; then
    echo "ERROR: did not see MC/DC contiguous error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

if [ -d mycache ] ; then
    find mycache -type f -exec chmod ugo+r {} \;
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover
fi
