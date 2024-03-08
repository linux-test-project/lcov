#!/bin/bash
set +x

CLEAN_ONLY=0
COVER=
UPDATE=0
PARALLEL='--parallel 0'
PROFILE="--profile"
CXX='g++'
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
            if [[ "$1"x != 'x' && $1 != "-"*  ]] ; then
               COVER_DB=$1
               LOCAL_COVERAGE=0
               shift
            fi
            if [ ! -d ${COVER_DB} ] ; then
                mkdir -p ${COVER_DB}
            fi
            COVER="perl -MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine "
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

        --update )
            UPDATE=1
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
if [ -f $LCOV_HOME/scripts/getp4version ] ; then
    SCRIPTS_DIR=$LCOV_HOME/scripts
else
    SCRIPTS_DIR=$LCOV_HOME/share/lcov/support-scripts
fi
GET_VERSION=$SCRIPTS_DIR/getp4version
SELECT_SCRIPT=$SCRIPTS_DIR/select.pm
CRITERIA_SCRIPT=$SCRIPTS_DIR/criteria.pm
ANNOTATE_SCRIPT=$SCRIPTS_DIR/p4annotate.pm


# filter out the compiler-generated _GLOBAL__sub_... symbol
LCOV_BASE="$EXTRA_GCOV_OPTS --branch-coverage $PARALLEL $PROFILE --no-external --ignore unused,unsupported --erase-function .*GLOBAL.*"
LCOV_OPTS="$LCOV_BASE"
DIFFCOV_OPTS="--filter line,branch,function --function-coverage --branch-coverage --highlight --demangle-cpp --prefix $PARENT_VERSION $PROFILE "

rm -f test.cpp *.gcno *.gcda a.out *.info *.log *.json diff.txt
rm -rf select criteria annotate empty unused_src

if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover -delete
fi

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type "${CXX}" >/dev/null 2>&1 ; then
        echo "Missing tool: $CXX" >&2
        exit 2
fi

echo `which gcov`
echo `which lcov`

ln -s ../simple/simple.cpp test.cpp
${CXX} --coverage test.cpp
./a.out

# old version of gcc has inconsistent line/function data
IFS='.' read -r -a VER <<< `gcc -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    # can't get branch coverpoints in 'initial' mode, with ancient GCC
    IGNORE="--ignore usage"
fi

# some warnings..
echo lcov $LCOV_OPTS --capture --directory .  --initial --all --output-file initial.info --test-name myTest $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --initial --all --output-file initial.info --test-name myTest $IGNORE 2>&1 | tee initial_all.log
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -- "'--all' ignored" initial_all.log
if [ 0 != $? ] ; then
    echo "ERROR: missing ignore message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# need data for version error message checking as well
echo lcov $LCOV_OPTS --capture --directory .  --output-file version.info --test-name myTest --version-script $SCRIPTS_DIR/getp4version
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory .  --output-file version.info --test-name myTest --version-script $SCRIPTS_DIR/getp4version | tee version.log
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# help message
for T in "$GENHTML_TOOL" "$LCOV_TOOL" "$GENINFO_TOOL" ; do
    echo  "'$T' --help"
    $COVER $T --help
    if [ 0 != $? ] ; then
        echo "unsuccessful $T help"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    echo  "'$T' --noSuchOppt"
    $COVER $T --noSuchOpt
    if [ 0 == $? ] ; then
        echo "didn't catch missing opt"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

# generate some usage errors..
echo lcov $LCOV_OPTS --list initial.info --initial
$COVER $LCOV_TOOL $LCOV_OPTS --list initial.info --initial 2>&1 | tee initial_warn.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --list failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "'--initial' is ignored" initial_warn.log
if [ 0 != $? ] ; then
    echo "ERROR: missing ignore message 2"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo lcov $LCOV_OPTS --summary initial.info --prune
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --prune 2>&1 | tee prune_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --summary 3 failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep 'prune-tests has effect' prune_err.log
if [ 0 != $? ] ; then
    echo "ERROR: missing ignore message 2"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo lcov $LCOV_OPTS --summary initial.info --prune --ignore usage
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --prune --ignore usgae 2>&1 | tee prune_warn.log

echo lcov $LCOV_OPTS --capture -d . -o build.info --build-dir x/y
$COVER $LCOV_TOOL $LCOV_OPTS --capture -d . -o build.info --build-dir x/y 2>&1 | tee build_dir_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --list failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "'x/y' is not a directory" build_dir_err.log
if [ 0 != $? ] ; then
    echo "ERROR: missing build dir message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo lcov $LCOV_OPTS --summary initial.info --config-file noSuchFile --ignore usage
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --config-file noSuchFile --ignore usgae 2>&1 | tee err_missing.log
grep "cannot read configuration file 'noSuchFile'" err_missing.log
if [ 0 != $? ] ; then
    echo "ERROR: missing config file message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo lcov $LCOV_OPTS --capture -d . -o build.info --build-dir $LCOV_HOME
$COVER $LCOV_TOOL $LCOV_OPTS --capture -d . -o build.info --build-dir $LCOV_HOME 2>&1 | tee build_dir_unused.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --list failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "\"--build-directory .* is unused" build_dir_unused.log
if [ 0 != $? ] ; then
    echo "ERROR: missing build dir unused message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


echo lcov $LCOV_OPTS --summary initial.info --rc memory_percentage=-10
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --rc memory_percentage=-10 2>&1 | tee mem_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --summary 4 failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "memory_percentage '-10' " mem_err.log
if [ 0 != $? ] ; then
    echo "ERROR: missing percent message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo lcov $LCOV_OPTS --summary initial.info --rc memory_percentage=-10 --ignore usage
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --rc memory_percentage=-10 --ignore usage 2>&1 | tee mem_warn.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov memory usage failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo genhtml $DIFCOV_OPTS initial.info -o select --select-script $SELECT_SCRIPT --select-script -x
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o select --select-script $SELECT_SCRIPT --select-script -x 2>&1 | tee script_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml select passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "unable to create callback from" script_err.log
if [ 0 != $? ] ; then
    echo "ERROR: missing script message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

for arg in "--select-script $SELECT_SCRIPT" \
               "--criteria-script $CRITERIA_SCRIPT" \
               "--annotate-script $ANNOTATE_SCRIPT" \
           ; do
    echo genhtml $DIFCOV_OPTS initial.info -o scriptErr ${arg},-x
    $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o scriptErr ${arg},-x 2>&1 | tee script_err.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        echo "ERROR: genhtml scriptErr passed by accident"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    grep "unable to create callback from" script_err.log
    if [ 0 != $? ] ; then
        echo "ERROR: missing script message"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

echo genhtml $DIFCOV_OPTS initial.info -o select --select-script ./select.sh --rc compute_file_version=1
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o select --select-script ./select.sh  --rc compute_file_version=1 2>&1 | tee select_scr.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml compute_version failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ 0 != $? ] ; then
    echo "ERROR: trivial select failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "'compute_file_version=1' option has no effect" select_scr.log
if [ 0 != $? ] ; then
    echo "ERROR: missing script message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# and again, as a differential report with annotation
NOW=`date`
echo genhtml $DIFCOV_OPTS initial.info -o select --select-script ./select.sh --annotate $SCRIPTS_DIR/p4annotate --baseline-file initial.info
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o select --select-script ./select.sh --annotate $SCRIPTS_DIR/p4annotate --baseline-file initial.info --title 'selectExample' --header-title 'this is the header' --date-bins 1,5,22 --baseline-date "$NOW" --prefix x --no-prefix 2>&1 | tee select_scr.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml select failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# differntial report with empty diff file
touch diff.txt
echo genhtml $DIFCOV_OPTS initial.info -o empty --diff diff.txt --annotate $SCRIPTS_DIR/p4annotate --baseline-file initial.info
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o empty --diff diff.txt --annotate $SCRIPTS_DIR/p4annotate --baseline-file initial.info 2>&1 | tee empty_diff.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml select failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "'diff' data file diff.txt contains no differences" empty_diff.log
if [ 0 != $? ] ; then
    echo "ERROR: missing empty message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# insensitive flag with case-sensitive substitute expr
#   - this will trigger multiple usage messages, but we set the max count
#     to 1 (one) - to also trigger a 'count exceeded' message.
echo lcov $LCOV_OPTS --summary initial.info --substitute 's#aBc#AbC#' --substitute 's@XyZ#xyz#i' --rc case_insensitive=1 --ignore source --rc max_message_count=1
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --substitute 's#aBc#AbC#' --rc case_insensitive=1 --ignore source --rc max_message_count=1 2>&1 | tee insensitive.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --summary insensitive"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep " --substitute pattern 's#aBc#AbC#' does not seem to be case insensitive" insensitive.log
if [ 0 != $? ] ; then
    echo "ERROR: missing insensitive message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep " (count) max_message_count=1 reached for 'usage' messages: no more will be reported." insensitive.log
if [ 0 != $? ] ; then
    echo "ERROR: missing max count message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi


# callback error testing
#  die() in 'extract' callback:
echo lcov $LCOV_OPTS --summary version.info --filter line--version-script ./genError.pm
$COVER $LCOV_TOOL $LCOV_OPTS --summary version.info --filter line --version-script ./genError.pm 2>&1 | tee extract_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov extract passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "extract_version.+ failed" extract_err.log
if [ 0 != $? ] ; then
    echo "ERROR: extract_version message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# pass 'extract' but die in check (need to check version in order to filter)
echo lcov $LCOV_OPTS --summary version.info --filter line --version-script ./genError.pm --version-script extract
$COVER $LCOV_TOOL $LCOV_OPTS --summary version.info --filter line --version-script ./genError.pm --version-script extract 2>&1 | tee extract_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov extract passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "compare_version.+ failed" extract_err.log
if [ 0 != $? ] ; then
    echo "ERROR: compare_version message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# resolve
echo lcov $LCOV_OPTS --summary initial.info --rc case_insensitive=1 --resolve ./genError.pm
$COVER $LCOV_TOOL $LCOV_OPTS --summary initial.info --rc case_insensitive=1 --resolve ./genError.pm 2>&1 | tee resolve_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: lcov --summary resolve"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "resolve.+ failed" resolve_err.log
if [ 0 != $? ] ; then
    echo "ERROR: resolve message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

for callback in select annotate criteria ; do

  echo genhtml $DIFCOV_OPTS initial.info -o $callback --${callback}-script ./genError.pm
  $COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o $callback --${callback}-script ./genError.pm 2>&1 | tee ${callback}_err.log
  if [ 0 == ${PIPESTATUS[0]} ] ; then
      echo "ERROR: genhtml $callback error passed by accident"
      if [ 0 == $KEEP_GOING ] ; then
          exit 1
      fi
  fi
  grep -E "${callback}.* failed" ${callback}_err.log
  if [ 0 != $? ] ; then
      echo "ERROR: $callback message"
      if [ 0 == $KEEP_GOING ] ; then
          exit 1
      fi
  fi
done

echo genhtml $DIFCOV_OPTS initial.info -o unused_src --source-dir ../..
$COVER $GENHTML_TOOL $DIFFCOV_OPTS initial.info -o unused_src --source-dir ../.. 2>&1 | tee src_err.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: genhtml source-dir error passed by accident"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E -- '"--source-directory ../.." is unused' src_err.log
if [ 0 != $? ] ; then
    echo "ERROR: missing srcdir message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
                
echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    cover
fi
