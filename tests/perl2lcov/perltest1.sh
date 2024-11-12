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
            if [[ "$1"x != 'x' && $1 != "-"* ]] ; then
               COVER_DB=$1
               LOCAL_COVERAGE=0
               shift
            fi
            COVER="perl -MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine,-silent,1 "
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
       if [ -f ../../bin/lcov ] ; then
           LCOV_HOME=../..
       else
           LCOV_HOME=../../../releng/coverage/lcov
       fi
fi
LCOV_HOME=`(cd ${LCOV_HOME} ; pwd)`

if [[ ! ( -d $LCOV_HOME/bin && -d $LCOV_HOME/lib && -x $LCOV_HOME/bin/genhtml && -f $LCOV_HOME/lib/lcovutil.pm ) ]] ; then
    echo "LCOV_HOME '$LCOV_HOME' seems not to be invalid"
    exit 1
fi

export PATH=${LCOV_HOME}/bin:${LCOV_HOME}/share:${PATH}
export MANPATH=${MANPATH}:${LCOV_HOME}/man

if [ 'x' == "x$GENHTML_TOOL" ] ; then
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    PERL2LCOV_TOOL=${LCOV_HOME}/bin/perl2lcov
fi

ROOT=`pwd`
PARENT=`(cd .. ; pwd)`

LCOV_OPTS="--branch-coverage $PARALLEL $PROFILE"

rm -rf *.xml *.dat *.info *.json cover_one perl2lcov_report cover_genhtml *.log

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover -delete
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

perl -MDevel::Cover=-db,cover_one,-coverage,statement,branch,condition,subroutine,-silent,1 example.pl
if [ 0 != $? ] ; then
    echo "perl exec failed"
    exit 1
fi

# error check:  try to run perl2lcov before running 'cover':
$COVER ${EXEC_COVER} $PERL2LCOV_TOOL --output err.info --testname test1 ./cover_one 2>&1 | tee err.log
if [ 0 == ${PIPESTATUS[0} ] ; then
    echo "expected to fail - but passed"
    exit 1
fi
grep "appears to be empty" err.log
if [ 0 != $? ] ; then
    echo "expected error message not found"
    exit 1
fi

cover cover_one -silent 1

$COVER ${EXEC_COVER} $PERL2LCOV_TOOL --output one.info --testname test1 ./cover_one
if [ 0 != $? ] ; then
    echo "perl2lcov failed"
    exit 1
fi

# did we generate the test name we expected
N=`grep -c TN: one.info`
if [ "$N" != '1' ] ; then
    echo "wrong number of tests"
    exit 1;
fi
T=`grep TN: one.info`
if [ "$T" != 'TN:test1' ] ; then
    echo "wrong test name"
    exit 1
fi

#should be 2 functions in namespace 1 and namespace 2
for space in 'space1' 'space2' ; do
    N=`grep FNA: one.info | grep -c $space::`
    if [ 2 != "$N" ] ; then
        echo "wrong number of functions in $space"
        exit 1
    fi
done
# expect only one function in global namespace
#   rather than looking for known index '4' for this function, would be better
#   to look for the name - then find index from name, then find location from index
#   but this is easier and testcase is simple.
G=`grep FNA: one.info | grep -v space`
if [ "$G" != 'FNA:4,1,global1' ] ; then
    echo "wrong name/location for function in global namespace"
    exit 1
fi
DA=`grep -c -E '^DA:' one.info`
BR=`grep -c -E '^BRDA:' one.info`

# do region exclusions work?
$COVER ${EXEC_COVER} $PERL2LCOV_TOOL --filter region --output region.info ./cover_one
if [ 0 != $? ] ; then
    echo "perl2lcov failed"
    exit 1
fi
# how many lines now?
REGION_DA=`grep -c -E '^DA:' region.info`
REGION_BR=`grep -c -E '^BRDA:' region.info`
if [ $BR -lt $REGION_BR ] ; then
    echo "wrong region branch count $BR -> $REGION_BR"
    exit 1
fi
if [ $DA -lt $REGION_DA ] ; then
    echo "wrong region line count $DA -> $REGION_DA"
    exit 1
fi

# how about just branch exclusion...
$COVER ${EXEC_COVER} $PERL2LCOV_TOOL --filter branch_region --output br_region.info ./cover_one
if [ 0 != $? ] ; then
    echo "perl2lcov failed"
    exit 1
fi
# how many lines now?
BREGION_DA=`grep -c -E '^DA:' br_region.info`
BREGION_BR=`grep -c -E '^BRDA:' br_egion.info`
if [ $REGION_BR != $BREGION_BR ] ; then
    echo "wrong branch region branch count $BR -> $BREGION_BR"
    exit 1
fi
if [ $DA != $BREGION_DA ] ; then
    echo "wrong branch region line count $DA -> $BREGION_DA"
    exit 1
fi


# run again, collecting checksum..
$COVER ${EXEC_COVER} $PERL2LCOV_TOOL --output checksum.info --testname testCheck ./cover_one --checksum
if [ 0 != $? ] ; then
    echo "perl2lcov checksum failed"
fi

# do we see the checksums we expect?
# expect to see checksum on each DA line..
for l in `grep -E '^DA:' checksum.info` ; do
    echo $l | grep -E 'DA:[0-9]+,[0-9]+,.+'
    if [ 0 != $? ] ; then
        echo "no checksum in '$l'"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done


$COVER ${EXEC_COVER} $PERL2LCOV_TOOL -o x.info --exclude example.pl ./cover_one
if [ 0 == $? ] ; then
    echo "expected ERROR_EMPTY not found"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
$COVER ${EXEC_COVER} $PERL2LCOV_TOOL --exclude example.pl --ignore empty ./cover_one -o x.info
if [ 0 != $? ] ; then
    echo "didn't ignore ERROR_EMPTY"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ `test ! -z x.info` ] ; then
    echo 'expected empty file - but not empty'
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

$COVER ${EXEC_COVER} $PERL2LCOV_TOOL --help
if [ 0 != $? ] ; then
    echo "perl2lcov help failed"
    exit 1
fi

# incorrect option
$COVER ${EXEC_COVER} $PERL2LCOV_TOOL --unsupported
if [ 0 == $? ] ; then
    echo "did not see expected error"
    exit 1
fi

# is the data generated by perl2lcov valid?
$COVER $LCOV_TOOL $LCOV_OPTS --summary one.info
if [ 0 != $? ] ; then
    echo "lcov summary failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# now try running genhtml on the perl2lcov-generated .info file...
perl -MDevel::Cover=-db,cover_genhtml,-silent,1 ../../bin/genhtml -o perl2lcov_report --flat --show-navigation one.info --branch
if [ 0 != $? ] ; then
    echo "genhtml failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
cover cover_genhtml -silent 1

# ignore inconsistency:  line hit but no branch on line is hit
$COVER ${EXEC_COVER} $PERL2LCOV_TOOL --output genhtml.info --testname genhtml_test ./cover_genhtml --ignore inconsistent
if [ 0 != $? ] ; then
    echo "perl2lcov genhtml"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
    $PERL2LCOV_TOOL -o ${COVER_DB}/perlcov.info ${COVER_DB}
    $GENHTML_TOOL -o ${COVER_DB}/report ${COVER_DB}/perlcov.info --flat --show-navigation --branch
fi
