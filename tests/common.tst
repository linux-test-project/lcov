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
	    PERL_COVER_ARGS="-MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine,-silent,1 "
            COVER="perl $PERL_COVER_ARGS"

            # A coverage run which was killed - a Ctrl-C, the harness
            # per-test timeout, the OOM killer - can leave a zero-length
            # 'digests' file behind:  Devel::Cover writes that file by
            # unlinking it, re-creating it empty and only then encoding into
            # it, and its reader checks that the file exists but not that it
            # has any content.  From then on every instrumented process using
            # this database aborts in BEGIN with "bad Sereal decoder usage",
            # so the testcase fails with whatever symptom that produces - an
            # exit status it did not expect, a tool which appears to have done
            # nothing - and stays failed on every later run until the database
            # is removed by hand.  The file is only a cache mapping a source
            # digest to the name coverage is recorded under, so dropping it
            # costs nothing:  Devel::Cover writes it again at exit.
            if [ -d "$COVER_DB" ] && [ -f "$COVER_DB/digests" ] &&
               [ ! -s "$COVER_DB/digests" ] ; then
                echo "removing empty $COVER_DB/digests left by a killed run"
                rm -f "$COVER_DB/digests"
            fi

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
    HTML2LCOV_TOOL=${LCOV_HOME}/bin/html2lcov
fi

# --------------------------------------------------------------------------
# Keep the gcov the tools capture with matched to the compiler the testcases
# build with.
#
# A testcase compiles its fixture with $CC or $CXX and then captures it with
# geninfo, whose gcov is whatever 'gcov' PATH happens to find first.  Those are
# the same toolchain only by convention:  'module load gcc/N' puts the matching
# gcc and gcov on PATH together, but naming a compiler directly - 'make
# CC=/usr/bin/gcc check' - leaves geninfo reading gcc 8's .gcno with, say, gcc
# 16's gcov.  The .gcno version tags do not match, geninfo raises
# ERROR_VERSION, and every test which captures real data fails for a reason
# which has nothing to do with what it tests.
#
# A compiler's own gcov is its sibling, so when that exists and reports a
# different version from the one on PATH, capture with it instead:
# 'geninfo_gcov_tool' goes on the capture tools below, where an explicit
# '--gcov-tool' still overrides it.  When the two agree - the usual case - $GCOV
# is simply the gcov already on PATH and nothing about the run changes.
#
# One gcov cannot match two toolchains, so if $CC and $CXX turn out to be
# different ones there is no setting which serves both:  $CC wins and the other
# is reported, because a C++ testcase failing on a .gcno version tag is a great
# deal harder to recognise than a line saying which gcov the run chose.
#
# $GCOV is exported because a testcase which asks gcov about itself has to ask
# the same one:  tests/lcov/coverage/geninfo.sh decides from 'gcov --help'
# whether the capture it is about to check can work at all, and answering that
# from the wrong gcov is as wrong as reading with it.
# --------------------------------------------------------------------------
GCOV=$(command -v gcov 2>/dev/null)
GCOV_TOOL_RC=
MATCHED_GCOV=
MATCHED_COMPILER=
for COMPILER in "${CC:-gcc}" "${CXX:-g++}" ; do
    RESOLVED=$(command -v "$COMPILER" 2>/dev/null)
    # a compiler named with flags ('CC=gcc -m32'), or one whose directory has
    #   no gcov of its own (a ccache wrapper, say), tells us nothing
    if [ -z "$RESOLVED" ] || [ ! -x "$(dirname "$RESOLVED")/gcov" ] ; then
        continue
    fi
    SIBLING=$(dirname "$RESOLVED")/gcov
    if [ -z "$MATCHED_GCOV" ] ; then
        MATCHED_GCOV=$SIBLING
        MATCHED_COMPILER=$RESOLVED
    elif [ "$SIBLING" != "$MATCHED_GCOV" ] ; then
        echo "warning: '$RESOLVED' is not the toolchain of '$MATCHED_COMPILER'"
        echo "warning: capturing with '$MATCHED_GCOV' - testcases built with" \
             "'$RESOLVED' may fail on the .gcno version"
    fi
done
if [ -n "$MATCHED_GCOV" ] && [ "$MATCHED_GCOV" != "$GCOV" ] &&
   [ "$("$MATCHED_GCOV" --version 2>/dev/null | head -1)" != \
     "$("$GCOV" --version 2>/dev/null | head -1)" ] ; then
    echo "using gcov '$MATCHED_GCOV' to match compiler '$MATCHED_COMPILER'"
    GCOV=$MATCHED_GCOV
    GCOV_TOOL_RC="--rc geninfo_gcov_tool=$GCOV"
fi
export GCOV
if [ -n "$GCOV_TOOL_RC" ] ; then
    LCOV_TOOL="$LCOV_TOOL $GCOV_TOOL_RC"
    GENINFO_TOOL="$GENINFO_TOOL $GCOV_TOOL_RC"
    # $LCOV is $LCOV_TOOL plus the testsuite lcovrc - it comes from
    #   common.mak, so it exists only when the test was started by 'make'
    if [ -n "$LCOV" ] ; then
        LCOV="$LCOV $GCOV_TOOL_RC"
    fi
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
        rm -f cover.log
    fi
}

function generate_coverage()
{
    TESTNAME=$1
    LOCAL_COVERAGE=$2
    PYCOV_COVERAGE=$3

    INFO_FILES='perlcov.info'
    echo "Generating coverage report for $TESTNAME"
    if [ "$PYCOV_COVERAGE" == 1 ] ; then
	echo ${LCOV_HOME}/bin/py2lcov -o pycov.info --test-name $TESTNAME --version-script $GET_VERSION $PYCOV_DB
	${LCOV_HOME}/bin/py2lcov -o pycov.info --test-name TESTNAME --version-script $GET_VERSION $PYCOV_DB
	INFO_FILES="$INFO_FILES pycov.info"
    fi
    if [ 0 != "$LOCAL_COVERAGE" ] ; then
        cover $COVER_DB > cover.log 2>&1
        ${LCOV_HOME}/bin/perl2lcov -o perlcov.info --test-name $TESTNAME --version-script $GET_VERSION $COVER_DB --ignore inconsistent
        ${LCOV_HOME}/bin/genhtml -o html_report $INFO_FILES --branch --flat --show-navigation --show-proportion --version-script $GET_VERSION --annotate-script $ANNOTATE --parallel --ignore empty,usage,inconsistent
        echo "see HTML report 'html_report'"
    fi
}
