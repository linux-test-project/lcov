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

source ../../common.tst

rm -f test *.gcno *.gcda

clean_cover

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
