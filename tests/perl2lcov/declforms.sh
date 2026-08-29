#!/bin/bash
set +x

# ============================================================================
# perl2lcov's view of the source file behind a Devel::Cover database.
#
# Devel::Cover says where each subroutine starts, but not where it ends, so
#   perl2lcov reads the source and looks for the 'package' and 'sub'
#   declarations itself:  a subroutine ends at the last executable line before
#   the next declaration.  That scan used to be a forked 'grep' for
#   '^\s*(package|sub) ' whose output was then matched against two narrower
#   patterns - 'package NAME;' and 'sub NAME' - and any line grep had produced
#   which neither pattern matched was a fatal "unexpected grep output".  Perl
#   has more ways to open a package than that:  'package NAME { ... }' and
#   'package NAME VERSION;' are both ordinary declarations, and either one
#   killed perl2lcov outright.  The scan is now done in this process, and the
#   patterns which recognise a declaration are the only ones there are.
#
#   The scan is still a scan and not a parse, but the text in a file which is
#   not code - a heredoc body, POD, everything after '__END__' - is skipped now.
#   Reading a 'package' out of one of those does not just misplace an extent:
#   every subroutine below it is reported under that package's name.
#
# The other half of this test is which file perl2lcov looks at.  A Devel::Cover
#   database is keyed by the path perl was given, and that is the name every
#   lookup into the database has to use - but it is not necessarily the name the
#   file is reported under:  '--substitute' and '--source-directory' both say
#   otherwise.  Everything about the file as reported - its version, its
#   checksum, and the declaration scan above - used to be taken from the
#   database key instead.
#
# Cases:
#   1. a package block and a versioned package are declarations, not errors
#   2. the extents the scan produces bound each subroutine at the following
#      declaration
#   3. '--substitute': the version callback is asked about the file the 'SF:'
#      record names
#   4. '--substitute' to a name which is not on disk: the '--checksum'
#      complaint names that file
#   5. a source file which cannot be read is a 'source' error, not a silent
#      absence of extents
#   6. a heredoc body is text:  a 'package' or 'sub' in one is not a declaration
#   7. POD is text too, including an '__END__' inside it
#   8. '<<TAG' in a string is not a heredoc introducer unless the terminator is
#      really there, so it cannot swallow the rest of the file
# ============================================================================

if [[ "x" == ${LCOV_HOME}x ]] ; then
    if [ -f ../../bin/lcov ] ; then
        LCOV_HOME=../..
    fi
fi
source ../common.tst

# each name spelled out:  'perltest1.sh' runs in this same directory and the
#   harness runs the two concurrently, so a '*.log' glob here deletes the
#   'err.log' that test writes and then greps
rm -rf decl_db declforms.log subst.log nofile.log noread.log \
    declforms.info subst.info nofile.info noread.info \
    elsewhere echoversion.cb

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

# 'FNL:<index>,<start>,<end>' and 'FNA:<index>,<count>,<name>' are two records
#   joined by the index;  print "name start end" for each function.  The name is
#   whatever follows the second comma - a qualified perl name has colons in it,
#   and may well have a comma too
extents()
{
    awk '/^FNL:/ { split(substr($0, 5), l, ",") ;
                   s[l[1]] = l[2] ; e[l[1]] = l[3] }
         /^FNA:/ { rest = substr($0, 5) ;
                   i = index(rest, ",") ;
                   idx = substr(rest, 1, i - 1) ;
                   rest = substr(rest, i + 1) ;
                   name = substr(rest, index(rest, ",") + 1) ;
                   print name, s[idx], e[idx] }' $1 | LC_ALL=C sort
}

# ---------------------------------------------------------------------------
# the database:  'declforms.pl' declares its packages and subroutines in every
# form the scan has to know about
# ---------------------------------------------------------------------------
perl -MDevel::Cover=-db,decl_db,-coverage,statement,branch,condition,subroutine,-silent,1 \
    declforms.pl
if [ 0 != $? ] ; then
    echo "perl exec failed"
    exit 1
fi
cover decl_db -silent 1

# ----------------------------------------------------------------------
echo "*** 1. a package block and a versioned package"
# ----------------------------------------------------------------------
# declforms.pl has no conditional in it, so there is no branch data to find
$COVER ${EXEC_COVER} $PERL2LCOV_TOOL -o declforms.info --test-name decl \
    ./decl_db --ignore empty 2>&1 | tee declforms.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail forms "perl2lcov failed on declforms.pl"
fi
if grep -F -q 'unexpected' declforms.log ; then
    grep -F 'unexpected' declforms.log
    fail forms "a declaration form was not recognised"
fi
# the package prefix on the last two names is Devel::Cover's, and is what says
#   the two package forms opened a package at all
NAMES=`extents declforms.info | cut -d' ' -f1 | tr '\n' ' '`
echo "functions: $NAMES"
EXPECT="Block::Form::inBlock Versioned::afterHeredoc Versioned::afterPod "
EXPECT+="Versioned::beforeText Versioned::versioned plain prototyped "
if [ "$EXPECT" != "$NAMES" ] ; then
    fail forms "unexpected function list: '$NAMES'"
fi

# ----------------------------------------------------------------------
echo "*** 2. the extents bound each subroutine at the next declaration"
# ----------------------------------------------------------------------
# 'inBlock' is inside 'package Block::Form { ... }', which ends before the
#   'package Versioned 1.23;' line;  'versioned' follows that line.  Both
#   bounds come from declaration lines the old scan died on, so they are what
#   says the scan understood them
VERSIONED_LINE=`grep -n '^package Versioned' declforms.pl | cut -d: -f1`
echo "'package Versioned' is at line $VERSIONED_LINE"
extents declforms.info
IN_BLOCK_END=`extents declforms.info | awk '/^Block::Form::inBlock /{print $3}'`
VERSIONED_START=`extents declforms.info |
                 awk '/^Versioned::versioned /{print $2}'`
if [ -z "$IN_BLOCK_END" ] || [ "$IN_BLOCK_END" -ge "$VERSIONED_LINE" ] ; then
    fail extents \
        "inBlock ends at '$IN_BLOCK_END', not before line $VERSIONED_LINE"
fi
if [ -z "$VERSIONED_START" ] || [ "$VERSIONED_START" -le "$VERSIONED_LINE" ] ;
then
    fail extents \
        "versioned starts at '$VERSIONED_START', not after line $VERSIONED_LINE"
fi

# ----------------------------------------------------------------------
echo "*** 3. --substitute: the version is asked about the reported file"
# ----------------------------------------------------------------------
# a second copy of the source, under the name the report will use.  The version
#   callback prints the path it was handed, so the 'VER:' record says which of
#   the two names perl2lcov asked about
mkdir -p elsewhere
cp declforms.pl elsewhere/declforms.pl
cat > echoversion.cb <<'EOF'
#!/bin/bash
# not a version at all - the path this was asked about
echo "asked_about:$1"
EOF
chmod +x echoversion.cb
$COVER ${EXEC_COVER} $PERL2LCOV_TOOL -o subst.info --test-name decl ./decl_db \
    --ignore empty --substitute 's#^declforms#elsewhere/declforms#' \
    --version-script ./echoversion.cb 2>&1 | tee subst.log
if [ 0 != ${PIPESTATUS[0]} ] ; then
    fail subst "perl2lcov failed with --substitute"
fi
for pattern in 'SF:elsewhere/declforms.pl' \
    'VER:asked_about:elsewhere/declforms.pl' ; do
    if ! grep -F -q -e "$pattern" subst.info ; then
        grep -E '^(SF|VER):' subst.info
        fail subst "expected '$pattern' in the output"
    fi
done

# ----------------------------------------------------------------------
echo "*** 4. --substitute to a name which is not on disk"
# ----------------------------------------------------------------------
# there is no such file, so there is nothing to checksum, and the complaint has
#   to name the file which is missing - not the database key, which is there
$COVER ${EXEC_COVER} $PERL2LCOV_TOOL -o nofile.info --test-name decl ./decl_db \
    --ignore empty --substitute 's#^declforms.pl#elsewhere/nosuch.pl#' \
    --checksum 2>&1 | tee nofile.log
if [ 0 == ${PIPESTATUS[0]} ] ; then
    fail nofile "expected a 'source' error for a file which is not on disk"
fi
for pattern in 'ERROR: (source)' "cannot read 'elsewhere/nosuch.pl'" \
    'unable to compute --checksum' ; do
    if ! grep -F -q -e "$pattern" nofile.log ; then
        fail nofile "message does not mention: $pattern"
    fi
done

# ----------------------------------------------------------------------
echo "*** 5. a source file which cannot be read"
# ----------------------------------------------------------------------
# the file is there, so the scan is attempted, and fails.  Skipped when the
#   test is run by a user who can read a file whatever its mode says
cp declforms.pl elsewhere/noread.pl
chmod 000 elsewhere/noread.pl
if [ -r elsewhere/noread.pl ] ; then
    echo "elsewhere/noread.pl is readable anyway - skipping"
else
    $COVER ${EXEC_COVER} $PERL2LCOV_TOOL -o noread.info --test-name decl \
        ./decl_db --ignore empty \
        --substitute 's#^declforms.pl#elsewhere/noread.pl#' 2>&1 |
        tee noread.log
    if [ 0 == ${PIPESTATUS[0]} ] ; then
        fail noread "expected a 'source' error for an unreadable source file"
    fi
    for pattern in 'ERROR: (source)' "unable to read 'elsewhere/noread.pl'" \
        'package/sub extents' ; do
        if ! grep -F -q -e "$pattern" noread.log ; then
            fail noread "message does not mention: $pattern"
        fi
    done
fi
chmod 644 elsewhere/noread.pl

# 'name start end' for one function out of the case 1 report
extent_of()
{
    extents declforms.info | awk -v n="$1" '$1 == n { print $2, $3 }'
}

# ----------------------------------------------------------------------
echo "*** 6. a heredoc body is text, not declarations"
# ----------------------------------------------------------------------
# 'declforms.pl' has a heredoc whose body is 'package NotAPackage;' and
#   'sub notASub {'.  Reading that 'package' as a declaration renames every
#   subroutine below it - which case 1 would have caught - and ends
#   'afterHeredoc' at its own last line instead of at the last executable line
#   before the next real declaration, which is the '$shifty' statement
SHIFTY_LINE=`grep -n '^our \$shifty' declforms.pl | cut -d: -f1`
echo "'\$shifty' is at line $SHIFTY_LINE"
if grep -F -q 'NotAPackage' declforms.info ; then
    grep -F 'NotAPackage' declforms.info
    fail heredoc "a 'package' in a heredoc body was read as a declaration"
fi
AFTER_HEREDOC_END=`extent_of Versioned::afterHeredoc | cut -d' ' -f2`
echo "afterHeredoc ends at line $AFTER_HEREDOC_END"
if [ "$AFTER_HEREDOC_END" != "$SHIFTY_LINE" ] ; then
    fail heredoc \
        "afterHeredoc ends at '$AFTER_HEREDOC_END', not at line $SHIFTY_LINE"
fi

# ----------------------------------------------------------------------
echo "*** 7. POD is text too, including an '__END__' inside it"
# ----------------------------------------------------------------------
# the same thing again, for the '=pod ... =cut' block which declares
#   'package InPod;'.  That block also contains an '__END__' line, which ends
#   the scan when it is code and is text here:  reading it as code loses every
#   declaration below the POD, which case 1's function list is what catches
if grep -F -q 'InPod' declforms.info ; then
    grep -F 'InPod' declforms.info
    fail pod "a 'package' inside POD was read as a declaration"
fi
# the assertion above only means anything while the fixture still has it
if ! awk '/^=pod/ { p = 1 } /^=cut/ { p = 0 }
          /^__END__/ { if (p) found = 1 }
          END { exit(found ? 0 : 1) }' declforms.pl ; then
    fail pod "declforms.pl no longer has an '__END__' inside its POD block"
fi

# ----------------------------------------------------------------------
echo "*** 8. '<<TAG' in a string with no terminator is not a heredoc"
# ----------------------------------------------------------------------
# the '$shifty' string above contains '<<NOSUCHTAG', and nothing below it is a
#   line saying 'NOSUCHTAG'.  Treating it as a heredoc introducer anyway skips
#   the whole rest of the file, so the 'package main;' and 'sub afterPod'
#   declarations below are lost and 'afterPod' runs on to the end of the file
MAIN_LINE=`grep -n '^package main;' declforms.pl | cut -d: -f1`
AFTER_POD_END=`extent_of Versioned::afterPod | cut -d' ' -f2`
echo "'package main' is at line $MAIN_LINE, afterPod ends at $AFTER_POD_END"
if [ -z "$AFTER_POD_END" ] || [ "$AFTER_POD_END" -ge "$MAIN_LINE" ] ; then
    fail unterminated \
        "afterPod ends at '$AFTER_POD_END', not before line $MAIN_LINE"
fi

# ----------------------------------------------------------------------
if [ 0 == $STATUS ] ; then
    echo "Tests passed"
else
    echo "Tests failed"
fi

if [ "x$COVER" != "x" ] && [ $LOCAL_COVERAGE == 1 ] ; then
    generate_coverage 'declforms' $LOCAL_COVERAGE 0
fi

exit $STATUS
