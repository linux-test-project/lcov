#!/bin/bash
set +x

CLEAN_ONLY=0
COVER=

PARALLEL='--parallel 0'
PROFILE="--profile"
if [ 'x' == "x${COVER_DB}" ] ; then
    COVER_DB='cover_db'
fi
if [ 'x' == "x${PYCOV_DB}" ] ; then
    PYCOV_DB='pycov.dat'
fi
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

        -k | --keep-going )
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
            PYCOV="COVERAGE_FILE=${PYCOV_DB} coverage run --branch --append"
            #PYCOV="coverage run --data-file=${PYCOV_DB} --branch --append"
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

if [ "x" == "x$LCOV_HOME" ] ; then
       if [ -f ../../bin/lcov ] ; then
           LCOV_HOME=../..
       else
           LCOV_HOME=../../../releng/coverage/lcov
       fi
fi

LCOV_HOME=`(cd ${LCOV_HOME} ; pwd)`

if [ 'x' == "x$PY2LCOV_TOOL" ] ; then
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    PERLLCOV_TOOL=${LCOV_HOME}/bin/perl2lcov
    PY2LCOV_TOOL=${LCOV_HOME}/bin/py2lcov
fi
PY2LCOV_SCRIPT=${LCOV_HOME}/bin/py2lcov

if [ -f $LCOV_HOME/scripts/getp4version ] ; then
    SCRIPT_DIR=$LCOV_HOME/scripts
else
    # running test from lcov install
    SCRIPT_DIR=$LCOV_HOME/share/lcov/support-scripts
    MD5_OPT='--version-script --md5'
fi
# is this git or P4?
git -C . rev-parse > /dev/null 2>&1
if [ 0 == $? ] ; then
    # this is git
    VERSION="--version-script ${SCRIPT_DIR}/gitversion.pm"
    ANNOTATE="--annotate-script ${SCRIPT_DIR}/gitblame.pm"
else
    VERSION="--version-script ${SCRIPT_DIR}/getp4version"
    ANNOTATE="--annotate-script ${SCRIPT_DIR}/p4annotate.pm"
fi


if [ ! -x $PY2LCOV_SCRIPT ] ; then
    echo "missing py2lcov script - dying"
    exit 1
fi

if [[ ! ( -d $LCOV_HOME/bin && -d $LCOV_HOME/lib && -x $LCOV_HOME/bin/genhtml && -f $LCOV_HOME/lib/lcovutil.pm ) ]] ; then
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

LCOV_OPTS="--branch-coverage $PARALLEL $PROFILE"

rm -rf *.xml* *.dat *.info *.json __pycache__ help.txt *.pyc

if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover -delete
    rm -rf pycov
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

which coverage
if [ 0 != $? ] ; then
    echo "unable to run py2lcov - please install python Coverage.py package"
    exit 1
fi

# some corner cases:
COVERAGE_FILE=./functions.dat coverage  run --branch ./test.py
if [ 0 != $? ] ; then
    echo "coverage functions failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
eval ${PYCOV} ${PY2LCOV_TOOL} -o functions.info functions.dat $VERSION
if [ 0 != $? ] ; then
    echo "py2lcov failed function example"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# lines test.py:10, 12 should be 'not hit
for line in 10 12 13 ; do
    grep "DA:$line,0" functions.info
    if [ 0 != $? ] ; then
        echo "did not find expected zero hit on function line $line"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done
# look for expected location and function hit counts:
for d in \
    'FN:2,7,enter' \
    'FNDA:1,enter' \
    'FN:10,12,unusedFunc' \
    'FNDA:0,unusedFunc' \
    'FN:13,14,main.localfunc.nested1.nested2' \
    'FNDA:0,main.localfunc.nested1.nested2' \
    'FN:12,16,main.localfunc.nested1' \
    'FNDA:0,main.localfunc.nested1' \
    'FN:10,18,main.localfunc' \
    'FNDA:0,main.localfunc' \
    'FN:5,18,main' \
    'FNDA:1,main' ; do

    grep $d functions.info
    if [ 0 != $? ] ; then
        echo "did not find expected function data $d"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done


# legacy mode:  run with intermediate XML file
COVERAGE_FILE=./functions.dat coverage xml -o functions.xml
if [ 0 != $? ] ; then
    echo "coverage xml failed"
    exit 1
fi

eval ${PYCOV} ${PY2LCOV_TOOL} -i functions.xml -o functions2.info $VERSION
if [ 0 != $? ] ; then
    echo "coverage extract XML failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# result should be identical:
diff functions.info functions2.info
if [ 0 != $? ] ; then
    echo "XML vs direct failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# run again, generating checksum data...
eval ${PYCOV} ${PY2LCOV_TOOL} -o checksum.info functions.dat $VERSION --checksum
if [ 0 != $? ] ; then
    echo "py2lcov failed function example"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

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

# run without generating function data:
eval ${PYCOV} ${PY2LCOV_TOOL} functions.dat -o no_functions.info $VERSION --no-function
if [ 0 != $? ] ; then
    echo "coverage no_functions failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

COUNT=`grep -c FNDA: no_function.info`
if [ 0 != $COUNT ] ; then
    echo "--no-function flag had no effect"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# run without extracting version
eval ${PYCOV} ${PY2LCOV_TOOL} functions.dat -o no_version.info
if [ 0 != $? ] ; then
    echo "coverage no_functions failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

COUNT=`grep -c VER: no_version.info`
if [ 0 != $COUNT ] ; then
    echo "lack of --version flag had no effect"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# test exclusion
eval ${PYCOV} ${PY2LCOV_TOOL} -o excl.info --exclude test.py functions.dat
if [ 0 != $? ] ; then
    echo "coverage no_functions failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

grep -E 'SF:.*test.py' excl.info
if [ 0 == $? ] ; then
    echo "exclude was ignored"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# generate help message:
eval ${PYCOV} ${PY2LCOV_TOOL} --help 2>&1 | tee help.txt
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "help failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep 'usage: py2lcov ' help.txt
if [ 0 != $? ] ; then
    echo "no help message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# some usage errors
eval ${PYCOV} ${PY2LCOV_TOOL} functions.dat -o paramErr.info ${VERSION},-x
if [ 0 == $? ] ; then
    echo "coverage version did not see error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# run again with --keep-going flag - should generate same result as we see without version script
eval ${PYCOV} ${PY2LCOV_TOOL} functions.dat -o keepGoing.info ${VERSION},-x --keep-going --verbose
if [ 0 != $? ] ; then
    echo "keepGoing version saw error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
diff no_version.info keepGoing.info
if [ 0 != $? ] ; then
    echo "no_version vs keepGoing failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# usage error:
# can't run this unless we have a new enough 'coverage' version
#   to support the --data-file input
if [[ "${PYCOV}" =~ "COVERAGE_FILE=" || "${PY2LCOV_TOOL}" =~ "COVERAGE_FILE=" ]] ; then
    ${LCOV_HOME}/bin/py2lcov -o missing.info
else
    eval ${PYCOV} ${PY2LCOV_TOOL} -o missing.info
fi
if [ 0 == $? ] ; then
    echo "did not see error with missing input data"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# usage error:
eval ${PYCOV} ${PY2LCOV_TOOL} -o noFile.info run.dat y.xml
if [ 0 == $? ] ; then
    echo "did not see error with missing input file"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# usage error:
eval ${PYCOV} ${PY2LCOV_TOOL} -o badArg.info --noSuchParam run_help.dat
if [ 0 == $? ] ; then
    echo "did not see error with unsupported param"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# can't run this unless we have a new enough 'coverage' version
#   to support the --data-file input
if [[ "${PYCOV}" =~ "COVERAGE_FILE=" || "${PY2LCOV_TOOL}" =~ "COVERAGE_FILE=" ]] ; then
    # can't generate coverage report for this feature...
    COVERAGE_FILE=functions.dat ${LCOV_HOME}/bin/py2lcov -o fromEnv.info
else
    # get input from environment var:
    eval COVERAGE_FILE=functions.dat ${PYCOV} ${PY2LCOV_TOOL} -o fromEnv.info
fi

if [ 0 != $? ] ; then
    echo "unable to get input file from env. var"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# result should be identical:
diff no_version.info fromEnv.info
if [ 0 != $? ] ; then
    echo "--input vs from env differ"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# aggregate the files - as a syntax check
$COVER $LCOV_TOOL $LCOV_OPTS -o aggregate.info -a functions.info -a no_functions.info $VERSION
if [ 0 != $? ] ; then
    echo "lcov aggregate failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# and the ones that don't have version info...
$COVER $LCOV_TOOL $LCOV_OPTS -o aggregate2.info -a no_version.info -a excl.info
if [ 0 != $? ] ; then
    echo "lcov aggregate2 failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

#check that python filtering works as expected...
$COVER $LCOV_TOOL $LCOV_OPTS -o region.info -a no_version.info --filter region
if [ 0 != $? ] ; then
    echo "lcov filter region failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS -o branch_region.info -a no_version.info --filter branch_region
if [ 0 != $? ] ; then
    echo "lcov filter branch_region failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

DA=`grep -c -E '^DA:' no_version.info`
BR=`grep -c -E '^BRDA:' no_version.info`

REGION_DA=`grep -c -E '^DA:' region.info`
REGION_BR=`grep -c -E '^BRDA:' region.info`

BRANCH_REGION_DA=`grep -c -E '^DA:' branch_region.info`
BRANCH_REGION_BR=`grep -c -E '^BRDA:' branch_region.info`

if [ $REGION_BR != $BRANCH_REGION_BR ] ; then
    echo "wrong branch region branch count $BR -> $BRNCH_BREGION_BR"
    exit 1
fi
if [ $DA != $BRANCH_REGION_DA ] ; then
    echo "wrong branch region line count $DA -> $BRANCH_REGION_DA"
    exit 1
fi

if [ $BR -le $_REGION_BR ] ; then
    echo "wrongregion branch count $BR -> $BREGION_BR"
    exit 1
fi
if [ $DA -le $REGION_DA ] ; then
    echo "wrong region line count $DA -> $REGION_DA"
    exit 1
fi


echo "Tests passed"

if [[ "x$COVER" != "x" && $LOCAL_COVERAGE == 1 ]] ; then
    cover
    ${LCOV_HOME}/bin/perl2lcov -o perlcov.info --testname py2lcov $VERSION ./cover_db
    ${PY2LCOV_TOOL} -o pycov.info --testname py2lcov $VERSION ${PYCOV_DB}
    ${GENHTML_TOOL} -o pycov pycov.info perlcov.info --flat --show-navigation --show-proportion --branch $VERSION $ANNOTATE --ignore inconsistent,version
fi
