#!/bin/sh
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

LCOV_OPTS="--rc lcov_branch_coverage=1 $PARALLEL $PROFILE"

rm -rf *.gcda *.gcno a.out *.info* *.txt* *.json dumper* testRC *.gcov *.gcov.*

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
if [ $COUNT == '1' ] ; then
    echo "expected at least 2 files in external.info - found $COUNT"
    exit 1
fi

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --no-external --directory . -o internal.info

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --list internal.info

COUNT=`grep -c SF: internal.info`
if [ $COUNT != '1' ] ; then
    echo "expected 1 file in internal.info - found $COUNT"
    exit 1
fi

# check to see if "--omit-lines" works properly...
$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --no-external --omit-lines '\s+std::string str.+' --directory . -o omit.info

if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from lcov --omit"
    exit 1
fi

# a bit of a hack:  gcc/10 doesn't put a DA entry on the closing brace
COUNT=`grep -v DA:22 omit.info | grep -c ^DA:`
if [ $COUNT != '11' ] ; then
    echo "expected 11 DA entries in 'omit.info' - found $COUNT"
    exit 1
fi

# check to see if "--omit-lines" works fails if no match
$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --no-external --omit-lines 'xyz\s+std::string str.+' --directory . -o omitErr.info

if [ 0 == $? ] ; then
    echo "Error:  did not see expected error code from lcov --omit"
    exit 1
fi

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --no-external --omit-lines 'xyz\s+std::string str.+' --directory . -o omitWarn.info --ignore unused

if [ 0 != $? ] ; then
    echo "Error:  unexpected expected error code from lcov --omit --ignore.."
    exit 1
fi
COUNT=`grep -v DA:22 omitWarn.info | grep -c ^DA:`
if [ $COUNT != '12' ] ; then
    echo "expected 12 DA entries in 'omitWarn.info' - found $COUNT"
    exit 1
fi

# try again, with rc file instead
echo "omit_lines = ^std::string str.+\$" > testRC # no space at start ofline
echo "omit_lines = ^\\s+std::string str.+\$" >> testRC
#should fail due to no match...
$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --no-external --config-file testRC --directory . -o rc_omitErr.info

if [ 0 == $? ] ; then
    echo "Error:  did not see expected error code from lcov --config with bad omit"
    exit 1
fi
echo "ignore_errors = unused" >> testRC
echo "ignore_errors = empty" >> testRC

$COVER $LCOV_HOME/bin/lcov $LCOV_OPTS --capture --no-external --config-file testRC --directory . -o rc_omitWarn.info

if [ 0 != $? ] ; then
    echo "Error:  saw unexpected error code from lcov --config with ignored bad omit"
    exit 1
fi
COUNT=`grep -v DA:22  rc_omitWarn.info | grep -c ^DA:`
if [ $COUNT != '11' ] ; then
    echo "expected 11 DA entries in 'rc_omitWarn.info' - found $COUNT"
    exit 1
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] ; then
    cover
fi
