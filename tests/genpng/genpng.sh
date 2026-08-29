#!/usr/bin/env bash
#
# Test suite for bin/genpng
#
# genpng draws one pixel per source character, coloring each row by the coverage
# of the line it came from.  It had no test at all, and the three things checked
# below were all broken:
#
#   - the reader for '.gcov' input still expected the layout gcc 2.x/3.0 wrote.
#     One of those patterns matches a modern line with an empty count field, so
#     every line was read as uninstrumented and the image came out uniformly
#     plain:  a picture of nothing, with no error and a zero exit status.
#   - tabs were expanded over the whole '<count>:<text>' string rather than over
#     the source text, so a line's indentation moved by the width of that line's
#     own hit count and two lines at the same indentation were drawn at
#     different ones.
#   - the row's tag and count were carried forward to the next row from the
#     regexp capture buffers rather than from the values the row was drawn with.
#     Those are empty for an uninstrumented row, so the color of a block of
#     uninstrumented lines reset after the first of them instead of extending
#     over the whole block.
#
# The images are read back with GD (see dumppng.pl) rather than compared against
# a stored PNG, and the expected colors are read out of lcovutil, so the checks
# are about the geometry and the categories rather than about the palette or the
# PNG encoding.
#
# Tests:
#   1.  a '.gcov' file written by this toolchain's gcov
#   2.  the modern '.gcov' layout, checked line by line
#   3.  a file which is not '.gcov' is plain text
#   4.  --dark-mode
#   5.  --help, --version, and a missing filename

set +x

if [[ "x" == "${LCOV_HOME}x" ]] ; then
    if [ -f ../../bin/lcov ] ; then
        LCOV_HOME=../..
    fi
fi
source ../common.tst

PERL="${COVER:-perl}"

# genpng cannot do anything at all without GD.pm, and nothing else in the suite
#   needs it, so it may well not be installed.  Say so loudly rather than
#   reporting a pass which checked nothing
if ! perl -e 'use GD;' 2>/dev/null ; then
    echo "*** SKIPPING ALL genpng TESTS: GD.pm is not installed on this system"
    echo "***   genpng exits with an error without it, so there is nothing to test"
    exit 0
fi

rm -f *.png *.log *.gcov *.gcda *.gcno prog plain.txt hand.c.gcov
rm -rf real

clean_cover

if [ "$CLEAN_ONLY" == 1 ] ; then
    exit 0
fi

PASS=0
FAIL=0

pass() { echo "PASS: $1" ; PASS=$((PASS + 1)) ; }
fail() { echo "FAIL: $1" ; FAIL=$((FAIL + 1)) ;
         if [ "$KEEP_GOING" != 1 ] ; then exit 1 ; fi ; }

# The categories a report with no baseline uses:  'GNC' is hit and 'UNC' is not
#   hit.  Read them from the library rather than writing the hex here, so that a
#   palette change is not a test failure
GNC=$($PERL -I$LCOV_HOME/lib -e \
      'use lcovutil; print lc($lcovutil::tlaColor{GNC});' | tr -d '#')
UNC=$($PERL -I$LCOV_HOME/lib -e \
      'use lcovutil; print lc($lcovutil::tlaColor{UNC});' | tr -d '#')
# the background for a line which is not instrumented at all;  genpng allocates
#   this one itself rather than taking it from the category table
PLAIN=ffffff
DARK=000000

if [ -z "$GNC" ] || [ -z "$UNC" ] ; then
    echo "unable to read the category colors from lcovutil" >&2
    exit 1
fi

# dump <image> -- one line per row: '<row> <background> <first text column>'
dump() { $PERL ./dumppng.pl "$1" ; }

# row <dumpfile> <row> -- the dump line for one row of the image
row() { sed -n "$(($2 + 1))p" "$1" ; }

# ---------------------------------------------------------------------------
# Test 1: a '.gcov' file produced by the gcov which matches $CC
#   The point of the test is that genpng reads what today's gcov actually
#   writes, so the input has to come from gcov rather than from this script.
#   What is asserted is only that both categories reached the image - the exact
#   geometry depends on the compiler, and test 2 checks that against a fixed
#   input
# ---------------------------------------------------------------------------
mkdir real
cat > real/prog.c << 'EOF'
#include <stdio.h>

int hit(int a)
{
	return a + 1;
}

int missed(int a)
{
	return a - 1;
}

int main()
{
	printf("%d\n", hit(1));
	return 0;
}
EOF

echo $CC --coverage -o real/prog real/prog.c
( cd real && $CC --coverage -o prog prog.c && ./prog && $GCOV prog.c ) \
    > real.log 2>&1
if [ 0 != $? ] ; then
    cat real.log
    fail "Test 1 gcov: unable to build and run the testcase"
elif [ ! -f real/prog.c.gcov ] ; then
    cat real.log
    fail "Test 1 gcov: '$GCOV' did not write real/prog.c.gcov"
else
    echo genpng real/prog.c.gcov
    $COVER $GENPNG_TOOL --width 80 -o real.png real/prog.c.gcov 2>&1 | tee genpng1.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail "Test 1 gcov: genpng failed"
    elif [ -s genpng1.log ] ; then
        cat genpng1.log
        fail "Test 1 gcov: genpng printed something"
    else
        dump real.png > real.dump
        if ! grep -q " $GNC " real.dump ; then
            fail "Test 1 gcov: no line was drawn as hit ($GNC): `cat real.dump`"
        elif ! grep -q " $UNC " real.dump ; then
            fail "Test 1 gcov: no line was drawn as not hit ($UNC): `cat real.dump`"
        else
            pass "Test 1: a .gcov file from this toolchain's gcov is read"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Test 2: the modern layout, '<count>:<line number>:<source text>'
#   Written here rather than captured, so that every row of the image has a
#   known expected value:  a count of '-' is an uninstrumented line, '#####' and
#   '=====' are lines which were never executed, a trailing '*' on the count
#   marks a line containing an unexecuted block, and line number 0 carries the
#   file's metadata rather than any source.
#   The two hit lines are indented by one tab and have counts of very different
#   widths, so that they must still be drawn at the same indentation.
# ---------------------------------------------------------------------------
printf -- '        -:    0:Source:hand.c\n' >  hand.c.gcov
printf -- '        -:    0:Runs:1\n'        >> hand.c.gcov
printf -- '        -:    1:int main()\n'    >> hand.c.gcov
printf -- '        -:    2:{\n'             >> hand.c.gcov
printf -- '        3:    3:\tint a = 1;\n'  >> hand.c.gcov
printf -- '    1000*:    4:\tint b = 2;\n'  >> hand.c.gcov
printf -- '    #####:    5:\tint c = 3;\n'  >> hand.c.gcov
printf -- '    =====:    6:\tint d = 4;\n'  >> hand.c.gcov
printf -- '        -:    7:\n'              >> hand.c.gcov
printf -- '        -:    8:\treturn 0;\n'   >> hand.c.gcov
printf -- '        -:    9:}\n'             >> hand.c.gcov

echo genpng --tab-size 4 hand.c.gcov
$COVER $GENPNG_TOOL --width 60 --tab-size 4 -o hand.png hand.c.gcov 2>&1 | tee genpng2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "Test 2 layout: genpng failed"
elif [ -s genpng2.log ] ; then
    # the '*' on the count of line 4 has to be stripped before the count is
    #   compared with zero, or the comparison warns that it is not a number
    cat genpng2.log
    fail "Test 2 layout: genpng printed something"
else
    dump hand.png > hand.dump
    # nine source lines, and no row for either of the two metadata lines
    ROWS=`wc -l < hand.dump`
    if [ "$ROWS" != 9 ] ; then
        fail "Test 2 layout: expected 9 rows, got $ROWS: `cat hand.dump`"
    else
        pass "Test 2a: line number 0 carries metadata, not source"
    fi

    # the expected '<background> <first text column>' of each row.  Rows 4 to 8
    #   are all in the 'not hit' category:  the three uninstrumented lines after
    #   line 6 take the color of the line above them, which is what widens a
    #   block of uninstrumented lines into one colored area
    EXPECT=()
    EXPECT[0]="$PLAIN 0"      # int main()
    EXPECT[1]="$PLAIN 0"      # {
    EXPECT[2]="$GNC 4"        # tab, count '3'
    EXPECT[3]="$GNC 4"        # tab, count '1000*' - the same indentation
    EXPECT[4]="$UNC 4"        # tab, count '#####'
    EXPECT[5]="$UNC 4"        # tab, count '====='
    EXPECT[6]="$UNC -1"       # empty line - no text pixel at all
    EXPECT[7]="$UNC 4"        # tab, uninstrumented
    EXPECT[8]="$UNC 0"        # }
    RC=0
    for i in `seq 0 8` ; do
        GOT=`row hand.dump $i | cut -d' ' -f2-`
        if [ "$GOT" != "${EXPECT[$i]}" ] ; then
            echo "  row $i: expected '${EXPECT[$i]}', got '$GOT'"
            RC=1
        fi
    done
    if [ 0 != $RC ] ; then
        fail "Test 2 layout: the image does not match the input"
    else
        pass "Test 2b: every row is drawn in the category and column expected"
    fi
fi

# ---------------------------------------------------------------------------
# Test 3: an input which is not named '.gcov' is plain text
#   Every line is uninstrumented, so every row is the plain background
# ---------------------------------------------------------------------------
printf 'line one\n\tline two\nline three\n' > plain.txt
echo genpng plain.txt
$COVER $GENPNG_TOOL --width 60 --tab-size 4 -o plain.png plain.txt 2>&1 | tee genpng3.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "Test 3 plain text: genpng failed"
else
    dump plain.png > plain.dump
    if [ "`wc -l < plain.dump`" != 3 ] ; then
        fail "Test 3 plain text: expected 3 rows: `cat plain.dump`"
    elif [ "`grep -c \" $PLAIN \" plain.dump`" != 3 ] ; then
        fail "Test 3 plain text: not every row is plain: `cat plain.dump`"
    elif [ "`row plain.dump 1 | cut -d' ' -f3`" != 4 ] ; then
        fail "Test 3 plain text: the tab was not expanded: `cat plain.dump`"
    else
        pass "Test 3: a file which is not .gcov is drawn as plain text"
    fi
fi

# ---------------------------------------------------------------------------
# Test 4: --dark-mode reverses the plain foreground and background
# ---------------------------------------------------------------------------
echo genpng --dark-mode hand.c.gcov
$COVER $GENPNG_TOOL --width 60 --tab-size 4 --dark-mode -o dark.png hand.c.gcov 2>&1 |
    tee genpng4.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "Test 4 dark mode: genpng failed"
else
    dump dark.png > dark.dump
    if [ "`row dark.dump 0 | cut -d' ' -f2`" != "$DARK" ] ; then
        fail "Test 4 dark mode: an uninstrumented line is not dark: `cat dark.dump`"
    elif [ "`row dark.dump 2 | cut -d' ' -f2`" != "$GNC" ] ; then
        fail "Test 4 dark mode: the category colors changed: `cat dark.dump`"
    else
        pass "Test 4: --dark-mode reverses the plain colors"
    fi
fi

# ---------------------------------------------------------------------------
# Test 5: the usage messages
# ---------------------------------------------------------------------------
$COVER $GENPNG_TOOL --help > help.log 2>&1
if [ 0 != $? ] ; then
    fail "Test 5 usage: --help did not exit 0"
elif ! grep -q 'output-filename' help.log ; then
    fail "Test 5 usage: --help did not print the option list: `cat help.log`"
else
    pass "Test 5a: --help prints the usage message"
fi

$COVER $GENPNG_TOOL --version > version.log 2>&1
if [ 0 != $? ] ; then
    fail "Test 5 usage: --version did not exit 0"
elif ! grep -q 'genpng' version.log ; then
    fail "Test 5 usage: --version did not name the tool: `cat version.log`"
else
    pass "Test 5b: --version prints the version"
fi

$COVER $GENPNG_TOOL > noname.log 2>&1
if [ 0 == $? ] ; then
    fail "Test 5 usage: no filename should be an error"
elif ! grep -q 'No filename specified' noname.log ; then
    fail "Test 5 usage: did not say what was missing: `cat noname.log`"
else
    pass "Test 5c: a missing filename is an error"
fi

$COVER $GENPNG_TOOL --no-such-option hand.c.gcov > badopt.log 2>&1
if [ 0 == $? ] ; then
    fail "Test 5 usage: an unknown option should be an error"
elif ! grep -q 'to get usage information' badopt.log ; then
    fail "Test 5 usage: no pointer to --help: `cat badopt.log`"
else
    pass "Test 5d: an unknown option is an error"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ] ; then
    echo "Tests FAILED"
else
    echo "All genpng tests passed"
fi

if [ "x$COVER" != "x" ] && [ 0 != $LOCAL_COVERAGE ] ; then
    generate_coverage 'genpng' $LOCAL_COVERAGE 0
fi

[ $FAIL -eq 0 ]
