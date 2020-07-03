LCOV test suite
===============

This directory contains a number of regression tests for LCOV. To start it,
simply run `make check`. The resulting output is written to the terminal and
stored in a log file.


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
