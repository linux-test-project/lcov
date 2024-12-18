#!/bin/sh

if [ 'die' = "$1" ] ; then
    echo "dying"
    exit 1
fi

echo USERNAME `whoami`
echo MULTILINE  line1
echo MULTILINE  line2
echo MULTILINE  line3
exit 0
