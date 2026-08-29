#!/bin/bash
set +x

# ============================================================================
# The arguments of the sample callback scripts which take a list:
#   'scripts/select.pm' and 'scripts/simplify.pm'.
#
# Both are documented as taking a separator character and a list of things
#   separated by it, and both then hand that character to 'split' - which
#   takes a pattern.  For the default ',' the two are the same thing, so
#   nothing in the suite noticed;  for any of the characters a user would
#   reach for when the list elements contain a comma - '|' above all, which
#   perl regexps also contain - they are not.  A '|' pattern matches the empty
#   string, so 'split' returns one element per character and every one of them
#   is a criterion which cannot match anything.  That failure is silent:  the
#   run succeeds, the report is written, and the only trace is the match-count
#   summary at the end, which says '0' beside names nobody asked for.
#
# 'select.pm' has a second, related problem:  it validates a '--tla' name by
#   matching it as an unanchored regexp against the known TLA names, but
#   selects with 'eq'.  So a name which is merely a substring of a TLA - 'C',
#   'UB', or any single character of the '|' split above - passes validation
#   and then matches nothing.
#
# And 'simplify.pm' stored the replacement half of its 's///' pattern as a
#   plain string, which 's/$re/$text/g' inserts literally:  a pattern with
#   capture groups put '${1}' in the report rather than what it captured.
#   'lcovutil::verify_regexp_patterns' accepts such a pattern - it is a
#   perfectly good substitution - so this too was silent.
#
# The cases:
#   1. select.pm '--separator |' with a two-TLA list:  two criteria, and the
#      one which is in the report has a nonzero count
#   2. select.pm '--tla C':  rejected, rather than accepted and unmatchable
#   3. select.pm '--tla' with the default separator still works - the fix is
#      to how the separator is used, not to what it is
#   4. simplify.pm with capture groups in the replacement
#   5. simplify.pm with a plain replacement, and an unused pattern reported -
#      the hit counter of a pattern lives in the same list as the compiled
#      pattern, so a change to that list has to keep 'warn_pattern_list'
#      working
#
# A second, unrelated group of cases:  a script-form callback which fails.
#   'ScriptCaller' reads the callback's answer off a pipe;  for the callbacks
#   whose answer is a line of text - extract_version, resolve, simplify,
#   history - the pipe used never to be closed at all, so the callback's exit
#   status was never looked at.  A callback which printed something and then
#   exited non-zero, or which died from a signal, was believed:  whatever it
#   had managed to print became the file's version, the resolved path, or the
#   simplified name, and the run reported success.  'simplify' was the one
#   which said anything, and all it said was "broken 'simplify' callback" -
#   without naming the callback or saying what was wrong with it.
#
#   6. a '--version-script' which answers and then exits non-zero
#   7. a '--resolve-script' which answers and then exits non-zero
#   8. a '--simplify-script' which exits zero without answering:  the message
#      names the command and says what it did
#   9. a '--simplify-script' which answers and then exits non-zero
#  (the fourth of these callbacks, 'history', is an lcov option - see
#   tests/lcov/scheduling)
# ============================================================================

source ../../common.tst

GENHTML_OPTS="--function-coverage $PARALLEL $PROFILE"

rm -rf *.info *.log *.json *.udiff *.counts proj rpt_* \
    perlcov.info pycov.info __pycache__ *.cb

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

# the criteria half of the match-count summary select.pm prints when it is
#   done.  Not the coverpoint total on the line above it:  how many
#   coverpoints the report generator offered the callback depends on which of
#   them were selected, so it is not the same from case to case
select_counts()
{
    sed -n -e '/^select.pm criteria match counts:$/,$p' $1 |
        grep -E '^ +' | sed -e 's/^ *//' | grep -v ' coverpoint'
}

# --------------------------------------------------------------------------
# the inputs:  one source file, a baseline and a current trace which differ,
# and a udiff which says so - so the report has both GNC (new code, covered)
# and UBC lines, which is what gives '--tla' something to select.
# The function name carries the string the simplify patterns rewrite
# --------------------------------------------------------------------------
mkdir -p proj

cat >proj/foo.c <<'EOF'
int xfoo_bary(int a)
{
    if (a > 0)
        return a + 1;
    return -a;
}
EOF

cat >baseline.info <<'EOF'
TN:sa
SF:proj/foo.c
FN:1,6,xfoo_bary
FNDA:2,xfoo_bary
FNF:1
FNH:1
DA:1,2
DA:3,2
DA:4,2
DA:5,0
LF:4
LH:3
end_of_record
EOF

cat >current.info <<'EOF'
TN:sa
SF:proj/foo.c
FN:1,6,xfoo_bary
FNDA:3,xfoo_bary
FNF:1
FNH:1
DA:1,3
DA:3,3
DA:4,3
DA:5,0
LF:4
LH:3
end_of_record
EOF

cat >diff.udiff <<'EOF'
--- proj/foo.c
+++ proj/foo.c
@@ -1,6 +1,6 @@
 int xfoo_bary(int a)
 {
     if (a > 0)
-        return a;
+        return a + 1;
     return -a;
 }
EOF

DIFF_OPTS="--baseline-file baseline.info --diff-file diff.udiff"

# ----------------------------------------------------------------------
echo "*** 1. select.pm --separator '|' with a two-element --tla list"
# ----------------------------------------------------------------------
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_sep current.info $DIFF_OPTS \
    --select-script $SELECT,--separator,'|',--tla,'GNC|UNC' 2>&1 | tee sep.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail sep "genhtml failed with '--separator |'"
fi
select_counts sep.log > sep.counts
cat sep.counts
# exactly the two names which were asked for.  Split as a pattern, '|' matches
#   the empty string, so this said 'G', 'N', 'C', '|', 'U', 'N', 'C' instead
if ! diff - sep.counts <<'EOF' ; then
tla:
GNC : 1
UNC : 0
EOF
    fail sep "'--separator |' did not split the list into two criteria"
fi

# ----------------------------------------------------------------------
echo "*** 2. select.pm rejects a --tla which is only part of a TLA"
# ----------------------------------------------------------------------
# 'C' is a substring of CBC, DCB, ... and a TLA of nothing.  Selection
#   compares with 'eq', so accepting this name buys a run which quietly
#   selects no coverpoint at all
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_badtla current.info $DIFF_OPTS \
    --select-script $SELECT,--tla,C 2>&1 | tee badtla.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail badtla "expected an incomplete TLA name to be rejected"
fi
for pattern in 'ERROR: (package)' "invalid tla 'C'" ; do
    if ! grep -F -q -e "$pattern" badtla.log ; then
        fail badtla "message does not mention: $pattern"
    fi
done
# the constructor's die is quoted into the 'unable to create callback' message
#   without the tool name and severity prefix which the die handler puts on
#   every die - including one which an 'eval' catches
if grep -E -q 'ERROR: .*(ERROR|WARNING): ' badtla.log ; then
    fail badtla "message prefix appears twice"
fi

# ----------------------------------------------------------------------
echo "*** 3. the default separator is unchanged"
# ----------------------------------------------------------------------
# a comma cannot be handed through '--select-script', whose own argument list
#   is comma separated - which is why '--separator' exists at all - so the
#   default path is reached by repeating the option:  the two names are joined
#   with the default separator and split again
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_comma current.info $DIFF_OPTS \
    --select-script $SELECT,--tla,GNC,--tla,UBC 2>&1 | tee comma.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail comma "genhtml failed with the default separator"
fi
select_counts comma.log > comma.counts
cat comma.counts
if ! diff - comma.counts <<'EOF' ; then
tla:
GNC : 1
UBC : 1
EOF
    fail comma "the default separator no longer splits the list"
fi

# ----------------------------------------------------------------------
echo "*** 4. simplify.pm with capture groups in the replacement"
# ----------------------------------------------------------------------
# the report is the only place a simplified name appears - the coverage
#   database keeps the real one - so the function detail pages are what has to
#   be looked at
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_capture current.info \
    --simplify-script "${SCRIPT_DIR}/simplify.pm,--re,s/(foo)_(bar)/\${2}-\${1}/g" \
    2>&1 | tee capture.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail capture "genhtml failed with a capture group in the replacement"
fi
NAMES=`grep -h -o 'x[a-zA-Z${}0-9_-]*y' rpt_capture/proj/foo.c.func.html |
       sort -u`
echo "simplified name(s): $NAMES"
if [ "xbar-fooy" != "$NAMES" ] ; then
    fail capture "expected 'xbar-fooy', found '$NAMES'"
fi

# ----------------------------------------------------------------------
echo "*** 5. simplify.pm with a plain replacement, and an unused pattern"
# ----------------------------------------------------------------------
# two patterns, applied in order:  the first rewrites the name, the second
#   matches nothing.  The unused one has to be reported - which it can only be
#   if each pattern's hit count survived alongside the compiled pattern
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_plain current.info \
    --simplify-script "${SCRIPT_DIR}/simplify.pm,--re,s/foo_bar/plain/g,--re,s/never_here/x/g" \
    --ignore unused 2>&1 | tee plain.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail plain "genhtml failed with a plain replacement"
fi
NAMES=`grep -h -o 'x[a-zA-Z${}0-9_-]*y' rpt_plain/proj/foo.c.func.html | sort -u`
echo "simplified name(s): $NAMES"
if [ "xplainy" != "$NAMES" ] ; then
    fail plain "expected 'xplainy', found '$NAMES'"
fi
for pattern in "'simplify' pattern 's/never_here/x/g' is unused" \
    "1 of 2 'simplify' patterns were never applied" ; do
    if ! grep -F -q -e "$pattern" plain.log ; then
        fail plain "the unused pattern was not reported: $pattern"
    fi
done
if grep -F -q -e "'s/foo_bar/plain/g' is unused" plain.log ; then
    fail plain "a pattern which was applied was reported as unused"
fi

# --------------------------------------------------------------------------
# the failing callbacks:  each answers on stdout - so the answer is there to
# be believed - and then reports failure the only way a child process can
# --------------------------------------------------------------------------
cat >answer_then_fail.cb <<'EOF'
#!/bin/bash
# print the answer the caller asked for, then exit non-zero
echo "$ANSWER"
exit 3
EOF
cat >say_nothing.cb <<'EOF'
#!/bin/bash
# exit successfully without answering at all
exit 0
EOF
chmod +x answer_then_fail.cb say_nothing.cb

# an error from a callback is 'ERROR: (callback)', which is fatal unless
#   ignored:  a run which used to succeed now stops, so 'genhtml failed' is the
#   first thing each of these cases checks
check_callback_error()
{
    # $1 = scenario label, $2 = log file, $3 = the reason in the message,
    # $4.. = anything else which must appear
    local label=$1 log=$2 reason=$3
    shift 3
    for pattern in 'ERROR: (callback)' "$reason" "$@" ; do
        if ! grep -F -q -e "$pattern" $log ; then
            fail $label "message does not mention: $pattern"
        fi
    done
}

# ----------------------------------------------------------------------
echo "*** 6. a --version-script which answers and then fails"
# ----------------------------------------------------------------------
# the version is used to decide whether the source on disk is the source the
#   coverage data was gathered from, so believing a failed callback is worse
#   than having no version at all
ANSWER=made_up_version $COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_failver \
    current.info --version-script ./answer_then_fail.cb 2>&1 | tee failver.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail failver "expected genhtml to fail when the version callback did"
fi
check_callback_error failver failver.log 'extract_version callback failed' \
    'answer_then_fail.cb' 'non-zero exit status 3'

# ----------------------------------------------------------------------
echo "*** 7. a --resolve-script which answers and then fails"
# ----------------------------------------------------------------------
# the resolve callback is only consulted for a file which is not where the
#   coverage data says it is
sed -e 's/proj\/foo\.c/proj\/moved.c/' current.info > moved.info
ANSWER=proj/foo.c $COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_failresolve \
    moved.info --resolve-script ./answer_then_fail.cb 2>&1 | tee failresolve.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail failresolve "expected genhtml to fail when the resolve callback did"
fi
check_callback_error failresolve failresolve.log \
    'resolve_filename callback failed' 'answer_then_fail.cb' \
    'non-zero exit status 3'

# ----------------------------------------------------------------------
echo "*** 8. a --simplify-script which says nothing"
# ----------------------------------------------------------------------
# there is no answer to fall back on here, so this case always died - but the
#   message was just "broken 'simplify' callback", which says neither which
#   callback nor what it did
$COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_silent current.info \
    --simplify-script ./say_nothing.cb 2>&1 | tee silent.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail silent "expected genhtml to fail when the simplify callback said nothing"
fi
for pattern in "broken 'simplify' callback" 'say_nothing.cb' 'it said nothing' ; do
    if ! grep -F -q -e "$pattern" silent.log ; then
        fail silent "message does not mention: $pattern"
    fi
done

# ----------------------------------------------------------------------
echo "*** 9. a --simplify-script which answers and then fails"
# ----------------------------------------------------------------------
ANSWER=xsimplifiedy $COVER $GENHTML_TOOL $GENHTML_OPTS -o rpt_failsimplify \
    current.info --simplify-script ./answer_then_fail.cb 2>&1 |
    tee failsimplify.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail failsimplify "expected genhtml to fail when the simplify callback did"
fi
check_callback_error failsimplify failsimplify.log \
    'simplify callback failed' 'answer_then_fail.cb' 'non-zero exit status 3'

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'scriptargs' $LOCAL_COVERAGE 0
fi

exit $STATUS
