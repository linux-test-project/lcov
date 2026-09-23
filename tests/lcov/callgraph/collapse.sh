#! /usr/bin/env bash

# The 'collapse_callgraph_alias' setting:  merging the aliases of a function
#   which the callgraph cannot tell apart.
#
# Each instantiation of a template is an alias of one FunctionEntry, and call
#   site attribution (see 'attribution.sh') keeps the calls each one made apart.
#   Where two aliases made the same calls - from the same places, to the same
#   functions - and were called from the same places, the report has nothing to
#   say about one which it does not say about the other, and the setting folds
#   them into one:  the shortest name - a lambda counting as longer than any
#   other - then the first in sort order, with the sum of the counts.  A file
#   nothing in the report says anything about the calls of is left alone:
#   there, aliases are alike because nothing was measured.  The name kept remembers each name merged into it with
#   that name's own count, so no function coverage is lost, and the setting is
#   on unless the configuration turns it off.
#
# Everything here is a hand-written '.info' over a checked-in source, so it
#   needs no compiler.

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf collapse.d
    exit 0
fi

WORKDIR=collapse.d
source ./setup_common.sh

checkFunctionRecords()
{
    # checkFunctionRecords label file <<expected
    #   the function and call records of a '.info', against stdin
    local label=$1
    local file=$2
    if [ ! -f $file ] ; then
        fail $label "$file was not written"
        cat > /dev/null
        return
    fi
    cat > $label.expect
    grep -E '^(SF|FNA|FNM|FNC)' $file > $label.actual
    if ! diff -u $label.expect $label.actual ; then
        fail $label "unexpected function records in $file"
    fi
}

shown()
{
    # the pages '$@' without the tooltips of the merged-name marks:  the names
    #   they list are in the page, and are not where a name is shown
    perl -pe 's{<span class="mergedNamesList">.*?</sup>}{</sup>}g' "$@"
}

checkLog()
{
    # checkLog label log message...
    #   each message has to be in the log
    local label=$1
    local log=$2
    shift 2
    local message
    for message in "$@" ; do
        if ! grep -q -F -e "$message" $log ; then
            fail $label "expected '$message' in $log"
        fi
    done
}

# Every name in 'c.h' is a template with two instantiations, each pair made to
#   be merged or not for one reason:
#     f  calls 'g' from one place, and is called by 'k' from one place:  merged
#     k  is called from two places in 'main':  not merged - and the calls it
#        made to the two 'f's fold into one, once those are one
#     h  calls nothing and nothing calls it:  merged
#     m  one has external linkage ('e') and the other not:  not merged
#     n  one has callers outside the callgraph ('x') and the other not:  not
#        merged
#     p  both have 'x':  merged, with the sum
#     q  calls 's', which is ambiguous (two files define a file-local 's'):  a
#        call nobody can resolve is still the same call, so merged;  'w' calls
#        'q' from another file, and its two calls fold
#     r  calls 'v' and calls 'g' from the same place:  not merged
#     z  one name is also defined elsewhere:  left alone
cat >proj/c.h <<'EOF'
int g(int x) { return x; }
template <class T> int f(T x) { return g(x); }
template <class T> int k(T x) { return f(x); }
int main() { return k(1) + k('a'); }
template <class T> int h(T x) { return x; }
template <class T> int m(T x) { return x; }
template <class T> int n(T x) { return x; }
template <class T> int p(T x) { return x; }
template <class T> int q(T x) { return s(x); }
template <class T> int r(T x) { return sizeof(T) == 1 ? v(x) : g(x); }
template <class T> int z(T x) { return x; }
int v(int x) { return x; }
EOF
cat >proj/u.c <<'EOF'
#include "c.h"
template <class T> int w(T x) { return q(x); }
int use() { return w(1) + w('a'); }
EOF
printf 'static int s(int x) { return x; }\nint z_a() { return 0; }\n' \
    > proj/a1.c
cp proj/a1.c proj/a2.c

cat >c.info <<'EOF'
TN:
SF:proj/c.h
FNL:0,1,1
FNA:0,3,g
FNL:1,2,2
FNA:1,1,f<char>
FNA:1,1,f<int>
FNC:1,2,40,0,2,g
FNL:2,3,3
FNA:2,1,k<char>
FNA:2,1,k<int>
FNC:2#0,3,40,0,1,f<char>
FNC:2#1,3,40,1,1,f<int>
FNL:3,4,4
FNA:3,1,main
FNC:3,4,21,0,1,k<int>
FNC:3,4,28,0,1,k<char>
FNL:4,5,5
FNA:4,0,h<int>
FNA:4,0,h<long>
FNL:5,6,6
FNA:5e,1,m<char>
FNA:5,1,m<int>
FNL:6,7,7
FNA:6x2,2,n<char>
FNA:6,0,n<int>
FNL:7,8,8
FNA:7x1,1,p<a>
FNA:7x2,2,p<b>
FNL:8,9,9
FNA:8,1,q<char>
FNA:8,1,q<int>
FNC:8,9,40,0,2,s
FNL:9,10,10
FNA:9,1,r<char>
FNA:9,1,r<int>
FNC:9#0,10,40,0,1,v
FNC:9#1,10,40,1,1,g
FNL:10,11,11
FNA:10,1,z<a>
FNA:10,1,z<b>
FNL:11,12,12
FNA:11,1,v
FNF:12
FNH:11
FNCF:8
FNCH:8
DA:1,1
DA:2,1
DA:3,1
DA:4,1
DA:5,0
DA:6,1
DA:7,1
DA:8,1
DA:9,1
DA:10,1
DA:11,1
DA:12,1
LF:12
LH:11
end_of_record
TN:
SF:proj/u.c
FNL:0,2,2
FNA:0,1,w<char>
FNA:0,1,w<int>
FNC:0#0,2,40,0,1,q<char>
FNC:0#1,2,40,1,1,q<int>
FNL:1,3,3
FNA:1,1,use
FNC:1,3,20,0,1,w<int>
FNC:1,3,27,0,1,w<char>
FNF:2
FNH:2
FNCF:4
FNCH:4
DA:2,1
DA:3,1
LF:2
LH:2
end_of_record
EOF
for f in a1 a2 ; do
    cat >>c.info <<EOF
TN:
SF:proj/$f.c
FNL:0,1,1
FNA:0,1,s
FNL:1,2,2
FNA:1,1,z<a>
FNF:2
FNH:2
FNCF:0
FNCH:0
DA:1,1
DA:2,1
LF:2
LH:2
end_of_record
EOF
done

# the call to 's' cannot be resolved, whether or not the aliases are merged
AMBIGUOUS="call to 's' cannot be resolved"
# ..and the aliases are kept apart where this says so
APART='--rc collapse_callgraph_alias=0'

# ----------------------------------------------------------------------
echo "*** 1. what the callgraph cannot tell apart is merged"
# ----------------------------------------------------------------------
runWarn plain "$AMBIGUOUS" --callgraph $APART -a c.info -o plain.info
if [ -f plain.info ] && ( ! grep -q -x -F 'FNA:4,0,h<long>' plain.info ||
                              grep -q '^FNM:' plain.info ) ; then
    fail plain "with the setting off, the aliases were merged"
fi

runWarn collapse "$AMBIGUOUS" --callgraph -v -a c.info -o collapse.info
checkFunctionRecords collapse collapse.info <<'EOF'
SF:proj/a1.c
FNA:0d,1,s
FNA:1d,1,z<a>
FNCF:0
FNCH:0
SF:proj/a2.c
FNA:0d,1,s
FNA:1d,1,z<a>
FNCF:0
FNCH:0
SF:proj/c.h
FNA:0,3,g
FNA:1,2,f<int>
FNM:1#0,1,f<char>
FNC:1,2,40,0,2,g
FNA:2,1,k<char>
FNA:2,1,k<int>
FNC:2,3,40,1,2,f<int>
FNA:3d,1,main
FNC:3,4,21,0,1,k<int>
FNC:3,4,28,0,1,k<char>
FNA:4,0,h<int>
FNM:4#0,0,h<long>
FNA:5ed,1,m<char>
FNA:5d,1,m<int>
FNA:6x2,2,n<char>
FNA:6,0,n<int>
FNA:7x3,3,p<a>
FNM:7#0,2,p<b>
FNA:8,2,q<int>
FNM:8#0,1,q<char>
FNC:8,9,40,0,2,s
FNA:9d,1,r<char>
FNA:9d,1,r<int>
FNC:9#0,10,40,0,1,v
FNC:9#1,10,40,1,1,g
FNA:10d,1,z<a>
FNA:10d,1,z<b>
FNA:11,1,v
FNCF:7
FNCH:7
SF:proj/u.c
FNA:0,1,w<char>
FNA:0,1,w<int>
FNC:0,2,40,1,2,q<int>
FNA:1d,1,use
FNC:1,3,20,0,1,w<int>
FNC:1,3,27,0,1,w<char>
FNCF:3
FNCH:3
EOF
# ..and says, at verbosity 1, what it merged and why it did not
checkLog collapse collapse.log \
    "merged 'f<char>' into 'f<int>'" "merged 'h<long>' into 'h<int>'" \
    "merged 'p<b>' into 'p<a>'" "merged 'q<char>' into 'q<int>'" \
    "not merging 'm<char>', 'm<int>':  they differ in the 'e' flag" \
    "not merging 'n<char>', 'n<int>':  they differ in the 'x' flag" \
    "1 group(s) of aliases not merged only because their 'e' flags differ, 1 only because their 'x' flags differ"
if grep -q -E "merged '(k|r|z)<" collapse.log ; then
    fail collapse "merged aliases which the callgraph tells apart"
fi

# ..the same on a merge done across a fork
LCOV_FORCE_PARALLEL=1 runWarn collapse_par "$AMBIGUOUS" --callgraph \
    --parallel 0 -a c.info -o collapse_par.info
if [ -f collapse_par.info ] && ! diff -u collapse.info collapse_par.info ; then
    fail collapse_par "a parallel merge collapsed differently"
fi

# ----------------------------------------------------------------------
echo "*** 2. the setting, from a configuration file and without a callgraph"
# ----------------------------------------------------------------------
echo 'collapse_callgraph_alias = 0' > apart.rc
runWarn rc "$AMBIGUOUS" --config-file apart.rc --callgraph \
    -a c.info -o rc.info
if [ -f rc.info ] && ! diff -u plain.info rc.info ; then
    fail rc "'collapse_callgraph_alias = 0' in a configuration file merged"
fi
# ..and with no callgraph there is nothing to merge by, and nothing to say
runLcov nocg -a c.info -o nocg.info
runLcov nocg_apart $APART -a c.info -o nocg_apart.info
if [ -f nocg.info ] && [ -f nocg_apart.info ] &&
       ! diff -u nocg_apart.info nocg.info ; then
    fail nocg "aliases were merged without callgraph coverage"
fi
# ..while names merged already are still written:  they are what a name stands
#   for, which a report of functions alone shows too
runLcov fnm_nocg -a collapse.info -o fnm_nocg.info
if [ -f fnm_nocg.info ] && ! grep -q -x -F 'FNM:1#0,1,f<char>' fnm_nocg.info
then
    fail fnm_nocg "the merged names were not written without a callgraph"
fi

# ----------------------------------------------------------------------
echo "*** 3. every testcase is merged as the summary is"
# ----------------------------------------------------------------------
sed -e 's/^TN:$/TN:one/' c.info > one.info
sed -e 's/^TN:$/TN:two/' c.info > two.info
runWarn tests "$AMBIGUOUS" --callgraph -a one.info -a two.info -o tests.info
# each testcase has what one input has, so its records are those above - and
#   the 'd' flag, which is a property of the summary, is on each of them
if [ -f tests.info ] ; then
    for t in one two ; do
        awk -v T="TN:$t" '/^TN:/ { keep = ($0 == T) } keep' tests.info |
            sed -e "s/^TN:$t\$/TN:/" -e 's/^FNA:\([0-9]*[ex]*[0-9]*\)d*,[0-9]*,/FNA:\1,/' \
                > $t.records
        sed -e 's/^FNA:\([0-9]*[ex]*[0-9]*\)d*,[0-9]*,/FNA:\1,/' collapse.info \
            > collapse.records
        if ! diff -u <(grep -E '^(SF|FNA|FNM|FNC)' collapse.records) \
                     <(grep -E '^(SF|FNA|FNM|FNC)' $t.records) ; then
            fail tests "testcase '$t' was not merged as the summary was"
        fi
    done
fi
LCOV_FORCE_PARALLEL=1 runWarn tests_par "$AMBIGUOUS" --callgraph \
    --parallel 0 -a one.info -a two.info -o tests_par.info
if [ -f tests_par.info ] && ! diff -u tests.info tests_par.info ; then
    fail tests_par "a parallel merge collapsed the testcases differently"
fi

# ----------------------------------------------------------------------
echo "*** 4. genhtml merges the baseline and the current data each on its own"
# ----------------------------------------------------------------------
# In the baseline 'f<char>' has an 'x' flag, so there it is not merged;  in the
#   current data it is.  The baseline then takes the names the current data
#   kept, so its 'f<char>' is compared with the current 'f<int>':  no page
#   shows 'f<char>' other than in the tooltip of the name it was merged into
sed -e 's/^FNA:1,1,f<char>$/FNA:1x1,1,f<char>/' c.info > base.info
$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph \
    --ignore-errors inconsistent --baseline-file base.info \
    -o html c.info 2>&1 | tee html.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail html "genhtml failed:" `grep -E 'ERROR' html.log`
else
    if shown html/proj/c.h.func.html | grep -q -F 'f&lt;char&gt;' ; then
        fail html "the baseline's 'f<char>' was not compared with 'f<int>'"
    fi
    if ! grep -q -F '<span class="mergedNamesName">f&lt;char&gt;</span>' \
            html/proj/c.h.func.html ; then
        fail html "'f<int>' does not say that it stands for 'f<char>'"
    fi
    if shown html/proj/*.callers.html html/proj/*.callees.html |
            grep -q -F '>f&lt;char&gt;' ; then
        fail html "the current 'f<char>' was not merged"
    fi
fi

# ----------------------------------------------------------------------
echo "*** 5. '--filter function' shows the callers of a function as one list"
# ----------------------------------------------------------------------
# With the aliases kept apart in the data, the page lists the function under
#   one name, and so lists its callers
#   once:  no caption per alias, one row - and one call site of its rate - for
#   the location which called both 'f's, and one row for the calls from outside the report which each 'p' and
#   each 'm' received
callerRows()
{
    # the cells of a caller page, '|'-separated, one function to a line
    sed -n '/Callee/,$p' $1 |
        sed -e 's/<[^>]*>/ /g' -e 's/&nbsp;/ /g' -e 's/&lt;/</g' \
            -e 's/&gt;/>/g' -e 's/  */ /g' -e 's/^ //' -e 's/ $//' |
        grep -v '^$' | tr '\n' '|' | sed -e 's/100.0 % (/\n&/g'
    echo
}
for f in plain function ; do
    filter=
    [ $f == function ] && filter='--filter function'
    $COVER $GENHTML_TOOL $LCOV_OPTS --callgraph $APART $filter \
        --ignore-errors inconsistent -o html_$f c.info 2>&1 | tee html_$f.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail html_$f "genhtml failed:" `grep -E 'ERROR' html_$f.log`
    fi
    callerRows html_$f/proj/c.h.callers.html > html_$f.rows
done
# ..where without it each alias has a list of its own
checkLog html_plain html_plain.rows \
    '|Callers of alias f<char>|k<int>|c.h:3:40|1|Callers of alias f<int>|k<int>|c.h:3:40|1|' \
    '|Callers of alias p<a>|<external callers>|1|Callers of alias p<b>|<external callers>|2|'
checkLog html_function html_function.rows \
    '(1 / 1)|k<int>|c.h:3:40|2|g|' \
    '(2 / 2)|main|c.h:4:21|1|main|c.h:4:28|1|m<int> external callers only|-|<deduced external callers>|(2)|' \
    'n<int> external callers only|-|<external callers>|2|' \
    'p<a> external callers only|-|<external callers>|3|' \
    '(1 / 1)|w<int>|u.c:2:40|2|'
if grep -q 'Callers of alias' html_function.rows ; then
    fail html_function "'--filter function' listed the callers of an alias"
fi

# ----------------------------------------------------------------------
echo "*** 6. the name kept remembers the names merged into it"
# ----------------------------------------------------------------------
fRecords()
{
    # the 'FNA:'/'FNM:' records of function index 1 of 'c.h':  the 'f's
    awk '/^SF:/ { keep = ($0 == "SF:proj/c.h") } keep' $1 |
        grep -E '^FN[AM]:1([a-z][0-9]*)*[#,]'
}
checkF()
{
    # checkF label file expected:  those records, '|'-terminated, are 'expected'
    local actual=`fRecords $2 | tr '\n' '|'`
    if [ "$actual" != "$3" ] ; then
        fail $1 "expected '$3' in $2 but got '$actual'"
    fi
}
# ..which round trip..
runWarn fnm_round "$AMBIGUOUS" --callgraph -a collapse.info -o fnm_round.info
if [ -f fnm_round.info ] && ! diff -u collapse.info fnm_round.info ; then
    fail fnm_round "the merged names do not round trip"
fi
# ..and, merged with the data they were merged from, are one name each:  the
#   name is merged again, and its count is the sum of its counts..
runWarn fnm_again "$AMBIGUOUS" --callgraph -a collapse.info -a c.info \
    -o fnm_again.info
checkF fnm_again fnm_again.info \
    'FNA:1,4,f<int>|FNM:1#0,2,f<char>|'
# ..while with the aliases kept apart both names are there, and the position
#   of the one which is kept is its position among the 'FNA:' records written
#   - so whether or not the data crossed a fork
runWarn fnm_union "$AMBIGUOUS" --callgraph $APART -a collapse.info -a c.info \
    -o fnm_union.info
checkF fnm_union fnm_union.info \
    'FNA:1,1,f<char>|FNA:1,3,f<int>|FNM:1#1,1,f<char>|'
LCOV_FORCE_PARALLEL=1 runWarn fnm_union_par "$AMBIGUOUS" --callgraph $APART \
    --parallel 0 -a collapse.info -a c.info -o fnm_union_par.info
if [ -f fnm_union_par.info ] && ! diff -u fnm_union.info fnm_union_par.info ; then
    fail fnm_union_par "a parallel merge lost the merged names"
fi
# ..and an intersection keeps them on the alias which survives it
runWarn fnm_intersect "$AMBIGUOUS" --callgraph collapse.info \
    --intersect c.info -o fnm_intersect.info
checkF fnm_intersect fnm_intersect.info \
    'FNA:1,3,f<int>|FNM:1#0,1,f<char>|'

# A name merged into a name which is merged in turn goes with it, with its own
#   count - so the one it was merged into brings what is left of its count -
#   and the name kept is never one of its own merged names
sed -e 's/^FNA:1,1,f<char>$/&\nFNM:1#0,1,f<short>\nFNM:1#0,0,f<int>/' c.info \
    > chain.info
runWarn fnm_chain "$AMBIGUOUS" --callgraph -a chain.info -o fnm_chain.info
checkF fnm_chain fnm_chain.info \
    'FNA:1,2,f<int>|FNM:1#0,0,f<char>|FNM:1#0,1,f<short>|'

# The count of a merged name is a count as any other is:  normalized as it is
#   read..
sed -e 's/^FNA:1,1,f<char>$/&\nFNM:1#0,1.5,f<short>/' c.info > fraction.info
runWarn fnm_fraction "$AMBIGUOUS" --callgraph $APART -a fraction.info \
    -o fnm_fraction.info
checkF fnm_fraction fnm_fraction.info \
    'FNA:1,1,f<char>|FNM:1#0,1,f<short>|FNA:1,1,f<int>|'
# ..and one which is not a number is a format error
sed -e 's/^FNA:1,1,f<char>$/&\nFNM:1#0,many,f<short>/' c.info > badcount.info
checkFail fnm_badcount "function 'f<short>'" --callgraph -a badcount.info \
    -o fnm_badcount.info

# A merged name for an alias which has not been read yet is a format error -
#   whether the position is one the index has later, or the index is unknown
FNM_EARLY='found before that alias is defined'
for bad in '1#1,1,f<long>' '42#0,1,f<long>' ; do
    sed -e "s/^FNA:1,1,f<char>\$/FNM:$bad\n&/" c.info > early.info
    checkFail fnm_early "$FNM_EARLY" --callgraph -a early.info \
        -o fnm_early.info
done
# ..which, ignored, drops the record
runWarn fnm_early_ign "$FNM_EARLY" --callgraph --ignore-errors format \
    -a early.info -o fnm_early_ign.info
if [ -f fnm_early_ign.info ] && grep -q "^FNM:.*,f<long>\$" fnm_early_ign.info ; then
    fail fnm_early_ign "a merged name with no alias was kept"
fi

# A call to a merged name is a call to the name kept - here from a file which
#   uses the instantiation without defining it, read after the merge was done.
#   The site is renamed, so it is one call to 'f<int>' and not a call out of
#   the report, with the setting on or off
cat >proj/x.c <<'EOF'
#include "c.h"
extern template int f<char>(char);
int ext() { return f('a'); }
EOF
cat >x.info <<'EOF'
TN:
SF:proj/x.c
FNL:0,3,3
FNA:0,1,ext
FNC:0,3,20,0,1,f<char>
FNF:1
FNH:1
FNCF:1
FNCH:1
DA:3,1
LF:1
LH:1
end_of_record
EOF
for mode in on off ; do
    opt=''
    [ $mode == off ] && opt=$APART
    runWarn fnm_call_$mode "$AMBIGUOUS" --callgraph $opt -a collapse.info \
        -a x.info -o fnm_call_$mode.info
    if [ -f fnm_call_$mode.info ] &&
        ! grep -q -x -F 'FNC:0,3,20,0,1,f<int>' fnm_call_$mode.info ; then
        fail fnm_call_$mode "the call to a merged name was not a call to the name kept"
    fi
done
# ..and a renamed call keeps the line of the statement it is part of
sed -e 's/^FNC:0,3,/FNC:0^2,3,/' x.info > x_statement.info
runWarn fnm_call_statement "$AMBIGUOUS" --callgraph -a collapse.info \
    -a x_statement.info -o fnm_call_statement.info
if [ -f fnm_call_statement.info ] &&
    ! grep -q -x -F 'FNC:0^2,3,20,0,1,f<int>' fnm_call_statement.info ; then
    fail fnm_call_statement "the renamed call lost its statement line"
fi
# ..unless some file defines the name itself:  a definition is what a call
#   resolves to, and a merged name is only remembered
sed -e 's,proj/x.c,proj/y.c,' -e 's/^FNA:0,1,ext$/FNA:0,1,f<char>/' \
    -e '/^FNC/d' -e 's/^FNCF:1/FNCF:0/' -e 's/^FNCH:1/FNCH:0/' x.info > y.info
cp proj/x.c proj/y.c
runWarn fnm_shadow "$AMBIGUOUS" --callgraph -a collapse.info -a x.info \
    -a y.info -o fnm_shadow.info
if [ -f fnm_shadow.info ] &&
    ! grep -q -x -F 'FNC:0,3,20,0,1,f<char>' fnm_shadow.info ; then
    fail fnm_shadow "a call to a defined name went to a merged one"
fi

# Two versions which keep different names:  'c3.info' has an instantiation
#   'f<ab>' which 'c.info' has not, and which is shorter than 'f<int>' - so the
#   one merges into 'f<int>' and the other into 'f<ab>'.  Merged, the two are
#   one name, with every count..
sed -e 's/^FNA:1,1,f<int>$/&\nFNA:1,1,f<ab>/' \
    -e 's/^FNA:2,1,k<int>$/&\nFNA:2,1,k<ab>/' \
    -e 's/^FNC:2#1,3,40,1,1,f<int>$/&\nFNC:2#2,3,40,2,1,f<ab>/' c.info > c3.info
runWarn winners_c3 "$AMBIGUOUS" --callgraph -a c3.info -o c3_collapse.info
checkF winners_c3 c3_collapse.info \
    'FNA:1,3,f<ab>|FNM:1#0,1,f<char>|FNM:1#0,1,f<int>|'
for order in 'collapse.info c3_collapse.info' 'c3_collapse.info collapse.info'
do
    set -- $order
    runWarn winners_merge "$AMBIGUOUS" --callgraph -a $1 -a $2 \
        -o winners_merge.info
    checkF winners_merge winners_merge.info \
        'FNA:1,5,f<ab>|FNM:1#0,2,f<char>|FNM:1#0,2,f<int>|'
done
# ..and, the one the baseline of the other, the function is one function in
#   both, shown by the name the current version keeps - with a callgraph or
#   without one
fnTla()
{
    # the category of the row of function '$2' of the page '$1'
    grep -A1 -F ">$2</a>" $1 | grep -o 'tla[A-Z]*' | head -1
}
checkWinners()
{
    # checkWinners label baseline current name-kept name-not-kept genhtml-opts
    local label=$1
    local base=$2
    local current=$3
    local name=`echo "$4" | sed -e 's/</\&lt;/g' -e 's/>/\&gt;/g'`
    local gone=`echo "$5" | sed -e 's/</\&lt;/g' -e 's/>/\&gt;/g'`
    shift 5
    $COVER $GENHTML_TOOL $LCOV_OPTS "$@" --ignore-errors inconsistent \
        --baseline-file $base -o html_$label $current > $label.log 2>&1
    if [ 0 != $? ] ; then
        fail $label "genhtml failed:" `grep -E 'ERROR' $label.log`
        return
    fi
    local page=html_$label/proj/c.h.func.html
    if [ "`fnTla $page $name`" != tlaCBC ] ; then
        fail $label "'$name' was not compared with its baseline"
    fi
    if grep -q -F ">$gone</a>" $page ; then
        fail $label "the baseline's '$gone' is a function of its own"
    fi
}
checkWinners winners_html collapse.info c3_collapse.info 'f<ab>' 'f<int>' \
    --callgraph
# ..where the call from 'k' to it is the same call in both:  the one new call is
#   that of the new instantiation 'k<ab>'.  'main' calls two of the aliases of
#   'k', so they are three groups, and a call every alias makes is listed
#   under each of them - with its anchor only once, on the row of the summary
#   above them which is that one unique site:  four rows, each with its count
CALLEES=html_winners_html/proj/c.h.callees.html
if [ -f $CALLEES ] ; then
    if [ `grep -c 'tlaGIC">' $CALLEES` != 4 ] ; then
        fail winners_html "the call from 'k' was not matched with its baseline"
    fi
    if [ "`grep -o 'id="group_k_[a-z]*_"' $CALLEES | tr '\n' ' '`" != \
        'id="group_k_ab_" id="group_k_char_" id="group_k_int_" ' ] ; then
        fail winners_html "expected the three groups of 'k'"
    fi
    if [ 1 != `grep -c 'id="site_3_40_1"' $CALLEES` ] ; then
        fail winners_html "expected the anchor of the call from 'k' once"
    fi
fi
checkWinners winners_rev c3_collapse.info collapse.info 'f<int>' 'f<ab>' \
    --callgraph
checkWinners winners_nocg c3_collapse.info collapse.info 'f<int>' 'f<ab>'
# ..and a baseline of several testcases, each of which is renamed
sed -e 's/^TN:.*/TN:t1/' collapse.info > collapse_tn.info
sed -e 's/^TN:.*/TN:t2/' collapse.info >> collapse_tn.info
checkWinners winners_tn collapse_tn.info c3_collapse.info 'f<ab>' 'f<int>'     --callgraph

# Many instantiations of one template, in two testcases:  half of them call 'g'
#   and half call 'v' from one place, and every one calls 'shared'.  They merge
#   into two names, each standing for the rest of its half, and the call they
#   all make is one call.  Nothing calls them, so each has the deduced-caller
#   flag
N=150
awk -v n=$N 'BEGIN {
    for (t = 1; t <= 2; ++t) {
        print "TN:t" t; print "SF:proj/many.h"
        print "FNL:0,1,1"; print "FNA:0,1,g"
        print "FNL:1,2,4"
        for (i = 0; i < n; ++i) print "FNA:1,1,t<a" i ">"
        for (i = 0; i < n; ++i) print "FNA:1,1,t<b" i ">"
        a = "0"; for (i = 1; i < n; ++i) a = a "." i
        b = n; for (i = n + 1; i < 2 * n; ++i) b = b "." i
        print "FNC:1#" a ",3,10,0," n ",g"
        print "FNC:1#" b ",3,10,1," n ",v"
        print "FNC:1,4,10,0," 2 * n ",shared"
        print "FNL:2,5,5"; print "FNA:2,1,v"
        print "FNL:3,6,6"; print "FNA:3,1,shared"
        print "FNF:4"; print "FNH:4"; print "FNCF:3"; print "FNCH:3"
        print "DA:1,1"; print "DA:3,1"; print "DA:5,1"; print "DA:6,1"
        print "LF:4"; print "LH:4"
        print "end_of_record"
    }
}' > many.info
printf 'int g(int);\ntemplate <class T> int t(T x)\n{\n  return x ? g(x) : v(x);\n  shared(x);\n}\nint v(int);\nint shared(int);\n' \
    > proj/many.h
runLcov many --callgraph -a many.info -o many.info.out
manyRecords()
{
    # the function index 1 records of one testcase section of the output
    awk -v tn="TN:$1" '/^TN:/ { keep = ($0 == tn) } keep' many.info.out |
        grep -E '^FN[AMC]:1[a-z0-9]*[#,]'
}
for tn in t1 t2 ; do
    actual=`manyRecords $tn | grep -v '^FNM:' | tr '\n' '|'`
    expect="FNA:1d,$N,t<a0>|FNA:1d,$N,t<b0>|FNC:1#0,3,10,0,$N,g|FNC:1#1,3,10,1,$N,v|FNC:1,4,10,0,$((2 * N)),shared|"
    if [ "$actual" != "$expect" ] ; then
        fail many_$tn "expected '$expect' but got '$actual'"
    fi
    if [ `manyRecords $tn | grep -c -E '^FNM:1#0,1,t<a[0-9]+>$'` != $((N - 1)) ] ||
        [ `manyRecords $tn | grep -c -E '^FNM:1#1,1,t<b[0-9]+>$'` != $((N - 1)) ] ; then
        fail many_$tn "each name kept does not stand for the rest of its half"
    fi
done

# Two templates whose instantiations call each other:  'k<a>' calls 'm<a>' and
#   'm<a>' calls 'k<a>', and the same for 'b'.  Merging 'k' first leaves the
#   calls to 'k<b>' to rename, and until then they must still be calls to that
#   function - or 'm<a>' and 'm<b>' would look like they call different ones
cat >mutual.info <<'EOF'
TN:
SF:proj/mutual.h
FNL:0,1,3
FNA:0,1,k<a>
FNA:0,1,k<b>
FNC:0#0,2,10,0,1,m<a>
FNC:0#1,2,10,1,1,m<b>
FNL:1,4,6
FNA:1,1,m<a>
FNA:1,1,m<b>
FNC:1#0,5,10,0,1,k<a>
FNC:1#1,5,10,1,1,k<b>
FNF:4
FNH:4
FNCF:4
FNCH:4
DA:1,1
DA:2,1
DA:4,1
DA:5,1
LF:4
LH:4
end_of_record
EOF
printf 'template <class T> int k(T x)\n{\n  return m(x);\n}\ntemplate <class T> int m(T x)\n{\n  return k(x);\n}\n' \
    > proj/mutual.h
runLcov mutual --callgraph -a mutual.info -o mutual.info.out
checkFunctionRecords mutual mutual.info.out <<'EOF'
SF:proj/mutual.h
FNA:0,2,k<a>
FNM:0#0,1,k<b>
FNC:0,2,10,0,2,m<a>
FNA:1,2,m<a>
FNM:1#0,1,m<b>
FNC:1,5,10,0,2,k<a>
FNCF:2
FNCH:2
EOF

# A call to a merged name is a call to the name kept:  here from a file which
#   is then removed, so that what is left is the 'x' call - in each testcase
for f in a b p1 p2 p3 ; do
    printf 'int x;\nint y;\nint z;\n' > proj/$f.c
done
for t in t1 t2 ; do
    cat <<EOF
TN:$t
SF:proj/a.c
FNL:0,1,3
FNA:0,2,k<a>
FNM:0#0,1,k<b>
FNF:1
FNH:1
DA:1,2
LF:1
LH:1
end_of_record
TN:$t
SF:proj/b.c
FNL:0,1,2
FNA:0,1,g
FNC:0,2,10,0,1,k<b>
FNF:1
FNH:1
FNCF:1
FNCH:1
DA:1,1
LF:1
LH:1
end_of_record
EOF
done > ext.info
runLcov ext_read --callgraph -a ext.info --ignore-errors unused -o ext_read.info
runLcov ext --callgraph --remove ext_read.info '*b.c' --ignore-errors unused \
    -o ext.info.out
checkFunctionRecords ext ext.info.out <<'EOF'
SF:proj/a.c
FNA:0x1d,2,k<a>
FNM:0#0,1,k<b>
FNCF:0
FNCH:0
SF:proj/a.c
FNA:0x1d,2,k<a>
FNM:0#0,1,k<b>
FNCF:0
FNCH:0
EOF

# ..and a name merged in three files is one which several files define:  the
#   call from 'p3.c' is to its own
for p in p1 p2 p3 ; do
    echo "TN:"
    echo "SF:proj/$p.c"
    echo "FNL:0,1,1"
    echo "FNA:0,2,f<a>"
    echo "FNM:0#0,1,f<b>"
    echo "FNL:1,2,3"
    echo "FNA:1,1,h"
    [ $p == p3 ] && echo "FNC:1,3,5,0,1,f<b>"
    echo "FNF:2"
    echo "FNH:2"
    if [ $p == p3 ] ; then
        echo "FNCF:1" ; echo "FNCH:1"
    else
        echo "FNCF:0" ; echo "FNCH:0"
    fi
    echo "DA:1,2" ; echo "DA:2,1" ; echo "LF:2" ; echo "LH:2"
    echo "end_of_record"
done > m3.info
runLcov m3 --callgraph -a m3.info -o m3.info.out
actual=`grep -E '^(SF|FNC):' m3.info.out | tr '\n' '|'`
expect="SF:proj/p1.c|SF:proj/p2.c|SF:proj/p3.c|FNC:1,3,5,0,1,f<a>|"
if [ "$actual" != "$expect" ] ; then
    fail m3 "expected '$expect' but got '$actual'"
fi

# ----------------------------------------------------------------------
echo "*** 7. genhtml marks a name with the number of names it stands for"
# ----------------------------------------------------------------------
mark()
{
    # the HTML of name '$1' marked as standing for itself and the names '$2' -
    #   a ','-separated list of 'name (count)' - after its link, or inside it if
    #   '$3' says so:  a callee cell names every symbol which leads to its
    #   destination, inside the one link
    local n=$((`echo "$2" | tr ',' '\n' | wc -l` + 1))
    local name=`echo "$1" | sed -e 's/</\&lt;/g' -e 's/>/\&gt;/g'`
    local end='</a>'
    [ "x$3" == xinside ] && end=
    local -a rows
    local item
    while read -r item ; do
        rows+=("${item##*(}")
        rows[-1]="${rows[-1]%)}:${item% (*}"
    done < <(echo "$2" | tr ',' '\n' | sed -e 's/^ *//')
    echo "$name$end`markList "$1" $n "${rows[@]}"`"
}
markList()
{
    # markList name total rows...:  the HTML of the mark of 'name', which stands
    #   for 'total' names, listing 'rows' - each 'count:name', or '...' -  as one
    #   row of the tooltip each, the rows in alternating colors
    local name=`echo "$1" | sed -e 's/</\&lt;/g' -e 's/>/\&gt;/g'`
    local n=$2
    shift 2
    local html="<sup class=\"mergedNames\">$n<span class=\"mergedNamesList\"><span class=\"mergedNamesHead\">$name stands for $n names - merged into it:</span>"
    local alt=
    local row count
    for row in "$@" ; do
        if [ "x$row" == 'x...' ] ; then
            count=
        else
            count="${row%%:*}:"
            row="${row#*:}"
        fi
        row=`echo "$row" | sed -e 's/</\&lt;/g' -e 's/>/\&gt;/g'`
        html="$html<span class=\"mergedNamesRow$alt\"><span class=\"mergedNamesCount\">$count</span><span class=\"mergedNamesName\">$row</span></span>"
        [ -z "$alt" ] && alt=Alt || alt=
    done
    echo "$html</span></sup>"
}
checkMark()
{
    # checkMark label page name names [inside]:  the page marks the name
    local m=`mark "$3" "$4" $5`
    if ! grep -q -F -e "$m" $2 ; then
        fail $1 "expected '$m' in $2"
    fi
}
F=`mark 'f<int>' 'f<char> (1)'`
runGenhtml marks --callgraph --ignore-errors inconsistent -o html_marks \
    collapse.info
# ..in the function table, as the function and as the caller of 'g' and the
#   callee of 'k<int>' on the call site pages - one call site and its caller
#   in another file included - and the function itself, on its callers page
checkMark marks html_marks/proj/c.h.func.html 'f<int>' 'f<char> (1)'
checkMark marks html_marks/proj/c.h.func.html 'h<int>' 'h<long> (0)'
checkMark marks html_marks/proj/c.h.callees.html 'f<int>' 'f<char> (1)' inside
checkMark marks html_marks/proj/u.c.callees.html 'q<int>' 'q<char> (1)' inside
checkMark marks html_marks/proj/c.h.callers.html 'p<a>' 'p<b> (2)'
if [ 2 != `grep -c -F -e "$F" html_marks/proj/c.h.callers.html` ] ; then
    fail marks "expected 'f<int>' marked as callee and as caller"
fi
# ..and nothing where nothing was merged
if grep -q -E '(k|m|n|r|z)&lt;[a-z]*&gt;(</a>)?<sup' html_marks/proj/*.html ; then
    fail marks "a name which nothing was merged into was marked"
fi

# ..on the row of each alias, where the function has several, and in the
#   caption of its callers
runGenhtml marks_union --callgraph $APART --ignore-errors inconsistent \
    -o html_marks_union fnm_union.info
checkMark marks_union html_marks_union/proj/c.h.func.html \
    'f<int>' 'f<char> (1)'
if ! grep -q -F -e "Callers of alias f&lt;int&gt;<sup class=\"mergedNames\"" \
        html_marks_union/proj/c.h.callers.html ; then
    fail marks_union "the caption of 'f<int>' was not marked"
fi

# ..with as many names as there are, and the tooltip lists the first few:  ten,
#   the name itself included, unless 'genhtml_alias_list_length' says otherwise
awk '{ print } $0 == "FNA:1,1,f<char>" {
         for (i = 1; i <= 10; ++i) printf("FNM:1#0,0,f<b%02d>\n", i) }' \
    c.info > many.info
B='0:f<b01> 0:f<b02>'
NINE="$B 0:f<b03> 0:f<b04> 0:f<b05> 0:f<b06> 0:f<b07> 0:f<b08> 0:f<b09>"
ALL="$NINE 0:f<b10> 1:f<char>"
checkAliasList()
{
    # checkAliasList label expected-sup [genhtml-opts]:  the mark of 'f<int>'
    local label=$1
    local sup=$2
    shift 2
    runGenhtml $label --callgraph --ignore-errors inconsistent "$@" \
        -o html_$label many.info || return
    if ! grep -q -F -e "f&lt;int&gt;</a>$sup" html_$label/proj/c.h.func.html
    then
        fail $label "expected '$sup' as the mark of 'f<int>'"
    fi
}
DEFAULT=`markList 'f<int>' 12 $NINE ...`
checkAliasList marks_many "$DEFAULT"
checkAliasList marks_three "`markList 'f<int>' 12 $B ...`" \
    --rc genhtml_alias_list_length=3
checkAliasList marks_all "`markList 'f<int>' 12 $ALL`" \
    --rc genhtml_alias_list_length=0
checkAliasList marks_leader '<sup class="mergedNames">12</sup>' \
    --rc genhtml_alias_list_length=1
# ..and a negative length is a usage error - which, ignored, is the default
$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph --ignore-errors inconsistent \
    --rc genhtml_alias_list_length=-1 -o html_marks_neg many.info \
    > marks_neg.log 2>&1
if [ 0 == $? ] ; then
    fail marks_neg "expected genhtml to fail"
elif ! grep -q -F "Unsupported value 'genhtml_alias_list_length = -1'" \
        marks_neg.log ; then
    fail marks_neg "expected a usage error but got:" `grep ERROR marks_neg.log`
fi
runGenhtmlWarn marks_neg_ign \
    "Unsupported value 'genhtml_alias_list_length = -1'" \
    --callgraph --ignore-errors inconsistent,usage \
    --rc genhtml_alias_list_length=-1 -o html_marks_neg_ign many.info
if ! grep -q -F -e "f&lt;int&gt;</a>$DEFAULT" \
        html_marks_neg_ign/proj/c.h.func.html ; then
    fail marks_neg_ign "an ignored bad length was not the default"
fi

# ..and, in a differential report, the names merged in the version whose count
#   is shown:  here the baseline knows 'h<int>' as 'h<short>', and keeps
#   'h<long>' with 'h<short>' merged into it - while the current data merged
#   'h<long>' into 'h<int>', so the two are one function, shown as the current
#   data shows it;  and the baseline ran 'q<char>' more often
sed -e 's/h<int>/h<short>/' -e 's/^FNA:8,1,q<char>$/FNA:8,5,q<char>/' \
    c.info > base2.info
$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph \
    --ignore-errors inconsistent --baseline-file base2.info \
    -o html_marks_base c.info 2>&1 | tee html_marks_base.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail html_marks_base "genhtml failed:" `grep -E 'ERROR' html_marks_base.log`
fi
checkMark marks_base html_marks_base/proj/c.h.func.html 'h<int>' 'h<long> (0)'
if [ "`fnTla html_marks_base/proj/c.h.func.html 'h&lt;int&gt;'`" != tlaUBC ] ||
    grep -q -F '>h&lt;long&gt;</a>' html_marks_base/proj/c.h.func.html ; then
    fail marks_base "the baseline's 'h<long>' was not compared with 'h<int>'"
fi
checkMark marks_base html_marks_base/proj/c.h.func.html 'f<int>' 'f<char> (1)'
checkMark marks_base html_marks_base/proj/c.h.func.html 'q<int>' 'q<char> (1)'

# ----------------------------------------------------------------------
echo "*** 8. the name kept is called from each place the merged names were"
# ----------------------------------------------------------------------
# 'u' calls 'y' from two places, so each instantiation of 'y' is called from
#   both:  they merge, and 'y<int>' has the callers of both, in the order of
#   the places they call from.  'main' calls the two 'u's from two places, so
#   those are not merged
cat >proj/y.h <<'EOF'
template <class T> int y(T x) { return x; }
template <class T> int u(T x) { return y(x) + y(x); }
int main() { return u(1) + u('a'); }
EOF
cat >y.info <<'EOF'
TN:
SF:proj/y.h
FNL:0,1,1
FNA:0,2,y<char>
FNA:0,2,y<int>
FNL:1,2,2
FNA:1,1,u<char>
FNA:1,1,u<int>
FNC:1#0,2,40,0,1,y<char>
FNC:1#0,2,47,0,1,y<char>
FNC:1#1,2,40,1,1,y<int>
FNC:1#1,2,47,1,1,y<int>
FNL:2,3,3
FNA:2,1,main
FNC:2,3,21,0,1,u<int>
FNC:2,3,28,0,1,u<char>
FNF:3
FNH:3
FNCF:6
FNCH:6
DA:1,1
DA:2,1
DA:3,1
LF:3
LH:3
end_of_record
EOF
runLcov two_places --callgraph -a y.info -o two_places.info
checkFunctionRecords two_places two_places.info <<'EOF'
SF:proj/y.h
FNA:0,4,y<int>
FNM:0#0,2,y<char>
FNA:1,1,u<char>
FNA:1,1,u<int>
FNC:1,2,40,1,2,y<int>
FNC:1,2,47,1,2,y<int>
FNA:2d,1,main
FNC:2,3,21,0,1,u<int>
FNC:2,3,28,0,1,u<char>
FNCF:4
FNCH:4
EOF
$COVER $GENHTML_TOOL $LCOV_OPTS --callgraph -o html_two_places y.info \
    > html_two_places.log 2>&1
if [ 0 != $? ] ; then
    fail html_two_places "genhtml failed:" `grep -E 'ERROR' html_two_places.log`
fi
# the callers of 'y<int>':  the site each is at, and its count
CALLERS=`awk '/id="caller_y_int__/ { f = 1 }
    f && match($0, />y\.h:[0-9]+:[0-9]+</) {
        s = substr($0, RSTART + 5, RLENGTH - 6) }
    f && s && match($0, /call">[0-9]+</) {
        printf "%s:%s ", s, substr($0, RSTART + 6, RLENGTH - 7); s = "" }
    /<\/table>/ { f = 0 }' \
    html_two_places/proj/y.h.callers.html`
if [ "$CALLERS" != '2:40:2 2:47:2 ' ] ; then
    fail html_two_places "callers of 'y<int>': '$CALLERS'"
fi

# ----------------------------------------------------------------------
echo "*** 9. which name is kept, and a file whose calls were not measured"
# ----------------------------------------------------------------------
# Each function of 'nc.c' has two aliases which make the same call:  the
#   shortest name is kept - 'x<aa>' and 'x<bb>' are as long as each other, so
#   the first in sort order - and a lambda counts as longer than any other
#   name.  'nd.c' is the same file with nothing measured about its calls:  no
#   call site, and nothing calls into it - and with names of its own, as a name
#   two files define is left alone anyway.  There, nothing tells its aliases
#   apart because nothing was measured, so none of them is merged
for f in nc nd ; do
    callee=u
    [ $f == nd ] && callee=v
    printf 'int %s() { return 0; }\n' $callee > proj/$f.c
    for i in 2 3 4 ; do
        echo "int t$i() { return $callee(); }" >> proj/$f.c
    done
    cat > $f.in <<EOF
TN:
SF:proj/$f.c
FNL:0,1,1
FNA:0,4,$callee
FNL:1,2,2
FNA:1,1,t<b>
FNA:1,1,t<a>
FNC:1,2,10,0,2,$callee
FNL:2,3,3
FNA:2,1,x<bb>
FNA:2,1,x<aa>
FNC:2,3,10,0,2,$callee
FNL:3,4,4
FNA:3,1,a{lambda(int)#1}
FNA:3,1,a_long_named_function
FNC:3,4,10,0,2,$callee
FNF:7
FNH:7
FNCF:3
FNCH:3
DA:1,4
DA:2,2
DA:3,2
DA:4,2
LF:4
LH:4
end_of_record
EOF
done
cp nc.in nc.info
grep -v '^FNC' nd.in | sed -e 's/,\([a-z]\)\([<{_]\)/,n\1\2/' > nd.info
runLcov names -a nc.info -a nd.info --callgraph -o names.info &&
    checkFunctionRecords names names.info <<'EOF'
SF:proj/nc.c
FNA:0,4,u
FNA:1d,2,t<a>
FNM:1#0,1,t<b>
FNC:1,2,10,0,2,u
FNA:2d,2,x<aa>
FNM:2#0,1,x<bb>
FNC:2,3,10,0,2,u
FNA:3d,2,a_long_named_function
FNM:3#0,1,a{lambda(int)#1}
FNC:3,4,10,0,2,u
FNCF:3
FNCH:3
SF:proj/nd.c
FNA:0,4,v
FNA:1,1,nt<a>
FNA:1,1,nt<b>
FNA:2,1,nx<aa>
FNA:2,1,nx<bb>
FNA:3,1,na_long_named_function
FNA:3,1,na{lambda(int)#1}
EOF
# ..and in genhtml, a function table row for each alias of 'nd.c', with
#   nothing to say about calls
runGenhtmlNames()
{
    $COVER $GENHTML_TOOL $LCOV_OPTS --callgraph --show-proportion \
        --ignore-errors inconsistent "$@" 2>&1 | tee html_names.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail html_names "genhtml failed:" `grep -E 'ERROR' html_names.log`
    fi
}
runGenhtmlNames -o html_names nc.info nd.info
if [ -f html_names/proj/nd.c.func.html ] ; then
    if [ 6 != `grep -c 'class="coverFnAlias"' html_names/proj/nd.c.func.html` ]
    then
        fail html_names "expected a row for each alias of 'nd.c'"
    fi
    if grep -q 'group_' html_names/proj/nd.c.func.html ; then
        fail html_names "an alias of 'nd.c' was shown as a group"
    fi
fi

# A baseline captured without the callgraph, against a current which has it:
#   the aliases of 'f' are two groups in the current data - 'f<int>' calls
#   'g', the other two call 'h' - and in the baseline they are not merged at
#   all, nothing being measured there.  Each alias of the baseline is compared
#   with the group it is in now, so an unchanged function is unchanged:  no
#   function is new or lost, and only the calls - which the baseline has none
#   of - are
printf 'int g() { return 0; }\nint h() { return 1; }\n' > proj/grp.c
printf 'template <class T> int f(T x)\n{\n' >> proj/grp.c
printf '  return sizeof(T) == 1 ? g() :\n         h();\n}\n' >> proj/grp.c
cat > grp.info <<'EOF'
TN:
SF:proj/grp.c
FNL:0,1,1
FNA:0,5,g
FNL:1,2,2
FNA:1,0,h
FNL:2,3,7
FNA:2,2,f<int>
FNA:2,3,f<char>
FNA:2,0,f<long>
FNC:2#0,5,27,0,3,g
FNC:2#1.2,6,10,0,0,h
FNF:5
FNH:3
FNCF:2
FNCH:1
DA:1,5
DA:2,0
DA:3,5
DA:5,5
DA:6,0
LF:5
LH:3
end_of_record
EOF
grep -v '^FNC' grp.info > grp_base.info
runGenhtmlNames -o html_grp --baseline-file grp_base.info grp.info
checkLog html_grp html_names.log '    function: UBC:1 CBC:3' \
    '    callgraph: UIC:1 GIC:1'
# ..and the function table has a row for each group under the function:  its
#   category, its count - 'f<char>' and the 'f<long>' merged into it - and its
#   own call sites, leading to its rows on the callees page.  The function's
#   row has all of them
checkLog html_grp html_grp/proj/grp.c.func.html \
    'grp.c.callees.html#func_f_int_" title="Click to go to the call sites of this function">50.0&nbsp;% (1 / 2)' \
    'grp.c.callees.html#group_f_char_" title="Click to go to the call sites of this alias group">0.0&nbsp;% (0 / 1)' \
    'grp.c.callees.html#group_f_int_" title="Click to go to the call sites of this alias group">100.0&nbsp;% (1 / 1)'
if [ -f html_grp/proj/grp.c.func.html ] &&
    [ 2 != `grep -A2 'class="coverFnAlias"' html_grp/proj/grp.c.func.html |
              grep -c -E 'coverFnAliasHi">(3|2)<'` ] ; then
    fail html_grp "expected the count of each group"
fi
# ..and on the callees page the function's summary block comes first:  one row
#   per unique call site of all of its groups, the uncovered one first, with
#   the anchors of the sites - and then the name cell of each group, beside
#   its own calls
GROUP_ROWS=`perl -ne 'print("$1: $2 ")
                      if m{class="calleeFnAlias"[^>]*id="(group_[^"]*)"><a[^>]*>([^<]*)<};
                  print("$1 ") if m{<td[^>]*id="(site_[0-9_]*)"}' \
            html_grp/proj/grp.c.callees.html 2>/dev/null`
if [ "$GROUP_ROWS" != 'site_6_10 site_5_27 group_f_char_: f&lt;char&gt; group_f_int_: f&lt;int&gt; ' ] ; then
    fail html_grp "unexpected groups on the callees page: '$GROUP_ROWS'"
fi
# ..and on both pages the first row of the function is that of its summary
#   block:  the proportion of all of its callers and of all of its call sites
#   span the block, and its name leads to its definition.  On the callers page
#   the block is the one row of the callers outside the report, the deduced
#   calls of both groups summed, and the proportion of the other direction leads
#   to the summary block of the callees page.  On the callees page it is the
#   two unique sites, and the category and count of the uncovered one lead to
#   the next row which has them:  the first row of the group 'f<char>', which
#   has no anchor of its own but the group's
for page in callers callees ; do
    PAGE=html_grp/proj/grp.c.$page.html
    [ -f $PAGE ] || continue
    SUMMARY=`perl -0 -ne 'if (m{<tr[^>]*class="callgraphFirstRow">\n(.*?)</tr>}s) {
                              my $row = $1;
                              my @links = ($row =~ m{href="([^"]*)"}g);
                              my $empty = () = $row =~
                                  m{<td class="coverCallgraph"></td>}g;
                              my @rates = ($row =~ m{\(\d+ / \d+\)}g);
                              print("@links|$empty|@rates");
                          }' $PAGE`
    if [ $page == callers ] ; then
        expect='grp.c.callees.html#func_f_int_ grp.c.gcov.html#L1|2|(1 / 2)'
    else
        expect='grp.c.gcov.html#L1 grp.c.gcov.html#L6 ../proj/grp.c.callers.html#func_h #group_f_char_ #group_f_char_|0|(1 / 2)'
    fi
    if [ "$SUMMARY" != "$expect" ] ; then
        fail html_grp "unexpected row of the function on the $page page: '$SUMMARY'"
    fi
done
checkLog html_grp html_grp/proj/grp.c.callees.html \
    '<td class=coverPerLo rowspan="2">50.0&nbsp;% (1 / 2)</td>' \
    '<tr class="callgraphGroupRow">'
# ..and the rows of each group are set off by subdued colours:  the two group
#   rows of the function table are marked as such, and so is the one row of
#   each group on either page - and not the rows of the summary block above
#   them
for page in func callers callees ; do
    PAGE=html_grp/proj/grp.c.$page.html
    [ -f $PAGE ] || continue
    if [ 2 != `grep -c -E '<tr class="(fn|callgraph)GroupRow">' $PAGE` ] ; then
        fail html_grp "expected the two group rows of the $page page to be marked"
    fi
done
# ..by the stylesheet:  the neutral cells in the pale grey of the alias rows of
#   the function table, the call cells paler still, the proportions and counts
#   in the owner colours, and each category halfway to the page background - a
#   named colour as it is
checkCss()
{
    local css=$1
    shift
    for rule in "$@" ; do
        if ! RULE="$rule" perl -0 -ne 'exit(index($_, $ENV{RULE}) < 0)' $css
        then
            fail css "missing from $css: '$rule'"
        fi
    done
}
checkCss html_grp/gcov.css \
    "td.calleeFnAlias
{
  text-align: left;
  vertical-align: top;
  padding-left: 30px;
  padding-right: 20px;
  color: #284fa8;
  background-color: #E5DBDB;" \
    "tr.callgraphGroupRow td.coverCallgraph
{
  padding-left: 30px;
  background-color: #F2EEEE;" \
    "tr.callgraphGroupRow td.coverCallgraphLo
{
  background-color: #EC7063;" \
    "tr.callgraphGroupRow td.coverCallgraphHi,
tr.callgraphGroupRow td.calleeXref,
tr.callgraphGroupRow td.calleeXrefAlt,
tr.fnGroupRow td.coverFn
{
  background-color: #E5DBDB;" \
    "tr.callgraphGroupRow td.coverPerHi,
tr.fnGroupRow td.coverPerHi
{
  background-color: #82E0AA;" \
    "tr.callgraphGroupRow td.coverPerMed,
tr.fnGroupRow td.coverPerMed
{
  background-color: #F9E79F;" \
    "tr.callgraphGroupRow td.coverPerLo,
tr.fnGroupRow td.coverPerLo
{
  background-color: #EC7063;" \
    "tr.callgraphGroupRow td.tlaUIC,
tr.callgraphGroupRow a.tlaBgUIC,
tr.fnGroupRow td.tlaUIC {
  background-color: #F6D497;" \
    "tr.fnGroupRow td.tlaEUC {
  background-color: white;"
# ..and in dark mode, halfway to its background
runGenhtmlNames -o html_grp_dark --dark-mode --baseline-file grp_base.info \
    grp.info
checkCss html_grp_dark/gcov.css \
    "tr.fnGroupRow td.tlaUIC {
  background-color: #553B0C;"
# ..where the callers page has each group leading to its own rows on the
#   callees page
checkLog html_grp html_grp/proj/grp.c.callers.html \
    '<td class=coverPerLo><a href="grp.c.callees.html#group_f_char_" title="Click to go to list of callees">0.0&nbsp;% (0 / 1)</a></td>' \
    '<td class=coverPerHi><a href="grp.c.callees.html#group_f_int_" title="Click to go to list of callees">100.0&nbsp;% (1 / 1)</a></td>'
# ..and a call of the function which left the boundary of the report is a call
#   of none of its groups:  the last row of the summary block, above the
#   groups, none of which has it
sed -e 's/^FNL:2,/FNL:2c,/' grp.info > grp_ext.info
runGenhtmlNames -o html_grp_ext grp_ext.info
EXT_ROWS=`perl -ne 'print("$1 ") if m{class="(calleeFnAlias)"[^>]*>};
                    print("ext ") if m{&lt;external callee&gt;}' \
            html_grp_ext/proj/grp.c.callees.html 2>/dev/null`
if [ "$EXT_ROWS" != 'ext calleeFnAlias calleeFnAlias ' ] ; then
    fail html_grp_ext "unexpected rows of the function on the callees page: '$EXT_ROWS'"
fi

# ..and with the groups suppressed, each page has the function's summary block
#   alone, and says so above the table.  The name of the function stands for
#   every alias of all of its groups - the mark on it counts them, and its
#   tooltip lists the others in alphabetical order - and nothing leads to a
#   group, on the call site pages or from the function table
runGenhtmlNames -o html_grp_supp --rc suppress_alias_groups=1 \
    --baseline-file grp_base.info grp.info
for page in callers callees func ; do
    PAGE=html_grp_supp/proj/grp.c.$page.html
    if [ ! -f $PAGE ] ; then
        fail html_grp_supp "$PAGE was not written"
        continue
    fi
    if grep -q -E 'group_|calleeFnAlias|callgraphGroupRow' $PAGE ; then
        fail html_grp_supp "an alias group is shown on the $page page"
    fi
    [ $page == func ] && continue
    checkLog html_grp_supp $PAGE \
        "<td class=\"callgraphNote\" colspan=\"7\">Alias groups suppressed - see 'suppress_alias_groups' configuration file option</td>" \
        '<a href="grp.c.gcov.html#L1">f&lt;int&gt;</a><sup class="mergedNames">3<span class="mergedNamesList"><span class="mergedNamesHead">f&lt;int&gt; stands for 3 names - merged into it:</span><span class="mergedNamesRow"><span class="mergedNamesCount">3:</span><span class="mergedNamesName">f&lt;char&gt;</span></span><span class="mergedNamesRowAlt"><span class="mergedNamesCount">0:</span><span class="mergedNamesName">f&lt;long&gt;</span></span></span></sup>'
done
checkLog html_grp_supp html_grp_supp/proj/grp.c.func.html \
    '<td class=coverPerLo><a href="grp.c.callees.html#func_f_int_" title="Click to go to the call sites of this function">50.0&nbsp;% (1 / 2)</a></td>' \
    '<td class=coverPerLo>0.0&nbsp;% (0 / 1)</td>' \
    '<td class=coverPerHi>100.0&nbsp;% (1 / 1)</td>'
# ..and a page with no function shown as groups has no note
runGenhtmlNames -o html_nd_supp --rc suppress_alias_groups=1 nc.info nd.info
for page in callers callees ; do
    PAGE=html_nd_supp/proj/nc.c.$page.html
    if [ ! -f $PAGE ] || grep -q -F 'Alias groups suppressed' $PAGE ; then
        fail html_grp_supp "the note is on the $page page of 'nc.c', which has no groups"
    fi
done

# ..and a caller which calls one group twice from one place - one call
#   which reached it and one which did not - and the other group once, and
#   not at all.  In the group, the two are one row, which was hit:  'GIC',
#   since the category of a row agrees with its count.  In the summary they are
#   one unique site which was hit:  'GIC', with the count of both - below the
#   other site, which was not hit.  The callers outside the report are one row
#   of the summary, summed over both groups
printf 'void m()\n{\n  f((char)1); f((char)2);\n  f(1);\n}\n' > proj/grpm.c
cp grp.info grp_fold.info
cat >> grp_fold.info <<'EOF'
TN:
SF:proj/grpm.c
FNL:0,1,5
FNA:0,1,m
FNC:0,3,3,0,1,f<char>
FNC:0,3,3,1,0,f<char>
FNC:0,4,3,0,0,f<int>
FNF:1
FNH:1
FNCF:2
FNCH:1
DA:1,1
DA:3,1
DA:4,1
LF:3
LH:3
end_of_record
EOF
runGenhtmlNames -o html_grp_fold --baseline-file grp_base.info grp_fold.info
FOLD_ROWS=`perl -0 -ne 'while (m{<tr id="caller_f_int__(\d+)"[^>]*>(.*?)</tr>}sg) {
                            my ($n, $row) = ($1, $2);
                            my ($at) = $row =~ m{>(grpm\.c:\d+:\d+)<};
                            my ($tla) = $row =~ m{class="tla(\w+)"};
                            print("$n:$at:$tla ");
                        }
                        print("ext:$1 ")
                            while m{<td class="coverCallgraph\w*[^>]*>\((\d+)\)</td>}g' \
            html_grp_fold/proj/grp.c.callers.html 2>/dev/null`
if [ "$FOLD_ROWS" != '0:grpm.c:4:3:UIC 1:grpm.c:3:3:GIC 2:grpm.c:3:3:GIC 3:grpm.c:4:3:UIC ext:4 ext:2 ext:2 ext:2 ' ] ; then
    fail html_grp_fold "unexpected rows of the callers of 'f': '$FOLD_ROWS'"
fi
checkLog html_grp_fold html_grp_fold/proj/grp.c.callers.html \
    '<td class="tlaGIC"><a href="#caller_g_0" title="click for the next hit call">1</a></td>'
# ..and the callgraph numbers of the report are those of the rows the pages
#   show:  the three records of 'grpm.c' are its two rows, and 'grp.c' is the
#   two rows of the summary block of 'f'
checkLog html_grp_fold html_names.log \
    '  lines=3 hit=3 functions=1 hit=1 callgraph=2 hit=1' \
    '  lines=5 hit=3 functions=5 hit=3 callgraph=2 hit=1' \
    '  callgraph...: 50.0% (2 of 4 callees)'

# With 'show_callgraph_summary = 0' a function shown as groups has no summary
#   block:  its groups are listed as functions are, one after the other, with
#   no indent and none of the subdued colours.  They share the colour of the
#   function in the alternation of the page and the rule above it, and the
#   first of them carries the anchor of the function.  Each group is counted:
#   'grp.c' is the 2 rows of 'f<char>' and 'f<int>', which share no site
runGenhtmlNames -o html_grp_nosum --rc show_callgraph_summary=0 \
    --baseline-file grp_base.info grp.info
checkLog html_grp_nosum html_names.log \
    '  lines=5 hit=3 functions=4 hit=3 callgraph=2 hit=1' \
    '    callgraph: UIC:1 GIC:1'
for page in callers callees ; do
    PAGE=html_grp_nosum/proj/grp.c.$page.html
    if [ ! -f $PAGE ] ; then
        fail html_grp_nosum "$PAGE was not written"
        continue
    fi
    if grep -q -E 'calleeFnAlias|callgraphGroupRow|Alias groups suppressed' \
            $PAGE ; then
        fail html_grp_nosum "a group of the $page page is shown as a summary's"
    fi
    # the name cell of each group, in the order of the page:  the least
    #   covered first - on the callees page 'f<char>', which calls nothing
    #   which was taken.  On the callers page both are called from outside the
    #   report only, and are in name order.  Whether its row has the rule above
    #   it and whether its cell has the anchor of the function
    NOSUM=`perl -0 -ne 'while (m{<tr([^>]*)>((?:(?!</tr>).)*?<td class="(calleeFn\w*)"[^>]*id="(group_\w+)">(<span id="func_\w+">)?)}sg) {
                            my ($tr, $class, $id, $func) = ($1, $3, $4, $5);
                            print("$id:$class:",
                                  ($tr =~ /callgraphFirstRow/ ? "rule" : "-"),
                                  ($func ? ":func" : ""), " ");
                        }' $PAGE`
    if [ "$NOSUM" != 'group_f_char_:calleeFn:rule:func group_f_int_:calleeFn:- ' ] ; then
        fail html_grp_nosum "unexpected groups on the $page page: '$NOSUM'"
    fi
done
# ..and each group has its own row of callers from outside the report, and
#   the note beside its name
if [ -f html_grp_nosum/proj/grp.c.callers.html ] ; then
    if [ 3 != `grep -c '&lt;deduced external callers&gt;' html_grp_nosum/proj/grp.c.callers.html` ] ; then
        fail html_grp_nosum "expected a row of external callers for each group and 'g'"
    fi
    if [ 3 != `grep -c 'class="calleeFnNote"' html_grp_nosum/proj/grp.c.callers.html` ] ; then
        fail html_grp_nosum "expected the note on the callers of each group and 'g'"
    fi
fi
# ..and the function table links the function to its first group, where the
#   anchor of the function now is, and its proportion is the sum of theirs
checkLog html_grp_nosum html_grp_nosum/proj/grp.c.func.html \
    'grp.c.callees.html#func_f_int_" title="Click to go to the call sites of this function">50.0&nbsp;% (1 / 2)' \
    'grp.c.callees.html#group_f_char_" title="Click to go to the call sites of this alias group">0.0&nbsp;% (0 / 1)'

# ..and where groups share a site, it is a row of each of them, and counted
#   by each:  the call from 'm' sets 'f<char>' apart from 'f<long>', and both
#   of them call 'h' at 6:10, so 'grp.c' has 3 rows.  Two groups of the same
#   rate are in the order of the larger denominator, then of their names, on
#   every sort order of the page
runGenhtmlNames -o html_grp_fold_nosum --rc show_callgraph_summary=0 \
    --baseline-file grp_base.info grp_fold.info
checkLog html_grp_fold_nosum html_names.log \
    '  lines=3 hit=3 functions=1 hit=1 callgraph=2 hit=1' \
    '  lines=5 hit=3 functions=5 hit=3 callgraph=3 hit=1' \
    '    callgraph: UIC:2 GIC:1' \
    '  callgraph...: 40.0% (2 of 5 callees)'
for page in callees callees-c callees-x ; do
    ORDER=`perl -ne 'print("$1 ") while m{id="(group_\w+)"}g' \
               html_grp_fold_nosum/proj/grp.c.$page.html 2>/dev/null`
    if [ "$ORDER" != 'group_f_char_ group_f_long_ group_f_int_ ' ] ; then
        fail html_grp_fold_nosum "unexpected order of the groups on $page: '$ORDER'"
    fi
done
checkLog html_grp_fold_nosum html_grp_fold_nosum/proj/grp.c.func.html \
    'grp.c.callees.html#func_f_int_" title="Click to go to the call sites of this function">33.3&nbsp;% (1 / 3)'
# ..and a call of the function from another file leads to the group it calls
checkLog html_grp_fold_nosum html_grp_fold_nosum/proj/grpm.c.callees.html \
    'href="../proj/grp.c.callers.html#group_f_char_"' \
    'href="../proj/grp.c.callers.html#group_f_int_"'

# ..and the call which left the boundary of the report is the last row of the
#   first group
runGenhtmlNames -o html_grp_ext_nosum --rc show_callgraph_summary=0 \
    grp_ext.info
EXT_ROWS=`perl -ne 'print("$1 ") if m{class="calleeFn"[^>]*id="(group_\w+)"};
                    print("ext ") if m{&lt;external callee&gt;}' \
            html_grp_ext_nosum/proj/grp.c.callees.html 2>/dev/null`
if [ "$EXT_ROWS" != 'group_f_char_ ext group_f_int_ ' ] ; then
    fail html_grp_ext_nosum "unexpected rows of the function on the callees page: '$EXT_ROWS'"
fi

# ..and there is nothing to suppress the groups in favour of:  the two settings
#   together are a usage error - a warning unless made fatal - and the groups
#   are shown
runGenhtmlNames -o html_grp_conflict --rc show_callgraph_summary=0 \
    --rc suppress_alias_groups=1 grp.info
checkLog html_grp_conflict html_names.log \
    "WARNING: (usage) 'suppress_alias_groups = 1' conflicts with 'show_callgraph_summary = 0':  alias groups are shown."
if [ -f html_grp_conflict/proj/grp.c.callees.html ] &&
    ( ! grep -q 'id="group_f_int_"' html_grp_conflict/proj/grp.c.callees.html ||
      grep -q 'Alias groups suppressed' html_grp_conflict/proj/grp.c.callees.html ) ; then
    fail html_grp_conflict "the groups were not shown"
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'collapse' $LOCAL_COVERAGE 0
fi

exit $STATUS
