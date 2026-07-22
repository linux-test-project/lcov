#!/bin/bash
set +x

: ${USER:="$(id -u -n)"}

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    if [ -d part1.d ] ; then
        chmod -R u+rwx part1.d 2>/dev/null
        rm -rf part1.d
    fi
    exit 0
fi

# Shared setup: create part1.d, symlink sources, compile extract.cpp (does NOT
# run a.out -- the '--initial' capture below must run before any .gcda exists).
WORKDIR=part1.d
source ./setup_common.sh

# ===========================================================================
# Part 1: initial/all capture, external/no_external/unreach merge checks,
#         criteria callbacks, context callbacks, internal.info + list.gold.
# (Corresponds to the first ~L68-467 of the original monolithic extract.sh.)
# ===========================================================================

if [ 1 != "$NO_INITIAL_CAPTURE" ] ; then
    $COVER $CAPTURE . $LCOV_OPTS --initial -o initial.info $IGNORE_EMPTY --profile --all --ignore usage 2>&1 | tee initial.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "Error:  unexpected error code from lcov --initial"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    # did we find the expected message
    grep "'--all' ignored when '--initial' is used" initial.log
    if [ 0 != $? ] ; then
	echo "ERROR: did not find expected --all message"
        if [ $KEEP_GOING == 0 ] ; then
	    exit 1
	fi
    fi
else
    if [ "${VER[0]}" -lt 5 ] ; then
	   $COVER $CAPTURE . $LCOV_OPTS --initial -o initial2.info $IGNORE_EMPTY --profile 2>&1 | tee initial2.log
	   if [ 0 == ${PIPESTATUS[0]} ] ; then
               echo "Error:  unexpected error code from lcov --initial"
               if [ $KEEP_GOING == 0 ] ; then
		   exit 1
	       fi
	   fi
	   grep -- "--initial cannot generate branch coverage" initial2.log
	   if [ 0 != $? ] ; then
	       echo "Error:  didn't find expected --initial message"
               if [ $KEEP_GOING == 0 ] ; then
		   exit 1
	       fi
	   fi
       fi
fi

${CC} -c --coverage $COMPILE_OPTS unused.c
if [ 0 != $? ] ; then
    echo "Error:  unexpected error from gcc"
    if [ $KEEP_GOING == 0 ] ; then
	exit 1
    fi
fi

if [ "$NO_INITIAL_CAPTURE" != 1 ] ; then
    # capture 'all' - which will pick up the unused file
    $COVER $CAPTURE . $LCOV_OPTS --all -o all_initial.info $IGNORE_EMPTY $IGNORE_USAGE --history $SCRIPT_DIR/history.pm,initial.info.json --profile $EMPTY_BRANCH
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "Error:  unexpected error code from lcov --capture --all"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    # does the result contain file 'unused'
    grep -E "SF:.+unused.c$" all_initial.info
    if [ $? != 0 ] ; then
        echo "Error: did not find 'unused'"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
fi

./a.out 1
if [ 0 != $? ] ; then
    echo "Error:  unexpected error return from a.out"
    exit 1
fi

# test an empty/trivial history callback
# exclude code that some gcc versions suck in, from /usr/include/...
$COVER $CAPTURE . $LCOV_OPTS -o external.info $FILTER $IGNORE --profile --history ./history.sh $EMPTY_BRANCH
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --capture"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS --list external.info $FILTER $IGNORE
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --list"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# how many files reported?
COUNT=`grep -c SF: external.info`
if [ $COUNT == '1' ] ; then
    echo "expected at least 2 files in external.info - found $COUNT"
    exit 1
fi

# need the 'no-external' DB so we can compare effect of unreachable
#  expressions while filtering out files from /usr/include that some
#  old gcc versions want to include
$COVER $CAPTURE . $LCOV_OPTS -o no_external.info $FILTER $IGNORE --profile --no-external
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --capture"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# capture while marking 'unreachable' branch and condition
$COVER $CAPTURE . $LCOV_OPTS -o unreach.info $FILTER $IGNORE --profile $UNREACHABLE --no-external
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --capture --unreach"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# combine 'unreach' with vanilla - should see warning about mismatched
#  'unreach' flags
$COVER $LCOV_TOOL $LCOV_OPTS -o both_mismatch.info -a no_external.info -a unreach.info --ignore mismatch 2>&1 | tee both_mismatch.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error code from lcov merge both"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# look for both error messages...
types="branch"
if [ "$ENABLE_MCDC" == 1 ] ; then
    types="$types MC/DC"
fi
for type in $types ; do
    grep -E "mismatched 'unreachable' tag for $type" both_mismatch.log
    if [ 0 != $? ] ; then
        echo "Error:  didn't find expected $type mismatch unreach message"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

# write out the 'unreach' data while turning off the flag -
#  result should be identical to 'external.info'
$COVER $LCOV_TOOL $LCOV_OPTS -o identical.info -a unreach.info --rc ignore_unreachable_flag=1
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov ignore unreach"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
diff identical.info no_external.info
if [ 0 != $? ] ; then
    echo "Error:   error diff output on ignore unreach"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# exclude some un-covered standard includes
EXCLUDE='--exclude */include/c++/* --exclude */include/g++-v* --ignore unused'

# callback tests
echo $COVER $CAPTURE . $LCOV_OPTS -o callback.info $FILTER $IGNORE --criteria $SCRIPT_DIR/threshold.pm,--line,90,--branch,65,--function,100 $EXCLUDE
$COVER $CAPTURE . $LCOV_OPTS -o callback.info $FILTER $IGNORE --criteria $SCRIPT_DIR/threshold.pm,--line,90,--branch,65,--function,100 $EXCLUDE --history $SCRIPT_DIR/history.pm,external.info.json 2>&1 | tee callback_fail.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected criteria fail from lcov --capture - but not found"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -i 'failed coverage criteria' callback_fail.log
if [ 0 != $? ] ; then
    echo "Error:  didn't find expected criteria message"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
echo $COVER $CAPTURE . $LCOV_OPTS -o callback2.info $FILTER $IGNORE --criteria $SCRIPT_DIR/threshold.pm,--line,20 --history $SCRIPT_DIR/history.pm,external.info.json,callback.info.json $EXCLUDE
$COVER $CAPTURE . $LCOV_OPTS -o callback2.info $FILTER $IGNORE --criteria $SCRIPT_DIR/threshold.pm,--line,20 --history $SCRIPT_DIR/history.pm,external.info.json,callback.info.json $EXCLUDE
if [ 0 != $? ] ; then
    echo "Error:  expected criteria pass from lcov --capture - but failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

echo $COVER $LCOV_TOOL $LCOV_OPTS -o aggregata.info -a callback.info $FILTER $IGNORE --criteria $SCRIPT_DIR/threshold.pm,--line,90,--branch,65,--function,100 $EXCLUDE
$COVER $LCOV_TOOL $LCOV_OPTS -o aggregata.info -a callback.info $FILTER $IGNORE --criteria $SCRIPT_DIR/threshold.pm,--line,90,--branch,65,--function,100 $EXCLUDE 2>&1 | tee callback_fail2.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected criteria fail from lcov --aggregate - but not found"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -i 'failed coverage criteria' callback_fail2.log
if [ 0 != $? ] ; then
    echo "Error:  didn't find second expected criteria message"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
$COVER $LCOV_TOOL $LCOV_OPTS -o aggregate2.info -a callback.info $FILTER $IGNORE --criteria $SCRIPT_DIR/threshold.pm,--line,20 $EXCLUDE
if [ 0 != $? ] ; then
    echo "Error:  expected criteria pass from lcov --aggregate - but failed"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# error check for typo in command line - "--branchy"
echo $COVER $CAPTURE . $LCOV_OPTS -o callback.info $FILTER $IGNORE --criteria $SCRIPT_DIR/threshold.pm,--line,90,--branchy,65,--function,100
$COVER $CAPTURE . $LCOV_OPTS -o callback.info $FILTER $IGNORE --criteria $SCRIPT_DIR/threshold.pm,--line,90,--branchy,65,--function,100 2>&1 | tee callback_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected criteria config fail from lcov --capture"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -i 'Error: unexpected option' callback_err.log
if [ 0 != $? ] ; then
    echo "Error:  didn't find expected criteria config message"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#bad value - not numeric
echo $COVER $CAPTURE . $LCOV_OPTS -o callback.info $FILTER $IGNORE --criteria $SCRIPT_DIR/threshold.pm,--line,90,--branch,x,--function,100
$COVER $CAPTURE . $LCOV_OPTS -o callback.info $FILTER $IGNORE --criteria $SCRIPT_DIR/threshold.pm,--line,90,--branch,x,--function,100 2>&1 | tee callback_err2.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected another criteria config fail from lcov --capture"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -i 'unexpected branch threshold' callback_err2.log
if [ 0 != $? ] ; then
    echo "Error:  didn't find expected criteria config message 2"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# context callbacks...
echo $CAPTURE . $LCOV_OPTS --all -o context.info $IGNORE $IGNORE_EMPTY $IGNORE_USAGE --context $SCRIPT_DIR/context.pm
$COVER $CAPTURE . $LCOV_OPTS --all -o context.info $IGNORE $IGNORE_EMPTY $IGNORE_USAGE --context $SCRIPT_DIR/context.pm
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --capture --context"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep -F "\"user\":\"$USER\"" context.info.json
if [ 0 != $? ] ; then
    echo "Error:  did not find expected context field"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep user: context.info
if [ 0 == $? ] ; then
    echo "Error:  did not expect to find context field in info"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

echo $CAPTURE . $LCOV_OPTS --all -o context_comment.info $IGNORE $IGNORE_EMPTY $IGNORE_USAGE --context $SCRIPT_DIR/context.pm,--comment
$COVER $CAPTURE . $LCOV_OPTS --all -o context_comment.info $IGNORE $IGNORE_EMPTY $IGNORE_USAGE --context $SCRIPT_DIR/context.pm,--comment
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --capture --context"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep -F "\"user\":\"$USER\"" context.info.json
if [ 0 != $? ] ; then
    echo "Error:  did not find expected context field"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep "#user: $USER" context_comment.info
if [ 0 != $? ] ; then
    echo "Error:  did not find context data in comment field"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


# check error...
$COVER $LCOV_TOOL -d . $LCOV_OPTS --all -o err.info $IGNORE $IGNORE_EMPTY $IGNORE_USAGE --context $SCRIPT_DIR/context.pm --context tooManyArgs
if [ 0 == $? ] ; then
    echo "Error:  expected error lcov --capture --context ..."
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# call a context shellscript...
echo $CAPTURE . $LCOV_OPTS --all -o context2.info $IGNORE $IGNORE_EMPTY $IGNORE_USAGE --context ./testContext.sh
$COVER $CAPTURE . $LCOV_OPTS --all -o context2.info $IGNORE $IGNORE_EMPTY $IGNORE_USAGE --context ./testContext.sh
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --capture --context shellscript"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# call a context shellscript which fails...
echo $CAPTURE . $LCOV_OPTS --all -o context3.info $IGNORE $IGNORE_EMPTY $IGNORE_USAGE --context ./testContext.sh --context die
$COVER $CAPTURE . $LCOV_OPTS --all -o context3.info $IGNORE $IGNORE_EMPTY $IGNORE_USAGE --context ./testContext.sh --context die
if [ 0 == $? ] ; then
    echo "Error:  expected error code from lcov --capture --context shellscript"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

echo $CAPTURE . $LCOV_OPTS --all -o context4.info $IGNORE $IGNORE_EMPTY $IGNORE_USAGE --context ./testContext.sh --context arg --ignore callback
$COVER $CAPTURE . $LCOV_OPTS --all -o context4.info $IGNORE $IGNORE_EMPTY $IGNORE_USAGE --context ./testContext.sh --context arg --ignore callback
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code: ignore not applied"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# applying EXCLUDE directive - so we can test both EXCLUDE and UNREACHABLE
#  without changing the test much
#CAPTURE="$GENINFO_TOOL --rc lcov_excl_start=LCOV_EXCL_START_1 --rc lcov_excl_stop=LCOV_EXCL_STOP_1"

$COVER $CAPTURE . $LCOV_OPTS --no-external -o internal.info --rc lcov_excl_start=LCOV_EXCL_START_1 --rc lcov_excl_stop=LCOV_EXCL_STOP_1
if [ 0 != $? ] ; then
    echo "Error:  unexpected error from capture-internal"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# substitute PWD so the test isn't dependent on directory layout.
# quiet, to suppress core count and (empty) message summary
$COVER $LCOV_TOOL $LCOV_OPTS --list internal.info --subst "s#$PWD#.#" -q -q --filter function > list.dat

if [ "$ENABLE_MCDC" == 1 ] ; then
    diff list.dat list_mcdc.gold
else
    # substitute the actual numbers - to become insensitive to compiler version
    #  which produce different numbers of coverpoints
    sed -E 's/[1-9][0-9]*\b/N/g' list.dat > munged.dat
    diff munged.dat list.gold
fi
if [ 0 != $? ] ; then
    echo "Error:  unexpected list difference"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

COUNT=`grep -c SF: internal.info`
if [ $COUNT != '1' ] ; then
    echo "expected 1 file in internal.info - found $COUNT"
    exit 1
fi
INITIAL_COUNT=`grep -c BRDA internal.info`

# capture again, using --all - should pick up 'unused.c'
$COVER $CAPTURE . $LCOV_OPTS --all -o all_internal.info --no-external $FILTER $IGNORE --rc lcov_excl_start=LCOV_EXCL_START_1 --rc lcov_excl_stop=LCOV_EXCL_STOP_1
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --capture --all"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
if [ "$NO_INITIAL_CAPTURE" != 1 ] ; then
    # does the result contain file 'unused'
    grep -E "SF:.+unused.c$" all_internal.info
    if [ $? != 0 ] ; then
        echo "Error: did not find 'unused' 2"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    if [ "${VER[0]}" -gt 7 ] ; then
        # should have found the branch in 'unused.c'
        C=`grep -c BRDA: all_internal.info`
        let DIFF=$C-$INITIAL_COUNT
        if [ "$DIFF" != 2 ] ; then
            echo "Error: unexpected branch count $C in 'unused' - expected $INITIAL_COUNT + 2"
            if [ $KEEP_GOING == 0 ] ; then
                exit 1
            fi
        fi
    fi
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'extract_1' $LOCAL_COVERAGE
fi

echo "Tests passed"
