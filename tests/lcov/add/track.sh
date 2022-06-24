#!/usr/bin/env bash

# test function coverage mapping (trivial tests at the moment)

# adding zero does not change anything
$LCOV -o track -a $FULLINFO -a $ZEROINFO --map-functions
grep $ZEROINFO track
if [ $? == 0 ] ; then
    echo "Expected not to find '$ZEROINFO'"
    exit 1
fi
grep $FULLINFO track
if [ $? != 0 ] ; then
    echo "Expected to find '$FULLINFO'"
    exit 1
fi
