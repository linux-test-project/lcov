#! /usr/bin/env bash

# Call sites in the '.info' file:  the 'FNC:' record, and the reader and writer
# of it - part 3 of 3.
#
# The former monolithic 'format.sh' ran 20 scenarios over the same hand-written
# tracefiles, which is the longest single test in the suite under '--coverage'.
# The scenarios keep their original numbering here:  'format1.sh' runs 1 to 8,
# 'format2.sh' 9 to 14, 'format3.sh' 15 to 21, so a cross-reference to a section
# number still finds it.  The discussion of the record itself, the helpers and
# the two fixtures which more than one part reads are in 'setup_common.sh'; each
# part runs in its own working directory (format3.d), so the three cannot
# collide.

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf format3.d
    exit 0
fi

WORKDIR=format3.d
source ./setup_common.sh

# ----------------------------------------------------------------------
echo "*** 15. a call written in a file other than the caller's own"
# ----------------------------------------------------------------------
# The compiler builds the body of a function out of the text of whichever file
#   that text was written in, so the file a call is written in is not always the
#   file the function which makes it is defined in:  an '#include'd fragment is
#   the plain case, and an inline function in a header is the common one.  The
#   site belongs to the caller either way - it is the caller's count which the
#   call changes - so the record goes in the caller's section, and names the other
#   file.
# It names it by an index, because the name is long and would otherwise be
#   repeated on every record:  'SF:[<index>,]<name>' gives a file one, and
#   'FNC:<fnIndex>[@<sfIndex>],..' uses it.  Both fields are optional and are
#   written only when something needs them.
#
# 'shim' is defined in 'b.c' and its whole body is written in 'inc.h', so both of
#   its calls are in a file it is not defined in;  'caller' in 'a.c' calls the
#   same two functions from its own file, so one fixture holds both shapes.
cat >proj/inc.h <<'EOF'
    int a = helper(x);
    int b = other(x);
    return a + b;
EOF
cat >proj/b.c <<'EOF'
int shim(int x)
{
#include "inc.h"
}
EOF

# This is what the writer produces for itself, so it is the round-trip fixture
#   too.  Note the order:  sections are written in file-name order, so 'inc.h' -
#   which is where the index is defined - comes after the records which use it.
#   That is not an accident of this fixture and cannot be avoided in general:
#   two files can call into each other, so a reader has to tolerate a forward
#   reference, and does (see '_resolvePendingSites').
# Only 'inc.h' has an index, because only 'inc.h' is named by a record.  The
#   files which hold the calls do not get one for holding them
cat >xf.info <<'EOF'
TN:format
SF:proj/a.c
FNL:0,1,4
FNA:0d,8,helper
FNL:1,6,9
FNA:1,1,other
FNL:2,11,15
FNA:2d,1,caller
FNC:2,13,13,0,3,helper
FNC:2,13,31,0,2,helper
FNF:3
FNH:3
FNCF:2
FNCH:2
DA:1,8
DA:3,8
DA:6,1
DA:8,1
DA:11,1
DA:13,1
DA:14,1
LF:7
LH:7
end_of_record
TN:format
SF:proj/b.c
FNL:0,1,4
FNA:0d,1,shim
FNC:0@0,1,13,0,1,helper
FNC:0@0,2,13,0,1,other
FNF:1
FNH:1
FNCF:2
FNCH:2
DA:1,1
DA:3,1
LF:2
LH:2
end_of_record
TN:format
SF:0,proj/inc.h
FNF:0
FNH:0
FNCF:0
FNCH:0
DA:1,1
DA:2,1
DA:3,1
LF:3
LH:3
end_of_record
EOF

runLcov xfround --callgraph -a xf.info -o xfround.info
if [ -f xfround.info ] && ! diff -u xf.info xfround.info ; then
    fail xfround "a cross-file call site does not round trip"
fi

# ..and the same file read in chunks, which is the one path that cannot see the
#   whole tracefile as it reads:  a chunk which holds a record naming an index
#   whose 'SF:' record went to another chunk re-reads the file for the file
#   records alone.  Every width, since which chunk boundary lands between the two
#   is the question
for WIDTH in 2 3 4 8 ; do
    runLcov xfchunk$WIDTH --callgraph -a xf.info \
        --rc parallel_parse_min_lines=1 --parallel $WIDTH -o xfchunk$WIDTH.info
    if [ -f xfchunk$WIDTH.info ] && ! diff -u xf.info xfchunk$WIDTH.info ; then
        fail xfchunk$WIDTH \
            "a chunked read of a cross-file call site differs at width $WIDTH"
    fi
done

# The index is a property of one tracefile and nothing else, which is what makes
#   two of them concatenable:  each half numbered the files it names for itself,
#   so the same number can mean two different files in one input.  A site takes
#   the definition its own half gave - the first one at or after it, and the last
#   one before it if there is none.
# 'c.c' is 'b.c' again in a second tracefile, with its own 'inc2.h' also numbered
#   0.  If a site took the wrong definition the calls would come out attributed
#   to the other header, and the sites of one of the two would be dropped
cat >proj/inc2.h <<'EOF'
    return helper(x) * 2;
EOF
cat >proj/c.c <<'EOF'
int shim2(int x)
{
#include "inc2.h"
}
EOF
cat >xf2.info <<'EOF'
TN:format
SF:proj/c.c
FNL:0,1,4
FNA:0,5,shim2
FNC:0@0,1,12,0,5,helper
FNF:1
FNH:1
FNCF:1
FNCH:1
DA:1,5
DA:3,5
LF:2
LH:2
end_of_record
TN:format
SF:0,proj/inc2.h
FNF:0
FNH:0
FNCF:0
FNCH:0
DA:1,5
LF:1
LH:1
end_of_record
EOF
cat xf.info xf2.info > xfboth.info
runLcov xfcat --callgraph -a xfboth.info -o xfcat.info
# ..and the indexes in the result are this file's own:  assigned in file-name
#   order over the files which need one, so the header 'c.c' uses is 1 here and
#   was 0 in its own input
checkCallRecords xfcat xfcat.info <<'EOF'
FNC:2,13,13,0,3,helper
FNC:2,13,31,0,2,helper
FNCF:2
FNCH:2
FNC:0@0,1,13,0,1,helper
FNC:0@0,2,13,0,1,other
FNCF:2
FNCH:2
FNC:0@1,1,12,0,5,helper
FNCF:1
FNCH:1
FNCF:0
FNCH:0
FNCF:0
FNCH:0
EOF
grep -E '^SF:' xfcat.info > xfcat.sf
cat >xfcat.sfexpect <<'EOF'
SF:proj/a.c
SF:proj/b.c
SF:proj/c.c
SF:0,proj/inc.h
SF:1,proj/inc2.h
EOF
if ! diff -u xfcat.sfexpect xfcat.sf ; then
    fail xfcat "unexpected source records in xfcat.info"
fi

# Removing the file the calls are written in takes the sites with it:  the record
#   names that file by index and only an 'SF:' record can define one, so a site
#   whose file has no section cannot be written at all.  That is the same loss
#   'noteExternalCalls' covers and gets the same treatment - the call survives on
#   the callee as the 'x' flag, "somebody called me and this report cannot say
#   who", carrying the count the site had.  'helper' was entered 8 times and
#   the two sites which are left and the one which went account for 6 of them,
#   so it is still deduced to have been called from somewhere else;  'other' is
#   accounted for by the one call its removed site made.  With no cross-file
#   site left, no file needs an index either.
# 'b.c' loses more than its sites:  every call it made was written in the file
#   which went, so what is left of it says nothing about its calls at all, and it
#   gets no 'FNCF:'/'FNCH:' pair either (see FunctionMap::hasCallgraphData).  A
#   zero pair would have been the one answer which is certainly wrong - 'shim'
#   does call, and the report can no longer show it
runLcov xfrm --callgraph -r xf.info 'proj/inc.h' -o xfrm.info
checkAliasRecords xfrm xfrm.info <<'EOF'
FNA:0x1d,8,helper
FNA:1x1,1,other
FNA:2d,1,caller
FNA:0,1,shim
EOF
checkCallRecords xfrm xfrm.info <<'EOF'
FNC:2,13,13,0,3,helper
FNC:2,13,31,0,2,helper
FNCF:2
FNCH:2
EOF
if grep -q -E '^SF:[0-9]+,' xfrm.info ; then
    fail xfrm "an index was written for a report which needs none:" \
        `grep -E '^SF:' xfrm.info`
fi

# An index no 'SF:' record defines is a malformed tracefile, and is reported as
#   the 'format' error that it is rather than guessed at
sed -e 's/@0,/@7,/' xf.info > xfbad.info
checkFail xfbadidx \
    "no 'SF:' record defines source file index '7', named by the call to 'helper'" \
    --callgraph -a xfbad.info -o xfbadidx.info
# ..and ignoring it drops the site, which is the only other thing it could do:
#   there is no file to attribute the call to.  The callee does not acquire the
#   'x' flag for it, either - a record which could not be read is not evidence
#   that a call was made
runWarn xfbadignore "no 'SF:' record defines source file index '7'" \
    --callgraph -a xfbad.info --ignore-errors format -o xfbadignore.info
checkAliasRecords xfbadignore xfbadignore.info <<'EOF'
FNA:0d,8,helper
FNA:1d,1,other
FNA:2d,1,caller
FNA:0,1,shim
EOF

# Two callees at one location in a file other than the caller's own is the
#   same 'mismatch' as it is in the caller's file, and the message names the
#   file the call is written in
sed -e 's/^FNC:0@0,1,13,0,1,helper$/&\nFNC:0@0,1,13,0,1,other/' \
    -e '/^SF:proj\/b.c$/,/^end_of_record$/{s/^FNCF:2$/FNCF:3/;s/^FNCH:2$/FNCH:3/}' \
    xf.info > xfmismatch.info
checkFail xfmismatch \
    "\"proj/inc.h\":1: call site 1:13:0:proj/inc.h in 'shim' calls 'helper' but also 'other'" \
    --callgraph -a xfmismatch.info -o discard.info

# The one file name a reader could not tell from an index is one which begins
#   with digits and a comma.  Such a file is given an index whether or not any
#   record names it, which makes the record unambiguous without touching the
#   name:  the name is then the field which takes the rest of the line.
# Also with the metric off, since the name has to survive a plain merge as well
cat >odd.info <<'EOF'
TN:format
SF:0,12,odd.c
FNL:0,1,4
FNA:0,1,oddfn
FNC:0,3,10,0,1,helper
FNF:1
FNH:1
FNCF:1
FNCH:1
DA:1,1
DA:3,1
LF:2
LH:2
end_of_record
EOF
runLcov oddname --callgraph -a odd.info -o oddname.info
if [ -f oddname.info ] && ! grep -q -F -e 'SF:0,12,odd.c' oddname.info ; then
    fail oddname "a file name which looks like an index lost its index:" \
        `grep -E '^SF:' oddname.info`
fi
runLcov oddplain -a odd.info -o oddplain.info
if [ -f oddplain.info ] && ! grep -q -F -e 'SF:0,12,odd.c' oddplain.info ; then
    fail oddplain "the index is needed whether or not the metric is on:" \
        `grep -E '^SF:' oddplain.info`
fi

# ..and what the records are for, in the report:  the call is counted by the file
#   the caller is defined in, which is what 'FNCF'/'FNCH' say and the only thing a
#   per-file total can mean - and it is shown in the source view of the file it is
#   written in, whose text is where the reader can see the call.  So 'b.c' has
#   both sites, 'inc.h' has the lines they are on, and the page of each callee
#   names the site by the file it is written in and links to the caller's table
runGenhtml xfhtml --callgraph -o html_xf xf.info
if ! grep -E 'callgraph.*100.0% \(4 of 4 callees\)' xfhtml.log ; then
    fail xfhtml "expected '4 of 4 callees':" `grep -i callee xfhtml.log`
fi
AFUNC=`find html_xf -name 'a.c.callers.html'`
BFUNC=`find html_xf -name 'b.c.callees.html'`
INCSRC=`find html_xf -name 'inc.h.gcov.html'`
if [ ! -f "$AFUNC" ] || [ ! -f "$BFUNC" ] || [ ! -f "$INCSRC" ] ; then
    fail xfhtml "the pages of the cross-file fixture were not written"
else
    # the caller's own table, which is where the count is
    for WHERE in 'inc.h:1:13' 'inc.h:2:13' ; do
        if ! grep -q -F -e "$WHERE" $BFUNC ; then
            fail xfhtml "'$WHERE' is not in the call table of 'shim'"
        fi
    done
    # ..the callee's table, which shows the same location and links back to it
    if ! grep -q -F -e 'b.c.callees.html#site_proj_inc_h_1_13_1' $AFUNC ; then
        fail xfhtml "the callers of 'helper' do not link to the site in inc.h:"
        grep -F -e 'id="func_helper"' -A 8 $AFUNC
    fi
    if ! grep -q -F -e 'inc.h:1:13' $AFUNC ; then
        fail xfhtml "the callers of 'helper' do not name the file inc.h"
    fi
    # ..with a category on its count, like any other row of that table.  A
    #   cross-file site is categorized when its *caller's* file is read, which is
    #   not the file whose page shows it here, so the row would be left
    #   uncategorized - class 'coverCallgraphHi' instead of a 'tla*' - if the
    #   categorization were not done for the whole report up front
    if ! grep -A 4 -F -e 'site_proj_inc_h_1_13_1' $AFUNC | grep -q -F 'tlaGNC'
    then
        fail xfhtml "the cross-file caller of 'helper' has no category:"
        grep -A 4 -F -e 'site_proj_inc_h_1_13_1' $AFUNC
    fi
    # ..and the source view of the file the call is written in, whose own
    #   functions make no calls at all:  the links are to another file's page
    if ! grep -q -F -e 'b.c.callees.html#site_proj_inc_h_2_13' $INCSRC ; then
        fail xfhtml "the source view of inc.h does not decorate its calls:"
        grep -F -e 'callSite' $INCSRC
    fi
fi

# A line which still carries a call site is not a line the line filters take -
#   what is called on a line which looks like nothing but a closing brace is a
#   real call, to the destructor of an object which went out of scope there (see
#   section 12) - and a call written in another file is not on one of this file's
#   lines at all.  Its line number indexes that other file, so the line of this
#   file which happens to have the same number must not be held against it.
# 'd.c' line 3 is excluded by name and has nothing on it;  the calls of 'wrap'
#   are written in 'inc3.h', one of them on line 3 of that file
cat >proj/inc3.h <<'EOF'
    int u = helper(t);
    int v = t + 1;
    return other(u) + v;
EOF
cat >proj/d.c <<'EOF'
int wrap(int x)
{
    int t = x;    /* NOISEWORD */
#include "inc3.h"
}

int helper(int x) { return x + 1; }
int other(int x) { return x - 1; }
EOF
cat >xfomit.info <<'EOF'
TN:format
SF:proj/d.c
FNL:0,1,5
FNA:0d,2,wrap
FNC:0@0,1,13,0,2,helper
FNC:0@0,3,12,0,2,other
FNL:1,7,7
FNA:1,2,helper
FNL:2,8,8
FNA:2,2,other
FNF:3
FNH:3
FNCF:2
FNCH:2
DA:1,2
DA:3,2
DA:7,2
DA:8,2
LF:4
LH:4
end_of_record
TN:format
SF:0,proj/inc3.h
FNF:0
FNH:0
FNCF:0
FNCH:0
DA:1,2
DA:2,2
DA:3,2
LF:3
LH:3
end_of_record
EOF
runLcov xfomit --callgraph -a xfomit.info --omit-lines NOISEWORD -o xfomit.out
# ..so the excluded line goes, and the two calls stay:  an exclusion in the
#   caller's file does not reach a call written somewhere else, exactly as it
#   does not reach one written in an '#include'd fragment of its own
sed -n '/^SF:proj\/d.c$/,/^end_of_record$/p' xfomit.out > xfomit.dc
cat >xfomit.dcexpect <<'EOF'
SF:proj/d.c
FNL:0,1,5
FNA:0d,2,wrap
FNC:0@0,1,13,0,2,helper
FNC:0@0,3,12,0,2,other
FNL:1,7,7
FNA:1,2,helper
FNL:2,8,8
FNA:2,2,other
FNF:3
FNH:3
FNCF:2
FNCH:2
DA:1,2
DA:7,2
DA:8,2
LF:3
LH:3
end_of_record
EOF
if [ -f xfomit.out ] && ! diff -u xfomit.dcexpect xfomit.dc ; then
    fail xfomit "the line the cross-file call is not on survived its exclusion"
fi
# ..and the file the calls are written in is untouched:  line 3 there is the line
#   one of them is on, and nothing asked for it to go
sed -n '/^SF:0,proj\/inc3.h$/,/^end_of_record$/p' xfomit.out > xfomit.inc
cat >xfomit.incexpect <<'EOF'
SF:0,proj/inc3.h
FNF:0
FNH:0
FNCF:0
FNCH:0
DA:1,2
DA:2,2
DA:3,2
LF:3
LH:3
end_of_record
EOF
if [ -f xfomit.out ] && ! diff -u xfomit.incexpect xfomit.inc ; then
    fail xfomit "the file the calls are written in lost a line"
fi

# ----------------------------------------------------------------------
echo "*** 16. a call to a callee the report does not describe"
# ----------------------------------------------------------------------
# The default:  such a call is dropped.  The metric answers "were the functions
#   this report describes exercised", and a call to something it does not
#   describe cannot contribute to that answer - there is no page for the name to
#   lead to, and no test the user could add to this report to cover it, while a
#   C++ report carries enough of them (every implicit 'std::' instantiation) to
#   dominate the denominator.  What is left of such a call is the 'c' flag of its
#   caller's leader record, which section 18 is about.

# 'printf' goes, the calls to 'helper' and 'other' stay, and the totals are
#   recomputed from what is left
runLcov extdrop --callgraph -a a.info -o extdrop.info
checkCallRecords extdrop extdrop.info <<'EOF'
FNC:2,13,13,0,3,helper
FNC:2,13,13,1,0,other
FNC:2,13,31,0,2,helper
FNC:2,13,31,1,2,helper
FNCF:4
FNCH:3
EOF

# ..and it is not done silently:  '--verbose' says how many went
runLcov extmsg --callgraph -a a.info -v -o extmsg.info
if [ -f extmsg.log ] &&
   ! grep -q -F -e "dropped 1 call site(s) whose callee is not in this report" \
        extmsg.log ; then
    fail extmsg "the removal was not reported:" `grep -i -e callee extmsg.log`
fi

# ..and what is left of the drop is the expectation 'setup_common.sh' derives by
#   hand:  the site gone and its caller's leader flagged, with everything else of
#   the fixture untouched
if [ -f extdrop.info ] && ! diff -u ar.info extdrop.info ; then
    fail extdrop "the resolved tracefile is not what was expected"
fi

# The rate the user sees, which is the point of all of it:  one of the five
#   sites of this fixture is a call out of the report, and it was taken - so
#   dropping it removes one from 'found' and one from 'hit' both.  Of the four
#   left, the two at 13:31 both call 'helper' and are one row of the callees
#   page, which is what genhtml counts:  3 sites, 2 of them taken
runGenhtml extrpt --callgraph --show-proportion -o html_ext a.info
if ! grep -E 'callgraph.*66\.7% \(2 of 3 callees\)' extrpt.log ; then
    fail extrpt "expected '2 of 3 callees':" `grep -i callee extrpt.log`
fi

# ..and the name is gone from the report as well as from the totals, so there is
#   nothing left for a reader to wonder about the lack of a link on
EXTPAGE=`find html_ext -name "a.c.callees.html"`
if [ ! -f "$EXTPAGE" ] ; then
    fail extrpt "the call site page was not written"
else
    if grep -q -F -e 'printf' $EXTPAGE ; then
        fail extrpt "the dropped call is still shown:"
        grep -F -e 'printf' $EXTPAGE
    fi
fi

# ----------------------------------------------------------------------
echo "*** 17. a function with nothing to say in one of the two directions"
# ----------------------------------------------------------------------
# Each page answers one question per function, and a function which has no answer
#   to that question is not on that page:  there is no row with an empty half and
#   no note saying that there is nothing to say, since the page a reader is on is
#   the question they asked.
# 'dead' is never entered and no site in the report names it, which is the only
#   shape in which nothing at all can be said about a function's callers;  it is
#   on the page of the calls it makes, because it does contain one.  'used' is the
#   mirror image:  it is called, and calls nothing itself - so each function is on
#   exactly one of the two pages, and neither name cell offers the way to the
#   other direction, which for either of them would lead to a page it has no row
#   on
cat >proj/quiet.c <<'EOF'
static void used(int n)
{
    (void)n;
}

static void dead(void)
{
    used(1);
}
EOF
cat >quiet.info <<'EOF'
TN:format
SF:proj/quiet.c
FNL:0,1,4
FNA:0,0,used
FNL:1,6,9
FNA:1,0,dead
FNC:1,8,5,0,0,used
FNF:2
FNH:0
FNCF:1
FNCH:0
DA:1,0
DA:3,0
DA:6,0
DA:8,0
LF:4
LH:0
end_of_record
EOF
runGenhtml quiet --callgraph -o html_quiet quiet.info
QUIETCALLEES=html_quiet/proj/quiet.c.callees.html
QUIETCALLERS=html_quiet/proj/quiet.c.callers.html
if [ ! -f $QUIETCALLEES ] || [ ! -f $QUIETCALLERS ] ; then
    fail quiet "both call site pages of a file with both were not written"
else
    # one function per page, and it is the one the page has an answer for
    for pair in "$QUIETCALLEES:dead:used" "$QUIETCALLERS:used:dead" ; do
        PAGE=${pair%%:*}
        WANT=`echo $pair | cut -d: -f2`
        NOT=`echo $pair | cut -d: -f3`
        if ! grep -q -F -e "id=\"func_$WANT\"" $PAGE ; then
            fail quiet "'$WANT' has no row on $PAGE"
        fi
        if grep -q -F -e "id=\"func_$NOT\"" $PAGE ; then
            fail quiet "'$NOT' has a row on $PAGE and nothing to put in it"
        fi
        # ..and exactly one row, which is the one function:  a page has no
        #   placeholder row for the function it left out
        if [ 1 != `grep -c -F -e 'class="callgraphFirstRow"' $PAGE` ] ; then
            fail quiet "$PAGE does not hold exactly one function:" \
                `grep -c -F -e 'class="callgraphFirstRow"' $PAGE`
        fi
        # ..and the column beside its name does not offer the other direction,
        #   which is the page it has no row on
        if grep -q -E -e 'Click to go to list of call(ers|ees)' $PAGE ; then
            fail quiet "$PAGE offers the other direction of a function" \
                "which is not on that page:" \
                `grep -o -E '<a[^>]*Click to go to list of[^<]*<' $PAGE`
        fi
    done
    # ..and each of them is still named by the row of the other one, as the other
    #   end of the one call:  what the drop rule takes away is the row, not the
    #   call.  'used' is on the callers page, so the row which calls it leads
    #   there;  'dead' is not, and the row it calls from leads to the call site
    #   instead - which is on the page that row is already on
    if ! grep -q -F -e \
        '<a href="../proj/quiet.c.callers.html#func_used" title="Click to go to the callers of used">used</a>' \
        $QUIETCALLEES ; then
        fail quiet "the callee of 'dead' does not lead to its own callers:" \
            `grep -o -E '<a[^>]*>used</a>' $QUIETCALLEES`
    fi
    if ! grep -q -F -e \
        '<a href="../proj/quiet.c.callees.html#site_8_5_1" title="Click to go to list of functions called from this site">dead</a>' \
        $QUIETCALLERS ; then
        fail quiet "the caller of 'used' does not lead to the site it called" \
            "from:" `grep -o -E '<a[^>]*>dead</a>' $QUIETCALLERS`
    fi
fi

# ----------------------------------------------------------------------
echo "*** 18. the flag field of 'FNL:':  a call out of the boundary"
# ----------------------------------------------------------------------
# The mirror image of section 10.  A call whose *callee* is outside the boundary
#   of the report is dropped, for the reasons section 16 gives, and the one thing
#   which can still be said about it is that the caller made it - which is what
#   the 'c' flag of the caller's own leader record keeps.  It is on the 'FNL:'
#   record rather than on an 'FNA:' one because making a call is a property of
#   the body, which every alias of a function shares.
# The two flags are the same rule applied to the two ends of a call:  whichever
#   end the report keeps, that end records that the edge was there and that the
#   other end of it is not something this report can name.  So the answer does
#   not depend on how the boundary came to be drawn - the callee was never
#   captured, its file was removed, or the callee alone was erased - which is
#   what the runs below assert one shape at a time.

# 'caller' is the only function of the fixture which calls out of the report:
#   'printf', the site section 16 watched go.  A call whose callee the report does
#   describe crosses nothing, and a function which makes no call at all crosses
#   nothing either, so it is also the only leader which grows a letter
runLcov cflag --callgraph -a a.info -o cflag.info
checkLeaderRecords cflag cflag.info <<'EOF'
FNL:0,1,4
FNL:1,6,9
FNL:2c,11,15
EOF

# The reader:  what the writer wrote comes back as the same fact, so writing it a
#   second time is the same file byte for byte
runLcov cround --callgraph -a cflag.info -o cround.info
if [ -f cround.info ] && ! diff -u cflag.info cround.info ; then
    fail cround "the flagged tracefile does not round trip"
fi

# ..and the flag survives a merge with data which does not assert it, in either
#   order:  it is a property of the function rather than of the run which
#   observed it, which is what makes it correct to capture the units of a program
#   separately and combine them afterwards
grep -v -F -e 'FNC:2,14,5,0,1,printf' a.info |
    sed -e 's/^FNCF:5$/FNCF:4/' -e 's/^FNCH:4$/FNCH:3/' > noflag.info
if [ 1 != `grep -c -E '^FNCF:4$' noflag.info` ] ; then
    fail noflag "the unflagged fixture was not built"
fi
runLcov cmerge1 --callgraph -a cflag.info -a noflag.info -o cmerge1.info
runLcov cmerge2 --callgraph -a noflag.info -a cflag.info -o cmerge2.info
for label in cmerge1 cmerge2 ; do
    checkLeaderRecords $label $label.info <<'EOF'
FNL:0,1,4
FNL:1,6,9
FNL:2c,11,15
EOF
done
if [ -f cmerge1.info ] && [ -f cmerge2.info ] &&
   ! diff -u cmerge1.info cmerge2.info ; then
    fail cmerge "the merge does not commute"
fi

# The set intersection keeps it for the same reason, and in either order:  the
#   two operands describe the same function, and one of them says that it called
#   out of the report
$COVER $LCOV_TOOL $LCOV_OPTS --callgraph -o cinter1.info cflag.info \
    --intersect noflag.info 2>&1 | tee cinter1.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail cinter1 "lcov --intersect failed:" `grep -E 'ERROR|WARNING' cinter1.log`
fi
$COVER $LCOV_TOOL $LCOV_OPTS --callgraph -o cinter2.info noflag.info \
    --intersect cflag.info 2>&1 | tee cinter2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail cinter2 "lcov --intersect failed:" `grep -E 'ERROR|WARNING' cinter2.log`
fi
for label in cinter1 cinter2 ; do
    if [ -f $label.info ] && ! grep -q -E '^FNL:2c,' $label.info ; then
        fail $label "the intersection lost the flag:" `grep -E '^FNL:' $label.info`
    fi
done

# An unknown letter is a 'format' error, as it is on an 'FNA:' record:  the flags
#   are not an open set, so a reader which does not know one cannot say what the
#   data means
sed -e 's/^FNL:2c,11,15$/FNL:2cz,11,15/' cflag.info > cbad.info
if [ 1 != `grep -c -E '^FNL:2cz,' cbad.info` ] ; then
    fail cbad "the malformed-flag fixture was not built"
fi
checkFail cbadfail \
    "unknown function flag 'z' in .info file record 'FNL:2cz,11,15'" \
    --callgraph -a cbad.info -o cbadfail.info
# ..and ignoring it keeps the function and the letters which were understood:
#   the flags say nothing about any count, so the data is good whatever the
#   letter meant
runWarn cbadok "unknown function flag 'z'" --callgraph -a cbad.info \
    --ignore-errors format --rc max_message_count=10 -o cbadok.info
checkLeaderRecords cbadok cbadok.info <<'EOF'
FNL:0,1,4
FNL:1,6,9
FNL:2c,11,15
EOF

# The flag exists for the sake of this metric and is read by nothing else, so a
#   run which did not ask for callgraph coverage writes none - the same rule the
#   'FNA:' letters follow
runLcov cnocallee -a cflag.info -o cnocallee.info
if [ -f cnocallee.info ] && grep -q -E '^FNL:[0-9]+[a-z]' cnocallee.info ; then
    fail cnocallee "a function flag was written without --callgraph-coverage"
fi

# Now the boundary the user draws.  The fixture is one callgraph across two
#   files:  'lib.c' is the library - 'lib_fn' calls 'lib_helper' - and 'use.c' is
#   the code under test, where 'use_a' calls into the library and 'use_b' calls
#   'use_a'.  Each file keeps a call of its own, so whichever file is taken away
#   the report still has call data and the run is about the flags rather than
#   about the 'empty' error an entirely call-less report raises
cat >proj/lib.c <<'EOF'
int lib_helper(int x)
{
    return x + 2;
}

int lib_fn(int x)
{
    return lib_helper(x) + 1;
}
EOF
cat >proj/use.c <<'EOF'
int use_a(int n)
{
    return lib_fn(n);
}

int use_b(int n)
{
    return use_a(n) + 1;
}
EOF
cat >bnd.info <<'EOF'
TN:format
SF:proj/lib.c
FNL:0,1,4
FNA:0e,1,lib_helper
FNL:1,6,9
FNA:1e,1,lib_fn
FNC:1,8,12,0,1,lib_helper
FNF:2
FNH:2
FNCF:1
FNCH:1
DA:1,1
DA:3,1
DA:6,1
DA:8,1
LF:4
LH:4
end_of_record
TN:format
SF:proj/use.c
FNL:0,1,4
FNA:0e,1,use_a
FNC:0,3,12,0,1,lib_fn
FNL:1,6,9
FNA:1ed,1,use_b
FNC:1,8,12,0,1,use_a
FNF:2
FNH:2
FNCF:2
FNCH:2
DA:1,1
DA:3,1
DA:6,1
DA:8,1
LF:4
LH:4
end_of_record
EOF

# Remove the library:  'use_a' called something which is no longer in the report,
#   so its site goes and the flag is what is left of it.  'use_b' called 'use_a',
#   which is still here, so its site is still a site
runLcov rm_lib --callgraph -o rm_lib.info --remove bnd.info '*/lib.c'
checkLeaderRecords rm_lib rm_lib.info <<'EOF'
FNL:0c,1,4
FNL:1,6,9
EOF
checkCallRecords rm_lib rm_lib.info <<'EOF'
FNC:1,8,12,0,1,use_a
FNCF:1
FNCH:1
EOF
# ..and the call which crossed the other way is not asserted here:  'lib_fn'
#   called 'lib_helper', and both of them left the report together
checkAliasRecords rm_lib rm_lib.info <<'EOF'
FNA:0e,1,use_a
FNA:1ed,1,use_b
EOF

# '--extract' is the same boundary said the other way round
runLcov rm_lib_x --callgraph -o rm_lib_x.info --extract bnd.info '*/use.c'
if [ -f rm_lib_x.info ] && ! diff -u rm_lib.info rm_lib_x.info ; then
    fail rm_lib_x "keeping one file and removing the other disagree"
fi

# The same fixture with the boundary drawn the other way:  the caller leaves, and
#   the callee it called records the crossing instead - the 'x' flag of section
#   10.  One fixture, two boundaries, and each end says the same thing about the
#   same call.  The one call the removed site made is every call 'lib_fn' had,
#   so nothing is deduced
runLcov rm_use --callgraph -o rm_use.info --remove bnd.info '*/use.c'
checkAliasRecords rm_use rm_use.info <<'EOF'
FNA:0e,1,lib_helper
FNA:1ex1,1,lib_fn
EOF
checkLeaderRecords rm_use rm_use.info <<'EOF'
FNL:0,1,4
FNL:1,6,9
EOF

# The flag says that the edge is there, not that it was taken - so the count of
#   the dropped site does not enter into it, exactly as for 'x'.  A site whose
#   count is zero and a site whose count is unknown both leave a 'c' behind, and
#   the same one the taken call above left
for shape in 0 - ; do
    sed -e "s/^FNC:0,3,12,0,1,lib_fn\$/FNC:0,3,12,0,$shape,lib_fn/" \
        bnd.info > untakenout.info
    if [ 1 != `grep -c -E "^FNC:0,3,12,0,[0-],lib_fn\$" untakenout.info` ] ; then
        fail untakenout "the untaken-call fixture was not built"
    fi
    runLcov rm_untakenout --callgraph -o rm_untakenout.info \
        --remove untakenout.info '*/lib.c'
    checkLeaderRecords rm_untakenout rm_untakenout.info <<'EOF'
FNL:0c,1,4
FNL:1,6,9
EOF
    if [ -f rm_lib.info ] && [ -f rm_untakenout.info ] &&
       ! diff -u <(grep -E '^FNL:' rm_lib.info) \
                <(grep -E '^FNL:' rm_untakenout.info) ; then
        fail rm_untakenout "the count of a removed site changed what the flag says"
    fi
done

# '--erase-functions' draws the boundary around a single function, and the answer
#   has to be the one a whole removed file would have given.  Erasing 'lib_fn'
#   puts it outside the report:  'use_a' called it, so 'use_a' is the source of an
#   edge which now leaves the boundary and grows a 'c'; and 'lib_fn' called
#   'lib_helper', which is still here, so 'lib_helper' is the destination of an
#   edge which now enters it and grows an 'x'.  One erasure, both flags, each on
#   whichever end of a call the report kept
runLcov erase_fn --callgraph -o erase_fn.info -a bnd.info \
    --erase-functions '^lib_fn$'
checkAliasRecords erase_fn erase_fn.info <<'EOF'
FNA:0ex1,1,lib_helper
FNA:0e,1,use_a
FNA:1ed,1,use_b
EOF
checkLeaderRecords erase_fn erase_fn.info <<'EOF'
FNL:0,1,4
FNL:0c,1,4
FNL:1,6,9
EOF
checkCallRecords erase_fn erase_fn.info <<'EOF'
FNCF:0
FNCH:0
FNC:1,8,12,0,1,use_a
FNCF:1
FNCH:1
EOF

# ..and the same thing one file along:  erasing 'use_a' leaves 'use_b' calling out
#   of the boundary and 'lib_fn' called from outside it
runLcov erase_use --callgraph -o erase_use.info -a bnd.info \
    --erase-functions '^use_a$'
checkAliasRecords erase_use erase_use.info <<'EOF'
FNA:0e,1,lib_helper
FNA:1ex1,1,lib_fn
FNA:0ed,1,use_b
EOF
checkLeaderRecords erase_use erase_use.info <<'EOF'
FNL:0,1,4
FNL:1,6,9
FNL:0c,6,9
EOF

# ..and a third way of drawing the same boundary, which has to give the same
#   answer:  an exclusion marker on the line 'use_a' is defined on removes the
#   function the way a name pattern does, so the call it made leaves the report
#   with it and 'lib_fn' is again called from outside.
# The marker is on that line alone - not around the body - so the call site at
#   line 3 is not itself in an excluded region:  the only thing which can account
#   for the flag is the removal of the function which held the site
sed -e 's|^int use_a(int n)$|int use_a(int n)    // LCOV_EXCL_LINE|' \
    proj/use.c > proj/use_x.c
if [ 1 != `grep -c -F -e 'LCOV_EXCL_LINE' proj/use_x.c` ] ; then
    fail region_fn "the excluded-function fixture was not built"
fi
sed -e 's|^SF:proj/use.c$|SF:proj/use_x.c|' bnd.info > bndx.info
runLcov region_fn --callgraph -o region_fn.info -a bndx.info --filter region
checkAliasRecords region_fn region_fn.info <<'EOF'
FNA:0e,1,lib_helper
FNA:1ex1,1,lib_fn
FNA:0ed,1,use_b
EOF
checkLeaderRecords region_fn region_fn.info <<'EOF'
FNL:0,1,4
FNL:1,6,9
FNL:0c,6,9
EOF
checkCallRecords region_fn region_fn.info <<'EOF'
FNC:1,8,12,0,1,lib_helper
FNCF:1
FNCH:1
FNCF:0
FNCH:0
EOF

# A call whose two ends were both erased is recorded nowhere:  there is no
#   surviving callee for it to be a fact about, and an unrelated definition of the
#   same name in another file must not answer for a call which never reached it -
#   the rule section 10 pins for a removed file which defined its own callee.
# The fixture is the trivial-function filter rather than a name pattern, because
#   a name pattern erases every definition of the name and would leave none to
#   mark by mistake.  An empty destructor body is the case which really has both:
#   the body is trivial, and the closing brace still calls the destructor of a
#   member - so 'Inner::~Inner' here is erased alongside the 'Outer::~Outer' which
#   calls it, while the out-of-line 'Inner::~Inner' of the other file survives
cat >proj/triv.cpp <<'EOF'
struct Inner
{
    ~Inner() {}
};

struct Outer
{
    Inner i;
    ~Outer() {}
};

Outer make(void);
EOF
cat >proj/other.cpp <<'EOF'
struct Inner
{
    ~Inner();
};

Inner::~Inner()
{
    volatile int x = 1;
    (void)x;
}

void drop(void)
{
    Inner i;
}
EOF
cat >triv.info <<'EOF'
TN:format
SF:proj/triv.cpp
FNL:0,3,3
FNA:0e,1,Inner::~Inner
FNL:1,9,9
FNA:1e,1,Outer::~Outer
FNC:1,9,15,0,1,Inner::~Inner
FNF:2
FNH:2
FNCF:1
FNCH:1
DA:3,1
DA:9,1
LF:2
LH:2
end_of_record
TN:format
SF:proj/other.cpp
FNL:0,6,10
FNA:0ed,2,Inner::~Inner
FNC:0,8,18,0,2,__cxa_guard
FNL:1,12,15
FNA:1ed,1,drop
FNC:1,15,1,0,1,Inner::~Inner
FNF:2
FNH:2
FNCF:2
FNCH:2
DA:6,2
DA:8,2
DA:9,2
DA:12,1
DA:14,1
DA:15,1
LF:6
LH:6
end_of_record
EOF
runLcov triv --callgraph -o triv.info.out -a triv.info --filter trivial
# both functions of 'triv.cpp' are gone, which is what leaves the call between
#   them with no end the report keeps
if [ -f triv.info.out ] &&
   ! grep -q -A 1 -F -e 'SF:proj/triv.cpp' triv.info.out ||
   ! grep -A 1 -F -e 'SF:proj/triv.cpp' triv.info.out |
     grep -q -F -x -e 'FNF:0' ; then
    fail triv "the trivial functions were not erased:" \
        `grep -E '^(SF|FNA):' triv.info.out`
fi
# ..and the definition which survives in the other file is untouched:  the call
#   it did not receive is not a fact about it.  'drop' does call it, from a site
#   which is still there, so the flag it does not have is one which something in
#   this run could have set
checkAliasRecords triv triv.info.out <<'EOF'
FNA:0ed,2,Inner::~Inner
FNA:1ed,1,drop
EOF
# ..where the call 'Inner::~Inner' makes out of the report - to '__cxa_guard',
#   which no file here describes - is its own and is recorded on it, which is the
#   other half of the same assertion:  this run does set the 'c' flag
checkLeaderRecords triv triv.info.out <<'EOF'
FNL:0c,6,10
FNL:1,12,15
EOF
checkCallRecords triv triv.info.out <<'EOF'
FNC:1,15,1,0,1,Inner::~Inner
FNCF:1
FNCH:1
FNCF:0
FNCH:0
EOF

# ----------------------------------------------------------------------
echo "*** 19. what the call site pages say about each kind of caller and callee"
# ----------------------------------------------------------------------
# One fixture with every case on it, which is the enumeration the
#   '--callgraph-coverage' section of the genhtml manual gives.  Each function is
#   on the page of each direction it has anything to say in, and on neither page
#   twice:
#   'leaf'   - called from a site in the report AND from outside it, the crossing
#              asserted by the 'x' flag - and entered more often than the site
#              in the report and the one call the flag counts account for,
#              which the arithmetic deduces on its own:  a row for each site and one
#              '<external and deduced callers>' row counting '1 (1)', all on
#              the callers page.
#              It calls nothing, so it is not on the callees page at all.
#   'caller' - called from outside the report, with nothing asserting it:  the
#              function was entered more often than its listed callers account
#              for, which is all the '<deduced external callers>' row and its
#              parenthesized count claim.  It calls 'leaf', which is in the
#              report, and 'puts', which is not, so it is on both pages.
#   'lonely' - calls nothing but 'puts', so its callees row is the
#              '<external callee>' row and nothing else:  the crossing is the
#              whole of what it has to say, and a function which has that to say
#              is not dropped.  It was entered once by nobody the report names, so
#              its callers row is the '<deduced external callers>' one, counting
#              '(1)'.
#   'quiet'  - never entered, called by nothing, and its one call out of the
#              report was never made:  the flag says that the edge is there and
#              not that it was taken, so the crossing is recorded anyway and it
#              keeps its callees row.  Nothing at all is known about its callers,
#              not even that they are outside, so the callers page leaves it out.
#   'dead'   - never entered and called by nothing, but it does contain a call to
#              a function the report has:  the callees page and not the callers
#              page, and the mirror image of 'leaf'.
cat >proj/rows.c <<'EOF'
int leaf(int x)
{
    return x + 1;
}

int caller(int n)
{
    return leaf(n) + puts("x");
}

int lonely(int n)
{
    return puts("y") + n;
}

int quiet(int n)
{
    return puts("z") + n;
}

int dead(int n)
{
    return leaf(n) - 1;
}
EOF
cat >rows.info <<'EOF'
TN:format
SF:proj/rows.c
FNL:0,1,4
FNA:0ex1,3,leaf
FNL:1,6,9
FNA:1e,1,caller
FNC:1,8,12,0,1,leaf
FNC:1,8,22,0,1,puts
FNL:2,11,14
FNA:2e,1,lonely
FNC:2,13,12,0,1,puts
FNL:3,16,19
FNA:3e,0,quiet
FNC:3,18,12,0,0,puts
FNL:4,21,24
FNA:4e,0,dead
FNC:4,23,12,0,0,leaf
FNF:5
FNH:3
FNCF:5
FNCH:3
DA:1,3
DA:3,3
DA:6,1
DA:8,1
DA:11,1
DA:13,1
DA:16,0
DA:18,0
DA:21,0
DA:23,0
LF:10
LH:6
end_of_record
EOF
runGenhtml rows --callgraph -o html_rows rows.info
ROWCALLEES=html_rows/proj/rows.c.callees.html
ROWCALLERS=html_rows/proj/rows.c.callers.html
if [ ! -f $ROWCALLEES ] || [ ! -f $ROWCALLERS ] ; then
    fail rows "a call site page was not written"
else
    # one row per case, and no more:  a second '<external callee>' row on one
    #   function would be the same fact said twice.  Each label is on the page of
    #   the direction it is a fact about, and nowhere else
    for pair in "$ROWCALLEES:$EXTCALLEE:3" "$ROWCALLEES:$EXTCALLER:0" \
                "$ROWCALLEES:$DEDUCED:0" "$ROWCALLEES:$DEDUCEDEXT:0" \
                "$ROWCALLERS:$EXTCALLEE:0" "$ROWCALLERS:$EXTCALLER:0" \
                "$ROWCALLERS:$DEDUCEDEXT:1" "$ROWCALLERS:$DEDUCED:2" \
                "$ROWCALLEES:$EXTROW:0" "$ROWCALLEES:$DEDUCEDROW:0" \
                "$ROWCALLEES:$BOTHROW:0" "$ROWCALLERS:$EXTROW:0" \
                "$ROWCALLERS:$BOTHROW:1" "$ROWCALLERS:$DEDUCEDROW:2" ; do
        page=${pair%%:*}
        note=${pair#*:}
        want=${note##*:}
        note=${note%:*}
        got=`grep -c -E -e "$note" $page`
        if [ "$want" != "$got" ] ; then
            fail rows "expected $want of '$note' in $page, got $got"
        fi
    done
    # ..and each function is on the pages the enumeration above says it is on
    for pair in "leaf:callers" "caller:callers callees" "lonely:callers callees" \
                "quiet:callees" "dead:callees" ; do
        func=${pair%%:*}
        want=" ${pair#*:} "
        for dir in callers callees ; do
            page=html_rows/proj/rows.c.$dir.html
            case "$want" in
                *" $dir "*)
                    if ! grep -q -F -e "id=\"func_$func\"" $page ; then
                        fail rows "'$func' has no row in $page"
                    fi
                    ;;
                *)
                    if grep -q -F -e "id=\"func_$func\"" $page ; then
                        fail rows "'$func' has nothing to say in $page and a" \
                            "row in it"
                    fi
                    ;;
            esac
        done
    done
    # 'quiet' is on the callees page for the sake of one crossing and nothing else:
    #   the count of the site it lost does not come into that, so what is left is
    #   the crossing alone
    if ! grep -A 4 -F -e 'id="func_quiet"' $ROWCALLEES |
         grep -q -F -e "$EXTCALLEE" ; then
        fail rows "the row of 'quiet' does not name the crossing:"
        grep -A 4 -F -e 'id="func_quiet"' $ROWCALLEES
    fi
    # The '<external callee>' row has no call site, no category and no count:
    #   the site which carried all three is what was dropped, and inventing any
    #   of them would be claiming something the report does not know
    if grep -A 2 -F -e "$EXTCALLEE" $ROWCALLEES |
       grep -E -e 'coverCallgraph(Hi|Lo|Unknown)|href=' ; then
        fail rows "the '<external callee>' row carries a count or a link"
    fi
    # ..where the caller-side row does have a count when the arithmetic gives
    #   one:  'leaf' was entered 3 times, the site in the report accounts for
    #   1 of them and the flag for 1 more, so 2 calls came from outside it - one
    #   asserted and one deduced
    if ! grep -q -E -e 'class="coverCallgraphHi" title="[^"]*">1&nbsp;\(1\)</td>' \
         $ROWCALLERS ; then
        fail rows "the '<external and deduced callers>' row does not" \
            "carry the flagged and deduced calls:"
        grep -A 4 -F -e "$BOTHROW" $ROWCALLERS
    fi
    # ..and every label and note on either page is a fact about the boundary or
    #   about the absence of data, so each says so on hover rather than leaving
    #   the reader to guess what the brackets mean.  Matched a clause at a time:
    #   a reworded message fails here, which is the point - these strings are the
    #   whole of what the page tells a reader who hovers
    for pair in "$ROWCALLERS:at least one call site outside the callgraph boundary calls this function" \
                "$ROWCALLEES:calls at least one function which is outside the callgraph boundary" \
                "$ROWCALLERS:this function was entered more often than the call sites in this report account for" \
                "$ROWCALLERS:In addition, this function was entered more often" \
                "$ROWCALLERS:2 calls:  1 from call sites outside the callgraph boundary and (1) deduced" ; do
        if ! grep -q -F -e "${pair#*:}" ${pair%%:*} ; then
            fail rows "${pair%%:*} does not explain '${pair#*:}'"
        fi
    done
fi

# ----------------------------------------------------------------------
echo "*** 20. the '--unreachable-script' callback removing a call site"
# ----------------------------------------------------------------------
# The callback is asked about each coverage type in turn, and 'callgraph' is the
#   type which offers it the call sites.  Unlike the branch and MC/DC types it
#   removes rather than marks:  a site carries no vector of outcomes for a mark
#   to sit on, so a call the user says does not belong in the report is simply
#   not in it.
# Which is why the callback is asked once for the whole file rather than once per
#   testcase, as the other two types are:  a second pass over the same source
#   would be asking about sites which are already gone.  The two-testcase run
#   below is what pins that.
# 'scripts/unreach.pm' is the shipped sample, and the annotation it reads is
#   'LCOV_EXCLUDE_CALL', optionally naming the callee and the column:  here the
#   call to 'other' on line 13, and the second of the two calls to 'helper' on
#   line 14 - the one at column 22, which is what the column is for.
cat >proj/u.c <<'EOF'
int helper(int x)
{
    return x + 1;
}

int other(int x)
{
    return x - 1;
}

int caller(int n)
{
    int r = helper(n) + other(n);    // LCOV_EXCLUDE_CALL other
    r += helper(n) + helper(r);      // LCOV_EXCLUDE_CALL helper,22
    return r;
}
EOF

cat >u.info <<'EOF'
TN:format
SF:proj/u.c
FNL:0,1,4
FNA:0,4,helper
FNL:1,6,9
FNA:1d,1,other
FNL:2,11,16
FNA:2d,1,caller
FNC:2,13,13,0,1,helper
FNC:2,13,25,0,1,other
FNC:2,14,10,0,1,helper
FNC:2,14,22,0,2,helper
FNF:3
FNH:3
FNCF:4
FNCH:4
DA:1,4
DA:3,4
DA:6,1
DA:8,1
DA:11,1
DA:13,1
DA:14,1
DA:15,1
DA:16,1
LF:9
LH:9
end_of_record
EOF

UNREACH="--unreachable-script $SCRIPT_DIR/unreach.pm"

runLcov cb --callgraph -a u.info -o cb.info $UNREACH -v
checkCallRecords cb cb.info <<'EOF'
FNC:2,13,13,0,1,helper
FNC:2,14,10,0,1,helper
FNCF:2
FNCH:2
EOF
# Each removal is reported at '--verbose':  a call which leaves the report
#   without the user being able to see it go is how a misspelled callee name
#   turns into a coverage rate nobody can account for
for site in "call to 'other' at 13:25:0" "call to 'helper' at 14:22:0" ; do
    if [ -f cb.log ] && ! grep -q -F -e "excluded $site" cb.log ; then
        fail cb "the callback's removal of the $site was not reported:"
        grep -F -e 'excluded' cb.log
    fi
done
# ..and counted, which is the summary the script prints for every type it
#   handles.  Two calls on two different lines
if [ -f cb.log ] && ! grep -q -F -e 'Excluded 2 calls from 2 lines.' cb.log ; then
    fail cb "the callback did not report what it excluded:"
    grep -F -e 'Excluded' cb.log
fi
# Both totals went with the sites:  'FNCF' and 'FNCH' each lost the two calls
#   which are gone, above.  An excluded coverpoint is outside the boundary of the
#   report by definition, so the report cannot say that either of those calls was
#   made - and cannot say that it was not either, which is why neither of them is
#   left in 'found' as a call to be accounted for.
# What does survive is a fact about the callees, which are both still here:  each
#   excluded call was taken, so it reached its callee from a site which is no
#   longer in the report, and the callee is marked as having been called from
#   outside it ('x'), with the count of the calls the excluded site made.
#   Their own execution counts are untouched - those count entries, not call
#   sites - and the surviving sites and the flag together account for all of
#   them, so neither callee is deduced to have another caller
checkAliasRecords cb cb.info <<'EOF'
FNA:0x2,4,helper
FNA:1x1,1,other
FNA:2d,1,caller
EOF
# ..on the alias, and not on the leader:  the flag of an 'FNL:' record says that
#   this function called something outside the report, which 'caller' did not -
#   both of the callees it lost a call to are in the report;  it is the call
#   sites which are not
checkLeaderRecords cb cb.info <<'EOF'
FNL:0,1,4
FNL:1,6,9
FNL:2,11,16
EOF

# ..which is then what the report is able to say out loud.  The last row of the
#   callers table of each of those two functions names the crossing, where the
#   same arithmetic without the flag would only support the weaker
#   '<deduced external callers>' - which is what 'caller' itself still gets,
#   having been entered once by something no site in the report accounts for
runGenhtml cbhtml --callgraph -o html_cb cb.info
CBPAGE=html_cb/proj/u.c.callers.html
if [ ! -f $CBPAGE ] ; then
    fail cbhtml "no call site page was written"
else
    for pair in "$DEDUCEDEXT:0" "$DEDUCED:1" "$EXTCALLER:2" "$BOTHROW:0" \
                "$DEDUCEDROW:1" "$EXTROW:2" ; do
        note=${pair%:*}
        want=${pair##*:}
        got=`grep -c -E -e "$note" $CBPAGE`
        if [ "$want" != "$got" ] ; then
            fail cbhtml "expected $want of '$note' on the page, got $got"
        fi
    done
    # The count on the row is the calls the excluded site made:  'helper' was
    #   entered 4 times, its two surviving sites account for 2 of them and the
    #   excluded one for the other 2
    if ! grep -q -E -e 'class="coverCallgraphHi" title="[^"]*">2</td>' \
         $CBPAGE ; then
        fail cbhtml "the '<external callers>' row does not carry the count of" \
            "the excluded site:"
        grep -A 4 -F -e "$EXTROW" $CBPAGE
    fi
fi

# An excluded site which was never taken leaves the same thing behind:  the site
#   goes, 'found' loses it, 'hit' never had it, and the callee is marked as having
#   a caller outside the report, because the flag says that the edge is there and
#   not that it was taken - 'x0', a call site which made no calls.  Here the excluded call to 'other' was never made and
#   'other' was never entered, while line 14 keeps its annotation off so that the
#   taken call is not what is being measured
sed -e 's| *// LCOV_EXCLUDE_CALL helper,22$||' proj/u.c > proj/uzero.c
if [ 1 != `grep -c -F -e 'LCOV_EXCLUDE_CALL' proj/uzero.c` ] ; then
    fail cbzero "the untaken-call fixture was not built"
fi
cat >uzero.info <<'EOF'
TN:format
SF:proj/uzero.c
FNL:0,1,4
FNA:0,4,helper
FNL:1,6,9
FNA:1,0,other
FNL:2,11,16
FNA:2d,1,caller
FNC:2,13,13,0,1,helper
FNC:2,13,25,0,0,other
FNC:2,14,10,0,1,helper
FNC:2,14,22,0,2,helper
FNF:3
FNH:2
FNCF:4
FNCH:3
DA:1,4
DA:3,4
DA:6,0
DA:8,0
DA:11,1
DA:13,1
DA:14,1
DA:15,1
DA:16,1
LF:9
LH:7
end_of_record
EOF
runLcov cbzero --callgraph -a uzero.info -o cbzero.info $UNREACH
checkCallRecords cbzero cbzero.info <<'EOF'
FNC:2,13,13,0,1,helper
FNC:2,14,10,0,1,helper
FNC:2,14,22,0,2,helper
FNCF:3
FNCH:3
EOF
checkAliasRecords cbzero cbzero.info <<'EOF'
FNA:0,4,helper
FNA:1x0,0,other
FNA:2d,1,caller
EOF

# Both names are optional, and an annotation with nothing after it excludes every
#   call written on the line:  the two calls of line 13 here, where the run above
#   named one of them.  Line 14 keeps its annotation off and both of its calls,
#   which is what shows that the whole-line form is about the line it is on
sed -e 's|// LCOV_EXCLUDE_CALL other$|// LCOV_EXCLUDE_CALL|' \
    -e 's| *// LCOV_EXCLUDE_CALL helper,22$||' proj/u.c > proj/uall.c
if [ 1 != `grep -c -E -e '// LCOV_EXCLUDE_CALL$' proj/uall.c` ] ; then
    fail cball "the whole-line fixture was not built"
fi
sed -e 's|^SF:proj/u.c$|SF:proj/uall.c|' u.info > uall.info
runLcov cball --callgraph -a uall.info -o cball.info $UNREACH
checkCallRecords cball cball.info <<'EOF'
FNC:2,14,10,0,1,helper
FNC:2,14,22,0,2,helper
FNCF:2
FNCH:2
EOF

# An annotation which matches nothing is not an error.  The site it names may
#   already have been removed by a filter, or by a run whose data this one is
#   being merged with, and a call which is not in the report is the outcome the
#   annotation asked for either way
sed -e 's|// LCOV_EXCLUDE_CALL other$|// LCOV_EXCLUDE_CALL nosuch|' \
    proj/u.c > proj/unone.c
sed -e 's|^SF:proj/u.c$|SF:proj/unone.c|' u.info > unone.info
runLcov cbnone --callgraph -a unone.info -o cbnone.info $UNREACH
checkCallRecords cbnone cbnone.info <<'EOF'
FNC:2,13,13,0,1,helper
FNC:2,13,25,0,1,other
FNC:2,14,10,0,1,helper
FNCF:3
FNCH:3
EOF

# Two testcases, one file.  A site lives in each testcase's map as well as in the
#   summary, so a removal which reached only one of them would be a report whose
#   totals disagreed with its tables - and a callback which was asked once per
#   testcase would be asked a second time about a site it had already taken.
#   The answer is the one-testcase answer in each of the two sections the writer
#   then produces
sed -e 's/^TN:format$/TN:t2/' u.info > u2.info
cat u.info u2.info > utwo.info
runLcov cbtwo --callgraph -a utwo.info -o cbtwo.info $UNREACH
checkCallRecords cbtwo cbtwo.info <<'EOF'
FNC:2,13,13,0,1,helper
FNC:2,14,10,0,1,helper
FNCF:2
FNCH:2
FNC:2,13,13,0,1,helper
FNC:2,14,10,0,1,helper
FNCF:2
FNCH:2
EOF
if [ -f cbtwo.log ] &&
   ! grep -q -F -e 'Excluded 2 calls from 2 lines.' cbtwo.log ; then
    fail cbtwo "the callback was not asked exactly once for the file:"
    grep -F -e 'Excluded' cbtwo.log
fi
# ..and the mark on the callees is in both sections, which is the same answer
#   said once per testcase:  the writer writes each section out of that
#   testcase's own function data, so a mark which reached only the summary would
#   be written by a one-testcase report and lost by this one
checkAliasRecords cbtwo cbtwo.info <<'EOF'
FNA:0x2,4,helper
FNA:1x1,1,other
FNA:2d,1,caller
FNA:0x2,4,helper
FNA:1x1,1,other
FNA:2d,1,caller
EOF

# A callback which throws is the user's bug, and the error names the call which
#   failed - argument order included, which is what the user debugging it will
#   read the callback's own signature against.  Ignored, the file is left as the
#   callback found it:  nothing it might have half done is counted as a change
cat >diecb.pm <<'PERL'
package diecb;

sub new
{
    my $class = shift;
    return bless [], $class;
}
sub start { }
sub end   { }

sub exclude
{
    my ($self, $type) = @_;
    die("diecb cannot decide about '$type'\n");
}

1;
PERL
DIECB="--unreachable-script ./diecb.pm"
checkFail cbdie \
    '"unreachable" callback diecb->exclude(callgraph, readSrc, perTestDB, summaryDB) failed:' \
    --callgraph -a u.info -o cbdie.info $DIECB
runWarn cbdieok 'diecb cannot decide' --callgraph -a u.info -o cbdieok.info \
    $DIECB --ignore callback
checkCallRecords cbdieok cbdieok.info <<'EOF'
FNC:2,13,13,0,1,helper
FNC:2,13,25,0,1,other
FNC:2,14,10,0,1,helper
FNC:2,14,22,0,2,helper
FNCF:4
FNCH:4
EOF

# The sample callback answers only for the coverpoint types which are enabled,
#   so a run with none of them enabled is one where it can have no effect - which
#   is a mistake in the command line, not something to do silently
NOTYPE="--rc branch_coverage=0 --rc mcdc_coverage=0 --rc callgraph_coverage=0"
checkFail cbnotype '--unreachable-script has no effect without' \
    -a u.info -o cbnotype.info $NOTYPE $UNREACH
runWarn cbnotypeok '--unreachable-script has no effect without' \
    -a u.info -o cbnotypeok.info $NOTYPE $UNREACH --ignore usage

# ----------------------------------------------------------------------
echo "*** 21. the caller side names the row the callee side numbers"
# ----------------------------------------------------------------------
# The two tables of the call site page are two views of the same sites, and the
#   'called from' row of a callee links to the row of the group the call is in -
#   so the two have to agree about which row that is.  The numbering is the
#   position of the row in its group, and a group whose location has more than one
#   destination is where there is something to get wrong: the callee side has to
#   name row 2 of the group for the second destination and row 1 for the first.
# The caller's numbering is read out of an index built from its own sites, kept
#   for as long as it is worth keeping, since a function which calls many things
#   is a caller on the page of every file it calls into.  What is kept cannot
#   change an answer, so the whole page is rendered a second time with the index
#   held to nothing - LCOV_CALLSITE_INDEX_LIMIT, which is to this what
#   LCOV_FORCE_PARALLEL is to the fork paths - and the two have to be the same
#   page
cat >proj/hub.cpp <<'EOF'
struct S { virtual int f(int x) { return x; } };
struct T : S { int f(int x) { return x + 1; } };

int one(int x)
{
    return x + 1;
}

int hub(S* s, int n)
{
    return s->f(n) + one(n);
}

int also(int n)
{
    return one(n) + 1;
}
EOF

# 11:15 is 'f', which dispatches to either override, and 11:22 is 'one':  a
#   caller with two groups, one of which has two rows.  'also' is a second
#   caller of 'one', so the index is asked about more than one function and the
#   page has a callee whose two rows are numbered out of two different callers
cat >hub.info <<'EOF'
TN:format
SF:proj/hub.cpp
FNL:0,1,1
FNA:0,2,S::f
FNL:1,2,2
FNA:1,1,T::f
FNL:2,4,7
FNA:2,4,one
FNL:3,9,12
FNA:3,3,hub
FNC:3,11,15,0,2,S::f
FNC:3,11,15,1,1,T::f
FNC:3,11,22,0,3,one
FNL:4,14,17
FNA:4,1,also
FNC:4,16,12,0,1,one
FNF:5
FNH:5
FNCF:4
FNCH:4
DA:1,2
DA:2,1
DA:4,4
DA:6,4
DA:9,3
DA:11,3
DA:14,1
DA:16,1
LF:8
LH:8
end_of_record
EOF

runGenhtml hub --callgraph -o html_hub hub.info
HUBCALLERS=html_hub/proj/hub.cpp.callers.html
HUBCALLEES=html_hub/proj/hub.cpp.callees.html
if [ ! -f $HUBCALLERS ] || [ ! -f $HUBCALLEES ] ; then
    fail hub "a call site page was not written"
else
    # Row order within a group is by callee symbol, so 'S::f' is row 1 of the
    #   group at 11:15 and 'T::f' row 2 - and the calls to 'one' are each row 1
    #   of their own group, there being one destination in each to be.  The row
    #   number is what a caller row on the other page links to, so that a location
    #   with two destinations does not land the reader on the wrong one
    for anchor in site_11_15_1 site_11_15_2 site_11_22_1 site_16_12_1 ; do
        if ! grep -q -F -e "#$anchor\"" $HUBCALLERS ; then
            fail hub "no caller row links to '$anchor':"
            grep -o -E '#site_[0-9_]+"' $HUBCALLERS
        fi
    done
    # ..and each of those rows is on the other page, under the anchor of its group
    for anchor in site_11_15 site_11_22 site_16_12 ; do
        if ! grep -q -F -e "id=\"$anchor\"" $HUBCALLEES ; then
            fail hub "the group '$anchor' the callers page links to is not there"
        fi
    done
fi

# hovering over a call site lists what it leads to, one 'count: name' line per
#   destination with the counts right-aligned, so that the names start in one
#   column.  The list is the attribute, drawn by CSS:  text in the source line
#   would come back from 'html2lcov' as source
sed -e 's/^FNA:0,2,S::f$/FNA:0,12,S::f/' -e 's/^DA:1,2$/DA:1,12/' \
    -e 's/^FNC:3,11,15,0,2,S::f$/FNC:3,11,15,0,12,S::f/' hub.info > hubwide.info
runGenhtml hubwide --callgraph -o html_hubwide hubwide.info
if ! grep -q -F -e '<a class="callSite" href="hub.cpp.callees.html#site_11_15" data-calls="12: S::f&#10; 1: T::f">f</a><span class="calleeMulti" data-n="2"></span>' \
        html_hubwide/proj/hub.cpp.gcov.html ; then
    fail hubwide "the site does not list its calls:" \
        `grep -o -E 'data-calls="[^"]*"' html_hubwide/proj/hub.cpp.gcov.html`
fi
if ! grep -q -F -e 'a[data-calls]:hover::after' html_hubwide/gcov.css ; then
    fail hubwide "no style draws the list"
fi

# the numbering is memoized per calling function, and dropped once it
#   covers more sites than the limit.  At limit 0 it is dropped as soon as a
#   second caller is asked about ('also' here), so this run is the one where
#   every lookup is a fresh computation - and the page must not care
LCOV_CALLSITE_INDEX_LIMIT=0 runGenhtml hubnoindex --callgraph -o html_hub0 \
    hub.info
for page in callers callees ; do
    HUBPAGE=html_hub/proj/hub.cpp.$page.html
    HUBPAGE0=html_hub0/proj/hub.cpp.$page.html
    if [ -f $HUBPAGE ] && [ -f $HUBPAGE0 ] ; then
        # everything but the line which says when the report was made, which is
        #   the one thing two runs of the same input do not agree about
        if ! diff -u <(grep -v -E 'headerValue">[0-9]{4}-' $HUBPAGE) \
            <(grep -v -E 'headerValue">[0-9]{4}-' $HUBPAGE0) ; then
            fail hubnoindex \
                "the $page page depends on what the site index kept"
        fi
    fi
done

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'format_3' $LOCAL_COVERAGE 0
fi

exit $STATUS
