#!/usr/bin/env bash
#
# Copyright IBM Corp. 2020
#
# Test lcov --help
#

source ../../common.mak

STDOUT=help_stdout.log
STDERR=help_stderr.log

$LCOV --help 2> >(grep -v Devel::Cover: > ${STDERR}) >${STDOUT}
RC=$?
cat "${STDOUT}" "${STDERR}"

# Exit code must be zero
if [[ $RC -ne 0 && $KEEP_GOING != 1 ]] ; then
        echo "Error: Non-zero lcov exit code $RC"
        exit 1
fi

# There must be output on stdout
if [[ ! -s "${STDOUT}" ]] ; then
        echo "Error: Missing output on standard output"
        exit 1
fi

# There must not be any output on stderr
if [[ -s "${STDERR}" && $COVER == '' ]] ; then
        echo "Error: Unexpected output on standard error"
        exit 1
fi

exit 0
