#!/bin/bash
set +x

# ============================================================================
# The '--select-script' callback when it is an executable rather than a perl
#   module, and the '--version-script' '--compare' callback - the two callbacks
#   which went through 'ScriptCaller::call'.
#
# Two things were wrong with that.
#
# The answer channel:  every other script callback answers by writing to
#   stdout, and lcovrc(5) says that this one returns "1" or "0" - but the
#   implementation took the exit status as the answer.  So a script which did
#   what the documentation says ("echo 1 ; exit 0") said 'no' for every
#   coverpoint of every file:  the report came out empty, with a zero exit
#   status and no message.  And since the status was the answer, a script which
#   could not be executed, died, or failed said 'no' as well - or 'yes', which
#   is worse, because an exit status of 1 is what a shell script produces when
#   it falls over.  Nothing in the suite noticed:  the one script callback in it
#   - 'tests/genhtml/errs/select.sh' - was a stub which nothing asserted
#   anything about, and there was no sample script to compare against either.
#
# The arguments:  the command was built with join(' ') and handed to backticks,
#   so a shell re-parsed it.  For 'select' that destroyed the call:  the JSON
#   arguments lost their quotes, the empty annotation argument disappeared and
#   shifted the two arguments after it, and the line 'number' of a deleted line
#   - the key '<<<N' - was eaten as a here-string redirection, so the callback
#   was handed two arguments instead of four.  For 'compare_version' the three
#   arguments were single-quoted by hand, which works right up to the first
#   version ID or file name containing an apostrophe.
#
# So the script now answers on stdout, and the arguments are passed as a list.
#   A callback which cannot be believed - one which cannot be executed, exits
#   non-zero, is killed, or writes something other than '0' or '1' - is
#   reported as an ignorable 'callback' error, and the coverpoint is selected:
#   an unexpectedly large report is easier to notice than an empty one.
#
# The cases:
#   1. a doc-compliant script ("write 1, exit 0") selects everything
#   2. a script which writes '0' selects nothing
#   3. a script which decides from the coverpoint data selects that subset -
#      which needs the JSON quoting to have survived
#   4. the arguments:  four of them, every time, including for the deleted
#      line, with the JSON quoting and an annotation containing a space and an
#      apostrophe intact
#   5. a script which exits non-zero is reported, and the coverpoint is kept
#   6. so is one which answers something else
#   7. so is one which is killed by a signal
#   8. so is one which cannot be executed at all
#   9. a script which writes more than it was asked to is not thereby broken
#  10. 'compare_version' is handed three arguments, and a version ID with a
#      space and an apostrophe in it arrives as it was written
#  11. a 'compare_version' script which is killed reports a callback error -
#      not a version mismatch, which is what 'non-zero exit status' means here,
#      and what it wrote before it died is in the message
#  12. the module form of the select callback, dying:  reported once, by the
#      caller, since that failure is not one lcov reported itself
#  13. the same for the module form of 'compare_version' - and a comparison
#      which could not be made is not a match
#  14. and for 'extract_version', the third of the callers which catches a
#      callback's die and reports it
#  15. no "isn't numeric" warning:  a deleted line is keyed '<<<N', and
#      genhtml's interesting-region bookkeeping used to put that key into a
#      list it sorts numerically and compare it with '!=' - which numified it
#      to 0, so the region stack never advanced past it and every line from
#      there on was 'interesting'.  The key is now mapped to the line the
#      deleted line is displayed beside before any arithmetic is done with it
# ============================================================================

source ../../common.tst

# deliberately not $PARALLEL:  the callbacks below append the arguments they
#   were handed to a log, one line per argument, and forked report writers
#   would interleave those records
GENHTML_OPTS="--function-coverage $PROFILE"

rm -rf *.info *.log *.argv *.txt *.json *.udiff proj rpt_* \
    sel.pl ann.pl ver.pl seldie.pm verdie.pm verextdie.pm \
    perlcov.info pycov.info __pycache__ cover_db.dat html_report

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
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

HERE=`pwd`

# --------------------------------------------------------------------------
# the inputs:  the same one source file, baseline, current trace and udiff as
# tests/genhtml/scriptargs - which give the report one line of each of GNC,
# UBC and DCB and two of CBC.  The DCB line is the interesting one:  it is the
# line the udiff removed, so its key in the coverage data is '<<<4' rather
# than a number
# --------------------------------------------------------------------------
mkdir -p proj

cat >proj/foo.c <<'EOF'
int xfoo_bary(int a)
{
    if (a > 0)
        return a + 1;
    return -a;
}
EOF

cat >baseline.info <<'EOF'
TN:sa
SF:proj/foo.c
FN:1,6,xfoo_bary
FNDA:2,xfoo_bary
FNF:1
FNH:1
DA:1,2
DA:3,2
DA:4,2
DA:5,0
LF:4
LH:3
end_of_record
EOF

cat >current.info <<'EOF'
TN:sa
SF:proj/foo.c
FN:1,6,xfoo_bary
FNDA:3,xfoo_bary
FNF:1
FNH:1
DA:1,3
DA:3,3
DA:4,3
DA:5,0
LF:4
LH:3
end_of_record
EOF

cat >diff.udiff <<'EOF'
--- proj/foo.c
+++ proj/foo.c
@@ -1,6 +1,6 @@
 int xfoo_bary(int a)
 {
     if (a > 0)
-        return a;
+        return a + 1;
     return -a;
 }
EOF

# the version of the source in the data file.  It differs from what the
#   version script computes below, so the two have to be compared by calling
#   the script - which is the point.  Both contain a space and an apostrophe
cat >version.info <<'EOF'
TN:sa
SF:proj/foo.c
VER:rev 1 (o'brien)
DA:1,3
DA:3,3
DA:4,3
DA:5,0
LF:4
LH:3
end_of_record
EOF

DIFF_OPTS="--baseline-file baseline.info --diff-file diff.udiff"

# --------------------------------------------------------------------------
# the callbacks.  Each one records the arguments it was handed, one line per
# argument, so that the cases below can require the call to have arrived
# whole
# --------------------------------------------------------------------------

# the annotation is here for one reason:  it puts a string containing a space
#   and an apostrophe into the JSON which the select callback is handed.  The
#   line text is read from the source file so that it matches by construction
cat >ann.pl <<'EOF'
#!/usr/bin/env perl
# annotate callback:  one line per source line, as
#   commit|abbreviated_name;full_name|date|text
use strict;
use warnings;

open(my $handle, '<', $ARGV[0]) or die("cannot read '$ARGV[0]': $!");
my $lineNo = 0;
while (my $line = <$handle>) {
    chomp($line);
    ++$lineNo;
    print("C0000$lineNo|a'b c;Some One|2026-01-0$lineNo|$line\n");
}
close($handle);
exit(0);
EOF

cat >sel.pl <<'EOF'
#!/usr/bin/env perl
# select callback, called as
#   sel.pl mode argvLog lineDataJson annotateDataJson fileName lineNumber
# 'mode' and 'argvLog' are the callback arguments from '--select-script'; the
#   four after them are what genhtml passes.
use strict;
use warnings;

my $mode = shift(@ARGV);
my $log  = shift(@ARGV);

open(my $handle, '>>', $log) or die("cannot append to '$log': $!");
print($handle 'ARGC=' . scalar(@ARGV) . "\n");
for (my $i = 0; $i <= $#ARGV; ++$i) {
    print($handle '  [' . ($i + 1) . ']=<' . $ARGV[$i] . ">\n");
}
close($handle);

if ('exit42' eq $mode) {
    # a script which falls over:  it says '1', and then says it failed
    print(STDERR "select: cannot reach the server\n");
    print("1\n");
    exit(42);
}
kill('KILL', $$) if 'signal' eq $mode;
if ('junk' eq $mode) {
    print("yes\n");
    exit(0);
}
if ('chatty' eq $mode) {
    print("1\nand another thing\n");
    exit(0);
}
if ('gnc' eq $mode) {
    # select the 'new code' coverpoints:  the TLA is in the line data, which
    #   is only true JSON if its quoting survived the call
    print(($ARGV[0] =~ /"GNC"/) ? "1\n" : "0\n");
    exit(0);
}
die("unknown mode '$mode'") unless 'yes' eq $mode || 'no' eq $mode;
print('yes' eq $mode ? "1\n" : "0\n");
exit(0);
EOF

cat >ver.pl <<'EOF'
#!/usr/bin/env perl
# version callback, called as
#   ver.pl mode argvLog sourceFileName                         (extract), or
#   ver.pl mode argvLog --compare versionId versionId fileName (compare)
use strict;
use warnings;

my $mode = shift(@ARGV);
my $log  = shift(@ARGV);

if ('--compare' eq $ARGV[0]) {
    shift(@ARGV);
    open(my $handle, '>>', $log) or die("cannot append to '$log': $!");
    print($handle 'ARGC=' . scalar(@ARGV) . "\n");
    for (my $i = 0; $i <= $#ARGV; ++$i) {
        print($handle '  [' . ($i + 1) . ']=<' . $ARGV[$i] . ">\n");
    }
    close($handle);
    if ('signal' eq $mode) {
        # say something, and then die from it.  What it said is all the caller
        #   has to go on, so it has to reach the caller:  a killed process
        #   never flushes
        $| = 1;
        print("cannot reach the server\n");
        kill('KILL', $$);
    }
    # the two IDs differ, so an exact match is not what is being asked:  they
    #   are the same revision if they name the same author
    exit(0) if 3 == scalar(@ARGV) &&
        $ARGV[0] =~ /\(o'brien\)$/ &&
        $ARGV[1] =~ /\(o'brien\)$/;
    exit(1);
}
print("rev 2 (o'brien)\n");
exit(0);
EOF

# the module form of the same callback, failing in a way lcov has not already
#   reported.  That is the one case the wrapper in genhtml has to report
#   itself;  a script callback's failures are reported where they happen, and
#   the wrapper has to let those out rather than wrap them in a second message
cat >seldie.pm <<'EOF'
package seldie;

use strict;
use warnings;

sub new
{
    my $class = shift;
    return bless({}, $class);
}

sub select
{
    die("seldie: cannot make up my mind\n");
}

1;
EOF

# and the module form of the version callback, failing the same way:  a
#   different version ID from the one in the data file, so that the two have to
#   be compared, and a comparison which falls over
cat >verdie.pm <<'EOF'
package verdie;

use strict;
use warnings;

sub new
{
    my $class = shift;
    return bless({}, $class);
}

sub extract_version
{
    return "rev 3 (o'brien)";
}

sub compare_version
{
    die("verdie: cannot tell one from the other\n");
}

1;
EOF

# and one which cannot work out the version in the first place
cat >verextdie.pm <<'EOF'
package verextdie;

use strict;
use warnings;

sub new
{
    my $class = shift;
    return bless({}, $class);
}

sub extract_version
{
    die("verextdie: no such revision\n");
}

sub compare_version
{
    return 0;    # never reached:  there is nothing to compare
}

1;
EOF

chmod +x ann.pl sel.pl ver.pl

# what the annotation argument has to look like when it arrives:  one
#   argument, with the space and the apostrophe in it
cat >expect_annotate.txt <<'EOF'
  [2]=<["a'b c",null]>
EOF

# and what the whole 'compare' call has to look like, once the (absolute)
#   source file path is folded away
cat >expect_compare.txt <<'EOF'
ARGC=3
  [1]=<rev 1 (o'brien)>
  [2]=<rev 2 (o'brien)>
  [3]=<PATH>
EOF

# the select callback is called once per coverpoint;  a mode which selects
#   everything therefore sees all five, including the deleted line, whose key
#   is not a number.
# Line 2 is not a coverpoint:  it is asked about as a candidate context line -
#   the region around a selected line takes in adjacent non-code lines which
#   the criterion also selects.  That only happens now that the region stack
#   advances past the deleted line's key;  see case 15
cat >expect_lines.txt <<'EOF'
1
2
3
4
5
<<<4
EOF

# run genhtml with the select callback in $1, and the rest of the arguments
select_run()
{
    # $1 = mode, $2.. = extra genhtml options
    local mode=$1
    shift
    rm -f $mode.argv
    $COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_$mode current.info $DIFF_OPTS \
        --annotate-script $HERE/ann.pl \
        --select-script $HERE/sel.pl,$mode,$HERE/$mode.argv \
        --rc num_context_lines=0 "$@" >$mode.log 2>&1
    local rc=$?
    cat $mode.log
    return $rc
}

# the whole report is there:  4 lines, one of each TLA except CBC, which has
#   two.  This is what the fix has to produce for a callback which says '1',
#   and what the broken implementation produced for one which said '0'
require_everything()
{
    # $1 = label, $2 = log file
    local label=$1 log=$2
    if ! grep -E -q '^ +lines\.+: 75\.0% \(3 of 4 lines\)$' $log ; then
        fail "$label" "expected all 4 lines in the report"
    fi
    for tla in 'UBC....: 1' 'GNC....: 1' 'CBC....: 2' 'DCB....: 1' ; do
        if ! grep -F -q -e "$tla" $log ; then
            fail "$label" "expected '$tla' in the summary"
        fi
    done
}

# ----------------------------------------------------------------------
echo "*** 1. a script which writes '1' and exits zero selects everything"
# ----------------------------------------------------------------------
# the documented protocol.  Before the fix this emptied the report:  the exit
#   status was the answer, and zero meant 'no'
select_run yes
if [ 0 != $? ] ; then
    fail yes "genhtml failed"
fi
require_everything yes yes.log

# ----------------------------------------------------------------------
echo "*** 2. a script which writes '0' selects nothing"
# ----------------------------------------------------------------------
select_run no
if [ 0 != $? ] ; then
    fail no "genhtml failed"
fi
if ! grep -F -q -e \
    "no data found (your '--select-script' criteria may not match any coverpoints)" \
    no.log ; then
    fail no "expected an empty report"
fi

# ----------------------------------------------------------------------
echo "*** 3. a script which decides from the coverpoint data"
# ----------------------------------------------------------------------
# the mode looks for '"GNC"' in the line data - so this passes only if the
#   JSON arrived as JSON, quotes and all
select_run gnc
if [ 0 != $? ] ; then
    fail gnc "genhtml failed"
fi
if ! grep -E -q '^ +lines\.+: 100\.0% \(1 of 1 line\)$' gnc.log ; then
    fail gnc "expected exactly the one GNC line in the report"
fi
if ! grep -F -q -e 'GNC....: 1' gnc.log ; then
    fail gnc "expected the GNC line in the summary"
fi
# not DCB:  the callback declines the deleted line too, but genhtml shows a
#   removed line beside the line which replaced it - so it is displayed, and
#   counted, as part of the region the selected line brought in.  That is
#   pre-existing behaviour and has nothing to do with the callback:  a
#   criterion which selects the UBC line instead, which no diff hunk touches,
#   reports UBC alone
for tla in CBC UBC ; do
    if grep -F -q -e "$tla....:" gnc.log ; then
        fail gnc "'$tla' was selected by a 'GNC' criterion"
    fi
done

# ----------------------------------------------------------------------
echo "*** 4. the arguments arrive whole"
# ----------------------------------------------------------------------
# every call has four arguments - the deleted line included, which used to
#   arrive with two because '<<<4' was read as a here-string
CALLS=`grep -c '^ARGC=' yes.argv`
FOURS=`grep -c '^ARGC=4$' yes.argv`
echo "select callback: $CALLS calls, $FOURS of them with 4 arguments"
if [ "$CALLS" != "$FOURS" ] || [ 0 == "$CALLS" ] ; then
    fail argv "expected 4 arguments in every call"
    grep '^ARGC=' yes.argv | sort | uniq -c
fi
# and every coverpoint was offered, by its own key
grep -h '^  \[4\]=' yes.argv | sed -e 's/^  \[4\]=<\(.*\)>$/\1/' |
    LC_ALL=C sort -u >got_lines.txt
cat got_lines.txt
if ! diff expect_lines.txt got_lines.txt ; then
    fail argv "the callback was not asked about every coverpoint"
fi
# the annotation data is one argument, spaces, apostrophe and quoting intact
if ! grep -F -q -f expect_annotate.txt yes.argv ; then
    fail argv "the annotation argument did not arrive whole"
    grep -F -e '[2]=' yes.argv | sort -u
fi
# the line data is JSON
if ! grep -E -q '^  \[1\]=<\[[0-9]+,\["[A-Z]{3}",' yes.argv ; then
    fail argv "the line data argument is not json"
    grep -F -e '[1]=' yes.argv | sort -u
fi

# ----------------------------------------------------------------------
echo "*** 5. a script which exits non-zero is reported"
# ----------------------------------------------------------------------
select_run exit42
if [ 0 == $? ] ; then
    fail exit42 "expected a failing select callback to be an error"
fi
for pattern in 'ERROR: (callback)' 'select callback failed' \
    'returned non-zero exit status 42' ; do
    if ! grep -F -q -e "$pattern" exit42.log ; then
        fail exit42 "message does not mention: $pattern"
    fi
done
# once, and not wrapped inside a second copy of itself:  the caller catches the
#   die which the report above turned into, and has to recognize it as already
#   reported rather than report it again
if grep -E -q 'ERROR: .*(ERROR|WARNING):' exit42.log ; then
    fail exit42 "the failure was reported twice"
fi
# ...and, when the error is ignored, the coverpoint is kept rather than
#   silently dropped
select_run exit42 --ignore-errors callback
if [ 0 != $? ] ; then
    fail exit42 "genhtml failed with the callback error ignored"
fi
require_everything exit42 exit42.log

# ----------------------------------------------------------------------
echo "*** 6. a script which answers something else is reported"
# ----------------------------------------------------------------------
select_run junk
if [ 0 == $? ] ; then
    fail junk "expected an unparsable answer to be an error"
fi
for pattern in 'ERROR: (callback)' "answered 'yes' - expected '0' or '1'" ; do
    if ! grep -F -q -e "$pattern" junk.log ; then
        fail junk "message does not mention: $pattern"
    fi
done
select_run junk --ignore-errors callback
if [ 0 != $? ] ; then
    fail junk "genhtml failed with the callback error ignored"
fi
require_everything junk junk.log

# ----------------------------------------------------------------------
echo "*** 7. a script which is killed is reported"
# ----------------------------------------------------------------------
select_run signal
if [ 0 == $? ] ; then
    fail signal "expected a killed select callback to be an error"
fi
for pattern in 'ERROR: (callback)' 'died due to signal 9' ; do
    if ! grep -F -q -e "$pattern" signal.log ; then
        fail signal "message does not mention: $pattern"
    fi
done

# ----------------------------------------------------------------------
echo "*** 8. a script which cannot be executed is reported"
# ----------------------------------------------------------------------
rm -f nosuch.argv
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_nosuch current.info $DIFF_OPTS \
    --select-script $HERE/nosuch.pl,yes,$HERE/nosuch.argv \
    >nosuch.log 2>&1
if [ 0 == $? ] ; then
    fail nosuch "expected an unexecutable select callback to be an error"
fi
cat nosuch.log
for pattern in 'ERROR: (callback)' "select: 'open(-|" \
    'No such file or directory' ; do
    if ! grep -F -q -e "$pattern" nosuch.log ; then
        fail nosuch "message does not mention: $pattern"
    fi
done

# ----------------------------------------------------------------------
echo "*** 9. a script which says more than it was asked to is not broken"
# ----------------------------------------------------------------------
# only the first line is the answer.  The rest has to be read anyway, or the
#   callback is killed by SIGPIPE and reported for it
select_run chatty
if [ 0 != $? ] ; then
    fail chatty "genhtml failed on a callback which wrote two lines"
fi
require_everything chatty chatty.log
if grep -F -q -e 'ERROR: (callback)' chatty.log ||
   grep -F -q -e 'WARNING: (callback)' chatty.log ; then
    fail chatty "a callback which wrote two lines was reported as broken"
fi

# ----------------------------------------------------------------------
echo "*** 10. compare_version gets three arguments, whole"
# ----------------------------------------------------------------------
# both version IDs contain a space and an apostrophe.  The apostrophe is the
#   one which mattered:  the three arguments used to be single-quoted by hand
#   and handed to a shell, which made a syntax error of this
rm -f match.argv
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_match version.info \
    --version-script $HERE/ver.pl,match,$HERE/match.argv >match.log 2>&1
if [ 0 != $? ] ; then
    cat match.log
    fail match "genhtml failed"
fi
cat match.log
if grep -F -q -e 'ERROR: (version)' match.log ; then
    fail match "the version IDs did not arrive as they were written"
fi
sed -e 's|^\(  \[3\]=\)<.*>$|\1<PATH>|' match.argv >got_compare.txt
cat got_compare.txt
if ! diff expect_compare.txt got_compare.txt ; then
    fail match "the compare call did not arrive whole"
fi

# ----------------------------------------------------------------------
echo "*** 11. a compare_version script which is killed is reported"
# ----------------------------------------------------------------------
# the exit status is the answer for this callback, so 'non-zero' means "the
#   versions differ" and cannot also mean "I failed".  What can still be told
#   apart is a callback which died - and that is a callback error, not a
#   version mismatch
rm -f vsignal.argv
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_vsignal version.info \
    --version-script $HERE/ver.pl,signal,$HERE/vsignal.argv >vsignal.log 2>&1
if [ 0 == $? ] ; then
    fail vsignal "expected a killed compare callback to be an error"
fi
cat vsignal.log
# the callback is not asked to write anything - the exit status is the answer -
#   but if it wrote something before it fell over, that is the most useful
#   thing there is to show, so it is in the message.  It used to be captured
#   and thrown away
for pattern in 'ERROR: (callback)' 'compare_version callback failed' \
    'died due to signal 9' 'cannot reach the server' ; do
    if ! grep -F -q -e "$pattern" vsignal.log ; then
        fail vsignal "message does not mention: $pattern"
    fi
done
if grep -F -q -e 'ERROR: (version)' vsignal.log ; then
    fail vsignal "a failed compare callback was reported as a version mismatch"
fi
if grep -E -q 'ERROR: .*(ERROR|WARNING):' vsignal.log ; then
    fail vsignal "the failure was reported twice"
fi

# ----------------------------------------------------------------------
echo "*** 12. a select callback module which dies is reported, once"
# ----------------------------------------------------------------------
# the module form of the callback.  Its failure is not one lcov reported, so
#   here the wrapper in genhtml is the one which has to report it - and it too
#   keeps the coverpoint
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_module current.info $DIFF_OPTS \
    --select-script $HERE/seldie.pm >module.log 2>&1
if [ 0 == $? ] ; then
    fail module "expected a select callback module which dies to be an error"
fi
cat module.log
for pattern in 'ERROR: (callback)' 'select(..) failed' \
    'seldie: cannot make up my mind' ; do
    if ! grep -F -q -e "$pattern" module.log ; then
        fail module "message does not mention: $pattern"
    fi
done
if grep -E -q 'ERROR: .*(ERROR|WARNING):' module.log ; then
    fail module "the failure was reported twice"
fi
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_module current.info $DIFF_OPTS \
    --select-script $HERE/seldie.pm --ignore-errors callback \
    >module_ignore.log 2>&1
if [ 0 != $? ] ; then
    cat module_ignore.log
    fail module "genhtml failed with the callback error ignored"
fi
cat module_ignore.log
require_everything module module_ignore.log

# ----------------------------------------------------------------------
echo "*** 13. a compare_version callback module which dies is reported, once"
# ----------------------------------------------------------------------
# the same, for the other callback:  a module whose comparison falls over is
#   reported by the caller, and the versions are then taken not to match -
#   which is the safe assumption, and a separate, ignorable, 'version' error
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_vmodule version.info \
    --version-script $HERE/verdie.pm >vmodule.log 2>&1
if [ 0 == $? ] ; then
    fail vmodule "expected a compare_version module which dies to be an error"
fi
cat vmodule.log
for pattern in 'ERROR: (callback)' 'compare_version(' \
    'verdie: cannot tell one from the other' ; do
    if ! grep -F -q -e "$pattern" vmodule.log ; then
        fail vmodule "message does not mention: $pattern"
    fi
done
if grep -E -q 'ERROR: .*(ERROR|WARNING):' vmodule.log ; then
    fail vmodule "the failure was reported twice"
fi
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_vmodule version.info \
    --version-script $HERE/verdie.pm --ignore-errors callback,version \
    >vmodule_ignore.log 2>&1
if [ 0 != $? ] ; then
    cat vmodule_ignore.log
    fail vmodule "genhtml failed with the callback and version errors ignored"
fi
cat vmodule_ignore.log
if ! grep -F -q -e 'version mismatch' vmodule_ignore.log ; then
    fail vmodule "a comparison which could not be made should not be a match"
fi

# ----------------------------------------------------------------------
echo "*** 14. an extract_version callback which dies is reported, once"
# ----------------------------------------------------------------------
# the third of the callers which catches a callback's die and reports it
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_vextract version.info \
    --version-script $HERE/verextdie.pm >vextract.log 2>&1
if [ 0 == $? ] ; then
    fail vextract "expected an extract_version module which dies to be an error"
fi
cat vextract.log
for pattern in 'ERROR: (callback)' 'extract_version(' \
    'verextdie: no such revision' ; do
    if ! grep -F -q -e "$pattern" vextract.log ; then
        fail vextract "message does not mention: $pattern"
    fi
done
if grep -E -q 'ERROR: .*(ERROR|WARNING):' vextract.log ; then
    fail vextract "the failure was reported twice"
fi

# ----------------------------------------------------------------------
echo "*** 15. the deleted-line key never reaches numeric context"
# ----------------------------------------------------------------------
# '<<<4' in a numeric comparison numifies to 0:  the warning is the visible
#   half of the bug, and the invisible half is that the interesting-region
#   stack stopped advancing there, so every line below it was selected
NUMERIC=`grep -l "isn't numeric" *.log 2>/dev/null`
if [ -n "$NUMERIC" ] ; then
    fail numeric "a line key reached numeric context: $NUMERIC"
    grep -h "isn't numeric" $NUMERIC | sort -u
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'selectscript' $LOCAL_COVERAGE 0
fi

exit $STATUS
