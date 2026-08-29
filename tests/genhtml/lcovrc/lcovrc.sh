#!/bin/bash
set +x

# The options which can only be set from a configuration file, and the example
#   configuration file the manual prints.
#
# Several genhtml options have no command line form at all, and a few more have
#   a command line form which cannot express every value lcovrc(5) documents:
#   'genhtml_show_owner_table = 0' and 'genhtml_show_navigation = 0' are both
#   documented, and neither is reachable from the command line, where the same
#   two options are flags.  So the config file is the only way to write them -
#   and it is the way nothing tested.
#
# The cases:
#   1. 'genhtml_show_owner_table'.  Every place which decides whether the owner
#      tables were asked for at all asks whether the option is *defined*, so the
#      documented off value - the string '0', which is defined - used to switch
#      the tables on.  With no '--annotate-script' that is not a report with
#      extra tables in it but a hard exit 255:  a site configuration file which
#      spells out the documented default breaks every run.
#      The value '1' is documented as equivalent to the bare flag, but was read
#      as "all owners" by the places which test it for truth and as "only owners
#      with un-exercised code" by the places which compare it with 'all', so the
#      summary table announced that it held all the code and then listed a
#      subset of it
#   2. 'genhtml_show_navigation'.  The same shape one step smaller: four places
#      ask whether it is defined and thirty ask whether it is true, so '0' put
#      an empty three-character 'TLA' column into every source view of a
#      non-differential report
#   3. the five '*_field_width' options.  None of them has a command line form,
#      so Getopt::Long never type checks them, and they are used as arithmetic:
#      a width of zero divides by zero once the data has to be distributed over
#      several lines, and a width perl does not read as a number formats to
#      nothing at all - up to 31 warnings, then a report and exit 0
#   4. the example configuration file in lcovrc(5), which a reader is invited to
#      copy.  One line of it had lost its comment marker, which no rst build can
#      notice, so the documented file was not a legal configuration file at all
#
# Cases 1 and 2 are checked by comparing whole reports:  the value under test is
#   correct exactly when it produces the report its documented equivalent
#   produces, and the control - the value documented as different - has to
#   produce a different one, or the comparison would prove nothing.

source ../../common.tst

GENHTML_OPTS="$PARALLEL $PROFILE"
ANNOTATE="--annotate-script `pwd`/annotate.pl"

rm -rf *.info *.log *.json src rc_* doc.rc o_* perlcov.info pycov.info \
    __pycache__

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

# the two reports, ignoring what changes from one run to the next:  the command
#   line which produced them, the time they were generated, and the profile
#   timings (the last three of these exist only under '--profile')
report_diff()
{
    diff -r -x cmd_line -x cmdline.html -x genhtml.json -x profile.html \
        -I '<td class="headerValue">[0-9][0-9-]* [0-9:]*</td>' $1 $2
}

# ----------------------------------------------------------------------
# the fixture:  four lines of code owned by three different people, exactly one
#   of whom has an un-exercised line.  That is what tells the two readings of
#   'show_owner_table = 1' apart:  'all' lists three owners and the bare flag
#   lists one
# ----------------------------------------------------------------------
mkdir -p src

cat >src/hello.c <<'EOF'
int hello(int a)
{
    if (a > 0)
        return a + 1;
    return -a;
}
EOF

cat >src/hello.c.owners <<'EOF'
alice
bob
carol
dave
alice
bob
EOF

cat >hello.info <<'EOF'
TN:lcovrc
SF:src/hello.c
FN:1,6,hello
FNDA:5,hello
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
LF:4
LH:3
end_of_record
EOF

# ----------------------------------------------------------------------
echo "*** 1a. 'genhtml_show_owner_table = 0' with no annotate script"
# ----------------------------------------------------------------------
# the value lcovrc(5) gives as the default, in a run which asks for nothing
#   else:  it has to behave like a run with no configuration file at all
$COVER $GENHTML_TOOL $GENHTML_OPTS -o o_plain hello.info 2>&1 | tee plain.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail plain "genhtml failed with no configuration file"
fi

echo 'genhtml_show_owner_table = 0' > rc_owner0
$COVER $GENHTML_TOOL $GENHTML_OPTS --config-file rc_owner0 -o o_owner0 \
    hello.info 2>&1 | tee owner0.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail owner0 "the documented default of 'show_owner_table' failed the run"
fi
if grep -F -q -e 'requires "--annotate-script"' owner0.log ; then
    fail owner0 "'show_owner_table = 0' asked for the owner tables"
fi
if [ -e o_owner0/index-owner.html ] ; then
    fail owner0 "'show_owner_table = 0' produced an owner table"
fi
if ! report_diff o_plain o_owner0 ; then
    fail owner0 "'show_owner_table = 0' is not the same as not asking"
fi

# ----------------------------------------------------------------------
echo "*** 1b. 'genhtml_show_owner_table' = 0, 1 and all, with an annotate script"
# ----------------------------------------------------------------------
# the three documented values against the two command line spellings they are
#   documented to be equivalent to
$COVER $GENHTML_TOOL $GENHTML_OPTS $ANNOTATE -o o_annotate hello.info 2>&1 |
    tee annotate.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail annotate "genhtml failed with an annotate script"
fi
$COVER $GENHTML_TOOL $GENHTML_OPTS $ANNOTATE --show-owners -o o_owners \
    hello.info 2>&1 | tee owners.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail owners "genhtml failed with '--show-owners'"
fi
$COVER $GENHTML_TOOL $GENHTML_OPTS $ANNOTATE --show-owners all -o o_ownersall \
    hello.info 2>&1 | tee ownersall.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail ownersall "genhtml failed with '--show-owners all'"
fi
# the control:  the two command line spellings are genuinely different reports,
#   so 'matches this one' is a statement with content
if report_diff o_owners o_ownersall >/dev/null 2>&1 ; then
    fail ownersall "'--show-owners' and '--show-owners all' agree"
fi

echo 'genhtml_show_owner_table = 1' > rc_owner1
echo 'genhtml_show_owner_table = all' > rc_ownerall
for value in 0 1 all ; do
    case $value in
        0)   expect=o_annotate ;;    # off, as documented
        1)   expect=o_owners ;;      # "equivalent to the --show-owners flag"
        all) expect=o_ownersall ;;
    esac
    $COVER $GENHTML_TOOL $GENHTML_OPTS $ANNOTATE --config-file rc_owner$value \
        -o o_rc_owner$value hello.info 2>&1 | tee rc_owner$value.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail rc_owner$value "'show_owner_table = $value' failed the run"
        continue
    fi
    if ! report_diff $expect o_rc_owner$value ; then
        fail rc_owner$value \
            "'show_owner_table = $value' does not match $expect"
    fi
done

# ..and a value which is none of the three is a usage error, not a fourth
#   reading of the option
$COVER $GENHTML_TOOL $GENHTML_OPTS $ANNOTATE --show-owners bogus -o o_bogus \
    hello.info 2>&1 | tee bogus.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail bogus "an unsupported '--show-owners' value did not fail the run"
fi
for pattern in 'ERROR: (usage)' "Unsupported '--show-owners' value 'bogus'" ; do
    if ! grep -F -q -e "$pattern" bogus.log ; then
        fail bogus "message does not mention: $pattern"
    fi
done
# ignored, it is the bare flag:  the tables were asked for, so produce the ones
#   the flag produces rather than a report which cannot decide
$COVER $GENHTML_TOOL $GENHTML_OPTS $ANNOTATE --show-owners bogus \
    --ignore-errors usage -o o_bogus_ignore hello.info 2>&1 |
    tee bogus_ignore.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail bogus_ignore "run with '--ignore-errors usage' failed"
fi
if ! report_diff o_owners o_bogus_ignore ; then
    fail bogus_ignore "an ignored bad value is not the bare flag"
fi

# ----------------------------------------------------------------------
echo "*** 2. 'genhtml_show_navigation'"
# ----------------------------------------------------------------------
echo 'genhtml_show_navigation = 0' > rc_nav0
echo 'genhtml_show_navigation = 1' > rc_nav1
$COVER $GENHTML_TOOL $GENHTML_OPTS --config-file rc_nav0 -o o_nav0 hello.info \
    2>&1 | tee nav0.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail nav0 "'show_navigation = 0' failed the run"
fi
if ! report_diff o_plain o_nav0 ; then
    fail nav0 "'show_navigation = 0' is not the same as not asking"
fi
# the control, again:  '= 1' is documented as a different report
$COVER $GENHTML_TOOL $GENHTML_OPTS --config-file rc_nav1 -o o_nav1 hello.info \
    2>&1 | tee nav1.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail nav1 "'show_navigation = 1' failed the run"
fi
if report_diff o_plain o_nav1 >/dev/null 2>&1 ; then
    fail nav1 "'show_navigation = 1' changed nothing"
fi

# ----------------------------------------------------------------------
echo "*** 3. the '*_field_width' options"
# ----------------------------------------------------------------------
# a zero and a value which is not a number, for each of the five.  Two of the
#   five used to divide by zero - but only when the coverage data was wide
#   enough to have to be wrapped - and the other three wrote a report and
#   exited 0 after up to 31 warnings, so exit status alone is not the whole
#   assertion:  a run which is rejected has to say which option was rejected
for key in line branch mcdc owner age ; do
    for value in 0 abc ; do
        echo "genhtml_${key}_field_width = $value" > rc_width
        $COVER $GENHTML_TOOL $GENHTML_OPTS --config-file rc_width \
            --branch-coverage --mcdc-coverage $ANNOTATE -o o_width \
            hello.info 2>&1 | tee width.log
        if [ 0 == ${PIPESTATUS[0]} ] ; then
            fail width "'${key}_field_width = $value' did not fail the run"
        fi
        if ! grep -F -q -e "genhtml_${key}_field_width = $value" width.log ; then
            fail width \
                "message does not name 'genhtml_${key}_field_width = $value'"
        fi
        if grep -q -e 'WARNING' width.log ; then
            fail width "'${key}_field_width = $value' warned instead"
        fi
        rm -rf o_width
    done
done

# ..and a width which is legal still is:  the check must reject nothing else,
#   and the option still has to do what it is for
echo 'genhtml_line_field_width = 20' > rc_width20
$COVER $GENHTML_TOOL $GENHTML_OPTS --config-file rc_width20 -o o_width20 \
    hello.info 2>&1 | tee width20.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail width20 "a legal 'line_field_width' failed the run"
fi
if report_diff o_plain o_width20 >/dev/null 2>&1 ; then
    fail width20 "a wider 'line_field_width' changed nothing"
fi

# ----------------------------------------------------------------------
echo "*** 4. the example configuration file from lcovrc(5)"
# ----------------------------------------------------------------------
RST=$LCOV_HOME/docs/man/lcovrc.rst
if [ ! -f $RST ] ; then
    # an installed tree has the built man page and not its source
    echo "skipping the example configuration check: no $RST"
else
    # what a reader copying from the rendered page gets:  the literal block
    #   which follows the '**Example configuration:**' paragraph, de-indented by
    #   the two spaces rst requires, with the substitutions the build expands
    awk '/^\*\*Example configuration:\*\*/ { seen = 1 }
         seen && /^::$/ { block = 1 ; next }
         block && /^[^ ]/ { exit }
         block { print }' $RST |
        sed -e 's/^  //' -e 's/|ToolName|/LCOV/g' -e 's/|TOOL_NAME|/LCOV/g' \
            -e 's/\\-/-/g' > doc.rc
    COUNT=`grep -c . doc.rc`
    if [ 100 -gt "$COUNT" ] ; then
        fail doc "found only $COUNT lines of example configuration in $RST"
    fi
    # the whole of the syntax check:  a configuration file is blank lines,
    #   comments and 'key = value'
    BAD=`grep -nvE '^[[:space:]]*($|#|[a-zA-Z_]+[[:space:]]*=)' doc.rc`
    if [ -n "$BAD" ] ; then
        fail doc "the example configuration is not a configuration file: $BAD"
    fi
    # ..and the tools accept it.  '--branch-coverage' is the interesting part:
    #   the example used to turn on a 75% branch coverage gate which the shipped
    #   'lcovrc' leaves commented out, so copying it as documented made a
    #   perfectly good report exit 1
    $COVER $GENHTML_TOOL $GENHTML_OPTS --config-file doc.rc --branch-coverage \
        -o o_doc hello.info 2>&1 | tee doc.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        fail doc "genhtml did not accept the documented example configuration"
    fi
    if grep -q -e 'ERROR:' -e 'WARNING:' doc.log ; then
        fail doc "the documented example configuration was complained about"
    fi

    # ..and, while the manual is open:  a width which the shipped configuration
    #   file sets has to be the width the manual calls the default, or the
    #   out-of-the-box report is not the documented one
    for key in line branch mcdc owner age ; do
        # the '..' stand for the pair of back-quotes rst puts around the key
        #   name:  a literal back-quote cannot be written inside the command
        #   substitution below
        DOC=`awk -v key="genhtml_${key}_field_width" \
                 '$0 ~ "^.." key ".. =" { found = 1 }
                  found && /^Default is [0-9]+\.$/ {
                      gsub(/[^0-9]/, "") ; print ; exit
                  }' $RST`
        if [ -z "$DOC" ] ; then
            fail doc "$RST documents no default for genhtml_${key}_field_width"
            continue
        fi
        # only the ones the shipped file actually sets:  a commented out entry
        #   is an illustration, not a value
        RC=
        if [ -f $LCOV_HOME/lcovrc ] ; then
            RC=`sed -n -e "s/^genhtml_${key}_field_width *= *//p" \
                $LCOV_HOME/lcovrc`
        fi
        if [ -n "$RC" ] && [ "$DOC" != "$RC" ] ; then
            fail doc \
                "lcovrc sets genhtml_${key}_field_width to $RC, $RST says $DOC"
        fi
    done
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'lcovrc' $LOCAL_COVERAGE 0
fi

exit $STATUS
