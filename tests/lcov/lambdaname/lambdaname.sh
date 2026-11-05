#!/bin/bash

# C++ lambdas are recognised by their function names - in every spelling:
#   mangled (as geninfo writes them by default), or demangled by GNU c++filt
#   or by llvm-cxxfilt, with gcc's and clang's closure names.  A function
#   which is only instantiated on a closure type is not a lambda.
#   1. geninfo:  the lambda in 'one_line.cpp' is never called, but its first
#      line is hit (it holds the call of 'call_if' too).  A lambda's first line
#      is not checked - so no inconsistency, with or without --demangle-cpp
#   2. the first line exemption, by name:  each function is not hit while its
#      first line is.  A lambda is not reported;  any other function is
#   3. 'ignore_lambda_consistency', by name:  a function which is not hit
#      while its second line is - where the next function starts.  If that one
#      is a lambda - by its name or by one of its aliases - the check is
#      suppressed;  otherwise, the function is reported
set +x

source ../../common.tst

rm -rf *.txt* *.json dumper* *.gcda *.gcno *.info one_line *.log

clean_cover

if [[ 1 == "$CLEAN_ONLY" ]] ; then
    exit 0
fi

STATUS=0
fail()
{
    echo "ERROR ($1): $2"
    STATUS=1
    if [ $KEEP_GOING == 0 ] ; then
        exit 1
    fi
}

# ----------------------------------------------------------------------
echo "*** 1. geninfo:  the lambda's first line, mangled and demangled"
# ----------------------------------------------------------------------
if ! type ${CXX} >/dev/null 2>&1 ; then
    fail one_line "missing tool: ${CXX}"
fi
${CXX} -std=c++11 --coverage -O0 -o one_line one_line.cpp ||
    fail one_line 'compile'
./one_line

for DEMANGLE in '' --demangle-cpp ; do
    label=one_line${DEMANGLE:+_demangled}
    $COVER $GENINFO_TOOL . --branch $PARALLEL $PROFILE -o $label.info \
        --rc ignore_lambda_consistency=0 $DEMANGLE > $label.log 2>&1
    if [ 0 != $? ] ; then
        cat $label.log
        fail $label "geninfo failed"
    fi
    if grep -q -F 'is not hit but line' $label.log ; then
        fail $label "the lambda's first line was checked"
    fi
    # the lambda (at line 5) is still not hit
    if ! grep -q -E '^FNL:[0-9]+,5,5$' $label.info ||
        [ 0 != `awk -F'[:,]' '/^FNL:/ && $3 == 5 { idx[$2] = 1 }
                /^FNA:/ && ($2 in idx) { print $3; exit }' $label.info` ] ; then
        fail $label "expected the lambda at line 5, not hit"
    fi
done
if ! grep -q -E '^FNA:[0-9]+,0,_Z' one_line.info ||
    grep -q -E '^FNA:[0-9]+,0,_Z' one_line_demangled.info ; then
    fail one_line "expected mangled and demangled names"
fi

# lambdas, in each spelling
cat > lambdas.txt <<'EOF'
_ZZ4mainENKUlvE_clEv
_ZZ4mainENKUlT_E_clIiEEDaS_
_ZZ4mainENUlvE0_4_FUNEv
_ZZ4mainENKUlvE0_cvPFivEEv
_ZZ4mainENUliE_D2Ev
_ZNK2ns1gMUlPFivEE_clES2_
_ZZN1S1mEvENKUlvE_clEv
_ZZ4mainENK3$_0clEv
_ZZ4mainENK3$_1clIiEEDaT_
_ZZ4mainEN3$_28__invokeEv
_ZZ4mainENK3$_2cvPFivEEv
_ZZ4mainEN3$_3D2Ev
main::{lambda()#1}::operator()() const
auto main::{lambda(auto:1)#1}::operator()<int>(int) const
main::{lambda()#2}::_FUN()
main::{lambda()#2}::operator int (*)()() const
main::{lambda(int)#1}::~main()
ns::g::{lambda(int (*)())#1}::operator()(int (*)()) const
S::m()::{lambda()#1}::operator()() const
main::'lambda'()::operator()() const
auto main::'lambda'(auto)::operator()<int>(auto) const
main::'lambda0'()::_FUN()
main::'lambda0'()::operator int (*)()() const
main::'lambda'(int)::~()
main::$_0::operator()() const
main::$_2::__invoke()
main::$_2::operator int (*)()() const
main::$_3::~$_3()
EOF
# not lambdas:  instantiations on a closure type, and ordinary functions
cat > others.txt <<'EOF'
_Z7call_ifIZ4mainEUlvE_EibT_
_Z6call_gIZ4mainEUlT_E_EibS0_
_Z3twoIZ4mainEUlvE2_Z4mainEUlvE3_EiT_T0_
_Z7call_ifIZ4mainE3$_0EibT_
_Z3twoIZ4mainE3$_5Z4mainE3$_6EiT_T0_
_ZN1S1mEv
int call_if<main::{lambda()#1}>(bool, main::{lambda()#1})
int call_g<main::{lambda(auto:1)#1}>(bool, main::{lambda(auto:1)#1})
int two<main::{lambda()#4}, main::{lambda()#5}>(main::{lambda()#4}, main::{lambda()#5})
int call_if<main::'lambda'()>(bool, main::'lambda'())
int call_g<main::'lambda'(auto)>(bool, auto)
int call_if<main::$_0>(bool, main::$_0)
S::m()
EOF

# write the '.info' file for case $1 (2 or 3) of the names in the files $3...
#   to $2.  Function 'i' of the list is at line 10 * i
writeInfo()
{
    local kind=$1
    local out=$2
    shift 2
    cat "$@" | awk -v kind=$kind '
BEGIN { print "TN:"; print "SF:proj/names.cpp" }
{
    l = 10 * NR
    if (kind == 2) {
        # not hit, first line hit
        printf("FNL:%d,%d,%d\nFNA:%d,0,%s\nDA:%d,1\nDA:%d,0\n",
               NR, l, l + 1, NR, $0, l, l + 1)
    } else {
        # "outer" is not hit, its second line is - where the named function
        #   starts, and is hit
        printf("FNL:%d,%d,%d\nFNA:%d,0,outer%d\n", 2 * NR, l, l + 2, 2 * NR, NR)
        printf("FNL:%d,%d,%d\nFNA:%d,1,%s\n", 2 * NR + 1, l + 1, l + 1,
               2 * NR + 1, $0)
        if ($0 ~ /^_ZZ4mainENKUlvE_clEv$/) {
            # ..and a lambda which is an alias of an ordinary function
            printf("FNA:%d,0,a\n", 2 * NR + 1)
        }
        printf("DA:%d,0\nDA:%d,1\nDA:%d,0\n", l, l + 1, l + 2)
    }
}
END {
    # line and function totals:  one line and one function of each name hit
    printf("FNF:%d\nFNH:%d\n", (kind == 2 ? 1 : 2) * NR, (kind == 2 ? 0 : NR))
    printf("LF:%d\nLH:%d\n", (kind == 2 ? 2 : 3) * NR, NR)
    print "end_of_record"
}' > $out
}

# was function '$2' reported in log $1?
reported()
{
    grep -q -F "function '$2' is not hit but line" $1
}

# ----------------------------------------------------------------------
echo "*** 2. the first line exemption, by name"
# ----------------------------------------------------------------------
writeInfo 2 first.info lambdas.txt others.txt
$COVER $LCOV_TOOL $PARALLEL $PROFILE -o first_out.info -a first.info \
    --rc ignore_lambda_consistency=0 --ignore inconsistent \
    --rc max_message_count=0 > first.log 2>&1
if [ 0 != $? ] ; then
    cat first.log
    fail first "lcov failed"
fi
while read -r name ; do
    if reported first.log "$name" ; then
        fail first "lambda '$name' was checked on its first line"
    fi
done < lambdas.txt
while read -r name ; do
    if ! reported first.log "$name" ; then
        fail first "'$name' was not reported"
    fi
done < others.txt

# ----------------------------------------------------------------------
echo "*** 3. 'ignore_lambda_consistency', by name"
# ----------------------------------------------------------------------
writeInfo 3 suppress.info lambdas.txt others.txt
$COVER $LCOV_TOOL $PARALLEL $PROFILE -o suppress_out.info -a suppress.info \
    --rc ignore_lambda_consistency=1 --ignore inconsistent \
    --rc max_message_count=0 -v > suppress.log 2>&1
if [ 0 != $? ] ; then
    cat suppress.log
    fail suppress "lcov failed"
fi
N=`wc -l < lambdas.txt`
for ((i = 1 ; i <= N ; ++i)) ; do
    if reported suppress.log outer$i ; then
        fail suppress "line of lambda '`sed -n ${i}p lambdas.txt`' was checked"
    fi
    if ! grep -q -F "names.cpp\":$((10 * i + 1)): lambda detected" \
        suppress.log ; then
        fail suppress "no suppression of lambda '`sed -n ${i}p lambdas.txt`'"
    fi
done
M=`wc -l < others.txt`
for ((i = N + 1 ; i <= N + M ; ++i)) ; do
    if ! reported suppress.log outer$i ; then
        fail suppress "line of '`sed -n $((i - N))p others.txt`' was not checked"
    fi
done

if [ 0 != $STATUS ] ; then
    echo "Tests failed"
    exit 1
fi
echo "Tests passed"

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ]; then
    generate_coverage 'lambdaname' $LOCAL_COVERAGE 0
fi
