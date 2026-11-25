#!/bin/bash

# test relative path usage
set +x

source ../../common.tst

rm -rf *.txt* *.json dumper* relative prefix prefix_test.cc prefix.info \
    prefix.log

clean_cover

if [[ 1 == "$CLEAN_ONLY" ]] ; then
    exit 0
fi

LCOV_OPTS="--branch $PARALLEL $PROFILE"
# gcc/4.8.5 (and possibly other old versions) generate inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
    # and filter exception branches to avoid spurious differences for old compiler
    FILTER='--filter branch'
fi

if ! type ${CXX} >/dev/null 2>&1 ; then
        echo "Missing tool: ${CXX}" >&2
        exit 2
fi

# 'empty' because this fixture is line data only, and both function coverage
#  (the tests/lcovrc default) and '--branch' above ask for more than it has
$COVER $GENHTML_TOOL $LCOV_OPTS -o relative relative.info --ignore source,source,empty,empty --synthesize --missed
if [ 0 != $? ] ; then
    echo "Error:  unexpected error code from genhtml"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

grep Missed relative/index.html
if [ 0 != $? ] ; then
    echo "--missed flag had no effect"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
    

for dir in lib src lib/src ; do
    if [ -e relative/$dir/$dir ] ; then
        echo "Error: unexpected duplicated path to '$dir'"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

for f in lib lib/other_class.dart.gcov.html lib/src lib/src/sample_class.dart.gcov.html ; do
    if [ ! -e relative/$f ] ; then
        echo "Error: can't find '$f'"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

# ..and a table is sorted only by the columns it has:  this data has neither
#   function nor branch coverage, so no page has those columns, and a table
#   sorted by one of them would be a page nothing leads to
if [ ! -e relative/index-sort-l.html ] ; then
    echo "Error: no table sorted by line coverage"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
for sort in f b ; do
    if [ -n "`find relative -name index-sort-$sort.html`" ] ; then
        echo "Error: a table sorted by a column it does not have: index-sort-$sort.html"
        if [ $KEEP_GOING == 0 ] ; then
            exit 1
        fi
    fi
done

# a relative source file name, with '--prefix' naming the directory it is
#   relative to - genhtml run from the directory which holds the source.  The
#   prefix names a directory which holds a source file, so genhtml moves it up
#   one level - see 'layout_name' in genhtml.
# This runs in the test directory rather than in one made for it so that,
#   under --coverage, the data goes to the same (relative) database
printf 'int main() {\n  return 0;\n}\n' > prefix_test.cc
cat > prefix.info <<EOF
SF:prefix_test.cc
FNL:0,1
FNA:0,1,main
FNF:1
FNH:1
DA:2,1
LH:1
LF:1
end_of_record
EOF
$COVER $GENHTML_TOOL -o prefix --prefix "`pwd -P`" prefix.info \
    --ignore unsupported > prefix.log 2>&1
if [ 0 != $? ] ; then
    cat prefix.log
    echo "Error:  genhtml failed with a relative name and '--prefix' of its directory"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi
# the prefix moved up one level, so the page is under this directory's name
PAGE=prefix/$(basename "$(pwd -P)")/prefix_test.cc.gcov.html
if [ ! -e "$PAGE" ] ; then
    echo "Error: can't find '$PAGE'"
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'relative.sh' $LOCAL_COVERAGE
fi
