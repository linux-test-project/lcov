#!/bin/bash

# 'merge_continuation_lines':  a line coverpoint on a line which only
#   continues a statement is removed if its count is 0, or if both it and the
#   statement's first line (or, if that has no line coverpoint, its last) are
#   hit and its count is less than or equal to that line's - in the summary
#   and in each testcase.  The branch and MC/DC data of the line is then moved
#   to that line (see also tests/lcov/branchmerge).
# The sources are never compiled; the '.info' files are written here, by hand.
#   The lines of 'c.c' with a count of 0, and what is expected of each:
#      4,5  later lines of an expression                 merged into 3
#      7    later line of an 'if' condition              merged into 6
#     10    no line of the statement is hit              merged into 9
#     16    the start line of a function                 retained
#     20    an exclusion marker in the statement         retained
#     22    has branch data                              merged into 21
#   The lines of 'c.c' which are hit:
#     12    a smaller count than line 11's               merged into 11
#     29    the same count as line 28                    merged into 28
#     31    the same count as line 30, and branch data   merged into 30
#     33    the same summary count as line 32, but a
#           greater count in one testcase                retained
#     41    the condition of a 'for' loop:  a greater count
#           than line 40's                               retained
#     42    the increment of the 'for' loop:  a smaller count
#           than line 41's                               merged into 41
#   The statement which a line coverpoint stands for is recorded as its span -
#   the optional last field of its 'DA' record.  A statement whose lines cannot
#   all be merged is partitioned into segments, each with a span of its own:
#   16-18 (line 18 is hit and line 16 is not), 32-33 and 40-42.  The opening
#   brace of a function, which has no coverpoint, is not part of the statement
#   of its declaration:  so 1, 26 and 37 have no span.
#   Line 30 has branches of its own, none of which is taken:  they are checked
#   together with those of line 31 once line 31 is merged.
#   'x.xs' is an XSUB with the same data as lines 30 and 31:  the 'CODE:' line
#   ends the declaration before the statement.
#   The lines of 'p.pl' with a count of 0:
#      6    a 'foreach' list which holds '//' and a 'sort' block, and which
#           has branch data                              merged into 5
#     11    the operand of a division                    merged into 10
#     13    a regular expression                         retained
#   With '--callgraph', a call written on a line which has no line coverpoint -
#   because the line was merged, or because it never had one - is allocated to
#   the statement's line, and keeps the line and column it is written at.  The
#   calls in function 'h' of 'c.c':
#     27:1  on the function's opening brace              left alone
#     28:11 on a line which keeps its coverpoint         left alone
#     29:13 on a merged line                             allocated to 28
#     31:10 on a merged line                             allocated to 30
#     33:9  on a line which keeps its coverpoint         left alone
#   A call to 'strlen', which no file of the report defines, is removed.
#   At the end of the run, the number of continuation lines merged and the
#   number of statement lines they were merged into are reported - unless
#   '-q -q'.
#   In a differential report whose baseline was captured without the merge and
#   whose current data was captured with it, the continuation lines of the
#   baseline are folded into their statement lines - with their branch and
#   MC/DC data, the statement line keeping the greater count - before the two
#   are compared.

set +x

source ../../common.tst

rm -rf *.log *.json *.info *.in *.raw *.diff cg_html cg_lost_html fold_html \
    fold.c fold_mcdc_html

clean_cover

if [[ 1 == "$CLEAN_ONLY" ]] ; then
    exit 0
fi

LCOV_OPTS="--branch $PARALLEL $PROFILE --ignore inconsistent"
LINEMERGE='--rc merge_continuation_lines=1'
STATUS=0

fail()
{
    echo "ERROR ($1): $2"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

# write a '.info' file from coverpoint records:  the found/hit records which
#   close each section are computed here
mkinfo()
{
    awk -F'[:,]' '
/^end_of_record/ {
    if (fnf) print "FNF:" fnf "\nFNH:" fnh
    if (fncf) print "FNCF:" fncf "\nFNCH:" fnch
    if (lf) print "LF:" lf "\nLH:" lh
    if (brf) print "BRF:" brf "\nBRH:" brh
    if (mcf) print "MCF:" mcf "\nMCH:" mch
    print
    fnf = fnh = fncf = fnch = lf = lh = brf = brh = mcf = mch = 0
    next
}
/^FNDA:/ { ++fnf; if ($2 > 0) ++fnh }
/^FNA:/  { ++fnf; if ($3 > 0) ++fnh }
/^FNC:/  { ++fncf; if ($6 != "-" && $6 > 0) ++fnch }
/^DA:/   { ++lf; if ($3 > 0) ++lh }
/^BRDA:/ { ++brf; if ($5 != "-" && $5 > 0) ++brh }
/^MCDC:/ { ++mcf; if ($5 > 0) ++mch }
{ print }' > $1
}

# run label lcov-args...
run()
{
    local label=$1
    shift
    $COVER $LCOV_TOOL $LCOV_OPTS -o $label.info "$@" > $label.log 2>&1
    if [ 0 != $? ] ; then
        cat $label.log
        fail $label "unexpected lcov failure"
    fi
}

# the lines of source file $2 which have record $1 in testcase $4 (any
#   testcase if empty) of .info file $3, in order
lines()
{
    awk -F'[:,]' -v rec=$1 -v file=$2 -v tn="$4" '
/^TN:/ { test = $2 }
/^SF:/ { mine = ($2 == file && (tn == "" || tn == test)) }
mine && $1 == rec { print $2 }' $3 | sort -n | uniq | tr '\n' ' ' |
        sed -e 's/ $//'
}

# the value of summary record $1 of source file $2 in each testcase of .info
#   file $3
summary()
{
    awk -F: -v rec=$1 -v file=$2 '
/^SF:/ { mine = ($2 == file) }
mine && $1 == rec { print $2 }' $3 | uniq
}

# the call sites of source file $2 in testcase $4 of .info file $3 which have
#   a statement line, as 'line^statement', in order
statements()
{
    awk -F'[:,^]' -v file=$1 -v tn="$3" '
/^TN:/ { test = $2 }
/^SF:/ { mine = ($2 == file && tn == test) }
mine && /^FNC:[0-9]+\^/ { print $4 "^" $3 }' $2 | sort -n | tr '\n' ' ' |
        sed -e 's/ $//'
}

# the statement spans of source file $1 in testcase $3 of .info file $2, as
#   'first-last', in order
spans()
{
    awk -F'[:,]' -v file=$1 -v tn="$3" '
/^TN:/ { test = $2 }
/^SF:/ { mine = ($2 == file && tn == test) }
mine && /^DA:/ && $5 != "" { print $2 "-" $5 }' $2 | sort -n | tr '\n' ' ' |
        sed -e 's/ $//'
}

# the lines of source file $2 which message $3 is about, in log $1
said()
{
    grep -F -e "$3" $1 | grep -o "\"$2\":[0-9]*" | cut -d: -f2 | sort -n |
        uniq | tr '\n' ' ' | sed -e 's/ $//'
}

# expect label what actual expected
expect()
{
    if [ "$3" != "$4" ] ; then
        fail $1 "$2: '$3', expected '$4'"
    fi
}

MERGED='merged continuation line coverpoint into statement line'
PARTITIONED='partitioned into'
HIT_NO_BRANCH='line is hit but no branches on line have been evaluated'
# the totals in the summary at the end of the run
TOTALS='Merged [0-9]* continuation line'

# the summary totals in log $1
totals()
{
    grep -o 'Merged [0-9]* continuation lines\? into [0-9]* statement lines\?' $1
}

# ----------------------------------------------------------------------
# C:  testcases 't1' and 't2' have the same data
# ----------------------------------------------------------------------
for tn in t1 t2 ; do
    if [ $tn == t1 ] ; then
        L32=2
        L33=1
    else
        L32=1
        L33=2
    fi
    cat <<EOF
TN:$tn
SF:c.c
FN:1,14,f
FNDA:2,f
FN:16,24,g
FNDA:2,g
FN:26,35,h
FNDA:3,h
FN:37,45,k
FNDA:1,k
DA:1,2
DA:3,2
DA:4,0
DA:5,0
DA:6,2
DA:7,0
DA:8,1
DA:9,0
DA:10,0
DA:11,2
DA:12,1
DA:13,2
DA:16,0
DA:18,2
DA:19,2
DA:20,0
DA:21,2
DA:22,0
DA:23,2
DA:26,3
DA:28,3
DA:29,3
DA:30,3
DA:31,3
DA:32,$L32
DA:33,$L33
DA:34,3
DA:37,1
DA:39,1
DA:40,1
DA:41,6
DA:42,5
DA:43,5
DA:44,1
BRDA:22,0,0,-
BRDA:22,0,1,-
BRDA:30,0,0,0
BRDA:30,0,1,0
BRDA:31,0,0,3
BRDA:31,0,1,0
BRDA:41,0,0,5
BRDA:41,0,1,1
end_of_record
EOF
done | mkinfo c.info

ALL='1 3 4 5 6 7 8 9 10 11 12 13 16 18 19 20 21 22 23 26 28 29 30 31 32 33 34 37 39 40 41 42 43 44'
KEPT='1 3 6 8 9 11 13 16 18 19 20 21 23 26 28 30 32 33 34 37 39 40 41 43 44'

run off -a c.info -v
expect off 'merged' "`said off.log c.c "$MERGED"`" ''
expect off 'result' "`lines DA c.c off.info`" "$ALL"
expect off 'inconsistent' "`said off.log c.c "$HIT_NO_BRANCH"`" 30
expect off 'totals' "`grep -c "$TOTALS" off.log`" 0

# the branch data of lines 22 and 31 is moved to 21 and 30 after the line
#   merge
run cline -a c.info $LINEMERGE -v
expect cline 'merged' "`said cline.log c.c "$MERGED"`" '4 5 7 10 12 22 29 31 42'
# 9 lines, into 3 6 9 11 21 28 30 41
expect cline 'totals' "`totals cline.log`" \
    'Merged 9 continuation lines into 8 statement lines'
expect cline 'anchor' \
    "`grep -c -F '"c.c":4: merged continuation line coverpoint into statement line 3' cline.log`" 1
for tn in t1 t2 ; do
    expect cline "result $tn" "`lines DA c.c cline.info $tn`" "$KEPT"
done
expect cline 'LF' "`summary LF c.c cline.info`" 25
expect cline 'LH' "`summary LH c.c cline.info`" 22
expect cline 'spans' "`spans c.c cline.info t1`" \
    '3-5 6-7 9-10 11-12 16-17 21-22 28-29 30-31 41-42'
expect cline 'partitioned' "`said cline.log c.c "$PARTITIONED"`" '16 32 40'
# no spans unless the option is on - and the spans of the input are kept
expect off 'spans' "`spans c.c off.info t1`" ''
run cline_off -a cline.info -v
expect cline_off 'spans' "`spans c.c cline_off.info t1`" \
    '3-5 6-7 9-10 11-12 16-17 21-22 28-29 30-31 41-42'
expect cline 'branches' "`lines BRDA c.c cline.info`" '21 30 41'
expect cline 'inconsistent' "`said cline.log c.c "$HIT_NO_BRANCH"`" 21

# the merge is done in a child process even though no filter is enabled, and
#   its result is handed back
LCOV_FORCE_PARALLEL=1 run cline_fork -a c.info $LINEMERGE --parallel 2 -v
expect cline_fork 'forked' "`grep -c 'Filter: chunkSize' cline_fork.log`" 1
expect cline_fork 'merged' "`said cline_fork.log c.c "$MERGED"`" \
    '4 5 7 10 12 22 29 31 42'
diff cline.info cline_fork.info > cline_fork.diff ||
    fail cline_fork "result differs from the serial merge"
expect cline_fork 'totals' "`totals cline_fork.log`" \
    'Merged 9 continuation lines into 8 statement lines'

# '-q -q' suppresses the totals
run cline_quiet -a c.info $LINEMERGE -q -q
expect cline_quiet 'totals' "`grep -c "$TOTALS" cline_quiet.log`" 0

# a baseline without the merge against a current with it, of the same source:
#   the baseline's continuation lines are folded into their statement lines -
#   with their branches - so that the unchanged code is unchanged.  No line is
#   excluded, no branch is lost and no function is new
rm -rf fold_html
$COVER $GENHTML_TOOL --branch --ignore inconsistent -v -v \
    --baseline-file c.info -o fold_html cline.info > fold_html.log 2>&1
if [ 0 != $? ] ; then
    cat fold_html.log
    fail fold_html "unexpected genhtml failure"
fi
expect fold_html 'folded' \
    "`grep -c -F '"c.c": baseline continuation lines 4,5,7,10,12,22,29,31,42 folded into their statement lines' fold_html.log`" 1
expect fold_html 'line' "`grep -c '^    line: UBC:3 CBC:22$' fold_html.log`" 1
expect fold_html 'branch' "`grep -c '^    branch: UBC:5 CBC:3$' fold_html.log`" 1
expect fold_html 'function' "`grep -c '^    function: CBC:4$' fold_html.log`" 1

# ..and in each testcase, the statement line keeps the greater of the two
#   counts, and the MC/DC data of the continuation line is moved with it
cat > fold.c <<'EOF'
int m(int a, int b)
{
  int x = a &&
          b;
  return x;
}
EOF
# the baseline, without the merge:  in 't1', continuation line 4 counts more
#   than its statement line
mkinfo fold_base.info <<'EOF'
TN:t1
SF:fold.c
FNL:0,1,6
FNA:0,2,m
DA:1,2
DA:3,1
DA:4,2
DA:5,2
MCDC:4,2,t,1,0,a
MCDC:4,2,f,0,0,a
MCDC:4,2,t,1,1,b
MCDC:4,2,f,1,1,b
end_of_record
TN:t2
SF:fold.c
FNL:0,1,6
FNA:0,1,m
DA:1,1
DA:3,1
DA:4,0
DA:5,1
end_of_record
EOF
# ..and the current data, with it
mkinfo fold_curr.info <<'EOF'
TN:t1
SF:fold.c
FNL:0,1,6
FNA:0,2,m
DA:1,2
DA:3,2,,4
DA:5,2
MCDC:3,2^4,t,1,0,a
MCDC:3,2^4,f,0,0,a
MCDC:3,2^4,t,1,1,b
MCDC:3,2^4,f,1,1,b
end_of_record
TN:t2
SF:fold.c
FNL:0,1,6
FNA:0,1,m
DA:1,1
DA:3,1,,4
DA:5,1
end_of_record
EOF
rm -rf fold_mcdc_html
$COVER $GENHTML_TOOL --mcdc --ignore inconsistent,usage -v -v \
    --baseline-file fold_base.info -o fold_mcdc_html fold_curr.info \
    > fold_mcdc_html.log 2>&1
if [ 0 != $? ] ; then
    cat fold_mcdc_html.log
    fail fold_mcdc_html "unexpected genhtml failure"
fi
expect fold_mcdc_html 'folded' \
    "`grep -c -F '"fold.c": baseline continuation line 4 folded into its statement line' fold_mcdc_html.log`" 1
expect fold_mcdc_html 'line' "`grep -c '^    line: CBC:3$' fold_mcdc_html.log`" 1
expect fold_mcdc_html 'mcdc' "`grep -c '^    mcdc: UBC:1 CBC:3$' fold_mcdc_html.log`" 1

# ----------------------------------------------------------------------
# XS
# ----------------------------------------------------------------------
mkinfo x.info <<EOF
TN:
SF:x.xs
FN:12,24,new
FNDA:6,new
DA:17,6
DA:19,6
DA:21,6
BRDA:17,0,0,0
BRDA:17,0,1,0
BRDA:19,0,0,0
BRDA:19,0,1,6
BRDA:19,1,0,0
BRDA:19,1,1,0
end_of_record
EOF

run xs_off -a x.info -v
expect xs_off 'inconsistent' "`said xs_off.log x.xs "$HIT_NO_BRANCH"`" 17

run xs -a x.info $LINEMERGE -v
expect xs 'merged' "`said xs.log x.xs "$MERGED"`" 19
expect xs 'totals' "`totals xs.log`" \
    'Merged 1 continuation line into 1 statement line'
expect xs 'result' "`lines DA x.xs xs.info`" '17 21'
expect xs 'branches' "`lines BRDA x.xs xs.info`" 17
expect xs 'inconsistent' "`said xs.log x.xs "$HIT_NO_BRANCH"`" ''

# ----------------------------------------------------------------------
# Perl
# ----------------------------------------------------------------------
mkinfo p.info <<EOF
TN:
SF:p.pl
FN:1,15,f
FNDA:2,f
DA:3,2
DA:4,2
DA:5,440
DA:6,0
DA:8,210
DA:10,2
DA:11,0
DA:12,2
DA:13,0
DA:14,2
BRDA:6,0,0,-
BRDA:6,0,1,-
end_of_record
EOF

run perl -a p.info $LINEMERGE -v
expect perl 'merged' "`said perl.log p.pl "$MERGED"`" '6 11'
expect perl 'result' "`lines DA p.pl perl.info`" '3 4 5 8 10 12 13 14'
expect perl 'branches' "`lines BRDA p.pl perl.info`" 5
expect perl 'totals' "`totals perl.log`" \
    'Merged 2 continuation lines into 2 statement lines'

# the totals are over all the files - here, each merged in a child process
LCOV_FORCE_PARALLEL=1 run all -a c.info -a x.info -a p.info $LINEMERGE \
    --parallel 2
expect all 'totals' "`totals all.log`" \
    'Merged 12 continuation lines into 11 statement lines'

# ----------------------------------------------------------------------
# callgraph:  'h' of 'c.c', testcases 't1' and 't2'
# ----------------------------------------------------------------------
for tn in t1 t2 ; do
    if [ $tn == t1 ] ; then
        L32=2
        L33=1
    else
        L32=1
        L33=2
    fi
    cat <<EOF
TN:$tn
SF:c.c
FNL:0,16,24
FNA:0,2,g
FNL:1,26,35
FNA:1,3,h
FNC:1,27,1,0,0,g
FNC:1,28,11,0,3,g
FNC:1,29,13,0,3,h
FNC:1,31,10,0,3,g
FNC:1,33,9,0,1,g
DA:16,0
DA:18,2
DA:19,2
DA:20,0
DA:21,2
DA:22,0
DA:23,2
DA:26,3
DA:28,3
DA:29,3
DA:30,3
DA:31,3
DA:32,$L32
DA:33,$L33
DA:34,3
BRDA:30,0,0,0
BRDA:30,0,1,0
BRDA:31,0,0,3
BRDA:31,0,1,0
end_of_record
EOF
done > cg.raw
mkinfo cg.in < cg.raw

ALLOCATED='allocated call site'
STATEMENTS='29^28 31^30'

run cg_off -a cg.in --callgraph -v
expect cg_off 'allocated' "`said cg_off.log c.c "$ALLOCATED"`" ''
expect cg_off 'statements' "`statements c.c cg_off.info t1`" ''

run cgm -a cg.in --callgraph $LINEMERGE -v
expect cgm 'allocated' "`said cgm.log c.c "$ALLOCATED"`" '29 31'
for tn in t1 t2 ; do
    expect cgm "statements $tn" "`statements c.c cgm.info $tn`" "$STATEMENTS"
done
expect cgm 'FNCF' "`summary FNCF c.c cgm.info`" 5
expect cgm 'FNCH' "`summary FNCH c.c cgm.info`" 4

# the statement line is read back, retained by a merge with data which has
#    none, and survives the hand-off from a child process
LCOV_FORCE_PARALLEL=1 run cg_union -a cg_off.info -a cgm.info --callgraph \
    --parallel 2
for tn in t1 t2 ; do
    expect cg_union "statements $tn" "`statements c.c cg_union.info $tn`" \
        "$STATEMENTS"
done

# a call to a function which no file of the report defines is removed - from
#   each testcase as well as from the summary
sed -e 's/^FNC:1,29,13,0,3,h$/&\nFNC:1,29,20,0,3,strlen/' cg.raw |
    mkinfo cg_ext.in
expect cg_ext 'input' "`grep -c ',strlen$' cg_ext.in`" 2
run cg_ext -a cg_ext.in --callgraph $LINEMERGE
expect cg_ext 'removed' "`grep -c 'strlen' cg_ext.info`" 0
for tn in t1 t2 ; do
    expect cg_ext "statements $tn" "`statements c.c cg_ext.info $tn`" \
        "$STATEMENTS"
done

# a statement line which is too far from the call is not one
sed -e 's/^FNC:1^28,29,/FNC:1^200,29,/' cgm.info > cg_far.in
run cg_far -a cg_far.in --callgraph --ignore format
expect cg_far 'message' \
    "`grep -c "unexpected call site statement line '200'" cg_far.log`" 2
expect cg_far 'statements' "`statements c.c cg_far.info t1`" '31^30'

# the coverpoint is counted on the statement line, and the link to the call
#   leads to where it is written
rm -rf cg_html
$COVER $GENHTML_TOOL --callgraph --ignore inconsistent,usage \
    --baseline-file cg_off.info -o cg_html cgm.info > cg_html.log 2>&1
if [ 0 != $? ] ; then
    cat cg_html.log
    fail cg_html "unexpected genhtml failure"
fi
PAGE=`find cg_html -name c.c.gcov.html`
CALLEES=`find cg_html -name c.c.callees.html`
expect cg_html 'first missed callee' \
    "`grep -o 'href="#L[0-9]*" title="goto first UBC callee"' $PAGE`" \
    'href="#L27" title="goto first UBC callee"'
expect cg_html 'call links' \
    "`grep -o 'gcov.html#L[0-9]*" title="Click to go to callsite[^>]*>[0-9:]*' $CALLEES |
        sed -e 's/".*>/ /' -e 's/.*#//' | tr '\n' ' '`" \
    'L27 27:1 L28 28:11 L29 29:13 L31 31:10 L33 33:9 '

# a call both inputs have keeps the statement line either one gives it
run cg_inter cg_off.info --intersect cgm.info --callgraph
for tn in t1 t2 ; do
    expect cg_inter "statements $tn" "`statements c.c cg_inter.info $tn`" \
        "$STATEMENTS"
done

# a call which only the baseline has is placed on its statement line too
grep -v '^FNC:1,29,' cg.raw | mkinfo cg_lost.in
run cg_lost -a cg_lost.in --callgraph $LINEMERGE
rm -rf cg_lost_html
$COVER $GENHTML_TOOL --callgraph --ignore inconsistent,usage \
    --baseline-file cgm.info -o cg_lost_html cg_lost.info > cg_lost_html.log 2>&1
if [ 0 != $? ] ; then
    cat cg_lost_html.log
    fail cg_lost_html "unexpected genhtml failure"
fi
expect cg_lost_html 'lost call' \
    "`grep -c 'href="#L28" title="goto first ECB callee"' cg_lost_html/linemerge/c.c.gcov.html`" 1

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    generate_coverage 'linemerge' $LOCAL_COVERAGE 1
fi
exit $STATUS
