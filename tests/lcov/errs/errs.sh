#!/bin/bash
set +x

CLEAN_ONLY=0
COVER=

PARALLEL='--parallel 0'
PROFILE="--profile"
CC="${CC:-gcc}"
CXX="${CXX:-g++}"
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
            COVER="perl -MDevel::Cover=-db,$COVER_DB,-coverage,statement,branch,condition,subroutine,-silent,1 "
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

ROOT=`pwd`
PARENT=`(cd .. ; pwd)`

LCOV_OPTS="--branch $PARALLEL $PROFILE"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
    # and filter exception branches to avoid spurious differences for old compiler
    FILTER='--filter branch'
fi

rm -f  *.log *.json dumper*
rm -rf emptyDir

if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover -delete
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

status=0

for f in badFncLine badFncEndLine fncMismatch badBranchLine badLine ; do
    echo lcov $LCOV_OPTS --summary $f.info
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info 2>&1 | tee $f.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "failed to notice incorrect decl in $f"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    grep -E '(unexpected|mismatched) .*line' $f.log
    if [ 0 != $? ] ; then
        echo "missing error message"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi

    echo lcov $LCOV_OPTS --summary $f.info --ignore inconsistent
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info --ignore inconsistent 2>&1 | tee ${f}2.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "failed to ignore message ${f}2.log"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
done

for f in noFunc ; do
    echo lcov $LCOV_OPTS --summary $f.info
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info 2>&1 | tee $f.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "failed to notice incorrect decl in $f"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    grep -E 'unknown function' $f.log
    if [ 0 != $? ] ; then
        echo "missing error message"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi

    echo lcov $LCOV_OPTS --summary $f.info --ignore mismatch
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info --ignore mismatch 2>&1 | tee ${f}2.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "failed to ignore message ${f}2.log"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
done

for f in emptyFileRecord ; do
    echo lcov $LCOV_OPTS --summary $f.info
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info 2>&1 | tee $f.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "failed to notice incorrect decl in $f"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    grep -E 'unexpected empty file name' $f.log
    if [ 0 != $? ] ; then
        echo "missing error message"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi

    echo lcov $LCOV_OPTS --summary $f.info --ignore mismatch
    $COVER $LCOV_TOOL $LCOV_OPTS --summary $f.info --ignore format 2>&1 | tee ${f}2.log
    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "failed to ignore message ${f}2.log"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
done


for f in exceptionBranch ; do
    echo lcov $LCOV_OPTS -a ${f}1.info -a ${f}2.info -o $f.out
    $COVER $LCOV_TOOL $LCOV_OPTS -a ${f}1.info -a ${f}2.info -o $f.out 2>&1 | tee $f.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "failed to notice incorrect decl in $f"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    grep -E 'mismatched exception tag' $f.log
    if [ 0 != $? ] ; then
        echo "missing error message"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
    if [ -f $f.out ] ; then
        echo "should not have created file, on error"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi

    echo lcov $LCOV_OPTS -a ${f}1.info -a ${f}2.info --ignroe mismatch -o ${f}2.log
    $COVER $LCOV_TOOL $LCOV_OPTS -a ${f}1.info -a ${f}2.info --ignore mismatch -o $f.log

    if [ 0 != ${PIPESTATUS[0]} ] ; then
        echo "failed to ignore message ${f}2.log"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit $status
        fi
    fi
done

mkdir -p emptyDir

echo lcov $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info
$COVER $LCOV_TOOL $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info 2>&1 | tee emptyDir.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "failed to notice empty dir"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit $status
    fi
fi
grep 'no files matching' emptyDir.log
if [ 0 != $? ] ; then
    echo "did not find expected empty dir message"
fi
echo lcov $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info --ignore empty
$COVER $LCOV_TOOL $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info --ignore empty 2>&1 | tee emptyDir2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "failed to ignore empty dir"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit $status
    fi
fi

# trigger error from unreadable directory
chmod ugo-rx emptyDir
echo lcov $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info
$COVER $LCOV_TOOL $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info 2>&1 | tee noRead.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "failed to notice unreadable"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit $status
    fi
fi
grep 'error in "find' noRead.log
if [ 0 != $? ] ; then
    echo "did not find expected unreadable dir message"
fi
echo lcov $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info --ignore utility,empty
$COVER $LCOV_TOOL $LCOV_OPTS -a emptyDir -a exceptionBranch1.info -o emptyDir.info --ignore utility,empty 2>&1 | tee noRead2.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "failed to ignore unreadable dir"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit $status
    fi
fi


if [ 0 == $status ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi

exit $status
