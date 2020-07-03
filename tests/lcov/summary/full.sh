#!/usr/bin/env bash
#
# Copyright IBM Corp. 2020
#
# Check lcov --summary output for info files containing 100% coverage rates
#

STDOUT=summary_full_stdout.log
STDERR=summary_full_stderr.log

$LCOV --summary "${FULLINFO}" >${STDOUT} 2>${STDERR}
RC=$?
cat "${STDOUT}" "${STDERR}"

# Exit code must be zero
if [[ $RC -ne 0 ]] ; then
	echo "Error: Non-zero lcov exit code $RC"
	exit 1
fi

# There must be output on stdout
if [[ ! -s "${STDOUT}" ]] ; then
	echo "Error: Missing output on standard output"
	exit 1
fi

# There must not be any output on stderr
if [[ -s "${STDERR}" ]] ; then
	echo "Error: Unexpected output on standard error"
	exit 1
fi

# Check counts in output
check_counts "$FULLCOUNTS" "${STDOUT}" || exit 1

# Success
exit 0
