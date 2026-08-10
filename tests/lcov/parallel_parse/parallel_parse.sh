#!/bin/bash
set +x

# Exercise the parallel read of the '.info' files 'lcov -a' is given:  it used
#   to fork a child per input file, so one input file was read serially no matter
#   how large it was, and a set of inputs was divided by input rather than by
#   work.  The inputs are now scanned, split at 'end_of_record' boundaries, and
#   the pieces read - and filtered - by several children at once (see
#   '$lcovutil::parallel_parse_min_lines' and
#   'AggregateTraces::_parallel_parse').  A chunk can hold sections from more
#   than one input, and holds all of the sections naming any source file it
#   holds a section for, wherever in the set they are.
#
# In every case the assertion that matters is that the split read produces
#   exactly what the serial read produced - the same data, the same messages,
#   the same exit status:
#   1. identity, in both the XS and the pure-Perl backend
#   2. a testname inherited from the top of the file by a section which a later
#      chunk reads
#   3. line numbers in diagnostics are file-relative, not chunk-relative
#   4. a source file which appears under several testnames is not split across
#      chunks
#   5. a skewed file - one source file with most of the lines - either splits
#      into fewer pieces or is not split at all
#   6. a file below the threshold is not split, and LCOV_FORCE_PARALLEL says to
#      split it anyway
#   7. a compressed (unseekable) file falls back to the serial read.  Note that
#      'lcov -a' cannot read standard input at all ("'-' ... is not a readable
#      file"), so the '-' case in the seekability check is unreachable from here
#   8. the filters run in the read children, once - not again in the parent
#   9. a truncated final section is the same format error as before
#  10. an input larger than the scanner's read buffer, an 'end_of_record' which
#      is not at the start of a line, and comments after the last section
#  11. '--memory' throttles the read
#  12. a chunk which cannot be read at all
#  13. '--map-functions', which merges into a table rather than a tracefile
#  14. a source file whose sections are scattered through the file, under
#      several testnames and more than once under one of them
#  15. the '--profile' data reports each phase where it happened - per chunk
#      when the chunks did it, per input file when whole files were read - and
#      the spreadsheet made from it shows the chunks and both of those tables
#  16. several inputs at once:  one source file carried by two of them, a large
#      input packed together with many small ones, an input which cannot be
#      split, a bad record in the second input, '--prune-tests', and a set from
#      which every source file is excluded

source ../../common.tst

rm -rf *.info *.info.gz *.log *.json *.txt *.c *.xlsx cover_db.dat \
    html_report perlcov.info pycov.info __pycache__

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if [ 'x' == "x$LCOV_TOOL" ] ; then
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
fi

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

# read the file serially:  the reference for every case
SERIAL="--parallel 1 --rc parallel_parse_min_lines=0"
# ..and read it in parallel.  These inputs are small, so lower both thresholds:
#   'parallel_parse_min_lines' to make the file "large", and
#   'dedicate_segment_line_estimate' because it also bounds the chunk count.
SPLIT="--parallel 4 --rc parallel_parse_min_lines=1 \
       --rc dedicate_segment_line_estimate=10"

norm_log()
{
    # The chunk count is expected to differ (the serial read does not print it)
    #   and the children finish in whatever order they finish in, so sort.
    # A message from a child never carries the "(use --ignore-errors ..)" hint
    #   - see '$lcovutil::in_child_process' in 'lcovutil::ignorable_error':
    #   several children would each print it, and each one counts occurrences
    #   only within itself.  The same is true of the existing one-child-per-
    #   input-file read, so drop the hint rather than treat it as a difference.
    # 'Merging <input>..N remaining' counts the inputs down within whichever
    #   process is reading them, so with more than one input its text depends on
    #   how the work was divided - as it already did for the one-child-per-input
    #   read.  The chunk children do not print it at all.
    # 'Filter: chunkSize .. nChunks ..' announces the chunking of the SEPARATE
    #   filter pass, which only the unsplit read has - a split read filters in
    #   the read children and never gets there.  With '--parallel 1' that pass
    #   normally says nothing, but 'LCOV_FORCE_PARALLEL' makes it chunk and
    #   announce anyway, so the line has to be dropped rather than compared.
    grep -v -E 'in [0-9]+ chunk|^Removing temporary directories' $1 |
        grep -v -E '^	\(use "|^Merging .* remaining|^Using [0-9]+ segment' |
        grep -v -E '^Filter: chunkSize' |
        sort
}

chunk_count()
{
    # how many pieces the file was split into, 0 if it was not split
    local n
    n=`grep -oE 'in [0-9]+ chunks' $1 | grep -oE '[0-9]+'`
    echo ${n:-0}
}

run_multi()
{
    # $1 = scenario label, $2 = the input tracefiles, space separated, $3.. =
    #   extra lcov arguments.
    # Read the inputs both ways and require the same result.  Both runs write to
    #   the same output name, so that the log text can be compared directly.
    local label=$1 inputs=$2
    shift 2
    local args= f
    for f in $inputs ; do
        args="$args -a $f"
    done
    rm -f out.info
    echo "$LCOV_TOOL $args -o out.info $SERIAL $@"
    $COVER $LCOV_TOOL $args -o out.info $SERIAL "$@" \
        > ${label}_serial.log 2>&1
    local serialStatus=$?
    if [ -f out.info ] ; then
        mv out.info ${label}_serial.info
    fi
    echo "$LCOV_TOOL $args -o out.info $SPLIT $@"
    $COVER $LCOV_TOOL $args -o out.info $SPLIT "$@" \
        > ${label}_split.log 2>&1
    local splitStatus=$?
    if [ -f out.info ] ; then
        mv out.info ${label}_split.info
    fi

    if [ $serialStatus != $splitStatus ] ; then
        fail $label "exit status $splitStatus, expected $serialStatus"
    fi
    if [ -f ${label}_serial.info ] || [ -f ${label}_split.info ] ; then
        if ! diff ${label}_serial.info ${label}_split.info ; then
            fail $label "split read produced different data"
        fi
    fi
    if ! diff <(norm_log ${label}_serial.log) \
              <(norm_log ${label}_split.log) ; then
        fail $label "split read produced different messages"
    fi
}

run_pair()
{
    # $1 = scenario label, $2 = input tracefile, $3.. = extra lcov arguments
    local label=$1 input=$2
    shift 2
    run_multi $label "$input" "$@"
}

#-----------------------------------------------------------------------
# 1. identity:  8 sections, in both backends - and the two backends have to
#    agree with each other as well as with their own serial read
#-----------------------------------------------------------------------
perl ./gen_info.pl multi.info 8 40
for backend in xs pure_perl ; do
    if [ $backend == pure_perl ] ; then
        export LCOV_PURE_PERL=1
    else
        unset LCOV_PURE_PERL
    fi
    run_pair identity_$backend multi.info
    if [ 0 == `chunk_count identity_${backend}_split.log` ] ; then
        fail identity_$backend "file was not split"
    fi
done
unset LCOV_PURE_PERL
if ! diff identity_xs_split.info identity_pure_perl_split.info ; then
    fail identity "XS and pure-Perl split reads disagree"
fi

#-----------------------------------------------------------------------
# 2. inherited testname:  one 'TN:' at the top of the file, so every section
#    but the first - and thus every chunk but the first - has to be told which
#    testcase it belongs to
#-----------------------------------------------------------------------
perl ./gen_info.pl inherit.info 8 40 inherit
run_pair inherit inherit.info
if ! grep -x 'TN:tinherit' inherit_split.info >/dev/null ; then
    fail inherit "testname was not inherited by the chunks"
fi

#-----------------------------------------------------------------------
# 3. line numbers in diagnostics:  break a record in the LAST section, which
#    lands in a late chunk.  The reported line has to be the line in the file,
#    not the line in the chunk
#-----------------------------------------------------------------------
BAD_LINE=`grep -n '^DA:' multi.info | tail -1 | cut -d: -f1`
BAD_SECTION=`grep -n '^SF:' multi.info | tail -1 | cut -d: -f1`
awk -v n=$BAD_LINE '{ print (NR == n ? "DA:oops" : $0) }' multi.info > bad.info
# ..listing each error only once:  twice means 'do not even mention it'
run_pair bad bad.info --ignore-errors corrupt,format
for f in bad_serial.log bad_split.log ; do
    if ! grep -E "\"bad.info\":$BAD_LINE: unexpected .info file record 'DA:oops'.* beginning at line $BAD_SECTION" $f >/dev/null ; then
        cat $f
        fail bad "$f does not report line $BAD_LINE of section at $BAD_SECTION"
    fi
done

#-----------------------------------------------------------------------
# 4. repeated 'SF:':  three testnames, each with a section for every source
#    file.  All the sections for one source file have to be read by the same
#    child, so there are as many chunks as there are source files - not as
#    many as there are sections
#-----------------------------------------------------------------------
perl ./gen_info.pl repeat.info 8 40 repeat
run_pair repeat repeat.info
count=`chunk_count repeat_split.log`
if [ "$count" != 8 ] ; then
    fail repeat "split into $count chunks, expected one per source file (8)"
fi
for t in t1 t2 t3 ; do
    if ! grep -x "TN:$t" repeat_split.info >/dev/null ; then
        fail repeat "testcase $t is missing from the merged result"
    fi
done

#-----------------------------------------------------------------------
# 5. skew:  one source file with most of the lines cannot be split, so there is
#    no point in asking for one chunk per worker.  A moderate skew is split
#    into fewer chunks than there are source files;  an extreme one is not
#    split at all
#-----------------------------------------------------------------------
perl ./gen_info.pl skew.info 31 10 plain 15
run_pair skew skew.info
count=`chunk_count skew_split.log`
if [ "$count" == 0 ] || [ "$count" -ge 31 ] ; then
    fail skew "split into $count chunks, expected fewer than one per file (31)"
fi
perl ./gen_info.pl dominant.info 4 10 plain 200
run_pair dominant dominant.info
count=`chunk_count dominant_split.log`
if [ "$count" != 0 ] ; then
    fail dominant "split into $count chunks; one file has all the lines"
fi

#-----------------------------------------------------------------------
# 6. thresholds:  a small file is not split (the default
#    'parallel_parse_min_lines'), LCOV_FORCE_PARALLEL says to split it anyway,
#    and '--parallel 1' never splits
#-----------------------------------------------------------------------
# 'LCOV_FORCE_PARALLEL' has to be out of the environment for this one:  it is
#   exactly the override the next case exercises, and 'make check' sets it for
#   the whole suite in one of its two passes - so inheriting it here would turn
#   this assertion false by design.
env -u LCOV_FORCE_PARALLEL $COVER $LCOV_TOOL -a multi.info -o small.info \
    --parallel 4 > small.log 2>&1
if [ 0 != $? ] ; then
    cat small.log
    fail threshold "read of small file failed"
fi
if [ 0 != `chunk_count small.log` ] ; then
    fail threshold "small file was split"
fi
if ! diff identity_xs_serial.info small.info ; then
    fail threshold "unsplit read produced different data"
fi
LCOV_FORCE_PARALLEL=1 $COVER $LCOV_TOOL -a multi.info -o forced.info \
    --parallel 4 --rc dedicate_segment_line_estimate=10 > forced.log 2>&1
if [ 0 != $? ] ; then
    cat forced.log
    fail forced "forced parallel read failed"
fi
if [ 0 == `chunk_count forced.log` ] ; then
    fail forced "LCOV_FORCE_PARALLEL did not split the file"
fi
if ! diff identity_xs_serial.info forced.info ; then
    fail forced "forced split read produced different data"
fi
$COVER $LCOV_TOOL -a multi.info -o serial1.info --parallel 1 \
    --rc parallel_parse_min_lines=1 --rc dedicate_segment_line_estimate=10 \
    > serial1.log 2>&1
if [ 0 != `chunk_count serial1.log` ] ; then
    fail serial1 "file was split despite '--parallel 1'"
fi

#-----------------------------------------------------------------------
# 7. unseekable input:  a compressed file has to fall back to the serial read
#-----------------------------------------------------------------------
gzip -c multi.info > multi.info.gz
$COVER $LCOV_TOOL -a multi.info.gz -o gz.info --parallel 4 \
    --rc parallel_parse_min_lines=1 --rc dedicate_segment_line_estimate=10 \
    > gz.log 2>&1
if [ 0 != $? ] ; then
    cat gz.log
    fail gzip "read of compressed file failed"
fi
if [ 0 != `chunk_count gz.log` ] ; then
    fail gzip "compressed file was split"
fi
if ! diff identity_xs_serial.info gz.info ; then
    fail gzip "compressed read produced different data"
fi

#-----------------------------------------------------------------------
# 8. filter fusion:  the read children filter their own data, so the filters
#    run once - the counts are not doubled and the parent does not filter again
#-----------------------------------------------------------------------
FILTERS="--filter line,function,branch,trivial,brace,blank \
         --ignore-errors usage,usage"
run_pair filter multi.info $FILTERS --profile filter.json
count=`grep -c 'Apply filtering' filter_split.log`
if [ "$count" != 1 ] ; then
    fail filter "'Apply filtering' appears $count times, expected once"
fi
for f in blank brace ; do
    if ! grep -A1 "^  $f:" filter_split.log | grep -E '[0-9]+ instance' \
        >/dev/null ; then
        cat filter_split.log
        fail filter "the '$f' filter did not fire"
    fi
done
if [ ! -f filter.json ] ; then
    fail filter "no profile was written"
elif ! grep -E '"chunks"' filter.json >/dev/null ; then
    cat filter.json
    fail filter "the profile does not report the chunk count"
else
    # ..and the profile of that read says what the filters cost where they ran:
    #   in each chunk, as a part of what the chunk cost.  These filters really do
    #   fire - see the loop above - so the number has to be a positive one, and
    #   not the near-zero an unfiltered run would report.
    # 'filter.json' is the split read: 'run_pair' reads serially first and both
    #   runs are given the same '--profile' name, so the split read overwrote it.
    problem=`perl -e 'use JSON::PP;
             local $/;
             open(P, "<", $ARGV[0]) or die("cannot read $ARGV[0]: $!\n");
             my $p = JSON::PP->new->decode(<P>);
             my $n = 0;
             foreach my $job (sort(grep(/^\d+$/, keys(%$p)))) {
                 next unless ("HASH" eq ref($p->{$job}));
                 ++$n;
                 my $t = $p->{$job}->{filter};
                 print("chunk $job filter time is " .
                       (defined($t) ? $t : "missing") . "\n")
                     unless (defined($t) && $t > 0);
             }
             print("no chunk data at all\n") unless $n;' filter.json`
    if [ -n "$problem" ] ; then
        fail filter "profile of the filtered split read: $problem"
    fi
fi

#-----------------------------------------------------------------------
# 9. truncated final section:  the same format error as a serial read, with
#    the same line numbers
#-----------------------------------------------------------------------
head -n -1 multi.info > trunc.info
run_pair trunc trunc.info --ignore-errors corrupt,format
for f in trunc_serial.log trunc_split.log ; do
    if ! grep -E "unexpected end of file: missing 'end_of_record'" $f \
        >/dev/null ; then
        cat $f
        fail trunc "$f does not report the missing 'end_of_record'"
    fi
done

#-----------------------------------------------------------------------
# 10. the scanner:  a file larger than the scanner's read buffer (so that a
#     section straddles two buffers and a buffer ends in mid-line), an
#     'end_of_record' which is not at the start of a line - the reader ignores
#     it, so the scanner has to as well - and comments after the last section
#-----------------------------------------------------------------------
perl ./gen_info.pl big.info 40 8000
if [ 4194304 -ge `wc -c < big.info` ] ; then
    fail big "big.info is not larger than the scanner's read buffer"
fi
run_pair big big.info

awk '{ print ; if ($0 ~ /^FNH:/) print "# not an end_of_record here" }' \
    multi.info > oddities.info
echo '# trailing comment' >> oddities.info
echo '' >> oddities.info
run_pair oddities oddities.info
if [ 0 == `chunk_count oddities_split.log` ] ; then
    fail oddities "file was not split"
fi

#-----------------------------------------------------------------------
# 11. memory constraint:  a chunk costs memory too, so '--memory' throttles the
#     read the same way it throttles any other parallel phase
#-----------------------------------------------------------------------
$COVER $LCOV_TOOL -a multi.info -o mem.info $SPLIT --memory 1 > mem.log 2>&1
if [ 0 != $? ] ; then
    cat mem.log
    fail memory "read with '--memory 1' failed"
fi
if ! grep 'Throttling to ' mem.log >/dev/null ; then
    cat mem.log
    fail memory "'--memory 1' did not throttle the read"
fi
if ! diff identity_xs_serial.info mem.info ; then
    fail memory "throttled read produced different data"
fi

#-----------------------------------------------------------------------
# 12. a chunk which cannot be read at all:  the child's message is the serial
#     message, and the parent says which chunk died
#-----------------------------------------------------------------------
$COVER $LCOV_TOOL -a bad.info -o fatal.info $SERIAL > fatal_serial.log 2>&1
serialStatus=$?
$COVER $LCOV_TOOL -a bad.info -o fatal.info $SPLIT > fatal_split.log 2>&1
splitStatus=$?
if [ 0 == $serialStatus ] || [ $serialStatus != $splitStatus ] ; then
    fail fatal "exit status $splitStatus, expected the serial status" \
        "$serialStatus (and not 0)"
fi
if ! grep -E "\(corrupt\) unable to read trace file 'bad.info'" \
    fatal_split.log >/dev/null ; then
    cat fatal_split.log
    fail fatal "the split read does not report the unreadable file"
fi
if ! grep -E "\(child\) aggregate: 'while reading chunk [0-9]+'" \
    fatal_split.log >/dev/null ; then
    cat fatal_split.log
    fail fatal "the split read does not say which chunk died"
fi
# ..and not the "possibly killed by OS due to out-of-memory" guess:  the child
#   exited, it was not signalled
if grep 'killed by OS' fatal_split.log >/dev/null ; then
    cat fatal_split.log
    fail fatal "an ordinary child exit was reported as a signal"
fi

#-----------------------------------------------------------------------
# 13. '--map-functions' builds its own table rather than a tracefile, so the
#     chunks are merged into that table instead.  The order of the table is not
#     defined (it is a hash), so compare it sorted
#-----------------------------------------------------------------------
$COVER $LCOV_TOOL -a multi.info -o map_serial.txt $SERIAL --map-functions \
    > map_serial.log 2>&1
if [ 0 != $? ] ; then
    cat map_serial.log
    fail map "serial '--map-functions' failed"
fi
$COVER $LCOV_TOOL -a multi.info -o map_split.txt $SPLIT --map-functions \
    > map_split.log 2>&1
if [ 0 != $? ] ; then
    cat map_split.log
    fail map "split '--map-functions' failed"
fi
if [ 0 == `chunk_count map_split.log` ] ; then
    fail map "file was not split"
fi
if ! diff <(sort map_serial.txt) <(sort map_split.txt) ; then
    fail map "split '--map-functions' produced a different table"
fi

#-----------------------------------------------------------------------
# 14. scattered sections:  one source file appears several times, under
#     different testnames and more than once under the same testname, at
#     irregular places in the file.  All of it still has to go to one child -
#     both so that the counts are summed once and so that the fused filters see
#     the whole file - so the chunk's byte ranges are not contiguous
#-----------------------------------------------------------------------
perl ./gen_info.pl scatter.info 8 40 scatter
run_pair scatter scatter.info
count=`chunk_count scatter_split.log`
if [ "$count" != 8 ] ; then
    fail scatter "split into $count chunks, expected one per source file (8)"
fi
for t in t1 t2 t3 ; do
    if ! grep -x "TN:$t" scatter_split.info >/dev/null ; then
        fail scatter "testcase $t is missing from the merged result"
    fi
done
# ..and again with the filters, which run in the child:  a chunk holds several
#   testcases of the same file, so the child sees the whole file
run_pair scatter_filter scatter.info $FILTERS
count=`grep -c 'Apply filtering' scatter_filter_split.log`
if [ "$count" != 1 ] ; then
    fail scatter_filter "'Apply filtering' appears $count times, expected once"
fi

#-----------------------------------------------------------------------
# 15. profile data:  every phase is reported where it happened.  A serial read
#     reads whole input files, so what reading and merging each of them cost is
#     reported against that file, and the filter step which follows is one
#     whole-job number.  A split read reports all three against the chunk which
#     did them - a chunk is a part of an input, and the chunks holding the rest
#     of it read at the same time, so there is nothing per input file to say -
#     plus the pre-scan, which is per input file either way.
#     And the spreadsheet made from that data, which used to show neither the
#     chunks the read was split into nor - for any run which was divided up at
#     all - the per-input table the read times live in.
#-----------------------------------------------------------------------
$COVER $LCOV_TOOL -a big.info -o prof.info $SERIAL --profile prof_serial.json \
    > prof_serial.log 2>&1
if [ 0 != $? ] ; then
    cat prof_serial.log
    fail profile "serial read with '--profile' failed"
fi
$COVER $LCOV_TOOL -a big.info -o prof.info $SPLIT --profile prof_split.json \
    > prof_split.log 2>&1
if [ 0 != $? ] ; then
    cat prof_split.log
    fail profile "split read with '--profile' failed"
fi
check_profile()
{
    # $1 = profile, $2 = 1 if the file was split.  Print what is wrong, if
    #   anything:  the caller turns any output into a failure
    perl -e 'use JSON::PP;
             my ($f, $split) = @ARGV;
             local $/;
             open(P, "<", $f) or die("cannot read $f: $!\n");
             my $p = JSON::PP->new->decode(<P>);
             print("no total in $f\n") unless exists($p->{total});
             # ..only the split read pre-scans for the record boundaries it
             #   divides the inputs at
             print("scan " . ($split ? "missing from" : "found in") . " $f\n")
                 if ($split xor exists($p->{scan}));
             # ..and only a read of whole input files has anything to say about
             #   what reading and merging one of them cost:  a split read
             #   reports both against the chunk which did them, below
             foreach my $key (qw(parse append)) {
                 print("per-input $key " .
                       ($split ? "found in" : "missing from") . " $f\n")
                     if ($split xor !exists($p->{$key}));
             }
             # Filtering:  a split read has no separate filter step - each chunk
             #   child filters what it read, as it reads it - so what it cost is
             #   reported with the rest of what that chunk cost, and is a part of
             #   it.  An unsplit read filters once, afterwards, over everything
             #   it read, and so reports one number for the whole job.
             if ($split) {
                 print("whole-job filter time in $f\n") if exists($p->{filter});
                 my $nJobs = 0;
                 foreach my $job (sort(grep(/^\d+$/, keys(%$p)))) {
                     my $d = $p->{$job};
                     next unless ("HASH" eq ref($d) && exists($d->{total}));
                     ++$nJobs;
                     # Reading its piece, merging what it read into its own
                     #   total and filtering the result all happened inside this
                     #   chunk, so all three are reported here - and none of
                     #   them can have cost more than the chunk itself did.
                     foreach my $key (qw(parse append filter)) {
                         unless (exists($d->{$key})) {
                             print("no $key time for chunk $job in $f\n");
                             next;
                         }
                         print("chunk $job $key $d->{$key} exceeds its total " .
                               "$d->{total} in $f\n")
                             if ($d->{$key} > $d->{total});
                     }
                 }
                 print("no chunk data in $f\n") unless $nJobs;
             } elsif (!exists($p->{filter})) {
                 print("no whole-job filter time in $f\n");
             } else {
                 print("filter $p->{filter} exceeds total $p->{total} in $f\n")
                     if ($p->{filter} > $p->{total});
             }
             exit(0) if $split;
             # one input, read as a whole:  one per-input read time, and it
             #   cannot exceed what the whole run took
             my $parse = $p->{parse};
             print("no parse time in $f\n"), exit(0)
                 unless ($parse && 1 == scalar(keys(%$parse)));
             my ($t) = values(%$parse);
             print("parse $t exceeds total $p->{total} in $f\n")
                 if ($t > $p->{total});' $1 $2
}
problem=`check_profile prof_serial.json 0`
if [ -n "$problem" ] ; then
    fail profile "serial profile: $problem"
fi
problem=`check_profile prof_split.json 1`
if [ -n "$problem" ] ; then
    fail profile "split profile: $problem"
fi

# ...and the spreadsheet made from those profiles.  The lcov sheet used to show
#   neither the chunks a split read was divided into - it looked only for the
#   'segments' a divided-by-input run has - nor, for any run which was divided
#   up at all, the per-input table the read times themselves live in.  Every
#   sub-table has one shape, so the check is the scheduling test's generic
#   layout checker;  it needs xlsxwriter (spreadsheet.py) but nothing to read
#   the result back.
if ! python3 -c "import xlsxwriter" >/dev/null 2>&1 ; then
    echo "skipping spreadsheet check:  no xlsxwriter module"
else
    LAYOUT=../scheduling/check_table_layout.py
    INDEX=../scheduling/check_table_index.py
    COLUMN=../scheduling/check_table_column.py
    SCALAR=../scheduling/check_scalar_row.py
    echo $SPREADSHEET_TOOL -o prof.xlsx prof_split.json prof_serial.json
    eval ${PYCOVER} $SPREADSHEET_TOOL -o prof.xlsx prof_split.json \
        prof_serial.json 2>&1 | tee prof_spreadsheet.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -f prof.xlsx ] ; then
        fail profile "spreadsheet generation from the read profiles failed"
    else
        # the split read:  one row per chunk, then the input file and source
        # file tables
        python3 $LAYOUT prof.xlsx prof_split.json chunks info source
        if [ 0 != $? ] ; then
            fail profile "split read spreadsheet layout"
        fi
        # ...and the serial read has those same two tables, and no chunks
        python3 $LAYOUT prof.xlsx prof_serial.json info source
        if [ 0 != $? ] ; then
            fail profile "serial read spreadsheet layout"
        fi
        # Where the filtering is reported follows where it happened.  The split
        # read filtered in its chunk children, so every chunk row says what that
        # cost - and the per-input table says nothing about it, because a source
        # file is filtered once no matter how many inputs mention it.
        python3 $COLUMN prof.xlsx prof_split.json chunks filter
        if [ 0 != $? ] ; then
            fail profile "split read filter time is not reported per chunk"
        fi
        python3 $COLUMN prof.xlsx prof_split.json info -filter
        if [ 0 != $? ] ; then
            fail profile "split read reports filter time per input file"
        fi
        # The read itself follows the same rule.  The chunk children read and
        # merged their own piece, so every chunk row says what each of those
        # cost - and the per-input table is left with the pre-scan alone, since
        # several chunks read the same input at the same time and what one of
        # them spent on it is not what reading that input cost.
        python3 $COLUMN prof.xlsx prof_split.json chunks parse append
        if [ 0 != $? ] ; then
            fail profile "split read time is not reported per chunk"
        fi
        python3 $COLUMN prof.xlsx prof_split.json info scan -parse -append
        if [ 0 != $? ] ; then
            fail profile "split read reports read time per input file"
        fi
        # ...while the serial read read whole input files, so there it is the
        # per-input table which says what reading and merging each of them cost
        python3 $COLUMN prof.xlsx prof_serial.json info parse append
        if [ 0 != $? ] ; then
            fail profile "serial read time is not reported per input file"
        fi
        # ...while the serial read filtered once, after reading and merging
        # everything:  one number for the whole job, on a row of its own
        python3 $SCALAR prof.xlsx prof_serial.json filter
        if [ 0 != $? ] ; then
            fail profile "serial read whole-job filter time"
        fi
        # These are the sheets in the suite long enough to need an index of
        # their tables:  a reader looking for the source file table should not
        # have to scroll past 16 chunks - or 40 source files - to find out it is
        # there.  The checker re-derives whether the sheet needs one, so it fails
        # both if the index is missing and if it is there when it should not be.
        for f in prof_split.json prof_serial.json ; do
            python3 $INDEX prof.xlsx $f index
            if [ 0 != $? ] ; then
                fail profile "$f spreadsheet table index"
            fi
        done
        # a well-formed profile must produce no warning at all - the keys the
        # lcov sheet did not know about used to be reported as unwritable
        if grep -E 'unable to write|not sure what to do with' \
                prof_spreadsheet.log ; then
            fail profile "spreadsheet warning from a well-formed profile"
        fi
    fi
fi

#-----------------------------------------------------------------------
# 16. several inputs:  the work is divided over the whole set rather than one
#     input at a time, so a chunk can hold sections from more than one input -
#     and the sections naming one source file still all go to one child, even
#     when they are in different inputs
#-----------------------------------------------------------------------
# (a) the same 8 source files in two inputs, under different testnames and in
#     opposite orders:  a group spans both inputs, so every chunk reads both
perl ./gen_info.pl cross_a.info 8 40
awk '/^TN:/ { ++n } { s[n] = s[n] $0 "\n" }
     END { for (i = n; i >= 1; --i) printf("%s", s[i]) }' \
    cross_a.info | sed 's/^TN:tmain$/TN:tsecond/' > cross_b.info
if [ `grep -c '^SF:' cross_b.info` != 8 ] ; then
    fail cross "cross_b.info does not have the 8 sections of cross_a.info"
fi
run_multi cross "cross_a.info cross_b.info"
count=`chunk_count cross_split.log`
if [ "$count" != 8 ] ; then
    fail cross "split into $count chunks, expected one per source file (8)"
fi
for t in tmain tsecond ; do
    if ! grep -x "TN:$t" cross_split.info >/dev/null ; then
        fail cross "testcase $t is missing from the merged result"
    fi
done
# ..and the chunks say so:  '--verbose' lists what each of them reads
$COVER $LCOV_TOOL -a cross_a.info -a cross_b.info -o cross_v.info $SPLIT \
    --verbose > cross_v.log 2>&1
if [ 0 != $? ] ; then
    cat cross_v.log
    fail cross "verbose split read of two inputs failed"
fi
count=`grep -c -E '^Chunk [0-9]+: cross_a.info \(1 runs\), cross_b.info \(1 runs\)$' \
    cross_v.log`
if [ "$count" != 8 ] ; then
    cat cross_v.log
    fail cross "$count of 8 chunks read both inputs"
fi
# ..and with the filters, which the children run:  a chunk holds all of a source
#   file's data across the inputs, which is what makes that legal
run_multi cross_filter "cross_a.info cross_b.info" $FILTERS
count=`grep -c 'Apply filtering' cross_filter_split.log`
if [ "$count" != 1 ] ; then
    fail cross_filter "'Apply filtering' appears $count times, expected once"
fi

# (b) one large input and many small ones:  there are more source files than
#     chunks, so the small inputs' files have to share a chunk with each other
#     and with the large input's.  One chunk per worker rather than the usual
#     four, so that there are fewer chunks than groups whatever the machine is
PACKED="--rc parallel_parse_chunks_per_worker=1"
perl ./gen_info.pl pack_big.info 4 2000
SMALL=
for i in 1 2 3 4 5 6 ; do
    perl ./gen_info.pl pack_s$i.info 2 20
    SMALL="$SMALL pack_s$i.info"
done
run_multi pack "pack_big.info $SMALL" $PACKED
$COVER $LCOV_TOOL -a pack_big.info `for f in $SMALL ; do echo -a $f ; done` \
    -o pack_v.info $SPLIT $PACKED --verbose > pack_v.log 2>&1
if [ 0 != $? ] ; then
    cat pack_v.log
    fail pack "verbose split read of many inputs failed"
fi
if ! grep -E '^Chunk [0-9]+:.*runs\).*,.*runs\)' pack_v.log >/dev/null ; then
    cat pack_v.log
    fail pack "no chunk holds sections from more than one input"
fi

# (c) an input which cannot be split costs the whole set its split:  a source
#     file in the compressed input could belong to any group, so the guarantee
#     that one child sees all of a file cannot be kept
run_multi mixed "cross_a.info multi.info.gz"
if [ 0 != `chunk_count mixed_split.log` ] ; then
    fail mixed "the set was split although one input is compressed"
fi

# (d) a bad record in the second input:  the message has to name that input and
#     the line the record is really on
BAD_LINE=`grep -n '^DA:' cross_b.info | tail -1 | cut -d: -f1`
BAD_SECTION=`grep -n '^SF:' cross_b.info | tail -1 | cut -d: -f1`
awk -v n=$BAD_LINE '{ print (NR == n ? "DA:oops" : $0) }' cross_b.info \
    > cross_bad.info
run_multi cross_bad "cross_a.info cross_bad.info" --ignore-errors corrupt,format
for f in cross_bad_serial.log cross_bad_split.log ; do
    if ! grep -E "\"cross_bad.info\":$BAD_LINE: unexpected .info file record 'DA:oops'.* beginning at line $BAD_SECTION" $f >/dev/null ; then
        cat $f
        fail cross_bad \
            "$f does not report line $BAD_LINE of cross_bad.info"
    fi
done

# (e) '--prune-tests' asks which inputs contributed coverage no other input had.
#     A child answers for its own chunk, having seen every input's data for the
#     files in it - so a duplicated input is recognized as redundant, which the
#     one-child-per-input read cannot do when the copies land in different
#     children
cp cross_a.info cross_dup.info
PRUNE="-a cross_a.info -a cross_dup.info -a cross_b.info"
$COVER $LCOV_TOOL $PRUNE -o prune_serial.txt $SERIAL --prune-tests \
    > prune_serial.log 2>&1
if [ 0 != $? ] ; then
    cat prune_serial.log
    fail prune "serial '--prune-tests' failed"
fi
$COVER $LCOV_TOOL $PRUNE -o prune_split.txt $SPLIT --prune-tests \
    > prune_split.log 2>&1
if [ 0 != $? ] ; then
    cat prune_split.log
    fail prune "split '--prune-tests' failed"
fi
if [ 0 == `chunk_count prune_split.log` ] ; then
    fail prune "the set was not split"
fi
if ! diff prune_serial.txt prune_split.txt ; then
    fail prune "split '--prune-tests' retained a different set of inputs"
fi
if grep -x 'cross_dup.info' prune_split.txt >/dev/null ; then
    cat prune_split.txt
    fail prune "the duplicated input was reported as effective"
fi

# (f) nothing survives:  exclude every source file, so no chunk returns any
#     data.  A child cannot tell "my chunk is empty" from "the input is empty",
#     so the parent makes the check once, for the whole set - and then has to
#     name every input, as the serial read does, rather than just the first
run_multi excl "cross_a.info cross_b.info" --exclude '*' --ignore-errors empty
if [ 0 == `chunk_count excl_split.log` ] ; then
    fail excl "the set was not split"
fi
for f in cross_a.info cross_b.info ; do
    if ! grep -E "\(empty\) no valid records found in tracefile $f" \
        excl_split.log >/dev/null ; then
        cat excl_split.log
        fail excl "the split read does not report $f as empty"
    fi
done

if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    # '1':  case 15 runs spreadsheet.py, so there is python coverage too
    generate_coverage 'parallel_parse' $LOCAL_COVERAGE 1
fi

exit $STATUS
