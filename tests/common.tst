# common utility for testing - mainly argument parsing

CLEAN_ONLY=0
COVER=

PARALLEL='--parallel 0'
PROFILE="--profile"
LOCAL_COVERAGE=1
KEEP_GOING=0

#echo "CMD:  $0 $@"

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

        --keep-going | -k )
            KEEP_GOING=1
            ;;

        --coverage )
            if [[ "$1"x != 'x' && $1 != "-"*  ]] ; then
               COVER_DB=$1
               LOCAL_COVERAGE=0
               shift
            else
                COVER_DB='cover_db.dat'
            fi
            export PYCOV_DB="${COVER_DB}_py"
            COVER="perl -MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine,-silent,1 "

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

            PYCOVER="COVERAGE_FILE=$PYCOV_DB $CMD run --branch --append"
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

        --llvm )
            LLVM=1
            module load como/tools/llvm-gnu/11.0.0-1
            # seems to have been using same gcov version as gcc/4.8.3
            module load gcc/4.8.3
            #EXTRA_GCOV_OPTS="--gcov-tool '\"llvm-cov gcov\"'"
            CXX="clang++"
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
    echo "LCOV_HOME '$LCOV_HOME' seems not to be valid"
    exit 1
fi

export PATH=${LCOV_HOME}/bin:${LCOV_HOME}/share:${PATH}
export MANPATH=${MANPATH}:${LCOV_HOME}/man

ROOT=`pwd`
PARENT=`(cd .. ; pwd)`
if [ -f $LCOV_HOME/scripts/getp4version ] ; then
    SCRIPT_DIR=$LCOV_HOME/scripts
else
    # running test from lcov install
    SCRIPT_DIR=$LCOV_HOME/share/lcov/support-scripts
    MD5_OPT='--version-script --md5'
fi
if [ 'x' == "x$GENHTML_TOOL" ] ; then
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    GENINFO_TOOL=${LCOV_HOME}/bin/geninfo
    SPREADSHEET_TOOL=${SCRIPT_DIR}/spreadsheet.py
    LLVM2LCOV_TOOL=${LCOV_HOME}/bin/llvm2lcov
    PERL2LCOV_TOOL=${LCOV_HOME}/bin/perl2lcov
    PY2LCOV_TOOL=${LCOV_HOME}/bin/py2lcov
    XML2LCOV_TOOL=${LCOV_HOME}/bin/xml2lcov
fi

# is this git or P4?
IS_GIT=0
IS_P4=0
git -C . rev-parse > /dev/null 2>&1
if [ 0 == $? ] ; then
    # this is git
    IS_GIT=1
else
    p4 have ... > /dev/null 2>&1
    if [ 0 == $? ] ; then
        IS_P4=1
    fi
fi

if [ "$IS_GIT" == 1 ] || [ "$IS_P4" == 0 ] ; then
    USE_GIT=1
    GET_VERSION=${SCRIPT_DIR}/gitversion.pm
    GET_VERSION_EXE=${SCRIPT_DIR}/gitversion
    ANNOTATE=${SCRIPT_DIR}/gitblame.pm
else
    USE_P4=1
    GET_VERSION=${SCRIPT_DIR}/getp4version
    GET_VERSION_EXE=${SCRIPT_DIR}/getp4version
    ANNOTATE=${SCRIPT_DIR}/p4annotate.pm
fi
CRITERIA=${SCRIPT_DIR}/criteria
SELECT=${SCRIPT_DIR}/select.pm

function clean_cover()
{
    if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
        if [ -d $COVER_DB ] ; then
            cover -delete -db $COVER_DB
        fi
        rm -rf $PYCOV_DB
    fi
}
