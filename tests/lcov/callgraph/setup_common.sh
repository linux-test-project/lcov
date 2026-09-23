#! /usr/bin/env bash

# Call sites in the '.info' file:  the 'FNC:' record, and the reader and writer
# of it.
#
# 'FNC:<callerIndex>[@<fileIndex>],<line>,<column>,<ordinal>,<count>,<callee>' is
#   written in the *caller's* section, after the 'FNA:' records of the function it
#   belongs to - the index is the one those records established, and the reader
#   needs a name for the index before it has a FunctionEntry to attach a site to.
#   The optional '@<fileIndex>' is an 'SF:' index, written only when the call is
#   written somewhere other than the file its caller is defined in - a call in an
#   '#include'd fragment.  The callee is a symbol rather than an index because it
#   may live in a file which has not been read yet, or in no file the report
#   describes at all; it is the record's one free-text field, so it comes last and
#   takes the rest of the line.
#
# The key of a site is (line, column, ordinal) - and that file, when there is one
#   - while the callee is payload, so one
#   location can dispatch to several targets - a virtual call, or a call in a
#   template body, which is one FunctionEntry for every instantiation - and each
#   target keeps its own count.  Within one input the ordinal is part of the
#   identity of a site, and two callees at one key is a 'mismatch' error rather
#   than a silent choice between them;  across inputs it is only which of the
#   calls at that location this is, and two producers which numbered them
#   differently merge by callee.  See 'resolve.sh' for the callee-side view of
#   the same records.
#
# Everything here is a hand-written '.info' over a checked-in source, so it
#   needs no compiler and runs on every platform.  The capture half of the
#   metric is 'geninfo.sh', which needs one;  the format is pinned here, apart
#   from anything which generates it.
#
# This file is not a test:  it is the setup which 'format1.sh', 'format2.sh' and
#   'format3.sh' share, sourced by each of them after '../../common.tst' and with
#   WORKDIR already set to that part's own working directory.  It holds the
#   helpers all three use, and the two fixtures used by more than one part - the
#   'proj/a.c' round-trip data, and the linkage/flag data which section 8 pins
#   and section 9 reads.  Everything else a scenario needs it writes itself.

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

rm -rf $WORKDIR
mkdir $WORKDIR
cd $WORKDIR || exit 1
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

runLcov()
{
    # runLcov label out.info args...
    #   'lcov' has to succeed and say nothing about anything
    local label=$1
    shift
    $COVER $LCOV_TOOL $LCOV_OPTS "$@" 2>&1 | tee $label.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail $label "lcov failed:" `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    if grep -q -E '(ERROR|WARNING)' $label.log ; then
        fail $label "unexpected message:" `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    return 0
}

runWarn()
{
    # runWarn label message args...
    #   'lcov' has to succeed, warning about 'message':  what survives an
    #   ignored error is as much a part of the contract as the message is
    local label=$1
    local message=$2
    shift 2
    $COVER $LCOV_TOOL $LCOV_OPTS "$@" 2>&1 | tee $label.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail $label "lcov failed:" `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    if ! grep -q -F -e "$message" $label.log ; then
        fail $label "expected a warning about '$message' but got:" \
            `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    return 0
}

runGenhtml()
{
    # runGenhtml label args...
    #   as runLcov, for the other tool which reads these records
    local label=$1
    shift
    $COVER $GENHTML_TOOL $LCOV_OPTS "$@" 2>&1 | tee $label.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail $label "genhtml failed:" `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    if grep -q -E '(ERROR|WARNING)' $label.log ; then
        fail $label "unexpected message:" `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    return 0
}

checkFail()
{
    # checkFail label message args...
    #   'lcov' has to fail, saying 'message'
    local label=$1
    local message=$2
    shift 2
    $COVER $LCOV_TOOL $LCOV_OPTS "$@" 2>&1 | tee $label.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        fail $label "expected lcov to fail"
        return
    fi
    if ! grep -q -F -e "$message" $label.log ; then
        fail $label "expected a failure saying '$message' but got:" \
            `grep -E 'ERROR|WARNING' $label.log`
    fi
}

runGenhtmlWarn()
{
    # runGenhtmlWarn label message args...
    #   genhtml has to succeed, saying 'message' and nothing else:  a report
    #   which needs a warning to be produced at all is still a report, but this
    #   test is not the place to discover a second one
    local label=$1
    local message=$2
    shift 2
    $COVER $GENHTML_TOOL $LCOV_OPTS "$@" 2>&1 | tee $label.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail $label "genhtml failed:" `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    if ! grep -q -F -e "$message" $label.log ; then
        fail $label "expected a warning about '$message' but got:" \
            `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    if grep -v -F -e "$message" $label.log | grep -q -E '(ERROR|WARNING)' ; then
        fail $label "unexpected message:" \
            `grep -v -F -e "$message" $label.log | grep -E 'ERROR|WARNING'`
        return 1
    fi
    return 0
}

runWarnRe()
{
    # runWarnRe label regexp args...
    #   as runWarn, where the message is only determined up to something the
    #   test cannot pin down
    local label=$1
    local regexp=$2
    shift 2
    $COVER $LCOV_TOOL $LCOV_OPTS "$@" 2>&1 | tee $label.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail $label "lcov failed:" `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    if ! grep -q -E -e "$regexp" $label.log ; then
        fail $label "expected a warning matching '$regexp' but got:" \
            `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    return 0
}

checkFailRe()
{
    # checkFailRe label regexp args...
    #   as checkFail, where the message is only determined up to something the
    #   test cannot pin down
    local label=$1
    local regexp=$2
    shift 2
    $COVER $LCOV_TOOL $LCOV_OPTS "$@" 2>&1 | tee $label.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        fail $label "expected lcov to fail"
        return
    fi
    if ! grep -q -E -e "$regexp" $label.log ; then
        fail $label "expected a failure matching '$regexp' but got:" \
            `grep -E 'ERROR|WARNING' $label.log`
    fi
}

checkCallRecords()
{
    # checkCallRecords label file <<expected
    #   compare just the call records of a '.info' - and the totals the writer
    #   computes from them - against the expected text on stdin
    local label=$1
    local file=$2
    if [ ! -f $file ] ; then
        fail $label "$file was not written"
        cat > /dev/null
        return
    fi
    cat > $label.expect
    grep -E '^FNC' $file > $label.actual
    if ! diff -u $label.expect $label.actual ; then
        fail $label "unexpected call records in $file"
    fi
}

checkAliasRecords()
{
    # checkAliasRecords label file <<expected
    #   the same for the 'FNA:' records:  the flag letters are what section 10
    #   is about, and the counts beside them are what shows that nothing else
    #   moved while a file was being taken out
    local label=$1
    local file=$2
    if [ ! -f $file ] ; then
        fail $label "$file was not written"
        cat > /dev/null
        return
    fi
    cat > $label.expect
    grep -E '^FNA:' $file > $label.actual
    if ! diff -u $label.expect $label.actual ; then
        fail $label "unexpected function records in $file"
    fi
}

checkLeaderRecords()
{
    # checkLeaderRecords label file <<expected
    #   and the same for the 'FNL:' records, which is where the other half of
    #   the same fact is written:  the flag letter of a leader says that this
    #   function called out of the boundary of the report, as the flag letter of
    #   an alias says that something outside it called in.  Section 18
    local label=$1
    local file=$2
    if [ ! -f $file ] ; then
        fail $label "$file was not written"
        cat > /dev/null
        return
    fi
    cat > $label.expect
    grep -E '^FNL:' $file > $label.actual
    if ! diff -u $label.expect $label.actual ; then
        fail $label "unexpected leader records in $file"
    fi
}

# 'caller' calls 'helper' three times and 'other' once;  'printf' is called
#   from a function which the report does describe, but is not described itself.
cat >proj/a.c <<'EOF'
int helper(int x)
{
    return x + 1;
}

int other(int x)
{
    return x - 1;
}

int caller(int n)
{
    int r = helper(n) + other(n) + helper(n);
    return r;
}
EOF

# This is exactly what a capture of that source would hold, and what the writer
#   produces for it:  locations in source order, aliases sorted by name, the call
#   sites of a function after its aliases and in source order, then the totals.
# Every shape a site can have is here:
#   13:13:0 and 13:13:1 - one location, two callees, which is what a virtual
#                         call or a template body looks like:  told apart by
#                         the ordinal, and 'other' was never taken from here
#   13:31:0 and 13:31:1 - one location, one callee, twice:  a macro, or two
#                         calls the compiler put at the same column
#   14:5:0              - a callee which is not in the report at all
cat >a.info <<'EOF'
TN:format
SF:proj/a.c
FNL:0,1,4
FNA:0,7,helper
FNL:1,6,9
FNA:1,0,other
FNL:2,11,15
FNA:2,1,caller
FNC:2,13,13,0,3,helper
FNC:2,13,13,1,0,other
FNC:2,13,31,0,2,helper
FNC:2,13,31,1,2,helper
FNC:2,14,5,0,1,printf
FNF:3
FNH:2
FNCF:5
FNCH:4
DA:1,7
DA:3,7
DA:6,0
DA:8,0
DA:11,1
DA:13,1
DA:14,1
LF:7
LH:5
end_of_record
EOF

# ..and what a *report* keeps of it, which is what every run below writes:  the
#   call to 'printf' leaves the boundary of the report, so the site is dropped
#   and the 'c' flag of its caller's leader record is what is left of that edge -
#   see section 16 for the rule and section 18 for the flag.  'caller' was
#   entered once and no site of the report calls it, so the report deduces an
#   external caller and says so with a 'd' - which a capture never writes, since
#   it has not resolved anything.  Derived from 'a.info' by hand rather than by
#   a tool run, so that it is an expectation and not a second copy of the
#   behaviour being tested
sed -e '/^FNC:2,14,5,0,1,printf$/d' -e 's/^FNL:2,11,15$/FNL:2c,11,15/' \
    -e 's/^FNA:2,1,caller$/FNA:2d,1,caller/' \
    -e 's/^FNCF:5$/FNCF:4/' -e 's/^FNCH:4$/FNCH:3/' a.info > ar.info
if [ 1 != `grep -c -F -e 'FNL:2c,11,15' ar.info` ] ||
   [ 1 != `grep -c -F -e 'FNA:2d,1,caller' ar.info` ] ||
   [ 0 != `grep -c -F -e 'printf' ar.info` ] ; then
    fail setup "the resolved expectation was not built"
fi

# Three files which call across their own boundaries, and the two tracefiles
#   over them:  'link.info', which asserts external linkage where a symbol has
#   it, and 'xlink.info', which also asserts that something the report cannot
#   name called in.  Section 8 (format1.sh) is about the records themselves and
#   section 9 (format2.sh) reads them, so they are built here and neither part
#   depends on the other having run.
mkdir -p proj
cat >proj/glob.c <<'EOF'
int f(int x)
{
    return x + 1;
}

int g(int x)
{
    return x + 2;
}

int k(int x)
{
    return x + 3;
}
EOF
cat >proj/call.c <<'EOF'
int h(int n)
{
    return f(n) + g(n) + k(n);
}
EOF
cat >proj/stat.c <<'EOF'
static int f(int x)
{
    return x - 1;
}
EOF

# 'g' and 'k' also set up section 9:  their counts are deliberately more than the
#   one call site each has, which is what a call from outside the report looks
#   like.  'f' is exactly accounted for and 'stat.c's 'f' was never called.
# 'g' says so with a 'd', which is what the writer puts beside a function whose
#   count its known sites do not account for - and 'h', whose count no site
#   accounts for at all, has one too.  'k' has none:  its one site has an
#   unknown count, so nothing can be deduced.  The reader recomputes the flag
#   rather than trusting it, so the fixture is a round trip expectation either
#   way - and a file which says it is one that reader accepts
cat >link.info <<'EOF'
TN:format
SF:proj/call.c
FNL:0,1,4
FNA:0d,4,h
FNC:0,3,12,0,4,f
FNC:0,3,19,0,2,g
FNC:0,3,26,0,-,k
FNF:1
FNH:1
FNCF:3
FNCH:2
DA:1,4
DA:3,4
LF:2
LH:2
end_of_record
TN:format
SF:proj/glob.c
FNL:0,1,4
FNA:0e,4,f
FNL:1,6,9
FNA:1ed,6,g
FNL:2,11,14
FNA:2e,3,k
FNF:3
FNH:3
FNCF:0
FNCH:0
DA:1,4
DA:3,4
DA:6,6
DA:8,6
DA:11,3
DA:13,3
LF:6
LH:6
end_of_record
TN:format
SF:proj/stat.c
FNL:0,1,4
FNA:0,0,f
FNF:1
FNH:0
FNCF:0
FNCH:0
DA:1,0
DA:3,0
LF:2
LH:0
end_of_record
EOF

# ..and the same data with the other flag set as well, on the two symbols
#   section 9 needs it on.  Written in the order the writer writes them, so this
#   is a round trip expectation too
sed -e 's/^FNA:0e,4,f$/FNA:0ex,4,f/' -e 's/^FNA:2e,3,k$/FNA:2ex,3,k/' \
    link.info > xlink.info
if [ 2 != `grep -c -E '^FNA:[0-9]+ex,' xlink.info` ] ; then
    fail xlink "the two-flag fixture was not built"
fi

# The rows which name a crossing of the report boundary - the last row of
#   either table.  Section 9 (format2.sh) and section 18 (format3.sh) both reach
#   for these, as extended regexps.  The caller side says which of its two
#   facts hold twice, once in its label and once in its count cell:  'E' where
#   a flag says that a call site outside the report calls the function ('-'
#   where how often is not known), '(R)' where the function was entered more
#   often than the sites of the report account for, and 'E (R)' where both are
#   true
EXTROW='>&lt;external callers&gt;<'
DEDUCEDROW='>&lt;deduced external callers&gt;<'
BOTHROW='>&lt;external and deduced callers&gt;<'
XCELL='class="coverCallgraph(Hi|Lo|Unknown)[^"]*" title="[^"]*">'
EXTCALLER="${XCELL}([0-9]+|-)</td>"
DEDUCED="${XCELL}\([0-9]+\)</td>"
DEDUCEDEXT="${XCELL}[0-9]+&nbsp;\([0-9]+\)</td>"
EXTCALLEE='>&lt;external callee&gt;<'
