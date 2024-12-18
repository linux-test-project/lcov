#! /usr/bin/env bash
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
       if [ -f ../../../bin/lcov ] ; then
           LCOV_HOME=../../..
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
    GENINFO_TOOL=${LCOV_HOME}/bin/geninfo
    LLVM2LCOV_TOOL=${LCOV_HOME}/bin/llvm2lcov
    PERL2LCOV_TOOL=${LCOV_HOME}/bin/perl2lcov
fi

if [ -f $LCOV_HOME/scripts/getp4version ] ; then
    SCRIPT_DIR=$LCOV_HOME/scripts
else
    # running test from lcov install
    SCRIPT_DIR=$LCOV_HOME/share/lcov/support-scripts
fi
# is this git or P4?
git -C . rev-parse > /dev/null 2>&1
if [ 0 == $? ] ; then
    # this is git
    GET_VERSION=${SCRIPT_DIR}/gitversion.pm
else
    GET_VERSION=${SCRIPT_DIR}/P4version.pm,--local-edit,--md5
fi

ROOT=`pwd`
PARENT=`(cd .. ; pwd)`

LCOV_OPTS="--branch-coverage $PARALLEL $PROFILE"

rm -rf *.xml *.dat *.info *.jsn cover_one *_rpt *Test[123]*

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover -delete
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -ge 14 ] ; then
    ENABLE_MCDC=1
fi
IFS='.' read -r -a LLVM_VER <<< `clang -dumpversion`
if [ "${LLVM_VER[0]}" -ge 14 ] ; then
    ENABLE_LLVM=1
fi

STATUS=0

function runClang()
(
    # runClang exeName srcFile flags
    clang++ -fprofile-instr-generate -fcoverage-mapping -fcoverage-mcdc -o $1 main.cpp test.cpp $2
    if [ $? != 0 ] ; then
        echo "ERROR from clang++ $1"
        return 1
    fi
    ./$1
    llvm-profdata merge --sparse *.profraw -o $1.profdata
    if [ $? != 0 ] ; then
        echo "ERROR from llvm-profdata $1"
        return 1
    fi
    llvm-cov export -format=text -instr-profile=$1.profdata ./$1 > $1.jsn
    if [ $? != 0 ] ; then
        echo "ERROR from llvm-cov $1"
        return 1
    fi
    $COVER $LLVM2LCOV_TOOL --branch --mcdc -o $1.info $1.jsn --version-script $GET_VERSION
    if [ $? != 0 ] ; then
        echo "ERROR from llvm2lcov $1"
        return 1
    fi
    $COVER $GENHTML_TOOL --flat --branch --mcdc -o $1_rpt $1.info --version-script $GET_VERSION
    if [ $? != 0 ] ; then
        echo "ERROR from genhtml $1"
        return 1
    fi
    # run again, excluding 'main.cpp'
    $COVER $LLVM2LCOV_TOOL --branch --mcdc -o $1.excl.info $1.jsn --version-script $GET_VERSION --exclude '*/main.cpp'
    if [ $? != 0 ] ; then
        echo "ERROR from llvm2lcov --exclude $1"
        return 1
    fi
    COUNT=`grep -c SF: $1.excl.info`
    if [ 1 != "$COUNT" ] ; then
        echo "ERROR llvm2lcov --exclude $1 didn't work"
        return 1
    fi
    rm -f *.profraw *.profdata
)

function runGcc()
{
    # runGcc exeName srcFile flags
    g++ --coverage -fcondition-coverage -o $1 main.cpp test.cpp $2
    if [ $? != 0 ] ; then
        echo "ERROR from g++ $1"
        return 1
    fi
    ./$1
    $COVER $GENINFO_TOOL -o $1.info --mcdc --branch $1-test.gcda
    if [ $? != 0 ] ; then
        echo "ERROR from geninfo $1"
        return 1
    fi
    $COVER $GENHTML_TOOL --flat --branch --mcdc -o $1_rpt $1.info
    if [ $? != 0 ] ; then
        echo "ERROR from genhtml $1"
        return 1
    fi
    rm -f *.gcda *.gcno
}


$COVER $LLVM2LCOV_TOOL --help
if [ 0 != $? ] ; then
    echo "ERROR: unexpected return code from --help"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

$COVER $LLVM2LCOV_TOOL --unknown_arg
if [ 0 == $? ] ; then
    echo "ERROR: expected return code from --help"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi


if [ "$ENABLE_MCDC" == 1 ] ; then
    runGcc gccTest1
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    runGcc gccTest2 -DSENS1
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    runGcc gccTest3 -DSENS2
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
else
    echo "SKIPPING MC/DC tests:  ancient compiler"
fi

if [ "$ENABLE_LLVM" == 1 ] ; then
    runClang clangTest1
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    runClang clangTest2 -DSENS1
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    runClang clangTest3 -DSENS2
    if [ $? != 0 ] ; then
        STATUS=1
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
else 
    echo "SKIPPING LLVM tests"
fi

if [ $STATUS == 0 ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi

exit $STATUS
