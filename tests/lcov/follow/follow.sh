#!/bin/bash
set +x

CLEAN_ONLY=0
COVER=

PARALLEL='--parallel 0'
PROFILE="--profile"
CC="${CC:-gcc}"
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
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
fi

rm -rf rundir *.info

if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover -delete
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

mkdir -p rundir
cd rundir

rm -Rf src src2

mkdir src
ln -s src src2

echo 'int a (int x) { return x + 1; }' > src/a.c
echo 'int b (int x) { return x + 2; }' > src/b.c

${CC} -c --coverage src/a.c -o src/a.o
${CC} -c --coverage src2/b.c -o src/b.o

$COVER $LCOV_TOOL -o out2.info --capture --initial --no-external -d src --follow --rc geninfo_follow_file_links=1
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --initial --follow"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

COUNT2=`grep -c SF: out2.info`
if [ 2 != $COUNT2 ] ; then
    echo "Error:  expected COUNT==2, found $COUNT2"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $GENINFO_TOOL -o out3.info --initial --no-external src --follow --rc geninfo_follow_file_links=1
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from geninfo --initial --follow"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

diff out3.info out2.info
if [ 0 != $? ] ; then
    echo "Error:  expected identical geninfo output"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $GENINFO_TOOL -o out4.info --initial --no-external src2 --follow
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov src2"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

diff out4.info out2.info
# should not be identical as the 'src2/b.c' path should be in 'out4.info'
if [ 0 == $? ] ; then
    echo "Error:  expected not identical geninfo output"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
cat out4.info | sed -e s/src2/src/g > out5.info
diff out5.info out2.info
# should be identical now
if [ 0 != $? ] ; then
    echo "Error:  expected identical geninfo output after substitution"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

cd ..
$COVER $GENINFO_TOOL -o top.info --initial --no-external rundir --follow
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov src2"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
diff top.info rundir/out4.info
# should be identical now
if [ 0 != $? ] ; then
    echo "Error:  expected identical geninfo output after substitution"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi
