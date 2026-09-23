#!/bin/bash

# Statement spans:  with 'merge_continuation_lines', the line coverpoint of a
#   statement written over several lines is placed on the statement's first
#   line, and the last line of the statement is recorded as its span - the
#   optional last field of the 'DA' record:  'DA:<line>,<count>,[<checksum>],<end>'.
# genhtml uses the span:  a coverpoint of a statement which the diff changed
#   anywhere is new code, and the date and owner of the statement are those of
#   its most recent edit.
# The sources are never compiled; the '.info' files are written here, by hand.
#   's.c' is the current version and 'base/s.c' the baseline.  The statements
#   of 's.c', and what is expected of each in the differential report:
#      1     the function's declaration:  its '{' is not
#            part of it, so it has no span               CBC
#      3-5   line 4 edited;  branches, MC/DC and a call  CBC -> GNC
#      6-7   line 7 edited                                UBC -> UNC
#      8-9   line 9 edited                                LBC -> UNC
#     10-11  line 11 edited                               UIC -> UNC
#     12-14  a 'for' header, partitioned into 12 and 13-14;  line 14 edited:
#            12 and its branch                            CBC
#            13 and its branch                            CBC -> GNC
#     16-17  unchanged                                    CBC
#     18-19  a baseline line between them was deleted     CBC -> GNC
#     20-21  unchanged;  the line after it is edited      CBC
#   The annotation gives each of these an owner and a date:
#      3-5   line 4 is the most recent edit               'bob'
#      6-7   edited at the same time:  the first line     'alice'
#      8-9   the same day, line 9 later                   'carol'
#     12     a segment of its own                         'alice'
#     13-14  line 14 is the most recent edit              'erin'

set +x

source ../../common.tst

rm -rf *.log *.json *.info *.raw *.in *.diff html_* annotate.pm e.c

clean_cover

if [[ 1 == "$CLEAN_ONLY" ]] ; then
    exit 0
fi

LCOV_OPTS="--branch $PARALLEL $PROFILE"
MERGE='--rc merge_continuation_lines=1'
STATUS=0

fail()
{
    echo "ERROR ($1): $2"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

# write a '.info' file from coverpoint records:  the found/hit records which
#   close each section are computed here
mkinfo()
{
    awk -F'[:,]' '
/^end_of_record/ {
    if (fnf) print "FNF:" fnf "\nFNH:" fnh
    if (fncf) print "FNCF:" fncf "\nFNCH:" fnch
    if (lf) print "LF:" lf "\nLH:" lh
    if (brf) print "BRF:" brf "\nBRH:" brh
    if (mcf) print "MCF:" mcf "\nMCH:" mch
    print
    fnf = fnh = fncf = fnch = lf = lh = brf = brh = mcf = mch = 0
    next
}
/^FNA:/  { ++fnf; if ($3 > 0) ++fnh }
/^FNC:/  { ++fncf; if ($6 != "-" && $6 > 0) ++fnch }
/^DA:/   { ++lf; if ($3 > 0) ++lh }
/^BRDA:/ { ++brf; if ($5 != "-" && $5 > 0) ++brh }
/^MCDC:/ { ++mcf; if ($5 > 0) ++mch }
{ print }' > $1
}

# run label status lcov-args...
run()
{
    local label=$1
    local expected=$2
    shift 2
    $COVER $LCOV_TOOL $LCOV_OPTS -o $label.info "$@" > $label.log 2>&1
    local status=$?
    if [ $expected == 0 -a 0 != $status ] ; then
        cat $label.log
        fail $label "unexpected lcov failure"
    elif [ $expected != 0 -a 0 == $status ] ; then
        cat $label.log
        fail $label "expected lcov failure"
    fi
}

# the statement spans of source file $1 in .info file $2, as 'first-last', in
#   order
spans()
{
    awk -F'[:,]' -v file=$1 '
/^SF:/ { mine = ($2 == file) }
mine && /^DA:/ && $5 != "" { print $2 "-" $5 }' $2 | sort -n | uniq |
        tr '\n' ' ' | sed -e 's/ $//'
}

# the records of source file $2 which start with $1, in .info file $3
records()
{
    awk -F: -v rec=$1 -v file=$2 '
/^SF:/ { mine = ($2 == file) }
mine && index($0, rec) == 1 { print }' $3 | sort -u | tr '\n' ' ' |
        sed -e 's/ $//'
}

# the lines of source file $2 which message $3 is about, in log $1
said()
{
    grep -F -e "$3" $1 | grep -o "\"$2\":[0-9]*" | cut -d: -f2 | sort -n |
        uniq | tr '\n' ' ' | sed -e 's/ $//'
}

# expect label what actual expected
expect()
{
    if [ "$3" != "$4" ] ; then
        fail $1 "$2: '$3', expected '$4'"
    fi
}

MERGED='merged continuation line coverpoint into statement line'
MOVED='moved line coverpoint to statement line'
PARTITIONED='partitioned into'

# ----------------------------------------------------------------------
# the spans of the current version
# ----------------------------------------------------------------------
mkinfo current.raw <<EOF
TN:
SF:s.c
FNL:0,1,23
FNA:0,1,f
FNC:0,4,13,0,1,f
DA:1,1
DA:3,1
DA:4,1
DA:5,1
DA:6,0
DA:7,0
DA:8,0
DA:10,0
DA:12,1
DA:13,6
DA:14,5
DA:15,5
DA:16,1
DA:17,1
DA:18,1
DA:20,1
DA:22,1
BRDA:3,0,0,1
BRDA:3,0,1,0
MCDC:3,2,t,1,0,a
MCDC:3,2,f,1,0,a
MCDC:3,2,t,1,1,b
MCDC:3,2,f,0,1,b
BRDA:12,0,0,1
BRDA:12,0,1,0
BRDA:13,0,0,5
BRDA:13,0,1,1
end_of_record
EOF

run current 0 -a current.raw $MERGE --callgraph --mcdc -v
expect current 'spans' "`spans s.c current.info`" \
    '3-5 6-7 8-9 10-11 13-14 16-17 18-19 20-21'
expect current 'merged' "`said current.log s.c "$MERGED"`" '4 5 7 14 17'
expect current 'partitioned' "`said current.log s.c "$PARTITIONED"`" 12
expect current 'partition message' \
    "`grep -c -F '"s.c":12: statement 12-14 partitioned into 12, 13-14' current.log`" 1
# the call on line 4 is the statement's
expect current 'call' "`records FNC: s.c current.info`" 'FNC:0^3,4,13,0,1,f'

# the spans are read back, and kept when the option is off
run readback 0 -a current.info --callgraph
expect readback 'spans' "`spans s.c readback.info`" \
    "`spans s.c current.info`"
# ..and survive the hand-off from a child process
LCOV_FORCE_PARALLEL=1 run parallel 0 -a current.info -a readback.info \
    --callgraph --parallel 2
expect parallel 'spans' "`spans s.c parallel.info`" "`spans s.c current.info`"
# a filter which removes a line coverpoint removes its span with it
run omit 0 -a current.info --omit-lines 'int y = ' --callgraph
expect omit 'spans' "`spans s.c omit.info`" \
    '3-5 8-9 10-11 13-14 16-17 18-19 20-21'
# with the option, a statement whose data has spans is not merged again
sed -e 's/^DA:3,1,,5$/DA:3,1,,5\nDA:4,1/' current.info > remerge.in
run remerge 0 -a remerge.in $MERGE --callgraph -v
expect remerge 'merged' "`said remerge.log s.c "$MERGED"`" ''
expect remerge 'line 4' "`records DA:4, s.c remerge.info`" 'DA:4,1'

# ----------------------------------------------------------------------
# format
# ----------------------------------------------------------------------
# with a checksum
perl -MDigest::MD5=md5_base64 -pe 'BEGIN { open(F, "s.c"); @s = <F>; chomp(@s) }
    s/^DA:(\d+),(\d+)$/"DA:$1,$2," . md5_base64($s[$1 - 1])/e' current.raw \
    > checksum.raw
run checksum 0 -a checksum.raw $MERGE --checksum
CHK=`records DA:3, s.c checksum.info`
if ! echo "$CHK" | grep -E -q '^DA:3,1,[^,]+,5$' ; then
    fail checksum "line 3: '$CHK', expected a checksum and a span"
fi
run checksum_read 0 -a checksum.info --checksum
expect checksum_read 'line 3' "`records DA:3, s.c checksum_read.info`" "$CHK"

# a malformed span, an empty one and one which is too long are format errors:
#   the coverpoint is kept and its span dropped
for bad in 'x' '3' '200' ; do
    sed -e "s/^DA:3,1,,5$/DA:3,1,,$bad/" current.info > bad.in
    run bad_$bad 1 -a bad.in
    expect bad_$bad 'message' \
        "`grep -c "unexpected statement end line '$bad' for line coverpoint s.c:3" bad_$bad.log`" 1
    run bad_${bad}_ignored 0 -a bad.in --ignore format
    expect bad_${bad}_ignored 'line 3' \
        "`records DA:3, s.c bad_${bad}_ignored.info`" 'DA:3,1'
done

# data which has no spans takes those of the data it is merged with
run nospan 0 -a current.raw -a current.info
expect nospan 'spans' "`spans s.c nospan.info`" "`spans s.c current.info`"
# two inputs with the same spans agree;  two with different ones do not
run same 0 -a current.info -a readback.info
expect same 'spans' "`spans s.c same.info`" "`spans s.c current.info`"
sed -e 's/^DA:3,1,,5$/DA:3,1,,4/' current.info > other.in
run conflict 1 -a current.info -a other.in
expect conflict 'message' \
    "`grep -c -E 'statement span mismatch at s.c:3: 3-[45] -> 3-[45]$' conflict.log`" 1
run conflict_ignored 0 -a current.info -a other.in --ignore inconsistent
expect conflict_ignored 'line 3' \
    "`records DA:3, s.c conflict_ignored.info`" 'DA:3,2'
# ..and a span which disagrees with the one the same input gave already
sed -e 's/^DA:3,1,,5$/DA:3,1,,5\nDA:3,1,,4/' current.info > twice.in
run twice 1 -a twice.in
expect twice 'message' \
    "`grep -c 'statement span mismatch at s.c:3 in' twice.log`" 1

# ----------------------------------------------------------------------
# the coverpoint is written on the statement's last line:  it is moved to
#   the first, and its branches say where they are written
# ----------------------------------------------------------------------
mkinfo m.in <<EOF
TN:
SF:m.c
FNL:0,1,6
FNA:0,1,g
DA:1,1
DA:4,1
DA:5,1
BRDA:4,0,0,1
BRDA:4,0,1,0
end_of_record
EOF
run moved 0 -a m.in $MERGE -v
expect moved 'moved' "`said moved.log m.c "$MOVED"`" 4
expect moved 'lines' "`records DA: m.c moved.info`" 'DA:1,1 DA:3,1,,4 DA:5,1'
expect moved 'branches' "`records BRDA: m.c moved.info`" \
    'BRDA:3,0^4,0,1 BRDA:3,0^4,1,0'
# ..and its checksum is that of the line it is moved to
perl -MDigest::MD5=md5_base64 -pe 'BEGIN { open(F, "m.c"); @s = <F>; chomp(@s) }
    s/^DA:(\d+),(\d+)$/"DA:$1,$2," . md5_base64($s[$1 - 1])/e' m.in \
    > moved_checksum.in
run moved_checksum 0 -a moved_checksum.in $MERGE --checksum
expect moved_checksum 'line 3' "`records DA:3, m.c moved_checksum.info`" \
    "DA:3,1,`sed -n 3p m.c | perl -MDigest::MD5=md5_base64 -ne 'chomp; print md5_base64($_)'`,4"

# ----------------------------------------------------------------------
# Python logical lines, and a Perl 'if' header
# ----------------------------------------------------------------------
mkinfo p.in <<EOF
TN:
SF:p.py
FNL:0,1,6
FNA:0,1,f
DA:1,1
DA:2,1
DA:3,1
DA:4,1
DA:5,0
DA:6,1
end_of_record
TN:
SF:p.pl
FNL:0,1,8
FNA:0,1,f
DA:2,1
DA:3,1
DA:4,1
DA:5,1
DA:7,0
end_of_record
EOF
run script 0 -a p.in $MERGE --ignore empty
expect script 'python' "`spans p.py script.info`" '2-3 4-5'
expect script 'perl' "`spans p.pl script.info`" '3-4'

# ----------------------------------------------------------------------
# a line at either end of a statement which holds nothing but a brace - once
#   comments are removed - and has no line coverpoint is not part of it:
#   the '{' after the declaration of 'f' in 'b.c', and after the 'if' header
#   in 'b.pl'.  A '{' line which has a coverpoint is part of the statement
# ----------------------------------------------------------------------
mkinfo brace.raw <<EOF
TN:
SF:b.c
FNL:0,1,13
FNA:0,1,f
DA:1,1
DA:3,1
DA:5,1
DA:8,1
DA:9,1
DA:10,1
DA:12,1
end_of_record
TN:
SF:b.pl
FNL:0,1,9
FNA:0,1,f
DA:2,1
DA:3,1
DA:6,1
DA:8,1
end_of_record
EOF
run brace 0 -a brace.raw $MERGE --ignore empty
expect brace 'c' "`spans b.c brace.info`" '3-4 5-6'
expect brace 'perl' "`spans b.pl brace.info`" '3-4'
sed -e 's/^DA:1,1$/DA:1,1\nDA:2,1/' brace.raw | mkinfo brace_kept.in
run brace_kept 0 -a brace_kept.in $MERGE --ignore empty
expect brace_kept 'c' "`spans b.c brace_kept.info`" '1-2 3-4 5-6'
# ..and a filter checks the spans it reads:  a '{' at the end of one is
#   removed;  so is a '}' whose coverpoint the filter removes - which leaves
#   8-9 with one line, and no span.  '{}' is more than a brace
sed -e 's/^DA:5,1$/DA:5,1,,7/' -e 's/^DA:8,1$/DA:8,1,,9/' \
    -e 's/^DA:10,1$/DA:10,1,,11/' brace.raw | mkinfo brace_span.in
run brace_blank 0 -a brace_span.in --filter blank --ignore empty
expect brace_blank 'spans' "`spans b.c brace_blank.info`" '5-6 8-9 10-11'
run brace_filter 0 -a brace_span.in --filter brace --ignore empty
expect brace_filter 'spans' "`spans b.c brace_filter.info`" '5-6 10-11'

# ----------------------------------------------------------------------
# genhtml:  the differential report
# ----------------------------------------------------------------------
mkinfo base.info <<EOF
TN:
SF:s.c
FNL:0,1,24
FNA:0,1,f
FNC:0^3,4,13,0,1,f
DA:1,1
DA:3,1,,5
DA:6,0,,7
DA:8,1,,9
DA:12,1
DA:13,6,,14
DA:15,5
DA:16,1,,17
DA:18,1,,20
DA:21,1,,22
DA:23,1
BRDA:3,0,0,1
BRDA:3,0,1,0
MCDC:3,2,t,1,0,a
MCDC:3,2,f,1,0,a
MCDC:3,2,t,1,1,b
MCDC:3,2,f,0,1,b
BRDA:12,0,0,1
BRDA:12,0,1,0
BRDA:13,0,0,5
BRDA:13,0,1,1
end_of_record
EOF

diff -u base/s.c s.c | sed -e 's#^--- base/s.c.*#--- s.c#' \
    -e 's#^+++ s.c.*#+++ s.c#' > s.diff

cat > annotate.pm <<'EOF'
package annotate;

use strict;

# line -> [owner, date]
my %who = (3  => ['alice', '2025-01-01T00:00:00Z'],
           4  => ['bob',   '2026-09-01T00:00:00Z'],
           6  => ['alice', '2026-09-01T10:00:00Z'],
           7  => ['carol', '2026-09-01T10:00:00Z'],
           8  => ['alice', '2026-09-01T10:00:00Z'],
           9  => ['carol', '2026-09-01T12:00:00Z'],
           12 => ['alice', '2025-01-01T00:00:00Z'],
           13 => ['dave',  '2025-01-01T00:00:00Z'],
           14 => ['erin',  '2026-09-01T00:00:00Z'],);
# 'e.c':  line 4 is older than line 3
my %e = (3 => ['alice', '2026-09-01T00:00:00Z'],
         4 => ['bob', '2025-01-01T00:00:00Z'],);

sub new
{
    my $class = shift;
    return bless [], $class;
}

sub annotate
{
    my ($self, $file) = @_;
    my $who = $file =~ /\be\.c$/ ? \%e : \%who;
    open(my $fh, '<', $file) or return (1, []);
    my @lines;
    my $n = 0;
    while (my $line = <$fh>) {
        chomp($line);
        my ($owner, $when) =
            exists($who->{++$n}) ? @{$who->{$n}} :
            ('old', '2020-01-01T00:00:00Z');
        push(@lines, [$line, $owner, $owner, $when, "CL$n"]);
    }
    close($fh);
    return (0, \@lines);
}

1;
EOF

# 'now' is fixed, so the ages are
export SOURCE_DATE_EPOCH=`date -d 2026-10-01T00:00:00Z +%s`

rm -rf html_diff
$COVER $GENHTML_TOOL --branch --mcdc --callgraph $PARALLEL $PROFILE $MERGE -v \
    --baseline-file base.info --diff-file s.diff -o html_diff current.info \
    --annotate-script `pwd`/annotate.pm --show-owners all \
    --date-bins 60,365 --ignore inconsistent > html_diff.log 2>&1
if [ 0 != $? ] ; then
    cat html_diff.log
    fail html_diff "unexpected genhtml failure"
fi
expect html_diff 'merged' "`said html_diff.log s.c "$MERGED"`" ''

PAGE=`find html_diff -name s.c.gcov.html`
# the category of the line coverpoint of line $1 of the source view
tla()
{
    grep -o "<span id=\"L$1\"[^>]*>.*" $PAGE | grep -o 'tla[A-Z][A-Z][A-Z]' |
        head -1 | sed -e 's/tla//'
}
for l in 1:CBC 3:GNC 6:UNC 8:UNC 10:UNC 12:CBC 13:GNC 15:CBC 16:CBC 18:GNC \
    20:CBC 22:GNC ; do
    expect html_diff "line ${l%:*}" "`tla ${l%:*}`" ${l#*:}
done
# the source view row of line $1
row()
{
    grep -o "<span id=\"L$1\".*" $PAGE
}
# the categories of the branches of line $1
branches()
{
    row $1 | grep -o 'title="[A-Z]*: branch' | sed -e 's/title="//' \
        -e 's/: branch//' | tr '\n' ' ' | sed -e 's/ $//'
}
# the owner of line $1
owner()
{
    row $1 | grep -o 'rdquo; bin"[^>]*>[a-z]*</a>' | sed -e 's/.*>\([a-z]*\)<.*/\1/' \
        | head -1
}
expect html_diff 'branches 3' "`branches 3`" 'GNC UNC'
expect html_diff 'branches 12' "`branches 12`" 'CBC UBC'
expect html_diff 'branches 13' "`branches 13`" 'GNC GNC'
# the MC/DC expressions of line 3
expect html_diff 'MC/DC 3' "`row 3 | grep -o 'title="[A-Z]*: [TF][a-z]* sense' |
    sed -e 's/title="//' -e 's/:.*//' | tr '\n' ' '`" 'GNC GNC GNC UNC '
# the call on line 4, where it is written and where its callee is
for page in callees callers ; do
    expect html_diff "call $page" \
        "`grep -o 'title="[A-Z][A-Z][A-Z]"' html_diff/stmtspan/s.c.$page.html`" \
        'title="GNC"'
done
for l in 3:bob 6:alice 8:carol 12:alice 13:erin ; do
    expect html_diff "owner ${l%:*}" "`owner ${l%:*}`" ${l#*:}
done
# the category whose color the source text of continuation line $1 has - its
#   count and category columns are empty
continued()
{
    row $1 | sed -e 's/<span class="tla[A-Z]*"> <a [^>]*>[-+#]<\/a> <\/span>//g' |
        grep -o '[0-9]</span>[][ :]*: <span class="tla[A-Z]*">' |
        grep -o 'tla[A-Z]*' | sed -e 's/tla//'
}
for l in 2: 4:GNC 5:GNC 7:UNC 9:UNC 11:UNC 14:GNC 17:CBC 19:GNC 21:CBC ; do
    expect html_diff "continued ${l%:*}" "`continued ${l%:*}`" "${l#*:}"
done
# a line which is in no statement is not colored
expect html_diff 'not continued 23' "`continued 23`" ''
# the statement's date:  line 3 is in the youngest bin
expect html_diff 'date 3' \
    "`row 3 | grep -c 'next GNC in &ldquo;\[..60\] days&rdquo; bin'`" 1
# the tooltip of the statement's line gives the statement's attribution, and
#   then the line's own;  that of a later line only its own
expect html_diff 'tooltip 3' "`row 3 | grep -o 'title="Line [^"]*"' | head -1`" \
    'title="Line 4: commit CL4 on 2026-09-01 by bob (statement 3-5)&#10;Line 3: commit CL3 on 2025-01-01 by alice"'
expect html_diff 'tooltip 4' "`row 4 | grep -o 'title="Line [^"]*"' | head -1`" \
    'title="Line 4: commit CL4 on 2026-09-01 by bob"'
# the owner table counts the statement's coverpoints for its owner
# the line of the first coverpoint of category $1 in the bin of owner $2
first_in_bin()
{
    grep -o "<a href=\"s.c.gcov.html#L[0-9]*\"[^>]*title=\"Go to first $1 in '$2' bin" \
        html_diff/stmtspan/index-bin_owner.html | grep -o '#L[0-9]*' |
        sed -e 's/#L//'
}
for what in 'GNC line' 'GNC branch' 'UNC branch' 'GNC callee' ; do
    expect html_diff "owner table $what" "`first_in_bin "$what" bob`" 3
done
expect html_diff 'owner table erin' "`first_in_bin 'GNC line' erin`" 13

# a baseline which has no span anywhere was captured without them:  each of
#   its line coverpoints stands for the current statement which starts on the
#   line it maps to.  A statement is changed if one of its lines was edited -
#   or if a baseline line between two of them was deleted:  18-19
sed -E 's/^(DA:[0-9]+,[0-9]+),,[0-9]+$/\1/' base.info > base_nospan.info
# ..but a baseline which has a span anywhere has them everywhere:  a baseline
#   coverpoint without one is a single line, so the line deleted after 18 was
#   not part of it
cat base_nospan.info - > base_somespan.info <<EOF
TN:
SF:b.c
DA:3,1,,4
LF:1
LH:1
end_of_record
EOF
for base in nospan somespan ; do
    rm -rf html_$base
    $COVER $GENHTML_TOOL --branch --mcdc --callgraph $PARALLEL $PROFILE \
        --baseline-file base_$base.info --diff-file s.diff -o html_$base \
        current.info > html_$base.log 2>&1
    if [ 0 != $? ] ; then
        cat html_$base.log
        fail html_$base "unexpected genhtml failure"
    fi
done
PAGE=`find html_nospan -name s.c.gcov.html`
for l in 1:CBC 3:GNC 6:UNC 8:UNC 10:UNC 12:CBC 13:GNC 16:CBC 18:GNC 20:CBC \
    22:GNC ; do
    expect html_nospan "line ${l%:*}" "`tla ${l%:*}`" ${l#*:}
done
PAGE=`find html_somespan -name s.c.gcov.html`
for l in 3:GNC 13:GNC 18:CBC ; do
    expect html_somespan "line ${l%:*}" "`tla ${l%:*}`" ${l#*:}
done

# a statement which runs past the end of the file - into the lines which are
#   synthesized for a coverpoint after it:  those lines do not date it.  A
#   current statement which has no span still changes with the baseline
#   statement it maps to
sed -e 's/^DA:18,1,,19$/DA:18,1/' -e 's/^DA:22,1$/DA:22,1,,24\nDA:25,1/' \
    current.info > edge.in
rm -rf html_edge
$COVER $GENHTML_TOOL --branch --mcdc --callgraph $PARALLEL $PROFILE \
    --baseline-file base.info --diff-file s.diff -o html_edge edge.in \
    --annotate-script `pwd`/annotate.pm --show-owners all \
    --date-bins 60,365 --ignore inconsistent,range > html_edge.log 2>&1
if [ 0 != $? ] ; then
    cat html_edge.log
    fail html_edge "unexpected genhtml failure"
fi
PAGE=`find html_edge -name s.c.gcov.html`
expect html_edge 'line 18' "`tla 18`" GNC
expect html_edge 'line 22' "`tla 22`" GNC
expect html_edge 'owner 22' "`owner 22`" old
expect html_edge 'date 22' \
    "`row 22 | grep -c 'next GNC in &ldquo;(365..) days&rdquo; bin'`" 1

# a baseline coverpoint on a later line of a current statement - a statement
#   of its own in the baseline, which partitioned the current one - has the
#   date and owner of the current statement, not those of its own line:  that
#   is where it is counted
cat > e.c <<EOF
int f(int a)
{
    int x = a +
        2 +
        3;
    return x;
}
EOF
mkinfo base_e.info <<EOF
TN:
SF:e.c
FNL:0,1,7
FNA:0,1,f
DA:1,1
DA:3,1
DA:4,1,,5
DA:6,1
end_of_record
EOF
mkinfo curr_e.info <<EOF
TN:
SF:e.c
FNL:0,1,7
FNA:0,1,f
DA:1,1
DA:3,1,,5
DA:6,1
end_of_record
EOF
rm -rf html_ecb
$COVER $GENHTML_TOOL $PARALLEL $PROFILE --baseline-file base_e.info \
    -o html_ecb curr_e.info --annotate-script `pwd`/annotate.pm \
    --show-owners all --date-bins 60,365 > html_ecb.log 2>&1
if [ 0 != $? ] ; then
    cat html_ecb.log
    fail html_ecb "unexpected genhtml failure"
fi
PAGE=`find html_ecb -name e.c.gcov.html`
expect html_ecb 'line 3' "`tla 3`" CBC
expect html_ecb 'line 4' "`tla 4`" ECB
expect html_ecb 'owner 4' "`owner 4`" alice
expect html_ecb 'date 4' \
    "`row 4 | grep -c 'next ECB in &ldquo;\[..60\] days&rdquo; bin'`" 1
expect html_ecb 'tooltip 4' "`row 4 | grep -o 'title="Line [^"]*"' | head -1`" \
    'title="Line 3: commit CL3 on 2026-09-01 by alice (statement 3-5)&#10;Line 4: commit CL4 on 2025-01-01 by bob"'
for bin in owner date ; do
    expect html_ecb "$bin table" \
        "`grep -c 'title="Go to first ECB line in' html_ecb/stmtspan/index-bin_$bin.html`" 1
done

# without a baseline, continuation lines are colored in the same way
rm -rf html_plain
$COVER $GENHTML_TOOL --branch $PARALLEL $PROFILE -o html_plain current.info \
    > html_plain.log 2>&1
if [ 0 != $? ] ; then
    cat html_plain.log
    fail html_plain "unexpected genhtml failure"
fi
PAGE=`find html_plain -name s.c.gcov.html`
for l in 2: 4:GNC 7:UNC 9:UNC 14:GNC 23: ; do
    expect html_plain "continued ${l%:*}" "`continued ${l%:*}`" "${l#*:}"
done

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    generate_coverage 'stmtspan' $LOCAL_COVERAGE 1
fi
exit $STATUS
