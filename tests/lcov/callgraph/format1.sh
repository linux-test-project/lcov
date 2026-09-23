#! /usr/bin/env bash

# Call sites in the '.info' file:  the 'FNC:' record, and the reader and writer
# of it - part 1 of 3.
#
# The former monolithic 'format.sh' ran 20 scenarios over the same hand-written
# tracefiles, which is the longest single test in the suite under '--coverage'.
# The scenarios keep their original numbering here:  'format1.sh' runs 1 to 8,
# 'format2.sh' 9 to 14, 'format3.sh' 15 to 21, so a cross-reference to a section
# number still finds it.  The discussion of the record itself, the helpers and
# the two fixtures which more than one part reads are in 'setup_common.sh'; each
# part runs in its own working directory (format1.d), so the three cannot
# collide.

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf format1.d
    exit 0
fi

WORKDIR=format1.d
source ./setup_common.sh

# ----------------------------------------------------------------------
echo "*** 1. read and write:  byte for byte"
# ----------------------------------------------------------------------
# 'FNCF' counts sites and 'FNCH' the ones which were taken, both recomputed
#   from the records rather than read - so a fixture which comes back as expected
#   has asserted the reader, the writer and the totals at once.
# What a capture holds is not quite what a report keeps:  'a.info' calls one
#   function no file of it defines, and that site is dropped where the report is
#   assembled (section 16), leaving the 'c' flag in its place (section 18).  So
#   the first pass is 'a.info' in and 'ar.info' out
runLcov round --callgraph-coverage -a a.info -o round.info
if [ -f round.info ] && ! diff -u ar.info round.info ; then
    fail round "a tracefile with call sites was not resolved as expected"
fi

# ..and the second is byte for byte:  what a report writes it reads back
#   unchanged, there being nothing left in it to resolve
runLcov reround --callgraph-coverage -a ar.info -o reround.info
if [ -f reround.info ] && ! diff -u ar.info reround.info ; then
    fail reround "a resolved tracefile does not round trip"
fi

# '--callgraph' is the abbreviation, and it has to mean the same thing
runLcov abbrev --callgraph -a a.info -o abbrev.info
if [ -f abbrev.info ] && ! diff -u ar.info abbrev.info ; then
    fail abbrev "--callgraph is not --callgraph-coverage"
fi

# ----------------------------------------------------------------------
echo "*** 2. without the option the records are skipped"
# ----------------------------------------------------------------------
# A '.info' captured with call data is an ordinary '.info' to a run which did
#   not ask for the metric:  the records are dropped on the way in, not
#   rejected, and nothing is written back
runLcov nocallee -a a.info -o nocallee.info
if [ -f nocallee.info ] ; then
    if grep -q -E '^FNC' nocallee.info ; then
        fail nocallee "call records survived a run without --callgraph-coverage:"
        grep -E '^FNC' nocallee.info
    fi
    # ..and the rest of the function data is untouched
    if ! diff -u <(grep -E '^(FNL|FNA|FNF|FNH):' a.info) \
        <(grep -E '^(FNL|FNA|FNF|FNH):' nocallee.info) ; then
        fail nocallee "the function records changed"
    fi
fi

# ----------------------------------------------------------------------
echo "*** 3. merge:  the count of a site is the sum"
# ----------------------------------------------------------------------
runLcov merge --callgraph -a a.info -a a.info -o merge.info
# A site which was never taken stays untaken, so 'FNCH' does not move
checkCallRecords merge merge.info <<'EOF'
FNC:2,13,13,0,6,helper
FNC:2,13,13,1,0,other
FNC:2,13,31,0,4,helper
FNC:2,13,31,1,4,helper
FNCF:4
FNCH:3
EOF

# ----------------------------------------------------------------------
echo "*** 4. one location, several callees"
# ----------------------------------------------------------------------
# A virtual call dispatches to whichever override the object has, and a call in
#   a template body is compiled once per instantiation - so a single location
#   has more than one callee, and the two are told apart by the ordinal alone.
#   Each of them accumulates its own count, which is the whole point of keeping
#   the callee as payload rather than folding it into the key
cat >proj/v.cpp <<'EOF'
struct B { virtual int f(int x) { return x; } };
struct D : B { int f(int x) { return x + 1; } };

int dispatch(B* b, int n)
{
    return b->f(n);
}
EOF

cat >v1.info <<'EOF'
TN:format
SF:proj/v.cpp
FNL:0,1,1
FNA:0,5,B::f
FNL:1,2,2
FNA:1,0,D::f
FNL:2,4,7
FNA:2,5,dispatch
FNC:2,6,15,0,5,B::f
FNC:2,6,15,1,0,D::f
FNF:3
FNH:2
FNCF:2
FNCH:1
DA:1,5
DA:2,0
DA:4,5
DA:6,5
LF:4
LH:3
end_of_record
EOF

# a second run of the same build, which happened to take the other branch of
#   the dispatch every time
sed -e 's/^FNA:0,5,B::f$/FNA:0,0,B::f/' \
    -e 's/^FNA:1,0,D::f$/FNA:1,3,D::f/' \
    -e 's/^FNA:2,5,dispatch$/FNA:2,3,dispatch/' \
    -e 's/^FNC:2,6,15,0,5,B::f$/FNC:2,6,15,0,0,B::f/' \
    -e 's/^FNC:2,6,15,1,0,D::f$/FNC:2,6,15,1,3,D::f/' \
    -e 's/^DA:1,5$/DA:1,0/' -e 's/^DA:2,0$/DA:2,3/' \
    -e 's/^DA:4,5$/DA:4,3/' -e 's/^DA:6,5$/DA:6,3/' v1.info > v2.info

runLcov virtual --callgraph -a v1.info -a v2.info -o virtual.info
# neither target is lost, and each carries its own total
checkCallRecords virtual virtual.info <<'EOF'
FNC:2,6,15,0,5,B::f
FNC:2,6,15,1,3,D::f
FNCF:2
FNCH:2
EOF

# The ordinal is not a name:  it says which of the calls at one location this is,
#   and two producers of the same location need not agree on the numbering.  A
#   template instantiated in two translation units, an inline shared by two
#   objects, a comdat - the two definitions are aliases of one function and so
#   share one call site list, and each unit numbered the sites there from zero.
# So the same data, numbered the other way round, merges to the same answer:
#   the sites are matched by callee, and a numbering difference is neither an
#   error nor a change in what the report says.  Serial, because which input
#   becomes the accumulator is a property of the merge order, and that is what
#   decides which of the two callees ends up with ordinal 0
sed -e 's/^FNC:2,6,15,0,0,B::f$/FNC:2,6,15,1,0,B::f/' \
    -e 's/^FNC:2,6,15,1,3,D::f$/FNC:2,6,15,0,3,D::f/' v2.info > v3.info
runLcov swapped --callgraph -a v1.info -a v3.info -o swapped.info --parallel 1
checkCallRecords swapped swapped.info <<'EOF'
FNC:2,6,15,0,5,B::f
FNC:2,6,15,1,3,D::f
FNCF:2
FNCH:2
EOF

# ----------------------------------------------------------------------
echo "*** 5. a malformed record"
# ----------------------------------------------------------------------
# Each of these is one field of one record made wrong, so each of them names
#   the field which is wrong and the record it is in:  a '.info' file is
#   generated, so the only way to find the generator is from the message
bad()
{
    # bad name sedExpression
    sed -e "$2" a.info > $1.info
}

bad bad_index  's/^FNC:2,13,13,0,3,helper$/FNC:9,13,13,0,3,helper/'
bad bad_line   's/^FNC:2,13,13,0,3,helper$/FNC:2,0,13,0,3,helper/'
bad negative   's/^FNC:2,13,13,0,3,helper$/FNC:2,13,13,0,-3,helper/'
bad noninteger 's/^FNC:2,13,13,0,3,helper$/FNC:2,13,13,0,x,helper/'
bad nofield    's/^FNC:2,13,13,0,3,helper$/FNC:2,13,13,0,3/'
bad excess     's/^FNC:2,13,13,0,3,helper$/FNC:2,13,13,0,9,helper/'
bad mismatch   's/^FNC:2,13,13,1,0,other$/FNC:2,13,13,0,1,other/'
# an index which 'FNL:' declared and no 'FNA:' ever named
sed -e 's/^FNL:1,6,9$/FNL:1,6,9\nFNC:1,7,5,0,1,printf/' -e '/^FNA:1,0,other$/d' \
    a.info > noalias.info

checkFail bad_index \
    "\"bad_index.info\":9: unknown function index '9' in .info file record 'FNC:9,13,13,0,3,helper'" \
    --callgraph -a bad_index.info -o discard.info

checkFail noalias \
    "\"noalias.info\":6: function index '1' has no 'FNA:' record in .info file record 'FNC:1,7,5,0,1,printf'" \
    --callgraph -a noalias.info -o discard.info

checkFail bad_line \
    "\"bad_line.info\":9: unexpected call site line '0' in .info file record 'FNC:2,0,13,0,3,helper'" \
    --callgraph -a bad_line.info -o discard.info

# Each of those three is a record the reader cannot place, so ignoring the error
#   drops that one record and reads the rest of the file:  the alternative -
#   keeping a site whose caller, or whose line, is not known - would put data in
#   the report which no filter, no source view and no summary could account for
runWarn bad_index_ok \
    "unknown function index '9'" \
    --callgraph -a bad_index.info -o bad_index_ok.info --ignore-errors format
checkCallRecords bad_index_ok bad_index_ok.info <<'EOF'
FNC:2,13,13,1,0,other
FNC:2,13,31,0,2,helper
FNC:2,13,31,1,2,helper
FNCF:3
FNCH:2
EOF

# 'other' loses its 'FNA:', so it is not in the report at all and the two
#   surviving functions renumber - which is why the index is a per-file property
#   of the '.info' and never of the data.  Not being in the report also puts it
#   outside the boundary, so the call to it goes the way the call to 'printf'
#   does, and the three calls to 'helper' are all that is left
runWarn noalias_ok \
    "function index '1' has no 'FNA:' record" \
    --callgraph -a noalias.info -o noalias_ok.info --ignore-errors format
checkCallRecords noalias_ok noalias_ok.info <<'EOF'
FNC:1,13,13,0,3,helper
FNC:1,13,31,0,2,helper
FNC:1,13,31,1,2,helper
FNCF:3
FNCH:3
EOF

runWarn bad_line_ok \
    "unexpected call site line '0'" \
    --callgraph -a bad_line.info -o bad_line_ok.info --ignore-errors format
checkCallRecords bad_line_ok bad_line_ok.info <<'EOF'
FNC:2,13,13,1,0,other
FNC:2,13,31,0,2,helper
FNC:2,13,31,1,2,helper
FNCF:3
FNCH:2
EOF

# A count is a count:  the same arithmetic, and the same three complaints, as
#   every other one in the file - which is why the site is normalized where it
#   is stored and not where it is read
checkFail negative \
    "Unexpected negative call count '-3' for call site 13:13:0 in 'caller' of proj/a.c calling 'helper'" \
    --callgraph -a negative.info -o discard.info

checkFail noninteger \
    "Unexpected non-integer call count 'x' for call site 13:13:0 in 'caller' of proj/a.c calling 'helper'" \
    --callgraph -a noninteger.info -o discard.info

checkFail excess \
    "Unexpected excessive call count '9' for call site 13:13:0 in 'caller' of proj/a.c calling 'helper'" \
    --callgraph -a excess.info -o discard.info --rc excessive_count_threshold=8

# ..and an excessive count which is ignored is kept as it was read
runWarn excess_ok \
    "Unexpected excessive call count '9' for call site 13:13:0 in 'caller'" \
    --callgraph -a excess.info -o excess.info.out \
    --rc excessive_count_threshold=8 --ignore-errors excessive \
    --rc max_message_count=10
if [ -f excess.info.out ] &&
   ! grep -q -F -e 'FNC:2,13,13,0,9,helper' excess.info.out ; then
    fail excess_ok "the ignored count was not kept:"
    grep -E '^FNC' excess.info.out
fi

# The callee is the one field which can hold anything, so it is the last one:
#   a record without it is not a call site with an anonymous target, it is a
#   record this reader does not know
checkFail nofield \
    "unexpected .info file record 'FNC:2,13,13,0,3'" \
    --callgraph -a nofield.info -o discard.info

checkFail mismatch \
    "\"proj/a.c\":13: call site 13:13:0 in 'caller' calls 'helper' but also 'other'" \
    --callgraph -a mismatch.info -o discard.info

# ..and ignoring the mismatch keeps the first target and loses the second - so
#   one site fewer than the file has records for
runWarn mismatch_ok \
    "call site 13:13:0 in 'caller' calls 'helper' but also 'other'" \
    --callgraph -a mismatch.info -o mismatch_ok.info \
    --ignore-errors mismatch --rc max_message_count=10
checkCallRecords mismatch_ok mismatch_ok.info <<'EOF'
FNC:2,13,13,0,3,helper
FNC:2,13,31,0,2,helper
FNC:2,13,31,1,2,helper
FNCF:3
FNCH:3
EOF

# A count which was written by a tool doing arithmetic in floating point is
#   truncated, exactly as 'FNDA:' is, and says nothing about it
bad float 's/^FNC:2,13,13,0,3,helper$/FNC:2,13,13,0,3.7,helper/'
runLcov float --callgraph -a float.info -o float.info.out
if [ -f float.info.out ] &&
   ! grep -q -F -e 'FNC:2,13,13,0,3,helper' float.info.out ; then
    fail float "a fractional count was not truncated:"
    grep -E '^FNC' float.info.out
fi

# ----------------------------------------------------------------------
echo "*** 6. genhtml reads it too"
# ----------------------------------------------------------------------
# genhtml is where the callee-side view is built:  one 'resolveCallSites' in the
#   parent, after the merge and the filters and before any summary.  The display
#   of it is 'differential.sh'; what is asserted here is that the resolution runs
#   and the report is still produced - which is exactly the failure mode a
#   derived view invites, since the metric it feeds would read 0/0 rather than
#   die if the pass were skipped
runGenhtml genhtml --callgraph -o html a.info
if [ ! -f html/index.html ] ; then
    fail genhtml "no report was written"
fi

# In differential mode the baseline has call data of its own and is resolved
#   separately, because a site is categorized by comparing the two.  Comparing a
#   report against itself with no diff is exactly the case genhtml warns about,
#   and that warning is not what this is testing
runGenhtmlWarn genhtml_base \
    "Specified --baseline-file without --diff-file" \
    --callgraph --baseline-file a.info -o html_base a.info
if [ ! -f html_base/index.html ] ; then
    fail genhtml_base "no differential report was written"
fi

# ----------------------------------------------------------------------
echo "*** 7. the unknown count '-'"
# ----------------------------------------------------------------------
# A capture can know that the compiled code makes a call and have no count for
#   it:  gcov produced no arc, which is what an inlined call looks like from
#   there.  '-' says that, exactly as it does in a 'BRDA:' record, and it is a
#   third state and not a zero - "not measured" is a different claim from "the
#   tests never made this call", and writing 0 would put the second in the
#   report on the strength of the first.
# So the site is in 'FNCF' and never in 'FNCH':  it counts against the rate,
#   because a call which may never have been made cannot be reported as made,
#   and the report says which of the two it is rather than picking one.
# Read unconditionally, not under '--callgraph-partial-data':  that option decides
#   what a *capture* keeps, and by the time the record exists the decision has
#   been made - a run which refused to read it would fail on its own data.
# 13:13 is a location with one known and one unknown destination and 13:25 one
#   with nothing but the unknown, which is the distinction the report has to
#   draw:  the first location was reached and the second may not have been
cat >u.info <<'EOF'
TN:format
SF:proj/a.c
FNL:0,1,4
FNA:0,7,helper
FNL:1,6,9
FNA:1,0,other
FNL:2,11,15
FNA:2,1,caller
FNC:2,13,13,0,3,helper
FNC:2,13,13,1,-,other
FNC:2,13,25,0,-,other
FNC:2,13,31,0,2,helper
FNC:2,14,5,0,1,printf
FNF:3
FNH:2
FNCF:5
FNCH:3
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

# '-' is not a count, so it is not normalized like one:  it goes through the
#   reader, the writer and the totals as itself.  The call to 'printf' leaves the
#   boundary here as it does everywhere else, so the expectation is the fixture
#   with that site resolved away - see section 16.  'helper' was entered 7
#   times and its two sites account for 5, and 'caller' is called by no site
#   at all, so both have a deduced caller.  'other' was never entered, so
#   there is nothing for its two unknown sites to leave unaccounted for
sed -e '/^FNC:2,14,5,0,1,printf$/d' -e 's/^FNL:2,11,15$/FNL:2c,11,15/' \
    -e 's/^FNA:0,7,helper$/FNA:0d,7,helper/' \
    -e 's/^FNA:2,1,caller$/FNA:2d,1,caller/' \
    -e 's/^FNCF:5$/FNCF:4/' -e 's/^FNCH:3$/FNCH:2/' u.info > ur.info
runLcov unknown --callgraph -a u.info -o unknown.info
if [ -f unknown.info ] && ! diff -u ur.info unknown.info ; then
    fail unknown "a tracefile with an unknown call count does not round trip"
fi

# Merging is a lattice with 'unknown' at the bottom:  a measurement absorbs it,
#   because one capture having a count for the call is all it takes to know
#   there was a call there to count.  Two runs of the same build merge here, so
#   'other' at 13:13 is unknown in both and stays unknown, and nothing about the
#   totals moves
runLcov unknown_self --callgraph -a u.info -a u.info -o unknown_self.info
checkCallRecords unknown_self unknown_self.info <<'EOF'
FNC:2,13,13,0,6,helper
FNC:2,13,13,1,-,other
FNC:2,13,25,0,-,other
FNC:2,13,31,0,4,helper
FNCF:4
FNCH:2
EOF

# ..and against a capture which did have the counts, the known value wins in
#   both directions.  'a.info' has 13:13:1 as a measured 0, so that site becomes
#   a call which was measured and never made - which is a claim, where '-' was
#   the absence of one.  13:25:0 is in neither of a.info's records, so it stays
#   unknown:  absorbing is about the same site, not about the file
for order in known_first known_last ; do
    if [ $order == known_first ] ; then
        ORDER_ARGS="-a a.info -a u.info"
    else
        ORDER_ARGS="-a u.info -a a.info"
    fi
    runLcov $order --callgraph $ORDER_ARGS -o $order.info
    checkCallRecords $order $order.info <<'EOF'
FNC:2,13,13,0,6,helper
FNC:2,13,13,1,0,other
FNC:2,13,25,0,-,other
FNC:2,13,31,0,4,helper
FNC:2,13,31,1,2,helper
FNCF:5
FNCH:3
EOF
done

# genhtml has to say which of the two states a site is in, and it cannot do it
#   by testing the count:  '-' is a non-empty string, so it is *true* in Perl,
#   and every place which asked 'was this taken?' directly would answer yes for
#   a call nobody measured.  Hence the third rendering, in both views
runGenhtml genhtml_unknown --callgraph -o html_unknown u.info
if [ ! -f html_unknown/proj/a.c.callees.html ] ; then
    fail genhtml_unknown "no call site view was written"
else
    # the count cell of the unknown site, which says '-' and says why on hover
    if ! grep -q -F -e \
        'title="the compiler recorded this call and the coverage data carries no count for it - click for the next missed call">-<' \
        html_unknown/proj/a.c.callees.html ; then
        fail genhtml_unknown "the unknown count was not rendered as '-':"
        grep -o -E '<td[^>]*>[-0-9]+</td>' html_unknown/proj/a.c.callees.html
    fi
    # ..and the location cell of a site whose every destination is unknown is
    #   coloured as not taken - no test is known to have made the call.  The one
    #   at 13:13 is not:  a location with a destination which was reached is a
    #   location which was reached, so it stays 'Hi'
    if [ 1 != `grep -c -F -e 'class="coverCallgraphLo" id="site_' \
                    html_unknown/proj/a.c.callees.html` ] ; then
        fail genhtml_unknown "expected exactly one not-taken call location:" \
            `grep -o -E 'class="coverCallgraph[A-Za-z]*"' \
                  html_unknown/proj/a.c.callees.html | sort | uniq -c`
    fi
    # ..and the count cell of each of the two unknown sites is coloured by its
    #   category - the not-taken one - and is on the tour of the calls which were
    #   not taken, as a count of zero would be.  The source view below still
    #   marks the site as unknown rather than as missed
    if [ 2 != `grep -c -F -e \
        '<td class="tlaUNC"><a href="#top" title="the compiler recorded' \
                    html_unknown/proj/a.c.callees.html` ] ; then
        fail genhtml_unknown "expected two not-taken unknown count cells:" \
            `grep -o -E '<td class="[A-Za-z]*"><a [^>]*title="the compiler' \
                  html_unknown/proj/a.c.callees.html | sort | uniq -c`
    fi
    if grep -q -F -e 'coverCallgraphUnknown' \
            html_unknown/proj/a.c.callees.html ; then
        fail genhtml_unknown "an unknown count cell is still uncoloured"
    fi
fi
if [ ! -f html_unknown/proj/a.c.gcov.html ] ; then
    fail genhtml_unknown "no source view was written"
else
    # and in the source view, the identifier at the unknown location - which is
    #   'other' at 13:25.  A dashed underline rather than the 'not taken'
    #   background:  the site is not known to have been missed
    if ! grep -q -F -e 'class="callSiteUnknown"' \
            html_unknown/proj/a.c.gcov.html ; then
        fail genhtml_unknown "the unknown call site was not marked in the" \
            "source view:" \
            `grep -o -E 'class="callSite[A-Za-z]*"' \
                  html_unknown/proj/a.c.gcov.html | sort | uniq -c`
    fi
fi

# ----------------------------------------------------------------------
echo "*** 8. the flag field of 'FNA:':  linkage, and callers which cannot be named"
# ----------------------------------------------------------------------
# Two things about a symbol are neither a count nor a location, so no count
#   record can hold them:  that it has external linkage, and that something the
#   report cannot name called it.  They are flag letters on the 'FNA:' record of
#   the alias they are about - 'FNA:0ex,4,f' - and they ride on the index rather
#   than in a field of their own because the alias name is that record's last
#   field and takes the rest of the line, commas and all.
#
# 'e' - external linkage.  Resolution is by symbol name, so a name which more
#   than one file defines cannot be resolved from the calling file alone, and an
#   *unrelated* 'static' of the same name in some third file must not void a
#   perfectly good call to the global.  A call from a file which defines no
#   function of that name must have gone to one which is reachable from outside
#   its own file, so the static candidates are excluded outright.
# 'x' - called from a site which has no record.  See section 9 for what a reader
#   does with it.
#
# Absent means "not asserted" - which is what a file written by a tool that does
#   not know these flags says, and what a comdat says for 'e', since an inline
#   function is file-qualified in the callgraph info too.  'stat.c' does not assert
#   linkage for its 'f' and 'call.c' does not for 'h':  absence is not a claim,
#   so a fixture need not carry the flag for every symbol which would in fact
#   have it.
# The fixtures are 'link.info' and 'xlink.info', built by 'setup_common.sh'
#   because section 9 reads them as well.

# The flags are written where they are read - as the leading field of the same
#   'FNA:' record - so each fixture is its own round trip expectation
for f in link xlink ; do
    runLcov ${f}_round --callgraph -a $f.info -o ${f}_round.info
    if [ -f ${f}_round.info ] && ! diff -u $f.info ${f}_round.info ; then
        fail ${f}_round "a tracefile with function flags does not round trip"
    fi
done

# The flags are recorded for the sake of callgraph coverage and read by nothing
#   else, so they go the way 'FNC:' goes:  a run which did not ask for the metric
#   drops them, and a report which asked for no call data does not grow fields
runLcov link_nocallee -a xlink.info -o link_nocallee.info
if [ -f link_nocallee.info ] &&
   grep -q -E '^FNA:[0-9]+[a-z]' link_nocallee.info ; then
    fail link_nocallee "function flags survived a run without --callgraph-coverage"
fi

# Both facts travel with the definition rather than with the run which captured
#   it, which is what makes them correct under 'lcov -a' of captures taken
#   separately:  merging a file which asserts a flag with one which does not must
#   keep it, in either order, since a symbol cannot have two linkages and a call
#   which was made cannot become one which was not.
# Only the index and the flags are compared:  the counts are summed by the merge,
#   which is the one thing here that is *not* supposed to be preserved
sed -e 's/^\(FNA:[0-9]\+\)[a-z]\+,/\1,/' xlink.info > nolink.info
if ! diff -q <(grep -c -E '^FNA:' xlink.info) \
             <(grep -c -E '^FNA:' nolink.info) >/dev/null ||
   grep -q -E '^FNA:[0-9]+[a-z]' nolink.info ; then
    fail nolink "the unflagged fixture was not built"
fi
for order in link_first link_last ; do
    if [ $order == link_first ] ; then
        ORDER_ARGS="-a xlink.info -a nolink.info"
    else
        ORDER_ARGS="-a nolink.info -a xlink.info"
    fi
    runLcov $order --callgraph $ORDER_ARGS -o $order.info
    if [ -f $order.info ] &&
       ! diff -u <(grep -o -E '^FNA:[0-9]+[a-z]*' xlink.info) \
                 <(grep -o -E '^FNA:[0-9]+[a-z]*' $order.info) ; then
        fail $order "a function flag was lost in a merge"
    fi
done

# ..and without the linkage flag the call is ambiguous again, which is the defect
#   that flag exists to fix.  Said out loud, because it is a caller the callee's
#   page should have listed and does not - a loss of information rather than the
#   ordinary shape of a call out of the report, which stays silent.  A warning
#   and not an error, since the caller-side totals are unaffected - and so not
#   ignored here:  an ignored warning is a suppressed one, and the point of this
#   one is that it gets said
runWarn nolink \
    "\"proj/call.c\":3: call to 'f' cannot be resolved:  2 file(s) define that name, this file defines none of them, and none of them is recorded as having external linkage" \
    --callgraph -a nolink.info -o nolink_out.info --rc max_message_count=10

# A letter this reader does not know.  A format error and not a silently ignored
#   field:  every letter is an assertion, so one which is not understood is data
#   which would be lost without saying so
sed -e 's/^FNA:0e,4,f$/FNA:0eq,4,f/' link.info > link_badflag.info
checkFail link_badflag \
    "\"link_badflag.info\":20: unknown function flag 'q' in .info file record 'FNA:0eq,4,f'" \
    --callgraph -a link_badflag.info -o discard.info

# Dropping just that letter is the right recovery:  the flags say nothing about
#   the count, so the alias is good data whatever the letter meant - and the
#   letters which ARE understood still apply
runWarn link_badflag_ok \
    "unknown function flag 'q'" \
    --callgraph -a link_badflag.info -o link_badflag_ok.info \
    --ignore-errors format --rc max_message_count=10
if [ -f link_badflag_ok.info ] ; then
    if ! grep -q -F -x -e 'FNA:0e,4,f' link_badflag_ok.info ; then
        fail link_badflag_ok "the alias of the bad record was not kept:" \
            `grep -E '^FNA:' link_badflag_ok.info`
    fi
    if grep -q -F -e 'q' link_badflag_ok.info ; then
        fail link_badflag_ok "the unknown letter was written back out"
    fi
fi

# The 'x' letter may carry a count:  the number of calls the call sites it
#   stands for made.  'f' is entered 4 times and the site in 'call.c' accounts
#   for all of them, so the 3 its flag counts leave nothing to deduce;  'g' is
#   entered 6 times, the site accounts for 2 and the flag for 3, so 1 is deduced
#   and the 'd' is written after the count.  Each is its own round trip
sed -e 's/^FNA:0ex,4,f$/FNA:0ex3,4,f/' -e 's/^FNA:1ed,6,g$/FNA:1ex3d,6,g/' \
    xlink.info > xcount.info
if [ 2 != `grep -c -E '^FNA:[0-9]ex3d?,' xcount.info` ] ; then
    fail xcount "the counted-flag fixture was not built"
fi
runLcov xcount_round --callgraph -a xcount.info -o xcount_round.info
if [ -f xcount_round.info ] && ! diff -u xcount.info xcount_round.info ; then
    fail xcount_round "a flag with a count does not round trip"
fi

# ..and where the site and the flag together account for every call there is
#   no 'd', whatever the record which was read said:  the letter is computed
#   from the counts when the report is written, and 4 external calls plus the 2
#   of the site are all 6 of 'g'
sed -e 's/^FNA:1ex3d,6,g$/FNA:1ex4d,6,g/' xcount.info > xall.info
runLcov xall --callgraph -a xall.info -o xall_out.info
if [ -f xall_out.info ] && ! grep -q -F -x -e 'FNA:1ex4,6,g' xall_out.info ; then
    fail xall "external and internal callers which account for every call" \
        "still deduce one:" `grep -E '^FNA:1' xall_out.info`
fi

# A merge sums the counts, as it sums the counts of the sites the flag stands
#   for:  'g' is then entered 12 times, its sites account for 4 and the flags
#   for 6, so 2 are deduced.  A bare 'x' - a count which is not known - beside a
#   known one adds nothing to it, as a '-' site count does, and a side with no
#   flag at all contributes nothing
runLcov xcount_merge --callgraph -a xcount.info -a xcount.info \
    -o xcount_merge.info
runLcov xcount_bare --callgraph -a xlink.info -a xcount.info \
    -o xcount_bare.info
for pair in 'xcount_merge:FNA:0ex6,8,f FNA:1ex6d,12,g' \
            'xcount_bare:FNA:0ex3,8,f FNA:1ex3d,12,g' ; do
    label=${pair%%:*}
    if [ -f $label.info ] ; then
        got=`grep -E '^FNA:[01]e' $label.info | head -2 | tr '\n' ' '`
        if [ "${pair#*:} " != "$got" ] ; then
            fail $label "expected '${pair#*:}' but got '$got'"
        fi
    fi
done

# Only 'x' carries a count:  digits after any other letter are not a count of
#   anything, and are the unknown flag they spell
sed -e 's/^FNA:0e,4,f$/FNA:0e5,4,f/' link.info > link_digitflag.info
checkFail link_digitflag \
    "unknown function flag 'e5' in .info file record 'FNA:0e5,4,f'" \
    --callgraph -a link_digitflag.info -o discard.info

# ..and the report agrees about which definition a site calls.  Each of three
#   files has its own 'static' 'helper' and calls it, so the callee cell of each
#   site leads to the callers page of its own file and not to whichever file the
#   report happened to read first.  Three definitions, not two:  the second one is
#   what moves the name into genhtml's by-file index, and the third has to find it
#   already there
mkdir -p proj
for u in sa sb sc ; do
    cat >proj/$u.c <<EOF
static int helper(int x)
{
    return x + 1;
}

int use_$u(int n)
{
    return helper(n);
}
EOF
    cat <<EOF
TN:format
SF:proj/$u.c
FNL:0,1,4
FNA:0,1,helper
FNL:1,6,9
FNA:1e,1,use_$u
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
done > static_fn.info
runGenhtml statics_html --callgraph -o statics_html static_fn.info
for u in sa sb sc ; do
    CALLEES=statics_html/proj/$u.c.callees.html
    if [ ! -f $CALLEES ] ; then
        fail statics_html "no call site view was written for $u.c"
    elif [ "x`grep -o -E 'href=\"[^\"]*callers.html#func_helper\"' $CALLEES`" != \
           "xhref=\"../proj/$u.c.callers.html#func_helper\"" ] ; then
        fail statics_html "the call in $u.c does not lead to its own 'helper':" \
            `grep -o -E 'href="[^"]*callers.html#func_helper"' $CALLEES`
    fi
done

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'format_1' $LOCAL_COVERAGE 0
fi

exit $STATUS
