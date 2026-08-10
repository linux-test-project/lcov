#!/bin/bash
set +x

# Exercise the failure arms of every fork/join loop in the toolchain:  a fork()
#   which fails, a child which the OS kills, and a child which leaves no
#   serialized data behind.  None of these is reachable by running the tools
#   normally - they need a machine which has really run out of process slots or
#   memory - so 'lcovutil::fork_child' injects them on request:
#
#     LCOV_FORCE_FORK_FAIL=N   the next N fork() calls report failure
#     LCOV_FORCE_CHILD_KILL=N  the next N children SIGKILL themselves before
#                              doing any work
#     LCOV_FORCE_NO_DUMP=N     the next N children exit(0) before doing any
#                              work, so the parent finds nothing to merge
#     LCOV_FORCE_ORPHAN=N      the next N forks leave behind an extra process
#                              which the parent is not tracking, which is what
#                              a callback module that leaks a child looks like
#     LCOV_FORCE_OOM_MSG=N     the next N children write an out-of-memory
#                              complaint to the log the parent reads and exit
#                              non-zero without being signalled (geninfo only)
#     LCOV_FORCE_BAD_DATA=N    the next N children exit(0) after leaving data
#                              behind which the parent can read but cannot use
#     LCOV_FORCE_STORE_FAIL=N  the next N children cannot write the data they
#                              computed, which is what a full or read-only
#                              filesystem looks like (ForkManager::fork_one)
#
#   There are five such loops and each one is driven here:
#     site 1  TraceFile::_processFilterWorklist  ('lcov -a --filter', >50 files)
#     site 2  AggregateTraces::_parallel_parse   ('lcov -a', input split into
#                                                 chunks)
#     site 3  AggregateTraces::merge segments    ('lcov -a', one segment per
#                                                 testcase, no chunk split)
#     site 4  geninfo's compute-chunk loop
#     site 5  genhtml's compute-job scheduler
#
#   In each case the assertions are:
#     - the unit is put back on the worklist and the run still succeeds
#     - the retried run produces exactly what the un-injected run produced
#     - the message says which unit failed, and why:  'killed by OS' only for a
#       child which was signalled, never for one which exited
#     - the same unit failing more than 'max_fork_fails' times escalates to
#       ERROR_PARALLEL instead of being retried forever, and that error is
#       ignorable
#     - a process which the parent never forked is reported and otherwise
#       ignored:  it is not one of ours, so it does not reduce the number of
#       children we are still waiting for, and the run still produces
#       everything
#
#   The escalation case is what genhtml could not do:  it passed the retry count
#   to 'report_fork_failure' in the wrong argument slot, so the count it tested
#   was always the literal 0 and a job which failed every time was rescheduled
#   forever.

source ../../common.tst

rm -rf *.info *.log *.json *.txt *.c *.o *.gcda *.gcno a.out rpt_* \
    cover_db.dat html_report perlcov.info pycov.info __pycache__

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type ${CC} >/dev/null 2>&1 ; then
    echo "Missing tool: ${CC}" >&2
    exit 2
fi

if [ 'x' == "x$LCOV_TOOL" ] ; then
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    GENINFO_TOOL=${LCOV_HOME}/bin/geninfo
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
fi

# Each case below chooses which of the five loops the injected failure lands in,
#   and LCOV_FORCE_PARALLEL moves that choice:  it makes the read split its
#   input where this test wants the read to be serial, and it makes a child fork
#   filter workers of its own - so the injected failure would be spent
#   somewhere other than the loop the case is about.  The suite runs the whole
#   testsuite with the variable set, so drop it rather than let it decide.
unset LCOV_FORCE_PARALLEL

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

expect_msg()
{
    # $1 = label, $2 = logfile, $3 = extended regexp which has to appear in it
    if ! grep -E "$3" $2 >/dev/null ; then
        cat $2
        fail $1 "expected /$3/ in $2"
    fi
}

reject_msg()
{
    # $1 = label, $2 = logfile, $3 = extended regexp which must NOT appear
    if grep -E "$3" $2 >/dev/null ; then
        cat $2
        fail $1 "unexpected /$3/ in $2"
    fi
}

expect_status()
{
    # $1 = label, $2 = the status we got, $3 = the status we wanted
    if [ "$2" != "$3" ] ; then
        fail $1 "exit status $2, expected $3"
    fi
}

expect_nonzero()
{
    # $1 = label, $2 = the status we got
    if [ "$2" == 0 ] ; then
        fail $1 "exit status 0, expected a failure"
    fi
}

expect_same()
{
    # $1 = label, $2 = reference file, $3 = the file the injected run wrote
    if [ ! -f $3 ] ; then
        fail $1 "$3 was not written"
    elif ! diff $2 $3 ; then
        fail $1 "the retried run produced different data"
    fi
}

# 'fork_fail_timeout' is how long the parent sleeps before re-trying;  every
#   case here injects several failures, so leave it at 0 rather than spend the
#   default 10 seconds per failure.  'max_fork_fails' is left alone except in
#   the escalation cases, which set it explicitly.
IGN="--ignore-errors fork --rc fork_fail_timeout=0"
LOW="--rc max_fork_fails=2 $IGN"
# an untracked process is ERROR_CHILD rather than ERROR_FORK:  nothing failed,
#   the parent just reaped something which was not its own
ORPHAN="--ignore-errors child"

#-----------------------------------------------------------------------
# the inputs:  one large tracefile for the chunk-split read and the filter
#   worklist, two small ones for the per-testcase segment path, and a real
#   capture for geninfo and genhtml
#-----------------------------------------------------------------------
GEN_INFO=../parallel_parse/gen_info.pl
perl $GEN_INFO many.info 60 40
perl $GEN_INFO a.info 4 20
perl $GEN_INFO b.info 4 20
# ..and a copy of the second one with a record which cannot be parsed, so that a
#   segment child exits non-zero rather than being signalled
BAD_LINE=`grep -n '^DA:' b.info | tail -1 | cut -d: -f1`
awk -v n=$BAD_LINE '{ print (NR == n ? "DA:oops" : $0) }' b.info > bad.info

cat > cc1.c <<'EOF'
int fa(int x){ if (x > 0) return 1; return 0; }
int main(){ return fa(1) - 1; }
EOF
cat > cc2.c <<'EOF'
int fb(int x){ if (x > 1) return 2; return 0; }
EOF
${CC} --coverage -c cc1.c cc2.c
${CC} --coverage cc1.o cc2.o -o a.out
./a.out

#-----------------------------------------------------------------------
# site 2:  the chunk-split read.  'parallel_parse_min_lines=1' makes this
#   small input "large" and 'dedicate_segment_line_estimate=10' lets it be cut
#   into several chunks
#-----------------------------------------------------------------------
PARSE="--parallel 4 --rc parallel_parse_min_lines=1 \
       --rc dedicate_segment_line_estimate=10"

echo "*** site 2: chunk-split read, no injected failure"
$COVER $LCOV_TOOL -a many.info $PARSE -o parse_base.info > parse_base.log 2>&1
expect_status parse_base $? 0
expect_msg parse_base parse_base.log 'in [0-9]+ chunks'

echo "*** site 2: fork() fails twice"
LCOV_FORCE_FORK_FAIL=2 $COVER $LCOV_TOOL -a many.info $PARSE $IGN \
    -o parse_ff.info > parse_ff.log 2>&1
expect_status parse_ff $? 0
expect_msg parse_ff parse_ff.log \
    '\(fork\) fork\(\) syscall failed while trying to read tracefile chunk'
expect_same parse_ff parse_base.info parse_ff.info

echo "*** site 2: two children killed by the OS"
LCOV_FORCE_CHILD_KILL=2 $COVER $LCOV_TOOL -a many.info $PARSE $IGN \
    -o parse_ck.info > parse_ck.log 2>&1
expect_status parse_ck $? 0
expect_msg parse_ck parse_ck.log \
    'read chunk [0-9]+: killed by OS - possibly due to out-of-memory'
expect_same parse_ck parse_base.info parse_ck.info

echo "*** site 2: two children leave no serialized data"
LCOV_FORCE_NO_DUMP=2 $COVER $LCOV_TOOL -a many.info $PARSE $IGN \
    -o parse_nd.info > parse_nd.log 2>&1
expect_status parse_nd $? 0
expect_msg parse_nd parse_nd.log \
    'read chunk [0-9]+: serialized data .*dumper_[0-9]+ not found'
# the children exited, they were not signalled, so the out-of-memory guess has
#   no business being here
reject_msg parse_nd parse_nd.log 'killed by OS'
expect_same parse_nd parse_base.info parse_nd.info

echo "*** site 2: a process the parent never forked"
LCOV_FORCE_ORPHAN=1 $COVER $LCOV_TOOL -a many.info $PARSE $ORPHAN \
    -o parse_orph.info > parse_orph.log 2>&1
expect_status parse_orph $? 0
expect_msg parse_orph parse_orph.log 'found unknown process [0-9]+ while waiting'
# it is not one of ours, so it must not be counted as one of the chunks we are
#   waiting for:  if it is, a chunk is never merged and data goes missing
expect_same parse_orph parse_base.info parse_orph.info

echo "*** site 2: a child which reports success but leaves unusable data"
# the child said it succeeded, so there is no status to blame the failure on:
#   the parent invents "exited with 1".  Handing the reporters an already
#   shifted status turns that into "died due to signal 1".
LCOV_FORCE_BAD_DATA=1 $COVER $LCOV_TOOL -a many.info $PARSE \
    -o parse_bd.info > parse_bd.log 2>&1
expect_nonzero parse_bd $?
expect_msg parse_bd parse_bd.log 'unable to merge chunk [0-9]+'
expect_msg parse_bd parse_bd.log 'returned non-zero exit status 1'
reject_msg parse_bd parse_bd.log 'due to signal'

echo "*** site 2: more consecutive fork() failures than max_fork_fails"
LCOV_FORCE_FORK_FAIL=3 $COVER $LCOV_TOOL -a many.info $PARSE $LOW \
    -o parse_ffx.info > parse_ffx.log 2>&1
expect_nonzero parse_ffx $?
expect_msg parse_ffx parse_ffx.log \
    'ERROR: \(parallel\) 3 consecutive fork\(\) failures'

echo "*** site 2: ..and that error is ignorable"
LCOV_FORCE_FORK_FAIL=3 $COVER $LCOV_TOOL -a many.info $PARSE $LOW \
    --ignore-errors parallel -o parse_ffi.info > parse_ffi.log 2>&1
expect_status parse_ffi $? 0
expect_msg parse_ffi parse_ffi.log \
    'WARNING: \(parallel\) 3 consecutive fork\(\) failures'
expect_same parse_ffi parse_base.info parse_ffi.info

echo "*** site 2: a chunk which is killed every time is not retried forever"
LCOV_FORCE_CHILD_KILL=20 $COVER $LCOV_TOOL -a many.info $PARSE $LOW \
    -o parse_ckx.info > parse_ckx.log 2>&1
expect_nonzero parse_ckx $?
expect_msg parse_ckx parse_ckx.log \
    'ERROR: \(parallel\) [0-9]+ consecutive fork\(\) failures'

#-----------------------------------------------------------------------
# site 1:  the filter worklist.  'parallel_parse_min_lines=0' keeps the read
#   serial - so the filters run in the parent, which forks a worker per chunk
#   of the 60 files rather than filtering in the read children
#-----------------------------------------------------------------------
FILTER="--parallel 4 --rc parallel_parse_min_lines=0 --filter blank,brace"

echo "*** site 1: filter worklist, no injected failure"
$COVER $LCOV_TOOL -a many.info $FILTER -o filt_base.info > filt_base.log 2>&1
expect_status filt_base $? 0
expect_msg filt_base filt_base.log 'Filter: chunkSize [0-9]+ nChunks [0-9]+'

echo "*** site 1: two filter children killed by the OS"
LCOV_FORCE_CHILD_KILL=2 $COVER $LCOV_TOOL -a many.info $FILTER $IGN \
    -o filt_ck.info > filt_ck.log 2>&1
expect_status filt_ck $? 0
expect_msg filt_ck filt_ck.log \
    'filter segment [0-9]+: killed by OS - possibly due to out-of-memory'
expect_same filt_ck filt_base.info filt_ck.info

echo "*** site 1: two filter children leave no serialized data"
LCOV_FORCE_NO_DUMP=2 $COVER $LCOV_TOOL -a many.info $FILTER $IGN \
    -o filt_nd.info > filt_nd.log 2>&1
expect_status filt_nd $? 0
expect_msg filt_nd filt_nd.log \
    'filter segment [0-9]+: serialized data .*dumper_[0-9]+ not found'
reject_msg filt_nd filt_nd.log 'killed by OS'
expect_same filt_nd filt_base.info filt_nd.info

echo "*** site 1: a process the parent never forked"
LCOV_FORCE_ORPHAN=1 $COVER $LCOV_TOOL -a many.info $FILTER $ORPHAN \
    -o filt_orph.info > filt_orph.log 2>&1
expect_status filt_orph $? 0
expect_msg filt_orph filt_orph.log 'found unknown process [0-9]+ while waiting'
expect_same filt_orph filt_base.info filt_orph.info

#-----------------------------------------------------------------------
# site 3:  one segment per testcase.  Two inputs, each with its own testname,
#   and 'parallel_parse_min_lines=0' so that the read is not chunk-split
#   instead
#-----------------------------------------------------------------------
SEG="--parallel 4 --rc parallel_parse_min_lines=0"

echo "*** site 3: segment read, no injected failure"
$COVER $LCOV_TOOL -a a.info -a b.info $SEG -o seg_base.info > seg_base.log 2>&1
expect_status seg_base $? 0
expect_msg seg_base seg_base.log 'Using 2 segments'

echo "*** site 3: both segment children killed by the OS"
LCOV_FORCE_CHILD_KILL=2 $COVER $LCOV_TOOL -a a.info -a b.info $SEG $IGN \
    -o seg_ck.info > seg_ck.log 2>&1
expect_status seg_ck $? 0
expect_msg seg_ck seg_ck.log \
    'aggregate segment [0-9]+: killed by OS - possibly due to out-of-memory'
# the retried segment is forked in a second pass of the outer loop:  reaping a
#   fixed count of children rather than the ones which are running asks wait()
#   for children which do not exist
reject_msg seg_ck seg_ck.log 'found unknown process'
expect_same seg_ck seg_base.info seg_ck.info

echo "*** site 3: both segment children leave no serialized data"
LCOV_FORCE_NO_DUMP=2 $COVER $LCOV_TOOL -a a.info -a b.info $SEG $IGN \
    -o seg_nd.info > seg_nd.log 2>&1
expect_status seg_nd $? 0
expect_msg seg_nd seg_nd.log \
    'aggregate segment [0-9]+: serialized data .*dumper_[0-9]+ not found'
reject_msg seg_nd seg_nd.log 'killed by OS'
expect_same seg_nd seg_base.info seg_nd.info

echo "*** site 3: a child which reports success but leaves unusable data"
LCOV_FORCE_BAD_DATA=1 $COVER $LCOV_TOOL -a a.info -a b.info $SEG \
    -o seg_bd.info > seg_bd.log 2>&1
expect_nonzero seg_bd $?
expect_msg seg_bd seg_bd.log 'unable to deserialize segment [0-9]+'
expect_msg seg_bd seg_bd.log 'returned non-zero exit status 1'
reject_msg seg_bd seg_bd.log 'due to signal'

echo "*** site 3: a child which cannot write the data it computed"
# a child which fails to dump must not report success:  the parent would look
#   for a file which is not there instead of running the segment again.  This is
#   the rule genhtml used to be alone in applying.
# One failure, not two:  a retried segment is forked after some other segment
#   has already been merged, and a child which merged into the parent's running
#   total handed that total back to be counted a second time.  Injecting a
#   failure for every segment hides it, because then nothing has been merged yet.
LCOV_FORCE_STORE_FAIL=1 $COVER $LCOV_TOOL -a a.info -a b.info $SEG $IGN \
    --ignore-errors parallel -o seg_sf.info > seg_sf.log 2>&1
expect_status seg_sf $? 0
expect_msg seg_sf seg_sf.log 'Child [0-9]+ serialize failed'
# no dumpfile, so the segment is retried rather than blamed on the child
expect_msg seg_sf seg_sf.log \
    'aggregate segment [0-9]+: serialized data .*dumper_[0-9]+ not found'
expect_same seg_sf seg_base.info seg_sf.info

echo "*** site 3: a process the parent never forked"
LCOV_FORCE_ORPHAN=1 $COVER $LCOV_TOOL -a a.info -a b.info $SEG $ORPHAN \
    -o seg_orph.info > seg_orph.log 2>&1
expect_status seg_orph $? 0
expect_msg seg_orph seg_orph.log 'found unknown process [0-9]+ while waiting'
expect_same seg_orph seg_base.info seg_orph.info

echo "*** site 3: a segment child which exits non-zero is not a signalled child"
$COVER $LCOV_TOOL -a a.info -a bad.info $SEG -o seg_bad.info \
    > seg_bad.log 2>&1
expect_nonzero seg_bad $?
expect_msg seg_bad seg_bad.log \
    "\(child\) aggregate: 'while processing segment [0-9]+'"
# the child exited with 1;  reporting the already-shifted wait status would
#   turn that into "died due to signal 1"
expect_msg seg_bad seg_bad.log 'returned non-zero exit status 1'
reject_msg seg_bad seg_bad.log 'due to signal'

#-----------------------------------------------------------------------
# site 4:  geninfo's compute chunks.  'geninfo_dedicate_segment_size=1' gives
#   each of the two .gcda a forked chunk of its own
#-----------------------------------------------------------------------
CAPTURE="--parallel 4 --rc geninfo_dedicate_segment_size=1 --ignore empty"

echo "*** site 4: capture, no injected failure"
$COVER $GENINFO_TOOL . $CAPTURE -o cap_base.info > cap_base.log 2>&1
expect_status cap_base $? 0

echo "*** site 4: fork() fails twice"
LCOV_FORCE_FORK_FAIL=2 $COVER $GENINFO_TOOL . $CAPTURE $IGN \
    -o cap_ff.info > cap_ff.log 2>&1
expect_status cap_ff $? 0
expect_msg cap_ff cap_ff.log \
    '\(fork\) fork\(\) syscall failed while trying to process chunk'
expect_same cap_ff cap_base.info cap_ff.info

echo "*** site 4: a compute child killed by the OS"
LCOV_FORCE_CHILD_KILL=1 $COVER $GENINFO_TOOL . $CAPTURE $IGN \
    -o cap_ck.info > cap_ck.log 2>&1
expect_status cap_ck $? 0
expect_msg cap_ck cap_ck.log \
    'compute job [0-9]+: killed by OS - possibly due to out-of-memory'
# the killed chunk was reaped, so the parent has to stop counting it:  counting
#   only the chunks which succeeded leaves it waiting for a child which is
#   already gone
reject_msg cap_ck cap_ck.log 'found unknown process'
expect_same cap_ck cap_base.info cap_ck.info

echo "*** site 4: a compute child which says it ran out of memory"
# geninfo is the only site which applies this rule:  a child which was not
#   signalled, but whose log says that an allocation failed, is treated as
#   though the OS had killed it, because that chunk is worth another try with
#   less parallelism.
LCOV_FORCE_OOM_MSG=1 $COVER $GENINFO_TOOL . $CAPTURE $IGN \
    -o cap_oom.info > cap_oom.log 2>&1
expect_status cap_oom $? 0
expect_msg cap_oom cap_oom.log 'std::bad_alloc'
expect_msg cap_oom cap_oom.log \
    'compute job [0-9]+: killed by OS - possibly due to out-of-memory'
expect_same cap_oom cap_base.info cap_oom.info

echo "*** site 4: a process the parent never forked"
LCOV_FORCE_ORPHAN=1 $COVER $GENINFO_TOOL . $CAPTURE $ORPHAN \
    -o cap_orph.info > cap_orph.log 2>&1
expect_status cap_orph $? 0
expect_msg cap_orph cap_orph.log 'found unknown process [0-9]+ while waiting'
expect_same cap_orph cap_base.info cap_orph.info

#-----------------------------------------------------------------------
# site 5:  genhtml's compute jobs.  The tiny line estimate and threshold give
#   each source file a segment of its own
#-----------------------------------------------------------------------
REPORT="--parallel 4 --rc dedicate_segment_line_estimate=1 \
        --rc dedicate_segment_threshold=1 --ignore empty,inconsistent"

# genhtml's HTML carries a timestamp, so compare the coverage it reported
#   rather than the files it wrote.  The per-directory lines are printed as the
#   children are merged, which is whatever order they finish in, so sort.
report_summary()
{
    grep -E '^  (lines|functions|branches)' $1 | sort
}

echo "*** site 5: report, no injected failure"
$COVER $GENHTML_TOOL cap_base.info $REPORT -o rpt_base > rpt_base.log 2>&1
expect_status rpt_base $? 0

echo "*** site 5: fork() fails twice"
LCOV_FORCE_FORK_FAIL=2 $COVER $GENHTML_TOOL cap_base.info $REPORT $IGN \
    -o rpt_ff > rpt_ff.log 2>&1
expect_status rpt_ff $? 0
expect_msg rpt_ff rpt_ff.log \
    '\(fork\) fork\(\) syscall failed while trying to process segment [0-9]+'
if ! diff <(report_summary rpt_base.log) <(report_summary rpt_ff.log) ; then
    fail rpt_ff "the run whose fork failed reported different coverage"
fi

echo "*** site 5: a compute child killed by the OS"
LCOV_FORCE_CHILD_KILL=1 $COVER $GENHTML_TOOL cap_base.info $REPORT $IGN \
    -o rpt_ck > rpt_ck.log 2>&1
expect_status rpt_ck $? 0
expect_msg rpt_ck rpt_ck.log '\(fork\) .*compute job [0-9]+ \(child [0-9]+\)'
if [ ! -f rpt_ck/index.html ] ; then
    fail rpt_ck "the retried run wrote no report"
fi
if ! diff <(report_summary rpt_base.log) <(report_summary rpt_ck.log) ; then
    fail rpt_ck "the retried run reported different coverage"
fi

echo "*** site 5: a compute child leaves no serialized data"
LCOV_FORCE_NO_DUMP=1 $COVER $GENHTML_TOOL cap_base.info $REPORT $IGN \
    -o rpt_nd > rpt_nd.log 2>&1
expect_status rpt_nd $? 0
expect_msg rpt_nd rpt_nd.log \
    'compute job [0-9]+ \(child [0-9]+\): serialized data .* not found'
if ! diff <(report_summary rpt_base.log) <(report_summary rpt_nd.log) ; then
    fail rpt_nd "the retried run reported different coverage"
fi

echo "*** site 5: a child which reports success but leaves unusable data"
# the data is readable, so there is nothing to retry:  the job is simply never
#   merged, and the report which would have been missing those pages is not
#   written at all
LCOV_FORCE_BAD_DATA=1 $COVER $GENHTML_TOOL cap_base.info $REPORT \
    -o rpt_bd > rpt_bd.log 2>&1
expect_nonzero rpt_bd $?
expect_msg rpt_bd rpt_bd.log 'unable to deserialize .*dumper_[0-9]+'
expect_msg rpt_bd rpt_bd.log 'returned non-zero exit status 1'
reject_msg rpt_bd rpt_bd.log 'due to signal'

echo "*** site 5: a process the parent never forked"
LCOV_FORCE_ORPHAN=1 $COVER $GENHTML_TOOL cap_base.info $REPORT $ORPHAN \
    -o rpt_orph > rpt_orph.log 2>&1
expect_status rpt_orph $? 0
expect_msg rpt_orph rpt_orph.log 'found unknown process [0-9]+ while waiting'
if ! diff <(report_summary rpt_base.log) <(report_summary rpt_orph.log) ; then
    fail rpt_orph "the run with an orphan reported different coverage"
fi

echo "*** site 5: a job which is killed every time is not rescheduled forever"
# This is the one which needs the retry count to reach 'report_fork_failure':
#   with the count stuck at 0 the comparison against max_fork_fails is never
#   true, every kill is just another reschedule, and the run either finishes as
#   though nothing had happened or never finishes at all.
LCOV_FORCE_CHILD_KILL=20 $COVER $GENHTML_TOOL cap_base.info $REPORT $LOW \
    -o rpt_esc > rpt_esc.log 2>&1
expect_nonzero rpt_esc $?
expect_msg rpt_esc rpt_esc.log \
    'ERROR: \(parallel\) [0-9]+ consecutive fork\(\) failures'

echo "*** done"

if [ $STATUS == 0 ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    generate_coverage 'parallel_fail' $LOCAL_COVERAGE 0
fi

exit $STATUS
