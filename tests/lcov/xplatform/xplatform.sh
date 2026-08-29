#!/bin/bash
set +x

# Reading a '.info' file which was written on the other platform:  the source
#   file names in it use that platform's directory separator.  The two
#   directions are not symmetric, because the platforms are not:
#
#   - a Windows name read on a POSIX machine names nothing which can be found
#     here, so it is translated to this platform's separator as it is read,
#     which is what 'cross_platform_read' asks for and what it asks for by
#     default.  Set it to 0 to say that a backslash really is part of the name,
#     and such a name is used exactly as it is and reported as an ERROR_USAGE
#     which says what that costs
#   - a POSIX name read on Windows works as it stands - Windows accepts '/' as a
#     directory separator as well as '\' - so it is not an error.  It is
#     normalized to '\' all the same:  the filesystem there takes both
#     separators, but we do not - every path operation of ours splits on the one
#     character '$dirseparator_re' - so a name left in the foreign spelling is
#     decomposed one way by us and another way by the path modules we build
#     names with.  We note the normalization at verbosity 1;  the setting has
#     nothing to add there
#   - Cygwin and MSYS are a third case.  They
#     write POSIX names, so nothing of ours is munged on the way out - but they
#     accept a Windows name on the way in, drive letter and all, so a Windows
#     name read there is not an error.  Same treatment as the POSIX name read on
#     Windows, in the other direction
#   - a name which uses both separators is ambiguous on a POSIX machine, where a
#     backslash is a legal character in a file name:  there is no way to tell
#     which of the two divides its directories, so it is an ERROR_USAGE and the
#     name is used exactly as it is.  Where both are accepted there is nothing
#     to tell - every one of them is a separator - so it is normalized like
#     any other foreign name
#
#   See 'lcovutil::check_path_separator'.
#
# 'path_style' is what makes the other two platforms' halves of that code
#   reachable from here:  it forces the convention this run works in, so a POSIX
#   '.info' read with 'path_style=windows' takes the path a POSIX trace would
#   take on Windows, and a Windows '.info' read with 'path_style=cygwin' takes
#   the path it would take there.  See 'lcovutil::set_path_style'.
#
# The cases:
#   1. a Windows trace read here with 'cross_platform_read=0':  ERROR_USAGE
#      naming the file, the line, the separator it found and the one this
#      platform uses, with the explanation and the suggested fix - once for the
#      input rather than once per section - and no output file
#   2. ..and '--ignore usage' as well:  a warning instead of the error, and the
#      names kept exactly as they are
#   3. the default:  every name in this platform's terms, and the same coverage
#      data as the read which kept them - only the names change.  '--list' is
#      where that shows:  it groups the translated names under their common
#      directory, and can only print the kept ones in full.  The translation is
#      noted once per input file at verbosity 1, and not at all below it
#   4. and with '--substitute' to drop the drive letter - the documented way to
#      deal with one, since no local directory can be guessed for it - the trace
#      reads as exactly the POSIX trace which names the same files
#   5. so the sources here are found:  genhtml has real source to show, and
#      '--exclude' patterns written with '/' match - neither of which is true of
#      a name which was kept.  What is true either way is the *layout* of the
#      report:  a name in the Windows spelling is decomposed as though it were
#      written '/C:/proj/src/foo.c', so the pages, the directories they are
#      written in and the relative hrefs between them are the ones the
#      translated read produces.  See 'lcovutil::native_path'
#   6. the other direction, driven by 'path_style=windows':  a POSIX trace read
#      as Windows just works - no error, the names normalized to '\', a note at
#      verbosity 1 and nothing at all without '-v' - and neither value of the
#      setting changes any of that, since normalizing there is not optional
#   7. an invalid 'path_style' value - and the values it does accept
#   8. a name which uses both separators is an error here, whichever way the
#      setting is left - and is used exactly as it is when the error is ignored.
#      Read as Windows the same name is unremarkable, and normalized like any
#      other
#   9. a trace already in this platform's terms is untouched either way - the
#      translation is a no-op, not a rewrite.  Note that the output of case 3 is
#      such a trace:  the drive letter is kept as an ordinary path element, so
#      what we write can be read back without complaint
#  10. the split read:  the error is raised in the child which read the chunk,
#      and its count reaches the parent
#  11. the third platform, driven by 'path_style=cygwin':  a Windows trace read
#      there just works - no error, and a note at verbosity 1 naming this
#      platform rather than Windows - and the names are normalized to the POSIX
#      separator Cygwin writes whatever the setting says, so the result
#      is the translated read of case 3.  A mixed name is unremarkable there
#      too, for the reason it is unremarkable on Windows
#  12. what that normalization is worth on those platforms, which is what case 3
#      is worth here:  '--list' groups the names under their common directory
#      instead of printing every one of them in full, genhtml finds the sources,
#      and '--exclude' patterns written with '/' match.  Normalizing there is
#      not optional, which is why those platforms do it whatever the setting
#      says:  on a real Cygwin/MSYS host 'File::Spec' takes '\' for a
#      separator and 'File::Basename' does not, so a name which uses '\' has two
#      decompositions which disagree.  The hierarchy is not in that list:  it is
#      built from the decomposed name, so it is the same either way

source ../../common.tst

LCOV_OPTS="--branch $PARALLEL $PROFILE"

rm -rf *.info *.log *.json *.xlsx proj html html_asread html_prefix \
    html_prefix2 html_cyg perlcov.info pycov.info __pycache__

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

# Cases 1 to 9 read the input in one process, and check the message it produced
#   exactly:  how many times the foreign separator was reported, and the whole
#   text of the report - including the "(use --ignore-errors usage ..)" hint.
#   Neither of those is well defined for a split read:  a child reports for its
#   own chunk (it inherits an empty '%reported_foreign_separator'), so the count
#   is the number of chunks which held a foreign name rather than one, and a
#   child prints no hint at all - see '$lcovutil::in_child_process' in
#   'lcovutil::ignorable_error'.  LCOV_FORCE_PARALLEL splits this input whatever
#   its size, and the suite runs the whole testsuite with the variable set, so
#   drop it rather than let it decide.  Case 10 is the split read, and asks for
#   the split itself.
unset LCOV_FORCE_PARALLEL

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

# ----------------------------------------------------------------------
# the inputs:  a small source tree here, and three traces which name it - one
#   written on Windows, one written here, and one which uses both separators.
#   The Windows names are the POSIX ones with a 'C:' drive prefix, so that
#   dropping that prefix from a translated read has to produce the POSIX trace
#   exactly (case 4).
# The two sections are deliberately the same number of lines:  a section is
#   indivisible, so 'AggregateTraces::_partition_sections' declines to split an
#   input at all unless the largest source file is at most half of it, and case
#   10 needs the split to happen.
# ----------------------------------------------------------------------
mkdir -p proj/src/sub

cat >proj/src/foo.c <<'EOF'
int foo(int a)
{
    if (a > 0)
        return a;
    return -a;
}
EOF

cat >proj/src/sub/bar.c <<'EOF'
int bar(int b)
{
    if (b > 0)
        return b + 1;
    return 0;
}
EOF

cat >posix.info <<'EOF'
TN:xplat
SF:proj/src/foo.c
FN:1,6,foo
FNDA:2,foo
FNF:1
FNH:1
BRDA:3,0,0,2
BRDA:3,0,1,0
BRF:2
BRH:1
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
BRDA:3,0,0,5
BRDA:3,0,1,0
BRF:2
BRH:1
DA:1,5
DA:3,5
DA:4,5
DA:5,0
DA:6,0
LF:5
LH:3
end_of_record
EOF

cat >win.info <<'EOF'
TN:xplat
SF:C:\proj\src\foo.c
FN:1,6,foo
FNDA:2,foo
FNF:1
FNH:1
BRDA:3,0,0,2
BRDA:3,0,1,0
BRF:2
BRH:1
DA:1,2
DA:3,2
DA:4,2
DA:5,0
LF:4
LH:3
end_of_record
SF:C:\proj\src\sub\bar.c
FN:1,6,bar
FNDA:5,bar
FNF:1
FNH:1
BRDA:3,0,0,5
BRDA:3,0,1,0
BRF:2
BRH:1
DA:1,5
DA:3,5
DA:4,5
DA:5,0
DA:6,0
LF:5
LH:3
end_of_record
EOF

cat >mixed.info <<'EOF'
TN:xplat
SF:C:\proj/src\foo.c
FN:1,6,foo
FNDA:2,foo
FNF:1
FNH:1
BRDA:3,0,0,2
BRDA:3,0,1,0
BRF:2
BRH:1
DA:1,2
DA:3,2
DA:4,2
DA:5,0
LF:4
LH:3
end_of_record
EOF

# ----------------------------------------------------------------------
echo "*** 1. cross_platform_read=0: the foreign separator is an error"
# ----------------------------------------------------------------------
# There is no command line option for the setting:  '--rc' is how a single run
#   changes it, and a configuration file is how a machine which really does have
#   backslashes in its file names would
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o disabled.info \
    --rc cross_platform_read=0 2>&1 | tee disabled.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail disabled "expected lcov to fail reading a Windows trace"
fi
if [ -f disabled.info ] ; then
    fail disabled "wrote an output file anyway"
fi
COUNT=`grep -c 'ERROR: (usage)' disabled.log`
if [ 1 != "$COUNT" ] ; then
    fail disabled "expected 1 usage error, saw $COUNT"
fi
# where, what, and how to fix it
for pattern in '"win.info":2: source file name' \
    "uses the Windows directory separator" \
    "this run works in POSIX paths, whose separator is '/'" \
    'the source file cannot be' \
    'the name is decomposed as' \
    "'/C:/proj/src/foo.c'" \
    "'cross_platform_read' is disabled" \
    '--rc cross_platform_read=1' \
    "'C:\\proj\\src\\foo.c' -> 'C:/proj/src/foo.c'" \
    '--ignore-errors usage' ; do
    if ! grep -F -q -e "$pattern" disabled.log ; then
        fail disabled "message does not mention: $pattern"
    fi
done

# ----------------------------------------------------------------------
echo "*** 2. ..and --ignore usage: the names are kept exactly as they are"
# ----------------------------------------------------------------------
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o keep.info \
    --rc cross_platform_read=0 --ignore usage 2>&1 | tee keep.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail keep "lcov failed with the error ignored"
fi
COUNT=`grep -c 'WARNING: (usage)' keep.log`
if [ 1 != "$COUNT" ] ; then
    fail keep "expected 1 usage warning, saw $COUNT"
fi
for name in 'SF:C:\proj\src\foo.c' 'SF:C:\proj\src\sub\bar.c' ; do
    if ! grep -F -x -q -e "$name" keep.info ; then
        fail keep "'$name' was not kept"
    fi
done

# ----------------------------------------------------------------------
echo "*** 3. by default the names are translated, and nothing else changes"
# ----------------------------------------------------------------------
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o xplat.info 2>&1 | tee xplat.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail xplat "lcov failed reading a Windows trace"
fi
if grep -q 'usage' xplat.log ; then
    fail xplat "translating the names still complained about them"
fi
# the translation is not a problem, so it is not reported - but it does explain
#   why the names in the result are not the names in the input, so it is worth a
#   note at verbosity 1
if grep -q -e 'separator' xplat.log ; then
    fail xplat "the translation was reported below verbosity 1"
fi
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o wnote.info -v 2>&1 | tee wnote.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail xplat "lcov failed reading a Windows trace verbosely"
fi
for pattern in '"win.info":2: source file name' \
    "uses the Windows directory separator '\\'" \
    'is not a separator here' \
    "normalizing these names to '/'" ; do
    if ! grep -F -q -e "$pattern" wnote.log ; then
        fail xplat "the verbose note does not mention: $pattern"
    fi
done
# one note for the input, not one per section
COUNT=`grep -c 'normalizing these names' wnote.log`
if [ 1 != "$COUNT" ] ; then
    fail xplat "expected 1 note, saw $COUNT"
fi
if ! diff xplat.info wnote.info ; then
    fail xplat "the verbose read produced a different result"
fi
for name in 'SF:C:/proj/src/foo.c' 'SF:C:/proj/src/sub/bar.c' ; do
    if ! grep -F -x -q -e "$name" xplat.info ; then
        fail xplat "'$name' is not in the result"
    fi
done
if grep -q '^SF:.*\\' xplat.info ; then
    fail xplat "a name still uses the Windows separator"
fi
# the data is the same data:  the names are the only difference
if ! diff <(grep -v '^SF:' keep.info) <(grep -v '^SF:' xplat.info) ; then
    fail xplat "the translated read changed more than the names"
fi
# ..and what that is worth:  '--list' can find the common directory of the
#   translated names and take it off the front of each one.  Where the name is
#   kept, it finds nothing to remove and prints the whole name of every file
#   under a single '[/]' heading:  '--list' shows the names as they were read,
#   and those have no elements it can see.
#   Windows input usually wants 'case_insensitive' as well, which takes the
#   other of the two prefix comparisons
for flag in '' '--rc case_insensitive=1' ; do
    label="list${flag:+_nocase}"
    $COVER $LCOV_TOOL $LCOV_OPTS --list xplat.info $flag 2>&1 | tee $label.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail xplat "'--list' failed on the translated names ('$flag')"
    fi
    # the heading is lower case when the names are compared that way
    if ! grep -i -F -x -q -e '[C:/proj/src/]' $label.log ; then
        fail xplat "'--list' did not find the common directory ('$flag')"
    fi
    for name in 'foo.c' 'sub/bar.c' ; do
        if ! grep -q -e "^$name  *|" $label.log ; then
            fail xplat "'--list' did not shorten '$name' ('$flag')"
        fi
    done
done
# the names of 'keep.info' are still the Windows ones, so this run has to keep
#   them too - reading them back is the same read, and the same error
$COVER $LCOV_TOOL $LCOV_OPTS --list keep.info \
    --rc cross_platform_read=0 --ignore usage 2>&1 | tee listkeep.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail xplat "'--list' failed on the names which were kept"
fi
if ! grep -F -x -q -e '[/]' listkeep.log ; then
    fail xplat "'--list' grouped the kept names under a directory"
fi
if ! grep -q -e '^C:\\proj\\src\\foo.c  *|' listkeep.log ; then
    fail xplat "'--list' shortened a name which was kept"
fi

# ----------------------------------------------------------------------
echo "*** 4. with --substitute, the Windows trace becomes the POSIX one"
# ----------------------------------------------------------------------
# the drive letter is an ordinary leading path element after the translation,
#   so '--substitute' is what removes it.  The names are then the names the
#   POSIX trace uses, and the two reads have to agree exactly;
#   case 5 is where that name is used to find the source.
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o subst.info \
    --substitute 's#^C:/##' 2>&1 | tee subst.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail subst "lcov failed reading the translated names"
fi
$COVER $LCOV_TOOL $LCOV_OPTS -a posix.info -o native.info 2>&1 | tee native.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail subst "lcov failed reading the POSIX trace"
fi
if ! diff native.info subst.info ; then
    fail subst "the Windows trace did not read as the POSIX one"
fi
# ..and the drive-letter-agnostic pattern the man page suggests does the same.
#   Note that it is written with '/':  the substitution is applied after the
#   name has been translated, not to the name as it appears in the file
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o subst_any.info \
    --substitute 's#^[A-Za-z]:/##' \
    2>&1 | tee subst_any.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail subst "lcov failed with the generic drive letter pattern"
fi
if ! diff native.info subst_any.info ; then
    fail subst "the generic drive letter pattern did not remove 'C:'"
fi

# ----------------------------------------------------------------------
echo "*** 5. genhtml has a hierarchy to build, and '/' patterns match"
# ----------------------------------------------------------------------
$COVER $GENHTML_TOOL $LCOV_OPTS -o html win.info \
    --substitute 's#^C:/##' 2>&1 | tee html.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail html "genhtml failed reading a Windows trace"
fi
BAR=`find html -name 'bar.c.gcov.html'`
if [ 1 != `echo "$BAR" | wc -w` ] ; then
    fail html "expected one bar.c page, found: $BAR"
fi
case "$BAR" in
    */sub/bar.c.gcov.html) ;;
    *) fail html "bar.c is not in a 'sub' directory: $BAR" ;;
esac
if [ 0 == `find html -name 'foo.c.gcov.html' | wc -l` ] ; then
    fail html "no page for foo.c"
fi
# and the name reaches a source file which is really here:  no
#   '--synthesize-missing', and the page shows the line the trace counted
if ! grep -F -q -e 'return b + 1;' "$BAR" ; then
    fail html "the source of bar.c was not read"
fi
# ..and the layout of that report does not depend on the spelling at all:  a run
#   which keeps the names writes the same pages in the same directories, with
#   the same relative links between them.  It is the source and the patterns
#   which need the translation, not the report.
#   The name to decompose is what 'lcovutil::native_path' returns, so a page is
#   named after a file rather than after a whole path, and the href to it is a
#   relative path a browser can resolve.
$COVER $GENHTML_TOOL $LCOV_OPTS -o html_asread win.info \
    --rc cross_platform_read=0 --ignore usage,source --synthesize-missing \
    2>&1 | tee html_asread.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail html "genhtml failed reading the names as they were written"
fi
PAGES=`find html_asread -name '*.gcov.html' | sed -e 's|^html_asread/||' | sort`
if [ "$PAGES" != "src/foo.c.gcov.html
src/sub/bar.c.gcov.html" ] ; then
    fail html "expected the pages of a directory hierarchy, found: $PAGES"
fi
# nothing written here is named after a path rather than a file
if [ 0 != `find html_asread -name '*\\*' -o -name '*:*' | wc -l` ] ; then
    fail html "a report file is named after the whole path"
fi
# ..which is to say it is the report the translated read of case 5 produced -
#   the same files, in the same places
if ! diff <(cd html_asread && find . | sort) <(cd html && find . | sort) ; then
    fail html "the spelling of the names reached the report layout"
fi
# the links a browser has to resolve are the relative ones that layout implies
if ! grep -F -q -e 'href="src/index.html"' html_asread/index.html ; then
    fail html "the top-level index does not link to the 'src' directory"
fi
if ! grep -F -q -e 'href="foo.c.gcov.html"' html_asread/src/index.html ; then
    fail html "the 'src' index does not link to the foo.c page"
fi
if grep -q -e 'href="[^"]*\\' html_asread/index.html \
    html_asread/src/index.html ; then
    fail html "an href holds the separator the names were read with"
fi
# ..and they are the hrefs of the translated read, one for one
for page in index.html src/index.html src/sub/index.html ; do
    if ! diff <(grep -o 'href="[^"]*"' html_asread/$page | sort -u) \
        <(grep -o 'href="[^"]*"' html/$page | sort -u) ; then
        fail html "the hrefs of '$page' depend on the spelling of the names"
    fi
done
# the report is the same wherever it is run from:  a drive letter is decomposed
#   as an absolute name, so no part of the current directory reaches the layout
if grep -F -q -e "`pwd`" html_asread/index.html ; then
    fail html "the current directory reached the report layout"
fi
# ..and a '--prefix' may be written the way the '.info' file writes its names:
#   it is the leading part of one of those names, so it is decomposed the same
#   way.  'C:\proj\src' names a directory which holds sources rather than
#   directories, which genhtml shortens by one element and says so - and that
#   message is the proof that the Windows spelling reached the comparison.
#   The list is comma separated, so this is also the several-prefixes path;  the
#   second one names nothing in this trace and is simply not used
$COVER $GENHTML_TOOL $LCOV_OPTS -o html_prefix win.info \
    --prefix 'C:\proj\src,C:\other' --rc cross_platform_read=0 \
    --ignore usage,source --synthesize-missing 2>&1 | tee html_prefix.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail html "genhtml failed with a Windows-spelled '--prefix'"
fi
for pattern in "using prefix '/C:/proj' (rather than '/C:/proj/src')" \
    'Using user-specified filename prefix "/C:/proj"' ; do
    if ! grep -F -q -e "$pattern" html_prefix.log ; then
        fail html "the Windows-spelled prefix was not decomposed: $pattern"
    fi
done
if ! diff <(cd html_prefix && find . | sort) \
    <(cd html_asread && find . | sort) ; then
    fail html "the Windows-spelled prefix laid the report out differently"
fi
# ..and it reaches that comparison the same way when the names themselves have
#   been translated:  both sides are decomposed, so the two spellings meet
$COVER $GENHTML_TOOL $LCOV_OPTS -o html_prefix2 win.info \
    --prefix 'C:\proj\src,C:\other' \
    --ignore source --synthesize-missing 2>&1 | tee html_prefix2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail html "genhtml failed with a Windows-spelled '--prefix' and translation"
fi
for pattern in "using prefix '/C:/proj' (rather than '/C:/proj/src')" \
    'Using user-specified filename prefix "/C:/proj"' ; do
    if ! grep -F -q -e "$pattern" html_prefix2.log ; then
        fail html "the prefix did not match the translated names: $pattern"
    fi
done
if ! diff <(cd html_prefix2 && find . | sort) \
    <(cd html_prefix && find . | sort) ; then
    fail html "the prefix laid the report out differently once translated"
fi

# an '--exclude' pattern written for this platform
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o excl.info \
    --exclude '*/sub/*' 2>&1 | tee excl.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail exclude "lcov failed excluding the translated name"
fi
COUNT=`grep -c '^SF:' excl.info`
if [ 1 != "$COUNT" ] ; then
    fail exclude "expected 1 file left, saw $COUNT"
fi
# ..which the same pattern cannot do to a name that was kept:  it has no '/' for
#   the pattern to match, so nothing is excluded and 'unused' has to be ignored
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o noexcl.info \
    --rc cross_platform_read=0 --ignore usage,unused --exclude '*/sub/*' \
    2>&1 | tee noexcl.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail exclude "lcov failed excluding a name which was kept"
fi
COUNT=`grep -c '^SF:' noexcl.info`
if [ 2 != "$COUNT" ] ; then
    fail exclude "expected the pattern not to match, $COUNT files left"
fi

# ----------------------------------------------------------------------
echo "*** 6. the other direction: path_style=windows over a POSIX trace"
# ----------------------------------------------------------------------
# Windows accepts '/' as a directory separator as well as '\', so a POSIX name
#   read there is not an error:  no error, no warning.  It is still normalized
#   to the separator that platform writes - we split paths on one character, and
#   the modules we build them with do not agree with each other about the other
#   one - and '-v' says so, since it explains why the report does not name the
#   files the way the '.info' file did
$COVER $LCOV_TOOL $LCOV_OPTS -a posix.info -o wstyle.info -v \
    --rc path_style=windows 2>&1 | tee wstyle.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail wstyle "a POSIX trace read as Windows should simply work"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' wstyle.log ; then
    fail wstyle "reading POSIX names as Windows complained"
fi
for name in 'SF:proj\src\foo.c' 'SF:proj\src\sub\bar.c' ; do
    if ! grep -F -x -q -e "$name" wstyle.info ; then
        fail wstyle "'$name' is not in the result"
    fi
done
# no name is left in the spelling we read:  that is the whole point - one
#   spelling everywhere, so that every part of the tool decomposes a name the
#   same way
if grep -q '^SF:.*/' wstyle.info ; then
    fail wstyle "a name still uses the POSIX separator"
fi
for pattern in "uses the POSIX directory separator '/'" \
    "which Windows accepts:  normalizing these names to '\\'." ; do
    if ! grep -F -q -e "$pattern" wstyle.log ; then
        fail wstyle "'-v' did not note the POSIX names: $pattern"
    fi
done
# ..once for the input, not once per section
COUNT=`grep -c 'which Windows accepts' wstyle.log`
if [ 1 != "$COUNT" ] ; then
    fail wstyle "expected 1 note, saw $COUNT"
fi
# and nothing at all without '-v':  this is not a problem the user has to see
$COVER $LCOV_TOOL $LCOV_OPTS -a posix.info -o wquiet.info \
    --rc path_style=windows 2>&1 | tee wquiet.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail wstyle "lcov failed reading POSIX names as Windows"
fi
if grep -q 'Windows accepts' wquiet.log ; then
    fail wstyle "the note was printed without '-v'"
fi
if ! diff wstyle.info wquiet.info ; then
    fail wstyle "'-v' changed the result"
fi

# 'cross_platform_read' has nothing to ask for on a platform which takes both
#   separators:  the name is normalized because it has to be, so neither value
#   of the setting changes anything here - neither the result nor the note.  It
#   is not a no-op everywhere:  where '\' is not a separator, it is the
#   difference between case 1 and case 3
for value in 0 1 ; do
    $COVER $LCOV_TOOL $LCOV_OPTS -a posix.info -o wstyle_$value.info -v \
        --rc path_style=windows --rc cross_platform_read=$value \
        2>&1 | tee wstyle_$value.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail wstyle "lcov failed with 'cross_platform_read=$value'"
    fi
    if ! diff wstyle.info wstyle_$value.info ; then
        fail wstyle "'cross_platform_read=$value' changed a Windows-style read"
    fi
    if ! diff <(grep 'which Windows accepts' wstyle.log) \
        <(grep 'which Windows accepts' wstyle_$value.log) ; then
        fail wstyle "the note differs with 'cross_platform_read=$value'"
    fi
done

# ----------------------------------------------------------------------
echo "*** 7. an invalid path_style"
# ----------------------------------------------------------------------
$COVER $LCOV_TOOL $LCOV_OPTS -a posix.info -o vms.info --rc path_style=vms \
    2>&1 | tee vms.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail path_style "expected lcov to reject 'path_style=vms'"
fi
if ! grep -F -q -e "invalid 'path_style' value 'vms'" vms.log ; then
    fail path_style "did not say which value was wrong"
fi
EXPECT="expected 'auto', 'cygwin', 'posix', 'windows'"
if ! grep -F -q -e "$EXPECT" vms.log ; then
    fail path_style "did not say which values are accepted"
fi
# ignored, it falls back to the platform we are on
$COVER $LCOV_TOOL $LCOV_OPTS -a posix.info -o vms2.info --rc path_style=vms \
    --ignore usage 2>&1 | tee vms2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail path_style "lcov failed with the invalid value ignored"
fi
if ! grep -F -x -q -e 'SF:proj/src/foo.c' vms2.info ; then
    fail path_style "the ignored value did not fall back to this platform"
fi

# ----------------------------------------------------------------------
echo "*** 8. a name which uses both separators is an error here"
# ----------------------------------------------------------------------
# a backslash is a legal character in a POSIX file name, so there is no way to
#   tell which of the two separators divides this name's directories - and
#   translating them cannot resolve that either, so it is an error whichever way
#   'cross_platform_read' is set
for value in 0 1 ; do
    label="mixed_err_$value"
    $COVER $LCOV_TOOL $LCOV_OPTS -a mixed.info -o $label.info \
        --rc cross_platform_read=$value 2>&1 | tee $label.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        fail mixed "expected a mixed name to be an error ('$value')"
    fi
    if [ -f $label.info ] ; then
        fail mixed "wrote an output file anyway ('$value')"
    fi
    COUNT=`grep -c 'ERROR: (usage)' $label.log`
    if [ 1 != "$COUNT" ] ; then
        fail mixed "expected 1 usage error, saw $COUNT ('$value')"
    fi
    for pattern in "uses both the POSIX directory separator '/'" \
        "and the Windows one '\\'" \
        'Translating the separators cannot help' \
        "'--substitute'" ; do
        if ! grep -F -q -e "$pattern" $label.log ; then
            fail mixed "message does not mention: $pattern ('$value')"
        fi
    done
done
# ignored, the name is used exactly as it is - no guess in either direction
$COVER $LCOV_TOOL $LCOV_OPTS -a mixed.info -o mixed_kept.info \
    --ignore usage 2>&1 | tee mixed_kept.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail mixed "lcov failed with the error ignored"
fi
if ! grep -F -x -q -e 'SF:C:\proj/src\foo.c' mixed_kept.info ; then
    fail mixed "the mixed name was changed"
fi
# the documented recipe for a name you can identify:  rewrite it yourself, and
#   ignore the error - substitutions are applied after the check, so the error
#   is raised whether or not a pattern would have fixed the name
$COVER $LCOV_TOOL $LCOV_OPTS -a mixed.info -o mixed_subst.info \
    --ignore usage --substitute 's#\\#/#g' 2>&1 | tee mixed_subst.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail mixed "lcov failed rewriting a mixed name"
fi
if ! grep -F -x -q -e 'SF:C:/proj/src/foo.c' mixed_subst.info ; then
    fail mixed "'--substitute' did not rewrite the mixed name"
fi
COUNT=`grep -c 'WARNING: (usage)' mixed_subst.log`
if [ 1 != "$COUNT" ] ; then
    fail mixed "expected the message even with the pattern, saw $COUNT"
fi
# ..and read as Windows there is nothing to tell:  every one of the separators
#   is a separator there, so the name is unremarkable - and is normalized like
#   any other foreign name, whichever way 'cross_platform_read' is set
$COVER $LCOV_TOOL $LCOV_OPTS -a mixed.info -o mixed_win.info \
    --rc path_style=windows 2>&1 | tee mixed_win.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail mixed "a mixed name read as Windows should simply work"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' mixed_win.log ; then
    fail mixed "a mixed name read as Windows complained"
fi
if ! grep -F -x -q -e 'SF:C:\proj\src\foo.c' mixed_win.info ; then
    fail mixed "the mixed name was not normalized reading it as Windows"
fi
$COVER $LCOV_TOOL $LCOV_OPTS -a mixed.info -o mixed_win2.info \
    --rc path_style=windows --rc cross_platform_read=0 2>&1 | tee mixed_win2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail mixed "lcov failed normalizing a mixed name to Windows"
fi
if ! diff mixed_win.info mixed_win2.info ; then
    fail mixed "the setting reached a mixed name which was normalized anyway"
fi

# ----------------------------------------------------------------------
echo "*** 9. the setting does nothing to a trace which is already ours"
# ----------------------------------------------------------------------
# there is no foreign separator in these names, so there is nothing to translate
#   and nothing for the setting to change
$COVER $LCOV_TOOL $LCOV_OPTS -a posix.info -o plain.info 2>&1 | tee plain.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail noop "lcov failed reading the POSIX trace"
fi
$COVER $LCOV_TOOL $LCOV_OPTS -a posix.info -o noop.info \
    --rc cross_platform_read=0 2>&1 | tee noop.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail noop "lcov failed with 'cross_platform_read=0'"
fi
if ! diff plain.info noop.info ; then
    fail noop "the setting changed a trace which was already ours"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' plain.log noop.log ; then
    fail noop "reading a POSIX trace here complained"
fi
# ..including the one we translated:  'C:' is an ordinary path element now, so
#   reading our own output back is not an error
$COVER $LCOV_TOOL $LCOV_OPTS -a xplat.info -o reread.info \
    2>&1 | tee reread.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail noop "a translated trace does not read back"
fi
if ! diff <(grep '^SF:' xplat.info) <(grep '^SF:' reread.info) ; then
    fail noop "re-reading a translated trace changed the names"
fi

# ----------------------------------------------------------------------
echo "*** 10. the split read reports from the child which read the chunk"
# ----------------------------------------------------------------------
# these inputs are small, so lower both thresholds to make the file "large"
#   enough to split - as 'parallel_parse' does
SPLIT="--parallel 4 --rc parallel_parse_min_lines=1 \
       --rc dedicate_segment_line_estimate=10"
$COVER $LCOV_TOOL --branch $PROFILE $SPLIT -a win.info -o split.info \
    --rc cross_platform_read=0 2>&1 | tee split.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail split "expected the split read to fail too"
fi
CHUNKS=`grep -oE 'in [0-9]+ chunks' split.log | grep -oE '[0-9]+'`
if [ "${CHUNKS:-0}" -lt 2 ] ; then
    fail split "the input was not split (${CHUNKS:-0} chunks)"
fi
if ! grep -q 'ERROR: (usage)' split.log ; then
    fail split "the child did not report the foreign separator"
fi
# the parent counts what its children reported:  '--expect-message-count' is
#   evaluated there, after 'update_state' has folded the counts in
$COVER $LCOV_TOOL --branch $PROFILE $SPLIT -a win.info -o split2.info \
    --rc cross_platform_read=0 --ignore usage \
    --expect-message-count 'usage:%C>=1' 2>&1 | tee split2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail split "the parent did not count the children's usage messages"
fi
# ..and each child translates its own chunk, so the whole result is the one the
#   unsplit read produced
$COVER $LCOV_TOOL --branch $PROFILE $SPLIT -a win.info -o split3.info \
    2>&1 | tee split3.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail split "the split read failed"
fi
if ! diff <(grep '^SF:' xplat.info) <(grep '^SF:' split3.info) ; then
    fail split "the split read translated the names differently"
fi

# ----------------------------------------------------------------------
echo "*** 11. path_style=cygwin: a Windows name is accepted as it stands"
# ----------------------------------------------------------------------
# Cygwin and MSYS write POSIX names but accept Windows ones, drive letter and
#   all:  'C:\proj\src\foo.c' opens there.  Reporting it would be reporting a
#   name which works - so this is the case 6 treatment in the other direction:
#   not an error, and normalized to the separator this platform writes.
# '$^O' is 'cygwin' or 'msys' on those platforms, and neither of them matches
#   the /Win/ which picks the separator, so they were classified as plain POSIX
#   hosts and got the case 1 error on a name they can open.
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o cyg.info -v \
    --rc path_style=cygwin 2>&1 | tee cyg.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail cygwin "a Windows trace read as Cygwin should simply work"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' cyg.log ; then
    fail cygwin "reading Windows names as Cygwin complained"
fi
for name in 'SF:C:/proj/src/foo.c' 'SF:C:/proj/src/sub/bar.c' ; do
    if ! grep -F -x -q -e "$name" cyg.info ; then
        fail cygwin "'$name' is not in the result"
    fi
done
if grep -q '^SF:.*\\' cyg.info ; then
    fail cygwin "a name still uses the Windows separator"
fi
# ..so this is the translated read of case 3, which a POSIX host does because
#   the setting says so and this one does whatever it says:  same names, and the
#   same coverage data as the read the case 1 error was raised on
if ! diff xplat.info cyg.info ; then
    fail cygwin "the accepted read is not the POSIX host's translated read"
fi
if ! diff <(grep -v '^SF:' keep.info) <(grep -v '^SF:' cyg.info) ; then
    fail cygwin "the accepted read is not the read the error was raised on"
fi
# both halves of the note are the other way round from case 6:  the separator it
#   found is the Windows one, and the platform which accepts it is this one
for pattern in "uses the Windows directory separator '\\'" \
    "which Cygwin accepts:  normalizing these names to '/'." ; do
    if ! grep -F -q -e "$pattern" cyg.log ; then
        fail cygwin "'-v' did not note the Windows names: $pattern"
    fi
done
# ..once for the input, not once per section
COUNT=`grep -c 'which Cygwin accepts' cyg.log`
if [ 1 != "$COUNT" ] ; then
    fail cygwin "expected 1 note, saw $COUNT"
fi
# and nothing at all without '-v':  this is not a problem the user has to see
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o cygquiet.info \
    --rc path_style=cygwin 2>&1 | tee cygquiet.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail cygwin "lcov failed reading Windows names as Cygwin"
fi
if grep -q 'Cygwin accepts' cygquiet.log ; then
    fail cygwin "the note was printed without '-v'"
fi
if ! diff cyg.info cygquiet.info ; then
    fail cygwin "'-v' changed the result"
fi

# the setting has nothing to say here either:  turning it off does not stop the
#   normalization, because a name has to be normalized on a platform which takes
#   both separators - so the result and the note are the ones above
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o cyg2.info -v \
    --rc path_style=cygwin --rc cross_platform_read=0 2>&1 | tee cyg2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail cygwin "lcov failed with 'cross_platform_read=0' on Cygwin"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' cyg2.log ; then
    fail cygwin "'cross_platform_read=0' made an accepted name a complaint"
fi
if ! diff cyg.info cyg2.info ; then
    fail cygwin "the setting reached a read which normalized anyway"
fi
if ! diff <(grep 'which Cygwin accepts' cyg.log) \
    <(grep 'which Cygwin accepts' cyg2.log) ; then
    fail cygwin "the note differs with 'cross_platform_read=0'"
fi

# ..and a name which uses both separators is unremarkable here for the reason it
#   is unremarkable on Windows:  both of the characters in it are separators, so
#   there is no ambiguity to report and nothing stops us normalizing it
$COVER $LCOV_TOOL $LCOV_OPTS -a mixed.info -o cygmixed.info \
    --rc path_style=cygwin 2>&1 | tee cygmixed.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail cygwin "a mixed name read as Cygwin should simply work"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' cygmixed.log ; then
    fail cygwin "a mixed name read as Cygwin complained"
fi
if ! grep -F -x -q -e 'SF:C:/proj/src/foo.c' cygmixed.info ; then
    fail cygwin "the mixed name was not normalized reading it as Cygwin"
fi
$COVER $LCOV_TOOL $LCOV_OPTS -a mixed.info -o cygmixed2.info \
    --rc path_style=cygwin --rc cross_platform_read=0 2>&1 | tee cygmixed2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail cygwin "lcov failed with 'cross_platform_read=0' on a mixed name"
fi
if ! diff cygmixed.info cygmixed2.info ; then
    fail cygwin "the setting reached a mixed name which was normalized anyway"
fi

# ----------------------------------------------------------------------
echo "*** 12. ..and what the normalization is worth on such a platform"
# ----------------------------------------------------------------------
# exactly what case 3 and case 5 are worth here, and for the same reasons - only
#   here the setting cannot take them away.  Keeping the Windows spelling was
#   not free:  '--list' printed every name in full under one '[/]' heading (see
#   'listkeep.log' above), no source was found, and patterns written with '/'
#   matched nothing.  The directory hierarchy is not one of those things:
#   case 5 has just shown that genhtml builds it from the decomposed name, so it
#   does not wait for the names themselves to be normalized.
$COVER $LCOV_TOOL $LCOV_OPTS --list cyg.info --rc path_style=cygwin \
    2>&1 | tee cyglist.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail cyghtml "'--list' failed on the accepted names"
fi
if ! grep -F -x -q -e '[C:/proj/src/]' cyglist.log ; then
    fail cyghtml "'--list' did not find the common directory"
fi
for name in 'foo.c' 'sub/bar.c' ; do
    if ! grep -q -e "^$name  *|" cyglist.log ; then
        fail cyghtml "'--list' did not shorten '$name'"
    fi
done
# genhtml gets a hierarchy to build and real source to show, and the '/' pattern
#   which removes the drive letter matches - none of which the setting can take
#   away on a platform which takes both separators.  The two ignores and
#   '--synthesize-missing' hide nothing here:  the whole log is checked below,
#   and it reports no messages at all
$COVER $GENHTML_TOOL $LCOV_OPTS -o html_cyg win.info --rc path_style=cygwin \
    --substitute 's#^C:/##' --ignore source,unused --synthesize-missing \
    2>&1 | tee cyghtml.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail cyghtml "genhtml failed reading a Windows trace as Cygwin"
fi
if grep -q -e 'ERROR:' -e 'WARNING:' cyghtml.log ; then
    fail cyghtml "genhtml complained about the accepted names"
fi
# every page is where its name says it is - two of them, in two directories
PAGES=`find html_cyg -name '*.gcov.html' | sed -e 's|^html_cyg/||' | sort`
if [ "$PAGES" != "src/foo.c.gcov.html
src/sub/bar.c.gcov.html" ] ; then
    fail cyghtml "expected the pages of a directory hierarchy, found: $PAGES"
fi
# ..and the name reached a source file which is really here
if ! grep -F -q -e 'return b + 1;' html_cyg/src/sub/bar.c.gcov.html ; then
    fail cyghtml "the source of bar.c was not read"
fi
$COVER $LCOV_TOOL $LCOV_OPTS -a win.info -o cygexcl.info \
    --rc path_style=cygwin --exclude '*/sub/*' 2>&1 | tee cygexcl.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail cyghtml "lcov failed excluding an accepted name"
fi
COUNT=`grep -c '^SF:' cygexcl.info`
if [ 1 != "$COUNT" ] ; then
    fail cyghtml "expected 1 file left, saw $COUNT"
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
