#!/usr/bin/env bash
set +x
: ${USER:="$(id -u -n)"}

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

# adding zero does not change anything
$COVER $LCOV_TOOL -o prune -a $FULLINFO -a $ZEROINFO --prune
if [[ $? != 0 && $KEEP_GOING != 1 ]] ; then
    echo "lcov -prune failed"
    exit 1
fi
PRUNED=`cat prune`
if [ "$PRUNED" != "$FULLINFO" ] ; then
        echo "Expected '$FULLINFO' - got '$PRUNED'"
        exit 1
fi

# expect that all the additions did something...
#  note that the generated data is inconsistent:  sometimes, function
#  has zero hit count but some contained lines are hit
$COVER $LCOV_TOOL -o prune2 -a $PART1INFO -a $PART2INFO -a $FULLINFO --prune --ignore inconsistent
if [[ $? != 0 && $KEEP_GOING != 1 ]] ; then
    echo "lcov -prune2 failed"
    exit 1
fi
PRUNED2=`cat prune2`
EXP=$(printf "$PART1INFO\n$PART2INFO\n$FULLINFO\n")
if [ "$PRUNED2" != "$EXP" ] ; then
        echo "Expected 1 '$EXP' - got '$PRUNED2'"
        exit 1
fi

# sorting the input changes order so different file is pruned (only 'full' remains)
$COVER $LCOV_TOOL -o prune3s -a $PART1INFO -a $PART2INFO -a $FULLINFO --prune --ignore inconsistent --rc sort_input=1
if [[ $? != 0 && $KEEP_GOING != 1 ]] ; then
    echo "lcov -prune2 failed"
    exit 1
fi
PRUNED3S=`cat prune3s`
EXP2=$(printf "$FULLINFO\n")
if [ "$PRUNED3S" != "$EXP2" ] ; then
        echo "Expected 1 '$EXP2' - got '$PRUNED3S'"
        exit 1
fi

# using the --sort-input flag
$COVER $LCOV_TOOL -o prune3t -a $PART1INFO -a $PART2INFO -a $FULLINFO --prune --ignore inconsistent --sort-input
if [[ $? != 0 && $KEEP_GOING != 1 ]] ; then
    echo "lcov -prune2 failed"
    exit 1
fi
PRUNED3T=`cat prune3t`
EXP3=$(printf "$FULLINFO\n")
if [ "$PRUNED3T" != "$EXP3" ] ; then
        echo "Expected 2 '$EXP3' - got '$PRUNED3T'"
        exit 1
fi

# expect no effect from adding 'part1' or 'part2' after 'full'
$COVER $LCOV_TOOL -o prune3 -a $FULLINFO -a $PART1INFO -a $PART2INFO --prune --ignore inconsistent
if [[ $? != 0 && $KEEP_GOING != 1 ]] ; then
    echo "lcov -prune3 failed"
    exit 1
fi
PRUNED3=`cat prune3`
if [ "$PRUNED3" != "$FULLINFO" ] ; then
        echo "Expected '$FULLINFO' - got '$PRUNED3'"
        exit 1
fi

if [ "x$COVER" != "x" ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover
fi
