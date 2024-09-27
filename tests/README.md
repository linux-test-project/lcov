LCOV test suite
===============

This directory contains a number of regression tests for LCOV. To start it:

  - if you are running in a build/development directory:

      - run `make check`

      - The resulting output is written to the terminal and
        stored in a log file.

  - if you are running in or from an installed 'release' (e.g., from
    $LCOV_HOME/share/lcov/tests):

       - (optional):  cp -r $LCOV_HOME/share/lcov/tests myTestDir ; cd myTestDir

       - make [COVERAGE=1]

         - to generate coverage data for the lcov module, the 'Devel::Cover'
           perl package must be available.

          - the Devel::Cover result is written to the terminal and stored in
            'test.log'

       - Results:

           The Devel::Cover 'raw' coverage data can be viewed by pointing your
           browser to .../cover_db/coverage.html.
           The coverage data can be redirected to a different location via the
           COVER_DB variable:
              $ make [COVER_DB=path/to/wherever] COVERAGE=1 ... test

           The data is translated to LCOV format and stored in
           .../cover_db/perlcov.info.
           The data can be redirected to a different location via the PERLCOV
           variable:
              $ make [PERLCOV=path/to/my/file.info] COVERAGE=1 ... test

           The corresponding genhtml-generated HTMLreport can be viewed by
           pointing your browser to .../perlcov/index.html.
           The report can be redirected to a different location via the HTML_RPT
           variable:
              $ make [HTML_RPT=path/to/my/html] COVERAGE=1 ... test

  - environment variables:

      - LCOV_SHOW_LOCATION:
        if set, show location on die() or warn()

      - LCOV_FORCE_PARALLEL:
        if set, force parallel processing, regardless of number of tasks -
        even if only one.  This is useful for regression testing - to make
        sure that we cover both serial and parallel execution.

You can modify some aspects of testing by specifying additional parameters on
`make` invocation:

  - SIZE

    Select the size of the artificial coverage files used for testing.
    Supported values are small, medium, and large.

    The default value is small.

    Example usage:

    ```
    make check SIZE=small|medium|large
    ```


  - LCOVFLAGS

    Specify additional parameters to pass to the `lcov` tool during testing.

  - GENHTMLFLAGS

    Specify additional parameters to pass to the `genhtml` tool during testing.


Adding new tests
----------------

Each test case is implemented as a stand-alone executable that is run by a
Makefile. The Makefile has the following content:

```
include ../test.mak

TESTS := test1 test2
```

To add a new test, create a new executable and add its name to the TESTS
variable in the corresponding Makefile. A test reports its result using
the program exit code:

  * 0 for pass
  * 1 for fail
  * 2 for skip (last line of output will be interpreted as reason for skip)
