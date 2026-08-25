#!/bin/bash
set +x

# Exercise '--tempdir' and its rc spelling 'lcov_tmp_dir', which used to be two
#   different things:  'lcov_tmp_dir' named the parent that a uniquely-named
#   temporary directory was created under (and removed from again), while
#   '--tempdir' named an exact directory which was used verbatim and never
#   cleaned up.  Only geninfo bridged the two ($lcovutil::tempdirname was copied
#   into $lcovutil::tmp_dir), so what '--tempdir' did depended on the tool and,
#   within lcov, on the phase.
#
# They are one variable now - $lcovutil::tmp_dir - and it always names the
#   parent:
#   1. '--tempdir X' puts a generated subdirectory in X, and takes it away again
#   2. ...unless '--preserve' says to keep it
#   3. X is created if it does not exist, and removed again if we created it
#   4. an X the user created is left alone, and so is anything already in it
#   5. '--tempdir' beats 'lcov_tmp_dir' ('apply_rc_params' runs before
#      'GetOptions'), and 'lcov_tmp_dir' works on its own
#   6. every phase of one run writes under the same X 
#   7. 'genhtml --preserve' preserves:  its temp directory was created with a
#      hardcoded 'CLEANUP => 1'
#   8. an X we can neither write to nor create is a usage error, reported once,
#      up front, rather than as a failure to write some particular file
#  9. 'lcov --capture' hands it on to the geninfo child, so the capture and
#      the rest of the run share one X
#
# geninfo's side of this is in 'lcov/coverage/geninfo.sh' (tests 8, 8a-8d).

source ../../common.tst

rm -rf *.info *.log *.c *.gcov *.rpt *.udiff cover_db.dat html_report report \
    save_report perlcov.info tmproot cap __pycache__

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if [ 'x' == "x$LCOV_TOOL" ] ; then
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
    HTML2LCOV_TOOL=${LCOV_HOME}/bin/html2lcov
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

# html2lcov only forks its scrape when it has at least two chunks, and it puts
#   at least $MIN_CHUNK_FILES (8) files in a chunk - so 16 files is the smallest
#   fixture which makes it create 'html2lcov_dat*' at all
NFILES=16
NTESTS=6

# ----------------------------------------------------------------------------
# Fixture:  'NFILES' source files, and one tracefile per testname covering all
#   of them.  Enough files for 'html2lcov' to want more than one chunk, and
#   enough testnames for 'lcov -a' to want more than one segment.
# ----------------------------------------------------------------------------
i=0
while [ $i -lt $NFILES ] ; do
    cat > src$i.c <<EOF
int f${i}_a(int x)
{
    return x + $i;
}
int f${i}_b(int x)
{
    return x - $i;
}
EOF
    i=$((i + 1))
done

t=0
while [ $t -lt $NTESTS ] ; do
    : > t$t.info
    i=0
    while [ $i -lt $NFILES ] ; do
        cat >> t$t.info <<EOF
TN:test$t
SF:$PWD/src$i.c
FN:1,f${i}_a
FNDA:$((t + 1)),f${i}_a
FN:5,f${i}_b
FNDA:$t,f${i}_b
FNF:2
FNH:$([ $t == 0 ] && echo 1 || echo 2)
DA:1,$((t + 1))
DA:3,$((t + 1))
DA:5,$t
DA:7,$t
LF:4
LH:$([ $t == 0 ] && echo 2 || echo 4)
end_of_record
EOF
        i=$((i + 1))
    done
    t=$((t + 1))
done
# genhtml takes the tracefiles as positional arguments; 'lcov' wants '-a' in
#   front of each one
ALL_INFO=
ADD_INFO=
t=0
while [ $t -lt $NTESTS ] ; do
    ALL_INFO="$ALL_INFO t$t.info"
    ADD_INFO="$ADD_INFO -a t$t.info"
    t=$((t + 1))
done

# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------

# contents of a directory, one name per line ('ls -A', so no . or ..)
contents()
{
    ls -A "$1" 2>/dev/null
}

# $1 = label, $2 = directory:  must exist and be empty
check_emptied()
{
    local label=$1 dir=$2 left
    if [ ! -d "$dir" ] ; then
        fail $label "'$dir' was removed - it existed before the run"
        return
    fi
    left=$(contents "$dir")
    if [ -n "$left" ] ; then
        fail $label "'$dir' still holds: $(echo $left)"
    fi
}

# $1 = label, $2 = directory, $3 = glob one of the survivors must match.  A run
#   which forks more than once keeps one directory per fork - all of them under
#   the parent, which is the point - so this asks for the named one rather than
#   for it alone.
check_kept()
{
    local label=$1 dir=$2 pat=$3 left name found=0
    left=$(contents "$dir")
    if [ -z "$left" ] ; then
        fail $label "--preserve kept nothing in '$dir'"
        return
    fi
    for name in $left ; do
        # shellcheck disable=SC2254
        case "$name" in
            $pat) found=1 ;;
        esac
    done
    if [ 0 == $found ] ; then
        fail $label "expected '$pat' in '$dir', got: $(echo $left)"
    fi
}

# ----------------------------------------------------------------------------
# 1./2./8.  genhtml --tempdir, with and without --preserve
# ----------------------------------------------------------------------------
mkdir -p tmproot/gh_plain
$COVER $GENHTML_TOOL $ALL_INFO --tempdir tmproot/gh_plain \
    -o report/gh_plain >gh_plain.log 2>&1
if [ 0 != $? ] ; then
    cat gh_plain.log
    fail gh_plain "genhtml --tempdir failed"
fi
check_emptied gh_plain tmproot/gh_plain
if [ ! -f report/gh_plain/index.html ] ; then
    fail gh_plain "no report generated"
fi

mkdir -p tmproot/gh_preserve
$COVER $GENHTML_TOOL $ALL_INFO --tempdir tmproot/gh_preserve --preserve \
    -o report/gh_preserve >gh_preserve.log 2>&1
if [ 0 != $? ] ; then
    cat gh_preserve.log
    fail gh_preserve "genhtml --tempdir --preserve failed"
fi
check_kept gh_preserve tmproot/gh_preserve 'genhtml_*'
# the flag used to be a no-op:  the directory it really used was the default
if ! grep -q 'tmproot/gh_preserve/genhtml_' gh_preserve.log ; then
    # only reported at '--verbose', so not fatal on its own - but if the data
    #   landed there then it must be what genhtml said it was using
    :
fi

# ----------------------------------------------------------------------------
# 3.  a --tempdir which does not exist yet:  created, then removed again
# ----------------------------------------------------------------------------
$COVER $GENHTML_TOOL $ALL_INFO --tempdir tmproot/made/up/path \
    -o report/gh_mkdir >gh_mkdir.log 2>&1
if [ 0 != $? ] ; then
    cat gh_mkdir.log
    fail gh_mkdir "genhtml --tempdir of a non-existent directory failed"
fi
if [ -d tmproot/made/up/path ] ; then
    fail gh_mkdir "'tmproot/made/up/path' was created but not removed again"
fi

# ...and with '--preserve' it stays, because there is something in it
$COVER $GENHTML_TOOL $ALL_INFO --tempdir tmproot/made/up/kept --preserve \
    -o report/gh_mkdir_keep >gh_mkdir_keep.log 2>&1
if [ 0 != $? ] ; then
    cat gh_mkdir_keep.log
    fail gh_mkdir_keep "genhtml --tempdir --preserve of a new directory failed"
fi
check_kept gh_mkdir_keep tmproot/made/up/kept 'genhtml_*'

# ----------------------------------------------------------------------------
# 4.  a directory the user made, with something already in it
# ----------------------------------------------------------------------------
mkdir -p tmproot/gh_mine
echo 'do not touch' > tmproot/gh_mine/keepme
$COVER $GENHTML_TOOL $ALL_INFO --tempdir tmproot/gh_mine \
    -o report/gh_mine >gh_mine.log 2>&1
if [ 0 != $? ] ; then
    cat gh_mine.log
    fail gh_mine "genhtml --tempdir of a populated directory failed"
fi
if [ ! -d tmproot/gh_mine ] ; then
    fail gh_mine "our own temp directory was removed"
elif [ "$(contents tmproot/gh_mine)" != keepme ] ; then
    fail gh_mine "unexpected contents: $(contents tmproot/gh_mine)"
elif [ "$(cat tmproot/gh_mine/keepme)" != 'do not touch' ] ; then
    fail gh_mine "pre-existing file was modified"
fi

# ----------------------------------------------------------------------------
# 5.  '--tempdir' beats 'lcov_tmp_dir', and 'lcov_tmp_dir' works alone
# ----------------------------------------------------------------------------
mkdir -p tmproot/rc_loser tmproot/rc_winner
$COVER $GENHTML_TOOL $ALL_INFO --rc lcov_tmp_dir=tmproot/rc_loser \
    --tempdir tmproot/rc_winner --preserve \
    -o report/gh_rc >gh_rc.log 2>&1
if [ 0 != $? ] ; then
    cat gh_rc.log
    fail gh_rc "genhtml --rc lcov_tmp_dir + --tempdir failed"
fi
check_emptied gh_rc tmproot/rc_loser
check_kept gh_rc tmproot/rc_winner 'genhtml_*'

mkdir -p tmproot/rc_only
$COVER $GENHTML_TOOL $ALL_INFO --rc lcov_tmp_dir=tmproot/rc_only --preserve \
    -o report/gh_rconly >gh_rconly.log 2>&1
if [ 0 != $? ] ; then
    cat gh_rconly.log
    fail gh_rconly "genhtml --rc lcov_tmp_dir failed"
fi
check_kept gh_rconly tmproot/rc_only 'genhtml_*'

# ----------------------------------------------------------------------------
# 6.  lcov -a, both of the forks it can take:
#
#     - the filter fork ('TraceFile::_processFilterWorklist'), which used to
#       write 'filter_dat*' to $tmp_dir - i.e. to '/tmp' - no matter what
#       '--tempdir' said, because only the read and aggregate paths looked at
#       $tempdirname
#     - the read/aggregate fork ('AggregateTraces::_parallel_parse' and
#       'TraceFile::merge'), which used $tempdirname *as* its temp directory
#       rather than creating one under it
#
#     The two are alternatives rather than both happening in one run:  when the
#     read is split the children filter their own chunk, so the parent has
#     nothing left to filter.  Drive each of them separately.
# ----------------------------------------------------------------------------

# one input and '--parallel 1':  nothing to split, so the parent filters - in
#   children, because LCOV_FORCE_PARALLEL says to
mkdir -p tmproot/filter_preserve
LCOV_FORCE_PARALLEL=1 $COVER $LCOV_TOOL -a t0.info \
    --tempdir tmproot/filter_preserve --preserve --parallel 1 \
    --filter line -o filter_preserve.info >filter_preserve.log 2>&1
if [ 0 != $? ] ; then
    cat filter_preserve.log
    fail filter_preserve "lcov -a --tempdir --preserve failed"
fi
if [ ! -s filter_preserve.info ] ; then
    fail filter_preserve "no tracefile produced"
fi
check_kept filter_preserve tmproot/filter_preserve 'filter_dat*'

mkdir -p tmproot/filter_plain
LCOV_FORCE_PARALLEL=1 $COVER $LCOV_TOOL -a t0.info \
    --tempdir tmproot/filter_plain --parallel 1 \
    --filter line -o filter_plain.info >filter_plain.log 2>&1
if [ 0 != $? ] ; then
    cat filter_plain.log
    fail filter_plain "lcov -a --tempdir failed"
fi
check_emptied filter_plain tmproot/filter_plain
if ! diff -q filter_plain.info filter_preserve.info >/dev/null ; then
    fail filter_plain "'--preserve' changed the result"
fi

# the whole set, in parallel:  the read/aggregate children
mkdir -p tmproot/agg_preserve
LCOV_FORCE_PARALLEL=1 $COVER $LCOV_TOOL $ADD_INFO \
    --tempdir tmproot/agg_preserve --preserve --parallel 4 \
    --filter line -o agg_preserve.info >agg_preserve.log 2>&1
if [ 0 != $? ] ; then
    cat agg_preserve.log
    fail agg_preserve "lcov -a --tempdir --preserve failed"
fi
if [ ! -s agg_preserve.info ] ; then
    fail agg_preserve "no aggregate tracefile produced"
fi
# a generated name under the directory we named - not the directory itself,
#   which is what the aggregate path used to use
LEFT=$(contents tmproot/agg_preserve)
if [ -z "$LEFT" ] ; then
    fail agg_preserve "the read/aggregate children wrote nothing under --tempdir"
elif [ 1 != $(echo "$LEFT" | wc -l) ] || [ ! -d "tmproot/agg_preserve/$LEFT" ] ; then
    fail agg_preserve "expected one generated subdirectory, got: $(echo $LEFT)"
fi

mkdir -p tmproot/agg_plain
LCOV_FORCE_PARALLEL=1 $COVER $LCOV_TOOL $ADD_INFO \
    --tempdir tmproot/agg_plain --parallel 4 \
    --filter line -o agg_plain.info >agg_plain.log 2>&1
if [ 0 != $? ] ; then
    cat agg_plain.log
    fail agg_plain "lcov -a --tempdir failed"
fi
check_emptied agg_plain tmproot/agg_plain
if ! diff -q agg_plain.info agg_preserve.info >/dev/null ; then
    fail agg_plain "'--preserve' changed the result"
fi

# ----------------------------------------------------------------------------
# 7.  html2lcov
# ----------------------------------------------------------------------------
$COVER $GENHTML_TOOL $ALL_INFO --save -o save_report >save.log 2>&1
if [ 0 != $? ] ; then
    cat save.log
    fail save "genhtml --save failed"
fi

mkdir -p tmproot/h2l_preserve
$COVER $HTML2LCOV_TOOL save_report --tempdir tmproot/h2l_preserve --preserve \
    --parallel 4 --no-branch-coverage \
    --ignore-errors empty,unsupported -o h2l_preserve.info >h2l_preserve.log 2>&1
if [ 0 != $? ] ; then
    cat h2l_preserve.log
    fail h2l_preserve "html2lcov --tempdir --preserve failed"
fi
check_kept h2l_preserve tmproot/h2l_preserve 'html2lcov_dat*'

mkdir -p tmproot/h2l_plain
$COVER $HTML2LCOV_TOOL save_report --tempdir tmproot/h2l_plain \
    --parallel 4 --no-branch-coverage \
    --ignore-errors empty,unsupported -o h2l_plain.info >h2l_plain.log 2>&1
if [ 0 != $? ] ; then
    cat h2l_plain.log
    fail h2l_plain "html2lcov --tempdir failed"
fi
check_emptied h2l_plain tmproot/h2l_plain

# ----------------------------------------------------------------------------
# 9.  the two ways 'lcovutil::create_tmp_dir' can refuse:  a parent we cannot
#     write to, and a parent we cannot create.  Both are ERROR_USAGE.
# ----------------------------------------------------------------------------
if [ 0 == $(id -u) ] ; then
    echo "SKIP: running as root - the mode bits below would not stop us"
else
    mkdir -p tmproot/readonly
    chmod a-w tmproot/readonly

    $COVER $GENHTML_TOOL $ALL_INFO --tempdir tmproot/readonly \
        -o report/gh_ro >gh_ro.log 2>&1
    if [ 0 == $? ] ; then
        cat gh_ro.log
        fail gh_ro "genhtml --tempdir of an unwriteable directory succeeded"
    elif ! grep -q "temporary directory 'tmproot/readonly' is not writeable" \
            gh_ro.log ; then
        cat gh_ro.log
        fail gh_ro "missing 'is not writeable' error"
    fi

    # ..and one we would have to create inside it
    $COVER $GENHTML_TOOL $ALL_INFO --tempdir tmproot/readonly/nope \
        -o report/gh_nomk >gh_nomk.log 2>&1
    if [ 0 == $? ] ; then
        cat gh_nomk.log
        fail gh_nomk "genhtml --tempdir below an unwriteable directory succeeded"
    elif ! grep -q \
        "unable to create temporary directory 'tmproot/readonly/nope'" \
            gh_nomk.log ; then
        cat gh_nomk.log
        fail gh_nomk "missing 'unable to create temporary directory' error"
    fi

    chmod u+w tmproot/readonly
fi

# ----------------------------------------------------------------------------
# 10.  'lcov --capture' hands '--tempdir' on to the geninfo child, so that the
#      whole capture writes under the one parent.  It only needs to do that for
#      a '--tempdir' on the command line:  an rc-file 'lcov_tmp_dir' reaches the
#      child through the rc file the child reads for itself.
# ----------------------------------------------------------------------------
if ! type ${CC:-gcc} >/dev/null 2>&1 ; then
    echo "SKIP: no C compiler (${CC:-gcc}) - not exercising 'lcov --capture'"
else
    mkdir -p cap
    cat > cap/hello.c <<'EOF'
int add(int a, int b) { return a + b; }
int main(void) { return add(1, 2) != 3; }
EOF
    (cd cap && ${CC:-gcc} --coverage -o hello hello.c && ./hello)
    if [ 0 != $? ] ; then
        fail cap "could not build the capture fixture"
    else
        mkdir -p tmproot/cap_preserve
        $COVER $LCOV_TOOL --capture -d cap \
            --tempdir tmproot/cap_preserve --preserve \
            -o cap_preserve.info >cap_preserve.log 2>&1
        if [ 0 != $? ] ; then
            cat cap_preserve.log
            fail cap_preserve "lcov --capture --tempdir --preserve failed"
        elif ! grep -q -- '--tempdir tmproot/cap_preserve' cap_preserve.log ; then
            cat cap_preserve.log
            fail cap_preserve "'--tempdir' was not passed on to geninfo"
        fi
        check_kept cap_preserve tmproot/cap_preserve 'geninfo_dat*'

        mkdir -p tmproot/cap_plain
        $COVER $LCOV_TOOL --capture -d cap --tempdir tmproot/cap_plain \
            -o cap_plain.info >cap_plain.log 2>&1
        if [ 0 != $? ] ; then
            cat cap_plain.log
            fail cap_plain "lcov --capture --tempdir failed"
        fi
        check_emptied cap_plain tmproot/cap_plain
    fi
fi

if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    generate_coverage 'tempdir' $LOCAL_COVERAGE 0
fi

exit $STATUS
