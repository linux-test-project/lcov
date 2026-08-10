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
# 10. the same per-job memory data in the generated spreadsheet:  each
#     per-job section must carry peakVM then peakRSS in the two columns
#     immediately right of that section's anchor key, which is the key the
#     sheet groups them with rather than always its last one - the table below
#     names the anchor per section:  'chunks' in a geninfo sheet, and
#     'segments' in an lcov or genhtml sheet.  The whole-run 'peak mem' block
#     has the same shape, with a single 'max' row instead of one row per job.
#     Also the layout of each sub-table:  two empty rows, a boldface
#     descriptive title saying what one row of the table is, a boldface title
#     row whose every column title links to the glossary entry for that metric,
#     the italic total/max/avg/stddev rows over that table's elements, then the
#     element rows.  These sheets' tables are all short, so none of them leads
#     with the index of links to its tables which a long sheet gets - see
#     tests/lcov/parallel_parse, whose split read is long enough to need one.
#     An lcov sheet has two more tables of that shape which are keyed by name
#     rather than by job:  'info', the read of each input '.info' file, and
#     'source', the per-source-file callbacks and checks.  Neither is job data,
#     so a segmented run used to stop after the 'segments' table and show
#     neither of them.
#     A run which filtered as a step of its own, after reading and merging - as
#     the aggregation in step 9 did - has a 'filter' table as well, one row per
#     forked filter worker, with the same parent/child breakdown (queue wait,
#     time in the worker, the parent's deserialize and merge, the worker's own
#     peak memory) the job table has, plus the whole-job filter time on a row of
#     its own.  What that step cost is not a property of a segment - a segment
#     child does not filter - so the segment table must have no filter column.
#     And the 'XS enabled' row, which says which implementation of the coverage
#     data classes ran and sits immediately below the sheet's 'tool' row.
#     And the capture summary sheet, whose every data cell is a reference into
#     one of those tables:  each column has to land on the cell the capture
#     sheet's own labels say it should - an offset-based reference still looks
#     well-formed when it points at the wrong number.
#     And the observed parallelism beside a report's elapsed total, which is the
#     total of one named column of the per-object table over that total - not of
#     whichever per-object metric happens to be first.
#     And the thresholds every one of those tables is colorized at, both at the
#     defaults and as --threshold/--low/--high set them:  those three options
#     were parsed and then never read, so each of them silently did nothing, and
#     the conditional formatting rules are the only place the effect shows.
#     And what a profile which is not quite right gets:  a value which cannot be
#     written is named - in a table, in a scalar row, and on the generic sheet a
#     tool with no layout falls through to - rather than leaving a hole no reader
#     can tell from a metric which was never recorded;  a number the profile
#     quoted as a string is written as the number it is;  a capture which
#     recorded which files it read but not the order it read them in still gets
#     its file table;  a report with no elapsed total still gets its tables,
#     without the one figure which is divided by it;  and a run given nothing it
#     can read produces the empty workbook that asks for rather than failing over
#     a sheet which was never written.
#     And that an option after the first profile name is honoured, which is where
#     a shell history naturally leaves one.
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
geninfo_prof.json chunks work
agg_prof.json segments undump
agg_prof.json filter filt_merge
prof.json segments segment
geninfo_prof.json peak_mem none
EOF

        # ...and the layout of each of those sub-tables:  two empty rows, the
        # descriptive title, the boldface title row with a glossary link per
        # column, the italic total/max/avg/stddev rows over its elements, then
        # the element rows.  The 'total' of a peak memory column must be empty -
        # the jobs ran concurrently, so their sum means nothing.
        while read sheet sections ; do
            python3 ./check_table_layout.py mem.xlsx $sheet $sections
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "$sheet sub-table layout"
            fi
        done <<EOF
geninfo_prof.json chunks files
agg_prof.json segments info filter source
prof.json segments
EOF

        # The aggregation above filtered as a step of its own, after the inputs
        # were read and merged, and forked workers to do it - so that step gets a
        # table of its own ('filter', checked for shape above) with the same
        # parent/child breakdown the job table has, and a whole-job time on a row
        # of its own.  What it cost is not a property of a segment, and must not
        # appear as a column of the segment table:  a segment child does not
        # filter at all.  (The other way round - a split read, whose children
        # filter their own chunk - is the parallel_parse test.)
        python3 ./check_scalar_row.py mem.xlsx agg_prof.json filter
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "whole-job filter time of the aggregation"
        fi
        python3 ./check_table_column.py mem.xlsx agg_prof.json segments -filter
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "segment table reports a filter time"
        fi
        python3 ./check_table_column.py mem.xlsx agg_prof.json filter \
            filt_child filt_queue filt_merge peakVM peakRSS
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "filter worker table columns"
        fi

        # ...and that none of these sheets leads with an index of links to its
        # tables:  every one of them is short enough to be read without one.
        # The checker re-derives that from the sheet, so it fails both if an
        # index appears here and if these tables stop being short.
        for f in geninfo_prof.json agg_prof.json prof.json ; do
            python3 ./check_table_index.py mem.xlsx $f noindex
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "$f sub-table index"
            fi
        done

        # ...and the 'XS enabled' row, which every tool sheet carries
        # immediately below its 'tool' row:  which implementation of the
        # coverage data classes actually ran is the config entry worth reading
        # first - it explains times which are otherwise inexplicable - so it
        # does not stay where the alphabetical config order put it.
        for f in geninfo_prof.json agg_prof.json prof.json ; do
            if [ "`jq -r '.config.xs // 0' $f`" == "0" ] ; then
                expect=0
            else
                expect=1
            fi
            python3 ./check_xs_row.py mem.xlsx $f $expect
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "$f 'XS enabled' row"
            fi
        done

        # ...and every column of the capture summary table:  the scalar
        # statistics of the run - total time, observed and configured
        # parallelism, the whole-run peak VM and RSS - and each sub-table key's
        # total (or maximum, for peak memory, whose sum means nothing) and
        # average.  Every one of those is a reference into the capture sheet, so
        # the checker re-derives the cell each column should point at from that
        # sheet's own labels.
        python3 ./check_summary_refs.py mem.xlsx
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "capture summary cell references"
        fi

        # ...and the observed parallelism beside the report's elapsed total,
        # which is the total of the per-object table's 'file' column over that
        # elapsed total.  The checker looks that column up by its title rather
        # than by counting from the left, because which column a key lands in
        # depends on which keys the profile recorded at all - see the
        # noscope.xlsx case below, which is the same check on a profile where
        # the scope key is not the first column.
        python3 ./check_parallelism.py mem.xlsx prof.json file
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "prof.json observed parallelism"
        fi

        # ...and the capture's directory scan times, which are a flat
        # two-column list rather than a table:  nothing knows what those
        # numbers are, so there is nothing to total or colorize.
        python3 ./check_value_list.py mem.xlsx geninfo_prof.json find \
            `jq -r '.find | length' geninfo_prof.json`
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "geninfo_prof.json 'find' value list"
        fi

        # ...and the thresholds every one of those tables is colorized at,
        # which with no options given are the built-in defaults.
        for sheet in geninfo_prof.json agg_prof.json prof.json ; do
            python3 ./check_thresholds.py mem.xlsx $sheet 0.15 1.5 2.0
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "$sheet default colorizing thresholds"
            fi
        done
        # the summary sheet states two of the three in its colour legend, so it
        # has to agree with the rules
        python3 ./check_thresholds.py mem.xlsx capture_summary 0.15 1.5 2.0
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "capture summary threshold legend"
        fi

        # ...and that '--threshold', '--low' and '--high' move them.  Those
        # three options were parsed and then never read, so each of them did
        # nothing at all;  the conditional formatting rules are the only place
        # the effect is visible, which is why nothing noticed.
        echo $SPREADSHEET_TOOL --threshold 0.4 --low 1.1 --high 3.3 \
            -o thresh.xlsx geninfo_prof.json prof.json
        eval ${PYCOVER} $SPREADSHEET_TOOL --threshold 0.4 --low 1.1 \
            --high 3.3 -o thresh.xlsx geninfo_prof.json prof.json 2>&1 | \
            tee thresh.log
        if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f thresh.xlsx ] ; then
            fail_memory spreadsheet "spreadsheet.py --threshold/--low/--high"
        else
            for sheet in geninfo_prof.json prof.json capture_summary ; do
                python3 ./check_thresholds.py thresh.xlsx $sheet 0.4 1.1 3.3
                if [ 0 != $? ] ; then
                    fail_memory spreadsheet "$sheet requested thresholds"
                fi
            done
        fi

        # ...and that an option written after the first profile name is still
        # an option:  the parser used to stop at the first name and collect
        # everything after it as another file, which is exactly where a shell
        # history leaves a flag.  '-v' is the one which changes the sheet - it
        # adds the per-file gcov read and translate columns - so it says the
        # option arrived rather than only that nothing crashed.
        echo $SPREADSHEET_TOOL -o late.xlsx geninfo_prof.json -v
        eval ${PYCOVER} $SPREADSHEET_TOOL -o late.xlsx geninfo_prof.json -v \
            2>&1 | tee late.log
        if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f late.xlsx ] ; then
            fail_memory spreadsheet "spreadsheet.py trailing option"
        else
            # it was read as an option, and not collected as one more profile to
            # open - which is what it used to become
            if grep -F -- '-v: unable to parse' late.log ; then
                fail_memory spreadsheet "trailing '-v' read as a file name"
            fi
            # the gcov intermediate format is read in one step, so those two
            # keys exist only when the text format was used
            if [ "`jq -r 'has(\"read\")' geninfo_prof.json`" == "true" ] ; then
                LATE_KEYS="file read translate"
            else
                LATE_KEYS="file -read -translate"
            fi
            python3 ./check_table_column.py late.xlsx geninfo_prof.json \
                files $LATE_KEYS
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "trailing '-v' verbose columns"
            fi
        fi

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
                # the summary table gets the filter columns too, and the case
                # which has no filter sub-table must leave them empty rather
                # than referring to another table's cells
                python3 ./check_summary_refs.py filt.xlsx
                if [ 0 != $? ] ; then
                    fail_memory spreadsheet \
                        "--show-filter capture summary cell references"
                fi
            fi
        fi
    fi

    # a serial capture has no chunk sub-table at all - the file table takes its
    # place - so the summary's chunk columns have to be left empty for it, while
    # the parallel capture alongside it in the same table still has them.
    jq -r 'del(.child, .chunk, .queue, .work, .process, .undump, .merge)' \
        geninfo_prof.json > serial_prof.json
    echo $SPREADSHEET_TOOL -o serial.xlsx serial_prof.json geninfo_prof.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o serial.xlsx serial_prof.json \
        geninfo_prof.json 2>&1 | tee serial.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f serial.xlsx ] ; then
        fail_memory spreadsheet "spreadsheet generation for a serial capture"
    else
        python3 ./check_summary_refs.py serial.xlsx
        if [ 0 != $? ] ; then
            fail_memory spreadsheet \
                "capture summary cell references for a serial capture"
        fi
    fi

    # a profile from a release which recorded neither the whole-run 'total' nor
    # whether the XS extension loaded:  the summary's elapsed time and
    # parallelism columns have to be left empty rather than pointing at whatever
    # row landed where 'total' used to be, and the 'XS enabled' row must still
    # be written - reading 0, since the pure Perl fallback is silent.
    # Alongside it, the same profile with the XS flag quoted as it would be by a
    # profile writer which quotes its numbers:  the row must read 1 for "1" and
    # 0 for "0" - which the string "0" being true in python makes easy to get
    # wrong - so this covers both values whichever backend this run actually
    # used.
    jq -r 'del(.total) | del(.config.xs)' geninfo_prof.json > old_prof.json
    jq -r '.config.xs = "1"' geninfo_prof.json > xson_prof.json
    jq -r '.config.xs = "0"' geninfo_prof.json > xsoff_prof.json
    echo $SPREADSHEET_TOOL -o old.xlsx old_prof.json xson_prof.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o old.xlsx old_prof.json \
        xson_prof.json xsoff_prof.json geninfo_prof.json 2>&1 | tee old.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f old.xlsx ] ; then
        fail_memory spreadsheet "spreadsheet generation without a total time"
    else
        python3 ./check_summary_refs.py old.xlsx
        if [ 0 != $? ] ; then
            fail_memory spreadsheet \
                "capture summary cell references without a total time"
        fi
        while read f expect ; do
            python3 ./check_xs_row.py old.xlsx $f $expect
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "$f 'XS enabled' row"
            fi
        done <<EOF
old_prof.json 0
xson_prof.json 1
xsoff_prof.json 0
EOF
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
    else
        # the summary's peak memory columns must be empty here, and - the
        # interesting part - the columns after them must still land on the right
        # cells:  the whole 'peak mem' block is missing from these sheets, so
        # anything which counted rows past it would be off by two.
        python3 ./check_summary_refs.py nomem.xlsx
        if [ 0 != $? ] ; then
            fail_memory spreadsheet \
                "capture summary cell references without memory data"
        fi
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
    if ! grep -E 'untooled.json: unknown tool' untooled.log >/dev/null ; then
        cat untooled.log
        fail_memory spreadsheet "no warning for a profile with no tool"
    fi

    # ...and on that sheet, which of the two lists names a key does not decide
    # which shape it is written as:  a key has either shape depending on how the
    # run was invoked - 'lcov --extract' records one 'parse' number where a
    # normal run records one per input file - so the shape has to be read off
    # the value.  Writing a hash as a number, or a number as a hash, raised, and
    # took the whole run with it rather than just that key.
    # So: 'parse', which is normally a table, as a single number; 'parse_source',
    # normally a single number, as a hash; a number the profile quoted as a
    # string, which was recorded and so must be written; a value which cannot be
    # written either way, which must be named; a key recorded and empty, whose
    # label still has to keep its row; and a key nothing knows about.
    cat > generic.json <<'EOF'
{
  "config": { "tool": "notatool", "date": "2026-01-01", "version": "0" },
  "total": 12.5,
  "parse": 3.25,
  "parse_source": { "a.c": 1.5, "b.c": "2.5" },
  "annotate": { "x.c": "corrupt" },
  "find": {},
  "emit": "corrupt",
  "nonsense": 7
}
EOF
    echo $SPREADSHEET_TOOL -o generic.xlsx generic.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o generic.xlsx generic.json 2>&1 | \
        tee generic.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f generic.xlsx ] ; then
        fail_memory spreadsheet "spreadsheet generation for unrecognized shapes"
    else
        # the table key which is a number this time
        python3 ./check_scalar_row.py generic.xlsx generic.json parse
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "scalar 'parse' on a generic sheet"
        fi
        # the scalar key which is a hash this time, including the entry the
        # profile quoted:  both of its values have to be numbers
        python3 ./check_value_list.py generic.xlsx generic.json parse_source 2
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "hash 'parse_source' on a generic sheet"
        fi
        # the key recorded and empty:  labelled, and nothing written over it
        python3 ./check_value_list.py generic.xlsx generic.json find 0
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "empty 'find' on a generic sheet"
        fi
        for expect \
            in 'generic.json: unable to write corrupt for \[annotate\]\[x.c\]' \
               'generic.json: unable to write corrupt for emit' \
               'not sure what to do with nonsense' ; do
            if ! grep -E "$expect" generic.log >/dev/null ; then
                cat generic.log
                fail_memory spreadsheet "no warning matching '$expect'"
            fi
        done
    fi

    # a run given nothing it can read - a name which is not there, and a file
    # which is not a profile - has no data sheet to open the workbook on.  The
    # empty workbook that asks for is a better answer than failing over the sheet
    # which was never written, which is what happened for as long as there were
    # two names on the command line:  a second name is what creates the summary
    # sheet, and the summary sheet is what makes the tool go looking for one.
    echo '{ "total": 1 }' > notaprofile.json
    echo $SPREADSHEET_TOOL -o empty.xlsx nosuchfile.json notaprofile.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o empty.xlsx nosuchfile.json \
        notaprofile.json 2>&1 | tee empty.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f empty.xlsx ] ; then
        cat empty.log
        fail_memory spreadsheet "spreadsheet generation with no readable input"
    fi
    for expect in 'nosuchfile.json: unable to parse' \
                  "notaprofile.json: no 'config' data key" ; do
        if ! grep -F "$expect" empty.log >/dev/null ; then
            cat empty.log
            fail_memory spreadsheet "no warning matching '$expect'"
        fi
    done

    # a partly corrupt/incomplete profile must warn rather than crash:  drop
    # one segment's 'merge' time and make another's non-numeric in the lcov
    # profile, and do the same to a genhtml segment.  Make one of a capture's
    # scalar phase times non-numeric too:  that one is named in the summary
    # table, so it has to be reported rather than silently left out.  Corrupt
    # one source file's consistency check time as well - the tables which are
    # keyed by name rather than by job leave a cell empty for a key which was
    # simply not recorded for that element, so a value which cannot be written
    # has to be told apart from that and reported.  The tool has to keep going
    # and still produce a spreadsheet.
    # Corrupt one cell of each of the other two element tables as well - the
    # capture's per-'.gcda' table and the report's per-object table - and one
    # count and one whole-run phase time, which are scalar rows:  those keep
    # their row when the value cannot be written, so that the next key does not
    # overwrite the label of the one which failed.
    jq -r '."0" |= del(.merge) | ."1".total = "corrupt"
           | (.check_consistency | keys[0]) as $k
           | .check_consistency[$k] = "corrupt"' agg_prof.json \
        > bad_agg.json
    # ('' is the report's top level, and would leave the warning naming no
    #  object at all - pick one which has a name)
    jq -r '.segment."0" = "corrupt" | .parse_current = "corrupt"
           | (.file | keys | map(select(length > 0)) | .[0]) as $k
           | .file[$k] = "corrupt"' prof.json \
        > bad_prof.json
    jq -r '.write = "corrupt" | .nChunks = "corrupt"
           | (.exec | keys[0]) as $k | .exec[$k] = "corrupt"' geninfo_prof.json \
        > bad_geninfo.json
    echo $SPREADSHEET_TOOL -o bad.xlsx bad_agg.json bad_prof.json bad_geninfo.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o bad.xlsx bad_agg.json bad_prof.json \
        bad_geninfo.json 2>&1 | tee bad.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f bad.xlsx ] ; then
        fail_memory spreadsheet "spreadsheet generation for corrupt profile"
    fi
    for expect in 'bad_geninfo.json: unable to write corrupt for write' \
                  'bad_geninfo.json: unable to write corrupt for nChunks' \
                  'bad_geninfo.json: unable to write corrupt for .*\.exec' \
                  'bad_agg.json: no merge for segment 0' \
                  'bad_agg.json: unable to write corrupt for segment 1.total' \
                  'bad_prof.json: unable to write corrupt for segment 0.segment' \
                  'bad_prof.json: unable to write corrupt for parse_current' \
                  'bad_prof.json: unable to write corrupt for .*\.file' \
                  'bad_agg.json: unable to write corrupt for .*\.c\.check_consistency' ; do
        if ! grep -E "$expect" bad.log >/dev/null ; then
            cat bad.log
            fail_memory spreadsheet "no warning matching '$expect'"
        fi
    done
    # ...and the count whose value could not be written still has its own row,
    # with the rows which follow it where they belong:  the label used to be
    # written and the row then not advanced, so the next count overwrote it.
    python3 ./check_scalar_row.py bad.xlsx bad_geninfo.json chunkSize nFiles
    if [ 0 != $? ] ; then
        fail_memory spreadsheet "count rows after a corrupt 'nChunks'"
    fi

    # a profile which quotes its numbers - a writer which emitted them as JSON
    # strings - recorded them just as much as one which did not, so they have to
    # be written as the numbers they are rather than reported as unwritable.
    # Quote one of each kind:  a count, a whole-run scalar, an element table cell
    # and one of the directory scan times.
    jq -r '.nFiles |= tostring | .write |= tostring
           | .exec |= with_entries(.value |= tostring)
           | .find |= with_entries(.value |= tostring)' geninfo_prof.json \
        > str_geninfo.json
    echo $SPREADSHEET_TOOL -o str.xlsx str_geninfo.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o str.xlsx str_geninfo.json 2>&1 | \
        tee str.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f str.xlsx ] ; then
        fail_memory spreadsheet "spreadsheet generation for a quoted profile"
    elif grep -E 'str_geninfo.json: unable to write' str.log ; then
        fail_memory spreadsheet "quoted numbers reported as unwritable"
    else
        python3 ./check_scalar_row.py str.xlsx str_geninfo.json nFiles write
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "quoted scalar rows"
        fi
        python3 ./check_table_column.py str.xlsx str_geninfo.json files exec
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "quoted 'exec' column"
        fi
        python3 ./check_value_list.py str.xlsx str_geninfo.json find \
            `jq -r '.find | length' str_geninfo.json`
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "quoted 'find' value list"
        fi
    fi

    # the capture's file table is sorted by the order the files were processed
    # in, most recently finished first.  A capture which recorded which files it
    # read but not that order still has a file table to write:  say which file
    # has no order and put it wherever, rather than reporting no 'file' data at
    # all and dropping every row of it.
    # ...and a capture which recorded no per-file data at all does not have a
    # file table, which is what that message is for;  drop one of the run-shape
    # counts from it too, since a count which was not recorded has no row rather
    # than an empty one.
    jq -r 'del(.order)' geninfo_prof.json > noorder_geninfo.json
    jq -r 'del(.file) | del(.interval)' geninfo_prof.json > nofiles_geninfo.json
    echo $SPREADSHEET_TOOL -o noorder.xlsx noorder_geninfo.json \
        nofiles_geninfo.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o noorder.xlsx noorder_geninfo.json \
        nofiles_geninfo.json 2>&1 | tee noorder.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f noorder.xlsx ] ; then
        fail_memory spreadsheet "spreadsheet generation without processing order"
    elif grep -F "No 'file' data in noorder_geninfo.json" noorder.log ; then
        fail_memory spreadsheet "file table dropped with the processing order"
    else
        if ! grep -E 'noorder_geninfo.json: no processing order for ' \
             noorder.log >/dev/null ; then
            cat noorder.log
            fail_memory spreadsheet "no warning for a file with no order"
        fi
        # the table is there, and the column the order would have been in is
        # not:  a key with nothing under it gets no column at all
        python3 ./check_table_column.py noorder.xlsx noorder_geninfo.json \
            files file exec -order
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "file table without a processing order"
        fi
        # ...and the capture with no per-file data at all is what that message
        # is really about, and its sheet is still written:  the counts it did
        # record, and the scan times, are worth having on their own
        if ! grep -F "No 'file' data in nofiles_geninfo.json" \
             noorder.log >/dev/null ; then
            cat noorder.log
            fail_memory spreadsheet "no message for a capture with no file data"
        fi
        python3 ./check_scalar_row.py noorder.xlsx nofiles_geninfo.json \
            chunkSize nChunks nFiles
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "counts without an interval"
        fi
        python3 ./check_value_list.py noorder.xlsx nofiles_geninfo.json find \
            `jq -r '.find | length' nofiles_geninfo.json`
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "'find' value list with no file data"
        fi
    fi

    # the directory scan times are read out of the profile rather than assumed
    # to be there and to be a hash:  a capture which recorded none has the label
    # and nothing under it, and one which recorded something else is reported.
    # Reading it unguarded took out the sheet, every profile after it, and the
    # workbook.
    # ...and one whose scan times are a hash with something unwritable in it is
    # the third case:  that one is per directory, so it names the directory.
    jq -r 'del(.find)' geninfo_prof.json > nofind_geninfo.json
    jq -r '.find = "corrupt"' geninfo_prof.json > badfind_geninfo.json
    jq -r '.find = { "./nowhere": "corrupt" }' geninfo_prof.json \
        > badfindval_geninfo.json
    echo $SPREADSHEET_TOOL -o find.xlsx nofind_geninfo.json \
        badfind_geninfo.json badfindval_geninfo.json geninfo_prof.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o find.xlsx nofind_geninfo.json \
        badfind_geninfo.json badfindval_geninfo.json geninfo_prof.json 2>&1 | \
        tee find.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f find.xlsx ] ; then
        cat find.log
        fail_memory spreadsheet "spreadsheet generation without scan times"
    else
        for expect \
            in 'badfind_geninfo.json: unable to write corrupt for find' \
               'badfindval_geninfo.json: unable to write corrupt for \[find\]\[./nowhere\]' ; do
            if ! grep -E "$expect" find.log >/dev/null ; then
                cat find.log
                fail_memory spreadsheet "no warning matching '$expect'"
            fi
        done
        for f in nofind_geninfo.json badfind_geninfo.json ; do
            python3 ./check_value_list.py find.xlsx $f find 0
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "$f 'find' label"
            fi
        done
        # and the profile after them is still on the workbook, with its own
        # scan times intact
        python3 ./check_value_list.py find.xlsx geninfo_prof.json find \
            `jq -r '.find | length' geninfo_prof.json`
        if [ 0 != $? ] ; then
            fail_memory spreadsheet "'find' value list after a corrupt one"
        fi
    fi

    # what a genhtml sheet's per-object table covers is 'file' - one row per
    # source file and directory - but a profile old enough not to have recorded
    # a per-file total has only 'html', the time to write each page, so the
    # sheet falls back to that.  A profile with neither is not something a sheet
    # can be written from at all:  say so and go on to the next profile rather
    # than write a table with no rows.
    jq -r 'del(.file)' prof.json > nofile_prof.json
    jq -r 'del(.file) | del(.html)' prof.json > noscope_prof.json
    echo $SPREADSHEET_TOOL -o noscope.xlsx nofile_prof.json noscope_prof.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o noscope.xlsx nofile_prof.json \
        noscope_prof.json 2>&1 | tee noscope.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f noscope.xlsx ] ; then
        fail_memory spreadsheet "spreadsheet generation without per-file data"
    fi
    if ! grep -E 'noscope_prof.json: +incomplete data - skipping' \
         noscope.log >/dev/null ; then
        cat noscope.log
        fail_memory spreadsheet "no warning for a profile with nothing to report"
    fi
    # the fallback sheet is a real one:  its per-object table is keyed by the
    # pages 'html' was recorded for
    python3 ./check_table_layout.py noscope.xlsx nofile_prof.json segments
    if [ 0 != $? ] ; then
        fail_memory spreadsheet "nofile_prof.json sub-table layout"
    fi
    # ...and the observed parallelism beside the elapsed total divides that
    # fallback key's total, not whatever the first per-object column happens to
    # be.  The column was counted from the left, so dropping 'file' - which is
    # normally that first column - left the figure dividing the next metric
    # along, which is a plausible-looking number and the wrong one.
    python3 ./check_parallelism.py noscope.xlsx nofile_prof.json html
    if [ 0 != $? ] ; then
        fail_memory spreadsheet "nofile_prof.json observed parallelism"
    fi

    # the elapsed total is what that figure is divided by, and a report can be
    # missing it - a profile written by an older tool, or one truncated before
    # the run ended.  The sheet is still worth writing:  leave out the one figure
    # which needs the total and keep the rest.  Nothing may be carried over from
    # the sheet before either, which is what a per-workbook total was:  the
    # formula then divided by another report's row.
    jq -r 'del(.total) | del(.overall)' prof.json > nototal_prof.json
    jq -r '.total = "corrupt"' prof.json > badtotal_prof.json
    echo $SPREADSHEET_TOOL -o nototal.xlsx prof.json nototal_prof.json \
        badtotal_prof.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o nototal.xlsx prof.json \
        nototal_prof.json badtotal_prof.json 2>&1 | tee nototal.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f nototal.xlsx ] ; then
        cat nototal.log
        fail_memory spreadsheet "spreadsheet generation without an elapsed total"
    else
        if ! grep -E 'badtotal_prof.json: unable to write corrupt for total' \
             nototal.log >/dev/null ; then
            cat nototal.log
            fail_memory spreadsheet "no warning for a corrupt elapsed total"
        fi
        # both sheets are real, and neither of them has borrowed the total of
        # the sheet in front of it
        for f in nototal_prof.json badtotal_prof.json ; do
            python3 ./check_table_layout.py nototal.xlsx $f segments
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "$f sub-table layout"
            fi
            echo "expect the following check to fail (profile has no total):"
            python3 ./check_parallelism.py nototal.xlsx $f file
            if [ 0 == $? ] ; then
                fail_memory spreadsheet \
                    "$f has an observed parallelism with no elapsed total"
            fi
        done
    fi

    # 'lcov --extract' and '--remove' read exactly one file, so they record
    # 'parse' as a single number rather than as a hash of per-file times.  The
    # sheet has to write whichever of the two shapes the profile has - a scalar
    # row here, in place of the 'info' table - and it still gets the 'source'
    # table, which is per source file rather than per input file and which no
    # lcov sheet used to show at all.
    $COVER $LCOV_TOOL -e cov.info '*/a.c' -o extract.info \
        --profile extract_prof.json --ignore empty,inconsistent \
        2>&1 | tee extract.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail_memory spreadsheet "lcov --extract failed"
    elif [ "`jq -r '.parse | type' extract_prof.json`" != "number" ] ; then
        jq -r '.' extract_prof.json
        fail_memory spreadsheet "'parse' is not a scalar in extract_prof.json"
    else
        echo $SPREADSHEET_TOOL -o extract.xlsx extract_prof.json
        eval ${PYCOVER} $SPREADSHEET_TOOL -o extract.xlsx extract_prof.json \
            2>&1 | tee extract_spreadsheet.log
        if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f extract.xlsx ] ; then
            fail_memory spreadsheet "spreadsheet generation for lcov --extract"
        else
            python3 ./check_scalar_row.py extract.xlsx extract_prof.json parse
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "scalar 'parse' row for lcov --extract"
            fi
            python3 ./check_table_layout.py extract.xlsx extract_prof.json \
                source
            if [ 0 != $? ] ; then
                fail_memory spreadsheet "'source' table for lcov --extract"
            fi
        fi
        # ...and that row is a number, so a corrupt one has to be reported
        # rather than crash the write, exactly as for a table cell
        jq -r '.parse = "corrupt"' extract_prof.json > bad_extract.json
        eval ${PYCOVER} $SPREADSHEET_TOOL -o bad_extract.xlsx \
            bad_extract.json 2>&1 | tee bad_extract.log
        if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f bad_extract.xlsx ] ; then
            fail_memory spreadsheet \
                "spreadsheet generation for a corrupt scalar 'parse'"
        elif ! grep -E 'bad_extract.json: unable to write corrupt for parse' \
                bad_extract.log >/dev/null ; then
            cat bad_extract.log
            fail_memory spreadsheet "no warning for a corrupt scalar 'parse'"
        fi
    fi
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
