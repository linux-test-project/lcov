To see some examples of |TOOL_NAME| generated HTML coverage reports::

    $ cp -r $|TOOL_NAME|_HOME/share/lcov/example .
    $ cd example
    $ make

Review the 'make' log and the generated
data, and then point a web browser into the resulting reports.

The example builds with GCC by default.
You will need to make a few changes if you want to use LLVM instead.


- Default view:

  - Point your browser to ``output/index.html``

- Hierarchical view:

  - Point your browser to ``hierarchical/index.html``

  - Note that that the coverage data is the same - only the report
    format is different:

    - Follows directory structure, similar to MS file viewer
      (``--hierarchical`` flag)

    - Additional navigation links also enabled
      (``--show-navigation`` flag)

- Differential coverage:

  - Point your browser to ``exampleRepo/differential/index.html``

  - This example is slightly complicated because it emulates a moderately
    realistic project in that it pretends to see project changes:

    - updates to two project source files ``example.c`` and ``iterate.c``

    - change to the test suite: only one test of updated
      code rather than 3 of the original code

    The Makefile simulates this by checking code into a git repo,
    building an executable and then updating a few source files, rebuilding,
    and running some tests.

    There is one repo, ``exampleRepo``, and both this example and the
    **Java coverage with JaCoCo** example below use it - the way a project
    written in more than one language keeps one repo rather than one per
    language.  It is built by whichever of those examples runs first, with the
    sources of both of them checked in as its ``baseline`` revision, and is
    removed by ``make clean``.  This example modifies some of those sources and
    commits them as a second revision, so it starts by putting the repo back at
    ``baseline`` - which does nothing at all the first time it is run.

- Code review:

  - point your browser to ``exampleRepo/review/index.html``

  - This example builds on the **Differential coverage** example, above
    to emulate a possible code review methodology in which adds code
    coverage to the review criteria.
    The intent is to generate a reduced report which shows only the
    code changes which negatively affect code coverage - while removing
    other details which only distract from the review.

    - Use the ``genhtml --select-script ...`` feature to show only new
      source code which was negatively affected by the change under
      review (uncovered and/or lost code).
      You might want to modify the select criteria to include positive
      change (*e.g.*, GNC, GBC, and GIC categories).

    - Real use cases are likely to use more sophisticated select-script
      callbacks (*e.g.*, to select from a range of changelists).

    - The example uses caching and profile history to improve runtime
      performance - see the man pages for a more detailed description
      of the features.  There is no effect with a tiny example - but
      a real project may see benefit.
      The ``spreadsheet.py`` application script can be used to convert
      JSON profile files into more readable excel spreadsheets.  This
      can be useful to see the effect (if any) of the caching and/or
      history features, and can show where time is spent for your example.
      This can be helpful, to suggest opportunities to optimize the |ToolName|
      implementation.

- Create ``diff`` data from previous HTML coverage report and current
  source code (*i.e.*, when revision control has not been updated or
  is not available).

  - see ``make example_html2lcov`` and/or point your browser to
    ``repo2/differential2/index.html`` and ``repo2/review/index.html``
    to see reports generated using this data.

- Java coverage with JaCoCo:

  - point your browser to ``exampleRepo/jacoco_report/index.html``

  - ``make example_java`` compiles ``HelloWorld.java`` with debug information,
    runs it with the JaCoCo agent attached, translates the data JaCoCo
    collected with the ``jacoco2lcov`` tool, and generates a report using the
    same author/date and version callbacks as the **Differential coverage**
    example above.  The source is checked in for the same reason: that is where
    the callbacks read the annotations and versions from.  It is checked into
    the same ``exampleRepo`` as the C sources of that example - see there.

  - JaCoCo reports line, branch and function (method) coverage.  There is no
    MC/DC data in a JaCoCo report.

  - This example needs a JDK and a JaCoCo installation.
    The ``./java_avail.sh`` script tries to find them - and complains if it
    can't.

    - ``java`` and ``javac`` have to be on ``PATH`` - or ``JAVA_HOME`` has to
      name the JDK, and they are then used from ``$JAVA_HOME/bin``.
      ``JAVA_HOME`` wins when both are true.  It has to be a JDK rather than a
      JRE, because the example compiles its own source.

    - ``JACOCO_HOME`` has to be set, and to name a directory with
      ``jacocoagent.jar`` in it (either at the top level or under ``lib``, which
      is where a JaCoCo release puts it).

    The Makefile runs ``java_avail.sh`` before running the java example -
    and skips the example if something is missing.
    ``make`` still runs to completion on a machine which has no Java.

    How java and JaCoCo come to be in your environment is up to you - they
    may be installed on the system, unpacked anywhere and named with
    ``JAVA_HOME`` and ``JACOCO_HOME``, or provided by whatever environment or
    package manager your site uses.  The example only checks whether
    they exist - then uses them if they do.

Feel free to edit the Makefile or to run the lcov utilities directly,
to see the effect of other options that you find in the lcov man pages.
