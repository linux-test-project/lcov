#!/bin/bash
set +x

# ============================================================================
# Windows path names on the command line and in the environment.
#
# A git-bash, MSYS or Cygwin perl reports $^O as 'msys' or 'cygwin' and has no
#   notion of a drive letter:  'Z:\dir\file' is not an absolute path to it, and
#   a backslash is not a separator.  The drives are mounted in those
#   installations, so there is a name for the same file which that perl can
#   open, and 'posix_path' in lcovutil.pm is the translation to it:  every
#   backslash to a forward slash, and then 'Z:/...' to '<mount>/z/...'.
#
# The data side of this - a Windows name inside a .info file or a udiff - has
#   machinery of its own ('translate_path_separator', '$cross_platform_read').
#   What is tested here is the other half:  the names each tool has to open,
#   exec or write itself, which arrive on its own command line or in its
#   environment.  Two things went wrong when those were left untranslated:
#
#   - 'glob' treats a backslash as its own escape character, so the tracefile
#     argument 'Z:\in\t.info' expanded to 'Z:int.info', and the resulting
#     complaint named a file nobody had asked for.  That one bites on Linux
#     too, because 'glob' does it everywhere;
#   - an output name with a drive letter in it was used as written, so the
#     report or the .info file was quietly created in the current directory
#     under the literal name 'Z:\out\...' instead of on the drive.
#
# 'py2lcov' and 'xml2lcov' are python, and the same thing happens to them:  on
#   such a python 'sys.platform' is 'msys' or 'cygwin' and 'os.path' is
#   'posixpath', so os.path.split('Z:\bin\py2lcov') finds no directory at all
#   and os.path.join() puts another one in front of a drive-lettered name.
#   'posix_path' in xml2lcovutil.py is the same translation as the perl one, and
#   two things went wrong without it:  sys.path[0] became the current directory
#   rather than the directory the script is installed in, so 'import
#   xml2lcovutil' picked up whatever happened to be in the current directory or
#   nothing at all, and the 'lcov' which appends versions was left as a bare
#   relative name and looked for on the PATH.
#
# $LCOV_DRIVE_MOUNT is a test hook (see lcovutil.pm):  it names one more
#   directory to look for the mounted drives in, and turns the translation on,
#   so every line of it can be exercised from any platform.  'mnt/z' below is
#   therefore what 'Z:' means here, and every case writes its output under it -
#   so a name which was not translated shows up as a stray 'Z:...' entry in
#   this directory, which 'no_literals' checks for after each run.
#
# Cases:
#   1. a drive-lettered, backslashed tracefile argument reaches 'find_from_glob'
#      as the mounted name, and is not mangled by 'glob' on the way
#   2. genhtml's own file options - and gendesc, which writes one of them
#   3. genhtml's --baseline-file, --diff-file and --serialize, plus the common
#      --msg-log, --profile and --build-directory
#   4. --tempdir: the temporary directory is created on the drive
#   5. --config-file, both when it is there and when it is not
#   6. $HOME as a Windows path: the '.lcovrc' fallback in 'apply_rc_params'
#   7. the --...-script callbacks, in both their script and their module form
#   8. lcov: the positional tracefiles, -o, --intersect, --subtract, -e and -r
#   9. lcov -z: the directory arguments
#  10. lcov --to-package and --from-package, with -c, -d and -b
#  11. --gcov-tool: the gcov on the drive is the one which runs
#  12. geninfo: the positional data directories, including as a glob, and -b
#  13. html2lcov: the report argument, --source-directory, -o, --diff-file and
#      --current-file
#  14. perl2lcov: the Devel::Cover database argument and -o
#  15. llvm2lcov: the coverage export argument and -o
#  16. genpng: the source file argument and -o
#  17. a drive which is not mounted is left as the user wrote it
#  18. xml2lcov: the XML report, -o, -s and the source roots the report names
#  19. py2lcov: the coverage data files, -i, -o and --cmd
#  20. what the python tools make of their own sys.argv[0]: the directory
#      'xml2lcovutil' is imported from, and the 'lcov' installed beside them
#  21. the python tools with an unmounted drive, and with no drives mounted
#      anywhere - so with the translation off altogether
#  22. a PATH entry which is a drive letter that was split on its own ':' - the
#      one thing here which no translation can repair, only report
# ============================================================================

if [[ "x" == ${LCOV_HOME}x ]] ; then
    if [ -f ../../bin/lcov ] ; then
        LCOV_HOME=../..
    fi
fi

source ../common.tst

# 'Z:*' as well:  an untranslated output name leaves a file or a directory here
#   whose name is the literal Windows path, and the point of the run which
#   created it was that nothing should have
rm -rf mnt *.log Z:* *.info html_report

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

# ---------------------------------------------------------------------------
# the fake drive.  'Z:' is '$MNT/z', because $LCOV_DRIVE_MOUNT says to look for
# the drives in $MNT - so '$IN' and '$OUT' below are the names this shell uses
# for the directories the tools are told about as 'Z:\in' and 'Z:\out'
# ---------------------------------------------------------------------------
MNT=$ROOT/mnt
DRIVE=$MNT/z
IN=$DRIVE/in
OUT=$DRIVE/out
export LCOV_DRIVE_MOUNT=$MNT

# no other testcase runs gendesc, so neither common.mak nor common.tst names it
GENDESC_TOOL=${LCOV_HOME}/bin/gendesc

mkdir -p $IN/src $IN/build $IN/home $IN/reset $OUT

# something for 'lcov -z' to remove, in a directory of its own:  the build
#   directory below has the data every capture case needs
touch $IN/reset/x.gcda

cat > $IN/src/test.c <<'EOF'
#include <stdio.h>
int main(int argc, char** argv)
{
    if (argc > 1)
        printf("hello\n");
    else
        printf("goodbye\n");
    return 0;
}
EOF

# one file, with line, function and branch data, so that every tool below has
#   something to say about all three
cat > $IN/t.info <<EOF
TN:winpath
SF:$IN/src/test.c
FN:2,9,main
FNDA:1,main
FNF:1
FNH:1
BRDA:4,0,0,1
BRDA:4,0,1,0
BRF:2
BRH:1
DA:2,1
DA:4,1
DA:5,1
DA:7,0
DA:8,1
LF:5
LH:4
end_of_record
EOF

# a baseline version of the source, and the udiff from it to the current one.
#   The names in the udiff have to be the ones the .info file uses, or genhtml
#   reports a path mismatch which has nothing to do with this test
sed -e 's/goodbye/farewell/' $IN/src/test.c > $IN/base.c
diff -u $IN/base.c $IN/src/test.c |
    sed -e "1s#.*#--- $IN/src/test.c#" -e "2s#.*#+++ $IN/src/test.c#" \
    > $IN/t.diff

printf '/* winpath_css_marker */\nbody { background: #fff; }\n' > $IN/my.css
printf '<html><body><!-- winpath_prolog_marker -->\n' > $IN/prolog.html
printf '<!-- winpath_epilog_marker --></body></html>\n' > $IN/epilog.html
printf 'winpath\n\ta windows path testcase\n' > $IN/desc.txt

# a callback module which reports where perl found it:  it loads only if its
#   directory went onto @INC, and the path is our text, not perl's
cat > $IN/winpath_probe.pm <<'EOF'
package winpath_probe;
sub new { die("winpath_probe loaded from $INC{'winpath_probe.pm'}\n"); }
1;
EOF

# 'branch_coverage' is off by default in every tool, so a run which reports
#   branches is a run which read the config file
printf 'branch_coverage = 1\n' > $IN/my.lcovrc
cp $IN/my.lcovrc $IN/home/.lcovrc

# the gcov this toolchain captures with - see common.tst - reachable only as a
#   name on the drive
ln -sf $GCOV $DRIVE/gcov

# real coverage data for the capture cases:  the object has to be built where
#   the .gcda is to be written, which is the directory geninfo is pointed at.
#   Without a working compiler there is nothing to capture, and those cases
#   cannot run at all
CAPTURE=1
if ! ( cd $IN/build && ${CC:-gcc} --coverage -o test $IN/src/test.c &&
       ./test ) > compile.log 2>&1 ; then
    echo "unable to build an instrumented executable - skipping the captures"
    cat compile.log
    CAPTURE=
fi

# an llvm-cov export for the same source.  Hand-written, as in
#   tests/llvm2lcov/malformed.sh:  this test needs no clang
cat > $IN/llvm.json <<'EOF'
{ "version": "2.0.1", "data": [ { "files": [ { "filename": "src/test.c",
  "segments": [ [2,1,3,1,1,0], [4,9,2,1,1,0], [5,9,1,1,1,0],
                [8,5,1,1,1,0], [9,2,0,0,0,0] ], "branches": [] } ],
  "functions": [ { "name": "main", "count": 3, "filenames": [ "src/test.c" ],
                   "regions": [ [2,1,9,2,3,0,0,0] ], "branches": [] } ] } ] }
EOF

# a Devel::Cover database for perl2lcov to read
cat > $IN/tiny.pl <<'EOF'
sub f { return 1 }
f();
EOF
perl -MDevel::Cover=-db,$IN/cov_db,-coverage,statement,subroutine,-silent,1 \
    $IN/tiny.pl > /dev/null 2>&1
cover $IN/cov_db -silent 1 > /dev/null 2>&1
if [ ! -d $IN/cov_db ] ; then
    echo "unable to create a Devel::Cover database - skipping case 14"
    NO_COVER_DB=1
fi

# ---------------------------------------------------------------------------
# the python tools.  Neither common.mak nor common.tst names the scripts
#   themselves - only the command lines which run them under the coverage tool -
#   and cases 18 to 20 need both:  the script, to copy and to link to, and the
#   way the rest of the suite runs it
# ---------------------------------------------------------------------------
PY2LCOV_SCRIPT=${LCOV_HOME}/bin/py2lcov
XML2LCOV_SCRIPT=${LCOV_HOME}/bin/xml2lcov

if [ 'x' == "x$CMD" ] ; then
    if [ '' != "${COVERAGE_COMMAND}" ] ; then
        CMD=${COVERAGE_COMMAND}
    else
        CMD='coverage'
        if ! which $CMD > /dev/null 2>&1 ; then
            CMD='python3-coverage' # ubuntu?
        fi
    fi
fi
PYTHON=1
if ! which $CMD > /dev/null 2>&1 ; then
    echo "cannot find 'coverage' or 'python3-coverage'"
    echo "unable to run the python tools - skipping cases 18 to 20"
    PYTHON=
fi

if [ -n "$PYTHON" ] ; then

    # how a python tool is run.  The other testcases hand $PYCOVER to 'eval',
    #   which cannot be done here:  'eval' re-parses its arguments and would eat
    #   the backslashes which are the whole point of this test.  $PYCOVER is a
    #   plain word list - an environment variable assignment followed by a
    #   command - so 'env' runs it as it stands.  Without it the script is run by
    #   naming the interpreter, because some of the names below are relative and
    #   have no '/' in them at all:  the shell would look for those on the PATH
    if [ -n "$PYCOVER" ] ; then
        # ... and the database $PYCOVER names is relative to this directory,
        #   which is not the directory every case below runs in
        PYDB=$PYCOV_DB
        case $PYDB in
            /* ) ;;
            *  ) PYDB=$ROOT/$PYDB ;;
        esac
        PYRUN=(env "COVERAGE_FILE=$PYDB" $CMD run --branch --append)
    else
        PYRUN=(python3)
    fi

    # a Cobertura report whose source root is named the windows way, as a report
    #   written on windows names it, and whose one class names a file below that
    #   root
    cat > $IN/cob.xml <<'EOF'
<?xml version="1.0"?>
<coverage line-rate="0.8" branch-rate="0.5" version="2.0.3" timestamp="0">
  <sources>
    <source>Z:\in\src</source>
  </sources>
  <packages>
    <package name="winpath" line-rate="0.8" branch-rate="0.5">
      <classes>
        <class name="test" filename="test.c" line-rate="0.8" branch-rate="0.5">
          <lines>
            <line number="2" hits="1" branch="false"/>
            <line number="4" hits="1" branch="true" condition-coverage="50% (1/2)"/>
            <line number="5" hits="1" branch="false"/>
            <line number="7" hits="0" branch="false"/>
            <line number="8" hits="1" branch="false"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
EOF
    # the same report with no source roots at all, so that the file is found in
    #   the '--source-directory' search path instead - which is the other list
    #   of directories to be translated
    sed -e '/source/d' -e 's#filename="test.c"#filename="src/test.c"#' \
        $IN/cob.xml > $IN/cob2.xml

    # a Coverage.py database, for the input which is not XML:  py2lcov runs the
    #   '--cmd' executable to turn it into XML, and writes that XML beside the
    #   input file
    printf 'def f(x):\n    if x:\n        return 1\n    return 0\nf(1)\n' \
        > $IN/prog.py
    COVERAGE_FILE=$IN/py.dat $CMD run --branch $IN/prog.py > pydata.log 2>&1
    if [ ! -f $IN/py.dat ] ; then
        echo "unable to create a Coverage.py database - skipping the .dat case"
        cat pydata.log
        NO_PY_DAT=1
    fi
    printf '#!/bin/bash\nexec %s "$@"\n' "$CMD" > $DRIVE/covcmd
    chmod ugo+x $DRIVE/covcmd

    # the installation, reachable as a name on the drive:  'Z:\bin' is then the
    #   directory the tools are installed in, so 'Z:\bin\xml2lcov' is the name a
    #   windows caller would pass in sys.argv[0] and 'Z:\bin\lcov' is the lcov
    #   installed beside it
    ln -sf ${LCOV_HOME}/bin $DRIVE/bin

    # the drive-lettered names python is called by.  This platform has to be
    #   able to open them too, or python cannot run the script at all, so they
    #   are links into the installation:  what is under test is what the script
    #   makes of the name it was called by, not how it was found
    ARGV0=$MNT/argv0
    mkdir -p $ARGV0
    ln -sf $PY2LCOV_SCRIPT  "$ARGV0/Z:\\bin\\py2lcov"
    ln -sf $XML2LCOV_SCRIPT "$ARGV0/Z:\\bin\\xml2lcov"

    # ... and a copy, in a directory of its own.  A link is resolved before
    #   sys.path[0] is computed, so the installation is on the search path
    #   whether the name was translated or not;  a copy is not, so this is the
    #   case where the script has to find 'xml2lcovutil' for itself.  The copy
    #   is deliberately not run under the coverage tool:  it is not the file
    #   whose coverage is being measured, and its records would be filed under a
    #   name which is part of this fixture
    ARGV0COPY=$MNT/argv0copy
    mkdir -p $ARGV0COPY
    cp $PY2LCOV_SCRIPT "$ARGV0COPY/Z:\\bin\\py2lcov"
fi

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# run <label> <expected exit status> <tool> <args>... -- log goes to <label>.log
run()
{
    local label=$1
    local expect=$2
    local tool=$3
    shift 3

    echo "$label: $tool $*"
    $COVER $tool "$@" > $label.log 2>&1
    check_rc $label $expect $?
}

# runpy <label> <expected exit status> <tool> <args>... -- 'run' for the python
#   tools.  $RUNDIR, when it is set, is the directory to run in:  what a script
#   makes of its own sys.argv[0] depends on where it was called from.  $PYUNSET
#   is for the one case which turns the translation off again
runpy()
{
    local label=$1
    local expect=$2
    local tool=$3
    shift 3

    echo "$label: $tool $*"
    ( cd ${RUNDIR:-$ROOT} && $PYUNSET "${PYRUN[@]}" $tool "$@" ) \
        > $ROOT/$label.log 2>&1
    check_rc $label $expect $?
}

# check_rc <label> <expected exit status> <actual> -- shared by the two above.
#   Returns non-zero if the run is not worth looking at any further
check_rc()
{
    if [ "$2" == 'nonzero' ] ; then
        if [ 0 == $3 ] ; then
            fail $1 "expected a non-zero exit status"
            cat $1.log
            return 1
        fi
    elif [ $3 != $2 ] ; then
        fail $1 "expected exit status $2, got $3:"
        cat $1.log
        return 1
    fi
    no_literals $1
    return 0
}

# expect_log <label> <string> -- the run said this
expect_log()
{
    if ! grep -F -q -e "$2" $1.log ; then
        fail $1 "expected '$2' in the output:"
        cat $1.log
    fi
}

# reject_log <label> <string> -- and did not say this
reject_log()
{
    if grep -F -q -e "$2" $1.log ; then
        grep -F -e "$2" $1.log
        fail $1 "did not expect '$2' in the output"
    fi
}

# expect_file <label> <path>... -- each of these was created
expect_file()
{
    local label=$1
    shift
    local f
    for f in "$@" ; do
        if [ ! -e "$f" ] ; then
            fail $label "'$f' was not created"
        fi
    done
}

# expect_content <label> <file> <string> -- the file holds this
expect_content()
{
    if [ ! -f "$2" ] ; then
        fail $1 "'$2' was not created"
    elif ! grep -F -q -e "$3" "$2" ; then
        fail $1 "'$2' does not contain '$3'"
    fi
}

# no_literals <label> -- an untranslated output name is a file or directory in
#   this directory whose name still has the drive letter in it.  Nothing this
#   test asks for should be here at all:  every output name it uses is on the
#   drive
no_literals()
{
    local stray=`find . -maxdepth 1 \( -name '*Z:*' -o -name '*\\*' \) -print`
    if [ -n "$RUNDIR" ] ; then
        # and in the directory the case ran in, when that is not this one.  The
        #   drive-lettered names python is called by live there and are links -
        #   so anything there which is not a link is a stray
        stray="$stray `find $RUNDIR -maxdepth 1 \
            \( -name '*Z:*' -o -name '*\\*' \) -not -type l -print`"
        stray=`echo $stray`
    fi
    if [ -n "$stray" ] ; then
        echo "$stray"
        fail $1 "a path name was used untranslated"
    fi
}

# ----------------------------------------------------------------------
echo "*** 1. a drive-lettered, backslashed tracefile argument"
# ----------------------------------------------------------------------
# 'find_from_glob' is where every positional tracefile argument of genhtml and
#   of lcov arrives.  It has to translate before it globs as well as before it
#   tests for the file:  'glob' would turn 'Z:\in\t.info' into 'Z:int.info',
#   which is a name the user never wrote and a file which cannot exist
if run glob 0 $GENHTML_TOOL 'Z:\in\t.info' -o 'Z:\out\r1' ; then
    expect_log glob "$IN/t.info"
    reject_log glob 'Z:int.info'
    expect_file glob $OUT/r1/index.html
fi

# ----------------------------------------------------------------------
echo "*** 2. genhtml's own file options, and gendesc"
# ----------------------------------------------------------------------
# gendesc parses its own command line rather than calling 'parseOptions', so it
#   translates both of its paths itself.  Its output is then genhtml's
#   '--description-file', which is one of the options genhtml translates
if run gendesc 0 $GENDESC_TOOL 'Z:\in\desc.txt' -o 'Z:\out\desc' ; then
    expect_content gendesc $OUT/desc 'TD: a windows path testcase'
fi
if run genhtml_files 0 $GENHTML_TOOL 'Z:\in\t.info' -o 'Z:\out\r2' \
    --css-file 'Z:\in\my.css' --description-file 'Z:\out\desc' \
    --show-details --html-prolog 'Z:\in\prolog.html' \
    --html-epilog 'Z:\in\epilog.html' ; then
    expect_content genhtml_files $OUT/r2/gcov.css 'winpath_css_marker'
    expect_content genhtml_files $OUT/r2/index.html 'winpath_prolog_marker'
    expect_content genhtml_files $OUT/r2/index.html 'winpath_epilog_marker'
    expect_file genhtml_files $OUT/r2/descriptions.html
fi

# ----------------------------------------------------------------------
echo "*** 3. --baseline-file, --diff-file, --serialize and the common options"
# ----------------------------------------------------------------------
# '--baseline-file' goes through 'find_from_glob' like the current tracefiles;
#   the rest are translated by genhtml and by 'parseOptions'.  '--msg-log' is
#   worth naming explicitly because its default is derived from the output
#   argument, which is itself a name to be translated.
#   The baseline here is the current data, so every version is '<undef>' and
#   matches - which is the 'inconsistent' error, and is not what is under test
if run genhtml_diff 0 $GENHTML_TOOL 'Z:\in\t.info' -o 'Z:\out\r3' \
    --baseline-file 'Z:\in\t.info' --diff-file 'Z:\in\t.diff' \
    --serialize 'Z:\out\serial.dat' --msg-log 'Z:\out\msg.log' \
    --profile 'Z:\out\prof.json' --build-directory 'Z:\in\src' \
    --ignore-errors inconsistent ; then
    expect_log genhtml_diff "$IN/t.diff"
    expect_file genhtml_diff $OUT/r3/index.html $OUT/serial.dat $OUT/msg.log \
        $OUT/prof.json
fi

# ----------------------------------------------------------------------
echo "*** 4. --tempdir"
# ----------------------------------------------------------------------
# '--preserve' so that what was created is still there to be looked at
if run tempdir 0 $GENHTML_TOOL 'Z:\in\t.info' -o 'Z:\out\r4' \
    --tempdir 'Z:\out\tmp' --preserve ; then
    if [ ! -d $OUT/tmp ] ; then
        fail tempdir "the temporary directory was not created on the drive"
    fi
fi

# ----------------------------------------------------------------------
echo "*** 5. --config-file"
# ----------------------------------------------------------------------
# the config file is read by 'apply_rc_params', before 'GetOptions' - so it is
#   translated there and not with the rest of the options.  It sets
#   'branch_coverage', which is off by default:  a summary which reports
#   branches is one which read the file
if run config 0 $LCOV_TOOL --summary 'Z:\in\t.info' \
    --config-file 'Z:\in\my.lcovrc' ; then
    expect_log config 'branches....: 50.0%'
fi
# and a config file which is not there is reported by the name it was looked
#   for under - not by the Windows name, which says nothing about where this
#   perl went hunting
if run config_missing nonzero $LCOV_TOOL --summary 'Z:\in\t.info' \
    --config-file 'Z:\in\nosuch.lcovrc' ; then
    expect_log config_missing "cannot read configuration file '$IN/nosuch.lcovrc'"
fi

# ----------------------------------------------------------------------
echo "*** 6. \$HOME as a Windows path"
# ----------------------------------------------------------------------
# with no '--config-file', 'apply_rc_params' falls back to '$HOME/.lcovrc' and
#   then to '$LCOV_HOME/etc/lcovrc'.  Both of those come from the environment,
#   which on Windows holds Windows names
echo "home: HOME='Z:\\in\\home' lcov --summary"
HOME='Z:\in\home' $COVER $LCOV_TOOL --summary 'Z:\in\t.info' > home.log 2>&1
if [ 0 != $? ] ; then
    fail home "lcov failed with HOME naming a drive"
    cat home.log
else
    expect_log home 'branches....: 50.0%'
fi
no_literals home

# ----------------------------------------------------------------------
echo "*** 7. the --...-script callbacks"
# ----------------------------------------------------------------------
# every '--...-script' option of every tool is configured by
#   'configure_callback', so translating the script name there covers all of
#   them.  Only the first element is a path of ours - the rest are the
#   callback's own arguments.  The first two scripts do not exist:  what is
#   under test is which name the failure reports.  The probe module shows which
#   directory went onto @INC
if run callback_script nonzero $GENHTML_TOOL 'Z:\in\t.info' -o 'Z:\out\r5' \
    --annotate-script 'Z:\in\nosuch.sh' ; then
    expect_log callback_script "$IN/nosuch.sh"
fi
if run callback_module nonzero $GENHTML_TOOL 'Z:\in\t.info' -o 'Z:\out\r6' \
    --version-script 'Z:\in\nosuch.pm' ; then
    expect_log callback_module "unable to create callback from module '$IN/nosuch.pm'"
fi
if run callback_inc nonzero $GENHTML_TOOL 'Z:\in\t.info' -o 'Z:\out\r6p' \
    --version-script 'Z:\in\winpath_probe.pm' ; then
    expect_log callback_inc "winpath_probe loaded from $IN/winpath_probe.pm"
fi

# ----------------------------------------------------------------------
echo "*** 8. lcov: the tracefile arguments and the set operations"
# ----------------------------------------------------------------------
# '-o' is translated by 'parseOptions', which every tool hands its output
#   argument to;  the positional files and the '--intersect'/'--subtract'
#   patterns all go through 'find_from_glob';  '-e' and '-r' take the tracefile
#   as the option value and the patterns positionally, which is why the
#   positional arguments of lcov cannot simply be translated as a block
if run lcov_add 0 $LCOV_TOOL -a 'Z:\in\t.info' -o 'Z:\out\a.info' ; then
    expect_file lcov_add $OUT/a.info
fi
if run lcov_intersect 0 $LCOV_TOOL 'Z:\in\t.info' \
    --intersect 'Z:\in\t.info' -o 'Z:\out\i.info' ; then
    expect_file lcov_intersect $OUT/i.info
fi
if run lcov_subtract 0 $LCOV_TOOL 'Z:\in\t.info' \
    --subtract 'Z:\in\t.info' -o 'Z:\out\s.info' --ignore-errors empty ; then
    expect_file lcov_subtract $OUT/s.info
fi
if run lcov_extract 0 $LCOV_TOOL -e 'Z:\in\t.info' '*/test.c' \
    -o 'Z:\out\e.info' ; then
    expect_file lcov_extract $OUT/e.info
fi
if run lcov_remove 0 $LCOV_TOOL -r 'Z:\in\t.info' '*/nomatch.c' \
    -o 'Z:\out\rm.info' --ignore-errors unused ; then
    expect_file lcov_remove $OUT/rm.info
fi

# ----------------------------------------------------------------------
echo "*** 9. lcov -z: the directory arguments"
# ----------------------------------------------------------------------
# the same 'translate before you glob' as case 1, in the loop which expands the
#   directories to reset.  'Z:\in\re*et' is a pattern which matches nothing
#   until the separators have been translated
if run zero 0 $LCOV_TOOL -z -d 'Z:\in\re*et' ; then
    expect_log zero "$IN/reset"
    if [ -f $IN/reset/x.gcda ] ; then
        fail zero "the .gcda file on the drive was not removed"
    fi
fi
if run zero_missing nonzero $LCOV_TOOL -z -d 'Z:\in\nosuchdir' ; then
    expect_log zero_missing "$IN/nosuchdir is not a directory"
fi

# ----------------------------------------------------------------------
echo "*** 10. lcov --to-package and --from-package"
# ----------------------------------------------------------------------
# '--to-package' and '--from-package' name archives this tool reads and writes
#   itself, and the single directory argument of a '--to-package' capture is
#   used here rather than handed on to geninfo - so lcov translates that one too
if [ -n "$CAPTURE" ] ; then
    if run to_package 0 $LCOV_TOOL -c -d 'Z:\in\build' -b 'Z:\in\src' \
        --to-package 'Z:\out\pkg.tgz' ; then
        expect_log to_package "$IN/build"
        expect_log to_package "$IN/src"
        expect_file to_package $OUT/pkg.tgz
    fi
    if run from_package 0 $LCOV_TOOL --from-package 'Z:\out\pkg.tgz' -c \
        -o 'Z:\out\fp.info' ; then
        expect_log from_package "$OUT/pkg.tgz"
        expect_file from_package $OUT/fp.info
    fi
fi

# ----------------------------------------------------------------------
echo "*** 11. --gcov-tool"
# ----------------------------------------------------------------------
# '$DRIVE/gcov' is this toolchain's own gcov, reachable only by a name on the
#   drive:  geninfo runs it to find out its version and then to read the data,
#   so a capture which produces coverage is proof that the translated name was
#   executed.  lcov forwards its own '--gcov-tool' to geninfo, so both are
#   worth a run
if [ -n "$CAPTURE" ] ; then
    if run gcov_tool_lcov 0 $LCOV_TOOL -c -d 'Z:\in\build' \
        --gcov-tool 'Z:\gcov' -o 'Z:\out\c.info' ; then
        expect_log gcov_tool_lcov 'Found gcov version:'
        expect_content gcov_tool_lcov $OUT/c.info "SF:$IN/src/test.c"
    fi
    if run gcov_tool_geninfo 0 $GENINFO_TOOL 'Z:\in\build' \
        --gcov-tool 'Z:\gcov' -o 'Z:\out\c2.info' ; then
        expect_log gcov_tool_geninfo 'Found gcov version:'
        expect_content gcov_tool_geninfo $OUT/c2.info "SF:$IN/src/test.c"
    fi
fi

# ----------------------------------------------------------------------
echo "*** 12. geninfo: the data directories and --base-directory"
# ----------------------------------------------------------------------
# the positional arguments are expanded the same way as lcov's, so the same
#   'glob' escape applies;  'Z:\in\bu*ld' is a pattern which only matches once
#   the separators have been translated.  '--base-directory' additionally goes
#   through 'solve_relative_path', which used to carry a second, MSYS-only copy
#   of this translation
if [ -n "$CAPTURE" ] ; then
    if run geninfo_glob 0 $GENINFO_TOOL 'Z:\in\bu*ld' -b 'Z:\in\src' \
        -o 'Z:\out\g.info' ; then
        expect_log geninfo_glob "$IN/build"
        reject_log geninfo_glob 'Z:inbu*ld'
        expect_file geninfo_glob $OUT/g.info
    fi
fi
if run geninfo_missing nonzero $GENINFO_TOOL 'Z:\in\nosuchdir' \
    -o 'Z:\out\g2.info' ; then
    expect_log geninfo_missing "$IN/nosuchdir"
fi

# ----------------------------------------------------------------------
echo "*** 13. html2lcov"
# ----------------------------------------------------------------------
# the report to read is a positional argument, '--current-file' names .info
#   files to read, and '--diff-file' the udiff to write.  The report is the one
#   case 2 wrote - with '--save', so that the .info file html2lcov needs is in
#   it
if run genhtml_save 0 $GENHTML_TOOL 'Z:\in\t.info' -o 'Z:\out\r7' --save ; then
    expect_file genhtml_save $OUT/r7/index.html
fi
if run html2lcov 0 $HTML2LCOV_TOOL 'Z:\out\r7' --source-directory 'Z:\in' \
    -o 'Z:\out\h.info' --current-file 'Z:\in\t.info' \
    --diff-file 'Z:\out\h.udiff' --ignore-errors empty,unused,source ; then
    expect_log html2lcov "$OUT/r7"
    expect_file html2lcov $OUT/h.info $OUT/h.udiff
fi

# ----------------------------------------------------------------------
echo "*** 14. perl2lcov"
# ----------------------------------------------------------------------
if [ -z "$NO_COVER_DB" ] ; then
    if run perl2lcov 0 $PERL2LCOV_TOOL 'Z:\in\cov_db' -o 'Z:\out\p.info' \
        --ignore-errors empty ; then
        expect_file perl2lcov $OUT/p.info
    fi
fi

# ----------------------------------------------------------------------
echo "*** 15. llvm2lcov"
# ----------------------------------------------------------------------
if run llvm2lcov 0 $LLVM2LCOV_TOOL 'Z:\in\llvm.json' -o 'Z:\out\llvm.info' \
    --ignore-errors empty,source ; then
    expect_file llvm2lcov $OUT/llvm.info
fi

# ----------------------------------------------------------------------
echo "*** 16. genpng"
# ----------------------------------------------------------------------
# genpng parses its own command line, as gendesc does.  It needs GD.pm, which
#   is optional - a machine without it cannot run this case at all
if perl -e 'use GD;' > /dev/null 2>&1 ; then
    if run genpng 0 $GENPNG_TOOL 'Z:\in\src\test.c' -o 'Z:\out\test.png' ; then
        expect_file genpng $OUT/test.png
    fi
else
    echo "GD.pm is not installed - skipping"
fi

# ----------------------------------------------------------------------
echo "*** 17. a drive this installation has not mounted"
# ----------------------------------------------------------------------
# there is no 'y' under any of the mount points, so there is no name for 'Y:'
#   to be translated to.  The separators are still turned around - that part
#   needs no mount point - and the drive is left as the user wrote it, so that
#   whatever needs the file complains about the drive which was actually named
if run unmounted nonzero $LCOV_TOOL --summary 'Y:\in\t.info' ; then
    expect_log unmounted "'Y:/in/t.info'"
fi

# ----------------------------------------------------------------------
echo "*** 18. xml2lcov: the report, -o and the source roots"
# ----------------------------------------------------------------------
# 'ProcessFile.__init__' translates every path the command line named before any
#   of them is opened, and the source roots the report itself names are
#   translated as they are read.  '--checksum' makes the translation read the
#   source, so a root which was not translated is a run which finds nothing
if [ -n "$PYTHON" ] ; then
    if runpy xml2lcov 0 $XML2LCOV_SCRIPT 'Z:\in\cob.xml' -o 'Z:\out\x.info' \
        -t winpath --checksum ; then
        expect_content xml2lcov $OUT/x.info "SF:$IN/src/test.c"
        expect_content xml2lcov $OUT/x.info 'BRDA:4,'
    fi
    # and the '--source-directory' search path, which is where the file is
    #   looked for when the report names no root of its own
    if runpy xml2lcov_srcdir 0 $XML2LCOV_SCRIPT 'Z:\in\cob2.xml' \
        -o 'Z:\out\x2.info' -s 'Z:\in' ; then
        expect_content xml2lcov_srcdir $OUT/x2.info "SF:$IN/src/test.c"
    fi
fi

# ----------------------------------------------------------------------
echo "*** 19. py2lcov: the data files, -i and --cmd"
# ----------------------------------------------------------------------
# py2lcov shares 'ProcessFile' with xml2lcov and adds two path options of its
#   own:  the deprecated '-i', which it appends to the positional list, and
#   '--cmd', the Coverage.py executable it runs to turn a database into XML.
#   That XML is written beside the input file, so an input name which was not
#   translated leaves a literal 'Z:\in\...' here - which 'no_literals' is
#   looking for
if [ -n "$PYTHON" ] ; then
    if runpy py2lcov_input 0 $PY2LCOV_SCRIPT -i 'Z:\in\cob.xml' \
        -o 'Z:\out\p1.info' --no-functions ; then
        expect_content py2lcov_input $OUT/p1.info "SF:$IN/src/test.c"
    fi
    if [ -z "$NO_PY_DAT" ] ; then
        if runpy py2lcov_dat 0 $PY2LCOV_SCRIPT 'Z:\in\py.dat' \
            -o 'Z:\out\p2.info' --cmd 'Z:\covcmd' ; then
            expect_content py2lcov_dat $OUT/p2.info "$IN/prog.py"
            if [ -f $IN/py.xml ] ; then
                fail py2lcov_dat "the intermediate XML file was left behind"
            fi
        fi
    fi
fi

# ----------------------------------------------------------------------
echo "*** 20. the installation directory: sys.path and the lcov beside it"
# ----------------------------------------------------------------------
# What a python tool makes of its own sys.argv[0].  Both names below are
#   computed from it:  the directory 'xml2lcovutil' is imported from, and the
#   'lcov' which is run to append versions.  See the fixtures above for why the
#   first two runs use a link and the last two a copy
if [ -n "$PYTHON" ] ; then
    RUNDIR=$ARGV0
    # the module form of '--version-script' is appended by lcov rather than by
    #   the translation.  The module does not exist, so lcov fails - and the
    #   failure names the command which was run, which is how we see which
    #   'lcov' it was and that the module name reached it translated
    if runpy argv0_lcov nonzero 'Z:\bin\xml2lcov' 'Z:\in\cob.xml' \
        -o 'Z:\out\x3.info' --version-script 'Z:\in\nosuch.pm' ; then
        expect_log argv0_lcov "$DRIVE/bin/lcov"
        expect_log argv0_lcov "$IN/nosuch.pm"
    fi
    # the import is at the top of the script, so a run which gets as far as
    #   writing its output is a run which found the module
    if runpy argv0_py2lcov 0 'Z:\bin\py2lcov' -i 'Z:\in\cob.xml' \
        -o 'Z:\out\p3.info' --no-functions ; then
        expect_content argv0_py2lcov $OUT/p3.info "SF:$IN/src/test.c"
    fi
    RUNDIR=

    # the copy:  the directory python falls back to is not the installation, so
    #   the module is found only if the script worked out where it was installed
    if ( cd $ARGV0COPY && python3 'Z:\bin\py2lcov' --help ) \
        > argv0_copy.log 2>&1 ; then
        no_literals argv0_copy
    else
        fail argv0_copy "the copy did not find 'xml2lcovutil'"
        cat argv0_copy.log
    fi
    # ... and with the drives unmounted there is no name for 'Z:' to be
    #   translated to, so there is nowhere to look and the import fails - which
    #   is what used to happen with them mounted as well
    if ( cd $ARGV0COPY && env -u LCOV_DRIVE_MOUNT python3 'Z:\bin\py2lcov' \
        --help ) > argv0_unmounted.log 2>&1 ; then
        fail argv0_unmounted "expected the import to fail"
        cat argv0_unmounted.log
    else
        expect_log argv0_unmounted 'xml2lcovutil'
    fi
fi

# ----------------------------------------------------------------------
echo "*** 21. the python tools: an unmounted drive, and no translation at all"
# ----------------------------------------------------------------------
# the other two ends of 'posix_path', as case 17 is for the perl one:  a drive
#   which is not mounted has no name to be translated to and is left as the user
#   wrote it, and with the drives not mounted anywhere the translation is off
#   altogether and every name is used exactly as it was given - which is what a
#   python that understands its own path names does
if [ -n "$PYTHON" ] ; then
    if runpy unmounted_py nonzero $XML2LCOV_SCRIPT 'Y:\in\cob.xml' \
        -o 'Z:\out\y.info' ; then
        expect_log unmounted_py 'Y:/in/cob.xml'
    fi
    PYUNSET='env -u LCOV_DRIVE_MOUNT'
    if runpy notranslate 0 $XML2LCOV_SCRIPT $IN/cob2.xml -o $OUT/x4.info \
        -s $IN ; then
        expect_content notranslate $OUT/x4.info "SF:$IN/src/test.c"
    fi
    PYUNSET=
fi

# ----------------------------------------------------------------------
echo "*** 22. a PATH entry which is a drive letter split on its ':'"
# ----------------------------------------------------------------------
# 'S:/tools/lcov/bin' put into a PATH whose separator is ':' becomes the two
#   entries 'S' and '/tools/lcov/bin', neither of which is a directory - so
#   nothing in the directory which was meant is on the PATH at all, while the
#   variable still reads as though it were, and what cannot be found afterwards
#   is 'java' or 'gcov' rather than anything which names a drive.  A
#   single-letter entry is the signature of that, and 'warn_mangled_path' says
#   so at startup.  '$MNT/s' is a second mounted drive here, so the warning can
#   name the mount form to use instead
mkdir -p $MNT/s/tools/lcov/bin
SAVED_PATH=$PATH

PATH="S:/tools/lcov/bin:$PATH"
if run pathsplit 0 $GENHTML_TOOL --version ; then
    expect_log pathsplit "PATH entry 'S' is a single letter"
    expect_log pathsplit "'S:/tools/lcov/bin' was split"
    expect_log pathsplit "'$MNT/s/tools/lcov/bin' in PATH instead"
fi

# an unmounted drive, and a letter at the very end of the PATH with no
#   remainder to rejoin it to:  there is no mount form to suggest in either
#   case, so the warning says only what is wrong
PATH="Q:/tools/bin:$SAVED_PATH:R"
if run pathsplit_nomount 0 $GENHTML_TOOL --version ; then
    expect_log pathsplit_nomount "PATH entry 'Q' is a single letter"
    expect_log pathsplit_nomount "'Q:/tools/bin' was split"
    expect_log pathsplit_nomount "PATH entry 'R' is a single letter"
    expect_log pathsplit_nomount 'the name this perl understands'
fi

# and a PATH with nothing wrong with it is not complained about
PATH=$SAVED_PATH
if run pathsplit_none 0 $GENHTML_TOOL --version ; then
    reject_log pathsplit_none 'is a single letter'
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'winpath' $LOCAL_COVERAGE 1
fi

exit $STATUS
