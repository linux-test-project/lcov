#!/usr/bin/env bash
#
# java_avail.sh - is there a usable Java and JaCoCo installation here?
#
# The Java coverage example needs things that no other part of the example needs:
#
#   - a JDK.  'javac -g' compiles the class files with the line number table
#     JaCoCo reads, and 'java' runs them with the JaCoCo agent attached.  Either
#     they are on PATH, or JAVA_HOME names the JDK and they are found under
#     $JAVA_HOME/bin - which wins when both are true, because an environment
#     which sets JAVA_HOME means that JDK to be used even when an older java is
#     on PATH in front of it.
#
#   - a JaCoCo installation, named by JACOCO_HOME.  'jacocoagent.jar' collects
#     the data and 'jacococli.jar' turns it into the XML which jacoco2lcov
#     translates.  jacoco2lcov finds the cli jar for itself (see man
#     jacoco2lcov(1)), and looks in the same two places under JACOCO_HOME that
#     this script looks for the agent jar.
#
# Exit status is 0 (quietly) when everything is there.
# Exit with 1 and moan about missing components if something isn't found.
# The Makefile in this directory uses this script to decide whether to run the
# java_example or not.
# 'make' will still complete successfully if there is no Java install on
# the machine.
#
# How java and JaCoCo come to be in the environment is your problem:  they may
# be installed on the system, unpacked anywhere and pointed at with JAVA_HOME
# and JACOCO_HOME, or supplied by whatever environment or package manager the
# site uses.  This script only reports what it can see.

set -u

status=0

# Write complaints to stderr and exit with 1 if there are problems.
#  The message is indented as a block:  the Makefile in this directory then
#  prints the message into its log - along with everything else.
moan()
{
    echo "  $1" 1>&2
    status=1
}

# Where the JDK programs are:  under JAVA_HOME when that is set, else wherever
#   PATH finds them.
if [ -n "${JAVA_HOME:-}" ] ; then
    for tool in java javac ; do
        if [ ! -x "$JAVA_HOME/bin/$tool" ] ; then
            moan "no '$tool' in \$JAVA_HOME/bin ('$JAVA_HOME/bin/$tool' is
    not an executable file).  JAVA_HOME has to name a JDK - and a JDK, not
    just a JRE:  the example compiles its own source."
        fi
    done
else
    for tool in java javac ; do
        if ! command -v $tool > /dev/null 2>&1 ; then
            moan "no '$tool' on PATH.  Put a JDK on PATH, or set JAVA_HOME
    to name one ('\$JAVA_HOME/bin/$tool' is what would be used then)."
        fi
    done
fi

# JaCoCo, and the one jar of it which the Makefile has to name itself.
if [ -z "${JACOCO_HOME:-}" ] ; then
    moan "JACOCO_HOME is not set.  Set it to the directory a JaCoCo release
    was unpacked into - the one with 'lib/jacocoagent.jar' in it."
elif [ ! -f "$JACOCO_HOME/lib/jacocoagent.jar" ] &&
     [ ! -f "$JACOCO_HOME/jacocoagent.jar" ] ; then
    moan "no 'jacocoagent.jar' under JACOCO_HOME ('$JACOCO_HOME'):  looked
    for 'lib/jacocoagent.jar' and 'jacocoagent.jar' there.  Does JACOCO_HOME
    name a JaCoCo installation?"
fi

exit $status
