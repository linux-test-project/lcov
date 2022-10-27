#!/usr/bin/env bash

# adding zero does not change anything
$LCOV -o prune -a $FULLINFO -a $ZEROINFO --prune
PRUNED=`cat prune`
if [ "$PRUNED" != "$FULLINFO" ] ; then
    echo "Expected '$FULLINFO' - got '$PRUNED'"
    exit 1
fi

# expect that all the additions did something...
$LCOV -o prune2 -a $PART1INFO -a $PART2INFO -a $FULLINFO --prune
PRUNED2=`cat prune2`
EXP=$(printf "$PART1INFO\n$PART2INFO\n$FULLINFO\n")
if [ "$PRUNED2" != "$EXP" ] ; then
    echo "Expected '$EXP' - got '$PRUNED2'"
    exit 1
fi

# expect no effect from adding 'part1' or 'part2' after 'full'
$LCOV -o prune3 -a $FULLINFO -a $PART1INFO -a $PART2INFO --prune
PRUNED3=`cat prune3`
if [ "$PRUNED3" != "$FULLINFO" ] ; then
    echo "Expected '$FULLINFO' - got '$PRUNED3'"
    exit 1
fi
