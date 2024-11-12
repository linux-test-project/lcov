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

if [ 'x' == "x$XML2LCOV_TOOL" ] ; then
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    PERLLCOV_TOOL=${LCOV_HOME}/bin/perl2lcov
    PY2LCOV_TOOL=${LCOV_HOME}/bin/py2lcov
    XML2LCOV_TOOL=${LCOV_HOME}/bin/xml2lcov
fi

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

rm -rf *.info *.json __pycache__ help.txt *.pyc *.dat

if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover -delete
    rm -rf pycov
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

# NOTE:  the 'coverage.xml' file here is a copy of the one at
#   https://gist.github.com/apetro/fcfffb8c4cdab2c1061d
# except that I removed a huge number of packages - to reduce the
# disk space consumed by the testcase.  There appears to be nothing
# in the remove data that was significant from a test perspective.

# no source - so can't compute version
eval ${PYCOV} ${XML2LCOV_TOOL} -o test.info coverage.xml # $VERSION
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
