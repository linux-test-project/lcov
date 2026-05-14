======================================================
genpng - generate overview PNG file from coverage data
======================================================

NAME
----

genpng
 Generate an overview image from a source file (internal tool)

:Manual section: 1
:Manual group: |ToolName| 2.0
:Date: 2023-05-12

SYNOPSIS
--------

::

  genpng [ -h | --help ]
   [ -v | --version ]
   [ -t | --tab-size *tabsize* ]
   [ -w | --width *width* ]
   [ -d | --dark-mode ]
   [ -o | --output-filename *output-filename* ]
   source-file

DESCRIPTION
-----------

**genpng** creates an overview image for a given source code file of either
plain text or .gcov file format.

Note that the *GD.pm* Perl module has to be installed for this script to work
(it may be obtained from http://www.cpan.org).

Note also that **genpng** is called from within **genhtml** so that there is
usually no need to call it directly.

OPTIONS
-------

**-h**, **--help**
   Print a short help text, then exit.

**-v**, **--version**
   Print version number, then exit.

**-t** *tab-size*, **--tab-size** *tab-size*
   Use *tab-size* spaces in place of tab.

   All occurrences of tabulator signs in the source code file will be replaced
   by the number of spaces defined by *tab-size* (default is 4).

**-w** *width*, **--width** *width*
   Set width of output image to *width* pixel.

   The resulting image will be exactly *width* pixel wide (default is 80).

   Note that source code lines which are longer than *width* will be truncated.

**-d**, **--dark-mode**
   Use a light-display-on-dark-background color scheme rather than the default
   dark-display-on-light-background.

**-o** *filename*, **--output-filename** *filename*
   Write image to *filename*.

   Specify a name for the resulting image file (default is *source-file*.png).

AUTHOR
------

Peter Oberparleiter <Peter.Oberparleiter@de.ibm.com>

SEE ALSO
--------

:manpage:`lcov(1)`, :manpage:`genhtml(1)`, :manpage:`geninfo(1)`, :manpage:`gendesc(1)`, :manpage:`gcov(1)`

https://github.com/linux-test-project/lcov
