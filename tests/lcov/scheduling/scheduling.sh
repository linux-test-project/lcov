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
    agg* geninfo_prof.json *.xlsx nomem* untooled* bad* cover_db.dat \
    html_report __pycache__

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
# genhtml records its whole-run elapsed time under 'total', the same key
# geninfo, lcov and html2lcov use, so one consumer works for every tool.
python3 -c "
import json, sys
d = json.load(open('prof.json'))
if 'total' not in d:
    print('FAIL: genhtml profile has no \'total\' key: %s' % (sorted(d)))
    sys.exit(1)
if float(d['total']) <= 0:
    print('FAIL: genhtml profile \'total\' is not positive: %s' % (d['total']))
    sys.exit(1)
if 'overall' in d:
    print('FAIL: genhtml profile still carries the old \'overall\' key')
    sys.exit(1)
print('OK: genhtml profile total=%s' % (d['total']))
"
if [ 0 != $? ] ; then
    echo "genhtml profile 'total' key check failed"
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

#-----------------------------------------------------------------------
# 9. per-job peak memory in the --profile data.  Every forked worker records
#    its peak RSS/VM under memory{<phase>_<jobid>}, keyed by the SAME job id
#    the timing data uses, so memory{segment_3} lines up with segment{3} and
#    child{3}.  The phase prefix is required because the numeric id spaces
#    overlap:  geninfo uses child{N} for capture chunks and filt_child{N} for
#    filter workers, with the same N.  The pid is a field, not the key.
#    Tolerate a platform that does not expose peak memory (in which case
#    read_proc_peak_memory returns 0 and no memory data is emitted at all).
#-----------------------------------------------------------------------
fail_memory() {
    echo "ERROR (memory $1): $2"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

check_memory() {
    # $1 = profile json, $2 = phase prefix expected on worker keys,
    # $3 = name of the sibling timing data holding the same job ids,
    # $4 = jq path to that timing data (its keys are the job ids)
    local json=$1 phase=$2 timing=$3 idpath=$4
    local n bad ids mids id
    if [ ! -f $json ] ; then
        fail_memory $phase "$json not found"
        return
    fi
    if [ "`jq -r 'has("memory")' $json`" != "true" ] ; then
        echo "memory data absent in $json (platform does not expose peak memory)"
        return
    fi
    # every entry - parent and workers alike - must carry positive rss and
    # vsize, plus the pid field
    bad=`jq -r '[.memory | to_entries[]
                 | select((.value.rss // 0) <= 0
                          or (.value.vsize // 0) <= 0
                          or (.value.pid // 0) <= 0)
                 | .key] | join(",")' $json`
    if [ "x$bad" != "x" ] ; then
        jq -r '.memory' $json
        fail_memory $phase "entries missing rss/vsize/pid: $bad"
    fi
    # the parent must be keyed 'parent' - not by its pid
    if [ "`jq -r '.memory | has("parent")' $json`" != "true" ] ; then
        jq -r '.memory | keys' $json
        fail_memory $phase "no 'parent' entry in $json"
    fi
    # at least one worker keyed <phase>_<jobid>, and every such job id must
    # appear in the sibling timing data - that correlation is the whole point
    # of keying by job id instead of by pid
    mids=`jq -r --arg p "$phase" '[.memory | keys[]
              | select(startswith($p + "_")) | ltrimstr($p + "_")]
              | sort | join(" ")' $json`
    n=`echo $mids | wc -w`
    if [ $n -lt 1 ] ; then
        jq -r '.memory | keys' $json
        fail_memory $phase "no ${phase}_<jobid> entry in $json"
        return
    fi
    # one id per line, flattened to a space-separated list - avoids quoting a
    # separator inside the caller-supplied jq path expression
    ids=" `jq -r "$idpath | keys[]" $json | tr '\n' ' '` "
    for id in $mids ; do
        case "$ids" in
            *" $id "*) ;;
            *) fail_memory $phase \
                   "job id $id has no matching $timing entry (have:$ids)" ;;
        esac
    done
    echo "OK (memory $phase): $n worker(s) [$mids] correlated with $timing"
}

# geninfo capture chunks:  memory{capture_N} vs child{N}.  geninfo_prof.json
# was generated with --parallel 4 in step 3 above.
check_memory geninfo_prof.json capture child .child
# genhtml segments:  memory{segment_N} vs segment{N}, from prof.json in step 6
check_memory prof.json segment segment .segment

# Filter workers and aggregate groups.  Aggregating two inputs with parallel
# filtering forks both kinds, and their numeric job ids DO collide - both count
# from 0 - so this is the case that requires the phase prefix in the key.  The
# aggregate group's own timing is stored at the top level as {<groupIdx>}{total}
# rather than in a hash of its own.
LCOV_FORCE_PARALLEL=1 $COVER $LCOV_TOOL -a cov.info -a cov.info -o agg.info \
    --parallel 4 --profile agg_prof.json --filter branch,line \
    --ignore empty,inconsistent 2>&1 | tee agg.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "aggregate failed"
    exit 1
fi
check_memory agg_prof.json filter filt_child .filt_child
check_memory agg_prof.json aggregate 'group total' \
    '(with_entries(select(.key | test("^[0-9]+$"))))'

# Both phases must be present simultaneously in that one profile:  under the
# earlier pid keying they were indistinguishable, and under a flat numeric
# keying they would have overwritten each other.
for phase in filter aggregate ; do
    n=`jq -r --arg p "$phase" '[.memory | keys[]
           | select(startswith($p + "_"))] | length' agg_prof.json`
    if [ "${n:-0}" -lt 1 ] ; then
        fail_memory $phase "no $phase worker in agg_prof.json"
    fi
done
# ...and a collision would have been reported by merge_child_profile
if grep -i 'unexpected duplicate key' agg.log geninfo_hist.log genhtml_hist.log ; then
    fail_memory collision \
        "duplicate profile key reported - job id namespace collision"
fi

#-----------------------------------------------------------------------
# 9a. nested forks:  a forked worker which itself forks workers.  An
#     '--unreachable' callback keeps filtering enabled inside each aggregate
#     segment child, so every segment forks its own filter workers - and their
#     chunk id counters are process globals which fork() copied, so all the
#     segments would otherwise number their filter chunks from 0 and collide.
#     Both the memory key and the timing key of such a worker must therefore be
#     qualified with the label of the job which forked it:
#       memory{filter_aggregate_1_0} / filt_child{aggregate_1_0}
#     and the two must still line up, exactly as for a top-level worker.
#-----------------------------------------------------------------------
LCOV_FORCE_PARALLEL=1 $COVER $LCOV_TOOL -a cov.info -a cov.info -o nested.info \
    --parallel 4 --profile nested_prof.json --branch-coverage \
    --unreachable ${SCRIPT_DIR}/unreach.pm \
    --ignore empty,inconsistent,unused 2>&1 | tee nested.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "nested aggregate failed"
    exit 1
fi
# a collision here used to be fatal:  the child died serializing its profile
if grep -i 'unexpected duplicate key' nested.log ; then
    fail_memory nested "duplicate profile key from a nested fork"
fi
# the qualified filter workers, and the check that memory{filter_<id>} still
# lines up with filt_child{<id>} for them
nested=`jq -r '[.memory | keys[] | select(test("^filter_aggregate_"))]
               | sort | join(" ")' nested_prof.json`
if [ "`echo $nested | wc -w`" -lt 2 ] ; then
    jq -r '.memory | keys' nested_prof.json
    fail_memory nested "no nested filter worker in nested_prof.json"
else
    echo "OK (memory nested): [$nested]"
fi
check_memory nested_prof.json filter filt_child .filt_child

#-----------------------------------------------------------------------
# 10. the same per-job memory data in the generated spreadsheet:  the
#     per-job sections must carry peakVM then peakRSS in the columns just
#     right of their last timing key:  'chunks' in a geninfo sheet, and
#     'segments' in an lcov or genhtml sheet.  The whole-run 'peak mem' block
#     has the same shape, with a single 'max' row instead of one row per job.
#     Also the layout of each sub-table:  two empty rows, a boldface title row,
#     the italic total/max/avg/stddev rows over that table's elements, then the
#     element rows.
#     Needs xlsxwriter (spreadsheet.py) but nothing to read the result - the
#     checkers use zipfile + ElementTree.
#-----------------------------------------------------------------------
if ! python3 -c "import xlsxwriter" >/dev/null 2>&1 ; then
    echo "skipping spreadsheet check:  no xlsxwriter module"
elif [ "`jq -r 'has(\"memory\")' geninfo_prof.json`" != "true" ] ; then
    echo "skipping spreadsheet check:  no memory data on this platform"
else
    echo $SPREADSHEET_TOOL -o mem.xlsx geninfo_prof.json agg_prof.json prof.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o mem.xlsx geninfo_prof.json \
        agg_prof.json prof.json 2>&1 | tee spreadsheet.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f mem.xlsx ] ; then
        fail_memory spreadsheet "spreadsheet generation failed"
    else
        # <sheet> <section> <anchor>:  the key which must be immediately left
        # of peakVM in that section's column title row.  '_' stands in for a
        # space in the section name, so the fields stay whitespace-separated.
        while read sheet section anchor ; do
            python3 ./check_peakmem_columns.py mem.xlsx \
                $sheet "${section//_/ }" $anchor
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "$sheet '$section' peak memory columns"
            fi
        done <<EOF
geninfo_prof.json chunks merge
agg_prof.json segments append
prof.json segments segment
geninfo_prof.json peak_mem none
EOF

        # ...and the layout of each of those sub-tables:  two empty rows, the
        # boldface title row, the italic total/max/avg/stddev rows over its
        # elements, then the element rows.  The 'total' of a peak memory column
        # must be empty - the jobs ran concurrently, so their sum means nothing.
        while read sheet sections ; do
            python3 ./check_table_layout.py mem.xlsx $sheet $sections
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "$sheet sub-table layout"
            fi
        done <<EOF
geninfo_prof.json chunks files
agg_prof.json segments
prof.json segments
EOF

        # '--show-filter' adds a third geninfo sub-table, from the forked
        # filter workers.  Those exist only when filtering actually ran in
        # parallel, so capture once more with a filter enabled.
        LCOV_FORCE_PARALLEL=1 $COVER $GENINFO_TOOL . --parallel 4 \
            -o filt.info --profile filt_prof.json --branch-coverage \
            --filter branch,line --ignore empty,unused,inconsistent \
            2>&1 | tee filt_capture.log
        if [ 0 != ${PIPESTATUS[0]} ] || \
           [ "`jq -r 'has(\"filt_child\")' filt_prof.json`" != "true" ] ; then
            fail_memory spreadsheet "no filter worker data in filt_prof.json"
        else
            # pass the unfiltered profile too:  a second file both creates the
            # summary sheet (which has to find each sub-table's total and
            # average rows) and exercises '--show-filter' against a profile
            # which has no filter workers at all, so there is no filter
            # sub-table for the summary to reference.
            eval ${PYCOVER} $SPREADSHEET_TOOL --show-filter -o filt.xlsx \
                filt_prof.json geninfo_prof.json 2>&1 | tee filt_spreadsheet.log
            if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f filt.xlsx ] ; then
                fail_memory spreadsheet "spreadsheet generation with --show-filter"
            else
                python3 ./check_table_layout.py filt.xlsx filt_prof.json \
                    chunks files filter
                if [ 0 != $? ] ; then
                    fail_memory spreadsheet "--show-filter sub-table layout"
                fi
                # ...and the profile with no filter workers has the usual two
                # sub-tables, and no 'filter' one
                python3 ./check_table_layout.py filt.xlsx geninfo_prof.json \
                    chunks files
                if [ 0 != $? ] ; then
                    fail_memory spreadsheet \
                        "--show-filter layout without filter workers"
                fi
            fi
        fi
    fi

    # ...and the same profiles with the memory data removed - i.e. a profile
    # from an older lcov, or from a platform which does not expose peak
    # memory - must still generate, just without the memory rows/columns.
    for f in geninfo_prof.json agg_prof.json ; do
        jq -r 'del(.memory) | del(.memoryPeak)' $f > nomem_$f
    done
    echo $SPREADSHEET_TOOL -o nomem.xlsx nomem_geninfo_prof.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o nomem.xlsx \
        nomem_geninfo_prof.json nomem_agg_prof.json 2>&1 | tee nomem.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f nomem.xlsx ] ; then
        fail_memory spreadsheet "spreadsheet generation without memory data"
    fi
    # the checks above must NOT pass on that one - there is nothing to find.
    # the 'FAIL:' line the checker prints here is EXPECTED.
    echo "expect the following check to fail (profile has no memory data):"
    python3 ./check_peakmem_columns.py nomem.xlsx nomem_geninfo_prof.json \
        chunks merge
    if [ 0 == $? ] ; then
        fail_memory spreadsheet \
            "found peak memory columns in a profile that has none"
    fi

    # a profile whose tool cannot be identified falls through to the generic
    # key loop;  the memory keys must be skipped there too, rather than
    # landing in the "not sure what to do with" catch-all.
    jq -r 'del(.config.tool)' agg_prof.json > untooled.json
    echo $SPREADSHEET_TOOL -o untooled.xlsx untooled.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o untooled.xlsx untooled.json 2>&1 | \
        tee untooled.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f untooled.xlsx ] ; then
        fail_memory spreadsheet "spreadsheet generation for unknown tool"
    fi
    if grep -E 'not sure what to do with (memory|memoryPeak)' untooled.log ; then
        fail_memory spreadsheet "memory keys not handled for unknown tool"
    fi

    # a partly corrupt/incomplete profile must warn rather than crash:  drop
    # one segment's 'merge' time and make another's non-numeric in the lcov
    # profile, and do the same to a genhtml segment.  The tool has to keep
    # going and still produce a spreadsheet.
    jq -r '."0" |= del(.merge) | ."1".total = "corrupt"' agg_prof.json \
        > bad_agg.json
    jq -r '.segment."0" = "corrupt"' prof.json > bad_prof.json
    echo $SPREADSHEET_TOOL -o bad.xlsx bad_agg.json bad_prof.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o bad.xlsx bad_agg.json bad_prof.json \
        2>&1 | tee bad.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f bad.xlsx ] ; then
        fail_memory spreadsheet "spreadsheet generation for corrupt profile"
    fi
    for expect in 'bad_agg.json: no merge for segment 0' \
                  'bad_agg.json: unable to write corrupt for segment 1.total' \
                  'bad_prof.json: unable to write corrupt for segment 0.segment' ; do
        if ! grep -E "$expect" bad.log >/dev/null ; then
            cat bad.log
            fail_memory spreadsheet "no warning matching '$expect'"
        fi
    done
fi

if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    # '1':  section 10 runs spreadsheet.py, so there is python coverage too
    generate_coverage 'scheduling' $LOCAL_COVERAGE 1
fi

exit $STATUS
