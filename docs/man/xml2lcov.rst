==========================================================
xml2lcov - Translate XML coverage data to lcov format
==========================================================

:Manual section: 1
:Manual group: |ToolName| Tools

NAME
----

xml2lcov
  Translate XML coverage data to lcov format



SYNOPSIS
--------

::

    xml2lcov [--output mydata.info] [--test-name name] [options] coverage.xml+

DESCRIPTION
-----------

``xml2lcov`` traverses XML coverage data in one or more coverage data files and
translates it into LCOV ``.info`` format.

Two input schemas are read:

- The Cobertura schema
  (https://raw.githubusercontent.com/cobertura/web/master/htdocs/xml/coverage-04.dtd),
  which is what Cobertura writes, and what the Python ``Coverage.py`` module
  writes with ``coverage xml``. The root element is ``coverage``.

- The JaCoCo report schema (https://www.jacoco.org/jacoco/trunk/coverage/report.dtd),
  which is what ``java -jar jacococli.jar report --xml`` writes. The root
  element is ``report``.

The schema is deduced from the root element of the input file. Use ``--format``
to say which it is if the deduction is wrong - for example, for a report whose
root element is neither of the above.

``xml2lcov`` does not implement the full suite of |ToolName| features (*e.g.*,
demangling, filtering, substitutions, *etc.*). Generate the translated LCOV
format file and then read the data back into ``lcov`` to use those features.

**Source files**

The names in the coverage data are relative, and a source file has to be found
before its version can be extracted (``--version-script``) or its lines
checksummed (``--checksum``).

Cobertura data names its own search path, in the ``sources`` element of the XML.
Directories named by ``--source-directory`` are searched after those, so a
report whose ``sources`` do not match the current checkout can be corrected on
the command line.

JaCoCo data names no search path at all - the schema has no equivalent of the
Cobertura ``sources`` element - so ``--source-directory`` is the whole of it.
Give it the directories you would pass to ``javac``: the name of a source file
is the name of its package, used as a directory path, plus the name of the file.
A source file which is not found in the search path is not translated at all,
and neither is the source file of a class compiled without debug information,
which does not say which file it came from. Both are counted and reported when
the translation finishes.

**Branch coverage limitations**

Note that the XML coverage data format does not contain enough information
to deduce exactly which branch expressions have been taken or not taken.
It reports the total number of branch expressions associated with a particular
line, and the number of those which have been taken. There is no way to know
(except, possibly by inspection of surrounding code and/or some understanding
of your implementation) exactly which ones.

This is a problem in at least 2 ways:

- It is not straightforward to use the result to improve your regression
  suite because you don't really know what was exercised/not exercised.

- Coverage data merge is problematic. For example: you have two testcase
  XML files, each of which hit 4 of 8 branches on some line. Does that
  mean you hit 4 of them (both tests exercised the same code), all 8
  (tests exercised disjoint subsets), or some number between?

This implementation assumes that the first M branches are the ones which
are hit and the remaining N-M were not hit, in each testcase. Thus, the
combined result in the above example would claim 4 of 8 branches hit.
This definition turns out to be a lower bound.

If your data comes from JaCoCo, the merge problem above is avoidable: merge
before you translate rather than after. See **Merging JaCoCo data** below.

**JaCoCo conversion notes**

JaCoCo counts instructions and branches rather than executions, so the
execution counts in the translated data are derived:

- The ``DA:`` count of a line is the number of branches taken on that line, or
  1 if the line is covered and has no branches. A line which JaCoCo considers
  covered never reports a count of 0, but the count is not the number of times
  the line was executed.

- The ``FNA:`` count of a function is its covered cyclomatic complexity, which
  is 0 exactly when the function was not entered.

A JaCoCo ``method`` element names the line the method starts on, but not the
line it ends on, so the ``FNL:`` extent is derived: each method claims lines
from its source file's line list, starting at its own first line, until the
covered and missed quotas of its own ``LINE`` counter are filled. Every
function which begins on a particular line then reports the largest extent
found for that line, because LCOV identifies a function by its file and its
begin line - which is what a lambda and the method containing it share.

Those two derived quantities can disagree and |ToolName| will emit a message
when the JaCoCo data is read back.  The JaCoCo data contains the 'begin'
line of the method and says whether it is executed - but |ToolName| has
to derive the method end line.  This derivation can claim a line which
actually belongs to some other method, potentially creating a situation where
JaCoCo says that the function was never executed, but |ToolName| thinks
that at least one line contained within the function *is* executed:  an
inconsistency.
The JaCoCo data may or may not be correct - you will need to verify.
If the error is bogus, then you can either suppress the message (via
``--ignore-errors inconsistent``) or exclude the line or method.
Note that an uncalled lambda will not generate this error:
|ToolName| knows that the first line
of a lambda belongs to its enclosing method as well.

MC/DC data is not generated: JaCoCo reports how many branches on a line were
taken, but not which condition, and not which sense of it, was left uncovered -
which is precisely what an ``MCDC:`` record has to say.

**Merging JaCoCo data**

If you have coverage data from more than one test run, combine it on the JaCoCo
side and translate the single combined report - either by handing all the
execution data files to one ``jacococli.jar report`` run, or by combining them
first with ``jacococli.jar merge``. Do not translate each report separately and
then merge the resulting ``.info`` files with ``lcov -a``.

The reason is branch data. JaCoCo knows which branch of a line is which, so its
own merge combines the per-branch results exactly: a line whose first branch was
taken in one run and whose second branch was taken in another is reported with
both branches taken. ``xml2lcov`` cannot do that, because the XML no longer says
which branch is which - only how many of them were taken - so it assigns the
taken ones by position, as described under **Branch coverage limitations**
above. Merging translated data therefore merges those lower bounds, and the
result understates branch coverage whenever two runs took different branches on
the same line: in the extreme, two runs which between them covered every branch
of a line are reported as having covered only as many as the better of the two.

Line and function coverage do not have this problem - they are keyed by line
number, which survives the translation - so if the reports you want to combine
are already translated, merging them with ``lcov -a`` is still correct for
those, and only the branch data is pessimistic.

OPTIONS
-------

``-o``, ``--output`` *file*
   Specify the output LCOV ``.info`` file. Default: ``xml2lcov.info``.

``-t``, ``--test-name``, ``--testname`` *name*
   Specify the test name for the ``TN:`` entry in the LCOV ``.info`` file.

``-e``, ``--exclude`` *patterns*
   Specify exclude file patterns separated by commas.

``--format`` ``auto`` | ``cobertura`` | ``jacoco``
   Specify the schema of the input files. Default: ``auto``, which uses the XML
   root element to tell ``coverage`` (Cobertura) from ``report`` (JaCoCo).

``-s``, ``--source-directory``, ``--source-dir`` *directory*
   Specify a directory to search for source files. May be repeated. Searched
   after the directories the XML itself names, and the only search path for
   JaCoCo data, which names none.

``-v``, ``--verbose``
   Print debug messages.

``--version-script`` *script*
   Version extract callback script.

``--checksum``
   Compute line checksum. See :manpage:`lcov(1)`.

``-k``, ``--keep-going``
   Ignore errors and continue processing.

``xml2lcov`` is a stand-alone Python executable - and so does *not*
directly support the standard |ToolName| command line and RC options - *e.g.*,
for filtering, file inclusion and exclusion, *etc.*
To use these options, you will have to first use ``xml2lcov`` to translate
your coverage data, and then apply the options you want to use via
``lcov -a mydata.info <options> ...``. See :manpage:`lcov(1)` for details.

EXAMPLES
--------

Cobertura data:

::

      # generate the LCOV-format .info file
    $ xml2lcov -o mydata.info coverage1.xml coverage2.xml

      # apply some filtering
    $ lcov -a mydata.info --filter branch,blank -o filtered.info

      # and use genhtml to produce an HTML coverage report
    $ genhtml -o html_report mydata.info

      # use differential coverage to see exactly what filtering did
    $ genhtml -o html_differential --baseline-file mydata.info filtered.info

JaCoCo data:

::

      # generate the JaCoCo XML report from the coverage data JaCoCo collected.
      # Hand all of your execution data files to this one command rather than
      # translating each of them and merging the results - see 'Merging JaCoCo
      # data' above
    $ java -jar jacococli.jar report test1.exec test2.exec \
        --classfiles build/classes --xml jacoco.xml

      # translate it, telling xml2lcov where the sources are
    $ xml2lcov -o mydata.info -s src -s generated/src jacoco.xml

      # JaCoCo reports lines as covered whose branches it never saw evaluated,
      # which lcov and genhtml consider inconsistent
    $ genhtml -o html_report mydata.info --branch-coverage \
        --ignore-errors inconsistent

Note that :manpage:`jacoco2lcov(1)` wraps the java and xml2lcov commands
so you can capture Java coverage data without invoking multiple steps.

AUTHOR
------

Henry Cox <henry.cox@mediatek.com>

SEE ALSO
--------

:manpage:`lcov(1)`, :manpage:`genhtml(1)`, :manpage:`geninfo(1)`,
:manpage:`py2lcov(1)`, :manpage:`jacoco2lcov(1)`

- Cobertura documentation: https://cobertura.github.io/cobertura
- JaCoCo documentation: https://www.jacoco.org/jacoco/trunk/doc
