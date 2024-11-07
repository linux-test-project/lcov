#!/bin/bash

# lambda function extents
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
            COVER="perl -MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine "
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

rm -rf *.log *.json report initializer *.gcda *.gcno *.info

if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover -delete
fi

if [[ 1 == "$CLEAN_ONLY" ]] ; then
    exit 0
fi

LCOV_OPTS="--branch $PARALLEL $PROFILE"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
    # and filter exception branches to avoid spurious differences for old compiler
    FILTER='--filter branch'

    # gcc older than 5 doesn't support lambda
    echo "Compiler version is too old - skipping lambda test"
    exit 0
fi

if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

#use geninfo for capture - so we can collect coverage info
CAPTURE=$GENINFO_TOOL
#CAPTURE="$LCOV_TOOL --capture --directory"

${CXX} -o initializer --coverage initializer.cpp -std=c++17

./initializer
if [ 0 != $? ] ; then
    echo "Error:  'initializer' returned error code"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $CAPTURE . $LCOV_OPTS -o initializer.info --demangle --rc derive_function_end_line=0 --filter line,branch --include '*/initializer.cpp'
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from capture"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

COUNT=`grep -c "^DA:" initializer.info`

$COVER $CAPTURE . $LCOV_OPTS -o filtered.info --demangle --rc derive_function_end_line=0 --filter line,branch,initializer --include '*/initializer.cpp' 2>&1 | tee filt.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "Error:  unexpected error code from capture2"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

# did the non-filtered capture command find linecov entried on line 8, 9, or 10?
grep -E '^DA:\(8|9|10\)' initializer.info
if [ $? == 0 ] ; then
   COUNT2=`grep -c "^DA:" filtered.info`
   if [ "$COUNT" -le $COUNT2 ] ; then
       echo "ERROR: expected to filter out 3 initializer-list lines"
       if [ $KEEP_GOING == 0 ] ; then
           exit 1
       fi
   fi

   DIFF=`expr $COUNT - $COUNT2`
   if [ "$DIFF" != 3 ] ; then
       echo "ERROR: expected to filter out 3 initializer-list lines"
       if [ $KEEP_GOING == 0 ] ; then
           exit 1
       fi
   fi
else
    echo "no linecov points on std::initializer lines"
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi
