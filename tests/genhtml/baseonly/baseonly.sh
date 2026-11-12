#!/bin/bash
set +x

# A baseline file which no current file maps to - e.g., one which was deleted
#   or renamed between baseline and current.  It is not in the differential
#   report, so its source is not needed - and it is usually gone.  genhtml used
#   to read it anyway (to filter it, to check its consistency, to verify its
#   checksums), and stopped with a (source) error.
#
# The cases:
#   1. the diff does not mention the file at all (e.g., 'p4 diff -du' omits
#      deleted files) - serial and parallel
#   2. the diff deletes the file ('+++ /dev/null')
#   3. '--checksum' - which reads the source of every C file it loads
#   4. '--rc case_insensitive=1':  the name and basename are folded - in a
#      directory of its own, 'Mixed', so that folding changes the name
#   5. a baseline file which *does* map to a current file - by unique basename,
#      as 'TraceFile::data' looks it up - but whose source is gone:  that one
#      is in the report, so not finding its source is still an error
#   6. a build directory of soft links to the sources ('--build-directory'),
#      and a diff which renames a file.  The renamed file has no link in the
#      build directory any more - which is how build names are matched to diff
#      names - so the baseline's name for it used to match no diff entry:  its
#      baseline text was not recreated, and reading the (gone) file failed.
#      It is now found in the source directory its sibling links point to
#   7. as 6 - but the build directory collects links from two source
#      directories, and the diff renames a file of that name in both:  no
#      guessing, so this is still an error

source ../../common.tst

GENHTML_OPTS="--function-coverage --filter line $PROFILE"

rm -rf *.info *.log *.udiff src Mixed old repo build html_*

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

STATUS=0

fail()
{
    # $1 = scenario label, $2.. = what went wrong
    local label=$1
    shift
    echo "ERROR ($label): $*"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

mkdir src
cat > src/a.c <<EOT
int a()
{
  return 1;
}
EOT

# checksums of lines 1 and 3 - see case 3
CHK1=,$(perl -MDigest::MD5=md5_base64 -e 'print md5_base64("int a()")')
CHK3=,$(perl -MDigest::MD5=md5_base64 -e 'print md5_base64("  return 1;")')

# $1 = file name, $2 = 1 to write checksums
record()
{
    local c1= c3=
    if [ "$2" == 1 ] ; then
        c1=$CHK1
        c3=$CHK3
    fi
    cat <<EOT
SF:$1
FN:1,4,a
FNDA:1,a
FNF:1
FNH:1
DA:1,1$c1
DA:3,1$c3
LF:2
LH:2
end_of_record
EOT
}

# 'gone.c' exists only in the baseline - and is not on disk
( echo TN: ; record $PWD/src/a.c ; record $PWD/src/gone.c ) > base.info
( echo TN: ; record $PWD/src/a.c ) > curr.info
( echo TN: ; record $PWD/src/a.c 1 ; record $PWD/src/gone.c 1 ) > base_chk.info
( echo TN: ; record $PWD/src/a.c 1 ) > curr_chk.info
# the same in 'Mixed' - see case 4
mkdir Mixed
cp src/a.c Mixed/a.c
( echo TN: ; record $PWD/Mixed/a.c ; record $PWD/Mixed/gone.c ) > base_ci.info
( echo TN: ; record $PWD/Mixed/a.c ) > curr_ci.info
# 'old/a.c' is not on disk either - but shares its basename with the current
#   'src/a.c', so it is the baseline of that file
( echo TN: ; record $PWD/old/a.c ) > moved.info

touch none.udiff
# as 'p4udiff' writes it
cat > del.udiff <<EOT
--- $PWD/src/gone.c
+++ /dev/null
@@ -1,4 +0,0 @@
-int a()
-{
-  return 1;
-}
EOT

# $1 = label, $2 = diff file, rest = extra genhtml args
#   $SUFFIX selects the .info files
check_baseonly()
{
    local label=$1
    local diff=$2
    shift 2
    echo "$label"
    $COVER $GENHTML_TOOL $GENHTML_OPTS -o html_$label curr$SUFFIX.info \
        --baseline-file base$SUFFIX.info --diff-file $diff --ignore empty \
        --verbose "$@" > $label.log 2>&1
    if [ 0 != $? ] ; then
        fail $label "genhtml failed - see $label.log"
        return
    fi
    grep -q "not filtering '$PWD/src/gone.c':  it is not reported" $label.log ||
        fail $label "expected 'not filtering' message for gone.c"
    grep -qi "unable to open" $label.log &&
        fail $label "unexpected source error"
    # gone.c is not in the report
    [ -e html_$label/src/gone.c.gcov.html ] &&
        fail $label "gone.c should not be in the report"
    grep -q '^  line: CBC:2$' $label.log ||
        fail $label "expected 'line: CBC:2' summary"
}

check_baseonly none none.udiff --parallel 1
LCOV_FORCE_PARALLEL=1 check_baseonly none_parallel none.udiff --parallel 0
check_baseonly deleted del.udiff --parallel 1
LCOV_FORCE_PARALLEL=1 check_baseonly deleted_parallel del.udiff --parallel 0
SUFFIX=_chk check_baseonly checksum none.udiff --parallel 1 --checksum

# names are folded to lower case - so on a case sensitive filesystem, no file
#   in 'Mixed' can be opened:  ignore that (and synthesize the report's copy of
#   'a.c'), and check that 'a.c' was tried and 'gone.c' was not.  The data
#   keeps the name it was read with - only the lookup is folded.  (The folded
#   name of the test directory itself may or may not be the real one - so the
#   case does not depend on it.)
echo insensitive
LC_PWD=$(echo $PWD | tr A-Z a-z)
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_insensitive curr_ci.info \
    --baseline-file base_ci.info --diff-file none.udiff --ignore empty,source \
    --rc case_insensitive=1 --synthesize-missing --parallel 1 --verbose \
    > insensitive.log 2>&1
if [ 0 != $? ] ; then
    fail insensitive "genhtml failed - see insensitive.log"
fi
grep -q "not filtering '$PWD/Mixed/gone.c':  it is not reported" insensitive.log ||
    fail insensitive "expected 'not filtering' message for gone.c"
# ..but on a case insensitive filesystem, the folded name opens
if [ ! -e $LC_PWD/mixed/a.c ] ; then
    grep -q "unable to open $LC_PWD/mixed/a.c" insensitive.log ||
        fail insensitive "expected to try to open a.c"
fi
grep -q "unable to open .*gone.c" insensitive.log &&
    fail insensitive "unexpected attempt to open gone.c"

echo moved
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_moved curr.info \
    --baseline-file moved.info --diff-file none.udiff --ignore empty \
    --parallel 1 > moved.log 2>&1
if [ 0 == $? ] ; then
    fail moved "expected (source) error for old/a.c"
fi
grep -q "ERROR: (source) unable to open $PWD/old/a.c" moved.log ||
    fail moved "expected 'unable to open' message for old/a.c"

# ----------------------------------------------------------------------
# cases 6 and 7
mkdir -p repo/d1 repo/d2 build/inc
cat > repo/new.c <<EOT
int a()
{
  return 1;
}
EOT
for d in d1 d2 ; do
    cp repo/new.c repo/$d/x.h
    ( cd build/inc ; ln -s ../../repo/$d/x.h $d.h )
done
( cd build ; ln -s ../repo/new.c new.c )

# old.c was two lines longer:  its baseline coverpoint on line 6 is in range
#   only if the baseline text was recreated out of the diff
cat > rename.udiff <<EOT
diff --git $PWD/repo/old.c $PWD/repo/new.c
similarity index 66%
rename from repo/old.c
rename to repo/new.c
--- $PWD/repo/old.c
+++ $PWD/repo/new.c
@@ -3,4 +3,2 @@
   return 1;
 }
-int b()
-{ return 2; }
EOT
for d in d1 d2 ; do
    cat >> rename.udiff <<EOT
diff --git $PWD/repo/$d/old.h $PWD/repo/$d/x.h
similarity index 100%
rename from repo/$d/old.h
rename to repo/$d/x.h
--- $PWD/repo/$d/old.h
+++ $PWD/repo/$d/x.h
EOT
done
( echo TN: ; record $PWD/build/old.c | sed -e 's/^DA:3,1$/DA:3,1\nDA:6,1/' \
      -e 's/^LF:2$/LF:3/' -e 's/^LH:2$/LH:3/' ) > rename_base.info
( echo TN: ; record $PWD/build/new.c ) > rename_curr.info
( echo TN: ; record $PWD/build/inc/old.h ) > ambiguous_base.info
( echo TN: ; record $PWD/build/inc/d1.h ) > ambiguous_curr.info

echo rename
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_rename rename_curr.info \
    --baseline-file rename_base.info --diff-file rename.udiff \
    --build-directory build --parallel 1 > rename.log 2>&1
if [ 0 != $? ] ; then
    fail rename "genhtml failed - see rename.log"
fi
grep -qiE "unable to open|out of range|ERROR" rename.log &&
    fail rename "unexpected error - see rename.log"
# the deleted line is reported as such
grep -q 'DUB:\|DCB:' rename.log ||
    fail rename "expected deleted baseline coverpoint"

echo ambiguous
$COVER $GENHTML_TOOL $GENHTML_OPTS -o html_ambiguous ambiguous_curr.info \
    --baseline-file ambiguous_base.info --diff-file rename.udiff \
    --build-directory build --parallel 1 > ambiguous.log 2>&1
if [ 0 == $? ] ; then
    fail ambiguous "expected (source) error for build/inc/old.h"
fi
grep -q "ERROR: (source) unable to open $PWD/build/inc/old.h" ambiguous.log ||
    fail ambiguous "expected 'unable to open' message for build/inc/old.h"

if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'baseonly' $LOCAL_COVERAGE 0
fi

exit $STATUS
