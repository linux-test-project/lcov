#!/bin/bash
set +x

# Exercise the dedicated-segment scheduling enhancements:
#   1. geninfo size-based dedicated forked chunk (geninfo_dedicate_segment_size)
#   2. geninfo --large-file is a serial (memory) chunk, NOT a dedicated forked
#      chunk - the two mechanisms are mutually exclusive
#   3. geninfo history-based dedicated forked chunk (--history-script
#      prediction >= dedicate_segment_threshold).  The geninfo history-order
#      block only runs when chunkSize>1, so LCOV_FORCE_PARALLEL=1 is used to
#      enable it with a small file count.
#   4. genhtml size-based dedicated segment (dedicate_segment_line_estimate,
#      no history available)
#   5. genhtml history-based dedicated segment (--history-script prediction
#      >= dedicate_segment_threshold)
#   6. genhtml "shared" interleave path: a file predicted to run but BELOW the
#      dedicate threshold is interleaved across segments, not dedicated
#   7. feature disabled (threshold/size == 0) => no dedicated segments
# The observable signal in every case is the info message
#   "N file(s) assigned a dedicated segment."

source ../../common.tst

rm -rf *.gcda *.gcno a.out *.info* *.txt* *.json *.log rpt* prof* ghist* \
    geninfo_prof.json cover_db.dat html_report

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type ${CC} >/dev/null 2>&1 ; then
    echo "Missing tool: ${CC}" >&2
    exit 2
fi

if [ 'x' == "x$GENHTML_TOOL" ] ; then
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    GENINFO_TOOL=${LCOV_HOME}/bin/geninfo
fi
HISTORY_SCRIPT=${SCRIPT_DIR}/history.pm

# Two independent compilation units so there is more than one schedulable item.
cat > a.c <<'EOF'
int fa(int x){ if (x > 0) return 1; return 0; }
int main(){ return fa(1); }
EOF
cat > b.c <<'EOF'
int fb(int x){ if (x > 1) return 2; return 0; }
EOF

${CC} --coverage -c a.c b.c
${CC} --coverage a.o b.o -o a.out
./a.out

STATUS=0

check_msg() {
    # $1 = logfile, $2 = expected dedicated-segment count, $3 = scenario label
    local log=$1 want=$2 label=$3
    local got
    got=`grep -oE '[0-9]+ file\(s\) assigned a dedicated segment' $log | grep -oE '^[0-9]+'`
    got=${got:-0}
    if [ "$got" != "$want" ] ; then
        echo "ERROR ($label): expected $want dedicated segment(s), found $got"
        cat $log
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    else
        echo "OK ($label): $got dedicated segment(s)"
    fi
}

#-----------------------------------------------------------------------
# 1. geninfo size-based: tiny threshold => both .gcda become dedicated
#-----------------------------------------------------------------------
$COVER $GENINFO_TOOL . --parallel 4 -o size.info \
    --rc geninfo_dedicate_segment_size=1 --ignore empty 2>&1 | tee geninfo_size.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "geninfo size-based capture failed"
    exit 1
fi
check_msg geninfo_size.log 2 "geninfo size-based"

#-----------------------------------------------------------------------
# 2. geninfo --large-file is serial, NOT dedicated:  match a.gcda with
#    --large-file AND keep the tiny dedicate size.  a.gcda must go to the
#    serial parent chunk; only b.gcda gets a dedicated forked chunk.
#-----------------------------------------------------------------------
$COVER $GENINFO_TOOL . --parallel 4 -o large.info \
    --rc geninfo_dedicate_segment_size=1 --large-file 'a\.gcda' \
    --ignore empty -v 2>&1 | tee geninfo_large.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "geninfo --large-file capture failed"
    exit 1
fi
# exactly one file (b.gcda) is dedicated; a.gcda is handled serially
check_msg geninfo_large.log 1 "geninfo --large-file exclusivity"
grep -E 'large file:.*a\.gcda' geninfo_large.log
if [ 0 != $? ] ; then
    echo "ERROR: a.gcda was not routed to the serial large-file chunk"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#-----------------------------------------------------------------------
# 3. geninfo history-based: generate a geninfo profile, feed it back through
#    the history callback with a tiny threshold so the (exact) predicted
#    per-file times cross the bar.  Disable the size heuristic so only the
#    history path can trigger a dedicated chunk.  The geninfo history-order
#    block is gated on chunkSize>1, so force the parallel path.
#-----------------------------------------------------------------------
$COVER $GENINFO_TOOL . --parallel 4 -o prof.info --profile geninfo_prof.json \
    --ignore empty
if [ ! -f geninfo_prof.json ] ; then
    echo "geninfo profile generation failed"
    exit 1
fi
LCOV_FORCE_PARALLEL=1 $COVER $GENINFO_TOOL . --parallel 4 -o ghist.info \
    --history $HISTORY_SCRIPT,geninfo_prof.json \
    --rc dedicate_segment_threshold=0.0000001 --rc geninfo_dedicate_segment_size=0 \
    --ignore empty 2>&1 | tee geninfo_hist.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "geninfo history-based capture failed"
    exit 1
fi
check_msg geninfo_hist.log 2 "geninfo history-based"

#-----------------------------------------------------------------------
# 4. geninfo feature disabled (size=0, no history) => no dedicated segments
#-----------------------------------------------------------------------
$COVER $GENINFO_TOOL . --parallel 4 -o off.info \
    --rc geninfo_dedicate_segment_size=0 --ignore empty 2>&1 | tee geninfo_off.log
check_msg geninfo_off.log 0 "geninfo disabled"

# a normal capture for the genhtml scenarios
$COVER $GENINFO_TOOL . --parallel 4 -o cov.info --ignore empty
if [ 0 != $? ] ; then
    echo "baseline capture failed"
    exit 1
fi

#-----------------------------------------------------------------------
# 5. genhtml size-based (no history): tiny line estimate/threshold so the
#    instrumented files cross the bar and get dedicated segments.
#-----------------------------------------------------------------------
$COVER $GENHTML_TOOL cov.info -o rpt_size --parallel 4 \
    --rc dedicate_segment_line_estimate=1 --rc dedicate_segment_threshold=1 \
    --ignore empty,inconsistent 2>&1 | tee genhtml_size.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "genhtml size-based failed"
    exit 1
fi
# both instrumented files are >= 1 line, estimate = lines/1 >= threshold 1
check_msg genhtml_size.log 2 "genhtml size-based"

#-----------------------------------------------------------------------
# 6. genhtml history-based: generate a profile, then feed it back through
#    the history callback with a tiny threshold so the (exact) predicted
#    times cross the bar.
#-----------------------------------------------------------------------
$COVER $GENHTML_TOOL cov.info -o rpt_prof --parallel 4 --profile prof.json \
    --ignore empty,inconsistent
if [ ! -f prof.json ] ; then
    echo "profile generation failed"
    exit 1
fi
$COVER $GENHTML_TOOL cov.info -o rpt_hist --parallel 4 \
    --history $HISTORY_SCRIPT,prof.json \
    --rc dedicate_segment_threshold=0.0000001 \
    --ignore empty,inconsistent 2>&1 | tee genhtml_hist.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "genhtml history-based failed"
    exit 1
fi
check_msg genhtml_hist.log 2 "genhtml history-based"

#-----------------------------------------------------------------------
# 7. genhtml "shared" interleave path: files ARE predicted (tiny line
#    estimate) but the threshold is high, so none is dedicated; they take
#    the interleave-across-segments path instead.  Expect no dedicated
#    segment message.
#-----------------------------------------------------------------------
$COVER $GENHTML_TOOL cov.info -o rpt_shared --parallel 4 \
    --rc dedicate_segment_line_estimate=1 --rc dedicate_segment_threshold=1000000 \
    --ignore empty,inconsistent 2>&1 | tee genhtml_shared.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "genhtml shared-path failed"
    exit 1
fi
check_msg genhtml_shared.log 0 "genhtml shared interleave"

#-----------------------------------------------------------------------
# 8. genhtml feature disabled (threshold=0) => no dedicated segments,
#    even with the tiny line estimate.
#-----------------------------------------------------------------------
$COVER $GENHTML_TOOL cov.info -o rpt_off --parallel 4 \
    --rc dedicate_segment_line_estimate=1 --rc dedicate_segment_threshold=0 \
    --ignore empty,inconsistent 2>&1 | tee genhtml_off.log
check_msg genhtml_off.log 0 "genhtml disabled"

if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    generate_coverage 'scheduling' $LOCAL_COVERAGE 0
fi

exit $STATUS
