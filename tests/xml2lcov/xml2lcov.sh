#!/bin/bash
set +x

if [[ "x" == ${LCOV_HOME}x ]] ; then
    if [ -f ../../bin/lcov ] ; then
        LCOV_HOME=../..
    fi
fi
source ../common.tst

rm -rf *.info *.json __pycache__ help.txt *.pyc *.dat

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi


# is this git or P4?
if [ 1 == "$USE_GIT" ] ; then
    # this is git
    VERSION="--version-script ${SCRIPT_DIR}/gitversion.pm"
    ANNOTATE="--annotate-script ${SCRIPT_DIR}/gitblame.pm"
else
    VERSION="--version-script ${SCRIPT_DIR}/getp4version"
    ANNOTATE="--annotate-script ${SCRIPT_DIR}/p4annotate.pm"
fi

if [ $IS_GIT == 0 ] && [ $IS_P4 == 0 ] ; then
    VERSION="$VERSION --ignore usage"
fi

if [ ! -x $PY2LCOV_SCRIPT ] ; then
    echo "missing py2lcov script - dying"
    exit 1
fi


LCOV_OPTS="--branch-coverage $PARALLEL $PROFILE"


# NOTE:  the 'coverage.xml' file here is a copy of the one at
#   https://gist.github.com/apetro/fcfffb8c4cdab2c1061d
# except that I removed a huge number of packages - to reduce the
# disk space consumed by the testcase.  There appears to be nothing
# in the remove data that was significant from a test perspective.

# no source - so can't compute version
eval ${PYCOV} ${XML2LCOV_TOOL} -o test.info coverage.xml -v -v # $VERSION
if [ 0 != $? ] ; then
    echo "xml2lcov failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# run with verbosity turned on...
eval ${PYCOV} ${XML2LCOV_TOOL} --verbose --verbose -o test.info coverage.xml
if [ 0 != $? ] ; then
    echo "xml2lcov failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# version check should fail - because we have no source
eval ${PYCOV} ${XML2LCOV_TOOL} -o noSource.info coverage.xml $VERSION
if [ 0 == $? ] ; then
    echo "xml2lcov missing source for version check "
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# generate help message:
eval ${PYCOV} ${XML2LCOV_TOOL} --help 2>&1 | tee help.txt
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "help failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep 'usage: xml2lcov ' help.txt
if [ 0 != $? ] ; then
    echo "no help message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# some usage errors
eval ${PYCOV} ${XML2LCOV_TOOL} coverage.xml -o paramErr.info ${VERSION},-x
if [ 0 == $? ] ; then
    echo "coverage version did not see error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

if [ 0 == 1 ] ; then
    # disable this one for now

    # run again with --keep-going flag - should generate same result as we see without version script
    eval ${PYCOV} ${XML2LCOV_TOOL} coverage.xml -o keepGoing.info ${VERSION},-x --keep-going --verbose
    if [ 0 != $? ] ; then
        echo "keepGoing version saw error"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    diff test.info keepGoing.info
    if [ 0 != $? ] ; then
        echo "no_version vs keepGoing failed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
fi


# usage error:
eval ${PYCOV} ${XML2LCOV_TOOL} -o missing.info
if [ 0 == $? ] ; then
    echo "did not see error with missing input data"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# usage error:
eval ${PYCOV} ${XML2LCOV_TOOL} -o noFile.info y.xml
if [ 0 == $? ] ; then
    echo "did not see error with missing input file"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# usage error:
eval ${PYCOV} ${XML2LCOV_TOOL} -o badArg.info --noSuchParam coverage.xml
if [ 0 == $? ] ; then
    echo "did not see error with unsupported param"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# aggregate the files - as a syntax check
#  the file contains inconsistent data for 'org/jasig/portal/EntityTypes.java'
#  function 'mapRow' is declared twice at different locations and
#  overlaps with a previous decl
$COVER $LCOV_TOOL $LCOV_OPTS -o aggregate.info -a test.info --ignore inconsistent
if [ 0 != $? ] ; then
    echo "lcov aggregate failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo "Tests passed"

if [[ "x$COVER" != "x" && $LOCAL_COVERAGE == 1 ]] ; then
    cover
    ${PY2LCOV_TOOL} -o pycov.info --testname xml2lcov $VERSION ${PYCOV_DB}
    ${GENHTML_TOOL} -o pycov pycov.info --flat --show-navigation --show-proportion --branch $VERSION $ANNOTATE --ignore inconsistent,version,annotate
fi
