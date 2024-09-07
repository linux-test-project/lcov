#!/usr/bin/env bash

COVER_DB='cover_db'
LOCAL_COVERAGE=1
KEEP_GOING=0
COVER=

echo "LCOV = $LCOV"
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
            if [[ "$1"x != 'x' && $1 != "-"*  ]] ; then
               COVER_DB=$1
               LOCAL_COVERAGE=0
               shift
            fi
            echo $LCOV
            if [[ $LCOV =~ 'perl' ]] ; then
                # cover command already included - don't include again
                COVER=
            else
                COVER="perl -MDevel::Cover=-db,$COVER_DB,-coverage,statement,branch,condition,subroutine "
            fi
            KEEP_GOING=1
            ;;

        --home | -home )
            LCOV_HOME=$1
            shift
            if [ ! -f $LCOV_HOME/bin/lcov ] ; then
                echo "LCOV_HOME '$LCOV_HOME' does not exist"
                exit 1
            fi
            ;;


        * )
            echo "Error: unexpected option '$OPT'"
            exit 1
            ;;
    esac
done

if [ 'x' == "x$GENHTML_TOOL" ] ; then
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    GENINFO_TOOL=${LCOV_HOME}/bin/geninfo
fi

if [ "x$COVER" != 'x' ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover -delete
fi

# adding zero does not change anything
$COVER $LCOV_TOOL -o prune -a $FULLINFO -a $ZEROINFO --prune
if [[ $? != 0 && $KEEP_GOING != 1 ]] ; then
    echo "lcov -prune failed"
    exit 1
fi
PRUNED=`cat prune`
if [ "$PRUNED" != "$FULLINFO" ] ; then
        echo "Expected '$FULLINFO' - got '$PRUNED'"
        exit 1
fi

# expect that all the additions did something...
#  note that the generated data is inconsistent:  sometimes, function
#  has zero hit count but some contained lines are hit
$COVER $LCOV_TOOL -o prune2 -a $PART1INFO -a $PART2INFO -a $FULLINFO --prune --ignore inconsistent
if [[ $? != 0 && $KEEP_GOING != 1 ]] ; then
    echo "lcov -prune2 failed"
    exit 1
fi
PRUNED2=`cat prune2`
EXP=$(printf "$PART1INFO\n$PART2INFO\n$FULLINFO\n")
if [ "$PRUNED2" != "$EXP" ] ; then
        echo "Expected '$EXP' - got '$PRUNED2'"
        exit 1
fi

# expect no effect from adding 'part1' or 'part2' after 'full'
$COVER $LCOV_TOOL -o prune3 -a $FULLINFO -a $PART1INFO -a $PART2INFO --prune --ignore inconsistent
if [[ $? != 0 && $KEEP_GOING != 1 ]] ; then
    echo "lcov -prune3 failed"
    exit 1
fi
PRUNED3=`cat prune3`
if [ "$PRUNED3" != "$FULLINFO" ] ; then
        echo "Expected '$FULLINFO' - got '$PRUNED3'"
        exit 1
fi

if [ "x$COVER" != "x" ] && [ 0 != $LOCAL_COVERAGE ] ; then
    cover
fi
