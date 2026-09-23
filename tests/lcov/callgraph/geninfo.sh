#! /usr/bin/env bash

# Capturing callgraph coverage from a real compiler:  the only testcase in this
# directory which needs one.
#
# geninfo has to put two things together which no single tool produces.  gcov
#   says that a call happened on some line and how often, and never what was
#   called;  '-fcallgraph-info' says what is called from where, with a column,
#   and knows nothing about counts.  The join is positional, per caller function
#   - both sequences are in gimple order - and the reason it has to be
#   positional rather than by location is measured here rather than asserted:
#
#   - 'sum2(i ? y() : 0, w())' gives the edges to 'w' and to 'sum2' the same
#     column, because the compiler folds a nested call's location onto the
#     enclosing call.  Sorting the sites by column therefore has to break a tie
#     between them, and either way it breaks it, it hands y's count to 'sum2'.
#     So this testcase asserts the three counts, not just the three sites:  it
#     is the case which tells a correct implementation from a plausible one.
#   - the same folding is why a site key carries an ordinal.  Two of outer's
#     three sites, and all four of three's, differ only by it.
#   - and the ordinal numbers the sites of a coverpoint rather than of a symbol,
#     which is what the template fixture is for:  two instantiations are two
#     symbols defined at one line, hence aliases of one function, hence one site
#     list for both.
#   - what it does not distinguish is two arcs of one call.  A cleanup path calls
#     a local's destructor a second time, from the same place and to the same
#     callee, and gcov counts that arc apart with a count of zero;  the two fold
#     into one site, so what is measured is a call as it is written and the
#     '-fno-exceptions' build of the same program measures the same calls.
#
# And the counts are per call site, never per line:  a call in a '?:' arm or
#   after '&&' can go untaken on a line which executed, so a report built from
#   the line's count would show unexecuted calls as covered.  'pick' and 'andor'
#   are here for that, and their expected numbers (0 on a line whose count is 5,
#   0 on a line whose count is 1) are the ones an implementation that reused the
#   line count cannot produce.
#
# The assertions are written against callee names and counts rather than against
#   the emitted records verbatim, because the emission order and the columns
#   belong to the compiler:  what must be stable across compiler versions is the
#   truth about the program, which is what a correct join recovers.  Where the
#   record layout itself is the point - the ordinal collision - the assertion is
#   on the shape of the group of records at one location, not on the column.

source ../../common.tst

# The assertions below compare sorted lists of function names, and 'sort' in a
# locale ignores '_' and case:  the mangled names of the C++ fixture come out in
# one order under en_US and another under C.  Pin the collation rather than the
# expectations, which are written in the order the tool writes the names.
export LC_ALL=C

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
    rm -rf geninfo.d
    exit 0
fi

rm -rf geninfo.d
mkdir geninfo.d
cd geninfo.d || exit 1

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
         "- skipping callgraph capture test"
    cat probe.log
    exit 0
fi

# ..and geninfo refuses the request below gcov 14, which 'unsupported.sh'
#   is the testcase for.  A toolchain whose compiler has the option but whose
#   gcov is older is nothing this testcase can say anything about
GCOV_VER=`${GCOV} --version 2>/dev/null | head -1 | sed -e 's/.* //'`
IFS='.' read -r -a GVER <<< "$GCOV_VER"
if [ "${GVER[0]}" -lt 14 ] ; then
    echo "gcov '${GCOV}' is version $GCOV_VER - skipping callgraph capture test"
    exit 0
fi

# ----------------------------------------------------------------------
# The fixtures
# ----------------------------------------------------------------------
# Written here rather than kept as files because the numbers this testcase
#   asserts are properties of these exact bodies, and reading the two in one
#   place is the only way the expectations can be checked by eye.

# The C++ case:  a local (comdat) member symbol, which the callgraph info
#   file-qualifies; two calls to one callee on one line, distinguished only by
#   column; a call spread over three lines; an external callee ('printf') which
#   has no coverage data but does consume one of the line's gcov entries; and a
#   function which is never called, whose sites must be found and unexecuted.
cat >cs.cpp <<'EOF'
#include <stdio.h>
struct S { double m(double d) { return d * 2; } };
int freefn(int a, int b) { return a + b; }
int multi(S& s) { return freefn(
    1,
    2) + (int)s.m(3.0); }
int twice(int x) { return freefn(x, 1) + freefn(x, 2); }
int notcalled(S& s) { return (int)s.m(1.0); }
int main() { S s; printf("%d\n", multi(s) + twice(2)); return 0; }
EOF

# The C case, all of whose call sites are on one line per function, and whose
#   true counts are known by construction:  'outer' runs with i = 0,1,2 so w is
#   3, y is 2 (the '?:' arm is skipped once) and sum2 is 3;  'pick' runs 5 times
#   with the condition always true, so f is 5 and g is 0;  'andor' runs once
#   with the condition false, so f is 0;  'three' runs once, so each of a, b, c
#   and sum3 is 1 - and all four of its edges carry the same column.
cat >v.c <<'EOF'
int y(void) { return 1; }
int w(void) { return 2; }
int sum2(int a, int b) { return a + b; }
int f(void) { return 3; }
int g(void) { return 4; }
int a(void) { return 5; }
int b(void) { return 6; }
int c(void) { return 7; }
int sum3(int x, int y, int z) { return x + y + z; }
int outer(int i) { return sum2(i ? y() : 0, w()); }
int pick(int cc) { return cc ? f() : g(); }
int andor(int cc) { return cc && f(); }
int three(void) { return sum3(a(), b(), c()); }
int main(void) { int t = 0; for (int i = 0; i < 3; ++i) t += outer(i); for (int i = 0; i < 5; ++i) t += pick(1); t += andor(0); t += three(); return t == 0; }
EOF

build()
{
    # build compiler exe source
    echo "$1 --coverage -fcallgraph-info=su,da -O0 -o $2 $3"
    $1 --coverage -fcallgraph-info=su,da -O0 -o $2 $3 || return 1
    if [ ! -f $2.ci ] ; then
        # the whole testcase depends on where the compiler puts this
        fail build "$1 wrote no '$2.ci' beside the '.gcno'"
        return 1
    fi
    ./$2
    return 0
}

build ${CXX} cs cs.cpp || exit 1
build ${CC} v v.c || exit 1

# ----------------------------------------------------------------------
# Reading the result
# ----------------------------------------------------------------------
# Turn the 'FNC:' records of a '.info' into one line per call site, naming the
#   caller rather than its index:
#
#   <caller>|<line>:<column>:<ordinal>|<count>|<callee>
#
# Written with index()/substr() rather than by splitting on commas because a
#   demangled name contains them:  the callee is the last field of the record
#   and keeps its commas, exactly as 'FNA:' does.
sites()
{
    awk '
        /^FNA:/ {
            s = substr($0, 5)
            i = index(s, ","); idx = substr(s, 1, i - 1); s = substr(s, i + 1)
            # the index of an 'FNA:' may carry flag letters;  an 'FNC:' index
            #   never does
            sub(/[^0-9].*$/, "", idx)
            i = index(s, ",")
            if (!(idx in name)) name[idx] = substr(s, i + 1)
            alias[idx, nalias[idx]++] = substr(s, i + 1)
            next
        }
        /^FNC:/ {
            s = substr($0, 5); n = 0
            while (n < 5) {
                i = index(s, ",")
                f[++n] = substr(s, 1, i - 1)
                s = substr(s, i + 1)
            }
            # the index may name the site file (@<n>) and the aliases the
            #   site belongs to (#<pos>[.<pos>...], positions among the
            #   FNA records of the index);  a site attributed to some of
            #   the aliases is reported under them, joined by '+'
            caller = f[1]; sub(/[@#].*$/, "", caller)
            who = name[caller]
            if (match(f[1], /#[0-9.]+$/)) {
                np = split(substr(f[1], RSTART + 1), pos, ".")
                who = alias[caller, pos[1]]
                for (k = 2; k <= np; ++k) who = who "+" alias[caller, pos[k]]
            }
            printf "%s|%s:%s:%s|%s|%s\n", who, f[2], f[3], f[4], f[5], s
        }' $1
}

# ..and the same without the location, which is what the counts assertions
#   compare:  "which callee was called how often, from which function".
calls()
{
    sites $1 | sed -e 's/|[0-9]*:[0-9]*:[0-9]*|/|/'
}

expect()
{
    # expect label actual-file expected-file
    local label=$1
    if ! diff -u $3 $2 > $label.diff ; then
        fail $label "call data is not what the program does:"
        cat $label.diff
    fi
}

# The 'd' flag of an 'FNA:' record - a caller deduced from the arithmetic - is
#   written only by a tool which has resolved the callgraph, and a capture has
#   not:  geninfo does not know what the other files it did not capture call.
#   So what a capture wrote and what a merge of it writes differ by exactly
#   that letter, and a round trip compares them without it.
noDeduced()
{
    # noDeduced label file - a capture wrote no 'd' flag
    if grep -q -E '^FNA:[0-9]+[a-z]*d[a-z]*,' $2 ; then
        fail $1 "a capture wrote a deduced-caller flag:" \
            `grep -E '^FNA:[0-9]+[a-z]*d[a-z]*,' $2`
    fi
}
stripDeduced()
{
    # stripDeduced file - the file with no 'd' flag
    sed -E -e 's/^(FNA:[0-9]+[a-z]*)d([a-z]*,)/\1\2/' $1
}

# ----------------------------------------------------------------------
echo "*** 1. the C++ case"
# ----------------------------------------------------------------------
$COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -o cs.info cs.gcda 2>&1 | tee cs.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail cs "geninfo failed:" `grep -E 'ERROR' cs.log`
fi

# 'printf' is here because it is the case which breaks an implementation that
#   drops uninteresting callees before pairing:  it has no coverage data of its
#   own, but it is one of main's three gcov entries, and discarding its edge
#   first shifts multi's and twice's counts onto the wrong callees.
# 'S::m' is here twice, and both times the callgraph info says
#   'cs.cpp:_ZN1S1mEd' - a local symbol, file-qualified - which has to resolve
#   to the same name gcov gave the function or the callee side is a dangling
#   string.
cat >cs.expected <<'EOF'
_Z5multiR1S|1|_Z6freefnii
_Z5multiR1S|1|_ZN1S1mEd
_Z5twicei|1|_Z6freefnii
_Z5twicei|1|_Z6freefnii
_Z9notcalledR1S|0|_ZN1S1mEd
main|1|_Z5multiR1S
main|1|_Z5twicei
main|1|printf
EOF
calls cs.info | sort > cs.actual
expect cs cs.actual cs.expected

# the two calls to 'freefn' from 'twice' are one line and two sites, and the
#   only thing which distinguishes them is the column
TWICE=`sites cs.info | grep -c -E '^_Z5twicei\|7:[0-9]+:0\|'`
if [ 2 != "$TWICE" ] ; then
    fail cs_columns "expected two sites on line 7 with ordinal 0, found $TWICE:"
    sites cs.info | grep '^_Z5twicei'
fi
if [ 2 != `sites cs.info | grep '^_Z5twicei' | cut -d'|' -f2 | sort -u | wc -l` ] ; then
    fail cs_columns "the two calls to 'freefn' share a site key:"
    sites cs.info | grep '^_Z5twicei'
fi

# the call spread over three source lines is one site, on the line the call
#   starts on - which is also the line gcov reports it on, or the pairing's
#   line cross-check would have dropped it
if [ 1 != `sites cs.info | grep -c -E '^_Z5multiR1S\|4:'` ] ; then
    fail cs_multiline "the call spanning lines 4-6 is not reported on line 4:"
    sites cs.info | grep '^_Z5multiR1S'
fi

# ----------------------------------------------------------------------
echo "*** 2. --demangle-cpp"
# ----------------------------------------------------------------------
# The callgraph info only ever says 'mangled', so under '--demangle-cpp' every
#   symbol has to be translated - the caller to find the function it belongs to,
#   the callee so that it names a function the report can resolve.  A missing
#   translation on the caller side loses the sites silently, which is why the
#   assertion is that the same eight sites are there.
$COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --demangle-cpp -o csd.info cs.gcda \
    2>&1 | tee csd.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail csd "geninfo --demangle-cpp failed:" `grep -E 'ERROR' csd.log`
fi

cat >csd.expected <<'EOF'
main|1|multi(S&)
main|1|printf
main|1|twice(int)
multi(S&)|1|S::m(double)
multi(S&)|1|freefn(int, int)
notcalled(S&)|0|S::m(double)
twice(int)|1|freefn(int, int)
twice(int)|1|freefn(int, int)
EOF
calls csd.info | sort > csd.actual
expect csd csd.actual csd.expected

# ..and each of those callees is a name the report knows the function by, not a
#   second spelling of it:  the callee side of a site is resolved by name, so a
#   callee defined in this file which is not also one of its aliases is a
#   dangling string
grep -E '^FNA:' csd.info > csd.aliases
for CALLEE in 'multi(S&)' 'twice(int)' 'S::m(double)' 'freefn(int, int)' ; do
    if ! grep -q -F -e ",$CALLEE" csd.aliases ; then
        fail csd_names "the callee '$CALLEE' is not the name of any function:"
        cat csd.aliases
    fi
done

# A callee defined in another translation unit ('printf' here) is not in gcov's
#   data at all, so the only spelling of it is the mangled one and the demangler
#   has to be run on it - with the name as an argument rather than on stdin,
#   which is the one way of invoking it whose failure shows up only as an exit
#   status.  Every other use of that form is on the binary-'.gcno' path, i.e.
#   reachable only with a gcov older than 9;  a callee name uses it on the
#   ordinary JSON path, so the failure is reachable on any toolchain and there is
#   no reason not to check that it is reported.
# The stub succeeds on empty input, because that is the check lcovutil makes
#   when it registers the tool, and fails as soon as it is handed a name.
cat >failfilt.sh <<'EOF'
#!/bin/bash

# skip the options lcovutil appends to the command
while [[ $1 =~ ^- ]] ; do
    shift
done
# no names:  this is the 'echo "" | tool' check, which has to pass
[ -z "$*" ] && exec cat
exit 3
EOF
chmod ugo+x failfilt.sh

$COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --demangle-cpp `pwd`/failfilt.sh \
    -o failfilt.info cs.gcda 2>&1 | tee failfilt.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail failfilt "expected the capture to fail when the demangler does"
fi
if ! grep -q -F -e "failfilt.sh' exited with error 3" failfilt.log ; then
    fail failfilt "expected the demangler's exit status to be reported:"
    cat failfilt.log
fi

# ----------------------------------------------------------------------
echo "*** 3. the counts are per site, not per line"
# ----------------------------------------------------------------------
$COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -o v.info v.gcda 2>&1 | tee v.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail v "geninfo failed:" `grep -E 'ERROR' v.log`
fi

# Every number here is what the program does.  Three of them cannot be produced
#   by an implementation which took the line's count ('g', and 'andor'
#   calling 'f', are 0 on lines whose counts are 5 and 1), and two of them
#   cannot be produced by one which paired the sites by column ('y' is 2 while
#   'sum2', which shares a column with 'w', is 3).
cat >v.expected <<'EOF'
andor|0|f
main|1|andor
main|1|three
main|3|outer
main|5|pick
outer|2|y
outer|3|sum2
outer|3|w
pick|0|g
pick|5|f
three|1|a
three|1|b
three|1|c
three|1|sum3
EOF
calls v.info | sort > v.actual
expect v v.actual v.expected

# ..and the line counts really are the misleading ones, i.e. the fixture is
#   testing what it claims to:  'pick' ran 5 times and 'andor' once, on the
#   lines whose sites are 0
for EXPECT in 'DA:11,5' 'DA:12,1' ; do
    if ! grep -q -F -x -e "$EXPECT" v.info ; then
        fail v_lines "expected '$EXPECT' - the fixture does not have the line" \
            "counts which make the zero site counts interesting:" \
            `grep -E '^DA:1[12],' v.info`
    fi
done


# The call sites of a line marked 'LCOV_EXCL_CALLGRAPH_LINE' are excluded by
#   default - 'callgraph_region' is one of the filters geninfo applies when it
#   is given none, as 'branch_region' is for branch coverage - and the line
#   itself stays.  The marker is appended to line 11 ('pick') of the source
#   the data was built from, so that no line moves, and the time stamp is kept
#   so that gcov does not see a changed source.  With a '--filter' of its own,
#   geninfo applies no default filter and the sites are back
cp -p v.c v.c.orig
sed -e '11s,$, // LCOV_EXCL_CALLGRAPH_LINE,' v.c.orig > v.c
touch -r v.c.orig v.c
$COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -o vmark.info v.gcda 2>&1 |
    tee vmark.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail vmark "geninfo failed:" `grep -E 'ERROR' vmark.log`
fi
grep -v -E '^pick\|' v.expected > vmark.expected
calls vmark.info | sort > vmark.actual
expect vmark vmark.actual vmark.expected
if ! grep -q -F -x -e 'DA:11,5' vmark.info ; then
    fail vmark "the marked line was excluded with its call sites:" \
        `grep -E '^DA:11,' vmark.info`
fi
$COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --filter region -o vnomark.info \
    v.gcda 2>&1 | tee vnomark.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail vnomark "geninfo failed:" `grep -E 'ERROR' vnomark.log`
fi
calls vnomark.info | sort > vnomark.actual
expect vnomark vnomark.actual v.expected
mv v.c.orig v.c

# ----------------------------------------------------------------------
echo "*** 4. the ordinal, where two sites share a location"
# ----------------------------------------------------------------------
# 'outer' has three sites on one line, two of which the compiler gave the same
#   column;  they are two sites and not one because the key carries an ordinal.
#   Asserted on the shape of the records at a location rather than on the
#   column itself, which is the compiler's to choose
OUTER=`sites v.info | grep '^outer|' | cut -d'|' -f2 | cut -d: -f2,3 | sort`
if [ 3 != `echo "$OUTER" | wc -l` ] ; then
    fail ordinal "expected three sites in 'outer', found:" `echo $OUTER`
else
    # the two which share a column carry ordinals 0 and 1, and the third - a
    #   different column - starts again at 0
    SHARED=`echo "$OUTER" | cut -d: -f1 | uniq -c | sort -rn | head -1 | \
            awk '{print $1}'`
    if [ 2 != "$SHARED" ] ; then
        fail ordinal "expected two of outer's sites to share a column:" \
            `echo $OUTER`
    fi
    if [ "`echo "$OUTER" | cut -d: -f2 | sort | tr -d '\n'`" != "001" ] ; then
        fail ordinal "expected ordinals 0,1 at the shared column and 0 at the" \
            "other:" `echo $OUTER`
    fi
fi

# 'three' is the same thing at four sites:  all four edges carry the enclosing
#   call's column, so the four ordinals are 0,1,2,3 at one location
THREE=`sites v.info | grep '^three|' | cut -d'|' -f2 | sort`
if [ 1 != `echo "$THREE" | cut -d: -f1,2 | sort -u | wc -l` ] ; then
    fail ordinal4 "expected three's four sites to share a location:" \
        `echo $THREE`
fi
if [ "`echo "$THREE" | cut -d: -f3 | sort | tr -d '\n'`" != "0123" ] ; then
    fail ordinal4 "expected ordinals 0,1,2,3 in 'three':" `echo $THREE`
fi

# ----------------------------------------------------------------------
echo "*** 5. the ordinal, where two aliases share a coverpoint"
# ----------------------------------------------------------------------
# An ordinal numbers the sites of a coverpoint and not of a symbol.  Two
#   instantiations of one template are two symbols defined at one line, which is
#   what makes them aliases of one function - one 'FNL:' index, and therefore one
#   site list.  If each numbered its own sites from zero, their first calls would
#   land on one key with two different callees, which is the 'mismatch' error -
#   and which any template instantiated with two argument types would produce,
#   lcov's own XS sources included.
# The compiler folds both instantiations' calls onto the same columns, which is
#   what makes the collision unavoidable rather than incidental:  'f(i)' has one
#   column in both bodies and 'shared(i)' another.  Both cases are here - the two
#   calls which differ in their callee, and the two which do not.
cat >tmpl.cpp <<'EOF'
struct A { int operator()(int x) const { return x + 1; } };
struct B { int operator()(int x) const { return x + 2; } };
int shared(int x) { return x * 2; }
template <typename F> int apply(F f, int n) { int t = 0; for (int i = 0; i < n; ++i) t += f(i) + shared(i); return t; }
int main() { return apply(A(), 2) + apply(B(), 3) > 0 ? 0 : 1; }
EOF

TMPL_OK=1
if ! build ${CXX} tmpl tmpl.cpp ; then
    fail build_tmpl "could not build or run the template fixture"
    TMPL_OK=0
fi

if [ 1 == $TMPL_OK ] ; then
    $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -o tmpl.info tmpl.gcda 2>&1 |
        tee tmpl.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail tmpl "geninfo failed:" `grep -E 'ERROR' tmpl.log`
    fi
    # ..and silently:  there is nothing inconsistent about the data, so a
    #   complaint of any kind is the bug this scenario is here for
    if grep -q -E '(ERROR|WARNING)' tmpl.log ; then
        fail tmpl "the aliases' call sites were reported as a conflict:" \
            `grep -E '(ERROR|WARNING)' tmpl.log`
    fi

    # Which name of the coverpoint the records are read back under is not the
    #   point and is the writer's to choose, so the caller field is normalized to
    #   the function both symbols are;  the counts are properties of the program,
    #   which runs 'apply<A>' over two elements and 'apply<B>' over three
    calls tmpl.info | sed -e 's/^_Z5applyI1.EiT_i|/apply|/' | sort > tmpl.actual
    cat >tmpl.expected <<'EOF'
apply|2|_ZNK1AclEi
apply|3|_ZNK1BclEi
apply|5|_Z6sharedi
main|1|_Z5applyI1AEiT_i
main|1|_Z5applyI1BEiT_i
EOF
    expect tmpl tmpl.actual tmpl.expected

    # ..and each call through the template parameter belongs to the
    #   instantiation which made it:  'apply<A>' calls 'A::operator()' and
    #   'apply<B>' calls 'B::operator()', while the call to 'shared' is made by
    #   both and so carries no attribution - it is reported under the first name
    sites tmpl.info | grep -E '\|_ZNK1[AB]clEi$|\|_Z6sharedi$' | \
        grep -v '^main|' | cut -d'|' -f1,4 | sort > tmpl_alias.actual
    cat >tmpl_alias.expected <<'EOF'
_Z5applyI1AEiT_i|_Z6sharedi
_Z5applyI1AEiT_i|_ZNK1AclEi
_Z5applyI1BEiT_i|_ZNK1BclEi
EOF
    expect tmpl_alias tmpl_alias.actual tmpl_alias.expected

    TMPL_SITES=`sites tmpl.info | sed -e 's/^_Z5applyI1.EiT_i|/apply|/' | \
                grep '^apply|'`
    # the two calls through the template parameter are at one location and are
    #   two sites, because the second alias' call took the next ordinal instead
    #   of starting over
    FUNCTOR=`echo "$TMPL_SITES" | grep -E '\|_ZNK1[AB]clEi$' | cut -d'|' -f2`
    if [ 1 != `echo "$FUNCTOR" | cut -d: -f1,2 | sort -u | wc -l` ] ; then
        fail tmpl_ordinal "expected the two instantiations of 'f(i)' at one" \
            "location:" `echo $FUNCTOR`
    fi
    if [ "`echo "$FUNCTOR" | cut -d: -f3 | sort | tr -d '\n'`" != "01" ] ; then
        fail tmpl_ordinal "expected ordinals 0 and 1 at that location:" \
            `echo $FUNCTOR`
    fi

    # ..while the call both of them make to the same function from the same place
    #   is one site whose count is the sum:  the two are one 'FNC:' record no
    #   matter what it is numbered, so nothing could tell them apart, and this is
    #   how an alias' counts are aggregated everywhere else
    SHARED=`echo "$TMPL_SITES" | grep -E '\|_Z6sharedi$'`
    if [ 1 != `echo "$SHARED" | wc -l` ] ; then
        fail tmpl_shared "expected one site calling 'shared':" `echo $SHARED`
    fi

    # ..which is a claim about the denominator too:  the merged site counts once,
    #   so the unit has five - three in 'apply' and two in 'main' - all taken
    if ! grep -q -E '^FNCF:5$' tmpl.info ||
       ! grep -q -E '^FNCH:5$' tmpl.info ; then
        fail tmpl_totals "expected five call sites, all executed:" \
            `grep -E '^FNC[FH]:' tmpl.info`
    fi
fi

# ----------------------------------------------------------------------
echo "*** 6. one call with two arcs:  the exception path"
# ----------------------------------------------------------------------
# A function with a local whose destructor is not trivial and a call which may
#   throw gets a cleanup path, and the destructor is called on both paths:  the
#   callgraph info lists the same edge twice at the same location, and gcov
#   counts the two arcs apart - the normal one with the calls the tests made, the
#   unwind one with zero.
# That is one call as written, so it is one call site:  the second arc folds into
#   the first and adds its count.  Two sites would say that half of a call the
#   tests always made was missed, and could not say which half - a location and a
#   callee is the finest thing a report can name a call by, which is exactly a
#   call as it is written.
# A location is a line *and* a column, so the fold takes nothing the report could
#   have shown apart.  Scenario 1 is the other half of that rule and still passes
#   unchanged:  'twice' calls one function twice on one line at two columns, and
#   those stay two sites with their own counts.
# The callee has to be defined in another translation unit or the compiler proves
#   it nothrow and emits no cleanup path at all, which is why this fixture is two
#   objects.
cat >eh.cpp <<'EOF'
struct A { int x; A(int v) : x(v) {} ~A(); };
A::~A() { }
int mayThrow(int);
int f(int n) { A a(n); return mayThrow(a.x) + 1; }
EOF
cat >ehmain.cpp <<'EOF'
int mayThrow(int v) { return v; }
int f(int);
int main() { return f(3) - 4; }
EOF

buildEh()
{
    # buildEh subdir [extra compiler flags]
    local d=$1
    shift
    mkdir -p $d || return 1
    cp eh.cpp ehmain.cpp $d/ || return 1
    ( cd $d &&
      echo "${CXX} --coverage -fcallgraph-info=su,da -O0 $* -c eh.cpp" &&
      ${CXX} --coverage -fcallgraph-info=su,da -O0 $* -c eh.cpp -o eh.o &&
      ${CXX} --coverage -fcallgraph-info=su,da -O0 $* -c ehmain.cpp -o m.o &&
      ${CXX} --coverage $* -o eh eh.o m.o &&
      [ -f eh.ci ] &&
      ./eh )
}

EH_OK=1
if ! buildEh eh ; then
    fail build_eh "could not build or run the exception-path fixture"
    EH_OK=0
elif [ 0 == `grep -E '^edge:' eh/eh.ci | sort | uniq -d | wc -l` ] ; then
    # Whether a given compiler needs a cleanup path here is its business:  with
    #   no duplicated edge there is nothing for this scenario to say, and the
    #   fold itself is still covered by the aliases above
    echo "'${CXX}' listed no edge twice - skipping the exception-path scenario"
    EH_OK=0
fi

if [ 1 == $EH_OK ] ; then
    $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -o eh.info eh/eh.gcda 2>&1 |
        tee eh.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail eh "geninfo failed:" `grep -E 'ERROR' eh.log`
    fi
    # ..and silently:  the two edges have two arcs, so the pairing agrees and
    #   there is nothing inconsistent to report
    if grep -q -E '(ERROR|WARNING)' eh.log ; then
        fail eh "the exception path was reported as a problem:" \
            `grep -E '(ERROR|WARNING)' eh.log`
    fi

    # 'f' runs once and makes three calls, the destructor among them:  one record
    #   for it, and its count is the call the tests made rather than the zero of
    #   the path they did not take
    cat >eh.expected <<'EOF'
_Z1fi|1|_Z8mayThrowi
_Z1fi|1|_ZN1AC1Ei
_Z1fi|1|_ZN1AD1Ev
EOF
    calls eh.info | sort > eh.actual
    expect eh eh.actual eh.expected

    # ..which is the fold stated in general:  no callee has two sites at one
    #   location, whatever the compiler listed
    DOUBLED=`sites eh.info | \
             awk -F'|' '{ split($2, l, ":")
                          print $1 "|" l[1] ":" l[2] "|" $4 }' | sort | uniq -d`
    if [ "x$DOUBLED" != "x" ] ; then
        fail eh_fold "a callee has two sites at one location:" `echo $DOUBLED`
    fi

    # ..and the denominator says the same:  three calls, all taken.  Counting the
    #   unwind arc apart would make it four with three taken, i.e. a report in
    #   which a destructor call every test makes is 50% missed
    if ! grep -q -E '^FNCF:3$' eh.info || ! grep -q -E '^FNCH:3$' eh.info ; then
        fail eh_totals "expected three call sites, all executed:" \
            `grep -E '^FNC[FH]:' eh.info`
    fi

    # The control:  '-fno-exceptions' is the same program without the cleanup
    #   path, so the compiler lists the edge once and gcov has one arc.  The two
    #   builds must measure the same calls - that equality is what "a call as
    #   written is the coverpoint" means, and it is the one assertion here which
    #   does not depend on knowing what the duplicate arc is for
    if ! buildEh ne -fno-exceptions ; then
        fail build_ne "could not build the '-fno-exceptions' control"
    else
        $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -o ne.info ne/eh.gcda 2>&1 |
            tee ne.log
        if [ 0 != ${PIPESTATUS[0]} ] ; then
            fail ne "geninfo failed on the control:" `grep -E 'ERROR' ne.log`
        fi
        calls ne.info | sort > ne.actual
        expect ne ne.actual eh.expected
        if ! diff -u <(grep -E '^FNC[FH]:' eh.info) \
                     <(grep -E '^FNC[FH]:' ne.info) > ne_totals.diff ; then
            fail ne_totals "the two builds do not measure the same calls:"
            cat ne_totals.diff
        fi
    fi
fi

# ----------------------------------------------------------------------
echo "*** 7. a round trip"
# ----------------------------------------------------------------------
# Everything above is about what geninfo wrote;  this is that what it wrote can
#   be read back, which is what makes the ordinals part of a merge key rather
#   than a detail of one file
$COVER $LCOV_TOOL $LCOV_OPTS --callgraph -a v.info -o v_rt.info 2>&1 | tee rt.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail roundtrip "lcov failed:" `grep -E 'ERROR' rt.log`
fi
noDeduced roundtrip v.info
if ! diff <(grep -v -E '^TN:' v.info) \
          <(stripDeduced v_rt.info | grep -v -E '^TN:') > rt.diff ; then
    fail roundtrip "the data changed on a read/write round trip:"
    cat rt.diff
fi
# ..and the merge did deduce the caller of 'main', which nothing in the program
#   calls and which was entered anyway
if ! grep -q -E '^FNA:[0-9]+ed,1,main$' v_rt.info ; then
    fail roundtrip "the merge did not deduce the caller of 'main':" \
        `grep -E '^FNA:.*,main$' v_rt.info`
fi

# ----------------------------------------------------------------------
echo "*** 8. an initial capture"
# ----------------------------------------------------------------------
# A baseline is captured from the '.gcno' alone, and the callgraph info sits
#   beside that, so the sites are all there with count 0 - which is the right
#   answer for a baseline and is what lets a differential report categorize a
#   site as never having been called
$COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --initial -o base.info v.gcno 2>&1 |
    tee base.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail initial "geninfo --initial failed:" `grep -E 'ERROR' base.log`
fi
sites base.info | cut -d'|' -f1,2 | sort > base.actual
sites v.info | cut -d'|' -f1,2 | sort > base.expected
expect initial base.actual base.expected
if [ "`sites base.info | cut -d'|' -f3 | sort -u | tr -d '\n'`" != "0" ] ; then
    fail initial "a baseline capture reports calls as executed:"
    sites base.info
fi
if ! grep -q -E '^FNCH:0$' base.info ; then
    fail initial "expected 'FNCH:0' in a baseline capture:" \
        `grep -E '^FNC[FH]:' base.info`
fi

# ----------------------------------------------------------------------
echo "*** 9. 'lcov --capture' asks its geninfo child for the metric"
# ----------------------------------------------------------------------
# 'lcov --capture' does not read '.gcda' itself:  it builds a geninfo command
#   line and runs it.  The cover type flags are part of that command line and
#   have to be passed on, or the capture collects no call data no matter what the
#   user asked lcov for - and says nothing, because a capture with no call sites
#   in it is exactly what 'empty.sh' documents as an ordinary outcome.  So the
#   assertion is that the capture holds the same call data as the direct geninfo
#   run above, not merely that it succeeded
$COVER $LCOV_TOOL $LCOV_OPTS --callgraph --capture v.gcda -o cap.info 2>&1 |
    tee cap.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail capture "lcov --capture failed:" `grep -E 'ERROR' cap.log`
fi
calls cap.info | sort > cap.actual
calls v.info | sort > cap.expected
expect capture cap.actual cap.expected

# ..and the flag is passed because it was asked for, not always:  a capture
#   without it has no call records at all
$COVER $LCOV_TOOL $LCOV_OPTS --capture v.gcda -o nocap.info 2>&1 | tee nocap.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail nocapture "lcov --capture failed:" `grep -E 'ERROR' nocap.log`
fi
if grep -q -E '^FNC' nocap.info ; then
    fail nocapture "a capture which did not ask for call data collected some:"
    grep -E '^FNC' nocap.info
fi

# ----------------------------------------------------------------------
echo "*** 10. linkage, and the cross-file call it is there to resolve"
# ----------------------------------------------------------------------
# A call site names its callee by symbol, so a name which more than one file
#   defines cannot be resolved from the calling file alone - an unrelated
#   'static' of the same name in a third file must not void a perfectly good call
#   to the global.  The callgraph info knows the difference and gcov does not:  a
#   node title is file-qualified exactly when the symbol has no external linkage,
#   which is what geninfo records as the 'e' flag of the symbol's 'FNA:' record.
# Three units which disagree about what 'f' means, compiled separately because
#   that disagreement is the fixture:  'gdef.c' defines the global, 'call.c'
#   calls it and defines no 'f' of its own, and 'sdef.c' has a static 'f' which
#   has nothing to do with either and is called only from its own file.
mkdir link
cat >link/gdef.c <<'EOF'
int f(int x)
{
    return x + 1;
}
EOF
cat >link/call.c <<'EOF'
extern int f(int);

int g(int n)
{
    return f(n);
}
EOF
cat >link/sdef.c <<'EOF'
static int f(int x)
{
    return x - 1;
}

int h(int n)
{
    return f(n);
}
EOF
cat >link/main.c <<'EOF'
extern int g(int);
extern int h(int);

int main(void)
{
    int t = 0;
    for (int i = 0; i < 3; ++i)
        t += g(i);
    t += h(1);
    return t == 0;
}
EOF

LINK_OK=1
for UNIT in gdef call sdef main ; do
    echo "${CC} --coverage -fcallgraph-info=su,da -O0 -c $UNIT.c -o $UNIT.o"
    if ! ( cd link &&
           ${CC} --coverage -fcallgraph-info=su,da -O0 -c $UNIT.c -o $UNIT.o ) ||
       [ ! -f link/$UNIT.ci ] ; then
        fail build_link "${CC} wrote no 'link/$UNIT.ci' beside the '.gcno'"
        LINK_OK=0
        break
    fi
done
if [ 1 == $LINK_OK ] &&
   ! ( cd link && ${CC} --coverage -o prog gdef.o call.o sdef.o main.o &&
       ./prog ) ; then
    fail build_link "could not build or run the multi-unit fixture"
    LINK_OK=0
fi

# One line per recorded linkage assertion, as <file>|<name>.  The alias name is
#   the record's own last field, so no index has to be resolved to read it
externals()
{
    awk '
        /^SF:/ { file = substr($0, 4); sub(/^.*\//, "", file); next }
        /^FNA:[0-9]+[a-z]*e/ {
            s = substr($0, 5)
            sub(/^[^,]*,[^,]*,/, "", s)
            printf "%s|%s\n", file, s
        }' $1 | sort
}

if [ 1 == $LINK_OK ] ; then
    $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -o link.info link 2>&1 | tee link.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail link "geninfo failed:" `grep -E 'ERROR' link.log`
    fi

    # The static is the whole point of the list:  every other function of the
    #   fixture is external and is recorded so, and 'sdef.c's 'f' is not - which
    #   is a fact about the symbol that nothing else in the capture carries.
    #   'call.c' declares 'f' without defining it, and says nothing about it
    #   here, because a linkage record belongs to a function of the file
    cat >link.expected <<'EOF'
call.c|g
gdef.c|f
main.c|main
sdef.c|h
EOF
    externals link.info > link.actual
    expect link link.actual link.expected

    # ..and this is what it buys:  the call in 'call.c' resolves, silently, to
    #   the global - two files define 'f', the calling file defines neither, and
    #   exactly one of the two can be called from outside its own file
    $COVER $LCOV_TOOL $LCOV_OPTS --callgraph -a link.info -o link_rt.info 2>&1 |
        tee link_rt.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail link_resolve "lcov failed:" `grep -E 'ERROR' link_rt.log`
    fi
    if grep -q -E '(ERROR|WARNING)' link_rt.log ; then
        fail link_resolve "the cross-file call did not resolve:" \
            `grep -E '(ERROR|WARNING)' link_rt.log`
    fi
    externals link_rt.info > link_rt.actual
    expect link_roundtrip link_rt.actual link.expected

    # ..which is a claim about the records and not about the fixture:  without
    #   them the same data cannot tell the two definitions apart
    sed -e 's/^\(FNA:[0-9]\+\)[a-z]\+,/\1,/' link.info > link_nolink.info
    $COVER $LCOV_TOOL $LCOV_OPTS --callgraph -a link_nolink.info \
        -o link_nolink_out.info 2>&1 | tee link_nolink.log
    if ! grep -q -F -e "call to 'f' cannot be resolved" link_nolink.log ; then
        fail link_nolink "expected the call to be ambiguous without linkage:" \
            `grep -E '(ERROR|WARNING)' link_nolink.log`
    fi

    # ..and the resolution reaches the report:  the caller of the global 'f' is
    #   a function in another file, and the static 'f' - whose only caller is in
    #   its own file - did not acquire it
    $COVER $GENHTML_TOOL $LCOV_OPTS --callgraph -o link_html link.info 2>&1 |
        tee link_html.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail link_html "genhtml failed:" `grep -E 'ERROR' link_html.log`
    fi
    GDEF=`find link_html -name 'gdef.c.callers.html'`
    SDEF=`find link_html -name 'sdef.c.callers.html'`
    if [ ! -f "$GDEF" ] || [ ! -f "$SDEF" ] ; then
        fail link_html "the call site views were not written"
    else
        if ! grep -q -F -e 'call.c.callees.html' $GDEF ; then
            fail link_html "the global 'f' does not list its caller in call.c:"
            grep -F -e 'id="func_f"' -A 6 $GDEF
        fi
        if grep -q -F -e 'call.c.callees.html' $SDEF ; then
            fail link_html "the static 'f' acquired a caller from another file:"
            grep -F -e 'call.c.callees.html' $SDEF
        fi
    fi
fi

# ----------------------------------------------------------------------
echo "*** 11. calls gcov cannot count:  a 'pure' or 'const' callee"
# ----------------------------------------------------------------------
# A function declared 'pure' or 'const' has none of the effects a call is made
#   for, so the compiler gives the call no arc and gcov reports nothing for it -
#   while the callgraph info lists the edge like any other.  glibc declares
#   'atoi', 'strlen', 'strcmp' and 'abs' that way, so any ordinary C program has
#   such edges, and counting one as a call site trips the 'inconsistent' error
#   with advice ('rebuild at -O0') that cannot help because the build is already
#   at -O0.
# There is no call to count, so such an edge is not a call site:  geninfo reads
#   the declaration the callgraph info points at and drops it.  Both halves are
#   asserted - the capture is silent, and what it kept is the calls which really
#   are countable.
mkdir pure
cat >pure/p.c <<'EOF'
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

__attribute__((pure)) int defpure(int x)
{
    return x + 2;
}

/* file-local, so the callgraph info spells its node title 'p.c:spure' - the
   qualified form, which is the one where the symbol has to be separated from the
   qualification *after* the declaration's location has been read out of the same
   line */
static __attribute__((const)) int spure(int x)
{
    return x * 3;
}

int plain(const char *s)
{
    return (int)s[0];
}

int main(int argc, char *argv[])
{
    int t = 0;
    t += (int)strlen(argv[0]);
    t += atoi("7");
    t += defpure(argc);
    t += spure(argc);
    t += plain("z");
    printf("%d\n", t);
    return t == 0;
}
EOF

PURE_OK=1
if ! ( cd pure && ${CC} --coverage -fcallgraph-info=su,da -O0 p.c -o p &&
       ./p ) > pure_build.log 2>&1 || [ ! -f pure/p.ci ] ; then
    fail build_pure "could not build or run the 'pure' fixture"
    cat pure_build.log
    PURE_OK=0
fi

if [ 1 == $PURE_OK ] ; then
    $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -v -o pure.info pure 2>&1 |
        tee pure.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail pure "geninfo failed:" `grep -E 'ERROR' pure.log`
    fi
    # The whole point:  no complaint of any kind.  A call which cannot be
    #   counted is not a call site, so the two sequences never disagreed
    if grep -q -E '(ERROR|WARNING)' pure.log ; then
        fail pure "a call to a 'pure' function was reported as a mismatch:" \
            `grep -E '(ERROR|WARNING)' pure.log`
    fi

    # ..and what is left is the calls gcov does count.  'defpure' carries the
    #   attribute on its definition, which is where the callgraph info points, so
    #   a function of the unit itself is dropped on the same evidence as 'strlen';
    #   'spure' is the same case with a file-local symbol, whose node title the
    #   callgraph info qualifies with the file name
    cat >pure.expected <<'EOF'
main|1|plain
main|1|printf
EOF
    calls pure.info | sort > pure.actual
    expect pure pure.actual pure.expected

    # ..which is a claim about the denominator too:  an uncountable call left in
    #   'found' would put a ceiling on the metric that no test could lift
    if ! grep -q -E '^FNCF:2$' pure.info || ! grep -q -E '^FNCH:2$' pure.info ; then
        fail pure_totals "the dropped sites are still in the totals:" \
            `grep -E '^FNC[FH]:' pure.info`
    fi

    # ..and it is said, at verbosity, rather than done silently
    if ! grep -q -F -e "declared 'pure' or 'const'" pure.log ; then
        fail pure_said "the dropped call sites were not reported:" \
            `grep -F -e 'callgraph-coverage' pure.log`
    fi
    # ..naming them, up to the three that 'some_locations' prints before it
    #   elides the rest - so the count is what pins the fourth ('strlen', last in
    #   the sorted order, is the one elided here)
    for WHO in atoi defpure spure ; do
        if ! grep -F -e "declared 'pure' or 'const'" pure.log |
             grep -q -F -e "$WHO" ; then
            fail pure_said "'$WHO' is not named among the dropped callees:" \
                `grep -F -e "declared 'pure' or 'const'" pure.log`
        fi
    done
    if ! grep -F -e "declared 'pure' or 'const'" pure.log |
         grep -q -F -e "dropped 4 call site(s) to 4 function(s)" ; then
        fail pure_said "not all four uncountable calls were dropped:" \
            `grep -F -e "declared 'pure' or 'const'" pure.log`
    fi

    # ..and a declaration file which cannot be read is not an error:  the
    #   answer is "no attribute", so 'defpure' and 'spure' - whose source is
    #   gone - read as the mismatch the 'hdr' case below does
    cp -r pure nosrc && rm -f nosrc/p.c
    $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --debug --debug \
        -o nosrc.info --ignore-errors inconsistent,source nosrc 2>&1 |
        tee nosrc.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail nosrc "geninfo failed:" `grep -E 'ERROR' nosrc.log`
    fi
    if ! grep -q -F -e "cannot read declaration file" nosrc.log ; then
        fail nosrc "the unreadable declaration file was not reported"
    fi
    if ! grep -q -F -e "The call(s) with no arc go to: defpure, spure" \
            nosrc.log ; then
        fail nosrc "the calls to an unread declaration were dropped:" \
            `grep -E '(ERROR|WARNING)' nosrc.log`
    fi
fi

# The residual case, which is a limitation and not a fix:  the attribute is on a
#   prototype in a header, and the definition - which is where the callgraph info
#   points for a function of this unit - does not repeat it.  There is nothing to
#   read, so the call still reads as a mismatch;  what this asserts is that the
#   message now says which callee it was and what else can cause it, instead of
#   advising a rebuild at an optimization level the build already used.
mkdir hdr
cat >hdr/q.h <<'EOF'
int hdrpure(int x) __attribute__((pure));
EOF
cat >hdr/q.c <<'EOF'
#include "q.h"

int hdrpure(int x)
{
    return x + 1;
}

int main(void)
{
    return hdrpure(1) == 2 ? 0 : 1;
}
EOF
HDR_OK=1
if ! ( cd hdr && ${CC} --coverage -fcallgraph-info=su,da -O0 q.c -o q &&
       ./q ) > hdr_build.log 2>&1 || [ ! -f hdr/q.ci ] ; then
    fail build_hdr "could not build or run the 'hdr' fixture"
    cat hdr_build.log
    HDR_OK=0
fi

if [ 1 == $HDR_OK ] ; then
    $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -o hdr.info \
        --ignore-errors inconsistent hdr 2>&1 | tee hdr.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail hdr "geninfo failed:" `grep -E 'ERROR' hdr.log`
    fi
    if ! grep -q -F -e "declared 'pure' or 'const' has no arc either" hdr.log ; then
        fail hdr "the message does not offer the reason that applies:" \
            `grep -E '(ERROR|WARNING)' hdr.log`
    fi
    if ! grep -q -F -e "The call(s) with no arc go to: hdrpure" hdr.log ; then
        fail hdr "the message does not say which callee had no arc:" \
            `grep -E '(ERROR|WARNING)' hdr.log`
    fi
fi

# ----------------------------------------------------------------------
echo "*** 12. the source view, at the columns the compiler really gave"
# ----------------------------------------------------------------------
# The source view wraps a link around the callee's name at each site's column.
#   Which column that is depends on the front end:  GCC's C++ one points a call
#   at its opening parenthesis and its C one at the name, so the name is either
#   at the column or ends just left of it.  Both fixtures above are real
#   captures, which makes this the assertion that the view looks where the
#   compiler actually pointed - with hand written columns it cannot be.
# What a site whose column no name is at looks like is 'format.sh' section 12;
#   here every site has one, so the trailing comment must not be used at all.
decorations()
{
    # every call-site link a source page wraps around the source itself, in
    #   page order - written in perl because more than one of them is on a line
    perl -ne 'while (/(<a class="callSite[A-Za-z ]*"[^>]*>[^<]*<\/a>)/g) {
                  print "$1\n";
              }' $1
}

expectDecorations()
{
    # expectDecorations label actual-file expected-file
    local label=$1
    if ! diff -u $3 $2 > $label.diff ; then
        fail $label "the source view does not point at the calls:"
        cat $label.diff
    fi
}

# The fixture's call to 'printf' is the one site here whose callee no file of the
#   report defines, so it leaves the report and the source view does not decorate
#   it:  a real capture of the case 'format3.sh' section 16 pins on a hand written
#   fixture.  Every other column below is one the capture measured
$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph -o csd_html csd.info 2>&1 |
    tee csd_html.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail csd_html "genhtml failed:" `grep -E 'ERROR' csd_html.log`
fi
CSPAGE=`find csd_html -name 'cs.cpp.gcov.html'`
if [ ! -f "$CSPAGE" ] ; then
    fail csd_html "no source page was written"
else
    decorations $CSPAGE > csd_html.actual
    # 'freefn' twice on line 7, told apart only by column;  the call spread over
    #   three lines, whose parenthesis is the last character of line 4;  and a
    #   member call, whose name is not the first thing in the expression
    cat >csd_html.expected <<'EOF'
<a class="callSite" href="cs.cpp.callees.html#site_4_32" data-calls="1: freefn(int, int)">freefn</a>
<a class="callSite" href="cs.cpp.callees.html#site_6_18" data-calls="1: S::m(double)">m</a>
<a class="callSite" href="cs.cpp.callees.html#site_7_33" data-calls="1: freefn(int, int)">freefn</a>
<a class="callSite" href="cs.cpp.callees.html#site_7_48" data-calls="1: freefn(int, int)">freefn</a>
<a class="callSiteLo" href="cs.cpp.callees.html#site_8_38" data-calls="0: S::m(double)">m</a>
<a class="callSite" href="cs.cpp.callees.html#site_9_39" data-calls="1: multi(S&amp;)">multi</a>
<a class="callSite" href="cs.cpp.callees.html#site_9_50" data-calls="1: twice(int)">twice</a>
EOF
    expectDecorations csd_html csd_html.actual csd_html.expected
    if grep -q -F -e 'callgraphAnnot' $CSPAGE ; then
        fail csd_html "a call the source names went to the trailing comment:"
        grep -o -F -e 'callgraphAnnot' $CSPAGE | wc -l
    fi
    # ..and the name of the callee which left the report is nowhere on the page:
    #   there is nothing for a link on it to lead to
    if grep -q -F -e '>printf<' $CSPAGE ; then
        fail csd_html "the call which left the report is still decorated:"
        grep -F -e 'printf' $CSPAGE
    fi
fi

# ..and the C case, where the column is the name itself.  Two of these are
#   groups:  GCC folded the column of a nested call onto the enclosing one, so
#   the link leads to more than one callee and says how many
$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph -o v_html v.info 2>&1 | tee v_html.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail v_html "genhtml failed:" `grep -E 'ERROR' v_html.log`
fi
VPAGE=`find v_html -name 'v.c.gcov.html'`
if [ ! -f "$VPAGE" ] ; then
    fail v_html "no source page was written"
else
    decorations $VPAGE > v_html.actual
    cat >v_html.expected <<'EOF'
<a class="callSite" href="v.c.callees.html#site_10_27" data-calls="3: sum2&#10;3: w">sum2</a>
<a class="callSite" href="v.c.callees.html#site_10_36" data-calls="2: y">y</a>
<a class="callSite" href="v.c.callees.html#site_11_32" data-calls="5: f">f</a>
<a class="callSiteLo" href="v.c.callees.html#site_11_38" data-calls="0: g">g</a>
<a class="callSiteLo" href="v.c.callees.html#site_12_34" data-calls="0: f">f</a>
<a class="callSite" href="v.c.callees.html#site_13_26" data-calls="1: a&#10;1: b&#10;1: c&#10;1: sum3">sum3</a>
<a class="callSite" href="v.c.callees.html#site_14_62" data-calls="3: outer">outer</a>
<a class="callSite" href="v.c.callees.html#site_14_105" data-calls="5: pick">pick</a>
<a class="callSite" href="v.c.callees.html#site_14_119" data-calls="1: andor">andor</a>
<a class="callSite" href="v.c.callees.html#site_14_134" data-calls="1: three">three</a>
EOF
    expectDecorations v_html v_html.actual v_html.expected
    if grep -q -F -e 'callgraphAnnot' $VPAGE ; then
        fail v_html "a call the source names went to the trailing comment:"
        grep -o -F -e 'callgraphAnnot' $VPAGE | wc -l
    fi
    COUNT=`grep -o -F -e 'class="calleeMulti"' $VPAGE | wc -l`
    if [ 2 != "$COUNT" ] ; then
        fail v_html "expected 2 folded columns to be marked, got $COUNT"
    fi
fi

# ----------------------------------------------------------------------
echo "*** 13. a call written in a file other than the caller's own"
# ----------------------------------------------------------------------
# The body of a function is built out of the text of whichever file that text was
#   written in, and the callgraph info says which file each edge is in.  An
#   '#include'd fragment is the plain case of the two files differing, and is the
#   one used here because it is the case a test can write down:  the calls of
#   'g' are all in 'body.inc', while 'g' itself is defined in 'm.c'.
# Such a call is the program's own:  its count is gcov's, and the function it
#   changes the count of is 'g' - so it belongs to 'm.c's section, naming the file
#   it is written in.  That is what the 'SF:' index and the '@' of an 'FNC:' record
#   are for; 'format.sh' pins their syntax, and this asserts that a real capture
#   produces them.
# The callees are in a third file, so the same fixture is also a cross-file call
#   whose caller's file and whose site's file are both different from the callee's
mkdir frag
cat >frag/helper.c <<'EOF'
int f(int x)
{
    return x + 1;
}
int h(int x)
{
    return x * 2;
}
EOF
cat >frag/body.inc <<'EOF'
    int a = f(x);
    int b = h(x);
    return a + b;
EOF
cat >frag/m.c <<'EOF'
extern int f(int);
extern int h(int);
static int g(int x)
{
#include "body.inc"
}
int main(void)
{
    return g(3) == 10 ? 0 : 1;
}
EOF

# One line per call site as <caller>|<file it is written in>|<callee>, with the
#   file as its basename:  the columns and the emission order belong to the
#   compiler, and the file is the point here.  Two passes over the same input,
#   because a section may name an index which a later section defines - see
#   'format.sh'
fragsites()
{
    awk '
        FNR == NR {
            if (/^SF:[0-9]+,/) {
                s = substr($0, 4)
                i = index(s, ","); idx = substr(s, 1, i - 1); s = substr(s, i + 1)
                sub(/^.*\//, "", s)
                indexed[idx] = s
            }
            next
        }
        # a function index is a property of one section, so forget the names the
        #   last section gave:  this fixture has a function 0 in each of two files
        /^SF:/ { file = substr($0, 4); sub(/^[0-9]+,/, "", file)
                 sub(/^.*\//, "", file); delete name; next }
        /^FNA:/ {
            s = substr($0, 5)
            i = index(s, ","); idx = substr(s, 1, i - 1); s = substr(s, i + 1)
            sub(/[^0-9].*$/, "", idx)
            i = index(s, ",")
            if (!(idx in name)) name[idx] = substr(s, i + 1)
            next
        }
        /^FNC:/ {
            s = substr($0, 5)
            i = index(s, ","); lead = substr(s, 1, i - 1); s = substr(s, i + 1)
            where = file
            i = index(lead, "@")
            if (i > 0) {
                where = indexed[substr(lead, i + 1)]
                lead = substr(lead, 1, i - 1)
            }
            n = 0
            while (n < 4) { i = index(s, ","); ++n; s = substr(s, i + 1) }
            printf "%s|%s|%s\n", name[lead], where, s
        }' $1 $1 | sort
}

# ..and what each section counts, which is the other half of the decision:  a
#   site is counted by the file its caller is defined in, whatever file it is
#   written in, because that is the only thing a per-file total can mean
fragtotals()
{
    awk '
        /^SF:/ { file = substr($0, 4); sub(/^[0-9]+,/, "", file)
                 sub(/^.*\//, "", file); next }
        /^FNC[FH]:/ { printf "%s|%s\n", file, $0 }' $1
}

if ! ( cd frag &&
       ${CC} --coverage -fcallgraph-info=su,da -O0 m.c helper.c -o m &&
       ./m ) ; then
    fail build_frag "could not build or run the '#include'd body fixture"
else
    $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -o frag.info frag 2>&1 |
        tee frag.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail frag "geninfo failed:" `grep -E 'ERROR' frag.log`
    fi
    if grep -q -E '(ERROR|WARNING)' frag.log ; then
        fail frag "the capture was not silent:" \
            `grep -E '(ERROR|WARNING)' frag.log`
    fi

    fragsites frag.info > frag.actual
    cat >frag.expected <<'EOF'
g|body.inc|f
g|body.inc|h
main|m.c|g
EOF
    expect frag frag.actual frag.expected

    # 'm.c' holds every site, including the two written in the fragment;  the
    #   fragment's own section holds none, and neither does the file the callees
    #   are defined in
    fragtotals frag.info > fragtotals.actual
    cat >fragtotals.expected <<'EOF'
body.inc|FNCF:0
body.inc|FNCH:0
helper.c|FNCF:0
helper.c|FNCH:0
m.c|FNCF:3
m.c|FNCH:3
EOF
    expect fragtotals fragtotals.actual fragtotals.expected

    # ..and the records survive a merge unchanged, which is the reader and the
    #   writer agreeing about a file the capture numbered
    $COVER $LCOV_TOOL $LCOV_OPTS --callgraph -a frag.info -o frag_rt.info 2>&1 |
        tee frag_rt.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail frag_rt "lcov failed:" `grep -E 'ERROR' frag_rt.log`
    fi
    if grep -q -E '(ERROR|WARNING)' frag_rt.log ; then
        fail frag_rt "the cross-file calls did not resolve:" \
            `grep -E '(ERROR|WARNING)' frag_rt.log`
    fi
    noDeduced frag_rt frag.info
    if [ -f frag_rt.info ] &&
       ! diff -u frag.info <(stripDeduced frag_rt.info) ; then
        fail frag_rt "the capture does not round trip"
    fi

    # ..and the report shows the call where the reader can see it:  in the source
    #   view of the fragment, linking to the table on the page of the file whose
    #   function makes the call.  The anchor carries the fragment's path, so it is
    #   matched rather than spelled out
    $COVER $GENHTML_TOOL $LCOV_OPTS --callgraph -o frag_html frag.info 2>&1 |
        tee frag_html.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail frag_html "genhtml failed:" `grep -E 'ERROR' frag_html.log`
    fi
    FRAGSRC=`find frag_html -name 'body.inc.gcov.html'`
    FRAGCALLEE=`find frag_html -name 'helper.c.callers.html'`
    if [ ! -f "$FRAGSRC" ] || [ ! -f "$FRAGCALLEE" ] ; then
        fail frag_html "the pages of the fragment fixture were not written"
    else
        COUNT=`decorations $FRAGSRC |
               grep -c -E 'href="[^"]*m\.c\.callees\.html#site_[^"]*body_inc'`
        if [ 2 != "$COUNT" ] ; then
            fail frag_html \
                "expected both calls in the fragment to link to m.c, got $COUNT"
            decorations $FRAGSRC
        fi
        # ..and the callee's page names the file the call is written in, not the
        #   file its caller is defined in
        if ! grep -q -E 'body\.inc:[0-9]+:[0-9]+' $FRAGCALLEE ; then
            fail frag_html "the callers of 'f' do not name the fragment:"
            grep -F -e 'id="func_f"' -A 8 $FRAGCALLEE
        fi
    fi

    # ..and a capture which excludes the fragment cannot write the calls in it:
    #   the record names that file by index, and only its 'SF:' record could
    #   define one.  'geninfo' writes its result without resolving it, so the
    #   writer itself drops the sites and records the calls on the callees, as
    #   the 'x' flag - see TraceFile::_pruneUnwritableSites
    $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph -o fragx.info frag \
        --exclude '*body.inc' 2>&1 | tee fragx.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail fragx "geninfo failed:" `grep -E 'ERROR' fragx.log`
    fi
    if grep -q -E '^(SF:[0-9]+,|FNC:[0-9]+@)' fragx.info ; then
        fail fragx "a site in the excluded fragment was written:" \
            `grep -E '^(SF|FNC):' fragx.info`
    fi
    for callee in f h ; do
        if ! grep -q -E "^FNA:[0-9]+[a-z]*x1,1,$callee\$" fragx.info ; then
            fail fragx "the call to '$callee' was not recorded on the callee:" \
                `grep -E '^FNA:' fragx.info`
        fi
    done
fi

# ----------------------------------------------------------------------
echo "*** 14. one fragment '#include'd into two function bodies"
# ----------------------------------------------------------------------
# The shape of an inline function in a system header, in miniature:  the line of
#   'body.inc' is in the body of both 'g1' and 'g2', gcov reports it once per
#   function with no caller, and both callers number the call's block alike - so
#   the line holds two entries for one block and has two owners.  A real header
#   line had 31260 entries over 214 blocks and 7056 owners, and pairing every
#   entry with every owner was nearly all of the capture's time;  the capture
#   now pairs each block once.  What this pins is that each caller still gets
#   its own site at the fragment's line.
# Whether gcov also reports the arc under the '#include' line of 'm.c' is its
#   business:  where it does not, the arc has no owner and this is
#   'unsupported.sh' scenario 9, so probe first
mkdir frag2
cat >frag2/helper.c <<'EOF'
int f(int x)
{
    return x + 1;
}
EOF
cat >frag2/body.inc <<'EOF'
    return f(x);
EOF
cat >frag2/m.c <<'EOF'
extern int f(int);
static int g1(int x)
{
#include "body.inc"
}
static int g2(int x)
{
#include "body.inc"
}
int main(void)
{
    return g1(3) + g2(4) == 9 ? 0 : 1;
}
EOF

if ! ( cd frag2 &&
       ${CC} --coverage -fcallgraph-info=su,da -O0 m.c helper.c -o m &&
       ./m ) ; then
    fail build_frag2 "could not build or run the twice '#include'd fixture"
else
    $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --callgraph-partial-data \
        --ignore-errors inconsistent -o frag2.info frag2 2>&1 | tee frag2.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail frag2 "geninfo failed:" `grep -E 'ERROR' frag2.log`
    fi
    if grep -q -F -e '(inconsistent)' frag2.log ; then
        echo "gcov '${GCOV}' does not attribute the fragment's call to a line" \
             "of the including file - skipping the shared fragment scenario"
    else
        if grep -q -E '(ERROR|WARNING)' frag2.log ; then
            fail frag2 "the capture was not silent:" \
                `grep -E '(ERROR|WARNING)' frag2.log`
        fi
        fragsites frag2.info > frag2.actual
        cat >frag2.expected <<'EOF'
g1|body.inc|f
g2|body.inc|f
main|m.c|g1
main|m.c|g2
EOF
        expect frag2 frag2.actual frag2.expected

        fragtotals frag2.info > frag2totals.actual
        cat >frag2totals.expected <<'EOF'
body.inc|FNCF:0
body.inc|FNCH:0
helper.c|FNCF:0
helper.c|FNCH:0
m.c|FNCF:4
m.c|FNCH:4
EOF
        expect frag2totals frag2totals.actual frag2totals.expected
    fi
fi

# ----------------------------------------------------------------------
echo "*** 15. one object tree run in several copies"
# ----------------------------------------------------------------------
# A build which runs its tests in copies of the object tree, each with its own
#   '.gcda' next to a hard link of the one '.gcno' and '.ci', has geninfo read
#   the same '.ci' once per copy.  The parse is kept for the rest of the capture
#   and the second copy reuses it - which must make no difference to what is
#   captured:  the two copies captured in one run are the two captured apart and
#   merged.  Serially, so that the second copy starts after the first has
#   stored its parse
mkdir shard shard/obj shard/a shard/b
cat >shard/s.c <<'EOF'
int f(int x)
{
    return x + 1;
}
int main(int argc, char **argv)
{
    return f(argc) == 2 ? 0 : 1;
}
EOF
if ! ( cd shard &&
       ${CC} --coverage -fcallgraph-info=su,da -O0 -c `pwd`/s.c -o obj/s.o &&
       ${CC} --coverage obj/s.o -o obj/s &&
       cd obj && ./s && cp s.gcda ../a && ./s && cp s.gcda ../b &&
       for d in a b ; do ln s.gcno s.ci ../$d || exit 1 ; done ) ; then
    fail build_shard "could not build or run the copied object tree fixture"
else
    for d in a b ; do
        $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --parallel 1 \
            -o shard_$d.info shard/$d 2>&1 | tee shard_$d.log
        if [ 0 != ${PIPESTATUS[0]} ] ; then
            fail shard_$d "geninfo failed:" `grep -E 'ERROR' shard_$d.log`
        fi
    done
    $COVER $LCOV_TOOL $LCOV_OPTS --callgraph -o shard_sum.info \
        -a shard_a.info -a shard_b.info 2>&1 | tee shard_sum.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail shard_sum "lcov failed:" `grep -E 'ERROR' shard_sum.log`
    fi

    $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --parallel 1 -v \
        -o shard.info shard/a shard/b 2>&1 | tee shard.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail shard "geninfo failed:" `grep -E 'ERROR' shard.log`
    fi
    if grep -q -E '(ERROR|WARNING)' shard.log ; then
        fail shard "the capture was not silent:" \
            `grep -E '(ERROR|WARNING)' shard.log`
    fi
    for what in keeping reusing ; do
        COUNT=`grep -c -F -e "--callgraph-coverage: $what the parse of" shard.log`
        if [ 1 != "$COUNT" ] ; then
            fail shard "expected the parse to be $what once, got $COUNT"
        fi
    done
    noDeduced shard shard.info
    if [ -f shard.info ] &&
       ! diff -u <(stripDeduced shard_sum.info) shard.info ; then
        fail shard "the copies captured together differ from the copies merged"
    fi
    # ..and the two copies did count differently, or the comparison says little
    if diff -q shard_a.info shard_b.info > /dev/null ; then
        fail shard "the two copies of the fixture have the same counts"
    fi

    # ..and a parse which cannot be stored is not worth failing the capture
    #   over:  the second copy parses again.  Nothing outside the process can
    #   make a fresh temporary directory unwritable, so the store is made to
    #   fail from inside it - by a module which is not itself to be covered
    mkdir -p nostore_lib
    cat >nostore_lib/NoStore.pm <<'EOF'
package NoStore;
use Storable ();
no warnings 'redefine';
my $store = \&Storable::store;
*Storable::store = sub {
    die("no space left\n") if $_[1] =~ m{/callgraph/};
    goto &$store;
};
1;
EOF
    PERL5OPT="-I`pwd`/nostore_lib -MNoStore" \
        DEVEL_COVER_OPTIONS="-ignore,NoStore" \
        $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --parallel 1 -v \
        -o nostore.info shard/a shard/b 2>&1 | tee nostore.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail nostore "geninfo failed:" `grep -E 'ERROR' nostore.log`
    fi
    if grep -q -F -e "--callgraph-coverage: keeping the parse of" nostore.log ||
       grep -q -F -e "--callgraph-coverage: reusing the parse of" nostore.log
    then
        fail nostore "a parse which could not be stored was kept"
    fi
    if [ -f shard.info ] && ! diff -u shard.info nostore.info ; then
        fail nostore "the capture differs when the parse cannot be kept"
    fi
fi

# ----------------------------------------------------------------------
echo "*** 16. a source named with '..' and '.' in it"
# ----------------------------------------------------------------------
# The callgraph info spells the file as the command line did;  gcov collapses
#   'dir/..' when it can see 'dir'.  The two spellings are one file, and the
#   call pairs - once for an absolute name, which also starts with '/..', and
#   once for a relative name, which starts with a '..' nothing collapses and
#   has an empty and a '.' component as well
for d in abs rel ; do
    mkdir -p dots_$d/obj
    cp shard/s.c dots_$d
done
if ! ( cd dots_abs/obj &&
       ${CC} --coverage -fcallgraph-info=su,da -O0 -c /..`pwd`/../s.c -o s.o &&
       ${CC} --coverage s.o -o s && ./s &&
       cd ../../dots_rel/obj &&
       ${CC} --coverage -fcallgraph-info=su,da -O0 -c ../obj/..//./s.c -o s.o &&
       ${CC} --coverage s.o -o s && ./s ) ; then
    fail build_dots "could not build or run the '..' fixture"
else
    for d in abs rel ; do
        $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --parallel 1 \
            -o dots_$d.info dots_$d/obj 2>&1 | tee dots_$d.log
        if [ 0 != ${PIPESTATUS[0]} ] ; then
            fail dots_$d "geninfo failed:" `grep -E 'ERROR' dots_$d.log`
        fi
        if grep -q -E '(ERROR|WARNING)' dots_$d.log ; then
            fail dots_$d "the capture was not silent:" \
                `grep -E '(ERROR|WARNING)' dots_$d.log`
        fi
        sites dots_$d.info > dots_$d.actual
        echo 'main|7:12:0|1|f' > dots_$d.expected
        expect dots_$d dots_$d.actual dots_$d.expected
    done
fi

# ----------------------------------------------------------------------
echo "*** 17. a constructor's complete-object symbol, which gcov does not describe"
# ----------------------------------------------------------------------
# A constructor is two symbols, the complete-object 'C1' and the base-object
#   'C2' (and a destructor 'D1' and 'D2').  gcov describes only the 'C2' body.
#   gcc 16 gives 'C1' a callgraph node of its own, with one edge to 'C2';  an
#   older compiler has no such edge, so it is added here as gcc 16 writes it.
#   'C1' is a caller gcov said nothing about, so it has no sites.  It is also
#   the callee 'main' calls, which is why '--demangle-cpp' has a name for it -
#   and that name is not a description:  the capture is silent, and the sites
#   are the ones a capture of the same program without '--demangle-cpp' has
mkdir -p ctor
cat >ctor/ctor.cpp <<'EOF'
struct S {
    S();
    ~S();
    int v;
};
int g(int x);
S::S() : v(g(1)) {}
S::~S() { g(2); }
int g(int x) { return x + 1; }
int main()
{
    S s;
    return s.v - 2;
}
EOF
if ! ( cd ctor && build ${CXX} ctor ctor.cpp ) ; then
    fail build_ctor "could not build or run the constructor fixture"
else
    for sym in C D ; do
        if ! grep -q "sourcename: \"_ZN1S${sym}1Ev\"" ctor/ctor.ci ; then
            line=7
            [ $sym == D ] && line=8
            echo "edge: { sourcename: \"_ZN1S${sym}1Ev\" targetname: \"_ZN1S${sym}2Ev\" label: \"ctor.cpp:$line:1\" }" >> ctor/ctor.ci
        fi
    done
    for mode in strict partial ; do
        opts=
        if [ $mode == partial ] ; then
            opts="--callgraph-partial-data --ignore-errors inconsistent"
        fi
        $COVER $GENINFO_TOOL $LCOV_OPTS --callgraph --demangle-cpp $opts \
            -o ctor_$mode.info ctor 2>&1 | tee ctor_$mode.log
        if [ 0 != ${PIPESTATUS[0]} ] ; then
            fail ctor_$mode "geninfo failed:" `grep -E 'ERROR' ctor_$mode.log`
        fi
        if grep -q -E '(ERROR|WARNING)' ctor_$mode.log ; then
            fail ctor_$mode "the capture was not silent:" \
                `grep -E '(ERROR|WARNING)' ctor_$mode.log`
        fi
        sites ctor_$mode.info > ctor_$mode.actual
        cat >ctor_$mode.expected <<'EOF'
S::S()|7:13:0|1|g(int)
S::~S()|8:12:0|1|g(int)
main|12:7:0|1|S::S()
main|14:1:0|1|S::~S()
EOF
        expect ctor_$mode ctor_$mode.actual ctor_$mode.expected
    done
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'geninfo' $LOCAL_COVERAGE 0
fi

exit $STATUS
