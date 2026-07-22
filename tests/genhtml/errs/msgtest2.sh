#!/bin/bash
set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    rm -rf part2.d
    exit 0
fi

# ===========================================================================
# Part 2 of the split msgtest.sh:
#   scriptErr callback loop, sort/p4err, p4annotate cache tests, empty-diff, insensitive, invalid-regexp/simplify loops
#
# Shared setup (compile + run test.cpp, capture initial.info/version.info)
# lives in setup_common.sh; this part runs in its own working directory
# (part2.d) so it cannot collide with the other parts.
# ===========================================================================
WORKDIR=part2.d
source ./setup_common.sh

# note:  select.pm checks that annotation happened (requires annotation
#  in order to check date range)
for arg in "--annotate-script $ANNOTATE_SCRIPT --select-script $SELECT_SCRIPT,--range,0:10" \
               "--criteria-script $CRITERIA_SCRIPT,--signoff" \
               "--annotate-script $ANNOTATE_SCRIPT" \
               "--annotate-script $GITBLAME_SCRIPT,mediatek.com,--p4" \
               "--annotate-script $GITBLAME_SCRIPT,--p4" \
               "--annotate-script $GITBLAME_SCRIPT" \
               " --ignore version --version-script $GITVERSION_SCRIPT,--md5,--p4" \
           ; do
    echo genhtml $DIFFCOV_OPTS initial.info -o scriptErr ${arg},-x
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
    echo genhtml $DIFFCOV_OPTS initial.info -o scriptFixed ${arg}
    $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o scriptFixed ${arg} --ignore annotate --profile 2>&1 | tee script_err.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "ERROR: genhtml scriptFixed failed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

echo genhtml $DIFFCOV_OPTS initial.info -o sortTables --sort
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o sortTables --sort 2>&1 | tee sort.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml --sort passed but should not have"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "Option sort is ambiguous" sort.log
if [ 0 != $? ] ; then
    echo "ERROR: missing --sort message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo genhtml $DIFFCOV_OPTS initial.info -o p4err --version-script $P4VERSION_SCRIPT,-x
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


echo genhtml $DIFFCOV_OPTS initial.info -o select --select-script ./select.sh --rc compute_file_version=1
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
echo genhtml $DIFFCOV_OPTS initial.info -o select --select-script ./select.sh --annotate $ANNOTATE_SCRIPT,--cache,mycache --baseline-file initial.info $IGNORE_ANNOTATE
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
echo genhtml $DIFFCOV_OPTS initial.info -o cacheFail --select-script ./select.sh --annotate $ANNOTATE_SCRIPT,--cache,mycache --baseline-file initial.info --ignore version $IGNORE_ANNOTATE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o cacheFail --select-script ./select.sh --annotate $ANNOTATE_SCRIPT,--cache,mycache --baseline-file initial.info --title 'selectExample' --header-title 'this is the header' --date-bins 1,5,22 --baseline-date "$NOW" --prefix x --no-prefix --ignore version $IGNORE_ANNOTATE 2>&1 | tee cacheFail.log
cacheFail_status=${PIPESTATUS[0]}

if [ '' == "$IGNORE_ANNOTATE" ] ; then
    if [ 0 == $cacheFail_status ] ; then
        echo "ERROR: genhtml corrupt deserialize should have failed - but didn't"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    grep -E "corrupt.*unable to deserialize" cacheFail.log
    if [ 0 != $? ] && [ '' == "$IGNORE_ANNOTATE" ]; then
        echo "ERROR: failed to find cache corruption"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
fi

# make cache file unreadable
find mycache -type f -exec chmod ugo-r {} \;
echo genhtml $DIFFCOV_OPTS initial.info -o cacheFail --select-script ./select.sh --annotate $ANNOTATE_SCRIPT,--cache,mycache --baseline-file initial.info $IGNORE_ANNOTATE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o cacheFail --select-script ./select.sh --annotate $ANNOTATE_SCRIPT,--cache,mycache --baseline-file initial.info --title 'selectExample' --header-title 'this is the header' --date-bins 1,5,22 --baseline-date "$NOW" --prefix x $IGNORE_ANNOTATE --no-prefix 2>&1 | tee cacheFail2.log
cacheFail2_status=${PIPESTATUS[0]}

if [ '' == "$IGNORE_ANNOTATE" ] ; then
    if [ 0 == $cacheFail2_status ] ; then
        echo "ERROR: genhtml unreadable cache should have failed - but didn't"
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
echo genhtml $DIFFCOV_OPTS initial.info -o empty --diff diff.txt --annotate $ANNOTATE_SCRIPT --baseline-file initial.info
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

# invalid regexp
for flag in --substitute ; do
    echo genhtml $DIFFCOV_OPTS -o foo initial.info $flag 's#aBc#AbC' --ignore source --rc max_message_count=1
    $COVER $GENHTML_TOOL $DIFFCOV_OPTS -o foo initial.info $flag 's#aBc#AbC' --ignore source --rc max_message_count=1 2>&1 | tee invalid_regexp.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
	echo "ERROR: genhtml invalid $flag"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
    grep "Invalid regexp \"$flag " invalid_regexp.log
    if [ 0 != $? ] ; then
	echo "ERROR: missing regexp message for $flag"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
done

echo genhtml $DIFFCOV_OPTS -o foo initial.info --simplify $SIMPLIFY_SCRIPT,--re, 's#aBc#AbC' --ignore source --rc max_message_count=1
$COVER $GENHTML_TOOL $DIFFCOV_OPTS -o foo initial.info --simplify $SIMPLIFY_SCRIPT,--re, 's#aBc#AbC' --ignore source --rc max_message_count=1 2>&1 | tee script_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml invalid $flag"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
for str in 'Invalid regexp' 'unable to create callback from module ' ; do
    grep "$str" script_err.log
    if [ 0 != $? ] ; then
	echo "ERROR: missing err message for '$str'"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
done

# script errors
for args in '' ',--file,a,--re,s/a/b/' ',--file,a' ; do
    echo genhtml $DIFFCOV_OPTS -o foo initial.info --simplify ${SIMPLIFY_SCRIPT}${args} --ignore source --rc max_message_count=1
    $COVER $GENHTML_TOOL $DIFFCOV_OPTS -o foo initial.info --simplify ${SIMPLIFY_SCRIPT}${args} --ignore source --rc max_message_count=1 2>&1 | tee invalid_callback.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
	echo "ERROR: genhtml invalid '$args'"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
    grep "unable to create callback from module " invalid_callback.log
    if [ 0 != $? ] ; then
	echo "ERROR: missing regexp message for '$args'"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
done

if [ -d mycache ] ; then
    find mycache -type f -exec chmod ugo+r {} \;
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'message_2' $LOCAL_COVERAGE
fi

echo "Tests passed"

