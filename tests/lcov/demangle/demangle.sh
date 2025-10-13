#!/bin/bash
set +x

source ../../common.tst

LCOV_OPTS="--branch-coverage --no-external $PARALLEL $PROFILE"

rm -rf *.gcda *.gcno a.out *.info* *.txt* *.json dumper* testRC *.gcov *.gcov.* *.log simplify

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

if [ 'x' == "x$GENHTML_TOOL" ] ; then
    GENHTML_TOOL=${LCOV_HOME}/bin/genhtml
    LCOV_TOOL=${LCOV_HOME}/bin/lcov
    GENINFO_TOOL=${LCOV_HOME}/bin/geninfo
fi

SIMPLIFY_SCRIPT=${SCRIPT_DIR}/simplify.pm

${CXX} -std=c++1y --coverage demangle.cpp
./a.out 1

$COVER $LCOV_TOOL $LCOV_OPTS --capture --filter branch --demangle --directory . -o demangle.info --rc derive_function_end_line=0

$COVER $LCOV_TOOL $LCOV_OPTS --list demangle.info

# how many branches reported?
COUNT=`grep -c BRDA: demangle.info`
if [ $COUNT != '0' ] ; then
    echo "expected 0 branches - found $COUNT"
    exit 1
fi

for k in FNA ; do
    # how many functions reported?
    grep $k: demangle.info
    COUNT=`grep -v __ demangle.info | grep -c $k:`
    if [ $COUNT != '5' ] ; then
        echo "expected 5 $k function entries in demangle.info - found $COUNT"
        exit 1
    fi

    # were the function names demangled?
    grep $k: demangle.info | grep ::
    COUNT=`grep $k: demangle.info | grep -c ::`
    if [ $COUNT != '4' ] ; then
        echo "expected 4 $k function entries in demangele.info - found $COUNT"
        exit 1
    fi
done

# see if we can "simplify" the function names..
for callback in './simplify.pl' "${SIMPLIFY_SCRIPT},--sep,;,--re,s/Animal::Animal/subst1/;s/Cat::Cat/subst2/;s/subst2/subst3/" "${SIMPLIFY_SCRIPT},--file,simplify.cmd" ; do

    $COVER $GENHTML_TOOL --branch $PARLLEL $PROFILE -o simplify demangle.info --flat --simplify $callback
    if [ $? != 0 ] ; then
	echo "genhtml --simplify '$callback' failed"
	exit 1
    fi
    grep subst1 simplify/demangle/demangle.cpp.func.html
    if [ $? != 0 ] ; then
	echo "didn't find subst1 pattern after $callback"
	exit 1
    fi
    grep Animal::Animal simplify/demangle/demangle.cpp.func.html
    if [ $? == 0 ] ; then
	echo "found pattern that was supposed to be substituted after $callback"
	exit 1
    fi
    grep subst3 simplify/demangle/demangle.cpp.func.html
    if [ $? != 0 ] ; then
	echo "didn't find subst3 pattern after $callback"
	exit 1
    fi
    grep subst2 simplify/demangle/demangle.cpp.func.html
    if [ $? == 0 ] ; then
	echo "iteratative substitute failed after $callback "
	exit 1
    fi
done

# test unused regexp in simplify callback
for PAR in '' '--parallel' ; do
    $COVER $GENHTML_TOOL --branch $PARLLEL $PROFILE -o simplify demangle.info --flat --simplify "${SIMPLIFY_SCRIPT},--sep,;,--re,s/Animal::Animal/subst1/;s/Cat::Cat/subst2/;s/subst2/subst3/;s/foo/bar/" $PAR 2>&1 | tee simplifyErr.log
    if [ ${PIPESTATUS[0]} == 0 ] ; then
	echo "genhtml --simplify unused regexp didn't fail"
	exit 1
    fi
    grep "'simplify' pattern 's/foo/bar/' is unused" simplifyErr.log
    if [ $? != 0 ] ; then
	echo "didn't find expected unused error"
	exit 1
    fi

    $COVER $GENHTML_TOOL --branch $PARLLEL $PROFILE -o simplify demangle.info --flat --simplify "${SIMPLIFY_SCRIPT},--sep,;,--re,s/Animal::Animal/subst1/;s/Cat::Cat/subst2/;s/subst2/subst3/;s/foo/bar/" $PAR --ignore unused 2>&1 | tee simplifyWarn.log
    if [ ${PIPESTATUS[0]} != 0 ] ; then
	echo "genhtml --simplify unused regexp warn didn't pass"
	exit 1
    fi
    grep "'simplify' pattern 's/foo/bar/' is unused" simplifyWarn.log
    if [ $? != 0 ] ; then
	echo "didn't find expected unused error"
	exit 1
    fi
done


$COVER $LCOV_TOOL $LCOV_OPTS --capture --filter branch --directory . -o vanilla.info

$COVER $LCOV_TOOL $LCOV_OPTS --list vanilla.info

# how many branches reported?
COUNT=`grep -c BRDA: vanilla.info`
if [ $COUNT != '0' ] ; then
    echo "expected 0 branches - found $COUNT"
    exit 1
fi

for k in FNA ; do
    # how many functions reported?
    grep $k: vanilla.info
    COUNT=`grep -v __ demangle.info | grep -c $k: vanilla.info`
    # gcc may generate multiple entries for the inline functions..
    if [ $COUNT -lt 5 ] ; then
        echo "expected 5 $k function entries in $vanilla.info - found $COUNT"
        exit 1
    fi

    # were the function names demangled?
    grep $k: vanilla.info | grep ::
    COUNT=`grep $k: vanilla.info | grep -c ::`
    if [ $COUNT != '0' ] ; then
        echo "expected 0 demangled $k function entries in vanilla.info - found $COUNT"
        exit 1
    fi
done

# see if we can exclude a function - does the generated data contain
#  function end line numbers?
grep -E 'FNL:[0-9]+,[0-9]+,[0-9]+' demangle.info
if [ $? == 0 ] ; then
    echo "----------------------"
    echo "   compiler version support start/end reporting - testing erase"

    # end line is captured - so we should be able to filter
    $COVER $LCOV_TOOL $LCOV_OPTS --capture --filter branch --demangle-cpp --directory . --erase-functions main -o exclude.info -v -v
    if [ $? != 0 ] ; then
        echo "geninfo with exclusion failed"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    for type in DA FNA ; do
        ORIG=`grep -c -E "^$type:" demangle.info`
        NOW=`grep -c -E "^$type:" exclude.info`
        if [ $ORIG -le $NOW ] ; then
            echo "unexpected $type count: $ORIG -> $NOW"
            exit 1
        fi
    done

    # check that the same lines are removed by 'aggregate'
    $COVER $LCOV_TOOL $LCOV_OPTS -o aggregate.info -a demangle.info --erase-functions main -v

    diff exclude.info aggregate.info
    if [ $? != 0 ] ; then
        echo "unexpected 'exclude function' mismatch"
        exit 1
    fi

    perl -pe 's/(FNL:[0-9]+),([0-9]+),[0-9]+/$1,$2/' demangle.info > munged.info
    $COVER $LCOV_TOOL $LCOV_OPTS  --filter branch --demangle-cpp -a munged.info --erase-functions main -o munged_exclude.info --rc derive_function_end_line=0
    if [ $? == 0 ] ; then
        echo "lcov exclude with no function end lines passed"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    $COVER $LCOV_TOOL $LCOV_OPTS  --filter branch --demangle-cpp -a munged.info --erase-functions main -o munged_exclude.info --rc derive_function_end_line=0 --ignore unsupported
    if [ $? != 0 ] ; then
        echo "didn't ignore exclusion message"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

else
    # no end line in data - check for error message...
    echo "----------------------"
    echo "   compiler version DOESN't support start/end reporting - check error"
    $COVER $LCOV_TOOL $LCOV_OPTS --capture --filter branch --demangle-cpp --directory . --erase-functions main --ignore unused -o exclude.info --rc derive_function_end_line=0 --msg-log exclude.log
    if [ 0 == $? ] ; then
        echo "Error:  expected exit for unsupported feature"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    grep -E 'ERROR: .+Function begin/end line exclusions not supported' exclude.log
    if [ 0 != $? ] ; then
        echo "Error:  didn't find unsupported message"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    $COVER $LCOV_TOOL $LCOV_OPTS --capture --filter branch --demangle-cpp --directory . --erase-functions main --ignore unused -o exclude2.info --rc derive_function_end_line=1 --msg-log exclude2.log
    if [ 0 != $? ] ; then
        echo "Error:  unexpected exit when 'derive' enabled"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi

    grep -E 'WARNING: .+Function begin/end line exclusions.+attempting to derive' exclude2.log
    if [ 0 != $? ] ; then
        echo "Error:  didn't find derive warning"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi

    fi
    
    $COVER $LCOV_TOOL $LCOV_OPTS --capture --filter branch --demangle-cpp --directory . --erase-functions main --rc derive_function_end_line=0 --ignore unsupported,unused -o ignore.info --msg-log=exclude3.log
    if [ 0 != $? ] ; then
        echo "Error:  expected to ignore unsupported message"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
    grep -E 'WARNING: .+Function begin/end line exclusions.+See lcovrc man entry' exclude3.log
    if [ 0 != $? ] ; then
        echo "Error:  didn't find derive warning2"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi

    fi
    
    # expect not to find 'main'
    grep main ignore.info
    if [ $? == 0 ] ; then
        echo "expected 'main' to be filtered out"
        exit 1
    fi
    # but expect to find coverpoint within main..
    grep DA:40,1 ignore.info
    if [ $? != 0 ] ; then
        echo "expected to find coverpoint at line 40"
        exit 1
    fi
fi


echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    cover
fi
