#!/usr/bin/env bash
#
# Check demangling options
#   genhtml_demangle_cpp
#   genhtml_demangle_cpp_tool
#   genhtml_demangle_cpp_params
#

OUTDIR="out_demangle"
STDOUT="demangle_stdout.log"
STDERR="demangle_stderr.log"
INFO="demangle.info.tmp"
SOURCE="file.tmp"
HTML="${OUTDIR}/genhtml/${SOURCE}.func.html"
MYFILT="${PWD}/mycppfilt.sh"

function die() {
	echo "Error: $*" >&2
	exit 1
}

function cleanup() {
	rm -rf  "${OUTDIR}" "${INFO}" "${SOURCE}"
}

function prepare() {
	cat >"${INFO}" <<EOF
SF:$SOURCE
FN:1,myfunc1
FN:2,_Z7myfunc2v
FN:3,__Z7myfunc3v
DA:1,1
end_of_record
EOF
	touch "${SOURCE}"
}

function run() {
	local CMDLINE="${GENHTML} ${INFO} -o ${OUTDIR} $*"

	rm -rf "${OUTDIR}"

	# Run genhtml
	echo "CMDLINE: $CMDLINE"
	$CMDLINE >${STDOUT} 2>${STDERR}
	RC=$?

	echo "STDOUT_START"
	cat ${STDOUT}
	echo "STDOUT_STOP"

	echo "STDERR_START"
	cat ${STDERR}
	echo "STDERR_STOP"

	# Check exit code
	[[ $RC -ne 0 ]] && die "Non-zero genhtml exit code $RC"

	# Output must not contain warnings
	if [[ -s ${STDERR} ]] ; then
		echo "Error: Output on stderr.log:"
		cat ${STDERR}
		exit 1
	fi

	# Log function names
	echo "Found function names:"
	grep coverFn ${HTML}
}

prepare

echo "Run 1: No demangling"
run ""
if grep -q myfunc1 ${HTML} ; then
	echo "Success - found myfunc1"
else
	die "Missing function name 'myfunc1' in output"
fi

echo
echo "Run 2: Demangle using defaults"
if type -P c++filt >/dev/null ; then
	# Depending on environment, encoded symbols are converted to either
	# myfunc2() or myfunc3()
	run "--demangle-cpp"
	if grep -q 'myfunc[23]()' ${HTML} ; then
		echo "Success - found myfunc[23]() converted by c++filt"
	else
		die "Missing converted function name 'myfunc[23]()' in output"
	fi
else
	echo "Skipping - missing c++filt tool"
fi

echo
echo "Run 3: Demangle using custom demangling tool"
# mycppfilt.sh with no parameters prepends aaa to each function name
run "--demangle-cpp --rc genhtml_demangle_cpp_tool=$MYFILT"
if grep -q 'aaamyfunc' ${HTML} ; then
	echo "Success - found myfunc prefixed by mycppfilt.sh"
else
	die "Missing converted function name 'aaamyfunc' in output"
fi

echo
echo "Run 4: Demangle with params set"
# mycppfilt.sh with parameter prepends that parameter to to each function name
run "--demangle-cpp --rc genhtml_demangle_cpp_tool=$MYFILT --rc genhtml_demangle_cpp_params='bbb'"
if grep -q 'bbbmyfunc' ${HTML} ; then
	echo "Success - found myfunc prefixed by custom prefix"
else
	die "Missing converted function name 'bbbmyfunc' in output"
fi

# Success
cleanup

exit 0
