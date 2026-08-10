#!/bin/bash

set +x

source ../../common.tst

rm -rf out1.info out2.info repeat.info repeat_out.info repeat_html \
    aliasline.c aliasline_out.info aliasfn_out.info aliaserase_out.info \
    aliasfix.c aliasfix.info aliasfix_out.info \
    orphanmcdc.info orphanmcdc_html orphanmcdc2.info orphanmcdc2_out.info \
    alias*.info nomcdc.info nomcdc_out.info \
    mcdconly.info mcdconly_out.info nobranch_out.info \
    shared*.info sharedb*.info exc*.info naivecb.pm naivecb_out.info \
    missing_*.info missing*_out.info \
    diverge*.info *.log

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

LCOV_OPTS="--mcdc --branch"

$COVER $LCOV_TOOL $LCOV_OPTS --summary in.info 2>&1 | tee summary.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo 'lcov --summary failed'
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep '2 of 2 branches' summary.log
if [ 0 != $? ] ; then
    echo "didn't find expected branch count"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep '2 of 2 conditions' summary.log
if [ 0 != $? ] ; then
    echo "didn't find expected MCDC count"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -a in.info -o out1.info
for key in BRDA MCDC ; do
    COUNT=`grep -c $key out1.info`
    if [ $COUNT != 4 ] ; then
	echo "didn't find expected $key count 4: (found $COUNT)"
	if [ $KEEP_GOING == 0 ] ; then
            exit 1
	fi
    fi
done

$COVER $LCOV_TOOL $LCOV_OPTS -a in.info -forget-test-names -o out2.info
for key in BRDA MCDC ; do
    COUNT=`grep -c $key out2.info`
    if [ $COUNT != 2 ] ; then
	echo "didn't find expected $key count 2: (found $COUNT)"
	if [ $KEEP_GOING == 0 ] ; then
            exit 1
	fi
    fi
done

#
# The reader accumulates each section's records into a scratch map - one per
# coverage type - and then merges that map into both the per-testcase data and
# the summary.  It now hands the scratch map to the per-testcase data outright
# when that map is still empty - which is the whole point, since a union into an
# empty destination is just a deep copy - and only the summary takes the copy.
# Two arms result, and both need covering:
#   - a testname seen for the FIRST time takes the hand-over;
#   - a testname seen AGAIN (a second 'SF:' section for the same file and
#     testname) must union into the map that is already there, not replace it,
#     or the first section's data is lost.
# 'in.info' above only ever reaches the first arm.  The input below repeats
# 'test_a' for the same file, so a replace would silently drop the first
# section's data.
#
# Line and function data used to have no scratch map at all:  the reader wrote
# straight into the per-testcase map and unioned that into the summary once per
# section.  On a repeated testname the per-testcase map already held the earlier
# section by then - 'CountData::append' and 'FunctionEntry::addAlias' both ADD -
# so the summary got a running total instead of this section's contribution.
# Hence line 6 and function 'foo' below, which BOTH sections hit:  5 then 3, so
# the per-testcase count is 8 and the summary must be 8 as well.  It read 13
# (5 + 8) before the fix.  '.info' output cannot show this - 'write_info' emits
# only per-testcase maps - so the summary is checked through genhtml, which
# renders it as the per-line count, and through the '--summary' rates.
# Lines 3 and 4 are hit by one section each, which is the case that was always
# right and has to stay right.
#
cat > repeat.info <<'EOF'
TN:test_a
SF:./test.c
FN:1,7,foo
FNDA:5,foo
FNF:1
FNH:1
BRDA:3,0,0,1
BRDA:3,0,1,0
BRF:2
BRH:1
MCDC:3,1,t,1,0,a
MCDC:3,1,f,0,0,a
MCF:2
MCH:1
DA:1,5
DA:3,2
DA:6,5
LF:3
LH:3
end_of_record
TN:test_a
SF:./test.c
FN:1,7,foo
FNDA:3,foo
FNF:1
FNH:1
BRDA:4,0,0,0
BRDA:4,0,1,7
BRF:2
BRH:1
MCDC:4,1,t,0,0,b
MCDC:4,1,f,7,0,b
MCF:2
MCH:1
DA:1,3
DA:4,7
DA:6,3
LF:3
LH:3
end_of_record
EOF

REPEAT_IGNORE="--ignore source,inconsistent,unused,empty"
$COVER $LCOV_TOOL $LCOV_OPTS -a repeat.info -o repeat_out.info $REPEAT_IGNORE \
    2>&1 | tee repeat.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "lcov -a failed for the repeated-testname case"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# a single testcase section holding BOTH lines' coverpoints
COUNT=`grep -c '^TN:' repeat_out.info`
if [ 1 != "$COUNT" ] ; then
    echo "expected a single testcase in the repeated-testname output, got $COUNT"
    cat repeat_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for EXPECT in 'BRDA:3,0,0,1' 'BRDA:3,0,1,0' 'BRDA:4,0,0,0' 'BRDA:4,0,1,7' \
              'BRF:4' 'BRH:2' \
              'MCDC:3,1,t,1,0,a' 'MCDC:3,1,f,0,0,a' \
              'MCDC:4,1,t,0,0,b' 'MCDC:4,1,f,7,0,b' \
              'MCF:4' 'MCH:2' \
              'DA:1,8' 'DA:3,2' 'DA:4,7' 'DA:6,8' 'FNA:0,8,foo' \
              'LF:4' 'LH:4' ; do
    grep -qxF "$EXPECT" repeat_out.info
    if [ 0 != $? ] ; then
        echo "repeated-testname output is missing '$EXPECT':"
        cat repeat_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
# ...and the summary, which is what the aggregate map feeds, agrees
for EXPECT in '  lines.......: 100.0% (4 of 4 lines)' \
              '  functions...: 100.0% (1 of 1 function)' \
              '  branches....: 50.0% (2 of 4 branches)' \
              '  conditions..: 50.0% (2 of 4 conditions)' ; do
    grep -qF "$EXPECT" repeat.log
    if [ 0 != $? ] ; then
        echo "unexpected aggregate summary rate for the repeated testname:"
        echo "  expected '$EXPECT'"
        cat repeat.log
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

# The rates above are found/hit ratios, so they cannot distinguish a summary
#  count of 8 from one of 13 - both are 'hit'.  genhtml renders the summary
#  count itself, which is the only place the wrong value is visible.
$COVER $GENHTML_TOOL $LCOV_OPTS -o repeat_html repeat.info $REPEAT_IGNORE \
    2>&1 | tee repeat_html.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "genhtml failed for the repeated-testname case"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
REPEAT_SOURCE=`find repeat_html -name 'test.c.gcov.html'`
if [ -z "$REPEAT_SOURCE" ] ; then
    echo "genhtml wrote no annotated source for the repeated testname"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
else
    # both sections hit line 6 - 5 then 3 - so the count rendered against
    #  'return 0' must be 8.  It was 13 (5 + 8) before the fix.
    COUNT=`grep -F 'return 0;' $REPEAT_SOURCE | \
           sed -e 's|.*">  *\([0-9]*\) :.*|\1|'`
    if [ "8" != "$COUNT" ] ; then
        echo "genhtml rendered summary count '$COUNT' for line 6; expected 8"
        grep -F 'return 0;' $REPEAT_SOURCE
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
fi

#
# The summary branch map ALIASED to the single testcase's map.
#
# For one testcase the summary is a bit-identical copy of that testcase's data,
# so the reader now keeps just one map and points both at it.  Anything that
# goes on to mutate the two as independent objects has to break the alias first
# ('materializeAggregates'), or it applies its mutation twice to one
# object.  The two failure modes are quite different, so both are provoked:
#   - a MERGE applied twice silently doubles every count;
#   - a REMOVE applied twice dies, because the second one finds the line gone.
# 'in.info' at the top of this file has two testcases and so never aliases.
#
cat > alias1.info <<'EOF'
TN:test_a
SF:./test.c
BRDA:3,0,0,1
BRDA:3,0,1,0
BRF:2
BRH:1
MCDC:3,1,t,1,0,a
MCDC:3,1,f,0,0,a
MCF:2
MCH:1
DA:1,1
DA:3,1
DA:4,1
DA:6,0
LF:4
LH:3
end_of_record
EOF

# same shape, different counts:  merging the two must ADD them once, not twice
sed -e 's/^BRDA:3,0,0,1$/BRDA:3,0,0,4/' -e 's/^MCDC:3,1,t,1,0,a$/MCDC:3,1,t,4,0,a/' \
    alias1.info > alias2.info

ALIAS_IGNORE="--ignore inconsistent,unused,empty,unsupported"

# 'lcov -a f1 -a f2' goes through TraceInfo::merge, which merges each
#  per-testcase map and then the summary separately - the double-merge hazard.
$COVER $LCOV_TOOL $LCOV_OPTS -a alias1.info -a alias2.info -o aliasm.info \
    $ALIAS_IGNORE 2>&1 | tee aliasm.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "lcov -a failed for the aliased-summary merge"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# 1+4 == 5.  Applied twice it would read 9 (1+4+4): the summary and the
#  per-testcase map are the same object, so the second merge adds again.
for EXPECT in 'BRDA:3,0,0,5' 'BRDA:3,0,1,0' 'BRF:2' 'BRH:1' \
              'MCDC:3,1,t,5,0,a' 'MCDC:3,1,f,0,0,a' 'MCF:2' 'MCH:1' ; do
    grep -qxF "$EXPECT" aliasm.info
    if [ 0 != $? ] ; then
        echo "aliased-summary merge output is missing '$EXPECT':"
        cat aliasm.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
grep -q '  branches....: 50.0% (1 of 2 branches)' aliasm.log
if [ 0 != $? ] ; then
    echo "unexpected branch count for the aliased-summary merge"
    cat aliasm.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# A filter which DROPS a coverpoint removes it from every per-testcase map and
#  then from the summary, with no 'is it present' check on the latter - so an
#  un-broken alias dies rather than miscounting.  Line 6 of 'test.c' is a plain
#  'return', so the 'branch' filter removes the branch data there.
cat > aliasf.info <<'EOF'
TN:test_a
SF:./test.c
BRDA:3,0,0,1
BRDA:3,0,1,0
BRDA:6,0,0,3
BRDA:6,0,1,0
BRF:4
BRH:2
DA:1,1
DA:3,1
DA:4,1
DA:6,3
LF:4
LH:4
end_of_record
EOF

$COVER $LCOV_TOOL --branch -a aliasf.info --filter branch -o aliasf_out.info \
    $ALIAS_IGNORE 2>&1 | tee aliasf.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "lcov --filter branch failed for the aliased summary"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for EXPECT in 'BRDA:3,0,0,1' 'BRDA:3,0,1,0' 'BRF:2' 'BRH:1' ; do
    grep -qxF "$EXPECT" aliasf_out.info
    if [ 0 != $? ] ; then
        echo "aliased-summary filter output is missing '$EXPECT':"
        cat aliasf_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
grep -qxF 'BRDA:6,0,0,3' aliasf_out.info
if [ 0 == $? ] ; then
    echo "the 'branch' filter did not remove the line 6 branch data:"
    cat aliasf_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#
# A file with branch data but NO MC/DC data at all, filtered with 'mcdc'.
#
# The reader only creates a per-testcase MC/DC map for a section that actually
# carries 'MCDC:' records, but the filter loop below is entered for branch data
# alone - so the 'mcdc' filter has to tolerate an undefined map rather than
# calling a method on it.
#
cat > nomcdc.info <<'EOF'
TN:test_a
SF:./test.c
BRDA:3,0,0,1
BRDA:3,0,1,0
BRF:2
BRH:1
DA:1,1
DA:3,1
DA:4,1
DA:6,0
LF:4
LH:3
end_of_record
EOF

$COVER $LCOV_TOOL $LCOV_OPTS -a nomcdc.info --filter mcdc -o nomcdc_out.info \
    $ALIAS_IGNORE 2>&1 | tee nomcdc.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "lcov --filter mcdc failed on a file with no MC/DC data"
    cat nomcdc.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for EXPECT in 'BRDA:3,0,0,1' 'BRDA:3,0,1,0' 'BRF:2' 'BRH:1' ; do
    grep -qxF "$EXPECT" nomcdc_out.info
    if [ 0 != $? ] ; then
        echo "no-MC/DC output is missing '$EXPECT':"
        cat nomcdc_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

#
# The same aliasing, for the MC/DC summary.
#
# The MC/DC data has exactly the shape the branch data has - a summary plus a
# map of testname -> map - so it gets the same treatment and needs the same
# coverage.  These cases are kept separate from the branch ones above rather
# than folded into them, so that a failure says which of the two aggregates
# broke.  'aliasm.info' above happens to carry both, which covers the merge
# hazard for MC/DC; what is left is a filter which DROPS an MC/DC coverpoint
# while the summary is aliased, and the reader arm where a second testname
# arrives.
#
# The 'mcdc' filter removes a single-condition MC/DC when there is a matching
# branch expression on the same line - so the input needs both, on line 3, and
# the MC/DC record is what comes out.  Un-materialized, the second removal of
# that line dies on 'undef->totals()' (verified by reverting just the
# 'materializeAggregates' call in '_filterFile':  this input then fails).
#
cat > aliasmf.info <<'EOF'
TN:test_a
SF:./test.c
BRDA:3,0,0,1
BRDA:3,0,1,0
BRF:2
BRH:1
MCDC:3,1,t,1,0,a
MCDC:3,1,f,0,0,a
MCF:2
MCH:1
DA:1,1
DA:3,1
DA:4,1
DA:6,0
LF:4
LH:3
end_of_record
EOF

$COVER $LCOV_TOOL $LCOV_OPTS -a aliasmf.info --filter mcdc -o aliasmf_out.info \
    $ALIAS_IGNORE 2>&1 | tee aliasmf.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "lcov --filter mcdc failed for the aliased MC/DC summary"
    cat aliasmf.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# the branch data is untouched...
for EXPECT in 'BRDA:3,0,0,1' 'BRDA:3,0,1,0' 'BRF:2' 'BRH:1' ; do
    grep -qxF "$EXPECT" aliasmf_out.info
    if [ 0 != $? ] ; then
        echo "aliased MC/DC filter output is missing '$EXPECT':"
        cat aliasmf_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
# ...and the MC/DC record is gone, from the per-testcase data and the summary
grep -q '^MCDC:' aliasmf_out.info
if [ 0 == $? ] ; then
    echo "the 'mcdc' filter did not remove the single-condition MC/DC:"
    cat aliasmf_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -q '  conditions..: no data found' aliasmf.log
if [ 0 != $? ] ; then
    echo "the aliased MC/DC summary still reports conditions after filtering"
    cat aliasmf.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#
# The same 'mcdc' filter with '--mcdc' but NOT '--branch'.
#
# The filter looks for a branch expression on the same line, so it reaches for
# the per-testcase branch map - which does not exist at all when branch coverage
# is off, and the filter has to tolerate that rather than calling a method on
# it.  Same shape as the 'nomcdc.info' case below, with the roles swapped.
#
$COVER $LCOV_TOOL --mcdc -a aliasmf.info --filter mcdc -o nobranch_out.info \
    $ALIAS_IGNORE 2>&1 | tee nobranch.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "lcov --filter mcdc failed with branch coverage disabled"
    cat nobranch.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# with no branch data to match against, the MC/DC record stays
for EXPECT in 'MCDC:3,1,t,1,0,a' 'MCDC:3,1,f,0,0,a' 'MCF:2' 'MCH:1' ; do
    grep -qxF "$EXPECT" nobranch_out.info
    if [ 0 != $? ] ; then
        echo "no-branch output is missing '$EXPECT':"
        cat nobranch_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

#
# A second 'SF:' section for a testname already seen, with MC/DC data on a
# DIFFERENT line - the reader arm which must union into the map that is already
# there rather than replacing it.  'repeat.info' above covers this for both
# aggregates at once; here the file carries MC/DC only, so the branch data
# cannot mask a fault in the MC/DC path.
#
cat > mcdconly.info <<'EOF'
TN:test_a
SF:./test.c
MCDC:3,1,t,1,0,a
MCDC:3,1,f,0,0,a
MCF:2
MCH:1
DA:3,1
LF:1
LH:1
end_of_record
TN:test_a
SF:./test.c
MCDC:4,1,t,0,0,b
MCDC:4,1,f,7,0,b
MCF:2
MCH:1
DA:4,7
LF:1
LH:1
end_of_record
EOF

$COVER $LCOV_TOOL --mcdc -a mcdconly.info -o mcdconly_out.info $REPEAT_IGNORE \
    2>&1 | tee mcdconly.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "lcov -a failed for the repeated-testname MC/DC-only case"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for EXPECT in 'MCDC:3,1,t,1,0,a' 'MCDC:3,1,f,0,0,a' \
              'MCDC:4,1,t,0,0,b' 'MCDC:4,1,f,7,0,b' \
              'MCF:4' 'MCH:2' ; do
    grep -qxF "$EXPECT" mcdconly_out.info
    if [ 0 != $? ] ; then
        echo "repeated-testname MC/DC output is missing '$EXPECT':"
        cat mcdconly_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
grep -q '  conditions..: 50.0% (2 of 4 conditions)' mcdconly.log
if [ 0 != $? ] ; then
    echo "unexpected aggregate condition count for the MC/DC-only repeat"
    cat mcdconly.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#
# Filtering while the summary is ALIASED, and the same filtering when it is not.
#
# A filter applies the identical removal to each per-testcase map and to the
# summary.  When the summary is aliased to the single testcase's map those are
# one object, so the removal is done once and the second pass is skipped - see
# 'TraceInfo::isAliased'.  Two things then need asserting, because a wrong
# decision either way is easy to make and quiet:
#   - with ONE testcase the coverpoint must actually be gone from the output
#     (skipping the second pass must not mean skipping the removal);
#   - with TWO testcases nothing is aliased, so BOTH passes must still run -
#     otherwise the summary keeps a coverpoint the per-testcase data has lost,
#     and the summary counts come out too high.
# The second case also covers a hazard which has nothing to do with aliasing:
# the loop below runs once per testcase, so the summary removal has to be
# present-checked or the second testcase finds the line already gone and dies.
#
# Line 3 carries a 2-branch BRDA and a single-condition MC/DC, which is what the
# 'mcdc' filter looks for; 'shared2.info' is the same file for two testnames.
#
cat > shared1.info <<'EOF'
TN:test_a
SF:./test.c
BRDA:3,0,0,1
BRDA:3,0,1,0
BRF:2
BRH:1
MCDC:3,1,t,1,0,a
MCDC:3,1,f,0,0,a
MCF:2
MCH:1
DA:1,1
DA:3,1
DA:4,1
DA:6,0
LF:4
LH:3
end_of_record
EOF
sed -e 's/^TN:test_a$/TN:test_b/' shared1.info > shared_b.info
cat shared1.info shared_b.info > shared2.info

# one testcase: aliased - the MC/DC must still be removed
$COVER $LCOV_TOOL $LCOV_OPTS -a shared1.info --filter mcdc \
    -o shared1_out.info $ALIAS_IGNORE 2>&1 | tee shared1.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "lcov --filter mcdc failed for the single-testcase shared line"
    cat shared1.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -q '^MCDC:' shared1_out.info
if [ 0 == $? ] ; then
    echo "aliased: the 'mcdc' filter did not remove the coverpoint:"
    cat shared1_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -q '  conditions..: no data found' shared1.log
if [ 0 != $? ] ; then
    echo "aliased: summary still reports conditions after filtering"
    cat shared1.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# two testcases: NOT aliased - both passes must run, and the repeated summary
#  removal must not die
$COVER $LCOV_TOOL $LCOV_OPTS -a shared2.info --filter mcdc \
    -o shared2_out.info $ALIAS_IGNORE 2>&1 | tee shared2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "lcov --filter mcdc failed for the two-testcase shared line"
    cat shared2.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
COUNT=`grep -c '^TN:' shared2_out.info`
if [ 2 != "$COUNT" ] ; then
    echo "expected both testcases in the output, got $COUNT"
    cat shared2_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -q '^MCDC:' shared2_out.info
if [ 0 == $? ] ; then
    echo "not aliased: the 'mcdc' filter did not remove the coverpoint:"
    cat shared2_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# the summary is what this asserts:  if only the per-testcase maps were filtered
#  the summary would still hold the MC/DC and report 2 conditions
grep -q '  conditions..: no data found' shared2.log
if [ 0 != $? ] ; then
    echo "not aliased: summary still reports conditions after filtering"
    cat shared2.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#
# The same two cases for the 'branch' filter, which reaches the summary through
# a different site than the 'mcdc' filter above.
#
# Line 6 of 'test.c' is a plain 'return', so the branch histogram removes the
# branch data there and leaves line 3's.  With two testcases nothing is aliased
# and the summary needs its own removal:  without it the summary still holds
# line 6 and reports 4 branches where the per-testcase data has 2.
#
cat > sharedb1.info <<'EOF'
TN:test_a
SF:./test.c
BRDA:3,0,0,1
BRDA:3,0,1,0
BRDA:6,0,0,3
BRDA:6,0,1,0
BRF:4
BRH:2
DA:1,1
DA:3,1
DA:4,1
DA:6,3
LF:4
LH:4
end_of_record
EOF
sed -e 's/^TN:test_a$/TN:test_b/' sharedb1.info > sharedb_b.info
cat sharedb1.info sharedb_b.info > sharedb2.info

for pair in 'sharedb1.info 1' 'sharedb2.info 2' ; do
    set -- $pair
    INF=$1
    NTEST=$2
    $COVER $LCOV_TOOL --branch -a $INF --filter branch \
        -o ${INF%.info}_out.info $ALIAS_IGNORE 2>&1 | tee ${INF%.info}_br.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "lcov --filter branch failed for $INF"
        cat ${INF%.info}_br.log
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    # line 6's branch data is gone, line 3's remains
    grep -qxF 'BRDA:6,0,0,3' ${INF%.info}_out.info
    if [ 0 == $? ] ; then
        echo "$INF: the 'branch' filter did not remove the line 6 data:"
        cat ${INF%.info}_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    for EXPECT in 'BRDA:3,0,0,1' 'BRDA:3,0,1,0' 'BRF:2' 'BRH:1' ; do
        grep -qxF "$EXPECT" ${INF%.info}_out.info
        if [ 0 != $? ] ; then
            echo "$INF: filtered output is missing '$EXPECT':"
            cat ${INF%.info}_out.info
            if [ $KEEP_GOING == 0 ] ; then
                exit 1
            fi
        fi
    done
    # The summary is the assertion that matters:  it must agree with the
    #  per-testcase data, not still carry line 6.
    grep -q '  branches....: 50.0% (1 of 2 branches)' ${INF%.info}_br.log
    if [ 0 != $? ] ; then
        echo "$INF: summary branch count disagrees with the filtered data"
        cat ${INF%.info}_br.log
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

#
# The exception-branch filter, aliased and not.
#
# 'FilterBranchExceptions::applyFilter' filters the summary and then each
# per-testcase map, and skips the per-testcase pass which IS the summary pass
# when the two are aliased.  It also tallies every coverpoint it excludes on
# every pass, so the one remaining pass has to carry the weight of the two it
# replaces or the reported coverpoint total drops.  Both the data and that
# reported total are asserted, for one testcase and for two.
#
# Line 3's exception branch ('e0') is the one the filter removes, leaving the
# vanilla pair on line 4.
#
cat > exc1.info <<'EOF'
TN:test_a
SF:./test.c
BRDA:3,0,0,1
BRDA:3,e0,1,0
BRDA:4,0,0,1
BRDA:4,0,1,1
BRF:4
BRH:3
DA:1,1
DA:3,1
DA:4,1
DA:6,0
LF:4
LH:3
end_of_record
EOF
sed -e 's/^TN:test_a$/TN:test_b/' exc1.info > exc_b.info
cat exc1.info exc_b.info > exc2.info

# The expected coverpoint tally is one per pass over the data, and the number of
#  passes is what aliasing changes:  with one testcase the summary IS that
#  testcase's map, so there is a single pass which counts double (2); with two
#  testcases there is a summary pass plus one per testcase (3).  Getting this
#  wrong in either direction - a dropped pass, or a dropped pass weight - moves
#  these numbers, which is exactly what they are here to catch.
for pair in 'exc1.info 1 2' 'exc2.info 2 3' ; do
    set -- $pair
    INF=$1
    NTEST=$2
    EXPECT_CP=$3
    $COVER $LCOV_TOOL --branch -a $INF --filter exception \
        -o ${INF%.info}_out.info $ALIAS_IGNORE 2>&1 | tee ${INF%.info}_exc.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "lcov --filter exception failed for $INF"
        cat ${INF%.info}_exc.log
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    # The exception branch is marked excluded rather than deleted - 'e0' becomes
    #  'eU0' - so it stays in the output and stops being counted:  4 branches
    #  become 3.  The vanilla pair on line 4 is untouched.
    grep -qxF 'BRDA:3,eU0,1,0' ${INF%.info}_out.info
    if [ 0 != $? ] ; then
        echo "$INF: the exception branch was not excluded:"
        cat ${INF%.info}_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    for EXPECT in 'BRDA:4,0,0,1' 'BRDA:4,0,1,1' 'BRF:3' 'BRH:3' ; do
        grep -qxF "$EXPECT" ${INF%.info}_out.info
        if [ 0 != $? ] ; then
            echo "$INF: filtered output is missing '$EXPECT':"
            cat ${INF%.info}_out.info
            if [ $KEEP_GOING == 0 ] ; then
                exit 1
            fi
        fi
    done
    COUNT=`grep -c '^TN:' ${INF%.info}_out.info`
    if [ "$NTEST" != "$COUNT" ] ; then
        echo "$INF: expected $NTEST testcases after filtering, got $COUNT"
        cat ${INF%.info}_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    grep -q "$EXPECT_CP coverpoints" ${INF%.info}_exc.log
    if [ 0 != $? ] ; then
        echo "$INF: expected '$EXPECT_CP coverpoints' in the exception filter tally"
        cat ${INF%.info}_exc.log
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

#
# The user coverpoint callback, with an aliased summary.
#
# '--unreachable-script' hands the callback the summary map and the per-testcase
# map and lets it mutate both.  Unlike a filter, what it does is not knowable
# here, so it cannot be given one object twice:  it gets two independent ones,
# which means breaking the alias.
#
# The shipped 'scripts/unreach.pm' would survive an alias by luck - it mutates
# through 'set_excluded', which returns false the second time and so guards its
# own count adjustment - and therefore cannot detect whether the alias was
# broken.  The callback below is deliberately NOT idempotent, in the way a
# reasonable callback might not be:  it adjusts the counts of whichever map it
# is handed, once per call, with no 'already done' guard.  With the alias left
# in place both calls hit one map and the cached branch count goes negative.
#
cat > naivecb.pm <<'PERL'
package naivecb;

# A minimal '--unreachable-script' callback whose mutation is not idempotent.
sub new
{
    my $class = shift;
    my $self  = [];
    return bless $self, $class;
}
sub start { }
sub end   { }

sub exclude
{
    my ($self, $type, $reader, $testdata, $summary) = @_;
    return 0 unless $type eq 'branch';
    my $changed = 0;
    foreach my $line ($summary->keylist()) {
        # once for the summary, once for each testcase which has this line -
        #   which is the same object, twice, if the two are aliased
        $summary->adjust_counts(-1, 0);
        foreach my $tn ($testdata->keylist()) {
            my $d = $testdata->value($tn);
            next unless defined($d->value($line));
            $d->adjust_counts(-1, 0);
        }
        $changed = 1;
    }
    return $changed;
}

1;
PERL

# one testcase, so the summary is aliased when the callback is reached
CB_IGNORE="--ignore inconsistent,unused,empty,unsupported,callback,usage,unreachable"
PERL5LIB=. $COVER $LCOV_TOOL --branch -a sharedb1.info \
    --unreachable-script ./naivecb.pm -o naivecb_out.info $CB_IGNORE 2>&1 |
    tee naivecb.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "lcov --unreachable-script failed for the aliased summary"
    cat naivecb.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# 'sharedb1.info' has 2 branch lines x 2 branches; the callback removes one
#  'found' per map per line, so 4 - 2 == 2 remain.  Reached through an alias the
#  subtraction lands twice on one map and the count goes to 0 or below, which
#  shows up as a negative or nonsensical percentage.
grep -q 'branches' naivecb.log
if [ 0 != $? ] ; then
    echo "expected a branch summary line from the callback run"
    cat naivecb.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -qE 'branches.*: -|of -[0-9]+ branches' naivecb.log
if [ 0 == $? ] ; then
    echo "callback saw an aliased summary: branch count went negative"
    cat naivecb.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#
# DIVERGENT per-slot aliasing:  branch not aliased, MC/DC aliased, in one file.
#
# It would be convenient if aliasing were a property of the whole file - one
# testname means everything present is aliased - because then one question could
# be asked once instead of per coverage type.  It is not:  the reader installs
# an alias for a type only when that type's per-testcase map and its summary are
# both still empty, so the count of testnames carrying each type is what decides
# it, and the types need not agree.
#
# No capture produces this, since a capture writes a single section per source
# file and so installs each type exactly once.  It takes a merge:  a file with
# one testname carrying branch data, merged with a file with two testnames where
# the first carries branch and MC/DC data and the second carries MC/DC data but
# no branch data.  The input below is that merge result - two testnames, both
# with branch data, only one with MC/DC:
#   - branch data was installed for two testnames, so the summary is a real
#     merge of the two and is NOT aliased;
#   - MC/DC data was installed for one testname only, so its summary IS that
#     testname's map.
#
# Both coverage types are then filtered in the same run, on the same line, one
# aliased and one not.  A single whole-file answer is wrong here whichever way
# it goes:  'not aliased' means the MC/DC line is removed from one map twice and
# dies in 'BranchMap::remove'; 'aliased' means the branch summary never gets
# filtered and keeps reporting the coverpoint the per-testcase data dropped.
# Line 6 is a plain 'return', so the 'branch' filter drops its branch data,
# while the 'mcdc' filter drops the single-condition MC/DC on line 3.
#
cat > diverge_a.info <<'EOF'
TN:test_a
SF:./test.c
BRDA:3,0,0,1
BRDA:3,0,1,0
BRDA:6,0,0,3
BRDA:6,0,1,1
BRF:4
BRH:3
MCDC:3,1,t,1,0,a
MCDC:3,1,f,0,0,a
MCF:2
MCH:1
DA:1,1
DA:3,1
DA:4,1
DA:6,3
LF:4
LH:4
end_of_record
EOF
# test_b carries the same branch data but no MC/DC at all
sed -e 's/^TN:test_a$/TN:test_b/' -e '/^MCDC:/d' -e '/^MC[FH]:/d' \
    diverge_a.info > diverge_b.info
cat diverge_a.info diverge_b.info > diverge.info

$COVER $LCOV_TOOL --branch --mcdc -a diverge.info --filter branch,mcdc \
    -o diverge_out.info $ALIAS_IGNORE 2>&1 | tee diverge.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "lcov --filter branch,mcdc failed for divergent per-slot aliasing"
    cat diverge.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# both testnames survive
for EXPECT in 'TN:test_a' 'TN:test_b' ; do
    grep -qxF "$EXPECT" diverge_out.info
    if [ 0 != $? ] ; then
        echo "divergent filter output is missing '$EXPECT':"
        cat diverge_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
# the non-aliased branch summary was filtered:  line 6 is gone, line 3 remains
grep -qxF 'BRDA:6,0,0,3' diverge_out.info
if [ 0 == $? ] ; then
    echo "divergent: the 'branch' filter did not remove the line 6 data:"
    cat diverge_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for EXPECT in 'BRDA:3,0,0,1' 'BRDA:3,0,1,0' 'BRF:2' 'BRH:1' ; do
    grep -qxF "$EXPECT" diverge_out.info
    if [ 0 != $? ] ; then
        echo "divergent filter output is missing '$EXPECT':"
        cat diverge_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
# the aliased MC/DC data is gone
grep -q '^MCDC:' diverge_out.info
if [ 0 == $? ] ; then
    echo "divergent: the 'mcdc' filter did not remove the MC/DC coverpoint:"
    cat diverge_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# and the reported summaries agree with the filtered data, for both types:  the
#  branch summary would still say '3 of 4' had the non-aliased summary been
#  skipped as though it were aliased
grep -q '  branches....: 50.0% (1 of 2 branches)' diverge.log
if [ 0 != $? ] ; then
    echo "divergent: branch summary disagrees with the filtered data"
    cat diverge.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -q '  conditions..: no data found' diverge.log
if [ 0 != $? ] ; then
    echo "divergent: MC/DC summary still reports conditions after filtering"
    cat diverge.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#
# The LINE and FUNCTION summaries, aliased.
#
# Line and function data get the same treatment as branch and MC/DC: for a
# single testname their summary is that testname's map.  Every place which
# mutates a summary and the per-testcase maps as two steps has to account for
# it, and three of those places are specific to these two types.  Two of the
# three fail SILENTLY - the counts come out wrong but nothing complains - so
# each is provoked separately and the resulting count asserted.
#
# 1. The line filter's removal.  'CountData::remove' dies on a line that is not
#    there, so a removal repeated on one map is loud.
# 2. The function filter's removal.  'FunctionMap::remove' is handed the undef
#    'findKey' returns for a function already gone, and dies on that.
# 3. Function exclusion ('--erase-function'), which is SILENT: the erase is
#    'remove if present', so the data is right either way, but the pattern-usage
#    statistics are only counted on the pass over the master map.  Reach that
#    map second and there is nothing left to match, so a pattern which did apply
#    is reported unused.
#
# 'aliasline.info' has a single testname and three functions:  'foo', whose body
# contains a '// LCOV_EXCL_LINE' on line 4 for the 'region' filter to drop;
# 'trivial' on line 8, which the 'trivial' function filter removes; and
# 'excluded' on line 9, whose DEFINITION line is excluded, so the 'region' filter
# drops the whole function.  That last one is the only way to reach the function
# removal inside the region/range filter loop - the 'trivial' filter and
# '--erase-function' both go through '_eraseFunctions' instead, which is a
# different removal and a different guard.
#
cat > aliasline.c <<'EOF'
int foo(int a)
{
    if (a) {
        return 1;    // LCOV_EXCL_LINE
    }
    return 0;
}
int trivial(void) { }
int excluded(void) { return 1; }    // LCOV_EXCL_LINE
EOF
cat > aliasline.info <<'EOF'
TN:test_a
SF:./aliasline.c
FN:1,7,foo
FNDA:5,foo
FN:8,8,trivial
FNDA:2,trivial
FN:9,9,excluded
FNDA:3,excluded
FNF:3
FNH:3
DA:1,5
DA:3,5
DA:4,1
DA:6,4
DA:8,2
DA:9,3
LF:6
LH:6
end_of_record
EOF

LINE_IGNORE="--ignore inconsistent,unused,empty,unsupported"

# 1. the line removal, with the summary aliased:  line 4 must be gone, and the
#    remaining counts must be untouched - a second removal would have died, and
#    'CountData' caches found/hit, so a mismatch is caught by
#    'CountData::_checkCounts' on the next read
$COVER $LCOV_TOOL -a aliasline.info --filter region -o aliasline_out.info \
    $LINE_IGNORE 2>&1 | tee aliasline.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "the 'region' filter failed with an aliased line summary"
    cat aliasline.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -qxF 'DA:4,1' aliasline_out.info
if [ 0 == $? ] ; then
    echo "the 'region' filter did not remove the excluded line:"
    cat aliasline_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for EXPECT in 'DA:1,5' 'DA:3,5' 'DA:6,4' 'DA:8,2' 'LF:4' 'LH:4' ; do
    grep -qxF "$EXPECT" aliasline_out.info
    if [ 0 != $? ] ; then
        echo "'region' filter output is missing '$EXPECT':"
        cat aliasline_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
# ...and the function whose definition line was excluded is gone with it.  This
#   is the removal in the region/range function loop:  reaching the aliased map a
#   second time hands 'FunctionMap::remove' the undef that 'findKey' returns for
#   a function which is already gone, and it dies with 'expected FunctionEntry'.
grep -q 'excluded' aliasline_out.info
if [ 0 == $? ] ; then
    echo "the 'region' filter did not remove the excluded function:"
    cat aliasline_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for EXPECT in foo trivial ; do
    grep -qF "$EXPECT" aliasline_out.info
    if [ 0 != $? ] ; then
        echo "the 'region' filter removed function '$EXPECT' as well:"
        cat aliasline_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
# ...and re-reading it is what runs 'CountData::_checkCounts' over the result
$COVER $LCOV_TOOL --summary aliasline_out.info $LINE_IGNORE 2>&1 |
    tee alialine_reread.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "re-reading the 'region' filter output failed"
    cat alialine_reread.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -q '  lines.......: 100.0% (4 of 4 lines)' alialine_reread.log
if [ 0 != $? ] ; then
    echo "unexpected line count after filtering an aliased summary"
    cat alialine_reread.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# 2. the function filter, with the summary aliased:  the trivial function is
#    removed once, from the one map both point at
$COVER $LCOV_TOOL -a aliasline.info --filter trivial -o aliasfn_out.info \
    $LINE_IGNORE 2>&1 | tee aliasfn.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "the 'trivial' filter failed with an aliased function summary"
    cat aliasfn.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -q 'trivial' aliasfn_out.info
if [ 0 == $? ] ; then
    echo "the 'trivial' filter did not remove the function:"
    cat aliasfn_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for EXPECT in foo excluded ; do
    grep -qF "$EXPECT" aliasfn_out.info
    if [ 0 != $? ] ; then
        echo "the 'trivial' filter removed function '$EXPECT' as well:"
        cat aliasfn_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
grep -q '  functions...: 100.0% (2 of 2 functions)' aliasfn.log
if [ 0 != $? ] ; then
    echo "unexpected function count after filtering an aliased summary"
    cat aliasfn.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# 3. '--erase-function' with the summary aliased.  The erase itself is not the
#    point - the pattern-usage statistic is.  Passing '--ignore unused' would
#    hide exactly the failure being tested, so this run does NOT ignore it:  an
#    unused-pattern ERROR is the symptom of the master pass having run second.
$COVER $LCOV_TOOL -a aliasline.info --erase-function 'trivial' \
    -o aliaserase_out.info --ignore inconsistent,empty,unsupported 2>&1 |
    tee aliaserase.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "'--erase-function' failed with an aliased function summary"
    cat aliaserase.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -q "(unused) 'exclude-functions' pattern" aliaserase.log
if [ 0 == $? ] ; then
    echo "'--erase-function' pattern reported unused, but it did apply:"
    cat aliaserase.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -q 'trivial' aliaserase_out.info
if [ 0 == $? ] ; then
    echo "'--erase-function' did not remove the function:"
    cat aliaserase_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# 4. the inconsistency repair, with the summary aliased.  'bar' is marked not hit
#    while lines inside it are, so '_checkConsistency' marks the function - and
#    each of its aliases - hit, in the summary map and in each per-testcase map
#    holding the same function.  The count is ASSIGNED but the aliases are ADDED
#    to, so with the summary aliased to the one testcase's map, reaching that one
#    object twice doubles every alias count.  This one is silent in the rates:
#    the function is 'hit' either way and only the count is wrong, so the check
#    has to be on the emitted 'FNA:' count itself.
cat > aliasfix.c <<'EOF'
int bar(int a)
{
    if (a) {
        return 1;
    }
    return 0;
}
EOF
cat > aliasfix.info <<'EOF'
TN:test_a
SF:./aliasfix.c
FN:1,7,bar
FNDA:0,bar
FNF:1
FNH:0
DA:1,0
DA:3,7
DA:6,7
LF:3
LH:2
end_of_record
EOF
$COVER $LCOV_TOOL -a aliasfix.info -o aliasfix_out.info $LINE_IGNORE 2>&1 |
    tee aliasfix.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "the inconsistency repair failed with an aliased function summary"
    cat aliasfix.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -qxF 'FNA:0,7,bar' aliasfix_out.info
if [ 0 != $? ] ; then
    echo "wrong function count after repairing an aliased summary; expected 7:"
    cat aliasfix_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#
# An orphan MC/DC coverpoint, with the line summary aliased.
#
# A line which carries MC/DC but no 'DA:' record is inconsistent, and
# '_checkConsistency' repairs it by fabricating the missing line coverpoint from
# the MC/DC hit count - in the summary and in each per-testcase map that has the
# MC/DC.  'CountData::append' ADDS, so with the summary aliased to the one
# testcase's map, fabricating it in both gives the line twice the count it
# should have.  This is SILENT: the line is 'hit' either way, so every rate
# still reads 100% and only the count itself is wrong.
#
# Line 3 below carries MC/DC hit once and no 'DA:3', so the fabricated count
# must be 1.  '.info' output cannot show it - the fabricated line goes to the
# summary, which 'write_info' does not emit - so it is read back through
# genhtml, which renders the summary count.
#
cat > orphanmcdc.info <<'EOF'
TN:test_a
SF:./test.c
MCDC:3,1,t,1,0,a
MCDC:3,1,f,0,0,a
MCF:2
MCH:1
DA:1,1
DA:4,1
LF:2
LH:2
end_of_record
EOF

$COVER $GENHTML_TOOL --mcdc --branch -o orphanmcdc_html orphanmcdc.info \
    $ALIAS_IGNORE 2>&1 | tee orphanmcdc.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "genhtml failed for the orphan MC/DC case"
    cat orphanmcdc.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# the input has two 'DA:' records, so a third line means line 3 was fabricated
grep -q '  lines.......: 100.0% (3 of 3 lines)' orphanmcdc.log
if [ 0 != $? ] ; then
    echo "the orphan MC/DC line coverpoint was not fabricated at all"
    cat orphanmcdc.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
ORPHAN_SOURCE=`find orphanmcdc_html -name 'test.c.gcov.html'`
if [ -z "$ORPHAN_SOURCE" ] ; then
    echo "genhtml wrote no annotated source for the orphan MC/DC case"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
else
    # line 3 is 'if (a) {':  its MC/DC was hit once, so the fabricated line
    #  count is 1.  It was 2 when the summary and the testcase map were both
    #  appended to through an alias.
    COUNT=`grep -F 'if (a) {' $ORPHAN_SOURCE | \
           sed -e 's|.*">  *\([0-9]*\) :.*|\1|'`
    if [ "1" != "$COUNT" ] ; then
        echo "orphan MC/DC fabricated line count is '$COUNT'; expected 1"
        grep -F 'if (a) {' $ORPHAN_SOURCE
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
fi

# The same fabrication with TWO testcases, so the summary is NOT aliased and the
# per-testcase append is the one that has to happen.  This is the other side of
# the guard above:  that case proves the skip happens when the summary and the
# testcase map are the same object, this one proves the append is not skipped
# when they are not.  'write_info' emits only the per-testcase maps, so the
# fabricated 'DA:3' appearing in BOTH sections is the direct evidence.
cat > orphanmcdc2.info <<'EOF'
TN:test_a
SF:./test.c
MCDC:3,1,t,1,0,a
MCDC:3,1,f,0,0,a
MCF:2
MCH:1
DA:1,1
DA:4,1
LF:2
LH:2
end_of_record
TN:test_b
SF:./test.c
MCDC:3,1,t,1,0,a
MCDC:3,1,f,0,0,a
MCF:2
MCH:1
DA:1,1
DA:4,1
LF:2
LH:2
end_of_record
EOF

$COVER $LCOV_TOOL -a orphanmcdc2.info -o orphanmcdc2_out.info --mcdc --branch \
    $LINE_IGNORE 2>&1 | tee orphanmcdc2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "the two-testcase orphan MC/DC case failed"
    cat orphanmcdc2.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# one fabricated 'DA:3,1' per testcase section, and each section's own line
#  totals updated to match
COUNT=`grep -cxF 'DA:3,1' orphanmcdc2_out.info`
if [ "2" != "$COUNT" ] ; then
    echo "found $COUNT fabricated 'DA:3,1' records; expected one per testcase"
    cat orphanmcdc2_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
COUNT=`grep -cxF 'LF:3' orphanmcdc2_out.info`
if [ "2" != "$COUNT" ] ; then
    echo "found $COUNT 'LF:3' records; expected one per testcase"
    cat orphanmcdc2_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# Coverage types which disagree about which testcases have data for a file.
#  'missing_a.info' has line, branch and MC/DC data for 'tc1'; 'missing_b.info'
#  has line and MC/DC for 'tc2'; 'missing_c.info' has only line data, for 'tc3'.
#  So after the merge the file has three testcases, but branch data for one of
#  them and MC/DC data for two - which 'TraceInfo::checkTestcaseData' has to
#  report, once per (sourcefile, covertype, testname).
cat > missing_a.info <<'EOF'
TN:tc1
SF:./test.c
DA:1,1
DA:3,1
DA:4,1
LF:3
LH:3
BRDA:3,0,0,1
BRDA:3,0,1,0
BRF:2
BRH:1
MCDC:3,1,t,1,0,a
MCDC:3,1,f,0,0,a
MCF:2
MCH:1
end_of_record
EOF
cat > missing_b.info <<'EOF'
TN:tc2
SF:./test.c
DA:1,1
DA:3,1
DA:4,1
LF:3
LH:3
MCDC:3,1,t,1,0,a
MCDC:3,1,f,0,0,a
MCF:2
MCH:1
end_of_record
EOF
cat > missing_c.info <<'EOF'
TN:tc3
SF:./test.c
DA:1,1
DA:3,1
DA:4,1
LF:3
LH:3
end_of_record
EOF

$COVER $LCOV_TOOL -a missing_a.info -a missing_b.info -a missing_c.info \
    -o missing_out.info $LCOV_OPTS --ignore unused,empty,unsupported \
    2>&1 | tee missing.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "the missing-per-testcase-data case failed"
    cat missing.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# 'tc2' and 'tc3' have no branch data; 'tc3' has no MC/DC.  Nothing is missing
#  line data, and 'tc1' is not missing anything.
for EXPECT in 'no branch data for tc2 in' \
              'no branch data for tc3 in' \
              'no MC/DC data for tc3 in' ; do
    COUNT=`grep -cF "$EXPECT" missing.log`
    if [ "1" != "$COUNT" ] ; then
        echo "found $COUNT '$EXPECT' warnings; expected exactly 1"
        cat missing.log
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
for UNEXPECTED in 'no line data for' 'data for tc1 in' ; do
    if grep -qF "$UNEXPECTED" missing.log ; then
        echo "unexpected '$UNEXPECTED' warning"
        cat missing.log
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
COUNT=`grep -cF '(inconsistent)' missing.log`
if [ "3" != "$COUNT" ] ; then
    echo "found $COUNT 'inconsistent' messages; expected 3"
    cat missing.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# ...and the data itself is untouched:  all three testcases still emitted, with
#  their own coverpoints
for EXPECT in 'TN:tc1' 'TN:tc2' 'TN:tc3' ; do
    if ! grep -qxF "$EXPECT" missing_out.info ; then
        echo "'$EXPECT' missing from the merged output"
        cat missing_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
COUNT=`grep -cxF 'BRF:2' missing_out.info`
if [ "1" != "$COUNT" ] ; then
    echo "found $COUNT 'BRF:2' records; expected 1 (only tc1 has branch data)"
    cat missing_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# A single coverage type which is absent from EVERY testcase is not an
#  inconsistency:  a tracefile with no branch data at all is ordinary.  Merge
#  two line-only files and expect silence.
$COVER $LCOV_TOOL -a missing_c.info -a missing_b.info -o missing2_out.info \
    --ignore unused,empty,unsupported 2>&1 | tee missing2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "the line-only merge failed"
    cat missing2.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
if grep -qF '(inconsistent)' missing2.log ; then
    echo "unexpected 'inconsistent' warning when branch/MC/DC are disabled"
    cat missing2.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# One testcase cannot disagree with itself, no matter how many types it lacks.
$COVER $LCOV_TOOL -a missing_c.info -o missing3_out.info $LCOV_OPTS \
    --ignore unused,empty,unsupported 2>&1 | tee missing3.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "the single-testcase line-only case failed"
    cat missing3.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
if grep -qF '(inconsistent)' missing3.log ; then
    echo "unexpected 'inconsistent' warning for a single testcase"
    cat missing3.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage names $LOCAL_COVERAGE
fi

echo "Tests passed"

