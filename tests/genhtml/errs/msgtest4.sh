#!/bin/bash
set +x

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    rm -rf part4.d
    exit 0
fi

# ===========================================================================
# Part 4 of the split msgtest.sh:
#   expect-message loop, MsgContext, date-labels, --history profile tests, deprecated-RC loops, MC/DC error checks
#
# Shared setup (compile + run test.cpp, capture initial.info/version.info)
# lives in setup_common.sh; this part runs in its own working directory
# (part4.d) so it cannot collide with the other parts.
# ===========================================================================
WORKDIR=part4.d
source ./setup_common.sh

# baseline date used by the differential reports below (was set inline in the
# original monolith; each part now needs its own).
NOW=`date`


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

# test profile history fails
for f in noFile initial.info ; do
    $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o history --parallel --history $HISTORY_SCRIPT,$f 2>&1 | tee history.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
	echo "ERROR: genhtml --history $f didn't fail"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
    grep -E "ERROR.*usage.*--history.* is not a valid genhtml profile file" history.log
    if [ 0 != $? ] ; then
	echo "ERROR: didn't find expected --history message"
	if [ 0 == $KEEP_GOING ] ; then
            exit 1
	fi
    fi
done

# wrong profile type
$COVER $GENINFO_TOOL $LCOV_OPTS . -o profileTest.info --parallel --history $HISTORY_SCRIPT,scriptFixed.info.json 2>&1 | tee geninfo_history.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: geninfo --history scriptFixed.info.json didn't fail"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "ERROR.*usage.*--history.* is not a valid geninfo profile file" geninfo_history.log
if [ 0 != $? ] ; then
    echo "ERROR: didn't find expected geninfo --history message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# ignore the wrong history message - also need to ignore the resulting
# 'package' error when the callback can't be installed
$COVER $GENINFO_TOOL $LCOV_OPTS . -o profileTest.info --parallel --history $HISTORY_SCRIPT,scriptFixed.info.json --ignore usage,package 2>&1 | tee geninfo_history_ignore.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: geninfo --history --ignore failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "WARNING.*usage.*--history.* profile history not found" geninfo_history_ignore.log
if [ 0 != $? ] ; then
    echo "ERROR: didn't find expected geninfo --history --ignore message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

for opt in 'genhtml_demangle_cpp'        \
           'genhtml_demangle_cpp_tool'   \
           'genhtml_demangle_cpp_params' \
           'geninfo_checksum'            \
           'geninfo_no_exception_branch' \
           'geninfo_adjust_src_path'     \
           'lcov_branch_coverage'        \
           'lcov_function_coverage'      \
           'genhtml_function_coverage'   \
           'genhtml_branch_coverage'     \
           'genhtml_criteria_script'     \
           'lcov_fail_under_lines'       \
           'lcov_func_coverage'          \
           'lcov_br_coverage'            \
           'geninfo_adjust_src_path'     \
           'geninfo_no_exception_branch' \
	   ; do

    echo genhtml $DIFFCOV_OPTS initial.info -o rcErr --rc "$opt=err"
    $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o rcErr --rc "$opt=err" 2>&1 | tee rcOptErr.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "ERROR: no error for deprecated RC opt $opt"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    grep -E "$opt.+is deprecated.+ use" rcOptErr.log
    if [ 0 != $? ] ; then
        echo "ERROR: didn't find expected message for $opt"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done


echo "config_file = configErr.rc" > incFile.rc
for opt in 'lcov_func_coverage' ; do
    echo "$opt = 1" > configErr.rc

    echo genhtml $DIFFCOV_OPTS initial.info -o rcErr --config-file incFile.rc "$opt=err"
    $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o rcErr --config-file incFile.rc "$opt=err" 2>&1 | tee rcOptErr2.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "ERROR: no error for included deprecated RC opt $opt"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    grep -E "$opt.+is deprecated.+ use" rcOptErr2.log
    if [ 0 != $? ] ; then
        echo "ERROR: didn't find expected message for included RC $opt"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done



if [ "$ENABLE_MCDC" != 1 ] ; then
    $COVER $GENINFO_TOOL . -o mcdc --mcdc-coverage $LCOV_OPTS --msg-log mcdc_errs.log
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

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'message_4' $LOCAL_COVERAGE
fi

echo "Tests passed"
