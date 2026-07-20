#!/bin/bash
set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    rm -rf part1.d
    exit 0
fi

# ===========================================================================
# Part 1 of the split msgtest.sh:
#   help/usage errors, config-file (missing/loop) errors, build-dir, memory, basic select + selectErr1/2/3
#
# Shared setup (compile + run test.cpp, capture initial.info/version.info)
# lives in setup_common.sh; this part runs in its own working directory
# (part1.d) so it cannot collide with the other parts.
# ===========================================================================
WORKDIR=part1.d
source ./setup_common.sh

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
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --prune --ignore usage 2>&1 | tee prune_warn.log
if [ 0 != $? ] ; then
    echo "ERROR: lcov prune failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

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
    echo "ERROR: didn't find usage error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

for missing in noSuchFile missingDirectory/nofile ; do
    echo lcov $LCOV_OPTS --summary initial.info --config-file $missing --ignore usage
    $COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --config-file $missing 2>&1 | tee err_missing.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
	echo "ERROR: didn't exit after self missing config file '$missing' error"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
    grep "cannot read configuration file '$missing'" err_missing.log
    if [ 0 != $? ] ; then
	echo "ERROR: missing config file '$missing' message"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
done

# now skip the error, by setting 'stop_on_error = 0' in the RC file
#  (can't skip it by using '--ignore usage' because the ignore options
#  aren't processed until after the config file is read).
printf "stop_on_error = 0\nconfig_file = noSuchFile\n" > skipErr.rc

$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --config-file skipErr.rc 2>&1 | tee skip_missing.log
# return error code when 'keep-going'
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: skip  missing config file error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "usage: 1" skip_missing.log
if [ 0 != $? ] ; then
    echo "ERROR: did not run to completion when 'keep-going'"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "ERROR.+\(usage\).+cannot read configuration file" skip_missing.log
if [ 0 != $? ] ; then
    echo "ERROR: missing config file warning message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# read a config file which is there...
echo "message_log = message_file.log" > testing.rc
echo "config_file = testing.rc" > readThis.rc
echo lcov $LCOV_OPTS --summary initial.info --config-file readThis.rc
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --config-file readThis.rc
if [ 0 != $? ] ; then
    echo "ERROR: didn't read config file"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ ! -f message_file.log ] ; then
    echo "ERROR: didn't honor message_log"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# loop in config file inclusion
echo "config_file = loop1.rc" > loop1.rc
echo lcov $LCOV_OPTS --summary initial.info --config-file loop1.rc --ignore usage
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --config-file loop1.rc --ignore usage 2>&1 | tee err_selfloop.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: skipped self loop error - which isn't supposed to be possible right now"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "config file inclusion loop" err_selfloop.log
if [ 0 != $? ] ; then
    echo "ERROR: missing config file message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# skip the config loop message - see 'skipErr.rc' discussion, above
printf "stop_on_error = 0\nconfig_file = loop1.rc\n" > skipErr2.rc
echo lcov $LCOV_OPTS --summary initial.info --config-file skipErr2.rc
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --config-file skipErr2.rc 2>&1 | tee skipSelfLoop.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: didn't return error code when keep-going"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "usage: 1" skip_missing.log
if [ 0 != $? ] ; then
    echo "ERROR: did not run to completion when 'keep-going'"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "ERROR.+\(usage\).+config file inclusion loop" skipSelfLoop.log
if [ 0 != $? ] ; then
    echo "ERROR: missing config file warning message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo "config_file = loop3.rc" > loop2.rc
echo 'config_file = $ENV{PWD}/loop2.rc' > loop3.rc
echo lcov $LCOV_OPTS --summary initial.info --config-file loop2.rc --ignore usage
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --config-file loop2.rc --ignore usage 2>&1 | tee err_loop.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: skipped self loop error2 - which isn't supposed to be possible"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
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

echo genhtml $DIFFCOV_OPTS initial.info -o select --select-script $SELECT_SCRIPT --select-script -x
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

# test some 'select.pm' errors:
#   - --cl without annotate callback
echo genhtml $DIFFCOV_OPTS initial.info -o selectErr1 --select-script $SELECT_SCRIPT,--cl,123
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o selectErr1 --select-script $SELECT_SCRIPT,--cl,123 2>&1 | tee selectErr1.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml selectErr1 passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "cannot select date/owner/" selectErr1.log
if [ 0 != $? ] ; then
    echo "ERROR: missing script selectErr1 message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

#   - --tla LBC without baseline data
echo genhtml $DIFFCOV_OPTS initial.info -o selectErr2 --select-script $SELECT_SCRIPT,--tla,LBC
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o selectErr2 --select-script $SELECT_SCRIPT,--tla,LBC 2>&1 | tee selectErr2.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml selectErr2 passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "Will never see TLA other than" selectErr2.log
if [ 0 != $? ] ; then
    echo "ERROR: missing script selectErr2 message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

#   - --tla GNC without diff data
echo genhtml $DIFFCOV_OPTS --baseline-file initial.info build.info -o selectErr3 --select-script $SELECT_SCRIPT,--tla,GNC
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --baseline-file initial.info build.info -o selectErr3 --select-script $SELECT_SCRIPT,--tla,GNC 2>&1 | tee selectErr3.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml selectErr3 passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "Will never see 'GNC' category without --diff-file" selectErr3.log
if [ 0 != $? ] ; then
    echo "ERROR: missing script selectErr3 message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'message_1' $LOCAL_COVERAGE
fi

echo "Tests passed"
