#! /usr/bin/env bash

# Function aliases, through every operation which touches them.
#
# A function coverpoint is a location with a set of named aliases hanging off it
#   - one for a plain C function, several for a C++ template, a clone or a Java
#   lambda - and each alias carries its own hit count.  Every operation lcov has
#   reaches into that set:  the '.info' reader and writer, 'add'/'--intersect'/
#   '--subtract', '--erase-functions', the trivial-function and exclude-region
#   filters, the inconsistent-data repair, and - in genhtml - the differential
#   categorizer, which replaces each alias count with a (count, TLA) pair.
#
# The set is a 'FunctionAlias' object, reached through
#   'FunctionEntry::aliasNames()' and 'FunctionEntry::alias()' rather than indexed
#   into directly as a bare Perl hash, because a hash cannot survive the move into
#   XS:  an opaque C++ object either rebuilds a materialized copy on every call or
#   retains it for the life of the object, and the latter is what
#   'MCDC_Block::groups()' does - it cost 589 MB of peak RSS on a 132 MB report.
#
# The accessor discipline is behavior-neutral, so this test is written as an
#   assertion on the exact output of each of those operations:  the counts, the
#   record order, the found/hit totals the writer computes, and the per-alias TLA
#   in the HTML.
#   Nothing here needs a compiler - the inputs are hand-written '.info' files
#   over checked-in sources - so all of it runs on every platform.

source ../../common.tst

rm -rf *.info *.log *.json *.udiff *.actual *.expect proj html_* perlcov.info \
    cover_db.dat pycov.info __pycache__

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

LCOV_OPTS="$PARALLEL $PROFILE"
GENHTML_OPTS="$PARALLEL $PROFILE"
IGNORE="--ignore-errors inconsistent,unused,source"

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

checkFunctionRecords()
{
    # checkFunctionRecords label file <<expected
    #   compare just the function records of a '.info' against the expected text
    #   on stdin:  those records are what every case below is about, and the rest
    #   of the file is noise in the diff when one of them is wrong
    local label=$1
    local file=$2
    if [ ! -f $file ] ; then
        fail $label "$file was not written"
        return
    fi
    cat > $label.expect
    grep -E '^(FNL|FNA|FNF|FNH):' $file > $label.actual
    if ! diff -u $label.expect $label.actual ; then
        fail $label "unexpected function records in $file"
    fi
}

aliasRows()
{
    # aliasRows page
    #   the alias rows of one function view, in the order the page lists them,
    #   as 'name category count' - with '-' for the category when the report has
    #   no differential columns.  The leader row of a location carries the name
    #   of one of its aliases, so the rows have to be picked out by their class
    #   and not by the name in them
    perl -ne 'if (m{class="coverFnAlias"><a[^>]*>([^<]*)</a>}) {
                  $a = $1; $a =~ s/&lt;/</g; $a =~ s/&gt;/>/g; $t = "-";
              } elsif (defined($a) && m{<td class="tla(\w+)">}) {
                  $t = $1;
              } elsif (defined($a) &&
                       m{<td class="coverFnAlias(?:Lo|Hi)">(\d+)</td>}) {
                  print("$a $t $1\n"); undef($a);
              }' $1
}

checkAliasRows()
{
    # checkAliasRows label page <<expected
    local label=$1
    local page=$2
    if [ "x$page" == 'x' ] || [ ! -f "$page" ] ; then
        cat > /dev/null
        fail $label "no function view was written"
        return
    fi
    cat > $label.expect
    aliasRows $page > $label.actual
    if ! diff -u $label.expect $label.actual ; then
        fail $label "unexpected alias rows in $page"
    fi
}

checkFunctionBins()
{
    # checkFunctionBins label log 'sorted TLA:count list'
    #   the per-category function counts genhtml reports.  The bins are printed
    #   in hash order, so compare them sorted
    local label=$1
    local log=$2
    local expect=$3
    local actual=`grep -E '^ +function: ' $log | head -1 |
        sed -e 's/^ *function: //' | tr ' ' '\n' | sort | tr '\n' ' '`
    if [ "$actual" != "$expect " ] ; then
        fail $label "expected function bins '$expect', found '$actual'"
    fi
}

checkSummary()
{
    # checkSummary label log expectedLine...
    local label=$1
    local log=$2
    shift 2
    local expect
    for expect in "$@" ; do
        if ! grep -qxF "$expect" $log ; then
            fail $label "expected '$expect' in $log:"
            grep -E '^  (lines|functions)' $log
        fi
    done
}

mkdir -p proj

# 'twice' is one location with several aliases, 'trivial' is a one line function
#   with no body (the trivial filter is defined in terms of the source text, so
#   the braces have to really be there) and 'main' is an ordinary single-alias
#   function.
cat >proj/t.cpp <<'EOF'
template<class T> T twice(T x)
{
    return x + x;
}

int trivial(void) {}

int main(void)
{
    return twice(1) + trivial();
}
EOF

# 'FNL:<index>,<start>,<end>' names a location and 'FNA:<index>,<count>,<name>'
#   adds one alias to it.  'twice<long>' is present but never called, which is
#   the case an alias exists to record:  the location is hit, this symbol is not
cat >a.info <<'EOF'
TN:aliases
SF:proj/t.cpp
FNL:0,1,4
FNA:0,3,twice<int>
FNA:0,0,twice<long>
FNA:0,5,twice<char>
FNL:1,6,6
FNA:1,0,trivial
FNL:2,8,11
FNA:2,1,main
FNF:3
FNH:2
DA:1,8
DA:3,8
DA:6,0
DA:8,1
DA:10,1
LF:5
LH:4
end_of_record
EOF

# The same file from a second run.  Every relation one alias set can have to
#   another is here:  'twice<int>' and 'twice<long>' are shared (the counts add),
#   'twice<short>' is new and 'twice<char>' is missing (the union is neither),
#   and the location on line 6 has one alias in each which is not in the other -
#   so it has no alias at all in common, which is the one case where a set
#   operation has to remove the whole location
cat >b.info <<'EOF'
TN:aliases
SF:proj/t.cpp
FNL:0,1,4
FNA:0,4,twice<int>
FNA:0,6,twice<long>
FNA:0,2,twice<short>
FNL:1,6,6
FNA:1,0,trivial2
FNL:2,8,11
FNA:2,0,main
FNF:3
FNH:1
DA:1,12
DA:3,12
DA:6,0
DA:8,0
DA:10,0
LF:5
LH:2
end_of_record
EOF

# ----------------------------------------------------------------------
echo "*** 1. read and write one location with several aliases"
# ----------------------------------------------------------------------
# The writer sorts the aliases by name so that its output can be diffed, and
#   counts a location - not an alias - in 'FNF'/'FNH':  three locations, two of
#   which have at least one alias which was called
$COVER $LCOV_TOOL $LCOV_OPTS -o round.info -a a.info $IGNORE 2>&1 |
    tee round.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail round "lcov failed reading a multi-alias tracefile"
fi
checkFunctionRecords round round.info <<'EOF'
FNL:0,1,4
FNA:0,5,twice<char>
FNA:0,3,twice<int>
FNA:0,0,twice<long>
FNL:1,6,6
FNA:1,0,trivial
FNL:2,8,11
FNA:2,1,main
FNF:3
FNH:2
EOF

# ..and reading that back gives the same thing again
$COVER $LCOV_TOOL $LCOV_OPTS -o round2.info -a round.info $IGNORE 2>&1 |
    tee round2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail round "lcov failed on its own output"
elif ! diff -u round.info round2.info ; then
    fail round "a multi-alias tracefile does not round trip"
fi

# The summary counts aliases, because an alias is the symbol which was or was
#   not called:  5 aliases over 3 locations, 3 of them called.  '--filter
#   function' says to count locations instead, and then it is 3 and 2 - the same
#   numbers the writer put in 'FNF'/'FNH'
checkSummary round round.log \
    '  functions...: 60.0% (3 of 5 functions)'

$COVER $LCOV_TOOL $LCOV_OPTS -o merged_fn.info -a a.info --filter function \
    $IGNORE 2>&1 | tee merged_fn.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail filter_function "lcov failed with --filter function"
fi
checkSummary filter_function merged_fn.log \
    '  functions...: 66.7% (2 of 3 functions)'

# ----------------------------------------------------------------------
echo "*** 2. merge:  shared aliases add, unshared ones join"
# ----------------------------------------------------------------------
$COVER $LCOV_TOOL $LCOV_OPTS -o add.info -a a.info -a b.info $IGNORE 2>&1 |
    tee add.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail add "lcov failed merging two multi-alias tracefiles"
fi
# 'twice<int>' is 3+4 and 'twice<long>' is 0+6, 'twice<char>' and 'twice<short>'
#   each arrive from one side alone, and 'main' is 1+0
checkFunctionRecords add add.info <<'EOF'
FNL:0,1,4
FNA:0,5,twice<char>
FNA:0,7,twice<int>
FNA:0,6,twice<long>
FNA:0,2,twice<short>
FNL:1,6,6
FNA:1,0,trivial
FNA:1,0,trivial2
FNL:2,8,11
FNA:2,1,main
FNF:3
FNH:2
EOF

# ----------------------------------------------------------------------
echo "*** 3. --intersect and --subtract over an alias set"
# ----------------------------------------------------------------------
# Both operations are defined over coverpoints, and an alias is a coverpoint:
#   the intersection keeps the aliases both operands have, with the counts
#   summed, and drops the location on line 6 altogether - it is in both operands,
#   but they have no alias of it in common
$COVER $LCOV_TOOL $LCOV_OPTS -o inter.info a.info --intersect b.info \
    $IGNORE 2>&1 | tee inter.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail intersect "lcov --intersect failed"
fi
checkFunctionRecords intersect inter.info <<'EOF'
FNL:0,1,4
FNA:0,7,twice<int>
FNA:0,6,twice<long>
FNL:1,8,11
FNA:1,1,main
FNF:2
FNH:2
EOF

# ..and the difference keeps the aliases which are mine alone, with my counts.
#   'main' is the whole of the location on line 8, so that location goes; the
#   location on line 6 keeps 'trivial', because 'trivial2' is not mine
$COVER $LCOV_TOOL $LCOV_OPTS -o sub.info a.info --subtract b.info \
    $IGNORE 2>&1 | tee sub.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail subtract "lcov --subtract failed"
fi
checkFunctionRecords subtract sub.info <<'EOF'
FNL:0,1,4
FNA:0,5,twice<char>
FNL:1,6,6
FNA:1,0,trivial
FNF:2
FNH:1
EOF

# ----------------------------------------------------------------------
echo "*** 4. --erase-functions matching one alias of several"
# ----------------------------------------------------------------------
# The pattern is matched against each alias, and a match removes the whole
#   location - every alias of it, and the lines and branches inside it.  Match
#   'twice<char>' alone:  'twice<int>' and 'twice<long>' have to go too
$COVER $LCOV_TOOL $LCOV_OPTS -o erase.info -a a.info \
    --erase-functions 'twice<char>' $IGNORE 2>&1 | tee erase.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail erase "lcov --erase-functions failed"
fi
checkFunctionRecords erase erase.info <<'EOF'
FNL:0,6,6
FNA:0,0,trivial
FNL:1,8,11
FNA:1,1,main
FNF:2
FNH:1
EOF
if grep -q -F -e 'twice' erase.info ; then
    fail erase "an alias of the erased function survived:"
    grep -F -e 'twice' erase.info
fi

# ----------------------------------------------------------------------
echo "*** 5. --filter trivial removes every alias of the location"
# ----------------------------------------------------------------------
# 'trivial' has one alias, so the interesting half of this is the count the
#   filter reports:  it counts one instance and one coverpoint per alias removed
$COVER $LCOV_TOOL $LCOV_OPTS -o trivial.info -a a.info --filter trivial \
    $IGNORE 2>&1 | tee trivial.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail trivial "lcov --filter trivial failed"
fi
checkFunctionRecords trivial trivial.info <<'EOF'
FNL:0,1,4
FNA:0,5,twice<char>
FNA:0,3,twice<int>
FNA:0,0,twice<long>
FNL:1,8,11
FNA:1,1,main
FNF:2
FNH:2
EOF

# ----------------------------------------------------------------------
echo "*** 6. the exclude-region filter counts the aliases it removed"
# ----------------------------------------------------------------------
# An excluded region which contains a function reports how much was suppressed,
#   and the unit is the alias:  a three-alias location inside the region is
#   three suppressed function coverpoints, not one.  'r1.info' is the same
#   fixture with a single alias, and the two runs are compared against each
#   other so that the assertion does not depend on how the lines are counted
cat >proj/r.cpp <<'EOF'
// LCOV_EXCL_START
template<class T> T thrice(T x)
{
    return x + x + x;
}
// LCOV_EXCL_STOP

int r(void)
{
    return thrice(1);
}
EOF

cat >r.info <<'EOF'
TN:aliases
SF:proj/r.cpp
FNL:0,2,5
FNA:0,1,thrice<int>
FNA:0,2,thrice<long>
FNA:0,0,thrice<char>
FNL:1,8,11
FNA:1,1,r
FNF:2
FNH:2
DA:2,3
DA:4,3
DA:8,1
DA:10,1
LF:4
LH:4
end_of_record
EOF

# the same, with 'thrice' reduced to one alias
grep -v -e 'thrice<long>' -e 'thrice<char>' r.info |
    sed -e 's/^DA:2,3$/DA:2,1/' -e 's/^DA:4,3$/DA:4,1/' > r1.info

for mode in r r1 ; do
    $COVER $LCOV_TOOL $LCOV_OPTS -o ${mode}_filt.info -a $mode.info \
        --filter region $IGNORE 2>&1 | tee ${mode}_filt.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail region "lcov --filter region failed on $mode.info"
    fi
    if grep -q -F -e 'thrice' ${mode}_filt.info ; then
        fail region "an excluded function survived in ${mode}_filt.info:"
        grep -F -e 'thrice' ${mode}_filt.info
    fi
done
# 'Filter suppressions:' is followed by the filter name and its instance count
COUNT3=`grep -A2 -e '^  region:' r_filt.log | grep -o -E '[0-9]+ instance' |
    head -1 | cut -d' ' -f1`
COUNT1=`grep -A2 -e '^  region:' r1_filt.log | grep -o -E '[0-9]+ instance' |
    head -1 | cut -d' ' -f1`
if [ "x$COUNT3" == 'x' ] || [ "x$COUNT1" == 'x' ] ; then
    fail region "no 'region' filter summary was printed:"
    grep -A3 -e 'Filter suppressions' r_filt.log r1_filt.log
elif [ $(( $COUNT3 - $COUNT1 )) != 2 ] ; then
    fail region \
        "three aliases suppressed $COUNT3 and one suppressed $COUNT1: expected a difference of 2"
fi

# ----------------------------------------------------------------------
echo "*** 7. the inconsistent-data repair marks every alias hit"
# ----------------------------------------------------------------------
# A location whose lines are hit but whose aliases are all zero is inconsistent.
#   If the user ignores the message, lcov repairs it - and the repair has to
#   reach every alias, or the report says the symbol was never called on a line
#   it also says was executed
cat >fix.info <<'EOF'
TN:aliases
SF:proj/t.cpp
FNL:0,1,4
FNA:0,0,twice<int>
FNA:0,0,twice<long>
FNA:0,0,twice<char>
FNL:1,8,11
FNA:1,1,main
FNF:2
FNH:1
DA:1,7
DA:3,7
DA:8,1
DA:10,1
LF:4
LH:4
end_of_record
EOF

$COVER $LCOV_TOOL $LCOV_OPTS -o fixed.info -a fix.info \
    --ignore-errors inconsistent,unused,source 2>&1 | tee fix.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail fix "lcov failed on inconsistent function data"
fi
if ! grep -q -F -e "is not hit but line 1 is: function marked 'hit'" fix.log ; then
    fail fix "no repair message for the uncalled location:"
    grep -F -e 'inconsistent' fix.log
fi
checkFunctionRecords fix fixed.info <<'EOF'
FNL:0,1,4
FNA:0,7,twice<char>
FNA:0,7,twice<int>
FNA:0,7,twice<long>
FNL:1,8,11
FNA:1,1,main
FNF:2
FNH:2
EOF

# ----------------------------------------------------------------------
echo "*** 8. the alias table in the function view"
# ----------------------------------------------------------------------
# The aliases of a location are listed under it, and the same table is written
#   twice:  once keyed by name and once - the '-c' page - keyed by count
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_plain add.info $IGNORE \
    --function-coverage 2>&1 | tee plain.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail plain "genhtml failed on a multi-alias report"
fi
# The aliases of a location are listed under it, in name order on one page and in
#   ascending count order on the other - and the locations themselves are sorted
#   the same way, which is why the uncalled location comes first on the second
checkAliasRows plain "`find html_plain -name 't.cpp.func.html'`" <<'EOF'
trivial - 0
trivial2 - 0
twice<char> - 5
twice<int> - 7
twice<long> - 6
twice<short> - 2
EOF
checkAliasRows plain_c "`find html_plain -name 't.cpp.func-c.html'`" <<'EOF'
trivial - 0
trivial2 - 0
twice<short> - 2
twice<char> - 5
twice<long> - 6
twice<int> - 7
EOF
# ..and the uncalled alias is styled as uncovered where the called ones are not
PAGE=`find html_plain -name 't.cpp.func.html'`
if ! grep -q -F -e '<td class="coverFnAliasLo">0</td>' $PAGE ; then
    fail plain "the uncalled alias is not styled uncovered"
fi
if ! grep -q -F -e '<td class="coverFnAliasHi">7</td>' $PAGE ; then
    fail plain "a called alias is not styled covered"
fi

# '--suppress-aliases' says to show the location only
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_supp add.info $IGNORE \
    --function-coverage --suppress-aliases 2>&1 | tee supp.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail suppress "genhtml failed with --suppress-aliases"
else
    PAGE=`find html_supp -name 't.cpp.func.html'`
    if [ ! -f "$PAGE" ] ; then
        fail suppress "the function view was not written"
    elif grep -q -F -e 'coverFnAlias' $PAGE ; then
        fail suppress "--suppress-aliases still wrote the alias table:"
        grep -F -e 'coverFnAlias' $PAGE
    fi
fi

# '--show-proportion' adds the per-function line, branch and MC/DC rates to the
#   same table.  A rate belongs to the location and not to a symbol which was
#   compiled from it, so the alias rows leave those columns empty - all three of
#   them, which needs the report to have all three cover types in the function
cat >p.info <<'EOF'
TN:aliases
SF:proj/t.cpp
FNL:0,1,4
FNA:0,3,twice<int>
FNA:0,0,twice<long>
FNA:0,5,twice<char>
FNL:1,8,11
FNA:1,1,main
FNF:2
FNH:2
BRDA:3,0,0,5
BRDA:3,0,1,3
BRF:2
BRH:2
MCDC:3,2,t,5,0,x
MCDC:3,2,f,3,0,x
MCDC:3,2,t,4,1,y
MCDC:3,2,f,2,1,y
MCF:4
MCH:4
DA:1,8
DA:3,8
DA:8,1
DA:10,1
LF:4
LH:4
end_of_record
EOF

$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_prop p.info $IGNORE \
    --function-coverage --branch-coverage --mcdc-coverage --show-proportion \
    2>&1 | tee prop.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail proportion "genhtml failed with --show-proportion"
else
    PAGE=`find html_prop -name 't.cpp.func.html'`
    if [ ! -f "$PAGE" ] ; then
        fail proportion "the function view was not written"
    else
        # the location has a rate in each of the three columns..
        if [ 3 != `grep -A5 -F -e 'class="coverFn"><a href="t.cpp.gcov.html#L1"' \
            $PAGE | grep -c -E '^ *<td class=coverPer'` ] ; then
            fail proportion "the location does not have three rates:"
            grep -A5 -F -e 'class="coverFn"><a href="t.cpp.gcov.html#L1"' $PAGE
        fi
        # ..and each of the three alias rows has three empty ones instead
        if [ 9 != `grep -A5 -F -e 'class="coverFnAlias"><a href' $PAGE |
            grep -c -F -e '<td class="coverFn"></td>'` ] ; then
            fail proportion "an alias row does not have three empty rates:"
            grep -A5 -F -e 'class="coverFnAlias"><a href' $PAGE
        fi
    fi
fi

# ----------------------------------------------------------------------
echo "*** 9. every differential category of an alias"
# ----------------------------------------------------------------------
# The differential categorizer replaces each alias count with a (count, TLA)
#   pair, and which TLA it is depends on the alias' count in each of the two
#   reports and on whether the alias is in both of them at all.  All eight
#   answers are below, one per alias of 'twice':
#     <a> 0 -> 0 UBC   <b> 0 -> 5 GBC   <c> 3 -> 4 CBC   <d> 2 -> 0 LBC
#     <e> 0 -> gone EUB   <f> 7 -> gone ECB
#     <g> new, 0 UIC   <h> new, 9 GIC
# 'edited' is the other half:  it also has several aliases, but its body was
#   edited - so the category of each of its aliases is remapped from the baseline
#   vocabulary to the 'new code' one:
#     <p> 0 -> 0 UBC becomes UNC   <q> 3 -> 4 CBC becomes GNC
#     <r> 2 -> 0 stays LBC, because there is no 'lost new code'
cat >proj/d.cpp <<'EOF'
template<class T> T twice(T x)
{
    return x + x;
}

template<class T> T edited(T x)
{
    int n = x;
    return n + n;
}

int main(void)
{
    return twice(1) + edited(1);
}
EOF

cat >dbase.info <<'EOF'
TN:aliases
SF:proj/d.cpp
FNL:0,1,4
FNA:0,0,twice<a>
FNA:0,0,twice<b>
FNA:0,3,twice<c>
FNA:0,2,twice<d>
FNA:0,0,twice<e>
FNA:0,7,twice<f>
FNL:1,6,9
FNA:1,0,edited<p>
FNA:1,3,edited<q>
FNA:1,2,edited<r>
FNL:2,11,14
FNA:2,1,main
FNF:3
FNH:3
DA:1,12
DA:3,12
DA:6,5
DA:8,5
DA:11,1
DA:13,1
LF:6
LH:6
end_of_record
EOF

cat >dcurr.info <<'EOF'
TN:aliases
SF:proj/d.cpp
FNL:0,1,4
FNA:0,0,twice<a>
FNA:0,5,twice<b>
FNA:0,4,twice<c>
FNA:0,0,twice<d>
FNA:0,0,twice<g>
FNA:0,9,twice<h>
FNL:1,6,10
FNA:1,0,edited<p>
FNA:1,4,edited<q>
FNA:1,0,edited<r>
FNL:2,12,15
FNA:2,1,main
FNF:3
FNH:3
DA:1,18
DA:3,18
DA:6,4
DA:8,4
DA:9,4
DA:12,1
DA:14,1
LF:7
LH:7
end_of_record
EOF

# one statement became two, inside 'edited' - so 'twice' above it is untouched
#   and 'main' below it only moved
cat >d.udiff <<'EOF'
--- proj/d.cpp
+++ proj/d.cpp
@@ -6,4 +6,5 @@
 template<class T> T edited(T x)
 {
-    return x + x;
+    int n = x;
+    return n + n;
 }
EOF

$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_diff dcurr.info $IGNORE \
    --function-coverage --baseline-file dbase.info --diff-file d.udiff 2>&1 |
    tee diff.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail differential "genhtml failed on a differential multi-alias report"
fi
if ! check_tla_css html_diff ; then
    fail differential "unstyled TLA class in html_diff"
fi
PAGE=`find html_diff -name 'd.cpp.func.html'`
checkAliasRows differential "$PAGE" <<'EOF'
edited<p> UNC 0
edited<q> GNC 4
edited<r> LBC 0
twice<a> UBC 0
twice<b> GBC 5
twice<c> CBC 4
twice<d> LBC 0
twice<e> EUB 0
twice<f> ECB 7
twice<g> UIC 0
twice<h> GIC 9
EOF
# 'main' was hit before and after and its body did not change, which is 'CBC'.
#   It has one alias, so this is the leader row and not an alias row
if [ -f "$PAGE" ] && ! grep -A2 -F -e '>main</a></td>' $PAGE |
    grep -q -F -e '<td class="tlaCBC">CBC</td>' ; then
    fail differential "'main' is not in the baseline-covered category:"
    grep -A2 -F -e '>main</a></td>' $PAGE
fi

# The per-alias categories are also what the function bins are counted from:
#   eight aliases of 'twice' and three of 'edited', in one bin each, plus 'main'.
#   '--merge-aliases' says to count the location once instead, and then there are
#   just the three.  '--show-details' asks for the same bins per testcase, which
#   is a second reader of the same categories
for mode in split merged ; do
    if [ merged == $mode ] ; then
        EXTRA='--merge-aliases'
    else
        EXTRA=''
    fi
    $COVER $GENHTML_TOOL $GENHTML_OPTS -o html_$mode dcurr.info $IGNORE \
        --function-coverage --baseline-file dbase.info --diff-file d.udiff \
        --show-details $EXTRA 2>&1 | tee $mode.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail $mode "genhtml failed ($mode)"
        continue
    fi
    if [ merged == $mode ] ; then
        # 'twice' and 'main' were hit before and after and their bodies did not
        #   change, and 'edited' is the changed one
        EXPECT='CBC:2 GNC:1'
    else
        EXPECT='CBC:2 ECB:1 EUB:1 GBC:1 GIC:1 GNC:1 LBC:2 UBC:1 UIC:1 UNC:1'
    fi
    checkFunctionBins $mode $mode.log "$EXPECT"
    # the per-testcase table repeats the file's own bins, one row per testcase -
    #   named for the 'TN:' the data was read under
    if ! grep -r -q -F -e 'aliases' --include='index*.html' html_$mode ; then
        fail $mode "--show-details did not write the per-testcase row"
    fi
done

# ----------------------------------------------------------------------
echo "*** 10. --new-file-as-baseline remaps every alias category"
# ----------------------------------------------------------------------
# A file which is not in the baseline is 'included code', so an uncalled alias
#   of it is 'UIC' - which fails a coverage ratchet even though nothing was
#   added.  '--new-file-as-baseline' says to treat an old file as if it had been
#   in the baseline all along, which rewrites the category of every coverpoint
#   in it - aliases included, through the mutator, because an alias hands back a
#   copy of its differential pair in the XS backend
cat >dother.info <<'EOF'
TN:aliases
SF:proj/other.cpp
DA:1,1
LF:1
LH:1
end_of_record
EOF
printf 'int other(void) { return 0; }\n' > proj/other.cpp

$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_nfb dcurr.info $IGNORE \
    --function-coverage --baseline-file dother.info --new-file-as-baseline \
    --annotate-script `pwd`/annotate.pl --show-owners all \
    --ignore-errors annotate 2>&1 | tee nfb.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail nfb "genhtml failed with --new-file-as-baseline"
else
    # five uncalled aliases and four called ones, plus 'main'
    checkFunctionBins nfb nfb.log 'CBC:5 UBC:5'
    # 'UIC' becomes 'UBC' and 'GIC' becomes 'CBC', for the location and for
    #   every alias of it - so neither of the 'included' labels is left
    PAGE=`find html_nfb -name 'd.cpp.func.html'`
    checkAliasRows nfb "$PAGE" <<'EOF'
edited<p> UBC 0
edited<q> CBC 4
edited<r> UBC 0
twice<a> UBC 0
twice<b> CBC 5
twice<c> CBC 4
twice<d> UBC 0
twice<g> UBC 0
twice<h> CBC 9
EOF
    for cls in tlaUIC tlaGIC ; do
        if [ -f "$PAGE" ] && grep -q -F -e "$cls" $PAGE ; then
            fail nfb "'$cls' survived the remap:"
            grep -F -e "$cls" $PAGE
        fi
    done
fi

# ----------------------------------------------------------------------
echo "*** 11. a location with no line number is named by its first alias"
# ----------------------------------------------------------------------
# The writer checks the line number of each location as it goes, and a location
#   without one has no name of its own to complain about - so the message names
#   the first of its aliases in sorted order.  That is not the same thing as the
#   name of the location, which is the shortest of the alias names:  'twice<int>'
#   here, where the first alias is 'twice<char>'
cat >bogus.info <<'EOF'
TN:aliases
SF:proj/t.cpp
FNL:0,0,4
FNA:0,3,twice<int>
FNA:0,5,twice<char>
FNF:1
FNH:1
DA:1,8
DA:3,8
LF:2
LH:2
end_of_record
EOF

$COVER $LCOV_TOOL $LCOV_OPTS -a bogus.info -o bogus_out.info $IGNORE \
    --ignore-errors format 2>&1 | tee bogus.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail bogus "lcov failed on a location with no line number"
else
    if ! grep -q -F -e \
        "\"proj/t.cpp\": unexpected line number '0' for function twice<char>" \
        bogus.log ; then
        fail bogus "the message does not name the first alias:"
        grep -F -e 'unexpected line number' bogus.log
    fi
    # the message is ignorable, and then the record is written as it was read
    checkFunctionRecords bogus bogus_out.info <<'EOF'
FNL:0,0,4
FNA:0,5,twice<char>
FNA:0,3,twice<int>
FNF:1
FNH:1
EOF
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'aliases' $LOCAL_COVERAGE 0
fi

exit $STATUS
