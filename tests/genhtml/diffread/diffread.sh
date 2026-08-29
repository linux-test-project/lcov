#!/bin/bash
set +x

# The udiff reader and the baseline text it recreates out of the patch.  Every
#   differential category in the report is derived from those two things, and
#   each of the failures below is silent or nearly so:  the report is produced,
#   looks entirely ordinary, and says something which is not true of the code.
#
# The cases:
#   1. hunk headers whose ranges have no count.  A range whose length is 1 is
#      written as the start line alone ('@@ -4 +4 @@'), which is what 'diff -U0'
#      and 'git diff -U0' produce for a one-line change.  The reader used to
#      require both counts, so the header matched no arm at all:  the hunk's
#      content lines were then discarded too (they are only accepted while a
#      count is outstanding), and the file came out with a single 'unchanged'
#      chunk.  The whole patch was silently dropped
#   2. a '@@' line the reader does not understand.  Same mechanism, but there is
#      nothing to fix in the reader:  a malformed patch is a format error
#   3. a file which the diff renames.  The chunks are filed under the '+++'
#      name and the deleted text under the '---' name, so recreating the
#      baseline of a renamed file looked for its deleted lines under the wrong
#      name and aborted the run - or, when the baseline coverage data used the
#      old name, was not recognized as a diff entry at all and read whatever
#      file happened to be on disk under that name
#   4. a path which '--elide-path-mismatch' reconciles.  That decision was made
#      after the baseline had already been read, so the baseline source was the
#      *current* text of the file:  every filter and every exclusion marker saw
#      the wrong source, and every baseline coverage point past the current end
#      of file was reported as out of range
#
# The observable in 3 and 4 is a baseline which is longer than the current file:
#   a coverage point on a line which exists only in the baseline is in range
#   exactly when the recreated baseline is the real one.
#
# Every run asks for a filter, which is what makes the baseline source be read
#   at all:  without one, nothing needs the text of either version and the
#   recreated baseline is never built.

source ../../common.tst

GENHTML_OPTS="--branch-coverage --function-coverage --filter line $PARALLEL $PROFILE"

rm -rf *.info *.log *.json *.udiff proj other html_* \
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

# the categorized totals the report printed, independent of the order the files
#   were processed in and of how long each of them took
summary()
{
    grep -E '^ +(line|function|branch):' $1 | sort
}

# ----------------------------------------------------------------------
# the inputs for cases 1 and 2:  three files, one changed in place, one which
#   grew a line, and one which the diff creates.  The patch is in 'diff -U0'
#   form, so one of its ranges has no count, one has a count of 1 written out,
#   and the created file has the count 0 - which is legal, and is why the
#   default cannot be applied to a count which is merely false
# ----------------------------------------------------------------------
mkdir -p proj/src other

cat >proj/src/foo.c <<'EOF'
int foo(int a)
{
    if (a > 0)
        return a + 1;
    return -a;
}
EOF

cat >proj/src/bar.c <<'EOF'
int bar(int b)
{
    if (b > 0) {
        b += 1;
        return b;
    }
    return 0;
}
EOF

cat >proj/src/new.c <<'EOF'
int baz(void)
{
    return 0;
}
EOF

cat >current.info <<'EOF'
TN:diffread
SF:proj/src/foo.c
FN:1,6,foo
FNDA:3,foo
FNF:1
FNH:1
DA:1,3
DA:3,3
DA:4,3
DA:5,0
LF:4
LH:3
end_of_record
SF:proj/src/bar.c
FN:1,8,bar
FNDA:5,bar
FNF:1
FNH:1
DA:1,5
DA:3,5
DA:4,5
DA:5,5
DA:7,0
LF:5
LH:4
end_of_record
SF:proj/src/new.c
FN:1,4,baz
FNDA:2,baz
FNF:1
FNH:1
DA:1,2
DA:3,2
LF:2
LH:2
end_of_record
EOF

cat >baseline.info <<'EOF'
TN:diffread
SF:proj/src/foo.c
FN:1,6,foo
FNDA:2,foo
FNF:1
FNH:1
DA:1,2
DA:3,2
DA:4,2
DA:5,0
LF:4
LH:3
end_of_record
SF:proj/src/bar.c
FN:1,7,bar
FNDA:5,bar
FNF:1
FNH:1
DA:1,5
DA:3,5
DA:4,5
DA:6,0
LF:4
LH:3
end_of_record
EOF

# 'diff -U0 baseline current':  no context, so a range whose length is 1 is
#   written as the start line alone
cat >nocount.udiff <<'EOF'
--- proj/src/foo.c
+++ proj/src/foo.c
@@ -4 +4 @@
-        return a;
+        return a + 1;
--- proj/src/bar.c
+++ proj/src/bar.c
@@ -4 +4,2 @@
-        return b;
+        b += 1;
+        return b;
--- /dev/null
+++ proj/src/new.c
@@ -0,0 +1,4 @@
+int baz(void)
+{
+    return 0;
+}
EOF

# the same patch with every count written out:  this is the form the reader
#   always accepted, and the report it produces is what case 1 has to match
cat >count.udiff <<'EOF'
--- proj/src/foo.c
+++ proj/src/foo.c
@@ -4,1 +4,1 @@
-        return a;
+        return a + 1;
--- proj/src/bar.c
+++ proj/src/bar.c
@@ -4,1 +4,2 @@
-        return b;
+        b += 1;
+        return b;
--- /dev/null
+++ proj/src/new.c
@@ -0,0 +1,4 @@
+int baz(void)
+{
+    return 0;
+}
EOF

cat >bogus.udiff <<'EOF'
--- proj/src/foo.c
+++ proj/src/foo.c
@@ -4 +four @@
-        return a;
+        return a + 1;
EOF

# ----------------------------------------------------------------------
echo "*** 1. hunk headers whose ranges have no count"
# ----------------------------------------------------------------------
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_nocount current.info \
    --baseline-file baseline.info --diff-file nocount.udiff 2>&1 |
    tee nocount.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail nocount "genhtml failed reading a 'diff -U0' patch"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' nocount.log ; then
    fail nocount "reading a 'diff -U0' patch complained"
fi
# the patch reached the coverage data:  the changed line of 'foo.c', the two
#   lines 'bar.c' grew and both lines of the created file are new code, the
#   deleted lines were covered in the baseline, and the lines the patch says
#   nothing about are unchanged.  Dropping the patch produces UBC/CBC only -
#   a report which says the code did not change, which is a perfectly ordinary
#   thing for a report to say
if ! grep -E -q '^ +line: UBC:2 GNC:5 CBC:4 DCB:2$' nocount.log ; then
    fail nocount "the patch was not applied to the coverage data"
fi
if [ ! -f html_nocount/index.html ] ; then
    fail nocount "no report was written"
fi
# ..and it is the same report the fully written out form produces
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_count current.info \
    --baseline-file baseline.info --diff-file count.udiff 2>&1 | tee count.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail count "genhtml failed reading the same patch with counts"
fi
if ! diff <(summary nocount.log) <(summary count.log) ; then
    fail nocount "an omitted range count changed the report"
fi

# ----------------------------------------------------------------------
echo "*** 2. a hunk header the reader does not understand"
# ----------------------------------------------------------------------
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_bogus current.info \
    --baseline-file baseline.info --diff-file bogus.udiff 2>&1 | tee bogus.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail bogus "a malformed hunk header did not fail the run"
fi
for pattern in 'ERROR: (format)' 'bogus.udiff:3:' \
    "unexpected 'diff' hunk header" '@@ -4 +four @@' ; do
    if ! grep -F -q -e "$pattern" bogus.log ; then
        fail bogus "message does not mention: $pattern"
    fi
done
# with the error ignored, the hunk is skipped:  that is all the reader can do
#   with a header it cannot read, and it is what used to happen silently
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_ignore current.info \
    --baseline-file baseline.info --diff-file bogus.udiff \
    --ignore-errors format 2>&1 | tee ignore.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail bogus_ignore "run with '--ignore-errors format' failed"
fi
if ! grep -F -q -e 'WARNING: (format)' ignore.log ; then
    fail bogus_ignore "the malformed hunk header was not reported"
fi
if ! grep -E -q '^ +format: 1$' ignore.log ; then
    fail bogus_ignore "the message summary does not count the ignored message"
fi

# ----------------------------------------------------------------------
# the inputs for cases 3 and 4:  a baseline two lines longer than the current
#   file, so a baseline coverage point on its line 6 is past the end of the
#   current file.  If the 'baseline' source is not the recreated one, that
#   coverage point is out of range
# ----------------------------------------------------------------------
cat >proj/src/renamed.c <<'EOF'
int r(int x)
{
    if (x > 0)
        return x + 1;
}
EOF

cp proj/src/renamed.c other/g.c

renamed_hunk()
{
    # $1 = '---' name, $2 = '+++' name
    cat <<EOF
--- $1
+++ $2
@@ -1,7 +1,5 @@
 int r(int x)
 {
-    int y = x;
-    if (y > 0)
-        return y;
-    return 0;
+    if (x > 0)
+        return x + 1;
 }
EOF
}

renamed_hunk proj/src/old_r.c proj/src/renamed.c > rename.udiff
renamed_hunk proj/g.c proj/g.c > elide.udiff
renamed_hunk other/g.c other/g.c > noelide.udiff

# the current data:  five lines, the last two of them new
cov_data()
{
    # $1 = source file name, $2 = 'current' or 'baseline'
    if [ "$2" == current ] ; then
        cat <<EOF
TN:diffread
SF:$1
FN:1,5,r
FNDA:4,r
FNF:1
FNH:1
DA:1,4
DA:3,4
DA:4,4
LF:3
LH:3
end_of_record
EOF
    else
        cat <<EOF
TN:diffread
SF:$1
FN:1,7,r
FNDA:2,r
FNF:1
FNH:1
DA:1,2
DA:3,2
DA:4,2
DA:5,2
DA:6,0
LF:5
LH:4
end_of_record
EOF
    fi
}

cov_data proj/src/renamed.c current > rename_curr.info
cov_data proj/src/renamed.c baseline > rename_new.info
cov_data proj/src/old_r.c baseline > rename_old.info
cov_data other/g.c current > elide_curr.info
cov_data other/g.c baseline > elide_base.info

# ----------------------------------------------------------------------
echo "*** 3a. a renamed file whose baseline data uses the current name"
# ----------------------------------------------------------------------
# the deleted text is filed under the diff's '---' name, so looking for it
#   under the name the chunks are filed under found nothing at all and the run
#   died in the reader.
# The recreated baseline is two lines longer than the current file, and the
#   baseline coverage data has a coverage point on the last of those lines, so
#   a reconstruction which drops the deleted text cannot be quiet either:  that
#   coverage point is then out of range
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_rename_new rename_curr.info \
    --baseline-file rename_new.info --diff-file rename.udiff 2>&1 |
    tee rename_new.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail rename_new "genhtml failed on a renamed file"
fi
if ! grep -F -q -e 'no messages were reported' rename_new.log ; then
    fail rename_new "reading the baseline of a renamed file complained"
fi
if [ ! -f html_rename_new/index.html ] ; then
    fail rename_new "no report was written"
fi

# ----------------------------------------------------------------------
echo "*** 3b. a renamed file whose baseline data uses the old name"
# ----------------------------------------------------------------------
# this is the form 'genhtml' documents - the baseline coverage data was
#   captured before the rename, so it knows the file by its old name - and the
#   old name is not a file:  it does not exist any more.  The reader did not
#   recognize it as a diff entry, so it did not recreate anything and tried to
#   read the file instead
if [ -e proj/src/old_r.c ] ; then
    fail rename_old "the old name is supposed to be gone"
fi
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_rename_old rename_curr.info \
    --baseline-file rename_old.info --diff-file rename.udiff 2>&1 |
    tee rename_old.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail rename_old "genhtml failed on a baseline which uses the old name"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' rename_old.log ; then
    fail rename_old "reading the baseline under its old name complained"
fi
if grep -F -q -e 'unable to open' rename_old.log ; then
    fail rename_old "tried to read the file the rename removed"
fi
# this is the spelling for which the baseline coverage data is found as well,
#   so the whole differential report can be checked:  the two lines the patch
#   added are new code, the line it left alone was covered before and is
#   covered now, and the four lines it removed were baseline code
if ! grep -E -q '^ +line: GNC:2 CBC:1 DUB:1 DCB:3$' rename_old.log ; then
    fail rename_old "the recreated baseline is not the baseline"
fi

# ----------------------------------------------------------------------
echo "*** 4. a path reconciled by '--elide-path-mismatch'"
# ----------------------------------------------------------------------
# the reference:  the same data with a diff which names the file the way the
#   coverage data does, so nothing has to be reconciled
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_noelide elide_curr.info \
    --baseline-file elide_base.info --diff-file noelide.udiff 2>&1 |
    tee noelide.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail noelide "genhtml failed on the reference run"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' noelide.log ; then
    fail noelide "the reference run complained"
fi
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_elide elide_curr.info \
    --baseline-file elide_base.info --diff-file elide.udiff \
    --elide-path-mismatch 2>&1 | tee elide.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail elide "genhtml failed with '--elide-path-mismatch'"
fi
# the reconciliation is the one the option is for:  reported once, and not
#   fatal - which is the whole point of the option
if ! grep -F -q -e 'Possible pathname mismatch? (elided)' elide.log ; then
    fail elide "the path mismatch was not elided"
fi
COUNT=`grep -c 'WARNING: (mismatch)' elide.log`
if [ 1 != "$COUNT" ] ; then
    fail elide "expected 1 mismatch warning, saw $COUNT"
fi
# ..and it reached the baseline source:  a coverage point on a line which
#   exists only in the baseline is in range exactly when the baseline text is
#   the recreated one and not the current text of the file
if grep -F -q -e '(range)' elide.log ; then
    fail elide "the baseline was filtered against the wrong source"
fi
if ! diff <(summary noelide.log) <(summary elide.log) ; then
    fail elide "an elided path produced a different report"
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'diffread' $LOCAL_COVERAGE 0
fi

exit $STATUS
