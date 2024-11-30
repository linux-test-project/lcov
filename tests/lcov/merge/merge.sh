#!/bin/bash
# test lcov set operations

set +x

CLEAN_ONLY=0
COVER=

PARALLEL='--parallel 0'
PROFILE="--profile"
CC="${CC:-gcc}"
CXX="${CXX:-g++}"
COVER_DB='cover_db'
LOCAL_COVERAGE=1
KEEP_GOING=0
while [ $# -gt 0 ] ; do

    OPT=$1
    shift
    case $OPT in

        --clean | clean )
            CLEAN_ONLY=1
            ;;

        -v | --verbose | verbose )
            set -x
            ;;

        --keep-going | -k )
            KEEP_GOING=1
            ;;

        --coverage )
            #COVER="perl -MDevel::Cover "
            if [[ "$1"x != 'x' &&  $1 != "-"* ]] ; then
               COVER_DB=$1
               LOCAL_COVERAGE=0
               shift
            fi
            COVER="perl -MDevel::Cover=-db,$COVER_DB,-coverage,statement,branch,condition,subroutine "
            ;;

        --home | -home )
            LCOV_HOME=$1
            shift
            if [ ! -f $LCOV_HOME/bin/lcov ] ; then
                echo "LCOV_HOME '$LCOV_HOME' does not exist"
                exit 1
            fi
            ;;

        --no-parallel )
            PARALLEL=''
            ;;

        --no-profile )
            PROFILE=''
            ;;

        * )
            echo "Error: unexpected option '$OPT'"
            exit 1
            ;;
    esac
done

if [[ "x" == ${LCOV_HOME}x ]] ; then
       if [ -f ../../../bin/lcov ] ; then
           LCOV_HOME=../../..
       else
           LCOV_HOME=../../../../releng/coverage/lcov
       fi
fi
LCOV_HOME=`(cd ${LCOV_HOME} ; pwd)`

if [[ ! ( -d $LCOV_HOME/bin && -d $LCOV_HOME/lib && -x $LCOV_HOME/bin/genhtml && ( -f $LCOV_HOME/lib/lcovutil.pm || -f $LCOV_HOME/lib/lcov/lcovutil.pm ) ) ]] ; then
    echo "LCOV_HOME '$LCOV_HOME' seems not to be invalid"
    exit 1
fi

export PATH=${LCOV_HOME}/bin:${LCOV_HOME}/share:${PATH}
export MANPATH=${MANPATH}:${LCOV_HOME}/man

if [ 'x' == "x$GENHTML_TOOL" ] ; then
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    GENINFO_TOOL=${LCOV_HOME}/bin/geninfo
fi

ROOT=`pwd`
PARENT=`(cd .. ; pwd)`

LCOV_OPTS="--branch $PARALLEL $PROFILE --mcdc-coverage"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
    # and filter exception branches to avoid spurious differences for old compiler
    FILTER='--filter branch'
fi

rm -rf *.txt* *.json dumper* intersect*.info* diff*.info* cover_db

if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover -delete
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

status=0
# note that faked data is not consistent - but just ignoring the issue for now
$COVER $LCOV_TOOL $LCOV_OPTS -o intersect.info a.info --intersect b.info --ignore inconsistent
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from intersect"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
$COVER $LCOV_TOOL $LCOV_OPTS -o intersect_2.info b.info --intersect a.info --ignore inconsistent
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from intersect"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

diff intersect.info intersect_2.info
if [ 0 != $? ] ; then
    echo "Error:  expected reflexive but not"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

diff intersect.info intersect.gold
if [ 0 != $? ] ; then
    echo "Error:  unexpected mismatch:  intersect.gold"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


$COVER $LCOV_TOOL $LCOV_OPTS -o diff.info a.info --subtract b.info --ignore inconsistent
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from subtract"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
diff diff.info a_subtract_b.gold
if [ 0 != $? ] ; then
    echo "Error:  unexpected mismatch:  a_subtract_b.gold"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -o diff2.info b.info --subtract a.info --ignore inconsistent
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from subtract 2"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
diff diff2.info b_subtract_a.gold
if [ 0 != $? ] ; then
    echo "Error:  unexpected mismatch:  b_subtract_a.gold"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


# test some error messages...
$COVER $LCOV_TOOL $LCOV_OPTS -o x.info 'y.?info' --intersect a.info --ignore inconsistent
if [ 0 == $? ] ; then
    echo "Error:  expected error but did not see one"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
$COVER $LCOV_TOOL $LCOV_OPTS -o x.info a.info --intersect 'z.?info' --ignore inconsistent
if [ 0 == $? ] ; then
    echo "Error:  expected error but did not see one"
    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# test line coverpoint generation
$COVER $LCOV_TOOL $LCOV_OPTS -o gen.info -a mcdc.dat --ignore inconsistent
if [ 0 != $? ] ; then
    echo "Error:  MC/DC DA gen failed"

    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

for count in 'DA:6,0' 'LF:8' 'LH:2' ; do
    grep $count gen.info
    if [ 0 != $? ] ; then
        echo "Error:  didn't find expected count '$count' in MC/DC gen"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done


$COVER $LCOV_TOOL $LCOV_OPTS -o func.info -a functionBug_1.dat -a functionBug_2.dat --ignore inconsistent
if [ 0 != $? ] ; then
    echo "Error:  function merge failed"

    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

for count in 'FNF:2' 'FNH:2' ; do
    grep $count func.info
    if [ 0 != $? ] ; then
        echo "Error:  didn't find expected count '$count' in function merge"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

$COVER $LCOV_TOOL $LCOV_OPTS -o inconsistent.info -a a.dat -a b.dat --ignore inconsistent --msg-log inconsistent.log
if [ 0 != $? ] ; then
    echo "Error:  function merge2 failed"

    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
grep -E "duplicate function .+ starts on line .+ but previous definition" inconsistent.log
if [ 0 != $? ] ; then
    echo "Error:  didn't find definition message"

    status=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

if [ 0 == $status ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi

exit $status
