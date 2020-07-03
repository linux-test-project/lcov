#!/usr/bin/env bash
#
# Copyright IBM Corp. 2020
#
# Check lcov --summary output for coverage file with rates as specified in
# mkinfo profile.
#

STDOUT=summary_target_stdout.log
STDERR=summary_target_stderr.log

$LCOV --summary "${TARGETINFO}" >${STDOUT} 2>${STDERR}
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
check_counts "$TARGETCOUNTS" "${STDOUT}" || exit 1

# Success
exit 0
