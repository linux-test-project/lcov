LCOV test suite
===============

This directory contains a number of regression tests for LCOV. To start it,
simply run `make check`. The resulting output is written to the terminal and
stored in a log file.

You can modify some aspects of testing by specifying additional parameters on
`make` invocation:

  - SIZE

    Select the size of the artifical coverage files used for testing.
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
