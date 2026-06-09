============================================
geninfo - translate GCOV data to LCOV format
============================================

NAME
----

geninfo
  Generate tracefiles from GCOV coverage data files

SYNOPSIS
--------

::

  geninfo
           [-h | --help]
           [--version]
           [-q | --quiet]
           [-v | --verbose]
           [--debug]
           [--comment *comment-string*]
           [-i | --initial]
           [--all]
           [-t | --test-name *test-name*]
           [-o | --output-filename *filename*]
           [-f | --follow]
           [-b | --base-directory *directory*]
           [--build-directory *directory*]
           [--branch-coverage]
           [--mcdc-coverage]
           [--checksum]
           [--no-checksum]
           [--compat-libtool]
           [--no-compat-libtool]
           [--gcov-tool *tool*]
           [--parallel | -j [*integer*]]
           [--large-file *regexp*]
           [--memory *integer_num_Mb*]
           [--msg-log [*log_file_name*]]
           [--ignore-errors *errors*]
           [--expect-message-count *message_type* = *expr* [,*message_type* = *expr* ..]]
           [--keep-going]
           [--preserve]
           [--filter *type*]
           [--demangle-cpp [param]]
           [--no-recursion]
           [--external]
           [--no-external]
           [--sort-input]
           [--config-file *config-file*]
           [--no-markers]
           [--profile [*profile-file*]]
           [--history-script *callback*]
           [--compat *mode* = on|off|auto]
           [--rc *keyword* = *value*]
           [--include *glob_pattern*]
           [--exclude *glob_pattern*]
           [--erase-functions *regexp_pattern*]
           [--substitute *regexp_pattern*]
           [--omit-lines *regexp_pattern*]
           [--fail-under-branches *percentage*]
           [--fail-under-lines *percentage*]
           [--forget-test-names]
           [--context-script *script_file*]
           [--criteria-script *script_file*]
           [--resolve-script *script_file*]
           [--version-script *script_file*]
           [--unreachable-script *module_file*]
           [--tempdir *dirname*]
           *directory*

DESCRIPTION
-----------

Use ``geninfo`` to create |ToolName| tracefiles from GCC and LLVM/Clang coverage data files (see ``--gcov-tool`` for considerations when working with LLVM). You can use ``genhtml`` to create an HTML report from a tracefile.

Note that ``geninfo`` is called by ``lcov --capture``, so there is typically no need to call it directly.

Unless the ``--output-filename`` option is specified ``geninfo`` writes its output to one file with .info filename extension per input file.

Note also that the current user needs write access to both *directory* as well as to the original source code location. This is necessary because some temporary files have to be created there during the conversion process.

By default, ``geninfo`` collects line and function coverage data. Neither branch nor MC/DC data is collected by default; you can use the ``--branch-coverage`` and ``--mcdc-coverage`` command line options to enable them, or you can permanently enable them by adding ``branch_coverage = 1`` and/or ``mcdc_coverage = 1`` to your personal, group, or site lcov configuration file. See :manpage:`lcovrc(5)` for details.

File types
~~~~~~~~~~

A ``tracefile`` is a coverage data file in the format used by all |ToolName| tools such as ``geninfo``, ``lcov``, and ``genhtml``. By convention, tracefiles have a .info filename extension. See "Tracefile format" below for a description of the file format.

A ``.gcda file`` is a compiler-specific file containing run-time coverage data. It is created and updated when a program compiled with GCC/LLVM's ``--coverage`` option is run to completion. ``geninfo`` reads .gcda files in its default mode of operation. Note: earlier compiler versions used the .da filename extension for this file type.

A ``.gcno file`` is a compiler-specific file containing static, compile-time coverage data. It is created when source code is compiled with GCC/LLVM's ``--coverage`` option. ``geninfo`` reads .gcno files when option ``--initial`` is specified. Note: earlier compiler versions used .bb and .bbg filename extensions for this file type.

A ``.gcov file`` is a textual or JSON representation of the data found in .gcda and .gcno files. It is created by the ``gcov`` tools that is part of GCC (see ``--gcov-tool`` for LLVM considerations). There are multiple gcov file format versions, including textual, intermediate, and JSON format. ``geninfo`` internally uses ``gcov`` to extract coverage data from .gcda and .gcno files using the best supported gcov file format.

See the ``gcov`` man page for more information on .gcda, .gcno and .gcov output formats.

Exclusion markers
~~~~~~~~~~~~~~~~~

To exclude specific lines of code from a tracefile, you can add exclusion markers to the source code. Similarly, you can mark specific regions of code as "unreachable". An "unreachable" error message is generated if any coverpoints in unreachable regions are executed (*i.e.,* have non-zero hit counts. See the *retain_unreachable_coverpoints_if_executed* section in :manpage:`lcovrc(1)` for a description of the actions taken in this case.

Additionally you can exclude specific branches or MC/DC expressions without excluding the involved lines from line and function coverage.

Exclusion markers are keywords which can for example be added in the form of a comment. See :manpage:`lcovrc(5)` how to override the exclusion keywords (*e.g.,* to reuse markers inserted for other tools or to generate reports with different sets of excluded regions).

The following markers are recognized by geninfo:

``LCOV_EXCL_LINE``
    Lines containing this marker will be excluded.

``LCOV_EXCL_START``
    Marks the beginning of an excluded section. The current line is part of this section.

``LCOV_EXCL_STOP``
    Marks the end of an excluded section. The current line not part of this section.

``LCOV_UNREACHABLE_LINE``
    If the marked line is 'hit', then generate an error: we believe the marked code is unreachable and so there is a bug in the code, the placement of the directive, or both. Lines containing this marker will be excluded from reporting. Apart from error reporting, this directive is equivalent to *LCOV_EXCL_LINE.*

``LCOV_UNREACHABLE_START``
    Marks the beginning of an unreachable section of code. The current line in part of this region. As described in the *LCOV_UNREACHABLE_LINE* section, above: an error is generated if any code in the region is hit, but the code is excluded from reporting.

``LCOV_UNREACHABLE_STOP``
    Marks the end of the region of unreachable code. The current line not part of this section.

``LCOV_EXCL_BR_LINE``
    Lines containing this marker will be excluded from branch coverage.

``LCOV_EXCL_BR_START``
    Marks the beginning of a section which is excluded from branch coverage. The current line is part of this section.

``LCOV_EXCL_BR_STOP``
    Marks the end of a section which is excluded from branch coverage. The current line not part of this section.

``LCOV_EXCL_EXCEPTION_BR_LINE``
    Lines containing this marker will be excluded from exception branch coverage: Exception branches will be ignored, but non-exception branches will not be affected.

``LCOV_EXCL_EXCEPTION_BR_START``
    Marks the beginning of a section which is excluded from exception branch coverage. The current line is part of this section.

``LCOV_EXCL_EXCEPTION_BR_STOP``
    Marks the end of a section which is excluded from exception branch coverage. The current line not part of this section.

In addition, ``geninfo`` also supports the *"--unreachable-script"* option. This provides a mechanism to exclude particular branch expressions and/or MC/DC conditions from coverage reports. A simple sample callback can be found in:

    ``bin``/unreach.pm.

This sample callback adds support for branch-specific and condition-specific exclusion, specified by end-of-line annotations in the source code:

``LCOV_EXCLUDE_BRANCH  (expressionId[,blockId])+``
    One or more space-separated branch exclusions may specified.

    ``expressionId``:
        decimal integer which specifies which branch to exclude. An error is generated if the index is invalid

    ``blockId``
        decimal integer which specified the block index which contains the excluded expression. An error is generated if the block index is invalid. If there is only one branch block at this location, then the block ID does not need to be specified

``LCOV_UNREACHABLE_COND ([groupSize,]conditionId(t|f))+``
    One or more space-separated MC/DC exclusions may specified.

    ``groupSize``
        decimal integer which specified the group which contains the excluded condition. An error is generated if the groupSize is invalid. If there is only one MC/DC group at this location, then the groupSize does not need to be specified.

    ``conditionId``
        decimal integer which specifies which condition to exclude. An error is generated if the index is invalid

    ``sense``
        't' or 'f': the value of the condition which is unreachable

For example, the line:

::

    code // LCOV_EXCLUDE_BRANCH 0,1 3 LCOV_EXCLUDE_CONDITION 0f

will exclude branch expressions 1 and 3 from block 0 (or generate an error if there is more than one branch block on this line), and the 'false' sense of condition 0 (or generate an error if there is more than one MC/DC group on this line).

One way to determine the branch and/or condition ID in order to exclude them is to generate an HTML report without exclusions then hover the mouse over the colorized branch/condition region and read the IDs from the tooltip popup. Another way is to simply read the BRDA/MCDC entries in coverage data file.

See the comment at the top of the sample script for more details.

OPTIONS
-------

In general, (almost) all ``geninfo`` options can also be specified in your personal, group, project, or site configuration file - see the *--config-file* section, below, and :manpage:`lcovrc(5)` for details.

``-b``, ``--base-directory`` *directory*
   Use *directory* as base directory for relative paths.

    Use this option to specify the base directory of a build-environment when geninfo produces error messages like:

    ::

        ERROR: could not read source file /home/user/project/subdir1/subdir2/subdir1/subdir2/file.c

    In this example, use /home/user/project as base directory.

    This option is required when using geninfo on projects built with libtool or similar build environments that work with a base directory, *i.e.* environments, where the current working directory when invoking the compiler is not the same directory in which the source code file is located.

    Note that this option will not work in environments where multiple base directories are used. In that case use configuration file setting ``geninfo_auto_base=1`` (see :manpage:`lcovrc(5)`).

``--build-directory`` *build_dir*
    Search for .gcno data files from *build_dir* rather finding them only adjacent to the corresponding .o and/or .gcda file.

    By default, geninfo expects to find the .gcno and .gcda files (compile- and run-time data, respectively) in the same directory.

    When this option is used:

    ::

        geninfo path1 --build-directory path2 ...

    then geninfo will look for .gcno file

    ::

        path2/relative/path/to/da_base.gcno

    when it finds .gcda file

    ::

        path1/relative/path/to/da_base.gcda.

    Use this option when you have used the *GCOV_PREFIX* environment variable to direct the gcc or llvm runtime environment to write coverage data files to somewhere other than the directory where the code was originally compiled. See :manpage:`gcc(1)` and/or search for *GCOV_PREFIX* and *GCOV_PREFIX_STRIP*.

    This option can be used several times to specify multiple alternate directories to look for .gcno files. This may be useful if your application uses code which is compiled in many separate locations - for example, common libraries that are shared between teams.

``--source-directory`` *dirname*
    Add 'dirname' to the list of places to look for source files.

    For relative source file paths found in the gcov data - possibly after substitutions have been applied, ``geninfo`` will first look for the path from 'cwd' (where genhtml was invoked) and then from each alternate directory name in the order specified. The first location matching location is used.

    This option can be specified multiple times, to add more directories to the source search path.

``--branch-coverage``
    Collect and retain branch coverage data.

    This is equivalent to using the option "--rc branch_coverage=1"; the option was added to better match the genhtml interface.

``--mcdc-coverage``
    Collect and retain MC/DC data.

    This is equivalent to using the option "--rc mcdc_coverage=1". MC/DC coverage capture is supported for GCC versions 14.2 and higher, or LLVM versions 18.1 and higher.

    See *llvm2lcov --help* for details on MC/DC data capture in LLVM.

    See the MC/DC section of :manpage:`genhtml(1)` for more details.

``--checksum``, ``--no-checksum``
   Specify whether to generate checksum data when writing tracefiles.

    Use ``--checksum`` to enable checksum generation or ``--no-checksum`` to disable it. Checksum generation is ``disabled`` by default.

    When checksum generation is enabled, a checksum will be generated for each source code line and stored along with the coverage data. This checksum will be used to prevent attempts to combine coverage data from different source code versions.

    If you don't work with different source code versions, disable this option to speed up coverage data processing and to reduce the size of tracefiles.

    Note that this options is somewhat subsumed by the ``--version-script`` option - which does something similar, but at the 'whole file' level.

``--compat`` *mode* = *value* [,*mode* = *value*,...]
    Set compatibility mode.

    Use ``--compat`` to specify that geninfo should enable one or more compatibility modes when capturing coverage data. You can provide a comma-separated list of mode=value pairs to specify the values for multiple modes.

    Valid *values* are:

    ``on``
        Enable compatibility mode.

    ``off``
        Disable compatibility mode.

    ``auto``
        Apply auto-detection to determine if compatibility mode is required. Note that auto-detection is not available for all compatibility modes.

    If no value is specified, 'on' is assumed as default value.

    Valid *modes* are:

    ``libtool``
        Enable this mode if you are capturing coverage data for a project that was built using the libtool mechanism. See also ``--compat-libtool``.

        The default value for this setting is 'on'.

    ``hammer``
        Enable this mode if you are capturing coverage data for a project that was built using a version of GCC 3.3 that contains a modification (hammer patch) of later GCC versions. You can identify a modified GCC 3.3 by checking the build directory of your project for files ending in the extension .bbg. Unmodified versions of GCC 3.3 name these files .bb.

        The default value for this setting is 'auto'.

    ``split_crc``
        Enable this mode if you are capturing coverage data for a project that was built using a version of GCC 4.6 that contains a modification (split function checksums) of later GCC versions. Typical error messages when running geninfo on coverage data produced by such GCC versions are 'out of memory' and 'reached unexpected end of file'.

        The default value for this setting is 'auto'.

``--compat-libtool``, ``--no-compat-libtool``
   Specify whether to enable libtool compatibility mode.

    Use ``--compat-libtool`` to enable libtool compatibility mode or ``--no-compat-libtool`` to disable it. The libtool compatibility mode is ``enabled`` by default.

    When libtool compatibility mode is enabled, geninfo will assume that the source code relating to a .gcda file located in a directory named ".libs" can be found in its parent directory.

    If you have directories named ".libs" in your build environment but don't use libtool, disable this option to prevent problems when capturing coverage data.

``--config-file`` *config-file*
    Specify a configuration file to use. See :manpage:`lcovrc(5)` for details of the file format and options. Also see the *config_file* entry in the same man page for details on how to include one config file into another.

    When this option is specified, neither the system-wide configuration file /etc/lcovrc, nor the per-user configuration file ~/.lcovrc is read.

    This option may be useful when there is a need to run several instances of ``geninfo`` with different configuration file options in parallel.

    Note that this option must be specified in full - abbreviations are not supported.

``--profile`` [*profile-data-file*]
    Tell the tool to keep track of performance and other configuration data. If the optional *profile-data-file* is not specified, then the profile data is written to a file named with the same basename as the *--output-filename*, with suffix *".json"* appended.

    Profile data is useful if you are trying to optimize the ``geninfo`` implementation (see ``$LCOV_ROOT/share/lcov/support-scripts/spreadsheet.py``), and can also enable faster 'geninfo --parallel' execution (see the "--history-script" section of this man page).

``--history-script`` *callback*
    Tell the tool to use performance data from a prior job to predict resource usage by the current job. This may allow better segmentation to enable more balanced workloads between parallel threads - thus improving wall clock execution time.

    A common source for the performance history is the *previous-profile-data-file* generated by the *"--profile"* argument.

    See a sample callback implementation in ``$LCOV_ROOT/share/lcov/support-scripts/history.pm`` and its use in ``$LCOV_ROOT/share/lcov/example`` in the installed release (or ``.../example`` and ``.../scripts/history.pm`` in the source repository).

    See :manpage:`genhtml(1)` for more details.

``--external``, ``--no-external``
   Specify whether to capture coverage data for external source files.

    External source files are files which are not located in one of the directories specified by *--directory* or *--base-directory.* Use *--external* to include coverpoints in external source files while capturing coverage data or *--no-external* to exclude them. If your *--directory* or *--base-directory* path contains a soft link, then actual target directory is not considered to be "internal" unless the *--follow* option is used.

    The *--no-external* option is somewhat of a blunt instrument; the *--exclude* and *--include* options provide finer grained control over which coverage data is and is not included if your project structure is complex and/or *--no-external* does not do what you want.

    Data for external source files is ``included`` by default.

``-f``, ``--follow``
   Follow links when searching .gcda files, as well as to decide whether a particular (symbolically linked) source directory is "internal" to the project or not - see the *--no-external* option, above, for more information. The *--follow* command line option is equivalent to the *geninfo_follow_symlinks* config file option. See :manpage:`lcovrc(5)` for more information.

``--sort-input``
    Specify whether to sort file names before capture and/or aggregation. Sorting reduces certain types of processing order-dependent output differences. See the ``sort_input`` section in :manpage:`lcovrc(5)`.

``--gcov-tool`` *tool*
    Specify the location of the gcov tool.

    If the ``--gcov-tool`` option is used multiple times, then the arguments are concatenated when the callback is executed - similar to how the gcc ``-Xlinker`` parameter works. This provides a possibly easier way to pass arguments to your tool, without requiring a wrapper script. In that case, your callback will be executed as: *tool-0 'tool-1; ... 'filename'*'. Note that the second and subsequent arguments are quoted when passed to the shell, in order to handle parameters which contain spaces.

    The ``--gcov-tool`` argument may be a *split_char* separated string - see ``man(4) lcovrc``.

    A common use for this option is to enable LLVM:

    ::

        geninfo --gcov-tool llvm-cov --gcov-tool gcov ...
        geninfo --gcov-tool llvm-cov,gcov ...

    Note: 'llvm-cov gcov da_file_name' will generate output in gcov-compatible format as required by lcov.

    If not specified, 'gcov' is used by default.

``-h``, ``--help``
   Print a short help text, then exit.

``--include`` *pattern*
    Include source files matching *pattern*.

    Use this switch if you want to include coverage data for only a particular set of source files matching any of the given patterns. Multiple patterns can be specified by using multiple ``--include`` command line switches. The *patterns* will be interpreted as shell wildcard patterns (note that they may need to be escaped accordingly to prevent the shell from expanding them first).

    See the lcov man page for details.

``--exclude`` *pattern*
    Exclude source files matching *pattern*.

    Use this switch if you want to exclude coverage data from a particular set of source files matching any of the given patterns. Multiple patterns can be specified by using multiple ``--exclude`` command line switches. The *patterns* will be interpreted as shell wildcard patterns (note that they may need to be escaped accordingly to prevent the shell from expanding them first). Note: The pattern must be specified to match the ``absolute`` path of each source file.

    Can be combined with the ``--include`` command line switch. If a given file matches both the include pattern and the exclude pattern, the exclude pattern will take precedence.

    See the lcov man page for details.

``--erase-functions`` *regexp*
    Exclude coverage data from lines which fall within a function whose name matches the supplied regexp. Note that this is a mangled or demangled name, depending on whether the --demangle-cpp option is used or not.

    Note that this option requires that you use a gcc version which is new enough to support function begin/end line reports or that you configure the tool to derive the required data - see the ``derive_function_end_line`` discussion in the ``lcovrc`` man page.

``--substitute`` *regexp_pattern*
    Apply Perl regexp *regexp_pattern* to source file names found during processing. This is useful when the path name reported by gcov does not match your source layout and the file is not found. See the lcov man page for more details.

``--omit-lines`` *regexp*
    Exclude coverage data from lines whose content matches *regexp*.

    Use this switch if you want to exclude line, branch, and MC/DC coverage data for some particular constructs in your code (*e.g.*, some complicated macro). See the lcov man page for details.

``--forget-test-names``
    If non-zero, ignore testcase names in tracefile - *i.e.,* treat all coverage data as if it came from the same testcase. This may improve performance and reduce memory consumption if user does not need per-testcase coverage summary in coverage reports.

    This option can also be configured permanently using the configuration file option *forget_testcase_names*.

``--msg-log`` [*log_file_name*]
    Specify location to store error and warning messages (in addition to writing to STDERR). If *log_file_name* is not specified, then default location is used.

``--ignore-errors`` *errors*
    Specify a list of errors after which to continue processing.

    Use this option to specify a list of one or more classes of errors after which ``geninfo`` should continue processing instead of aborting. Note that the tool will generate a warning (rather than a fatal error) unless you ignore the error two (or more) times:

    ::

        geninfo ... --ignore-errors unused,unused

    *errors* can be a comma-separated list of the following keywords:

    ``branch``
        branch ID (2nd field in the .info file 'BRDA' entry) does not follow expected integer sequence.

    ``callback``
        Version script error.

    ``child``
        child process returned non-zero exit code during *--parallel* execution. This typically indicates that the child encountered an error: see the log file immediately above this message. In contrast: the ``parallel`` error indicates an unexpected/unhandled exception in the child process - not a 'typical' lcov error.

    ``corrupt``
        corrupt/unreadable file found.

    ``count``
        An excessive number of messages of some class have been reported - subsequent messages of that type will be suppressed. The limit can be controlled by the 'max_message_count' variable. See the lcovrc man page.

    ``deprecated``
        You are using a deprecated option. This option will be removed in an upcoming release - so you should change your scripts now.

    ``empty``
        the .info data file is empty (*e.g.*, because all the code was 'removed' or excluded.

    ``excessive``
        your coverage data contains a suspiciously large 'hit' count which is unlikely to be correct - possibly indicating a bug in your toolchain.

        See the *excessive_count_threshold* section in :manpage:`lcovrc(5)` for details.

    ``fork``
        Unable to create child process during *--parallel* execution.
        If the message is ignored (*--ignore-errors fork*), then genhtml will wait a brief period and then retry the failed execution.
        If you see continued errors, either turn off or reduce parallelism, set a memory limit, or find a larger server to run the task.

    ``format``
        Unexpected syntax or value found in .info file - for example, negative number or zero line number encountered.

    ``gcov``
        the gcov tool returned with a non-zero return code.

    ``graph``
        the graph file could not be found or is corrupted.

    ``inconsistent``
        your coverage data is internally inconsistent: it makes two or more mutually exclusive claims. For example, some expression is marked as both an exception branch and not an exception branch. (See :manpage:`genhtml(1)` for more details.

    ``internal``
        internal tool issue detected. Please report this bug along with a testcase.

    ``mismatch``
        Incorrect information found in coverage data and/or source code - for example, the source code contains overlapping exclusion directives.

    ``missing``
        File does not exist or is not readable.

    ``negative``
        negative 'hit' count found.

        Note that negative counts may be caused by a known GCC bug - see

        ::

            https://gcc.gnu.org/bugzilla/show_bug.cgi?id=68080

        and try compiling with "-fprofile-update=atomic". You will need to recompile, re-run your tests, and re-capture coverage data.

    ``package``
        a required perl package is not installed on your system. In some cases, it is possible to ignore this message and continue - however, certain features will be disabled in that case.

    ``parallel``
        various types of errors related to parallelism - *i.e.,* a child process died due to an error. The corresponding error message appears in the log file immediately before the *parallel* error.

        If you see an error related to parallel execution that seems invalid, it may be a good idea to remove the --parallel flag and try again. If removing the flag leads to a different result, please report the issue (along with a testcase) so that the tool can be fixed.

    ``parent``
        the parent process exited while child was active during *--parallel* execution. This happens when the parent has encountered a fatal error - *e.g.* an error in some other child which was not ignored. This child cannot continue working without its parent - and so will exit.

    ``path``
        some file paths were not resolved - *e.g.*, .gcno file corresponding to some .gcda was not found see *--build-directory* option for additional information.

    ``range``
        Coverage data refers to a line number which is larger than the number of lines in the source file. This can be caused by a version mismatch or by an issue in the *gcov* data.

    ``source``
        the source code file for a data set could not be found.

    ``unreachable``
        a coverpoint (line, branch, function, or MC/DC) within an "unreachable" region is executed (hit); either the code, directive placement, or both are wrong. If the error is ignored, the offending coverpoint is retained (not excluded) or not, depending on the value of the *retain_unreachable_coverpoints_if_executed* configuration parameter. See :manpage:`lcovrc(5)` and the *"Exclusion markers"* section, above.

    ``unsupported``
        the requested feature is not supported for this tool configuration. For example, function begin/end line range exclusions use some GCOV features that are not available in older GCC releases.

    ``unused``
        the include/exclude/erase/omit/substitute pattern did not match any file pathnames.

    ``usage``
        unsupported usage detected - *e.g.* an unsupported option combination.

    ``utility``
        a tool called during processing returned an error code (*e.g.*, 'find' encountered an unreadable directory).

    ``version``
        revision control IDs of the file which we are trying to merge are not the same - line numbering and other information may be incorrect.

    Also see the *--ignore-errors* section in :manpage:`genhtml(1)`. The description there may be more complete and/or more fully explained.

    See :manpage:`lcovrc(5)` for a discussion of the 'max_message_count' parameter which can be used to control the number of warnings which are emitted before all subsequent messages are suppressed. This can be used to reduce log file volume.

``--expect-message-count`` *message_type* = *expr* [,*message_type* = *expr*]
    Give ``geninfo`` a constraint on the number of messages of one or more types which are expected to be produced during execution. If the constraint is not true, then generate an error of type *"count"* (see above).

    See :manpage:`genhtml(1)` for more details about the flag, as well as the *"expect_message_count"* section in :manpage:`lcovrc(5)` for a description of the equivalent configuration file option.

``--keep-going``
    Do not stop if error occurs: attempt to generate a result, however flawed.

    This command line option corresponds to the *stop_on_error [0|1]* lcovrc option. See :manpage:`lcovrc(5)` for more details.

``--fail-under-lines`` *percentage*
    Use this option to tell geninfo to exit with a status of 1 if the total line coverage is less than *percentage.* See :manpage:`lcov(1)` for more details.

``--preserve``
    Preserve intermediate data files (*e.g.*, for debugging).

    By default, intermediate files are deleted.

``--filter`` *filters*
    Specify a list of coverpoint filters to apply to input data. See the genhtml man page for details.

``--demangle-cpp`` [param]
    Demangle C++ method and function names in captured output. See the genhtml man page for details.

``-i``, ``--initial``
   Capture initial zero coverage data.

    Run geninfo with this option on the directories containing .bb, .bbg or .gcno files before running any test case. The result is a "baseline" coverage data file that contains zero coverage for every instrumented line and function. Combine this data file (using lcov -a) with coverage data files captured after a test run to ensure that the percentage of total lines covered is correct even when not all object code files were loaded during the test. Also see the *--all* flag, below.

    Note: the ``--initial`` option is not supported for gcc versions less than 6, and does not generate branch coverage information for gcc versions less than 8.

``--all``
    Capture coverage data from both compile time (.gcno) data files which do not have corresponding runtime (.gcda) data files, as well as from those that *do* have corresponding runtime data. There will be no runtime data unless some executable which links the corresponding object file has run to completion.

    Note that the execution count of coverpoints found only in files which do not have any runtime data will be zero.

    This flag is ignored if the *--initial* flag is set.

    Using the ``--all`` flag is equivalent to executing both *geninfo --initial ...* and *geninfo ...* and merging the result.

    Also see the *geninfo_capture_all* entry in ``man(5) lcovrc``.

``--no-markers``
    Unless the *--no-markers* option is used, ``geninfo`` will apply both *region* and *branch_region* filters to the captured coverage data. Use this option if you want to get coverage data without regard to exclusion markers in the source code file.

    If any *--filter* options are applied, then the default region filters are not used.

    *--no-markers* should not be specified along with *--filter*.

``--no-recursion``
    Use this option if you want to get coverage data for the specified directory only without processing subdirectories.

``-o``, ``--output-filename`` *output-filename*
   Write all data to *output-filename*.

    If you want to have all data written to a single file (for easier handling), use this option to specify the respective filename. By default, one tracefile will be created for each processed .gcda file.

``--context-script`` *script*
    Use *script* to collect additional tool execution context information - to aid in infrastructure debugging and/or tracking.

    See the genhtml man page for more details on the context script.

``--criteria-script`` *script*
    Use *script* to test for coverage acceptance criteria.

    See the genhtml man page for more details on the criteria script. Note that geninfo does not keep track of date and owner information (see the *--annotate-script* entry in the genhtml man page) - so this information is not passed to the geninfo callback.

``--resolve-script`` *script*
    Use *script* to find the file path for some source or GCNO file which appears in an input data file if the file is not found after applying *--substitute* patterns and searching the *--source-directory* or *--build-directory* list.

    This option is equivalent to the ``resolve_script`` config file option. In addition, the *geninfo_follow_path_links* config file option can be used to resolve source paths to their actual target.

    See :manpage:`lcovrc(5)` for details.

``--version-script`` *script*
    Use *script* to get a source file's version ID from revision control when extracting data. The ID is used for error checking when merging .info files.

    See the genhtml man page for more details on the version script.

``--unreachable-script`` *module*
    Use *module* to decide whether particular branch expressions and/or MC/DC conditions should be removed from the coverage report. This option is equivalent to the ``unreachable_script`` config file option. See :manpage:`lcovrc(5)` for details.

    Note that *"module"* is required to be a Perl module.

    See the genhtml man page and the *"Exclusion markers"* section, above, for more information.

``-v``, ``--verbose``
   Increment informational message verbosity. This is mainly used for script and/or flow debugging - *e.g.*, to figure out which data file are found, where. Also see the ``--quiet`` flag.

    Messages are sent to stdout unless there is no output file (*i.e.*, if the coverage data is written to stdout rather than to a file) and to stderr otherwise.

``-q``, ``--quiet``
   Decrement informational message verbosity.

    Decreased verbosity will suppress 'progress' messages for example - while error and warning messages will continue to be printed.

``--debug``
    Increment 'debug messages' verbosity. This is useful primarily to developers who want to enhance the lcov tool suite.

``--comment`` *comment_string*
    Append *comment_string* to list of comments emitted into output result file. This option may be specified multiple times. Comments are printed at the top of the file, in the order they were specified.

    Comments can be useful to document the conditions under which the trace file was generated: host, date, environment, *etc.*

``--parallel`` [*integer*], ``-j`` [*integer*]
   Specify parallelism to use during processing (maximum number of forked child processes). If the optional integer parallelism parameter is zero or is missing, then use to use up the number of cores on the machine. Default is to use a single process (no parallelism).

    The *--large-file* option described below may be necessary to enable parallelism to succeed in the presence of data files which consume excessive memory in ``gcov``.

    Also see the *memory, memory_percentage, max_fork_fails, fork_fail_timeout, geninfo_chunk_size* and *geninfo_interval_update* entries in :manpage:`lcovrc(5)` for a description of some options which may aid in parameter tuning and performance optimization. A previously generated execution profile may help to enable better utilization and faster parallel execution. See the *"--profile"* and *"--history-script"* sections of this man page.

``--large-file`` *regexp*
    GCDA files whose name matches a *--large-file* regexp are processed serially - not in parallel with other files - so that their ``gcov`` process can use all available system memory.

    Use this option is you see errors related to memory allocation from gcov.

    This feature is exactly as if you had moved the matching GCDA files to another location and processed them serially, then processed remaining GDCA files in parallel and merged the results.

    This option may be used multiple times to specify more than one regexp.

``--memory`` *integer*
    Specify the maximum amount of memory to use during parallel processing, in Mb. Effectively, the process will not fork() if this limit would be exceeded. Default is 0 (zero) - which means that there is no limit.

    This option may be useful if the compute farm environment imposes strict limits on resource utilization such that the job will be killed if it tries to use too many parallel children - but the user does not know a priori what the permissible maximum is. This option enables the tool to use maximum parallelism - up to the limit imposed by the memory restriction.

    The configuration file *memory_percentage* option provided another way to set the maximum memory consumption. See :manpage:`lcovrc(5)` for details.

``--rc`` *keyword* = *value*
    Override a configuration directive.

    Use this option to specify a *keyword = value* statement which overrides the corresponding configuration statement in the lcovrc configuration file. You can specify this option more than once to override multiple configuration statements. See :manpage:`lcovrc(5)` for a list of available keywords and their meaning.

``-t``, ``--test-name`` *testname*
   Use test case name *testname* for resulting data. Valid test case names can consist of letters, decimal digits and the underscore character ('_').

    This proves useful when data from several test cases is merged (*i.e.* by simply concatenating the respective tracefiles) in which case a test name can be used to differentiate between data from each test case.

``--version``
    Print version number, then exit.

``--tempdir`` *dirname*
    Write temporary and intermediate data to indicated directory. Default is "/tmp".

TRACEFILE FORMAT
----------------

Following is a quick description of the tracefile format as used by ``genhtml``, ``geninfo`` and ``lcov``.

A tracefile is made up of several human-readable lines of text, divided into sections. If the ``---comment comment_string`` option is supplied, then:

::

    #comment_string

will appear at the top of the tracefile. There is no space before or after the *#* character.

If available, a tracefile begins with the *testname* which is stored in the following format:

::

    TN:<test name>

For each source file referenced in the .gcda file, there is a section containing filename and coverage data:

::

    SF:<path to the source file>

An optional source code version ID follows:

::

    VER:<version ID>

If present, the version ID is compared before file entries are merged (see ``lcov --add-tracefile``), and before the 'source detail' view is generated by genhtml. See the ``--version-script callback_script`` documentation and the sample usage in the lcov regression test examples.

Function coverage data follows. Note that the format of the function coverage data has changed from LCOV 2.2 onward. The tool continues to be able to read the old format but now writes only the new format. This change was made so that ``function`` filter outcome is persistent in the generated tracefile.

Functions and their aliases are recorded contiguously:

First, the leader:

::

    FNL:<index>,<line number of function start>[,line number of function end>]

Then the aliases of the function; there will be at least one alias. All aliases of a particular function share the same index.

::

    FNA:<index>,<execution count>,<name>

The now-obsolete function data format is:

::

    FN:<line number of function start>,[<line number of function end>,]<function name>

The 'end' line number is optional, and is generated only if the compiler/toolchain version is recent enough to generate the data (*e.g.*, gcc 9 or newer). This data is used to support the ``--erase-functions`` and ``--show-proportions`` options. If the function end line data is not available, then these features will not work.

Next, there is a list of execution counts for each instrumented function:

::

    FNDA:<execution count>,<function name>

This list is followed by two lines containing the number of functions found and hit:

::

    FNF:<number of functions found>
    FNH:<number of function hit>

Note that, as of LCOV 2.2, these numbers count function groups - not the individual aliases.

Branch coverage information is stored one line per branch:

::

    BRDA:<line_number>,[<exception>][<fallthrough][<unreachable>]<block>,<branch>,<taken>

*<line_number>*
    is the line number where the branch is found - and is expected to be a non-zero integer.

*<block>* and *<branch>*
    serve to uniquely define a particular edge in the expression tree of a particular conditional found on the associated line.

    Within a particular line, *<block>* is an integer numbered from zero with no gaps. For some languages and some coding styles, there will only be one block (index value zero) on any particular line.

    *<branch>* is a string which serves to uniquely identify a particular edge. For some languages and tools - *e.g.*, C/C++ code compiled with gcc or llvm - *<branch>* is an ordered integer index related to expression tree traversal order of the associated conditional. For others, it may be a meaningful string - see below. *<branch>* appears in the 'tooltip' popup of the associated branch in the ``genhtml`` output - so human-readable values are helpful to users who are trying to understand coverage results - for example, in order to develop additional regression tests, to improve coverage.

*<taken>*
    is either '-' if the corresponding expression was never evaluated (*e.g.*, the basic block containing the branch was never executed) or a number indicating how often that branch was taken.

*<exception>*
    is 'e' (single character) if this is a branch related to exception handling - and is not present if the branch is not related to exceptions. Exception branch identification requires compiler support. geninfo will be able to identify exception branches only if your toolchain version is new enough to support the feature.

*<fallthrough>*
    is 'f' (single character) if this is a branch is marked as 'fallthrough' (*e.g.*, in the gcov output) - and is not present if the branch is not marked. Fallthrough branch identification requires compiler support. geninfo will be able to identify fallthrough branches only if your toolchain version is new enough to support the feature. A branch may be marked as '<exception>' or '<fallthough' - but not both.

*<unreachable>*
    is 'U' (single character) if this branch is associated with an 'unreachable directive, and is not present if the branch is reachable. Unreachability is intended to mark branch expressions which are should not appear in coverage reports - enabling users to ignore uncovered branches which can never be covered, to concentrate on other areas of the coverage report.

    See the *"--unreachable-script"* discussion in :manpage:`genhtml(1)` and the *"ignore_unreachable_flag"* discussion in :manpage:`lcovrc(5)` for more information on how branch exclusion markers are set and used.

The following are example branch records whose *<branch>* expression values are human-readable strings.

::

      BRDA:10,0,enable,1
      BRDA:10,0,!enable,0

In this case, the corresponding code from line 10 is very likely similar to:

::

       if (enable) {
         ...
       }

such that the associated testcase entered the block ('enable' evaluated to 'true').

Arbitrarily complicated branch expressions are supported - including branch expressions which contain commas (*e.g.,* in an expression containing a function call).

Note that particular tools may or may not suppress expressions which are statically true or statically false - *e.g.,* expressions using template parameters. This makes it potentially complicated to compare coverage data generated by two different tools.

A note on branch identification, matching, and merging:

As noted previously: lcov merely presents coverage data which is identified by other tools such as gcov. Unfortunately, gcov (and other tools) do not produce sufficient information to uniquely identify branch expressions - so lcov is forced to use a heuristic solution based on the order of appearance as well as the number and type of individual branch elements - say, in the gcov output.

lcov computes a 'signature' for each "<block>". If the block ID and signature found while capturing data from multiple files or while merging coverage data - then the block is considered identical and corresponding expression counts are combined.

Within a particular line, there may be one or more blocks with the same signature - for example, corresponding to independent branch expressions in function call arguments on that line, or to different macro or template expansion. lcov keeps track of the order that branch blocks were found (say, in the gcov output or in an lcov .info file).

When merging branch data on a particular line:

-   Blocks which have different signatures are considered to be distinct.

-   Blocks which have identical signatures are matched in order: the zeroth block with signature *s1* in coverage DB A is merged with the zeroth block with signature *s1* in coverage DB B - and so on.

-   If one or the other DB does not contain some signature, or one DB contains more blocks with the same signature: then those non-matching blocks are simply copied to the merged output.

This heuristic can cause ambiguity in the generated report - especially for cases that a particular line expands in different ways in different compilation units - *e.g.,* due to template or macro expansion. In such cases, it may not be possible for lcov to know that some block whose signature and order appear to match, is not actually the same block. It may be possible to refactor the code slightly to introduce explicit temporaries (on their own line) to resolve the ambiguity.

Branch coverage summaries are stored in two lines:

::

    BRF:<number of branches found>

Note that this count does not include 'excluded' branches. Excluded branches *do* appear as BRDA records.

::

    BRH:<number of branches hit>

Note that this count does not include 'excluded' branches. Excluded branches *do* appear as BRDA records.

MC/DC information is stored one line per expression:

::

    MCDC:<line_number>,[<unreachable>]<groupSize>,<sense>,<taken>,<index>,<expression>

where:

*<line_number>*
    is the line number where the condition is found - and is expected to be a non-zero integer.

*<groupSize>* and *<index>*
    serve to uniquely define a particular element in the expression tree of a particular conditional found on the associated line.

    Within a particular line and group,

*<index>*
    is an integer numbered from zero to *<groupSize> - 1* with no gaps. For some languages and some coding styles, there will only be one group on any particular line.

*<sense>*
    is either *"f"* or *"t"*, indicating whether the condition is sensitive to the indicated change - that is, does the condition outcome change if the corresponding changes from 'false' to 'true' or from 'true to false, respectively.

*<taken>*
    is a count - 0 (zero) if the expression was not sensitized, non-zero if it was sensitized. Note that some tools may treat *<taken>* as the number of times that the expression was sensitized where others may treat it as a boolean - 1:sensitized or 0: not sensitized.

*<expression>*
    is an arbitrary string, intended to be a meaningful string which will help the user to understand the condition context - see below. *<expression>* appears in the 'tooltip' popup of the associated MC/DC condition in the ``genhtml`` output - so human-readable values are helpful to users who are trying to understand coverage results - for example, in order to develop additional regression tests, to improve coverage.

    For a given <groupSize> and <index>, the <expression> should be identical for both "t" and "f" senses.

*<unreachable>*
    is 'U' (single character) if this condition is associated with an 'unreachable directive, and is not present if the condition is reachable. Unreachability is intended to mark conditions which should not appear in coverage reports - enabling users to ignore uncovered conditions which can never be covered, to concentrate on other areas of the coverage report.

    See the *"--unreachable-script"* discussion in :manpage:`genhtml(1)` and the *"ignore_unreachable_flag"* discussion in :manpage:`lcovrc(5)` for more information on how branch exclusion markers are set and used.

The following are example MC/DC records whose *<expression>* values are human-readable strings.

::

      MCDC:10,2,f,0,0,enable
      MCDC:10,2,t,1,0,enable
      ...

In this case, the corresponding code from line 10 is very likely similar to:

::

       if (enable ...) {
         ...
       }

such that the associated testcase was sensitive to a change of 'enable' from true to false (but not the converse).

Arbitrarily complicated expressions are supported - including expressions which contain commas (*e.g.,* in an expression containing a function call).

Note that particular tools may or may not suppress expressions which are statically true or statically false - *e.g.,* expressions using template parameters. This makes it potentially complicated to compare coverage data generated by two different tools.

MCDC coverage summaries are stored in two lines:

::

    MCF:<number of conditions found>

Note that this count does not include 'excluded' conditions. Excluded branches *do* appear as MCDC records.

::

    MCH:<number of condition hit>

Note that this count does not include 'excluded' conditions. Excluded branches *do* appear as MCDC records.

Then there is a list of execution counts for each instrumented line (*i.e.* a line which resulted in executable code):

::

    DA:<line number>,<execution count>[,<checksum>]

Note that there may be an optional checksum present for each instrumented line. The current ``geninfo`` implementation uses an MD5 hash as checksumming algorithm.

At the end of a section, there is a summary about how many lines were found and how many were actually instrumented:

::

    LH:<number of lines with a non-zero execution count>
    LF:<number of instrumented lines>

Each sections ends with:

::

    end_of_record

In addition to the main source code file there are sections for all #included files which also contain executable code.

Note that the absolute path of a source file is generated by interpreting the contents of the respective .gcno file (see :manpage:`gcov(1)` for more information on this file type). Relative filenames are prefixed with the directory in which the .gcno file is found.

Note also that symbolic links to the .gcno file will be resolved so that the actual file path is used instead of the path to a link. This approach is necessary for the mechanism to work with the /proc/gcov files.

FILES
-----

*/etc/lcovrc*
    The system-wide configuration file.

*~/.lcovrc*
    The per-user configuration file.

``bin``/getp4version
    Sample script for use with ``--version-script`` that obtains version IDs via Perforce.

``bin``/get_signature
    Sample script for use with ``--version-script`` that uses md5hash as version IDs.

AUTHOR
------

Peter Oberparleiter <Peter.Oberparleiter@de.ibm.com>

Henry Cox <henry.cox@mediatek.com>
    Filtering, error management, parallel execution sections.

SEE ALSO
--------

:manpage:`genhtml(1)`, :manpage:`lcov(1)`, :manpage:`lcovrc(5)`,
:manpage:`gcov(1)`, 
:manpage:`llvm2lcov(1)`

https://github.com/linux-test-project/lcov
