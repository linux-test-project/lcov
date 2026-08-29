#!/usr/bin/env bash
set +x

# ============================================================================
# Which language a source file is taken to be written in, which is decided by
#   its extension.  Several filters apply only to C/C++ - the close-brace
#   filter used here among them - so the answer decides whether they run.
#
# The extension list is a literal alternation, and it was matched literally
#   even when the user said that names are not case sensitive:  on a
#   filesystem which does not distinguish them, 'FOO.CPP' and 'foo.cpp' are one
#   file, and only one of the two spellings was C++.
#
# The cases:
#   1. a lower-case extension:  filtered (the control)
#   2. the same extension in upper case:  not filtered, since names are case
#      sensitive by default and the list does not contain that spelling
#   3. the same file with '--rc case_insensitive=1':  filtered
# ============================================================================

source ../../common.tst

# $LCOV_TOOL is set by the test Makefile;  fall back to the tool in $LCOV_HOME
# when this script is run standalone (notably ./language.sh --coverage)
if [ 'x' == "x$LCOV_TOOL" ] ; then
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
fi

rm -f lang_*.log lang_*.info brace.cpp brace.CPP

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
    if [ "$KEEP_GOING" == 0 ] ; then
        exit 1
    fi
}

# the source, in both spellings.  Line 6 holds nothing but the closing brace
#   and was not hit, while line 5 was:  that is what the close-brace filter
#   removes
for f in brace.cpp brace.CPP ; do
    cat > $f <<'EOF'
int f(int a)
{
    if (a > 0)
        return 1;
    return 0;
}
EOF
done

# a tracefile for source file $2, written to $1.  The name is relative:  with
#   'case_insensitive' set, the name lcov opens is the lower case of this one,
#   and every component of an absolute path would be folded along with the
#   extension - which the case sensitive filesystem this may be running on
#   would then not find
mkinfo()
{
    cat > "$1" <<EOF
TN:
SF:$2
DA:1,1
DA:3,1
DA:4,0
DA:5,1
DA:6,0
LF:5
LH:3
end_of_record
EOF
}

# $1 = label, $2 = the tracefile lcov wrote, $3 = 'filtered' or 'kept'
check_brace()
{
    local n=`grep -c -E '^DA:6,' $2`
    if [ 'filtered' == "$3" ] ; then
        if [ 0 != "$n" ] ; then
            cat $2
            fail $1 "the close brace on line 6 was not filtered out"
        fi
    elif [ 1 != "$n" ] ; then
        cat $2
        fail $1 "the close brace on line 6 was filtered out anyway"
    fi
}

# ----------------------------------------------------------------------
echo "*** 1. a lower-case extension"
# ----------------------------------------------------------------------
mkinfo lang_lower_in.info brace.cpp
$COVER $LCOV_TOOL -a lang_lower_in.info -o lang_lower.info --filter brace \
    --ignore-errors empty > lang_lower.log 2>&1
if [ 0 != $? ] ; then
    cat lang_lower.log
    fail lower "lcov failed for brace.cpp"
fi
check_brace lower lang_lower.info filtered

# ----------------------------------------------------------------------
echo "*** 2. an upper-case extension, names case sensitive"
# ----------------------------------------------------------------------
mkinfo lang_upper_in.info brace.CPP
$COVER $LCOV_TOOL -a lang_upper_in.info -o lang_upper.info --filter brace \
    --ignore-errors empty > lang_upper.log 2>&1
if [ 0 != $? ] ; then
    cat lang_upper.log
    fail upper "lcov failed for brace.CPP"
fi
check_brace upper lang_upper.info kept

# ----------------------------------------------------------------------
echo "*** 3. an upper-case extension, names not case sensitive"
# ----------------------------------------------------------------------
$COVER $LCOV_TOOL -a lang_upper_in.info -o lang_insens.info --filter brace \
    --rc case_insensitive=1 --ignore-errors empty > lang_insens.log 2>&1
if [ 0 != $? ] ; then
    cat lang_insens.log
    fail insens "lcov failed for brace.CPP with case_insensitive=1"
fi
check_brace insens lang_insens.info filtered

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'language' $LOCAL_COVERAGE 0
fi

exit $STATUS
