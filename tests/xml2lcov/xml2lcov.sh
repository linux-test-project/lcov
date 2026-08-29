#!/bin/bash
set +x

if [[ "x" == ${LCOV_HOME}x ]] ; then
    if [ -f ../../bin/lcov ] ; then
        LCOV_HOME=../..
    fi
fi
source ../common.tst

rm -rf *.info *.json __pycache__ help.txt *.pyc *.dat malformed

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

# the source file the fixtures below refer to.  'nosuch.py' deliberately does
#  not exist, and 'short.py' is deliberately shorter than the line numbers the
#  data claims for it
printf 'a = 1\nb = 2\n' > malformed/a.py
printf 'x = 1\ny = 2\n' > malformed/short.py

# write_malformed <name> -- one .xml fixture, read from stdin
write_malformed()
{
    cat > malformed/$1.xml
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

    rm -f malformed/$tag.info malformed/$tag.O.info
    eval ${PYCOVER} ${XML2LCOV_TOOL} $* -o malformed/$tag.info \
        > malformed/$tag.log 2>&1
    local rc=$?
    eval PYTHONOPTIMIZE=1 ${PYCOVER} ${XML2LCOV_TOOL} $* \
        -o malformed/$tag.O.info > malformed/$tag.O.log 2>&1
    local orc=$?

    cat malformed/$tag.log
    if [ $rc != $expect ] ; then
        malformed_failed "$tag: expected exit status $expect, got $rc"
    elif [ $orc != $rc ] ; then
        malformed_failed "$tag: exit status $rc, but $orc with the asserts compiled out"
    elif grep -q Traceback malformed/$tag.log malformed/$tag.O.log ; then
        malformed_failed "$tag: reported by traceback rather than by message"
    elif ! diff malformed/$tag.log malformed/$tag.O.log ; then
        malformed_failed "$tag: compiling the asserts out changed what was reported"
    elif [ -f malformed/$tag.info -o -f malformed/$tag.O.info ] &&
         ! diff malformed/$tag.info malformed/$tag.O.info ; then
        malformed_failed "$tag: compiling the asserts out changed the data written"
    else
        return 0
    fi
    return 1
}

# malformed_expect <tag> <what> <pattern> -- the run had to have printed this
malformed_expect()
{
    if ! grep -q "$3" malformed/$1.log ; then
        malformed_failed "$1: $2"
    fi
}

# malformed_data <tag> <what> <pattern> -- the run had to have written this
malformed_data()
{
    if ! grep -q "$3" malformed/$1.info ; then
        cat malformed/$1.info
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
