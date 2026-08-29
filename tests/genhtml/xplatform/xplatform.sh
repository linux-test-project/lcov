#!/bin/bash
set +x

# The same question as 'tests/lcov/xplatform', asked of the other kind of input
#   whose names we read:  a udiff.  '--diff-file' entries name source files in
#   whatever platform's terms the diff was produced in, and those names are
#   matched against the names in the coverage data - so a udiff written on
#   Windows and read here matches nothing.
#
# That failure is silent, which is why it is worth a test of its own.  A '.info'
#   file whose names are kept as they were read at least produces a report which
#   looks wrong:  its layout is right - the names are decomposed as though they
#   were spelled our way - but no source is found for any of them.  An unmatched
#   diff entry produces a report which looks *right*:  every line of every file
#   is categorized as though the code had not changed at all, which is a
#   perfectly ordinary thing for a report to say.  Nothing else notices either -
#   the path-consistency check compares the last element of each name, and a
#   backslash is not a separator here, so the whole Windows name looks like one
#   element and is simply not similar to anything.
#
# 'lcovutil::check_path_separator' is called on all four kinds of name-bearing
#   record - 'Git Root:', '=== unchanged', '---' and '+++' - before
#   'strip_directories' and before '--substitute'/'resolve_path', so everything
#   downstream, including the comparison against the coverage data, works in
#   host-style paths.  The messages it prints for a udiff are not the '.info'
#   ones:  what a name in the other platform's terms costs is different here, so
#   what to do about it is described differently.
#
# The cases:
#   1. the reference:  a udiff written here.  One file changed, one unchanged -
#      so the report has GNC/DCB lines, which is the signal that the diff was
#      matched to the coverage data at all
#   2. the same diff written on Windows, read with 'cross_platform_read=0':
#      ERROR_USAGE naming the file, the line and the two separators, with the
#      udiff-specific explanation - once for the input, although four of its
#      records carry a name - and no report
#   3. '--ignore usage' as well:  a warning instead of the error, the names
#      kept, and every line categorized as unchanged
#   4. the default translation plus the '--substitute' which drops the drive
#      letter:  the Windows diff produces the reference report exactly
#   5. the translation on its own:  the names are translated but still name a
#      drive, so they do not match the coverage data - and being host-style
#      paths, they have a last element for the path-consistency check to
#      compare, so it says so
#   6. a diff entry which uses both separators:  an error here whichever way
#      'cross_platform_read' is set, as for a '.info' file
#   7. a udiff already in this platform's terms is untouched either way
#   8. the other direction:  a POSIX udiff read on a host whose separator is
#      '\'.  That separator is the escape character of a regular expression, so
#      it is also a test that the report generator quotes it everywhere it
#      builds a pattern out of it.  The setting has nothing to say there:  a
#      host which takes both separators normalizes the names it reads whatever
#      the setting says, which is the last thing this checks

source ../../common.tst

GENHTML_OPTS="--function-coverage $PARALLEL $PROFILE"

rm -rf *.info *.log *.json *.udiff proj html_* \
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

# what the report said, independent of the order the files were processed in and
#   of how long each of them took.  The lines before this point name the
#   directory we are running in, which is not the same from run to run, and
#   'Devel::Cover' has something to say only in the run which invalidates its
#   database - i.e. only under '--coverage', and only the first time
summary()
{
    sed -n -e '/^Generating output/,/^Message summary/p' $1 |
        grep -v '^Devel::Cover' | sed -e 's/ ([0-9.]*s)$//' | sort
}

# ----------------------------------------------------------------------
# the inputs:  a two-file source tree, a baseline and a current trace which
#   differ in 'foo.c', and a udiff which says so.  'bar.c' is named by the diff
#   as unchanged, so both kinds of entry are exercised.
# The Windows diff names the same files with a 'C:' drive prefix and
#   backslashes, so dropping that prefix from a translated read has to produce
#   the reference report exactly (case 4).
# ----------------------------------------------------------------------
mkdir -p proj/src/sub

cat >proj/src/foo.c <<'EOF'
int foo(int a)
{
    if (a > 0)
        return a + 1;
    return -a;
}
EOF

cat >proj/src/sub/bar.c <<'EOF'
int bar(int b)
{
    if (b > 0)
        return b;
    return 0;
}
EOF

cat >baseline.info <<'EOF'
TN:xplat
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
SF:proj/src/sub/bar.c
FN:1,6,bar
FNDA:5,bar
FNF:1
FNH:1
DA:1,5
DA:3,5
DA:4,5
DA:5,0
LF:4
LH:3
end_of_record
EOF

cat >current.info <<'EOF'
TN:xplat
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
SF:proj/src/sub/bar.c
FN:1,6,bar
FNDA:5,bar
FNF:1
FNH:1
DA:1,5
DA:3,5
DA:4,5
DA:5,0
LF:4
LH:3
end_of_record
EOF

cat >posix.udiff <<'EOF'
Git Root: proj
=== proj/src/sub/bar.c
--- proj/src/foo.c
+++ proj/src/foo.c
@@ -1,6 +1,6 @@
 int foo(int a)
 {
     if (a > 0)
-        return a;
+        return a + 1;
     return -a;
 }
EOF

cat >win.udiff <<'EOF'
Git Root: C:\proj
=== C:\proj\src\sub\bar.c
--- C:\proj\src\foo.c
+++ C:\proj\src\foo.c
@@ -1,6 +1,6 @@
 int foo(int a)
 {
     if (a > 0)
-        return a;
+        return a + 1;
     return -a;
 }
EOF

# the 'Git Root:' record is left in this platform's terms, so the entry which
#   uses both separators is the one the message has to point at
cat >mixed.udiff <<'EOF'
Git Root: proj
=== C:\proj/src\sub\bar.c
--- C:\proj/src\foo.c
+++ C:\proj/src\foo.c
@@ -1,6 +1,6 @@
 int foo(int a)
 {
     if (a > 0)
-        return a;
+        return a + 1;
     return -a;
 }
EOF

# ----------------------------------------------------------------------
echo "*** 1. the reference: a udiff written on this platform"
# ----------------------------------------------------------------------
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_posix current.info \
    --baseline-file baseline.info --diff-file posix.udiff 2>&1 | tee posix.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail posix "genhtml failed reading a POSIX udiff"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' posix.log ; then
    fail posix "reading a POSIX udiff complained"
fi
# the diff reached the coverage data:  the changed line of 'foo.c' is 'GNC'
#   (new code, covered) and its function is too, and the branch which is not
#   taken there is 'DCB' - none of which can be said without the diff
if ! grep -F -q -e 'line: UBC:2 GNC:1 CBC:5 DCB:1' posix.log ; then
    fail posix "the diff was not applied to the coverage data"
fi
if [ ! -f html_posix/index.html ] ; then
    fail posix "no report was written"
fi

# ----------------------------------------------------------------------
echo "*** 2. cross_platform_read=0: the Windows separator is an error"
# ----------------------------------------------------------------------
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_disabled current.info \
    --baseline-file baseline.info --diff-file win.udiff \
    --rc cross_platform_read=0 2>&1 | tee disabled.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail disabled "expected genhtml to fail reading a Windows udiff"
fi
if [ -f html_disabled/index.html ] ; then
    fail disabled "wrote a report anyway"
fi
# four records in that file carry a name;  the input is told about once
COUNT=`grep -c 'ERROR: (usage)' disabled.log`
if [ 1 != "$COUNT" ] ; then
    fail disabled "expected 1 usage error, saw $COUNT"
fi
# where, what, and how to fix it.  The explanation is not the '.info' one:
#   a diff entry is matched against the coverage data rather than used to reach
#   the file system, so what such a name costs is different
for pattern in '"win.udiff":1:' "'diff' file entry" \
    "uses the Windows directory separator" \
    "this run works in POSIX paths, whose separator is '/'" \
    'No name from this file will match a source file name in the coverage' \
    'as though the code had not changed at all' \
    'the path-mismatch check compares the' \
    "'cross_platform_read' is disabled" \
    '--rc cross_platform_read=1' \
    "translate the names read from the" \
    "'C:\\proj' -> 'C:/proj'" \
    '--ignore-errors usage' ; do
    if ! grep -F -q -e "$pattern" disabled.log ; then
        fail disabled "message does not mention: $pattern"
    fi
done
# ..and not the '.info' explanation, which is about reaching the file system
if grep -F -q -e 'the source file cannot be' disabled.log ; then
    fail disabled "a udiff was explained as though it were a '.info' file"
fi

# ----------------------------------------------------------------------
echo "*** 3. --ignore usage: the names are kept, and match nothing"
# ----------------------------------------------------------------------
# the names are used exactly as they were read:  the diff is read without
#   further complaint, none of its entries is found in the coverage data, and
#   the whole report says 'unchanged'.  Nothing else notices
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_keep current.info \
    --baseline-file baseline.info --diff-file win.udiff \
    --rc cross_platform_read=0 --ignore usage 2>&1 | tee keep.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail keep "genhtml failed with the error ignored"
fi
COUNT=`grep -c 'WARNING: (usage)' keep.log`
if [ 1 != "$COUNT" ] ; then
    fail keep "expected 1 usage warning, saw $COUNT"
fi
if ! grep -F -q -e 'line: UBC:2 CBC:6' keep.log ; then
    fail keep "expected every line to be categorized as unchanged"
fi
if grep -F -q -e 'GNC' keep.log ; then
    fail keep "an unmatched diff entry produced 'new code' lines"
fi

# ----------------------------------------------------------------------
echo "*** 4. translated, the Windows diff is the reference diff"
# ----------------------------------------------------------------------
# the drive letter is an ordinary leading path element after the translation, so
#   '--substitute' is what removes it - and the pattern is applied to the names
#   in the coverage data as well, so both sides of the comparison are rewritten
#   the same way
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_win current.info \
    --baseline-file baseline.info --diff-file win.udiff \
    --substitute 's#^C:/##' 2>&1 | tee win.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail win "genhtml failed reading a Windows udiff"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' win.log ; then
    fail win "translating the diff names still complained about them"
fi
if ! diff <(summary posix.log) <(summary win.log) ; then
    fail win "the Windows diff did not produce the reference report"
fi

# ----------------------------------------------------------------------
echo "*** 5. the translation alone: the mismatch is visible"
# ----------------------------------------------------------------------
# without the '--substitute', the translated names still name a drive, so they
#   do not match the coverage data.  That is the user's mistake rather than
#   ours - but it is one which can be described:  the check which compares the
#   last element of each name needs the name to have elements, which it does not
#   when its separator is not a separator here.  Case 3 is the silent run
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_nosub current.info \
    --baseline-file baseline.info --diff-file win.udiff 2>&1 | tee nosub.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail nosub "expected the unmatched drive letter to be reported"
fi
for pattern in 'WARNING: (mismatch)' \
    "has same basename as 'diff' entry 'C:/proj/src/foo.c'" \
    'ERROR: (path)' ; do
    if ! grep -F -q -e "$pattern" nosub.log ; then
        fail nosub "the mismatch was not reported: $pattern"
    fi
done
if grep -F -q -e 'ERROR: (usage)' nosub.log ; then
    fail nosub "the separator was reported although it was translated"
fi

# ----------------------------------------------------------------------
echo "*** 6. an entry which uses both separators is an error here"
# ----------------------------------------------------------------------
# a backslash is a legal character in a POSIX file name, so there is no way to
#   tell which of the two separators divides this name's directories - and
#   translating them cannot resolve that either, so it is an error whichever way
#   'cross_platform_read' is set
for value in 0 1 ; do
    label="mixed_$value"
    $COVER $GENHTML_TOOL $GENHTML_OPTS -o html_$label current.info \
        --baseline-file baseline.info --diff-file mixed.udiff \
        --rc cross_platform_read=$value 2>&1 | tee $label.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        fail mixed "expected a mixed name to be an error ('$value')"
    fi
    if [ -f html_$label/index.html ] ; then
        fail mixed "wrote a report anyway ('$value')"
    fi
    COUNT=`grep -c 'ERROR: (usage)' $label.log`
    if [ 1 != "$COUNT" ] ; then
        fail mixed "expected 1 usage error, saw $COUNT ('$value')"
    fi
    # the 'Git Root:' record of this file is a POSIX name, so the entry the
    #   message points at is the first one which is not
    for pattern in '"mixed.udiff":2:' "'diff' file entry" \
        "uses both the POSIX directory separator '/'" \
        "and the Windows one '\\'" \
        'Translating the separators cannot help' \
        "'--substitute'" ; do
        if ! grep -F -q -e "$pattern" $label.log ; then
            fail mixed "message does not mention: $pattern ('$value')"
        fi
    done
done

# ----------------------------------------------------------------------
echo "*** 7. the setting does nothing to a udiff which is already ours"
# ----------------------------------------------------------------------
# there is no foreign separator in these names, so there is nothing to translate
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_noop current.info \
    --baseline-file baseline.info --diff-file posix.udiff \
    --rc cross_platform_read=0 2>&1 | tee noop.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail noop "genhtml failed with 'cross_platform_read=0'"
fi
if ! diff <(summary posix.log) <(summary noop.log) ; then
    fail noop "the setting changed a udiff which was already ours"
fi

# ----------------------------------------------------------------------
echo "*** 8. the other host: a separator which is a regex escape character"
# ----------------------------------------------------------------------
# '--rc path_style=windows' forces the separator a genhtml run on a real Windows
#   machine uses, which is the only way to reach that code from here.  '\' is
#   the escape character of a regular expression, so every pattern the report
#   generator builds out of the separator has to quote it:  the page link, the
#   '--prefix' munging, the 'split' which builds the directory hierarchy, and
#   the '../..' counting in 'get_relative_base_path'.  Unquoted, the run dies
#   before writing anything - 'Trailing \ in regex m/^\/' - so this direction
#   cannot be driven end to end without that quoting.
# Such a host takes '/' as a separator as well, so the POSIX names of this udiff
#   - and of the traces - are not an error there;  they are normalized to '\'
#   all the same, without being asked, because we split paths on one character
#   and the modules we build them with do not agree about the other.  That is
#   what makes this run reach the code below:  a name left as it was read has no
#   elements this host can see, so '--prefix' would match nothing and the
#   hierarchy would be built from the root of the file system.
# The names are host-style now, so they name nothing which exists here - this is
#   still Linux, and a forced path style does not change the file system.
#   '--ignore source --synthesize-missing' is what lets the run finish;  it is
#   not what is being tested
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_wshost current.info \
    --baseline-file baseline.info --diff-file posix.udiff \
    --rc path_style=windows \
    --hierarchical --prefix `pwd` \
    --ignore source --synthesize-missing 2>&1 | tee wshost.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail wshost "genhtml failed with '\' as the directory separator"
fi
for pattern in 'Trailing \ in regex' 'Unmatched [' ; do
    if grep -F -q -e "$pattern" wshost.log ; then
        fail wshost "an unquoted separator reached a regular expression: $pattern"
    fi
done
if [ ! -f html_wshost/index.html ] ; then
    fail wshost "no report was written"
fi
# ..and the run is not merely quiet:  the diff was still matched to the coverage
#   data, and the hierarchy was built by splitting names on the new separator
if ! grep -F -q -e 'line: UBC:2 GNC:1 CBC:5 DCB:1' wshost.log ; then
    fail wshost "the diff was not applied to the coverage data"
fi
if ! grep -q -e 'Processing directory: .*\\' wshost.log ; then
    fail wshost "the directory hierarchy was not split on the separator"
fi
# ..and 'cross_platform_read' has nothing to say about any of it:  turning it
#   off does not stop the normalization, because a host which takes both
#   separators has to normalize.  It is not a no-op on a POSIX host:  there it
#   is the difference between case 2 and case 5
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_wsoff current.info \
    --baseline-file baseline.info --diff-file posix.udiff \
    --rc path_style=windows --rc cross_platform_read=0 \
    --hierarchical --prefix `pwd` \
    --ignore source --synthesize-missing 2>&1 | tee wsoff.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail wshost "genhtml failed with 'cross_platform_read=0'"
fi
if grep -q -e 'ERROR: (usage)' -e 'WARNING: (usage)' wsoff.log ; then
    fail wshost "'cross_platform_read=0' made an accepted name a complaint"
fi
if ! diff <(summary wshost.log) <(summary wsoff.log) ; then
    fail wshost "the setting reached a read which normalized anyway"
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'xplatform' $LOCAL_COVERAGE 0
fi

exit $STATUS
