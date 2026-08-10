#!/bin/bash
# test lcov set operations

set +x

source ../../common.tst

rm -f *.txt* *.json dumper* intersect*.info gen.info func.info inconsistent.info diff* *.log setop*.info
rm -rf cover_db

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

LCOV_OPTS="--branch $PARALLEL $PROFILE --mcdc-coverage"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
    # and filter exception branches to avoid spurious differences for old compiler
    FILTER='--filter branch'
fi

status=0
# note that faked data is not consistent - but just ignoring the issue for now
$COVER $LCOV_TOOL $LCOV_OPTS -o intersect.info a.info --intersect b.info --ignore inconsistent
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from intersect"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
$COVER $LCOV_TOOL $LCOV_OPTS -o intersect_2.info b.info --intersect a.info --ignore inconsistent
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from intersect"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

diff intersect.info intersect_2.info
if [ 0 != $? ] ; then
    echo "Error:  expected reflexive but not"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

diff intersect.info intersect.gold
if [ 0 != $? ] ; then
    echo "Error:  unexpected mismatch:  intersect.gold"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


$COVER $LCOV_TOOL $LCOV_OPTS -o diff.info a.info --subtract b.info --ignore inconsistent
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from subtract"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
diff diff.info a_subtract_b.gold
if [ 0 != $? ] ; then
    echo "Error:  unexpected mismatch:  a_subtract_b.gold"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -o diff2.info b.info --subtract a.info --ignore inconsistent
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from subtract 2"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
diff diff2.info b_subtract_a.gold
if [ 0 != $? ] ; then
    echo "Error:  unexpected mismatch:  b_subtract_a.gold"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


# test some error messages...
$COVER $LCOV_TOOL $LCOV_OPTS -o x.info 'y.?info' --intersect a.info --ignore inconsistent
if [ 0 == $? ] ; then
    echo "Error:  expected error but did not see one"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
$COVER $LCOV_TOOL $LCOV_OPTS -o x.info a.info --intersect 'z.?info' --ignore inconsistent
if [ 0 == $? ] ; then
    echo "Error:  expected error but did not see one"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# test line coverpoint generation
$COVER $LCOV_TOOL $LCOV_OPTS -o gen.info -a mcdc.dat --ignore inconsistent
if [ 0 != $? ] ; then
    echo "Error:  MC/DC DA gen failed"

    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

for count in 'DA:6,0' 'LF:8' 'LH:2' ; do
    grep $count gen.info
    if [ 0 != $? ] ; then
        echo "Error:  didn't find expected count '$count' in MC/DC gen"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done


$COVER $LCOV_TOOL $LCOV_OPTS -o func.info -a functionBug_1.dat -a functionBug_2.dat --ignore inconsistent,empty
if [ 0 != $? ] ; then
    echo "Error:  function merge failed"

    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

for count in 'FNF:2' 'FNH:2' ; do
    grep $count func.info
    if [ 0 != $? ] ; then
        echo "Error:  didn't find expected count '$count' in function merge"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

$COVER $LCOV_TOOL $LCOV_OPTS -o inconsistent.info -a a.dat -a b.dat --ignore inconsistent,empty --msg-log inconsistent.log
if [ 0 != $? ] ; then
    echo "Error:  function merge2 failed"

    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E "duplicate function .+ starts on line .+ but previous definition" inconsistent.log
if [ 0 != $? ] ; then
    echo "Error:  didn't find definition message"

    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#
# Set operations on branch and MC/DC data with EXCLUDED coverpoints.
#
# union/intersect/difference used to end by rescanning the whole map to rebuild
# the cached found/hit; they now maintain it incrementally, so every arm has to
# get its own arithmetic right.  These inputs are built by hand rather than
# captured because the interesting arms need shapes a compiler will not produce:
#   - a line present in one operand only (union copy / intersect+difference drop)
#   - a line present in both, whose coverpoints MERGE in place (the arm where a
#     count can change without anything being added or removed)
#   - 'U'-tagged (excluded) coverpoints, which are not counted at all
# Line 30 is excluded in both operands, so it contributes to no total anywhere.
#
cat > setopA.info <<'EOF'
TN:tc1
SF:setops.c
DA:10,5
DA:20,3
DA:30,0
BRDA:10,0,0,5
BRDA:10,0,1,0
BRDA:20,0,0,3
BRDA:20,0,1,0
BRDA:30,U0,0,0
BRDA:30,U0,1,0
BRF:4
BRH:2
MCDC:10,2,t,5,0,a&&b
MCDC:10,2,f,0,0,a&&b
MCDC:10,2,t,5,1,a&&b
MCDC:10,2,f,0,1,a&&b
MCDC:20,2,t,3,0,c||d
MCDC:20,2,f,0,0,c||d
MCDC:20,2,t,3,1,c||d
MCDC:20,2,f,0,1,c||d
MCDC:30,U2,t,0,0,e&&f
MCDC:30,U2,f,0,0,e&&f
MCDC:30,U2,t,0,1,e&&f
MCDC:30,U2,f,0,1,e&&f
LF:3
LH:2
end_of_record
EOF

cat > setopB.info <<'EOF'
TN:tc1
SF:setops.c
DA:20,1
DA:30,0
DA:40,7
BRDA:20,0,0,1
BRDA:20,0,1,2
BRDA:30,U0,0,0
BRDA:30,U0,1,0
BRDA:40,0,0,7
BRDA:40,0,1,0
BRF:4
BRH:3
MCDC:20,2,t,1,0,c||d
MCDC:20,2,f,0,0,c||d
MCDC:20,2,t,0,1,c||d
MCDC:20,2,f,2,1,c||d
MCDC:30,U2,t,0,0,e&&f
MCDC:30,U2,f,0,0,e&&f
MCDC:30,U2,t,0,1,e&&f
MCDC:30,U2,f,0,1,e&&f
MCDC:40,2,t,7,0,g&&h
MCDC:40,2,f,0,0,g&&h
MCDC:40,2,t,7,1,g&&h
MCDC:40,2,f,0,1,g&&h
LF:3
LH:2
end_of_record
EOF

# 'setops.c' does not exist on disk - only the .info data matters here
SETOP_IGNORE="--ignore source,inconsistent,unused,empty"

function checkSetop
{
    # checkSetop opDescription file expectedLine...
    #  Assert exact lines in either the written '.info' or the run's log.  Both
    #  matter, and they are not the same number:  the section-level BRF/BRH and
    #  MCF/MCH are recomputed by the writer as it walks the data, whereas the
    #  '<n> of <m>' summary lines report the CACHED found/hit that the set
    #  operations maintain incrementally.  Only the latter catches a missing
    #  count adjustment, so every case below asserts both.
    local WHAT=$1
    local OUT=$2
    shift 2
    for EXPECT in "$@" ; do
        grep -qxF "$EXPECT" $OUT
        if [ 0 != $? ] ; then
            echo "Error:  $WHAT is missing '$EXPECT':"
            cat $OUT
            status=1
            if [ $KEEP_GOING == 0 ] ; then
                exit 1
            fi
        fi
    done
}

# Union: lines 10, 20, 40 are counted, 30 is excluded -> 6 branches, 4 taken.
#  Cached MC/DC: 12 senses (30's four are excluded), 7 hit - line 10's two 't',
#  line 20's 't' and 'f' from the in-place merge, line 40's two 't'.
#  Written MCF is 16, because a section prints every sense, excluded included.
$COVER $LCOV_TOOL --branch --mcdc -o setopU.info -a setopA.info -a setopB.info \
    $SETOP_IGNORE 2>&1 | tee setopU.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error code from set-op union"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
checkSetop 'set-op union' setopU.info 'BRF:6' 'BRH:4' 'MCF:16' 'MCH:7'
checkSetop 'set-op union summary' setopU.log \
    '  branches....: 66.7% (4 of 6 branches)' \
    '  conditions..: 58.3% (7 of 12 conditions)'

# Intersect: only line 20 (and excluded 30) survive.  Line 20's coverpoints
#  merge in place - the arm where a count changes with nothing added or removed.
$COVER $LCOV_TOOL --branch --mcdc -o setopI.info setopA.info \
    --intersect setopB.info $SETOP_IGNORE 2>&1 | tee setopI.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error code from set-op intersect"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
checkSetop 'set-op intersect' setopI.info 'BRF:2' 'BRH:2' 'MCF:8' 'MCH:3'
checkSetop 'set-op intersect summary' setopI.log \
    '  branches....: 100.0% (2 of 2 branches)' \
    '  conditions..: 75.0% (3 of 4 conditions)'

# Difference: lines 20 and 30 are dropped, leaving only line 10.
$COVER $LCOV_TOOL --branch --mcdc -o setopD.info setopA.info \
    --subtract setopB.info $SETOP_IGNORE 2>&1 | tee setopD.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error code from set-op subtract"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
checkSetop 'set-op subtract' setopD.info 'BRF:2' 'BRH:1' 'MCF:4' 'MCH:2'
checkSetop 'set-op subtract summary' setopD.log \
    '  branches....: 50.0% (1 of 2 branches)' \
    '  conditions..: 50.0% (2 of 4 conditions)'

#
# A line present in BOTH operands whose blocks only PARTIALLY match: 'A' has two
# blocks on line 50, 'B' has one.  intersect keeps the common leading block and
# drops the rest; subtract keeps the excess.  Either way the surviving line is
# reinstalled as a freshly built BranchLocation - the arm that was installed
# without ever adding its counts, which is what the whole-map rescan used to
# paper over.  Block 0 of 'A' is entirely un-taken so the drop/keep decision
# visibly moves BRH, not just BRF.
#
cat > setopPa.info <<'EOF'
TN:tc1
SF:setops.c
DA:50,4
BRDA:50,0,0,0
BRDA:50,0,1,0
BRDA:50,1,0,3
BRDA:50,1,1,1
BRF:4
BRH:2
end_of_record
EOF

cat > setopPb.info <<'EOF'
TN:tc1
SF:setops.c
DA:50,5
BRDA:50,0,0,5
BRDA:50,0,1,2
BRF:2
BRH:2
end_of_record
EOF

$COVER $LCOV_TOOL --branch -o setopPi.info setopPa.info \
    --intersect setopPb.info $SETOP_IGNORE 2>&1 | tee setopPi.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error code from partial-block intersect"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# block 0 survives, merged: 0+5 and 0+2.  block 1 has no counterpart, dropped.
#  The summary count is the one that matters here: with the reinstalled line's
#  counts missing it reads '0 of 2', since the removal was accounted for and the
#  replacement was not.
checkSetop 'partial-block intersect' setopPi.info \
    'BRDA:50,0,0,5' 'BRDA:50,0,1,2' 'BRF:2' 'BRH:2'
checkSetop 'partial-block intersect summary' setopPi.log \
    '  branches....: 100.0% (2 of 2 branches)'

$COVER $LCOV_TOOL --branch -o setopPd.info setopPa.info \
    --subtract setopPb.info $SETOP_IGNORE 2>&1 | tee setopPd.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error code from partial-block subtract"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# the leading common block is removed; block 1 is kept, renumbered to 0
checkSetop 'partial-block subtract' setopPd.info \
    'BRDA:50,0,0,3' 'BRDA:50,0,1,1' 'BRF:2' 'BRH:2'
checkSetop 'partial-block subtract summary' setopPd.log \
    '  branches....: 100.0% (2 of 2 branches)'

#
# SPARSE union: a small operand merged into a much larger accumulated map.
#
# union() decides up front whether to keep the cached found/hit up to date as it
# goes or to rebuild it from scratch at the end, because neither is always the
# cheaper:  incremental costs about two totals() walks per line the INCOMING map
# brings, while a rebuild costs one walk per line the DESTINATION holds.  The
# unions above all take the rebuild branch (their operands are the same size, so
# 2*yours > mine), which leaves the incremental arms untested.  Here 'S1' has 6
# lines and 'S2' has 2, so 2*2 <= 6 selects the incremental path - and 'S2' is
# built to reach BOTH of its arms:
#   - line 20 exists in S1, so its coverpoints merge in place and the cached
#     counts have to move by the bracketed delta;
#   - line 70 is new, so it is copied and its totals added outright.
# Line 20 is the interesting one:  each operand takes one of its two branches,
# so the merge lifts it from 1-of-2 to 2-of-2 without adding any coverpoint.
#
cat > setopS1.info <<'EOF'
TN:tc1
SF:setops.c
DA:10,1
DA:20,1
DA:30,3
DA:40,4
DA:50,5
DA:60,6
BRDA:10,0,0,1
BRDA:10,0,1,0
BRDA:20,0,0,1
BRDA:20,0,1,0
BRDA:30,0,0,3
BRDA:30,0,1,0
BRDA:40,0,0,4
BRDA:40,0,1,0
BRDA:50,0,0,5
BRDA:50,0,1,0
BRDA:60,0,0,6
BRDA:60,0,1,0
BRF:12
BRH:6
MCDC:10,2,t,1,0,a&&b
MCDC:10,2,f,0,0,a&&b
MCDC:20,2,t,1,0,c||d
MCDC:20,2,f,0,0,c||d
MCDC:30,2,t,3,0,e&&f
MCDC:30,2,f,0,0,e&&f
MCDC:40,2,t,4,0,g&&h
MCDC:40,2,f,0,0,g&&h
MCDC:50,2,t,5,0,i&&j
MCDC:50,2,f,0,0,i&&j
MCDC:60,2,t,6,0,k&&l
MCDC:60,2,f,0,0,k&&l
LF:6
LH:6
end_of_record
EOF

cat > setopS2.info <<'EOF'
TN:tc1
SF:setops.c
DA:20,4
DA:70,9
BRDA:20,0,0,0
BRDA:20,0,1,4
BRDA:70,0,0,9
BRDA:70,0,1,0
BRF:4
BRH:2
MCDC:20,2,t,0,0,c||d
MCDC:20,2,f,4,0,c||d
MCDC:70,2,t,9,0,m&&n
MCDC:70,2,f,0,0,m&&n
LF:2
LH:2
end_of_record
EOF

$COVER $LCOV_TOOL --branch --mcdc -o setopS.info -a setopS1.info -a setopS2.info \
    $SETOP_IGNORE 2>&1 | tee setopS.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error code from sparse union"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# 7 lines x 2 coverpoints = 14; taken: one per line except line 20, which the
#  merge brings to two - so 5 + 2 + 1 = 8.  Nothing is excluded here, so the
#  section counts and the summary counts agree.
checkSetop 'sparse union' setopS.info \
    'BRDA:20,0,0,1' 'BRDA:20,0,1,4' 'BRF:14' 'BRH:8' 'MCF:14' 'MCH:8'
checkSetop 'sparse union summary' setopS.log \
    '  branches....: 57.1% (8 of 14 branches)' \
    '  conditions..: 57.1% (8 of 14 conditions)'

if [ 0 == $status ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi

exit $status
