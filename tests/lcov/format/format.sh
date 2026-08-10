#!/bin/bash
set +x

# test various errors in .info data

source ../../common.tst

LCOV_OPTS="--branch $PARALLEL $PROFILE"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
    # and filter exception branches to avoid spurious differences for old compiler
    FILTER='--filter branch'
fi

rm -rf *.gcda *.gcno a.out out.info out2.info *.txt* *.json dumper* testRC *.gcov *.gcov.* *.log \
    before_sf.info ver_before_sf.info after_eor.info double_eor.info \
    tn_inside.info nested_sf.info no_eor.info comments*.info \
    junk_in_section.info no_tag.info bad_payload.info ignored.info crlf.info \
    skip_brda.info skip_mcdc.info skip_fn.info skip_place.info \
    *_out.info

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

$COVER $LCOV_TOOL $LCOV_OPTS --summary format.info 2>&1 | tee err1.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected error from lcov --summary but didn't see it"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
ERRS=`grep -c 'ERROR: (negative)' err1.log`
if [ "$ERRS" != 1 ] ; then
    echo "didn't see expected 'negative' error"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS --summary format.info --ignore negative 2>&1 | tee err2.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected error from lcov --summary negative but didn't see it"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
ERRS=`grep -c 'ERROR: (format)' err2.log`
if [ "$ERRS" != 1 ] ; then
    echo "didn't see expected 'format' error"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -o out.info -a format.info --ignore format,negative 2>&1 | tee warn.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error from lcov -add"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for type in format negative ; do
    COUNT=`grep -c "WARNING: ($type)" warn.log`
    if [ "$COUNT" != 3 ] ; then
        echo "didn't see expected '$type' warnings: $COUNT"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    # and look for the summary count:
    grep "$type: 3" warn.log
    if [ 0 != $? ] ; then
        echo "didn't see Type summary count"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done


# the file we wrote should be clean
$COVER $LCOV_TOOL $LCOV_OPTS --summary out.info
if [ 0 != $? ] ; then
    echo "Error:  unexpected error from lcov --summary"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

rm -f out2.info
# test excessive count messages
$COVER $LCOV_TOOL $LCOV_OPTS -o out2.info -a format.info --ignore format,format,negative,negative --rc excessive_count_threshold=1000000 2>&1 | tee excessive.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected excessive hit count message"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep "ERROR: (excessive) Unexpected excessive hit count" excessive.log
if [ 0 != $? ] ; then
    echo "Error:  expected excessive hit count message but didn't find it"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
if [ -e out2.info ] ; then
    echo "Error: expected error to terminate processing - but out2.info generated"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# check that --keep-going works as expected
$COVER $LCOV_TOOL $LCOV_OPTS -o out2.info -a format.info --ignore format,format,negative,negative --rc excessive_count_threshold=1000000 --keep-going 2>&1 | tee keepGoing.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected excessive hit count message"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep "ERROR: (excessive) Unexpected excessive hit count" keepGoing.log
if [ 0 != $? ] ; then
    echo "Error:  expected excessive hit count message but didn't find it"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
if [ ! -e out2.info ] ; then
    echo "Error: expected --keep-going to continue execution - but out2.info not found"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
diff out.info out2.info
if [ 0 != $? ] ; then
    echo "Error: mismatched output generated"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -o out.info -a format.info --ignore format,format,negative,negative,excessive --rc excessive_count_threshold=1000000 2>&1 | tee warnExcessive.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected to warn"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
COUNT=`grep -c -E 'WARNING: \(excessive\) Unexpected excessive .+ count' warnExcessive.log`
if [ $COUNT -lt 3 ] ; then
    echo "Error:  unexpectedly found only $COUNT messages"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#
# Section structure.
#
# Where a record appears in a .info file is part of the format, not just a
# convention:
#
#   tracefile := ( comment | blank )*  section*
#   section   := 'TN:'?  'SF:'  ( coverpoint | 'VER:' | comment | blank )*
#               'end_of_record'
#
# 'TN:' names the testcase whose data the section holds, so it has to precede
# it; a coverpoint record means nothing outside a section.  Anything which does
# not fit is an ERROR_FORMAT.  Every case below used to be accepted, and all but
# the first two SILENTLY - records after an 'end_of_record' were added to the
# section which had just ended, a repeated 'end_of_record' doubled the section's
# counts, a mid-section 'TN:' discarded the branch data read so far, an 'SF:'
# with no intervening 'end_of_record' dropped the first file outright, and a
# missing final 'end_of_record' dropped the last one.
#
# Each case is run twice.  Once expecting the error, which is what a user sees;
# then again with '--ignore format', which pins down what the reader RECOVERS -
# malformed input that a user chooses to accept must still yield the data that
# was actually there, and nothing else.
#

# each entry:  name : the message the reader must produce
FORMAT_CASES=(
    "before_sf:\"before_sf.info\":1: unexpected .info file record 'DA:2,1' outside of a section:  expected 'TN:' or 'SF:'"
    "ver_before_sf:\"ver_before_sf.info\":1: unexpected .info file record 'VER:abc' outside of a section:  expected 'TN:' or 'SF:'"
    "after_eor:\"after_eor.info\":8: unexpected .info file record 'DA:4,99' outside of a section:  expected 'TN:' or 'SF:' - the section for 'test.c' ended at line 7"
    "double_eor:\"double_eor.info\":8: 'end_of_record' with no open section - the section for 'test.c' ended at line 7"
    "tn_inside:\"tn_inside.info\":5: 'TN:test_b' record must precede the 'SF:' record of its section - in the section for 'test.c' beginning at line 2"
    "nested_sf:\"nested_sf.info\":7: file record 'SF:other.c' found inside the section for 'test.c' beginning at line 2 - missing 'end_of_record'"
    "no_eor:\"no_eor.info\":6: unexpected end of file: missing 'end_of_record' for the section for 'test.c' beginning at line 2"
    "junk_in_section:\"junk_in_section.info\":4: unexpected .info file record 'XYZ:1,2' in the section for 'test.c' beginning at line 2"
    "no_tag:\"no_tag.info\":4: unexpected .info file record 'garbage' in the section for 'test.c' beginning at line 2"
    "bad_payload:\"bad_payload.info\":4: unexpected .info file record 'DA:x,1' in the section for 'test.c' beginning at line 2"
)

# a record which belongs to no section, before any 'SF:'
cat > before_sf.info <<'EOF'
DA:2,1
TN:test_a
SF:test.c
DA:2,7
DA:3,4
LF:2
LH:2
end_of_record
EOF

# ...and 'VER:', which reaches the same check by a different route:  the reader
# has no TraceInfo to record the version against until a section is open
cat > ver_before_sf.info <<'EOF'
VER:abc
TN:test_a
SF:test.c
DA:2,7
DA:3,4
LF:2
LH:2
end_of_record
EOF

# a record which belongs to no section, after the section closed
cat > after_eor.info <<'EOF'
TN:test_a
SF:test.c
DA:2,7
DA:3,4
LF:2
LH:2
end_of_record
DA:4,99
EOF

# a repeated 'end_of_record':  closing a section which is not open
cat > double_eor.info <<'EOF'
TN:test_a
SF:test.c
DA:2,7
DA:3,4
LF:2
LH:2
end_of_record
end_of_record
EOF

# 'TN:' inside a section, where it can no longer name the data's testcase
cat > tn_inside.info <<'EOF'
TN:test_a
SF:test.c
BRDA:3,0,0,1
BRDA:3,0,1,0
TN:test_b
BRF:2
BRH:1
DA:2,7
DA:3,4
LF:2
LH:2
end_of_record
EOF

# a second 'SF:' with no intervening 'end_of_record'
cat > nested_sf.info <<'EOF'
TN:test_a
SF:test.c
DA:2,7
DA:3,4
LF:2
LH:2
SF:other.c
DA:1,9
LF:1
LH:1
end_of_record
EOF

# end of file with the section still open
cat > no_eor.info <<'EOF'
TN:test_a
SF:test.c
DA:2,7
DA:3,4
LF:2
LH:2
EOF

# a record whose tag means nothing.  The reader identifies a record by the tag
#  before its first ':', so this is the case which reaches neither a record
#  handler nor the count records the reader ignores.
cat > junk_in_section.info <<'EOF'
TN:test_a
SF:test.c
DA:2,7
XYZ:1,2
DA:3,4
LF:2
LH:2
end_of_record
EOF

# ...and a record with no ':' at all, which has no tag to identify it by
cat > no_tag.info <<'EOF'
TN:test_a
SF:test.c
DA:2,7
garbage
DA:3,4
LF:2
LH:2
end_of_record
EOF

# ...and a record whose tag IS one the reader knows, but whose payload does not
#  fit that record's format.  Recognizing the tag is only how the reader picks
#  which format to check:  a tag it knows with a payload it cannot parse is
#  still an unexpected record, reported exactly as one with an unknown tag is.
cat > bad_payload.info <<'EOF'
TN:test_a
SF:test.c
DA:2,7
DA:x,1
DA:3,4
LF:2
LH:2
end_of_record
EOF

for CASE in "${FORMAT_CASES[@]}" ; do
    NAME=${CASE%%:*}
    MSG=${CASE#*:}
    rm -f ${NAME}_out.info
    # the malformed input is an error, and processing stops
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $NAME.info 2>&1 | tee $NAME.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "Error:  expected a format error for '$NAME' but didn't see it"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    # the message names the .info file, the line where the problem was found
    #  and - where there is one - the source file whose section is involved and
    #  the line where that section began or ended
    grep -qF "$MSG" $NAME.log
    if [ 0 != $? ] ; then
        echo "Error:  wrong or missing format message for '$NAME'; expected:"
        echo "  $MSG"
        cat $NAME.log
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    # ...and the same input, accepted:  the error becomes a warning and the
    #  reader recovers
    $COVER $LCOV_TOOL $LCOV_OPTS -o ${NAME}_out.info -a $NAME.info \
        --ignore format,empty,empty 2>&1 | tee ${NAME}_ignore.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "Error:  unexpected error from lcov -a for '$NAME'"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    grep -qF "WARNING: (format) $MSG" ${NAME}_ignore.log
    if [ 0 != $? ] ; then
        echo "Error:  expected the format message as a warning for '$NAME'"
        cat ${NAME}_ignore.log
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    if [ ! -e ${NAME}_out.info ] ; then
        echo "Error:  expected '$NAME' to be recovered - but no output written"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

# What each case must recover.  The records which were in the right place
#  survive; the ones which were not are discarded, never attributed to a
#  neighbouring section.
for CASE in before_sf ver_before_sf after_eor double_eor no_eor \
            junk_in_section no_tag bad_payload ; do
    # 'DA:2,7' rather than 'DA:2,14' for double_eor:  closing the section twice
    #  used to union the line data into the summary a second time
    for EXPECT in 'SF:test.c' 'DA:2,7' 'DA:3,4' 'LF:2' 'LH:2' ; do
        grep -qxF "$EXPECT" ${CASE}_out.info
        if [ 0 != $? ] ; then
            echo "Error:  '$CASE' output is missing '$EXPECT':"
            cat ${CASE}_out.info
            if [ $KEEP_GOING == 0 ] ; then
                exit 1
            fi
        fi
    done
done
# the stray record itself must NOT have been kept
for NOT in 'DA:2,1' 'DA:4,99' ; do
    for CASE in before_sf after_eor ; do
        grep -qxF "$NOT" ${CASE}_out.info
        if [ 0 == $? ] ; then
            echo "Error:  '$CASE' kept the out-of-section record '$NOT':"
            cat ${CASE}_out.info
            if [ $KEEP_GOING == 0 ] ; then
                exit 1
            fi
        fi
    done
done
grep -q '^VER:' ver_before_sf_out.info
if [ 0 == $? ] ; then
    echo "Error:  kept a 'VER:' record which preceded the 'SF:' record"
    cat ver_before_sf_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# the ignored 'TN:' must not have renamed the testcase, and the branch data
#  which preceded it must still be there
for EXPECT in 'TN:test_a' 'BRDA:3,0,0,1' 'BRDA:3,0,1,0' 'BRF:2' 'BRH:1' ; do
    grep -qxF "$EXPECT" tn_inside_out.info
    if [ 0 != $? ] ; then
        echo "Error:  'tn_inside' output is missing '$EXPECT':"
        cat tn_inside_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
grep -q '^TN:test_b' tn_inside_out.info
if [ 0 == $? ] ; then
    echo "Error:  a mid-section 'TN:' record renamed the testcase:"
    cat tn_inside_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# closing the unterminated section keeps its file:  BOTH are in the output
for EXPECT in 'SF:test.c' 'SF:other.c' 'DA:2,7' 'DA:1,9' ; do
    grep -qxF "$EXPECT" nested_sf_out.info
    if [ 0 != $? ] ; then
        echo "Error:  'nested_sf' output is missing '$EXPECT':"
        cat nested_sf_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

#
# Comment records.  A comment is legal anywhere - inside a section or outside
# one - and is simply ignored:  it is not coverage data, so there is nothing to
# keep and nothing is written back out.  No errors at all here; this is
# well-formed input.
#
cat > comments.info <<'EOF'
#outside, before any section
TN:test_a
SF:test.c
#inside, before the data
DA:2,7
#inside, after the data
DA:3,4
LF:2
LH:2
end_of_record
#outside, after the section
EOF

$COVER $LCOV_TOOL $LCOV_OPTS -o comments_out.info -a comments.info \
    --ignore empty,empty 2>&1 | tee comments.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error reading comment records"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
COUNT=`grep -c '(format)' comments.log`
if [ "$COUNT" != 0 ] ; then
    echo "Error:  comment records are legal anywhere, but got $COUNT messages"
    cat comments.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# the coverage data around them was read, and no comment survives
for EXPECT in 'SF:test.c' 'DA:2,7' 'DA:3,4' ; do
    grep -qxF "$EXPECT" comments_out.info
    if [ 0 != $? ] ; then
        echo "Error:  'comments' output is missing '$EXPECT':"
        cat comments_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done
COUNT=`grep -c '^#' comments_out.info`
if [ "$COUNT" != 0 ] ; then
    echo "Error:  comment records are ignored, but $COUNT were written"
    cat comments_out.info
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

#
# Records which are ignored rather than rejected.  The count records ('LF:',
# 'LH:', 'FNF:', ...) carry nothing the reader keeps - it recomputes them all -
# and they have always been recognized loosely, by prefix.  So a count record
# with something appended to its tag, or one with no ':' at all, is ignored
# rather than reported, and 'end_of_record' closes the section even with text
# after it.  None of that is worth relying on, but the reader identifies records
# by the tag before their first ':', which is exactly what these three inputs
# do not have - so this pins down that they are still ignored and not turned
# into format errors.
#
cat > ignored.info <<'EOF'
TN:test_a
SF:test.c
DA:2,7
DA:3,4
LFOO:9
MCH
end_of_record:trailing
EOF

$COVER $LCOV_TOOL $LCOV_OPTS -o ignored_out.info -a ignored.info \
    --ignore empty,empty 2>&1 | tee ignored.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error reading ignored records"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
COUNT=`grep -c '(format)' ignored.log`
if [ "$COUNT" != 0 ] ; then
    echo "Error:  these records are ignored, but got $COUNT messages"
    cat ignored.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for EXPECT in 'SF:test.c' 'DA:2,7' 'DA:3,4' ; do
    grep -qxF "$EXPECT" ignored_out.info
    if [ 0 != $? ] ; then
        echo "Error:  'ignored' output is missing '$EXPECT':"
        cat ignored_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

#
# Trailing whitespace.  It comes off the record before the record is looked at,
# so a file written with DOS line endings - or with padding after the last
# field - reads the same as a clean one.  Worth its own case because that strip
# is guarded on the last character of the line (after the chomp, essentially no
# line has any trailing space, so running the substitution over every line is
# most of its cost):  the guard has to fire on exactly the lines which need it.
#
printf 'TN:test_a\r\nSF:test.c\r\nDA:2,7   \r\nDA:3,4\t\r\nBRDA:3,0,0,1 \r\nBRDA:3,0,1,0\r\nend_of_record \r\n' > crlf.info

$COVER $LCOV_TOOL $LCOV_OPTS -o crlf_out.info -a crlf.info \
    --ignore empty,empty 2>&1 | tee crlf.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error reading a file with DOS line endings"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
COUNT=`grep -c '(format)' crlf.log`
if [ "$COUNT" != 0 ] ; then
    echo "Error:  trailing whitespace is stripped, but got $COUNT messages"
    cat crlf.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# the padded records are there, and the padding is not part of the data
for EXPECT in 'SF:test.c' 'DA:2,7' 'DA:3,4' 'BRDA:3,0,0,1' 'BRDA:3,0,1,0' ; do
    grep -qxF "$EXPECT" crlf_out.info
    if [ 0 != $? ] ; then
        echo "Error:  'crlf' output is missing '$EXPECT':"
        cat crlf_out.info
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

#
# Records of a cover type which is turned off.
#
# Such a record is dropped as soon as its tag is recognized - before the
# regular expression which would parse it is run - because there is nowhere to
# put the data and that expression is essentially the whole cost of reading the
# record.  It is also the whole of the validation, so the visible consequence is
# that a malformed record of a disabled type is accepted in silence.  Each case
# below is run twice: with its cover type enabled, where the malformed record is
# an ERROR_FORMAT, and with it disabled, where the same input is read cleanly.
#
# What is NOT conditional is where a record appears: the type is checked after
# the section structure is, so a coverpoint record outside any section is still
# an error with its cover type turned off.  That is the last case.
#

BASE_OPTS="$PARALLEL $PROFILE"

# each entry, '|' separated:  name, the option which enables the cover type, the
#  option which disables it (MC/DC is off by default and has no '--no-' option),
#  the message the reader must produce when the type is enabled
SKIP_CASES=(
    "skip_brda|--branch-coverage|--no-branch-coverage|\"skip_brda.info\":4: unexpected .info file record 'BRDA:x,0,0,1' in the section for 'test.c' beginning at line 2"
    "skip_mcdc|--mcdc-coverage||\"skip_mcdc.info\":4: unexpected .info file record 'MCDC:x,3,t,1,0,a>0' in the section for 'test.c' beginning at line 2"
    "skip_fn|--function-coverage|--no-function-coverage|\"skip_fn.info\":4: unexpected .info file record 'FN:x,myFunc' in the section for 'test.c' beginning at line 2"
)

# a malformed 'BRDA:' record - the tag is one the reader knows, the payload is
#  not something it can parse
cat > skip_brda.info <<'EOF'
TN:test_a
SF:test.c
DA:2,7
BRDA:x,0,0,1
DA:3,4
end_of_record
EOF

# ...and the same for 'MCDC:'
cat > skip_mcdc.info <<'EOF'
TN:test_a
SF:test.c
DA:2,7
MCDC:x,3,t,1,0,a>0
DA:3,4
end_of_record
EOF

# ...and for 'FN:', whose cover type is the one which is enabled by default
cat > skip_fn.info <<'EOF'
TN:test_a
SF:test.c
DA:2,7
FN:x,myFunc
DA:3,4
end_of_record
EOF

for CASE in "${SKIP_CASES[@]}" ; do
    NAME=${CASE%%|*}
    REST=${CASE#*|}
    ENABLE=${REST%%|*}
    REST=${REST#*|}
    DISABLE=${REST%%|*}
    MSG=${REST#*|}

    # with the cover type enabled, the malformed record is an error
    $COVER $LCOV_TOOL $BASE_OPTS $ENABLE --summary $NAME.info 2>&1 | tee $NAME.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "Error:  expected a format error for '$NAME $ENABLE'"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    grep -qF "$MSG" $NAME.log
    if [ 0 != $? ] ; then
        echo "Error:  wrong or missing format message for '$NAME $ENABLE'; expected:"
        echo "  $MSG"
        cat $NAME.log
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    # ...and with it disabled, the record is dropped without being looked at:
    #  no message, no error exit - and the data which is still wanted is read
    rm -f ${NAME}_out.info
    #  ('empty' is ignored because these inputs carry only the one cover type
    #   under test, plus line data)
    $COVER $LCOV_TOOL $BASE_OPTS $DISABLE -o ${NAME}_out.info -a $NAME.info \
        --ignore empty,empty 2>&1 | tee ${NAME}_skip.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "Error:  unexpected error from lcov -a for '$NAME $DISABLE'"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    COUNT=`grep -c '(format)' ${NAME}_skip.log`
    if [ "$COUNT" != 0 ] ; then
        echo "Error:  '$NAME $DISABLE' should not check the record, but got $COUNT messages"
        cat ${NAME}_skip.log
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    for EXPECT in 'SF:test.c' 'DA:2,7' 'DA:3,4' ; do
        grep -qxF "$EXPECT" ${NAME}_out.info
        if [ 0 != $? ] ; then
            echo "Error:  '$NAME $DISABLE' output is missing '$EXPECT':"
            cat ${NAME}_out.info
            if [ $KEEP_GOING == 0 ] ; then
                exit 1
            fi
        fi
    done
done

# A well-formed record of a disabled cover type, in a place where no coverpoint
#  record may appear.  Dropping the record because its type is off must not
#  swallow the structural error: the type is checked only after the record has
#  been found to be somewhere it belongs.
cat > skip_place.info <<'EOF'
BRDA:2,0,0,1
TN:test_a
SF:test.c
DA:2,7
end_of_record
EOF

MSG="\"skip_place.info\":1: unexpected .info file record 'BRDA:2,0,0,1' outside of a section:  expected 'TN:' or 'SF:'"
$COVER $LCOV_TOOL $BASE_OPTS --no-branch-coverage --summary skip_place.info 2>&1 | \
    tee skip_place.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "Error:  expected a format error for an out-of-section 'BRDA:' record"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -qF "$MSG" skip_place.log
if [ 0 != $? ] ; then
    echo "Error:  wrong or missing message for an out-of-section 'BRDA:' record; expected:"
    echo "  $MSG"
    cat skip_place.log
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    generate_coverage 'format' $LOCAL_COVERAGE 0
fi
