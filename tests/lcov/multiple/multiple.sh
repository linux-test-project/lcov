#!/bin/bash
set +x

CLEAN_ONLY=0
COVER=

PARALLEL='--parallel 0'
PROFILE="--profile"
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

        --keep-going )
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
if [ -d $LCOV_HOME/scripts ] ; then
    SCRIPTS=$LCOV_HOME/scripts
else
    SCRIPTS=$LCOV_HOME/share/lcov/support-scripts
fi

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

LCOV_OPTS="$PARALLEL $PROFILE"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `gcc -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
fi

rm -rf rundir

if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover -delete
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

mkdir -p rundir
cd rundir

rm -Rf a b out
mkdir a b

echo 'int a (int x) { return x + 1; }' > a/a.c
echo 'int b (int x) { return x + 2;}' > b/b.c

( cd a ; gcc -c --coverage a.c -o a.o )
( cd b ; gcc -c --coverage b.c -o b.o )

$COVER $LCOV_TOOL -o out.info --capture --initial --no-external -d a -d b
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --initial"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

COUNT=`grep -c SF: out.info`
if [ 2 != $COUNT ] ; then
    echo "Error:  expected COUNT==2, found $COUNT"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $GENINFO_TOOL -o out2.info --initial --no-external a b
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from geninfo --initial"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

diff out.info out2.info
if [ 0 != $? ] ; then
    echo "Error:  expected identical geninfo output"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# old version of gcc doesn't encode path into .gcno file
#  so the case-insensitive compare is not required.
IFS='.' read -r -a VER <<< `gcc -dumpversion`
if [ "${VER[0]}" -ge 9 ] ; then
    rm -rf B
    mv b B

    $COVER $GENINFO_TOOL -o out3.info --initial --no-external a B
    if [ 0 != $? ] ; then
        echo "Error:  unexpected error code from geninfo"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    COUNT=`grep -c SF: out3.info`
    if [ 1 != $COUNT ] ; then
        echo "Error:  expected COUNT==1, found $COUNT"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    # don't look for exclusions:  our filesystem isn't case-insensitive
    # and we will see a 'source' error
    $COVER $GENINFO_TOOL -o out4.info --initial --no-external a B --rc case_insensitive=1 --no-markers
    if [ 0 != $? ] ; then
        echo "Error:  expected error code from geninfo insensitive"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    diff out4.info out.info
    if [ 0 != $? ] ; then
        echo "Error:  expected identical case-insensitive output, found $COUNT"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
fi


echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi
