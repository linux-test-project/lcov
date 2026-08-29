#!/bin/bash
set +x

# ============================================================================
# genhtml coverage criteria which are evaluated inside a forked worker.
#
# A file's criteria are checked where that file is processed - and that is a
# forked segment worker as soon as there is more than one thing to schedule -
# so the result has to travel back to the parent in the child's payload
# (genhtml 'SegmentTask::_process_child' -> 'SegmentTask::merge_child').
# Nothing else in the suite went through that path:  the criteria tests in
# genhtml/simple report a single source file, which the scheduler always
# computes in-process, and the shipped 'scripts/criteria.pm' answers only for
# the top level, which is likewise always computed by the parent, after the
# last worker has been merged.
#
# Covers:
#   1. a file-level criteria failure raised in a worker is reported by the
#      parent, on stdout and stderr, and sets genhtml's exit status
#   2. a file whose check passes but has something to say is reported too -
#      and does NOT clear the failure of a file which was merged before it
#   3. the criteria of a parallel run are identical to those of a serial one
#   4. the shipped 'scripts/threshold.pm' checks the MC/DC coverage it was
#      asked to check.  The name of the option is '--mcdc', but the key
#      genhtml puts in the JSON is 'MC/DC' ('type2str'), and 'check_criteria'
#      skips any threshold whose key the JSON does not have - so a threshold
#      filed under the wrong name is not a check which fails to fire, it is
#      no check at all:  the run passes with exit status 0 whatever the MC/DC
#      coverage is
#   5. criteria over age bins ('criteria_callback_data=date').  The bins hold
#      only the TLAs an age bin can have - 'lineCovCount' dies on any other -
#      which is fewer than '@tlaPriorityOrder' lists, so the bin has to be
#      asked whether it has a key before it is read.  What that costs is not
#      a wrong answer but a pile of 'uninitialized value' warnings, which do
#      not even reach the message summary
#   6. criteria over owner bins ('criteria_callback_data=owner').  The same
#      loop, over a different set of bins:  every owner is listed even when
#      every count in that owner's bin is zero, which is what distinguishes
#      this arm from the age one
# ============================================================================

source ../../common.tst

rm -rf proj *.info *.log *.err *.json rpt_* filecriteria.pm criteria_*.txt \
    dumpcrit.pm annstub.pm criteria_dump.txt

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

STATUS=0

fail()
{
    # $1 = scenario label, $2 = what went wrong
    echo "ERROR ($1): $2"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

# --------------------------------------------------------------------------
# the report:  two files in one directory, so there are two file tasks to
# schedule - one of them fully covered, the other not.  The sources exist only
# so that genhtml can read them;  the coverage data is written by hand because
# what this test needs is the file count and the hit/found split, not a
# compiler.
# --------------------------------------------------------------------------
mkdir -p proj
for f in covered uncovered ; do
    cat > proj/$f.c <<EOF
int $f(int i)
{
    int total = 0;
    while (i > 0) {
        total += i;
        i -= 1;
    }
    return total;
}
/* $f */
EOF
done

SRC=`pwd`/proj
{
    echo 'TN:'
    echo "SF:$SRC/covered.c"
    for line in 1 2 3 4 5 6 7 8 9 10 ; do
        echo "DA:$line,1"
    done
    echo 'LF:10'
    echo 'LH:10'
    echo 'end_of_record'
    echo 'TN:'
    echo "SF:$SRC/uncovered.c"
    for line in 1 2 3 4 5 6 7 ; do
        echo "DA:$line,1"
    done
    for line in 8 9 10 ; do
        echo "DA:$line,0"
    done
    echo 'LF:10'
    echo 'LH:7'
    echo 'end_of_record'
} > cov.info

# --------------------------------------------------------------------------
# the callback:  a criteria module which answers at 'file' level, which is
# what puts criteria data inside a worker.  Its answers are chosen so that the
# only failure of the run comes from a file - and so that a passing file is
# merged after the failing one:  the parent merges its children in completion
# order, so the sleep in the passing answer pins that ordering, which is the
# case in which a pass used to clear the fail.
# --------------------------------------------------------------------------
cat > filecriteria.pm <<'EOF'
package filecriteria;

use strict;
use Time::HiRes;

sub new
{
    # the only argument is this module's path - there is nothing to configure
    my $class = shift;
    return bless [], $class;
}

sub check_criteria
{
    my ($self, $name, $type, $data) = @_;

    # say nothing at the top level:  then the exit status of the run can only
    #   be the one a file raised
    return (0, []) unless $type eq 'file';

    my $line  = exists($data->{line}) ? $data->{line} : {};
    my $found = exists($line->{found}) ? $line->{found} : 0;
    my $hit   = exists($line->{hit}) ? $line->{hit} : 0;
    return (1, [($found - $hit) . " uncovered line(s)"])
        if $found != $hit;

    # a pass which has something to say - and which finishes last, see above
    Time::HiRes::sleep(0.5);
    return (0, ['fully covered']);
}

1;
EOF

CRITERIA_OPTS="--criteria `pwd`/filecriteria.pm --rc criteria_callback_levels=top,file"

# the criteria section of a genhtml log:  the header and the indented entries
criteria_section()
{
    grep -E '^(Failed )?[Cc]overage criteria:$|^  (top|file|directory)' $1
}

# --------------------------------------------------------------------------
# 1. + 2. the parallel run:  each file is a job of its own, so both criteria
#    are computed in a child and merged by the parent.
# --------------------------------------------------------------------------
echo genhtml cov.info -o rpt_parallel --parallel 2 $CRITERIA_OPTS
$COVER $GENHTML_TOOL cov.info -o rpt_parallel --parallel 2 $CRITERIA_OPTS \
    --profile parallel.json > parallel.log 2> parallel.err
if [ 0 == $? ] ; then
    cat parallel.log
    fail parallel "genhtml did not fail the criteria raised by a worker"
fi

# the run has to have forked, or it proves nothing:  one task per job, and one
# child per job - the two file tasks.  The directory and top-level tasks are
# computed in the parent (nothing else is left to run by then), so they have
# no 'child' or 'nJobs' entry.
python3 -c "
import json, sys
d = json.load(open('parallel.json'))
child = d.get('child', {})
jobs = d.get('nJobs', {})
if sorted(jobs.values()) != [1, 1]:
    print('FAIL: expected two single-task jobs, found %s' % (jobs))
    sys.exit(1)
if sorted(child.keys()) != sorted(jobs.keys()):
    print('FAIL: forked jobs %s do not match children %s' %
          (sorted(jobs), sorted(child)))
    sys.exit(1)
print('OK: %d file task(s) computed in a child' % (len(child)))
"
if [ 0 != $? ] ; then
    fail parallel "the file tasks were not computed in a forked worker"
fi

if ! grep -q '^Failed coverage criteria:$' parallel.log ; then
    cat parallel.log
    fail parallel "criteria failure of a worker not reported"
fi
# the failing file, on stdout and (because it is a failure) on stderr
for log in parallel.log parallel.err ; do
    if ! grep -F -q "file \"$SRC/uncovered.c\": \"3 uncovered line(s)\"" $log ; then
        cat $log
        fail parallel "uncovered.c criteria missing from $log"
    fi
done
# ..and the passing file, which is reported on stdout only
if ! grep -F -q "  file \"$SRC/covered.c\": \"fully covered\"" parallel.log ; then
    cat parallel.log
    fail parallel "covered.c criteria missing from parallel.log"
fi
if grep -F -q "\"$SRC/covered.c\"" parallel.err ; then
    cat parallel.err
    fail parallel "a passing criteria was reported on stderr"
fi

# --------------------------------------------------------------------------
# 3. the same report, computed entirely in the parent:  criteria which came
#    back from a child must match the ones the parent computed itself.
# --------------------------------------------------------------------------
echo genhtml cov.info -o rpt_serial --parallel 1 $CRITERIA_OPTS
$COVER $GENHTML_TOOL cov.info -o rpt_serial --parallel 1 $CRITERIA_OPTS \
    --profile serial.json > serial.log 2> serial.err
if [ 0 == $? ] ; then
    cat serial.log
    fail serial "genhtml did not fail the criteria"
fi
python3 -c "
import json, sys
d = json.load(open('serial.json'))
if 'child' in d:
    print('FAIL: the serial run forked: %s' % (d['child']))
    sys.exit(1)
print('OK: serial run computed every task in the parent')
"
if [ 0 != $? ] ; then
    fail serial "the --parallel 1 run was not serial"
fi

criteria_section parallel.log > criteria_parallel.txt
criteria_section serial.log > criteria_serial.txt
if [ ! -s criteria_serial.txt ] ; then
    cat serial.log
    fail serial "no criteria reported at all"
fi
diff criteria_serial.txt criteria_parallel.txt
if [ 0 != $? ] ; then
    fail compare "parallel and serial criteria differ"
fi

# --------------------------------------------------------------------------
# the fixture for 4. and 5.:  a file with MC/DC data as well as line data.
# The expression on line 3 is fully sensitized and the one on line 5 is not,
# which is 6 of 8 coverpoints - so a '--mcdc 100' threshold has to fail and a
# '--mcdc 75' one has to pass.  Written by hand:  what matters is the hit and
# found split, not which compiler produced it
# --------------------------------------------------------------------------
cat > proj/mcdc.c <<'EOF'
int mcdc(int a, int b)
{
    if (a > 0 && b > 0)
        return 1;
    if (a < 0 || b < 0)
        return -1;
    return 0;
}
EOF

{
    echo 'TN:'
    echo "SF:$SRC/mcdc.c"
    for line in 1 3 4 5 6 7 ; do
        echo "DA:$line,1"
    done
    echo 'LF:6'
    echo 'LH:6'
    echo 'MCDC:3,2,t,1,0,0'
    echo 'MCDC:3,2,f,1,0,0'
    echo 'MCDC:3,2,t,1,1,1'
    echo 'MCDC:3,2,f,1,1,1'
    echo 'MCDC:5,2,t,1,0,0'
    echo 'MCDC:5,2,f,0,0,0'
    echo 'MCDC:5,2,t,1,1,1'
    echo 'MCDC:5,2,f,0,1,1'
    echo 'end_of_record'
} > mcdc.info

# --------------------------------------------------------------------------
# 4. threshold.pm, on the MC/DC coverage it was given a threshold for
# --------------------------------------------------------------------------
echo genhtml mcdc.info -o rpt_mcdc_fail --criteria-script threshold.pm,--mcdc,100
$COVER $GENHTML_TOOL mcdc.info -o rpt_mcdc_fail --mcdc-coverage \
    --criteria-script ${SCRIPT_DIR}/threshold.pm,--mcdc,100 \
    > mcdc_fail.log 2>&1
if [ 0 == $? ] ; then
    cat mcdc_fail.log
    fail mcdc "an unmet MC/DC threshold did not fail the run"
fi
# the number is the MC/DC coverage of the fixture and not, say, its line
# coverage - which is 100% and would pass any threshold
if ! grep -F -q 'MC/DC: 75.00 < 100.00' mcdc_fail.log ; then
    cat mcdc_fail.log
    fail mcdc "the MC/DC threshold was not the criteria which failed"
fi

# ..and the same threshold met:  quiet, and exit status 0.  This is the run
#   which tells a threshold that fires from one that is simply never checked
echo genhtml mcdc.info -o rpt_mcdc_pass --criteria-script threshold.pm,--mcdc,75
$COVER $GENHTML_TOOL mcdc.info -o rpt_mcdc_pass --mcdc-coverage \
    --criteria-script ${SCRIPT_DIR}/threshold.pm,--mcdc,75 \
    > mcdc_pass.log 2>&1
if [ 0 != $? ] ; then
    cat mcdc_pass.log
    fail mcdc "a met MC/DC threshold failed the run"
fi
if grep -q 'MC/DC:' mcdc_pass.log ; then
    cat mcdc_pass.log
    fail mcdc "a met MC/DC threshold was reported as a failure"
fi

# --------------------------------------------------------------------------
# 5. criteria over age bins.
# The annotation is a stub rather than a repo:  '--date-bins' needs dates and
# nothing here needs them to be real.  It alternates a recent date with an old
# one so that more than one bin is populated - a single bin would exercise the
# loop just as well, but two make the dump below worth reading
#
# The recent date is computed from the current time rather than written down.
# A literal is a date which gets older every day, so the bin it falls in is
# whatever the age of the checkout says:  '2026-08-31' was inside the '(1,7]
# days' bin for four days after it was written and has been in the '(7..)' bin
# ever since, alongside the old date - which leaves the bin this case asserts
# on empty and fails the test for no reason but the calendar.
# --------------------------------------------------------------------------
cat > annstub.pm <<'EOF'
package annstub;

use strict;
use POSIX qw(strftime);

sub new
{
    my $class = shift;
    return bless [], $class;
}

sub annotate
{
    my ($self, $file) = @_;
    my @lines;
    my $n = 0;
    # three days ago:  inside the '(1,7] days' bin for the cutpoints this case
    #   passes, and far enough from either edge that the run's own duration and
    #   the local timezone cannot move it out
    my $recentDate =
        strftime('%Y-%m-%dT%H:%M:%S-00:00', gmtime(time() - 3 * 24 * 60 * 60));
    open(my $fh, '<', $file) or return (1, []);
    while (my $line = <$fh>) {
        chomp($line);
        # one date inside the '(1,7]' bin, one older than the last cutpoint;
        #   two owners, so the owner bins below have more than one entry
        my $recent = (++$n % 2);
        my $when   = $recent ? $recentDate : '2020-01-01T00:00:00-00:00';
        my $who    = $recent ? 'me' : 'you';
        push(@lines, [$line, $who, "$who\@here", $when, "CL$n"]);
    }
    close($fh);
    return (0, \@lines);
}

1;
EOF

# a criteria module which writes down what it was handed:  the point of the
#   case is that the age bins reach the callback, so the callback has to say so
cat > dumpcrit.pm <<'EOF'
package dumpcrit;

use strict;

sub new
{
    my $class = shift;
    return bless [], $class;
}

sub check_criteria
{
    my ($self, $name, $type, $db) = @_;
    open(my $fh, '>>', 'criteria_dump.txt') or die("cannot append: $!");
    foreach my $key (sort keys %$db) {
        foreach my $bin (sort keys %{$db->{$key}}) {
            my $v = $db->{$key}->{$bin};
            print($fh "$type|$key|$bin|",
                  ref($v) ? join(',', map({ "$_=$v->{$_}" } sort keys %$v)) : $v,
                  "\n");
        }
    }
    close($fh);
    return (0, []);
}

1;
EOF

rm -f criteria_dump.txt
echo genhtml mcdc.info -o rpt_bins --rc criteria_callback_data=date --date-bins 1,7
$COVER $GENHTML_TOOL mcdc.info -o rpt_bins --mcdc-coverage \
    --criteria-script `pwd`/dumpcrit.pm \
    --rc criteria_callback_data=date --rc criteria_callback_levels=top \
    --date-bins 1,7 --annotate-script `pwd`/annstub.pm > bins.log 2>&1
if [ 0 != $? ] ; then
    cat bins.log
    fail bins "genhtml failed computing criteria over age bins"
fi
COUNT=`grep -c 'uninitialized value' bins.log`
if [ 0 != "$COUNT" ] ; then
    grep 'uninitialized value' bins.log
    fail bins "reading the age bins warned $COUNT time(s)"
fi
# ..and the run is not merely quiet:  the bins reached the callback.  The keys
#   are bin indices - one per cutpoint, plus one for everything older - so
#   both the 'line' and the 'MC/DC' entry have a bin '1' beside the ordinary
#   whole-file counts
if [ ! -f criteria_dump.txt ] ; then
    fail bins "the criteria callback was never called"
else
    for pattern in 'top|line|1|' 'top|line|2|' 'top|MC/DC|1|' ; do
        if ! grep -F -q -e "$pattern" criteria_dump.txt ; then
            cat criteria_dump.txt
            fail bins "no age bin was passed to the callback: $pattern"
        fi
    done
fi

# --------------------------------------------------------------------------
# 6. criteria over owner bins.  The annotation above hands out two owners.
# --------------------------------------------------------------------------
rm -f criteria_dump.txt
echo genhtml mcdc.info -o rpt_owners --rc criteria_callback_data=owner
$COVER $GENHTML_TOOL mcdc.info -o rpt_owners --mcdc-coverage \
    --criteria-script `pwd`/dumpcrit.pm \
    --rc criteria_callback_data=owner --rc criteria_callback_levels=top \
    --annotate-script `pwd`/annstub.pm > owners.log 2>&1
if [ 0 != $? ] ; then
    cat owners.log
    fail owners "genhtml failed computing criteria over owner bins"
fi
COUNT=`grep -c 'uninitialized value' owners.log`
if [ 0 != "$COUNT" ] ; then
    grep 'uninitialized value' owners.log
    fail owners "reading the owner bins warned $COUNT time(s)"
fi
if [ ! -f criteria_dump.txt ] ; then
    fail owners "the criteria callback was never called"
else
    # both owners are named, and each brought a TLA count with it.  An owner
    #   bin holds only TLAs - there is no 'found' or 'hit' in one, which is
    #   why the whole-file entries in the same dump are the only place those
    #   appear
    for who in me you ; do
        if ! grep -E -q "^top\|line\|$who\|[A-Z]+=[0-9]+$" criteria_dump.txt
        then
            cat criteria_dump.txt
            fail owners "owner '$who' reached the callback with no counts"
        fi
    done
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'criteria' $LOCAL_COVERAGE 0
fi

exit $STATUS
