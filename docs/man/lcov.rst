=========================================================================
lcov - capture and manipulate coverage data from lcov tracefiles or gcov.
=========================================================================

NAME
----

lcov
Capture and manipulate coverage data from lcov tracefiles or gcov

SYNOPSIS
--------

Capture coverage data tracefile (from compiler-generated data).
The lcov tracefile (".info" file) format is described in :manpage:`geninfo(1)`.

::

   lcov -c | --capture
       [ -d | --directory *directory* ]
       [ -k | --kernel-directory *directory* ]
       [ -o | --output-file *tracefile* ]
       [ -t | --test-name *testname* ]
       [ -b | --base-directory *directory* ]
       [ --build-directory *directory* ]
       [ --source-directory *directory* ]
       [ -i | --initial ]
       [ --all ]
       [ --gcov-tool *tool* ]
       [ --branch-coverage ]
       [ --mcdc-coverage ]
       [ --demangle-cpp [ *param* ] ]
       [ --checksum ]
       [ --no-checksum ]
       [ --no-recursion ]
       [ -f | --follow ]
       [ --sort-input ]
       [ --compat-libtool ]
       [ --no-compat-libtool ]
       [ --msg-log [ *log_file_name* ] ]
       [ --ignore-errors *errors* ]
       [ --expect-message-count *message_type=expr[,message_type=expr..]* ]
       [ --preserve ]
       [ --to-package *package* ]
       [ --from-package *package* ]
       [ --no-markers ]
       [ --external ]
       [ --no-external ]
       [ --compat *mode*\ =on|off|auto]
       [ --context-script *script_file* ]
       [ --criteria-script *script_file* ]
       [ --history-script *callback* ]
       [ --resolve-script *script_file* ]
       [ --version-script *script_file* ]
       [ --unreachable-script *callback* ]
       [ --comment *comment_string* ]
       [ --large-file *regexp* ]

Generate tracefile (from compiler-generated data) with all counter values set to zero:

::

   lcov -z | --zerocounters
       [ -d | --directory *directory* ]
       [ --no-recursion ]
       [ -f | --follow ]

Show coverage counts recorded in previously generated tracefiles:

::

   lcov -l | --list *tracefile*
       [ --list-full-path ]
       [ --no-list-full-path ]

Aggregate multiple coverage tracefiles into one:

::

   lcov -a | --add-tracefile *tracefile_patterns*
       [ -o | --output-file *tracefile* ]
       [ --prune-tests ]
       [ --forget-test-names ]
       [ --map-functions ]
       [ --branch-coverage ]
       [ --mcdc-coverage ]
       [ --checksum ]
       [ --no-checksum ]
       [ --sort-input ]

Depending on your use model, it may not be necessary to create aggregate coverage data files.
For example, if your regression tests are split into multiple suites, you may want to keep separate suite data and to compare both per-suite and aggregate results over time.
``genhtml`` allows you specify tracefiles via one or more glob patterns - which enables you
generate aggregate reports without explicitly generating aggregated trace files.
See the ``genhtml`` man page.

Generate new tracefile from existing tracefile, keeping only data from files matching pattern:

::

   lcov -e | --extract *tracefile pattern*
       [ -o | --output-file *tracefile* ]
       [ --checksum ]
       [ --no-checksum ]

Generate new tracefile from existing tracefile, removing data from files matching pattern:

::

   lcov -r | --remove *tracefile pattern*
       [ -o | --output-file *tracefile* ]
       [ --checksum ]
       [ --no-checksum ]

Generate new tracefile from existing tracefiles by performing set operations on coverage data:

::

   lcov --intersect *rh_glob_pattern*
       [ -o | --output-file *tracefile* ]
       lh_glob_pattern

The output will reflect

   *(union of files matching lh_glob_patterns)* *intersect* *(union of files matching rh_glob_patterns)*

such that coverpoints found in both sets are merged (summed) whereas coverpoints found in only one set are dropped.
Note that branch blocks are defined to be the same if and only if their block ID and the associated branch expressions list are identical.
Functions are defined to be the same if their name and location are identical.

::

   lcov --subtract *rh_glob_pattern*
       [ -o | --output-file *tracefile* ]
       lh_glob_pattern

The output will reflect

   *(union of files matching lh_glob_patterns)* *subtract* *(union of files matching rh_glob_patterns)*

such that coverpoints found only in the set on the left will be retained and all others are dropped.

Summarize tracefile content:

::

   lcov --summary *tracefile*

Print version or help message and exit:

::

   lcov [ -h | --help ]
       [ --version ]

Common lcov options - supported by all the above use cases:

::

   lcov [ --keep-going ]
       [ --filter *type* ]
       [ -q | --quiet ]
       [ -v | --verbose ]
       [ --comment *comment_string* ]
       [ --debug ]
       [ --parallel | -j [*integer*] ]
       [ --memory *integer_num_Mb* ]
       [ --tempdir *dirname* ]
       [ --branch-coverage ]
       [ --mcdc-coverage ]
       [ --config-file *config-file* ]
       [ --rc *keyword*\ =\ *value* ]
       [ --profile [ *profile-file* ] ]
       [ --include *glob_pattern* ]
       [ --exclude *glob_pattern* ]
       [ --erase-functions *regexp_pattern* ]
       [ --substitute *regexp_pattern* ]
       [ --omit-lines *regexp_pattern* ]
       [ --fail-under-branches *percentage* ]
       [ --fail-under-lines *percentage* ]

DESCRIPTION
-----------

``lcov`` is a graphical front-end for GCC's coverage testing tool gcov. It collects
line, function and branch coverage data for multiple source files and creates
HTML pages containing the source code annotated with coverage information.
It also adds overview pages for easy navigation within the file structure.

Use ``lcov`` to collect coverage data and ``genhtml`` to create HTML pages. Coverage data can either be collected from the
currently running Linux kernel or from a user space application. To do this,
you have to complete the following preparation steps:

For Linux kernel coverage:

   Follow the setup instructions for the gcov-kernel infrastructure:
   *https://docs.kernel.org/dev-tools/gcov.html*

For user space application coverage:

   Compile the application with GCC using the options
   "-fprofile-arcs" and "-ftest-coverage" or "--coverage".

Please note that this man page refers to the output format of
``lcov`` as ".info file" or "tracefile" and that the output of GCOV
is called ".da file".

Also note that when printing percentages, 0% and 100% are only printed when
the values are exactly 0% and 100% respectively. Other values which would
conventionally be rounded to 0% or 100% are instead printed as nearest
non-boundary value. This behavior is in accordance with that of the
:manpage:`gcov(1)` tool.

By default,
``lcov`` and related tools generate and collect line and function coverage data.
Branch data is not collected or displayed by default; all tools support the
``--branch-coverage``
and
``--mcdc-coverage``
options to enable branch and MC/DC coverage, respectively - or you can permanently enable branch coverage by adding the appropriate
settings to your personal, group, or site lcov configuration file.  See man
:manpage:`lcovrc(5)` for details.

OPTIONS
-------

In general, (almost) all
``lcov``
options can also be specified in a configuration file - see man
:manpage:`lcovrc(5)` for details.

``-a`` *tracefile_patterns*
``--add-tracefile`` *tracefile_patterns*

   Add contents of all files matching glob pattern *tracefile_patterns*.

   Specify several tracefiles using the -a switch to combine the coverage data
   contained in these files by adding up execution counts for matching test and
   filename combinations.

   The result of the add operation will be written to stdout or the tracefile
   specified with -o.

   Only one of  -z, -c, -a, -e, -r, -l or --summary may be
   specified at a time.

``-b`` *directory*
``--base-directory`` *directory*

   Use *directory* as base directory for relative paths.

   Use this option to specify the base directory of a build-environment
   when lcov produces error messages like:

   ::

      ERROR: could not read source file /home/user/project/subdir1/subdir2/subdir1/subdir2/file.c

   In this example, use /home/user/project as base directory.

   This option is required when using lcov on projects built with libtool or
   similar build environments that work with a base directory, *i.e.* environments,
   where the current working directory when invoking the compiler is not the same
   directory in which the source code file is located.

   Note that this option will not work in environments where multiple base
   directories are used. In that case use configuration file setting
   ``geninfo_auto_base=1``
   (see man
   :manpage:`lcovrc(5)`).

``--build-directory`` *build_directory*

   search for .gcno data files from build_directory rather than
   adjacent to the corresponding .gcda file.

   See man
   :manpage:`geninfo(1)`
   for details.

``--source-directory`` *dirname*

   Add 'dirname' to the list of places to look for source files.

   For relative source file paths listed in
   *e.g.*
   paths found in
   *tracefile*,
   or found in gcov output during
   *--capture*
   - possibly after substitutions have been applied -
   ``lcov``
   will first look for the path from 'cwd' (where genhtml was
   invoked) and
   then from each alternate directory name in the order specified.
   The first location matching location is used.

   This option can be specified multiple times, to add more directories to the source search path.

``-c``
``--capture``

   Capture runtime coverage data.

   By default captures the current kernel execution counts and writes the
   resulting coverage data to the standard output. Use the --directory
   option to capture counts for a user space program.

   The result of the capture operation will be written to stdout or the tracefile
   specified with -o.

   When combined with the
   ``--all``
   flag, both runtime and compile-time coverage will be extracted in one step.
   See the description of the
   ``--initial``
   flag, below.

   See man
   :manpage:`geninfo(1)`)
   for more details about the capture process and available options and parameters.

   Only one of  -z, -c, -a, -e, -r, -l, --diff or --summary may be
   specified at a time.

``--branch-coverage``

   Collect and/or retain branch coverage data.

   This is equivalent to using the option "--rc branch_coverage=1"; the option was added to better match the genhtml interface.

``--mcdc-coverage``

   Collect and retain MC/DC data.

   This is equivalent to using the option "--rc mcdc_coverage=1".
   MC/DC coverage is supported for GCC versions 14.2 and higher, or
   LLVM 18.1 and higher.

   See
   *llvm2lcov --help*
   for details on MC/DC data capture in LLVM.

   See the MC/DC section of man
   :manpage:`genhtml(1)`
   for more details

``--checksum``
``--no-checksum``

   Specify whether to generate checksum data when writing tracefiles and/or to
   verify matching checksums when combining trace files.

   Use --checksum to enable checksum generation or --no-checksum to
   disable it. Checksum generation is
   ``disabled``
   by default.

   When checksum generation is enabled, a checksum will be generated for each
   source code line and stored along with the coverage data. This checksum will
   be used to prevent attempts to combine coverage data from different source
   code versions.

   If you don't work with different source code versions, disable this option
   to speed up coverage data processing and to reduce the size of tracefiles.

   Note that this options is somewhat subsumed by the
   ``--version-script``
   option - which does something similar, but at the 'whole file' level.

``--compat`` *mode*\ =\ *value*[,*mode*\ =\ *value*,...]

   Set compatibility mode.

   Use --compat to specify that lcov should enable one or more compatibility
   modes when capturing coverage data. You can provide a comma-separated list
   of mode=value pairs to specify the values for multiple modes.

   Valid
   *values*
   are:

   ``on``

      Enable compatibility mode.

   ``off``

      Disable compatibility mode.

   ``auto``

      Apply auto-detection to determine if compatibility mode is required. Note that
      auto-detection is not available for all compatibility modes.

   If no value is specified, 'on' is assumed as default value.

   Valid
   *modes*
   are:

   ``libtool``

      Enable this mode if you are capturing coverage data for a project that
      was built using the libtool mechanism. See also
      --compat-libtool.

      The default value for this setting is 'on'.

   ``hammer``

      Enable this mode if you are capturing coverage data for a project that
      was built using a version of GCC 3.3 that contains a modification
      (hammer patch) of later GCC versions. You can identify a modified GCC 3.3
      by checking the build directory of your project for files ending in the
      extension '.bbg'. Unmodified versions of GCC 3.3 name these files '.bb'.

      The default value for this setting is 'auto'.

   ``split_crc``

      Enable this mode if you are capturing coverage data for a project that
      was built using a version of GCC 4.6 that contains a modification
      (split function checksums) of later GCC versions. Typical error messages
      when running lcov on coverage data produced by such GCC versions are
      'out of memory' and 'reached unexpected end of file'.

      The default value for this setting is 'auto'

``--compat-libtool``
``--no-compat-libtool``

   Specify whether to enable libtool compatibility mode.

   Use --compat-libtool to enable libtool compatibility mode or --no-compat-libtool
   to disable it. The libtool compatibility mode is
   ``enabled``
   by default.

   When libtool compatibility mode is enabled, lcov will assume that the source
   code relating to a .da file located in a directory named ".libs" can be
   found in its parent directory.

   If you have directories named ".libs" in your build environment but don't use
   libtool, disable this option to prevent problems when capturing coverage data.

``--config-file`` *config-file*

   Specify a configuration file to use.
   See man
   :manpage:`lcovrc(5)`
   for details of the file format and options.  Also see the
   *config_file*
   entry in the same man page for details on how to include one config file into
   another.

   When this option is specified, neither the system-wide configuration file
   /etc/lcovrc, nor the per-user configuration file ~/.lcovrc is read.

   This option may be useful when there is a need to run several
   instances of
   ``lcov``
   with different configuration file options in parallel.

   Note that this option must be specified in full - abbreviations are not supported.

``--profile`` [*profile-data-file*]

   Tell the tool to keep track of performance and other configuration data.
   If the optional
   *profile-data-file*
   is not specified, then the profile data is written to a file named with the same
   basename as the
   *--output-filename*, with suffix
   *".json"*
   appended.
   Profile data is useful if you are trying to optimize the
   ``lcov``
   implementation (see ``$LCOV_ROOT/share/lcov/support-scripts/spreadsheet.py``), and can also enable faster 
   *--parallel* execution (see the
   *"--history-script"*
   section of this man page).

``--history-script`` *callback*

   Use
   *callback*
   to predict current runtime cost using observed cost from prior execution.

   See man
   :manpage:`genhtml(1)`
   for more information.

Only one of  -z, -c, -a, -e, -r, -l, --diff or --summary may be
specified at a time.

``-d`` *directory*
``--directory`` *directory*

   Use .da files in
   *directory*
   instead of kernel.

   If you want to work on coverage data for a user space program, use this
   option to specify the location where the program was compiled (that's
   where the counter files ending with .da will be stored).

   Note that you may specify this option more than once.

``--exclude`` *pattern*

   Exclude source files matching
   *pattern*.

   Use this switch if you want to exclude coverage data for a particular set
   of source files matching any of the given patterns. Multiple patterns can be
   specified by using multiple
   ``--exclude`` command line switches. The
   *patterns*
   will be interpreted as shell wildcard patterns (note that they may need to be
   escaped accordingly to prevent the shell from expanding them first).

   Note: The pattern must be specified to match the
   ``absolute``
   path of each source file.
   If you specify a pattern which does not seem to be correctly applied - files that you expected to be excluded still appear in the output - you can look for warning messages in the log file.
   ``lcov``
   will emit a warning for every pattern which is not applied at least once.

   Can be combined with the
   ``--include``
   command line switch. If a given file matches both the include pattern and the
   exclude pattern, the exclude pattern will take precedence.

``--erase-functions`` *regexp*

   Exclude coverage data from lines which fall within a function whose name matches the supplied regexp.  Note that this is a mangled or demangled name, depending on whether the --demangle-cpp option is used or not.

   Note that this option requires that you use a gcc version which is new enough to support function begin/end line reports or that you configure the tool to derive the required data - see the
   ``derive_function_end_line``
   discussion in man
   :manpage:`lcovrc(5)`.

``--substitute`` *regexp_pattern*

   Apply Perl regexp
   *regexp_pattern*
   to source file names found during processing.  This is useful, for example, when the path name reported by gcov does not match your source layout and the file is not found, or in more complicated environments where the build directory structure does not match the source code layout or the layout in the projects's revision control system.

   Use this option in situations where geninfo cannot find the correct
   path to source code files of a project. By providing a
   *regexp_pattern*
   in Perl regular expression format (see man
   :manpage:`perlre(1)`), you can instruct geninfo to
   remove or change parts of the incorrect source path.
   Also see the
   ``--resolve-script``
   option.

   One or more
   *--substitution*
   patterns and/or a
   *--resolve-script*
   may be specified.  When multiple patterns are specified, they are applied in the order specified, substitution patterns first followed by the resolve callback.
   The file search order is:

   1. Look for file name (unmodified).
      
      If the file exits: return it.

   2. Apply all substitution patterns in order - the result of the first pattern is used as the input of the second pattern, and so forth.
      
      If a file corresponding to the resulting name exists:  return it.

   3. Apply the 'resolve' callback to the final result of pattern substitutions.
      
      If a file corresponding to the resulting name exists:  return it.

   4. Otherwise:  return original (unmodified) file name.
      
      Depending on context, the unresolved file name may or may not result in an error.

   Substitutions are used in multiple contexts by lcov/genhtml/geninfo:

   -  during
      *--capture*,
      applied to source file names found in gcov-generated coverage data files (see man
      :manpage:`gcov(1)`).

   -  during
      *--capture*,
      applied to alternate
      *--build-dir*
      paths, when looking for the
      *.gcno*
      (compile time) data file corresponding to some
      *.gcda*
      (runtime) data file.

   -  applied to file names found in lcov data files (".info" files) -
      *e.g.*,
      during lcov data aggregation or HTML and text report generation.
      
      For example, substituted names are used to find source files for
      text-based filtering (see the
      *--filter*
      section, below) and are passed to
      *--version-script, --annotate-script,*
      and
      *-criteria-script*
      callbacks.

   -  applied to file names found in the
      *--diff-file*
      passed to genhtml.

**Example:**

1. When geninfo reports that it cannot find source file

   ::

      /path/to/src/.libs/file.c

   while the file is actually located in

   ::

      /path/to/src/file.c

   use the following parameter:

   ::

      --substitute 's#/.libs##g'

   This will remove all "/.libs" strings from the path.

2. When geninfo reports that it cannot find source file

   ::

      /tmp/build/file.c

   while the file is actually located in

   ::

      /usr/src/file.c

   use the following parameter:

   ::

      --substitute 's#/tmp/build#/usr/src#g'

   This will change all "/tmp/build" strings in the path to "/usr/src".

``--omit-lines`` *regexp*

   Exclude coverage data from lines whose content matches
   *regexp*.

   Use this switch if you want to exclude line and branch coverage data for some particular constructs in your code (*e.g.*, some complicated macro).  Multiple patterns can be
   specified by using multiple
   ``--omit-lines`` command line switches. The
   *regexp*
   will be interpreted as perl regular expressions (note that they may need to be
   escaped accordingly to prevent the shell from expanding them first).
   If you want the pattern to explicitly match from the start or end of the line, your regexp should start and/or end with "^" and/or "$".

   Note that the
   ``lcovrc``
   config file setting
   ``lcov_excl_line = regexp``
   is similar to
   ``--omit-lines.``.
   ``--omit-lines``
   is useful if there are multiple teams each of which want to exclude certain patterns.
   ``--omit-lines``
   is additive and can be specified across multiple config files whereas each call to
   ``lcov_excl_line``
   overrides the previous value - and thus teams must coordinate.

``--external``
``--no-external``

   Specify whether to capture coverage data for external source files.

   External source files are files which are not located in one of the directories
   specified by
   *--directory*
   or
   *--base-directory*.
   Use
   *--external*
   to include
   coverpoints in external source files while capturing coverage data or
   *--no-external*
   to exclude them.
   If your
   *--directory*
   or
   *--base-directory*
   path contains a soft link, then actual target directory is not considered to be
   "internal" unless the
   *--follow*
   option is used.

   The
   *--no-external*
   option is somewhat of a blunt instrument;  the
   *--exclude*
   and
   *--include*
   options provide finer grained control over which coverage data is and is not
   included if your project structure is complex and/or
   *--no-external*
   does not do what you want.

   Data for external source files is
   ``included``
   by default.

``--forget-test-names``

   If non-zero, ignore testcase names in .info file -
   *i.e.*,
   treat all coverage data as if it came from the same testcase.
   This may improve performance and reduce memory consumption if user does
   not need per-testcase coverage summary in coverage reports.

   This option can also be configured permanently using the configuration file
   option
   *forget_testcase_names*.

``--prune-tests``

   Determine list of unique tracefiles.

   Use this option to determine a list of unique tracefiles from the list
   specified by
   ``--add-tracefile``.
   A tracefile is considered to be unique if it is the only tracefile that:

   1. contains data for a specific source file

   2. contains data for a specific test case name

   3. contains non-zero coverage data for a specific line, function or branch

   Note that the list of retained files may depend on the order they are processed.  For example, if
   *A*
   and
   *B*
   contain identical coverage data, then the first one we see will be retained and the second will be pruned.
   The file processing order is nondeterministic when the
   ``--parallel``
   option is used - implying that the pruned result may differ from one execution to the next in this case.

   ``--prune-tests`` must be specified together with
   ``--add-tracefile``.
   When specified,
   ``lcov``
   will emit the list of unique files rather than combined tracefile data.

``--map-functions``

   List tracefiles with non-zero coverage for each function.

   Use this option to determine the list of tracefiles that contain non-zero
   coverage data for each function from the list of tracefiles specified by
   ``--add-tracefile``.

   This option must be specified together with
   ``--add-tracefile``.
   When specified,
   ``lcov``
   will emit the list of functions and associated tracefiles rather than combined tracefile data.

``--context-script`` *script*

   Use
   *script*
   to collect additional tool execution context information - to aid in
   infrastructure debugging and/or tracking.

   See the genhtml man page for more details on the context script.

``--criteria-script`` *script*

   Use
   *script*
   to test for coverage acceptance criteria.

   See the genhtml man page for more details on the criteria script.
   Note that lcov does not keep track of date and owner information (see the
   *--annotate-script*
   entry in the genhtml man page) - so this information is not passed to the lcov callback.

``--resolve-script`` *script*

   Use
   *script*
   to find the file path for some source file which appears in
   an input data file if the file is not found after applying
   *--substitute*
   patterns and searching the
   *--source-directory*
   list.  This option is equivalent to the
   ``resolve_script``
   config file option. See man
   :manpage:`lcovrc(5)`
   for details.

``--version-script`` *script*

   Use
   *script*
   to get a source file's version ID from revision control when
   extracting data and to compare version IDs for the purpose of error checking when merging .info files.

   See the genhtml man page for more details on the version script.

``--unreachable-script`` *module*

   Use
   *module*
   to decide whether particular branch expressions and/or MC/DC conditions
   should be removed from the coverage report.
   This option is equivalent to the
   ``unreachable_script``
   config file option. See man
   :manpage:`lcovrc(5)`
   for details.

   Note that
   *"module"*
   is required to be a Perl module.

   See the genhtml man page for more details.

``--comment`` *comment_string*

   Append
   *comment_string*
   to list of comments emitted into output result file.
   This option may be specified multiple times.
   Comments are printed at the top of the file, in the order they were specified.

   Comments may be useful to document the conditions under which the trace file was
   generated:  host, date, environment,
   *etc.*

   Note that this option has no effect for lcov operations which do not write an
   output result file:
   *--list*
   *--summary*,
   *--prune-tests*,
   and
   *--map-functions*.

   See the
   ``geninfo``
   man page for a description of the comment format in the result file.

``-e`` *tracefile pattern*
``--extract`` *tracefile pattern*

   Extract data from
   *tracefile*.

   Use this switch if you want to extract coverage data for only a particular
   set of files from a tracefile. Additional command line parameters will be
   interpreted as shell wildcard patterns (note that they may need to be
   escaped accordingly to prevent the shell from expanding them first).
   Every file entry in
   *tracefile*
   which matches at least one of those patterns will be extracted.

   Note: The pattern must be specified to match the
   ``absolute``
   path of each source file.

   The result of the extract operation will be written to stdout or the tracefile
   specified with -o.

   Only one of  -z, -c, -a, -e, -r, -l, --diff or --summary may be
   specified at a time.

``-f``
``--follow``

   Follow links when searching for .da files.

``--large-file`` *regexp*

   See the
   *--large-file*
   section of man
   :manpage:`geninfo(1)`
   for details.

``--from-package`` *package*

   Use .da files in
   *package*
   instead of kernel or directory.

   Use this option if you have separate machines for build and test and
   want to perform the .info file creation on the build machine. See
   --to-package for more information.

``--sort-input``

   Specify whether to sort file names before capture and/or aggregation.
   Sorting reduces certain types of processing order-dependent output differences.
   See the
   ``sort_input``
   section in
   man
   :manpage:`lcovrc(5)`.

``--gcov-tool`` *tool*

   Specify the location of the gcov tool.

   See the geninfo man page for more details.

``-h``
``--help``

   Print a short help text, then exit.

``--include`` *pattern*

   Include source files matching
   *pattern*.

   Use this switch if you want to include coverage data for only a particular set
   of source files matching any of the given patterns. Multiple patterns can be
   specified by using multiple
   ``--include`` command line switches. The
   *patterns*
   will be interpreted as shell wildcard patterns (note that they may need to be
   escaped accordingly to prevent the shell from expanding them first).

   Note: The pattern must be specified to match the
   ``absolute``
   path of each source file.

   If you specify a pattern which does not seem to be correctly applied - files that you expected to be included in the output do not appear - lcov will generate an error message of type 'unused'.  See the --ignore-errors option for how to make lcov ignore the error or turn it into a warning.

``--msg-log`` [*log_file_name*]

   Specify location to store error and warning messages (in addition to writing to STDERR).
   If
   *log_file_name*
   is not specified, then default location is used.

``--ignore-errors`` *errors*

   Specify a list of errors after which to continue processing.

   Use this option to specify a list of one or more classes of errors after which
   lcov should continue processing instead of aborting.
   Note that the tool will generate a warning (rather than a fatal error) unless you ignore the error two (or more) times:

   ::

      lcov ... --ignore-errors source,source ...

   *errors*
   can be a comma-separated list of the following keywords:

   ``branch``

      branch ID (2nd field in the .info file 'BRDA' entry) does not follow expected integer sequence.

   ``callback``

      Version script error.

   ``child``

      child process returned non-zero exit code during
      *--parallel*
      execution.  This typically indicates that the child encountered an error:  see the log file immediately above this message.
      In contrast:  the
      ``parallel``
      error indicates an unexpected/unhandled exception in the child process - not a 'typical' lcov error.

   ``corrupt``

      corrupt/unreadable file found.

   ``count``

      An excessive number of messages of some class have been reported - subsequent messages of that type will be suppressed.
      The limit can be controlled by the 'max_message_count' variable. See man
      :manpage:`lcovrc(5)`.

   ``deprecated``

      You are using a deprecated option.
      This option will be removed in an upcoming release - so you should change your
      scripts now.

   ``empty``

      the .info data file is empty (*e.g.*, because all the code was 'removed' or excluded.

   ``excessive``

      your coverage data contains a suspiciously large 'hit' count which is unlikely
      to be correct - possibly indicating a bug in your toolchain.
      See the
      *excessive_count_threshold*
      section in man
      :manpage:`lcovrc(5)`
      for details.

   ``fork``

      Unable to create child process during
      *--parallel*
      execution.
      
      If the message is ignored (
      *--ignore-errors fork*
      ), then genhtml
      will wait a brief period and then retry the failed execution.
      
      If you see continued errors, either turn off or reduce parallelism, set a memory limit, or find a larger server to run the task.

   ``format``

      Unexpected syntax or value found in .info file - for example, negative number or
      zero line number encountered.

   ``gcov``

      the gcov tool returned with a non-zero return code.

   ``graph``

      the graph file could not be found or is corrupted.

   ``inconsistent``

      your coverage data is internally inconsistent:  it makes two or more mutually
      exclusive claims.  For example, some expression is marked as both an exception branch and not an exception branch.  (See man
      :manpage:`genhtml(1)`
      for more details.

   ``internal``

      internal tool issue detected.  Please report this bug along with a testcase.

   ``mismatch``

      Inconsistent entries found in trace file:

      - branch expression (3rd field in the .info file 'BRDA' entry) of merge data does not match, or

      - function execution count (FNDA:...) but no function declaration (FN:...).

   ``missing``

      File does not exist or is not readable.

   ``negative``

      negative 'hit' count found.

      Note that negative counts may be caused by a known GCC bug - see

        https://gcc.gnu.org/bugzilla/show_bug.cgi?id=68080

      and try compiling with "-fprofile-update=atomic". You will need to recompile, re-run your tests, and re-capture coverage data.

   ``package``

      a required perl package is not installed on your system.  In some cases, it is possible to ignore this message and continue - however, certain features will be disabled in that case.

   ``parallel``

      various types of errors related to parallelism -
      *i.e.*,
      a child process died due to an error.  The corresponding error message appears in the log file immediately before the
      *parallel*
      error.

      If you see an error related to parallel execution that seems invalid, it may be a good idea to remove the --parallel flag and try again.  If removing the flag leads to a different result, please report the issue (along with a testcase) so that the tool can be fixed.

   ``parent``

      the parent process exited while child was active during
      *--parallel*
      execution.  This happens when the parent has encountered a fatal error -
      *e.g.*
      an error in some other child which was not ignored.  This child cannot continue working without its parent - and so will exit.

   ``range``

      Coverage data refers to a line number which is larger than the number of
      lines in the source file.  This can be caused by a version mismatch or
      by an issue in the
      *gcov*
      data.

   ``source``

      the source code file for a data set could not be found.

   ``unreachable``

      a coverpoint (line, branch, function, or MC/DC) within an "unreachable" region is executed (hit); either the code, directive placement, or both are wrong.
      If the error is ignored, the offending coverpoint is retained (not excluded) or not, depending on the value of the
      *retain_unreachable_coverpoints_if_executed*
      configuration parameter.
      See man
      :manpage:`lcovrc(5)`
      and the
      *"Exclusion markers"*
      section of man
      :manpage:`geninfo(1)`
      for more information.

   ``unsupported``

      the requested feature is not supported for this tool configuration.  For example, function begin/end line range exclusions use some GCOV features that are not available in older GCC releases.

   ``unused``

      the include/exclude/erase/omit/substitute pattern did not match any file pathnames.

   ``usage``

      unsupported usage detected - *e.g.* an unsupported option combination.

   ``utility``

      a tool called during processing returned an error code (*e.g.*, 'find' encountered an unreadable directory).

   ``version``

      revision control IDs of the file which we are trying to merge are not the same - line numbering and other information may be incorrect.

   Also see man
   :manpage:`lcovrc(5)`
   for a discussion of the 'max_message_count' parameter which can be used to control the number of warnings which are emitted before all subsequent messages are suppressed.  This can be used to reduce log file volume.

``--expect-message-count message_type:expr[,message_type:expr]``

   Give
   ``lcov``
   a constraint on the number of messages of one or more types which are expected to
   be produced during execution.  If the constraint is not true, then generate an
   error of type
   *"count"*
   (see above).

   See man
   :manpage:`genhtml(1)`
   for more details about the flag, as well as the
   *"expect_message_count"*
   section in man
   :manpage:`lcovrc(5)`
   for a description of the equivalent configuration file option.

``--keep-going``

   Do not stop if error occurs: attempt to generate a result, however flawed.

   This command line option corresponds to the
   *stop_on_error [0|1]*
   lcovrc option.  See man
   :manpage:`lcovrc(5)`
   for more details.

``--preserve``

   Preserve intermediate data files generated by various steps in the tool - *e.g.*, for debugging.  By default, these files are deleted.

``--filter`` *filters*

   Specify a list of coverpoint filters to apply to input data.
   See the genhtml man page for details.

``--demangle-cpp`` [*param*]

   Demangle C++ function names.  See the genhtml man page for details.

``-i``
``--initial``

   Capture initial zero coverage data - *i.e.*, from the compile-time '.gcno' data
   files.
   Also see the
   ``--all``
   flag, which tells the tool to capture both compile-time ('.gcno') and runtime
   ('.gcda') data at the same time.

   Run lcov with -c and this option on the directories containing .bb, .bbg
   or .gcno files before running any test case. The result is a "baseline"
   coverage data file that contains zero coverage for every instrumented line.
   Combine this data file (using lcov -a) with coverage data files captured
   after a test run to ensure that the percentage of total lines covered is
   correct even when not all source code files were loaded during the test.

   Recommended procedure when capturing data for a test case:

   1. create baseline coverage data file

      ::

         # lcov -c -i -d appdir -o app_base.info

   2. perform test

      ::

         # appdir/test

   3. create test coverage data file

      ::

         # lcov -c -d appdir -o app_test.info

   4. combine baseline and test coverage data

      ::

         # lcov -a app_base.info -a app_test.info -o app_total.info

   The above 4 steps are equivalent to

   ::

      # lcov --capture --all -o app_total.info -d appdir

   The combined compile- and runtime data will produce a different result than
   capturing runtime data alone if your project contains some compilation units
   which are not used in any of your testcase executables or shared libraries -
   that is, there are some '.gcno' (compile time) data files that do not
   have matching '.gcda' (runtime) data files.
   In that case, the runtime-only report will not contain any coverpoints from
   the unused files, whereas those coverpoints will appear (with all zero 'hit'
   counts) in the combined report.

   The
   ``--initial``
   flag is ignored except in
   ``--capture``
   mode.  The
   ``--all``
   flag is ignored if the
   ``--initial``
   flag is specified.

``-k`` *subdirectory*
``--kernel-directory`` *subdirectory*

   Capture kernel coverage data only from
   *subdirectory*.

   Use this option if you don't want to get coverage data for all of the
   kernel, but only for specific subdirectories. This option may be specified
   more than once.

   Note that you may need to specify the full path to the kernel subdirectory
   depending on the version of the kernel gcov support.

``-l`` *tracefile*
``--list`` *tracefile*

   List the contents of the
   *tracefile*.

   Only one of  -z, -c, -a, -e, -r, -l, --diff or --summary may be
   specified at a time.

``--list-full-path``
``--no-list-full-path``

   Specify whether to show full paths during list operation.

   Use --list-full-path to show full paths during list operation
   or --no-list-full-path to show shortened paths. Paths are
   ``shortened``
   by default.

``--no-markers``

   Use this option if you want to get coverage data without regard to exclusion
   markers in the source code file. See
   ``geninfo (1)``
   for details on exclusion markers.

``--no-recursion``

   Use this option if you want to get coverage data for the specified directory
   only without processing subdirectories.

``-o`` *tracefile*
``--output-file`` *tracefile*

   Write data to
   *tracefile*
   instead of stdout.

   Specify "-" as a filename to use the standard output.

   By convention, lcov-generated coverage data files are called "tracefiles" and
   should have the filename extension ".info".

``-v``
``--verbose``

   Increment informational message verbosity.  This is mainly used for script and/or flow debugging - *e.g.*, to figure out which data file are found, where.
   Also see the --quiet flag.

   Messages are sent to stdout unless there is no output file (*i.e.*, if the coverage data is written to stdout rather than to a file) and to stderr otherwise.

``-q``
``--quiet``

   Decrement informational message verbosity.

   Decreased verbosity will suppress 'progress' messages for example - while error and warning messages will continue to be printed.

``--debug``

   Increment 'debug messages' verbosity.  This is useful primarily to developers who want to enhance the lcov tool suite.

``--parallel`` [*integer*]
``-j`` [*integer*]

   Specify parallelism to use during processing (maximum number of forked child processes).  If the optional integer parallelism parameter is zero or is missing, then use to use up the number of cores on the machine.  Default is to use a single process (no parallelism).
   
   Also see the
   *memory, memory_percentage, max_fork_fails*
   and
   *fork_fail_timeout*
   entries in man
   :manpage:`lcovrc(5)`.
   A previously generated execution profile may help to enable better utilization
   and faster parallel execution.  See the
   *"--profile"*
   and
   *"--history"*
   sections of this man page.

``--memory`` *integer*

   Specify the maximum amount of memory to use during parallel processing, in Mb.  Effectively, the process will not fork() if this limit would be exceeded.  Default is 0 (zero) - which means that there is no limit.

   This option may be useful if the compute farm environment imposes strict limits on resource utilization such that the job will be killed if it tries to use too many parallel children - but the user does now know a priori what the permissible maximum is.  This option enables the tool to use maximum parallelism - up to the limit imposed by the memory restriction.

   The configuration file
   *memory_percentage*
   option provided another way to set the maximum memory consumption.
   See man
   :manpage:`lcovrc(5)`
   for details.

``--rc`` *keyword*\ =\ *value*

   Override a configuration directive.

   Use this option to specify a
   *keyword*\ =\ *value*
   statement which overrides the corresponding configuration statement in
   the lcovrc configuration file. You can specify this option more than once
   to override multiple configuration statements.
   See man
   :manpage:`lcovrc(5)`
   for a list of available keywords and their meaning.

``-r`` *tracefile pattern*
``--remove`` *tracefile pattern*

   Remove data from
   *tracefile*.

   Use this switch if you want to remove coverage data for a particular
   set of files from a tracefile. Additional command line parameters will be
   interpreted as shell wildcard patterns (note that they may need to be
   escaped accordingly to prevent the shell from expanding them first).
   Every file entry in
   *tracefile*
   which matches at least one of those patterns will be removed.

   Note: The pattern must be specified to match the
   ``absolute``
   path of each source file.

   The result of the remove operation will be written to stdout or the tracefile
   specified with -o.

   Only one of  -z, -c, -a, -e, -r, -l, --diff or --summary may be
   specified at a time.

``--summary`` *tracefile*

   Show summary coverage information for the specified tracefile.

   Note that you may specify this option more than once.

   Only one of  -z, -c, -a, -e, -r, -l, --diff or --summary may be
   specified at a time.

``--fail-under-branches`` *percentage*

   Use this option to tell lcov to exit with a status of 1 if the total
   branch coverage is less than
   *percentage*.

``--fail-under-lines`` *percentage*

   Use this option to tell lcov to exit with a status of 1 if the total
   line coverage is less than
   *percentage*.

``-t`` *testname*
``--test-name`` *testname*

   Specify test name to be stored in the tracefile.

   This name identifies a coverage data set when more than one data set is merged
   into a combined tracefile (see option -a).

   Valid test names can consist of letters, decimal digits and the underscore
   character ("_").

``--to-package`` *package*

   Store .da files for later processing.

   Use this option if you have separate machines for build and test and
   want to perform the .info file creation on the build machine. To do this,
   follow these steps:

   On the test machine:

      - run the test
      - run lcov -c [-d directory] --to-package *file*
      - copy *file* to the build machine

   On the build machine:

      - run lcov -c --from-package *file* [-o and other options]

   This works for both kernel and user space coverage data. Note that you might
   have to specify the path to the build directory using -b with
   either --to-package or --from-package. Note also that the package data
   must be converted to a .info file before recompiling the program or it will
   become invalid.

``--version``

   Print version number, then exit.

``-z``
``--zerocounters``

   Reset all execution counts to zero.

   By default tries to reset kernel execution counts. Use the --directory
   option to reset all counters of a user space program.

   Only one of  -z, -c, -a, -e, -r, -l, --diff or --summary may be
   specified at a time.

``--tempdir`` *dirname*

   Write temporary and intermediate data to indicated directory.  Default is "/tmp".

FILES
-----

*/etc/lcovrc*

   The system-wide configuration file.

*~/.lcovrc*

   The per-user configuration file.

AUTHOR
------

Peter Oberparleiter <Peter.Oberparleiter@de.ibm.com>

Henry Cox <henry.cox@mediatek.com>

   Filtering, error management, parallel execution sections.

SEE ALSO
--------

:manpage:`lcovrc(5)`,
:manpage:`genhtml(1)`,
:manpage:`geninfo(1)`,
:manpage:`gendesc(1)`,
:manpage:`gcov(1)`
:manpage:`llvm2lcov(1)`
:manpage:`py2lcov(1)`
:manpage:`perl2lcov(1)`

*https://github.com/linux-test-project/lcov*
