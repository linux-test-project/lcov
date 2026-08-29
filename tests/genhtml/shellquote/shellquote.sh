#!/bin/bash
set +x

# ============================================================================
# File names which the tools hand to a shell.
#
# Most of lcov's file access is a plain 'open', which does not go through a
#   shell and so does not care what the name contains.  Four places are not:
#   the gzip pipes and the demangler pipes in 'InOutFile' (lib/lcovutil.pm),
#   and the '--html-gzip' pipe in genhtml ('html_create').  Each of those is a
#   one-argument 'open' - i.e. a command string - into which the file name was
#   interpolated raw.  So a name containing a space became two words and a name
#   containing a quote became a syntax error, and neither failure was reported
#   usefully:  'open' for a pipe reports the success of the fork, not of the
#   command, so the writing cases exited 0 having written nothing at all.
#
# The names used here are an output directory containing a space and a trace
#   file whose name contains an apostrophe.  Neither is exotic - "my project"
#   and "it's" are ordinary things to type - and between them they cover both
#   the word-splitting and the quoting failure.
#
# The cases:
#   1. '--html-gzip' into an output directory whose name contains a space
#   2. a '.gz' trace file whose name contains an apostrophe:  written by lcov,
#      then read back by lcov - the two ends of the gzip pipe
#   3. the same name, uncompressed, read through '--demangle-cpp' - the
#      demangler reads the file itself, so the name is part of that command
#   4. the demangler on the writing side.  No tool passes 'demangle' to
#      'InOutFile->out' today, so this one calls the library directly
# ============================================================================

source ../../common.tst

GENHTML_OPTS="--function-coverage $PARALLEL $PROFILE"

# the demangler stub of the genhtml demangle test:  it prefixes every function
#   name it is handed with 'aaa', which is how the cases below tell a run which
#   went through the demangler from one which did not
MYFILT="../mycppfilt.sh"

# 'deprecated' because '--demangle-cpp <tool>' is the deprecated spelling of
#   the tool name;  it is the spelling genhtml/demangle.sh uses, and the point
#   of these cases is the file name rather than the option
DEMANGLE="--demangle-cpp $MYFILT --ignore-errors deprecated"

rm -rf *.info *.info.gz *.log *.json proj rpt_* "out dir" \
    perlcov.info pycov.info __pycache__

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

# --------------------------------------------------------------------------
# the input:  one source file with one function, and coverage data for it
# written by hand - what matters here is the name of the file the data is in,
# not where the data came from
# --------------------------------------------------------------------------
mkdir -p proj

cat >proj/foo.c <<'EOF'
int xfoo_bary(int a)
{
    return a > 0 ? a : -a;
}
EOF

cat >cov.info <<'EOF'
TN:sq
SF:proj/foo.c
FN:1,xfoo_bary
FNDA:2,xfoo_bary
FNF:1
FNH:1
DA:1,2
DA:3,2
LF:2
LH:2
end_of_record
EOF

# the name with the apostrophe, used by cases 2, 3 and 4
APOS="it's.info"

# ----------------------------------------------------------------------
echo "*** 1. --html-gzip into an output directory whose name has a space"
# ----------------------------------------------------------------------
# unquoted, 'gzip -c > out dir/index.html' redirects into the directory
#   'out' - which is a directory, so the shell writes nothing and genhtml,
#   which only knows that the fork worked, reports success
$COVER $GENHTML_TOOL $GENHTML_OPTS -o 'out dir' cov.info --html-gzip \
    > gzhtml.log 2>&1
if [ 0 != $? ] ; then
    cat gzhtml.log
    fail gzhtml "genhtml failed writing to an output directory with a space"
fi
if [ ! -s 'out dir/index.html' ] ; then
    cat gzhtml.log
    ls -l 'out dir'
    fail gzhtml "no top level page was written"
elif ! gzip -t 'out dir/index.html' ; then
    fail gzhtml "the top level page is not gzip data"
fi
# ..and the shell had nothing to complain about
if grep -q 'Is a directory' gzhtml.log ; then
    cat gzhtml.log
    fail gzhtml "the output name was split into words"
fi

# ----------------------------------------------------------------------
echo "*** 2. a .gz trace file whose name contains an apostrophe"
# ----------------------------------------------------------------------
# the writing end:  'gzip -c >it's.info.gz' is an unterminated quote, so the
#   shell dies without running gzip and there is no output file
$COVER $LCOV_TOOL -a cov.info -o "$APOS.gz" > gzout.log 2>&1
if [ 0 != $? ] ; then
    cat gzout.log
    fail gzout "lcov failed writing '$APOS.gz'"
fi
if [ ! -s "$APOS.gz" ] ; then
    cat gzout.log
    fail gzout "'$APOS.gz' was not written"
elif ! gzip -t "$APOS.gz" ; then
    fail gzout "'$APOS.gz' is not valid gzip data"
fi

# ..and the reading end:  the same name back through 'gzip -cd'
$COVER $LCOV_TOOL -a "$APOS.gz" -o back.info > gzin.log 2>&1
if [ 0 != $? ] ; then
    cat gzin.log
    fail gzin "lcov failed reading '$APOS.gz'"
fi
COUNT=`grep -c '^DA:' back.info 2>/dev/null`
if [ "2" != "$COUNT" ] ; then
    cat gzin.log
    fail gzin "expected the 2 line records of cov.info, found ${COUNT:-none}"
fi

# ----------------------------------------------------------------------
echo "*** 3. the demangler reading a file whose name has an apostrophe"
# ----------------------------------------------------------------------
# '--demangle-cpp' hands the whole trace file to the demangler as its stdin
#   redirection, so the name is part of that command string too
cp cov.info "$APOS"
$COVER $LCOV_TOOL -a "$APOS" -o demangled.info $DEMANGLE > dmin.log 2>&1
if [ 0 != $? ] ; then
    cat dmin.log
    fail dmin "lcov failed reading '$APOS' through the demangler"
fi
if grep -q 'syntax error' dmin.log ; then
    cat dmin.log
    fail dmin "the file name reached the shell unquoted"
fi
# the stub prefixes every function name with 'aaa':  the data has to have gone
#   through it, and not merely have been read
if ! grep -q 'aaaxfoo_bary' demangled.info ; then
    grep '^FN' demangled.info
    fail dmin "the trace file did not go through the demangler"
fi

# ----------------------------------------------------------------------
echo "*** 4. the demangler writing a file whose name has an apostrophe"
# ----------------------------------------------------------------------
# 'InOutFile->out(name, mode, demangle)' pipes what is written to it through
#   the demangler and redirects the result into 'name'.  Nothing in bin/ asks
#   for that today, so the case is driven through the library directly rather
#   than through a tool
rm -f "$APOS"
${COVER:-perl} -I"$LCOV_HOME/lib" -e '
use lcovutil;
@lcovutil::cpp_demangle = ($ARGV[0]);
lcovutil::do_mangle_check();
my $f = InOutFile->out($ARGV[1], undef, 1);
my $h = $f->hdl();
print($h "FN:1,xfoo_bary\n");
' -- "$MYFILT" "$APOS" > dmout.log 2>&1
if [ 0 != $? ] ; then
    cat dmout.log
    fail dmout "writing '$APOS' through the demangler failed"
fi
if [ ! -s "$APOS" ] ; then
    cat dmout.log
    fail dmout "'$APOS' was not written"
elif ! grep -q '^FN:1,aaaxfoo_bary$' "$APOS" ; then
    cat "$APOS"
    fail dmout "'$APOS' did not come out of the demangler"
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'shellquote' $LOCAL_COVERAGE 0
fi

exit $STATUS
