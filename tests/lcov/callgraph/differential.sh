#! /usr/bin/env bash

# Call sites in a differential report:  the categorizer, the summaries and the
# genhtml display of both directions of the callgraph.
#
# A call site is categorized exactly as a line, a branch or an MC/DC expression
#   is - by comparing the current count against the baseline count of the *same
#   site*, where "the same site" means the same (line, column, ordinal) after the
#   diff has mapped the baseline line number onto a current one.  So the twelve
#   displayed categories all have to be reachable, and this fixture reaches every
#   one of them:  the whole point of the metric in a differential report is
#   telling "this call was already never taken" (UBC) from "this call stopped
#   being taken" (LBC) from "this call is new and is not taken" (UNC), and a
#   fixture which only produced the easy half would not notice the other.
#
# The site is categorized against the *caller's* diff, not the callee's - it is
#   the caller's source line that the call is on.  'main' calls 'c' twice on a
#   newly inserted line, and 'c' itself lives in a file which did not change at
#   all:  those two sites are still UNC and GNC, and not UBC/CBC.
#
# genhtml shows the same data three ways, and the three have to agree:
#   - one number per function, in the function table (the sites the function
#     contains - the 'per file' view, which is what FNCF/FNCH count);
#   - that function's rows on the two call site pages (the sites it contains, and
#     the sites which target it - the 'per function' view, which is derived);
#   - the source line itself, with the identifier at each call site linked to the
#     first of those two pages.
# The last of those is the one with a trap in it:  the columns index the raw
#   source text, the page shows escaped text, and 'html2lcov' recovers the source
#   from the page by stripping tags.  So the round trip through 'html2lcov' is
#   asserted here as well - a decoration which added any *text* to a source line
#   would come back as source and change it.
#
# Everything here is a hand-written '.info' over a checked-in source, so it needs
#   no compiler and runs on every platform.  See 'format.sh' for the record
#   itself and 'resolve.sh' for the callee-side resolution in isolation.

source ../../common.tst

# This directory is shared with 'aliases.sh', which removes '*.info' and '*.log'
# as it starts, so run in a private subdirectory - as 'format.sh' does.
SRCDIR=`pwd`
if [ "x$COVER" != "x" ] ; then
    # a bare '--coverage' leaves COVER_DB relative to the invocation directory
    case "$COVER_DB" in
        /*) ;;
        *)  COVER_DB="$SRCDIR/$COVER_DB"
            export PYCOV_DB="${COVER_DB}_py"
            PERL_COVER_ARGS="-MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine,-silent,1 "
            COVER="perl $PERL_COVER_ARGS"
            ;;
    esac
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf differential.d
    exit 0
fi

rm -rf differential.d
mkdir differential.d
cd differential.d || exit 1
mkdir proj

LCOV_OPTS="$PARALLEL $PROFILE"

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

runGenhtml()
{
    # runGenhtml label args...
    #   genhtml has to succeed and say nothing about anything
    local label=$1
    shift
    $COVER $GENHTML_TOOL $LCOV_OPTS "$@" 2>&1 | tee $label.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail $label "genhtml failed:" `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    if grep -q -E '(ERROR|WARNING)' $label.log ; then
        fail $label "unexpected message:" `grep -E 'ERROR|WARNING' $label.log`
        return 1
    fi
    return 0
}

checkLine()
{
    # checkLine label file text
    #   'file' has to contain 'text' somewhere
    local label=$1
    local file=$2
    local text=$3
    if [ ! -f $file ] ; then
        fail $label "$file was not written"
        return
    fi
    if ! grep -q -F -e "$text" $file ; then
        fail $label "'$text' is not in $file"
    fi
}

checkPattern()
{
    # checkPattern label file pattern
    #   'file' has to contain a line matching the extended regexp 'pattern'.
    #   Use this rather than checkLine for a summary line:  the cover type label
    #   there is padded out to the width of the widest one, so write that run of
    #   '.' as '\.+' and a change of label does not reach into every test
    local label=$1
    local file=$2
    local pattern=$3
    if [ ! -f $file ] ; then
        fail $label "$file was not written"
        return
    fi
    if ! grep -q -E -e "$pattern" $file ; then
        fail $label "'$pattern' does not match any line of $file"
    fi
}

checkNoLine()
{
    # checkNoLine label file text
    local label=$1
    local file=$2
    local text=$3
    if [ -f $file ] && grep -q -F -e "$text" $file ; then
        fail $label "'$text' should not be in $file"
        grep -F -e "$text" $file
    fi
}

fncRecords()
{
    # fncRecords tracefile
    #   every call record of a tracefile, keyed by the file it belongs to and
    #   sorted, so that comparing two tracefiles does not depend on the order in
    #   which they happen to list their files
    awk '/^SF:/ { f = $0 } /^FNC/ { print f, $0 }' $1 | sort
}

# ----------------------------------------------------------------------
# The fixture.
#
# 'lib.cpp' holds every callee and makes no calls of its own, and does not
#   change between the two versions:  a callee-side view which is built from the
#   caller's records has to work across files, and a file with no call data of
#   its own must still show 'callers of this function' tables.
#   Line 1 defines two symbols at one location - identical code folding, which is
#   what an alias *is* - so that a site which resolves to 'aa' and a site which
#   resolves to 'a' land on the same definition and collapse to one display row.
# ----------------------------------------------------------------------
cat >proj/lib.cpp <<'EOF'
int a(void) { return 1; }
int b(void) { return 2; }
int c(void) { return 3; }
struct Shape { virtual int area(void) = 0; };
struct Circle : Shape { int area(void) { return 4; } };
struct Square : Shape { int area(void) { return 5; } };
EOF

# 'c.cpp' is the caller.  Between the baseline and the current version 'drop'
#   was deleted and the body of 'main' was rewritten; everything above line 12
#   is untouched, which is where the eight 'unchanged code' categories come from.
cat >proj/c.cpp <<'EOF'
int both(void)
{
    return a() + b() + a();
}
int mix(void)
{
    return a() + b() + c() + b() + a();
}
int dispatch(Shape* p)
{
    return p->area() + p->area() + ext();
}
int main(void)
{
    int t = both();
    return t + c() + mix() + dispatch(0);
}
EOF

# The baseline of 'c.cpp' is never written to disk - genhtml reconstructs the
#   baseline lines it needs from the diff - so this is the diff and nothing else.
cat >c.udiff <<'EOF'
--- proj/c.cpp
+++ proj/c.cpp
@@ -13,8 +13,5 @@
-int drop(void)
-{
-    return c() + a();
-}
 int main(void)
 {
-    return both() + mix();
+    int t = both();
+    return t + c() + mix() + dispatch(0);
 }
EOF

# The current data.  Every column below is the real column of the identifier in
#   the source above, because the source view checks it:  'genhtml' will not
#   hyperlink an identifier which does not match one of the site's callees.
#
# The categories these produce, once compared against the baseline below:
#   3:12   a               1 -> 3    CBC
#   3:24:0 a               -    0    UIC   two records, one location, one
#   3:24:1 aa              -    2    GIC     destination:  they merge to one row
#   7:12   a               0 -> 0    UBC
#   7:18   b               0 -> 4    GBC
#   7:24   c               5 -> 0    LBC
#   7:36   a               2 -> 2    CBC
#   11:15:0 Circle::area   2 -> 2    CBC   one location, two destinations
#   11:15:1 Square::area   0 -> 0    UBC
#   11:27  Circle::area    1 -> 1    CBC
#   11:36  ext             1 -> 1    CBC   a callee this report does not describe
#   15:13  both            +    1    GNC
#   16:12  c               +    1    GNC
#   16:16  c               +    0    UNC   the callee is in an unchanged file
#   16:22  mix             +    1    GNC
#   16:30  dispatch        +    1    GNC
cat >curr.info <<'EOF'
TN:differential
SF:proj/lib.cpp
FNL:0,1,1
FNA:0,3,a
FNA:0,2,aa
FNL:1,2,2
FNA:1,4,b
FNL:2,3,3
FNA:2,1,c
FNL:3,5,5
FNA:3,3,Circle::area
FNL:4,6,6
FNA:4,0,Square::area
FNF:5
FNH:4
FNCF:0
FNCH:0
DA:1,3
DA:2,4
DA:3,1
DA:5,3
DA:6,0
LF:5
LH:4
end_of_record
SF:proj/c.cpp
FNL:0,1,4
FNA:0,1,both
FNC:0,3,12,0,3,a
FNC:0,3,24,0,0,a
FNC:0,3,24,1,2,aa
FNL:1,5,8
FNA:1,1,mix
FNC:1,7,12,0,0,a
FNC:1,7,18,0,4,b
FNC:1,7,24,0,0,c
FNC:1,7,36,0,2,a
FNL:2,9,12
FNA:2,1,dispatch
FNC:2,11,15,0,2,Circle::area
FNC:2,11,15,1,0,Square::area
FNC:2,11,27,0,1,Circle::area
FNC:2,11,36,0,1,ext
FNL:3,13,17
FNA:3,1,main
FNC:3,15,13,0,1,both
FNC:3,16,12,0,1,c
FNC:3,16,16,0,0,c
FNC:3,16,22,0,1,mix
FNC:3,16,30,0,1,dispatch
FNF:4
FNH:4
FNCF:16
FNCH:11
DA:1,1
DA:3,3
DA:5,1
DA:7,4
DA:9,1
DA:11,3
DA:13,1
DA:15,1
DA:16,1
LF:9
LH:9
end_of_record
EOF

# The baseline.  'lib.cpp' is byte for byte the same; 'c.cpp' has
#   - 3:18 'b', which the current version no longer calls at all:  ECB, because
#     it was covered there and is not a coverpoint here
#   - 7:30 'b', likewise but never taken:  EUB
#   - 'drop' at 13-16 and the old body of 'main' at 17-20, both of which the
#     diff deletes:  DCB where they were taken and DUB where they were not
cat >base.info <<'EOF'
TN:differential
SF:proj/lib.cpp
FNL:0,1,1
FNA:0,3,a
FNA:0,2,aa
FNL:1,2,2
FNA:1,4,b
FNL:2,3,3
FNA:2,1,c
FNL:3,5,5
FNA:3,3,Circle::area
FNL:4,6,6
FNA:4,0,Square::area
FNF:5
FNH:4
FNCF:0
FNCH:0
DA:1,3
DA:2,4
DA:3,1
DA:5,3
DA:6,0
LF:5
LH:4
end_of_record
SF:proj/c.cpp
FNL:0,1,4
FNA:0,1,both
FNC:0,3,12,0,1,a
FNC:0,3,18,0,7,b
FNL:1,5,8
FNA:1,1,mix
FNC:1,7,12,0,0,a
FNC:1,7,18,0,0,b
FNC:1,7,24,0,5,c
FNC:1,7,30,0,0,b
FNC:1,7,36,0,2,a
FNL:2,9,12
FNA:2,1,dispatch
FNC:2,11,15,0,2,Circle::area
FNC:2,11,15,1,0,Square::area
FNC:2,11,27,0,1,Circle::area
FNC:2,11,36,0,1,ext
FNL:3,13,16
FNA:3,1,drop
FNC:3,15,12,0,4,c
FNC:3,15,18,0,0,a
FNL:4,17,20
FNA:4,1,main
FNC:4,19,12,0,1,both
FNC:4,19,21,0,1,mix
FNF:5
FNH:5
FNCF:15
FNCH:10
DA:1,1
DA:3,1
DA:5,1
DA:7,5
DA:9,1
DA:11,3
DA:13,1
DA:15,4
DA:17,1
DA:19,1
LF:10
LH:10
end_of_record
EOF

# ----------------------------------------------------------------------
echo "*** 1. every category, and the totals"
# ----------------------------------------------------------------------
runGenhtml diff --callgraph --show-proportion -o html \
    --baseline-file base.info --diff-file c.udiff curr.info

# The per-file breakdown, in display order.  The numbers are of the rows of the
#   callees page:  the two records at 3:24 lead to one destination and are one
#   row.  'aa' took it, so the row is hit and categorized 'GIC'.  20 sites:
#   the 14 current rows, the two the baseline had at a line which still exists,
#   and the four on baseline lines the diff deleted.  Those six have no row on
#   any page; they are counted as their records are.
# The fixture writes a sixteenth current record - 11:36 calls 'ext', which no file
#   of this report defines - and it is in none of these numbers:  a call whose
#   callee the report cannot name is dropped, and it is dropped out of both
#   versions, so it produces no category at all rather than the 'DUB'/'DCB' of
#   something the diff removed.  The baseline is resolved by the same rule as the
#   current data, so the site is not on either side of the comparison
checkLine diff diff.log \
    '    callgraph: UNC:1 LBC:1 UBC:2 GBC:1 GIC:1 GNC:4 CBC:4 EUB:1 ECB:1 DUB:1 DCB:3'

# ..and the two places the same numbers are said as a proportion.  Only the
#   sites which are in the current version are in the totals - a '.info' knows
#   nothing about a baseline - so this is 14 and not 20.  They are the numbers of
#   the header of the callees page
checkLine diff diff.log '  lines=9 hit=9 functions=4 hit=4 callgraph=14 hit=10'
checkPattern diff diff.log '  callgraph\.+: 71\.4% \(10 of 14 callees\)'

# 'lib.cpp' contains no calls, so it has no line of its own here:  the file is
#   only in this report as a callee, and the caller-side total of a file with no
#   call sites is not a 0/0 rate to display
checkLine diff diff.log '  lines=5 hit=4 functions=6 hit=5'
checkNoLine diff diff.log '  lines=5 hit=4 functions=6 hit=5 callgraph='

# ----------------------------------------------------------------------
echo "*** 2. the two directions of the callgraph, a page each"
# ----------------------------------------------------------------------
# Each direction of the callgraph is a page of its own:  the calls each function
#   of the file makes, and the calls made to it.  A function is on the page of a
#   direction only when it has something to say there, so the two pages of one
#   file need not list the same functions - and a file whose functions all make
#   no calls has no 'callees' page at all.
# This is read out of the pages rather than eyeballed because the two directions
#   are generated by different code from different data - the callees from the
#   function's own records, the callers from the derived index - and the
#   assertion worth making is that they agree with each other.
cat >dump.pl <<'EOF'
#!/usr/bin/env perl

# Print the table of one genhtml call site page, one row per line, as
#   <function>|<row anchor>|<cell>|<cell>|..
# A page holds one direction of the callgraph, so a line here is one row of it:
#   the cells of a row, in order, with the cells the row above spans left out -
#   which is the point.  A cell whose text is a link within the page carries its
#   destination as '>#anchor', which is what the category and annotation chains
#   are;  a cell which is the anchor of a call site group carries it as '{id}'.
# The function field is the name cell, which only the first row of a function
#   carries:  '*N' is the number of rows it spans and each '{...}' one of the
#   notes it adds below the name.  The rest of that function's rows repeat the
#   name alone.

use strict;
use warnings;

sub strip($)
{
    # the text of one cell, with the markup which decorates it taken out
    my $text = defined($_[0]) ? $_[0] : '';
    $text =~ s/<[^>]*>//g;
    return $text;
}

sub text($)
{
    my $text = strip($_[0]);
    $text =~ s/&lt;/</g;
    $text =~ s/&gt;/>/g;
    $text =~ s/&amp;/&/g;
    $text =~ s/&nbsp;/ /g;
    $text =~ s/&[lr]dquo;/"/g;
    return $text;
}

my $file = $ARGV[0];
open(my $fh, '<', $file) or die("cannot open $file: $!");
my $func = '';
my ($inTable, $inRow, $isHead, $anchor, $marks) = (0, 0, 0, '-', '');
my @cells;
while (my $line = <$fh>) {
    chomp($line);
    # the page has other tables on it - the file header is one - so the rows of
    #   the one table this dump is about are the rows of the centered table
    $inTable = 1 if $line =~ /<center>/;
    if ($line =~ /<\/table>/) {
        $inTable = 0;
        next;
    }
    next unless $inTable;
    if ($line =~ /^\s*<tr\b([^>]*)>\s*$/) {
        my $attr = $1;
        $anchor = $attr =~ /\bid="([^"]*)"/ ? $1 : '-';
        ($inRow, $isHead, $marks) = (1, 0, '');
        @cells = ();
        next;
    }
    next unless $inRow;
    if ($line =~ /^\s*<\/tr>\s*$/) {
        $inRow = 0;
        print(join('|', $func . $marks, $anchor, @cells), "\n") unless $isHead;
        next;
    }
    $isHead = 1 if $line =~ /class="tableHead"/;
    next unless $line =~ /<td\b([^>]*)>(.*)<\/td>\s*$/;
    my ($attr, $body) = ($1, $2);
    if ($attr =~ /class="calleeFn(?:Alt)?"/) {
        # the name cell, which spans the rows of one function and may carry a
        #   note about its callers and a link to the other direction
        # ..printed as the page writes it, escapes and all, where the cells are
        #   unescaped:  the two together show that the name is escaped in both
        #   the name cell and the cell of whoever calls it
        my ($name, @notes) = split(/<br>/, $body);
        $func  = strip($name);
        $marks = '*' . ($attr =~ /rowspan="(\d+)"/ ? $1 : 1);
        $marks .= '{' . strip($_) . '}' foreach (@notes);
        next;
    }
    my $cell = text($body);
    # a link which stays on this page is one of the chains which tour a category,
    #   an author or a date bin, so where it leads is the assertion
    $cell .= '>' . $1 if $body =~ /<a[^>]*\bhref="(#[^"]*)"/;
    # the location cell of a group carries the group's own anchor;  say so, since
    #   it is what the source view and the back-links point at
    $cell .= '{' . $1 . '}' if $attr =~ /\bid="([^"]*)"/;
    # ..and a cell which spans more than its own row is one cell for the run of
    #   rows below it:  '^N' is how many, and the rows it covers do not have one
    $cell .= '^' . $1 if $attr =~ /\browspan="(\d+)"/ && $1 > 1;
    push(@cells, $cell);
}
close($fh);
EOF

checkColumns()
{
    # checkColumns label page <<expected
    #   the headings of the table of 'page', top to bottom of the heredoc, left to
    #   right of the page.  Which side of the name the callgraph columns are on is
    #   a decision about the page and not about the data, and the row dumps below
    #   cannot see it:  they take the name cell out of the row, so a column moving
    #   past it leaves them unchanged
    local label=$1
    local page=$2
    if [ ! -f $page ] ; then
        fail $label "$page was not written"
        cat > /dev/null
        return
    fi
    cat > $label.columns.expect
    perl -ne 'next unless m|<td class="tableHead"[^>]*>(.*?)</td>|;
              my $head = $1;
              $head =~ s/<[^>]*>//g;   # the heading of a sortable column links
              $head =~ s/\s+$//;
              print("$head\n");' $page > $label.columns.actual
    if ! diff -u $label.columns.expect $label.columns.actual ; then
        fail $label "unexpected columns in $page"
    fi
}

checkTables()
{
    # checkTables label page <<expected
    local label=$1
    local page=$2
    if [ ! -f $page ] ; then
        fail $label "$page was not written"
        cat > /dev/null
        return
    fi
    cat > $label.expect
    perl dump.pl $page > $label.actual
    if ! diff -u $label.expect $label.actual ; then
        fail $label "unexpected call site table in $page"
    fi
}

# The callers page of the file which does the calling, in the order the page is
#   in:  by function name, which is how a reader looks one up.  The column before
#   the name is the way to the other side of the callgraph and the one after it is
#   the proportion of this function's own side of it which the tests exercised,
#   and neither of them is a column the caller rows fill:  they belong to the
#   function, so they span its rows and only its first row carries them.
#   The name cell is dumped separately, so it is the '*<rows>' after the function
#   name rather than a field of its own, which is why the first field below is the
#   cell which leads to the other direction
# Nothing in the report calls 'main', and it ran anyway, so its one row names no
#   call site:  the count is the difference between the times it was entered and
#   the times a known site entered it, which is a fact about the callee and has no
#   TLA of its own - it is not a coverpoint and has no baseline to be compared
#   against.  It is in neither half of the proportion for the same reason, which
#   is what leaves 'main' with no proportion at all - '-', and not '0 / 0', which
#   would invite the reader to divide two numbers which are not one.  That is what
#   its name cell's note says, in the one place a reader of the whole page will
#   see it;  the other three functions are entered exactly as often as their one
#   caller says, so they have neither the row nor the note
checkTables caller html/proj/c.cpp.callers.html <<'EOF'
both*1|caller_both_0|100.0 % (2 / 2)|100.0 % (1 / 1)|main|c.cpp:15:13|GNC>#top^2|1>#top
dispatch*1|caller_dispatch_0|66.7 % (2 / 3)|100.0 % (1 / 1)|main|c.cpp:16:30|1>#top
main*1{external callers only}|-|80.0 % (4 / 5)|-|<deduced external callers>|||(1)
mix*1|caller_mix_0|50.0 % (2 / 4)|100.0 % (1 / 1)|main|c.cpp:16:22|GNC>#top|1>#top
EOF

# ..and the callees page of the same file, which is the same four functions the
#   other way round.  All four make calls and all four are called, so both pages
#   list all four - and every row of both leads to the other one, with the
#   proportion of that direction as the text of the link.  Except 'main' here:
#   its one caller is outside the report and has no count, so there is no
#   proportion to show, and the cell is empty rather than a link reading '-'.
# 11:15 is one location with two destinations, so its second row has no location
#   cell of its own.
# 'dispatch' also made the call to 'ext' which scenario 1 describes, and what is
#   left of it is the '<external callee>' row:  it says that the call existed
#   without naming a callee the report no longer has.  Its location, category and
#   count cells are all empty even here, where every other row of the page has a
#   category - the site which carried all three is what was dropped, and a
#   differential category is a comparison of two sides neither of which has it.
#   It is in neither half of 'dispatch's proportion either, which is why that is
#   2 of 3 and not 2 of 4
# The category cell of a row leads to the next group of its own category:  past
#   the whole run of rows which share it, to the next row which has it again, and
#   to the top of the page when there is no later one.  So the three contiguous
#   'CBC' rows of 'both' and 'dispatch' form one chain and the two 'GNC' rows of
#   'main' at 15:13 and 16:12 both lead past 16:16 to 16:22
# The row at 3:24 is the two records of the fixture, 'a' (UIC, not taken) and
#   'aa' (GIC, taken).  The row was taken, so it is 'GIC':  a category has to
#   agree with the count it is shown with
checkTables callee html/proj/c.cpp.callees.html <<'EOF'
both*2|site_3_12_1|100.0 % (1 / 1)^2|100.0 % (2 / 2)^2|3:12{site_3_12}|a|CBC>#site_11_15_1|3>#site_11_27_1
both|site_3_24_1|3:24{site_3_24}|a, aa|GIC>#top|2>#site_11_27_1
dispatch*4|site_11_15_1|100.0 % (1 / 1)^4|66.7 % (2 / 3)^4|11:15{site_11_15}^2|Circle::area|CBC>#site_11_27_1|2>#site_11_27_1
dispatch|site_11_15_2|Square::area|UBC>#site_7_12_1|0>#site_16_16_1
dispatch|site_11_27_1|11:27{site_11_27}|Circle::area|CBC>#site_7_36_1|1>#site_16_22_1
dispatch|-||<external callee>||
main*5|site_15_13_1|^5|80.0 % (4 / 5)^5|15:13{site_15_13}|both|GNC>#site_16_22_1^2|1>#site_16_22_1
main|site_16_12_1|16:12{site_16_12}|c|1>#site_16_22_1
main|site_16_16_1|16:16{site_16_16}|c|UNC>#top|0>#site_7_12_1
main|site_16_22_1|16:22{site_16_22}|mix|GNC>#top^2|1>#site_7_18_1
main|site_16_30_1|16:30{site_16_30}|dispatch|1>#site_7_18_1
mix*4|site_7_12_1|100.0 % (1 / 1)^4|50.0 % (2 / 4)^4|7:12{site_7_12}|a|UBC>#top|0>#site_7_24_1
mix|site_7_18_1|7:18{site_7_18}|b|GBC>#top|4>#site_7_36_1
mix|site_7_24_1|7:24{site_7_24}|c|LBC>#top|0>#top
mix|site_7_36_1|7:36{site_7_36}|a|CBC>#top|2>#top
EOF

# ..and the callers page of the file which is only called:  'lib.cpp' holds no
#   call data of its own, so not one of its functions has anything to say in the
#   other direction and the report has no callees page for it at all.  Hence also
#   no link to the other direction in any of these name cells - the page a link
#   leads to has to exist
if [ -f html/proj/lib.cpp.callees.html ] ; then
    fail callee "a callees page was written for a file which makes no calls"
fi
# The two symbols at line 1 are one entry with two aliases, and their callers
#   tell them apart:  they are two alias groups, laid out as the function table
#   lays them out.  The function comes first with its summary block:  one row
#   per unique call site of both groups, beside its name and the proportion of
#   all of those sites, which span the block - and then each group's callers,
#   beside a cell naming the group and the proportion of its own callers.  The
#   site at 3:24, which leads to both groups, is under both of them and is one
#   row of the summary, hit since 'aa' took it:  'UIC' in 'a' and 'GIC' in 'aa'
#   are one call which is 'GIC', so the function has three of four sites hit.
#   The summary is in the order a reader fixing the tests wants it:  the worst
#   category first, then the fewest calls, then the location - so the 'UBC' at
#   7:12, then the 'GIC', then the two 'CBC's, the one with fewer calls first.
#   The category and count chains tour the groups too:  'GIC' at 3:24 leads to
#   the row of 'aa' which has it
checkTables callee html/proj/lib.cpp.callers.html <<'EOF'
Circle::area*2|caller_Circle::area_0|100.0 % (2 / 2)^2|dispatch|c.cpp:11:15|CBC>#caller_a_2^2|2>#caller_a_1
Circle::area|caller_Circle::area_1|dispatch|c.cpp:11:27|1>#caller_a_1
Square::area*1|caller_Square::area_0|0.0 % (0 / 1)|dispatch|c.cpp:11:15|UBC>#caller_a_6^2|0>#caller_a_5
a*4|caller_a_0|75.0 % (3 / 4)^4|mix|c.cpp:7:12|0>#caller_a_5
a|caller_a_1|both|c.cpp:3:24|GIC>#caller_a_8|2>#caller_a_7
a|caller_a_2|mix|c.cpp:7:36|CBC>#caller_a_7^3|2>#caller_a_7
a|caller_a_3|both|c.cpp:3:12|3>#caller_a_7
a|caller_a_4|a{group_a}^4|50.0 % (2 / 4)^4|both|c.cpp:3:12|3>#caller_a_7
a|caller_a_5|both|c.cpp:3:24|UIC>#top|0>#caller_c_0
a|caller_a_6|mix|c.cpp:7:12|UBC>#top|0>#caller_c_0
a|caller_a_7|mix|c.cpp:7:36|CBC>#top|2>#caller_c_1
a|caller_a_8|aa{group_aa}|100.0 % (1 / 1)|both|c.cpp:3:24|GIC>#top|2>#caller_c_1
b*1|caller_b_0|100.0 % (1 / 1)|mix|c.cpp:7:18|GBC>#top|4>#caller_c_1
c*3|caller_c_0|33.3 % (1 / 3)^3|mix|c.cpp:7:24|LBC>#top|0>#caller_c_2
c|caller_c_1|main|c.cpp:16:12|GNC>#top|1>#top
c|caller_c_2|main|c.cpp:16:16|UNC>#top|0>#top
EOF

# ..and neither page of 'c.cpp' carries the note the name cells used to, since
#   the way to the other direction is a column of its own:  one cell per function,
#   in the same place on every row, whether or not that function has one
for page in c.cpp.callers c.cpp.callees ; do
    checkNoLine xref html/proj/$page.html 'calleeFnNote"><a href='
done
# 'lib.cpp' has no callees page, so its callers page has no column leading to one
#   - a column no function of the file could have an entry in is not written at all
checkNoLine xref html/proj/lib.cpp.callers.html 'class="calleeXref'
checkNoLine xref html/proj/lib.cpp.callers.html '<td class="tableHead">Callee</td>'
# ..and the function table of each of the two files names the directions that file
#   has:  both of them for the caller, and only the one for the file which is
#   called and calls nothing
checkPattern xref html/proj/c.cpp.func.html '<td class="tableHead">Callers <span'
checkPattern xref html/proj/c.cpp.func.html '<td class="tableHead">Callgraph <span'
checkPattern xref html/proj/lib.cpp.func.html '<td class="tableHead">Callers <span'
checkNoLine xref html/proj/lib.cpp.func.html '<td class="tableHead">Callgraph'
# ..and in the function table those columns are at the right, with the other
#   proportions of the function - one column per direction:  the callee side had
#   a column on each side of the name, saying the same thing twice
checkColumns xref html/proj/c.cpp.func.html <<'EOF'
Function Name
TLA
Hit count
Lines
Callers
Callgraph
EOF
# ..while on the two call site pages the other direction stays left of the name:
#   there the cell is the only thing naming the other page
checkColumns xref html/proj/c.cpp.callers.html <<'EOF'
Callee
Function Name
Rate
Called from
Call site
TLA
Count
EOF
checkColumns xref html/proj/c.cpp.callees.html <<'EOF'
Caller
Function Name
Rate
Call site
Callee
TLA
Count
EOF
# ..and an alias has no link of its own in either column:  the callgraph pages
#   list a function under its leader symbol, which is the row above it.  Each
#   proportion leads to this function's own entry on the page of that direction,
#   and is written and coloured as every other proportion of this table is
checkLine xref html/proj/lib.cpp.func.html \
    '<td class=coverPerMed><a href="lib.cpp.callers.html#func_a" title="Click to go to the callers of this function">75.0&nbsp;% (3 / 4)</a></td>'
checkLine xref html/proj/lib.cpp.func.html \
    '<td class=coverPerHi><a href="lib.cpp.callers.html#func_Circle::area" title="Click to go to the callers of this function">100.0&nbsp;% (2 / 2)</a></td>'
checkLine xref html/proj/lib.cpp.func.html \
    '<td class=coverPerLo><a href="lib.cpp.callers.html#func_Square::area" title="Click to go to the callers of this function">0.0&nbsp;% (0 / 1)</a></td>'
checkNoLine xref html/proj/lib.cpp.func.html 'class="calleeXref'
# ..and a function none of whose rows carries a count has no proportion to
#   show:  there is no honest percentage of nothing, so the cell is empty and
#   leads nowhere - 'main' is called from outside this report and from nowhere it
#   names
checkLine xref html/proj/c.cpp.func.html '<td class="coverFn"></td>'
checkNoLine xref html/proj/c.cpp.func.html 'c.cpp.callers.html#func_main'
checkNoLine xref html/proj/lib.cpp.func.html '#func_aa'

# ..and the row of a group says on hover what a group is, the name it carries
#   being one which need not appear in the sources at all
if [ -f html/proj/lib.cpp.callers.html ] &&
    ! grep -q -F -e 'one alias group of this function' \
    html/proj/lib.cpp.callers.html ; then
    fail callee "the row of an alias group does not say what a group is"
fi
# ..and in the function table each group is a row under the function, with its
#   own category and count, and the proportion of its own callers - leading to
#   its rows on the callers page.  The function's row has the proportion of all
#   of its call sites, 3 of 4 - the site under both groups is one site
checkLine groups html/proj/lib.cpp.func.html \
    'lib.cpp.callers.html#func_a" title="Click to go to the callers of this function">75.0&nbsp;% (3 / 4)'
checkLine groups html/proj/lib.cpp.func.html \
    'lib.cpp.callers.html#group_a" title="Click to go to the callers of this alias group">50.0&nbsp;% (2 / 4)'
checkLine groups html/proj/lib.cpp.func.html \
    'lib.cpp.callers.html#group_aa" title="Click to go to the callers of this alias group">100.0&nbsp;% (1 / 1)'

# The scaffolding which makes each page readable as a function at a time:  a
#   rule above the first row of each function, and the name cell of every second
#   function in the other of two colours.  Both are CSS classes rather than
#   markup, so they are asserted where they are emitted - a first row per
#   function, on every page, and the two colours in turn
for page in c.cpp.callers c.cpp.callees lib.cpp.callers ; do
    PAGE=html/proj/$page.html
    FIRST=`grep -c -F -e 'class="callgraphFirstRow"' $PAGE`
    NAMED=`grep -c -E 'class="calleeFn(Alt)?"' $PAGE`
    if [ "$FIRST" != "$NAMED" ] ; then
        fail rows "$page: $FIRST separator rows for $NAMED functions"
    fi
    # ..and they are the same rows:  a separator anywhere else would cut a
    #   function in half.  Asked of the whole row and not of the line after the
    #   separator, since the name is no longer the first cell of it - the column
    #   which leads to the other direction is left of the name, and the annotated
    #   page has two more columns left of that
    MISMATCH=`perl -ne 'if (m|^\s*<tr\b([^>]*)>|) {
                            $first = $1 =~ /callgraphFirstRow/ ? 1 : 0;
                            $named = 0;
                            next;
                        }
                        $named = 1 if m|class="calleeFn(?:Alt)?"|;
                        ++$bad if m|^\s*</tr>| && $first != $named;
                        END { print($bad + 0) }' $PAGE`
    if [ "$MISMATCH" != 0 ] ; then
        fail rows "$page: $MISMATCH rows separate what is not a function"
    fi
    perl -ne 'print("$1\n") if /class="callee(Fn|FnAlt)"/;' $PAGE > $page.actual
done
# the two pages of 'c.cpp' hold the same four functions, and 'lib.cpp' five
for page in c.cpp.callers c.cpp.callees ; do
    cat > $page.expect <<'EOF'
Fn
FnAlt
Fn
FnAlt
EOF
done
cat > lib.cpp.callers.expect <<'EOF'
Fn
FnAlt
Fn
FnAlt
Fn
EOF
for page in c.cpp.callers c.cpp.callees lib.cpp.callers ; do
    if ! diff -u $page.expect $page.actual ; then
        fail rows "$page: the name cells do not alternate"
    fi
done

# The link on a caller's name leads to the calls that caller makes, at the site
#   the row is about:  which row of the site group it is, so that a location with
#   several destinations does not land the reader on the wrong one - and on the
#   callees page of the file which defines the caller, which is the page that
#   list is on.  'Square::area' is the second row of 11:15 and 'Circle::area' the
#   first
# ..and it is a report-root-relative path, because a caller need not be in the
#   same directory as the function it calls
checkLine callee html/proj/lib.cpp.callers.html \
    'href="../proj/c.cpp.callees.html#site_11_15_2"'
checkLine callee html/proj/lib.cpp.callers.html \
    'href="../proj/c.cpp.callees.html#site_11_15_1"'

# ..and the other way round:  the link on a callee's name leads to that callee's
#   own callers page, which is the list of everything else that calls it
checkLine caller html/proj/c.cpp.callees.html \
    'href="../proj/lib.cpp.callers.html#func_Circle::area"'

# Both pages are in both orders, and each of them says which one it is:  the
#   heading of the order the page is already in is the only one without a link,
#   exactly as in the function table
for view in callers callees ; do
    checkLine sort html/proj/c.cpp.$view.html \
        "<a href=\"c.cpp.$view-c.html\">"
    checkLine sort html/proj/c.cpp.$view-c.html \
        "<a href=\"c.cpp.$view.html\">"
done
# ..the second of them by how much of that direction the tests exercised, least
#   first, ties by name:  'mix' made two of its four calls, 'dispatch' two of
#   three, 'main' four of five and every call 'both' makes was made
perl dump.pl html/proj/c.cpp.callees-c.html |
    perl -ne 'print("$1\n") if /^([^|*]+)\*/;' > order.actual
cat > order.expect <<'EOF'
mix
dispatch
main
both
EOF
if ! diff -u order.expect order.actual ; then
    fail sort "unexpected order on the unexercised-callee page"
fi
# ..which is the proportion and not the count of unexercised rows behind it, as
#   the callers of 'lib.cpp' show:  'Square::area' has one caller and it never
#   called, so it is the first function a reader should look at, while 'a' and 'c'
#   each have two callers which never called - more rows left, but a smaller share
#   of them.  Ties at every call made go by name, and an upper case letter sorts
#   before a lower case one
perl dump.pl html/proj/lib.cpp.callers-c.html |
    perl -ne 'print("$1\n") if /^([^|*]+)\*/;' > order_c.actual
cat > order_c.expect <<'EOF'
Square::area
c
a
Circle::area
b
EOF
if ! diff -u order_c.expect order_c.actual ; then
    fail sort "unexpected order on the unexercised-caller page"
fi
# ..and a reader who followed a link keeps the order they were in:  the way to
#   the other direction, to another file and to the other page of this one are
#   all named with the suffix of the page they are on
checkLine sort html/proj/c.cpp.callees-c.html 'href="c.cpp.callers-c.html#func_mix"'
checkLine sort html/proj/lib.cpp.callers-c.html \
    'href="../proj/c.cpp.callees-c.html#site_11_15_1"'

# ----------------------------------------------------------------------
echo "*** 3. the per-function proportion, and the sort page"
# ----------------------------------------------------------------------
# One number per function in the function table:  the sites the function
#   *contains*.  That is not the number of rows in its 'callers' table, and the
#   two do not total to each other - which is exactly why both are shown.
# It counts the rows of the callees page, so 'both' is 2 of 2:  the two records
#   at 3:24 lead to one place and are one row, which was taken.  It is the Rate
#   of the function on that page
# ..and the cell is the way to the sites it counts:  a link to this function's
#   row of the call site page, which every function counted here has
TITLE='title="Click to go to the call sites of this function"'
for expect in \
    "<td class=coverPerHi><a href=\"c.cpp.callees.html#func_both\" $TITLE>100.0&nbsp;% (2 / 2)</a></td>" \
    "<td class=coverPerLo><a href=\"c.cpp.callees.html#func_mix\" $TITLE>50.0&nbsp;% (2 / 4)</a></td>" \
    "<td class=coverPerLo><a href=\"c.cpp.callees.html#func_dispatch\" $TITLE>66.7&nbsp;% (2 / 3)</a></td>" \
    "<td class=coverPerMed><a href=\"c.cpp.callees.html#func_main\" $TITLE>80.0&nbsp;% (4 / 5)</a></td>" ; do
    checkLine proportion html/proj/c.cpp.func.html "$expect"
done
# ..and each of those functions is on the page the link names.  The anchor is on
#   the name cell and not on the row, because the row is a call site's and carries
#   that site's anchor:  one row of the one table can be the answer to both links
for func in both mix dispatch main ; do
    checkLine proportion html/proj/c.cpp.callees.html \
        "id=\"func_$func\"><a href=\"c.cpp.gcov.html#L"
done

# ..and the file is sortable by how many of its sites are not taken, on a page
#   of its own like every other sort order
if [ ! -f html/proj/c.cpp.func-x.html ] ; then
    fail sortpage "no callee sort page was written"
else
    # 'mix' misses 2 of 4, 'dispatch' and 'main' one each, and 'both' none:
    #   most missed first, ties by name
    perl -ne 'print("$1\n") if /<td class="coverFn"><a href="[^"]*">([^<]*)</;' \
        html/proj/c.cpp.func-x.html > sortpage.actual
    cat > sortpage.expect <<'EOF'
mix
dispatch
main
both
EOF
    if ! diff -u sortpage.expect sortpage.actual ; then
        fail sortpage "unexpected order on the callee sort page"
    fi
fi

# ----------------------------------------------------------------------
echo "*** 4. the source view"
# ----------------------------------------------------------------------
# The identifier at each call site column is linked to that site's group in the
#   table above.  The column is the compiler's, and the source is the reader's -
#   so it is checked before it is used, and a column which does not hold one of
#   the site's callees is not decorated
checkLine source html/proj/c.cpp.gcov.html \
    '<a class="callSite" href="c.cpp.callees.html#site_3_12" data-calls="3: a">a</a>'

# a site which was never taken is marked as such, in the source as in the tables
checkLine source html/proj/c.cpp.gcov.html \
    '<a class="callSiteLo" href="c.cpp.callees.html#site_7_12" data-calls="0: a">a</a>'

# a site with more than one destination says how many, and says it with CSS
#   rather than with text - see the round trip in scenario 7
checkLine source html/proj/c.cpp.gcov.html \
    'data-calls="2: Circle::area&#10;0: Square::area">area</a><span class="calleeMulti" data-n="2"></span>'
COUNT=`grep -c -F -e 'class="calleeMulti" data-n=' html/proj/c.cpp.gcov.html`
if [ 1 != "$COUNT" ] ; then
    fail source "expected exactly one multi-destination marker, got $COUNT"
fi

# 16:12 is a call to 'c' whose column holds 't' - which is what a compiler does
#   with a nested call:  it folds the location of a call in an argument list onto
#   the enclosing expression.  No text on the line names 'c' at that column, so
#   the two verified reads both fail and 'strict_callee_match' decides what
#   happens.  By default it is 0, and the column is believed anyway - the text it
#   points at is linked to the site.  That is the answer C++ needs, where an
#   operator call, a virtual call and a call through a pointer are all written as
#   something other than the callee's name;  the cost is a case like this one,
#   where the identifier is on the line for another reason
checkLine source html/proj/c.cpp.gcov.html \
    '<a class="callSite" href="c.cpp.callees.html#site_16_12" data-calls="1: c">t</a>'
checkLine source html/proj/c.cpp.gcov.html \
    '<a class="callSite" href="c.cpp.callees.html#site_16_22" data-calls="1: mix">mix</a>'
# ..so nothing on this line needs the trailing comment or the line-number link
checkNoLine source html/proj/c.cpp.gcov.html '<a href="#site_16_12"'
checkNoLine source html/proj/c.cpp.gcov.html 'data-callee="c"'
# ..and the keyword just left of the call is not what gets linked:  the relaxed
#   read looks left of the column first, which here is 'return'
checkNoLine source html/proj/c.cpp.gcov.html '>return</a>'
# ..and a line with nothing wrong with it has no line-number link
checkNoLine source html/proj/c.cpp.gcov.html '<a href="#site_3_12"'

# 'strict_callee_match=1' is the other answer:  only a verified read decorates,
#   and a site like 16:12 is named in a comment appended to the line, whose text
#   the stylesheet generates - see the round trip in scenario 7.  A setting and
#   not an option, so it is set with '--rc'
runGenhtml strict --callgraph --baseline-file base.info --diff-file c.udiff \
    --rc strict_callee_match=1 -o html_strict curr.info
checkLine strict html_strict/proj/c.cpp.gcov.html \
    '<span class="callgraphAnnot"><a class="callSite callgraphAnnot" href="c.cpp.callees.html#site_16_12" title="call recorded at column 12" data-callee="c"></a></span>'
checkNoLine strict html_strict/proj/c.cpp.gcov.html \
    '#site_16_12" data-calls='
# ..and a site whose column does hold its callee's name is decorated either way
checkLine strict html_strict/proj/c.cpp.gcov.html \
    '<a class="callSite" href="c.cpp.callees.html#site_16_22" data-calls="1: mix">mix</a>'

# The dropped call to 'ext' is not pointed at either, since there is no longer a
#   row for the link to lead to.  The other two calls on the same line are still
#   decorated:  what was dropped is one site and not the line
checkNoLine source html/proj/c.cpp.gcov.html 'site_11_36'
checkLine source html/proj/c.cpp.gcov.html 'site_11_15'
checkLine source html/proj/c.cpp.gcov.html 'site_11_27'

# A site which is only in the baseline is not in the current source at all, so
#   it has no line to decorate:  ECB, EUB, DCB and DUB are in the tables and the
#   bins, and nowhere in the source view
checkNoLine source html/proj/c.cpp.gcov.html '#site_3_18'
checkNoLine source html/proj/c.cpp.gcov.html '#site_19_12'

# The CSS the above depends on.  A class which is emitted and not defined styles
#   nothing, and nothing says so - which is why it is asserted rather than
#   assumed;  'check_tla_css' does the same for the TLA classes, which the tables
#   also use
for class in 'a.callSite' 'a.callSiteLo' 'span.calleeMulti::after' \
    'span.callgraphAnnot::before' 'a.callgraphAnnot::after' \
    'span.callgraphCaption' 'span.calleeFnNote' \
    'td.calleeFn' 'td.calleeFnAlt' 'td.calleeAnnot' 'td.calleeAnnotAlt' \
    'td.calleeXref' 'td.calleeXrefAlt' \
    'tr.callgraphFirstRow td' \
    'td.callgraphNote' 'td.calleeFnAlias' 'td.coverCallgraph' \
    'td.coverCallgraphLo' 'td.coverCallgraphHi' 'td.coverCallgraphUnknown' \
    'tr.callgraphGroupRow td.coverCallgraph' 'tr.callgraphGroupRow td.coverPerLo' \
    'tr.fnGroupRow td.coverFn' 'tr.fnGroupRow td.tlaUNC' ; do
    checkLine css html/gcov.css "$class"
done
# ..and the cross-direction cell which leads somewhere is a proportion, coloured
#   by the 'coverPer' classes:  the three it was coloured by when it showed no
#   number are gone
for class in 'td.calleeXrefHi' 'td.calleeXrefMed' 'td.calleeXrefLo' ; do
    checkNoLine css html/gcov.css "$class"
done
check_tla_css html
if [ 0 != $? ] ; then
    fail css "TLA styles missing from the stylesheet"
fi

# ----------------------------------------------------------------------
echo "*** 5. owner and date bins"
# ----------------------------------------------------------------------
# A call site is at one point in the source, so the annotation of the line it is
#   on says who wrote the call and when - which is why this metric has owner and
#   date bins where function coverage does not.
# The dates are computed from the current time and not written down:  a literal
#   is a date which gets older every day, so the bin it lands in would depend on
#   when the suite ran.
cat >ann.pm <<'EOF'
package ann;

# Two owners and two dates, split at line 9 of the file:  'both' and 'mix' are
#   'bertie', 'dispatch' and 'main' are 'fred'.  So each owner bin holds nine call
#   sites of 'c.cpp' and the two bins between them hold every category which is
#   binned at all - which does not include the deleted ones.

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
    # three days ago:  inside the '(1,7] days' bin for the cutpoints below, and
    #   far enough from either edge that the run's own duration cannot move it
    my $recent =
        strftime('%Y-%m-%dT%H:%M:%S-00:00', gmtime(time() - 3 * 24 * 60 * 60));
    open(my $fh, '<', $file) or return (1, []);
    my @lines;
    my $n = 0;
    while (my $line = <$fh>) {
        chomp($line);
        ++$n;
        my $old = $n >= 9;
        my ($who, $mail) =
            $old ? ('fred', 'uncle.fred@ickenham.uk')
              : ('bertie', 'bertie.wooster@jeeves.co.uk');
        push(@lines,
             [$line, $who, $mail,
              $old ? '2020-01-01T00:00:00-00:00' : $recent, "CL$n"]);
    }
    close($fh);
    return (0, \@lines);
}

1;
EOF

# a criteria module which writes down what it was handed:  the point of the case
#   is that the call-site bins reach the callback, so the callback has to say so
cat >dumpcrit.pm <<'EOF'
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
                  ref($v) ? join(',', map({ "$_=$v->{$_}" } sort keys %$v)) :
                      $v,
                  "\n");
        }
    }
    close($fh);
    return (0, []);
}

1;
EOF

rm -f criteria_dump.txt
runGenhtml dates --callgraph --show-proportion -o html_dates \
    --baseline-file base.info --diff-file c.udiff curr.info \
    --annotate-script `pwd`/ann.pm --date-bins 1,7 --show-owners all \
    --criteria-script `pwd`/dumpcrit.pm \
    --rc criteria_callback_data=date --rc criteria_callback_levels=top

# bin 1 is '(1,7] days' - 'bertie' - and bin 2 is everything older.  Every
#   category which is binned at all is here;  'DUB' and 'DCB' are not, because a
#   deleted line has no annotation to bin it by.  As in every other count, the two
#   records at 3:24 are the one 'GIC' row of the page
checkLine dates criteria_dump.txt \
    'top|callgraph|1|CBC=2,ECB=1,EUB=1,GBC=1,GIC=1,LBC=1,UBC=1,found=8,hit=4'
checkLine dates criteria_dump.txt \
    'top|callgraph|2|CBC=2,GNC=4,UBC=1,UNC=1,found=8,hit=6'

rm -f criteria_dump.txt
runGenhtml owners --callgraph --show-proportion -o html_owners \
    --baseline-file base.info --diff-file c.udiff curr.info \
    --annotate-script `pwd`/ann.pm --show-owners all \
    --criteria-script `pwd`/dumpcrit.pm \
    --rc criteria_callback_data=owner --rc criteria_callback_levels=top

checkLine owners criteria_dump.txt \
    'top|callgraph|bertie|CBC=2,ECB=1,EUB=1,GBC=1,GIC=1,LBC=1,UBC=1,found=8,hit=4'
checkLine owners criteria_dump.txt \
    'top|callgraph|fred|CBC=2,GNC=4,UBC=1,UNC=1,found=8,hit=6'

# ..and the count in a bin is a link to the first call site in it - the half of
#   the bin data which the criteria callback never sees.  Line 7 holds the LBC
#   site 'mix -> c' and line 16 the UNC site 'main -> c';  the link names the
#   file by basename, because it is relative to the page it appears on
lbc='<a href="c.cpp.gcov.html#L7" class="tlaBgLBC" title="Go to first LBC callee'
unc='<a href="c.cpp.gcov.html#L16" class="tlaBgUNC" title="Go to first UNC callee'
checkLine owners html_owners/proj/index-bin_owner.html \
    "$lbc in 'bertie' bin in c.cpp\">"
checkLine owners html_owners/proj/index-bin_owner.html \
    "$unc in 'fred' bin in c.cpp\">"
# the other run bins by date:  three days ago lands in '(1,7]', 2020 does not
checkLine dates html_dates/proj/index-bin_date.html \
    "$lbc in '(1,7] days' bin in c.cpp\">"
checkLine dates html_dates/proj/index-bin_date.html \
    "$unc in '(7..) days' bin in c.cpp\">"
# ..and the same link from the file table, which is not binned at all
checkLine diff html/proj/index.html "$lbc in c.cpp\">"
# ..and on the callees page of the file, where the same numbers are a count of
#   the rows of the table below them, the link goes to the first row it counts
#   rather than to the source line:  the first UBC site on the page is the second
#   call of 'dispatch', which is fred's, while the first of bertie's is the first
#   call of 'mix' - 'both' and 'mix' being bertie's, and the page in name order.
#   The source view links the same bins to the lines those sites are on
for page in dates owners ; do
    checkLine $page html_$page/proj/c.cpp.callees.html \
        '<a href="#site_11_15_2" title="goto first UBC callee">2</a>'
    checkLine $page html_$page/proj/c.cpp.gcov.html \
        '<a href="#L11" title="goto first UBC callee in &ldquo;fred&rdquo; bin" class="tlaBgUBC">'
done
checkLine dates html_dates/proj/c.cpp.callees.html \
    '<a href="#site_7_12_1" title="goto first UBC callee in &ldquo;(1,7] days&rdquo; bin" class="tlaBgUBC">'
checkLine dates html_dates/proj/c.cpp.callees.html \
    '<a href="#site_11_15_2" title="goto first UBC callee in &ldquo;fred&rdquo; bin" class="tlaBgUBC">'
checkLine owners html_owners/proj/c.cpp.callees.html \
    '<a href="#site_7_12_1" title="goto first UBC callee in &ldquo;bertie&rdquo; bin" class="tlaBgUBC">'
# ..and the header of the callers page counts the rows of the table below it
#   too, which are not the call sites of this file but the calls into it:  every
#   one of the three calls made to a function of 'c.cpp' was taken, while half
#   of the calls its own functions make were not.  They are binned by the
#   function called, which is the date and author the Age and Owner columns
#   show - 'both' being bertie's and recent, 'dispatch' fred's and old - and each
#   number leads to the first row it counts
# The titles of the callgraph numbers of the header, which say which call sites
#   they count - not the same ones on the callers page as anywhere else
INTO="Callgraph edge sources in this file (number of callee sites):  each call location in the table below, once per alias of the function it calls - or, for a function shown as alias groups, once:  its unique call sites.  See 'unique call site' in genhtml(1)"
FROM_TAIL=" (number of caller sites):  every call site record, including several at one location - which the call site pages count as one unique call site where they call the same function.  See 'unique call site' in genhtml(1)"
for page in dates owners ; do
    checkLine $page html_$page/proj/c.cpp.callers.html \
        '<a href="#caller_both_0" title="goto first GNC callee">3</a>'
    checkLine $page html_$page/proj/c.cpp.callers.html \
        '<a href="#caller_dispatch_0" title="goto first GNC callee in &ldquo;fred&rdquo; bin" class="tlaBgGNC">1</a>'
    checkLine $page html_$page/proj/c.cpp.callers.html \
        '<a href="#caller_both_0" title="goto first GNC callee in &ldquo;bertie&rdquo; bin" class="tlaBgGNC">2</a>'
    # ..and that header says what it is counting, since it is the one page of
    #   the report on which the callgraph numbers are not the calls a file makes
    checkLine $page html_$page/proj/c.cpp.callers.html \
        "<td class=\"headerItem\" title=\"$INTO\">Callgraph:</td>"
    checkLine $page html_$page/proj/c.cpp.callers.html \
        "<span title=\"$INTO\">Callgraph coverage ownership bins</span>"
    checkNoLine $page html_$page/proj/c.cpp.callers.html 'edge destinations'
    # ..and the other pages of the file - its source view, its function detail
    #   page and its callees page - say that theirs are the calls it makes, as
    #   do the directory and the project, of the files they sum
    for p in callees gcov func ; do
        checkLine $page html_$page/proj/c.cpp.$p.html \
            "<td class=\"headerItem\" title=\"Callgraph edge destinations in this file$FROM_TAIL\">Callgraph:</td>"
        checkLine $page html_$page/proj/c.cpp.$p.html \
            "<span title=\"Callgraph edge destinations in this file$FROM_TAIL\">Callgraph coverage ownership bins</span>"
        checkNoLine $page html_$page/proj/c.cpp.$p.html 'edge sources'
    done
    checkLine $page html_$page/proj/index.html \
        "<td class=\"headerItem\" title=\"Callgraph edge destinations in this directory$FROM_TAIL\">Callgraph:</td>"
    checkLine $page html_$page/index.html \
        "<td class=\"headerItem\" title=\"Callgraph edge destinations in this project$FROM_TAIL\">Callgraph:</td>"
    checkNoLine $page html_$page/index.html 'edge sources'
done
checkLine dates html_dates/proj/c.cpp.callers.html \
    '<a href="#caller_both_0" title="goto first GNC callee in &ldquo;(1,7] days&rdquo; bin" class="tlaBgGNC">2</a>'
checkLine dates html_dates/proj/c.cpp.callers.html \
    '<a href="#caller_dispatch_0" title="goto first GNC callee in &ldquo;(7..) days&rdquo; bin" class="tlaBgGNC">1</a>'
checkLine dates html_dates/proj/c.cpp.callers.html \
    "<span title=\"$INTO\">Callgraph coverage date bins:</span>"
checkLine dates html_dates/proj/c.cpp.gcov.html \
    "<span title=\"Callgraph edge destinations in this file$FROM_TAIL\">Callgraph coverage date bins:</span>"

# ----------------------------------------------------------------------
echo "*** 6. a filtered report"
# ----------------------------------------------------------------------
# '--select-script' throws lines away after the totals have been computed, so
#   every metric has to un-count what it drops.  Selecting only the lines up to
#   7 keeps 9 and 11 as context - the region is five lines wide - and drops 13,
#   15 and 16:  'main' and its five call sites, four of which were taken
cat >select.pl <<'EOF'
#!/usr/bin/env perl

# select(userArgs.., lineDataJson, annotateDataJson, fileName, lineNumber):
#   print 1 to keep the line, 0 to drop it.  A deleted line is keyed by its
#   baseline number with a '<<<' prefix.

use strict;
use warnings;

my $max  = shift(@ARGV);
my $line = $ARGV[3];
$line =~ s/^<+//;
print(($line <= $max) ? "1\n" : "0\n");
EOF
# ..which is exec'd, not 'require'd like the two callbacks above
chmod +x select.pl

runGenhtml select --callgraph --show-proportion -o html_select \
    --baseline-file base.info --diff-file c.udiff curr.info \
    --select-script `pwd`/select.pl,7

checkPattern select select.log '  callgraph\.+: 66\.7% \(6 of 9 callees\)'
# the bins are accumulated per line, so they show the same nine sites
checkLine select select.log \
    '    callgraph: LBC:1 UBC:2 GBC:1 GIC:1 CBC:4 EUB:1 ECB:1'
# ..and the dropped lines are gone from the source view, and so is the function
#   whose definition was on one of them:  'main' is on line 13, so the filter took
#   it out of the function table and out of both call site pages with it
checkNoLine select html_select/proj/c.cpp.gcov.html 'site_16_22'
checkNoLine select html_select/proj/c.cpp.func.html 'func_main'
for view in callers callees ; do
    checkNoLine select html_select/proj/c.cpp.$view.html 'id="func_main"'
done
# ..but the calls it made are facts about the functions it called, which the filter
#   did not touch:  each of the other three still has the row saying 'main' called
#   it, at the site where it did - as text, because the line and the site it would
#   lead to are not on the pages any more.  The same holds in the other file,
#   which cannot know what this one shows:  which part of a file the filter keeps
#   is decided where that file is written, in a pass and possibly a process of
#   its own, so a link to another file is not written at all
checkLine select html_select/proj/c.cpp.callers.html \
    '<td class="coverCallgraph">main</td>'
checkLine select html_select/proj/c.cpp.callers.html \
    '<td class="coverCallgraph">c.cpp:16:22</td>'
for f in c lib ; do
    checkNoLine select html_select/proj/$f.cpp.callers.html 'c.cpp.gcov.html#L16'
    checkNoLine select html_select/proj/$f.cpp.callers.html 'callees.html#site_16'
done
checkLine select html_select/proj/lib.cpp.callers.html \
    '<td class="coverCallgraph">c.cpp:16:12</td>'

# A selection with holes in it, and no context around what it keeps:  the
#   definitions of 'dispatch' and 'main', a line of the body of 'mix' and the
#   last line of 'main'.  Whatever a page leads to has to be on the page it
#   leads to - which the validator checks, page by page
cat >pick.pl <<'EOF'
#!/usr/bin/env perl

# select(lines.., lineDataJson, annotateDataJson, fileName, lineNumber):
#   keep the listed lines of 'c.cpp', and nothing else

use strict;
use warnings;

my @keep = splice(@ARGV, 0, @ARGV - 4);
my ($file, $line) = @ARGV[2, 3];
$line =~ s/^<+//;
print(((grep({ $_ == $line } @keep) && $file =~ /c\.cpp$/) ? 1 : 0), "\n");
EOF
chmod +x pick.pl
runGenhtml pick --validate --callgraph --show-proportion -o html_pick \
    --baseline-file base.info --diff-file c.udiff curr.info \
    --select-script `pwd`/pick.pl,7,9,13,16 --rc num_context_lines=0
# ..which is the deleted lines' business too:  each is shown beside a current
#   line, which is where the filter has to look at it - so the line the header
#   leads to as the first of its category is one the source view shows
checkLine pick html_pick/proj/c.cpp.gcov.html \
    '<a href="#L16" title="goto first GNC line">1</a>'
checkNoLine pick html_pick/proj/c.cpp.gcov.html '<span id="L15"'
# the sites on line 7 are in the body of 'mix', which the filter took out of the
#   tables:  each still says what it calls, and leads nowhere.  Those on line 16
#   belong to 'main', which is in them
checkLine pick html_pick/proj/c.cpp.gcov.html \
    '<a class="callSite" data-calls="4: b">b</a>'
checkLine pick html_pick/proj/c.cpp.gcov.html \
    '<a class="callSite" href="c.cpp.callees.html#site_16_22" data-calls="1: mix">'
# ..and a site on a line which is not shown is named without a link, and so is
#   a callee the filter took out ('both') or which is defined in another file
#   ('Circle::area').  A callee which is listed is linked to
checkLine pick html_pick/proj/c.cpp.callees.html \
    '<td class="coverCallgraphHi" rowspan="2" id="site_11_15">11:15</td>'
checkLine pick html_pick/proj/c.cpp.callees.html \
    '<td class="coverCallgraph">both</td>'
checkLine pick html_pick/proj/c.cpp.callees.html \
    '<td class="coverCallgraph">Circle::area</td>'
checkLine pick html_pick/proj/c.cpp.callees.html \
    'id="site_16_30"><a href="c.cpp.gcov.html#L16"'
checkLine pick html_pick/proj/c.cpp.callees.html \
    '<a href="../proj/c.cpp.callers.html#func_dispatch"'
checkLine pick html_pick/proj/c.cpp.callers.html \
    '<a href="../proj/c.cpp.callees.html#site_16_30_1"'
# ..and the name of a function leads a couple of lines above its definition,
#   or to the first line from there which is shown:  'dispatch' can go to line 7,
#   'main' only to the line its definition is shown beside
for page in func callers callees ; do
    checkLine pick html_pick/proj/c.cpp.$page.html \
        '<a href="c.cpp.gcov.html#L7">dispatch</a>'
    checkLine pick html_pick/proj/c.cpp.$page.html \
        '<a href="c.cpp.gcov.html#L12">main</a>'
done

# ----------------------------------------------------------------------
echo "*** 7. the source survives the round trip"
# ----------------------------------------------------------------------
# 'html2lcov' recovers the source of a report by stripping the tags out of each
#   line of the source view.  Decorating a call site splices tags into that text,
#   which is harmless - but splicing any *text* would not be, and neither would a
#   bare '>' inside an attribute value, which would end the tag early and take
#   the rest of the line with it.  So the guard on the source view is that the
#   report still recovers the source it was built from, byte for byte.
runGenhtml save --callgraph --show-proportion -o html_save --save curr.info

$COVER $HTML2LCOV_TOOL html_save --callgraph --source-directory proj -o rt \
    --ignore empty,unused 2>&1 | tee rt.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail roundtrip "html2lcov failed:" `grep -E 'ERROR' rt.log`
fi
if [ -s rt.udiff ] ; then
    fail roundtrip "the recovered source differs from the source it was built from"
    cat rt.udiff
fi
checkLine roundtrip rt.rpt '0 changed, 0 added, 0 removed, 2 unchanged'
# ..and the call records came back with it.  This is an exact comparison, which is
#   why 'lib.cpp' carries an 'FNCF:0'/'FNCH:0' pair in the fixture above:  that is
#   what the writer emits for a file which has functions but no call sites, so a
#   recovered tracefile has it whether the input did or not
if [ -f rt.info ] &&
   ! diff -u <(fncRecords curr.info) <(fncRecords rt.info) ; then
    fail roundtrip "the recovered call records do not match"
fi

# ----------------------------------------------------------------------
echo "*** 8. a caller which is in no baseline"
# ----------------------------------------------------------------------
# A baseline which predates 'c.cpp' entirely - 'lib.cpp' is in it and 'c.cpp' is
#   not, which is what a report of a newly added file looks like.  Its sites are
#   then 'included code' on the lines the diff leaves alone and 'new code' on the
#   two it inserts.
# The assertion is that the two categorizations agree.  A site is categorized
#   twice - once by the file it is in, when that file's page is built, and once
#   for every file in the parent, because the 'callers of this function' table
#   displays the category of a site in some *other* file which may be built in
#   another process.  A baseline with no entry for the caller's file is exactly
#   where the two lookups can differ (an absent entry is an empty FunctionMap to
#   one of them and no map at all to the other, which are different answers), and
#   '--parallel' is what makes it visible:  a child sees only what the parent
#   computed, so the callee-side table cannot be repaired by the caller's own pass
{
    echo 'TN:differential'
    awk '/^SF:proj\/lib.cpp$/, /^end_of_record$/' base.info
} > lib_only.info

for mode in serial parallel ; do
    if [ $mode == parallel ] ; then
        threads='--parallel 2'
    else
        threads='--parallel 1'
    fi
    # ..after whatever the harness passed in $LCOV_OPTS, so this wins
    runGenhtml $mode --callgraph --show-proportion -o html_$mode $threads \
        --baseline-file lib_only.info --diff-file c.udiff curr.info
    # the 14 rows of the callees page:  3:24 is one 'GIC' row, as in scenario 1
    checkLine $mode $mode.log '    callgraph: UNC:1 UIC:3 GIC:6 GNC:4'
    # the callee-side view of 14 of the same 15 sites - the fifteenth is the call
    #   to 'ext', which has no callee in this report to be listed under.  Every
    #   row here is a site of 'c.cpp', so every category on this page came from
    #   the parent's pass
    checkTables $mode html_$mode/proj/lib.cpp.callers.html <<'EOF'
Circle::area*2|caller_Circle::area_0|100.0 % (2 / 2)^2|dispatch|c.cpp:11:15|GIC>#caller_a_1^2|2>#caller_a_1
Circle::area|caller_Circle::area_1|dispatch|c.cpp:11:27|1>#caller_a_1
Square::area*1|caller_Square::area_0|0.0 % (0 / 1)|dispatch|c.cpp:11:15|UIC>#caller_a_5^2|0>#caller_a_5
a*4|caller_a_0|75.0 % (3 / 4)^4|mix|c.cpp:7:12|0>#caller_a_5
a|caller_a_1|both|c.cpp:3:24|GIC>#caller_a_7^4|2>#caller_a_7
a|caller_a_2|mix|c.cpp:7:36|2>#caller_a_7
a|caller_a_3|both|c.cpp:3:12|3>#caller_a_7
a|caller_a_4|a{group_a}^4|50.0 % (2 / 4)^4|both|c.cpp:3:12|3>#caller_a_7
a|caller_a_5|both|c.cpp:3:24|UIC>#caller_c_0^2|0>#caller_c_0
a|caller_a_6|mix|c.cpp:7:12|0>#caller_c_0
a|caller_a_7|mix|c.cpp:7:36|GIC>#top^3|2>#caller_c_1
a|caller_a_8|aa{group_aa}|100.0 % (1 / 1)|both|c.cpp:3:24|2>#caller_c_1
b*1|caller_b_0|100.0 % (1 / 1)|mix|c.cpp:7:18|4>#caller_c_1
c*3|caller_c_0|33.3 % (1 / 3)^3|mix|c.cpp:7:24|UIC>#top|0>#caller_c_2
c|caller_c_1|main|c.cpp:16:12|GNC>#top|1>#top
c|caller_c_2|main|c.cpp:16:16|UNC>#top|0>#top
EOF
done

# ----------------------------------------------------------------------
echo "*** 9. --new-file-as-baseline remaps a call site category"
# ----------------------------------------------------------------------
# The same input, with the option which says to treat a file the baseline does
#   not have as if it had been there all along:  'GIC' becomes 'CBC' and 'UIC'
#   becomes 'UBC', so that turning a metric on does not fail a coverage ratchet
#   with work nobody did.  Call sites are rewritten with everything else, through
#   the site mutator - a site hands back a copy of its differential data in the XS
#   backend, so assigning to a field of that copy would change nothing.
# The rewrite needs the file's age, so it needs an annotation:  see 'ann.pm'
#   above, which dates everything from line 9 on to 2020.
# 'GNC' and 'UNC' are not in the remap table and are left alone, which is the
#   point of the option:  the code the diff really did add is still new code
runGenhtml nfb --callgraph --show-proportion -o html_nfb \
    --baseline-file lib_only.info --diff-file c.udiff --new-file-as-baseline \
    --annotate-script `pwd`/ann.pm curr.info
checkLine nfb nfb.log '    callgraph: UNC:1 UBC:3 GNC:4 CBC:6'
# ..and the same sites on the caller's own pages, where neither of the
#   'included' labels is left in either the function table or the source view
for page in html_nfb/proj/c.cpp.func.html html_nfb/proj/c.cpp.gcov.html ; do
    for cls in tlaUIC tlaGIC ; do
        checkNoLine nfb $page "$cls"
    done
done
# ..and this is the run which has an annotation, so it is the one which shows the
#   two columns the annotation buys:  how long ago the function was last changed
#   and by whom, which are the questions the source view asks of a line asked of
#   the function whose definition the row is about.  'ann.pm' dates everything
#   from line 9 on to 2020 and everything above it to three days ago, so 'both'
#   (line 3) and 'mix' (line 7) are bertie's recent work and 'dispatch' (11) and
#   'main' (15) are fred's old work.
# The age is counted in days, exactly as the source view counts it, so neither of
#   the two is written down:  three days back is three days whenever the suite
#   runs, but a fixed date gets one day older every day, so the old one is
#   computed the way genhtml computes it
# A cell is a run of contiguous functions rather than one function:  those which
#   share the author - or the date bin - and the colour are one cell, spanning
#   all of their rows.  The colour is the category of the calls of the function
#   which were not taken, the first of them in category order where there are
#   several, and none where every call was taken.  Each cell leads past its own
#   run to the next run of the same author, or bin, in the same colour, exactly
#   as the category cells do.  On this page no two neighbours share both:
#   'dispatch' and 'main' are both fred's, but 'dispatch' missed a UBC call and
#   'main' a UNC one, so they are two cells;  'both' missed nothing and 'mix'
#   missed a UBC call, so 'both' leads to no other bertie run but the top
RECENT_AGE=3
OLD_AGE=`perl -MDateTime -e 'print(
    DateTime->new(year => 2020, month => 1, day => 1)
        ->delta_days(DateTime->now())->in_units("days"));'`
checkTables nfb html_nfb/proj/c.cpp.callees.html <<EOF
both*2|site_3_12_1|$RECENT_AGE>#top^2|bertie.wooster@jeeves.co.uk>#top^2|100.0 % (1 / 1)^2|100.0 % (2 / 2)^2|3:12{site_3_12}|a|CBC>#site_11_27_1^3|3>#site_11_27_1
both|site_3_24_1|3:24{site_3_24}|a, aa|2>#site_11_27_1
dispatch*4|site_11_15_1|$OLD_AGE>#top^4|uncle.fred@ickenham.uk>#top^4|100.0 % (1 / 1)^4|66.7 % (2 / 3)^4|11:15{site_11_15}^2|Circle::area|2>#site_11_27_1
dispatch|site_11_15_2|Square::area|UBC>#site_7_12_1|0>#site_16_16_1
dispatch|site_11_27_1|11:27{site_11_27}|Circle::area|CBC>#site_7_18_1|1>#site_16_22_1
dispatch|-||<external callee>||
main*5|site_15_13_1|$OLD_AGE>#top^5|uncle.fred@ickenham.uk>#top^5|^5|80.0 % (4 / 5)^5|15:13{site_15_13}|both|GNC>#site_16_22_1^2|1>#site_16_22_1
main|site_16_12_1|16:12{site_16_12}|c|1>#site_16_22_1
main|site_16_16_1|16:16{site_16_16}|c|UNC>#top|0>#site_7_12_1
main|site_16_22_1|16:22{site_16_22}|mix|GNC>#top^2|1>#site_7_18_1
main|site_16_30_1|16:30{site_16_30}|dispatch|1>#site_7_18_1
mix*4|site_7_12_1|$RECENT_AGE>#top^4|bertie.wooster@jeeves.co.uk>#top^4|100.0 % (1 / 1)^4|50.0 % (2 / 4)^4|7:12{site_7_12}|a|UBC>#site_7_24_1|0>#site_7_24_1
mix|site_7_18_1|7:18{site_7_18}|b|CBC>#site_7_36_1|4>#site_7_36_1
mix|site_7_24_1|7:24{site_7_24}|c|UBC>#top|0>#top
mix|site_7_36_1|7:36{site_7_36}|a|CBC>#top|2>#top
EOF
# ..and the two are the leftmost columns of the page and are headed the way the
#   source view heads them, 'Age' being a count of days and not a date
checkColumns nfb html_nfb/proj/c.cpp.callees.html <<'EOF'
Age
Owner
Caller
Function Name
Rate
Call site
Callee
TLA
Count
EOF
# ..and the two cells are coloured the way the source view colours the same two
#   columns:  only where this page has something of that function left
#   unexercised.  'dispatch' misses a call and is coloured, 'both' misses none
#   and is not - the colour is there to be scanned for, and every row carrying
#   it would say nothing.  The tooltip names the colour being followed, or says
#   'group' where there is none
checkLine nfb html_nfb/proj/c.cpp.callees.html \
    '<a class="tlaBgUBC" href="#top" title="next UBC by fred">uncle.fred@ickenham.uk</a>'
checkLine nfb html_nfb/proj/c.cpp.callees.html \
    '<a class="tlaBgUNC" href="#top" title="next UNC by fred">uncle.fred@ickenham.uk</a>'
checkLine nfb html_nfb/proj/c.cpp.callees.html \
    "<a href=\"#top\" title=\"next group by &ldquo;[..7] days&rdquo; bin\">$RECENT_AGE</a>"
# ..and the date bin is named in the tooltip of the date cell and the author in
#   the tooltip of the author cell, which is the only place the bin and the short
#   login appear on a page whose cells carry the long spelling of both.  This run
#   named no '--date-bins', so the bin is one of the default ones
checkLine nfb html_nfb/proj/c.cpp.callees.html 'title="next group by bertie">bertie.wooster@jeeves.co.uk'
# ..and the cell itself, as opposed to its link, says what it stands for:  the
#   date the age is counted from, the author's full name and the category
RECENT_DATE=`perl -MPOSIX -e 'print(strftime("%Y-%m-%d", gmtime(time() - 3 * 24 * 60 * 60)))'`
checkLine nfb html_nfb/proj/c.cpp.callees.html \
    "<td class=\"calleeAnnot\" rowspan=\"2\" title=\"$RECENT_DATE\"><a href=\"#top\""
checkLine nfb html_nfb/proj/c.cpp.callees.html \
    '<td class="calleeAnnotAlt" rowspan="4" title="2020-01-01"><a class="tlaBgUBC"'
checkLine nfb html_nfb/proj/c.cpp.callees.html \
    '<td class="calleeAnnot" rowspan="2" title="bertie.wooster@jeeves.co.uk"><a href="#top"'
checkLine nfb html_nfb/proj/c.cpp.callees.html \
    '<td class="tlaUBC" title="UBC"><a class="tlaBgUBC" href="#site_7_12_1" title="Next UBC group">UBC</a></td>'
# The callees of 'lib.cpp' are where runs do merge:  every function there is
#   bertie's, 'Square::area' and 'a' both missed a UIC call and nothing ranked
#   before it, so the two are one cell ten rows tall, and the cell of
#   'Circle::area' - which missed nothing - skips it to lead to 'b', which
#   missed nothing either.  'c' missed a UNC call as well as a UIC one, and UNC
#   comes first, so 'c' is a colour of its own.
# The category column merges the same way, row by row:  the two GIC calls of
#   'Circle::area' are one cell, and so are the last two calls of 'a' and the call
#   of 'b' below them - a run of rows is a run whichever function they belong to -
#   while a caption ends a run, being in the way of the span
checkTables nfbcallers html_nfb/proj/lib.cpp.callers.html <<EOF
Circle::area*2|caller_Circle::area_0|$RECENT_AGE>#func_b^2|bertie.wooster@jeeves.co.uk>#func_b^2|100.0 % (2 / 2)^2|dispatch|c.cpp:11:15|GIC>#caller_a_1^2|2>#caller_a_1
Circle::area|caller_Circle::area_1|dispatch|c.cpp:11:27|1>#caller_a_1
Square::area*1|caller_Square::area_0|$RECENT_AGE>#top^10|bertie.wooster@jeeves.co.uk>#top^10|0.0 % (0 / 1)|dispatch|c.cpp:11:15|UIC>#caller_a_5^2|0>#caller_a_5
a*4|caller_a_0|75.0 % (3 / 4)^4|mix|c.cpp:7:12|0>#caller_a_5
a|caller_a_1|both|c.cpp:3:24|GIC>#caller_a_7^4|2>#caller_a_7
a|caller_a_2|mix|c.cpp:7:36|2>#caller_a_7
a|caller_a_3|both|c.cpp:3:12|$RECENT_AGE>#caller_a_7
a|caller_a_4|a{group_a}^4|50.0 % (2 / 4)^4|both|c.cpp:3:12|$RECENT_AGE>#caller_a_7
a|caller_a_5|both|c.cpp:3:24|UIC>#caller_c_0^2|0>#caller_c_0
a|caller_a_6|mix|c.cpp:7:12|0>#caller_c_0
a|caller_a_7|mix|c.cpp:7:36|GIC>#top^3|2>#caller_c_1
a|caller_a_8|aa{group_aa}|100.0 % (1 / 1)|both|c.cpp:3:24|2>#caller_c_1
b*1|caller_b_0|$RECENT_AGE>#top|bertie.wooster@jeeves.co.uk>#top|100.0 % (1 / 1)|mix|c.cpp:7:18|4>#caller_c_1
c*3|caller_c_0|$RECENT_AGE>#top^3|bertie.wooster@jeeves.co.uk>#top^3|33.3 % (1 / 3)^3|mix|c.cpp:7:24|UIC>#top|0>#caller_c_2
c|caller_c_1|main|c.cpp:16:12|GNC>#top|1>#top
c|caller_c_2|main|c.cpp:16:16|UNC>#top|0>#top
EOF
checkLine nfbcallers html_nfb/proj/lib.cpp.callers.html \
    '<a class="tlaBgUIC" href="#top" title="next UIC by bertie">bertie.wooster@jeeves.co.uk</a>'
# ..and the shading of the two columns alternates by cell, as the name column
#   does by function:  the merged cell is one cell, so the one below it is
#   shaded the other way even though it is two functions further down
cat > nfbshade.expect <<'EOF'
calleeAnnot 2
calleeAnnotAlt 10
calleeAnnot 1
calleeAnnotAlt 3
EOF
perl -ne 'print("$1 ", $2 || 1, "\n")
              if /<td class="(calleeAnnot(?:Alt)?)"(?: rowspan="(\d+)")?(?: title="[^"]*")?>.*title="next [^"]* by bertie"/' \
    html_nfb/proj/lib.cpp.callers.html > nfbshade.actual
if ! diff -u nfbshade.expect nfbshade.actual ; then
    fail nfbshade "unexpected shading of the owner column of lib.cpp.callers.html"
fi
# ..and on the callers page of 'c.cpp' 'dispatch' and 'main' merge:  both are
#   fred's, and neither shows a call which was not taken
checkTables nfbcallers html_nfb/proj/c.cpp.callers.html <<EOF
both*1|caller_both_0|$RECENT_AGE>#func_mix|bertie.wooster@jeeves.co.uk>#func_mix|100.0 % (2 / 2)|100.0 % (1 / 1)|main|c.cpp:15:13|GNC>#top^2|1>#top
dispatch*1|caller_dispatch_0|$OLD_AGE>#top^2|uncle.fred@ickenham.uk>#top^2|66.7 % (2 / 3)|100.0 % (1 / 1)|main|c.cpp:16:30|1>#top
main*1{external callers only}|-|80.0 % (4 / 5)|-|<deduced external callers>|||(1)
mix*1|caller_mix_0|$RECENT_AGE>#top|bertie.wooster@jeeves.co.uk>#top|50.0 % (2 / 4)|100.0 % (1 / 1)|main|c.cpp:16:22|GNC>#top|1>#top
EOF
# 'lib.cpp' is deliberately not checked here.  The rewrite is a per-file decision
#   which needs that file's annotation, so it happens where the file is
#   processed - and the callee-side table shows what the parent computed, which
#   is the un-rewritten category.  See the comment on the callee arm of
#   'FileCoverageInfo::recategorizeTlaAsBaseline'

# ----------------------------------------------------------------------
echo "*** 10. the unknown count '-' in a differential report"
# ----------------------------------------------------------------------
# A second fixture, because the interesting thing about '-' is what it does to a
#   *comparison* and every combination of it needs a site of its own.  'format.sh'
#   section 7 covers the record, the totals and the two renderings in a
#   single-file report; what is left is the categorizer, which is the one place
#   where the count is arithmetic rather than a label.
#
# The trap is that '-' is a count and not a flag - 'CallSite::DASH', so that a
#   site which has one can still be merged and written - and it is a *non-empty
#   string*, which makes it true in Perl.  Every comparison here would answer
#   "taken" for a call nobody measured if it read the count directly, so they all
#   go through 'lcovutil::site_count_value' (the number to compare, where the
#   unknown is 0) and 'lcovutil::site_count_hit' (whether to count it as hit,
#   where the unknown never is).  There is no thirteenth category for "unknown":
#   of the two that exist the only honest one is the not-taken one, and the
#   marker is kept for display, which is where the difference can be told.
#
# The line the calls are on carries a raw '<' and a raw '&' as well.  The source
#   view splices tags into that text and 'html2lcov' recovers the source by
#   stripping them again, so an unescaped '<' would truncate a tag and take the
#   rest of the line with it - and the callee's name is spliced into a title
#   attribute, where 't<int>' would do the same.  Scenario 11 is that guard.
mkdir dash
cat >dash/d.cpp <<'EOF'
int p(void) { return 1; }
int q(void) { return 2; }
int r(void) { return 3; }
template<class T> int t(T v) { return (int)v; }
int cmp(int n)
{
    return p() < n && q() > n && t(n);
}
int keep(int n)
{
    return p() + q() + r();
}
int main(void)
{
    return keep(1) + cmp(2) + r();
}
EOF

# 'gone' is deleted and the body of 'main' is rewritten;  everything above line
#   13 is untouched, which is where the unchanged-code comparisons come from
cat >d.udiff <<'EOF'
--- dash/d.cpp
+++ dash/d.cpp
@@ -13,8 +13,4 @@
-int gone(void)
-{
-    return q() + r();
-}
 int main(void)
 {
-    return keep(1) + cmp(2);
+    return keep(1) + cmp(2) + r();
 }
EOF

# The comparisons, current against baseline:
#   7:12   p       0  -> -    UBC   unknown now, and never taken before:  the
#                                     honest reading of '-' is the not-taken one
#   7:23   q       3  -> -    LBC   was taken, and now cannot be said to be
#   7:34   t<int>  0  -> 1    GBC   an ordinary comparison on the same line
#   11:12  p       -  -> 2    GBC   unknown before, taken now
#   11:18  q       -  -> -    UBC   unknown on both sides:  stable, and neither
#                                     an improvement nor a regression
#   11:24  r       4  -> 4    CBC
#   15:12  keep    +     1    GNC   inserted line
#   15:22  cmp     +     1    GNC
#   15:31  r       +     -    UNC   inserted, and unknown:  new code which
#                                     cannot be reported as covered
# ..and in the baseline only:
#   15:12  q       -        DUB   on a line the diff deletes, so it is shown
#   15:18  r       2        DCB     there and compared against nothing
#   19:12  keep    1        DCB   the old body of 'main', likewise
#   19:22  cmp     1        DCB
#
# 'p' is entered 3 times and the sites which name it account for 2 of them plus
#   an unknown, so whether any call came from outside cannot be decided;  'q' is
#   entered twice and both its sites are unknown, likewise.  'r' is entered 4
#   times and one counted site accounts for all 4, so its unknown site adds
#   nothing to decide and it has no remainder row.  See 'lcovutil::classify_callers'
cat >dcurr.info <<'EOF'
TN:differential
SF:dash/d.cpp
FNL:0,1,1
FNA:0,3,p
FNL:1,2,2
FNA:1,2,q
FNL:2,3,3
FNA:2,4,r
FNL:3,4,4
FNA:3,1,t<int>
FNL:4,5,8
FNA:4,1,cmp
FNC:4,7,12,0,-,p
FNC:4,7,23,0,-,q
FNC:4,7,34,0,1,t<int>
FNL:5,9,12
FNA:5,1,keep
FNC:5,11,12,0,2,p
FNC:5,11,18,0,-,q
FNC:5,11,24,0,4,r
FNL:6,13,16
FNA:6,1,main
FNC:6,15,12,0,1,keep
FNC:6,15,22,0,1,cmp
FNC:6,15,31,0,-,r
FNF:7
FNH:7
FNCF:9
FNCH:5
DA:1,3
DA:2,2
DA:3,4
DA:4,1
DA:5,1
DA:7,1
DA:9,1
DA:11,1
DA:13,1
DA:15,1
LF:10
LH:10
end_of_record
EOF

cat >dbase.info <<'EOF'
TN:differential
SF:dash/d.cpp
FNL:0,1,1
FNA:0,3,p
FNL:1,2,2
FNA:1,4,q
FNL:2,3,3
FNA:2,6,r
FNL:3,4,4
FNA:3,1,t<int>
FNL:4,5,8
FNA:4,1,cmp
FNC:4,7,12,0,0,p
FNC:4,7,23,0,3,q
FNC:4,7,34,0,0,t<int>
FNL:5,9,12
FNA:5,1,keep
FNC:5,11,12,0,-,p
FNC:5,11,18,0,-,q
FNC:5,11,24,0,4,r
FNL:6,13,16
FNA:6,1,gone
FNC:6,15,12,0,-,q
FNC:6,15,18,0,2,r
FNL:7,17,20
FNA:7,1,main
FNC:7,19,12,0,1,keep
FNC:7,19,22,0,1,cmp
FNF:8
FNH:8
FNCF:10
FNCH:5
DA:1,3
DA:2,4
DA:3,6
DA:4,1
DA:5,1
DA:7,1
DA:9,1
DA:11,1
DA:13,1
DA:15,1
DA:17,1
DA:19,1
LF:12
LH:12
end_of_record
EOF

runGenhtml dash --callgraph --show-proportion -o html_dash \
    --baseline-file dbase.info --diff-file d.udiff dcurr.info

# 13 sites:  the 9 current records and the 4 the baseline has on lines the diff
#   deleted.  Every category above, and no thirteenth one
checkLine dash dash.log \
    '    callgraph: UNC:1 LBC:1 UBC:2 GBC:2 GNC:2 CBC:1 DUB:1 DCB:3'
# ..and the totals, which are the current records only.  4 of the 9 are unknown,
#   so they are in 'found' and not in 'hit':  a call which may never have been
#   made cannot be reported as made
checkLine dash dash.log '  lines=10 hit=10 functions=7 hit=7 callgraph=9 hit=5'
checkPattern dash dash.log '  callgraph\.+: 55\.6% \(5 of 9 callees\)'

# The calls each function makes.  The count cell of an unknown site says '-'
#   rather than 0, in the differential view as in the plain one, and the category
#   beside it is the not-taken one - which is the pair of decisions this scenario
#   exists to pin:  the comparison reads '-' as 0 and the display does not.
# The proportion says the same thing a third way:  an unknown site is found and
#   not hit, as it is in the totals above, so 'cmp' - which makes three calls, two
#   of them unknown - is 1 of 3.  A proportion which left the two out would call
#   'cmp' fully exercised beside two rows categorized as not taken.
# The cell beside the name is the other direction, as a proportion too:  'main'
#   has no counted caller at all - its only one is outside the report - so its
#   cell is empty
# Only three of the seven functions call anything, and they are the only three
#   this page lists:  a function with nothing to say in this direction is not a
#   row with an empty half, it is absent
checkTables dash html_dash/dash/d.cpp.callees.html <<'EOF'
cmp*3|site_7_12_1|100.0 % (1 / 1)^3|33.3 % (1 / 3)^3|7:12{site_7_12}|p|UBC>#site_11_18_1|->#site_11_18_1
cmp|site_7_23_1|7:23{site_7_23}|q|LBC>#top|->#site_11_18_1
cmp|site_7_34_1|7:34{site_7_34}|t<int>|GBC>#top^2|1>#site_11_24_1
keep*3|site_11_12_1|100.0 % (1 / 1)^3|66.7 % (2 / 3)^3|11:12{site_11_12}|p|2>#site_11_24_1
keep|site_11_18_1|11:18{site_11_18}|q|UBC>#top|->#site_15_31_1
keep|site_11_24_1|11:24{site_11_24}|r|CBC>#top|4>#top
main*3|site_15_12_1|^3|66.7 % (2 / 3)^3|15:12{site_15_12}|keep|GNC>#top^2|1>#top
main|site_15_22_1|15:22{site_15_22}|cmp|1>#top
main|site_15_31_1|15:31{site_15_31}|r|UNC>#top|->#top
EOF

# ..and who calls each of them, which all seven have an answer to.
# An unknown count can leave it undecided who made the rest of the calls, which
#   is what the note beside 'p' and 'q' says:  each was entered more often than
#   its one known site accounts for, and the site which might account for the
#   difference is the one whose count is a '-'.
# 'r' has a '-' site too and no note, because it is not undecided:  its known site
#   accounts for all four of its entries on its own, so what the '-' site did or
#   did not add changes no answer.  't<int>' is the same case without the '-'
checkTables dashcaller html_dash/dash/d.cpp.callers.html <<'EOF'
cmp*1|caller_cmp_0|33.3 % (1 / 3)|100.0 % (1 / 1)|main|d.cpp:15:22|GNC>#top^2|1>#caller_p_1
keep*1|caller_keep_0|66.7 % (2 / 3)|100.0 % (1 / 1)|main|d.cpp:15:12|1>#caller_p_1
main*1{external callers only}|-|66.7 % (2 / 3)|-|<deduced external callers>|||(1)
p*2{callers may be outside the callgraph boundary}|caller_p_0|^2|50.0 % (1 / 2)^2|cmp|d.cpp:7:12|UBC>#caller_q_1|->#caller_q_0
p|caller_p_1|keep|d.cpp:11:12|GBC>#caller_t_int__0|2>#caller_r_0
q*2{callers may be outside the callgraph boundary}|caller_q_0|^2|0.0 % (0 / 2)^2|cmp|d.cpp:7:23|LBC>#top|->#caller_r_1
q|caller_q_1|keep|d.cpp:11:18|UBC>#top|->#caller_r_1
r*2|caller_r_0|^2|50.0 % (1 / 2)^2|keep|d.cpp:11:24|CBC>#top|4>#caller_t_int__0
r|caller_r_1|main|d.cpp:15:31|UNC>#top|->#top
t&lt;int&gt;*1|caller_t_int__0||100.0 % (1 / 1)|cmp|d.cpp:7:34|GBC>#top|1>#top
EOF
# The name cell of the last function names it escaped and the rows which call it
#   name it unescaped, and both are right:  'dump.pl' unescapes the cells and
#   leaves the name cell as the page writes it, so what is shown here is that the
#   page escapes the name in both places.  An escaped cell is what scenario 11 is
#   about.  Its anchor is escaped a third way, since the fragment a link carries
#   can hold neither the '<' nor the '>' - 't_int_' below is that name.
# ..and the four functions which call nothing have a row on this page and none on
#   the other one, which is the drop rule the other way round.  They are named on
#   the other page all the same, as the callees of the three functions which do
#   call something - so what is absent there is the row, which is the anchor
for func in p q r t_int_ ; do
    checkLine dashcaller html_dash/dash/d.cpp.callers.html "id=\"func_$func\""
    checkNoLine dashcaller html_dash/dash/d.cpp.callees.html "id=\"func_$func\""
    checkLine dashcaller html_dash/dash/d.cpp.callees.html \
        "d.cpp.callers.html#func_$func\""
done

# ..and the function table says the same thing in two columns of its own:  a
#   reader who is looking at a function goes to its callers or to its callees from
#   where the function already is, and the column of a direction the function has
#   nothing to say in is empty rather than a link which lands on a page that does
#   not list it
FUNCPAGE=html_dash/dash/d.cpp.func.html
checkPattern dashfunc $FUNCPAGE '<td class="tableHead">Callers <span'
checkPattern dashfunc $FUNCPAGE '<td class="tableHead">Callgraph <span'
# ..the exact proportion each of those cells reports is what scenario 2 checks;
#   here it is only the link which matters, so the proportion is left open
for func in cmp keep p q r t_int_ ; do
    checkPattern dashfunc $FUNCPAGE "<td class=coverPer[A-Za-z]+><a href=\"d.cpp.callers.html#func_$func\" title=\"Click to go to the callers of this function\">[0-9.]+&nbsp;% \([0-9]+ / [0-9]+\)</a></td>"
done
for func in cmp keep main ; do
    checkPattern dashfunc $FUNCPAGE "<td class=coverPer[A-Za-z]+><a href=\"d.cpp.callees.html#func_$func\" title=\"Click to go to the call sites of this function\">[0-9.]+&nbsp;% \([0-9]+ / [0-9]+\)</a></td>"
done
# ..and the cell of a direction the function has no proportion in is empty and
#   leads nowhere:  it keeps the plain function-table background, whether the
#   function has nothing in that direction at all - 'p' and the three below call
#   nothing - or has rows there and not one count between them, which is 'main'
#   with its single external caller.  'q', whose two callers are both unknown, is
#   not that case:  they are found and not hit, and it reads 0 of 2
checkLine dashfunc $FUNCPAGE '<td class="coverFn"></td>'
checkNoLine dashfunc $FUNCPAGE 'd.cpp.callers.html#func_main"'
checkLine dashfunc $FUNCPAGE \
    '<td class=coverPerLo><a href="d.cpp.callers.html#func_q" title="Click to go to the callers of this function">0.0&nbsp;% (0 / 2)</a></td>'
for func in p q r t_int_ ; do
    checkNoLine dashfunc $FUNCPAGE "d.cpp.callees.html#func_$func\""
done

# The source view marks an unknown site as neither taken nor missed:  a dashed
#   underline and no colour, because "not measured" is not "never called"
checkLine dash html_dash/dash/d.cpp.gcov.html \
    '<a class="callSiteUnknown" href="d.cpp.callees.html#site_15_31" data-calls="-: r">r</a>'
# ..and a site which really was measured and never taken still reads as missed
checkNoLine dash html_dash/dash/d.cpp.gcov.html 'class="callSiteLo"'
# ..while the count cell of the site's row counts it as not taken, which is how
#   it is categorized:  no test is known to have made the call.  It is coloured
#   by that category and is on the tour of the calls which were not taken - the
#   '-' is still what it shows, and the tooltip still says what that means
checkLine dash html_dash/dash/d.cpp.callees.html \
    '<td class="tlaUNC"><a href="#top" title="the compiler recorded this call and the coverage data carries no count for it - click for the next missed call">-</a></td>'
# ..and so is the location cell of a site whose only count is a '-'
checkLine dash html_dash/dash/d.cpp.callees.html \
    '<td class="coverCallgraphLo" id="site_7_23">'
checkNoLine dash html_dash/dash/d.cpp.callees.html 'coverCallgraphUnknown'
# ..and the same on the callers page.  Where it is undecided whether anything
#   outside the report made the rest of the calls, there is no caller row for
#   it:  nothing outside was seen and nothing can be deduced, and the note
#   beside the name is what says so
checkLine dashcaller html_dash/dash/d.cpp.callers.html \
    '<td class="tlaUNC"><a href="#top" title="the compiler recorded this call and the coverage data carries no count for it - click for the next missed call">-</a></td>'
checkNoLine dashcaller html_dash/dash/d.cpp.callers.html 'coverCallgraphUnknown'

# '--select-script' throws lines away after the totals are computed, so every
#   metric un-counts what it drops - and an unknown site has to be un-counted
#   from 'found' without being un-counted from 'hit', which it was never in.
#   Keeping only the lines up to 7 keeps 9 and 11 as context and drops 13 and 15,
#   which is 'main' and its three sites:  two taken and one unknown
runGenhtml dselect --callgraph --show-proportion -o html_dselect \
    --baseline-file dbase.info --diff-file d.udiff dcurr.info \
    --select-script `pwd`/select.pl,7
checkPattern dselect dselect.log '  callgraph\.+: 50\.0% \(3 of 6 callees\)'
checkNoLine dselect html_dselect/dash/d.cpp.gcov.html 'site_15_31'

# ----------------------------------------------------------------------
echo "*** 11. a raw '<' and '&' on a call-bearing line"
# ----------------------------------------------------------------------
# Line 7 of 'd.cpp' is 'return p() < n && q() > n && t(n);' - every character
#   HTML needs escaped, on a line with three call sites on it - and the callee at
#   7:34 is 't<int>', whose name is spliced into a title attribute.  A raw '<'
#   there does not merely shift a column the way '>' does:  it opens a tag, and
#   everything to the end of the line disappears into it.
# The guard is the same one scenario 7 uses:  the report still recovers the
#   source it was built from, byte for byte, and the columns still land on the
#   identifiers.  A single grep, because the point is that the escaped text and
#   the spliced anchors are interleaved correctly and not just present
checkLine escape html_dash/dash/d.cpp.gcov.html \
    'data-calls="-: p">p</a>() &lt; n &amp;&amp; <a class="callSiteUnknown" href="d.cpp.callees.html#site_7_23" data-calls="-: q">q</a>() &gt; n &amp;&amp; <a class="callSite" href="d.cpp.callees.html#site_7_34" data-calls="1: t&lt;int&gt;">t</a>(n);'

runGenhtml dsave --callgraph --show-proportion -o html_dsave --save dcurr.info

$COVER $HTML2LCOV_TOOL html_dsave --callgraph --source-directory dash -o drt \
    --ignore empty,unused 2>&1 | tee drt.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail escape "html2lcov failed:" `grep -E 'ERROR' drt.log`
fi
if [ -s drt.udiff ] ; then
    fail escape "the recovered source differs from the source it was built from"
    cat drt.udiff
fi
checkLine escape drt.rpt '0 changed, 0 added, 0 removed, 1 unchanged'
if [ -f drt.info ] &&
   ! diff -u <(fncRecords dcurr.info) <(fncRecords drt.info) ; then
    fail escape "the recovered call records do not match"
fi

# ----------------------------------------------------------------------
echo "*** 12. a call written in a file the diff renames"
# ----------------------------------------------------------------------
# A third fixture:  a call which is not written in the file its caller is defined
#   in.  'inl.h' is a fragment which is '#include'd into the body of 'wrap', so
#   the calls belong to 'wrap' - and to 'd.cpp', which is what counts them - while
#   the lines they are on are lines of 'inl.h'.  See 'format.sh' section 15 for
#   the record which carries that file and 'geninfo.sh' section 12 for a compiler
#   actually producing one.
#
# The site is categorized against the diff of the file it is *written* in, which
#   for a cross-file site is not the caller's file:  the line number it holds is a
#   line of the fragment, and asking the caller's diff about it would compare
#   unrelated lines.  The fragment is renamed here (the baseline calls it 'inc.h')
#   because each version's records spell the file the way that version spells it,
#   while the diff is keyed by the *current* name:  a baseline site which went
#   looking for 'inc.h' would find no diff data and no bucket to match against, so
#   every cross-file site would read as inserted code ('GIC'/'ECB' below) instead
#   of being compared against its baseline.
mkdir frag
cat >frag/lib.cpp <<'EOF'
int a(void) { return 1; }
int b(void) { return 2; }
int c(void) { return 3; }
EOF

cat >frag/inl.h <<'EOF'
    int p = a();
    int q = b();
    return p + q;
EOF

cat >frag/d.cpp <<'EOF'
int wrap(void)
{
#include "inl.h"
}
EOF

# The rename, and the edit:  a call to 'a' is inserted above the call to 'b',
#   which is therefore the same call one line further down, and the call to 'c'
#   goes away with the line it was on
cat >f.udiff <<'EOF'
--- frag/inc.h
+++ frag/inl.h
@@ -1,2 +1,3 @@
+    int p = a();
     int q = b();
-    return q + c();
+    return p + q;
EOF

# The comparisons, current against baseline:
#   inl.h:1:13  a  +  -> 2   GNC   an inserted line of the fragment
#   inl.h:2:13  b  1  -> 3   CBC   baseline 'inc.h:1:13', which the diff maps
#                                    onto current line 2
#   inc.h:2:16  c  4         DCB   on a line the diff deletes
# 'lib.cpp' does not change and holds no call data of its own, so every category
#   on its page was computed while 'd.cpp' was processed
cat >fcurr.info <<'EOF'
TN:differential
SF:frag/d.cpp
FNL:0,1,4
FNA:0d,1,wrap
FNC:0@0,1,13,0,2,a
FNC:0@0,2,13,0,3,b
FNF:1
FNH:1
FNCF:2
FNCH:2
DA:1,1
DA:3,1
LF:2
LH:2
end_of_record
TN:differential
SF:0,frag/inl.h
FNF:0
FNH:0
FNCF:0
FNCH:0
DA:1,2
DA:2,3
DA:3,1
LF:3
LH:3
end_of_record
TN:differential
SF:frag/lib.cpp
FNL:0,1,1
FNA:0,2,a
FNL:1,2,2
FNA:1,3,b
FNL:2,3,3
FNA:2,0,c
FNF:3
FNH:2
FNCF:0
FNCH:0
DA:1,2
DA:2,3
DA:3,0
LF:3
LH:2
end_of_record
EOF

cat >fbase.info <<'EOF'
TN:differential
SF:frag/d.cpp
FNL:0,1,4
FNA:0d,1,wrap
FNC:0@0,1,13,0,1,b
FNC:0@0,2,16,0,4,c
FNF:1
FNH:1
FNCF:2
FNCH:2
DA:1,1
DA:3,1
LF:2
LH:2
end_of_record
TN:differential
SF:0,frag/inc.h
FNF:0
FNH:0
FNCF:0
FNCH:0
DA:1,1
DA:2,4
LF:2
LH:2
end_of_record
TN:differential
SF:frag/lib.cpp
FNL:0,1,1
FNA:0d,1,a
FNL:1,2,2
FNA:1,1,b
FNL:2,3,3
FNA:2,4,c
FNF:3
FNH:3
FNCF:0
FNCH:0
DA:1,1
DA:2,1
DA:3,4
LF:3
LH:3
end_of_record
EOF

runGenhtml frag --callgraph -o html_frag \
    --baseline-file fbase.info --diff-file f.udiff fcurr.info
checkLine frag frag.log '    callgraph: GNC:1 CBC:1 DCB:1'
checkPattern frag frag.log '  callgraph\.+: 100\.0% \(2 of 2 callees\)'
# ..and none of what the untranslated name produces:  the current site matched
#   against nothing ('GIC', included code) and the two baseline sites left over
#   ('ECB', excluded from the current version)
checkNoLine frag frag.log 'GIC'
checkNoLine frag frag.log 'ECB'

# Both sites are counted by 'd.cpp', which is where their caller is defined and
#   the only thing a per-file total can mean;  the fragment they are written in
#   counts no callees of its own
checkLine frag frag.log 'lines=2 hit=2 functions=1 hit=1 callgraph=2 hit=2'
checkLine frag frag.log 'Processing file frag/inl.h (source code changed)'
if grep -A 2 -F -e 'Processing file frag/inl.h' frag.log |
    grep -q -E 'callee|callgraph'
then
    fail frag "the fragment counted a call site of its own:"
    grep -A 2 -F -e 'Processing file frag/inl.h' frag.log
fi

# The caller's page names each site by the file it is written in, and the callee's
#   page shows the same site with the same category.  The baseline-only site has
#   no row on either page, as a deleted site has nowhere in the current sources to
#   be shown - it is in the totals above, which is where it is reported
checkTables fragcaller html_frag/frag/d.cpp.callees.html <<'EOF'
wrap*2|site_frag_inl_h_1_13_1|^2|100.0 % (2 / 2)^2|inl.h:1:13{site_frag_inl_h_1_13}|a|GNC>#top|2>#top
wrap|site_frag_inl_h_2_13_1|inl.h:2:13{site_frag_inl_h_2_13}|b|CBC>#top|3>#top
EOF
checkTables fragcallee html_frag/frag/lib.cpp.callers.html <<'EOF'
a*1|caller_a_0|100.0 % (1 / 1)|wrap|inl.h:1:13|GNC>#top|2>#top
b*1|caller_b_0|100.0 % (1 / 1)|wrap|inl.h:2:13|CBC>#top|3>#top
EOF
# ..and 'wrap' is called from nowhere the report knows about, so its own callers
#   page is the one row which says so - a function with nothing but external
#   callers still has a page and a row, since "who called this" has an answer
#   even when the answer is "not this report".  'c' is the other way round:  it is
#   defined in 'lib.cpp' and never called, so no page lists it at all
checkTables fragouter html_frag/frag/d.cpp.callers.html <<'EOF'
wrap*1{external callers only}|-|100.0 % (2 / 2)|-|<deduced external callers>|||(1)
EOF
checkNoLine frag html_frag/frag/lib.cpp.callers.html 'func_c'

# ..and the source view of the fragment, which defines no function of its own:
#   the decorations point at the table of a function in another file, at the
#   anchors the dump above shows
checkLine frag html_frag/frag/inl.h.gcov.html \
    'href="../frag/d.cpp.callees.html#site_frag_inl_h_1_13" data-calls="2: a"'
checkLine frag html_frag/frag/inl.h.gcov.html \
    'href="../frag/d.cpp.callees.html#site_frag_inl_h_2_13" data-calls="3: b"'
# ..except where a filter decides what each file shows:  the fragment's
#   decorations lead to another file's page, and which part of that file is on
#   it is decided where that file is written.  Keeping every line, each site
#   still says what it calls, and neither file links into the other
runGenhtml fsel --validate --callgraph -o html_fsel \
    --baseline-file fbase.info --diff-file f.udiff fcurr.info \
    --select-script `pwd`/select.pl,99
checkLine fsel html_fsel/frag/inl.h.gcov.html \
    '<a class="callSite" data-calls="2: a">'
checkLine fsel html_fsel/frag/d.cpp.callees.html \
    'id="site_frag_inl_h_1_13">inl.h:1:13</td>'
checkNoLine fsel html_fsel/frag/inl.h.gcov.html 'd.cpp.callees.html'

# Each version keeps its own spelling of the fragment and its own index for it:
#   the index is a name for a file within one tracefile and not a thing the two
#   versions have to agree on, so a merge of either one is that tracefile again
for VERSION in fcurr fbase ; do
    $COVER $LCOV_TOOL $LCOV_OPTS --callgraph -a $VERSION.info -o $VERSION-rt.info \
        2>&1 | tee $VERSION-rt.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail frag "lcov failed on $VERSION.info:" \
            `grep -E 'ERROR|WARNING' $VERSION-rt.log`
    elif ! diff -u $VERSION.info $VERSION-rt.info ; then
        fail frag "$VERSION.info did not survive the round trip"
    fi
done

# ----------------------------------------------------------------------
echo "*** 13. a function whose only callee is outside the boundary"
# ----------------------------------------------------------------------
# The drop rule is about what a function has to say in one direction, and having
#   only an external answer is still having one:  'only' calls a function no file
#   of this report defines, so the calls it makes are one row which names no
#   callee - and it keeps its place on the page, because "does this function call
#   anything" is answered 'yes' by that row.
# ..and 'main' is the mirror of it on the other page:  nothing in the report calls
#   it, and the row which says so is the whole of its side of the callgraph.
# A plain run, with no baseline and no diff:  the two pages then have no category
#   column at all, which is the other shape the writer has to produce
mkdir lone
cat >lone/e.cpp <<'EOF'
int only(void)
{
    return ext();
}
int main(void)
{
    return only();
}
EOF

cat >ecurr.info <<'EOF'
TN:differential
SF:lone/e.cpp
FNL:0,1,4
FNA:0,2,only
FNC:0,3,12,0,2,ext
FNL:1,5,8
FNA:1,1,main
FNC:1,7,12,0,2,only
FNF:2
FNH:2
FNCF:2
FNCH:2
DA:1,2
DA:3,2
DA:5,1
DA:7,1
LF:4
LH:4
end_of_record
EOF

runGenhtml lone --callgraph --show-proportion -o html_lone ecurr.info
# the call to 'ext' is in neither total:  a call whose callee the report does not
#   describe is not a coverpoint of the report, which is what the boundary means
checkLine lone lone.log 'lines=4 hit=4 functions=2 hit=2 callgraph=1 hit=1'

checkTables lone html_lone/lone/e.cpp.callees.html <<'EOF'
main*1|site_7_12_1||100.0 % (1 / 1)|7:12{site_7_12}|only|2>#top
only*1|-|100.0 % (1 / 1)|-||<external callee>|
EOF
checkTables lonecaller html_lone/lone/e.cpp.callers.html <<'EOF'
main*1{external callers only}|-|100.0 % (1 / 1)|-|<deduced external callers>||(1)
only*1|caller_only_0||100.0 % (1 / 1)|main|e.cpp:7:12|2>#top
EOF
# ..and neither row is a link to anything:  there is no page for a callee the
#   report does not have, and none for a caller it does not have either
checkNoLine lone html_lone/lone/e.cpp.callees.html '>&lt;external callee&gt;</a>'
checkNoLine lonecaller html_lone/lone/e.cpp.callers.html '>&lt;deduced external callers&gt;</a>'

# ----------------------------------------------------------------------
echo "*** 14. the category column of a report which has no baseline"
# ----------------------------------------------------------------------
# '--show-navigation' asks for the category navigation without asking for a
#   comparison, so there are only two categories to navigate:  a call the tests
#   made and a call they did not.  'GNC' and 'UNC' are differential jargon in that
#   report, and genhtml calls them 'Hit' and 'Missed' instead - which is a word the
#   count cell beside them already says in a colour.
# So the column is not written at all here:  what would be lost with it, the word
#   and the tour of one category, moves onto the count, and the reader gets one
#   cell saying one thing instead of two saying the same thing twice.  The first
#   fixture again, with neither a baseline nor a diff - which is what makes the
#   labels the legacy ones
runGenhtml nav --callgraph --show-proportion --show-navigation -o html_nav \
    curr.info
checkColumns nav html_nav/proj/c.cpp.callers.html <<'EOF'
Callee
Function Name
Rate
Called from
Call site
Count
EOF
checkColumns nav html_nav/proj/c.cpp.callees.html <<'EOF'
Caller
Function Name
Rate
Call site
Callee
Count
EOF
for page in c.cpp.callers c.cpp.callees ; do
    checkNoLine nav html_nav/proj/$page.html '<td class="tableHead">Hit?</td>'
    checkNoLine nav html_nav/proj/$page.html '<td class="tableHead">TLA</td>'
done
# ..and this is the count cell which took the column over.  Three things are in
#   it:  the count, the word - and the link, which goes past the rest of this run
#   of missed calls to where the next missed call is, as the count cell of every
#   report does.  The background class is still the TLA, which is what the
#   stylesheet is written in;  only what the reader is shown is the word
checkLine nav html_nav/proj/c.cpp.callees.html \
    '<td class="tlaUNC"><a class="tlaBgUNC" href="#site_16_16_1" title="Missed - click for the next missed call">0</a></td>'
checkLine nav html_nav/proj/c.cpp.callers.html \
    '<td class="tlaGNC"><a class="tlaBgGNC" href="#top" title="Hit - click for the next hit call">1</a></td>'
# ..and a row which is not a call site is not a category either, so its count is
#   not a link:  'main' is entered from outside the report, which is a count with
#   no site and nothing to navigate to.  It keeps its colour, and is set in the
#   font and alignment of the category count cells above it
checkLine nav html_nav/proj/c.cpp.callers.html \
    '<td class="coverCallgraphHi callgraphTlaCount" title="(1) calls deduced from the number of times the function was entered">(1)</td>'
# ..and an unknown count, which is binned as missed:  no test is known to have
#   made the call, so it is on the tour of the calls which were not taken and
#   is coloured by the category it is binned in, and the word is folded into
#   its tooltip as it is into every other.  The fixture of scenario 10
runGenhtml dnav --callgraph --show-navigation -o html_dnav dcurr.info
checkLine dnav html_dnav/dash/d.cpp.callees.html \
    '<td class="tlaUNC"><a class="tlaBgUNC" href="#site_11_18_1" title="the compiler recorded this call and the coverage data carries no count for it - Missed - click for the next missed call">-</a></td>'
checkNoLine dnav html_dnav/dash/d.cpp.callees.html 'coverCallgraphUnknown'
# ..while the report which does have a baseline keeps the column, because there
#   the categories are the twelve and no word replaces them.  Scenario 2 checks
#   the column;  what is checked here is that the fold did not follow the option:
#   the count still leads to the next missed call, but it neither says the word
#   nor takes the colour of the category, which the column beside it has
checkLine diff html/proj/c.cpp.callees.html '<td class="tableHead">TLA</td>'
checkLine diff html/proj/c.cpp.callees.html \
    '<td class="tlaUBC"><a href="#site_16_16_1" title="click for the next missed call">0</a></td>'
checkNoLine diff html/proj/c.cpp.callees.html 'title="Missed - click'
# ..and the function table is a different table:  it keeps its category column in
#   both reports, the cell beside it there being the hit count rather than
#   anything which repeats the category.  What that heading does not have is a
#   width of its own - it held a tenth of the table for one short word, and the
#   space came out of the function name
checkLine nav html_nav/proj/c.cpp.func.html '<td class="tableHead">Hit?</td>'
checkLine diff html/proj/c.cpp.func.html '<td class="tableHead">TLA</td>'
checkNoLine nav html_nav/proj/c.cpp.func.html 'width="10%" class="tableHead"'
checkNoLine diff html/proj/c.cpp.func.html 'width="10%" class="tableHead"'

# ----------------------------------------------------------------------
echo "*** 15. each proportion of the function table leads to what it counts"
# ----------------------------------------------------------------------
# A reader who sees that something in a function was never exercised wants the
#   code, and the top of the function is not it where the function is longer
#   than the screen.  So each proportion leads to the first coverpoint of its own
#   kind - the first line, the first branch, the first MC/DC expression - and the
#   two callgraph proportions to this function's entry on the page of that
#   direction.  A source link lands a couple of lines above its target, as the
#   name does, so that the target is not the top line of the window.
# 'f' starts at line 1 and has nothing to count until line 5, a branch at 6 and
#   an MC/DC expression at 9:  four different places, so a link to the wrong one
#   cannot pass for the right one.  'h' has a range and no coverpoint in it, so
#   there is nowhere for its line proportion to go - which lcov calls
#   inconsistent, and the report is written anyway where that is ignored
mkdir kinds
cat >kinds/k.cpp <<'EOF'
int f(int a, int b)
{
    // nothing
    // here
    int r = 0;
    if (a)
        r = 1;
    // gap
    if (a && b)
        r = 2;
    return r;
}
int main(void)
{
    return f(1, 0);
}
void h(void)
{
}
EOF

cat >kcurr.info <<'EOF'
TN:differential
SF:kinds/k.cpp
FNL:0,1,12
FNA:0,1,f
FNL:1,13,16
FNA:1,1,main
FNC:1,15,12,0,1,f
FNL:2,17,19
FNA:2,0,h
FNF:3
FNH:2
FNCF:1
FNCH:1
DA:5,1
DA:6,1
DA:7,1
DA:9,1
DA:10,0
DA:11,1
DA:15,1
LF:7
LH:6
BRDA:6,0,0,1
BRDA:6,0,1,0
BRF:2
BRH:1
MCDC:9,2,t,1,0,a
MCDC:9,2,f,0,0,a
MCDC:9,2,t,0,1,b
MCDC:9,2,f,1,1,b
MCF:4
MCH:2
end_of_record
EOF

runGenhtml kinds --callgraph --show-proportion --branch-coverage \
    --mcdc-coverage --ignore-errors inconsistent,inconsistent -o html_kinds \
    kcurr.info
KPAGE=html_kinds/kinds/k.cpp.func.html
# the callgraph columns are proportions of the function like the others, so they
#   are at the right with them - and not between the reader and the name, which
#   is the column the reader reads first
checkColumns kinds $KPAGE <<'EOF'
Function Name
Hit count
Lines
MC/DC
Branches
Callers
Callgraph
EOF
checkLine kinds $KPAGE \
    '<td class="coverFn"><a href="k.cpp.gcov.html#L1">f</a></td>'
checkLine kinds $KPAGE \
    '<td class=coverPerMed><a href="k.cpp.gcov.html#L3" title="Click to go to the first line of this function">83.3&nbsp;% (5 / 6)</a></td>'
checkLine kinds $KPAGE \
    '<td class=coverPerLo><a href="k.cpp.gcov.html#L4" title="Click to go to the first branch of this function">50.0&nbsp;% (1 / 2)</a></td>'
checkLine kinds $KPAGE \
    '<td class=coverPerLo><a href="k.cpp.gcov.html#L7" title="Click to go to the first MC/DC expression of this function">50.0&nbsp;% (2 / 4)</a></td>'
checkLine kinds $KPAGE \
    '<td class=coverPerHi><a href="k.cpp.callers.html#func_f" title="Click to go to the callers of this function">100.0&nbsp;% (1 / 1)</a></td>'
checkLine kinds $KPAGE \
    '<td class=coverPerHi><a href="k.cpp.callees.html#func_main" title="Click to go to the call sites of this function">100.0&nbsp;% (1 / 1)</a></td>'
# ..'main' is where the name and the first line differ:  the line is two further
#   down than the declaration
checkLine kinds $KPAGE \
    '<td class="coverFn"><a href="k.cpp.gcov.html#L11">main</a></td>'
checkLine kinds $KPAGE \
    '<td class=coverPerHi><a href="k.cpp.gcov.html#L13" title="Click to go to the first line of this function">100.0&nbsp;% (1 / 1)</a></td>'
# ..and 'h' has the proportion and nothing to lead to
checkLine kinds $KPAGE '<td class=coverPerHi>- (0 / 0)</td>'

# ..while the same data reported without '--callgraph' says nothing about calls
#   anywhere:  no column in the function table, no page for either direction and
#   no sort order by call sites - the records are in the input, and it is the
#   option which decides that they are a coverage metric of this report
runGenhtml nocg --show-proportion --branch-coverage --mcdc-coverage \
    --ignore-errors inconsistent,inconsistent -o html_nocg kcurr.info
checkColumns nocg html_nocg/kinds/k.cpp.func.html <<'EOF'
Function Name
Hit count
Lines
MC/DC
Branches
EOF
for page in callers callees callers-c callees-c func-x ; do
    if [ -e html_nocg/kinds/k.cpp.$page.html ] ; then
        fail nocg "html_nocg/kinds/k.cpp.$page.html should not be written"
    fi
done
for page in k.cpp.func k.cpp.gcov index ; do
    checkNoLine nocg html_nocg/kinds/$page.html 'callers.html'
    checkNoLine nocg html_nocg/kinds/$page.html 'callees.html'
done

# ----------------------------------------------------------------------
echo "*** 16. a '<' just right of the identifier at a call site's column"
# ----------------------------------------------------------------------
# The identifier at a column is read rightward, and a '<' straight after it is
#   either a template argument list - which belongs to the name - or a
#   comparison written without spaces.  The two are told apart by whether the
#   '<' is closed:
#   5:12  t<int>  the name is 't<int>', and it names the callee
#   5:24  u       GCC folded the column onto the operand 'n' of 'n<u(n)', whose
#                   '<' is never closed.  It is not read as 'n<u(n);', so no
#                   text on the line is taken for the site and it goes in the
#                   trailing comment
mkdir tpl
cat >tpl/t.cpp <<'EOF2'
template<class T> int t(T v) { return (int)v; }
int u(int n) { return n; }
int f(int n)
{
    return t<int>(n) + n<u(n);
}
EOF2
cat >tpl.info <<'EOF2'
TN:tpl
SF:tpl/t.cpp
FNL:0,1,1
FNA:0,1,t<int>
FNL:1,2,2
FNA:1,1,u
FNL:2,3,6
FNA:2,1,f
FNC:2,5,12,0,1,t<int>
FNC:2,5,24,0,1,u
FNF:3
FNH:3
FNCF:2
FNCH:2
DA:1,1
DA:2,1
DA:3,1
DA:5,1
LF:4
LH:4
end_of_record
EOF2
runGenhtml tpl --callgraph -o html_tpl tpl.info
checkLine tpl html_tpl/tpl/t.cpp.gcov.html \
    '<a class="callSite" href="t.cpp.callees.html#site_5_12" data-calls="1: t&lt;int&gt;">t&lt;int&gt;</a>(n)'
checkLine tpl html_tpl/tpl/t.cpp.gcov.html \
    'href="t.cpp.callees.html#site_5_24" title="call recorded at column 24" data-callee="u"'
checkNoLine tpl html_tpl/tpl/t.cpp.gcov.html '>n&lt;u'

# ----------------------------------------------------------------------
echo "*** 17. every column of a function is an order of its page"
# ----------------------------------------------------------------------
# Each column which describes a function rather than one of its calls sorts the
#   page:  on the function table every proportion, and on the call site pages
#   the proportion of the page's own direction, that of the other direction, the
#   owner and the age.  A proportion is ordered lowest first, then by the larger
#   denominator - the same proportion of more coverpoints is more left to do -
#   then by name, and a function with nothing to divide is last.  The owner is
#   ordered by the full name the column shows and the age as a number of days,
#   each of them followed by the order of the page's own proportion.
# Seven functions, whose proportions are chosen so that each order differs from
#   the name order and from the count of unexercised coverpoints, and so that
#   both tie-breaks decide something.  'ace' is entered from outside and called
#   by nothing here, so its share of its callers has no denominator;  'abel' and
#   'foxtrot' call nothing, so they are not on the callees page, and 'abel' has
#   no line of its own - which lcov calls inconsistent.  The owners' logins sort
#   the other way round from their full names, and the ages are 5, 30 and 100
#   days, which sort the other way round as strings.  SOURCE_DATE_EPOCH fixes
#   'now', so that the ages do not depend on when the suite ran
mkdir srt
cat >srt/s.cpp <<'EOF'
int abel(void)
{
    return 1;
}
int foxtrot(void)
{
    return 2;
}
int delta(void)
{
    return abel();
}
int charlie(void)
{
    return foxtrot() + delta();
}
int bravo(void)
{
    int x = abel() + abel();
    return x + foxtrot() + delta();
}
int alpha(void)
{
    return abel() + foxtrot();
}
int ace(void)
{
    int x = alpha() + alpha();
    return x + bravo() + charlie();
}
EOF
cat >sort.info <<'EOF'
TN:sort
SF:srt/s.cpp
FNL:0,1,4
FNA:0,2,abel
FNL:1,5,8
FNA:1,1,foxtrot
FNL:2,9,12
FNA:2,1,delta
FNC:2,11,12,0,0,abel
FNL:3,13,16
FNA:3,1,charlie
FNC:3,15,12,0,0,foxtrot
FNC:3,15,24,0,1,delta
FNL:4,17,21
FNA:4,1,bravo
FNC:4,19,13,0,1,abel
FNC:4,19,22,0,0,abel
FNC:4,20,16,0,1,foxtrot
FNC:4,20,28,0,0,delta
FNL:5,22,25
FNA:5,2,alpha
FNC:5,24,12,0,1,abel
FNC:5,24,21,0,0,foxtrot
FNL:6,26,30
FNA:6,1,ace
FNC:6,28,13,0,1,alpha
FNC:6,28,23,0,0,alpha
FNC:6,29,16,0,1,bravo
FNC:6,29,26,0,0,charlie
FNF:7
FNH:7
FNCF:13
FNCH:6
BRDA:7,0,0,0
BRDA:7,0,1,0
BRDA:19,0,0,1
BRDA:19,0,1,0
BRDA:28,0,0,1
BRDA:28,0,1,0
BRDA:28,1,0,1
BRDA:28,1,1,0
BRF:8
BRH:3
MCDC:22,2,t,1,0,a
MCDC:22,2,f,1,0,a
MCDC:22,2,t,0,1,b
MCDC:22,2,f,0,1,b
MCDC:11,1,t,1,0,c
MCDC:11,1,f,0,0,c
MCDC:15,1,t,0,0,d
MCDC:15,1,f,0,0,d
MCF:8
MCH:3
DA:5,1
DA:7,1
DA:9,1
DA:11,1
DA:13,1
DA:15,0
DA:17,1
DA:19,1
DA:20,0
DA:22,1
DA:24,0
DA:26,1
DA:28,1
DA:29,0
DA:30,0
LF:15
LH:10
end_of_record
EOF
cat >own.pm <<'EOF'
package own;

use strict;

sub new
{
    my $class = shift;
    return bless [], $class;
}

sub annotate
{
    my ($self, $file) = @_;
    # [first line, login, full name, date]:  each function is one author and one
    #   date, from the line it starts on to the line the next one does
    my @who = ([1,  'amy', 'Zoe Amy',   '2023-10-23T00:00:00-00:00'],
               [5,  'zed', 'Alice Zed', '2024-01-01T00:00:00-00:00'],
               [9,  'amy', 'Zoe Amy',   '2024-01-01T00:00:00-00:00'],
               [13, 'zed', 'Alice Zed', '2024-01-26T00:00:00-00:00'],
               [17, 'amy', 'Zoe Amy',   '2024-01-26T00:00:00-00:00'],
               [22, 'zed', 'Alice Zed', '2024-01-01T00:00:00-00:00'],
               [26, 'amy', 'Zoe Amy',   '2024-01-26T00:00:00-00:00'],);
    open(my $fh, '<', $file) or return (1, []);
    my @lines;
    my $n = 0;
    my $at = 0;
    while (my $line = <$fh>) {
        chomp($line);
        ++$n;
        ++$at while $at < $#who && $who[$at + 1]->[0] <= $n;
        my (undef, $login, $full, $when) = @{$who[$at]};
        push(@lines, [$line, $login, $full, $when, "CL$n"]);
    }
    close($fh);
    return (0, \@lines);
}

1;
EOF
export SOURCE_DATE_EPOCH=`date -d 2024-01-31T00:00:00Z +%s`
runGenhtml srt --callgraph --show-proportion --branch-coverage \
    --mcdc-coverage --ignore-errors inconsistent,inconsistent -o html_srt \
    --annotate-script `pwd`/own.pm sort.info
unset SOURCE_DATE_EPOCH

checkOrder()
{
    # checkOrder label page <<expected
    #   the functions of the table of 'page', top to bottom
    local label=$1
    local page=html_srt/srt/s.cpp.$2.html
    if [ ! -f $page ] ; then
        fail $label "$page was not written"
        cat > /dev/null
        return
    fi
    cat > $label.order.expect
    case $2 in
        func*)
            perl -ne 'print("$1\n") if /<td class="coverFn"><a href="[^"]*">([^<]*)</;' \
                $page > $label.order.actual
            ;;
        *)
            perl dump.pl $page |
                perl -ne 'print("$1\n") if /^([^|*]+)\*/;' > $label.order.actual
            ;;
    esac
    if ! diff -u $label.order.expect $label.order.actual ; then
        fail $label "unexpected order of $page"
    fi
}

# The function table.  Lines:  'ace' 2 of 4 before 'alpha' and 'charlie' 1 of 2
#   each - the larger denominator, then the name - then 'bravo' 2 of 3, then the
#   two which are 2 of 2, and 'abel', which has no line, last
checkOrder srt_l func-l <<'EOF'
ace
alpha
charlie
bravo
delta
foxtrot
abel
EOF
# ..branches:  'foxtrot' took neither of its 2 and 'ace' 2 of 4, which is the
#   same number left - so it is the proportion which puts 'foxtrot' first, and
#   the denominator which puts 'ace' before 'bravo' 1 of 2
checkOrder srt_b func-b <<'EOF'
foxtrot
ace
bravo
abel
alpha
charlie
delta
EOF
# ..MC/DC expressions:  'charlie' 0 of 2, 'alpha' 2 of 4, 'delta' 1 of 2
checkOrder srt_m func-m <<'EOF'
charlie
alpha
delta
abel
ace
bravo
foxtrot
EOF
# ..the call sites each function contains, which is the order of the 'Rate' of
#   the callees page:  'delta' 0 of 1, 'ace' and 'bravo' 2 of 4, 'alpha' and
#   'charlie' 1 of 2, and the two which call nothing
checkOrder srt_x func-x <<'EOF'
delta
ace
bravo
alpha
charlie
abel
foxtrot
EOF
# ..and the calls which reach each function, which is the order of the 'Rate'
#   of the callers page:  'abel' 2 of 4 before 'alpha' and 'delta' 1 of 2, and
#   'ace', which has no denominator, last
checkOrder srt_r func-r <<'EOF'
charlie
foxtrot
abel
alpha
delta
bravo
ace
EOF
# ..whose heading leads to that order, except on the page which is in it
checkLine srt_r html_srt/srt/s.cpp.func.html '<a href="s.cpp.func-r.html">'
checkNoLine srt_r html_srt/srt/s.cpp.func-r.html '<a href="s.cpp.func-r.html">'

# The callers page.  'Rate' is the proportion of the calls which reach the
#   function, so it is the order of the 'Callers' column of the function table
checkOrder srt_cc callers-c <<'EOF'
charlie
foxtrot
abel
alpha
delta
bravo
ace
EOF
# ..'Callee' is the proportion of the calls the function makes, and 'abel' and
#   'foxtrot', which make none, are last although they are first by name
checkOrder srt_cx callers-x <<'EOF'
delta
ace
bravo
alpha
charlie
abel
foxtrot
EOF
# ..'Owner' is 'Alice Zed' before 'Zoe Amy', whose logins are 'zed' and 'amy',
#   and in each of them the order of 'Rate'
checkOrder srt_co callers-o <<'EOF'
charlie
foxtrot
alpha
abel
delta
bravo
ace
EOF
# ..and 'Age' is 5 days before 30 before 100
checkOrder srt_ca callers-a <<'EOF'
charlie
bravo
ace
foxtrot
alpha
delta
abel
EOF
# The callees page:  'Rate' is the proportion of the calls the function makes
checkOrder srt_ec callees-c <<'EOF'
delta
ace
bravo
alpha
charlie
EOF
# ..'Caller' that of the calls which reach it, which 'ace' has no denominator of
checkOrder srt_ex callees-x <<'EOF'
charlie
alpha
delta
bravo
ace
EOF
checkOrder srt_eo callees-o <<'EOF'
alpha
charlie
delta
ace
bravo
EOF
checkOrder srt_ea callees-a <<'EOF'
ace
bravo
charlie
delta
alpha
EOF
# ..and a function's rows move as one block, so the owner and age cells are
#   merged by the functions which are next to each other in this order:  one
#   'Alice Zed' cell spans the eight rows of 'charlie', 'foxtrot' and 'alpha', and
#   one '30' cell the six of 'foxtrot' and 'alpha'
perl dump.pl html_srt/srt/s.cpp.callers-o.html > srt_rows.actual
checkPattern srt_rows srt_rows.actual '^charlie\*2[^|]*\|[^|]*\|5>#top\^2\|Alice Zed>#top\^8\|'
checkPattern srt_rows srt_rows.actual '^foxtrot\*3\|[^|]*\|30>#func_delta\^6\|'
# ..each heading leads to its order, except on the page which is in it
for order in '' -c -x -o -a ; do
    for other in '' -c -x -o -a ; do
        for view in callers callees ; do
            page=html_srt/srt/s.cpp.$view$order.html
            if [ "$order" == "$other" ] ; then
                checkNoLine srt_head $page "<a href=\"s.cpp.$view$other.html\">"
            else
                checkLine srt_head $page "<a href=\"s.cpp.$view$other.html\">"
            fi
        done
    done
done
# ..and the way to the other direction of the file keeps the order, which the
#   other page is written in too
checkLine srt_cross html_srt/srt/s.cpp.callers-o.html \
    'href="s.cpp.callees-o.html#func_alpha"'
checkLine srt_cross html_srt/srt/s.cpp.callees-a.html \
    'href="s.cpp.callers-a.html#func_alpha"'
checkLine srt_cross html_srt/srt/s.cpp.callers-x.html \
    'href="s.cpp.callees-x.html"'

# A page is written in an order only where it has the column which leads to it:
#   the first report has no annotation, so neither page has an owner or an age,
#   and 'lib.cpp' has no callees page, so its callers page has no way to one
for page in c.cpp.callers-o c.cpp.callers-a c.cpp.callees-o c.cpp.callees-a \
    lib.cpp.callers-x lib.cpp.callers-o lib.cpp.callers-a ; do
    if [ -e html/proj/$page.html ] ; then
        fail srt_pages "html/proj/$page.html should not be written"
    fi
done
checkNoLine srt_pages html/proj/c.cpp.callers.html 'callers-o.html'
checkNoLine srt_pages html/proj/lib.cpp.callers.html 'callers-x.html'
for page in c.cpp.callers-x c.cpp.callees-x ; do
    if [ ! -f html/proj/$page.html ] ; then
        fail srt_pages "html/proj/$page.html was not written"
    fi
done
# ..and a link to another file's page keeps only the order every call site page
#   is written in, because which of the others that page has depends on columns
#   this one cannot see
checkLine srt_foreign html/proj/c.cpp.callees-x.html \
    'href="../proj/lib.cpp.callers.html#func_Circle::area"'
checkLine srt_foreign html/proj/c.cpp.callees-c.html \
    'href="../proj/lib.cpp.callers-c.html#func_Circle::area"'

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'differential' $LOCAL_COVERAGE 0
fi

exit $STATUS
