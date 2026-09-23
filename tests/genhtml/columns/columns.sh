#!/bin/bash
set +x

# The order of the metric column groups of the coverage tables.
#
# A coverage table is wide:  each metric is a group of columns, and with five
#   metrics a reader who sorted by one of them has to find that one's group.
#   So a table sorted by a metric shows that metric's group first, and the
#   others in the configured order - 'genhtml_metric_column_order', whose
#   default is line, MC/DC, branch, function, callgraph.  A table sorted by
#   name is in the configured order.
#
# The cases:
#   1. the directory tables, keyed by name, by owner and by date, and their
#      owner and date detail rows and per-testcase rows:  every row of a table
#      follows its headings, so a row whose test has no data for a metric has
#      that metric's group empty rather than the groups after it shifted left
#   2. the function table:  the column it is sorted by first.  It has no
#      function column, and two callgraph columns - the calls into the function
#      and the calls it makes
#   3. a configured order;  a metric the list leaves out goes at the end
#   4. a list naming something which is not a metric, or one twice:  an error,
#      and if that is ignored, the default order
#   5. a differential report:  a test's empty column group has the group's
#      TLA columns too
#   6. the alias rows of the function table

source ../../common.tst

GENHTML_OPTS="$PARALLEL $PROFILE"

rm -rf *.info *.log *.expect *.actual *.pm *.pl kinds html_*

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

runGenhtml()
{
    # runGenhtml label args...
    #   genhtml has to succeed and say nothing about anything
    local label=$1
    shift
    $COVER $GENHTML_TOOL $GENHTML_OPTS "$@" 2>&1 | tee $label.log
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

# rows.pl page:  one line per row of the page's coverage table which holds a
#   name - a file, an owner or date bin, a test or a function - and its cells,
#   ' | '-separated:  the text of each, '_' for an empty one, 'BAR' for the line
#   coverage bar, and '*N' after a cell which spans N columns
cat >rows.pl <<'EOF'
use strict;
local $/;
open(my $fh, '<', $ARGV[0]) or die("cannot open $ARGV[0]: $!");
my $html = <$fh>;
close($fh);
# the bar is a table of its own, inside its cell
$html =~ s|<td class="(?:owner_)?coverBar"[^>]*>.*?</table>\s*</td>|<td>BAR</td>|gs;
while ($html =~ m|<tr[^>]*>(.*?)</tr>|gs) {
    my $row = $1;
    next unless $row =~ /class="(coverFile|coverDirectory|ownerName|testName|coverFn)"/;
    my @cells;
    while ($row =~ m|<td([^>]*)>(.*?)</td>|gs) {
        my ($attr, $text) = ($1, $2);
        $text =~ s/<[^>]*>//g;
        $text =~ s/&nbsp;/ /g;
        $text =~ s/\s+/ /g;
        $text =~ s/^ | $//g;
        $text = '_' if $text eq '';
        $text .= "*$1" if $attr =~ /colspan=(\d+)/;
        push(@cells, $text);
    }
    print(join(' | ', @cells), "\n");
}
EOF

checkHeadings()
{
    # checkHeadings label page <<expected
    #   the metric headings of the coverage table of 'page', left to right
    local label=$1
    local page=$2
    if [ ! -f $page ] ; then
        fail $label "$page was not written"
        cat > /dev/null
        return
    fi
    cat > $label.head.expect
    perl -ne 'while (m|<td class="tableHead"[^>]*>(.*?)</td>|g) {
                  my $head = $1;
                  $head =~ s/<[^>]*>//g;
                  $head =~ s/\s+$//;
                  print("$1\n") if $head =~ /^(\S+) Coverage/ ||
                      $head =~ /^(Lines|Branches|MC\/DC|Callers|Callgraph)$/;
              }' $page > $label.head.actual
    if ! diff -u $label.head.expect $label.head.actual ; then
        fail $label "unexpected column order in $page"
    fi
}

checkRows()
{
    # checkRows label page <<expected
    #   the rows of 'page' - see rows.pl - which start with a name the heredoc
    #   has a line for
    local label=$1
    local page=$2
    if [ ! -f $page ] ; then
        fail $label "$page was not written"
        cat > /dev/null
        return
    fi
    cat > $label.rows.expect
    perl rows.pl $page > $label.rows.actual
    if ! diff -u $label.rows.expect $label.rows.actual ; then
        fail $label "unexpected rows in $page"
    fi
}

# Two files of one directory, each with every metric:  the same code, and one
#   more line hit in the second, so that the two rows of a table differ.  The
#   rates of 'k.cpp' are all different from each other - line 85.7%, MC/DC and
#   branch 50.0% (of 4 and 2), function 66.7%, callgraph 100.0% - so a rate
#   in the wrong column group cannot pass for the right one
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
cp kinds/k.cpp kinds/k2.cpp

for f in k k2 ; do
    if [ $f == k ] ; then
        TN=first
        DA10=0
    else
        TN=second
        DA10=1
    fi
    cat >>k.info <<EOF
TN:$TN
SF:kinds/$f.cpp
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
DA:10,$DA10
DA:11,1
DA:15,1
LF:7
LH:$((6 + DA10))
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
done

# lines 1 to 8 are 'bertie's and recent, the rest 'fred's and old:  two owners
#   and two date bins, each with some of the coverpoints
cat >ann.pm <<'EOF'
package ann;

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
            $old ? ('fred', 'fred@example.com') : ('bertie', 'bertie@example.com');
        push(@lines,
             [$line, $who, $mail,
              $old ? '2020-01-01T00:00:00-00:00' : $recent, "CL$n"]);
    }
    close($fh);
    return (0, \@lines);
}

1;
EOF

ALL="--callgraph --show-proportion --branch-coverage --mcdc-coverage --function-coverage --ignore-errors inconsistent,inconsistent"
DETAIL="--show-details --annotate-script `pwd`/ann.pm --show-owners all --date-bins 1,7"

# ----------------------------------------------------------------------
echo "*** 1. the directory tables:  the sorted metric first"
# ----------------------------------------------------------------------
runGenhtml dflt $ALL $DETAIL -o html_dflt k.info
P=html_dflt/kinds

checkHeadings name $P/index.html <<'EOF'
Line
MC/DC
Branch
Function
Callgraph
EOF
checkHeadings sort_l $P/index-sort-l.html <<'EOF'
Line
MC/DC
Branch
Function
Callgraph
EOF
checkHeadings sort_m $P/index-sort-m.html <<'EOF'
MC/DC
Line
Branch
Function
Callgraph
EOF
checkHeadings sort_b $P/index-sort-b.html <<'EOF'
Branch
Line
MC/DC
Function
Callgraph
EOF
checkHeadings sort_f $P/index-sort-f.html <<'EOF'
Function
Line
MC/DC
Branch
Callgraph
EOF
checkHeadings sort_c $P/index-sort-c.html <<'EOF'
Callgraph
Line
MC/DC
Branch
Function
EOF
# ..and the rows follow:  the bar goes with the line rate wherever that is
checkRows sort_c $P/index-sort-c.html <<'EOF'
k.cpp | 100.0 % | 1 | 1 | BAR | 85.7 % | 7 | 6 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2
k2.cpp | 100.0 % | 1 | 1 | BAR | 100.0 % | 7 | 7 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2
EOF
checkRows name $P/index.html <<'EOF'
k.cpp | BAR | 85.7 % | 7 | 6 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2 | 100.0 % | 1 | 1
k2.cpp | BAR | 100.0 % | 7 | 7 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2 | 100.0 % | 1 | 1
EOF
# a test's row has no callgraph data;  the line group is not first, so the test
#   name does not span the bar column, and the bar column is empty
checkRows detail_c $P/index-detail-sort-c.html <<'EOF'
k.cpp | 100.0 % | 1 | 1 | BAR | 85.7 % | 7 | 6 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2
first*1 | _ | _ | _ | _ | 85.7 % | 7 | 6 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2
k2.cpp | 100.0 % | 1 | 1 | BAR | 100.0 % | 7 | 7 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2
second*1 | _ | _ | _ | _ | 100.0 % | 7 | 7 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2
EOF
# ..and when it is first, the test name spans it
checkRows detail $P/index-detail.html <<'EOF'
k.cpp | BAR | 85.7 % | 7 | 6 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2 | 100.0 % | 1 | 1
first*2 | 85.7 % | 7 | 6 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2
k2.cpp | BAR | 100.0 % | 7 | 7 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2 | 100.0 % | 1 | 1
second*2 | 100.0 % | 7 | 7 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2
EOF
# the owner and date detail rows
checkHeadings owner_m $P/index-owner-detail-sort-m.html <<'EOF'
MC/DC
Line
Branch
Function
Callgraph
EOF
checkRows owner_m $P/index-owner-detail-sort-m.html <<'EOF'
k.cpp | Total | 50.0 % | 4 | 2 | BAR | 85.7 % | 7 | 6 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2 | 100.0 % | 1 | 1
fred | 50.0 % | 4 | 2 | _ | 66.7 % | 6 | 4 | - | _ | _ | - | _ | _ | 100.0 % | 1 | 1
bertie | - | _ | _ | _ | 100.0 % | 4 | 4 | 50.0 % | 2 | 1 | - | _ | _ | - | _ | _
first*2 | 50.0 % | 4 | 2 | _ | 85.7 % | 7 | 6 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2
k2.cpp | Total | 50.0 % | 4 | 2 | BAR | 100.0 % | 7 | 7 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2 | 100.0 % | 1 | 1
fred | 50.0 % | 4 | 2 | _ | 83.3 % | 6 | 5 | - | _ | _ | - | _ | _ | 100.0 % | 1 | 1
bertie | - | _ | _ | _ | 100.0 % | 4 | 4 | 50.0 % | 2 | 1 | - | _ | _ | - | _ | _
second*2 | 50.0 % | 4 | 2 | _ | 100.0 % | 7 | 7 | 50.0 % | 2 | 1 | 66.7 % | 3 | 2
EOF
checkHeadings owner_b $P/index-owner-sort-b.html <<'EOF'
Branch
Line
MC/DC
Function
Callgraph
EOF
checkHeadings date_f $P/index-date-detail-sort-f.html <<'EOF'
Function
Line
MC/DC
Branch
Callgraph
EOF
checkRows date_f $P/index-date-detail-sort-f.html <<'EOF'
k.cpp | Total | 66.7 % | 3 | 2 | BAR | 85.7 % | 7 | 6 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 100.0 % | 1 | 1
(7..) days | 50.0 % | 2 | 1 | _ | 75.0 % | 4 | 3 | 50.0 % | 4 | 2 | - | _ | _ | 100.0 % | 1 | 1
(1,7] days | 100.0 % | 1 | 1 | _ | 100.0 % | 3 | 3 | - | _ | _ | 50.0 % | 2 | 1 | - | _ | _
first*2 | 66.7 % | 3 | 2 | _ | 85.7 % | 7 | 6 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1
k2.cpp | Total | 66.7 % | 3 | 2 | BAR | 100.0 % | 7 | 7 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1 | 100.0 % | 1 | 1
(7..) days | 50.0 % | 2 | 1 | _ | 100.0 % | 4 | 4 | 50.0 % | 4 | 2 | - | _ | _ | 100.0 % | 1 | 1
(1,7] days | 100.0 % | 1 | 1 | _ | 100.0 % | 3 | 3 | - | _ | _ | 50.0 % | 2 | 1 | - | _ | _
second*2 | 66.7 % | 3 | 2 | _ | 100.0 % | 7 | 7 | 50.0 % | 4 | 2 | 50.0 % | 2 | 1
EOF
# the tables keyed by owner and by date;  files which tie on the sorted
#   metric are in name order
checkHeadings bin_owner_c $P/index-bin_owner-sort-c.html <<'EOF'
Callgraph
Line
MC/DC
Branch
EOF
checkRows bin_owner_c $P/index-bin_owner-sort-c.html <<'EOF'
bertie | Total | - | _ | _ | BAR | 100.0 % | 8 | 8 | - | _ | _ | 50.0 % | 4 | 2
k.cpp | - | _ | _ | _ | 100.0 % | 4 | 4 | - | _ | _ | 50.0 % | 2 | 1
k2.cpp | - | _ | _ | _ | 100.0 % | 4 | 4 | - | _ | _ | 50.0 % | 2 | 1
fred | Total | 100.0 % | 2 | 2 | BAR | 75.0 % | 12 | 9 | 50.0 % | 8 | 4 | - | _ | _
k.cpp | 100.0 % | 1 | 1 | _ | 66.7 % | 6 | 4 | 50.0 % | 4 | 2 | - | _ | _
k2.cpp | 100.0 % | 1 | 1 | _ | 83.3 % | 6 | 5 | 50.0 % | 4 | 2 | - | _ | _
EOF
checkHeadings bin_date_m $P/index-bin_date-sort-m.html <<'EOF'
MC/DC
Line
Branch
Function
Callgraph
EOF
checkRows bin_date_m $P/index-bin_date-sort-m.html <<'EOF'
(1,7] days | Total | - | _ | _ | BAR | 100.0 % | 6 | 6 | 50.0 % | 4 | 2 | 100.0 % | 2 | 2 | - | _ | _
k.cpp | - | _ | _ | _ | 100.0 % | 3 | 3 | 50.0 % | 2 | 1 | 100.0 % | 1 | 1 | - | _ | _
k2.cpp | - | _ | _ | _ | 100.0 % | 3 | 3 | 50.0 % | 2 | 1 | 100.0 % | 1 | 1 | - | _ | _
(7..) days | Total | 50.0 % | 8 | 4 | BAR | 87.5 % | 8 | 7 | - | _ | _ | 50.0 % | 4 | 2 | 100.0 % | 2 | 2
k.cpp | 50.0 % | 4 | 2 | _ | 75.0 % | 4 | 3 | - | _ | _ | 50.0 % | 2 | 1 | 100.0 % | 1 | 1
k2.cpp | 50.0 % | 4 | 2 | _ | 100.0 % | 4 | 4 | - | _ | _ | 50.0 % | 2 | 1 | 100.0 % | 1 | 1
EOF

# ----------------------------------------------------------------------
echo "*** 2. the function table:  the sorted column first"
# ----------------------------------------------------------------------
# the cells of a row are the function name, its count, then the columns
checkHeadings func $P/k.cpp.func.html <<'EOF'
Lines
MC/DC
Branches
Callers
Callgraph
EOF
checkRows func $P/k.cpp.func.html <<'EOF'
f | 1 | 83.3 % (5 / 6) | 50.0 % (2 / 4) | 50.0 % (1 / 2) | 100.0 % (1 / 1) | _
h | 0 | - (0 / 0) | _ | _ | _ | _
main | 1 | 100.0 % (1 / 1) | _ | _ | _ | 100.0 % (1 / 1)
EOF
checkHeadings func_c $P/k.cpp.func-c.html <<'EOF'
Lines
MC/DC
Branches
Callers
Callgraph
EOF
checkHeadings func_l $P/k.cpp.func-l.html <<'EOF'
Lines
MC/DC
Branches
Callers
Callgraph
EOF
checkHeadings func_m $P/k.cpp.func-m.html <<'EOF'
MC/DC
Lines
Branches
Callers
Callgraph
EOF
checkRows func_m $P/k.cpp.func-m.html <<'EOF'
f | 1 | 50.0 % (2 / 4) | 83.3 % (5 / 6) | 50.0 % (1 / 2) | 100.0 % (1 / 1) | _
h | 0 | _ | - (0 / 0) | _ | _ | _
main | 1 | _ | 100.0 % (1 / 1) | _ | _ | 100.0 % (1 / 1)
EOF
checkHeadings func_b $P/k.cpp.func-b.html <<'EOF'
Branches
Lines
MC/DC
Callers
Callgraph
EOF
checkRows func_b $P/k.cpp.func-b.html <<'EOF'
f | 1 | 50.0 % (1 / 2) | 83.3 % (5 / 6) | 50.0 % (2 / 4) | 100.0 % (1 / 1) | _
h | 0 | _ | - (0 / 0) | _ | _ | _
main | 1 | _ | 100.0 % (1 / 1) | _ | _ | 100.0 % (1 / 1)
EOF
checkHeadings func_r $P/k.cpp.func-r.html <<'EOF'
Callers
Lines
MC/DC
Branches
Callgraph
EOF
checkRows func_r $P/k.cpp.func-r.html <<'EOF'
f | 1 | 100.0 % (1 / 1) | 83.3 % (5 / 6) | 50.0 % (2 / 4) | 50.0 % (1 / 2) | _
h | 0 | _ | - (0 / 0) | _ | _ | _
main | 1 | _ | 100.0 % (1 / 1) | _ | _ | 100.0 % (1 / 1)
EOF
checkHeadings func_x $P/k.cpp.func-x.html <<'EOF'
Callgraph
Lines
MC/DC
Branches
Callers
EOF
checkRows func_x $P/k.cpp.func-x.html <<'EOF'
main | 1 | 100.0 % (1 / 1) | 100.0 % (1 / 1) | _ | _ | _
f | 1 | _ | 83.3 % (5 / 6) | 50.0 % (2 / 4) | 50.0 % (1 / 2) | 100.0 % (1 / 1)
h | 0 | _ | - (0 / 0) | _ | _ | _
EOF

# ----------------------------------------------------------------------
echo "*** 3. a configured order"
# ----------------------------------------------------------------------
# blanks and case do not matter;  line, MC/DC and function are left out, so
#   they follow, in the default order.  The function table has no function
#   column, and both its callgraph columns go where callgraph is
runGenhtml cfg $ALL --rc genhtml_metric_column_order='callgraph, Branch' \
    -o html_cfg k.info
P=html_cfg/kinds
checkHeadings cfg_name $P/index.html <<'EOF'
Callgraph
Branch
Line
MC/DC
Function
EOF
checkHeadings cfg_l $P/index-sort-l.html <<'EOF'
Line
Callgraph
Branch
MC/DC
Function
EOF
checkHeadings cfg_f $P/index-sort-f.html <<'EOF'
Function
Callgraph
Branch
Line
MC/DC
EOF
checkRows cfg_f $P/index-sort-f.html <<'EOF'
k.cpp | 66.7 % | 3 | 2 | 100.0 % | 1 | 1 | 50.0 % | 2 | 1 | BAR | 85.7 % | 7 | 6 | 50.0 % | 4 | 2
k2.cpp | 66.7 % | 3 | 2 | 100.0 % | 1 | 1 | 50.0 % | 2 | 1 | BAR | 100.0 % | 7 | 7 | 50.0 % | 4 | 2
EOF
checkHeadings cfg_func $P/k.cpp.func.html <<'EOF'
Callers
Callgraph
Branches
Lines
MC/DC
EOF
checkHeadings cfg_func_l $P/k.cpp.func-l.html <<'EOF'
Lines
Callers
Callgraph
Branches
MC/DC
EOF

# ----------------------------------------------------------------------
echo "*** 4. a list which is not one"
# ----------------------------------------------------------------------
n=0
for order in 'line,bogus' 'line,branch,line' ; do
    n=$((n + 1))
    if [ $n == 1 ] ; then
        MSG="unknown metric 'bogus'"
    else
        MSG="'line' appears more than once"
    fi
    $COVER $GENHTML_TOOL $GENHTML_OPTS $ALL \
        --rc genhtml_metric_column_order="$order" -o html_bad$n k.info \
        > bad$n.log 2>&1
    if [ 0 == $? ] ; then
        fail bad$n "genhtml did not fail"
    fi
    if ! grep -q "ERROR: (usage) Unsupported value 'genhtml_metric_column_order = $order':  $MSG" bad$n.log ; then
        fail bad$n "expected message not found"
    fi
    # ..ignored:  the default order
    $COVER $GENHTML_TOOL $GENHTML_OPTS $ALL --ignore-errors usage \
        --rc genhtml_metric_column_order="$order" -o html_ign$n k.info \
        > ign$n.log 2>&1
    if [ 0 != $? ] ; then
        fail ign$n "genhtml failed"
    fi
    if ! grep -q "WARNING: (usage) Unsupported value 'genhtml_metric_column_order = $order':  $MSG" ign$n.log ; then
        fail ign$n "expected warning not found"
    fi
    checkHeadings ign${n}_name html_ign$n/kinds/index.html <<'EOF'
Line
MC/DC
Branch
Function
Callgraph
EOF
    checkHeadings ign${n}_b html_ign$n/kinds/index-sort-b.html <<'EOF'
Branch
Line
MC/DC
Function
Callgraph
EOF
done

# ----------------------------------------------------------------------
echo "*** 5. a differential report:  the empty group of a test has its TLA columns"
# ----------------------------------------------------------------------
# no diff file:  the baseline is the same code
runGenhtml tla $ALL --show-details --baseline-file k.info \
    --ignore-errors usage,usage -o html_tla k.info
P=html_tla/kinds
checkHeadings tla_c $P/index-detail-sort-c.html <<'EOF'
Callgraph
Line
MC/DC
Branch
Function
EOF
checkRows tla_c $P/index-detail-sort-c.html <<'EOF'
k.cpp | 100.0 % | 1 | 1 | 1 | BAR | 85.7 % | 7 | 6 | 2 | 8 | 50.0 % | 4 | 2 | 2 | 2 | 50.0 % | 2 | 1 | 1 | 1 | 66.7 % | 3 | 2 | 1 | 2
first*1 | _ | _ | _ | _ | _ | 85.7 % | 7 | 6 | _ | 6 | 50.0 % | 4 | 2 | 2 | 2 | 50.0 % | 2 | 1 | 1 | 1 | 66.7 % | 3 | 2 | 1 | 2
k2.cpp | 100.0 % | 1 | 1 | 1 | BAR | 100.0 % | 7 | 7 | 1 | 9 | 50.0 % | 4 | 2 | 2 | 2 | 50.0 % | 2 | 1 | 1 | 1 | 66.7 % | 3 | 2 | 1 | 2
second*1 | _ | _ | _ | _ | _ | 100.0 % | 7 | 7 | _ | 7 | 50.0 % | 4 | 2 | 2 | 2 | 50.0 % | 2 | 1 | 1 | 1 | 66.7 % | 3 | 2 | 1 | 2
EOF

# ----------------------------------------------------------------------
echo "*** 6. the alias rows of the function table follow its headings"
# ----------------------------------------------------------------------
# 'f' has a second name, 'g', which was not called
cat >alias.info <<'EOF'
TN:
SF:kinds/k.cpp
FNL:0,1,12
FNA:0,1,f
FNA:0,0,g
FNF:1
FNH:1
DA:5,1
DA:6,1
DA:7,1
DA:9,1
DA:10,0
DA:11,1
LF:6
LH:5
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
runGenhtml alias --show-proportion --branch-coverage --mcdc-coverage \
    --function-coverage -o html_alias alias.info
P=html_alias/kinds
checkHeadings alias_b $P/k.cpp.func-b.html <<'EOF'
Branches
Lines
MC/DC
EOF
checkRows alias_b $P/k.cpp.func-b.html <<'EOF'
f | 1 | 50.0 % (1 / 2) | 83.3 % (5 / 6) | 50.0 % (2 / 4)
g | 0 | _ | _ | _
f | 1 | _ | _ | _
EOF

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'columns' $LOCAL_COVERAGE 0
fi

exit $STATUS
