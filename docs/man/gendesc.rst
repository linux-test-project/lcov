===============================================
gendesc - generate a test case description file
===============================================

:Manual section: 1
:Manual group: |ToolName| 2.5

NAME
----

gendesc
 Generate a test case description file (internal application)


SYNOPSIS
--------

**gendesc** [ **-h** | **--help** ] [ **-v** | **--version** ]
   [ **-o** | **--output-filename** *filename* ]
   *inputfile*

DESCRIPTION
-----------

Convert plain text test case descriptions into a format as understood by
**genhtml**. *inputfile* needs to observe the following format:

For each test case:

- one line containing the test case name beginning at the start of the line
- one or more lines containing the test case description indented with at
  least one whitespace character (tab or space)

**Example input file:**

::

   test01
       An example test case description.
       Description continued

   test42
       Supposedly the answer to most of your questions

Note: valid test names can consist of letters, decimal digits and the
underscore character ('_').

OPTIONS
-------

**-h**, **--help**
   Print a short help text, then exit.

**-v**, **--version**
   Print version number, then exit.

**-o** *filename*, **--output-filename** *filename*
   Write description data to *filename*.

   By default, output is written to STDOUT.

AUTHOR
------

Peter Oberparleiter <Peter.Oberparleiter@de.ibm.com>

SEE ALSO
--------

:manpage:`lcov(1)`, :manpage:`genhtml(1)`, :manpage:`geninfo(1)`, :manpage:`genpng(1)`, :manpage:`gcov(1)`

https://github.com/linux-test-project/lcov
