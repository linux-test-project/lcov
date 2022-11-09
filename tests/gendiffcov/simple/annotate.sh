#!/bin/sh

FILE=$1
ANNOTATED=${FILE}.annotated
if [ -f $ANNOTATED ]; then
        cat ${1}.annotated
else
        sed -e 's/^/NONE|NONE|1900-01-01T00:00:01-05:05|/' <$FILE
fi
