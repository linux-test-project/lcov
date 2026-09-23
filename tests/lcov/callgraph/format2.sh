#! /usr/bin/env bash

# Call sites in the '.info' file:  the 'FNC:' record, and the reader and writer
# of it - part 2 of 3.
#
# The former monolithic 'format.sh' ran 20 scenarios over the same hand-written
# tracefiles, which is the longest single test in the suite under '--coverage'.
# The scenarios keep their original numbering here:  'format1.sh' runs 1 to 8,
# 'format2.sh' 9 to 14, 'format3.sh' 15 to 21, so a cross-reference to a section
# number still finds it.  The discussion of the record itself, the helpers and
# the two fixtures which more than one part reads are in 'setup_common.sh'; each
# part runs in its own working directory (format2.d), so the three cannot
# collide.

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf format2.d
    exit 0
fi

WORKDIR=format2.d
source ./setup_common.sh

# ----------------------------------------------------------------------
echo "*** 9. how the callers of a callee relate to the calls it received"
# ----------------------------------------------------------------------
# Every site in the report which named a symbol is on its caller list, with the
#   file it is in and the count it was taken:  those are known exactly, and the
#   callee's linkage has nothing to do with it - the record is written by the
#   *caller's* translation unit.
# What cannot be known is who made the REST of the calls.  The symbol's own
#   execution count is the number of times it was entered from anywhere, so the
#   difference is calls which came from outside anything this report describes -
#   an uncaptured translation unit, a call through a function pointer or a
#   virtual dispatch, or the runtime itself.  That count is known and its origin
#   is not, which is exactly the distinction the classification draws.
# Derived from data the report already carries, so it needs no record of its own
#   and is right after any merge (see lcovutil::classify_callers).
runGenhtml genhtml_link --callgraph -o html_link link.info
# ..and the two rows which name a crossing of the boundary outright - the label
#   of the last row of either table, and the count cell which says what it is
#   made of.  Section 18 reaches for those too, so $EXTCALLER and $EXTCALLEE
#   come from 'setup_common.sh'.
# ..and the note beside a function's own name, which says the same thing about all
#   of its call sites at once:  which side of the boundary its callers are on, for
#   a reader going down the page rather than reading one function's rows
EXTONLY='>external callers only<'
BOTHWAYS='>internal and external callers<'
MAYBEEXT='>callers may be outside the callgraph boundary<'
# ..each of which is a summary of a whole function's rows, so each says on hover
#   what it summarizes.  Matched a clause at a time rather than by a keyword:
#   the wording is the whole of the explanation the reader gets
EXTONLY_WHY='its only callers are outside the callgraph boundary'
BOTHWAYS_WHY='this function is named both by a call site within the callgraph'
MAYBEEXT_WHY='impossible to tell whether any call came from outside the callgraph boundary'
checkNotes()
{
    # checkNotes label page <external> <both> <undecided>
    #   how many functions of a page carry each of the three notes
    local label=$1
    local page=$2
    shift 2
    local notes=("$EXTONLY" "$BOTHWAYS" "$MAYBEEXT")
    local whys=("$EXTONLY_WHY" "$BOTHWAYS_WHY" "$MAYBEEXT_WHY")
    local i
    for i in 0 1 2 ; do
        local want=$1
        shift
        local got=`grep -c -F -e "${notes[$i]}" $page`
        if [ "$want" != "$got" ] ; then
            fail $label "expected $want of '${notes[$i]}' in $page, got $got"
        elif [ 0 != "$want" ] && ! grep -q -F -e "${whys[$i]}" $page ; then
            fail $label "'${notes[$i]}' in $page does not explain itself:" \
                "'${whys[$i]}' is not there"
        fi
    done
}
if [ ! -f html_link/proj/glob.c.callers.html ] ; then
    fail genhtml_link "no call site view was written"
else
    # 'f' was entered 4 times and its one call site accounts for all 4, so every
    #   caller is known and there is no remainder to show.  'g' was entered 6
    #   times and its one site accounts for 2, so 4 calls came from somewhere this
    #   report cannot name:  a caller deduced from the arithmetic, since nothing
    #   in the data names one
    if [ 1 != `grep -c -E -e "$DEDUCED" html_link/proj/glob.c.callers.html` ] ||
       [ 1 != `grep -c -F -e "$DEDUCEDROW" html_link/proj/glob.c.callers.html` ]
    then
        fail genhtml_link "expected exactly one function with a deduced" \
            "caller in glob.c:" \
            `grep -c -E -e "$DEDUCED" -e "$DEDUCEDROW" \
                html_link/proj/glob.c.callers.html`
    fi
    if ! grep -q -E -e 'class="coverCallgraphHi" title="[^"]*">\(4\)</td>' \
         html_link/proj/glob.c.callers.html ; then
        fail genhtml_link "the count of the calls from elsewhere is not 4"
    fi
    # ..and it is set like the call site counts beside it:  a report which is not
    #   coloured by category has no category cells for it to look like
    if grep -q -F -e 'callgraphTlaCount' html_link/proj/glob.c.callers.html ; then
        fail genhtml_link "a count is styled after category cells which are not there"
    fi
    # 'k' was called from a site whose count is unknown, so whether ANY call came
    #   from elsewhere cannot be decided.  Nothing outside was seen and nothing can
    #   be deduced, so there is no caller row to write - the note beside the name
    #   is what says it cannot be told
    if ! grep -q -F -e \
        "impossible to tell whether any call came from outside the callgraph boundary" \
        html_link/proj/glob.c.callers.html ; then
        fail genhtml_link "an undecidable remainder is not explained"
    fi
    if grep -q -E -e "$EXTCALLER" -e "$DEDUCEDEXT" -e "$EXTROW" -e "$BOTHROW" \
        html_link/proj/glob.c.callers.html ; then
        fail genhtml_link "an unflagged function claims an external caller"
    fi
    # ..and the same three answers beside the three names, where the reader of the
    #   page meets them without adding up rows:  'f' is called from this report
    #   and from nowhere else, which its rows already say, so it says nothing;
    #   'g' is called both ways;  'k' cannot be told
    checkNotes genhtml_link html_link/proj/glob.c.callers.html 0 1 1
fi
# 'h' is called by nothing in the report and was entered anyway - the shape of
#   'main', of a function pointer, and of a caller in an uncaptured unit.  Its
#   caller side exists for the sake of that one row, which is the whole point:
#   "called, and by nothing here" is a fact about the callee worth saying - and
#   the note beside its name is the same fact in the words the metric asks for
if [ -f html_link/proj/call.c.callers.html ] ; then
    if ! grep -q -E -e "$DEDUCED" html_link/proj/call.c.callers.html ; then
        fail genhtml_link "a callee with no known caller has no caller row"
    fi
    checkNotes genhtml_link html_link/proj/call.c.callers.html 1 0 0
fi
# ..while a symbol which was never entered and has no call site has nothing to
#   say, and gets no table at all.  'stat.c' holds nothing else, so it gets
#   neither call site page - and its function view must not link to one
for dir in callers callees ; do
    if [ -f html_link/proj/stat.c.$dir.html ] ; then
        fail genhtml_link "a function which was never called grew a $dir table"
    fi
done
for page in stat.c.gcov.html stat.c.func.html ; do
    if [ ! -f html_link/proj/$page ] ; then
        fail genhtml_link "no $page was written"
    elif grep -q -E 'stat.c.call(ers|ees).html' html_link/proj/$page ; then
        fail genhtml_link "$page links to a call site page which does not exist"
    fi
done
# ..whereas a file which does have call site detail names it in every view of
#   the file, a link per direction it has anything to say in - with the entry for
#   the page you are on the one which is not a link, and the filename itself the
#   way back to the source.
# 'glob.c' defines nothing which calls anything, so the one direction it has is
#   the callers of its functions and the one link is to that page:  a header names
#   the pages which exist, which is the same rule the pages themselves follow
LINKED_FUNC='<a href="glob.c.func-c.html" title="Click to go to function table">functions</a>'
LINKED_CALLERS='<a href="glob.c.callers.html" title="Click to go to the callers of the functions of this file">callers</a>'
SOURCE_BACK='<a href="glob.c.gcov.html" title="Click to go to source detail">glob.c</a>'
if ! grep -q -F -e "($LINKED_FUNC / $LINKED_CALLERS)" \
        html_link/proj/glob.c.gcov.html ; then
    fail genhtml_link "the source view does not link to the callers page:" \
        `grep -o -E '\(<?a?[^)]*\)' html_link/proj/glob.c.gcov.html`
fi
if ! grep -q -F -e "$SOURCE_BACK<span" html_link/proj/glob.c.func.html ||
   ! grep -q -F -e "(functions / $LINKED_CALLERS)" \
        html_link/proj/glob.c.func.html ; then
    fail genhtml_link "the function view header is wrong:" \
        `grep -o -E 'proj</a> - .*</td>' html_link/proj/glob.c.func.html`
fi
if ! grep -q -F -e "$SOURCE_BACK<span" html_link/proj/glob.c.callers.html ||
   ! grep -q -F -e "($LINKED_FUNC / callers)" \
        html_link/proj/glob.c.callers.html ; then
    fail genhtml_link "the call site view header is wrong:" \
        `grep -o -E 'proj</a> - .*</td>' html_link/proj/glob.c.callers.html`
fi
# ..and 'call.c' is the file which has both directions:  'h' calls three functions
#   and is called by nothing the report names, so every view of it offers all four
#   pages and each one leaves its own name plain
CALL_FUNC='<a href="call.c.func-c.html" title="Click to go to function table">functions</a>'
CALL_CALLERS='<a href="call.c.callers.html" title="Click to go to the callers of the functions of this file">callers</a>'
CALL_CALLEES='<a href="call.c.callees.html" title="Click to go to the callees of the functions of this file">callees</a>'
for page in "gcov:$CALL_FUNC / $CALL_CALLERS / $CALL_CALLEES" \
    "func:functions / $CALL_CALLERS / $CALL_CALLEES" \
    "callers:$CALL_FUNC / callers / $CALL_CALLEES" \
    "callees:$CALL_FUNC / $CALL_CALLERS / callees" ; do
    if ! grep -q -F -e "(${page#*:})" html_link/proj/call.c.${page%%:*}.html ; then
        fail genhtml_link "the ${page%%:*} header of call.c is wrong:" \
            `grep -o -E 'proj</a> - .*</td>' html_link/proj/call.c.${page%%:*}.html`
    fi
done

# The 'x' flag is the other way a call from outside the report is known:  not a
#   count the known sites do not account for, but the callee's own record that a
#   call site which this report cannot name is one of its callers.  It is evidence
#   where the remainder is inference, so it decides both of the cases the
#   arithmetic gets wrong on its own.
# 'k' is called from a site whose count is unknown, so the remainder is
#   undecidable - and "something the report cannot name called it" is not
#   undecidable at all.  'f' is exactly accounted for by its one site, and the
#   flag says that its sites are nevertheless not the whole story.  Neither of
#   them can say HOW MANY such calls there were:  those calls are inside the
#   execution count which the known sites already cover, so the row has no number
runGenhtml genhtml_xlink --callgraph -o html_xlink xlink.info
if [ ! -f html_xlink/proj/glob.c.callers.html ] ; then
    fail genhtml_xlink "no call site view was written"
else
    # 'f' and 'k' by the flag, 'g' by its remainder - and the row says which,
    #   because the two are not the same claim:  the flag is evidence that an edge
    #   crosses the boundary of the report, where a remainder only says that
    #   whoever made the rest of the calls is not in it
    if [ 2 != `grep -c -E -e "$EXTCALLER" html_xlink/proj/glob.c.callers.html` ] ; then
        fail genhtml_xlink "expected two flagged callees:" \
            `grep -c -E -e "$EXTCALLER" html_xlink/proj/glob.c.callers.html`
    fi
    if [ 1 != `grep -c -E -e "$DEDUCED" html_xlink/proj/glob.c.callers.html` ] ; then
        fail genhtml_xlink "expected one function whose remainder is all there is:" \
            `grep -c -E -e "$DEDUCED" html_xlink/proj/glob.c.callers.html`
    fi
    if [ 2 != `grep -c -F -e \
        "call site outside the callgraph boundary calls this function" \
        html_xlink/proj/glob.c.callers.html` ] ; then
        fail genhtml_xlink "the flagged callees do not say why their count is" \
            "unknown"
    fi
    # ..and the undecidable-remainder wording is gone:  it was the answer for
    #   'k' only for as long as nothing else was known about it
    if grep -q -F -e \
        "impossible to tell whether any call came from outside the callgraph boundary" \
        html_xlink/proj/glob.c.callers.html ; then
        fail genhtml_xlink "a flagged callee still calls its remainder undecidable"
    fi
    # 'g's remainder is still a number:  the flag is not set for it, and nothing
    #   about the other two changes what its own sites account for
    if ! grep -q -E -e 'class="coverCallgraphHi" title="[^"]*">\(4\)</td>' \
         html_xlink/proj/glob.c.callers.html ; then
        fail genhtml_xlink "the count of a computed remainder was lost"
    fi
    # ..and all three functions are now called both ways:  each is named by a site
    #   of this report and has a call from outside it, which is the one answer the
    #   note has for all three however the crossing became known.  'k' is the case
    #   the note cannot take from the classification:  no call site accounts for
    #   any of its calls - its one site has an unknown count - so the arithmetic
    #   calls it external, where the page has a caller row to show
    checkNotes genhtml_xlink html_xlink/proj/glob.c.callers.html 0 3 0
fi

# ----------------------------------------------------------------------
echo "*** 10. removing a file:  its calls outlive its call sites"
# ----------------------------------------------------------------------
# Taking a file out of a report takes its call sites with it - and a call one of
#   them made is a fact about the *callee*, which the report may well be keeping.
#   That is the shape of the use model this metric is for:  an application plus a
#   pile of testcases, where the interesting question is which application
#   functions were called and from inside or outside the application, and the
#   test files themselves are then removed from the report.  Without the flag the
#   answer would depend on which files happened to be in the report - the same
#   function reading "called internally" in one report and "never called" in the
#   next - and two such reports cannot be compared at all.
#   So the flag is set as the file goes away:  it is the last moment the sites
#   exist, and nothing later can tell that they were ever there.
# The reader takes the note for a section it skips, which is what '--remove',
#   '--extract' and an '--exclude' pattern all are;  'TraceFile::remove' takes it
#   for a removal from data already read, and 'resolve.sh' is where that half is
#   asserted.  Either way it is applied after the last input has been read, since
#   the callee's own file may be read later - or, under '--parallel', by another
#   process.
# The fixture is the use model in miniature:  'app.c' is the application - 'api'
#   calls 'helper', 'unused' is called by nothing - and 'test.c' is a testcase,
#   which calls 'api' once and 'helper' twice.  'helper' was entered 3 times, so
#   its own count is where the two calls from the testcase are; 'api' was entered
#   only from the testcase.
cat >proj/app.c <<'EOF'
int helper(int x)
{
    return x + 1;
}

int api(int n)
{
    return helper(n) + 1;
}

int unused(int n)
{
    return n;
}
EOF
cat >proj/test.c <<'EOF'
int test_one(void)
{
    return api(1) + helper(2) + helper(3);
}
EOF
cat >app.info <<'EOF'
TN:format
SF:proj/app.c
FNL:0,1,4
FNA:0e,3,helper
FNL:1,6,9
FNA:1e,1,api
FNC:1,8,12,0,1,helper
FNL:2,11,14
FNA:2e,0,unused
FNF:3
FNH:2
FNCF:1
FNCH:1
DA:1,3
DA:3,3
DA:6,1
DA:8,1
DA:11,0
DA:13,0
LF:6
LH:4
end_of_record
TN:format
SF:proj/test.c
FNL:0,1,4
FNA:0,1,test_one
FNC:0,3,12,0,1,api
FNC:0,3,22,0,2,helper
FNF:1
FNH:1
FNCF:2
FNCH:2
DA:1,1
DA:3,1
LF:2
LH:2
end_of_record
EOF

runLcov rm_test --callgraph -o rm_test.info --remove app.info '*/test.c'
# 'helper' and 'api' were called from sites which are now gone, so each carries
#   the flag, and the flag carries the number of calls those sites made:  2 to
#   'helper' and 1 to 'api'.  'unused' was called by nothing and still is.
# The execution counts are untouched by all of this - the calls are inside them
#   either way.  The site which is left and the flag together account for every
#   call of each, so neither is deduced to have a caller the report cannot name
checkAliasRecords rm_test rm_test.info <<'EOF'
FNA:0ex2,3,helper
FNA:1ex1,1,api
FNA:2e,0,unused
EOF
# ..and the application's own call site is still a call site:  the flag is what
#   is left of the calls which had one and lost it, not a replacement for the
#   ones which still do
checkCallRecords rm_test rm_test.info <<'EOF'
FNC:1,8,12,0,1,helper
FNCF:1
FNCH:1
EOF
# ..so the caller row of each is the asserted one alone, and its count is the
#   calls the removed sites made
runGenhtml rm_html --callgraph -o html_rm rm_test.info
if [ -f html_rm/proj/app.c.callers.html ] ; then
    if [ 2 != `grep -c -E -e "$EXTCALLER" html_rm/proj/app.c.callers.html` ] ||
       [ 2 != `grep -c -F -e "$EXTROW" html_rm/proj/app.c.callers.html` ] ; then
        fail rm_html "expected 'helper' and 'api' to have external callers:" \
            `grep -c -E -e "$EXTCALLER" -e "$EXTROW" \
                html_rm/proj/app.c.callers.html`
    fi
    for n in 1 2 ; do
        if ! grep -q -E -e "${XCELL}$n</td>" html_rm/proj/app.c.callers.html
        then
            fail rm_html "no external caller row counts $n calls"
        fi
    done
    if grep -q -E -e "$DEDUCEDEXT" -e "$DEDUCED" -e "$DEDUCEDROW" \
        -e "$BOTHROW" html_rm/proj/app.c.callers.html ; then
        fail rm_html "a caller row deduces calls which the flag accounts for"
    fi
else
    fail rm_html "no call site view was written"
fi

# '--extract' is the same operation said the other way round, and it is the one
#   the use model actually reaches for:  keep the application, drop everything
#   else
runLcov rm_extract --callgraph -o rm_extract.info --extract app.info '*/app.c'
if [ -f rm_extract.info ] && ! diff -u rm_test.info rm_extract.info ; then
    fail rm_extract "keeping one file and removing the other disagree"
fi

# Whether the removed site was taken does not decide whether there is a flag:
#   the flag says that an edge crosses the boundary - that a call site outside
#   the report names this function - and the site said that whether it was ever
#   taken or not.  Its count is what the flag counts:  a site which was never
#   taken adds 0, and one whose count is not known leaves the flag's count
#   unknown.  So 'helper' is 'x0' - and its two calls which no site accounts for
#   are deduced - while 'api' is a bare 'x', and whether any of its calls came
#   from somewhere else cannot be told
sed -e 's/^FNC:0,3,12,0,1,api$/FNC:0,3,12,0,-,api/' \
    -e 's/^FNC:0,3,22,0,2,helper$/FNC:0,3,22,0,0,helper/' app.info > untaken.info
if [ 2 != `grep -c -E '^FNC:0,3,(12,0,-,api|22,0,0,helper)$' untaken.info` ] ; then
    fail untaken "the untaken-call fixture was not built"
fi
runLcov rm_untaken --callgraph -o rm_untaken.info --remove untaken.info '*/test.c'
checkAliasRecords rm_untaken rm_untaken.info <<'EOF'
FNA:0ex0d,3,helper
FNA:1ex,1,api
FNA:2e,0,unused
EOF
# ..and the caller rows say the same:  'api' has the asserted row alone, whose
#   count is not known, and 'helper' has both, counting the 0 calls of the
#   removed site and the 2 deduced ones
runGenhtml rm_untaken_html --callgraph -o html_untaken rm_untaken.info
UNTAKEN=html_untaken/proj/app.c.callers.html
if [ -f $UNTAKEN ] ; then
    if ! grep -q -F -e 'is not recorded">-</td>' $UNTAKEN ; then
        fail rm_untaken_html "the '<external callers>' row of 'api' does not" \
            "say that its count is not known:"
        grep -A 3 -F -e "$EXTROW" $UNTAKEN
    fi
    if ! grep -q -E -e "${XCELL}0&nbsp;\(2\)</td>" $UNTAKEN ; then
        fail rm_untaken_html "the '<external and deduced callers>' row of" \
            "'helper' does not count 0 flagged and 2 deduced calls"
    fi
    if [ 1 != `grep -c -F -e "$EXTROW" $UNTAKEN` ] ||
       [ 1 != `grep -c -F -e "$BOTHROW" $UNTAKEN` ] ; then
        fail rm_untaken_html "the labels of 'api' and 'helper' do not say" \
            "what their counts say"
    fi
    if ! grep -q -F -e '2 calls:  0 from call sites outside' $UNTAKEN ; then
        fail rm_untaken_html "the row of 'helper' does not say what its count" \
            "is made of"
    fi
else
    fail rm_untaken_html "no call site view was written"
fi

# A call to a name the removed file defines itself went to that definition - the
#   rule every call site is resolved by - and that definition is going away with
#   the site.  There is no surviving callee for the call to be a fact about, so
#   nothing is recorded:  otherwise an unrelated definition of the same name
#   elsewhere would answer for the call once the file which owned it was gone,
#   and a function which nothing ever called would be reported as called.
cat >proj/tlocal.c <<'EOF'
static int helper(int x)
{
    return x + 2;
}

int test_two(void)
{
    return helper(2) + helper(3);
}
EOF
cat >own.info <<'EOF'
TN:format
SF:proj/app.c
FNL:0,1,4
FNA:0e,0,helper
FNL:1,6,9
FNA:1e,1,api
FNC:1,8,12,0,0,helper
FNF:2
FNH:1
FNCF:1
FNCH:0
DA:1,0
DA:3,0
DA:6,1
DA:8,1
LF:4
LH:2
end_of_record
TN:format
SF:proj/tlocal.c
FNL:0,1,4
FNA:0,2,helper
FNL:1,6,9
FNA:1,1,test_two
FNC:1,8,12,0,2,helper
FNF:2
FNH:2
FNCF:1
FNCH:1
DA:1,2
DA:3,2
DA:6,1
DA:8,1
LF:4
LH:2
end_of_record
EOF
runLcov rm_own --callgraph -o rm_own.info --remove own.info '*/tlocal.c'
checkAliasRecords rm_own rm_own.info <<'EOF'
FNA:0e,0,helper
FNA:1ed,1,api
EOF

# The same, where the removed file spells its own definitions the old way:  a
#   'FN:' record defines a function without an index, so it can be the callee of a
#   site but never the caller of one, and a section may hold both spellings.  The
#   names of a skipped section come from wherever they are written, since the
#   check is "did this file define what it called".
cat >proj/tlegacy.c <<'EOF'
static int helper(int x)
{
    return x + 3;
}

int test_three(void)
{
    return helper(4);
}
EOF
cat >oldown.info <<'EOF'
TN:format
SF:proj/app.c
FNL:0,1,4
FNA:0e,0,helper
FNL:1,6,9
FNA:1e,1,api
FNC:1,8,12,0,0,helper
FNF:2
FNH:1
FNCF:1
FNCH:0
DA:1,0
DA:3,0
DA:6,1
DA:8,1
LF:4
LH:2
end_of_record
TN:format
SF:proj/tlegacy.c
FN:1,4,helper
FNDA:2,helper
FNL:0,6,9
FNA:0,1,test_three
FNC:0,8,12,0,2,helper
FNF:2
FNH:2
FNCF:1
FNCH:1
DA:1,2
DA:3,2
DA:6,1
DA:8,1
LF:4
LH:2
end_of_record
EOF
# ..and the fixture is data this reader accepts, which is what makes the removal
#   above a fact about the removal rather than about a malformed input
runLcov old_control --callgraph -o old_control.info -a oldown.info
runLcov rm_oldown --callgraph -o rm_oldown.info --remove oldown.info '*/tlegacy.c'
checkAliasRecords rm_oldown rm_oldown.info <<'EOF'
FNA:0e,0,helper
FNA:1ed,1,api
EOF

# The flag is recorded for the sake of callgraph coverage and read by nothing else,
#   so a run which did not ask for the metric does not grow one:  the call records
#   of the removed file were dropped unread, and there is nothing to record
runLcov rm_nocallee -o rm_nocallee.info --remove app.info '*/test.c'
if [ -f rm_nocallee.info ] &&
   grep -q -E '^FNA:[0-9]+[a-z]' rm_nocallee.info ; then
    fail rm_nocallee "a function flag was written without --callgraph-coverage"
fi

# ..and the merge the use model ends with:  the run whose testcase files were
#   removed, together with one which kept them.  The known site comes back and the
#   flag stays - "called from here, and from something this report cannot name" -
#   which is the same pair of facts either input had on its own.  The sites of
#   both inputs and the flag of the first account for every call, so nothing is
#   deduced;  'test_one' has no caller in either
runLcov rm_merge --callgraph -o rm_merge.info -a rm_test.info -a app.info
checkAliasRecords rm_merge rm_merge.info <<'EOF'
FNA:0ex2,6,helper
FNA:1ex1,2,api
FNA:2e,0,unused
FNA:0d,1,test_one
EOF

# ----------------------------------------------------------------------
echo "*** 11. the filters, and a line which has nothing on it but a call"
# ----------------------------------------------------------------------
# A line which still carries a coverpoint of some other kind is not a line the
#   filters may suppress - the rule the branch and MC/DC data have always been
#   held to - and a call site is such a coverpoint.  The case which makes it
#   matter is the closing brace of a scope:  what is called there is the
#   destructor of an object which went out of scope, or the end of a 'catch', and
#   the call is real even though the line looks like punctuation.
# An *explicit* exclusion still wins:  the sites on an excluded line are removed
#   with it, so that the line is then a line with nothing on it and goes the way
#   every other excluded line goes.
# Every callee is defined in the file as well, below the function which calls it:
#   a call whose callee no file of the report defines leaves the boundary and is
#   dropped before any of this is visible (section 16), and what these runs are
#   about is the filters.  Below, so that 'scope' is still the first function of
#   the section and the caller index of every site stays 0
cat >proj/s.cpp <<'EOF'
struct Obj { Obj(int x); ~Obj(); };
struct Other { ~Other(); };
int other(int x);
int use(int x);

int scope(int n)
{
    Obj o(n);
    int r = use(n);
    r += other(n);    // LCOV_EXCL_LINE
    return r;
}

Obj::Obj(int x) { (void)x; }
Obj::~Obj() {}
int other(int x) { return x; }
int use(int x) { return x + 1; }
Other::~Other() {}
EOF

cat >s.info <<'EOF'
TN:format
SF:proj/s.cpp
FNL:0,6,12
FNA:0,1,scope
FNC:0,8,9,0,1,Obj::Obj
FNC:0,9,13,0,1,use
FNC:0,10,10,0,1,other
FNC:0,12,1,0,1,Obj::~Obj
FNL:1,14,14
FNA:1,1,Obj::Obj
FNL:2,15,15
FNA:2,1,Obj::~Obj
FNL:3,16,16
FNA:3,1,other
FNL:4,17,17
FNA:4,1,use
FNF:5
FNH:5
FNCF:4
FNCH:4
DA:8,1
DA:9,1
DA:10,1
DA:11,1
DA:12,1
DA:14,1
DA:15,1
DA:16,1
DA:17,1
LF:9
LH:9
end_of_record
EOF

# The brace filter would take line 12:  it is a closing brace whose count is the
#   count of the line above it, which is the whole of its criterion.  The call to
#   the destructor is what keeps it
#   ('LCOV_EXCL_LINE' on line 10 is the region filter's business and not this
#   run's, so every site is still here)
runLcov brace --callgraph -a s.info --filter brace -o brace.info
checkCallRecords brace brace.info <<'EOF'
FNC:0,8,9,0,1,Obj::Obj
FNC:0,9,13,0,1,use
FNC:0,10,10,0,1,other
FNC:0,12,1,0,1,Obj::~Obj
FNCF:4
FNCH:4
EOF
if [ -f brace.info ] && ! grep -q -F -e 'DA:12,1' brace.info ; then
    fail brace "the closing brace was filtered away under a call site:"
    grep -E '^DA:' brace.info
fi

# ..and the control:  the same file with that one record taken out, where the
#   filter does fire.  Without it the assertion above would pass on a report in
#   which the brace filter had simply not run
grep -v -F -e 'FNC:0,12,1,0,1,Obj::~Obj' s.info |
    sed -e 's/^FNCF:4$/FNCF:3/' -e 's/^FNCH:4$/FNCH:3/' > nodtor.info
runLcov nodtor --callgraph -a nodtor.info --filter brace -o nodtor.info.out
if [ -f nodtor.info.out ] && grep -q -F -e 'DA:12,1' nodtor.info.out ; then
    fail nodtor "the brace filter did not fire on a line with no call site:"
    grep -E '^DA:' nodtor.info.out
fi

# A closing brace with a zero count and call sites on it has rules of its own,
#   and they are about the destructors called there - of the objects which go
#   out of scope - and nothing else:
#   - 'taken', line 9:  a destructor ran, so the line did too.  Its count is the
#     smallest non-zero destructor count, per testcase:  3 of 3 and 4 in 't1'
#     (the 1 of 'note' is not a destructor and does not count), 2 of 2 and 0
#     in 't2'.  '_ZN3MngD1Ev' is there to be recognized mangled
#   - 'missed', lines 17 and 19:  no destructor ran, and every other line of the
#     function did - so the lines go, with their sites.  The two scopes are
#     nested, and neither blocks the other
#   - 'kept', line 27:  line 25 was not executed, so the constructors may not
#     all have been called either, and the line stays
#   - 'unknown', line 33:  the destructor's count is not known
#   - 'noend', line 39:  the function's end line is not known (and is not to be
#     derived:  that is 'derive_function_end_line')
#   - 'plain', line 44:  the only call is not to a destructor, so it is the rule
#     for a brace with no call site - a zero count under a line which ran - and
#     the site goes with the line
# The sites which go are recorded on their callees:  the 'x' flag
cat >proj/d.cpp <<'EOF'
struct Obj { Obj(int x); ~Obj(); };
struct Mng { ~Mng(); };
int use(int x);
void note(int x);
int taken(int n)
{
    Obj a(n); Mng m;
    return use(n);
}

int missed(int n)
{
    Obj a(n);
    {
        Obj b(n);
        use(n);
    }
    return use(n);
}

int kept(int n)
{
    Obj a(n);
    if (n)
        use(n);
    return n;
}

int unknown(int n)
{
    Obj a(n);
    return n;
}

int noend(int n)
{
    Obj a(n);
    return n;
}

void plain(int n)
{
    use(n);
}

Obj::Obj(int x) { (void)x; }
Obj::~Obj() {}
Mng::~Mng() {}
int use(int x) { return x + 1; }
void note(int x) { (void)x; }
EOF

cat >d.info <<'EOF'
TN:t1
SF:proj/d.cpp
FNL:0,5,9
FNA:0,3,taken
FNC:0,7,9,0,3,Obj::Obj
FNC:0,8,12,0,3,use
FNC:0,9,1,0,3,Obj::~Obj
FNC:0,9,2,0,4,_ZN3MngD1Ev
FNC:0,9,3,0,1,note
FNL:1,11,19
FNA:1,1,missed
FNC:1,13,9,0,1,Obj::Obj
FNC:1,15,13,0,1,Obj::Obj
FNC:1,16,9,0,1,use
FNC:1,17,5,0,0,Obj::~Obj
FNC:1,18,12,0,1,use
FNC:1,19,1,0,0,Obj::~Obj
FNL:2,21,27
FNA:2,1,kept
FNC:2,23,9,0,1,Obj::Obj
FNC:2,25,9,0,0,use
FNC:2,27,1,0,0,Obj::~Obj
FNL:3,29,33
FNA:3,1,unknown
FNC:3,31,9,0,1,Obj::Obj
FNC:3,33,1,0,-,Obj::~Obj
FNL:4,35
FNA:4,1,noend
FNC:4,37,9,0,1,Obj::Obj
FNC:4,39,1,0,0,Obj::~Obj
FNL:5,41,44
FNA:5,1,plain
FNC:5,43,5,0,1,use
FNC:5,44,1,0,0,note
FNL:6,46,46
FNA:6,7,Obj::Obj
FNL:7,47,47
FNA:7,3,Obj::~Obj
FNL:8,48,48
FNA:8,4,_ZN3MngD1Ev
FNL:9,49,49
FNA:9,6,use
FNL:10,50,50
FNA:10,1,note
DA:7,3
DA:8,3
DA:9,0
DA:13,1
DA:15,1
DA:16,1
DA:17,0
DA:18,1
DA:19,0
DA:23,1
DA:24,1
DA:25,0
DA:26,1
DA:27,0
DA:31,1
DA:32,1
DA:33,0
DA:37,1
DA:38,1
DA:39,0
DA:43,1
DA:44,0
DA:46,7
DA:47,3
DA:48,4
DA:49,6
DA:50,1
FNF:11
FNH:11
FNCF:20
FNCH:13
LF:27
LH:19
end_of_record
TN:t2
SF:proj/d.cpp
FNL:0,5,9
FNA:0,2,taken
FNC:0,7,9,0,2,Obj::Obj
FNC:0,8,12,0,2,use
FNC:0,9,1,0,2,Obj::~Obj
FNC:0,9,2,0,0,_ZN3MngD1Ev
FNC:0,9,3,0,0,note
FNL:6,46,46
FNA:6,2,Obj::Obj
FNL:7,47,47
FNA:7,2,Obj::~Obj
FNL:8,48,48
FNA:8,0,_ZN3MngD1Ev
FNL:9,49,49
FNA:9,2,use
FNL:10,50,50
FNA:10,0,note
DA:7,2
DA:8,2
DA:9,0
DA:46,2
DA:47,2
DA:48,0
DA:49,2
DA:50,0
FNF:6
FNH:4
FNCF:5
FNCH:3
LF:8
LH:5
end_of_record
EOF

runLcov dtor --callgraph -a d.info --filter brace -o dtor.info \
    --rc derive_function_end_line=0
checkCallRecords dtor dtor.info <<'EOF'
FNC:0,7,9,0,3,Obj::Obj
FNC:0,8,12,0,3,use
FNC:0,9,1,0,3,Obj::~Obj
FNC:0,9,2,0,4,_ZN3MngD1Ev
FNC:0,9,3,0,1,note
FNC:1,13,9,0,1,Obj::Obj
FNC:1,15,13,0,1,Obj::Obj
FNC:1,16,9,0,1,use
FNC:1,18,12,0,1,use
FNC:2,23,9,0,1,Obj::Obj
FNC:2,25,9,0,0,use
FNC:2,27,1,0,0,Obj::~Obj
FNC:3,31,9,0,1,Obj::Obj
FNC:3,33,1,0,-,Obj::~Obj
FNC:4,37,9,0,1,Obj::Obj
FNC:4,39,1,0,0,Obj::~Obj
FNC:5,43,5,0,1,use
FNCF:17
FNCH:13
FNC:0,7,9,0,2,Obj::Obj
FNC:0,8,12,0,2,use
FNC:0,9,1,0,2,Obj::~Obj
FNC:0,9,2,0,0,_ZN3MngD1Ev
FNC:0,9,3,0,0,note
FNCF:5
FNCH:3
EOF
# ..the line records, per testcase
if [ -f dtor.info ] ; then
    awk '/^TN:/ {tn=$0} /^DA:(9|17|19|27|33|39|44),/ {print tn " " $0}' \
        dtor.info > dtor.lines
    cat > dtor.lines.expect <<'EOF'
TN:t1 DA:9,3
TN:t1 DA:27,0
TN:t1 DA:33,0
TN:t1 DA:39,0
TN:t2 DA:9,2
EOF
    if ! diff -u dtor.lines.expect dtor.lines ; then
        fail dtor "unexpected closing brace records"
    fi
    for flag in 'FNA:7x0,3,Obj::~Obj' 'FNA:10x0,1,note' ; do
        if ! grep -q -F -e "$flag" dtor.info ; then
            fail dtor "the removed site was not recorded:  no '$flag'"
        fi
    done
fi

# 'LCOV_EXCL_CALLGRAPH_LINE' and 'LCOV_EXCL_CALLGRAPH_START/STOP' take the call
#   sites of the lines they mark and nothing else:  every line record stays, and
#   so does the branch data - except on line 12, whose 'LCOV_EXCL_BR_LINE' is
#   honoured alongside, since the two markers are independent of one another.
#   Only the site on line 11 is left, and each callee now accounts for fewer of
#   its calls than it was entered:  the 'd' flag
cat >proj/m.cpp <<'EOF'
int use(int x);
int other(int x);

int marked(int n)
{
    int r = use(n);    // LCOV_EXCL_CALLGRAPH_LINE
    // LCOV_EXCL_CALLGRAPH_START
    r += other(n);
    r += use(r);
    // LCOV_EXCL_CALLGRAPH_STOP
    r += other(r);
    if (n) r += use(1);    // LCOV_EXCL_BR_LINE LCOV_EXCL_CALLGRAPH_LINE
    return r;
}

int use(int x) { return x + 1; }
int other(int x) { return x; }
EOF

cat >m.info <<'EOF'
TN:marker
SF:proj/m.cpp
FNL:0,4,14
FNA:0,1,marked
FNC:0,6,13,0,1,use
FNC:0,8,10,0,1,other
FNC:0,9,10,0,1,use
FNC:0,11,10,0,1,other
FNC:0,12,17,0,1,use
FNL:1,16,16
FNA:1,3,use
FNL:2,17,17
FNA:2,2,other
BRDA:12,0,0,1
BRDA:12,0,1,0
BRDA:11,0,0,1
BRDA:11,0,1,1
DA:6,1
DA:8,1
DA:9,1
DA:11,1
DA:12,1
DA:13,1
DA:16,1
DA:17,1
FNF:3
FNH:3
FNCF:5
FNCH:5
BRF:4
BRH:3
LF:8
LH:8
end_of_record
EOF

runLcov cgmark --callgraph --branch -a m.info \
    --filter branch_region,callgraph_region -o cgmark.info
checkCallRecords cgmark cgmark.info <<'EOF'
FNC:0,11,10,0,1,other
FNCF:1
FNCH:1
EOF
checkAliasRecords cgmark cgmark.info <<'EOF'
FNA:0d,1,marked
FNA:1d,3,use
FNA:2d,2,other
EOF
if [ -f cgmark.info ] ; then
    if [ 8 != `grep -c -E '^DA:' cgmark.info` ] ; then
        fail cgmark "a line was excluded with its call sites:" \
            `grep -E '^DA:' cgmark.info`
    fi
    if [ 'BRDA:11,0,0,1 BRDA:11,0,1,1' != "`grep -E '^BRDA:' cgmark.info | xargs`" ] ; then
        fail cgmark "unexpected branch records:" `grep -E '^BRDA:' cgmark.info`
    fi
fi

# ..the markers are regexps which the lcovrc file can change, as the branch
#   markers are:  with another one for the line, only the region is excluded
runLcov cgmarkrc --callgraph -a m.info --filter callgraph_region \
    --rc lcov_excl_callgraph_line=NO_SUCH_MARKER -o cgmarkrc.info
checkCallRecords cgmarkrc cgmarkrc.info <<'EOF'
FNC:0,6,13,0,1,use
FNC:0,11,10,0,1,other
FNC:0,12,17,0,1,use
FNCF:3
FNCH:3
EOF

# ..a region which is not closed, and a close without an open, are mismatches
sed -e 's,^SF:proj/m.cpp$,SF:mproj/m.cpp,' m.info > mproj.info
mkdir -p mproj
sed -e 's,// LCOV_EXCL_CALLGRAPH_STOP,,' proj/m.cpp > mproj/m.cpp
checkFail cgunclosed 'unmatched LCOV_EXCL_CALLGRAPH_START at line 7' \
    --callgraph -a mproj.info --filter callgraph_region -o cgunclosed.info
sed -e 's,// LCOV_EXCL_CALLGRAPH_START,,' proj/m.cpp > mproj/m.cpp
checkFail cgunopened \
    'found LCOV_EXCL_CALLGRAPH_STOP directive at line 10 without matching LCOV_EXCL_CALLGRAPH_START' \
    --callgraph -a mproj.info --filter callgraph_region -o cgunopened.info

# ..and it is a filter about call sites, which is a contradiction without them
runWarn cgmarknometric \
    "'callgraph_region' filter enabled but callgraph coverage is not enabled" \
    -a m.info --filter callgraph_region -o cgmarknometric.info

# The 'blank' filter is held to the same rule, and one run asserts both halves of
#   it:  line 7 is blank and has nothing else on it, so it goes, and line 9 is
#   blank and carries a call site, so it stays.
# The site on line 9 is put there by hand, as the out-of-range one further down
#   is:  what is being pinned is the rule and not any compiler's output.  A line
#   record with a zero count on a line with no text on it is what compilers really
#   do produce, and is the whole reason the filter exists
cat >proj/b.cpp <<'EOF'
int other(int x);
int use(int x);

int both(int n)
{
    int r = other(n);

    r += use(n);

    return r;
}

int other(int x) { return x; }
int use(int x) { return x + 1; }
EOF

cat >b.info <<'EOF'
TN:format
SF:proj/b.cpp
FNL:0,4,11
FNA:0,1,both
FNC:0,6,13,0,1,other
FNC:0,8,10,0,1,use
FNC:0,9,5,0,0,other
FNL:1,13,13
FNA:1,1,other
FNL:2,14,14
FNA:2,1,use
FNF:3
FNH:3
FNCF:3
FNCH:2
DA:6,1
DA:7,0
DA:8,1
DA:9,0
DA:10,1
DA:11,1
DA:13,1
DA:14,1
LF:8
LH:6
end_of_record
EOF

runLcov blank --callgraph -a b.info --filter blank -o blank.info
checkCallRecords blank blank.info <<'EOF'
FNC:0,6,13,0,1,other
FNC:0,8,10,0,1,use
FNC:0,9,5,0,0,other
FNCF:3
FNCH:2
EOF
if [ -f blank.info ] && ! grep -q -F -e 'DA:9,0' blank.info ; then
    fail blank "a blank line was filtered away under a call site:"
    grep -E '^DA:' blank.info
fi
if [ -f blank.info ] && grep -q -F -e 'DA:7,0' blank.info ; then
    fail blank "the blank filter did not fire on a line with no call site:"
    grep -E '^DA:' blank.info
fi
# ..and the suppression is counted under its own name.  This is also the
#   assertion that asking for 'blank' by itself is enough:  the filter used to be
#   reachable only in company - '--filter line' is 'brace' and 'blank' together -
#   so a run of it alone silently did nothing
if [ -f blank.log ] && ! grep -q -E -e '^  blank:' blank.log ; then
    fail blank "the blank filter reported no suppression:"
    grep -A 4 -F -e 'Filter suppressions' blank.log
fi

# The excluded line loses its call site and then itself.  '-v' says so, because
#   a suppressed call is a coverpoint the user cannot otherwise see going away
runLcov region --callgraph -a s.info --filter region -o region.info -v
checkCallRecords region region.info <<'EOF'
FNC:0,8,9,0,1,Obj::Obj
FNC:0,9,13,0,1,use
FNC:0,12,1,0,1,Obj::~Obj
FNCF:3
FNCH:3
EOF
if [ -f region.info ] && grep -q -F -e 'DA:10,1' region.info ; then
    fail region "an excluded line survived its call site:"
    grep -E '^DA:' region.info
fi
if [ -f region.log ] &&
   ! grep -q -E -e "filter FNC \(region\).*proj/s.cpp:10 call to 'other'" \
        region.log ; then
    fail region "the removed call site was not reported at -v:"
    grep -E 'filter' region.log
fi

# ..and the same rule reached from a pattern rather than from a marker in the
#   source:  '--omit-lines' excludes the line it matches, and the call written on
#   that line goes with it.  Counted and reported under its own name, which is
#   what tells the two ways of excluding a line apart in the summary
runLcov omit --callgraph -a s.info --omit-lines 'r \+= other\(' -o omit.info -v
checkCallRecords omit omit.info <<'EOF'
FNC:0,8,9,0,1,Obj::Obj
FNC:0,9,13,0,1,use
FNC:0,12,1,0,1,Obj::~Obj
FNCF:3
FNCH:3
EOF
if [ -f omit.info ] && grep -q -F -e 'DA:10,1' omit.info ; then
    fail omit "an omitted line survived its call site:"
    grep -E '^DA:' omit.info
fi
if [ -f omit.log ] &&
   ! grep -q -E -e "filter FNC \(omit_lines\).*proj/s.cpp:10 call to 'other'" \
        omit.log ; then
    fail omit "the omitted call site was not reported at -v:"
    grep -E 'filter' omit.log
fi

# A line whose text is a preprocessor directive is not a line a call is written
#   on either.  'llvm-cov' nonetheless attributes one to the '#define' whose body
#   makes the call, so the 'directive' filter takes those sites along with the
#   line records it came for - and leaves the call the source really does make
cat >proj/d.cpp <<'EOF'
int other(int x);
#define CALL(x) other(x)

int use(int n)
{
    return CALL(n);
}

int other(int x) { return x; }
EOF

cat >d.info <<'EOF'
TN:format
SF:proj/d.cpp
FNL:0,4,7
FNA:0,1,use
FNC:0,2,17,0,1,other
FNC:0,6,12,0,1,other
FNL:1,9,9
FNA:1,2,other
FNF:2
FNH:2
FNCF:2
FNCH:2
DA:2,1
DA:6,1
DA:7,1
DA:9,2
LF:4
LH:4
end_of_record
EOF

runLcov directive --callgraph -a d.info --filter directive -o directive.info -v
checkCallRecords directive directive.info <<'EOF'
FNC:0,6,12,0,1,other
FNCF:1
FNCH:1
EOF
if [ -f directive.info ] && grep -q -F -e 'DA:2,1' directive.info ; then
    fail directive "a directive line survived its call site:"
    grep -E '^DA:' directive.info
fi
if [ -f directive.log ] &&
   ! grep -q -E -e "filter FNC \(directive\).*proj/d.cpp:2 call to 'other'" \
        directive.log ; then
    fail directive "the removed call site was not reported at -v:"
    grep -E 'filter' directive.log
fi

# A site past the end of the file is out of range, and the range filter takes it
#   the way it takes an out-of-range line.  Without that filter the site is kept
#   and the reader is told instead - see 'unsupported.sh' scenario 7, where the
#   'range' message is over a capture which really does produce one
sed -e 's|^FNCF:4$|FNC:0,99,7,0,1,use\nFNCF:5|' -e 's|^FNCH:4$|FNCH:5|' s.info \
    > oor.info
runLcov oor --callgraph -a oor.info --filter range -o oor.info.out
checkCallRecords oor oor.info.out <<'EOF'
FNC:0,8,9,0,1,Obj::Obj
FNC:0,9,13,0,1,use
FNC:0,10,10,0,1,other
FNC:0,12,1,0,1,Obj::~Obj
FNCF:4
FNCH:4
EOF

# A capture taken before that rule existed has the shape it forbids:  the line
#   records of the brace line filtered away, its call record kept.  genhtml has
#   to read it - a line whose only coverpoint is a call site takes its category
#   from the site, since the 'UNK' it would otherwise keep is not a category
#   anything can count, and asking for its location is a 'category' error on top
#   of an uninitialized value.  'runGenhtml' fails on any message at all, which
#   is what makes this an assertion about both of them
grep -v -F -e 'DA:12,1' s.info | sed -e 's/^LF:9$/LF:8/' -e 's/^LH:9$/LH:8/' \
    > nolinedata.info
runGenhtml nolinedata --callgraph -o html_nolinedata nolinedata.info
if [ ! -f html_nolinedata/proj/s.cpp.gcov.html ] ; then
    fail nolinedata "no source page was written"
fi

# ..and what the source view does with such a line.  There is no identifier at
#   the column of a destructor call on a closing brace - the source cannot be
#   decorated the way an ordinary call is - so the sites are named in a comment
#   appended to the line, one link each.  Two of them here:  the second one is
#   what the separator between two names is for, and its count is zero, so the
#   two ways a name in the comment can be marked are both on this page
cat >annot.info <<'EOF'
TN:format
SF:proj/s.cpp
FNL:0,6,12
FNA:0,1,scope
FNC:0,9,13,0,1,use
FNC:0,12,1,0,1,Obj::~Obj
FNC:0,12,3,0,0,Other::~Other
FNL:1,15,15
FNA:1,1,Obj::~Obj
FNL:2,17,17
FNA:2,1,use
FNL:3,18,18
FNA:3,0,Other::~Other
FNF:4
FNH:3
FNCF:3
FNCH:2
DA:8,1
DA:9,1
DA:10,1
DA:11,1
DA:12,1
DA:15,1
DA:17,1
DA:18,0
LF:8
LH:7
end_of_record
EOF

runGenhtml annot --callgraph --save -o html_annot annot.info
if ! grep -q -F -e '<span class="callgraphAnnot"><a class="callSite callgraphAnnot" href="s.cpp.callees.html#site_12_1" title="call recorded at column 1" data-callee="Obj::~Obj"></a><a class="callSiteLo callgraphAnnot" href="s.cpp.callees.html#site_12_3" title="call recorded at column 3" data-callee="Other::~Other"></a></span>' \
        html_annot/proj/s.cpp.gcov.html ; then
    fail annot "the calls on the closing brace are not named in a comment:"
    grep -F -e '<span id="L12"' html_annot/proj/s.cpp.gcov.html
fi
# ..and the comment is the whole of it:  the line number cell of such a line is
#   left alone, since a second link to the same place is only more page
if grep -q -F -e 'class="lineNum"><a' html_annot/proj/s.cpp.gcov.html ; then
    fail annot "the line number cell was linked as well as the comment:"
    grep -F -e '<span id="L12"' html_annot/proj/s.cpp.gcov.html
fi
# a call the source *can* point at is still pointed at, and is not in a comment
if ! grep -q -F -e '<a class="callSite" href="s.cpp.callees.html#site_9_13" data-calls="1: use">use</a>' \
        html_annot/proj/s.cpp.gcov.html ; then
    fail annot "the call on line 9 was not decorated in place"
fi
COUNT=`grep -c -F -e 'class="callgraphAnnot"' html_annot/proj/s.cpp.gcov.html`
if [ 1 != "$COUNT" ] ; then
    fail annot "expected exactly one annotated line, got $COUNT"
fi
# every character of that comment is generated by the stylesheet out of the
#   attributes.  A class which is emitted and not defined styles nothing, and
#   nothing says so - so the rules it needs are asserted, not assumed
for class in 'span.callgraphAnnot::before' 'a.callgraphAnnot::after' \
    'a.callgraphAnnot + a.callgraphAnnot::before' ; do
    if ! grep -q -F -e "$class" html_annot/gcov.css ; then
        fail annot "the stylesheet does not define '$class'"
    fi
done

# The comment is not in the source file, so it must not come back as if it were:
#   'html2lcov' recovers the source by stripping tags, which leaves nothing of a
#   tag with no text in it.  The guard is that the round trip still answers the
#   source the report was built from, byte for byte
$COVER $HTML2LCOV_TOOL html_annot --callgraph --source-directory proj -o annotrt \
    --ignore empty,unused 2>&1 | tee annotrt.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail annotrt "html2lcov failed:" `grep -E 'ERROR' annotrt.log`
fi
#   ('proj' holds the fixtures of every scenario above, so the other files in it
#    are reported as added - what this is about is 's.cpp', which must be
#    recovered exactly)
if [ -f annotrt.udiff ] && grep -q -F -e 's.cpp' annotrt.udiff ; then
    fail annotrt "the comment came back as part of the source"
    grep -A 20 -F -e 's.cpp' annotrt.udiff
fi

# ----------------------------------------------------------------------
echo "*** 12. which column of a call the source view has to look at"
# ----------------------------------------------------------------------
# A site's column is where the compiler said the call is, and the two GCC front
#   ends do not agree on where that is:  the C one points at the callee's name,
#   the C++ one at the call's opening parenthesis (measured on both - see the
#   'link' and 'cs' fixtures of 'geninfo.sh', whose columns are the compiler's).
#   So the name a link may be wrapped around is either at the column or ends
#   just left of it, and the source view has to try both or every call in a C++
#   report ends up in the trailing comment.
# This fixture is the second case in the shapes that make it interesting, with
#   the sites written by hand at exactly the parenthesis:  an ordinary call, a
#   template instantiation - whose argument list is part of the name the reader
#   sees - whitespace between the name and the parenthesis, and a member call
#   whose name is not the first thing in the expression.
cat >proj/shapes.cpp <<'EOF'
template <class T> T tf(T v);
int add(int a, int b);
int (*fp)(int);
struct P { int m(); ~P(); };

int shapes(P& p, int n)
{
    int r = add(n, 1);
    r += tf<int>(n);
    r += add (n, 2);
    r += p.m();
    r += (*fp)(n);
    r += n > 0 ? 1 : 0;
    {
        P q;
    }
    return r;
}

template <class T> T tf(T v) { return v; }
int add(int a, int b) { return a + b; }
int P::m() { return 0; }
P::~P() {}
int indirect(int x) { return x; }
int cmp(int x) { return x; }
EOF

# The last three sites are the ones no text can be wrapped around, one for each
#   way that happens:  a call through a pointer, where the parenthesis follows
#   another one;  a '>' to the left which is a comparison and not the end of an
#   argument list;  and the destructor of a scope, whose line is a closing brace
#   with nothing but indentation to its left.
# Every callee is defined below the caller, so that a site is a site of the report
#   and 'shapes' is still function 0 of the section
cat >shapes.info <<'EOF'
TN:format
SF:proj/shapes.cpp
FNL:0,6,18
FNA:0,1,shapes
FNC:0,8,16,0,1,add
FNC:0,9,17,0,1,tf<int>
FNC:0,10,14,0,1,add
FNC:0,11,13,0,1,P::m
FNC:0,12,15,0,1,indirect
FNC:0,13,14,0,1,cmp
FNC:0,16,5,0,1,P::~P
FNL:1,20,20
FNA:1,1,tf<int>
FNL:2,21,21
FNA:2,2,add
FNL:3,22,22
FNA:3,1,P::m
FNL:4,23,23
FNA:4,1,P::~P
FNL:5,24,24
FNA:5,1,indirect
FNL:6,25,25
FNA:6,1,cmp
FNF:7
FNH:7
FNCF:7
FNCH:7
DA:8,1
DA:9,1
DA:10,1
DA:11,1
DA:12,1
DA:13,1
DA:15,1
DA:16,1
DA:17,1
DA:20,1
DA:21,2
DA:22,1
DA:23,1
DA:24,1
DA:25,1
LF:15
LH:15
end_of_record
EOF

runGenhtml shapes --callgraph -o html_shapes shapes.info
SHAPES=html_shapes/proj/shapes.cpp.gcov.html
# the four which the source can point at, as the whole anchor:  the text the
#   link wraps is the assertion, and for the template it is the name with its
#   argument list and not just 'tf'
while read -r EXPECT ; do
    if ! grep -q -F -e "$EXPECT" $SHAPES ; then
        fail shapes "not decorated in place: $EXPECT"
        grep -F -e 'class="callSite"' $SHAPES
    fi
done <<'EOF'
<a class="callSite" href="shapes.cpp.callees.html#site_8_16" data-calls="1: add">add</a>
<a class="callSite" href="shapes.cpp.callees.html#site_9_17" data-calls="1: tf&lt;int&gt;">tf&lt;int&gt;</a>
<a class="callSite" href="shapes.cpp.callees.html#site_10_14" data-calls="1: add">add</a>
<a class="callSite" href="shapes.cpp.callees.html#site_11_13" data-calls="1: P::m">m</a>
EOF

# ..and the three which it cannot are in the comment, where the whole point is
#   that they are not silently dropped
while read -r EXPECT ; do
    if ! grep -q -F -e "$EXPECT" $SHAPES ; then
        fail shapes "not named in a comment: $EXPECT"
        grep -F -e 'callgraphAnnot' $SHAPES
    fi
done <<'EOF'
<a class="callSite callgraphAnnot" href="shapes.cpp.callees.html#site_12_15" title="call recorded at column 15" data-callee="indirect"></a>
<a class="callSite callgraphAnnot" href="shapes.cpp.callees.html#site_13_14" title="call recorded at column 14" data-callee="cmp"></a>
<a class="callSite callgraphAnnot" href="shapes.cpp.callees.html#site_16_5" title="call recorded at column 5" data-callee="P::~P"></a>
EOF

# The counts are the guard against an assertion which passes for the wrong
#   reason:  four decorations in the source, three names in a comment, and
#   nothing decorated twice
COUNT=`grep -o -F -e 'class="callSite" href="shapes.cpp.callees.html' $SHAPES |
    wc -l`
if [ 4 != "$COUNT" ] ; then
    fail shapes "expected 4 calls decorated in place, got $COUNT"
fi
COUNT=`grep -o -F -e 'callSite callgraphAnnot' $SHAPES | wc -l`
if [ 3 != "$COUNT" ] ; then
    fail shapes "expected 3 calls named in a comment, got $COUNT"
fi

# ----------------------------------------------------------------------
echo "*** 13. a call whose source text is not its callee's name"
# ----------------------------------------------------------------------
# The two reads above check what they found against the site's callees, which is
#   what makes them trustworthy - and it is also what makes them fail for a large
#   part of a real C++ report, because a call is often written as something other
#   than the name of the function it calls:
#     an operator call is written as its operands;
#     a call to a symbol which was not demangled cannot match source text at all;
#     a call whose column GCC folded onto an enclosing expression points at that
#       expression.
#   In every one of those the reader still wants to reach the site from the place
#   the call is written, so with 'strict_callee_match' clear - the default - the
#   column is believed even though nothing verified it.  Set, only a verified
#   read decorates and these all go to the trailing comment.
# One fixture, rendered both ways, since the assertion is the difference.
cat >proj/relax.cpp <<'EOF'
struct S { int v; int get(); };
bool operator==(const S& a, const S& b);

int relax(S& a, S& b, int n)
{
    int r = 0;
    if (a == b) { r += 1; }
    r += b.get();
    return r + n;
}

bool operator==(const S& a, const S& b) { return a.v == b.v; }
int S::get() { return v; }
int hidden(int x) { return x; }
EOF

# 7:11 is the first '=' of the operator call, 8:15 the parenthesis of a call
#   whose callee is still mangled, and 9:12 the 'r' of an expression which is not
#   a call at all - the shape a folded column has.  All hand written, because the
#   point is which column the view is given and not which column a compiler
#   chose;  'geninfo.sh' scenario 11 is the assertion about real columns.
# As above, each callee is defined below the caller so that the sites are inside
#   the boundary of the report - the mangled one under the name the site names it
#   by, since nothing here demangles
cat >relax.info <<'EOF'
TN:format
SF:proj/relax.cpp
FNL:0,4,10
FNA:0,1,relax
FNC:0,7,11,0,1,S::operator==
FNC:0,8,15,0,1,_ZN1S3getEv
FNC:0,9,12,0,1,hidden
FNL:1,12,12
FNA:1,1,S::operator==
FNL:2,13,13
FNA:2,1,_ZN1S3getEv
FNL:3,14,14
FNA:3,1,hidden
FNF:4
FNH:4
FNCF:3
FNCH:3
DA:6,1
DA:7,1
DA:8,1
DA:9,1
DA:12,1
DA:13,1
DA:14,1
LF:7
LH:7
end_of_record
EOF

runGenhtml relax --callgraph -o html_relax relax.info
RELAX=html_relax/proj/relax.cpp.gcov.html
# The operand of the operator, the demangled-looking part of the member call, and
#   the identifier the folded column landed on.  The last one is also the keyword
#   guard:  the read looks left of the column first, and left of 'r' is 'return'
while read -r EXPECT ; do
    if ! grep -q -F -e "$EXPECT" $RELAX ; then
        fail relax "not decorated in place: $EXPECT"
        grep -F -e 'class="callSite"' $RELAX
    fi
done <<'EOF'
<a class="callSite" href="relax.cpp.callees.html#site_7_11" data-calls="1: S::operator==">a</a>
<a class="callSite" href="relax.cpp.callees.html#site_8_15" data-calls="1: _ZN1S3getEv">get</a>
<a class="callSite" href="relax.cpp.callees.html#site_9_12" data-calls="1: hidden">r</a>
EOF
if grep -q -F -e '>return</a>' $RELAX ; then
    fail relax "the keyword left of the column was linked:"
    grep -F -e 'return' $RELAX
fi
COUNT=`grep -o -F -e 'callSite callgraphAnnot' $RELAX | wc -l`
if [ 0 != "$COUNT" ] ; then
    fail relax "expected no call in the trailing comment, got $COUNT"
fi

# ..and with the setting, the same three are in the comment and the source text
#   is left alone.  A configuration file setting and not a command line option,
#   so '--rc'
runGenhtml strictmatch --callgraph --rc strict_callee_match=1 \
    -o html_strict relax.info
STRICT=html_strict/proj/relax.cpp.gcov.html
while read -r EXPECT ; do
    if ! grep -q -F -e "$EXPECT" $STRICT ; then
        fail strictmatch "not named in a comment: $EXPECT"
        grep -F -e 'callgraphAnnot' $STRICT
    fi
done <<'EOF'
<a class="callSite callgraphAnnot" href="relax.cpp.callees.html#site_7_11" title="call recorded at column 11" data-callee="S::operator=="></a>
<a class="callSite callgraphAnnot" href="relax.cpp.callees.html#site_8_15" title="call recorded at column 15" data-callee="_ZN1S3getEv"></a>
<a class="callSite callgraphAnnot" href="relax.cpp.callees.html#site_9_12" title="call recorded at column 12" data-callee="hidden"></a>
EOF
COUNT=`grep -o -F -e 'class="callSite" href="relax.cpp.callees.html' $STRICT |
    wc -l`
if [ 0 != "$COUNT" ] ; then
    fail strictmatch "expected nothing decorated in place, got $COUNT"
fi

# ----------------------------------------------------------------------
echo "*** 14. the 'unknown_callee_count' filter"
# ----------------------------------------------------------------------
# A site whose count is unknown is in 'found' and never in 'hit', so it is a
#   ceiling on the rate which no test can lift:  the site is in the report
#   without being measured by it.  Whether that is worth reporting is not
#   something the data can say, so it is a filter - and it removes every such
#   site, there being nothing about one unknown count which makes it better than
#   another.
# The fixture has a known count, a measured zero, and three unknowns - two of
#   them on one line, so that the filter's location count and its coverpoint
#   count differ, which is what the histogram prints.  Every callee is a function
#   the report defines:  a call which leaves the boundary is dropped before this
#   filter is reached, whatever its count, and section 16 is where that is pinned
cat >proj/u.cpp <<'EOF'
int helper(int x) { return x + 1; }

int helper2(int x) { return x + 2; }

int useit(int n)
{
    int r = helper(n);
    r += helper(n) + helper2(n);
    r += helper2(1);
    if (n < 0) r += helper(-n);
    return r;
}
EOF

cat >u.info <<'EOF'
TN:format
SF:proj/u.cpp
FNL:0,1,1
FNA:0,1,helper
FNL:1,3,3
FNA:1,2,helper2
FNL:2,5,12
FNA:2,1,useit
FNC:2,7,13,0,1,helper
FNC:2,8,10,0,-,helper
FNC:2,8,22,0,-,helper2
FNC:2,9,10,0,-,helper2
FNC:2,10,21,0,0,helper
FNF:3
FNH:3
FNCF:5
FNCH:1
DA:1,1
DA:3,2
DA:7,1
DA:8,1
DA:9,1
DA:10,1
DA:11,1
LF:7
LH:7
end_of_record
EOF

# Not asked for:  nothing is removed.  This is the assertion that the filter is
#   opt-in - a report cannot lose a coverpoint to a default
runLcov ucoff --callgraph -a u.info -o ucoff.info
checkCallRecords ucoff ucoff.info <<'EOF'
FNC:2,7,13,0,1,helper
FNC:2,8,10,0,-,helper
FNC:2,8,22,0,-,helper2
FNC:2,9,10,0,-,helper2
FNC:2,10,21,0,0,helper
FNCF:5
FNCH:1
EOF
if [ -f ucoff.log ] && grep -q -F -e 'unknown_callee_count:' ucoff.log ; then
    fail ucoff "the filter ran without being asked for:"
    grep -A 2 -F -e 'unknown_callee_count:' ucoff.log
fi

# Asked for:  the three unknowns go and the two measured sites stay - including
#   the measured zero, which is a call the tests are known not to have made and
#   so is exactly what this filter must not touch
runLcov uc --callgraph -a u.info --filter unknown_callee_count -o uc.info
checkCallRecords uc uc.info <<'EOF'
FNC:2,7,13,0,1,helper
FNC:2,10,21,0,0,helper
FNCF:2
FNCH:1
EOF

# ..and it is counted like every other filter, so that '--filter' never removes
#   anything silently.  Two source lines and three coverpoints, so the histogram
#   prints both numbers - a location can hold several calls, which is why the
#   filter counts them separately
if [ -f uc.log ] ; then
    if ! grep -q -F -e 'unknown_callee_count:' uc.log ; then
        fail uc "the filter did not report what it removed:"
        cat uc.log
    fi
    if ! grep -A 1 -F -e 'unknown_callee_count:' uc.log |
         grep -q -E '^ *2 instances$' ; then
        fail uc "expected 2 locations:"
        grep -A 2 -F -e 'unknown_callee_count:' uc.log
    fi
    if ! grep -A 2 -F -e 'unknown_callee_count:' uc.log |
         grep -q -E '^ *3 coverpoints$' ; then
        fail uc "expected 3 coverpoints:"
        grep -A 2 -F -e 'unknown_callee_count:' uc.log
    fi
fi

# ..and asking for the filter with the metric turned off is a warning, the way
#   the 'mcdc' filter with MC/DC off is:  nothing to filter is not a
#   contradiction, but it is not what the user meant either
runWarn ucnometric \
    "'unknown_callee_count' filter enabled but callgraph coverage is not enabled" \
    -a u.info --filter unknown_callee_count -o ucnometric.info

# What all of this is for, read off the report rather than the tracefile:  the
#   rate the user sees.  Three of the five sites here have no count, so the
#   unfiltered report can reach 40% at best;  with them removed it reads 1 of 2
runGenhtml ucplain --callgraph -o html_ucplain u.info
if ! grep -E 'callgraph.*20\.0% \(1 of 5 callees\)' ucplain.log ; then
    fail ucplain "expected '1 of 5 callees':" `grep -i callee ucplain.log`
fi
runGenhtml ucfiltered --callgraph --filter unknown_callee_count \
    -o html_ucfiltered u.info
if ! grep -E 'callgraph.*50\.0% \(1 of 2 callees\)' ucfiltered.log ; then
    fail ucfiltered "expected '1 of 2 callees':" `grep -i callee ucfiltered.log`
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'format_2' $LOCAL_COVERAGE 0
fi

exit $STATUS
