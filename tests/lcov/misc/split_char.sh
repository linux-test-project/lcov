#!/usr/bin/env bash
set +x

# ============================================================================
# The 'split_char' RC option.
#
# 'split_char' is documented as "the character (or regexp) used to split
#   list-like parameters which have been passed as a single string", and it
#   exists precisely so that a list whose elements contain a comma can be
#   passed with some other delimiter.  It was handed straight to 'split',
#   which takes a pattern - so the delimiter a user actually reaches for in
#   that situation, '|', was read as the empty alternation:  it matches the
#   empty string, so 'split' returned one element per character of the list
#   and every option value became a single letter.  For '--ignore-errors'
#   that is an immediate "unknown argument" death; for the options which
#   accept anything it is silent.
#
# So a single character is now taken literally, whatever it means to the
#   regexp engine, and anything longer is taken as a regexp - which the
#   documentation also allows - but is checked: it has to compile, and it must
#   not match the empty string, because that is the failure above by another
#   route.  A value which does not pass is reported (as an ignorable 'usage'
#   error, since the delimiter is needed before the suppression list itself
#   can be split) and the default ',' is used instead.
#
# The related case is the file extension lists, which are joined into a regexp
#   alternation with the same delimiter.  Those are deliberately regexps - the
#   default RTL list is 'v|vh|sv|vhdl?' - so they are not quoted; but an
#   alternation which does not compile is now reported when it is set rather
#   than from inside 'is_language', at the first file name looked at.
#
# The cases:
#   1. the default ',' still splits a two-element list
#   2. '--rc split_char=|' splits a two-element list - the case which used to
#      die - and both elements take effect
#   3. a multi-character value is still a regexp
#   4. an empty value is rejected
#   5. a value which matches the empty string is rejected
#   6. a value which is not a valid regexp is rejected
#   7. a rejected value leaves the default in place, so the run continues
#      when 'usage' is ignored
#   8. an extension list which is not a valid alternation is rejected, and one
#      which is a valid regexp is still accepted
# ============================================================================

source ../../common.tst

# $LCOV comes from the test Makefile, so it is unset when this script is run
# standalone (notably ./split_char.sh --coverage).  Fall back to the tool in
# $LCOV_HOME, under $COVER so a --coverage run instruments it.
if [ 'x' == "x$LCOV_TOOL" ] ; then
        LCOV_TOOL=${LCOV_HOME}/bin/lcov
fi
if [ 'x' == "x$LCOV" ] ; then
        LCOV="$COVER $LCOV_TOOL"
fi

rm -f split_char.c split_char.info sc_*.log

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

# --------------------------------------------------------------------------
# the input:  a four-line source file and a trace which mentions line 9, so
# that '--filter line' has something to say about it.  The 'range' message is
# an error by default, so a run which reports it is one whose
# '--ignore-errors' list was split correctly
# --------------------------------------------------------------------------
cat >split_char.c <<'EOF'
int foo(int a)
{
    return a + 1;
}
EOF

cat >split_char.info <<'EOF'
TN:t
SF:split_char.c
DA:1,1
DA:3,1
DA:9,0
LF:3
LH:2
end_of_record
EOF

# Two separately-parsed list options, each given two elements, and each
#   checked on its *second* element - the one which is lost if the delimiter
#   does not split:
#   --ignore-errors 'usage<sep>range' - the out-of-range line above is an
#     error unless 'range' was seen, so the run exits 0 with 'range: 1' in the
#     message summary only if it was
#   --filter 'line<sep>range' - the range filter removes that line, so the
#     line total drops from 3 to 2 only if 'range' was seen
# Two runs, because the second suppresses the message the first looks for.
check_split()
{
        # $1 = label, $2 = log prefix, $3.. = options which set the delimiter
        local label=$1 log=$2 sep=$3
        shift 3
        # '--filter line' so that the source file is read at all - the
        #   out-of-range line is noticed while filtering.  It is a one-element
        #   list, so it says nothing about the delimiter
        $LCOV --summary split_char.info "$@" --filter line \
                --ignore-errors "usage${sep}range" >"$log-ign.log" 2>&1
        local rc=$?
        cat "$log-ign.log"
        if [ 0 != $rc ] ; then
                fail "$label" "lcov exited $rc"
        elif ! grep -E -q '^ +range: 1$' "$log-ign.log" ; then
                fail "$label" "'--ignore-errors' list was not split"
        fi

        $LCOV --summary split_char.info "$@" --ignore-errors range \
                --filter "line${sep}range" >"$log-filt.log" 2>&1
        rc=$?
        cat "$log-filt.log"
        if [ 0 != $rc ] ; then
                fail "$label" "lcov exited $rc with a filter list"
        elif ! grep -E -q '^ +lines\.+: 100\.0% \(2 of 2 lines\)$' \
                "$log-filt.log" ; then
                fail "$label" "'--filter' list was not split"
        fi
}

# a rejected value has to say so, and has to leave a usable delimiter behind:
# 'usage' is ignored here, which is only possible if that list was split with
# the default ','
check_rejected()
{
        # $1 = label, $2 = log file, $3 = the value, $4 = expected complaint
        local label=$1 log=$2 value=$3 expect=$4
        $LCOV --summary split_char.info --rc split_char="$value" \
                --ignore-errors usage,range >"$log" 2>&1
        local rc=$?
        cat "$log"
        if [ 0 != $rc ] ; then
                fail "$label" "lcov exited $rc - the default was not restored"
        fi
        for pattern in "(usage) 'split_char' value" "$expect" \
                "using the default ',' instead" ; do
                if ! grep -F -q -e "$pattern" "$log" ; then
                        fail "$label" "message does not mention: $pattern"
                fi
        done
}

# ----------------------------------------------------------------------
echo "*** 1. the default separator"
# ----------------------------------------------------------------------
check_split default sc_default ','

# ----------------------------------------------------------------------
echo "*** 2. --rc split_char='|'"
# ----------------------------------------------------------------------
# the case which used to die with "unknown argument for --ignore-errors: 'u'"
check_split bar sc_bar '|' --rc split_char='|'

# ----------------------------------------------------------------------
echo "*** 3. a multi-character value is a regexp"
# ----------------------------------------------------------------------
# the value is a character class, and the lists below are split on ';' - which
#   is only possible if it was compiled as a pattern.  Quoted as a literal it
#   would match nothing at all
check_split regexp sc_regexp ';' --rc split_char='[:;]'

# ----------------------------------------------------------------------
echo "*** 4-6. values which are rejected"
# ----------------------------------------------------------------------
check_rejected empty sc_empty.log '' 'is empty'
check_rejected blank sc_blank.log '\s*' 'matches the empty string'
check_rejected badre sc_badre.log '(a' 'is not a valid regexp: Unmatched ('

# ----------------------------------------------------------------------
echo "*** 8. the extension lists are alternations"
# ----------------------------------------------------------------------
# '(cpp' is not a valid alternative;  the old code noticed only when a file
#   name was matched against it - if one ever was
$LCOV --summary split_char.info --rc c_file_extensions='c,h,(cpp' \
        >sc_badext.log 2>&1
if [ 0 == $? ] ; then
        cat sc_badext.log
        fail badext "expected an uncompilable extension list to be rejected"
fi
cat sc_badext.log
for pattern in "invalid c_file_extensions 'c,h,(cpp'" 'Unmatched (' ; do
        if ! grep -F -q -e "$pattern" sc_badext.log ; then
                fail badext "message does not mention: $pattern"
        fi
done

# ...but a list which is a regexp is meant to work:  that is what the default
#   RTL list is
$LCOV --summary split_char.info --rc rtl_file_extensions='v,vh,vhdl?' \
        >sc_goodext.log 2>&1
if [ 0 != $? ] ; then
        cat sc_goodext.log
        fail goodext "a regexp extension list was rejected"
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
        echo "Tests passed"
else
        echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
        generate_coverage 'split_char' $LOCAL_COVERAGE 0
fi

exit $STATUS
