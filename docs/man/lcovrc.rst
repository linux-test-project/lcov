===========================================================================================
lcovrc -  configuration file for |ToolName| tools containing default options and settings.
===========================================================================================

:Manual section: 5
:Manual group: |ToolName| Configuration

NAME
----

lcovrc
 Configuration file for |ToolName| tools containing default options and settings.

DESCRIPTION
-----------

The *lcovrc* file contains configuration information for the ``lcov`` code coverage tool (see ``lcov``\(1)).

The system-wide configuration file is located at *$|TOOL_NAME|_HOME/etc/lcovrc*. This is typically either */etc/lcovrc* or */usr/local/etc/lcovrc* but may be wherever you have installed the lcov package. To change settings for a single user, place a customized copy of this file at location *\~/.lcovrc*. Where available, command-line options override configuration file settings.

The *genhtml, lcov,* and *geninfo* commands also support the *\-\-config\-file* option, which can be used to specify one or more files which should be used instead of the system or user default rc files. Multiple options files may be useful if you have both project- and team-specific common options and want to ensure consistency across multiple users. If multiple \-\-config\-file options are applied in the order they appear. Note that the "\-\-config\-file" option name must be specified in full and cannot be abbreviated. An error will occur if the option is not recognized.

Lines in a configuration file can either be:

- empty lines or lines consisting only of white space characters. These lines are ignored.

- comment lines which start with a hash sign ('#'). These are treated like empty lines and will be ignored.

- statements in the form 'key = value'.

- Values may be taken from environment variables via the syntax 'key = ... $ENV{ENV_VAR_NAME} ...'.

  The substring '$ENV{ENV_VAR_NAME}' is replaced by the value of the environment variable.

  One or more environment variables may be used to set the RC value. 'key' is ignored if any of the environment variables are not set in your user environment.

A list of valid statements and their description can be found in section 'OPTIONS' below.

``NOTE`` that there is no error checking of keys in the options file: spelling errors are simply seen as values which are not used by some particular tool. If you are unsure of whether your options file is read or its values applied, you can use the *\-\-verbose \-\-verbose* flag to enable printing of option value overrides. (The option appears twice to enable a higher level of verbosity.)

Both 'list' and 'scalar' (non list) options are supported in the lcovrc file.

For scalar (non list) options:

- if specified on the command line and in the lcovrc file, the value specified on the command line wins. The value from the RC file is ignored.

- Scalar options include: 'criteria\_script = ...', 'genhtml\_annotate\_script = ...', 'version\_script = ...', etc.

For list options:

- the RC file entry can be used multiple times; each use appends to the list. For example, the entry below will result in two 'omit' patterns which will both be checked:

  ::

    # note explicit start/end line markers in the regexp
    omit_lines = ^\\s+//\\s*MY_EXCLUDE_MARKER\\s*$
    # Note that the regexp below matches anywhere on the line
    omit_lines = NR_CM_DBG_PRINT

- If entries are specified on the command line, then the RC file entries are ignored: command line wins. If entries are specified in more than one RC file (*i.e.*, multiple \-\-config\-file arguments are supplied), then RC files are applied in order of appearance, and list entries are appended in order. For most list-type options, order is not important.

- list options include:

  ::

    filter = ...
    exclude = ...
    ignore = ...
    substitute = ...
    omit_lines = ...
    erase_functions = ...
    genhtml_annotate_script = ...

  *etc.* For a complete set of list options, see the documentation of each configuration option, below.

**Example configuration:**

Note that this example does not include all possible configuration options. In general: (almost) all command line options can be specified in the configuration file instead, whereas some configuration file options have no command line equivalent.

See the OPTIONS section below for details.

::

  #
  # Example |ToolName| configuration file
  #
  # include some other config file
  #   e.g, user-specific options.  Note the environment variable expansion
  # config_file = $ENV{HOME}/.user_lcovrc
  #   or project specific - hard-coded from environment variable
  # config_file = /path/to/myproject/.lcovrc
  #   or in the current run directory
  # config_file = $ENV{PWD}/.lcovrc

  # External style sheet file
  #genhtml_css_file = gcov.css

  # Use 'dark' mode display (light foreground/dark background)
  # rather than default
  #genhtml_dark_mode = 1

  # Alternate header text to use at top of each page
  #genhtml_header = Coverage report for my project

  # Alternate footer text to use at the bottom of each page
  #genhtml_footer = My footer text

  # Coverage rate limits
  genhtml_hi_limit = 90
  genhtml_med_limit = 75

  # Ignore some errors (comma-separated list)
  #ignore_errors = empty,mismatch

  # Stop emitting message after this number have been printed
  # 0 == no limit
  max_message_count = 100

  # If nonzero, do not stop when an 'ignorable error' occurs - try
  #  to generate a result, however flawed.  This is equivalent to
  #  the '--keep-going' command line switch.
  # Default is 1:  stop when error occurs
  #stop_on_error = 1

  # If nonzero, treat warnings as error
  # note that ignored messages will still appear as warnings
  # Default is 0
  #treat_warning_as_error = 1

  # If set to non-zero, only issue particular warning once per file
  # Default is 1
  #warn_once_per_file = 1

  # extension associated with lcov trace files - glob match pattern
  # used as argument to 'find' - to find coverage files contained in
  # a directory argument
  #info_file_pattern = *.info

  # list of file extensions which should be treated as C/C++ code
  # (comma-separated list)
  #c_file_extensions = h,c,cpp,hpp

  # list of file extensions which should be treated as RTL code
  # (*e.g.*, Verilog) (comma-separated list)
  #rtl_file_extensions = v,vh,sv

  # list of file extensions which should be treated as Java code
  #java_file_extensions = java

  # list of file extensions which should be treated as perl code
  #perl_file_extensions = pl,pm

  # list of file extensions which should be treated as python code
  #python_file_extensions = py

  # maximum number of lines to look at, when filtering bogus branch expressions
  #filter_lookahead = 5

  # if nonzero, bitwise operators '|', '&', '~' indicate conditional expressions
  #filter_bitwise_conditional = 1

  # if nonzero, '--filter blank' is applied to blank lines, regardless
  # of their hit count
  #filter_blank_aggressive = 1

  # Width of line coverage field in source code view
  genhtml_line_field_width = 12

  # Width of branch coverage field in source code view
  genhtml_branch_field_width = 16

  # Width of MC/DC coverage field in source code view
  genhtml_mcdc_field_width = 14

  # width of 'owner' field in source code view - default is 20
  genhtml_owner_field_width = 20
  # width of 'age' field in source code view - default is 5
  genhtml_age_field_width = 5

  # Width of overview image
  genhtml_overview_width = 80

  # Resolution of overview navigation
  genhtml_nav_resolution = 4

  # Offset for source code navigation
  genhtml_nav_offset = 10

  # Do not remove unused test descriptions if non-zero
  genhtml_keep_descriptions = 0

  # Do not remove prefix from directory names if non-zero
  genhtml_no_prefix = 0

  # Do not create source code view if non-zero
  genhtml_no_source = 0

  # Specify size of tabs
  genhtml_num_spaces = 8

  # Include color legend in HTML output if non-zero
  genhtml_legend = 0

  # Include HTML file at start of HTML output
  #genhtml_html_prolog = prolog.html

  # Include HTML file at end of HTML output
  #genhtml_html_epilog = epilog.html

  # Use custom HTML file extension
  #genhtml_html_extension = html

  # Compress all generated html files with gzip.
  #genhtml_html_gzip = 1

  # Include sorted overview pages
  genhtml_sort = 1

  # Display coverage data in hierarchical directory structure
  # (rather than flat/3 level)
  #genhtml_hierarchical = 1

  # Display coverage data using 'flat' view
  #genhtml_flat_view = 1

  # Specify the character set of all generated HTML pages
  genhtml_charset=UTF-8

  # Allow HTML markup in test case description text if non-zero
  genhtml_desc_html=0

  # Specify the precision for coverage rates
  #genhtml_precision=1

  # Show missed counts instead of hit counts
  #genhtml_missed=1

  # group function aliases in report - see '--merge' section in man(1) genhtml
  #merge_function_aliases = 1

  # If set, suppress list of aliases in function detail table
  #suppress_function_aliases = 1

  # If set, derive function end line from line coverpoint data - default ON
  #derive_function_end_line = 1

  # If set, derive function end lines for all file types.
  # By default, we derive end lines for C/C++ files only
  #
  #derive_end_line_all_files = 0

  # Maximum size of function (number lines) which will be checked by '--filter trivial'
  #trivial_function_threshold = 5

  # Set threshold for hit count which tool should deem likely to indicate
  # a toolchain bug (corrupt coverage data)
  # excessive_count_threshold = number

  # Demangle C++ symbols
  # Call multiple times to specify command and command line arguments
  #  ('-Xlinker'-like behaviour)
  #demangle_cpp = c++filt

  # Location of the gcov tool
  #geninfo_gcov_tool = gcov

  # Adjust test names if non-zero
  #geninfo_adjust_testname = 0

  # Ignore testcase names in .info file
  forget_testcase_names = 0

  # Calculate and/or compute checksum for each line if non-zero
  checksum = 0

  # Enable libtool compatibility mode if non-zero
  geninfo_compat_libtool = 0

  # Specify whether to capture coverage data for external source
  # files
  #geninfo_external = 1

  # Specify whether to capture coverage data from compile-time data files
  # which have no corresponding runtime data.
  #geninfo_capture_all = 1

  # Use gcov's --all-blocks option if non-zero
  #geninfo_gcov_all_blocks = 1

  # Adjust 'executed' non-zero hit count of lines which contain no branches
  # and have attribute '"unexecuted_blocks": true'
  #geninfo_unexecuted_blocks = 0

  # Specify compatibility modes (same as \-\-compat option
  # of geninfo)
  #geninfo_compat = libtool=on, hammer=auto, split_crc=auto

  # Specify if geninfo should try to automatically determine
  # the base-directory when collecting coverage data.
  geninfo_auto_base = 1

  # Use gcov intermediate format? Valid values are 0, 1, auto
  geninfo_intermediate = auto

  # Specify if exception branches should be excluded from branch coverage.
  no_exception_branch = 0

  # Directory containing gcov kernel files
  lcov_gcov_dir = /proc/gcov

  # Location for temporary directories
  lcov_tmp_dir = /tmp

  # Show full paths during list operation if non-zero
  lcov_list_full_path = 0

  # Specify the maximum width for list output. This value is
  # ignored when lcov_list_full_path is non-zero.
  lcov_list_width = 80

  # Specify the maximum percentage of file names which may be
  # truncated when choosing a directory prefix in list output.
  # This value is ignored when lcov_list_full_path is non-zero.
  lcov_list_truncate_max = 20

  # Specify if function coverage data should be collected, processed, and
  # displayed.
  function_coverage = 1

  # Specify if branch coverage data should be collected, processed, and
  # displayed.
  branch_coverage = 0

  # Specify if Modified Condition / Decision Coverage data should be collected,
  #  processed, and displayed.
  mcdc_coverage = 0

  # Ask lcov/genhtml/geninfo to return non-zero exit code if branch coverage is
  # below specified threshold percentage.
  fail_under_branches = 75.0

  # Ask lcov/genhtml/geninfo to return non-zero exit code if line coverage is
  # below specified threshold percentage.
  #fail_under_lines = 97.5

  # Specify JSON module to use, or choose best available if
  # set to auto
  lcov_json_module = auto

  # Specify maximum number of parallel slaves
  # default: 1 (no parallelism)
  #parallel = 1

  # Specify maximum memory to use during parallel processing, in Mb.
  # Do not fork if estimated memory consumption exceeds this number.
  # default: 0 (no limit)
  #memory = 1024

  # Specify the number of consecutive fork() failures to allow before
  # giving up
  # max_fork_fails = 5

  # Seconds to wait after failing to fork() before retrying
  # fork_fail_timeout = 10

  # Throttling control:  specify a percentage of system memory to use as
  maximum during parallel processing.
  # Do not fork if estimated memory consumption exceeds the maximum.
  # this value is used only if the maximum memory is not set.
  # default: not set
  #memory_percentage = 75

  # Character used to split list-type parameters
  #  - for example, the list of "--ignore_errors source,mismatch"
  # default: , (comma)
  #split_char = ,

  # use case insensitive compare to find matching files, for include/exclude
  #  directives, etc
  #case_insensitive = 0

  # override line default line exclusion regexp
  #lcov_excl_line = LCOV_EXCL_LINE

  # override branch exclusion regexp
  #lcov_excl_br_line = LCOV_EXCL_BR_LINE

  # override exception branch exclusion regexp
  #lcov_excl_exception_br_line = LCOV_EXCL_EXCEPTION_BR_LINE

  # override start of exclude region regexp
  #lcov_excl_start = LCOV_EXCL_START

  # override end of exclude region regexp
  #lcov_excl_stop = LCOV_EXCL_STOP

  # override unreachable line default line exclusion regexp
  #lcov_unreachable_line = LCOV_UNREACHABLE_LINE

  # override start of unreachable region regexp
  #lcov_unreachable_start = LCOV_UNREACHABLE_START

  # override end of unreachable region regexp
  #lcov_unreachable_stop = LCOV_UNREACHABLE_STOP

  # override start of branch exclude region regexp
  #lcov_excl_br_start = LCOV_EXCL_BR_START

  # override start of exclude region regexp
  #lcov_excl_br_stop = LCOV_EXCL_BR_STOP

  # override start of exclude region regexp
  #lcov_excl_exception_br_start = LCOV_EXCL_EXCEPTION_BR_START

  # override start of exclude region regexp
  #lcov_excl_exception_br_stop = LCOV_EXCL_EXCEPTION_BR_STOP


OPTIONS
-------

``config_file`` = *filename*
----------------------------

Include another config file.

Inclusion is equivalent to inserting the text from *filename* at this point in the current file. As a result, settings from the included file are processed after earlier settings in the current file, but before later settings from the current file. As a result:

**Scalar options** set earlier in the current file are overridden by settings from the included file, and scalar options from the included file are overridden by later setting in the current file.

**Array options** from earlier in the current file appear before setting from the included file, and array options from later in the current file appear after.

Config file inclusion is recursive: an included config file may include another file - and so on. Inclusion loops are not supported and will result in a *usage* error.

The most common usecase for config file inclusion is so that a site-wide or project-wide options file can include a user-specific or module-specific options file - for example, as

::

   ...
   config_file = $ENV{HOME}/.lcovrc_user
   ...


``genhtml_css_file`` = *filename*
----------------------------------

Specify an external style sheet file. Use this option to modify the appearance of the HTML output as generated by ``genhtml``. During output generation, a copy of this file will be placed in the output directory.

This option corresponds to the \-\-css\-file command line option of ``genhtml``.

By default, a standard CSS file is generated.

``genhtml_header`` = *string*
-----------------------------

Specify header text to use at top of each HTML page.

This option corresponds to the \-\-header\-title command line option of ``genhtml``.

Default is "|ToolName| - (differential )? coverage report"

``genhtml_footer`` = *string*
-----------------------------

Specify footer text to use at bottom of each HTML page.

This option corresponds to the \-\-footer command line option of ``genhtml``.

Default is |ToolName| tool version string.

``genhtml_dark_mode`` = *0 | 1*
-------------------------------

If non-zero, display using light text on dark background rather than dark text on light background.

This option corresponds to the \-\-dark\-mode command line option of ``genhtml``.

By default, a 'light' palette is used.

``genhtml_hi_limit``  = *hi_limit*
``genhtml_med_limit`` = *med_limit*
-----------------------------------

Specify coverage rate limits for classifying file entries. Use this option to modify the coverage rates (in percent) for line, function and branch coverage at which a result is classified as high, medium or low coverage. This classification affects the color of the corresponding entries on the overview pages of the HTML output:

::

  High:   hi_limit  <= rate <= 100        default color: green
  Medium: med_limit <= rate < hi_limit    default color: yellow
  Low:    0         <= rate < med_limit   default color: red

Defaults are 90 and 75 percent.

There are also options to configure different thresholds for line, branch, and function coverages. See below.

``genhtml_line_hi_limit``  = *line_hi_limit*
``genhtml_line_med_limit`` = *line_med_limit*
----------------------------------------------

Specify specific threshold for line coverage limits used to decide whether a particular line coverage percentage is classified as high, medium, or low coverage. If the line-specific values are not specified, then the default *genhtml\_med\_limit* or *genhtml\_hi\_limit* values are used.

``genhtml_branch_hi_limit``  = *branch_hi_limit*
``genhtml_branch_med_limit`` = *branch_med_limit*
--------------------------------------------------

Specify specific threshold for branch coverage limits used to decide whether a particular branch coverage percentage is classified as high, medium, or low coverage. If the branch-specific values are not specified, then the default *genhtml\_med\_limit* or *genhtml\_hi\_limit* values are used.

``genhtml_function_hi_limit``  = *function_hi_limit*
``genhtml_function_med_limit`` = *function_med_limit*
------------------------------------------------------

Specify specific threshold for function coverage limits used to decide whether a particular function coverage percentage is classified as high, medium, or low coverage. If the function-specific values are not specified, then the default *genhtml\_med\_limit* or *genhtml\_hi\_limit* value is used.

``rtl_file_extensions`` = *str[,str]+*
--------------------------------------

Specify a comma-separated list of file extensions which should be assumed to be RTL code (*e.g.*, Verilog).

If not specified, the default set is 'v,vh,sv,vhdl?'. There is no command line option equivalent.

This option is used by genhtml and lcov.

``info_file_pattern`` = *str*
-----------------------------

Specify a glob-match pattern associated with lcov trace files (suitable as an argument to 'find'. If not specified, the default is '\*.info'.

``c_file_extensions`` = *str[,str]+*
------------------------------------

Specify a comma-separated list of file extensions which should be assumed to be C/C++ code.

If not specified, the default set is 'c,h,i,C,H,I,icc,cpp,cc,cxx,hh,hpp,hxx'. If you want all files to be treated as C/C++ code, you can use: *c\_file\_extensions = .\**

This parameter must be set from the lcovrc file or via the *\-\-rc name=value* command line option; note that you may need to protect the value from shell expansion in the latter case.

``java_file_extensions`` = *str[,str]+*
---------------------------------------

Specify a comma-separated list of file extensions which should be assumed to be Java code.

If not specified, the default set is 'java'. If you want all files to be treated as Java code, you can use: *java\_file\_extensions = .\**

This parameter must be set from the lcovrc file or via the *\-\-rc name=value* command line option; note that you may need to protect the value from shell expansion in the latter case.

``perl_file_extensions`` = *str[,str]+*
---------------------------------------

Specify a comma-separated list of file extensions which should be assumed to be Perl code.

If not specified, the default set is 'pl,pm'. If you want all files to be treated as Perl code, you can use: *perl\_file\_extensions = .\**

This parameter must be set from the lcovrc file or via the *\-\-rc name=value* command line option; note that you may need to protect the value from shell expansion in the latter case.

``python_file_extensions`` = *str[,str]+*
-----------------------------------------

Specify a comma-separated list of file extensions which should be assumed to be Python code.

If not specified, the default set is 'py'. If you want all files to be treated as Python code, you can use: *python\_file\_extensions = .\**

This parameter must be set from the lcovrc file or via the *\-\-rc name=value* command line option; note that you may need to protect the value from shell expansion in the latter case.

``filter_lookahead`` = *integer*
--------------------------------

Specify the maximum number of lines to look at when filtering bogus branch expressions. A larger number may catch more cases, but will increase execution time.

If not specified, the default set is 10. There is no command line option equivalent.

This option is used by genhtml and lcov.

``filter_bitwise_conditional`` = *0|1*
---------------------------------------

If set to non-zero value, bogus branch filtering will assume that expressions containing bitwise operators '&', '|', '~' are conditional expressions - and will not filter them out.

If not specified, the default set is 0 (do not treat them as conditional). There is no command line option equivalent.

This option is used by genhtml and lcov.

``filter_blank_aggressive`` = *0|1*
-----------------------------------

If set to non-zero value, then blank source lines will be ignored whether or not their 'hit' count is zero. See the *\-\-filter blank* section in :manpage:`genhtml(1)`.

If not specified, the default set is 0 (filter blank lines only if they are not hit). There is no command line option equivalent.

``ignore_errors`` = *message_type(,message_type)\**
----------------------------------------------------

Specify a message type which should be ignored.

This option can be used multiple times in the lcovrc file to ignore multiple message types.

This option is equivalent to the \-\-ignore\-errors option to geninfo, genhtml, or lcov. Note that the lcovrc file message list is not applied (those messages NOT ignored) if the '\-\-ignore\-errors' command line option is specified.

This option is used by genhtml, lcov, and geninfo.

``ignore_unreachable_flag`` = *0 | 1*
-------------------------------------

When parsing a trace file, ignore 'unreachable' flags on branch expressions and MC/DC conditions - effectively, treating them as reachable.

Note that the *ignore\_unreachable\_flag* is used only when reading a trace file. It has no effect on unreachable flags set by your *unreachable\_script* callback. See the *unreachable\_script* section, below.

This option is used by genhtml, lcov, and geninfo.

``expect_message_count`` = *message_type:expr(,message_type:expr)\**
---------------------------------------------------------------------

Specify a constraint on the number of messages of one or more types which are expected to be produced during tool execution. If the constraint is not true, an error of type *count* will be generated.

Multiple constraints can be specified using a comma-separated list or by using the option multiple times.

Substitutions are performed on the expression before it is evaluated:

For example:

-  ``expect_message_count = inconsistent : %C == 5``

   says that you expect exactly 5 messages of this type

-  ``expect_message_count inconsistent : %C > 6 && %C <= 10``

   says that you expect the number of messages to be in the range (6:10].

This option is useful if errors are caused by conditions that you cannot fix - for example, due to inconsistent coverage data generated by your toolchain. In those scenarios, you may decide:

-  to exclude the offending code, or

-  to exclude the entire offending file(s), or

-  to ignore the messages, either by converting them to warnings or suppressing them entirely.

In the latter case, this option provides some additional safety by warning you when the count differs due to some change which occurred, giving you the opportunity to diagnose the change and/or to review message changes.

This option is equivalent to the *\-\-expect\-message\-count* command line flag.

``max_message_count`` = *integer*
---------------------------------

Set the maximum number of warnings of any particular type which should be emitted. This can be used to reduce the size of log files.

No more warnings will be printed after this number is reached. 0 (zero) is interpreted as 'no limit'.

This option is used by genhtml, lcov, and geninfo.

``message_log`` = *filename*
----------------------------

Specify location to store error and warning messages (in addition to writing to STDERR). If not specified, then the default location is used.

This attribute is equivalent to the *\-\-msg\-log* command line option. The command line option takes precedence if both are specified.

``stop_on_error`` =  *0|1*
--------------------------

If set to 0, tell the tools to ignore errors and keep going to try to generate a result - however flawed or incomplete that result might be. Note that some errors cannot be ignored and that ignoring some errors may lead to other errors.

The tool will return a non-zero exit code if one or more errors are detected during execution when *stop\_on\_error* is disabled. That is, the tool will continue execution in the presence of errors but will return an exit status.

This is equivalent to the *'\-\-keep\-going'* command line option.

Default is 1: stop when error occurs.

If the *'ignore\_error msgType'* option is also used, then those messages will be treated as warnings rather than errors (or will be entirely suppressed if the message type appears multiple times in the ignore_messages option). Warnings do not cause a non-zero exit status.

This option is used by genhtml, lcov, and geninfo.

``treat_warning_as_error`` =  *0|1*
-----------------------------------

If set to 1, tell the tools that messages which are normally treated as warnings (*e.g.,* certain usage messages) should be treated as errors.

Note that ignored messages will still appear as warnings: see the *ignore\_errors* entry, above.

This option is used by genhtml, lcov, and geninfo.

``warn_once_per_file`` =  *0|1*
--------------------------------

If set to 1, tell the tools to emit certain errors only once per file (rather than multiple times, if the issue occurs multiple times in the same file).

Default is 1: do not report additional errors.

This option is used by genhtml, lcov, and geninfo.

``check_data_consistency`` =  *0|1*
-----------------------------------

If set to 1, tell the tools to execute certain data consistency checks - *e.g.,* that function with a non-zero hit count contains at least one line with a non-zero hit count - and vice versa.

It may be useful to use this option to disable checking if you have inconsistent legacy data and have no way to correct or exclude it.

Default is 1: execute consistency checks.

``genhtml_line_field_width`` = *number_of_characters*
------------------------------------------------------

Specify the width (in characters) of the source code view column containing line coverage information.

Default is 12.

``genhtml_branch_field_width`` = *number_of_characters*
--------------------------------------------------------

Specify the width (in characters) of the source code view column containing branch coverage information.

Default is 16.

``genhtml_mcdc_field_width`` = *number_of_characters*
------------------------------------------------------

Specify the width (in characters) of the source code view column containing MC/DC coverage information.

Default is 14.

``genhtml_owner_field_width`` = *number_of_characters*
-------------------------------------------------------

Specify the width (in characters) of the source code view column containing owner information (as reported by your annotation script. This option has an effect only if you are using a source annotation script: see the \-\-annotation-script option in the genhtml man page.

Default is 20.

``genhtml_age_field_width`` = *number_of_characters*
------------------------------------------------------

Specify the width (in characters) of the source code view column containing age of the corresponding block (as reported by your annotation script). This option has an effect only if you are using a source annotation script: see the \-\-annotation-script option in the genhtml man page.

Default is 5.

``genhtml_frames`` = *0 | 1*
----------------------------

Specify whether source detail view should contain a navigation image. See the *\-\-frame* entry in the ``genhtml`` man page.

``genhtml_overview_width`` = *pixel_size*
------------------------------------------

Specify the width (in pixel) of the overview image created when generating HTML output using the \-\-frames option of ``genhtml``.

Default is 80.

``genhtml_nav_resolution`` = *lines*
------------------------------------

Specify the resolution of overview navigation when generating HTML output using the \-\-frames option of ``genhtml``. This number specifies the maximum difference in lines between the position a user selected from the overview and the position the source code window is scrolled to.

Default is 4.

``genhtml_nav_offset`` = *lines*
--------------------------------

Specify the overview navigation line offset as applied when generating HTML output using the \-\-frames option of ``genhtml``.

Clicking a line in the overview image should show the source code view at a position a bit further up, so that the requested line is not the first line in the window. This number specifies that offset.

Default is 10.

``genhtml_keep_descriptions`` = *0 | 1*
---------------------------------------

If non-zero, keep unused test descriptions when generating HTML output using ``genhtml``.

This option corresponds to the \-\-keep\-descriptions option of ``genhtml``.

Default is 0.

``genhtml_no_prefix`` = *0 | 1*
--------------------------------

If non-zero, do not try to find and remove a common prefix from directory names.

This option corresponds to the \-\-no\-prefix option of ``genhtml``.

Default is 0.

``genhtml_no_source`` = *0 | 1*
--------------------------------

If non-zero, do not create a source code view when generating HTML output using ``genhtml``.

This option corresponds to the \-\-no\-source option of ``genhtml``.

Default is 0.

``genhtml_num_spaces`` = *num*
-------------------------------

Specify the number of spaces to use as replacement for tab characters in the HTML source code view as generated by ``genhtml``.

This option corresponds to the \-\-num\-spaces option of ``genhtml``.

Default is 8.

``genhtml_legend`` = *0 | 1*
-----------------------------

If non-zero, include a legend explaining the meaning of color coding in the HTML output as generated by ``genhtml``.

This option corresponds to the \-\-legend option of ``genhtml``.

Default is 0.

``genhtml_html_prolog`` = *filename*
------------------------------------

If set, include the contents of the specified file at the beginning of HTML output.

This option corresponds to the \-\-html\-prolog option of ``genhtml``.

Default is to use no extra prolog.

``genhtml_html_epilog`` = *filename*
------------------------------------

If set, include the contents of the specified file at the end of HTML output.

This option corresponds to the \-\-html\-epilog option of ``genhtml``.

Default is to use no extra epilog.

``genhtml_html_extension`` = *extension*
----------------------------------------

If set, use the specified string as filename extension for generated HTML files.

This option corresponds to the \-\-html\-extension option of ``genhtml``.

Default extension is "html".

``genhtml_html_gzip`` = *0 | 1*
--------------------------------

If set, compress all html files using gzip.

This option corresponds to the \-\-html\-gzip option of ``genhtml``.

Default extension is 0.

``genhtml_sort`` = *0 | 1*
---------------------------

If non-zero, create overview pages sorted by coverage rates when generating HTML output using ``genhtml``.

This option can be set to 0 by using the \-\-no\-sort option of ``genhtml``.

Default is 1.

``genhtml_hierarchical`` = *0 | 1*
-----------------------------------

If non-zero, the HTML report will follow the hierarchical directory structure of the source code.

This option is equivalent to using the \-\-hierarchical command line option of ``genhtml``. 'Hierarchical' and 'flat' views are mutually exclusive.

Default is 0.

``genhtml_flat_view`` = *0 | 1*
--------------------------------

If non-zero, the top-level HTML table will contain all of the files in the project and there will be no intermediate directory pages.

This option is equivalent to using the \-\-flat command line option of ``genhtml``. 'Hierarchical' and 'flat' views are mutually exclusive.

Default is 0.

``genhtml_show_navigation`` = *0 | 1*
--------------------------------------

If non-zero, the 'source code' view summary table will contain hyperlinks from the number to the first source line in the corresponding category ('Hit' or 'Not hit') in the non-differential coverage report. Source code hyperlinks are always enabled in differential coverage reports.

This option is equivalent to using the \-\-show\-navigation command line option of ``genhtml``.

Default is 0.

``genhtml_show_owner_table`` = *0 | 1 | all*
---------------------------------------------

If non-zero, equivalent to the genhtml *\-\-show\-owners* flag: see :manpage:`genhtml(1)` for details.

Default is 0.

``compact_summary_tables`` = *0 | 1*
------------------------------------

If non-zero, suppress the 'Total' row in the 'date' and 'owner' summary table if there is only one element in the corresponding bin.

When there are a large number of files with a single author, this can cut the summary table size by almost half.

Default is 1 (enabled).

``owner_table_entries`` = *integer*
-----------------------------------

This option is used to tell genhtml the number of 'owner' table entries to retain in the summary table (at the top of the page) if owner table truncation is requested. Authors are sorted by quantity of un-exercised code - so elided entries will be smaller offenders: maximal offenders are retained. If the option is not set, then owner tables are not truncated.

This option has no effect unless *genhtml \-\-show\-owners* is enabled. See the *\-\-show-owners* option in :manpage:`genhtml(1)` for details.

Default is not set (*i.e.,* do not truncate owner tables).

``truncate_owner_table`` = *comma_separated_list*
--------------------------------------------------

This option is used to tell genhtml whether to truncate the 'owner' table at the top, directory, or file level. This option acts together with the *owner\_table\_entries* parameter to determine how many author entries are retained.

This option has no effect unless *genhtml \-\-show\-owners* is enabled and and the *owner\_table\_entries* configuration is set.

If this option is set multiple times in the lcovrc file, the values are combined to form the list of levels where truncation will occur. Similarly, if this option is not set and *owner\_table\_entries* is set, then the table will be truncated everywhere.

See the *\-\-show-owners* option in :manpage:`genhtml(1)` for details.

Default is to not truncate the list.

``genhtml_show_noncode_owners`` = *0 | 1*
-----------------------------------------

If non-zero, equivalent to the genhtml *\-\-show\-noncode* flag: see :manpage:`genhtml(1)` for details.

Default is 0.

``genhtml_show_function_proportion`` = *0 | 1*
----------------------------------------------

If nonzero, add column to "function coverage detail" table to show the proportion of lines and branches within the function which are exercised.

This option is equivalent to using the \-\-show\-proportion command line option of ``genhtml``.

Default is 0.

``genhtml_synthesize_missing`` = *0 | 1*
----------------------------------------

If non-zero, equivalent to the genhtml *\-\-synthesize\-missing* flag: see :manpage:`genhtml(1)` for details.

Default is 0.

``genhtml_charset`` = *charset*
--------------------------------

Specify the character set of all generated HTML pages.

Use this option if the source code contains characters which are not part of the default character set. Note that this option is ignored when a custom HTML prolog is specified (see also ``genhtml_html_prolog``).

Default is UTF-8.

``demangle_cpp`` = *c++filt*
-----------------------------

If set, this option tells genhtml/lcov/geninfo to demangle C++ function names in function overviews, and gives the name of the tool used for demangling. Set this option to one if you want to convert C++ internal function names to human readable format for display on the HTML function overview page.

If the *demangle\_cpp* option is used multiple times, then the arguments are concatenated when the callback is executed - similar to how the gcc *\-Xlinker* parameter works. This provides a possibly easier way to pass arguments to your tool, without requiring a wrapper script. In that case, your callback will be executed as: *| tool\-0 'tool\-1; ...* Arguments are quoted when passed to the shell, in order to handle parameters which contain spaces.

Note that the demangling tool is called via a pipe, and is expected to read from stdin and write to stdout.

This option corresponds to the \-\-demangle\-cpp command line option of ``genhtml``.

Default is not set (C++ demangling is disabled).

``genhtml_desc_html`` = *0 | 1*
--------------------------------

If non-zero, test case descriptions may contain HTML markup.

Set this option to one if you want to embed HTML markup (for example to include links) in test case descriptions. When set to zero, HTML markup characters will be escaped to show up as plain text on the test case description page.

Default is 0.

``genhtml_precision`` =  *1 | 2 | 3 | 4*
-----------------------------------------

Specify how many digits after the decimal-point should be used for displaying coverage rates.

Default is 1.

``merge_function_aliases`` =  *0 | 1*
-------------------------------------

If non-zero, group function aliases in the function detail table. See man(1) genhtml.

Default is 0.

``genhtml_missed`` =  *0 | 1*
------------------------------

If non-zero, the count of missed lines, functions, or branches is shown as negative numbers in overview pages.

Default is 0.

``suppress_function_aliases`` = *0 | 1*
---------------------------------------

If non-zero, do not show aliases in the function detail table.

If nonzero, implies that ``merge_function_aliases`` is enabled. See the genhtml man page for more details.

Default is 0.

``derive_function_end_line`` =  *0 | 1*
----------------------------------------

If non-zero, use 'line' coverage data to deduce the end line of each function definition. This is useful when excluding certain functions from your coverage report. See the *\-\-erase\-functions,* *\-\-filter trivial* and *\ \-\-show\-proportion* options.

Default is 1.

This option is not required if you are using gcc/9 or newer; these versions report function begin/end lines directly.

Note that end lines are derived only for C/C++ files unless the *derive\_function\_end\_lines\_all\_files* option is enabled; see the *c\_file\_extensions* setting, above, for the list of extensions used to identify C/C++ these files.

Lambda functions are ignored during end line computation. Note that lambdas are identified via function name matching - so you must enable demangling if your toolchain is too old to report demangled names in the GCOV output. See the *demangle\_cpp* setting, above.

For languages other than C/C++: end-line derivation may compute the wrong value - *e.g.,* in cases where there are lines of code in global scope following some function definition. In this case, lcov will incorrectly associate the following code with the preceding function.

If this creates problems - for example, causes lcov to warn about inconsistent coverage data - then there are several possible workarounds:

-  disable end-line derivation - *e.g.,* via *\-\-rc derive_function_end_line=0*.

-  exclude the offending code and/or then entire associated file.

-  ignore the error message, *e.g.,* via the *\-\-ignore\-errors* command line option

-  disable coverage DB consistency checks - *e.g.,* via *\-\-rc check_data_consistency=0*.

``derive_function_end_line_all_files`` =  *0 | 1*
-------------------------------------------------

If non-zero, derive end lines for all functions, regardless of source language. By default, end lines are computed only in C/C++ files.

This option has no effect if *derive\_function\_end\_lines* is disabled.

Default is 0 (disabled).

``trivial_function_threshold`` =  *integer*
-------------------------------------------

Set the maximum size of function (in number of lines) which will be checked by *\-\-filter trivial filter.*

Default is 5.

``excessive_count_threshold`` = *number*
----------------------------------------

Set the threshold for hit count that lcov deems excessive/unlikely/indicating a bug somewhere in your toolchain.

For example, it is unlikely that your job can run long enough to rack up tens of billions of hits.

Message type ``excessive`` is used to report potential issue - see the ``genhtml(1), lcov(1), geninfo(1)`` man pages.

Default is not set. (Do not check for excessive counts.)

``geninfo_gcov_tool`` = *path_to_gcov*
---------------------------------------

Specify the location of the gcov tool (see ``gcov``\(1)) which is used to generate coverage information from data files.

This option can be used multiple times - *e.g.*, to add arguments to the gcov callback. See the geninfo man page for details.

``geninfo_adjust_testname`` = *0 | 1*
-------------------------------------

If non-zero, adjust test names to include operating system information when capturing coverage data.

Default is 0.

``forget_testcase_names`` = *0 | 1*
-----------------------------------

If non-zero, ignore testcase names in .info file. This may improve performance and reduce memory consumption if user does not need per-testcase coverage summary in coverage reports.

This is equivalent to the "\-\-forget\-test\-names" lcov/genhtml option.

Default is 0.

``checksum`` = *0 | 1*
-----------------------

If non-zero, generate source code checksums when capturing coverage data. Checksums are useful to prevent merging coverage data from incompatible source code versions but checksum generation increases the size of coverage files and the time used to generate those files.

This option can be overridden by the \-\-checksum and \-\-no\-checksum command line options.

Default is 0.

Note that this options is somewhat subsumed by the *version\_script* option - which does something similar, but at the 'whole file' level.

``geninfo_compat_libtool`` = *0 | 1*
-------------------------------------

If non-zero, enable libtool compatibility mode. When libtool compatibility mode is enabled, lcov will assume that the source code relating to a .da file located in a directory named ".libs" can be found in its parent directory.

This option corresponds to the \-\-compat\-libtool and \-\-no\-compat\-libtool command line option of ``geninfo``.

Default is 1.

``geninfo_external`` = *0 | 1*
--------------------------------

If non-zero, capture coverage data for external source files.

External source files are files which are not located in one of the directories (including sub-directories) specified by the \-\-directory or \-\-base\-directory options of ``lcov / geninfo``. Also see the *\-\-follow* option and the *geninfo\_follow\_symlinks* and *geninfo\_follow\_file\_links* for additional path controls.

Default is 1.

``geninfo_capture_all`` = *0 | 1*
---------------------------------

If non-zero, capture coverage data from both runtime data files as well as compile time data files which have no corresponding runtime data. See the *\-\-all* flag description in ``man(1) geninfo`` for more information.

Default is 0: do not process bare compile-time data files.

``geninfo_external`` = *0 | 1*
--------------------------------

If non-zero, capture coverage data for external source files.

External source files are files which are not located in one of the directories (including sub-directories) specified by the \-\-directory or \-\-base\-directory options of ``lcov / geninfo``. Also see the *\-\-follow* option and the *geninfo\_follow\_file\_links* for additional path controls.

Default is 1.

``geninfo_follow_symlinks`` = *0 | 1*
--------------------------------------

Equivalent to the lcov/geninfo *\-\-follow* command line option. See :manpage:`geninfo(1)` for details.

Default is 0: do not modify follow symbolic links.

``geninfo_follow_file_links`` = *0 | 1*
----------------------------------------

If non-zero and the lcov/geninfo *\-\-follow* command line option is specified, then source file pathnames which contain symlinks are resolved to their actual target. Note that the parent directory of the link target may be considered 'external' and thus be removed by the *\-\-no\-external* flag.

Default is 0: do not modify pathnames.

``geninfo_gcov_all_blocks`` = *0 | 1*
--------------------------------------

If non-zero, call the gcov tool with option --all-blocks.

Using --all-blocks will produce more detailed branch coverage information for each line. Set this option to zero if you do not need detailed branch coverage information to speed up the process of capturing code coverage or to work around a bug in some versions of gcov which will cause it to endlessly loop when analyzing some files.

Default is 1.

``geninfo_unexecuted_blocks`` = *0 | 1*
-----------------------------------------

If non-zero, adjust the 'hit' count of lines which have attribute *"unexecuted\_block": true* but which contain no branches and have a non-zero count. Assume that these lines are not executed.

Note that this option is effective only for gcov versions 9 and newer.

Default is 0.

``geninfo_compat`` = *mode=value[, mode=value,...]*
----------------------------------------------------

Specify that geninfo should enable one or more compatibility modes when capturing coverage data.

This option corresponds to the \-\-compat command line option of ``geninfo``.

Default is 'libtool=on, hammer=auto, split_crc=auto'.

``geninfo_adjust_src_path`` = *pattern* ``=>`` *replacement*
``geninfo_adjust_src_path`` = *pattern*
----------------------------------------

Adjust source paths when capturing coverage data.

Use this option in situations where geninfo cannot find the correct path to source code files of a project. By providing a *pattern* in Perl regular expression format (see ``perlre``\(1)) and an optional replacement string, you can instruct geninfo to remove or change parts of the incorrect source path.

**Example:**

1. When geninfo reports that it cannot find source file

   ::

       /path/to/src/.libs/file.c

   while the file is actually located in

   ::

       /path/to/src/file.c

   use the following parameter:

   ::

       geninfo_adjust_src_path = /.libs

   This will remove all "/.libs" strings from the path.

2. When geninfo reports that it cannot find source file

   ::

       /tmp/build/file.c

   while the file is actually located in

   ::

       /usr/src/file.c

   use the following parameter:

   ::

       geninfo_adjust_src_path = /tmp/build => /usr/src

   This will change all "/tmp/build" strings in the path to "/usr/src".

The *adjust\_src\_path* option is similar to the *substitution = ...* option - which is somewhat more general and allows you to specify multiple substitution patterns. Also see the *resolve\_script* option.

``source_directory`` = *dirname*
--------------------------------

Add 'dirname' to the list of places to look for source files. Also see the *\-\-source\-directory* entry in the ``lcov, geninfo,`` and ``genhtml`` man pages.

For relative source file paths *e.g.,* found in some *tracefile* or in gcov output, first look for the path from 'cwd' (where genhtml was invoked) and then from each alternate directory name in the order specified. The first location matching location is used.

This option can be specified multiple times, to add more directories to the source search path.

Note that the command line option overrides the RC file entries (if any).

``build_directory`` = *dirname*
--------------------------------

Add 'dirname' to the list of places to look for matching GCNO files (geninfo) or source file soft links (genhtml). See the *\-\-build\-directory* description in the ``geninfo`` and in the ``genhtml`` man page.

This option can be specified multiple times, to add more directories to the source search path.

Note that the command line option overrides the RC file entries (if any).

``geninfo_auto_base`` = *0 | 1*
--------------------------------

If non-zero, apply a heuristic to determine the base directory when collecting coverage data.

Use this option when using geninfo on projects built with libtool or similar build environments that work with multiple base directories, *i.e.* environments, where the current working directory when invoking the compiler is not the same directory in which the source code file is located, and in addition, is different between files of the same project.

Default is 1.

``geninfo_intermediate`` = *0 | 1 | auto*
------------------------------------------

Specify whether to use gcov intermediate format

Use this option to control whether geninfo should use the gcov intermediate format while collecting coverage data. The use of the gcov intermediate format should increase processing speed. It also provides branch coverage data when using the \-\-initial command line option.

Valid values are 0 for off, 1 for on, and "auto" to let geninfo automatically use immediate format when supported by gcov.

Default is "auto".

``no_exception_branch`` = *0 | 1*
---------------------------------

Specify whether to exclude exception branches from branch coverage. Whether C++ exception branches are identified and removed is dependent on your compiler/toolchain correctly marking them in the generated coverage data.

This option is used by lcov, geninfo, genhtml.

The value *no\_exception\_branch = 1* is equivalent to the *\-\-filter exception* command line option.

Default is 0.

``geninfo_chunk_size`` = *integer [%]*
--------------------------------------

Specify the number of GCDA files which should be processed per-call in each child process. This parameter affects the balance of CPU time spent in the child and thus the number of completed child processes which are queued to be merged into the parent - which then affects the queuing delay. Higher queuing delay lowers the effective parallelism.

The default is 80% of *total\_number\_of\_gcda\_files / maximum\_number\_of\_parallel\_children,* the average number of files expected to be processed by each child. See the *\-\-parallel* entry in the ``geninfo`` man page.

The argument may be either an integer value to be used as the chunk size or a percentage of the average number files processed per child.

This option has no effect unless the *\-\-parallel* option has been specified.

``geninfo_interval_update`` = *integer*
---------------------------------------

Set the percentage of GCDA files which should be processed between console/progress updates. This setting may be useful for parameter tuning and debugging apparent performance issues.

The default is 5%.

This option has no effect unless the *\-\-parallel* option has been specified.

``lcov_filter_chunk_size`` = *integer [%]*
-------------------------------------------

Specify the number of source files which should be processed per-call in each child process when applying coverpoint filters - see the ``filter = ...`` parameter, below. This parameter affects the balance of CPU time spent in the child and thus the number of completed child processes which are queued to be merged into the parent - which then affects the queuing delay. Higher queuing delay lowers the effective parallelism.

The default is 80% of *total\_number\_of\_source\_files / maximum\_number\_of\_parallel\_children.*

The argument may be either an integer value to be used as the chunk size or a percentage of the average number files processed per child.

This option has no effect unless the *\-\-parallel* option has been specified and ``lcov_filter_parallel`` is not zero.

``lcov_filter_parallel`` = *0 | 1*
----------------------------------

This option specifies whether coverpoint filtering should be done serially or in parallel. If the number of files to process is very large, then parallelization may improve performance.

This option has no effect unless the *\-\-parallel* option has been specified.

The default is 1 (enabled).

``lcov_gcov_dir`` = *path_to_kernel_coverage_data*
---------------------------------------------------

Specify the path to the directory where kernel coverage data can be found or leave undefined for auto-detection.

Default is auto-detection.

``lcov_tmp_dir`` = *temp*
--------------------------

Specify the location of a directory used for temporary files.

Default is '/tmp'.

``lcov_list_full_path`` = *0 | 1*
---------------------------------

If non-zero, print the full path to source code files during a list operation.

This option corresponds to the \-\-list\-full\-path option of ``lcov``.

Default is 0.

``lcov_list_max_width`` = *width*
---------------------------------

Specify the maximum width for list output. This value is ignored when lcov_list_full_path is non-zero.

Default is 80.

``lcov_list_truncate_max`` = *percentage*
-----------------------------------------

Specify the maximum percentage of file names which may be truncated when choosing a directory prefix in list output. This value is ignored when lcov_list_full_path is non-zero.

Default is 20.

``function_coverage`` = *0 | 1*
--------------------------------

Specify whether lcov/geninfo/genhtml should generate, process, and display function coverage data.

Turning off function coverage by setting this option to 0 can slightly reduce memory and CPU time consumption when lcov is collecting and processing coverage data, as well as reduce the size of the resulting data files.

This option can be overridden by the *\-\-function\-coverage* and *\-\-no\-function\-coverage* command line options.

Default is 1.

``branch_coverage`` = *0 | 1*
-----------------------------

Specify whether lcov/geninfo should generate, process, and display branch coverage data.

Turning off branch coverage by setting this option to 0 can reduce memory and CPU time consumption when lcov is collecting and processing coverage data, as well as reduce the size of the resulting data files.

This option can be overridden by the *\-\-branch\-coverage* and *\-\-no\-branch\-coverage* command line options.

Default is 0.

``mcdc_coverage`` = *0 | 1*
----------------------------

Specify whether lcov/geninfo should generate, process, and display Modified Condition / Decision Coverage (MC/DC) coverage data.

Turning off MC/DC coverage by setting this option to 0 can reduce memory and CPU time consumption when lcov is collecting and processing coverage data, as well as reduce the size of the resulting data files.

This option can be overridden by the *\-\-mcdc\-coverage* command line option.

Default is 0 (not enabled).

See the MC/DC section of :manpage:`genhtml(1)` for more details

``lcov_excl_line`` = *expression*
---------------------------------

Specify the regular expression of lines to exclude. Line, branch, and function coverpoints are associated with lines where this regexp is found are dropped.

There are at least 2 (moderately) common use cases for custom exclusion markers:

- You are using multiple tools for coverage analysis, each of which has its own directives, and you don't want to complicate your source code with directives for each of them.

- You want to exclude different regions/different types of code in different contexts - for example, to ignore or not ignore debug/trace code depending on your team.

Default is 'LCOV_EXCL_LINE'.

``lcov_excl_br_line`` = *expression*
------------------------------------

Specify the regular expression of lines to exclude from branch coverage. Branch coverpoints are associated with lines where this regexp is found are dropped. (Line and function coverpoints are not affected.)

Default is 'LCOV_EXCL_BR_LINE'.

``lcov_excl_exception_br_line`` = *expression*
------------------------------------------------

Specify the regular expression of lines to exclude from exception branch coverage. Exception-related Branch coverpoints associated with lines where this regexp is found are dropped. (Line, function coverpoints are not affected. Branch coverpoints which are not associated with exceptions are also not affected.)

Also see 'geninfo_no_exception_branch'; if nonzero, then all identified exception branches will be removed.

Note that this feature requires support from your compiler - and thus may not ignore all exception-related coverpoints.

Default is 'LCOV_EXCL_EXCEPTION_BR_LINE'.

``lcov_excl_start`` = *expression*
----------------------------------

Specify the regexp mark the start of an exception region All coverpoints within exception regions are dropped.

Default is 'LCOV_EXCL_START'.

``lcov_excl_stop`` = *expression*
---------------------------------

Specify the regexp mark the end of an exception region

Default is 'LCOV_EXCL_STOP'.

``lcov_excl_br_start`` = *expression*
-------------------------------------

Specify the regexp used to mark the start of a region where branch coverpoints are excluded. Line and function coverpoints within the region are not excluded.

Default is 'LCOV_EXCL_BR_START'.

``lcov_excl_br_stop`` = *expression*
------------------------------------

Specify the regexp used to mark the end of a region where branch coverpoints are excluded.

Default is 'LCOV_EXCL_BR_STOP'.

``lcov_excl_exception_br_start`` = *expression*
-------------------------------------------------

Specify the regexp used to mark the start of a region where branch coverpoints associated with exceptions are excluded. Line, function, and non-exception branch coverpoints within the region are not excluded.

Also see 'geninfo_no_exception_branch'; if nonzero, then all identified exception branches will be removed.

Note that exception branch coverpoint identification requires support from your compiler - and thus may not ignore all exception-related coverpoints.

Default is 'LCOV_EXCL_EXCEPTION_BR_START'.

``lcov_excl_exception_br_stop`` = *expression*
------------------------------------------------

Specify the regexp used to mark the end of a region where exception-related branch coverpoints are excluded.

Default is 'LCOV_EXCL_EXCEPTION_BR_STOP'.

``lcov_unreachable_line`` = *expression*
-----------------------------------------

Specify the regular expression of unreachable line which should be excluded from reporting, but should generate an "inconsistent" error if hit. That is: we believe that the marked code is unreachable, so there is a bug in the code, the placement of the directive, or both if the "unreachable" code is executed. Line, branch, and function coverpoints are associated with lines where this regexp is found are dropped.

Default is 'LCOV_UNREACHABLE_LINE'.

``lcov_unreachable_start`` = *expression*
-------------------------------------------

Specify the regexp mark the start of an unreachable code block. All coverpoints within exception regions are dropped, but the tool will generate an "inconsistent" error if any code in the block is executed.

Default is 'LCOV_UNREACHABLE_START'.

``lcov_unreachable_stop`` = *expression*
-----------------------------------------

Specify the regexp mark the end of the unreachable code block.

Default is 'LCOV_UNREACHABLE_STOP'.

``fail_under_branches`` = *percentage*
---------------------------------------

Specify branch coverage threshold: if the branch coverage is below this threshold, lcov/genhtml/geninfo will generate all the normal result files and messages, but will return a non-zero exit code.

This option is equivalent to the \-\-fail\-under\-branches lcov/genhtml/geninfo command line argument. See :manpage:`lcov(1)` for more details.

The default is 0 (no threshold).

``retain_unreachable_coverpoints_if_executed`` = *[0 | 1]*
-----------------------------------------------------------

Specify whether coverpoints in "unreachable" regions which are 'hit' are dropped (0) - because the region is excluded - or retained (1) - because the directive appears to be incorrect. See the "Exclusion markers" section in :manpage:`geninfo(1)` for more details.

The default is 1 (retain the coverpoints).

``fail_under_lines`` = *percentage*
-----------------------------------

Specify line coverage threshold to lcov. If the line coverage is below this threshold, lcov/genhtml/geninfo will generate all the normal result files and messages, but will return a non-zero exit code.

This option is equivalent to the \-\-fail\-under\-lines lcov/genhtml/geninfo command line argument.

The default is 0 (no threshold).

``profile`` = *filename*
-------------------------

If set, tells genhtml, lcov, or geninfo to generate some execution time/profile data which can be used to motivate future optimizations. It is equivalent to the *\-\-profile* command line option.

If *filename* is empty, then the profile is written to the default location chosen by the application.

This option is used by genhtml, lcov, and geninfo.

The default is unset: no data generated.

``parallel`` = *integer*
-------------------------

Tells genhtml, lcov, or geninfo the maximum number of simultaneous processes to use. Zero means to use as many cores as are available on the machine. The default is 1 (one) - which means to process sequentially (no parallelism).

This option is used by genhtml, lcov, and geninfo.

``memory`` = *integer\_Mb*
---------------------------

Tells genhtml, lcov, or geninfo the maximum memory to use during parallel processing operations. Effectively, the process will not fork() if this limit would be exceeded. Zero means that there is no limit. The default is 0 (zero) - which that there is no explicit limit.

This option is used by genhtml, lcov, and geninfo.

``memory_percentage`` = *number*
--------------------------------

Tells genhtml, lcov, or geninfo the maximum memory to use during parallel processing operations. Maximum is computed as a percentage of the total memory available on the system; for example, '75' would use limit to 75% of total memory, whereas 150.5 would limit to 150.5% (*i.e.,* larger than the total available. Effectively, the process will not fork() if this limit would be exceeded. Note that this value is used only if the maximum memory value is not set explicitly - either by a the *\-\-memory* command line option or the *memory = integer* configuration file setting.

The default is not set.

This option is used by genhtml, lcov, and geninfo.

``max_fork_fails`` = *integer*
--------------------------------

Tells genhtml, lcov, or geninfo the number of consecutive fork() failures to ignore during *\-\-parallel* execution before giving up. Note that genhtml/lcov/geninfo fail and stop immediately unless the *fork* error message ignored - either via the *ignore\_errors* directive (above), the *\-\-ignore\-errors* command line option, or if *stop\_on\_error* is disabled or the *\-\-keep-going* command line option is used.

The default fork failure maximum is 5.

``fork_fail_timeout`` = *integer\_seconds*
-------------------------------------------

Tells genhtml, lcov, or geninfo how long to wait after a fork() failure before retrying.

The default is 10 (seconds).

``max_tasks_per_core`` = *integer*
-----------------------------------

This is the maximum number of files that genhtml will handle in a single child process during parallel execution.

The default is 20.

``genhtml_date_bins`` = *integer[,integer..]*
----------------------------------------------

This option is equivalent to the "genhtml \-\-date\-bins" option. See :manpage:`genhtml(1)` for details.

This option can be used multiple times in the lcovrc file to set multiple cutpoints.

``genhtml_datelabels`` = *string[,string..]*
--------------------------------------------

This option is equivalent to the "genhtml \-\-date\-labels" option. See :manpage:`genhtml(1)` for details.

This option can be used multiple times in the lcovrc file to set multiple labels. The number of labels should equal one greater than number of cutpoints.

``genhtml_annotate_script`` = *path_to_executable | parameter*
---------------------------------------------------------------

This option is equivalent to the "genhtml \-\-annotate\-script" option.

This option can be used multiple times in the lcovrc file to specify both an annotation script and additional options which are passed to the script.

See the genhtml man page for details.

``genhtml_annotate_tooltip`` = *tooltip\_string*
-------------------------------------------------

This option sets the 'tooltip' popup which appears if user hovers mouse over the associated source code. Note that the tooltip is generated only if the annotation-script callback is successful and returns a commit ID other than "NONE". Set *tooltip\_string* to "" (empty string) to force genhtml to not produce the tooltip.

Substitutions are performed on *tooltip\_string:*

-  ``%C:`` commit ID (from annotate callback - see *\--annotate-script* entry in the ``genhtml`` man page)

-  ``%U:`` commit author abbreviated name (returned by annotate callback)

-  ``%F:`` commit author full name (returned by annotate callback)

-  ``%D:`` commit date (as returned by annotate callback)

-  ``%d:`` commit date with time of day removed (*i.e.*, date part only)

-  ``%A:`` commit age.

-  ``%l`` source line number.

``context_script`` = *path_to_executable_or_module | parameter*
---------------------------------------------------------------

This option is equivalent to the *\-\-context\-script* option of genhtml/lcov/geninfo

This option can be used multiple times in the lcovrc file to specify both a criteria script and additional options which are passed to the script.

See the genhtml man page for details.

``criteria_script`` = *path_to_executable_or_module | parameter*
----------------------------------------------------------------

This option is equivalent to the *\-\-criteria\-script* option of genhtml/lcov/geninfo

This option can be used multiple times in the lcovrc file to specify both a criteria script and additional options which are passed to the script.

See the genhtml man page for details.

``criteria_callback_data`` = *comma_separated_list*
-----------------------------------------------------

This option is used to tell genhtml whether you want date and/or owner summary data passed back to your criteria callback. Note that summary data is always passed.

Note that lcov and geninfo do not record date or owner data - and so do not pass it to the callback.

This option can be used multiple times in the lcovrc file to specify both date and owner data should be returned, or you can specify both in a comma-separated list. Date and/or owner data will be returned if and only if your genhtml command has enabled annotation.

If this option is appears multiple times in the lcovrc file; the values are combined to form the list of binning types which are passed to your callback.

See the genhtml man page for details.

``criteria_callback_levels`` = *comma_separated_list*
------------------------------------------------------

This option is used to tell genhtml whether criteria callbacks should occur at the top, directory, or file level.

If this option is appears multiple times in the lcovrc file, the values are combined to form the list of report levels when your callback will be executed.

See the genhtml man page for details.

``check_existence_before_callback`` = *0 | 1*
----------------------------------------------

This option configures the tool to check that the file exists before calling the *annotate-script* or *version-script* callback. If set and file does not exist, a ``source`` error is triggered. (Note that the error may be ignored - see the *\-\-ignore\-error* option.)

You may want to NOT check for file existence if your callback looks up information in a non-local repository.

The default is 1 (check for file existence).

``compute_file_version`` = *0 | 1*
-----------------------------------

This option is used to tell the tool to generate missing file version information when reading a .info (coverage data) file. Version information may be missing because the data was generated by a tool which did not support versioning, or because the data was generated without the required *\-\-version\-script* argument - or for some other reason.

Note that this option has no effect without a version\-script callback - defined by either the *\-\-version\-script* command line option or the *version\_script* config file option.

The default is 0: do not generate missing information.

``version_script`` = *path_to_executable | parameter*
-----------------------------------------------------

This option is equivalent to the geninfo/lcov/genhtml "\-\-version\-script" option.

This option can be used multiple times in the lcovrc file to specify both a version script and additional options which are passed to the script.

See the genhtml man page for details.

``resolve_script`` = *path_to_executable | parameter*
-----------------------------------------------------

This option is equivalent to the geninfo/lcov/genhtml "\-\-resolve\-script" option.

This option can be used multiple times in the lcovrc file to specify both a resolve script and additional options which are passed to the script.

The resolve script provides a mechanism to find a source or data file that cannot be found by simply modify paths via substitution patterns (see *"substitute = replace\_regexp"* above) and searching along the corresponding directory list:

``geninfo``:
  the *"'build\_directory = dirname'"* config file entry or *\-\-build\=directory* command line option, used to search for GCNO files,

``geninfo/genhtml/lcov``:
  the *"'source\_directory = dirname'"* config file entry or *\-\-source\=directory* command line option, used to search for source files.

The resolve script is called as:

``resolve_script`` [callback_args] *file_name*

or

*$resolve_callback* = ``resolve_module`` ->new([callback_args])

to initialize the callback, then

*$resolve\_callback*->``resolve`` *(file_name)*

to find the actual file location.

If necessary, the callback can check the suffix of the filename to determine whether it should look for either a source or data file.

The script should return either empty string (file not found/no such file) or the actual path name. The returned path may be either absolute or relative to CWD.

``select_script`` = *path_to_executable | parameter*
-----------------------------------------------------

This option is equivalent to the genhtml "\-\-select\-script" option.

This option can be used multiple times in the lcovrc file to specify both a select script and additional options which are passed to the script.

The select script provides a mechanism to decide whether a particular source line is interesting - whether it should be included in the generated coverage report - or not.

Lines which are not selected but fall within *num\_context\_lines* of a selected line are also included in the report. See below.

Note that selection is fundamentally intended to show regions of code with some surrounding context. It might not do what you expect if there is no code - *e.g.*, if the region of interest has been compiled out via compiler or exclusion directives. For example: when selecting based on SHA or changelist ID, an inserted comment will not be selected unless it is within *num\_context\_lines* of an inserted or changed line of code.

The select script is called as:

``select_script`` [callback_args] *lineDataJson annotateDataJson fileName lineNumber*

or as:

*$selectCallback* = ``select_module`` ->new([callback_args])

to initialize the callback object, then as

*$selectCallback* ``select`` *(lineDataRef annotateDataRef fileName lineNumber)*

to determine selection, where

- *fileName* is the name of the source file and

- *lineNumber* is the source file line number, indexed from zero,

- *lineDataJson* is a json-encoded LineData structure (see the lcovutil.pm source code), and

- *annotateDataJson* is the json-encoded data returned by your *annotate\-script* (see the *\-\-annotate\-script* parameter in :manpage:`genhtml(1)`.), or the empty string if there are no annotations for this file.

The module callback is similar except that is passed objects rather than JSON encodings of the objects.

The script should return "1" or "0".

See example implementation ``$|TOOL_NAME|_HOME/share/lcov/support-scripts/select.pm``.

``unreachable_script`` = *path_to_module | parameter*
-----------------------------------------------------

This option is equivalent to the geninfo/lcov/genhtml "\-\-unreachable\-script" option.

This option can be used multiple times in the lcovrc file to specify both a module script and additional options which are passed to the callback.

See the genhtml man page for details.

``num_context_lines`` =  *integer*
----------------------------------

Set the number of lines around each selected line which is included in the report - see *select\_script = ...* above and the *\-\-select\-script* command line option in :manpage:`genhtml(1)`.

``filter`` = *str[,str...]*
----------------------------

This option is equivalent to the \-\-filter option to geninfo, lcov, and genhtml. See the genhtml man page for details.

This option can be used multiple times in the lcovrc file to enable multiple filters. The filters specified in the lcovrc file are appended to the list specified on the command line.

This option is used by genhtml, lcov, and geninfo.

``exclude`` = *glob_pattern*
----------------------------

This option is equivalent to the \-\-exclude option to geninfo, lcov, and genhtml. See the lcov man page for details.;

This option can be used multiple times in the lcovrc file to specify multiple patterns to exclude. The patterns specified in the lcovrc file are appended to the list specified on the command line.

This option is used by genhtml, lcov, and geninfo.

``include`` = *glob_pattern*
-----------------------------

This option is equivalent to the \-\-include option to geninfo, lcov, and genhtml. See the lcov man page for details.;

This option can be used multiple times in the lcovrc file to specify multiple patterns to include. The patterns specified in the lcovrc file are appended to the list specified on the command line.

This option is used by genhtml, lcov, and geninfo.

``simplify_script`` = *path_to_executable | parameter*
------------------------------------------------------

This option is equivalent to the genhtml *\-\-simplify\-script* option. This option can be used multiple times in the lcovrc file to specify both a simplify script and additional options which are passed to the script.

See :manpage:`genhtml(1)` for details.

``substitute`` = *regexp*
--------------------------

This option is equivalent to the \-\-substitute option to geninfo, lcov, and genhtml. See the lcov man page for details.;

This option can be used multiple times in the lcovrc file to specify multiple substitution patterns. If patterns are specified on both the command line and in the lcovrc file, then the command line patterns are used and the lcovrc patterns are dropped.

This option is used by genhtml, lcov, and geninfo.

``omit_lines`` = *regexp*
--------------------------

This option is equivalent to the \-\-omit\-lines option to geninfo, lcov, and genhtml. See the genhtml man page for details.

This option can be used multiple times in the lcovrc file to specify multiple patterns to exclude. The patterns specified in the lcovrc file are appended to the list specified on the command line.

This option is used by genhtml, lcov, and geninfo.

``erase_functions`` = *regexp*
-------------------------------

This option is equivalent to the \-\-erase\-functions option to geninfo, lcov, and genhtml. See the genhtml man page for details.

This option can be used multiple times in the lcovrc file to specify multiple patterns to exclude. The patterns specified in the lcovrc file are appended to the list specified on the command line.

This option is used by genhtml, lcov, and geninfo.

``lcov_json_module`` = *module | auto*
---------------------------------------

Specify the JSON module to use, or choose best available from a set of alternatives if set to 'auto'. Note that some JSON modules are slower than others (notably JSON::PP can be very slow compared to JSON::XS).

Default is 'auto'.

``split_char`` = *char*
------------------------

Specify the character (or regexp) used to split list-like parameters which have been passed as a single string. This parameter is useful in the case that you need want to use a multi-option string but one or more of the options contains a comma character which would otherwise be seen as a delimiter.

Default is ',' (comma - no quotes).

``scope_regexp`` = *regexp*
----------------------------

Print debug messages for data in filenames which match *regexp.* Only certain categories of message are logged; the set changes from time to time - depending on debug need.

``case_insensitive`` = *[0|1]*
--------------------------------

Specify whether string comparison is case insensitive when finding matching filenames, checking include/exclude directives, etc.

Note that mixed-case or lower-case pathnames may be passed to your \-\-version\-script and \-\-annotate\-script callbacks when case-insensitive matching is used. Your callbacks must handle potential differences in case.

Default is '0': case sensitive matching.

``sort_input`` = *[0|1]*
--------------------------

Specify whether to sort file names before capture and/or aggregation. Sorting reduces certain types of processing order-dependent output differences - *e.g.,* due to ambiguities in branch data generated by gcc.

Default is '0': no sorting - process files in the order they were specified on the command line and/or were found during traversal of the filesystem.


FILES
-----

*$|TOOL_NAME|_HOME/etc/lcovrc*
   The system-wide ``lcov`` configuration file.

*\~/.lcovrc*
   The individual per-user configuration file.

SEE ALSO
--------

:manpage:`lcov(1)`, :manpage:`genhtml(1)`, :manpage:`geninfo(1)`, :manpage:`gcov(1)`
