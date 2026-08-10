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

# This test is about how geninfo resolves the name it was given, so several of
# the cases below deliberately pass a bare 'gcov' - as does mygcov.sh, which is
# a wrapper around whatever PATH finds.  That has to be the gcov matching $CC,
# or the capture fails on the .gcno version rather than on the path handling
# this test is checking.  common.tst worked out which one that is, so put a
# directory holding only a link to it at the front of PATH:  linking the one
# tool rather than prepending its whole directory leaves the rest of the path -
# the lcov under test above all - exactly as it was.
if [ -n "$GCOV" ] ; then
    mkdir gcovdir && ln -s "$GCOV" gcovdir/gcov
    if [ 0 != $? ] ; then
        echo "cannot link '$GCOV' into gcovdir"
        exit 1
    fi
    export PATH="$PWD/gcovdir:$PATH"
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
