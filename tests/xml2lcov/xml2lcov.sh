#!/bin/bash
set +x

if [[ "x" == ${LCOV_HOME}x ]] ; then
    if [ -f ../../bin/lcov ] ; then
        LCOV_HOME=../..
    fi
fi
source ../common.tst

rm -rf *.info *.json __pycache__ help.txt *.pyc *.dat malformed jacoco

clean_cover

if [[ 1 == $CLEAN_ONLY ]] ; then
    exit 0
fi


# is this git or P4?
if [ 1 == "$USE_GIT" ] ; then
    # this is git
    VERSION="--version-script ${SCRIPT_DIR}/gitversion.pm"
    ANNOTATE="--annotate-script ${SCRIPT_DIR}/gitblame.pm"
else
    VERSION="--version-script ${SCRIPT_DIR}/getp4version"
    ANNOTATE="--annotate-script ${SCRIPT_DIR}/p4annotate.pm"
fi

if [ $IS_GIT == 0 ] && [ $IS_P4 == 0 ] ; then
    VERSION="$VERSION --ignore usage"
fi

if [ ! -x $PY2LCOV_SCRIPT ] ; then
    echo "missing py2lcov script - dying"
    exit 1
fi


LCOV_OPTS="--branch-coverage $PARALLEL $PROFILE"


# NOTE:  the 'coverage.xml' file here is a copy of the one at
#   https://gist.github.com/apetro/fcfffb8c4cdab2c1061d
# except that I removed a huge number of packages - to reduce the
# disk space consumed by the testcase.  There appears to be nothing
# in the remove data that was significant from a test perspective.

# no source - so can't compute version
eval ${PYCOVER} ${XML2LCOV_TOOL} -o test.info coverage.xml -v -v # $VERSION
if [ 0 != $? ] ; then
    echo "xml2lcov failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# run with verbosity turned on...
eval ${PYCOVER} ${XML2LCOV_TOOL} --verbose --verbose -o test.info coverage.xml
if [ 0 != $? ] ; then
    echo "xml2lcov failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# version check should fail - because we have no source
eval ${PYCOVER} ${XML2LCOV_TOOL} -o noSource.info coverage.xml $VERSION
if [ 0 == $? ] ; then
    echo "xml2lcov missing source for version check "
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# generate help message:
eval ${PYCOVER} ${XML2LCOV_TOOL} --help 2>&1 | tee help.txt
if [ 0 != ${PIPESTATUS[0]} ] ; then
    echo "help failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi
grep 'usage: xml2lcov ' help.txt
if [ 0 != $? ] ; then
    echo "no help message"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# some usage errors
eval ${PYCOVER} ${XML2LCOV_TOOL} coverage.xml -o paramErr.info ${VERSION},-x
if [ 0 == $? ] ; then
    echo "coverage version did not see error"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

if [ 0 == 1 ] ; then
    # disable this one for now

    # run again with --keep-going flag - should generate same result as we see without version script
    eval ${PYCOVER} ${XML2LCOV_TOOL} coverage.xml -o keepGoing.info ${VERSION},-x --keep-going --verbose
    if [ 0 != $? ] ; then
        echo "keepGoing version saw error"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
    diff test.info keepGoing.info
    if [ 0 != $? ] ; then
        echo "no_version vs keepGoing failed"
        if [ 0 == $KEEP_GOING ] ; then
            exit 1
        fi
    fi
fi


# usage error:
eval ${PYCOVER} ${XML2LCOV_TOOL} -o missing.info
if [ 0 == $? ] ; then
    echo "did not see error with missing input data"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# usage error:
eval ${PYCOVER} ${XML2LCOV_TOOL} -o noFile.info y.xml
if [ 0 == $? ] ; then
    echo "did not see error with missing input file"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# usage error:
eval ${PYCOVER} ${XML2LCOV_TOOL} -o badArg.info --noSuchParam coverage.xml
if [ 0 == $? ] ; then
    echo "did not see error with unsupported param"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

# ===========================================================================
# Malformed and unexpected input
#
# The reader used to state its expectations about the XML it was handed with
# 'assert'.  Every one of those is a statement about the input rather than about
# the tool's own invariants:  the format is Cobertura, Coverage.py is only one of
# the tools which write it, and a report from another one is entitled to differ.
# An AssertionError names no input file, no element and no line, and cannot be
# waved through with --keep-going - and, because 'python -O' does not compile
# asserts in at all, it is not even the failure the user gets:  the run carries
# on past the thing which was being checked and either writes quietly wrong data
# or dies further down as something less obvious.  So every case below is run
# twice, once with the asserts compiled out, and the two runs have to agree.
#
# The two structural elements are looked up by name rather than by position for
# the same sort of reason:  the schema does not fix the order of 'sources' and
# 'packages', and a report which lists them the other way round was read as
# having no 'sources' at all.
# ===========================================================================

mkdir -p malformed

# where the fixtures of the section being run live, and where its output goes.
#  The JaCoCo section below reuses this same harness with its own directory
FIXTURE_DIR=malformed

# the source file the fixtures below refer to.  'nosuch.py' deliberately does
#  not exist, and 'short.py' is deliberately shorter than the line numbers the
#  data claims for it
printf 'a = 1\nb = 2\n' > malformed/a.py
printf 'x = 1\ny = 2\n' > malformed/short.py

# write_malformed <name> -- one .xml fixture, read from stdin
write_malformed()
{
    cat > $FIXTURE_DIR/$1.xml
}

# no 'sources' element at all:  there is then no search path, which is the same
#  situation as a report whose only sources are the empty ones the reader
#  already skips - so it is not a reason to stop when --keep-going is given
write_malformed nosources << 'EOF'
<?xml version="1.0" ?>
<coverage version="1.9">
  <packages>
    <package name=".">
      <classes>
        <class filename="a.py" name="a.py">
          <methods/>
          <lines>
            <line hits="1" number="1"/>
            <line hits="0" number="2"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
EOF

# 'packages' before 'sources'
write_malformed reversed << 'EOF'
<?xml version="1.0" ?>
<coverage version="1.9">
  <packages>
    <package name=".">
      <classes>
        <class filename="a.py" name="a.py">
          <methods/>
          <lines>
            <line hits="1" number="1"/>
            <line hits="0" number="2"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
  <sources>
    <source>malformed</source>
  </sources>
</coverage>
EOF

# no 'packages' element:  there is no coverage data to translate
write_malformed nopackages << 'EOF'
<?xml version="1.0" ?>
<coverage version="1.9">
  <sources>
    <source>malformed</source>
  </sources>
</coverage>
EOF

# a 'method' whose child is not the expected 'lines'
write_malformed methodchild << 'EOF'
<?xml version="1.0" ?>
<coverage version="1.9">
  <sources>
    <source>malformed</source>
  </sources>
  <packages>
    <package name=".">
      <classes>
        <class filename="a.py" name="a.py">
          <methods>
            <method name="oddball" signature="()V">
              <conditions/>
            </method>
          </methods>
          <lines>
            <line hits="1" number="1"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
EOF

# a method whose line elements are not in increasing line order
write_malformed methodorder << 'EOF'
<?xml version="1.0" ?>
<coverage version="1.9">
  <sources>
    <source>malformed</source>
  </sources>
  <packages>
    <package name=".">
      <classes>
        <class filename="a.py" name="a.py">
          <methods>
            <method name="backwards" signature="()V">
              <lines>
                <line hits="1" number="5"/>
                <line hits="1" number="3"/>
              </lines>
            </method>
          </methods>
          <lines>
            <line hits="1" number="3"/>
            <line hits="1" number="5"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
EOF

# a branch with no 'condition-coverage' attribute, and one whose attribute
#  cannot be read - in a method and in the file's own line list
write_malformed nocondition << 'EOF'
<?xml version="1.0" ?>
<coverage version="1.9">
  <sources>
    <source>malformed</source>
  </sources>
  <packages>
    <package name=".">
      <classes>
        <class filename="a.py" name="a.py">
          <methods>
            <method name="nocond" signature="()V">
              <lines>
                <line hits="1" number="1" branch="true"/>
              </lines>
            </method>
          </methods>
          <lines>
            <line hits="1" number="1" branch="true"/>
            <line hits="1" number="2" branch="true" condition-coverage="not a percentage"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
EOF

# data for a file which cannot be read
write_malformed nosuchsource << 'EOF'
<?xml version="1.0" ?>
<coverage version="1.9">
  <sources>
    <source>malformed</source>
  </sources>
  <packages>
    <package name=".">
      <classes>
        <class filename="nosuch.py" name="nosuch.py">
          <methods/>
          <lines>
            <line hits="1" number="1"/>
            <line hits="0" number="2"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
EOF

# a line number past the end of the file the data names
write_malformed shortsource << 'EOF'
<?xml version="1.0" ?>
<coverage version="1.9">
  <sources>
    <source>malformed</source>
  </sources>
  <packages>
    <package name=".">
      <classes>
        <class filename="short.py" name="short.py">
          <methods/>
          <lines>
            <line hits="1" number="1"/>
            <line hits="1" number="100"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
EOF

MALFORMED_RC=0

# malformed_failed <what> -- one of the expectations below did not hold
malformed_failed()
{
    echo "malformed input: $1"
    MALFORMED_RC=1
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
}

# malformed_run <tag> <expected exit status> <arg>... -- run one fixture twice
#   'PYTHONOPTIMIZE=1' is what 'python -O' sets, so the second run is the one
#   with the asserts compiled out:  it has to reach the same exit status, print
#   the same thing and write the same data as the first
malformed_run()
{
    local tag=$1 ; shift
    local expect=$1 ; shift

    rm -f $FIXTURE_DIR/$tag.info $FIXTURE_DIR/$tag.O.info
    eval ${PYCOVER} ${XML2LCOV_TOOL} $* -o $FIXTURE_DIR/$tag.info \
        > $FIXTURE_DIR/$tag.log 2>&1
    local rc=$?
    eval PYTHONOPTIMIZE=1 ${PYCOVER} ${XML2LCOV_TOOL} $* \
        -o $FIXTURE_DIR/$tag.O.info > $FIXTURE_DIR/$tag.O.log 2>&1
    local orc=$?

    cat $FIXTURE_DIR/$tag.log
    if [ $rc != $expect ] ; then
        malformed_failed "$tag: expected exit status $expect, got $rc"
    elif [ $orc != $rc ] ; then
        malformed_failed "$tag: exit status $rc, but $orc with the asserts compiled out"
    elif grep -q Traceback $FIXTURE_DIR/$tag.log $FIXTURE_DIR/$tag.O.log ; then
        malformed_failed "$tag: reported by traceback rather than by message"
    elif ! diff $FIXTURE_DIR/$tag.log $FIXTURE_DIR/$tag.O.log ; then
        malformed_failed "$tag: compiling the asserts out changed what was reported"
    elif [ -f $FIXTURE_DIR/$tag.info -o -f $FIXTURE_DIR/$tag.O.info ] &&
         ! diff $FIXTURE_DIR/$tag.info $FIXTURE_DIR/$tag.O.info ; then
        malformed_failed "$tag: compiling the asserts out changed the data written"
    else
        return 0
    fi
    return 1
}

# malformed_expect <tag> <what> <pattern> -- the run had to have printed this
malformed_expect()
{
    if ! grep -q "$3" $FIXTURE_DIR/$1.log ; then
        malformed_failed "$1: $2"
    fi
}

# malformed_absent <tag> <what> <pattern> -- the run must not have printed this
malformed_absent()
{
    if grep -q "$3" $FIXTURE_DIR/$1.log ; then
        malformed_failed "$1: $2"
    fi
}

# malformed_data <tag> <what> <pattern> -- the run had to have written this
malformed_data()
{
    if ! grep -q "$3" $FIXTURE_DIR/$1.info ; then
        cat $FIXTURE_DIR/$1.info
        malformed_failed "$1: $2"
    fi
}

# malformed_no_data <tag> <what> <pattern> -- and this it must not have written
malformed_no_data()
{
    if grep -q "$3" $FIXTURE_DIR/$1.info ; then
        cat $FIXTURE_DIR/$1.info
        malformed_failed "$1: $2"
    fi
}

# a missing 'sources' is an error, and one which --keep-going can wave through:
#  what is left is a report whose filenames are used exactly as they stand
malformed_run nosources 1 malformed/nosources.xml
malformed_expect nosources "did not say which element was missing" \
    "no 'sources' in malformed/nosources.xml"
if malformed_run nosources_k 0 malformed/nosources.xml --keep-going ; then
    malformed_data nosources_k "did not translate the data it kept going with" \
        '^SF:a.py$'
    malformed_data nosources_k 'lost the line data' '^DA:1,1$'
fi

# 'sources' after 'packages' is not an error at all:  finding the element by
#  name rather than at position 0 is what makes the search path usable here
if malformed_run reversed 0 malformed/reversed.xml ; then
    malformed_data reversed "did not search the 'sources' path" \
        '^SF:malformed/a.py$'
    if grep -q Error malformed/reversed.log ; then
        malformed_failed "reversed: the element order was reported as an error"
    fi
fi

# no 'packages' means there is nothing to translate
malformed_run nopackages 1 malformed/nopackages.xml
malformed_expect nopackages "did not say which element was missing" \
    "no 'packages' in malformed/nopackages.xml"
malformed_run nopackages_k 0 malformed/nopackages.xml --keep-going

# the diagnostics for a malformed element name the input, the element and the
#  line, which is what an AssertionError could not do
malformed_run methodchild 1 malformed/methodchild.xml
malformed_expect methodchild "did not name the element it did not expect" \
    "method 'oddball': expected a 'lines' element, found 'conditions'"
malformed_run methodchild_k 0 malformed/methodchild.xml --keep-going

# out of order line elements:  the larger line number is kept, so the function
#  still ends at its last line rather than before its first one
malformed_run methodorder 1 malformed/methodorder.xml
malformed_expect methodorder "did not name the lines which are out of order" \
    "method 'backwards': line 3 is not after line 5"
if malformed_run methodorder_k 0 malformed/methodorder.xml --keep-going ; then
    malformed_data methodorder_k 'the function ends before it starts' \
        '^FNL:0,5,5$'
fi

# an unreadable 'condition-coverage', in a method and in the line list
malformed_run nocondition 1 malformed/nocondition.xml
if malformed_run nocondition_k 0 malformed/nocondition.xml --keep-going ; then
    malformed_expect nocondition_k "did not report the method's branch" \
        "method 'nocond' line 1: branch has no 'condition-coverage'"
    malformed_expect nocondition_k 'did not report the missing attribute' \
        "line 1: branch has no 'condition-coverage'"
    malformed_expect nocondition_k 'did not report the unreadable attribute' \
        "line 2: unable to parse condition-coverage 'not a percentage'"
fi

# --checksum against a file which cannot be read:  under --keep-going there is
#  no source to hash, and the rest of the data is still worth writing
malformed_run nosuchsource 1 --checksum malformed/nosuchsource.xml
if malformed_run nosuchsource_k 0 --checksum malformed/nosuchsource.xml \
       --keep-going ; then
    malformed_expect nosuchsource_k 'did not name the file it could not read' \
        'cannot open nosuch.py - unable to compute line checksum'
    malformed_data nosuchsource_k 'did not write the data it could still write' \
        '^DA:1,1$'
fi

# --checksum against a line the file does not have
malformed_run shortsource 1 --checksum malformed/shortsource.xml
malformed_expect shortsource 'did not name the line it could not hash' \
    '"malformed/short.py":100: unable to compute checksum for missing line'
if malformed_run shortsource_k 0 --checksum malformed/shortsource.xml \
       --keep-going ; then
    malformed_data shortsource_k 'did not write the line with no checksum' \
        '^DA:100,1$'
fi

if [ 0 != $MALFORMED_RC ] ; then
    echo "malformed input tests failed"
    exit 1
fi

# ===========================================================================
# JaCoCo XML
#
# The second input schema.  The interesting part of the translation is what the
# JaCoCo schema does not say and the LCOV format needs:
#
#   - where the source files are.  Cobertura data carries its own search path in
#     the 'sources' element and JaCoCo data has no equivalent, so
#     '--source-directory' is the whole of it, and a file which is not found
#     there is dropped rather than reported under a name which resolves to
#     nothing
#
#   - how many times a line was executed.  JaCoCo counts instructions and
#     branches, so the count is derived, and the one thing it must not do is
#     call a line JaCoCo considers covered a count of 0
#
#   - where a method ends.  A 'method' element says which line it starts on and
#     nothing more, so the extent is derived by letting each method claim lines
#     from its file's line list until its own LINE counter is used up.  The
#     cases which make that interesting are all in Widget.java below:  a lambda
#     which begins on a line of the method containing it, and a static
#     initializer whose lines are not contiguous
#
# The whole Widget.java record is compared against the expected text, because
# the derivations above are only correct together:  checking the FNL: extents
# without checking the DA: counts they were derived from would let a wrong line
# list produce right-looking extents.
# ===========================================================================

mkdir -p jacoco

FIXTURE_DIR=jacoco

# write_source <path> <lines> -- a source file stand-in of the given length.
#  xml2lcov reads a source only to hash it or to extract its version, so this
#  does not have to be Java which compiles - only long enough for the line
#  numbers the coverage data claims
write_source()
{
    mkdir -p `dirname $1`
    local i=1
    while [ $i -le $2 ] ; do
        echo "// line $i"
        i=`expr $i + 1`
    done > $1
}

# the search path is what a JaCoCo report does not name:  the name of a source
#  file is its package name used as a directory path, plus the 'sourcefile'
#  name.  'Missing.java' deliberately does not exist
write_source jacoco/src/com/example/Widget.java 30
write_source jacoco/src/com/example/Helper.java 10
write_source jacoco/src/com/example/util/Util.java 6

# the data below describes this much of Widget.java:
#
#     5   the constructor - one covered line, no branches
#    10   'run' starts here, and so does the lambda it creates.  One of the two
#         branches on the line was taken
#    11   part of both 'run' and the lambda, not covered
#    12   part of 'run', and where the static initializer starts
#    20   'dead', never entered
#    25   the last line of the static initializer, which is therefore not
#         contiguous with line 12
#
# The methods are deliberately listed in an order which is not the order they
# have to be reported in.
write_malformed nominal << 'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!DOCTYPE report PUBLIC "-//JACOCO//DTD Report 1.1//EN" "report.dtd">
<report name="nominal">
  <sessioninfo id="somehost-12345678" start="1700000000000" dump="1700000001000"/>
  <package name="com/example">
    <class name="com/example/Widget" sourcefilename="Widget.java">
      <method name="dead" desc="()V" line="20">
        <counter type="LINE" missed="1" covered="0"/>
        <counter type="COMPLEXITY" missed="1" covered="0"/>
        <counter type="METHOD" missed="1" covered="0"/>
      </method>
      <method name="run" desc="()V" line="10">
        <counter type="INSTRUCTION" missed="4" covered="9"/>
        <counter type="BRANCH" missed="1" covered="1"/>
        <counter type="LINE" missed="1" covered="2"/>
        <counter type="COMPLEXITY" missed="1" covered="1"/>
        <counter type="METHOD" missed="0" covered="1"/>
      </method>
      <method name="&lt;clinit&gt;" desc="()V" line="12">
        <counter type="LINE" missed="0" covered="2"/>
        <counter type="COMPLEXITY" missed="0" covered="1"/>
      </method>
      <method name="&lt;init&gt;" desc="()V" line="5">
        <counter type="INSTRUCTION" missed="0" covered="3"/>
        <counter type="LINE" missed="0" covered="1"/>
        <counter type="COMPLEXITY" missed="0" covered="1"/>
      </method>
      <method name="lambda$run$0" desc="(I)V" line="10">
        <counter type="LINE" missed="1" covered="1"/>
        <counter type="COMPLEXITY" missed="0" covered="1"/>
      </method>
    </class>
    <class name="com/example/Helper" sourcefilename="Helper.java">
      <method name="help" desc="()V" line="3">
        <counter type="LINE" missed="0" covered="2"/>
        <counter type="COMPLEXITY" missed="0" covered="1"/>
      </method>
      <method name="noDebug" desc="()V">
        <counter type="LINE" missed="0" covered="1"/>
        <counter type="COMPLEXITY" missed="0" covered="1"/>
      </method>
      <method name="alsoNoDebug" desc="()V" line="0">
        <counter type="LINE" missed="1" covered="0"/>
        <counter type="COMPLEXITY" missed="1" covered="0"/>
      </method>
    </class>
    <class name="com/example/Stripped">
      <method name="gone" desc="()V" line="1">
        <counter type="LINE" missed="0" covered="1"/>
        <counter type="COMPLEXITY" missed="0" covered="1"/>
      </method>
    </class>
    <class name="com/example/Missing" sourcefilename="Missing.java">
      <method name="nowhere" desc="()V" line="1">
        <counter type="LINE" missed="1" covered="0"/>
        <counter type="COMPLEXITY" missed="1" covered="0"/>
      </method>
    </class>
    <sourcefile name="Widget.java">
      <line nr="5" mi="0" ci="3" mb="0" cb="0"/>
      <line nr="10" mi="0" ci="6" mb="1" cb="1"/>
      <line nr="11" mi="4" ci="0" mb="0" cb="0"/>
      <line nr="12" mi="0" ci="3" mb="0" cb="0"/>
      <line nr="20" mi="2" ci="0" mb="0" cb="0"/>
      <line nr="25" mi="0" ci="2" mb="0" cb="0"/>
    </sourcefile>
    <sourcefile name="Helper.java">
      <line nr="8" mi="0" ci="2" mb="0" cb="0"/>
      <line nr="3" mi="0" ci="4" mb="0" cb="0"/>
    </sourcefile>
    <sourcefile name="Missing.java">
      <line nr="1" mi="1" ci="0" mb="0" cb="0"/>
    </sourcefile>
  </package>
  <group name="modules">
    <package name="com/example/util">
      <class name="com/example/util/Util" sourcefilename="Util.java">
        <method name="id" desc="(I)I" line="4">
          <counter type="LINE" missed="0" covered="1"/>
          <counter type="COMPLEXITY" missed="0" covered="1"/>
        </method>
      </class>
      <sourcefile name="Util.java">
        <line nr="4" mi="0" ci="2" mb="0" cb="0"/>
      </sourcefile>
    </package>
  </group>
</report>
EOF

# the whole expected record of Widget.java.  Read it together with the data
#  above:  every number here is derived from something the JaCoCo schema does
#  not state directly
cat > jacoco/Widget.expected << 'EOF'
SF:jacoco/src/com/example/Widget.java
BRDA:10,0,0,1
BRDA:10,0,1,0
FNL:0,5,5
FNA:0,1,com.example.Widget.<init>()V
FNL:1,10,12
FNA:1,1,com.example.Widget.lambda$run$0(I)V
FNL:2,10,12
FNA:2,1,com.example.Widget.run()V
FNL:3,12,25
FNA:3,1,com.example.Widget.<clinit>()V
FNL:4,20,20
FNA:4,0,com.example.Widget.dead()V
DA:5,1
DA:10,1
DA:11,0
DA:12,1
DA:20,0
DA:25,1
LF:6
LH:4
BRF:2
BRH:1
FNF:5
FNH:4
end_of_record
EOF

# a root element which is neither schema
write_malformed badroot << 'EOF'
<?xml version="1.0" ?>
<results version="1.0">
  <package name="com/example"/>
</results>
EOF

MALFORMED_RC=0

# the nominal translation.  Note that the dropped data does not make this a
#  failure:  a report which mentions a file this checkout does not have is
#  ordinary, and the counts printed at the end are how the user finds out
if malformed_run nominal 0 -s jacoco/src jacoco/nominal.xml ; then
    awk '/^SF:/ { keep = ($0 == "SF:jacoco/src/com/example/Widget.java") }
         keep { print }' jacoco/nominal.info > jacoco/Widget.actual
    if ! diff jacoco/Widget.expected jacoco/Widget.actual ; then
        malformed_failed "nominal: Widget.java was not translated as expected"
    fi

    # a 'sourcefile' whose 'line' elements are not in line order:  the schema
    #  does not say that they are, and the extent of 'help' depends on it
    malformed_data nominal 'did not sort the line data' '^DA:3,1$'
    malformed_data nominal 'the function does not span its sorted lines' \
        '^FNL:0,3,8$'

    # a 'package' nested in a 'group' element is still a package
    malformed_data nominal 'did not descend into the group element' \
        '^SF:jacoco/src/com/example/util/Util.java$'

    # a file which is not in the search path is dropped:  data keyed by a name
    #  which resolves to nothing is of no use to anybody
    malformed_expect nominal 'did not name the file it could not find' \
        'did not find com/example/Missing.java in search path'
    malformed_no_data nominal 'reported a file it never found' 'Missing.java'
    malformed_expect nominal 'did not count the file it dropped' \
        'Warning: 1 source file(s) not found in the search path'

    # a class compiled without debug information says neither which file it came
    #  from nor which lines its methods are on
    malformed_expect nominal 'did not count the class which names no source' \
        'Warning: 1 class(es) which name no source file'
    malformed_expect nominal 'did not count the methods with no line number' \
        'Warning: 2 method(s) whose line number is unknown'
    malformed_no_data nominal 'reported a method with no line number' 'noDebug'

    # and the search path which was used is not reported as unused
    malformed_absent nominal 'called the search path it used unused' \
        "source directory 'jacoco/src' is unused"
fi

# an unused --source-directory is worth saying, because the usual reason for one
#  is a path which does not mean what the caller thought it did
if malformed_run unused 0 -s jacoco/src -s jacoco/nosuchdir \
       jacoco/nominal.xml ; then
    malformed_expect unused 'did not report the unused search path' \
        "source directory 'jacoco/nosuchdir' is unused"
fi

# no --source-directory at all is not an error - there is simply nothing to
#  resolve the names against, so they are left as they stand and nothing is
#  dropped for being unresolvable
if malformed_run nosearchpath 0 jacoco/nominal.xml ; then
    malformed_expect nosearchpath 'did not say the names are left relative' \
        'no --source-directory'
    malformed_data nosearchpath 'did not keep the relative name' \
        '^SF:com/example/Widget.java$'
    malformed_data nosearchpath 'dropped a file it was not asked to find' \
        '^SF:com/example/Missing.java$'
    malformed_absent nosearchpath 'searched a path it did not have' \
        'did not find'
fi

# --exclude matches the name relative to the package directory, which is the
#  only name there is before the search path is applied
if malformed_run excluded 0 -s jacoco/src --exclude '*/Helper.java' \
       jacoco/nominal.xml ; then
    malformed_no_data excluded 'translated the file it was told to exclude' \
        'Helper.java'
    malformed_data excluded 'excluded more than it was asked to' \
        '^SF:jacoco/src/com/example/Widget.java$'
fi

# --checksum needs the source, which is the other thing the search path is for
if malformed_run checksum 0 --checksum -s jacoco/src jacoco/nominal.xml ; then
    malformed_data checksum 'did not append the line checksum' '^DA:5,1,.'
fi

# --checksum against a source which resolves but cannot be read, and against a
#  line the source does not have.  'Unreadable.java' is a directory:  it is what
#  the search path finds, and not something open() can read - which is the same
#  situation as a file whose permissions do not allow it, without depending on
#  the permissions of whoever is running the test
#  The two are separate fixtures so that each of them is the reason the run
#  without --keep-going stops
mkdir -p jacoco/src/com/example/Unreadable.java
write_malformed checksumopen << 'EOF'
<?xml version="1.0" ?>
<report name="checksumopen">
  <package name="com/example">
    <sourcefile name="Unreadable.java">
      <line nr="1" mi="0" ci="2" mb="0" cb="0"/>
    </sourcefile>
  </package>
</report>
EOF

write_malformed checksumline << 'EOF'
<?xml version="1.0" ?>
<report name="checksumline">
  <package name="com/example">
    <sourcefile name="Widget.java">
      <line nr="999" mi="0" ci="2" mb="0" cb="0"/>
    </sourcefile>
  </package>
</report>
EOF

malformed_run checksumopen 1 --checksum -s jacoco/src jacoco/checksumopen.xml
malformed_expect checksumopen 'did not name the source it could not read' \
    'cannot open jacoco/src/com/example/Unreadable.java'
if malformed_run checksumopen_k 0 --checksum -s jacoco/src \
       jacoco/checksumopen.xml --keep-going ; then
    # the coverage data is still worth writing, without the checksums which
    #  could not be computed
    malformed_data checksumopen_k 'dropped the file it could not read' \
        '^DA:1,1$'
fi

malformed_run checksumline 1 --checksum -s jacoco/src jacoco/checksumline.xml
malformed_expect checksumline 'did not name the line it could not hash' \
    '"jacoco/src/com/example/Widget.java":999: unable to compute checksum for missing line'
if malformed_run checksumline_k 0 --checksum -s jacoco/src \
       jacoco/checksumline.xml --keep-going ; then
    malformed_data checksumline_k 'dropped the line it could not hash' \
        '^DA:999,1$'
fi

# the verbose trace, which says what was read and what was passed over.  Run
#  with --exclude as well, because the excluded file is one of the things the
#  trace has to account for
if malformed_run verbose 0 -v -v -s jacoco/src --exclude '*/Helper.java' \
       jacoco/nominal.xml ; then
    malformed_expect verbose 'did not name the package' "package: 'com/example'"
    malformed_expect verbose 'did not name the file it translated' \
        'file: jacoco/src/com/example/Widget.java'
    malformed_expect verbose 'did not say why the file was skipped' \
        'com/example/Helper.java is excluded'
    malformed_expect verbose 'did not name the class which names no source' \
        "class 'com.example.Stripped' names no source file"
    malformed_expect verbose 'did not name the method with no line number' \
        "method 'com.example.Helper.noDebug()V' has no line number"
fi

# a version script which succeeds:  what it printed becomes the VER: record.
#  'echo' stands in for a real version script - it prints the name it is handed,
#  which is enough to show that the record is what the script said
if malformed_run version 0 --version-script echo -s jacoco/src \
       jacoco/nominal.xml ; then
    malformed_data version 'did not record what the version script printed' \
        '^VER:jacoco/src/com/example/Widget.java$'
fi

# a version script which is a perl module rather than something which can be
#  run:  that one cannot be called per file from here, so the VER: records are
#  added by a pass of the 'lcov' beside this script over the finished file.
#  What that pass must not do is throw away the function data which is already
#  in the file - the option which asks for that is py2lcov's '--no-functions',
#  and xml2lcov has function coverage from its input and no such option
cat > jacoco/fixedversion.pm << 'EOF'
package fixedversion;

use strict;
use warnings;

sub new
{
    my $class = shift;
    return bless({}, $class);
}

sub extract_version
{
    return 'V1.0';    # the same for every file:  nothing here reads the source
}

sub compare_version
{
    my ($self, $new, $old) = @_;
    return $new ne $old;
}

1;
EOF

#  The counts are not compared against the 'nominal' record above:  that pass
#  merges the two functions which share a line range into one set of aliases,
#  which is lcov's own reading of the data and not something this case is about.
#  What it is about is that the function records are still there at all
if malformed_run versionmodule 0 --version-script jacoco/fixedversion.pm \
       -s jacoco/src jacoco/nominal.xml ; then
    malformed_data versionmodule 'did not record the version the module returned' \
        '^VER:V1.0$'
    malformed_data versionmodule 'dropped the function which was called' \
        'com.example.Widget.run()V'
    malformed_data versionmodule 'dropped the function which was not called' \
        ',0,com.example.Widget.dead()V$'
    malformed_data versionmodule 'dropped the function summary' '^FNF:[1-9]'
    malformed_data versionmodule 'dropped the function hit count' '^FNH:[1-9]'
    #  and the rest of the translation is still there
    malformed_data versionmodule 'dropped the branch data' '^BRDA:10,0,0,1$'
    malformed_data versionmodule 'dropped the line data' '^DA:5,1$'
fi

# an input file which is not there, or is not XML at all.  Under --keep-going the
#  run carries on to the next input file rather than stopping at the first one
printf 'this is not XML\n' > jacoco/notxml.xml
malformed_run unreadable 1 -s jacoco/src jacoco/nosuchfile.xml
malformed_expect unreadable 'did not name the file it could not read' \
    'unable to read "jacoco/nosuchfile.xml"'
if malformed_run unreadable_k 0 -s jacoco/src jacoco/nosuchfile.xml \
       jacoco/notxml.xml jacoco/nominal.xml --keep-going ; then
    malformed_expect unreadable_k 'did not report the file which is not XML' \
        'unable to read "jacoco/notxml.xml"'
    malformed_data unreadable_k 'did not carry on to the next input file' \
        '^SF:jacoco/src/com/example/Widget.java$'
fi

# --format forces the reader, and says so if the root element is not the one
#  that reader expects - because the answer is then likely to be no data at all
malformed_run mismatch 1 --format cobertura -s jacoco/src jacoco/nominal.xml
malformed_expect mismatch 'did not report the unexpected root element' \
    "expects a 'coverage' root element: found 'report'"
malformed_expect mismatch 'did not fail in the reader it was told to use' \
    "no 'packages' in jacoco/nominal.xml"

# a root element which is neither schema cannot be guessed at
malformed_run badroot 1 -s jacoco/src jacoco/badroot.xml
malformed_expect badroot 'did not name the root element it did not expect' \
    "unexpected XML root element 'results'"
malformed_expect badroot 'did not say how to resolve it' \
    'Use --format to say which it is'
malformed_run badroot_k 0 -s jacoco/src jacoco/badroot.xml --keep-going

# and --format is how:  the JaCoCo reader then finds no package elements in it,
#  which is no data rather than an error
if malformed_run forced 0 --format jacoco -s jacoco/src \
       jacoco/badroot.xml ; then
    malformed_expect forced 'did not report the unexpected root element' \
        "expects a 'report' root element: found 'results'"
fi

# ---------------------------------------------------------------------------
# Malformed JaCoCo input.  As above, the diagnostic has to name the input, the
# element and the line, and --keep-going has to be able to wave it through
# ---------------------------------------------------------------------------

# a 'sourcefile' with no name:  there is nothing to attach its lines to, and
#  nothing for a 'class' to refer to it by
write_malformed nosfname << 'EOF'
<?xml version="1.0" ?>
<report name="nosfname">
  <package name="com/example">
    <sourcefile>
      <line nr="5" mi="0" ci="3" mb="0" cb="0"/>
    </sourcefile>
    <sourcefile name="Widget.java">
      <line nr="5" mi="0" ci="3" mb="0" cb="0"/>
    </sourcefile>
  </package>
</report>
EOF

# 'line' elements which cannot be used:  no 'nr' attribute, an 'nr' which is not
#  a line number, the same 'nr' twice, and an unreadable count
write_malformed badlines << 'EOF'
<?xml version="1.0" ?>
<report name="badlines">
  <package name="com/example">
    <sourcefile name="Widget.java">
      <line mi="0" ci="3" mb="0" cb="0"/>
      <line nr="0" mi="0" ci="3" mb="0" cb="0"/>
      <line nr="5" mi="0" ci="3" mb="0" cb="0"/>
      <line nr="5" mi="0" ci="9" mb="0" cb="0"/>
      <line nr="10" mi="0" ci="oops" mb="0" cb="0"/>
    </sourcefile>
  </package>
</report>
EOF

# a class which names a 'sourcefile' the package does not have
write_malformed nosuchsf << 'EOF'
<?xml version="1.0" ?>
<report name="nosuchsf">
  <package name="com/example">
    <class name="com/example/Ghost" sourcefilename="Ghost.java">
      <method name="boo" desc="()V" line="1">
        <counter type="LINE" missed="0" covered="1"/>
        <counter type="COMPLEXITY" missed="0" covered="1"/>
      </method>
    </class>
    <sourcefile name="Widget.java">
      <line nr="5" mi="0" ci="3" mb="0" cb="0"/>
    </sourcefile>
  </package>
</report>
EOF

# a method whose 'line' is not a number, and one whose LINE counter cannot be
#  read.  The second one also has no COMPLEXITY counter, which is not an error:
#  a counter the element does not have is zero
write_malformed badmethod << 'EOF'
<?xml version="1.0" ?>
<report name="badmethod">
  <package name="com/example">
    <class name="com/example/Widget" sourcefilename="Widget.java">
      <method name="unreadable" desc="()V" line="five">
        <counter type="LINE" missed="0" covered="1"/>
        <counter type="COMPLEXITY" missed="0" covered="1"/>
      </method>
      <method name="bad" desc="()V" line="5">
        <counter type="LINE" missed="lots" covered="1"/>
      </method>
    </class>
    <sourcefile name="Widget.java">
      <line nr="5" mi="0" ci="3" mb="0" cb="0"/>
    </sourcefile>
  </package>
</report>
EOF

malformed_run nosfname 1 -s jacoco/src jacoco/nosfname.xml
malformed_expect nosfname 'did not name the package it was reading' \
    "package 'com/example': 'sourcefile' with no 'name' attribute"
if malformed_run nosfname_k 0 -s jacoco/src jacoco/nosfname.xml \
       --keep-going ; then
    malformed_data nosfname_k 'did not translate the file it could read' \
        '^SF:jacoco/src/com/example/Widget.java$'
fi

malformed_run badlines 1 -s jacoco/src jacoco/badlines.xml
malformed_expect badlines 'did not report the missing attribute' \
    "com/example/Widget.java: 'line' with no readable 'nr' attribute"
if malformed_run badlines_k 0 -s jacoco/src jacoco/badlines.xml \
       --keep-going ; then
    malformed_expect badlines_k 'did not report the out of range line number' \
        "com/example/Widget.java: 'line' with out of range 'nr' attribute 0"
    malformed_expect badlines_k 'did not report the repeated line number' \
        'com/example/Widget.java: line 5 appears more than once'
    malformed_expect badlines_k 'did not report the unreadable count' \
        "com/example/Widget.java: line 10: unable to read 'ci' attribute 'oops'"
    # the first of the two line 5 elements is the one which is kept, and the
    #  line whose instruction count could not be read is not called covered
    malformed_data badlines_k 'kept the wrong copy of the repeated line' \
        '^DA:5,1$'
    malformed_data badlines_k 'guessed at the unreadable count' '^DA:10,0$'
fi

malformed_run nosuchsf 1 -s jacoco/src jacoco/nosuchsf.xml
malformed_expect nosuchsf 'did not name the class and the file it wanted' \
    "class 'com.example.Ghost': package 'com/example' has no 'sourcefile' element for 'Ghost.java'"
malformed_run nosuchsf_k 0 -s jacoco/src jacoco/nosuchsf.xml --keep-going

malformed_run badmethod 1 -s jacoco/src jacoco/badmethod.xml
malformed_expect badmethod 'did not name the method and its line number' \
    "method 'com.example.Widget.unreadable()V': unable to read line number 'five'"
if malformed_run badmethod_k 0 -s jacoco/src jacoco/badmethod.xml \
       --keep-going ; then
    malformed_expect badmethod_k 'did not name the counter it could not read' \
        "method 'com.example.Widget.bad()V': unable to read its LINE counter"
    # a method with no readable extent still starts where it says it does, and
    #  the COMPLEXITY counter it does not have makes it not hit
    malformed_data badmethod_k 'did not report the method it could still report' \
        '^FNL:0,5,5$'
    malformed_data badmethod_k 'invented a hit count' \
        '^FNA:0,0,com.example.Widget.bad()V$'
fi

if [ 0 != $MALFORMED_RC ] ; then
    echo "jacoco input tests failed"
    exit 1
fi

# aggregate the files - as a syntax check
#  the file contains inconsistent data for 'org/jasig/portal/EntityTypes.java'
#  function 'mapRow' is declared twice at different locations and
#  overlaps with a previous decl
$COVER $LCOV_TOOL $LCOV_OPTS -o aggregate.info -a test.info --ignore inconsistent
if [ 0 != $? ] ; then
    echo "lcov aggregate failed"
    if [ 0 == $KEEP_GOING ] ; then
        exit 1
    fi
fi

if [[ "x$COVER" != "x" && $LOCAL_COVERAGE == 1 ]] ; then
    cover
    ${PY2LCOV_TOOL} -o pycov.info --testname xml2lcov $VERSION ${PYCOV_DB}
    ${GENHTML_TOOL} -o pycov pycov.info --flat --show-navigation --show-proportion --branch $VERSION $ANNOTATE --ignore inconsistent,version,annotate
fi

echo "Tests passed"
