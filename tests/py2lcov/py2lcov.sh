#!/bin/bash
set +x

if [[ "x" == ${LCOV_HOME}x ]] ; then
    if [ -f ../../bin/lcov ] ; then
        LCOV_HOME=../..
    fi
fi

source ../common.tst

rm -rf *.xml* *.dat *.info *.json __pycache__ help.txt *.pyc my_cache rpt1 rpt2

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

PY2LCOV_SCRIPT=${LCOV_HOME}/bin/py2lcov

if [ ! -f $LCOV_HOME/scripts/getp4version ] ; then
    # running test from lcov install
    MD5_OPT=',--md5'
fi
# is this git or P4?
if [ 1 == "$IS_P4" ] ; then
    VERSION="--version-script ${SCRIPT_DIR}/P4version.pm,--local-edit${MD5_OPT}"
    ANNOTATE="--annotate-script ${SCRIPT_DIR}/p4annotate.pm,--cache,./my_cache"
    DEPOT=",."
else
    # this is git
    VERSION="--version-script ${SCRIPT_DIR}/gitversion${MD5_OPT}"
    ANNOTATE="--annotate-script ${SCRIPT_DIR}/gitblame.pm,--cache,my_cache"
fi

if [ $IS_GIT == 0 ] && [ $IS_P4 == 0 ] ; then
    VERSION=
    ANNOTATE="$ANNOTATE --ignore annotate"
fi

if [ ! -x $PY2LCOV_SCRIPT ] ; then
    echo "missing py2lcov script - dying"
    exit 1
fi

LCOV_OPTS="--branch-coverage $PARALLEL $PROFILE"


if [ '' != "${COVERAGE_COMMAND}" ] ; then
    CMD=${COVERAGE_COMMAND}
else
    CMD='coverage'
    which $CMD
    if [ 0 != $? ] ; then
        CMD='python3-coverage' # ubuntu?
    fi
fi
which $CMD
if [ 0 != $? ] ; then
    echo "cannot find 'coverage' or 'python3-coverage'"
    echo "unable to run py2lcov - please install python Coverage.py package"
    exit 1
fi

# some corner cases:
COVERAGE_FILE=./functions.dat $CMD  run --branch ./test.py -v -v
if [ 0 != $? ] ; then
    echo "coverage functions failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
eval COVERAGE_COMMAND=$CMD ${PYCOV} ${PY2LCOV_TOOL} -o functions.info --cmd $CMD functions.dat $VERSION
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
    'FN functions.info' \
    'FNL:[0-9],10,12' \
    'FNA:[0-9],0,unusedFunc' \
    'FNL:[0-9],2,7' \
    'FNA:[0-9],1,enter' \
    'FNL:[0-9],10,18' \
    'FNA:[0-9],0,main.localfunc' \
    'FNL:[0-9],12,16' \
    'FNA:[0-9],0,main.localfunc.nested1' \
    'FNL:[0-9],13,14' \
    'FNA:[0-9],0,main.localfunc.nested1.nested2' \
    'FNL:[0-9],5,18' \
    ; do
    grep -E $d functions.info
    if [ 0 != $? ] ; then
        echo "did not find expected function data $d"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

# should be valid data to generate HTML
$GENHTML_TOOL -o rpt1 $VERSION $ANNOTATE functions.info --validate
if [ 0 != $? ] ; then
    echo "genhtml failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# legacy mode:  run with intermediate XML file
COVERAGE_FILE=./functions.dat $CMD xml -o functions.xml
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
eval ${PYCOV} ${PY2LCOV_TOOL} --cmd $CMD -o checksum.info functions.dat $VERSION --checksum
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

if [ $IS_GIT == 0 ] && [ $IS_P4 == 0 ] ; then
    D=
else
    D=$DEPOT
fi
# should be valid data to generate HTML
$GENHTML_TOOL -o rpt2 $VERSION$D $ANNOTATE functions.info checksum.info --validate
if [ 0 != $? ] ; then
    echo "genhtml 2 failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# run without generating function data:
eval ${PYCOV} ${PY2LCOV_TOOL} functions.dat --cmd $CMD -o no_functions.info $VERSION --no-function
if [ 0 != $? ] ; then
    echo "coverage no_functions failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

COUNT=`grep -c FNL: no_function.info`
if [ 0 != $COUNT ] ; then
    echo "--no-function flag had no effect"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# run without extracting version
eval ${PYCOV} ${PY2LCOV_TOOL} functions.dat --cmd $CMD -o no_version.info
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
eval ${PYCOV} ${PY2LCOV_TOOL} -o excl.info --cmd $CMD --exclude test.py functions.dat
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

if [ $IS_GIT == 1 ] || [ $IS_P4 == 1 ] ; then

    # some usage errors
    eval ${PYCOV} ${PY2LCOV_TOOL} functions.dat -o paramErr.info --cmd $CMD ${VERSION},-x
    if [ 0 == $? ] ; then
        echo "coverage version did not see error"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    # run again with --keep-going flag - should generate same result as we see without version script
    eval ${PYCOV} ${PY2LCOV_TOOL} functions.dat -o keepGoing.info --cmd $CMD ${VERSION},-x --keep-going --verbose
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
fi


# usage error:
# can't run this unless we have a new enough 'coverage' version
#   to support the --data-file input
if [[ "${PYCOV}" =~ "COVERAGE_FILE=" || "${PY2LCOV_TOOL}" =~ "COVERAGE_FILE=" ]] ; then
    ${LCOV_HOME}/bin/py2lcov -o missing.info --cmd $CMD
else
    eval ${PYCOV} ${PY2LCOV_TOOL} -o missing.info --cmd $CMD
fi
if [ 0 == $? ] ; then
    echo "did not see error with missing input data"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# usage error:
eval ${PYCOV} ${PY2LCOV_TOOL} -o noFile.info run.dat y.xml --cmd $CMD
if [ 0 == $? ] ; then
    echo "did not see error with missing input file"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# usage error:
eval ${PYCOV} ${PY2LCOV_TOOL} -o badArg.info --noSuchParam run_help.dat --cmd $CMD
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
    COVERAGE_FILE=functions.dat ${LCOV_HOME}/bin/py2lcov -o fromEnv.info --cmd $CMD
else
    # get input from environment var:
    eval COVERAGE_FILE=functions.dat ${PYCOV} ${PY2LCOV_TOOL} -o fromEnv.info --cmd $CMD
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
$COVER $LCOV_TOOL $LCOV_OPTS -o aggregate.info -a functions.info -a no_functions.info $VERSION --ignore inconsistent
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

if [ "$REGION_BR" != "$BRANCH_REGION_BR" ] ; then
    echo "wrong branch region branch count $REGION_BR -> $BRANCH_REGION_BR"
    exit 1
fi
if [ "$DA" != "$BRANCH_REGION_DA" ] ; then
    echo "wrong branch region line count $DA -> $BRANCH_REGION_DA"
    exit 1
fi

if [ "$BR" -le "$REGION_BR" ] ; then
    echo "wrong region branch count $BR -> $REGION_BR"
    exit 1
fi
if [ "$DA" -le "$REGION_DA" ] ; then
    echo "wrong region line count $DA -> $REGION_DA"
    exit 1
fi


echo "Tests passed"

if [[ "x$COVER" != "x" && $LOCAL_COVERAGE == 1 ]] ; then
    cover
    ${LCOV_HOME}/bin/perl2lcov -o perlcov.info --testname py2lcov $VERSION ./cover_db
    ${PY2LCOV_TOOL} -o pycov.info --testname py2lcov --cmd $CMD $VERSION ${PYCOV_DB}
    ${GENHTML_TOOL} -o pycov pycov.info perlcov.info --flat --show-navigation --show-proportion --branch $VERSION $ANNOTATE --ignore inconsistent,version
fi
