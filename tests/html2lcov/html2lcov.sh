#!/bin/bash
set +x

# Exercise the html2lcov tool, which screen-scrapes a genhtml-generated HTML
# report to recover (a) the saved .info coverage data and (b) the embedded
# source, then diffs that source against a --source-directory.  Scenarios:
#   1.  round-trip: geninfo -> genhtml --save -> html2lcov; recovered .info
#       matches the original DA records.
#   2.  report built WITHOUT --save => error (no .info in the report).
#   3.  source directory with no matching file => error.
#   4.  a file added under --source-directory is classified 'added'.
#   5.  a file removed from --source-directory is classified 'removed'.
#   6.  a changed file is classified 'changed' with +/- counts and a udiff.
#   7.  a whitespace-only / tab-vs-space change is classified 'unchanged'
#       (validates the 'diff -b' handling:  a tab and a run of spaces compare
#       equal, so no tab expansion is needed).
#   8.  --profile produces JSON; the JSON is consumable by spreadsheet.py.
#   9.  the udiff is valid 'diff -u' and is consumed by 'genhtml --diff';
#       udiff goes to stdout when -o is omitted.
#   10. multiple --source-directory roots resolve by relative path; --exclude
#       affects file selection.
#   11. shared writer/reader contract: genhtml --save with a baseline writes
#       'current_'/'baseline_' prefixed files that html2lcov still locates.
#   12. report saved WITHOUT source pages (genhtml --no-sourceview): .info is
#       present but no source is scrapable => ERROR_SOURCE (ignorable).
#   13. index.html coverFile row missing its 'title=' attribute: fall back to
#       deriving the source path from the .gcov.html name relative to the root.
#   14. usage-error diagnostics (no report dir; a non-directory arg; no saved
#       .info in any report dir); '--ignore usage' downgrades them to warnings.
#   15. the underlying 'diff' invocation fails (exit status > 1) => reported and
#       fatal (a stub 'diff' that always exits 2 is shadowed onto PATH).
#   16. --current-file whitelist restricts the udiff to named SF: files;
#       multi-value + comma-separated option handling; abs + rel path match.
#   17. --current-file SF: path not on disk => ignorable ERROR_SOURCE; when
#       ignored the file is dropped from the udiff and the aggregated .info.
#   18. --current-file path-mismatch (shared basename) => ignorable warning.
#   19. --current-file validation: missing=fatal, empty=ERROR_EMPTY, no-SF=fatal.
#   20. a recovered source page with a non-contiguous (missing) line number is
#       back-filled with a blank line (gap-line handling).
#   21. --current-file whitelist + --exclude:  an 'added' whitelisted file that
#       matches an exclude pattern is skipped (not added).
#   22. source-text extraction with an in-source ' : ' (a C ternary 'a ? b : c')
#       must anchor on the count-column separator, not the last ' : ' on the
#       row, so identical source round-trips as 'unchanged' (regression).
#   23. the udiff feeds 'genhtml --diff-file/--baseline-file' for a file with a
#       DELETED line (the coverage.sh differential-report workflow):  both diff
#       headers must name the SAME path (equal to the .info 'SF:' record), or
#       genhtml cannot recover the deleted baseline line and dies with
#       "missing baseline line" (regression).
#   24. no-common-root fallback:  a report whose recovered source paths share no
#       common leading directory (here 'mr1/one.c' and 'mr2/two.c') makes
#       common_root() return undef, so files are keyed by their full recovered
#       path rather than a report-root-relative path.  Classification and the
#       udiff/.info paths must still be correct.
#   25. parallel scrape + diff:  a report with enough source files to be split
#       into more than one chunk is scraped and diffed in child processes, with
#       the chunks balanced by the size of the HTML pages they have to scrape.
#       The .info, .rpt and .udiff outputs must be byte-identical to the same
#       run with '--parallel 1' (which does the work in this process and forks
#       nothing).
#   26. ..and the failure arms of that fork/join loop:  a child which the OS
#       kills, a child which leaves no serialized data, a child which cannot
#       store what it computed, and a fork() which fails.  In every case the
#       chunk is requeued and the run produces exactly what the un-injected run
#       produced (see tests/lcov/parallel_fail for the injection mechanism).
#   27. 'diff' killed by a signal (as opposed to scenario 15, where it exits
#       with an error status):  a signalled child's exit field is zero, so this
#       has to be recognised from the signal number or it reads as success and
#       every file compares equal.
#   28. a report file whose current version is found under a name which is not
#       its report-relative path - here via '--substitute'.  It has already been
#       compared against the report, so the walk for new files must not offer it
#       a second time as an 'added' file.
#   29. a report whose recovered source paths share only the filesystem root
#       (one under the test directory, one under /tmp).  'splitdir' of an
#       absolute path yields a leading empty component, so the two paths do have
#       a common component - which is not a common root.
#   30. '-o' with a dot in a directory component and none in the file name:
#       only the file name's extension may be stripped to make the output base.

if [[ "x" == ${LCOV_HOME}x ]] ; then
    if [ -f ../../bin/lcov ] ; then
        LCOV_HOME=../..
    fi
fi
source ../common.tst

rm -rf *.gcda *.gcno a.out *.info *.info.gz *.json *.log rpt* \
    out* err* prof* diffrpt src src2 more baseline_src empty_src \
    html2lcov.rpt html2lcov.info stdout.udiff stdout.err *.diff notadir.txt \
    *.udiff fakebin cur*.info src_partial src_mm src_gap rpt_gap src_tern \
    src_del rpt_del diffrpt_del mr_build src_mr par_build src_par2 \
    fakekill src_sub dup_build dot.d
# the second filesystem root scenario 29 needs (see there).  Named after the
#   user, since it is not under this test's directory and two users may well
#   run the suite on the same machine
OTHER_ROOT=/tmp/html2lcov_disjoint_`id -u`
rm -rf $OTHER_ROOT

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type ${CC} >/dev/null 2>&1 ; then
    echo "Missing tool: ${CC}" >&2
    exit 2
fi

if [ 'x' == "x$GENHTML_TOOL" ] ; then
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    GENINFO_TOOL=${LCOV_HOME}/bin/geninfo
    HTML2LCOV_TOOL=${LCOV_HOME}/bin/html2lcov
fi

STATUS=0
fail() {
    echo "ERROR: $1"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

# a source tree with a subdirectory, so relative-path matching is exercised
mkdir -p src/sub
cat > src/a.c <<'EOF'
int gg(int x);
int fa(int x){ if (x > 0) return 1; return 0; }
int main(){ return fa(1) + gg(1); }
EOF
cat > src/sub/b.c <<'EOF'
int fb(int x){ if (x > 1) return 2; return 0; }
EOF
# a multi-line file whose modified copy (src2/big.c below) changes only
#   interior lines, leaving a common prefix, a common suffix, AND a matching
#   context line inside the differing window.  This exercises html2lcov's
#   'diff -b -u' hunk generation on a real multi-line change:  an interior
#   context line sitting between two changed regions, which must appear as a
#   leading-space line inside the '@@' hunk.
cat > src/big.c <<'EOF'
int gg(int x){
    int r = 0;
    if (x > 0)
        r = 1;
    else
        r = 2;
    return r;
}
EOF

${CC} --coverage -c src/a.c src/sub/b.c src/big.c
${CC} --coverage a.o b.o big.o -o a.out
./a.out

# capture coverage into an .info that references the real source paths
$COVER $GENINFO_TOOL . --parallel 0 -o cov.info --ignore empty,unused 2>&1 |
    tee geninfo.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "geninfo capture failed"
fi

#-----------------------------------------------------------------------
# build a saved HTML report (scenario 1/9/11 setup)
#-----------------------------------------------------------------------
$COVER $GENHTML_TOOL cov.info -o rpt --save \
    --ignore empty,inconsistent,unused 2>&1 | tee genhtml_save.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "genhtml --save failed"
fi
# genhtml --save (no baseline) writes the .info with no prefix
if [ ! -f rpt/cov.info ] ; then
    fail "genhtml --save did not deposit cov.info in the report"
fi

#-----------------------------------------------------------------------
# 1. round-trip + 8. profile:  unmodified source => all 'unchanged',
#    recovered .info DA records match the original.  An empty udiff (the
#    current source is identical to the report) is a NORMAL, expected outcome:
#    html2lcov reports it as a non-fatal 'empty' WARNING and still exits 0.
#    (The recovered .info has no branch data, so the unrelated branch-coverage
#    'empty' warning is also emitted;  both share the 'empty' class, so we
#    '--ignore empty' here -- the point is simply that the run succeeds.)
#    We pass '-o out1.xyz' (with an extension) to exercise the base-name
#    derivation:  the trailing '.xyz' must be stripped so the artifacts land at
#    out1.info / out1.rpt / out1.udiff / out1.json (base == 'out1').
#-----------------------------------------------------------------------
$COVER $HTML2LCOV_TOOL rpt --source-directory src -o out1.xyz \
    --profile --ignore empty,unused 2>&1 | tee html2lcov1.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov round-trip run failed"
fi
# the '.xyz' extension must have been stripped:  no artifact keeps it
if ls out1.xyz* >/dev/null 2>&1 ; then
    fail "extension not stripped from -o argument (found out1.xyz* artifacts)"
fi
for f in out1.udiff out1.info out1.rpt out1.json ; do
    if [ ! -f $f ] ; then
        fail "expected artifact '$f' not produced"
    fi
done
# unmodified source: udiff must be empty
if [ -s out1.udiff ] ; then
    fail "udiff for unmodified source should be empty"
fi
# recovered coverage must match the original DA records
diff <(grep -E '^DA:' cov.info | sort) \
     <(grep -E '^DA:' out1.info | sort) > da.diff
if [ 0 != $? ] ; then
    fail "recovered .info DA records do not match the original"
    cat da.diff
fi
# every file should be reported 'unchanged'
if grep -qE 'changed|added|removed' out1.rpt ; then
    # 'unchanged' contains 'changed' as a substring; check the summary counts
    if ! grep -q '0 changed, 0 added, 0 removed' out1.rpt ; then
        fail "unmodified source should report no changes"
        cat out1.rpt
    fi
fi

# 8b. the html2lcov --profile JSON must be consumable by spreadsheet.py (which
#     recognizes tool == 'html2lcov' and emits its source/diff/info sections).
#     Use the profile from a run with real changes (src2 below is built later,
#     but src alone still yields 'source'/'parse'/'append' sections).  Skip
#     gracefully if the xlsxwriter module is unavailable.
if python3 -c 'import xlsxwriter' 2>/dev/null ; then
    eval ${PYCOVER} ${SPREADSHEET_TOOL} -o out8.xlsx out1.json 2>&1 |
        tee spreadsheet8.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail "spreadsheet.py failed on an html2lcov profile"
    fi
    if [ ! -s out8.xlsx ] ; then
        fail "spreadsheet.py produced no output for an html2lcov profile"
    fi
    if grep -qi 'not sure what to do\|unknown tool\|not lcov performance' \
        spreadsheet8.log ; then
        fail "spreadsheet.py did not recognize the html2lcov profile"
        cat spreadsheet8.log
    fi
    # a trimmed profile that omits a whole section group (no 'diff') exercises
    #   the section-skip path;  a single .info exercises the <2-samples (no
    #   stddev) path.
    cat > cur8b.json <<EOF
{ "config": { "tool": "html2lcov" }, "total": 0.5, "aggregate": 0.1,
  "source": { "a.c": 0.01 }, "check_consistency": { "a.c": 0.02 },
  "parse": { "x.info": 0.03 }, "append": { "x.info": 0.04 } }
EOF
    eval ${PYCOVER} ${SPREADSHEET_TOOL} -o out8b.xlsx cur8b.json 2>&1 |
        tee spreadsheet8b.log
    if [ 0 != ${PIPESTATUS[0]} ] || [ ! -s out8b.xlsx ] ; then
        fail "spreadsheet.py failed on a trimmed html2lcov profile"
    fi
    # the sections it did write must have the shape every sub-table has - a
    #   descriptive title saying what one row of the table is, a title row whose
    #   columns link to the glossary, the statistics rows, then the element rows.
    #   Both tables are one row long, so the sheet needs no index of them.  Uses
    #   the lcov scheduling test's generic checkers.
    CHECKERS=../lcov/scheduling
    python3 $CHECKERS/check_table_layout.py out8b.xlsx cur8b.json source info
    if [ 0 != $? ] ; then
        fail "html2lcov sub-table layout"
    fi
    python3 $CHECKERS/check_table_index.py out8b.xlsx cur8b.json noindex
    if [ 0 != $? ] ; then
        fail "html2lcov sub-table index"
    fi
else
    echo "skipping spreadsheet.py check: xlsxwriter not installed"
fi

# 1c. an empty udiff is NOT fatal:  it is a normal/expected outcome, reported
#     as a non-fatal 'empty' WARNING, and the tool still exits 0.  Here we
#     confirm the exit status and the warning text.  We build a report whose
#     saved .info carries branch data (--branch-coverage on capture) so the
#     unrelated 'no branch coverpoints' empty warning does NOT fire and we can
#     leave 'empty' un-ignored to observe the empty-udiff warning itself.
$COVER $GENINFO_TOOL . --parallel 0 --branch-coverage -o covbr.info \
    --ignore empty,unused 2>&1 > /dev/null
$COVER $GENHTML_TOOL covbr.info -o rpt_br --save --branch-coverage \
    --ignore empty,inconsistent,unused 2>&1 > /dev/null
$COVER $HTML2LCOV_TOOL rpt_br --source-directory src -o out1c --branch-coverage \
    --ignore unused 2>&1 | tee html2lcov1c.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "empty udiff should be non-fatal (a warning), so the run must succeed"
fi
grep -q "WARNING: (empty) No source code differences found" html2lcov1c.log ||
    fail "empty udiff should be reported as a non-fatal 'empty' warning"
# and '--ignore empty' suppresses the message entirely (still exits 0)
$COVER $HTML2LCOV_TOOL rpt_br --source-directory src -o out1d --branch-coverage \
    --ignore empty,unused 2>&1 | tee html2lcov1d.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "empty udiff run with '--ignore empty' should succeed"
fi
if grep -q "No source code differences found" html2lcov1d.log ; then
    fail "'--ignore empty' should suppress the empty-udiff message"
fi

#-----------------------------------------------------------------------
# 2. report built WITHOUT --save => error (no .info recoverable)
#-----------------------------------------------------------------------
$COVER $GENHTML_TOOL cov.info -o rpt_nosave \
    --ignore empty,inconsistent,unused 2>&1 > /dev/null
$COVER $HTML2LCOV_TOOL rpt_nosave --source-directory src -o err2 \
    --ignore empty,unused 2>&1 | tee err2.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail "expected error for report without --save"
fi
grep -q "run with '--save'" err2.log ||
    fail "missing expected 'no saved .info' diagnostic"

#-----------------------------------------------------------------------
# 3. source directory with no matching file => error
#-----------------------------------------------------------------------
mkdir -p empty_src
$COVER $HTML2LCOV_TOOL rpt --source-directory empty_src -o err3 \
    --ignore empty,unused 2>&1 | tee err3.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail "expected error when no source matches"
fi
grep -q "no file under --source-directory matches" err3.log ||
    fail "missing expected 'no matching source' diagnostic"

#-----------------------------------------------------------------------
# 4/5/6/9. changed + added + removed:  edit a.c, add c.c, drop b.c
#-----------------------------------------------------------------------
mkdir -p src2
cat > src2/a.c <<'EOF'
int gg(int x);
int fa(int x){ if (x >= 0) return 1; return 0; }
int main(){ return fa(2) + gg(1); }
EOF
cat > src2/c.c <<'EOF'
int fc(void){ return 42; }
EOF
# a non-source file in the source directory must be ignored (not classified as
#   'added') -- exercises the source-extension filter's reject path.
cat > src2/README.txt <<'EOF'
This is documentation, not source code.
EOF
# big.c with only interior lines changed:  the first line (common prefix) and
#   the last two lines (common suffix) are unchanged, and lines 3-5 in the
#   middle still match -- so the differing window has an interior context line.
#   This drives the 'diff -b -u' hunk generation (interior context inside a
#   single @@ hunk).
cat > src2/big.c <<'EOF'
int gg(int x){
    int r = 5;
    if (x > 0)
        r = 1;
    else
        r = 3;
    return r;
}
EOF
# note: src2 has no sub/b.c -> b.c must be 'removed'
$COVER $HTML2LCOV_TOOL rpt --source-directory src2 -o out2 \
    --ignore empty,unused 2>&1 | tee html2lcov2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov changed/added/removed run failed"
fi
grep -qE '^a\.c +changed' out2.rpt || fail "a.c not classified 'changed'"
grep -qE '^big\.c +changed' out2.rpt || fail "big.c not classified 'changed'"
grep -qE '^c\.c +added' out2.rpt || fail "c.c not classified 'added'"
grep -qE 'b\.c +removed' out2.rpt || fail "b.c not classified 'removed'"
# the non-source README.txt must NOT be picked up as an 'added' source file
grep -q 'README' out2.rpt && fail "non-source README.txt wrongly classified"
# big.c drives the interior-change diff path:  its hunk must contain an
#   interior context line (a leading-space line sitting between two changes),
#   which confirms 'diff -b -u' emitted a single hunk with interior context.
# interior context = a change, then a leading-space line, then another change
if ! awk '
    /^--- .*big\.c/ { inbig = 1 }
    inbig && /^\+\+\+/ { active = 1; next }
    active && /^--- /  { active = 0; inbig = 0 }
    active && /^[-+]/  { if (ctx_after_chg) interior = 1; seenchg = 1 }
    active && /^ /     { if (seenchg) ctx_after_chg = 1 }
    END { exit !interior }
' out2.udiff ; then
    fail "big.c udiff has no interior context line (diff -b -u hunk not exercised)"
    cat out2.udiff
fi
# udiff must be a well-formed unified diff:  a changed hunk and a /dev/null add
grep -q '^@@ ' out2.udiff || fail "udiff has no hunk header"
grep -q '^--- /dev/null' out2.udiff || fail "added file not shown against /dev/null"
# deletions must precede additions inside the changed hunk
if ! awk '/^-int fa/{d=NR} /^\+int fa/{a=NR} END{exit !(d && a && d < a)}' out2.udiff
then
    fail "udiff does not order deletions before additions"
fi

# 6b. --diff-file redirects the udiff away from the default <base>.udiff to the
#     named file;  the derived <base>.rpt (human report) and <base>.info are
#     still produced, and the default <base>.udiff is NOT written.  (src2 has
#     real changes, so there is a non-empty udiff to redirect.)
$COVER $HTML2LCOV_TOOL rpt --source-directory src2 -o out6b \
    --diff-file out6b_alt.udiff --ignore empty,unused 2>&1 | tee html2lcov6b.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov --diff-file run failed"
fi
# the udiff went to the --diff-file target, not the default <base>.udiff
grep -q '^@@ ' out6b_alt.udiff ||
    fail "--diff-file did not receive the universal diff"
if [ -f out6b.udiff ] ; then
    fail "--diff-file should suppress the default <base>.udiff output"
fi
# the derived <base>.rpt still holds the human-readable report
grep -q 'html2lcov difference report' out6b.rpt ||
    fail "<base>.rpt should hold the human report when --diff-file is used"
if grep -q '^@@ ' out6b.rpt ; then
    fail "<base>.rpt should not contain the udiff"
fi

# 9. the udiff round-trips through 'genhtml --diff' without error.  html2lcov
#    emits both diff headers ('---' and '+++') as the SAME path -- the report's
#    original source path, which is exactly the 'SF:' record in the recovered
#    .info -- so genhtml associates the diff with the coverage data with no
#    path mismatch and no basename-collision guessing.  (Scenario 23 exercises
#    the same round-trip for a DELETED line, where a mismatched header pair
#    would make genhtml die "missing baseline line".)
$COVER $GENHTML_TOOL out2.info -o diffrpt --diff-file out2.udiff \
    --ignore empty,inconsistent,unused 2>&1 | tee gendiff.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "genhtml could not consume the html2lcov udiff"
fi
# the headers matched the .info SF records, so no path/mismatch warning fired
if grep -qiE 'mismatch|ERROR: .*path' gendiff.log ; then
    fail "genhtml reported a path mismatch consuming the html2lcov udiff"
    cat gendiff.log
fi

# 9. udiff goes to stdout when -o is omitted; base name is 'html2lcov'
$COVER $HTML2LCOV_TOOL rpt --source-directory src2 \
    --ignore empty,unused > stdout.udiff 2> stdout.err
grep -q '^@@ ' stdout.udiff || fail "udiff not written to stdout when -o omitted"
if [ ! -f html2lcov.info ] ; then
    fail "default base name 'html2lcov' not used for .info"
fi

#-----------------------------------------------------------------------
# 7. whitespace-only / tab change => 'unchanged'
#-----------------------------------------------------------------------
mkdir -p more
# vary only INTERIOR whitespace:  an interior tab and extra interior spaces,
#   but the same (absent) leading indentation as the original.  'diff -b'
#   ignores changes in the amount of interior whitespace, so this is
#   'unchanged';  note that adding LEADING whitespace where there was none is a
#   real change under 'diff -b' (none is not "one or more"), so we must not do
#   that here.  The interior tab additionally confirms that 'diff -b' treats a
#   tab and a run of spaces as equal amounts of whitespace (so no tab expansion
#   is needed).
printf 'int gg(int x);\nint\tfa(int x){ if (x > 0)  return 1;   return 0; }\nint main(){ return fa(1) + gg(1); }\n' \
    > more/a.c
mkdir -p more/sub
cp src/sub/b.c more/sub/b.c
cp src/big.c more/big.c
$COVER $HTML2LCOV_TOOL rpt --source-directory more -o out7 \
    --ignore empty,unused 2>&1 | tee html2lcov7.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov whitespace run failed"
fi
if [ -s out7.udiff ] ; then
    fail "whitespace-only change should produce an empty udiff"
    cat out7.udiff
fi
grep -q '0 changed' out7.rpt ||
    fail "whitespace-only change should report 0 changed"

#-----------------------------------------------------------------------
# 10. multiple --source-directory + --exclude
#-----------------------------------------------------------------------
# split the current sources across two roots; a.c under src2, b.c under more
$COVER $HTML2LCOV_TOOL rpt --source-directory src2 --source-directory more \
    -o out10 --exclude '*/sub/b.c' --ignore empty,unused 2>&1 |
    tee html2lcov10.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov multi-source run failed"
fi
# b.c was excluded -> must not appear in the report
if grep -qE '(^|/)b\.c' out10.rpt ; then
    fail "--exclude did not drop b.c"
    cat out10.rpt
fi

#-----------------------------------------------------------------------
# 11. shared writer/reader contract with a baseline (current_/baseline_)
#-----------------------------------------------------------------------
# build a baseline .info (fewer hits) and a report that saves both
cp cov.info baseline.info
$COVER $GENHTML_TOOL cov.info --baseline-file baseline.info -o rpt_base \
    --save --ignore empty,inconsistent,unused 2>&1 > /dev/null
# with a baseline, genhtml --save prefixes the current file 'current_'
if ! ls rpt_base/current_*.info >/dev/null 2>&1 ; then
    fail "genhtml --save did not write current_ prefixed .info with a baseline"
fi
$COVER $HTML2LCOV_TOOL rpt_base --source-directory src -o out11 \
    --ignore empty,unused 2>&1 | tee html2lcov11.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov could not read a baselined saved report"
fi
# it must find the current_ file and NOT mistake baseline_ for current
diff <(grep -E '^DA:' cov.info | sort) \
     <(grep -E '^DA:' out11.info | sort) > da11.diff
if [ 0 != $? ] ; then
    fail "recovered .info from baselined report does not match current data"
    cat da11.diff
fi

#-----------------------------------------------------------------------
# 12. report saved WITHOUT source pages (genhtml --no-sourceview):  the .info
#     is present but no .gcov.html source can be scraped.  This is a real
#     user-site situation and must be reported as an ERROR_SOURCE.
#-----------------------------------------------------------------------
$COVER $GENHTML_TOOL cov.info -o rpt_nosrc --save --no-sourceview \
    --ignore empty,inconsistent,unused 2>&1 > /dev/null
if [ -n "$(find rpt_nosrc -name '*.gcov.html' 2>/dev/null)" ] ; then
    fail "--no-sourceview unexpectedly wrote source pages"
fi
# fatal by default: 'no source recovered from HTML report'
$COVER $HTML2LCOV_TOOL rpt_nosrc --source-directory src -o err12 \
    --ignore empty,unused 2>&1 | tee err12.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail "expected error when the report has no scrapable source"
fi
grep -q "no source recovered from HTML report" err12.log ||
    fail "missing expected 'no source recovered' diagnostic"

# 12b. with '--ignore source' the run continues; because no report source AND
#      no matching source were found, the .txt report shows the empty-set path.
$COVER $HTML2LCOV_TOOL rpt_nosrc --source-directory empty_src -o out12b \
    --ignore empty,unused,source 2>&1 | tee html2lcov12b.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov should continue past 'no source' when it is ignored"
fi
grep -q 'no source files recovered' out12b.rpt ||
    fail "empty difference report should say '(no source files recovered)'"

#-----------------------------------------------------------------------
# 13. index.html coverFile row missing its 'title=' attribute:  html2lcov
#     must fall back to deriving the source path from the .gcov.html page
#     name relative to the report root.  Hand-hack a good report to remove
#     the title attribute (older/edited reports can lack it).
#-----------------------------------------------------------------------
rm -rf rpt_notitle
cp -r rpt rpt_notitle
find rpt_notitle -name 'index.html' -exec perl -i -pe \
    's/(<td class="coverFile"><a href="[^"]+")\s+title="Click to go to file [^"]*"/$1/g' \
    {} +
if grep -rq 'coverFile"><a href="[^"]*" *title=' rpt_notitle/*/index.html ; then
    fail "test setup: failed to strip title= from coverFile rows"
fi
# the fallback derives paths relative to the report root (src/a.c, ...), so the
#   recovered root is 'src'; match against --source-directory src
$COVER $HTML2LCOV_TOOL rpt_notitle --source-directory src -o out13 \
    --ignore empty,unused 2>&1 | tee html2lcov13.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov failed on a report whose rows lack a title attribute"
fi
# the path-fallback still recovers all files:  everything is 'unchanged'
grep -qE '^a\.c +unchanged'     out13.rpt || fail "title-fallback lost a.c"
grep -qE '^sub/b\.c +unchanged' out13.rpt || fail "title-fallback lost sub/b.c"

#-----------------------------------------------------------------------
# 14. usage-error diagnostics.  These are fatal by default (ERROR_USAGE),
#     but '--ignore usage' downgrades them to warnings so the tool keeps
#     going -- which exercises the continue/skip branches after each check.
#-----------------------------------------------------------------------
# 14a. no report directory named at all
$COVER $HTML2LCOV_TOOL --source-directory src -o err14a \
    --ignore empty,unused,usage 2>&1 | tee err14a.log
grep -q "no HTML report directory specified" err14a.log ||
    fail "missing 'no HTML report directory' diagnostic"

# 14b. a non-directory argument is skipped with a warning; a good report that
#      follows it is still processed (so the run succeeds).
touch notadir.txt
$COVER $HTML2LCOV_TOOL notadir.txt rpt --source-directory src -o out14b \
    --ignore empty,unused,usage 2>&1 | tee html2lcov14b.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov should skip a non-directory arg and process the good one"
fi
grep -q "'notadir.txt' is not a directory" html2lcov14b.log ||
    fail "missing 'not a directory' diagnostic"
if [ ! -f out14b.info ] ; then
    fail "the valid report after a bad arg was not processed"
fi

# 14c. only a report(s) lacking saved .info => the aggregate 'no .info in any
#      report directory' error (distinct from the per-directory message).
$COVER $HTML2LCOV_TOOL rpt_nosave --source-directory src -o err14c \
    --ignore empty,unused,usage 2>&1 | tee err14c.log
grep -q "no saved .info coverage data found in any" err14c.log ||
    fail "missing aggregate 'no .info in any report directory' diagnostic"

#-----------------------------------------------------------------------
# 15. the underlying 'diff' invocation fails (exit status > 1).  This is a
#     real user-site possibility (a broken/unavailable 'diff', a resource
#     limit, ...).  Shadow 'diff' with a stub that always exits 2 and confirm
#     html2lcov reports the failure and dies.  src2 has real changes, so the
#     'diff -b -u' path is actually reached for at least one file.
#-----------------------------------------------------------------------
mkdir -p fakebin
cat > fakebin/diff <<'EOF'
#!/bin/sh
exit 2
EOF
chmod +x fakebin/diff
PATH="`pwd`/fakebin:$PATH" $COVER $HTML2LCOV_TOOL rpt --source-directory src2 \
    -o err15 --ignore empty,unused 2>&1 | tee err15.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail "html2lcov should fail when 'diff' exits with an error status"
fi
grep -q "'diff' failed (status 2)" err15.log ||
    fail "missing expected \"'diff' failed\" diagnostic"

#-----------------------------------------------------------------------
# 16. --current-file whitelist:  only files named in a current .info 'SF:'
#     record may appear in the udiff.  A whitelisted file is diffed;  a report
#     file NOT whitelisted is 'removed';  a whitelisted file not in the report
#     is 'added';  a source-directory file that is NOT whitelisted (even a
#     real source file) is ignored.  Also exercises the multi-value + comma-
#     separated (split_char) option handling, and matching by BOTH the report's
#     recovered absolute path (first candidate) and its report-relative path
#     (second candidate).
#-----------------------------------------------------------------------
# a whitelisted-but-ignored real source file:  present on disk, NOT in the
#   current set, so it must NOT be picked up as 'added' (proves the whitelist
#   restricts added-file discovery, unlike default mode).
cat > src2/extra.c <<'EOF'
int fx(void){ return 7; }
EOF
# split the whitelist across two files, comma-joined into ONE --current-file
#   value, so both the '@'-repeat and the split_char expansion are exercised.
#   'a.c' is given by its absolute recovered path (matches the first match
#   candidate);  'big.c' and 'c.c' by relative path (matches the second).
ACPATH=`grep -E '^SF:.*/a\.c$' cov.info | head -1 | sed 's/^SF://'`
if [ -z "$ACPATH" ] ; then
    fail "could not determine recovered absolute path of a.c"
fi
cat > cur16a.info <<EOF
TN:whitelist
SF:$ACPATH
DA:1,1
end_of_record
SF:big.c
DA:1,1
end_of_record
EOF
cat > cur16b.info <<'EOF'
SF:c.c
DA:1,1
end_of_record
EOF
$COVER $HTML2LCOV_TOOL rpt --source-directory src2 -o out16 \
    --current-file cur16a.info,cur16b.info \
    --ignore empty,unused 2>&1 | tee html2lcov16.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov --current-file run failed"
fi
grep -qE '^a\.c +changed'      out16.rpt || fail "16: a.c not 'changed'"
grep -qE '^big\.c +changed'    out16.rpt || fail "16: big.c not 'changed'"
grep -qE '^c\.c +added'        out16.rpt || fail "16: c.c not 'added'"
grep -qE 'b\.c +removed'       out16.rpt || fail "16: sub/b.c not 'removed'"
# extra.c is a real source file on disk but NOT whitelisted -> must be ignored
if grep -q 'extra\.c' out16.rpt ; then
    fail "16: non-whitelisted source extra.c wrongly included"
    cat out16.rpt
fi

#-----------------------------------------------------------------------
# 17. --current-file names a file that is not on disk.  For a file that IS in
#     the report (expected 'changed') this is a contradiction -> ERROR_SOURCE,
#     and when ignored the file is dropped from the udiff AND removed from the
#     aggregated .info.  For a file that is NOT in the report (expected 'added')
#     the same ERROR_SOURCE fires (removal from .info is a no-op).
#-----------------------------------------------------------------------
mkdir -p src_partial
# only a.c is present on disk (use the modified copy so the diff is non-empty)
cp src2/a.c src_partial/a.c
cat > cur17.info <<'EOF'
SF:a.c
DA:1,1
end_of_record
SF:big.c
DA:1,1
end_of_record
SF:ghost.c
DA:1,1
end_of_record
EOF
$COVER $HTML2LCOV_TOOL rpt --source-directory src_partial -o out17 \
    --current-file cur17.info --ignore empty,unused,source 2>&1 |
    tee html2lcov17.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov --current-file missing-source run failed"
fi
grep -q "'current' file '.*big\.c' not found" html2lcov17.log ||
    fail "17: missing 'current file not found' diagnostic for big.c"
grep -q "'current' file 'ghost\.c' not found" html2lcov17.log ||
    fail "17: missing 'current file not found' diagnostic for ghost.c"
# big.c must have been removed from the aggregated .info
if grep -qE '^SF:.*big\.c$' out17.info ; then
    fail "17: big.c not removed from aggregated .info after ERROR_SOURCE"
fi
# a.c (present + changed) is still there
grep -qE '^a\.c +changed' out17.rpt || fail "17: a.c should still be 'changed'"

#-----------------------------------------------------------------------
# 18. path-mismatch warning (D7):  a report file absent from the current set
#     whose basename matches a current file absent from the report is likely a
#     path mismatch -> ignorable 'mismatch' warning (behavior unchanged: still
#     a separate remove + add).
#-----------------------------------------------------------------------
mkdir -p src_mm/other src_mm/deep/nested
cp src/a.c src_mm/a.c
cp src/sub/b.c src_mm/other/b.c
cp src/sub/b.c src_mm/deep/nested/b.c
cat > cur18.info <<'EOF'
SF:a.c
DA:1,1
end_of_record
SF:other/b.c
DA:1,1
end_of_record
SF:deep/nested/b.c
DA:1,1
end_of_record
EOF
# do NOT ignore 'mismatch':  it is an ignorable_warning (non-fatal), and its
#   text is only emitted when it is not suppressed.
$COVER $HTML2LCOV_TOOL rpt --source-directory src_mm -o out18 \
    --current-file cur18.info --ignore empty,unused 2>&1 |
    tee html2lcov18.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov --current-file mismatch run failed"
fi
grep -q "Possible path mismatch" html2lcov18.log ||
    fail "18: missing expected path-mismatch warning"
grep -qE "WARNING: \(mismatch\)" html2lcov18.log ||
    fail "18: path mismatch should be a non-fatal warning"
# sub/b.c (report) is removed; other/b.c and deep/nested/b.c are added
grep -qE 'b\.c +removed' out18.rpt || fail "18: sub/b.c not 'removed'"
grep -qE 'other/b\.c +added' out18.rpt || fail "18: other/b.c not 'added'"

#-----------------------------------------------------------------------
# 19. --current-file validation:  missing file is fatal; empty file raises an
#     ignorable ERROR_EMPTY; a non-empty file with no 'SF:' record is fatal.
#-----------------------------------------------------------------------
# 19a. missing file -> fatal die
$COVER $HTML2LCOV_TOOL rpt --source-directory src2 -o err19a \
    --current-file no_such.info --ignore empty,unused 2>&1 | tee err19a.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail "19a: missing --current-file should be fatal"
fi
grep -q "no_such.info' not found" err19a.log ||
    fail "19a: missing 'current-file not found' diagnostic"

# 19b. empty file -> ignorable ERROR_EMPTY (fatal by default, so ignore it).
#      With an empty whitelist every report file is 'removed'.
: > cur19b.info
$COVER $HTML2LCOV_TOOL rpt --source-directory src2 -o err19b \
    --current-file cur19b.info --ignore unused 2>&1 | tee err19b.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail "19b: empty --current-file should raise a (fatal) ERROR_EMPTY"
fi
grep -q "cur19b.info' is empty" err19b.log ||
    fail "19b: missing 'current-file is empty' diagnostic"
# and it is downgraded to a warning under '--ignore empty'.  With an empty
#   whitelist every report file is 'removed', so nothing matches on disk -> the
#   'source' (no matching file) error also fires;  ignore it too.
$COVER $HTML2LCOV_TOOL rpt --source-directory src2 -o out19b \
    --current-file cur19b.info --ignore empty,unused,source 2>&1 | tee out19b.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "19b: '--ignore empty' should downgrade the empty-current-file error"
fi
grep -qE "WARNING: \(empty\) --current-file 'cur19b.info' is empty" out19b.log ||
    fail "19b: empty --current-file should warn under '--ignore empty'"

# 19c. non-empty file with no SF: record -> fatal (not an LCOV file)
printf 'TN:foo\nFNF:0\n' > cur19c.info
$COVER $HTML2LCOV_TOOL rpt --source-directory src2 -o err19c \
    --current-file cur19c.info --ignore empty,unused 2>&1 | tee err19c.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail "19c: --current-file with no SF: should be fatal"
fi
grep -q "contains no SF: records" err19c.log ||
    fail "19c: missing 'no SF: records' diagnostic"

#-----------------------------------------------------------------------
# 20. gap-line handling:  a recovered source page whose line-number anchors
#     are non-contiguous (a line is missing from the HTML) must be back-filled
#     with a blank line at the missing position, so the recovered array stays
#     line-number aligned.  Hand-hack a good report to delete the L2 row of
#     a.c, then diff against a source whose line 2 is blank -> 'unchanged'
#     (the gap fill produced a blank line that matches).
#-----------------------------------------------------------------------
rm -rf rpt_gap src_gap
cp -r rpt rpt_gap
find rpt_gap -name 'a.c.gcov.html' -exec perl -i -ne \
    'print unless /<span id="L2"/' {} +
if grep -q '<span id="L2"' rpt_gap/src/a.c.gcov.html ; then
    fail "test setup: failed to delete L2 row from a.c.gcov.html"
fi
# source whose middle line is blank, matching the back-filled gap
mkdir -p src_gap
printf 'int gg(int x);\n\nint main(){ return fa(1) + gg(1); }\n' > src_gap/a.c
$COVER $HTML2LCOV_TOOL rpt_gap --source-directory src_gap -o out20 \
    --ignore empty,unused 2>&1 | tee html2lcov20.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov failed on a report with a gap (missing) source line"
fi
# the gap-filled recovered a.c (blank line 2) equals src_gap/a.c under 'diff -b'
grep -qE '^a\.c +unchanged' out20.rpt ||
    fail "20: gap-filled a.c should be 'unchanged' vs a blank-line-2 source"

#-----------------------------------------------------------------------
# 21. --current-file whitelist + --exclude:  a whitelisted file that is NOT in
#     the report would normally be 'added', but if it matches an --exclude
#     pattern it must be skipped (not added).  a.c stays 'changed' so the run
#     still has a match.
#-----------------------------------------------------------------------
cat > src2/newmod.c <<'EOF'
int fn(void){ return 9; }
EOF
cat > cur21.info <<EOF
TN:whitelist
SF:$ACPATH
DA:1,1
end_of_record
SF:newmod.c
DA:1,1
end_of_record
EOF
$COVER $HTML2LCOV_TOOL rpt --source-directory src2 -o out21 \
    --current-file cur21.info --exclude '*newmod.c' \
    --ignore empty,unused 2>&1 | tee html2lcov21.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "html2lcov --current-file + --exclude run failed"
fi
# newmod.c is whitelisted + on disk, but excluded -> must NOT be 'added'
if grep -q 'newmod\.c' out21.rpt ; then
    fail "21: excluded whitelisted file newmod.c should not be 'added'"
    cat out21.rpt
fi
# a.c is still matched and diffed
grep -qE '^a\.c +changed' out21.rpt || fail "21: a.c should still be 'changed'"

#-----------------------------------------------------------------------
# 22. source-text extraction with an embedded ' : ' (regression):  a source
#     line that contains a spaced colon -- here a C ternary 'a ? b : c' -- puts
#     a ' : ' INSIDE the source, to the right of the fixed count-column
#     separator that genhtml emits ("<gutter> : <source>").  The extractor must
#     anchor on the count separator (the rightmost ' : ' common to every row),
#     NOT on the last ' : ' of the row;  otherwise it recovers only the ': c'
#     suffix and reports a spurious 'changed' for identical source.  The ternary
#     also creates branch coverpoints, so the branch column is present -- the
#     exact condition that first exposed the bug.
#-----------------------------------------------------------------------
rm -rf src_tern
mkdir -p src_tern
cat > src_tern/tern.c <<'EOF'
int classify(int x);
int classify(int x){ int r = x > 0 ? x : -x; return r; }
int main(void){ return classify(-5) + classify(7); }
EOF
( cd src_tern && ${CC} --coverage -c tern.c && ${CC} --coverage tern.o -o t.out \
    && ./t.out ) > /dev/null 2>&1
$COVER $GENINFO_TOOL src_tern --parallel 0 --branch-coverage -o tern.info \
    --ignore empty,unused 2>&1 > /dev/null
$COVER $GENHTML_TOOL tern.info -o rpt_tern --save --branch-coverage \
    --ignore empty,inconsistent,unused 2>&1 > /dev/null
if [ ! -f rpt_tern/tern.info ] ; then
    fail "22: genhtml --save did not deposit tern.info"
fi
# sanity: the HTML row for the ternary line really does carry a ' : ' inside the
#   source (i.e. the report reproduces the bug's trigger), else the test is moot
if ! find rpt_tern -name 'tern.c.gcov.html' \
        -exec grep -ql ' ? x : -x' {} + ; then
    fail "22: test setup -- ternary ' : ' not present in the HTML source row"
fi
# diff the report's embedded source against the IDENTICAL on-disk source
$COVER $HTML2LCOV_TOOL rpt_tern --source-directory src_tern -o out22 \
    --branch-coverage --ignore empty,unused 2>&1 | tee html2lcov22.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "22: html2lcov run on a report with an in-source ' : ' failed"
fi
# identical source => empty udiff and 'unchanged'.  With the old (rindex) bug
#   the recovered ternary line was truncated to ': -x; return r; }' and the file
#   showed 'changed' with a spurious hunk.
if [ -s out22.udiff ] ; then
    fail "22: identical source produced a non-empty udiff (source mis-extracted)"
    cat out22.udiff
fi
grep -qE '^tern\.c +unchanged' out22.rpt ||
    fail "22: tern.c with an in-source ternary ' : ' should be 'unchanged'"

#-----------------------------------------------------------------------
# 23. differential-report workflow:  edit the source IN PLACE
#     (delete a line), recover the baseline via html2lcov, and feed the udiff +
#     recovered .info to 'genhtml --diff-file/--baseline-file'.  genhtml stores
#     each deleted line's TEXT keyed by the udiff '---' name but looks it up by
#     the '+++' name;  a mixed absolute/relative header pair (as html2lcov used
#     to emit) makes that lookup miss and genhtml dies "missing baseline line".
#     Both headers must name the same path -- the same absolute 'SF:' path in
#     the recovered .info -- so genhtml can reconstruct the deleted line.
#-----------------------------------------------------------------------
rm -rf src_del rpt_del diffrpt_del
mkdir -p src_del
# a multi-line file so the deletion leaves surrounding context (real diff hunk)
cat > src_del/del.c <<'EOF'
int f(int x){
    int y = x + 1;
    int z = y * 2;
    return z;
}
int main(void){ return f(3); }
EOF
( cd src_del && ${CC} --coverage -c del.c && ${CC} --coverage del.o -o d.out \
    && ./d.out ) > /dev/null 2>&1
# capture references the absolute source path; save it into the HTML report
$COVER $GENINFO_TOOL src_del --parallel 0 -o del.info \
    --ignore empty,unused 2>&1 > /dev/null
$COVER $GENHTML_TOOL del.info -o rpt_del --save \
    --ignore empty,inconsistent,unused 2>&1 > /dev/null
if [ ! -f rpt_del/del.info ] ; then
    fail "23: genhtml --save did not deposit del.info"
fi
# now DELETE a line in the source, in place (drop 'int z = y * 2;' and use y)
cat > src_del/del.c <<'EOF'
int f(int x){
    int y = x + 1;
    return y;
}
int main(void){ return f(3); }
EOF
# recapture coverage for the modified source -> the 'current' .info (matches the
#   current 5-line source), (coverage.sh workflow)
( cd src_del && rm -f *.gcda *.gcno *.o d.out \
    && ${CC} --coverage -c del.c && ${CC} --coverage del.o -o d.out \
    && ./d.out ) > /dev/null 2>&1
$COVER $GENINFO_TOOL src_del --parallel 0 -o del_cur.info \
    --ignore empty,unused 2>&1 > /dev/null
# recover the baseline .info + the source udiff for the in-place change
$COVER $HTML2LCOV_TOOL rpt_del --source-directory src_del -o out23 \
    --diff-file out23.udiff --ignore empty,unused 2>&1 | tee html2lcov23.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "23: html2lcov run for the deleted-line workflow failed"
fi
# the deletion must produce a real udiff hunk
grep -q '^@@ ' out23.udiff ||
    fail "23: expected a udiff hunk for the deleted line"
# both diff headers must name the SAME path (no absolute/relative mix)
del_old=`grep -m1 '^--- ' out23.udiff | sed 's/^--- //'`
del_new=`grep -m1 '^+++ ' out23.udiff | sed 's/^+++ //'`
if [ "$del_old" != "$del_new" ] ; then
    fail "23: udiff '---' ($del_old) and '+++' ($del_new) headers must match"
fi
# and that path must be the recovered baseline .info 'SF:' path so genhtml can
#   associate the diff with the baseline coverage
if ! grep -q "^SF:$del_new\$" out23.info ; then
    fail "23: udiff header path '$del_new' must equal the recovered SF: record"
fi
# THE regression check:  genhtml should handle the CURRENT coverage +
#  recovered --baseline-file + the udiff without assert
$COVER $GENHTML_TOOL del_cur.info --baseline-file out23.info \
    --diff-file out23.udiff -o diffrpt_del \
    --ignore empty,inconsistent,unused 2>&1 | tee gendiff23.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "23: genhtml could not consume the html2lcov deleted-line udiff"
fi
if grep -q 'missing baseline line' gendiff23.log ; then
    fail "23: genhtml failed to recover the deleted baseline line"
    cat gendiff23.log
fi

#-----------------------------------------------------------------------
# 24. no-common-root fallback:  recover a report whose source files live under
#     two sibling directories with NO shared leading component ('mr1/one.c' and
#     'mr2/two.c').  common_root() returns undef, so html2lcov keys each file by
#     its full recovered path instead of a report-root-relative one.  We strip
#     the 'title=' attribute (as in scenario 13) so the recovered paths are the
#     report-relative page paths ('mr1/one.c', 'mr2/two.c') -- absolute 'SF:'
#     title paths would always share the leading '/' and never hit the fallback.
#     The report is built under a scratch 'mr_build' dir:  the recovered relative
#     paths ('mr1/one.c', ...) must NOT exist in the test cwd, or resolve_path()
#     would match them there and bypass --source-directory.
#-----------------------------------------------------------------------
rm -rf mr_build src_mr
mkdir -p mr_build/mr1 mr_build/mr2
cat > mr_build/mr1/one.c <<'EOF'
int one(int x){ if (x > 0) return 1; return 0; }
int main(){ return one(1); }
EOF
cat > mr_build/mr2/two.c <<'EOF'
int two(int x){ return x + 2; }
EOF
# a synthetic .info naming the two files by sibling relative paths
cat > mr_build/multiroot.info <<'EOF'
SF:mr1/one.c
DA:1,1
DA:2,1
end_of_record
SF:mr2/two.c
DA:1,1
end_of_record
EOF
( cd mr_build &&
  $COVER $GENHTML_TOOL multiroot.info -o rpt_mr --save \
      --ignore empty,inconsistent,unused 2>&1 ) > genhtml_mr.log 2>&1
if [ ! -f mr_build/rpt_mr/multiroot.info ] ; then
    fail "24: genhtml --save did not deposit multiroot.info"
fi
# strip title= so recovery falls back to report-relative page paths (no common root)
find mr_build/rpt_mr -name 'index.html' -exec perl -i -pe \
    's/(<td class="coverFile"><a href="[^"]+")\s+title="Click to go to file [^"]*"/$1/g' \
    {} +
# current source:  one.c changed ('return 1' -> 'return 99'), two.c identical
mkdir -p src_mr/mr1 src_mr/mr2
cat > src_mr/mr1/one.c <<'EOF'
int one(int x){ if (x > 0) return 99; return 0; }
int main(){ return one(1); }
EOF
cp mr_build/mr2/two.c src_mr/mr2/two.c
$COVER $HTML2LCOV_TOOL mr_build/rpt_mr --source-directory src_mr -o out24 \
    --ignore empty,unused 2>&1 | tee html2lcov24.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "24: html2lcov no-common-root run failed"
fi
# fallback keys files by their full recovered path (no common root stripped),
#   so classification is still correct:  one.c changed, two.c unchanged
grep -qE '^mr1/one\.c +changed'   out24.rpt || fail "24: mr1/one.c not 'changed'"
grep -qE '^mr2/two\.c +unchanged' out24.rpt || fail "24: mr2/two.c not 'unchanged'"
# the changed-file udiff headers name the recovered (root-less) path, matching
grep -q '^--- mr1/one\.c$' out24.udiff || fail "24: udiff '---' header wrong"
grep -q '^+++ mr1/one\.c$' out24.udiff || fail "24: udiff '+++' header wrong"

#-----------------------------------------------------------------------
# 25. parallel scrape + diff:  build a report with enough files that
#     'partition_files' splits them into more than one chunk (the tool leaves a
#     report with fewer than 8 files per chunk in this process:  forking costs
#     more than the ~20ms a file takes).  Everything about the output has to be
#     independent of '--parallel':  the chunks are contiguous runs of the sorted
#     file list, and the parent keys its tables by path and prints them sorted,
#     so the order in which the children finish cannot matter.
#
#     The files vary in length so that the pages the partitioner balances by are
#     not all the same size, and the current tree exercises all four
#     classifications at once (3 changed, 1 removed, 1 added, the rest
#     unchanged).  The report is built under a scratch 'par_build' dir with
#     absolute 'SF:' paths, so the report-relative paths ('f0.c', ...) do not
#     exist in the test cwd and must be resolved through --source-directory
#     (see scenario 24).
#-----------------------------------------------------------------------
rm -rf par_build src_par2
mkdir -p par_build/src_par
i=0
while [ $i -lt 24 ] ; do
    lines=$(( 5 + ($i % 7) * 4 ))
    ( echo "int f$i(int x){"
      j=0
      while [ $j -lt $lines ] ; do
          echo "    x += $j;   /* line $j of f$i */"
          j=$(( $j + 1 ))
      done
      echo "    return x;"
      echo "}" ) > par_build/src_par/f$i.c
    i=$(( $i + 1 ))
done
# a synthetic .info naming every file by absolute path, with a hit count on
#   every line
( for f in par_build/src_par/f*.c ; do
      echo "SF:`pwd`/$f"
      n=`wc -l < $f`
      k=1
      while [ $k -le $n ] ; do
          echo "DA:$k,$(( $k % 3 ))"
          k=$(( $k + 1 ))
      done
      echo end_of_record
  done ) > par_build/par.info
$COVER $GENHTML_TOOL par_build/par.info -o par_build/rpt_par --save \
    --ignore empty,inconsistent,unused > genhtml_par.log 2>&1
if [ ! -f par_build/rpt_par/par.info ] ; then
    fail "25: genhtml --save did not deposit par.info"
    cat genhtml_par.log
fi
# the current source:  three files changed, one removed, one added
mkdir -p src_par2
cp par_build/src_par/*.c src_par2/
for i in 3 11 19 ; do
    perl -i -pe 's/x \+= 0;/x += 100;/' src_par2/f$i.c
done
rm src_par2/f23.c
echo 'int extra(int x){ return x; }' > src_par2/extra.c

H2LPAR="par_build/rpt_par --source-directory src_par2 --ignore empty,unused"
# serial:  no child, and the reference the parallel runs have to reproduce
$COVER $HTML2LCOV_TOOL $H2LPAR -o out25s --parallel 1 2>&1 | tee out25s.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "25: serial html2lcov run failed"
fi
grep -qE '^  3 changed, 1 added, 1 removed, 20 unchanged' out25s.rpt ||
    fail "25: unexpected classification counts in the serial run"
# '--parallel 1' does the work here, so it never announces chunks
grep -q 'Scraping .* chunks' out25s.log &&
    fail "25: '--parallel 1' should not have forked a scrape child"

for p in 2 4 ; do
    $COVER $HTML2LCOV_TOOL $H2LPAR -o out25p$p --parallel $p 2>&1 |
        tee out25p$p.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail "25: html2lcov --parallel $p failed"
    fi
    # it really did split the work:  more than one chunk, so more than one child
    nchunks=`sed -nE 's/^Scraping 24 files in ([0-9]+) chunks.*/\1/p' \
        out25p$p.log | tail -1`
    if [ "x$nchunks" == 'x' ] || [ $nchunks -lt 2 ] ; then
        fail "25: --parallel $p did not split the scrape into chunks"
        cat out25p$p.log
    fi
    for ext in info rpt udiff ; do
        cmp -s out25s.$ext out25p$p.$ext ||
            fail "25: --parallel $p .$ext differs from the serial run"
    done
done

#-----------------------------------------------------------------------
# 26. the failure arms of the scrape loop.  'parallel_parse_min_lines=0' keeps
#     the .info read serial, so the injected failure is spent on a scrape child
#     and not on a read child;  LCOV_FORCE_PARALLEL would do the opposite (see
#     tests/lcov/parallel_fail), so drop it for these runs.
#-----------------------------------------------------------------------
save_force_parallel=$LCOV_FORCE_PARALLEL
unset LCOV_FORCE_PARALLEL
PAR26="$H2LPAR --parallel 4 --rc parallel_parse_min_lines=0"
IGN26="--ignore-errors fork --rc fork_fail_timeout=0"

echo "*** 26: a child killed by the OS"
LCOV_FORCE_CHILD_KILL=1 $COVER $HTML2LCOV_TOOL $PAR26 $IGN26 \
    -o out26ck > out26ck.log 2>&1
if [ 0 != $? ] ; then
    fail "26: run with a killed scrape child failed"
    cat out26ck.log
fi
grep -qE 'scrape chunk [0-9]+: killed by OS' out26ck.log ||
    fail "26: killed scrape child not reported"
for ext in info rpt udiff ; do
    cmp -s out25s.$ext out26ck.$ext ||
        fail "26: .$ext differs after a killed scrape child"
done

echo "*** 26: a child which leaves no serialized data"
LCOV_FORCE_NO_DUMP=1 $COVER $HTML2LCOV_TOOL $PAR26 $IGN26 \
    -o out26nd > out26nd.log 2>&1
if [ 0 != $? ] ; then
    fail "26: run with a scrape child that dumped nothing failed"
    cat out26nd.log
fi
grep -qE 'scrape chunk [0-9]+: serialized data .* not found' out26nd.log ||
    fail "26: scrape child with no data not reported"
# it exited rather than being signalled, so the out-of-memory guess must not
#   appear
grep -q 'killed by OS' out26nd.log &&
    fail "26: an exited scrape child must not be blamed on the OS"
for ext in info rpt udiff ; do
    cmp -s out25s.$ext out26nd.$ext ||
        fail "26: .$ext differs after a scrape child dumped nothing"
done

echo "*** 26: a child which cannot store what it computed"
LCOV_FORCE_STORE_FAIL=1 $COVER $HTML2LCOV_TOOL $PAR26 $IGN26 \
    --ignore-errors parallel -o out26sf > out26sf.log 2>&1
if [ 0 != $? ] ; then
    fail "26: run with a scrape child that could not store failed"
    cat out26sf.log
fi
grep -qE 'Child [0-9]+ serialize failed' out26sf.log ||
    fail "26: scrape child serialize failure not reported"
for ext in info rpt udiff ; do
    cmp -s out25s.$ext out26sf.$ext ||
        fail "26: .$ext differs after a scrape child could not store"
done

echo "*** 26: a child which leaves data the parent cannot use"
# the child reported success, so there is nothing to retry:  this one is fatal,
#   and it is blamed on an exit status rather than on a signal
LCOV_FORCE_BAD_DATA=1 $COVER $HTML2LCOV_TOOL $PAR26 $IGN26 \
    -o out26bd > out26bd.log 2>&1
if [ 0 == $? ] ; then
    fail "26: unusable scraped data should not have been silently accepted"
fi
grep -qE 'unable to deserialize .*dumper_[0-9]+' out26bd.log ||
    fail "26: unusable scraped data not reported"
grep -qE 'returned non-zero exit status 1' out26bd.log ||
    fail "26: a child which exited should not be blamed on a signal"
grep -q 'due to signal' out26bd.log &&
    fail "26: a child which exited must not be reported as signalled"

echo "*** 26: fork() fails"
LCOV_FORCE_FORK_FAIL=1 $COVER $HTML2LCOV_TOOL $PAR26 $IGN26 \
    -o out26ff > out26ff.log 2>&1
if [ 0 != $? ] ; then
    fail "26: run with a failed fork() failed"
    cat out26ff.log
fi
grep -qE 'fork\(\) syscall failed while trying to scrape chunk' out26ff.log ||
    fail "26: failed fork() for a scrape chunk not reported"
for ext in info rpt udiff ; do
    cmp -s out25s.$ext out26ff.$ext ||
        fail "26: .$ext differs after a fork() failure"
done

if [ "x$save_force_parallel" != 'x' ] ; then
    export LCOV_FORCE_PARALLEL=$save_force_parallel
fi

#-----------------------------------------------------------------------
# 27. 'diff' is killed by a signal.  Scenario 15 shadows a 'diff' which exits
#     2;  this one shadows a 'diff' which kills itself.  A signalled child
#     leaves the exit-status field of $? zero, so a status which is only shifted
#     down by 8 says the child succeeded - and the empty output it left behind
#     then says every file compares equal.
#-----------------------------------------------------------------------
mkdir -p fakekill
cat > fakekill/diff <<'EOF'
#!/bin/sh
kill -TERM $$
EOF
chmod +x fakekill/diff
PATH="`pwd`/fakekill:$PATH" $COVER $HTML2LCOV_TOOL rpt --source-directory src2 \
    -o err27 --ignore empty,unused 2>&1 | tee err27.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail "27: html2lcov should fail when 'diff' is killed"
fi
grep -q "'diff' died from signal 15" err27.log ||
    fail "27: missing expected \"'diff' died from signal\" diagnostic"
# and it must not be reported as an exit status, least of all a successful one
grep -q "'diff' failed (status" err27.log &&
    fail "27: a signalled 'diff' must not be blamed on its exit status"

#-----------------------------------------------------------------------
# 28. a file which is found under a name other than its report-relative path.
#     '--substitute' rewrites 'mr1/one.c' to 'alt1/one.c' before the current
#     version is looked for, so the file is compared against the report as
#     'src_sub/alt1/one.c' while the report still knows it as 'mr1/one.c'.  The
#     walk which looks for files the report does not mention sees 'alt1/one.c'
#     and has to recognise it as a file which was already compared - by what it
#     is on disk, the only name the two agree on.  Reuses scenario 24's report,
#     whose recovered paths have a leading directory to substitute.
#-----------------------------------------------------------------------
mkdir -p src_sub/alt1 src_sub/alt2
cp src_mr/mr1/one.c src_sub/alt1/one.c
cp src_mr/mr2/two.c src_sub/alt2/two.c
$COVER $HTML2LCOV_TOOL mr_build/rpt_mr --source-directory src_sub \
    --substitute 's#^mr1/#alt1/#' --substitute 's#^mr2/#alt2/#' \
    -o out28 --ignore empty,unused 2>&1 | tee html2lcov28.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "28: html2lcov run with substituted source paths failed"
fi
# one.c differs from the report (scenario 24 changed it), two.c does not, and
#   nothing was added:  both files are accounted for exactly once
grep -qE '^  1 changed, 0 added, 0 removed, 1 unchanged' out28.rpt ||
    fail "28: a file already compared was offered again as 'added'"
grep -qE '^alt[12]/' out28.rpt &&
    fail "28: a substituted path appears as a file of its own"

#-----------------------------------------------------------------------
# 29. a report whose files share only the filesystem root.  Both recovered
#     paths are absolute, in different top-level directories, so the only
#     component they have in common is the empty one 'splitdir' puts in front
#     of an absolute path.  That is not a root to key files by:  taken as one,
#     it is the empty string, which every later path operation reads as 'the
#     current directory' - and nothing in the report matches anything.
#-----------------------------------------------------------------------
if ! mkdir -p $OTHER_ROOT/two_root 2>/dev/null ; then
    echo "29: cannot create $OTHER_ROOT - skipping"
elif [ "`echo $PWD | cut -d/ -f2`" == "`echo $OTHER_ROOT | cut -d/ -f2`" ] ;
then
    # the tests are running under the same top-level directory, so the two
    #   paths would have a genuine common root
    echo "29: $OTHER_ROOT is not a second root here - skipping"
else
    mkdir -p dup_build/one_root
    cat > dup_build/one_root/one.c <<'EOF'
int one(int x){ if (x > 0) return 1; return 0; }
int main(){ return one(1); }
EOF
    cat > $OTHER_ROOT/two_root/two.c <<'EOF'
int two(int x){ return x + 2; }
EOF
    ( echo "SF:`pwd`/dup_build/one_root/one.c"
      echo "DA:1,1"
      echo "DA:2,1"
      echo "end_of_record"
      echo "SF:$OTHER_ROOT/two_root/two.c"
      echo "DA:1,1"
      echo "end_of_record" ) > dup_build/dup.info
    $COVER $GENHTML_TOOL dup_build/dup.info -o dup_build/rpt_dup --save \
        --ignore empty,inconsistent,unused > genhtml_dup.log 2>&1
    if [ ! -f dup_build/rpt_dup/dup.info ] ; then
        fail "29: genhtml --save did not deposit dup.info"
        cat genhtml_dup.log
    fi
    # the current source is the same tree, with one.c changed in place;  with no
    #   root to key by, each file is keyed by its whole recovered path, which is
    #   absolute and therefore resolves to itself
    perl -i -pe 's/return 1;/return 42;/' dup_build/one_root/one.c
    $COVER $HTML2LCOV_TOOL dup_build/rpt_dup -o out29 --ignore empty,unused \
        2>&1 | tee html2lcov29.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail "29: html2lcov run over two filesystem roots failed"
    fi
    grep -qE '^  1 changed, 0 added, 0 removed, 1 unchanged' out29.rpt ||
        fail "29: unexpected classification counts over two roots"
    # the report's first column is the key the file was classified under - here
    #   its whole path, which is longer than the column and so runs into the
    #   next one;  match on the fields, not on the layout
    st=`awk -v p="$PWD/dup_build/one_root/one.c" '$1 == p {print $2}' out29.rpt`
    if [ "changed" != "$st" ] ; then
        cat out29.rpt
        fail "29: one.c is '$st', not keyed by its full path and 'changed'"
    fi
    st=`awk -v p="$OTHER_ROOT/two_root/two.c" '$1 == p {print $2}' out29.rpt`
    if [ "unchanged" != "$st" ] ; then
        cat out29.rpt
        fail "29: two.c is '$st', not keyed by its full path and 'unchanged'"
    fi
fi
rm -rf $OTHER_ROOT

#-----------------------------------------------------------------------
# 30. the output base is '-o' with the extension of its FILE NAME removed.  A
#     dot in a directory component is not an extension of anything.
#-----------------------------------------------------------------------
mkdir -p dot.d
$COVER $HTML2LCOV_TOOL rpt --source-directory src2 -o dot.d/report \
    --ignore empty,unused 2>&1 | tee html2lcov30.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail "30: html2lcov run with a dotted output directory failed"
fi
for ext in info rpt udiff ; do
    if [ ! -f dot.d/report.$ext ] ; then
        ls dot.d
        fail "30: dot.d/report.$ext was not written"
    fi
done

#-----------------------------------------------------------------------
# help + bad option
#-----------------------------------------------------------------------
$COVER $HTML2LCOV_TOOL --help > /dev/null 2>&1 || fail "--help failed"
$COVER $HTML2LCOV_TOOL --unsupported-option > /dev/null 2>&1 &&
    fail "did not reject an unsupported option"

if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    # the third argument is 1 because this test runs spreadsheet.py under
    #   $PYCOVER - see section 8 - so there is python coverage data to report
    generate_coverage 'html2lcov' $LOCAL_COVERAGE 1
fi

exit $STATUS
