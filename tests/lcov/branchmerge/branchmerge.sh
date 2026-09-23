#!/bin/bash

# 'merge_continuation_lines':  branch and MC/DC data on a line without a line
#   coverpoint is moved to the line of the statement which the line is
#   part of - its first line, or its last if the first has no line coverpoint -
#   when the source makes the statement clear.  Then the counts on that line are
#   checked against each other.
# 'ignore_lambda_consistency':  whether the branch/line consistency of a line
#   which holds a lambda is checked.
# The sources are never compiled; the '.info' files are written here, by hand.
#   The lines of 'c.c' with branch data but no line coverpoint, and what is
#   expected of each:
#      5,6  later lines of an 'if' condition             merged onto 4
#      9    right-hand side of '||'                      merged onto 8
#     11    ':' arm of a conditional                     merged onto 10
#     12    first line of a statement, 13 has the count  13's moved to 12
#     17    a directive in the statement                 kept
#     20    a comment which spans lines                  kept
#     22    two statements on the line it starts on      kept
#     25    the body of an 'if' - not its condition      merged onto 24
#     29    3 lines into the statement                   merged onto 26
#                                                        kept with lookahead 2
#     31    no line of the statement has a count         kept
#     33    an exclusion marker in the statement         kept
#     43    the condition of an 'else if'                merged onto 42
#     46    a 'for' header, which holds ';'              merged onto 45
#     49    an 'if' header which holds ';'               kept
#     52    a condition which ends with the '{'          merged onto 51
#     55    a statement which starts after a '}'         merged onto 54
#     58    a statement after a blank line               merged onto 57
#     60    a '}' which ends the statement               kept
# A line which is kept is reported - 'location has branchcov but no linecov
#   data' - as it is without the merge.

set +x

source ../../common.tst

rm -rf *.log *.json *.info nav_html diff_html dropped_html

clean_cover

if [[ 1 == "$CLEAN_ONLY" ]] ; then
    exit 0
fi

LCOV_OPTS="--branch $PARALLEL $PROFILE"
MERGE='--rc merge_continuation_lines=1'
NOLAMBDA='--rc ignore_lambda_consistency=1'
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
    if (lf) print "LF:" lf "\nLH:" lh
    if (brf) print "BRF:" brf "\nBRH:" brh
    if (mcf) print "MCF:" mcf "\nMCH:" mch
    print
    fnf = fnh = lf = lh = brf = brh = mcf = mch = 0
    next
}
/^FNDA:/ { ++fnf; if ($2 > 0) ++fnh }
/^DA:/   { ++lf; if ($3 > 0) ++lh }
/^BRDA:/ { ++brf; if ($5 != "-" && $5 > 0) ++brh }
/^MCDC:/ { ++mcf; if ($5 > 0) ++mch }
{ print }' > $1
}

# rewrite .info file $1 with sed expression $2 into $3, and recompute its
#   found/hit records
derive()
{
    sed -e "$2" $1 | grep -v -E '^(FNF|FNH|LF|LH|BRF|BRH|MCF|MCH):' | mkinfo $3
}

# run label expected-exit(0 = success, 1 = failure) lcov-args...
run()
{
    local label=$1
    local expect=$2
    shift 2
    $COVER $LCOV_TOOL $LCOV_OPTS -o $label.info "$@" > $label.log 2>&1
    local status=$?
    if [ 0 == $expect -a 0 != $status ] ; then
        cat $label.log
        fail $label "unexpected lcov failure"
    elif [ 0 != $expect -a 0 == $status ] ; then
        cat $label.log
        fail $label "expected lcov to fail"
    fi
}

# the lines of source file $2 which have record $1 in .info file $3 (any
#   testcase), in order
lines()
{
    awk -F'[:,]' -v rec=$1 -v file=$2 '
/^SF:/ { mine = ($2 == file) }
mine && $1 == rec { print $2 }' $3 | sort -n | uniq | tr '\n' ' ' |
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

NOLINE='location has branchcov but no linecov data'
MERGED='merged branch/MC/DC data onto statement line'
MOVED='moved line coverpoint to statement line'
LAMBDA='lambda detected, consistency check suppressed'
HIT_NO_BRANCH='line is hit but no branches on line have been evaluated'
BRANCH_NO_HIT='line is not hit but at least one branch on line has been evaluated'

# ----------------------------------------------------------------------
# C:  which lines are merged, and where to
# ----------------------------------------------------------------------
# testcases 't1' and 't2' have the same data;  'MCDC:' records are read only
#   with '--mcdc'.  Line 4 has an MC/DC group of size 2 of its own:  the group
#   of that size on line 5 is folded into it, and the group of size 3 on line 6
#   becomes a second group on line 4
for tn in t1 t2 ; do
    cat <<EOF
TN:$tn
SF:c.c
FN:1,37,f
FNDA:2,f
FN:38,62,g2
FNDA:2,g2
DA:1,2
DA:3,2
DA:4,2
DA:7,1
DA:8,2
DA:10,2
DA:13,2
DA:15,2
DA:19,2
DA:21,2
DA:23,2
DA:24,1
DA:26,2
DA:32,2
DA:34,2
DA:35,2
DA:36,2
DA:38,2
DA:40,2
DA:41,2
DA:42,2
DA:44,2
DA:45,2
DA:47,2
DA:48,2
DA:50,2
DA:51,2
DA:53,2
DA:54,2
DA:57,2
DA:59,2
DA:61,2
BRDA:4,0,0,2
BRDA:4,0,1,0
BRDA:5,0,0,1
BRDA:5,0,1,1
BRDA:6,0,0,1
BRDA:6,0,1,0
BRDA:9,0,0,1
BRDA:9,0,1,1
BRDA:11,0,0,1
BRDA:11,0,1,1
BRDA:12,0,0,2
BRDA:12,0,1,0
BRDA:17,0,0,1
BRDA:17,0,1,1
BRDA:20,0,0,1
BRDA:20,0,1,1
BRDA:22,0,0,1
BRDA:22,0,1,1
BRDA:23,0,0,1
BRDA:23,0,1,1
BRDA:25,0,0,1
BRDA:25,0,1,0
BRDA:29,0,0,1
BRDA:29,0,1,1
BRDA:31,0,0,1
BRDA:31,0,1,1
BRDA:33,0,0,1
BRDA:33,0,1,1
BRDA:43,0,0,1
BRDA:43,0,1,1
BRDA:46,0,0,1
BRDA:46,0,1,1
BRDA:49,0,0,1
BRDA:49,0,1,1
BRDA:52,0,0,1
BRDA:52,0,1,1
BRDA:55,0,0,1
BRDA:55,0,1,1
BRDA:58,0,0,1
BRDA:58,0,1,1
BRDA:60,0,0,1
BRDA:60,0,1,1
MCDC:4,2,t,1,0,a
MCDC:4,2,f,1,0,a
MCDC:4,2,t,1,1,b
MCDC:4,2,f,0,1,b
MCDC:5,2,t,1,0,a
MCDC:5,2,f,0,0,a
MCDC:5,2,t,1,1,b
MCDC:5,2,f,1,1,b
MCDC:6,3,t,1,0,a
MCDC:6,3,f,1,0,a
MCDC:6,3,t,1,1,b
MCDC:6,3,f,1,1,b
MCDC:6,3,t,0,2,c
MCDC:6,3,f,1,2,c
end_of_record
EOF
done | mkinfo c.info

# the same, but with no function end line:  the consistency check is then run
#   by the filtering step, after the end line is derived
derive c.info 's/^FN:1,37,f/FN:1,f/' cderive.info

KEPT='17 20 22 31 33 49 60'
BR_MERGED='4 8 10 12 23 24 26 42 45 51 54 57'

# by default, nothing is merged:  the lines are errors - the first one found
#   stops the run
run off 1 -a c.info
OFF=`said off.log c.c "$NOLINE"`
if ! echo ' 5 6 9 11 12 17 20 22 25 29 31 33 43 46 49 52 55 58 60 ' | grep -q " $OFF " ; then
    fail off "reported lines: '$OFF', expected one line without a line coverpoint"
fi

# ..and the merge is part of the consistency check
run nocheck 0 -a c.info $MERGE --rc check_data_consistency=0
expect nocheck 'branch lines' "`lines BRDA c.c nocheck.info`" \
    '4 5 6 9 11 12 17 20 22 23 25 29 31 33 43 46 49 52 55 58 60'

run merge 0 -a c.info $MERGE --ignore inconsistent -v
expect merge 'merged lines' "`said merge.log c.c "$MERGED"`" \
    '5 6 9 11 25 29 43 46 52 55 58'
expect merge 'moved lines' "`said merge.log c.c "$MOVED"`" 13
for l in '5:.*line 4$' '6:.*line 4$' '9:.*line 8$' '11:.*line 10$' \
    '13:.*line 12$' '25:.*line 24$' '29:.*line 26$' '43:.*line 42$' \
    '46:.*line 45$' '52:.*line 51$' '55:.*line 54$' '58:.*line 57$' ; do
    if ! grep -q "\"c.c\":$l" merge.log ; then
        fail merge "expected '$l' in the merge messages"
    fi
done
expect merge 'reported lines' "`said merge.log c.c "$NOLINE"`" "$KEPT"
expect merge 'branch lines' "`lines BRDA c.c merge.info`" \
    "`echo $BR_MERGED $KEPT | tr ' ' '\n' | sort -n | tr '\n' ' ' | sed -e 's/ $//'`"
# the moved blocks follow the blocks already on the line, and each is written
#   with the line it came from;  the counts are unchanged, and so are the totals
L4=`grep '^BRDA:4,' merge.info | LC_ALL=C sort -u | tr '\n' ' '`
expect merge 'line 4' "$L4" \
    'BRDA:4,0,0,2 BRDA:4,0,1,0 BRDA:4,1^5,0,1 BRDA:4,1^5,1,1 BRDA:4,2^6,0,1 BRDA:4,2^6,1,0 '
expect merge 'totals' "`grep -e '^BR[FH]:' merge.info | sort -u | tr '\n' ' '`" \
    "`grep -e '^BR[FH]:' c.info | sort -u | tr '\n' ' '`"
# ..in each testcase
for tn in t1 t2 ; do
    COUNT=`awk -v tn="TN:$tn" '$0 == tn { mine = 1 } /^end_of_record/ { mine = 0 }
            mine && /^BRDA:5,/' merge.info | wc -l`
    expect merge "testcase $tn line 5" $COUNT 0
done
if [ 2 != `grep -c '^TN:' merge.info` ] ; then
    fail merge "expected both testcases in the output"
fi

# a statement longer than the lookahead window is not known
run lookahead 0 -a c.info $MERGE --ignore inconsistent --rc filter_lookahead=2
expect lookahead 'reported lines' "`said lookahead.log c.c "$NOLINE"`" \
    "17 20 22 29 31 33 49 60"

# the same with a filter - with and without a derived function end line, in
#   parallel.  The data is merged when it is read, and the filters see the
#   result
for input in c cderive ; do
    LCOV_FORCE_PARALLEL=1 run filter_$input 0 -a $input.info $MERGE \
        --ignore inconsistent --filter blank --parallel 2 --rc derive_function_end_line=1
    expect filter_$input 'branch lines' "`lines BRDA c.c filter_$input.info`" \
        "`lines BRDA c.c merge.info`"
    expect filter_$input 'reported lines' \
        "`said filter_$input.log c.c "$NOLINE"`" "$KEPT"
done

# MC/DC:  the groups on lines 5 and 6 are added to line 4.  Each keeps the line
#   it came from, so the group of size 2 from line 5 is not folded into the one
#   of the same size which was already on line 4
run mcdc 0 -a c.info $MERGE --mcdc --ignore inconsistent
expect mcdc 'MC/DC lines' "`lines MCDC c.c mcdc.info`" 4
L4=`grep '^MCDC:4,' mcdc.info | LC_ALL=C sort -u | tr '\n' ' '`
expect mcdc 'line 4' "$L4" \
    'MCDC:4,2,f,0,1,b MCDC:4,2,f,1,0,a MCDC:4,2,t,1,0,a MCDC:4,2,t,1,1,b MCDC:4,2^5,f,0,0,a MCDC:4,2^5,f,1,1,b MCDC:4,2^5,t,1,0,a MCDC:4,2^5,t,1,1,b MCDC:4,3^6,f,1,0,a MCDC:4,3^6,f,1,1,b MCDC:4,3^6,f,1,2,c MCDC:4,3^6,t,0,2,c MCDC:4,3^6,t,1,0,a MCDC:4,3^6,t,1,1,b '
expect mcdc 'totals' "`grep -e '^MC[FH]:' mcdc.info | sort -u | tr '\n' ' '`" \
    'MCF:14 MCH:11 '

# ..but a group from line 5 is folded into a group of line 4 which is written
#   at line 5:  the counts are added, and expressions which disagree are an
#   error
derive c.info 's/^MCDC:5,2,\(.,.,0,a\)$/&\nMCDC:4,2^5,\1/; s/^MCDC:5,2,\(.,.,1,\)b$/&\nMCDC:4,2^5,\1z/' mismatched.info
run mismatch 1 -a mismatched.info $MERGE --mcdc
if ! grep -q "\"c.c\":5: MC/DC group 2 expression 1 changed from 'z' to 'b'" mismatch.log ; then
    fail mismatch "expected the expressions to be reported"
fi
# ..which keeps the expression already on the line
run mismatch_ignored 0 -a mismatched.info $MERGE --mcdc --ignore inconsistent
if [ 0 == `grep -c -F -e 'MCDC:4,2^5,t,2,1,z' mismatch_ignored.info` ] ; then
    fail mismatch_ignored "the moved expression replaced the one on the line"
fi

# a group which has different expressions in two files cannot be merged.  The
#   message names the line the group is written at - the lower one if more
#   than one group differs
#   The counts do not change, so the summary records are kept
sed -e 's/^\(MCDC:4,2^5,.*,\)b$/\1z/; s/^\(MCDC:4,3^6,.*,\)c$/\1y/' mcdc.info > conflict.info
for op in add intersect ; do
    if [ $op == add ] ; then
        run conflict_$op 0 -a mcdc.info -a conflict.info --mcdc \
            --ignore inconsistent
    else
        run conflict_$op 0 mcdc.info --intersect conflict.info --mcdc \
            --ignore inconsistent
    fi
    if ! grep -q "c.c:5: cannot merge inconsistent MC/DC record: group 2" conflict_$op.log ; then
        fail conflict_$op "expected the group's line to be reported"
    fi
done

# a message about a block which is written at another line names that line:
#   block 1 of line 4 is written at 5, block 2 at 6
mkinfo displaced.info <<EOF
TN:
SF:c.c
DA:4,2
BRDA:4,0,0,1
BRDA:4,0,1,1
BRDA:4,1^5,0,1
BRDA:4,1^5,1,1
BRDA:4,e2^6,0,1
BRDA:4,e2^6,1,0
end_of_record
EOF
# ..removing the exception branches of block 2
run displaced_exception 0 -a displaced.info --filter exception -v -v \
    --ignore empty
if ! grep -q 'c.c:6: remove exception block 2' displaced_exception.log ; then
    fail displaced_exception "expected the block's line to be reported"
fi
# ..and merging block 1 with a copy which says it is unreachable
derive displaced.info 's/^BRDA:4,1^5,/BRDA:4,U1^5,/' displaced_unreach.info
run displaced_mismatch 1 -a displaced.info -a displaced_unreach.info \
    --ignore empty
if ! grep -q "\"c.c\":5: mismatched 'unreachable' tag for branch id" displaced_mismatch.log ; then
    fail displaced_mismatch "expected the block's line to be reported"
fi

# ----------------------------------------------------------------------
# the '^<location>' field
# ----------------------------------------------------------------------
# a location may be up to 127 lines after the line which holds the data, or
#   before it.  A location which is the line itself is not written.  The blocks
#   of a line are written in order - shortest signature first, and a block
#   with a location after one without - and numbered in that order, so reading
#   the output again gives the same output
mkinfo located_in.info <<EOF
TN:
SF:located.c
DA:4,2
DA:200,1
BRDA:4,0,0,1
BRDA:4,0,1,1
BRDA:4,1^131,0,1
BRDA:4,1^131,1,0
BRDA:4,2^4,0,1
BRDA:4,2^4,1,1
BRDA:200,0^73,0,1
BRDA:200,0^73,1,1
MCDC:4,2^131,t,1,0,a
MCDC:4,2^131,f,0,0,a
MCDC:4,2^131,t,1,1,b
MCDC:4,2^131,f,1,1,b
MCDC:200,2^73,t,1,0,a
MCDC:200,2^73,f,1,0,a
MCDC:200,2^73,t,1,1,b
MCDC:200,2^73,f,1,1,b
end_of_record
EOF
LOCATED='BRDA:4,0,0,1 BRDA:4,0,1,1 BRDA:4,1,0,1 BRDA:4,1,1,1 BRDA:4,2^131,0,1 BRDA:4,2^131,1,0 BRDA:200,0^73,0,1 BRDA:200,0^73,1,1 MCDC:4,2^131,t,1,0,a MCDC:4,2^131,f,0,0,a MCDC:4,2^131,t,1,1,b MCDC:4,2^131,f,1,1,b MCDC:200,2^73,t,1,0,a MCDC:200,2^73,f,1,0,a MCDC:200,2^73,t,1,1,b MCDC:200,2^73,f,1,1,b '
# ..in the order they are written, and the same when the data is passed
#   between processes
records()
{
    grep -E '^(BRDA|MCDC):' $1 | tr '\n' ' '
}
run located 0 -a located_in.info --mcdc --ignore empty
expect located 'records' "`records located.info`" "$LOCATED"
LCOV_FORCE_PARALLEL=1 run located_parallel 0 -a located_in.info --mcdc \
    --ignore empty --parallel 2
expect located_parallel 'records' "`records located_parallel.info`" \
    "$LOCATED"
run located_again 0 -a located.info --mcdc --ignore empty
expect located_again 'records' "`records located_again.info`" "$LOCATED"
expect located_again 'totals' \
    "`grep -E '^(BR|MC)[FH]:' located_again.info | tr '\n' ' '`" \
    "`grep -E '^(BR|MC)[FH]:' located_in.info | tr '\n' ' '`"

# a location more than 127 lines away is an error:  128 after the line, or 128
#   before it.  If the error is ignored, the record is read without its
#   location
derive located_in.info 's/1^131/1^132/; s/2^131/2^132/; s/0^73/0^72/; s/2^73/2^72/' \
    far_in.info
run far 1 -a far_in.info --mcdc --ignore empty
if ! grep -q -F "location 132 of line 4 is more than 127 lines away in .info file record 'BRDA:4,1^132,0,1'" far.log ; then
    fail far "expected the location to be reported"
fi
run far_ignored 0 -a far_in.info --mcdc --ignore empty,format
for r in 'BRDA:4,1^132' 'MCDC:4,2^132' 'BRDA:200,0^72' 'MCDC:200,2^72' ; do
    L=${r%^*}
    L=${L#*:}
    L=${L%,*}
    if ! grep -q -F "location ${r#*^} of line $L is more than 127 lines away in .info file record '$r," far_ignored.log ; then
        fail far_ignored "expected '$r' to be reported"
    fi
done
expect far_ignored 'records with a location' \
    "`grep -c -E '^(BRDA|MCDC):[0-9]+,[a-zU]*[0-9]+\^' far_ignored.info`" 0
expect far_ignored 'records' "`grep -c -E '^(BRDA|MCDC):' far_ignored.info`" 16

# genhtml shows a block or group at the line it is written at, and its
#   navigation links go there:  the only branch which was not taken is in the
#   block written at line 5, and the only condition which was not sensitized
#   is in the group written at line 6
mkinfo nav.info <<EOF
TN:
SF:c.c
DA:4,2
BRDA:4,0,0,1
BRDA:4,0,1,1
BRDA:4,1^5,0,1
BRDA:4,1^5,1,0
MCDC:4,2,t,1,0,a
MCDC:4,2,f,1,0,a
MCDC:4,2,t,1,1,b
MCDC:4,2,f,1,1,b
MCDC:4,2^6,t,1,0,a
MCDC:4,2^6,f,0,0,a
MCDC:4,2^6,t,1,1,b
MCDC:4,2^6,f,1,1,b
end_of_record
EOF
# links label html-dir:  the 'goto first' links of the page of 'c.c'
links()
{
    local page=`find $2 -name c.c.gcov.html`
    if [ -z "$page" ] ; then
        fail $1 "no page for c.c"
        return
    fi
    grep -o 'href="#L[0-9]*" title="goto first [^"]*"' $page | sort -u |
        tr '\n' ' '
}
# genhtml label genhtml-args...
html()
{
    local label=$1
    shift
    rm -rf $label
    $COVER $GENHTML_TOOL --branch --mcdc --show-navigation --ignore empty \
        $PARALLEL $PROFILE -o $label "$@" > $label.log 2>&1
    if [ 0 != $? ] ; then
        cat $label.log
        fail $label "unexpected genhtml failure"
    fi
}
html nav_html nav.info
expect nav_html 'links' "`links nav_html nav_html`" \
    'href="#L4" title="goto first Hit branch" href="#L4" title="goto first Hit condition" href="#L4" title="goto first Hit line" href="#L5" title="goto first Missed branch" href="#L6" title="goto first Missed condition" '
# ..and in a differential report:  the branch and the condition were covered
#   since the baseline
derive nav.info 's/^BRDA:4,1^5,1,0$/BRDA:4,1^5,1,1/; s/^MCDC:4,2^6,f,0,0,a$/MCDC:4,2^6,f,1,0,a/' \
    nav_current.info
html diff_html --baseline-file nav.info nav_current.info
expect diff_html 'links' "`links diff_html diff_html`" \
    'href="#L4" title="goto first CBC branch" href="#L4" title="goto first CBC condition" href="#L4" title="goto first CBC line" href="#L5" title="goto first GBC branch" href="#L6" title="goto first GBC condition" '
PAGE=`find diff_html -name c.c.gcov.html`
for l in '5:GBC: branch 1 was taken 1 time' \
    '6:GBC: False sense of expression &quot;a&quot; in group &quot;2&quot; was sensitized' ; do
    if ! grep "id=\"L${l%%:*}\"" $PAGE | grep -q -F "title=\"${l#*:}\"" ; then
        fail diff_html "expected '${l#*:}' at line ${l%%:*}"
    fi
done
# ..and a group which is not in the current data is shown where it was
#   written in the baseline
derive nav.info '/^MCDC:4,2^6,/d' nav_dropped.info
html dropped_html --baseline-file nav.info nav_dropped.info
expect dropped_html 'links' "`links dropped_html dropped_html`" \
    'href="#L4" title="goto first CBC branch" href="#L4" title="goto first CBC condition" href="#L4" title="goto first CBC line" href="#L5" title="goto first UBC branch" href="#L6" title="goto first ECB condition" href="#L6" title="goto first EUB condition" '
PAGE=`find dropped_html -name c.c.gcov.html`
for l in 'ECB: True sense of expression &quot;a&quot; in group &quot;2&quot; was dropped (previously sensitized)' \
    'EUB: False sense of expression &quot;a&quot; in group &quot;2&quot; was dropped' ; do
    if ! grep 'id="L6"' $PAGE | grep -q -F "title=\"$l\"" ; then
        fail dropped_html "expected '$l' at line 6"
    fi
done

# ----------------------------------------------------------------------
# C:  the counts on a line which received data
# ----------------------------------------------------------------------
#   line 4:  a branch taken more often than the statement was executed
#   line 8:  the statement was executed but no branch was taken
#   line 10: an MC/DC condition was sensitized, but the statement was not
#     executed
mkinfo counts.info <<EOF
TN:
SF:c.c
FN:1,37,f
FNDA:1,f
DA:1,1
DA:4,1
DA:8,2
DA:10,0
DA:36,1
BRDA:5,0,0,3
BRDA:5,0,1,0
BRDA:6,0,0,1
BRDA:6,0,1,0
BRDA:9,0,0,0
BRDA:9,0,1,0
MCDC:11,2,t,1,0,c
MCDC:11,2,f,0,0,c
MCDC:11,2,t,0,1,d
MCDC:11,2,f,0,1,d
end_of_record
EOF

run count 1 -a counts.info $MERGE
if ! grep -q '"c.c":4: after merging branch/MC/DC data from lines 5, 6 onto this statement: largest branch hit count 3 exceeds line hit count 1\.' count.log ; then
    fail count "expected the count of line 4 to be reported"
fi

run count_ignored 0 -a counts.info $MERGE --mcdc --ignore inconsistent
AFTER='after merging branch/MC/DC data'
expect count_ignored 'reported lines' "`said count_ignored.log c.c "$AFTER"`" \
    '4 8 10'
if ! grep -q "\"c.c\":8: $AFTER from line 9 onto this statement: $HIT_NO_BRANCH" count_ignored.log ; then
    fail count_ignored "expected the branches of line 8 to be reported"
fi
if ! grep -q "\"c.c\":10: $AFTER from line 11 onto this statement: line is not hit but an MC/DC condition on line is" count_ignored.log ; then
    fail count_ignored "expected the MC/DC data of line 10 to be reported"
fi
# ..once:  the message for the merged line is the only one.  Each file is
#   checked once - when all of the data read has been combined
PATTERN="\"c.c\":8: $HIT_NO_BRANCH"
expect count_ignored 'line 8' `grep -c -F "$PATTERN" count_ignored.log` 0
# the data is merged even so
expect count_ignored 'branch lines' "`lines BRDA c.c count_ignored.info`" '4 8'
expect count_ignored 'MC/DC lines' "`lines MCDC c.c count_ignored.info`" 10

# each file is checked once, when all of its data has been read and combined:
#   one message, however many inputs there are.  Without a statement merge
#   too - and with the filtering step, which is run on the combined data
mkinfo single.info <<EOF
TN:
SF:c.c
FN:1,37,f
FNDA:2,f
DA:1,2
DA:8,2
BRDA:8,0,0,0
BRDA:8,0,1,0
end_of_record
EOF
cp single.info single2.info
PATTERN="\"c.c\":8: $HIT_NO_BRANCH"
for filter in '' '--filter blank' ; do
    run once 0 -a single.info --ignore inconsistent $filter
    expect once "one input $filter" `grep -c -F "$PATTERN" once.log` 1
    run once 0 -a single.info -a single2.info --ignore inconsistent $filter
    expect once "two inputs $filter" `grep -c -F "$PATTERN" once.log` 1
done
# ..and a set operation checks each of its operands, but not the result when
#   the operands have no file in common
sed -e 's/^SF:c.c/SF:other.c/' single.info > other.info
run setop 0 single.info --subtract other.info --ignore inconsistent
expect setop 'subtract' `grep -c -F "$PATTERN" setop.log` 1
expect setop 'result' "`lines DA c.c setop.info`" '1 8'

# ----------------------------------------------------------------------
# lambdas
# ----------------------------------------------------------------------
#   lambda.cpp:6  the source defines a lambda on the line
#   lambda.cpp:9  no lambda:  always reported
#   lambda.cpp:10 a lambda by its name;  the data of line 11 is merged onto it
#   nosrc.cpp     there is no source - only the names:  demangled (5),
#                 mangled (8) and not a lambda (11)
#   Nosrc.java:3  a Java lambda, by name
mkinfo lambdas.info <<'EOF'
TN:
SF:lambda.cpp
FN:3,13,main
FNDA:1,main
FN:10,11,main::{lambda(int)#2}::operator()(int) const
FNDA:1,main::{lambda(int)#2}::operator()(int) const
DA:3,1
DA:5,1
DA:6,1
DA:7,1
DA:8,1
DA:9,1
DA:10,1
DA:12,1
BRDA:6,0,0,0
BRDA:6,0,1,0
BRDA:7,0,0,1
BRDA:7,0,1,0
BRDA:9,0,0,0
BRDA:9,0,1,0
BRDA:11,0,0,0
BRDA:11,0,1,0
end_of_record
SF:nosrc.cpp
FN:5,6,main::{lambda(int)#1}::operator()(int) const
FNDA:1,main::{lambda(int)#1}::operator()(int) const
FN:8,9,_ZZ4mainENKUlvE_clEv
FNDA:1,_ZZ4mainENKUlvE_clEv
FN:11,12,foo
FNDA:1,foo
DA:5,1
DA:8,1
DA:11,1
BRDA:5,0,0,0
BRDA:5,0,1,0
BRDA:8,0,0,0
BRDA:8,0,1,0
BRDA:11,0,0,0
BRDA:11,0,1,0
end_of_record
SF:Nosrc.java
FN:3,4,com.x.J.lambda$m$0
FNDA:1,com.x.J.lambda$m$0
DA:3,1
BRDA:3,0,0,0
BRDA:3,0,1,0
end_of_record
EOF

# by default, a lambda is checked like any other line
run lambda 0 -a lambdas.info $MERGE --ignore inconsistent -v
expect lambda 'lambda.cpp' "`said lambda.log lambda.cpp "$HIT_NO_BRANCH"`" \
    '6 9 10'
expect lambda 'nosrc.cpp' "`said lambda.log nosrc.cpp "$HIT_NO_BRANCH"`" \
    '5 8 11'
expect lambda 'Nosrc.java' "`said lambda.log Nosrc.java "$HIT_NO_BRANCH"`" 3
if grep -q -F "$LAMBDA" lambda.log ; then
    fail lambda "a lambda check was suppressed by default"
fi

run nolambda 0 -a lambdas.info $MERGE $NOLAMBDA --ignore inconsistent -v
expect nolambda 'lambda.cpp' "`said nolambda.log lambda.cpp "$HIT_NO_BRANCH"`" 9
expect nolambda 'nosrc.cpp' "`said nolambda.log nosrc.cpp "$HIT_NO_BRANCH"`" 11
expect nolambda 'Nosrc.java' "`said nolambda.log Nosrc.java "$HIT_NO_BRANCH"`" ''
expect nolambda 'lambda.cpp suppressed' \
    "`said nolambda.log lambda.cpp "$LAMBDA"`" '6 10'
expect nolambda 'nosrc.cpp suppressed' \
    "`said nolambda.log nosrc.cpp "$LAMBDA"`" '5 8'
expect nolambda 'merged' "`lines BRDA lambda.cpp nolambda.info`" '6 7 9 10'

# ..and independent of the merge
run nolambda_nomerge 0 -a lambdas.info $NOLAMBDA --ignore inconsistent -v
expect nolambda_nomerge 'nosrc.cpp' \
    "`said nolambda_nomerge.log nosrc.cpp "$HIT_NO_BRANCH"`" 11
expect nolambda_nomerge 'lambda.cpp' \
    "`said nolambda_nomerge.log lambda.cpp "$NOLINE"`" 11

# a branch taken on a line which is not executed is suppressed as well
derive lambdas.info 's/^DA:6,1/DA:6,0/;s/^BRDA:6,0,0,0/BRDA:6,0,0,1/' \
    lambda_nothit.info
run lambda_nothit 0 -a lambda_nothit.info $NOLAMBDA --ignore inconsistent -v
expect lambda_nothit 'reported' \
    "`said lambda_nothit.log lambda.cpp "$BRANCH_NO_HIT"`" ''
expect lambda_nothit 'suppressed' \
    "`said lambda_nothit.log lambda.cpp "$LAMBDA"`" 6

# ----------------------------------------------------------------------
# Java:  hit/not-hit data, so the statement is executed exactly if some branch
#   on it is taken
# ----------------------------------------------------------------------
#   3    a lambda, in the source
#   5-6  merged onto 5:  executed, but no branch is taken
mkinfo J.info <<'EOF'
TN:
SF:J.java
FN:2,8,J.m
FNDA:1,J.m
DA:2,1
DA:3,1
DA:5,1
DA:7,1
BRDA:3,0,0,0
BRDA:3,0,1,0
BRDA:6,0,0,0
BRDA:6,0,1,0
end_of_record
EOF
run java 0 -a J.info $MERGE $NOLAMBDA --ignore inconsistent -v
expect java 'merged' "`said java.log J.java "$MERGED"`" 6
expect java 'reported' "`said java.log J.java "$AFTER"`" 5
expect java 'suppressed' "`said java.log J.java "$LAMBDA"`" 3
expect java 'branch lines' "`lines BRDA J.java java.info`" '3 5'

# ..and taken, but not executed
derive J.info 's/^DA:5,1/DA:5,0/;s/^BRDA:6,0,0,0/BRDA:6,0,0,1/' J2.info
run java2 0 -a J2.info $MERGE --ignore inconsistent
if ! grep -q "\"J.java\":5: $AFTER from line 6 onto this statement: $BRANCH_NO_HIT" java2.log ; then
    fail java2 "expected the branches of line 5 to be reported"
fi

# ----------------------------------------------------------------------
# Perl:  a branch is taken only if the statement is executed - but the
#   statement may be executed without any branch being taken
# ----------------------------------------------------------------------
#   3-4  merged onto 3
#   5-6  a regular expression:  not known
mkinfo p.info <<'EOF'
TN:
SF:p.pl
FN:1,8,f
FNDA:1,f
DA:2,1
DA:3,1
DA:5,1
DA:7,1
BRDA:4,0,0,0
BRDA:4,0,1,0
BRDA:6,0,0,1
BRDA:6,0,1,0
end_of_record
EOF
run perl 0 -a p.info $MERGE --ignore inconsistent -v
expect perl 'merged' "`said perl.log p.pl "$MERGED"`" 4
expect perl 'reported' "`said perl.log p.pl "$AFTER"`" ''
expect perl 'kept' "`said perl.log p.pl "$NOLINE"`" 6

derive p.info 's/^DA:3,1/DA:3,0/;s/^BRDA:4,0,0,0/BRDA:4,0,0,1/' p2.info
run perl2 0 -a p2.info $MERGE --ignore inconsistent
if ! grep -q "\"p.pl\":3: $AFTER from line 4 onto this statement: $BRANCH_NO_HIT" perl2.log ; then
    fail perl2 "expected the branches of line 3 to be reported"
fi

# ----------------------------------------------------------------------
# Python:  a logical line spans physical lines inside parentheses or after a
#   backslash
# ----------------------------------------------------------------------
#   2-3   merged onto 2
#   4-5   merged onto 4:  executed, but no branch is taken
#   6-7   a string which spans lines:  not known
#   8-10  merged onto 8 - but not with lookahead 1
#   13-14 merged onto 13:  neither the '(' of the comment nor the ')' of the
#         string is a parenthesis
mkinfo py.info <<'EOF'
TN:
SF:p.py
FN:1,11,f
FNDA:1,f
FN:12,15,g
FNDA:1,g
DA:1,1
DA:2,1
DA:4,1
DA:6,1
DA:8,1
DA:11,1
DA:12,1
DA:13,1
DA:15,1
BRDA:3,0,0,1
BRDA:3,0,1,0
BRDA:5,0,0,0
BRDA:5,0,1,0
BRDA:7,0,0,1
BRDA:7,0,1,0
BRDA:10,0,0,1
BRDA:10,0,1,0
BRDA:14,0,0,1
BRDA:14,0,1,0
end_of_record
EOF
run python 0 -a py.info $MERGE --ignore inconsistent -v
expect python 'merged' "`said python.log p.py "$MERGED"`" '3 5 10 14'
expect python 'reported' "`said python.log p.py "$AFTER"`" 4
expect python 'kept' "`said python.log p.py "$NOLINE"`" 7

run python_lookahead 0 -a py.info $MERGE --ignore inconsistent -v \
    --rc filter_lookahead=1
expect python_lookahead 'merged' "`said python_lookahead.log p.py "$MERGED"`" \
    '3 5 14'
expect python_lookahead 'kept' "`said python_lookahead.log p.py "$NOLINE"`" \
    '7 10'

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    generate_coverage 'branchmerge' $LOCAL_COVERAGE 1
fi
exit $STATUS
