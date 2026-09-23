#! /usr/bin/env bash

# Which aliases of a function make a call:  the alias set of a call site.
#
# A call site belongs to a FunctionEntry - a location - and an entry is shared by
#   every name the function has there:  each instantiation of a template, each
#   clone.  Different instantiations of one template body call different
#   functions from the same place, so the site carries the set of aliases which
#   make it, written as a list of positions among the 'FNA:' records of the
#   index:
#
#     FNC:<index>[@<file>][#<pos>[.<pos>...]],<line>,<column>,<ordinal>,<count>,<callee>
#
#   No '#' means every alias of the index - which is what the reader makes of
#   it, spelled out, so that a later merge with a section which knows the
#   function by more names does not hand the call to those as well.  The writer
#   says '#' only when the set is a proper subset.
#
# Everything here is a hand-written '.info' over a checked-in source, so it
#   needs no compiler;  'geninfo.sh' is the capture side of the same thing.

source ../../common.tst

if [[ 1 == $CLEAN_ONLY ]] ; then
    clean_cover
    rm -rf attribution.d
    exit 0
fi

WORKDIR=attribution.d
source ./setup_common.sh

checkFunctionRecords()
{
    # checkFunctionRecords label file <<expected
    #   the function and call records of a '.info', against stdin
    local label=$1
    local file=$2
    if [ ! -f $file ] ; then
        fail $label "$file was not written"
        cat > /dev/null
        return
    fi
    cat > $label.expect
    grep -E '^(FNA|FNC)' $file > $label.actual
    if ! diff -u $label.expect $label.actual ; then
        fail $label "unexpected function records in $file"
    fi
}

cat >proj/t.h <<'EOF'
int g(int x) { return x; }
int h(int x) { return x + 1; }
int shared(int x) { return x * 2; }
template <class T>
int f(T x)
{
    int r = sizeof(T) == 1 ? h(x) : g(x);
    return r + shared(x);
}
EOF

# One translation unit instantiates 'f<int>', which calls 'g'..
cat >one.info <<'EOF'
TN:
SF:proj/t.h
FNL:0,1,1
FNA:0,1,g
FNL:1,2,2
FNA:1,0,h
FNL:2,3,3
FNA:2,1,shared
FNL:3,5,9
FNA:3,1,f<int>
FNC:3,7,37,0,1,g
FNC:3,8,16,0,1,shared
FNF:4
FNH:3
FNCF:2
FNCH:2
DA:1,1
DA:2,0
DA:3,1
DA:5,1
DA:7,1
DA:8,1
LF:6
LH:5
end_of_record
EOF
# ..and another 'f<char>', which calls 'h' - from the same expression
sed -e 's/^FNA:0,1,g$/FNA:0,0,g/' -e 's/^FNA:1,0,h$/FNA:1,1,h/' \
    -e 's/f<int>/f<char>/' -e 's/^FNC:3,7,37,0,1,g$/FNC:3,7,29,0,1,h/' \
    -e 's/^DA:1,1$/DA:1,0/' -e 's/^DA:2,0$/DA:2,1/' one.info > two.info

# ----------------------------------------------------------------------
echo "*** 1. merge:  each call stays with the instantiation which made it"
# ----------------------------------------------------------------------
# Neither input says '#':  each knows the function by one name, so the call is
#   that name's.  Merged, the entry has two names, and the call to 'g' is
#   'f<int>'s alone ('#1':  the writer emits the names sorted) while the call
#   to 'shared', which both made, is both of theirs and needs no '#'.
# Neither alias has a caller in the report, so both carry the deduced-caller
#   flag - an alias which only the second input knew included:  a merge used
#   to leave it out of the name index, which hid it from the flag
runLcov merge --callgraph -a one.info -a two.info -o merge.info
checkFunctionRecords merge merge.info <<'EOF'
FNA:0,1,g
FNA:1,1,h
FNA:2,2,shared
FNA:3d,1,f<char>
FNA:3d,1,f<int>
FNC:3#0,7,29,0,1,h
FNC:3#1,7,37,0,1,g
FNC:3,8,16,0,2,shared
FNCF:3
FNCH:3
EOF

# ..and the order of the inputs is not the answer
runLcov merge_rev --callgraph -a two.info -a one.info -o merge_rev.info
if [ -f merge_rev.info ] && ! diff -u merge.info merge_rev.info ; then
    fail merge_rev "the merge depends on the order of its inputs"
fi

# ..nor is whether the merge was done across a fork:  the alias set crosses
#   the boundary in the serialized site
LCOV_FORCE_PARALLEL=1 runLcov merge_par --callgraph --parallel 0 \
    -a one.info -a two.info -o merge_par.info
if [ -f merge_par.info ] && ! diff -u merge.info merge_par.info ; then
    fail merge_par "a parallel merge lost the alias of a call site"
fi

# ----------------------------------------------------------------------
echo "*** 2. read and write:  the '#' field round trips"
# ----------------------------------------------------------------------
runLcov round --callgraph -a merge.info -o round.info
if [ -f round.info ] && ! diff -u merge.info round.info ; then
    fail round "a tracefile with attributed call sites does not round trip"
fi

# ..merged with itself, the sets are unchanged and the counts are the sum
runLcov self --callgraph -a merge.info -a merge.info -o self.info
checkFunctionRecords self self.info <<'EOF'
FNA:0,2,g
FNA:1,2,h
FNA:2,4,shared
FNA:3d,2,f<char>
FNA:3d,2,f<int>
FNC:3#0,7,29,0,2,h
FNC:3#1,7,37,0,2,g
FNC:3,8,16,0,4,shared
FNCF:3
FNCH:3
EOF

# A position is counted among the 'FNA:' records of the index in the order the
#   file has them, which need not be sorted:  here '#0' is 'f<int>', and the
#   writer - which sorts - says '#1' for it
sed -e 's/^FNA:3d,1,f<char>$/FNA:3,1,f<int>/;t' \
    -e 's/^FNA:3d,1,f<int>$/FNA:3,1,f<char>/;t' \
    -e 's/^FNC:3#0,/FNC:3#1,/;t' -e 's/^FNC:3#1,/FNC:3#0,/' \
    merge.info > unsorted.info
runLcov unsorted --callgraph -a unsorted.info -o unsorted_out.info
if [ -f unsorted_out.info ] && ! diff -u merge.info unsorted_out.info ; then
    fail unsorted "an alias position was not read in file order"
fi

# Both positions is every alias - which is the same thing as no '#'
sed -e 's/^FNC:3,8,16,/FNC:3#1.0,8,16,/' merge.info > explicit.info
runLcov explicit --callgraph -a explicit.info -o explicit_out.info
if [ -f explicit_out.info ] && ! diff -u merge.info explicit_out.info ; then
    fail explicit "a site naming every alias was not written without '#'"
fi

# ----------------------------------------------------------------------
echo "*** 3. a position with no 'FNA:' record"
# ----------------------------------------------------------------------
# ..is a format error..
sed -e 's/^FNC:3#0,/FNC:3#5,/' merge.info > badpos.info
checkFail badpos "function index '3' has no alias '5'" \
    --callgraph -a badpos.info -o badpos_out.info

# ..which, ignored, drops the site:  no alias was named, and handing the call to
#   some alias nobody named would be inventing it
runWarn badpos_ign "function index '3' has no alias '5'" \
    --callgraph --ignore-errors format -a badpos.info -o badpos_ign.info
checkFunctionRecords badpos_ign badpos_ign.info <<'EOF'
FNA:0,1,g
FNA:1d,1,h
FNA:2,2,shared
FNA:3d,1,f<char>
FNA:3d,1,f<int>
FNC:3#1,7,37,0,1,g
FNC:3,8,16,0,2,shared
FNCF:2
FNCH:2
EOF

# ..while a site which names a good position as well keeps that one
sed -e 's/^FNC:3#0,/FNC:3#0.5,/' merge.info > partpos.info
runWarn partpos "function index '3' has no alias '5'" \
    --callgraph --ignore-errors format -a partpos.info -o partpos_out.info
if [ -f partpos_out.info ] && ! diff -u merge.info partpos_out.info ; then
    fail partpos "the good position of a site was not kept"
fi

# ----------------------------------------------------------------------
echo "*** 4. removing an alias removes its calls"
# ----------------------------------------------------------------------
# '--intersect' keeps the aliases both sides have:  'f<char>' goes, and with it
#   the call only it made, while the shared call is now every alias's
runLcov intersect --callgraph merge.info --intersect one.info \
    -o intersect.info
checkFunctionRecords intersect intersect.info <<'EOF'
FNA:0,2,g
FNA:1d,1,h
FNA:2,3,shared
FNA:3d,2,f<int>
FNC:3,7,37,0,2,g
FNC:3,8,16,0,3,shared
FNCF:2
FNCH:2
EOF

# '--subtract' removes the aliases both sides have:  here 'f<int>' alone, from a
#   side whose one call site is somewhere 'f' has none - so that the input has
#   call data at all - so it is the alias and not the site which goes.  The
#   call only 'f<int>' made goes with it, while the shared call is left to
#   'f<char>', now the only alias and so written without '#'.  'g' has lost
#   its one caller, so the call it received is now a deduced one
cat >fint.info <<'EOF'
TN:
SF:proj/t.h
FNL:0,5,9
FNA:0,1,f<int>
FNC:0,9,1,0,1,f<int>
FNF:1
FNH:1
FNCF:1
FNCH:1
DA:5,1
LF:1
LH:1
end_of_record
EOF
runLcov subtract --callgraph merge.info --subtract fint.info \
    -o subtract.info
checkFunctionRecords subtract subtract.info <<'EOF'
FNA:0d,1,g
FNA:1,1,h
FNA:2,2,shared
FNA:3d,1,f<char>
FNC:3,7,29,0,1,h
FNC:3,8,16,0,2,shared
FNCF:2
FNCH:2
EOF

# ----------------------------------------------------------------------
echo "*** 5. a call written in another file"
# ----------------------------------------------------------------------
# A site whose file is not its caller's ('@<file>') is held until the whole
#   tracefile has been read - and its alias set is held with it
cat >xf.info <<'EOF'
TN:
SF:proj/x.c
FNL:0,1,4
FNA:0,1,helper
FNL:1,6,9
FNA:1,1,other
FNF:2
FNH:2
FNCF:0
FNCH:0
DA:1,1
DA:6,1
LF:2
LH:2
end_of_record
TN:
SF:proj/y.cpp
FNL:0,1,4
FNA:0d,1,t<char>
FNA:0d,1,t<int>
FNC:0@0#0,1,13,0,1,helper
FNC:0@0#1,2,13,0,1,other
FNF:1
FNH:1
FNCF:2
FNCH:2
DA:1,1
LF:1
LH:1
end_of_record
TN:
SF:0,proj/z.h
FNF:0
FNH:0
FNCF:0
FNCH:0
DA:1,1
DA:2,1
LF:2
LH:2
end_of_record
EOF
runLcov xfround --callgraph -a xf.info -o xfround.info
if [ -f xfround.info ] && ! diff -u xf.info xfround.info ; then
    fail xfround "an attributed cross-file call site does not round trip"
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'attribution' $LOCAL_COVERAGE 0
fi

exit $STATUS
