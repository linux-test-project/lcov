#!/bin/bash
set +x

source ../../common.tst

rm -f *.cpp *.gcno *.gcda a.out *.info *.info.gz diff.txt *.log *.err *.json dumper* *.annotated *.log TEST.cpp TeSt.cpp
rm -rf ./baseline ./current ./differential* ./nodiff ./cover_db ./MixedCase ./mixedcase ./frames

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

if ! type "${CXX}" >/dev/null 2>&1 ; then
        echo "Missing tool: $CXX" >&2
        exit 2
fi

ANNOTATE=${SCRIPT_DIR}/p4annotate

if [ ! -f $ANNOTATE ] ; then
    echo "annotate '$ANNOTATE' not found"
    exit 1
fi

#PARALLEL=''
#PROFILE="''

LCOV_OPTS="$EXTRA_GCOV_OPTS --branch-coverage --version-script `pwd`/version.pl $PARALLEL $PROFILE"
DIFFCOV_OPTS="--function-coverage --branch-coverage --demangle-cpp --frame --prefix $PARENT --version-script `pwd`/version.pl $PROFILE $PARALLEL"


echo *

# filename was all upper case
ln -s ../simple/simple.cpp TEST.cpp
${CXX} --coverage TEST.cpp
./a.out

# $GCOV, not 'which gcov':  common.tst matched it to ${CC} - see there
echo $GCOV
echo `which lcov`

# old gcc version generates inconsistent line/function data
IFS='.' read -r -a VER <<< `${CC} -dumpversion`
if [ "${VER[0]}" -lt 5 ] ; then
    IGNORE="--ignore inconsistent"
fi

echo lcov $LCOV_OPTS --capture --directory . --output-file baseline.info $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file baseline.info --no-external $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

gzip -c baseline.info > baseline.info.gz

# newer versions of gcc generate coverage data with full paths to sources
#   in '.' - whereas older versions have relative paths.
# In case of relative paths, need some additional genhtml flags to make
#   tests run the same way
grep './TEST.cpp' baseline.info
if [ 0 == $? ] ; then
    # found - need some flags
    GENHTML_PORT='--elide-path-mismatch'
    LCOV_PORT='--substitute s#./#pwd/# --ignore unused'
fi

# test merge with names that differ in case
#  ignore 'source' error when we try to open the file (for filtering) - because
#  our filesystem is not actually case insensitive.
sed -e 's/TEST.cpp/test.cpp/g' < baseline.info > baseline2.info
$COVER $LCOV_TOOL $LCOV_OPTS --output merge.info -a baseline.info -a baseline2.info --ignore source
if [ 0 != $? ] ; then
    echo "ERROR: merge with mismatched case did not fail"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

COUNT=`grep -c SF: merge.info`
if [ $COUNT != '2' ] ; then
    echo "ERROR: expected 2 files found $COUNT"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

$COVER $LCOV_TOOL $LCOV_OPTS --rc case_insensitive=1 --output merge2.info -a baseline.info -a baseline2.info --ignore source
if [ 0 != $? ] ; then
    echo "ERROR: ignore error case insensitive merge failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
COUNT=`grep -c SF: merge2.info`
if [ $COUNT != '1' ] ; then
    echo "ERROR: expected 1 file in case-insensitive result found $COUNT"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
export PWD=`pwd`
echo $PWD

rm -f TEST.cpp *.gcno *.gcda a.out
ln -s ../simple/simple2.cpp TeSt.cpp
${CXX} --coverage -DADD_CODE -DREMOVE_CODE TeSt.cpp
./a.out
echo lcov $LCOV_OPTS --capture --directory . --output-file current.info $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file current.info $IGNORE
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture TeSt failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# udiff file has yet a different case...

( cd ../simple ; diff -u simple.cpp simple2.cpp ) | sed -e "s|simple2*\.cpp|$ROOT/tEsT.cpp|g" > diff.txt

# and put yet another different case in the annotate file name
ln -s ../simple/simple2.cpp.annotated TEst.cpp.annotated

# check that this works with test names
#  need to not do the existence callback because the 'insensitive' name
#  won't be found but the version-check in the .info file already contains
#  a value - so we would get a version check error
echo genhtml $DIFFCOV_OPTS  --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --show-noncode -o differential ./current.info --rc case_insensitive=1 --ignore-annotate,source $IGNORE --rc check_existence_before_callback=0 --ignore inconsistent
$COVER $GENHTML_TOOL $DIFFCOV_OPTS  --baseline-file ./baseline.info --diff-file diff.txt --annotate-script `pwd`/annotate.pl --show-owners all --show-noncode -o differential ./current.info --rc case_insensitive=1 $GENHTML_PORT --ignore annotate,source $IGNORE --rc check_existence_before_callback=0 --ignore inconsistent
if [ 0 != $? ] ; then
    echo "ERROR: genhtml differential failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# ..and the same report with no diff at all:  the diff map is consulted for
#   every file in every report, differential or not, and the case-insensitive
#   path takes 'lc' of its root directory - which used to be set only as the
#   last step of reading a diff file.  Six warnings per source file, and none
#   of them anywhere near the option which caused them
echo genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --show-noncode -o nodiff ./current.info --rc case_insensitive=1 --ignore annotate,source $IGNORE --rc check_existence_before_callback=0 --ignore inconsistent
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --show-noncode -o nodiff ./current.info --rc case_insensitive=1 $GENHTML_PORT --ignore annotate,source $IGNORE --rc check_existence_before_callback=0 --ignore inconsistent 2>&1 | tee nodiff.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: case-insensitive genhtml without a diff file failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if grep -q 'uninitialized' nodiff.log ; then
    echo "ERROR: case-insensitive genhtml without a diff file used an uninitialized value"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# ..and the same report written into a directory whose name has capitals in it.
#   'case_insensitive' is about matching the names which came out of the coverage
#   data - it is not a request to rename the directory the user asked for, and
#   the sites which create the directories, and which write the stylesheet and
#   the '.htaccess', do not rename it either.  So folding the case of the whole
#   path when writing a page names a file in a directory nothing ever created
echo genhtml $DIFFCOV_OPTS -o MixedCase ./current.info --rc case_insensitive=1
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --annotate-script `pwd`/annotate.pl --show-owners all --show-noncode -o MixedCase ./current.info --rc case_insensitive=1 $GENHTML_PORT --ignore annotate,source $IGNORE --rc check_existence_before_callback=0 --ignore inconsistent 2>&1 | tee mixedcase.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: case-insensitive genhtml into a mixed-case directory failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
if [ ! -f MixedCase/index.html ] ; then
    echo "ERROR: no index page in the directory which was asked for"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# the pages, the stylesheet and the icons all have to land in the same place
for f in MixedCase/gcov.css MixedCase/updown.png ; do
    if [ ! -f $f ] ; then
        echo "ERROR: '$f' was not written"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
done
if [ -e mixedcase ] ; then
    echo "ERROR: genhtml wrote into a lower-cased copy of the output directory"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# ..and the frames flavour, whose extra pages refer to each other by name.  The
#   frameset frames the overview page and the source page, the overview page
#   links back to the source page and embeds the overview image, and the name all
#   four of those are written under is lower-cased by 'case_insensitive'
echo genhtml $DIFFCOV_OPTS --annotate-script `pwd`/annotate.pl --show-noncode -o frames ./current.info --rc case_insensitive=1 --validate
$COVER $GENHTML_TOOL $DIFFCOV_OPTS --annotate-script `pwd`/annotate.pl --show-noncode -o frames ./current.info --rc case_insensitive=1 $GENHTML_PORT --validate --ignore annotate,source $IGNORE --rc check_existence_before_callback=0 --ignore inconsistent 2>&1 | tee frames.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: case-insensitive genhtml --frames failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
# '--validate' walks the '<a href>' and '<frame src>' links and reports one which
#   does not resolve as a 'path' error, so a clean run above is most of the check.
#   It does not parse the '<area href>' entries of the image map, the '<img src>'
#   of the image itself or the '<link>' to the stylesheet, so check every local
#   target named by either page directly
FRAMEDIR=frames/insensitive
for f in $FRAMEDIR/test.cpp.gcov.frameset.html $FRAMEDIR/test.cpp.gcov.overview.html ; do
    if [ ! -f $f ] ; then
        echo "ERROR: '$f' was not written"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
        continue
    fi
    for t in `grep -o -E '(href|src)="[^"#]*"' $f | sed -e 's/^[a-z]*="//' -e 's/"$//' | sort -u` ; do
        case $t in http*) continue ;; esac
        if [ ! -f $FRAMEDIR/$t ] ; then
            echo "ERROR: '$f' names '$t', which was not written"
            if [ 0 == $KEEP_GOING ] ; then
                exit 1
            fi
        fi
    done
done

# check warning
echo lcov $LCOV_OPTS --capture --directory . --output-file current.info --substitute 's/test/TEST/g' $IGNORE
$COVER $LCOV_TOOL $LCOV_OPTS --capture --directory . --output-file current.info --substitute 's/test\b/TEST/' --rc case_insensitive=1 --ignore unused,source  $IGNORE 2>&1 | tee warn.log
if [ 0 != $? ] ; then
    echo "ERROR: lcov --capture TeSt failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep "does not seem to be case insensitive" warn.log
if [ 0 != $? ] ; then
    echo "did not find expected warning message in warn.log"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

rm -f TeSt.cpp

# check annotation failure message...
# check that this works with test names
echo genhtml $DIFFCOV_OPTS  --baseline-file ./baseline.info --diff-file diff.txt --annotate-script $ANNOTATE --show-owners all --show-noncode -o differential2 ./current.info --ignore source $IGNORE --rc check_existence_before_callback=0
$COVER $GENHTML_TOOL $DIFFCOV_OPTS  --baseline-file ./baseline.info --diff-file diff.txt --annotate-script $ANNOTATE --show-owners all --show-noncode -o differential2 ./current.info $GENHTML_PORT --ignore source $IGNORE --rc check_existence_before_callback=0 2>&1 | tee fail.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: expected annotation error but didn't find"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -i -E "Error: \(annotate\) annotate command failed: .*non-zero exit status" fail.log
if [ 0 != $? ] ; then
    echo "did not find expected annotate error message in fail.log"
    exit 1
fi

# just ignore the version check error this time..
echo genhtml $DIFFCOV_OPTS  --baseline-file ./baseline.info --diff-file diff.txt --annotate-script $ANNOTATE --show-owners all --show-noncode -o differential3 ./current.info --ignore-source,annotate,version $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS  --baseline-file ./baseline.info --diff-file diff.txt --annotate-script $ANNOTATE --show-owners all --show-noncode -o differential3 ./current.info $GENHTML_PORT --ignore source,annotate,version $IGNORE 2>&1 | tee fail2.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    echo "ERROR: expected synthesize  error but didn't find"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -i -E "Warning: \(annotate\).* non-zero exit status" fail2.log
if [ 0 != $? ] ; then
    echo "did not find expected annotate warning message in fail2.log"
    exit 1
fi
grep "is not readable or doesn't exist" fail2.log
if [ 0 != $? ] ; then
    echo "did not find expected existence error message in fail2.log"
    exit 1
fi

echo genhtml $DIFFCOV_OPTS  --baseline-file ./baseline.info --diff-file diff.txt --annotate-script $ANNOTATE --show-owners all --show-noncode -o differential4 ./current.info --ignore-source,annotate,version --synthesize $IGNORE
$COVER $GENHTML_TOOL $DIFFCOV_OPTS  --baseline-file ./baseline.info --diff-file diff.txt --annotate-script $ANNOTATE --show-owners all --show-noncode -o differential4 ./current.info $GENHTML_PORT --ignore source,annotate,version --synthesize $IGNORE 2>&1 | tee fail3.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "ERROR: unexpected synthesize  error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep -E "cannot read .+synthesizing fake content" fail3.log
if [ 0 != $? ] ; then
    echo "did not find expected annotate warning message in fail3.log"
    exit 1
fi

echo "Tests passed"

if [ "x$COVER" != "x" ] && [ 0 != $LOCAL_COVERAGE ]; then
    # 'cover' with no argument reads 'cover_db', and '--coverage' with no
    #   database of its own names 'cover_db.dat' - so this used to end with
    #   "Can't open database", exit 2 and no 'perlcov.info' at all.  Every other
    #   test uses the helper, which knows the name and writes the .info file
    generate_coverage 'insensitive.sh' $LOCAL_COVERAGE
fi
