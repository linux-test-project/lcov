#!/bin/bash
#
# Check if --gcov-tool works with relative path specifications.
#

export CC="${CC:-gcc}"

TOOLS=( "$CC" "gcov" )

function check_tools() {
        local tool

        for tool in "${TOOLS[@]}" ; do
                if ! type -P "$tool" >/dev/null ; then
                        echo "Error: Missing tool '$tool'"
                        exit 2
                fi
        done
}

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
            if [[ "$1"x != 'x' &&  $1 != "-"* ]] ; then
               COVER_DB=$1
               LOCAL_COVERAGE=0
               shift
            fi
            COVER="perl -MDevel::Cover=-db,$COVER_DB,-coverage,statement,branch,condition,subroutine "
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
           LCOV_HOME=../../../../releng/coverage/lcov
       fi
fi
LCOV_HOME=`(cd ${LCOV_HOME} ; pwd)`

if [[ ! ( -d $LCOV_HOME/bin && -d $LCOV_HOME/lib && -x $LCOV_HOME/bin/genhtml && ( -f $LCOV_HOME/lib/lcovutil.pm || -f $LCOV_HOME/lib/lcov/lcovutil.pm ) ) ]] ; then
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

rm -f test *.gcno *.gcda

if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover -delete
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

check_tools


echo "Build test program"
"$CC" test.c -o test --coverage
if [ 0 != $? ] ; then
    echo "compile failed"
    exit 1
fi

echo "Run test program"
./test
if [ 0 != $? ] ; then
    echo "test execution failed"
    exit 1
fi

status=0
for TOOL in "$LCOV_TOOL --capture -d" "$GENINFO_TOOL" ; do

    : "-----------------------------"
    : "No gcov-tool option"
    : "-----------------------------"
    $COVER $TOOL . -o test.info --verbose
    if [ 0 != $? ] ; then
        echo "failed vanilla"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    fi

    : "-----------------------------"
    : "gcov-tool option without path"
    : "-----------------------------"
    $COVER $TOOL . -o test.info --verbose --gcov-tool "gcov"
    if [ 0 != $? ] ; then
        echo "failed gcov"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    fi

    : "-----------------------------"
    : "gcov-tool option with absolute path"
    : "-----------------------------"
    $COVER $TOOL . -o test.info --verbose --gcov-tool "$PWD/mygcov.sh"
    if [ 0 != $? ] ; then
        echo "failed script"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    fi

    : "-----------------------------"
    : "gcov-tool option with relative path"
    : "-----------------------------"
    $COVER $TOOL . -o test.info --verbose --gcov-tool "./mygcov.sh"
    if [ 0 != $? ] ; then
        echo "failed relative script"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    fi

    : "-----------------------------"
    : "gcov-tool option specifying nonexistent tool without path"
    : "-----------------------------"
    $COVER $TOOL . -o test.info --verbose --gcov-tool gcov.nonexistent
    if [ 0 == $? ] ; then
        echo "missing tool: should have failed"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    fi

    : "-----------------------------"
    : "gcov-tool option specifying nonexistent tool with absolute path"
    : "-----------------------------"
    $COVER $TOOL . -o test.info --verbose --gcov-tool "/gcov.nonexistent"
    if [ 0 == $? ] ; then
        echo "should have failed absolute path"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    fi

    : "-----------------------------"
    : "gcov-tool option specifying nonexistent tool with relative path"
    : "-----------------------------"
    $COVER $TOOL . -o test.info --verbose --gcov-tool "./gcov.nonexistent"
    if [ 0 == $? ] ; then
        echo "should have failed relative nonexistent"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    fi
done

if [ 0 == $status ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi

exit $status
