#!/bin/bash
set +x

CLEAN_ONLY=0
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

if [[ ! ( -d $LCOV_HOME/bin && -d $LCOV_HOME/lib && -x $LCOV_HOME/bin/genhtml && -f $LCOV_HOME/lib/lcovutil.pm ) ]] ; then
    echo "LCOV_HOME '$LCOV_HOME' seems not to be invalid"
    exit 1
fi

export PATH=${LCOV_HOME}/bin:${LCOV_HOME}/share:${PATH}
export MANPATH=${MANPATH}:${LCOV_HOME}/man

ROOT=`pwd`
PARENT=`(cd .. ; pwd)`

LCOV_OPTS="--branch-coverage --no-external $PARALLEL $PROFILE"

rm -rf *.gcda *.gcno a.out *.info* *.txt* *.json dumper* testRC *.gcov *.gcov.*

if [ "x$COVER" != 'x' ] ; then
    cover -delete
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

g++ -std=c++1y --coverage demangle.cpp
./a.out 1

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --filter branch --demangle --directory . -o demangle.info

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --list demangle.info

# how many branches reported?
COUNT=`grep -c BRDA: demangle.info`
if [ $COUNT != '0' ] ; then
    echo "expected 0 branches - found $COUNT"
    exit 1
fi

for k in FN FNDA ; do
    # how many functions reported?
    grep $k: demangle.info
    COUNT=`grep -v __ demangle.info | grep -c $k:`
    if [ $COUNT != '5' ] ; then
        echo "expected 5 $k function entries in demangle.info - found $COUNT"
        exit 1
    fi

    # were the function names demangled?
    grep $k: demangle.info | grep ::
    COUNT=`grep $k: demangle.info | grep -c ::`
    if [ $COUNT != '4' ] ; then
        echo "expected 4 $k function entries in demangele.info - found $COUNT"
        exit 1
    fi
done


$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --filter branch --directory . -o vanilla.info

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --list vanilla.info

# how many branches reported?
COUNT=`grep -c BRDA: vanilla.info`
if [ $COUNT != '0' ] ; then
    echo "expected 0 branches - found $COUNT"
    exit 1
fi

for k in FN FNDA ; do
    # how many functions reported?
    grep $k: vanilla.info
    COUNT=`grep -v __ demangle.info | grep -c $k: vanilla.info`
    # gcc may generate multiple entries for the inline functions..
    if [ $COUNT -lt 5 ] ; then
        echo "expected 5 $k function entries in $vanilla.info - found $COUNT"
        exit 1
    fi

    # were the function names demangled?
    grep $k: vanilla.info | grep ::
    COUNT=`grep $k: vanilla.info | grep -c ::`
    if [ $COUNT != '0' ] ; then
        echo "expected 0 demangled $k function entries in vanilla.info - found $COUNT"
        exit 1
    fi
done


echo "Tests passed"

if [ "x$COVER" != "x" ] ; then
    cover
fi
