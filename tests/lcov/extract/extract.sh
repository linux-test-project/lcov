#!/bin/sh
set +x

CLEAN_ONLY=0
LCOV_HOME=
COVER=

PARALLEL='--parallel 0'
PROFILE="--profile"
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

        --coverage )
            #COVER="perl -MDevel::Cover "
            COVER="perl -MDevel::Cover=-db,cover_db,-coverage,statement,branch,condition,subroutine "
            ;;

        --home | home )
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

export PATH=${LCOV_HOME}/bin:${LCOV_HOME}/share:${PATH}
export MANPATH=${MANPATH}:${LCOV_HOME}/man

ROOT=`pwd`
PARENT=`(cd .. ; pwd)`

LCOV_OPTS="--rc lcov_branch_coverage=1 $PARALLEL $PROFILE"

rm -rf *.gcda *.gcno a.out *.info* *.txt* *.json dumper*

if [ "x$COVER" != 'x' ] ; then
    cover -delete
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

g++ -std=c++1y --coverage extract.cpp
./a.out 1

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --directory . -o external.info

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --list external.info

# how many files reported?
COUNT=`grep -c SF: external.info`
if [ $COUNT != '2' ] ; then
    echo "expected 2 files in external.info - found $COUNT"
    exit 1
fi

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --no-external --directory . -o internal.info

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --list internal.info

COUNT=`grep -c SF: internal.info`
if [ $COUNT != '1' ] ; then
    echo "expected 1 file in internal.info - found $COUNT"
    exit 1
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] ; then
    cover
fi

