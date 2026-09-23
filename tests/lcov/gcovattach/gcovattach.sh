#!/bin/bash

# geninfo:  a branch block or MC/DC group which gcov writes on a line without a
#   line coverpoint belongs to the nearest statement before it - the greatest
#   line less than its own which has a line coverpoint.  It is held by that
#   line, and written at its own:  'BRDA:4,1^5,...', 'MCDC:4,2^5,...'.
# An unexecuted block on a line which has a count but no branch is the target
#   of a branch of the nearest statement before it, if that statement holds
#   branch data;  otherwise the line's count is inconsistent.
# 't.c' is compiled and run, and gcov's output is rewritten by 'edit.pl' (see
#   there) so that it holds each of those cases:
#      5   the branches and condition of 'b' - no count      held by line 4
#      8   unexecuted block, no branch;  line 7 has branches  accepted
#      9   unexecuted block, no branch;  line 8 has none      reported
# gcov 9 and later write the JSON intermediate format, and older ones the text
#   and the intermediate text formats;  the test runs with each this gcov has.
#   Of the intermediate text formats, only gcov 8's marks unexecuted blocks.
# gcov 14 and later also write the basic blocks of each line and the source and
#   target block of each branch.  They decide which statement holds the data,
#   and whether an unexecuted block is the target of a branch.  The 'far'
#   layout (see edit.pl) is placed by them differently than by the nearest
#   statement before it.

set +x

source ../../common.tst

rm -rf *.gcda *.gcno t *.info *.info.json *.log *.gcov fakegcov html_report

clean_cover

if [[ 1 == "$CLEAN_ONLY" ]] ; then
    exit 0
fi

if ! type ${CC} >/dev/null 2>&1 ; then
    echo "Missing tool: ${CC}" >&2
    exit 2
fi

STATUS=0

fail()
{
    echo "ERROR ($1): $2"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

# expect label what actual expected
expect()
{
    if [ "$3" != "$4" ] ; then
        fail $1 "$2: '$3', expected '$4'"
    fi
}

IFS='.' read -r -a VER <<< `${CC} -dumpversion`
MCDC=
FLAGS=
if [ "${VER[0]}" -ge 9 ] ; then
    FORMATS=json
    if $GCOV --help | grep -q -e '--conditions' &&
       ${CC} -fcondition-coverage -E - < /dev/null > /dev/null 2>&1 ; then
        MCDC=--mcdc
        FLAGS=-fcondition-coverage
    fi
else
    # the text format, and the intermediate text format
    FORMATS='text itext'
fi
echo "gcov ${VER[0]}:  $FORMATS $MCDC"

# an absolute path:  gcov 8 does not find a relative one from the directory
#   geninfo runs it in
${CC} --coverage $FLAGS -O0 -o t `pwd`/t.c || exit 1
./t

# the real gcov, with its output rewritten
EDIT=`pwd`/edit.pl
cat > fakegcov <<EOF2
#! /usr/bin/env bash
case " \$* " in
    *" --version "*|*" --help "*|*" -v "*|*" -h "*)
        exec $GCOV "\$@"
        ;;
    *" --stdout "*)
        $GCOV "\$@" | perl $EDIT json
        exit \${PIPESTATUS[0]}
        ;;
esac
$GCOV "\$@" || exit \$?
for f in *.gcov.json.gz ; do
    if [ -f "\$f" ] ; then
        gunzip -c "\$f" | perl $EDIT json | gzip -c > "\$f.new" &&
            mv "\$f.new" "\$f"
    fi
done
for f in *.gcov ; do
    if [ -f "\$f" ] ; then
        perl $EDIT text "\$f"
    fi
done
EOF2
chmod +x fakegcov

# capture with the rewritten output
# label expected-exit(0 = success, 1 = failure) geninfo-args...
capture()
{
    local label=$1
    local status=$2
    shift 2
    $COVER $GENINFO_TOOL . --gcov-tool `pwd`/fakegcov --branch $MCDC \
        $TEXT $PARALLEL $PROFILE \
        -o $label.info "$@" 2>&1 | tee $label.log
    local rc=${PIPESTATUS[0]}
    if [ $status == 0 -a $rc != 0 ] ; then
        fail $label "geninfo failed"
    elif [ $status != 0 -a $rc == 0 ] ; then
        fail $label "geninfo passed, but was expected to fail"
    fi
}

for format in $FORMATS ; do
    TEXT=
    if [ $format == text ] ; then
        TEXT='--rc geninfo_intermediate=0'
    fi
    UNEXEC=1
    if [ $format == itext -a "${VER[0]}" != 8 ] ; then
        UNEXEC=0
    fi
    echo "*** $format format"
    # the unexecuted block of line 9 is reported
    capture unexec_$format 0
    if [ $UNEXEC == 1 ] &&
       ! grep -q -E 't.c:9: unexecuted block on non-branch line' \
            unexec_$format.log ; then
        fail unexec_$format "expected line 9 to be reported"
    fi
    if grep -q -E 't.c:8: unexecuted block' unexec_$format.log ; then
        fail unexec_$format "line 8 was reported"
    fi

    capture attach_$format 0 --ignore inconsistent
    # line 5 has no line coverpoint, and no data:  its branches are held by
    #   line 4
    INFO=attach_$format.info
    expect attach_$format 'line 5' \
        "`grep -c -E '^(DA|BRDA|MCDC):5,' $INFO`" 0
    BR4=`grep -c -E '^BRDA:4,[a-z]*[0-9]+,' $INFO`
    BR5=`grep -c -E '^BRDA:4,[a-z]*[0-9]+\^5,' $INFO`
    if [ 0 == $BR4 -o 0 == $BR5 ] ; then
        fail attach_$format \
            "expected branches of line 4 at lines 4 and 5:" \
            `grep -E '^BRDA:4,' $INFO`
    fi
    # ..and so is its condition
    if [ -n "$MCDC" ] ; then
        expect attach_$format 'MC/DC at line 4' \
            "`grep -c -E '^MCDC:4,[0-9]+,' $INFO`" 0
        expect attach_$format 'MC/DC at line 5' \
            "`grep -c -E '^MCDC:4,2\^5,' $INFO`" 4
    fi
    # the counts of lines 8 and 9 are kept
    if [ $UNEXEC == 1 ] ; then
        expect attach_$format 'line 8' "`grep -E '^DA:8,' $INFO`" 'DA:8,2'
    fi
    expect attach_$format 'line 9' "`grep -E '^DA:9,' $INFO`" 'DA:9,2'

    # ..or line 9 is set to 0
    if [ $UNEXEC == 1 ] ; then
        capture adjust_$format 0 --rc geninfo_unexecuted_blocks=1
        expect adjust_$format 'line 8' \
            "`grep -E '^DA:8,' adjust_$format.info`" 'DA:8,2'
        expect adjust_$format 'line 9' \
            "`grep -E '^DA:9,' adjust_$format.info`" 'DA:9,0'
    fi

    # the text format reads the .gcno file alone for '--initial' - and
    #   cannot find branch data there
    if [ $format == text ] ; then
        capture initial_text 0 --initial --ignore usage
        if ! grep -q -E '\-\-initial cannot generate branch coverage' \
                initial_text.log ; then
            fail initial_text "expected branch coverage to be refused"
        fi
        expect initial_text 'line 4' \
            "`grep -E '^DA:4,' initial_text.info`" 'DA:4,0'
        expect initial_text 'branches' \
            "`grep -c -E '^BRDA:' initial_text.info`" 0
    fi
done

# the far layout:  line 8 has the branches and condition of 'b', and no
#   count.  The nearest statement before it is line 7, but gcov 14 and
#   later say that their block is one of line 4's
if [ "$FORMATS" == json ] ; then
    TEXT=
    if [ "${VER[0]}" -ge 14 ] ; then
        HOLDER=4
    else
        HOLDER=7
    fi
    echo "*** far layout:  held by line $HOLDER"
    EDIT_LAYOUT=far capture far_json 0
    INFO=far_json.info
    expect far_json 'line 8' "`grep -c -E '^(DA|BRDA|MCDC):8,' $INFO`" 0
    if [ 0 == `grep -c -E "^BRDA:$HOLDER,[a-z]*[0-9]+\^8," $INFO` ] ; then
        fail far_json \
            "expected branches of line 8 to be held by line $HOLDER:" \
            `grep -E '^BRDA:' $INFO`
    fi
    if [ -n "$MCDC" ] ; then
        expect far_json 'MC/DC at line 8' \
            "`grep -c -E "^MCDC:$HOLDER,2\^8," $INFO`" 4
    fi
    # line 9 follows line 7, which has branches, but gcov 14 and later say
    #   that its unexecuted block is not the target of one
    REPORTED=`grep -c -E 't.c:9: unexecuted block on non-branch line' \
              far_json.log`
    if [ $HOLDER == 4 ] ; then
        expect far_json 'line 9 reported' $REPORTED 1
    else
        expect far_json 'line 9 reported' $REPORTED 0
    fi
fi

if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    generate_coverage 'gcovattach' $LOCAL_COVERAGE 0
fi
exit $STATUS
