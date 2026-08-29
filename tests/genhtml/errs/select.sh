#!/usr/bin/env bash

#echo "$@_" >> x.log

# a trivial select callback:  select everything.  The answer is what the script
# writes to stdout - see lcovrc(5), 'select_script' - not the status it exits
# with.  This used to be 'exit 1', which meant the same thing back when the
# exit status was taken as the answer
echo 1
