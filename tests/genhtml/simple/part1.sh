#!/bin/bash
set +x

# ============================================================================
# part1 of the former monolithic 'simple' genhtml test (see setup_common.sh).
# Covers: capture comment round-trip, merge/filter version-mismatch handling,
# --fail-under, mismatched-version genhtml, baseline & baseline-filter reports,
# missing/invalid description handling, the vanilla/flat/hierarchical current
# report loop, and the --select-script / --show-navigation features.
# ============================================================================

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    rm -rf part1.d
    exit 0
fi

if ! type "${CXX}" >/dev/null 2>&1 ; then
        echo "Missing tool: $CXX" >&2
        exit 2
fi

if ! python3 -c "import xlsxwriter" >/dev/null 2>&1 ; then
        echo "Missing python module: xlsxwriter" >&2
        exit 2
fi

WORKDIR=part1.d
source ./setup_common.sh

status=0

# check that we wrote the comment that was expected...
head -1 baseline.info | grep -E '^#.+ the baseline$'
if [ 0 != $? ] ; then
    echo "ERROR: didn't write comment into capture"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# test merge with differing version
$COVER $LCOV_TOOL $LCOV_OPTS --output merge.info -a baseline.info -a baseline2.info $IGNORE
if [ 0 == $? ] ; then
    echo "ERROR: merge with mismatched version did not fail"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
$COVER $LCOV_TOOL $LCOV_OPTS --ignore version --output merge2.info -a baseline.info -a baseline2.info $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: ignore error merge with mismatched version failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# test filter with differing version
$COVER $LCOV_TOOL $LCOV_OPTS --output filt.info --filter branch,line -a baseline2.info $IGNORE
if [ 0 == $? ] ; then
    echo "ERROR: filter with mismatched version did not fail 2"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
$COVER $LCOV_TOOL $LCOV_OPTS --output filt.info --filter branch,line -a baseline2.info $IGNORE --ignore version
if [ 0 != $? ] ; then
    echo "ERROR: ignore error filter with mismatched version failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# run again with version script options passed in string
# test filter with differing version
$COVER $LCOV_TOOL $EXTRA_GCOV_OPTS $BASE_OPTS --version-script "$GET_VERSION_EXE --md5 --allow-missing" --output filt2.info --filter branch,line -a baseline2.info $IGNORE
if [ 0 == $? ] ; then
    echo "ERROR: filter with mismatched version did not fail 2"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ -e filt2.info ] ; then
    echo "ERROR: filter failed by still produced result"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
$COVER $LCOV_TOOL $EXTRA_GCOV_OPTS $BASE_OPTS --version-script "$GET_VERSION_EXE --md5  --allow-missing" --output filt2.info --filter branch,line -a baseline2.info $IGNORE --ignore version
if [ 0 != $? ] ; then
    echo "ERROR: ignore error filter with combined opts and mismatched version failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
diff filt.info filt2.info
if [ 0 != $? ] ; then
    echo "ERROR: string and separate args produced different result"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# test the 'fail under' flag
echo $LCOV_TOOL $LCOV_OPTS --output failUnder.info $IGNORE --capture -d . --ignore version --fail-under-lines 70
$COVER $LCOV_TOOL $LCOV_OPTS --output failUnder.info $IGNORE --capture -d . --ignore version --fail-under-lines 70
if [ 0 == $? ] ; then
    echo "ERROR: did not fail with low coverage"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ ! -f failUnder.info ] ; then
    echo "ERROR: did not write info file when failing"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo genhtml $DIFFCOV_OPTS $IGNORE failUnder.info --output-directory ./failUnder --fail-under-lines 70 --missed --html-gzip
$COVER $GENHTML_TOOL $DIFFCOV_OPTS $IGNORE failUnder.info --output-directory ./failUnder --fail-under-lines 70 --missed --html-gzip
if [ 0 == $? ] ; then
    echo "ERROR: genhtml did not fail with low coverage"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ ! -f failUnder/index.html ] ; then
    echo "ERROR: did not write (compressed) HTML when failing"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ ! -f failUnder/.htaccess ] ; then
    echo "ERROR: did not write .htaccess file"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# run genhtml with mismatched version
echo genhtml $DIFFCOV_OPTS baseline2.info --output-directory ./mismatched
$COVER $GENHTML_TOOL $DIFFCOV_OPTS baseline2.info --output-directory ./mismatched
if [ 0 == $? ] ; then
    echo "ERROR: genhtml with mismatched baseline did not fail"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo genhtml $DIFFCOV_OPTS baseline_orig.info --output-directory ./baseline $IGNORE --rc memory_percentage=50 --serialize ./baseline/coverage.dat
$COVER $GENHTML_TOOL $DIFFCOV_OPTS baseline_orig.info --output-directory ./baseline --save $IGNORE --rc memory_percentage=50 --serialize ./baseline/coverage.dat --profile
if [ 0 != $? ] ; then
    echo "ERROR: genhtml baseline failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ ! -f ./baseline/coverage.dat ] ; then
    echo "ERROR: no serialized data found"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# expect not to see differential categories...
echo $CAPTURE . $LCOV_OPTS --filter branch,line --output-file baseline-filter.info $IGNORE
$COVER $CAPTURE . $LCOV_OPTS --filter branch,line --output-file baseline-filter.info $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture (3) failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi

fi
gzip -c baseline-filter.info > baseline-filter.info.gz
echo genhtml $DIFFCOV_OPTS baseline-filter.info --output-directory ./baseline-filter $IGNORE --missed
$COVER $GENHTML_TOOL $DIFFCOV_OPTS baseline-filter.info --output-directory ./baseline-filter $IGNORE --missed --profile --history $HISTORY,baseline/genhtml.json,baseline/genhtml.json
if [ 0 != $? ] ; then
    echo "ERROR: genhtml baseline-filter failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo genhtml $DIFFCOV_OPTS --dark baseline-filter.info --output-directory ./baseline-filter-dark $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --dark baseline-filter.info --output-directory ./baseline-filter-dark $IGNORE --history $HISTORY,baseline-filter/genhtml.json
if [ 0 != $? ] ; then
    echo "ERROR: genhtml baseline-filter-dark failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

echo '' > names.data
echo  -o noNames $DIFFCOV_OPTS $IGNORE --show-details --description names.data current_name.info.gz
$COVER $GENHTML_TOOL -o noNames $DIFFCOV_OPTS $IGNORE --show-details --description names.data current_name.info.gz
if [ 0 == $? ] ; then
    echo "ERROR: expected fail due to missing descriptions - but passed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
echo "TD: out of sequence" > names.data
echo genhtml -o noNames $DIFFCOV_OPTS $IGNORE --show-details --description names.data current_name.info.gz
$COVER $GENHTML_TOOL -o noNames $DIFFCOV_OPTS $IGNORE --show-details --description names.data current_name.info.gz
if [ 0 == $? ] ; then
    echo "ERROR: expected fail due to invalid sequence - but passed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# restore the valid description data that setup_common created
cat > names.data <<EOF
TN:myTest
TD:faking some test data
# test empty description
TN:unusedTest
TD:
EOF

# check that vanilla, flat, hierarchical work with and without prefix
now=`date`
for mode in '' '--flat' '--hierarchical' ; do
    echo genhtml $DIFFCOV_OPTS $mode --show-details current_name.info.gz --output-directory ./current$mode $IGNORE --description names.data
    $COVER $GENHTML_TOOL $mode $DIFFCOV_OPTS current_name.info.gz --show-details --output-directory ./current$mode $IGNORE --current-date "$now" --description names.data
    if [ 0 != $? ] ; then
        echo "ERROR: genhtml current $mode failed"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    # verify that the 'details' link is there:
    #   index.html file should refer to 'show details'
    if [ '' == "$mode" ] ; then
        FILE=./current/simple/index.html
    else
        FILE=./current$mode/index.html
    fi
    grep 'show details' $FILE
    if [ 0 != $? ] ; then
        echo "ERROR: no testcase 'details' link"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi

    # run again with prefix
    echo genhtml $DIFFCOV_OPTS $mode --show-details current_name.info.gz --output-directory ./current_prefix$mode $IGNORE --prefix `pwd`  --description names.data
    $COVER $GENHTML_TOOL $mode $DIFFCOV_OPTS current_name.info.gz --show-details --output-directory ./current_prefix$mode $IGNORE --prefix `pwd` --current-date "$now"  --description names.data
    if [ 0 != $? ] ; then
        echo "ERROR: genhtml current $mode --prefix failed"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    diff current$mode/index.html current_prefix$mode/index.html
    if [ 0 != $? ] ; then
        echo "ERROR: diff current $mode --prefix failed"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    # and content should be the same
    ls current$mode > c
    ls current_prefix$mode > d
    diff c d
    if [ 0 != $? ] ; then
        echo "ERROR: diff current $mode content differs"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

# check select script
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --select "$SELECT" --select --owner --select stanley.ukeridge current.info -o select $IGNORE --validate
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --select "$SELECT" --select --owner --select stanley.ukeridge current.info -o select $IGNORE --validate
if [ 0 != $? ] ; then
    echo "ERROR: genhtml select did not pass"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
FILE=`find select -name test.cpp.gcov.html`
if [ 'x' == "x$FILE" ] ; then
    echo "did not find expected output HTML"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
for owner in roderick.glossop ; do #expect to filter these guys out
    grep $owner $FILE
    if [ 0 == $? ] ; then
        echo "ERROR: did not find $owner in select group"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done
COUNT=`grep -c 'ignored lines' $FILE`
if [ 0 != $? ] ; then
    echo "ERROR: did not find elided message 'ignored lines'"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ 2 != $COUNT ] ; then
    echo "ERROR: wrong elided message count"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# check select script
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --select "$SELECT" --select --owner --select not.there current.info -o select2 $IGNORE --validate
$COVER ${GENHTML_TOOL} $DIFFCOV_OPTS --baseline-file ./baseline.info.gz --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --ignore-errors source --select "$SELECT" --select --owner --select not.there current.info -o select2 $IGNORE --validate 2>&1 | tee selectNone.log
if [ 0 != $? ] ; then
    echo "ERROR: genhtml select did not pass"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

grep 'Coverage data table is empty' select2/index.html
if [ 0 != $? ] ; then
    echo "ERROR: did not find elided message"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

NAME=`(cd select2 ; ls *.html | grep -v -E '(cmdline|profile)')`
if [ "index.html" != "$NAME" ] ; then
    echo "ERROR: expected to find only one HTML file"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

grep "your '--select-script' criteria may not match any coverpoints" selectNone.log
if [ 0 != $? ] ; then
    echo "ERROR: did not no selection message"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# test '--show-navigation' option
# need "--ignore-unused for gcc/10.2.0 - which doesn't see code in its c++ headers
echo ${LCOV_HOME}/bin/genhtml $DIFFCOV_NOFRAME_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --show-navigation -o navigation --ignore unused --exclude '*/include/c++/*' ./current.info $IGNORE
$COVER ${GENHTML_TOOL} $DIFFCOV_NOFRAME_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --show-navigation -o navigation --ignore unused --exclude '*/include/c++/*' $GENHTML_PORT ./current.info $IGNORE > navigation.log 2> navigation.err

if [ 0 != $? ] ; then
    echo "ERROR: genhtml --show-navigation failed"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

HIT=`grep -c HIT.. navigation.log`
MISS=`grep -c MIS.. navigation.log`
if [ "$ENABLE_MCDC" != '1' ] ; then
    EXPECT_MISS=2
    EXPECT_HIT=3
else
    # MC/DC included...
    EXPECT_MISS=3
    EXPECT_HIT=4
fi
if [[ $HIT != $EXPECT_HIT || $MISS != $EXPECT_MISS ]] ; then
    echo "ERROR: 'navigation counts are wrong: hit $HIT != $EXPECT_HIT $MISS != $EXPECT_MISS"
    status=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
#look for navigation links in index.html files
for f in navigation/simple/index.html ; do
    grep -E 'href=.*#L[0-9]+.*Go to first ' $f
    if [ 0 != $? ] ; then
        status=1
        echo "ERROR:  no navigation links in $f"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done
# look for unexpected naming in HTML
for tla in GNC UNC ; do
    grep "next $tla in" ./navigation/simple/test.cpp.gcov.html
    if [ 0 == $? ] ; then
        echo "ERROR: found unexpected tla $tla in result"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done
# look for expected naming in HTML
for tla in HIT MIS ; do
    grep "next $tla in" ./navigation/simple/test.cpp.gcov.html
    if [ 0 != $? ] ; then
        echo "ERROR: did not find expected tla $tla in result"
        status=1
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done

echo $SPREADSHEET_TOOL -o results.xlsx `find . -name "*.json"`
eval $SPREADSHEET_TOOL -o results.xlsx `find . -name "*.json"`
if [ 0 != $? ] ; then
    status=1
    echo "ERROR:  spreadsheet generation failed"
    exit 1
fi

if [ 0 == $status ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] ; then
    generate_coverage 'simple_1' $LOCAL_COVERAGE 1
fi

exit $status
