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

rm -f test *.gcno *.gcda helpfail.sh helpfail.log \
    versionfail.sh versionfail.log quietversion.sh quietversion.log
rm -rf gcovdir

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

# A gcov whose '--help' fails, used by the last case below.  geninfo asks the
# tool three questions before it uses it: it runs '--help' to check that the
# name is executable at all (which only looks at whether the exec worked),
# then '--version', then '--help' again to read the option list out of it.  So
# a tool which answers '--version' and fails '--help' gets all the way to the
# capability query - which is the point: that query captured the wrong variable
# and reported "$!" (the last failed syscall, if any) rather than the exit
# status of the command it just ran.
cat > helpfail.sh <<'EOF'
#!/bin/bash

for arg in "$@" ; do
    if [ "--help" == "$arg" ] ; then
        echo "mygcov: no help available" >&2
        exit 4
    fi
done
exec gcov "$@"
EOF
chmod +x helpfail.sh

# The other two answers to '--version' a tool can give:  an error status, and
# nothing at all.  The error status used not to be looked at - the pipe was
# closed with 'close(...) or die("unable to close gcov pipe: $!")', which blames
# errno for an exit status it never reads.
cat > versionfail.sh <<'EOF'
#!/bin/bash

for arg in "$@" ; do
    if [ "--version" == "$arg" ] ; then
        echo "mygcov: cannot tell you which version I am" >&2
        exit 3
    fi
done
exec gcov "$@"
EOF
cat > quietversion.sh <<'EOF'
#!/bin/bash

for arg in "$@" ; do
    if [ "--version" == "$arg" ] ; then
        exit 0
    fi
done
exec gcov "$@"
EOF
chmod +x versionfail.sh quietversion.sh

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

    : "-----------------------------"
    : "gcov-tool which exists but whose --help fails"
    : "-----------------------------"
    # the run has to fail, and it has to say why:  the message is the exit
    # status of the tool, and not whatever errno happened to hold
    $COVER $TOOL . -o test.info --verbose --gcov-tool "$PWD/helpfail.sh" \
        > helpfail.log 2>&1
    if [ 0 == $? ] ; then
        echo "should have failed for a gcov tool whose --help fails"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    elif ! grep -F -q -e "--help' exited with error 4" helpfail.log ; then
        cat helpfail.log
        echo "expected the exit status of the failing '--help' to be reported"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    fi

    : "-----------------------------"
    : "gcov-tool whose --version fails"
    : "-----------------------------"
    # the tool is usable - it is only the version query which failed - so this
    # is an ignorable error;  what it must not be is a complaint about errno
    $COVER $TOOL . -o test.info --verbose --gcov-tool "$PWD/versionfail.sh" \
        > versionfail.log 2>&1
    if [ 0 == $? ] ; then
        echo "should have failed for a gcov tool whose --version fails"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    fi
    for pattern in 'unable to determine gcov version' \
        "--version' returned non-zero exit status 3" ; do
        if ! grep -F -q -e "$pattern" versionfail.log ; then
            cat versionfail.log
            echo "expected the failing '--version' to report: $pattern"
            status=1
            if [ $KEEP_GOING == 0 ] ; then
                exit $status
            fi
        fi
    done
    if grep -F -q -e 'unable to close gcov pipe' versionfail.log ; then
        echo "a non-zero exit status must not be reported as a close failure"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    fi

    : "-----------------------------"
    : "gcov-tool whose --version says nothing"
    : "-----------------------------"
    # there is no version to be had, so the assumed one is used;  saying so is
    # the whole of the report, and in particular there is no version string to
    # go looking for a number in
    $COVER $TOOL . -o test.info --verbose --gcov-tool "$PWD/quietversion.sh" \
        > quietversion.log 2>&1
    if ! grep -F -q -e 'cannot determine gcov version' quietversion.log ; then
        cat quietversion.log
        echo "expected a silent '--version' to fall back to the assumed version"
        status=1
        if [ $KEEP_GOING == 0 ] ; then
            exit $status
        fi
    fi
    if grep -F -q -e 'uninitialized value' quietversion.log ; then
        cat quietversion.log
        echo "the absent version string reached the version match"
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
