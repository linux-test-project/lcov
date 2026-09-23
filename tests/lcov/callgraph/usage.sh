#! /usr/bin/env bash

# Asking for callgraph coverage where it cannot be delivered.
#
# Two different answers, and which one a tool gives says something about the
# request:
#
#   - '--callgraph-coverage' together with '--no-function-coverage' (or
#     'function_coverage=0') is a 'usage' error.  Callee data hangs off
#     FunctionEntry and FunctionAlias, so with function coverage off there is
#     nothing for it to hang off and nothing would be written:  the two options
#     contradict each other, which is what that class means.  It is checked in
#     the shared option processing, so 'lcov', 'geninfo' and 'genhtml' all give
#     it by construction.
#
#   - '--callgraph-coverage' given to a converter whose input cannot carry call data
#     is an 'unsupported' error.  Nothing is contradictory about the request; the
#     tool simply does not have that cover type, and never will - a Devel::Cover
#     DB records a per-subroutine count and an 'llvm-cov export' records
#     segments, branches and MC/DC, and callgraph coverage needs the compiler's
#     static callgraph.  Same class as gcov being too old or an object built
#     without '-fcallgraph-info':  the reason differs, the statement does not.
#
# In both cases ignoring the error has to leave the run in exactly one coherent
#   state - the metric off - rather than continuing with the flag half-on and
#   writing records for a metric which was never measured.  So each case is
#   asserted twice:  the message, and what the ignored run produced.
#
# The converters' half also asserts *when* the check fires:  they are pointed at
#   an input which does not exist and still give the error, because a tool which
#   cannot produce a metric knows it before it reads anything.
#
# The two Python converters are the third answer:  they do not have the option at
#   all, so argparse rejects it.  They have no error classes and no
#   '--ignore-errors', so there would be nothing to ignore and a bespoke message
#   would say no more than "unrecognized arguments" already does.  Asserted here
#   because "the tool accepts a flag it cannot honour" is the failure this whole
#   testcase is about, and an option quietly reappearing in their tables is
#   exactly how it would come back.
#
# 'html2lcov' is deliberately absent:  its input is an lcov report, so whatever
#   the report shows is recoverable from it, and it supports the metric.  Its
#   answer to a report which has no call data in it is the 'empty' error - see
#   'empty.sh'.

source ../../common.tst

# This directory is shared with 'aliases.sh', which removes '*.info' and '*.log'
# as it starts, so run in a private subdirectory - as 'resolve.sh' does.
SRCDIR=`pwd`
if [ "x$COVER" != "x" ] ; then
    # a bare '--coverage' leaves COVER_DB relative to the invocation directory
    case "$COVER_DB" in
        /*) ;;
        *)  COVER_DB="$SRCDIR/$COVER_DB"
            export PYCOV_DB="${COVER_DB}_py"
            PERL_COVER_ARGS="-MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine,-silent,1 "
            COVER="perl $PERL_COVER_ARGS"
            ;;
    esac
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf usage.d
    exit 0
fi

rm -rf usage.d
mkdir usage.d
cd usage.d || exit 1
mkdir proj

LCOV_OPTS="$PARALLEL $PROFILE"

STATUS=0

fail()
{
    # $1 = scenario label, $2.. = what went wrong
    local label=$1
    shift
    echo "ERROR ($label): $*"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

runCmd()
{
    # runCmd label command
    #   the command is a string rather than a list because the Python tools are
    #   invoked through '$PYCOVER', which is a variable assignment and has to be
    #   re-parsed - the same 'eval' the py2lcov and xml2lcov testcases use
    local label=$1
    echo "$2" > $label.cmd
    eval "$2" > $label.log 2>&1
    RC=$?
    cat $label.log
}

expectFail()
{
    # expectFail label message command
    local label=$1
    local message=$2
    runCmd $label "$3"
    if [ 0 == $RC ] ; then
        fail $label "expected a failure, but the command succeeded"
        return
    fi
    if ! grep -q -F -e "$message" $label.log ; then
        fail $label "expected a failure saying '$message'"
    fi
}

expectWarn()
{
    # expectWarn label message command
    #   the same message, as a warning:  the error was ignored
    local label=$1
    local message=$2
    runCmd $label "$3"
    if ! grep -q -F -e "$message" $label.log ; then
        fail $label "expected a warning saying '$message'"
        return
    fi
    # ..and this message, not some other error, is the one which was ignored:
    #   a tool pointed at an input which does not exist has one of its own to
    #   report, which is not what this is about
    if grep -q -F -e "${message/WARNING:/ERROR:}" $label.log ; then
        fail $label "the ignored error was still fatal:" \
            `grep -E 'ERROR' $label.log`
    fi
}

noCallRecords()
{
    # noCallRecords label file
    #   a run which turned the metric off writes no record of it
    local label=$1
    local file=$2
    if [ ! -f $file ] ; then
        fail $label "$file was not written"
        return
    fi
    if grep -q -E '^FNC' $file ; then
        fail $label "call records were written for a metric which was off:"
        grep -E '^FNC' $file
    fi
}

cat >proj/a.c <<'EOF'
int helper(int x)
{
    return x + 1;
}

int caller(int n)
{
    return helper(n);
}
EOF

cat >a.info <<'EOF'
TN:usage
SF:proj/a.c
FNL:0,1,4
FNA:0,1,helper
FNL:1,6,9
FNA:1,1,caller
FNC:1,8,12,0,1,helper
FNF:2
FNH:2
FNCF:1
FNCH:1
DA:1,1
DA:3,1
DA:6,1
DA:8,1
LF:4
LH:4
end_of_record
EOF

# The smallest Cobertura document the Python tools will read:  they are given a
#   real input, so that the run which drops the flag is a conversion which
#   succeeds - which is what says the flag was the only thing wrong.
cat >tiny.xml <<'EOF'
<?xml version="1.0" ?>
<coverage line-rate="1.0" branch-rate="1.0" version="1.9" timestamp="0">
  <sources><source>.</source></sources>
  <packages>
    <package name="proj" line-rate="1.0" branch-rate="1.0" complexity="0">
      <classes>
        <class name="a" filename="proj/a.c" line-rate="1.0" branch-rate="1.0" complexity="0">
          <methods/>
          <lines>
            <line number="1" hits="1"/>
            <line number="3" hits="1"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
EOF

USAGE_MSG="--callgraph-coverage requires function coverage, which is disabled (--no-function-coverage or 'function_coverage=0')."

# ----------------------------------------------------------------------
echo "*** 1. --callgraph-coverage with function coverage turned off"
# ----------------------------------------------------------------------
# Both spellings of "off", because they are applied at different points and the
#   check has to sit after both of them
expectFail lcov_nofunc "ERROR: (usage) $USAGE_MSG" \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --no-function-coverage -a a.info -o nofunc.info"

expectFail lcov_rc "ERROR: (usage) $USAGE_MSG" \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --rc function_coverage=0 -a a.info -o rc.info"

# It is one check in shared option processing, so every tool which has the
#   option has it - including the two which are not otherwise in this testcase.
#   Neither needs a usable input:  the check runs before anything is read
expectFail geninfo_nofunc "ERROR: (usage) $USAGE_MSG" \
    "$COVER $GENINFO_TOOL --callgraph --no-function-coverage nonexistent.dir"

expectFail genhtml_nofunc "ERROR: (usage) $USAGE_MSG" \
    "$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph --no-function-coverage -o html_nofunc a.info"

# ..and ignoring it turns callgraph coverage off rather than leaving both flags
#   set:  no call records, and - since function coverage is what was turned off
#   in the first place - no function records either
expectWarn lcov_ignored "WARNING: (usage) $USAGE_MSG" \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --no-function-coverage -a a.info -o ignored.info --ignore-errors usage"
noCallRecords lcov_ignored ignored.info
if [ -f ignored.info ] && grep -q -E '^FN' ignored.info ; then
    fail lcov_ignored "--no-function-coverage was overridden to satisfy --callgraph:"
    grep -E '^FN' ignored.info
fi

expectWarn genhtml_ignored "WARNING: (usage) $USAGE_MSG" \
    "$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph --no-function-coverage -o html_ignored a.info --ignore-errors usage"
if [ ! -f html_ignored/index.html ] ; then
    fail genhtml_ignored "no report was written"
fi

# ----------------------------------------------------------------------
echo "*** 2. the converters whose input cannot carry call data"
# ----------------------------------------------------------------------
# Each message names the tool, says what its input holds instead, and says where
#   the metric does come from - which is the only actionable part, since there is
#   nothing to change about the invocation except to drop the flag
expectFail perl2lcov "perl2lcov: ERROR: (unsupported) --callgraph-coverage is not supported by perl2lcov: a Devel::Cover database records a per-subroutine count and no caller.  Callgraph coverage requires geninfo with -fcallgraph-info." \
    "$COVER $PERL2LCOV_TOOL --callgraph -o perl.info nonexistent.db"

expectFail llvm2lcov "llvm2lcov: ERROR: (unsupported) --callgraph-coverage is not supported by llvm2lcov: 'llvm-cov export' records segments, branches and MC/DC, but no edges.  Callgraph coverage requires geninfo with -fcallgraph-info." \
    "$COVER $LLVM2LCOV_TOOL --callgraph -o llvm.info nonexistent.json"

# 'perl2lcov' is also the one tool which has a second cover type it cannot
#   produce:  Devel::Cover has condition data, which becomes branch coverage,
#   and no MC/DC records ever come out.  Same helper, same class, same shape of
#   message - which is the point of the helper
expectFail perl2lcov_mcdc "perl2lcov: ERROR: (unsupported) --mcdc-coverage is not supported by perl2lcov: Devel::Cover condition data is converted to branch coverage, and no MC/DC records are produced.  MC/DC coverage requires geninfo with gcc 14.2 or later, or clang 18.1 or later." \
    "$COVER $PERL2LCOV_TOOL --mcdc-coverage -o perlmcdc.info nonexistent.db"

# ..and ignoring it lets the run continue with the metric off.  These three are
#   pointed at inputs which do not exist - which is what proves the check fires
#   before any of them is read - so the run then fails on the input.  What is
#   asserted is that the failure which follows is about the missing input and not
#   about the option
expectWarn perl2lcov_ignored \
    "WARNING: (unsupported) --callgraph-coverage is not supported by perl2lcov" \
    "$COVER $PERL2LCOV_TOOL --callgraph -o perl2.info nonexistent.db --ignore-errors unsupported"

expectWarn llvm2lcov_ignored \
    "WARNING: (unsupported) --callgraph-coverage is not supported by llvm2lcov" \
    "$COVER $LLVM2LCOV_TOOL --callgraph -o llvm2.info nonexistent.json --ignore-errors unsupported"

# ----------------------------------------------------------------------
echo "*** 3. the Python converters do not have the option"
# ----------------------------------------------------------------------
# No error class to ignore and no '--ignore-errors', so there is nothing a
#   message could offer that argparse's does not:  both spellings are simply not
#   options of these tools
expectFail py2lcov "unrecognized arguments: --callgraph-coverage" \
    "eval ${PYCOVER} ${PY2LCOV_TOOL} --callgraph-coverage -o py.info tiny.xml"

expectFail py2lcov_abbrev "unrecognized arguments: --callgraph" \
    "eval ${PYCOVER} ${PY2LCOV_TOOL} --callgraph -o py.info tiny.xml"

expectFail xml2lcov "unrecognized arguments: --callgraph-coverage" \
    "eval ${PYCOVER} ${XML2LCOV_TOOL} --callgraph-coverage -o xml.info tiny.xml"

expectFail xml2lcov_abbrev "unrecognized arguments: --callgraph" \
    "eval ${PYCOVER} ${XML2LCOV_TOOL} --callgraph -o xml.info tiny.xml"

# ..and the same command without the flag converts the same input, so what was
#   rejected was the flag and not the file
runCmd py2lcov_ok "eval ${PYCOVER} ${PY2LCOV_TOOL} -o py2.info tiny.xml"
if [ 0 != $RC ] ; then
    fail py2lcov_ok "py2lcov failed on an input it should read"
else
    noCallRecords py2lcov_ok py2.info
fi

runCmd xml2lcov_ok "eval ${PYCOVER} ${XML2LCOV_TOOL} -o xml2.info tiny.xml"
if [ 0 != $RC ] ; then
    fail xml2lcov_ok "xml2lcov failed on an input it should read"
else
    noCallRecords xml2lcov_ok xml2.info
fi

# ----------------------------------------------------------------------
echo "*** 4. --callgraph-partial-data on its own"
# ----------------------------------------------------------------------
# The option says what a capture keeps when the compiler recorded a call that
#   gcov produced no count for, so it means nothing with the metric off:  asking
#   for it alone asks for nothing.
# A warning and not an error, unlike section 1:  there is no contradiction to
#   resolve and no state left incoherent - the flag is simply dropped - and
#   'lcov --capture' passes it through to geninfo, where the metric may be
#   turned off again by a gcov which is too old or an object with no callgraph
#   info.  Failing there would make an ordinary mixed build unbuildable
PARTIAL_MSG="--callgraph-partial-data has no effect without --callgraph-coverage - ignoring it."

expectWarn partial_alone "WARNING: (usage) $PARTIAL_MSG" \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph-partial-data -a a.info -o partial_alone.info"
# ..and the run is a run:  the warning cost nothing but the flag
noCallRecords partial_alone partial_alone.info

# One check in shared option processing again, so the tools which capture have it
#   too
expectWarn geninfo_partial_alone "WARNING: (usage) $PARTIAL_MSG" \
    "$COVER $GENINFO_TOOL --callgraph-partial-data nonexistent.dir --ignore-errors gcov"

# ..and it is ignorable like any other usage complaint
runCmd partial_ignored \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph-partial-data -a a.info -o partial_ignored.info --ignore-errors usage"
if [ 0 != $RC ] ; then
    fail partial_ignored "lcov failed with the warning ignored:" \
        `grep -E 'ERROR' partial_ignored.log`
fi
if grep -q -F -e "$PARTIAL_MSG" partial_ignored.log ; then
    fail partial_ignored "'--ignore-errors usage' did not suppress it:" \
        `grep -E 'WARNING' partial_ignored.log`
fi

# ..while together they are what the option is for, and say nothing
runCmd partial_with \
    "$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --callgraph-partial-data -a a.info -o partial_with.info"
if [ 0 != $RC ] ; then
    fail partial_with "lcov failed:" `grep -E 'ERROR' partial_with.log`
fi
if grep -q -E '(ERROR|WARNING)' partial_with.log ; then
    fail partial_with "unexpected message:" \
        `grep -E 'ERROR|WARNING' partial_with.log`
fi
if [ -f partial_with.info ] &&
   ! grep -q -F -e 'FNC:1,8,12,0,1,helper' partial_with.info ; then
    fail partial_with "the call records were not kept:"
    grep -E '^FNC' partial_with.info
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'usage' $LOCAL_COVERAGE 1
fi

exit $STATUS
