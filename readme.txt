-------------------------------------------------
- README file for the LTP GCOV extension (lcov) -
- Last changes: 2002-09-05                      -
-------------------------------------------------


Contents
--------

1. Installing lcov
2. An example of how to access kernel coverage data
3. An example of how to access coverage data for a user space program
4. How to use lcov.pl
5. How to use genhtml.pl
6. How to use geninfo.pl
7. How to use genpng.pl
8. How to use gendesc.pl
9. Questions and Comments



1. Installing lcov
------------------

The LCOV scripts may be downloaded as either a tar/zip-package from

  http://ltp.sourceforge.net/lcov.php

or via CVS (most recent version), e.g. by using the following commands:

  cvs -d:pserver:anonymous@cvs.LTP.sourceforge.net:/cvsroot/ltp login

(simply press the ENTER key when asked for a password)

  cvs -z3 -d:pserver:anonymous@cvs.LTP.sourceforge.net:/cvsroot/ltp export -D now utils

You will then find the files in the utils/analysis/cat directory. Once you
got the scripts on your machine, you might consider copying all .pl files into
some directory in your shell's search path, e.g. by typing:

  cp *.pl /usr/local/bin



2. An example of how to access kernel coverage data
---------------------------------------------------

Requirements: get and install the gcov-kernel package from

  http://sourceforge/projects/lse

The resulting gcov-proc.o file should be located in the same directory as the
PERL scripts. As root do the following:

  a) Resetting counters

     lcov.pl --reset

  b) Capturing the current counter state to a file

     lcov.pl --capture --output-filename kernel.info

  c) Getting HTML output

     genhtml.pl kernel.info

Point the web browser of your choice to the resulting index.html file.



3. An example of how to access coverage data for a user space program
---------------------------------------------------------------------

Requirements: compile the program using GCC with the options -fprofile-arcs
and -ftest-coverage. Assuming the compile directory is called "appdir", do
the following:

  a) Resetting counters

     lcov.pl --directory appdir --reset

  b) Capturing the current counter state to a file - works only after the
     application has been started and stopped once

     lcov.pl --directory appdir --capture --output-filename app.info

  c) Getting HTML output

     genhtml.pl app.info

Point the web browser of your choice to the resulting index.html file.



4. How to use lcov.pl
---------------------

Usage: lcov.pl [OPTIONS]

Access GCOV code coverage data. By default, tries to access kernel coverage
data. Use the --directory option to get coverage data from a user space
program. Unless --output-file is used, coverage data is written to STDOUT.

To access kernel coverage data, the gcov-proc kernel module is required.
It may be obtained from http://sourceforge/projects/lse (files section,
package "gcov-kernel"). For ease of use, once you have the gcov-proc.o file
compiled, copy it to the same directory as lcov.pl. Note that you will need
root to access kernel coverage data.

Please note that the output of "lcov.pl --capture" is referred to as a ".info
file" or a "tracefile" in this readme text, as it is the format in which LCOV
stores the coverage data. In contrast to this, there is the ".da" file format
which is used by GCOV for the same purpose. ".da" files are created when a
program compiled with GCC's -fprofile-arcs option exits (user space
applications) or using the /proc/gcov file system entry provided by the
gcov-kernel package (linux kernel measurements).


Options:

  -h, --help
    Print a short help text, then exit


  -v, --version
    Print version number, then exit


  -q, --quiet
    Do not print progress messages

    When no output filename is specified, this option is implied to prevent
    progress messages to mess with coverage data which is also printed to
    the standard output.


  -r, --reset
    Reset all execution counts

    By default tries to reset kernel execution counts. Use the --directory
    option to reset all counters of a user space program.


  -c, --capture
    Capture coverage data

    By default captures the current kernel execution counts and writes the
    resulting coverage data to the standard output. Use the --directory
    option to capture counts for a user space program.


  -t, --test-name NAME
    Specify test name to be stored with data

    This name helps distinguish coverage results in cases were data from
    more than one test case is merged into a single file (may be done by
    simply concatentation the respective .info files). 


  -o, --output-file FILENAME
    Write data to FILENAME instead of stdout

    Specify - as a filename to use the standard output. But that would be
    pointless, wouldn't it? :)


  -d, --directory DIR(s)
    Use .da files in DIR instead of kernel

    If you want to work on coverage data for a user space program, use this
    option to specify the location where the program was compiled (that's
    were the counter files ending with .da will be stored).

    Note that you may specify more than one directory, all of which are then
    processed sequentially.


   -k, --kernel-directory KDIR(s)
    Capture kernel coverage data only from KDIR

    Use this option if you don't want to get coverage data for all of the
    kernel, but only for specific sub-directories.

    Note that you may specify more than one directory, all of which are then
    processed sequentially.



5. How to use genhtml.pl
------------------------

Usage: genhtml.pl [OPTIONS] INFOFILE(s)

Create an HTML view from coverage data found in INFOFILE. Note that INFOFILE
may also be a list of filenames. All files are created in the current working
directory unless the --output-directory option is used. If INFOFILE ends with
".gz", it is assumed to be GZIP-compressed.

Note that all source code files have to be present and readable at the location
they were compiled.


Options:

  -h, --help
    Print a short help text, then exit


  -v, --version
    Print version number, then exit


  -q, --quiet
    Do not print progress messages

    Suppresses all informational progress output. When this switch is enabled,
    only error or warning messages are printed.


  -f, --frames
    Use HTML frames for source code view

    If enabled, a frameset is created for each source code file, providing
    an overview of the source code as a "clickable" image. Note that this
    option will slow down output creation noticeably because each source
    code character has to be inspected once. Note also that the GD.pm PERL
    module has to be installed for this option to work (it may be obtained
    from http://www.cpan.org).


  -s, --show-details
    Generate detailed directory view

    When this option is enabled, genhtml.pl generates two versions of each
    file view. One containing the standard information plus a link to a
    "detailed" version. The latter additionally contains information about
    which test case covered how many lines of each source file.


  -b, --baseline-file BASEFILE
    Use BASEFILE as baseline file

    The .info file specified by BASEFILE is read and all counts found in
    the original INFOFILE are decremented by the counts in BASEFILE before
    creating any output. Note that when a count for a particular line in
    BASEFILE is greater than the corresponding count in INFOFILE, the result
    is zero.


  -o, --output-directory OUTDIR
    Write HTML output to OUTDIR

    Use this option if you want the output written to a directory other than
    the current one.


  -t, --title TITLE
    Display TITLE in header of all pages

    TITLE is written to the header portion of each generated HTML page to
    give a means of identifying the context in which a particular output
    was created. By default this is the .info filename.


  -d, --description-file DESCFILE
    Read test case descriptions from DESCFILE

    All test case descriptions found in DESCFILE and referenced in the input
    data file are read and written to an extra page which is then incorporated
    into the HTML output.

    The file format of DESCFILE is:

    for each test case:
      TN:<testname>
      TD:<test description>


  -k, --keep-descriptions
    Do not remove unused test descriptions

    Keep descriptions even if the respective test case didn't cover any files.


  -c, --css-file CSSFILE
    Use external style sheet file CSSFILE

    Using this option, an extra .css file may be specified which will replace
    the default one. May be helpful if the default colors make your eyes want
    to jump out of their sockets :)


  -p, --prefix PREFIX
    Remove PREFIX from all directory names

    Because lists containing long filenames are difficult to read, there is a
    mechanism implemented that will automatically try to shorten all directory
    names on the overview page beginning with a common prefix. By default,
    this is done using an algorithm that tries to find the prefix which, when
    applied, will minimze the resulting sum of characters of all directory
    names.

    Use this option to specify a prefix to be removed by yourself.


  --no-prefix
    Do not remove prefix from directory names

    This switch will completely disable the prefix mechanism described in the
    previous section.


  --no-source
    Do not create source code view

    Use this switch if you don't want to get a source code view for each file



6. How to use geninfo.pl
------------------------

Usage: geninfo.pl [OPTIONS] DIRECTORY


geninfo.pl converts .da files into .info files. The latter can be used as
input for genhtml.pl to get a graphical coverage data view. Unless the
--output-filename option is specified, geninfo.pl writes its output to one
file per ".da" file, the name of which is generated by simply appending
".info" to the respective .da file name.

Note that the current user needs write access to both DIRECTORY as well as to
the source code location because some temporary files have to be created
there.

Note also that geninfo.pl is called from within lcov.pl so that there is
usually need to call it directly.


Options:

  -h, --help
    Print a short help text, then exit


  -v, --version
    Print version number, then exit


  -q, --quiet
    Do not print progress messages

    Suppresses all informational progress output. When this switch is enabled,
    only error or warning messages are printed.


  -t, --test-name TESTNAME
    Use test case name TESTNAME for resulting data

    This proves useful when data from several test cases is merged (done by
    simply concatenating the respective .info files) because then a test
    name can be used to differentiate between date from each test case.


  -o, --output-filename OUTFILE
    Write all data to OUTFILE

    If you want to have all data written to a single file (for easier
    handling), use this option to specify the respective filename. By default,
    there would be a .info file created for each encountered .da file.


File format:

The .info file contains TESTNAME in the following format:

  TN:<test name>

For each source file referenced in the .da file, there is a section containing
file name and coverage data:

  SF:<absolute path to the source file>
  FN:<line number of function start>,<function name> for each function
  DA:<line number>,<execution count> for each instrumented line
  LH:<number of lines with an execution count> greater than 0
  LF:<number of instrumented lines>

Sections are separated by:

  end_of_record

In addition to the main source code file there are sections for each
#included file containing executable code. Note that the absolute path
of a source file is generated by interpreting the contents of the respective
.bb file. Relative filenames are prepended with the directory in which the
.bb file is found. Note also that symbolic links to the .bb file will be
resolved so that the actual file path is used instead of the path to a link.
This approach is necessary for the mechanism to work with the /proc/gcov
files.



7. How to use genpng.pl
-----------------------

Usage: genpng.pl [OPTIONS] SOURCEFILE

Create an overview image for a given source code file of either plain text
or .gcov file format.

Note that the GD.pm PERL module has to be installed for this script to work
(it may be obtained from http://www.cpan.org).

Note also that genpng.pl is called from within genhtml.pl so that there is
usually no need to call it directly.


Options:

  -h, --help
    Print a short help text, then exit


  -v, --version
    Print version number, then exit


  -t, --tab-size TABSIZE
    Use TABSIZE spaces in place of tab

    All occurences of tabulator signs in the source code file will be replaced
    by the number of spaces as defined by TABSIZE (default is 4).


  -w, --width WIDTH
    Set width of output image to WIDTH pixel

    The resulting image will be exactly WIDTH pixel wide (default is 80).
    Note that source code lines which are longer than WIDTH will be displayed
    truncated.


  -o, --output-filename FILENAME
    Write image to FILENAME

    Specify a name for the resulting image file (default is SOURCEFILE.png).



8. How to use gendesc.pl
------------------------

Usage: gendesc.pl [OPTIONS] INPUTFILE

Convert a test case description file into a format as understood by genhtml.pl.
INPUTFILE needs to observe the following format:

For each test case:

- one line containing the test case name beginning at the start of the line
- one or more lines containing the test case description indented with at
  least one whitespace character (tab or space)

Example:

test01

	An example test case description.
	Description continued

test02

	Another description.


Options:  

  -h, --help
    Print a short help text, then exit


  -v, --version
    Print version number, then exit


  -o, --output-filename FILENAME
    Write description to FILENAME

    By default, output is written to STDOUT



9. Questions and Comments
-------------------------

Please email you questions or comments to the LTP Mailing list at
ltp-list@lists.sourceforge.net

