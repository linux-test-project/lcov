#! /usr/bin/env bash

# The ways a callgraph capture can fail to happen, and what geninfo does about each
# of them when the error is ignored.
#
# All of them are about data which is missing rather than wrong, and the reason
#   each has its own error class is that the right answer differs.  There are
#   three which are reported, named below as the scenarios name them, and one
#   which is not:
#
#   an old gcov - older than 14, so its JSON has no count for each call, and no
#       object in this build can have callgraph data:  either '-fcallgraph-info'
#       did not exist (gcc older than 10) or there is nothing to pair its edges
#       with.  The request cannot be met at all, so ignoring it turns the metric
#       off:  a report with a callee column reading 0/0 would be a claim about
#       the code, and there is no measurement behind it.
#   a missing '.ci' - this object has none beside its '.gcno'.  The metric stays
#       on, because a build in which some objects were compiled with the flag and
#       some were not is exactly the case '--ignore-errors unsupported' exists
#       for - see the mixed scenario below, where the objects which do have the
#       data keep their sites.  Said once per run rather than once per object.
#   unpaired calls - the callgraph info and gcov do not describe the same calls.
#       The two are paired per caller by a forward-only walk which matches on
#       the location each side gives, so a disagreement is localized to the
#       calls which did not pair rather than to the whole function, and there
#       are two of them with different causes:  an edge with no arc is a call
#       the compiled code makes and gcov produced no count for, which is what an
#       inlined call looks like from here;  an arc with no edge is a call gcov
#       counted whose callee the callgraph info does not name, so there is
#       nothing to record it as.  The message says which, how many and where,
#       because the advice differs - "rebuild at -O0" helps with the first and
#       not the second.
#       What survives is '--callgraph-partial-data':  without it the function's
#       callgraph data goes and the rest of the file's stays;  with it the calls
#       which did pair are kept, and an edge with no arc is recorded with an
#       unknown count ('-') - counted in the total and never in the hits,
#       exactly as an untaken 'BRDA:' branch is.  So is every other site on that
#       edge's line:  the pairing matches on the line, so a line with fewer arcs
#       than edges does not say which of its calls lost one, and the walk's
#       answer there ("the earlier edges keep the arcs") is a guess which from
#       -O1 is usually wrong.  The error is reported either way:  the option says
#       what to keep and '--ignore-errors inconsistent' says whether to carry on,
#       and the two are independent on purpose.
#   ..and one which is nobody's error and no error at all:  a site in a file other
#       than the one its caller is defined in - which is every call in an
#       '#include'd fragment.  gcov attributes such a line to no function, so the
#       attribution is repaired from the callgraph info's edges, and the record
#       names the file the call is written in by index into the tracefile's 'SF:'
#       records.  Nothing is reported and nothing is dropped;  the scenarios here
#       are about the repair, and about where it stops - a fragment '#include'd
#       into two bodies, where nothing chooses between the two edges.
#
# The old gcov is exercised through a gcov wrapper which lies about its version,
#   and both directions of the unpaired calls by editing the compiled '.ci', for
#   the same reason:  each of those is a property of a toolchain, and a testcase
#   which could only run on an old compiler or at a particular optimization level
#   would in practice never run.  Editing the inputs makes the failures
#   deterministic on any toolchain new enough to produce the data at all.
#
# The last two scenarios need nothing edited and no particular compiler:  a call
#   gcov could not attribute to any function, which the callgraph info repairs by
#   naming the function whose body the line is in, and the same thing where the
#   repair cannot apply because the fragment is '#include'd into two bodies and
#   nothing chooses between them.

source ../../common.tst

# the assertions below compare sorted lists of function names, and 'sort' in a
# locale ignores '_' and case - see 'geninfo.sh'
export LC_ALL=C

# This directory is shared with 'aliases.sh', which removes '*.info' and '*.log'
# as it starts, so run in a private subdirectory - as 'resolve.sh' does.
SRCDIR=`pwd`

# A bare '--coverage' leaves COVER_DB relative to the invocation directory:
# anchor it so it survives the 'cd' below and so '--clean' still finds it.
if [ "x$COVER" != "x" ] ; then
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
    rm -rf unsupported.d
    exit 0
fi

rm -rf unsupported.d
mkdir unsupported.d
cd unsupported.d || exit 1

# '--parallel 1' rather than $PARALLEL throughout:  the missing-'.ci' message is
#   said once per process, so the once-only assertion below only means anything
#   in a run which does not fork, and a fatal error in a worker is reported by
#   the parent as a child error, which would put a second message in front of
#   the one being asserted on.  The forked paths are exercised by 'geninfo.sh'.
LCOV_OPTS="--parallel 1 $PROFILE"

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

# ----------------------------------------------------------------------
# Can this toolchain do it at all?
# ----------------------------------------------------------------------
# A feature probe rather than a version comparison:  '-fcallgraph-info' is gcc
#   10 and later and clang has no equivalent, but the question is whether this
#   compiler writes a '.ci' beside the '.gcno', so ask it.
cat >probe.c <<'EOF'
int main(void) { return 0; }
EOF
if ! ${CC} --coverage -fcallgraph-info=su,da -O0 -c probe.c -o probe.o \
     2>probe.log || [ ! -f probe.ci ] ; then
    echo "compiler '${CC}' does not support -fcallgraph-info" \
         "- skipping callgraph error test"
    cat probe.log
    exit 0
fi

# ..and an old gcov is what a toolchain older than 14 does with every one of
#   these scenarios, so there would be nothing left to distinguish
GCOV_VER=`${GCOV} --version 2>/dev/null | head -1 | sed -e 's/.* //'`
IFS='.' read -r -a GVER <<< "$GCOV_VER"
if [ "${GVER[0]}" -lt 14 ] ; then
    echo "gcov '${GCOV}' is version $GCOV_VER - skipping callgraph error test"
    exit 0
fi

# ----------------------------------------------------------------------
# The fixtures
# ----------------------------------------------------------------------
# 'three' makes four calls and 'other' two, so that when three's data is dropped
#   there is something left to check is still there.
mkdir ci
cat >ci/t.c <<'EOF'
int a(void) { return 1; }
int b(void) { return 2; }
int c(void) { return 3; }
int sum3(int x, int y, int z) { return x + y + z; }
int three(void) { return sum3(a(), b(), c()); }
int other(void) { return a() + b(); }
int main(void) { return three() + other() == 0; }
EOF

# ..and an object compiled the ordinary way, which is the missing-'.ci' case
mkdir noci
cat >noci/n.c <<'EOF'
int helper(void) { return 1; }
int main(void) { return helper() != 1; }
EOF

# ..and a unit with a call on a line gcov cannot attribute to any function:
#   '#include' of a fragment in the middle of a function body.  gcov names the
#   function a line belongs to only when that function is defined in the same
#   file as the line, so the call in the fragment is reported with no caller at
#   all.  The callgraph info does know which function it is in - there is an edge
#   from 'main' at that line - so the capture repairs the attribution and pairs
#   the site, which is then written naming the file it is in:  the site is in
#   'inc.h' and 'main' is in 'i.c'.
#   'other' is here so that there is a site written the ordinary way too.
mkdir frag
cat >frag/inc.h <<'EOF'
    t += helper();
EOF
cat >frag/i.c <<'EOF'
int helper(void) { return 1; }
int other(void) { return helper(); }
int main(void)
{
    int t = other();
#include "inc.h"
    return t != 2;
}
EOF

# ..and the same fragment '#include'd into two function bodies, which is where
#   that repair stops working:  the line is in the body of both, each has an edge
#   there, and nothing chooses between them - so putting a count on either would
#   be putting it on the wrong call.  Those calls stay unattributed and are
#   reported as unpaired, with the cause named:  no optimization setting helps.
#   The call is inside an 'if' so that the block it leaves from was built from
#   the fragment's line and no other.  Without that, gcov reports the arc under a
#   line of the including file as well (one arc is reported under every line its
#   block was built from), that line is in exactly one body, and the repair
#   applies after all - which is the scenario above and not this one.
mkdir dup
cat >dup/body.inc <<'EOF'
    if (flag) { total += helper(3); }
EOF
cat >dup/d.c <<'EOF'
int flag = 1;
int helper(int x) { return x + 1; }
int runA(void)
{
    int total = 0;
#include "body.inc"
    return total;
}
int runB(void)
{
    int total = 10;
#include "body.inc"
    return total;
}
int main(void) { return runA() + runB() != 18; }
EOF

# ..and a fragment whose call gcov numbers like a call its function makes itself,
#   which is what a line folded together with other functions' calls looks like
#   (the instantiations of a template in a header):  block numbers are per
#   function, so a match on the number alone is often a coincidence.  The call
#   is inside an 'if' so that its block is the fragment's line and no other, and
#   the fragment comes first so that its edge is the first one the pairing sees.
#   The coincidence itself is made by a gcov wrapper - see scenario 10
mkdir clash
cat >clash/inc.h <<'EOF'
    if (flag) { t += helper(); }
EOF
cat >clash/c.c <<'EOF'
int flag = 1;
int helper(void) { return 1; }
int other(void) { return helper(); }
int main(void)
{
    int t = 0;
#include "inc.h"
    for (int i = 0; i < 3; ++i) t += other();
    return t != 4;
}
EOF

build()
{
    # build directory source extra-compiler-flags..
    local dir=$1 src=$2 exe
    shift 2
    exe=${src%.c}
    echo "(cd $dir ; ${CC} --coverage $* -O0 -o $exe $src)"
    ( cd $dir && ${CC} --coverage $* -O0 -o $exe $src ) || return 1
    # the exit status is the program's, not the build's - what matters is that it
    #   ran and wrote a '.gcda'
    ( cd $dir && ./$exe )
    return 0
}

build ci t.c -fcallgraph-info=su,da || exit 1
build noci n.c || exit 1
build frag i.c -fcallgraph-info=su,da || exit 1
build dup d.c -fcallgraph-info=su,da || exit 1
build clash c.c -fcallgraph-info=su,da || exit 1
if [ ! -f ci/t.ci ] ; then
    echo "${CC} wrote no 'ci/t.ci' beside the '.gcno' - skipping callee" \
         "error test"
    exit 0
fi
if [ -f noci/n.ci ] ; then
    # the missing-'.ci' scenario depends on this, and a compiler which wrote one
    #   without being asked would make it pass for the wrong reason
    fail fixture "'noci/n.ci' exists, but n.c was built without" \
        "-fcallgraph-info"
    exit 1
fi
# the pristine copy the unpaired-call scenarios are edited from
cp ci/t.ci ci/t.ci.orig

# ----------------------------------------------------------------------
# Reading the result
# ----------------------------------------------------------------------
# The 'FNC:' records of a '.info' as "<caller>|<count>|<callee>", naming the
#   caller function rather than its index.  A site written in a file other than
#   its caller's own names that file, by index into the 'SF:' records, and is
#   reported as "<caller>@<file>" so that the two shapes are distinguishable.
#   Splitting on commas is safe here only because these fixtures are C:  a
#   demangled name contains commas, which is why 'geninfo.sh' does the same job
#   the hard way.
sites()
{
    # The caller name is resolved as each record is read, because a function
    #   index means what the section it is in says it means;  a source file index
    #   is global to the tracefile and may be defined after the record which uses
    #   it, so those are resolved at the end.
    awk -F, '
        /^SF:[0-9]+,/ {
            idx = substr($1, 4)
            path = substr($0, index($0, ",") + 1)
            sub(/^.*\//, "", path)
            sf[idx] = path
        }
        /^FNA:/ {
            # the index may carry flag letters, and an 'FNC:' index never does
            idx = substr($1, 5)
            sub(/[^0-9].*$/, "", idx)
            if (!(idx in name)) name[idx] = $3
        }
        /^FNC:/ {
            idx = substr($1, 5)
            where = ""
            if (idx ~ /@/) {
                where = substr(idx, index(idx, "@") + 1)
                sub(/@.*$/, "", idx)
            }
            site[++n] = name[idx] SUBSEP where SUBSEP $5 SUBSEP $6
        }
        END {
            for (i = 1; i <= n; ++i) {
                split(site[i], f, SUBSEP)
                printf "%s%s|%s|%s\n", f[1],
                       f[2] == "" ? "" : "@" sf[f[2]], f[3], f[4]
            }
        }' $1
}

flags()
{
    # flags file alias
    #   the flag letters of the 'FNA:' record of this alias - see 'geninfo.rst'
    awk -F, -v name="$2" '
        /^FNA:/ {
            if ($3 != name) next
            f = substr($1, 5)
            gsub(/[0-9]/, "", f)
            print f
        }' $1
}

checkCalledFromNowhere()
{
    # checkCalledFromNowhere label file alias expected
    #   whether this alias records having been called from a site this report
    #   cannot name.  'e' may be there too - linkage is a different assertion and
    #   this is not the test for it
    local label=$1 file=$2 alias=$3 expected=$4 actual
    actual=`flags $file $alias`
    case "$actual" in
        *x*) actual=1 ;;
        *)   actual=0 ;;
    esac
    if [ "$expected" != "$actual" ] ; then
        fail $label "expected the 'x' flag of '$alias' to be $expected:" \
            "flags are '`flags $file $alias`'"
    fi
}

mustFail()
{
    # mustFail label regexp args..
    #   the capture has to fail, saying something which matches 'regexp'.  An
    #   unignored error stops the run where it happens, so there is exactly one
    #   message no matter how many functions the unit has
    local label=$1
    local re=$2
    shift 2
    $COVER $GENINFO_TOOL $LCOV_OPTS "$@" 2>&1 | tee $label.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        fail $label "geninfo did not fail:" \
            `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    if ! grep -q -E -e "$re" $label.log ; then
        fail $label "expected a failure matching '$re' but got:"
        cat $label.log
        return 1
    fi
    return 0
}

mustPass()
{
    # mustPass label args..
    #   the capture has to succeed;  what it kept is the caller's assertion
    local label=$1
    shift
    $COVER $GENINFO_TOOL $LCOV_OPTS "$@" 2>&1 | tee $label.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail $label "geninfo failed:" `grep -E 'ERROR' $label.log`
        return 1
    fi
    return 0
}

checkSites()
{
    # checkSites label file <<expected
    #   compare the call sites of a '.info' against the expected text on stdin
    local label=$1
    local file=$2
    if [ ! -f $file ] ; then
        fail $label "$file was not written"
        cat > /dev/null
        return
    fi
    cat > $label.expect
    sites $file | sort > $label.actual
    if ! diff -u $label.expect $label.actual ; then
        fail $label "unexpected call sites in $file"
    fi
}

# ----------------------------------------------------------------------
echo "*** 1. gcov is too old"
# ----------------------------------------------------------------------
# There is no way to ask a new gcov to be old, and no way to know whether an old
#   one is installed, so the version - and only the version - comes from a
#   wrapper.  Everything else is answered by the real gcov, so the capture
#   around the error is a real capture.
cat >fakegcov <<EOF
#! /usr/bin/env bash
# report the newest gcov which is too old:  gcc 13 writes the '.ci', but its
#   gcov has no count for each call;  hand everything else to the real gcov
if [ "\$1" == "--version" ] ; then
    echo "gcov (GCC) 13.3.0"
    exit 0
fi
exec $GCOV "\$@"
EOF
chmod ugo+x fakegcov
FAKEGCOV=`pwd`/fakegcov

$COVER $GENINFO_TOOL $LCOV_OPTS --gcov-tool $FAKEGCOV --callgraph \
    -o old.info ci/t.gcda 2>&1 | tee old.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail old "geninfo did not fail on gcov 13:" \
        `grep -E 'ERROR|WARNING' old.log`
fi
if ! grep -q -E 'requires gcov 14 or later' old.log ; then
    fail old "expected the message to say which gcov is needed:"
    cat old.log
fi

# ..and ignoring it turns the metric off rather than reporting it as empty:
#   there is no 'FNC' data of any kind, not even a total
$COVER $GENINFO_TOOL $LCOV_OPTS --gcov-tool $FAKEGCOV --callgraph \
    --ignore-errors unsupported -o old2.info ci/t.gcda 2>&1 | tee old2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail old_ignore "geninfo failed with the error ignored:" \
        `grep -E 'ERROR' old2.log`
fi
if [ 0 != `grep -c -E '^FNC' old2.info` ] ; then
    fail old_ignore "callgraph coverage was not turned off:" \
        `grep -E '^FNC' old2.info`
fi
# ..while the rest of the capture is untouched, i.e. the run really did continue
if [ 0 == `grep -c -E '^FNA:' old2.info` ] ; then
    fail old_ignore "the capture lost its function data as well:"
    cat old2.log
fi

# ----------------------------------------------------------------------
echo "*** 2. no callgraph info beside the object"
# ----------------------------------------------------------------------
$COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -o noci.info noci/n.gcda 2>&1 |
    tee noci.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail noci "geninfo did not fail on an object with no callgraph info:" \
        `grep -E 'ERROR|WARNING' noci.log`
fi
if ! grep -q -E 'no callgraph info' noci.log ; then
    fail noci "expected the message to name the missing data:"
    cat noci.log
fi
if ! grep -q -E "fcallgraph-info" noci.log ; then
    fail noci "expected the message to say how to produce it:"
    cat noci.log
fi

# Ignored, and this run captured no call site anywhere:  the metric is not
#   measurable here, so geninfo turns it off and writes no 'FNC' record of any
#   kind - not even a zero total.  Ignoring the error means continuing, not
#   claiming to have measured something; the reason was already reported where
#   it was found, so the run just says what it did and goes on.  Contrast
#   section 3:  the decision is about the run, while the error stays per object.
$COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --ignore-errors unsupported \
    -o noci2.info noci/n.gcda 2>&1 | tee noci2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail noci_ignore "geninfo failed with the error ignored:" \
        `grep -E 'ERROR' noci2.log`
fi
if [ 0 != `grep -c -E '^FNC' noci2.info` ] ; then
    fail noci_ignore "callgraph coverage was not turned off:" \
        `grep -E '^FNC' noci2.info`
fi
if ! grep -q -E 'turning the metric off' noci2.log ; then
    fail noci_ignore "expected the run to say that it turned the metric off:"
    cat noci2.log
fi
# ..while the rest of the capture is untouched, i.e. the run really did continue
if [ 0 == `grep -c -E '^FNA:' noci2.info` ] ; then
    fail noci_ignore "the capture lost its function data as well:"
    cat noci2.log
fi

# ----------------------------------------------------------------------
echo "*** 3. a mixed build, ignored"
# ----------------------------------------------------------------------
# The case the error class exists for:  two objects, one compiled with the flag
#   and one without.  The one which has the data keeps every one of its sites,
#   which is the assertion that the error is per object and not per run.
$COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --ignore-errors unsupported \
    -o mixed.info ci/t.gcda noci/n.gcda 2>&1 | tee mixed.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail mixed "geninfo failed on a mixed build:" `grep -E 'ERROR' mixed.log`
fi
sites mixed.info | sort > mixed.actual
cat >mixed.expected <<'EOF'
main|1|other
main|1|three
other|1|a
other|1|b
three|1|a
three|1|b
three|1|c
three|1|sum3
EOF
if ! diff -u mixed.expected mixed.actual > mixed.diff ; then
    fail mixed "the object which has callgraph info lost sites:"
    cat mixed.diff
fi

# ..and the message is said once, not once per object without the data.  Both
#   objects of this run have a '.gcno';  only one has a '.ci'
if [ 1 != `grep -c -E 'no callgraph info' mixed.log` ] ; then
    fail mixed_once "expected the warning exactly once:" \
        `grep -E 'no callgraph info' mixed.log`
fi

# ..and the object which has no data claims none.  'n.c's 'main' does call
#   'helper', so the one thing which is certainly wrong to write for it is
#   'FNCF:0'/'FNCH:0' - "this file's calls were counted, and there are none".
#   Nothing in the capture distinguishes that from a leaf translation unit, which
#   is why the pair is written where there is a measurement behind it and nowhere
#   else:  a site of its own, a call which left the boundary of the report, or a
#   call into it from a file which does have the data (see
#   FunctionMap::hasCallgraphData).  't.c' has the first of those and keeps both
#   records
awk '/^SF:/ { file = $0; sub(/^.*\//, "", file) }
     /^FNC[FH]:/ { printf "%s|%s\n", file, $0 }' mixed.info > mixedtotals.actual
cat >mixedtotals.expected <<'EOF'
t.c|FNCF:8
t.c|FNCH:8
EOF
if ! diff -u mixedtotals.expected mixedtotals.actual > mixedtotals.diff ; then
    fail mixed_totals "the call totals are not on the objects which measured them:"
    cat mixedtotals.diff
fi
# ..while the function data of both objects is there either way:  what the object
#   without the '.ci' loses is the callgraph metric, not its functions
for fn in helper main ; do
    if ! grep -q -E "^FNA:[0-9]+,1,$fn\$" mixed.info ; then
        fail mixed_totals "'$fn' is missing from the capture:"
        grep -E '^FN[AL]:' mixed.info
    fi
done

# ----------------------------------------------------------------------
echo "*** 4. gcov counted a call the callgraph info does not list"
# ----------------------------------------------------------------------
# One arc with no edge:  gcov has a count for a call whose callee nothing names,
#   which is what a call the compiler generated rather than one the source makes
#   looks like from here.  There is no callee to record it against, so it is lost
#   either way - what the error says is that the function's remaining sites are
#   a pairing of two sequences which did not agree.
# Produced by removing one of three's four edges, because a compiler-generated
#   call is not something a testcase can conjure on demand.
perl -ne 'if (!$d && /^edge:.*sourcename:\s*"three"/) { $d = 1; next } print' \
    ci/t.ci.orig > ci/t.ci
if [ `grep -c -E 'sourcename:\s*"three"' ci/t.ci` != \
     `expr \`grep -c -E 'sourcename:\s*"three"' ci/t.ci.orig\` - 1` ] ; then
    fail extra "could not remove an edge from 'ci/t.ci':"
    grep -E 'sourcename:\s*"three"' ci/t.ci.orig
fi

# the message says which direction, how many of how many, and where
mustFail extra \
    "'three':  1 of the 4 call\(s\) gcov reports are not in the callgraph info \(t\.c:5\)" \
    --callgraph -o extra.info ci/t.gcda
# ..and gives the advice for this direction and not the other one:  rebuilding
#   without inlining would not put a callee on a call the callgraph info never
#   named, and telling the user to try is telling them to waste a build
if [ -f extra.log ] && grep -q -F -e 'fno-inline' extra.log ; then
    fail extra "expected the message not to blame inlining:"
    cat extra.log
fi

# Ignored, the caller whose sites cannot be paired loses all of them - there is
#   nothing to say which of the four lost its edge - and no other function is
#   affected.  The metric stays on, because the rest of the file was measured.
mustPass extra_drop --callgraph --ignore-errors inconsistent \
    -o extra_drop.info ci/t.gcda
checkSites extra_drop extra_drop.info <<'EOF'
main|1|other
main|1|three
other|1|a
other|1|b
EOF

# ..and with '--callgraph-partial-data' the three edges which did pair are kept.
#   Nothing is recorded with an unknown count:  the call which went missing is
#   gcov's, and a count with no callee is not a call site
mustPass extra_partial --callgraph --callgraph-partial-data \
    --ignore-errors inconsistent -o extra_partial.info ci/t.gcda
checkSites extra_partial extra_partial.info <<'EOF'
main|1|other
main|1|three
other|1|a
other|1|b
three|1|a
three|1|b
three|1|sum3
EOF
if [ -f extra_partial.info ] &&
   grep -q -E '^FNC:[0-9]+,[0-9]+,[0-9]+,[0-9]+,-,' extra_partial.info ; then
    fail extra_partial "an arc with no edge was recorded as an unknown count:"
    grep -E '^FNC' extra_partial.info
fi

# ----------------------------------------------------------------------
echo "*** 5. the callgraph info lists a call gcov has no count for"
# ----------------------------------------------------------------------
# The other direction, and the one inlining produces:  the call is gone from the
#   caller's CFG so gcov has no arc for it, while the callgraph info still lists
#   the edge.  Produced by duplicating one of three's edges rather than by
#   compiling at -O2, because which call a given compiler inlines at a given
#   optimization level is not something a testcase can depend on.
perl -ne 'print; if (!$d && /^edge:.*sourcename:\s*"three"/) { $d = 1; print }' \
    ci/t.ci.orig > ci/t.ci
if [ `grep -c -E 'sourcename:\s*"three"' ci/t.ci` != \
     `expr \`grep -c -E 'sourcename:\s*"three"' ci/t.ci.orig\` + 1` ] ; then
    fail missing "could not duplicate an edge in 'ci/t.ci':"
    grep -E 'sourcename:\s*"three"' ci/t.ci.orig
fi

mustFail missing \
    "'three':  1 of the 5 call site\(s\) callgraph info '[^']*t\.ci' lists have no call in gcov's data \(t\.c:5:[0-9]+\)" \
    --callgraph -o missing.info ci/t.gcda
# ..and this is the direction where there is something to keep, so the message
#   says how
if [ -f missing.log ] ; then
    if ! grep -q -F -e 'fno-inline' missing.log ; then
        fail missing "expected the message to name inlining as the cause:"
        cat missing.log
    fi
    if ! grep -q -F -e '--callgraph-partial-data' missing.log ; then
        fail missing "expected the message to say how to keep the rest:"
        cat missing.log
    fi
fi

# Ignored and with the default policy, the answer is the same as above:  the
#   whole function's callgraph data goes
mustPass missing_drop --callgraph --ignore-errors inconsistent \
    -o missing_drop.info ci/t.gcda
checkSites missing_drop missing_drop.info <<'EOF'
main|1|other
main|1|three
other|1|a
other|1|b
EOF

# ..and this is what '--callgraph-partial-data' is for:  the sites are kept, with an
#   unknown count.  Not 0:  "not measured" and "the tests never made this call"
#   are different claims, and only the first is supported by this data.
# Every one of three's, not just the unpaired one, because all of them are on
#   line 5 - 'three' is 'return sum3(a(), b(), c());' and the compiler folds all
#   four calls onto the location of the outer one.  Four arcs for five edges says
#   that one of the five was not counted and says nothing about which, so no count
#   on that line can be attributed:  the walk gives the arcs to the earlier edges
#   because nothing distinguishes them, and from -O1 that is not just arbitrary
#   but usually wrong - '-fipa-pure-const' deletes the arc of whichever callees
#   it proves nothrow, in no source order.  A wrong number is worse than none.
#   The case where a site does keep its count while another is unpaired is
#   scenario 7 below, where the two are on different lines
# Four sites and not five, though the edges are five:  the extra edge is a second
#   edge to 'c' from where the one call to 'c' is written, and that is one call
#   site - see join_call_sites.  The pairing still sees five edges, which is why
#   it still reports a mismatch;  what folds is what gets recorded
mustPass missing_partial --callgraph --callgraph-partial-data \
    --ignore-errors inconsistent -o missing_partial.info ci/t.gcda
checkSites missing_partial missing_partial.info <<'EOF'
main|1|other
main|1|three
other|1|a
other|1|b
three|-|a
three|-|b
three|-|c
three|-|sum3
EOF
# ..and the message says so, separately from the unpaired edge itself:  a user
#   looking at a call gcov obviously counted and a report which shows no number
#   for it has to be able to find out why
if [ -f missing_partial.log ] &&
   ! grep -q -F -e 'further site(s) are on a line with one of those' \
        missing_partial.log ; then
    fail missing_partial "the voided sites were not reported:" \
        `grep -E '(ERROR|WARNING)' missing_partial.log`
fi
# ..and the unknown ones are in the total and not in the hits, which is the whole
#   reason it is a third state rather than a zero
if [ -f missing_partial.info ] &&
   ! grep -q -E '^FNCF:8$' missing_partial.info ; then
    fail missing_partial "expected 'FNCF:8':" \
        `grep -E '^FNC[FH]:' missing_partial.info`
fi
if [ -f missing_partial.info ] &&
   ! grep -q -E '^FNCH:4$' missing_partial.info ; then
    fail missing_partial "expected 'FNCH:4' - a call with no count is not a" \
        "call which was made:" `grep -E '^FNC[FH]:' missing_partial.info`
fi

# 'lcov --capture' does not read a '.gcda' itself, it builds a geninfo command
#   line - so the option has to be on that command line.  Nothing else in this
#   run would show it missing:  a capture which dropped it would collect the same
#   file with three's data thrown away and say nothing about the difference
$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --callgraph-partial-data \
    --ignore-errors inconsistent --capture ci/t.gcda -o cap.info 2>&1 | tee cap.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail capture "lcov --capture failed:" `grep -E 'ERROR' cap.log`
fi
checkSites capture cap.info <<'EOF'
main|1|other
main|1|three
other|1|a
other|1|b
three|-|a
three|-|b
three|-|c
three|-|sum3
EOF

# ----------------------------------------------------------------------
echo "*** 6. more unpaired calls than the message lists"
# ----------------------------------------------------------------------
# A unit built with inlining on can have hundreds of unpaired calls, and a
#   message which listed all of them would be unreadable and would say nothing
#   the first few do not - so the list is cut off at three and ends with '...'.
#   Produced by duplicating every one of three's edges:  eight edges against
#   four arcs pairs the first four and leaves four with no arc, whichever order
#   the compiler lists them in.
perl -ne 'print; print if /^edge:.*sourcename:\s*"three"/' \
    ci/t.ci.orig > ci/t.ci
if [ `grep -c -E 'sourcename:\s*"three"' ci/t.ci` != \
     `expr 2 \* \`grep -c -E 'sourcename:\s*"three"' ci/t.ci.orig\`` ] ; then
    fail truncated "could not duplicate three's edges in 'ci/t.ci':"
    grep -E 'sourcename:\s*"three"' ci/t.ci
fi

# three locations and then '...', not four locations
mustFail truncated \
    "'three':  4 of the 8 call site\(s\) callgraph info '[^']*t\.ci' lists have no call in gcov's data \(t\.c:5:[0-9]+, t\.c:5:[0-9]+, t\.c:5:[0-9]+, \.\.\.\)" \
    --callgraph -o truncated.info ci/t.gcda

# ----------------------------------------------------------------------
echo "*** 7. both directions at once"
# ----------------------------------------------------------------------
# The two are counted separately and reported separately, because they are
#   different problems with different answers - so a function which has one of
#   each says both.  Produced by moving one edge to a line gcov reports no call
#   at:  that edge then finds no arc, and the arc it would have taken is left
#   over for nobody, which is one of each.
perl -pe 'if (!$d && /^edge:.*sourcename:\s*"three"/) {
              $d = 1 if s/(label: "[^"]*):\d+:/$1:99:/;
          }' ci/t.ci.orig > ci/t.ci
if ! grep -q -E ':99:' ci/t.ci ; then
    fail both "could not move an edge's line in 'ci/t.ci':"
    grep -E 'sourcename:\s*"three"' ci/t.ci.orig
fi

mustFail both \
    "have no call in gcov's data \(t\.c:99:[0-9]+\), and 1 of the 4 call\(s\) gcov reports are not in the callgraph info" \
    --callgraph -o both.info ci/t.gcda

# ..and with the data kept, the moved edge is the one with no count.  It is
#   recorded at the line the callgraph info gave it, which is the only location
#   the capture has for it:  the pairing believes the edge about where a call is,
#   and here the edge is what was made wrong.
# This is also the negative half of the voiding rule scenario 5 asserts:  the
#   unpaired edge is at line 99 and three's other three calls are at line 5,
#   where three edges meet four arcs, so those three keep their counts.  Voiding
#   is per line and not per function - a line the two sequences agree about is
#   not in doubt
# Line 99 of a seven line file is also out of range, and a call site is a
#   coverpoint like any other, so the filters say so - the same 'range' message a
#   line record at line 99 would get, which is why it is ignored here and
#   asserted below rather than being left to fail the capture
mustPass both_partial --callgraph --callgraph-partial-data \
    --ignore-errors inconsistent,range -o both_partial.info ci/t.gcda
if [ -f both_partial.log ] &&
   ! grep -q -E "unknown line '99' in .*t\.c" both_partial.log ; then
    fail both_partial "the out-of-range call site was not reported:"
    grep -E 'ERROR|WARNING' both_partial.log
fi
checkSites both_partial both_partial.info <<'EOF'
main|1|other
main|1|three
other|1|a
other|1|b
three|-|c
three|1|a
three|1|b
three|1|sum3
EOF
if [ -f both_partial.info ] &&
   ! grep -q -E '^FNC:[0-9]+,99,[0-9]+,0,-,c$' both_partial.info ; then
    fail both_partial "expected the unpaired site at the line its edge gave:"
    grep -E '^FNC' both_partial.info
fi

cp ci/t.ci.orig ci/t.ci

# ----------------------------------------------------------------------
echo "*** 8. a call gcov could not attribute to a function"
# ----------------------------------------------------------------------
# gcov names the function a line belongs to only when that function is defined
#   in the same file as the line, so the call in the '#include'd fragment is
#   reported with no caller at all.  The callgraph info does know - there is an
#   edge from 'main' at that line and from nowhere else - so the attribution is
#   repaired and the site pairs:  nothing is unpaired, because nothing about this
#   unit is inconsistent.
# Writing it down needs the file the call is in, which an 'FNC:' record carries as
#   an index into the tracefile's 'SF:' records - this site is in 'inc.h' while
#   'main' is in 'i.c', so the record goes to 'i.c's section and names 'inc.h'.
#   'format.sh' scenario 15 pins that syntax and 'geninfo.sh' scenario 12 pins a
#   capture of it;  what this scenario adds is that the repaired attribution and
#   the cross-file record work together, the site being one gcov did not attribute
#   to any function in the first place.
# Not a diagnostic of any kind:  nothing about this unit is inconsistent and
#   nothing is dropped, so there is nothing the user could act on
mustPass frag --callgraph -o frag.info frag/i.gcda
if [ -f frag.log ] && grep -q -E -e '(ERROR|WARNING)' frag.log ; then
    fail frag "a cross-file call site was reported as a problem:"
    cat frag.log
fi
checkSites frag frag.info <<'EOF'
main@inc.h|1|helper
main|1|other
other|1|helper
EOF
# ..and no callee records having been called from a site the report cannot name:
#   every site here was written down, the fragment's included
checkCalledFromNowhere frag frag.info helper 0
checkCalledFromNowhere frag frag.info other 0

# ----------------------------------------------------------------------
echo "*** 9. a fragment '#include'd into two function bodies"
# ----------------------------------------------------------------------
# Where that repair stops:  the line is in the body of both functions, each has
#   an edge there, and nothing chooses between them - so attributing the count to
#   either would be putting it on the wrong call.  Both callers are then left
#   with an edge and no arc - an unpaired call whose cause no optimization setting
#   helps with - and the message says so instead of asking for a rebuild.
#
# Whether it happens at all depends on how gcov distributes an arc over the lines
#   its block was built from, which is not something this test can pin down:  if
#   the arc turns up under a line of 'd.c' as well then that line has exactly one
#   owner, the repair applies, and this is scenario 7 again.  So probe first
mustPass dup_probe --callgraph --callgraph-partial-data \
    --ignore-errors inconsistent -o dup_probe.info dup/d.gcda
if [ -f dup_probe.log ] && ! grep -q -F -e '(inconsistent)' dup_probe.log ; then
    echo "gcov '${GCOV}' attributes the fragment's call to a line of the" \
         "including file - skipping the contested fragment scenario"
else
    # said once per caller, because it is the caller's data which is at stake
    for who in runA runB ; do
        if ! grep -q -E -e "'$who':  1 of the 1 call site\(s\) callgraph info '[^']*d\.ci' lists have no call in gcov's data \(body\.inc:1:[0-9]+\)" \
             dup_probe.log ; then
            fail dup "expected '$who' to be reported:"
            grep -E 'inconsistent' dup_probe.log
        fi
    done
    # ..with the cause named and no rebuild suggested
    if ! grep -q -F -e "'#include'd into more than one function body" \
            dup_probe.log ; then
        fail dup "expected the message to name the fragment as the cause:"
        grep -E 'inconsistent' dup_probe.log
    fi
    if grep -q -F -e 'fno-inline' dup_probe.log ; then
        fail dup "expected no advice to rebuild - no build setting helps:"
        grep -E 'inconsistent' dup_probe.log
    fi

    # The site the option keeps is written in 'body.inc' and its caller is in
    #   'd.c', so it is recorded naming the file it is in - once per including
    #   function, since each of them has an edge there and the count belongs to
    #   neither.  Which is the whole visible difference between the two tiers
    #   here:  one unknown count per caller, expressed as a cross-file record.
    # ..and 'helper' does not record having been called from a site the report
    #   cannot name:  both sites are in the report, and an unknown count is no
    #   evidence of a call in any case - the flag asserts that a call happened and
    #   can never be taken back once it is set
    checkSites dup_probe dup_probe.info <<'EOF'
main|1|runA
main|1|runB
runA@body.inc|-|helper
runB@body.inc|-|helper
EOF
    checkCalledFromNowhere dup_probe dup_probe.info helper 0

    # ..and without the option, only the sites which paired:  the unpaired one is
    #   dropped with the rest of its caller's callgraph data
    mustPass dup_drop --callgraph --ignore-errors inconsistent \
        -o dup_drop.info dup/d.gcda
    checkSites dup_drop dup_drop.info <<'EOF'
main|1|runA
main|1|runB
EOF
    # ..and without it there is no site to drop at all:  the whole function's
    #   callgraph data goes, which is a different route to the same answer
    checkCalledFromNowhere dup_drop dup_drop.info helper 0
fi

# ----------------------------------------------------------------------
echo "*** 10. a fragment's call numbered like a call of its own function"
# ----------------------------------------------------------------------
# The fragment's call is claimed by 'main' only if it is a second report of one
#   of main's own calls, and the block number cannot say so by itself.  A wrapper
#   around the real gcov gives the fragment's arc the block number of main's own
#   call to 'other' - once with the fragment's count, which disagrees with that
#   call's, and once with that call's count as well, when what is left to tell
#   them apart is that main's call to 'other' is already the call written at its
#   own line.  Either way the arc is not main's, the site at the fragment is the
#   unpaired one, and 'other' keeps its count.  Claimed, the fragment's edge -
#   the first in main - would have been paired with the call to 'other' and got
#   its count, leaving 'other' with none

# the arc of a line gcov gave no function renumbered to the block of main's own
#   call - and given its count, if $CLASH_COUNT is set.  $CLASH_MARK is written
#   when there was such an arc to renumber
cat >clashjson.pl <<'EOF'
use JSON::PP;
my $text = do { local $/; <STDIN> };
my $d     = JSON::PP->new->decode($text);
my @lines = map({ @{$_->{lines}} } @{$d->{files}});
my ($own) = grep({ ($_->{function_name} // "") eq "main" && @{$_->{calls}} }
                 @lines);
if ($own) {
    my $call = $own->{calls}->[0];
    foreach my $l (grep({ !exists($_->{function_name}) } @lines)) {
        foreach my $c (@{$l->{calls}}) {
            $c->{source_block_id} = $call->{source_block_id};
            $c->{returned}        = $call->{returned} if $ENV{CLASH_COUNT};
            open(my $mark, ">", $ENV{CLASH_MARK}) and close($mark);
        }
    }
}
print(JSON::PP->new->encode($d));
EOF
# ..run on what the real gcov wrote:  geninfo reads gcov's JSON from its stdout
#   (every gcov new enough for callgraph coverage can write it there)
cat >clashgcov <<EOF
#! /usr/bin/env bash
for arg in "\$@" ; do
    if [ "--stdout" == "\$arg" ] ; then
        set -o pipefail
        $GCOV "\$@" | perl `pwd`/clashjson.pl
        exit \$?
    fi
done
exec $GCOV "\$@"
EOF
chmod ugo+x clashgcov
export CLASH_MARK=`pwd`/clash.mark

rm -f $CLASH_MARK
mustPass clash_probe --gcov-tool `pwd`/clashgcov --callgraph \
    --callgraph-partial-data --ignore-errors inconsistent \
    -o clash_probe.info clash/c.gcda
if [ ! -f $CLASH_MARK ] ; then
    echo "gcov '${GCOV}' attributes the fragment's call to a function, or" \
         "'main' has no call of its own - skipping the block number scenario"
else
    for how in count spoken ; do
        if [ spoken == $how ] ; then
            export CLASH_COUNT=1
        fi
        mustFail clash_$how \
            "'main':  1 of the 2 call site\(s\) callgraph info '[^']*c\.ci' lists have no call in gcov's data \(inc\.h:1:[0-9]+\)" \
            --gcov-tool `pwd`/clashgcov --callgraph -o clash_$how.info \
            clash/c.gcda
        if [ -f clash_$how.log ] &&
           ! grep -q -F -e "already has a call with the arc's block number" \
                clash_$how.log ; then
            fail clash_$how "expected the message to name the block number:"
            grep -E 'inconsistent' clash_$how.log
        fi
        mustPass clash_${how}_partial --gcov-tool `pwd`/clashgcov \
            --callgraph --callgraph-partial-data \
            --ignore-errors inconsistent -o clash_${how}_partial.info \
            clash/c.gcda
        checkSites clash_${how}_partial clash_${how}_partial.info <<'EOF'
main@inc.h|-|helper
main|3|other
other|3|helper
EOF
    done
    unset CLASH_COUNT
fi

# ----------------------------------------------------------------------
echo "*** 11. a call written in a file gcov did not describe"
# ----------------------------------------------------------------------
# A site is written naming the file its call is in, and a file gcov wrote no
#   data for has no section for the record to name - so the site cannot be kept.
#   What can be kept is the fact that its callee was called from somewhere this
#   report cannot name:  the 'x' flag of the callee, which counts the calls the
#   dropped sites made.  Neither of the two here has a count - gcov described
#   neither of them - so the flag is a bare 'x', and whether 'helper' was called
#   from anywhere else cannot be told either.
# The fixture is the '#include'd fragment of scenario 8 with two calls in it, so
#   that a second dropped site is added to what the first left, and a wrapper
#   around the real gcov which removes the fragment's file from what it reports
mkdir gone
cat >gone/inc.h <<'EOF'
    t += helper();
    t += helper();
EOF
sed -e 's/return t != 2;/return t != 3;/' frag/i.c > gone/i.c
build gone i.c -fcallgraph-info=su,da || exit 1
cat >gonejson.pl <<'EOF'
use JSON::PP;
my $text = do { local $/; <STDIN> };
my $d    = JSON::PP->new->decode($text);
$d->{files} = [grep({ $_->{file} !~ /inc\.h$/ } @{$d->{files}})];
print(JSON::PP->new->encode($d));
EOF
cat >gonegcov <<EOF
#! /usr/bin/env bash
for arg in "\$@" ; do
    if [ "--stdout" == "\$arg" ] ; then
        set -o pipefail
        $GCOV "\$@" | perl `pwd`/gonejson.pl
        exit \$?
    fi
done
exec $GCOV "\$@"
EOF
chmod ugo+x gonegcov
mustPass gone --gcov-tool `pwd`/gonegcov --callgraph --callgraph-partial-data \
    --ignore-errors inconsistent -o gone.info gone/i.gcda
checkSites gone gone.info <<'EOF'
main|1|other
other|1|helper
EOF
if [ -f gone.info ] && ! grep -q -E -e '^FNA:[0-9]+e?x,3,helper$' gone.info ; then
    fail gone "expected 'helper' to be called 3 times, with a bare 'x':" \
        `grep -E '^FNA:' gone.info`
fi
checkCalledFromNowhere gone gone.info other 0

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'unsupported' $LOCAL_COVERAGE 0
fi

exit $STATUS
