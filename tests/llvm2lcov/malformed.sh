#!/bin/bash
set +x

# ============================================================================
# llvm2lcov against hand-written llvm-cov exports.
#
# Nothing validates llvm-cov's schema:  every list in the export used to be
#   dereferenced where it was found, so a truncated file, a file from a tool
#   which is not llvm-cov, or a version of llvm-cov which spells a field
#   differently produced a raw perl error - "Can't use an undefined value as an
#   ARRAY reference", or a stream of uninitialized-value warnings followed by
#   nonsense in the .info file - rather than the 'format' error every other
#   malformed input in this suite raises.
#
# The exports here are written by hand rather than captured from llvm-cov:
#   these are the shapes llvm-cov does not produce, and the cases about a
#   function's extent need regions in an order a real export would not use.
#   That also means this test needs no clang (see llvm2lcov.sh, which does).
#
# Cases:
#   1.  'files' absent
#   2.  'files' is a scalar
#   3.  a 'files' entry with no 'filename'
#   4.  'segments' is a hash
#   5.  'functions' absent
#   6.  a function with no 'name'
#   7.  a function whose 'filenames' list is empty
#   8.  a function with no 'regions' is skipped, not placed at line undef
#   9.  a function reported as several regions spans all of them:  the first
#       region is not necessarily the leftmost, nor the last the rightmost
#   10. a region from an expansion ('fileId' non-zero) carries line numbers
#       from the header the macro came from, and is not part of the extent
#   11. the branch elements of a branch with no source expression are named by
#       their own ids
#   12. MC/DC enabled for a file which has no MC/DC data at all
#   13. a branch region which covers nothing but whitespace
# ============================================================================

if [[ "x" == ${LCOV_HOME}x ]] ; then
    if [ -f ../../bin/lcov ] ; then
        LCOV_HOME=../..
    fi
fi

source ../common.tst

# only this test's own files:  'llvm2lcov.sh' runs in this same directory and
#   the harness runs the two concurrently, so a '*.json' glob here deletes the
#   export that test just captured from llvm-cov, out from under it
for stem in nofiles scalarfiles nofilename hashsegments nofunctions noname \
    nofilenames noregions multiregion expansion noexpr nomcdc blankexpr ; do
    rm -f $stem.json $stem.info $stem.log
done
rm -f src.c

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi

STATUS=0

fail()
{
    # $1 = case label, $2.. = what went wrong
    local label=$1
    shift
    echo "ERROR ($label): $*"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

# every message must be a 'format' error naming what was expected and where
check_format()
{
    # $1 = case label, $2 = log, $3.. = strings which must appear
    local label=$1 log=$2
    shift 2
    for pattern in 'ERROR: (format)' "$@" ; do
        if ! grep -F -q -e "$pattern" $log ; then
            cat $log
            fail $label "message does not mention: $pattern"
        fi
    done
}

# ---------------------------------------------------------------------------
# the source the exports refer to, and the two fragments they share:  a
# 'segments' list which covers it, and a 'files' entry built from that list.
# 'segments' needs at least three entries to reach the line-data loop at all
# ---------------------------------------------------------------------------
cat >src.c <<'EOF'
int f(int a)
{
    if (a > 0)
        return 1;
    return 0;
}
EOF

SEGMENTS='"segments": [ [1,1,3,1,1,0], [3,9,2,1,1,0], [4,9,1,1,1,0],
                        [5,5,1,1,1,0], [6,2,0,0,0,0] ]'
# a whole 'files' list for src.c, with no branch data of its own
FILES="\"files\": [ { \"filename\": \"src.c\", $SEGMENTS, \"branches\": [] } ]"

# ----------------------------------------------------------------------
echo "*** 1. 'files' is absent"
# ----------------------------------------------------------------------
cat >nofiles.json <<'EOF'
{ "version": "2.0.1", "data": [ { "functions": [] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o nofiles.info nofiles.json 2>&1 |
    tee nofiles.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail nofiles "expected llvm2lcov to reject an export with no 'files'"
fi
check_format nofiles nofiles.log "expected array 'files'" \
    "nofiles.json data[0]" 'found nothing'

# ----------------------------------------------------------------------
echo "*** 2. 'files' is a scalar"
# ----------------------------------------------------------------------
cat >scalarfiles.json <<'EOF'
{ "version": "2.0.1", "data": [ { "files": "oops", "functions": [] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o scalarfiles.info scalarfiles.json 2>&1 |
    tee scalarfiles.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail scalarfiles "expected llvm2lcov to reject a scalar 'files'"
fi
# the value is quoted into the message:  which of the schemas the file follows
#   is the user's problem to work out, and the value is the clue
check_format scalarfiles scalarfiles.log "expected array 'files'" "found 'oops'"

# ----------------------------------------------------------------------
echo "*** 3. a 'files' entry with no 'filename'"
# ----------------------------------------------------------------------
cat >nofilename.json <<'EOF'
{ "version": "2.0.1",
  "data": [ { "files": [ { "segments": [] } ], "functions": [] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o nofilename.info nofilename.json 2>&1 |
    tee nofilename.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail nofilename "expected llvm2lcov to reject a nameless 'files' entry"
fi
check_format nofilename nofilename.log "no 'filename' in" "'files' entry"

# ----------------------------------------------------------------------
echo "*** 4. 'segments' is a hash"
# ----------------------------------------------------------------------
cat >hashsegments.json <<'EOF'
{ "version": "2.0.1",
  "data": [ { "files": [ { "filename": "src.c", "segments": { "a": 1 },
                           "branches": [] } ],
              "functions": [] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o hashsegments.info hashsegments.json \
    --ignore empty 2>&1 | tee hashsegments.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail hashsegments "expected llvm2lcov to reject a hash 'segments'"
fi
# the reference type, for a value which cannot be quoted usefully
check_format hashsegments hashsegments.log "expected array 'segments'" \
    'found HASH reference'

# ----------------------------------------------------------------------
echo "*** 5. 'functions' is absent"
# ----------------------------------------------------------------------
cat >nofunctions.json <<EOF
{ "version": "2.0.1", "data": [ { $FILES } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o nofunctions.info nofunctions.json \
    --ignore empty 2>&1 | tee nofunctions.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail nofunctions "expected llvm2lcov to reject an export with no 'functions'"
fi
check_format nofunctions nofunctions.log "expected array 'functions'" \
    'found nothing'

# ----------------------------------------------------------------------
echo "*** 6. a function with no 'name'"
# ----------------------------------------------------------------------
cat >noname.json <<EOF
{ "version": "2.0.1", "data": [ { $FILES,
  "functions": [ { "count": 1, "filenames": [ "src.c" ],
                   "regions": [ [1,1,6,2,1,0,0,0] ], "branches": [] } ] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o noname.info noname.json --ignore empty \
    2>&1 | tee noname.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail noname "expected llvm2lcov to reject a nameless function"
fi
check_format noname noname.log "no 'name' in" "'functions' entry"

# ----------------------------------------------------------------------
echo "*** 7. a function whose 'filenames' list is empty"
# ----------------------------------------------------------------------
cat >nofilenames.json <<EOF
{ "version": "2.0.1", "data": [ { $FILES,
  "functions": [ { "name": "f", "count": 1, "filenames": [],
                   "regions": [ [1,1,6,2,1,0,0,0] ], "branches": [] } ] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o nofilenames.info nofilenames.json \
    --ignore empty 2>&1 | tee nofilenames.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail nofilenames "expected llvm2lcov to reject an empty 'filenames'"
fi
check_format nofilenames nofilenames.log "empty 'filenames' in"

# ----------------------------------------------------------------------
echo "*** 8. a function with no 'regions'"
# ----------------------------------------------------------------------
# there is nowhere to put the function, so it is skipped;  with the format
#   error ignored the run has to finish, rather than define a function at
#   line 'undef'
cat >noregions.json <<EOF
{ "version": "2.0.1", "data": [ { $FILES,
  "functions": [ { "name": "f", "count": 1, "filenames": [ "src.c" ],
                   "branches": [] } ] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o noregions.info noregions.json \
    --ignore empty,format 2>&1 | tee noregions.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail noregions "llvm2lcov failed with the 'regions' format error ignored"
fi
for pattern in "expected array 'regions'" "function 'f'" ; do
    if ! grep -F -q -e "$pattern" noregions.log ; then
        fail noregions "message does not mention: $pattern"
    fi
done
if grep -E -q '^FN(L|A):' noregions.info ; then
    grep -E '^FN' noregions.info
    fail noregions "a function with no region was recorded anyway"
fi
if grep -F -q 'uninitialized' noregions.log ; then
    grep -F 'uninitialized' noregions.log
    fail noregions "an undefined line number reached the coverage data"
fi

# ----------------------------------------------------------------------
echo "*** 9. a function reported as several regions"
# ----------------------------------------------------------------------
# the function occupies lines 1-6 and llvm reports it as two regions, the
#   inner one first.  Taking the extent from the first region alone made the
#   function 3-4:  the 'if' body, not the function
cat >multiregion.json <<EOF
{ "version": "2.0.1", "data": [ { $FILES,
  "functions": [ { "name": "f", "count": 3, "filenames": [ "src.c" ],
                   "regions": [ [3,9,4,17,2,0,0,0], [1,1,6,2,3,0,0,0] ],
                   "branches": [] } ] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o multiregion.info multiregion.json \
    --ignore empty 2>&1 | tee multiregion.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail multiregion "llvm2lcov failed on a multi-region function"
fi
EXTENT=`grep -E '^FNL:' multiregion.info | sed -e 's/^FNL:[0-9]*,//'`
echo "extent: $EXTENT"
if [ "1,6" != "$EXTENT" ] ; then
    fail multiregion "expected the function to span 1,6 - found '$EXTENT'"
fi

# ----------------------------------------------------------------------
echo "*** 10. a region from an expansion is not part of the extent"
# ----------------------------------------------------------------------
# 'fileId' 2 says the region's line numbers belong to whatever header the
#   macro was defined in - lines 100-200 of it here, which are not lines of
#   src.c at all.  Believing them put the function past the end of the file,
#   which the consistency check then complained about
cat >expansion.json <<EOF
{ "version": "2.0.1", "data": [ { $FILES,
  "functions": [ { "name": "f", "count": 3, "filenames": [ "src.c" ],
                   "regions": [ [100,1,200,5,1,2,0,0], [1,1,6,2,3,0,0,0] ],
                   "branches": [] } ] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o expansion.info expansion.json \
    --ignore empty 2>&1 | tee expansion.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail expansion "llvm2lcov failed on a function with an expansion region"
fi
EXTENT=`grep -E '^FNL:' expansion.info | sed -e 's/^FNL:[0-9]*,//'`
echo "extent: $EXTENT"
if [ "1,6" != "$EXTENT" ] ; then
    fail expansion "expected the function to span 1,6 - found '$EXTENT'"
fi

# ----------------------------------------------------------------------
echo "*** 11. branch elements with no source expression"
# ----------------------------------------------------------------------
# with no source to read the condition out of, a branch element is named by
#   its own id.  The id was allocated with a post-increment whose result was
#   then read again for the name, so every element was named one more than it
#   is - and the two names in a block were 1 and 2 rather than 0 and 1
cat >noexpr.json <<'EOF'
{ "version": "2.0.1", "data": [ {
  "files": [ { "filename": "gone.c",
               "segments": [ [1,1,3,1,1,0], [3,9,2,1,1,0], [4,9,1,1,1,0],
                             [5,5,1,1,1,0], [6,2,0,0,0,0] ],
               "branches": [] } ],
  "functions": [ { "name": "f", "count": 3, "filenames": [ "gone.c" ],
                   "regions": [ [1,1,6,2,3,0,0,0] ],
                   "branches": [ [3,9,3,14,2,1,0,0,4],
                                 [4,9,4,14,1,1,0,0,4] ] } ] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o noexpr.info noexpr.json \
    --ignore empty,source 2>&1 | tee noexpr.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail noexpr "llvm2lcov failed with no source to read expressions from"
fi
grep -E '^BRDA:' noexpr.info
if ! diff - <(grep -E '^BRDA:' noexpr.info) <<'EOF' ; then
BRDA:3,0,0,2
BRDA:3,0,1,1
BRDA:4,0,0,1
BRDA:4,0,1,1
EOF
    fail noexpr "branch elements are not named by their own ids"
fi

# ----------------------------------------------------------------------
echo "*** 12. MC/DC enabled for a file with no MC/DC data"
# ----------------------------------------------------------------------
# the merge summary walks every enabled coverage type, and a file need not
#   have data of each of them.  'value' then has nothing to give, and the
#   union of that undef was a bare "MCDC_Data: not a reference"
cat >nomcdc.json <<EOF
{ "version": "2.0.1", "data": [ { $FILES,
  "functions": [ { "name": "f", "count": 3, "filenames": [ "src.c" ],
                   "regions": [ [1,1,6,2,3,0,0,0] ], "branches": [] } ] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch --mcdc -o nomcdc.info nomcdc.json \
    --ignore empty 2>&1 | tee nomcdc.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail nomcdc "llvm2lcov failed with --mcdc and no MC/DC data"
fi
if grep -F -q 'not a reference' nomcdc.log ; then
    fail nomcdc "the missing MC/DC data reached 'union'"
fi
# the line and function data is still there
for pattern in 'SF:src.c' 'FNA:0,3,f' 'LH:6' ; do
    if ! grep -F -q -e "$pattern" nomcdc.info ; then
        cat nomcdc.info
        fail nomcdc "expected '$pattern' in the output"
    fi
done

# ----------------------------------------------------------------------
echo "*** 13. a branch region which covers nothing but whitespace"
# ----------------------------------------------------------------------
# the source read here is the one on the filesystem now, which is not
#   necessarily the one which was compiled, so a region's columns can land
#   anywhere - here on the indentation of line 3.  The expression was trimmed
#   with a match whose result was then used unconditionally, and a match
#   against whitespace does not succeed:  the name of the branch became
#   whatever the last successful match anywhere had captured
cat >blankexpr.json <<EOF
{ "version": "2.0.1", "data": [ { $FILES,
  "functions": [ { "name": "f", "count": 3, "filenames": [ "src.c" ],
                   "regions": [ [1,1,6,2,3,0,0,0] ],
                   "branches": [ [3,1,3,5,2,1,0,0,4] ] } ] } ] }
EOF
$COVER $LLVM2LCOV_TOOL --branch -o blankexpr.info blankexpr.json \
    --ignore empty 2>&1 | tee blankexpr.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail blankexpr "llvm2lcov failed on a branch region covering whitespace"
fi
grep -E '^BRDA:' blankexpr.info
if ! diff - <(grep -E '^BRDA:' blankexpr.info) <<'EOF' ; then
BRDA:3,0,() == True,2
BRDA:3,0,() == False,1
EOF
    fail blankexpr "the empty expression did not name the branch elements"
fi
if grep -F -q 'uninitialized' blankexpr.log ; then
    grep -F 'uninitialized' blankexpr.log
    fail blankexpr "the failed trim left the expression undefined"
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'malformed' $LOCAL_COVERAGE 0
fi

exit $STATUS
