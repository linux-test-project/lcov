#!/bin/bash
set +x

# The HTML the source and directory pages are built out of.  Every failure below
#   is silent - the run exits 0, writes a complete looking report, and the report
#   says something which is not true of the code, or renders as if the data were
#   not there.
#
# The cases:
#   1. a name which is the string '0'.  Two helpers special-cased their argument
#      with a truth test where they meant a length test, so a directory called
#      '0' lost the '../' prefix on every relative reference of every page below
#      it (the stylesheet, the icons and the 'top level' link all resolve into
#      the wrong directory), its breadcrumb link came out with no text at all,
#      and a source line whose text is a bare '0' was rendered blank
#   2. a test description line whose text is '0'.  Same root cause in its
#      inverted form:  the line was read as the documented "blank line means
#      paragraph break", so the text was dropped *and* the description it was in
#      the middle of was split in two at exactly that point
#   3. an author name containing '&', '"' and '<'.  Two of the three renderings
#      of it in one source line went into an HTML attribute unescaped, while the
#      third - in the same subroutine - escaped it.  The '"' terminates the
#      attribute, so the tooltip is lost and a stray element is opened inside
#      the source listing
#   4. two branches of one TLA on one line needing different marker characters.
#      '#' (the block was never executed) and '-' (reached, but this way out was
#      never taken) are both uncovered, and the per-TLA link cache baked the
#      character into the cached anchor:  the second branch was drawn with the
#      first one's glyph while carrying its own, contradicting, tooltip
#   5. an unreachable coverpoint in a report with no baseline.  '--show-navigation'
#      without a diff switches to the legacy 'HIT'/'MIS' vocabulary, which knows
#      two categories - but a coverpoint marked unreachable is categorized ECC or
#      EUC whether there is a baseline or not, and the 'U' flag which marks it is
#      carried in the '.info' file itself.  The branch renderer skipped such an
#      element entirely, losing the element, the bracket which closed its group
#      and its share of the column width; the MC/DC renderer did not skip it and
#      built its tooltip out of an undefined label; and the stylesheet was
#      written from the narrowed category list, so the class both of them emit
#      had no rule in it
#   6. a directory whose sources contribute no function coverpoints.  The
#      'Function Coverage columns elided as function owner is not identified'
#      footnote was emitted whenever the columns were missing, which includes the
#      case where there is no function data at all - in reports which contain no
#      owner information anywhere
#   7. '--css-file' naming something which cannot be copied.  The failure was
#      reported by printing '$!' after a 'cp' subprocess, which does not set it,
#      so the message ended at the colon which introduces the reason - and it did
#      not say where the copy was going either.  This one is not silent, but what
#      it says is empty
#   8. a function on a line which has no line coverage data, in a report with no
#      baseline.  This one IS an error - the run stops with 'unexpected category
#      UNK for line ...' - because the line's category was left at the value it
#      is constructed with.  The differential path repairs exactly this ("there
#      is a function here - but no line - manufacture some data"), but the
#      no-baseline path returned before reaching it
#   9. '--new-file-as-baseline' on an old file which is not in the baseline.  The
#      whole option did nothing:  its guard asked 'age()' how old the file is,
#      and 'age()' returned undef unless 'isProjectFile()' - which reads the
#      per-owner line bins, and those are not filled in until every line has been
#      categorized, which is after the guard.  So the recategorization was
#      unreachable, and with it two more failures underneath:  the MC/DC arm of
#      the differential categorizer dropped every coverpoint of a file that is
#      not in the baseline (it walked only the groups the *baseline* has), and
#      the remap loop wrote the new TLA by assigning into the array 'count()'
#      returns - which is the stored array in the pure-Perl backend and a fresh
#      copy in the XS one, so the same report came out differently depending on
#      which backend generated it
#
# Case 5's stylesheet assertion is the general form of that failure and is worth
#   making of any report:  it is 'check_tla_css' in 'tests/common.tst', and every
#   report this test writes is checked with it.

source ../../common.tst

GENHTML_OPTS="$PARALLEL $PROFILE"
IGNORE="--ignore-errors inconsistent,unused,source"

rm -rf *.info *.log *.json *.udiff *.txt *.css proj css_dir html_* \
    perlcov.info pycov.info __pycache__

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

# every report written here has to satisfy the stylesheet invariant
check_css()
{
    check_tla_css $1 || fail $2 "unstyled TLA class in $1"
}

# ----------------------------------------------------------------------
echo "*** 1. a directory named '0', and a source line whose text is '0'"
# ----------------------------------------------------------------------
# 'proj' is the elided common prefix, so '0' and 'sub' are sibling directories at
#   the top of the report and only pages under '0' are affected
mkdir -p proj/0 proj/sub

cat >proj/0/a.c <<'EOF'
int a(void)
{
    return 1;
}
EOF

cat >proj/sub/b.c <<'EOF'
static int t[] = {
1,
0
};
EOF

cat >zero.info <<'EOF'
TN:htmlgen
SF:proj/0/a.c
DA:1,1
DA:3,1
LF:2
LH:2
end_of_record
SF:proj/sub/b.c
DA:1,1
DA:2,1
DA:3,1
LF:3
LH:3
end_of_record
EOF

$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_zero zero.info $IGNORE 2>&1 |
    tee zero.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail zero "genhtml failed on a directory named '0'"
fi
check_css html_zero zero

# the stylesheet and the icons are written once, at the top of the report, so
#   every reference to them from a page one level down has to go up one level
ZERO=html_zero/0/a.c.gcov.html
SUB=html_zero/sub/b.c.gcov.html
if [ ! -f $ZERO ] || [ ! -f $SUB ] ; then
    fail zero "no source page under the '0' directory"
else
    for ref in 'href="../gcov.css"' 'href="../index.html"' 'src="../glass.png"' ; do
        if ! grep -F -q -e "$ref" $ZERO ; then
            fail zero "page under '0' does not refer to $ref"
        fi
        # ..and the sibling directory, whose name is not a false string, is the
        #   reference for what those references are supposed to look like
        if ! grep -F -q -e "$ref" $SUB ; then
            fail zero "page under 'sub' does not refer to $ref"
        fi
    done
fi

# the source text:  line 3 of 'b.c' is a bare '0'
if ! grep -E -q ' : 0</span>' $SUB ; then
    fail zero "a source line whose text is '0' was rendered blank"
fi

# ..and the breadcrumb link, which is built out of the path components
$COVER $GENHTML_TOOL $GENHTML_OPTS --hierarchical -o html_zero_h zero.info \
    $IGNORE 2>&1 | tee zero_h.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail zero_h "genhtml --hierarchical failed on a directory named '0'"
fi
check_css html_zero_h zero_h
if ! grep -F -q -e 'title="Click to go to directory 0">0</a>' \
    html_zero_h/0/a.c.gcov.html ; then
    fail zero_h "the breadcrumb link for the directory '0' has no text"
fi

# ----------------------------------------------------------------------
echo "*** 2. a test description line whose text is '0'"
# ----------------------------------------------------------------------
# the value the sentence is about, on its own line, in the middle of a
#   description:  a run which reads it as a blank line loses the value and cuts
#   the sentence in two
cat >desc.txt <<'EOF'
TN: htmlgen
TD: step 1: set the counter to
TD: 0
TD: and run again
EOF

$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_desc zero.info $IGNORE \
    --show-details --description-file desc.txt 2>&1 | tee desc.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail desc "genhtml failed reading a description file"
fi
check_css html_desc desc
if [ ! -f html_desc/descriptions.html ] ; then
    fail desc "no description page was written"
elif ! grep -F -q -e 'step 1: set the counter to 0 and run again' \
    html_desc/descriptions.html ; then
    fail desc "'TD: 0' was read as a blank line"
fi

# ----------------------------------------------------------------------
echo "*** 3. an author name which is markup"
# ----------------------------------------------------------------------
# every rendering of the name has to be escaped, and there are three of them.
#   Line 2 is a non-code line, attributed by the fixture script to somebody else,
#   so lines 1 and 3 are one block of one owner with a line of another owner's in
#   between:  line 3 is then a line whose owner changed but which is not the
#   start of that owner's block, and that is the one case which prints the name
#   in the owner column instead of linking it.  Line 4 is the un-hit line, so it
#   is the one which carries the owner/age gutter tooltip
cat >ann.info <<'EOF'
TN:htmlgen
SF:proj/sub/b.c
DA:1,1
DA:3,1
DA:4,0
LF:3
LH:2
end_of_record
EOF

$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_ann ann.info $IGNORE \
    --annotate-script `pwd`/annotate.pl --show-owners all --show-noncode \
    --ignore-errors annotate 2>&1 | tee ann.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail ann "genhtml failed with an annotation script"
fi
check_css html_ann ann
PAGE=html_ann/b.c.gcov.html
if [ ! -f $PAGE ] ; then
    PAGE=`find html_ann -name 'b.c.gcov.html'`
fi
if [ "x$PAGE" == 'x' ] || [ ! -f "$PAGE" ] ; then
    fail ann "no annotated source page was written"
else
    # the escaped spelling, in the per-line tooltip the template builds..
    if ! grep -F -q -e 'by R&amp;D &quot;lead&quot; &lt;boss&gt;' $PAGE ; then
        fail ann "the per-line tooltip does not escape the author name"
    fi
    # ..and in the owner/age gutter tooltip
    if ! grep -F -q -e 'title="R&amp;D &quot;lead&quot; &lt;boss&gt; ' $PAGE ; then
        fail ann "the owner gutter tooltip does not escape the author name"
    fi
    # ..and in the owner column itself, where the name is padded out to the
    #   'genhtml_owner_field_width' columns the column is wide.  The name is 17
    #   characters and the field is 20, so three spaces of padding and then the
    #   one which separates the column from the next.  Escaping the name before
    #   padding it measures the entities instead of the characters, and a name
    #   whose escaped form is already wider than the field gets no padding at all
    if ! grep -F -q -e 'R&amp;D &quot;lead&quot; &lt;boss&gt;    <span class="lineNum">' \
        $PAGE ; then
        fail ann "the owner column is not padded to the field width"
    fi
    # ..and nowhere the raw form.  The '"' is what makes this markup and not
    #   just an escaping miss:  it terminates the attribute it is inside
    if grep -F -q -e 'R&D "lead"' $PAGE ; then
        fail ann "the author name reached the page unescaped"
    fi
    # every 'title' attribute is closed by the quote which follows the name
    if grep -F -q -e 'title="Line 2: commit commit2 on 2024-01-15 by R&D "' \
        $PAGE ; then
        fail ann "the per-line tooltip was truncated at the author name"
    fi
fi

# ----------------------------------------------------------------------
echo "*** 4. two branches of one TLA needing different markers"
# ----------------------------------------------------------------------
# one new line carrying two blocks:  the first block was entered and its exit
#   was never taken ('0'), the second was never entered at all ('-').  Both are
#   new code, so both are UNC
cat >proj/x.c <<'EOF'
line1
if (a && b) c();
line2
EOF

cat >br_curr.info <<'EOF'
TN:htmlgen
SF:proj/x.c
DA:1,1
DA:2,1
DA:3,1
BRDA:2,0,0,0
BRDA:2,1,0,-
BRF:2
BRH:0
LF:3
LH:3
end_of_record
EOF

cat >br_base.info <<'EOF'
TN:htmlgen
SF:proj/x.c
DA:1,1
DA:2,1
LF:2
LH:2
end_of_record
EOF

cat >br.udiff <<'EOF'
--- proj/x.c
+++ proj/x.c
@@ -1,2 +1,3 @@
 line1
+if (a && b) c();
 line2
EOF

$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_br br_curr.info $IGNORE \
    --branch-coverage --baseline-file br_base.info --diff-file br.udiff 2>&1 |
    tee br.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail branch "genhtml failed on a two-block line"
fi
check_css html_br branch
PAGE=html_br/x.c.gcov.html
if [ ! -f $PAGE ] ; then
    PAGE=`find html_br -name 'x.c.gcov.html'`
fi
if [ "x$PAGE" == 'x' ] || [ ! -f "$PAGE" ] ; then
    fail branch "no source page was written"
else
    # both blocks are UNC, and the two markers say different things about them:
    #   '-' is "find an input which goes the other way", '#' is "find a test
    #   which gets here at all"
    for marker in '-' '#' ; do
        COUNT=`grep -c -F -e "class=\"branchTla\">$marker</a>" $PAGE`
        if [ 1 != "$COUNT" ] ; then
            fail branch "expected 1 '$marker' branch marker, found $COUNT"
        fi
    done
    # ..and the marker agrees with the tooltip beside it
    if ! grep -F -q -e 'was not taken" class="branchTla">-</a>' $PAGE ; then
        fail branch "the 'not taken' branch is not drawn with '-'"
    fi
    if ! grep -F -q -e 'was not executed" class="branchTla">#</a>' $PAGE ; then
        fail branch "the 'not executed' branch is not drawn with '#'"
    fi
fi

# ----------------------------------------------------------------------
echo "*** 5. an unreachable coverpoint under the legacy labels"
# ----------------------------------------------------------------------
cat >proj/t.c <<'EOF'
int f(int a, int b)
{
    if (a > 0)
        return 1;
    if (a > 0 && b > 0)
        return 2;
    return 0;
}
EOF

# the 'U' before the block field of a 'BRDA' record, and before the group size
#   of an 'MCDC' record, is how an unreachable coverpoint is written down.  No
#   callback script and no '--unreachable' flag is involved in reading it back.
# Both categories have to appear:  an unreachable coverpoint which was covered
#   anyway is 'ECC' and one which was not is 'EUC', and the two are rendered by
#   different arms of the renderer
cat >unreach.info <<'EOF'
TN:htmlgen
SF:proj/t.c
DA:1,3
DA:3,3
DA:4,1
DA:5,3
DA:6,1
DA:7,2
BRDA:3,0,0,3
BRDA:3,U0,1,0
BRF:2
BRH:1
MCDC:5,U2,t,3,0,a
MCDC:5,U2,f,0,0,a
MCDC:5,2,t,2,1,b
MCDC:5,2,f,1,1,b
MCF:4
MCH:3
LF:6
LH:6
end_of_record
EOF

COV_OPTS="--branch-coverage --mcdc-coverage"
for mode in plain nav ; do
    if [ $mode == nav ] ; then
        EXTRA='--show-navigation'
    else
        EXTRA=''
    fi
    $COVER $GENHTML_TOOL $GENHTML_OPTS -o html_$mode unreach.info $IGNORE \
        $COV_OPTS $EXTRA 2>&1 | tee unreach_$mode.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail unreach_$mode "genhtml failed on an unreachable coverpoint"
        continue
    fi
    # the undefined legacy label was a warning, not an error, so the run passed
    if grep -F -q -e 'uninitialized' unreach_$mode.log ; then
        fail unreach_$mode "used an uninitialized value"
    fi
    check_css html_$mode unreach_$mode
    PAGE=`find html_$mode -name 't.c.gcov.html'`
    if [ "x$PAGE" == 'x' ] ; then
        fail unreach_$mode "no source page was written"
        continue
    fi
    # the excluded coverpoints:  one branch and one MC/DC condition, each drawn
    #   with an 'x' in its own category
    for tla in ECC EUC ; do
        if ! grep -F -q -e "class=\"tla$tla\"" $PAGE ; then
            fail unreach_$mode "no '$tla' coverpoint in the source page"
        fi
    done
    # the source text has no brackets in it, so every '[' in the page opened a
    #   coverpoint group and every ']' closed one
    OPEN=`grep -o '\[' $PAGE | wc -l`
    CLOSE=`grep -o '\]' $PAGE | wc -l`
    if [ "$OPEN" != "$CLOSE" ] ; then
        fail unreach_$mode "$OPEN '[' but $CLOSE ']' in the source page"
    fi
    # the MC/DC tooltip is built out of a prefix and a sentence; a prefix which
    #   is an undefined label leaves the tooltip opening with a bare ': '
    if grep -F -q -e 'title=": ' $PAGE ; then
        fail unreach_$mode "a tooltip begins with an empty label"
    fi
done
# the two runs differ in the labels and the navigation columns, not in which
#   coverpoints they show
for mode in plain nav ; do
    # every excluded coverpoint is on the one line it belongs to, so this counts
    #   matches and not lines - and the page is found first, because backticks
    #   inside backticks do not nest
    PAGE=`find html_$mode -name 't.c.gcov.html'`
    COUNT=`grep -o -F -e 'tlaEUC' $PAGE | wc -l`
    eval "COUNT_$mode=$COUNT"
done
if [ "$COUNT_plain" != "$COUNT_nav" ] ; then
    fail unreach "--show-navigation dropped an excluded coverpoint" \
        "($COUNT_plain vs $COUNT_nav)"
fi

# ----------------------------------------------------------------------
echo "*** 6. a directory with no function coverpoints"
# ----------------------------------------------------------------------
mkdir -p proj/withfn proj/nofn

cat >proj/withfn/f.c <<'EOF'
int f(void)
{
    return 1;
}
EOF

cat >proj/nofn/g.c <<'EOF'
static int g = 1;
static int h = 0;
EOF

cat >fn.info <<'EOF'
TN:htmlgen
SF:proj/withfn/f.c
FN:1,4,f
FNDA:2,f
FNF:1
FNH:1
DA:1,2
DA:3,2
LF:2
LH:2
end_of_record
SF:proj/nofn/g.c
DA:1,1
DA:2,0
LF:2
LH:1
end_of_record
EOF

NOTE='function owner is not identified'

$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_fn fn.info $IGNORE \
    --function-coverage 2>&1 | tee fn.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail fn "genhtml failed with function coverage"
fi
check_css html_fn fn
# the directory which has function data shows the columns; the one which has
#   none simply does not - like every other empty cover type in the report
for page in html_fn/index.html html_fn/withfn/index.html \
    html_fn/nofn/index.html ; do
    if [ ! -f $page ] ; then
        fail fn "$page was not written"
    elif grep -F -q -e "$NOTE" $page ; then
        fail fn "$page blames a missing owner in a report with no owners"
    fi
done
if ! grep -F -q -e 'Function Coverage' html_fn/withfn/index.html ; then
    fail fn "the directory with function data has no function columns"
fi
if grep -F -q -e 'Function Coverage' html_fn/nofn/index.html ; then
    fail fn "the directory with no function data has function columns"
fi

# ..and the case the footnote is actually about:  the table whose primary key is
#   the owner - 'index-bin_owner.html', not the owner-binned 'index-owner.html' -
#   cannot attribute a function to an owner, so the columns are elided there and
#   the footnote says why
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_fnown fn.info $IGNORE \
    --function-coverage --annotate-script `pwd`/annotate.pl --show-owners all \
    --ignore-errors annotate 2>&1 | tee fnown.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail fnown "genhtml failed with function coverage and owners"
fi
check_css html_fnown fnown
if [ ! -f html_fnown/index-bin_owner.html ] ; then
    fail fnown "no per-owner page was written"
else
    if ! grep -F -q -e "$NOTE" html_fnown/index-bin_owner.html ; then
        fail fnown "the per-owner page does not explain the elided columns"
    fi
    # ..and the directory which has no function data still says nothing about
    #   owners:  the columns are missing there for the other reason
    if grep -F -q -e "$NOTE" html_fnown/nofn/index.html ; then
        fail fnown "'nofn/index.html' blames a missing owner for missing data"
    fi
fi

# ----------------------------------------------------------------------
echo "*** 7. '--css-file' naming something which cannot be copied"
# ----------------------------------------------------------------------
# The other end of the stylesheet:  '--css-file' says to use the user's own
#   instead of writing one, and the copy is done before anything else in the
#   report is.  It was a 'cp' subprocess, whose failure was reported by printing
#   '$!' - which the subprocess does not set, so the message ended at its colon
#   with nothing after it.  What the user actually got the reason from was 'cp's
#   own stderr, printed ahead of the message because the child inherits the
#   handle; a report generated where that output is not kept had only the empty
#   message.  The message also did not say where the copy was going.
mkdir -p css_dir
printf 'body { color: red }\n' > good.css
printf 'not readable\n' > noread.css
chmod 000 noread.css

# every case is a different errno, so each one is a different thing for the
#   message to be unable to say
CSS_CASES="nosuch.css css_dir good.css"
if [ -r noread.css ] ; then
    # running with privilege enough to read it anyway - then it is not a case
    echo "note: skipping the unreadable '--css-file' case"
else
    CSS_CASES="$CSS_CASES noread.css"
fi

for CSS in $CSS_CASES ; do
    LOG=css_`basename $CSS`.log
    rm -rf html_css
    $COVER $GENHTML_TOOL $GENHTML_OPTS -o html_css zero.info $IGNORE \
        --css-file $CSS 2>&1 | tee $LOG
    RC=${PIPESTATUS[0]}
    if [ good.css == $CSS ] ; then
        # the case which works:  the file is used as it stands
        if [ 0 != $RC ] ; then
            fail css "genhtml failed with a readable --css-file"
        elif ! diff good.css html_css/gcov.css ; then
            fail css "the stylesheet written is not the one named by --css-file"
        fi
        continue
    fi
    if [ 0 == $RC ] ; then
        fail css "genhtml accepted an unusable --css-file '$CSS'"
        continue
    fi
    # the message names the file, names where it was going, and ends with the
    #   reason rather than with the colon which introduces it
    if ! grep -E -q "cannot copy file .*$CSS to .*gcov\.css: [^ ]" $LOG ; then
        fail css "no reason given for failing to copy '$CSS':"
        grep -F 'cannot copy' $LOG
    fi
done
chmod 644 noread.css

# ----------------------------------------------------------------------
echo "*** 8. a function on a line with no line coverage data"
# ----------------------------------------------------------------------
# 'bump' starts on line 3 and 'untested' on line 9, and neither of those lines
#   has a 'DA:' record - only the line inside the body does.  A compiler whose
#   gcov does not emit function end lines leaves lcov to derive them, and an
#   inline or a template function then arrives in exactly this shape;  written by
#   hand here so that the case does not depend on which gcov is installed.
# One of the two functions was called and the other was not, which is both arms
#   of the category the line inherits - 'GNC' and 'UNC'.
cat >proj/nofnline.c <<'EOF'
static int counter;

static inline int bump(void)
{
    return ++counter;
}
int use(void) { return bump(); }

static inline int untested(void)
{
    return 0;
}
EOF

cat >fnline.info <<'EOF'
TN:htmlgen
SF:proj/nofnline.c
FN:3,6,bump
FNDA:2,bump
FN:7,7,use
FNDA:1,use
FN:9,12,untested
FNDA:0,untested
FNF:3
FNH:2
DA:5,2
DA:7,1
LF:2
LH:2
end_of_record
EOF

# note that '$IGNORE' does not contain 'category':  the uncategorized line is an
#   error, so this run stops rather than writing a wrong report
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_fnline fnline.info $IGNORE \
    --function-coverage --show-noncode --show-navigation 2>&1 | tee fnline.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail fnline "genhtml failed on a function whose line has no line data"
fi
if grep -F -q -e 'unexpected category' fnline.log ; then
    fail fnline "a function-only line was left uncategorized"
fi
check_css html_fnline fnline
# ..and the category it was given is the function's own:  three lines counted as
#   hit (the two with line data, plus 'bump') and one as missed ('untested'),
#   against the two lines the file has line coverage data for
if ! grep -E -q '^  line: GNC:3 UNC:1$' fnline.log ; then
    fail fnline "the function-only lines were not counted with their function:"
    grep -E '^  (line|function):' fnline.log
fi

# the same data with a baseline, which is the path that always handled this - so
#   it is the answer the run above has to agree with.  '--baseline-file' with no
#   '--diff-file' warns about itself, which is not what this case is about
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_fnline_b fnline.info $IGNORE \
    --baseline-file fnline.info --function-coverage --show-noncode \
    --ignore-errors usage 2>&1 | tee fnline_b.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail fnline_b "genhtml failed on the same data with a baseline"
fi
check_css html_fnline_b fnline_b
# identical to the run above, in the vocabulary a differential report uses:  the
#   baseline is the current data, so nothing is new or changed and the hit lines
#   are 'CBC' rather than 'GNC' - three of them, the same three
if ! grep -E -q '^  line: UBC:1 CBC:3$' fnline_b.log ; then
    fail fnline_b "the baseline path counts the function-only lines differently:"
    grep -E '^  (line|function):' fnline_b.log
fi

# ----------------------------------------------------------------------
echo "*** 9. '--new-file-as-baseline' on an old file with no baseline data"
# ----------------------------------------------------------------------
# The intended use of the option:  a file which has been in the source tree for
#   a long time is added to the coverage build, so it is not in the baseline and
#   everything in it is 'included code' (UIC/GIC) - which fails a ratchet that
#   requires UIC to be zero.  The option says to call it baseline code instead
#   (UBC/CBC), on the grounds that the code is not new, only the measurement is.
# Every cover type has one hit and one un-hit coverpoint here, so each of them
#   shows both halves of the remap:  the un-hit branch of the 'if' on line 3, the
#   false sense of 'a' on line 5, the never-called 'g', and the two lines of 'g'.
cat >proj/old.c <<'EOF'
int f(int a, int b)
{
    if (a > 0)
        return 1;
    if (a > 0 && b > 0)
        return 2;
    return 0;
}

int g(void)
{
    return 3;
}
EOF

cat >newbase.info <<'EOF'
TN:htmlgen
SF:proj/old.c
FN:1,8,f
FNDA:3,f
FN:10,13,g
FNDA:0,g
FNF:2
FNH:1
DA:1,3
DA:3,3
DA:4,1
DA:5,3
DA:6,1
DA:7,2
DA:10,0
DA:12,0
BRDA:3,0,0,3
BRDA:3,0,1,0
BRF:2
BRH:1
MCDC:5,2,t,3,0,a
MCDC:5,2,f,0,0,a
MCDC:5,2,t,2,1,b
MCDC:5,2,f,1,1,b
MCF:4
MCH:3
LF:8
LH:6
end_of_record
EOF

# the baseline is a different file, so 'proj/old.c' has no baseline data at all -
#   which is what the option is about.  It has to be non-empty:  the option only
#   applies to a file which is missing from a baseline that exists
cat >proj/base.c <<'EOF'
int b(void)
{
    return 0;
}
EOF

cat >newbase_base.info <<'EOF'
TN:htmlgen
SF:proj/base.c
DA:1,1
DA:3,1
LF:2
LH:2
end_of_record
EOF

NFB_OPTS="--branch-coverage --mcdc-coverage --function-coverage"
NFB_OPTS="$NFB_OPTS --baseline-file newbase_base.info"
# the fixture script dates every line 2024-01-15, which is older than the
#   baseline '.info' this test just wrote - so the file is 'old' by the
#   comparison the option makes
ANNOTATE="--annotate-script `pwd`/annotate.pl --show-owners all"

# 'nfb' is the case the option is for; the other three are the cases it must
#   leave alone.  'noann' is the one the repair has to keep refusing:  with no
#   annotation data there is no age to compare, so nothing is old enough
for mode in nfb nfb_off nfb_noann nfb_olderbase ; do
    case $mode in
        nfb)     EXTRA="--new-file-as-baseline $ANNOTATE" ;;
        nfb_off) EXTRA="$ANNOTATE" ;;
        nfb_noann) EXTRA="--new-file-as-baseline" ;;
        nfb_olderbase)
            EXTRA="--new-file-as-baseline $ANNOTATE --baseline-date 2020-01-01" ;;
    esac
    rm -rf html_$mode
    $COVER $GENHTML_TOOL $GENHTML_OPTS -o html_$mode newbase.info $IGNORE \
        $NFB_OPTS $EXTRA 2>&1 | tee nfb_$mode.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail $mode "genhtml failed with --new-file-as-baseline ($mode)"
        continue
    fi
    check_css html_$mode $mode
    if [ nfb == $mode ] ; then
        # the file is old and not in the baseline:  baseline vocabulary
        EXPECT='UBC'
        HIT='CBC'
    else
        EXPECT='UIC'
        HIT='GIC'
    fi
    # one line of the bin summary per cover type, all four of them remapped or
    #   none of them.  The MC/DC line is the one which used to be empty
    for expected in "line: $EXPECT:2 $HIT:6" "branch: $EXPECT:1 $HIT:1" \
        "mcdc: $EXPECT:1 $HIT:3" "function: $EXPECT:1 $HIT:1" ; do
        if ! grep -E -q "^    $expected\$" nfb_$mode.log ; then
            fail $mode "expected '$expected' in the $mode bin summary:"
            grep -E '^    (line|branch|mcdc|function):' nfb_$mode.log
        fi
    done
    # ..and nothing of the other vocabulary anywhere in the report
    PAGE=`find html_$mode -name 'old.c.gcov.html'`
    if [ "x$PAGE" == 'x' ] || [ ! -f "$PAGE" ] ; then
        fail $mode "no source page was written"
        continue
    fi
    if [ nfb == $mode ] ; then
        OTHER='tlaUIC tlaGIC'
    else
        OTHER='tlaUBC tlaCBC'
    fi
    for cls in $OTHER ; do
        if grep -F -q -e "$cls" $PAGE ; then
            fail $mode "'$cls' in the $mode source page"
        fi
    done
    # the MC/DC coverpoints are on the page at all:  four markers on line 5,
    #   which are dropped entirely if the categorizer walks only the baseline.
    #   All four are on one line, so this counts matches and not lines
    COUNT=`grep -o -F -e 'class="mcdcTla"' $PAGE | wc -l`
    if [ 4 != "$COUNT" ] ; then
        fail $mode "expected 4 MC/DC markers in the $mode page, found $COUNT"
    fi
    # ..and each marker carries its own TLA, which is where the remap has to
    #   have been written through the mutator rather than into a copy
    if ! grep -F -q -e "title=\"$EXPECT: False sense of expression &quot;a&quot; was not sensitized\"" \
        $PAGE ; then
        fail $mode "the un-sensitized MC/DC sense is not '$EXPECT' in $mode:"
        grep -o -e 'title="[A-Z][A-Z][A-Z]: False sense[^"]*"' $PAGE
    fi
done

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'htmlgen' $LOCAL_COVERAGE 0
fi

exit $STATUS
