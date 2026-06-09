=================================================================
genhtml - generate HTML view from |ToolName| coverage data files
=================================================================

NAME
----

genhtml 
 Generate HTML view from |ToolName| coverage data files - including differential coverage analysis, age and author binning, and various visualization options.


SYNOPSIS
--------

::

    genhtml [ -h | --help ] [ --version ]
        [ -q | --quiet ]
        [ -v | --verbose ]
        [ --debug ] [ --validate ]
        [ -s | --show-details ]
        [ -f | --frames ]
        [ -b | --baseline-file baseline-file-pattern ]
        [ -o | --output-directory output-directory ]
        [ --header-title banner ]
        [ --footer string ]
        [ -t | --title title ]
        [ -d | --description-file description-file ]
        [ -k | --keep-descriptions ] [ -c | --css-file css-file ]
        [ -p | --prefix prefix ] [ --no-prefix ]
        [ --build-directory directory ]
        [ --source-directory dirname ]
        [ --no-source ] [ --no-html ]
        [ --num-spaces num ] [ --highlight ]
        [ --legend ] [ --html-prolog prolog-file ]
        [ --html-epilog epilog-file ] [ --html-extension extension ]
        [ --html-gzip ] [ --sort-tables ] [ --no-sort ]
        [ --function-coverage ] [ --no-function-coverage ]
        [ --branch-coverage ] [ --no-branch-coverage ]
        [ --mcdc-coverage ]
        [ --demangle-cpp [ param ] ]
        [ --msg-log [ log_file_name ] ]
        [ --ignore-errors errors ]
        [ --expect-message-count message_type=expr[,message_type=expr..] ]
        [ --keep-going ] [ --config-file config-file ]
        [ --profile [ profile-file ] ]
        [ --history-script callback ]
        [ --rc keyword = value ]
        [ --precision num ] [ --missed ]
        [ --merge-aliases ]
        [ --suppress-aliases ]
        [ --forget-test-names ]
        [ --dark-mode ]
        [ --baseline-title title ]
        [ --baseline-date date ]
        [ --current-date date ]
        [ --diff-file diff-file ]
        [ --annotate-script script ]
        [ --context-script script ]
        [ --criteria-script script ]
        [ --version-script script ]
        [ --resolve-script script ]
        [ --select-script script ]
        [ --simplify-script script ]
        [ --unreachable-script module ]
        [ --checksum ]
        [ --fail-under-branches percentage ]
        [ --fail-under-lines percentage ]
        [ --new-file-as-baseline ]
        [ --elide-path-mismatch ]
        [ --synthesize-missing ]
        [ --date-bins day[,day,...] ]
        [ --date-labels string[,string,...] ]
        [ --show-owners [ all ] ]
        [ --show-noncode ]
        [ --show-zero-columns ]
        [ --show-navigation ]
        [ --show-proportions ]
        [ --simplified-colors ]
        [ --hierarchical ] [ --flat ]
        [ --filter filters ]
        [ --include glob_pattern ]
        [ --exclude glob_pattern ]
        [ --erase-functions regexp_pattern ]
        [ --substitute regexp_pattern ]
        [ --omit-lines regexp_pattern ]
        [ --parallel | -j [ integer ] ]
        [ --memory integer_num_Mb ]
        [ --tempdir dirname ]
        [ --preserve ]
        [ --save ]
        [ --sort-input ]
        [ --serialize serialize_output_file ]
        tracefile_pattern(s)

DESCRIPTION
-----------

``genhtml`` creates an HTML view of coverage data found in tracefiles ``geninfo`` and ``lcov`` tools which are found from glob-match pattern(s) *tracefile_pattern*. See :manpage:`geninfo(1)` for a description of the tracefile format.

Features include:

- Differential coverage comparison against baseline coverage data

- Annotation of reports with date and owner information ("binning")

The basic concepts of differential coverage and date/owner binning are described in the paper found at *https://arxiv.org/abs/2008.07947*


Differential coverage
~~~~~~~~~~~~~~~~~~~~~

Differential coverage compares two versions of source code - the baseline and the current versions - and the coverage results for each to segment the code into categories.

To create a differential coverage report, ``genhtml`` requires

1. one or more *baseline-files* specified via ``--baseline-file``, and

2. a patch file in unified format specified using ``--diff-file``.

Both *tracefile_pattern* and *baseline-file* are treated as glob patterns which match one or more files.

The difference in coverage between the set of *tracefiles* and *baseline-files* is classified line-by-line into categories based on changes in 2 aspects:

1. **Test coverage results**:\  a line of code can be tested (1), untested (0), or unused (#). An unused line is a source code line that has no associated coverage data, for example due to a disabled #ifdef statement.

2. **Source code changes**:\  a line can be unchanged, added (+ =>), or removed (=> -). Note that the diff-file format used by ``genhtml`` reports changes in lines as removal of old line and addition of new line.

Below are the resulting 12 categories, sorted by priority (assuming that untested code is more interesting than tested code, and new code is more interesting than old code):


**UNC**
   Uncovered New Code (+ => 0): newly added code is not tested.

**LBC**
   Lost Baseline Coverage (1 => 0): unchanged code is no longer tested.

**UIC**
   Uncovered Included Code (# => 0): previously unused code is untested.

**UBC**
   Uncovered Baseline Code (0 => 0): unchanged code was untested before, is untested now.

**GBC**
   Gained Baseline Coverage (0 => 1): unchanged code is tested now.

**GIC**
   Gained Included Coverage (# => 1): previously unused code is tested now.

**GNC**
   Gained New Coverage (+ => 1): newly added code is tested.

**CBC**
   Covered Baseline Code (1 => 1): unchanged code was tested before and is still tested.

**EUB**
   Excluded Uncovered Baseline (0 => #): previously untested code is unused now.

**ECB**
   Excluded Covered Baseline (1 => #): previously tested code is unused now.

**DUB**
   Deleted Uncovered Baseline (0 => -): previously untested code has been deleted.

   Note: Because these lines are not represented in the current source version, they are only represented in the classification summary table.

**DCB**
   Deleted Covered Baseline (1 => -): previously tested code has been deleted.

   Note: Because these lines are not represented in the current source version, they are only represented in the classification summary table.

The differential coverage report colorizes categorized regions in the source code view using unique colors for each. You can use the ``--simplified-colors`` option to instead use one color for 'covered' code and another for 'uncovered'.


Date and owner binning
~~~~~~~~~~~~~~~~~~~~~~

**Date binning** annotates coverage reports with age-of-last-change information to distinguish recently added or modified code which has not been tested from older, presumed stable code which is also not tested. **Owner binning** adds annotation identifying the author of changes.

Both age and ownership reporting can be used to enhance team efforts to maintain good coverage discipline by spotlighting coverage shortfalls in recently modified code, even in the absence of baseline coverage data.

To enable date and owner binning, the ``--annotate-script`` option must be used to specify a script that provides source code line age and ownership information.

For each source line, age is the interval since the most recent modification date and the owner is the user identity responsible for the most recent change to that line.

Line coverage overall totals and counts for each of the 12 classification categories are collected for each of the specified age ranges (see the ``--date-bins`` option, below).


Script conventions
~~~~~~~~~~~~~~~~~~

Some ``genhtml`` options expect the name of an external script or tool as argument. These scripts are then run as part of the associated function. This includes the following options:

::

   --annotate-script
   --context-script
   --criteria-script
   --history-script
   --resolve-script
   --select-script
   --simplify-script
   --unreachable-script
   --version-script

While each script performs a separate function there are some common aspects in the way these options are handled:

1. If the callback script name ends in ``.pm`` then the script is assumed to be a Perl module.

   A perl module may offer performance advantages over an external script, as it is compiled once and loaded into the interpreter and because it can load and maintain internal state.

   The module is expected to export a method 'new', which is called with the script name and the script parameters (if any) as arguments. It is expected to return an object which implements several standard methods:

   ``$callback_obj =`` *packagename* ``->new(perl_module_file, args);``

   version-script
      ``$version = $callback_obj->extract_version($source_file_ename);``

      ``$match = $version->check_version($old_version, $new_version, $source_file_name);``

      *$match* is expected to be 1 (true) if the version keys refer to the came file and 0 (false) otherwise.

   *$version*
      is a string representing a unique identifier of the particular version of the file

   See example implementations ``*$|TOOL_NAME|_HOME/share/lcov/support-scripts/gitversion.pm`` and ``$|TOOL_NAME|_HOME/share/lcov/support-scripts/getp4version.pm``.

   annotate-script
      ``($status, $array) = $callback_obj->annotate($source_file_name);``

      where

      *$status*
         is 0 if the command succeeded and nonzero otherwise. *$status* is interpreted in same way as the return code from 'system(..)'

      *$array*
         is a list of line data of the form:

         ``[$text, $abbrev, $full_name, $when, $changelist]``.

      and

      *$text*
         is the source text from the corresponding line (without newline termination)

      *$abbrev*
         is the "abbreviated author name" responsible for this line of code. This is the name that will be used in the various HTML tables. For example, for brevity/readability, you may want to strip the domain from developers who are inside your organization. If there is no associated author, then the value should be *\"NONE\"*.

      *$full_name*
         is the "full author name" which is used in annotation tooltips. See the *genhtml_annotate_tooltip* entry in :manpage:`lcovrc(5)`. *$fullname* may be *undef* if the full name and abbreviated names are the same.

      *$when*
         is the timestamp associated with the most recent edit of the corresponding line and may be *\"NONE\"* if there is no associated time.

      *$changelist*
         is the commit identifier associated with the most recent change to this line, or *\"NONE\"* if there isn't one.

   See example implementations ``$|TOOL_NAME|_HOME/share/lcov/support-scripts/gitblame.pm`` and ``$|TOOL_NAME|_HOME/share/lcov/support-scripts/p4annotate.pm``.

   context-script
      ``$hash = $callback_obj->context();``

      where *$hash* is a reference to a hash of key/value pairs which are meaningful to you. This data is stored in the *profile* database. See the 'profile' section in :manpage:`lcovrc(5)` for more information.

      If your callback is not a perl module - for example, is a shellscript - then it should return a string such that the first word on each line is the key and the remainder is the associated data. If a key is repeated, then the corresponding data strings are concatenated, separated by newline.

      If you want to record only system information, then a shell callback is likely sufficient. If you want to record any tool-specific/internal information, then you will need to implement a perl module so that your callback will be able to access the information.

      Note that the constructor of your *context-script* callback (or of any callback) can perform any additional actions which are required - for example, to write additional files, to query or set tool-specific information, *etc.* For example, the example implementation, below, has an option to append comments to the generated .info file.

      See the example implementation ``$|TOOL_NAME|_HOME/share/lcov/support-scripts/context.pm``.

   criteria-script
      ``($status, $array) = $callback_obj->check_criteria($obj_name, $type, $json);``

      where

      *$obj_name*
         is the source file or directory name, or "top" of the object whose coverage criteria is being checked.

      *$type*
         is the object type - either *\"file\"*, *\"directory\"*, or *\"top\"*.

      *$json*
         is the coverage data associated with this object, in JSON format - see below.

      *$status*
         is the return status of the operation, interpreted the same way as the *annotate* callback status, described above.

      *$array*
         is a reference to a possibly empty list of strings which will be reported by genhtml. The strings are expected to explain why the coverage criteria failed.

      See example implementations ``$|TOOL_NAME|_HOME/share/lcov/support-scripts/criteria.pm``.

   history-script
      ``$cpu_seconds = $callback_obj->history($element_name)``

      where *$cpu_seconds* is the predicted time taken to process *$element_name* or *undef* if there is no prediction/the element is unknown.

      See the sample implementation ``scripts/history.pm``,
      which uses the *--profile* data generated by a previous ``genhtml`` execution to predict the time required this time.

      The prediction may improve load balancing - and thus improve overall runtime performance (*i.e.*, because we won't be waiting for some "long pole" task to complete while all other threads are idle.

   resolve-script
      ``$newpath = $callback_obj->resolve($source_file_name)``

      where *$newpath* is the correct path to the indicated source file or *undef* if the source file is not found by the callback.

   simplify-script
      ``$new_func_name = $callback_obj->simplify($orig_func_name)``

      where *$new_func_name* is the function name which will appear in the function detail table and *$orig_func_name* is the (possibly demangled) function name found in the coverage DB.

      Note that the modified name is only used in the "function detail" table and does not modify information in the coverage DB.

   unreachable-script
      ``$data_changed = $callback_obj->exclude($type, $source, $summary, $testdata);``

      where *$data_changed* is non-zero if coverage data was changed in the callback, *$type* is either "branch" or "mcdc", *$source* is a "ReadCurrentSource" object, *$summary* is the coverage summary across all testcases, and *$testdata* is the per-testcase coverage data.

      See the sample implementation ``.../scripts/unreach.pm``
      for a simple example callback which uses source code annotations to indicate branch expressions and/or MC/DC conditions which are excluded. See the comment at the top of the file for script usage directions.

      More sophisticated unreachability analysis is easy to visualize. For example, one could use reachability data from the compiler or another tool, rather than relying on user annotation.

      Note that the *--unreachable-script* callback must be a Perl module. Unlike the other callbacks, generic scripts are not supported.

2. The option may be specified as a single *split_char* separated string which is divided into words (see :manpage:`lcovrc(5)`), or as a list of arguments. The resulting command line is passed to a shell interpreter to be executed. The command line includes the script path followed by optional additional parameters separated by spaces. Care must be taken to provide proper quoting if script path or any parameter contains spaces or shell special characters.

   Note that module callbacks must be called via the 'list' method: they cannot be called as an executable with a space-separated set of arguments.

   For convenience: your callback module may need to implement its own 'split_char' so that you can pass multiple parameters to your callback without interacting with genhtml's split mechanism.

3. If an option is specified multiple times, then the parameters are *not* split, but are simply concatenated to form the command line - see the examples, below.

   For simplicity and ease of understanding: your command line should pass all arguments individually, or all as a comma-separated list - not a mix of the two.

4. ``genhtml`` passes any additional parameters specified via option arguments between the script path and the parameters required by the script's function.

Example:

   ::

      genhtml --annotate-script /bin/script.sh
              --annotate-script arg0 ...

   results in the same callback as

   ::

      genhtml --annotate-script "/bin/script.sh arg0" ...

   or

   ::

      genhtml --annotate-script /bin/script.sh,arg0 ...

   Note that the first form is preferred.

The resulting ``genhtml`` callback executes the command line:

   ::

      /bin/script.sh arg0 *source_file_name*

Similarly

   ::

      genhtml --annotate-script */bin/myMoodule.pm*
              --annotate-script arg0 --annotate-script arg1 ...

   or

   ::

      genhtml --annotate-script */bin/myMoodule.pm,arg0,arg1*

result in ``genhtml`` executing

   ::

      $annotateCallback = myModule->new(arg0, arg1);

to initialize the class object - *arg0* and *arg1* passed as strings - and then to execute

   ::

      ($status, $arrayRef) = $annotateCallback(*source_file_name*);

to retrieve the annotation information.

In contrast, the command

   ::

      genhtml --annotate-script */bin/myMoodule.pm*
              --annotate-script arg0,arg1 ...

would result in ``genhtml`` initializing the callback object via

   ::

      $annotateCallback = myModule->new("arg0,arg1");

where "arg0,arg1" is passed as single comma-separated string.

Similarly, the command

   ::

      genhtml --annotate-script */bin/myMoodule.pm,arg0*
              --annotate-script arg1 ...

would very likely result in an error when genhtml tries to find a script called ``/bin/mymodule.pm,arg0``.

Note that multiple instances of each script may execute simultaneously if the ``--parallel`` option was specified. Therefore each script must either be reentrant or should arrange for its own synchronization, if necessary.

In particular, if your callback is implemented via a perl module:

   - the class object associated with the module will initialized once (in the parent process)

   - The callback will occur in the child process (possibly simultaneously with other child processes).

   As a result: if your callback needs to pass data back to the parent, you will need to arrange a communication mechanism to do so.


Callbacks and parallel execution
--------------------------------

Because callbacks may need to record data - *e.g.*, for error reporting or action summaries in the presence of parallel execution - ``genhtml`` (and ``lcov`` and ``geninfo``\ ) can call certain optional callback methods:

   - ``$callback->start()``

   is called when the child process begins execution. This method can be used to capture initial state - *e.g.*, to set the count of events in this child to zero. This method is optional.

   - ``my $data = $callback->save()``

   is called when processing is complete, just before the child process exits. The scalar *$data* returned by your *$callback*\ ``->save()`` method *$callback*\ ``->restore()`` method when the child process is reaped.

   - ``$callback->restore($data)``

   is called in the parent process when the child is reaped. *$data* is the data that was returned when your *$callback*\ ``->save()`` method was called in the child. (Serialization/deserialization has happened under the covers.)

   - ``$callback->finalize()``

   is called in the parent process when all calculations are complete and the parent setting up to report final results. This method is optional.

   Note that, unlike the other callback methods described in this section, *finalize()* is called in both parallel and serial execution contexts.

Note that your callback must implement ``$callback->restore()`` if it implements ``$callback->save()``.
``$callback->start()`` and ``$callback->finalize()`` are optional: if they are implemented, then they will be called.

These methods are available only for callbacks implemented a perl modules. If you callback is implemented as an executable script (say) - then you are free to implement parent/child data passing however you prefer.


Additional considerations
~~~~~~~~~~~~~~~~~~~~~~~~~~

If the ``--criteria-script`` option is used, genhtml will use the referenced script to determine whether your coverage criteria have been met - and will return a non-zero status and print a message if the criteria are not met.

The ``--version-script`` option is used to verify that the same/compatible source code versions are displayed as were used to capture coverage data, as well as to verify that the same source code was used to capture coverage information which is going to be merged and to verify that the source version used for filtering operations is compatible with the version used to generate the data.

HTML output files are created in the current working directory unless the ``--output-directory`` option is used. If *tracefile* or *baseline-file* ends with ".gz", it is assumed to be GZIP-compressed and the gunzip tool will be used to decompress it transparently.

Note that all source code files have to be present and readable at the exact file system location they were compiled, and all path references in the input data ".info" and "diff" files must match exactly (*i.e.*, exact string match).

Further, the ``--version-script``, ``--annotate-script``, and ``--criteria-script`` scripts use the same path strings. However, see the ``--substitute`` and ``--resolve-script`` options for a mechanism to adjust extracted paths so they match your source and/or revision control layout.

You can use the *check_existence_before_callback* configuration option to tell the tool to check that the file exists before calling the ``--version-script`` or ``--annotate-script`` callback. See :manpage:`lcovrc(5)` for details.


Additional options
~~~~~~~~~~~~~~~~~~

Use option ``--diff-file`` to supply a unified diff file that represents the changes to the source code files between the version used to compile and capture the baseline trace files, and the version used to compile and capture the current trace files.

Use option ``--css-file`` to modify layout and colors of the generated HTML output. Files are marked in different colors depending on the associated coverage rate.

By default, the coverage limits for low, medium and high coverage are set to 0-75%, 75-90% and 90-100% percent respectively. To change these values, use configuration file options.

   *genhtml_hi_limit* and *genhtml_med_limit*

or type-specific limits:

   *genhtml_line_hi_limit* and *genhtml_line_med_limit*
   *genhtml_branch_hi_limit* and *genhtml_branch_med_limit*
   *genhtml_function_hi_limit* and *genhtml_function_med_limit*

See :manpage:`lcovrc(5)` for details.

Also note that when displaying percentages, 0% and 100% are only printed when the values are exactly 0% and 100% respectively. Other values which would conventionally be rounded to 0% or 100% are instead printed as nearest non-boundary value. This behavior is in accordance with that of the :manpage:`gcov(1)` tool.

By default, ``genhtml`` reports will include both line and function coverage data. Neither branch or MC/DC data is displayed by default; you can use the ``--branch-coverage`` and ``--mcdc-coverage`` options to enable branch or MC/DC coverage, respectively - or you can permanently enable branch coverage by adding the appropriate settings to your personal, group, or site lcov configuration file. See the *branch_coverage* and *mcdc_coverage* sections of :manpage:`lcovrc(5)` for details.


OPTIONS
-------

In general, (almost) all ``genhtml`` options can also be specified in your personal, group, project, or site configuration file - see :manpage:`lcovrc(5)` for details.


``-h``, ``--help``
   Print a short help text, then exit.

``--version``
   Print version number, then exit.

``-v``, ``--verbose``
   Increment informational message verbosity. This is mainly used for script and/or flow debugging - *e.g.*, to figure out which data files are found, where. Also see the --quiet flag.

``-q``, ``--quiet``
   Decrement informational message verbosity.

   Decreased verbosity will suppress 'progress' messages for example - while error and warning messages will continue to be printed.

``--debug``
   Increment 'debug messages' verbosity. This is useful primarily to developers who want to enhance the lcov tool suite.

``--validate``
   Check the generated HTML to verify that there are no dead hyperlinks and no unused files in the output directory. The checks can also be enabled by setting environment variable ``LCOV_VALIDATE = 1``. This option is primarily intended for use by developers who modify the HTML report.

``--flat``, ``--hierarchical``
   Use the specified HTML report hierarchy layout.

   The default HTML report is 3 levels:

   1. **top-level**:\  table of all directories,

   2. **directory**:\  table of source files in a directory, and

   3. **source file detail**:\  annotated source code.

   Option ``--hierarchical`` produces a multilevel report which follows the directory structure of the source code (similar to the file tool in Microsoft Windows).

   Option ``--flat`` produces a two-level HTML report:

   1. **top-level**:\  table of all project source files, and

   2. **source file detail**:\  annotated source code.

   The 'flat' view can reduce the number of clicks required to navigate around the coverage report - but is unwieldy except for rather small projects consisting of only a few source files. It can be useful in 'code review' mode, even for very large projects (see the *--select-script* option).

   Most large projects follow a rational directory structure - which favors the 'hierarchical' report format. Teams responsible for a particular module can focus on a specific subdirectory or set of subdirectories.

   Only one of options ``--flat`` or ``--hierarchical`` can be specified at the same time.

   These options can also be persistently set via the lcovrc configuration file using either:

   *genhtml_hierarchical* = 1

   or

   *genhtml_flat_view* = 1

   See :manpage:`lcovrc(5)` for details.

``-f``, ``--frames``
   Use HTML frames for source code view.

   If enabled, a frameset is created for each source code file, providing an overview of the source code as a "clickable" image. Note that this option will slow down output creation noticeably because each source code character has to be inspected once. Note also that the GD.pm Perl module has to be installed for this option to work (it may be obtained from http://www.cpan.org).

   This option can also be controlled from the *genhtml_frames* entry of the ``lcovrc`` file.

   Please note that there is a bug in firefox and in chrome, such that enabling frames will disable hyperlinks from the 'directory' level summary table entry to the first line in the corresponding file in the particular category - *e.g.*, to the first 'MIS' line (vanilla coverage report - see the .i --show-navigation option, below), to the first 'UNC' branch (differential coverage report), etc. Hyperlinks from the summary table at the top of the 'source detail' page are not affected.

``-s``, ``--show-details``
   Generate detailed directory view.

   When this option is enabled, ``genhtml`` generates two versions of each source file file entry in the corresponding summary table:

   - one containing the standard information plus a link to a "detailed" version, and

   - a second which contains the number of coverpoints in the hit by each testcase.

   Note that missed coverpoints are not shown in the per-testcase table entry data.

   The corresponding summary table is found on the 'directory' page of the default 3-level genthm report, or on the top-level page of the 'flat' report (see *genhtml --flat ...* ), or on the parent directory page of the 'hierarchical' report (see *genhtml --hierarchical ...* ).

   Note that this option may significantly increase memory consumption.

``-b`` *baseline-file-pattern*, ``--baseline-file`` *baseline-file-pattern*
   Use data in the files found from glob pattern *baseline-file-pattern* as coverage baseline.

   ``--baseline-file`` may be specified multiple times - for example, if you have multiple trace data files for each of several test suites and you do not want to go through the additional step of merging all of them into a single aggregated data file.

   The coverage data files specified by *baseline-file-pattern* is read and used as the baseline for classifying the change in coverage represented by the coverage counts in *tracefile-patterns*. If *baseline-file-pattern* is a directory, then genhtml will search the directory for all files ending in '.info'. See the *info_file_extension* section in ``man(5) lcovrc`` for how to change this pattern.

   In general, you should specify a diff file in unified diff format via ``--diff-file`` when you specify a *--baseline-file-pattern*. Without a diff file, genhtml will assume that there are no source differences between 'baseline' and 'current'. For example: this might be used to find incremental changes caused by the addition of more testcases, or to compare coverage results between gcc versions, or between gcc and llvm.

``--baseline-title`` *title*
   Use *title* as the descriptive label text for the source of coverage baseline data.

``--baseline-date`` *date*
   Use *date* as the collection date in text format for the coverage baseline data. If this argument is not specified, the default is to use the creation time of the first file matched by *baseline-file-pattern* as the baseline date. If there are multiple baseline files, then the creation date of the first file is used.

``--current-date`` *date*
   Use *date* as the collection date in text format for the coverage baseline data. If this argument is not specified, the default is to use the creation time of the current *tracefile*.

``--diff-file`` *diff-file*
   Use the *diff-file* as the definition for source file changes between the sample points for *baseline-file-pattern* and *tracefile(s)*.

   Note:

   -  if filters are applied during the creation of a differential coverage report, (see the ,I --filter section, below), then those filters will be applied to the *baseline coverage data* (see the *--baseline-file* section, above) as well as to the *current coverage data*. It is important that the *diff-file* accurately reflect all source code changes so that the baseline coverage data can be correctly filtered.

   -  Best practice is to use a *--version-script* callback to verify that source versions match before source-based filtering is applied.

   It is almost always a better idea to filter at capture or aggregate time - not at report generation.

   A suitable *"universal diff"* input file for the *--diff-file* option can be generated using either the "p4udiff" or "gitdiff" sample scripts that are provided as part of this package, or by using revision control commands directly.

   The "p4udiff" or "gitdiff" sample scripts are found in:

      ``scripts/p4udiff``

   and

      ``scripts/gitdiff``

   These scripts simply post-process the 'p4' or 'git' output to (optionally) remove files that are not of interest and to explicitly note files which have not changed.

   ``p4udiff`` accepts either a changelist ID or the literal string "sandbox"; "sandbox" indicates that there are modified files which have not been checked in. See "*gitdiff -- help*" and "*p4udiff -- help*" for more information.

   It is useful to note unchanged files denoted by lines of the form:

   ::

      diff [optional header strings]
      === file_path

   in the p4diff/gitdiff output as this knowledge will help to suppress spurious 'path mismatch' warnings. See the ``--elide-path-mismatch`` and ``--build-directory`` entries, below.

   In general, you will specify ``--baseline-file`` when you specify ``--diff-file``. The *baseline_files* are used to compute coverage differences (*e.g.* gains and losses) between the baseline and current, where the *diff_file* is used to compute code changes: source text is identical between 'baseline' and 'current'. If you specify *baseline_files* but no *diff_file*, the tool will assume that there are no code changes between baseline and current. If you specify a *diff_file* but no *baseline_files*, the tool will assume that there is no baseline coverage data (no baseline code was covered); as result unchanged code (*i.e.*, which does not appear in the *diff_file* will be categorized as eiher GIC (covered) or UIC (not covered) while new or changed code will be categorized as either GNC or UNC.

``--annotate-script`` *script*
   Use *script* to get source code annotation data.

   Use this option to specify an external tool or command line that ``genhtml`` can use to obtain source code annotation data such as age and author of the last change for each source code line.

   This option also instructs ``genhtml`` to add a summary table to the HTML report header that shows counts in the various coverage categories, associated with each date bin. In addition, each source code line will show age and owner information. Annotation data is also used to populate a 'tooltip' which appears when the mouse hovers over the associated source code. See the *genhtml_annotate_tooltip* entry in :manpage:`lcovrc(5)` for details.

   The specified *script* is expected to obtain age and ownership information for each source code line from the revision management system and to output this information in the format described below.

   If the annotate script fails and annotation errors are ignored via ``--ignore-errors``, then ``genhtml`` will try to load the source file normally. If the file is not present or not readable, and the ``--synthesize-missing`` flag is specified, then ``genhtml`` will synthesize fake data for the file.

   ``genhtml`` will emit an error if you have specified an annotation script but no files are successfully annotated (see below). This can happen, for example, if your P4USER, P4CLIENT, or P4PORT environment variables are not set correctly - *e.g.*, if the Jenkins user who generates coverage reports is not the same and the user who checked out the code and owns the sandbox.

   Sample annotation scripts for Perforce ("p4annotate") and git ("gitblame") are provided as part of this package in the following locations:

      ``scripts/p4annotate``

   and

      ``scripts/gitblame``

   Note that these scripts generate annotations from the file version checked in to the repository - not the locally modified file in the build directory. If you need annotations for locally modified files, you can shelve your changes in P4, or check them in to a local branch in git.

   **Creating your own script**

   When creating your own script, please first see **Script considerations** above for general calling conventions and script requirements.

   *script* is called by genhtml with the following command line:

      ``script`` *[additional_parameters]* *source_file_name*

   where

      ``script``
         is the script executable

      ``additional_parameters``
         includes any optional parameters specified (see **Script conventions** above)

      ``source_file_name``
         is the source code file name

   The *script* executable should output a line to the standard output stream in the following format for each line in file *source_file_name*:

      *commit_id* | *author_data* | *date* | *source_code*

   where

      ``commit_id``
         is an ID identifying the last change to the line or NONE if this file is not checked in to your revision control system.

         ``genhtml`` counts the file as not 'successfully annotated' if ``commit_id`` is *NONE* and as 'successfully annotated' otherwise.

      ``author_data``
         identifies the author of the last change.

         For backward compatibility with existing annotate-script implementations, two *author_data* formats are supported:

         -  *string*:\  the string used as both the 'abbreviated name' (used as 'owner' name in HTML output and callbacks) and as 'full name' (used in tooltip callbacks)

         -  *abbrev_string;full_name*:\  the *author_data* string contains both an 'abbreviated name' and a 'full name' - separated by a semicolon character (';').

            This is useful when generating coverage reports for opensource software components where there are many 'External' contributors who you do not want to distinguish in 'owner' summary tables but you still want to know who the actual author was. (See the ``gitblame`` callback script for an example.)

      ``date``
         is the data of last change in W3CDTF format (<YYYY>-<MM>-<DD>T<hh>:<mm>:<ss><TZD>)

      ``source_code``
         is the line's source code

   The script should return 0 (zero) if processing was successful and non-zero if it encountered an error.

``--criteria-script`` *script*
   Use *script* to test for coverage acceptance criteria.

   Use this option to specify an external tool or command line that ``genhtml`` can use to determine if coverage results meet custom acceptance criteria. Criteria checking results are shown in the standard output log of ``genhtml``\ . If at least one check fails, ``genhtml`` will exit with a non-zero exit code after completing its processing.

   A sample coverage criteria script is provided as part of this package in the following location:

      ``scripts/criteria``

   The sample script checks that top-level line coverage meets the criteria "UNC + LBC + UIC == 0" (added code and newly activated code must be tested, and existing tested code must not become untested).

   As another example, it is possible to create scripts that mimic the ``lcov --fail-under-lines`` feature by checking that the ratio of exercised lines to total lines ("(GNC + GIC + CBC) / (GNC + GIC + CBC + UNC + UIC + UBC)") is greater than the threshold - either only at the top level, in every directory, or wherever desired. Similarly, criteria may include branch and function coverage metrics.

   By default the criteria script is called for all source code hierarchy levels, *i.e.*: top-level, directory, and file-level. The *criteria_callback_levels* configuration file option can be used to limit the hierarchy levels to any combination of 'top', 'directory', or 'file' levels.

   Example:

   ::

      genhtml --rc criteria_callback_levels=directory,top ...

   You can increase the amount of data passed to the criteria script using configuration file option *criteria_callback_data*. By default, only total counts are included. Specifying "date" adds per date-bin counts, "owner" adds per owner-bin counts.

   Example:

   ::

      genhtml --rc criteria_callback_data=date,owner ...

   See :manpage:`lcovrc(5)` for more details.

   **Creating your own script**

   When creating your own script, please first see **Script considerations** above for general calling conventions and script requirements.

   *script* is run with the following command line for each source code file, leaf-directory, and top-level coverage results:

   ::

      script [additional_parameters] "name " " type" "coverage_data"

   where

      ``script``
         is the script executable

      ``additional_parameters``
         includes any optional parameters specified (see **Script conventions** above)

      ``name``
         is the name of the object for which coverage criteria should be checked, that is either the source code file name, directory name, or "top" if the script is called for top-level data

      ``type``
         is the type of source code object for which coverage criteria should be checked, that is one of "file", "directory", or "top"

      ``coverage_data``
         is either a coverage data hash or a JSON representation of coverage data hash of the corresponding source code object. If the callback is a Perl module, then the it is passes a hash object - other wise, it is passed a JSON representation of that data.

   The JSON data format is defined as follows:

   ::

      {
        "<type>": {
          "found": <count>,
          "hit": <count>,
          "<category>": <count>,
          ...
        },
        "<bin_type>": {
          "<bin_id>" : {
            "found": <count>,
            "hit": <count>,
            "<category>": <count>,
            ...
          },
          ...
        },
        ...
      }

   where

      ``type``
         specifies the type of coverage as one of "line", "function", or "branch"

      ``bin_type``
         specifies the type of per-bin coverage as one of "line_age", "function_age", or "branch_age" for date-bin data, and "line_owners" or "branch_owners" for owner-bin data

      ``bin_id``
         specifies the date-bin index for date-bin data, and owner ID for owner-bin data.

      ``found``
         defines the number of found lines, functions, or branches

      ``hit``
         defines the number of hit lines, functions, or branches

      ``category``
         defines the number of lines, functions, or branches that fall in the specified category (see **Differential coverage** above)

   Note that data is only reported for non-empty coverage types and bins.

   The script should return 0 (zero) if the criteria are met and non-zero otherwise.

   If desired, it may print a single line output string which will be appended to the error log if the return status is non-zero. Additionally, non-empty lines are appended to the genhtml standard output log.

``--version-script`` *script*
   Use *script* to get source code file version data.

   Use this option to specify an external tool or command line that ``genhtml`` can use to obtain a source code file's version ID when generating HTML or applying source filters (see ``--filter`` option).

   A version ID can be a file hash or commit ID from revision control. It is used to check the version of the source file which is loaded against the version which was used to generate coverage data (*i.e.*, the file version seen by lcov/geninfo). It is important that source code versions match - otherwise inconsistent or confusing results may be produced.

   Version mismatches typically happen when the tasks of capture, aggregation, and report generation are split between multiple jobs - *e.g.*, when the same source code is used in multiple projects, a unified/global coverage report is required, and the projects accidentally use different revisions.

   If your .info (coverage data) file does not contain version information - for example, because it was generated by a tool which did not support versioning - then you can use the *compute_file_version* = 1 config file option to generate the data afterward. A convenient way to do this might be to use ``lcov`` *--add-tracefile* to read the original file, insert version information, and write out the result. See :manpage:`lcovrc(5)` for more details.

   Sample scripts for Perforce ("getp4version"), git ("gitversion") and using an md5 hash ("get_signature") are provided as part of this package in the following locations:

      ``scripts/getp4version``

      ``scripts/gitversion``

   and

      ``scripts/get_signature``

   Note that you must use the same script/same mechanism to determine the file version when you extract, merge, and display coverage data - otherwise, you may see spurious mismatch reports.

   **Creating your own script**

   When creating your own script, please first see **Script considerations** above for general calling conventions and script requirements.

   *"script "* is used both to generate and to compare the version ID to enable retaining history between calls or to do more complex processing to determine equivalence. It will be called by ``genhtml`` with either of the following command lines:

   1. Determine source file version ID

      ``script`` *source_file_name*

      It should write the version ID of *source_file_name* to stdout and return a 0 exit status. If the file is not versioned, it should write an empty string and return a 0 exit status.

   2. Compare source file version IDs

      ``script --compare`` *source_file_name* *source_file_id* *info_file_id*

      where

         "source_file_name"
            is the source code file name

         "source_file_id "
            is the version ID returned by calling "script source_file_name"

         "info_file_id "
            is the version ID found in the corresponding .info file

      It should return non-zero if the IDs do not match.

``--resolve-script`` *script*
   Use *script* to find the file path for some source file which which appears in an input data file if the file is not found after applying *--substitute* patterns and searching the *--source-directory* list. This option is equivalent to the *resolve_script* config file option. See :manpage:`lcovrc(5)` for details.

``--select-script`` *callback*
   Use *callback* to decide whether a particular source line is interesting and should be included in the output data/generated report or not.

   This option is equivalent to the *select_script* config file option. See :manpage:`lcovrc(5)` for details.

``--simplify-script`` *callback*
   Use *callback* to shorten/simplify long demangled C++ function and template names to make the function detail table more compact and readable - for example, to remove nested namespace names.

   Note that the simplifications affect only the display and not the actual names stored in the coverage DB. In particular, the DB name (not the simplified name) is the one used to match *--erase-function* patterns.

   This option is equivalent to the *simplify_script* config file option. See :manpage:`lcovrc(5)` for details

``--unreachable-script`` *module*
   Use *module* to decide whether particular branch expressions and/or MC/DC conditions should be removed from the coverage report. This option is equivalent to the *unreachable_script* config file option. See :manpage:`lcovrc(5)` for details.

   Note that *"module"* is required to be a Perl module.

   See the *--unreachable-script* discussion in the *"Script conventions"* section, above, and the *"Exclusion markers"* section in :manpage:`geninfo(1)`.

``--checksum``
   Specify whether to compare stored tracefile checksum to checksum computed from the source code.

   Checksum verification is **disabled** by default.

   When checksum verification is enabled, a checksum will be computed for each source code line and compared to the checksum found in the 'current' tracefile. This will help to prevent attempts to display source code which is not identical to the code used to generate the coverage data.

   Note that this option is somewhat subsumed by the ``--version-script`` option - which does something similar, but at the 'whole file' level.

``--fail-under-branches`` *percentage*
   Use this option to tell genhtml to exit with a status of 1 if the total branch coverage is less than *percentage*. See :manpage:`lcov(1)` for more details.

``--fail-under-lines`` *percentage*
   Use this option to tell genhtml to exit with a status of 1 if the total line coverage is less than *percentage*. See :manpage:`lcov(1)` for more details.

``--new-file-as-baseline``
   By default, when code is identified on source lines in the 'current' data which were not identified as code in the 'baseline' data, but the source text has not changed, their coverpoints are categorized as "included code": *GIC* or *UIC*.

   However, if the configuration of the coverage job has been recently changed to instrument additional files, then all un-exercised coverpoints in those files will fall into the *GIC* category - which may cause certain coverage criteria checks to fail.

   When this option is specified, genhtml pretends that the baseline data for the file is the same as the current data - so coverpoints are categorized as *CBC* or *UBC* which do not trigger the coverage criteria check.

   Please note that coverpoints in the file are re-categorized only if:

   - There is no 'baseline' data for any coverpoint in this file, AND

   - The file pre-dates the baseline: the oldest line in the file is older than the 'baseline' data file (or the value specified by the ``--baseline-date`` option).

``--elide-path-mismatch``
   Differential categorization uses file pathnames to match coverage entries from the ".info" file with file difference entries in the unified-diff-file. If the entries are not identical, then categorization may be incorrect or strange.

   When paths do not match, genhtml will produce "path" error messages to tell you about the mismatches.

   If mismatches occur, the best solution is to fix the incorrect entries in the .info and/or unified-diff-file files. However, fixing these entries is not possible, then you can use this option to attempt to automatically work around them.

   When this option is specified, genhtml will pretend that the unified-diff-file entry matches the .info file entries if:

   - the same path is found in both the 'baseline' and 'current' .info files, and

   - the basename of the path in the .info file and the path in the unified-diff-file are the same, and

   - there is only one unmatched unified-diff-file entry with that basename.

   See the ``--diff-file`` and ``--build-directory`` entries for a discussion of how to avoid spurious warnings and/or incorrect matches.

``--synthesize-missing``
   Generate (fake) file content if source file does not exist. This option can be used to work around otherwise fatal annotation errors.

   When generating annotated file content, ``genhtml`` assumes that the source was written 'now' (so age is zero), the author is *no.body* and the commit ID is *synthesized*. These names and ages will appear in your HTML reports.

   This option is equivalent config file *genhtml_synthesize_missing* parameter; see :manpage:`lcovrc(5)` for details.

``--date-bins`` *day[,day,...]*
   The ``--date-bins`` option is used to specify age boundaries (cutpoints) for date-binning classification. Each *age* element is expected to be an integer number of days prior to today (or prior to your SOURCE_DATE_EPOCH environment variable, if set). If *--date-bins* is not specified, the default is to use 4 age ranges: less than 7 days, 7 to 30 days, 30 to 180 days, and more than 180 days. This option is equivalent to the *genhtml_date_bins* config file option. See :manpage:`lcovrc(5)`.

   This argument has no effect if there is no *source-annotation-script*.

``--date-labels`` *string[,string,...]*
   The ``--date-labels`` option is used to specify labels used for the 'date-bin' table entries in the HTML report. The number of labels should be one greater than the number of cutpoints. If not specified, the default is to use label strings which specify the *[from ..to)* range of ages held by the corresponding bin.

   One possible use of this option is to use release names in the tables - *i.e.*, to indicate the release in which each particular line first appeared.

   This option is equivalent to the *genhtml_date_labels* config file option. See :manpage:`lcovrc(5)`.

   This argument has no effect if there is no *source-annotation-script*.

``--show-owners`` [ *all* ]
   If the ``--show-owners`` option is used, each coverage report header report contain a summary table, showing counts in the various coverage categories for everyone who appears in the revision control annotation as the most recent editor of the corresponding line. If the optional argument 'all' is not specified, the table will show only users who are responsible for un-exercised code lines. If the optional argument is specified, then users responsible for any code lines will appear. In both cases, users who are responsible for non-code lines (e.g, comments) are not shown. This option does nothing if ``--annotate-script`` is not used; it needs revision control information provided by calling the script.

   Please note: if the *all* option is not specified, the summary table will contain "Total" rows for all date/owner bins which are not empty - but there will be no secondary "File/Directory" entries for elements which have no "missed" coverpoints.

   This option is equivalent config file *genhtml_show_owner_table* parameter; see :manpage:`lcovrc(5)` for details.

   The lcovrc controls *owner_table_entries* and *truncate_owner_table* can be used to improve readability by limiting the number of authors who are displayed in the table when the author number is large. For example, if your configuration is:

      *owner_table_entries* = 5

      *truncate_owner_table* = top,directory

   then the owner table displayed at the top- and directory-levels will be truncated while the table shown at the 'file' level will display the full list.

   See :manpage:`lcovrc(5)` for details.

``--show-noncode``
   By default, the source code detail view does not show owner or date annotations in the far-left column for non-code lines (*e.g.*, comments). If the ``--show-noncode`` option is used, then the source code view will show annotations for both code and non-code lines. This argument has no effect if there is no *source-annotation-script*.

   This option is equivalent config file *genhtml_show_noncode_owners* parameter; see :manpage:`lcovrc(5)` for details.

``--show-zero-columns``
   By default, columns whose entries are all zero are removed (not shown) in the summary table at the top of each HTML page. If the ``--show-zero-columns`` option is used, then those columns will be shown.

   When columns are retained, then all the tables have the same width/contain the same number of columns - which may be a benefit in some situations.

   When columns are removed, then the tables are more compact and easier to read. This is especially true in relatively mature development environments, when there are very few un-exercised coverpoints in the project.

``--show-navigation``
   By default, the summary table in the source code detail view does not contain hyperlinks from the number to the first line in the corresponding category ('Hit' or 'Missed') and from the current location to the next location in the current category, in non-differential coverage reports. (This is the lcov 'legacy' view non-differential reports.)

   If the ``--show-navigation`` option is used, then the source code summary table will be generated with navigation links. Hyperlinks are always generated for differential coverage reports.

   This feature enables developers to find and understand coverage issues more quickly than they might otherwise, if they had to rely on scrolling.

   See the *--frames* description above for a description of a browser bug which disables these hyperlinks in certain conditions.

   Navigation hyperlinks are always enabled in differential coverage report.

``--show-proportions``
   In the 'function coverage detail' table, also show the percentage of lines and branches within the function which are exercised.

   This feature enables developers to focus attention on functions which have the largest effect on overall code coverage.

   This feature is disabled by default. Note that this option requires that you use a compiler version which is new enough to support function begin/end line reports or that you configure the tool to derive the required data - see the *derive_function_end_line* discussion in :manpage:`lcovrc(5)`.

``--simplified-colors``
   By default, each differential category is colorized uniquely in the source code detail view. With this option, only two colors are used: one for covered code and another for uncovered code. Note that ECB and EUB code is neither covered nor uncovered - and so may be difficult to distinguish in the source code view, as they will be presented in normal background color.

``--exclude`` *pattern*
   pattern is a glob-match pattern of filenames to exclude from the report. Files which do NOT match will be included. See the lcov man page for details.

``--include`` *pattern*
   pattern is a glob-match pattern of filenames to include in processing. Files which do not match will be excluded from the report. See the lcov man page for details.

``--erase-functions`` *regexp*
   Exclude coverage data from lines which fall within a function whose name matches the supplied regexp. Note that this is a mangled or demangled name, depending on whether the ``--demangle-cpp`` option is used or not.

   Note that this option requires that you use a compiler version which is new enough to support function begin/end line reports or that you configure the tool to derive the required data - see the *derive_function_end_line* discussion in :manpage:`lcovrc(5)`.

``--substitute`` *regexp_pattern*
   Apply Perl regexp *regexp_pattern* to source file names found during processing. This is useful when some file paths in the baseline or current .info file do not match your source layout and so the source code is not found. See the lcov man page for more details.

   Note that the substitution patterns are applied to the *--diff-file* entries as well as the baseline and current .info files.

``--omit-lines`` *regexp_pattern*
   Exclude coverage data from lines whose content matches *regexp*.

   Use this switch if you want to exclude line and branch coverage data for some particular constructs in your code (*e.g.*, some complicated macro). See the lcov man page for details.

``--parallel`` [*integer*], ``-j`` [*integer*]
   Specify parallelism to use during processing (maximum number of forked child processes). If the optional integer parallelism parameter is zero or is missing, then use up the number of cores on the machine. Default is to use a single process (no parallelism).

   Also see the *memory, memory_percentage, max_fork_fails* and *fork_fail_timeout* entries in :manpage:`lcovrc(5)`.

   A previously generated execution profile may help to enable better utilization and faster parallel execution. See the *--profile* and *--history-script* sections of this man page.

``--memory`` *integer*
   Specify the maximum amount of memory to use during parallel processing, in Mb. Effectively, the process will not fork() if this limit would be exceeded. Default is 0 (zero) - which means that there is no limit.

   This option may be useful if the compute farm environment imposes strict limits on resource utilization such that the job will be killed if it tries to use too many parallel children - but the user does not know a priori what the permissible maximum is. This option enables the tool to use maximum parallelism - up to the limit imposed by the memory restriction.

   The configuration file *memory_percentage* option provided another way to set the maximum memory consumption. See man ``lcovrc (5)`` for details.

``--filter`` *filters*
   Specify a list of coverpoint filters to apply to input data.

   Note that certain filters apply only to C/C++ source files. ``genhtml`` associates the file extension ('.c', '.vhd', *etc.*) with its source language. See the *c_file_extensions* and *rtl_file_extensions* sections of :manpage:`lcovrc(5)` for a description of the default associations and how they can be changed.

   Note that filters are applied to both 'branch' and 'MC/DC' coverpoints, where appropriate: if a particular filter would remove some branch, then it will also remove corresponding MC/DC coverpoints - for example, *--filter branch* will remove MC/DC coverpoints if there is no conditional expression on the corresponding line, and *--filter branch_region* will remove both branch and MC/DC coverpoints in the marked region.

   Most filters need the source code; filters are not applied if the source file is not available. Similarly, for each source file, if the version recorded in the coverage data (the '.info' file) does not match the version found on the filesystem, then a *version* error is reported. If the *version* error is ignored, then filtering is not applied to the mismatched file. See the *--version-script* for more information.

   *filters* can be a comma-separated list of the following keywords:

   branch:
      ignore branch counts for C/C++ source code lines which do not appear to contain conditionals. These may be generated automatically by the compiler (*e.g.*, from C++ exception handling) - and are not interesting to users. This option has no effect unless ``--branch-coverage`` is used.

      See also :manpage:`lcovrc(5)` - which describes several variables which affect branch filtering: *filter_lookahead* and *filter_bitwise_conditional*.

      The most common use for branch filtering is to remove compiler-generated branches related to C++ exception handlers. See the no_exception_branch' option in :manpage:`lcovrc(5)` for a way to remove all identified exception branches.

   brace:
      ignore line coverage counts on the closing brace of C/C++ code block, if the line contains only a closing brace and the preceding line has the same count or if the close brace has a zero count and either the preceding line has a non-zero count, or the close brace is not the body of a conditional.

      These lines seem to appear and disappear in gcov output - and cause differential coverage to report bogus LBC and/or GIC and/or UIC counts. Bogus LBC or UIC counts are a problem because an automated regression which uses pass criteria "LBC + UIC + UNC == 0" will fail.

   blank:
      ignore lines which contain only whitespace (or whitespace + comments) whose 'hit' count is zero. These appear to be a 'gcov' artifact related to compiler-generated code - such as exception handlers and destructor calls at the end of scope - and can confuse differential coverage criteria.

      If lcovrc option *filter_blank_aggressive* = 1 is enabled, then blank lines will be ignored whether their 'hit' count is zero or not. Aggressive filtering may be useful in LLVM-generated coverage data, which tends to include large numbers of such lines.

   directive:
      ignore lines which look like C compiler directives: #ifdef, #include, #define, *etc.* These lines are sometimes included by *llvm-cov* when LLVM profile data is translated to LCOV format.

   exception:
      Exclude branches related to C++ exception handling from branch coverage. Whether C++ exception branches are identified and removed is dependent on your compiler/toolchain correctly marking them in the generated coverage data. See the *no_exception_branch* section of :manpage:`lcovrc(5)`.

   initializer:
      Exclude lines which appear to be part of a C++ std::initializer_list.

   line:
      alias for "--filter brace,blank".

   mcdc:
      Remove MC/DC coverpoint which contains single expression, if 'branch' coverpoint is present on the same line. Single-element MC/DC coverpoints are identical to the corresponding branch - except in the case of compile-time expression evaluation, for example, in a template function.

   orphan:
      Remove branches which appear by themselves - *i.e.*, the branch has only one destination and so cannot be a conditional.

      These occur most frequently as a result of exception branch filtering.

   range:
      Ignore line and branch coverpoints on lines which are out-of range/whose line number is beyond the end of the source file. These appear to be gcov artifacts caused by a macro instantiation on the last line of the file.

   region:
      apply LCOV_EXCL_START/LCOV_EXCL_STOP/LCOV_EXCL_LINE and LCOV_UNREACHABLE_START/LCOV_UNREACHABLE_STOP/LCOV_UNREACHABLE_LINE directives found in source text to the coverpoints found in the current and baseline .info files. This option may be useful in cases that the source code was not found during 'lcov --capture ...' but is accessible now.

   branch_region:
      apply LCOV_EXCL_BR_START/LCOV_EXCL_BR_STOP/LCOV_EXCL_BR_LINE directives found in source text to the coverpoints found in the current and baseline .info files. This is similar to the 'region option, above - but applies to branch coverpoints only.

   function:
      combine data for every "unique" function which is defined at the same file/line. *geninfo/gcov* seem to have a bug such that they create multiple entries for the same function. This feature also merges all instances of the same template function/template method.

   trivial:
      remove trivial functions and associated coverpoints. 'Trivial' functions are whose body is empty/do not contain any statements. Commonly, these include compiler-generated methods (*e.g.*, default constructors and assignment operators) as well as static initialization wrappers, etc.

      Note that the *trivial* filter requires function end line information - and so requires that you use a compiler version which is new enough to support begin/end line reports (*e.g.*, gcc/9 or newer) or that you enable lcov/genhtml/geninfo to derive the information:

      In :manpage:`lcovrc(5)`, see the *derive_function_end_line* setting as well as the *trivial_function_threshold* setting. The former is used to turn end line calculation on or off, and the latter to change the lookahead used to determine whether the function body is empty. Also see the *lcov_filter_parallel* and *lcov_filter_chunk_size* settings, which may improve CPU performance if the number of files to process is very large.

``-o``, ``--output-directory`` *output-directory*
   Create files in *output-directory*.

   Use this option to tell ``genhtml`` to write the resulting files to a directory other than the current one. If *output-directory* does not exist, it will be created.

   It is advisable to use this option since depending on the project size, a lot of files and subdirectories may be created.

``-t``, ``--title`` *title*
   Display *title* in header table of all pages.

   *title* is written to the "Test:"-field in the header table at the top of each generated HTML page to identify the context in which a particular output was created. By default, this is the name of the 'current; tracefile.

   A common use is to specify a test run name, or a version control system identifier (perforce changelist or git SHA, for example) that indicates the code level that was tested.

``--header-title`` *BANNER*
   Display *BANNER* in header of all pages.

   *BANNER* is written to the header portion of each generated HTML page. By default, this simply identifies this as an |ToolName| (differential) coverage report.

   A common use is to specify the name of the project or project branch and the Jenkins build ID.

``--footer`` *FOOTER*
   Display *FOOTER* in footer of all pages.

   *FOOTER* is written to the footer portion of each generated HTML page. The default simply identifies the |ToolName| tool version used to generate the report.

``-d``, ``--description-file`` *description-file*
   Read test case descriptions from *description-file*.

   All test case descriptions found in *description-file* and referenced in the input data file are read and written to an extra page which is then incorporated into the HTML output.

   The file format of *description-file* is:

   for each test case:

      TN:<testname>
      TD:<test description>

   Valid test case names can consist of letters, numbers and the underscore character ('_').

``-k``, ``--keep-descriptions``
   Do not remove unused test descriptions.

   Keep descriptions found in the description file even if the coverage data indicates that the associated test case did not cover any lines of code.

   This option can also be configured permanently using the configuration file option *genhtml_keep_descriptions*.

``-c``, ``--css-file`` *css-file*
   Use external style sheet file *css-file*.

   Using this option, an extra .css file may be specified which will replace the default one. This may be helpful if the default colors make your eyes want to jump out of their sockets :)

   This option can also be configured permanently using the configuration file option *genhtml_css_file*.

``--build-directory`` *dirname*
   To support 'linked build directory' structures, add 'dirname' to the list of places to search for soft links to source files - *e.g.*, to handle the case that the links point to source files which are held in your revision control system, and appear in the *--diff-file* data. In this use case, paths in the coverage data very likely refer to the structure seen by the compiler during the build - so resolving them back to the corresponding revsion-controlled source structure is likely to be successful.

   Look in *dirname* for file paths which appear in *tracefile* - possibly after substitutions have been applied - which are soft links. Both the original file path and the path to the linked file will resolve to the same *--diff-file* entry.

   This option can be specified multiple times, to add more directories to the search path.

``--source-directory`` *dirname*
   Add 'dirname' to the list of places to look for source files.

   For relative source file paths *e.g.* paths found in *tracefile*, or in *diff-file* - possibly after substitutions have been applied - ``genhtml`` will first look for the path from 'cwd' (where genhtml was invoked) and then from each alternate directory name in the order specified. The first location matching location is used.

   This option can be specified multiple times, to add more directories to the source search path.

``-p``, ``--prefix`` *prefix*
   Remove *prefix* from all directory names.

   Because lists containing long filenames are difficult to read, there is a mechanism implemented that will automatically try to shorten all directory names on the overview page beginning with a common prefix. By default, this is done using an algorithm that tries to find the prefix which, when applied, will minimize the resulting sum of characters of all directory names.

   Use this option to specify the prefix to be removed by yourself.

``--no-prefix``
   Do not remove prefix from directory names.

   This switch will completely disable the prefix mechanism described in the previous section.

   This option can also be configured permanently using the configuration file option *genhtml_no_prefix*.

``--no-source``
   Do not create source code view.

   Use this switch if you don't want to get a source code view for each file.

   This option can also be configured permanently using the configuration file option *genhtml_no_source*.

``--no-html``
   Do not create HTML report.

   Use this switch if you want some artifact of coverage report generation - *e.g.*, the coverage criteria check or the serialized coverage DB, *etc.* - but do not need the coverage report HTML itself.

``--num-spaces`` *spaces*
   Change appearance of tabs in source view according to *spaces*.

   When set to 0, tabs and their behaviour will be the browser's default.

   Negative values will set the rendered width in the source view to *spaces* spaces.

   Positive values will replace tabs with *spaces* spaces.

   Default value is 8.

   This option can also be configured permanently using the configuration file option *genhtml_num_spaces*.

``--highlight``
   Highlight lines with converted-only coverage data.

   Use this option in conjunction with the ``--diff`` option of ``lcov`` to highlight those lines which were only covered in data sets which were converted from previous source code versions.

   This option can also be configured permanently using the configuration file option *genhtml_highlight*.

``--legend``
   Include color legend in HTML output.

   Use this option to include a legend explaining the meaning of color coding in the resulting HTML output.

   This option can also be configured permanently using the configuration file option *genhtml_legend*.

``--html-prolog`` *prolog-file*
   Read customized HTML prolog from *prolog-file*.

   Use this option to replace the default HTML prolog (the initial part of the HTML source code leading up to and including the <body> tag) with the contents of *prolog-file*. Within the prolog text, the following words will be replaced when a page is generated:

   ``@pagetitle@``
      The title of the page.

   ``@basedir@``
      A relative path leading to the base directory (*e.g.*, for locating css-files).

   This option can also be configured permanently using the configuration file option *genhtml_html_prolog*.

``--html-epilog`` *epilog-file*
   Read customized HTML epilog from *epilog-file*.

   Use this option to replace the default HTML epilog (the final part of the HTML source including </body>) with the contents of *epilog-file*.

   Within the epilog text, the following words will be replaced when a page is generated:

   ``@basedir@``
      A relative path leading to the base directory (*e.g.*, for locating css-files).

   This option can also be configured permanently using the configuration file option *genhtml_html_epilog*.

``--html-extension`` *extension*
   Use customized filename extension for generated HTML pages.

   This option is useful in situations where different filename extensions are required to render the resulting pages correctly (*e.g.*, php). Note that a '.' will be inserted between the filename and the extension specified by this option.

   This option can also be configured permanently using the configuration file option *genhtml_html_extension*.

``--html-gzip``
   Compress all generated html files with gzip and add a .htaccess file specifying gzip-encoding in the root output directory.

   Use this option if you want to save space on your webserver. Requires a webserver with .htaccess support and a browser with support for gzip compressed html.

   This option can also be configured permanently using the configuration file option *genhtml_html_gzip*.

``--sort-tables``, ``--no-sort``
   Specify whether to include sorted views of file and directory overviews.

   Use ``--sort-tables`` to include sorted views or ``--no-sort`` to not include them. Sorted views are **enabled** by default.

   When sorted views are enabled, each overview page will contain links to views of that page sorted by coverage rate.

   This option can also be configured permanently using the configuration file option *genhtml_sort*.

``--function-coverage``, ``--no-function-coverage``
   Specify whether to display function coverage summaries in HTML output.

   Use --function-coverage to enable function coverage summaries or --no-function-coverage to disable it. Function coverage summaries are **enabled** by default.

   This option can also be configured permanently using the configuration file option *genhtml_function_coverage*.

   When function coverage summaries are enabled, each overview page will contain the number of functions found and hit per file or directory, together with the resulting coverage rate. In addition, each source code view will contain a link to a page which lists all functions found in that file plus the respective call count for those functions. The function coverage page groups the data for every alias of each function, sorted by name or execution count. The representative name of the group of functions is the shorted (*i.e.*, containing the fewest characters).

   If using differential coverage and a sufficiently recent compiler version which report both begin and end line of functions (*e.g.*, gcc/9 and newer), functions are considered 'new' if any of their source lines have changed. With older compiler versions, functions are considered 'new' if the function signature has changed or if the entire function is new.

``--branch-coverage``, ``--no-branch-coverage``
   Specify whether to display branch coverage data in HTML output.

   Use ``--branch-coverage`` to enable branch coverage display or ``--no-branch-coverage`` to disable it. Branch coverage data display is **disabled** by default.

   When branch coverage display is enabled, each overview page will contain the number of branches found and hit per file or directory, together with the resulting coverage rate. In addition, each source code view will contain an extra column which lists all branches of a line with indications of whether the branch was taken or not. Branches are shown in the following format:

   ::

      ' + ': Branch was taken at least once
      ' - ': Branch was not taken
      ' # ': The basic block containing the branch was never executed

   Note that it might not always be possible to relate branches to the corresponding source code statements: during compilation, GCC might shuffle branches around or eliminate some of them to generate better code.

   This option can also be configured permanently using the configuration file option *branch_coverage*.

``--mcdc-coverage``
   Specify whether to display Modified Condition / Decision Coverage (MC/DC) data in HTML output.

   MC/DC data display is **disabled** by default.

   MC/DC coverage is supported for GCC versions 14.2 and higher, or LLVM 18.1 and higher.

   See *llvm2lcov --help* for details on MC/DC data capture in LLVM.

   When MC/DC display is enabled, each overview page will contain the number of MC/DC expressions found and hit per file or directory - two senses per expression - together with the resulting coverage rate. In addition, each source code view will contain an extra column which lists all expressions and condition senses of a line with indications of whether the condition was sensitized or not. Conditions are shown in the following format:

   T:
      True sense of subexpression was sensitized: if this subexpression's value had been false, then the condition result would have been different.

   t:
      True sense of subexpression was **not** sensitized: the condition result would not change if the subexpression value was different.

   F:
      False sense of subexpression was sensitized: if this subexpression's value had been true, then the condition result would have been different.

   f:
      False sense of subexpression was **not** sensitized: the condition result would not change if the subexpression value was different.

   Note that branch and MC/DC coverage are identical if the condition is a simple expression - *e.g.*,

   ::

      if (enable) ...

   Note that, where appropriate, filters are applied to both 'branch' and 'MC/DC' coverpoints: if a particular filter would remove some branch, then it will also remove corresponding MC/DC coverpoints. See the *--filter* section, above.

   This option can also be configured permanently using the configuration file option *mcdc_coverage*. See :manpage:`lcovrc(5)`.

   Note that MC/DC coverpoints are defined differently by GCC and LLVM.

   GCC:
      evaluates the sensitivity of the condition to the 'true' and 'false' sense of each constituent (leaf) expression independently.

      That is: it evaluates the question: does the result of the condition change if *this* constituent expression changed from true to false (termed the 'true' sense, above) or from false to true (termed the 'false' sense, above).

      For example, the expression *A || B* is sensitive to *A==true* when *B==false*, but is not sensitive to *A==true* when *B==true*.

   LLVM:
      records the subexpression as covered if and only if there is a pair of evaluations of the condition such that the condition was sensitized for both 'true' and 'false' values of the subexpression. This is defined as an *independence pair* in the LLVM documentation.

      That is: the testcase must sensitize both values in order to be marked covered by LLVM, whereas GCC will independently mark each. Consequently: in LLVM-generated ``lcov`` reports, either both 'true' and 'false' sensitizations will be covered, or neither will be.

      See the examples in testcase *.../tests/lcov/mcdc*.

``--demangle-cpp`` [ *param* ]
   Specify whether to demangle C++ function names.

   Use this option if you want to convert C++ internal function names to human readable format for display on the HTML function overview page.

   If called with no parameters, genhtml will use *c++filt* for demangling. This requires that the c++filt tool is installed (see ``c++filt(1)``).

   If *param* is specified, it is treated as th tool to call to demangle source code. The ``--demangle-cpp`` option can be used multiple times to specify the demangling tool and a set of command line options that are passed to the tool - similar to how the gcc *-Xlinker* parameter works. In that case, you callback will be executed as *| demangle_param0 demangle_param1 ...* Note that the demangle tool is called as a pipe and is expected to read from stdin and write to stdout.

``--msg-log`` [ *log_file_name* ]
   Specify location to store error and warning messages (in addition to writing to STDERR). If *log_file_name* is not specified, then default location is used.

``--ignore-errors`` *errors*
   Specify a list of errors after which to continue processing.

   Use this option to specify a list of error classes after which ``genhtml`` should continue processing with a warning message instead of aborting. To suppress the warning message, specify the error class twice.

   *errors* can be a comma-separated list of the following keywords:

   annotate:
      ``--annotate-script`` returned non-zero exit status - likely a file path or related error. HTML source code display will not be correct and ownership/date information may be missing.

   branch:
      Branch ID (2nd field in the .info file 'BRDA' entry) does not follow expected integer sequence.

   callback:
      Annotate, version, or criteria script error.

   category:
      Line number categorizations are incorrect in the .info file, so branch coverage line number turns out to not be an executable source line.

   child:
      child process returned non-zero exit code during *--parallel* execution. This typically indicates that the child encountered an error: see the log file immediately above this message. In contrast: the *parallel* error indicates an unexpected/unhandled exception in the child process - not a 'typical' lcov error.

   count:
      An excessive number of messages of some class has been reported - subsequent messages of that type will be suppressed. The limit can be controlled by the 'max_message_count' variable. See :manpage:`lcovrc(5)`.

   corrupt:
      Corrupt/unreadable coverage data file found.

   deprecated:
      You are using a deprecated option. This option will be removed in an upcoming release - so you should change your scripts now.

   empty:
      The patch file specified by the ``--diff-file`` argument does not contain any differences. This may be OK if there were no source code changes between 'baseline' and 'current' (*e.g.*, the only change was to modify a Makefile) - or may indicate an unsupported file format.

   excessive:
      your coverage data contains a suspiciously large 'hit' count which is unlikely to be correct - possibly indicating a bug in your toolchain. See the *excessive_count_threshold* section in :manpage:`lcovrc(5)` for details.

   fork:
      Unable to create child process during *--parallel* execution.

      If the message is ignored (*--ignore-errors fork*), then genhtml will wait a brief period and then retry the failed execution.

      If you see continued errors, either turn off or reduce parallelism, set a memory limit, or find a larger server to run the task.

   format:
      Unexpected syntax or value found in .info file - for example, negative number or zero line number encountered.

   inconsistent:
      This error indicates that your coverage data is internally inconsistent: it makes two or more mutually exclusive claims. For example:

      - Files have been moved or repository history presented by ``--diff-file`` data is not consistent with coverage data; for example, an 'inserted' line has baseline coverage data. These issues are likely to be caused by inconsistent handling in the 'diff' data compared to the 'baseline' and 'current' coverage data (*e.g.*, using different source versions to collect the data but incorrectly annotating those differences), or by inconsistent treatment in the 'annotate' script. Consider using a ``--version-script`` to guard against version mismatches.

      - Two or more ``gcov`` data files or ``lcov`` ".info" files report different end lines for the same function. This is likely due either to a gcc/gcov bug or to a source version mismatch.

         In this context, if the *"inconsistent"* error is ignored, then the tool will record the largest number as the function end line.

      - Two or more ``gcov`` data files or ``lcov`` ".info" files report different start lines for the same function. This is likely due either to a gcc/gcov bug or to a source version mismatch.

         In this context, if the *"inconsistent"* error is ignored, then the tool will retain only the first function definition that it saw.

      - Mismatched function declaration/alias records encountered:

         - (backward compatible LCOV format) function execution count record ( *FNDA* ) without matching function declaration record ( *FN* ).

         - (enhanced LCOV format) function alias record ( *FNA* ) without matching function declaration record ( *FLN* ).

      - branch expression (3rd field in the .info file 'BRDA' entry) of merge data does not match

         If the error is ignored, the offending record is skipped.

   internal:
      internal tool issue detected. Please report this bug along with a testcase.

   mismatch:
      Incorrect or inconsistent information found in coverage data and/or source code - for example, the source code contains overlapping exclusion directives.

   missing:
      remove all coverpoints associated with source files which are not found or are not readable. This is equivalent to adding a *--exclude* <name> pattern for each file which is not found.

      If a *--resolve-script* callback is specified, then the file is considered missing if it is not locally visible and the callback returns "" (empty string) or 'undef' - otherwise not missing.

   negative:
      negative 'hit' count found.

      Note that negative counts may be caused by a known GCC bug - see

      ::

         https://gcc.gnu.org/bugzilla/show_bug.cgi?id=68080

      and try compiling with "-fprofile-update=atomic". You will need to recompile, re-run your tests, and re-capture coverage data.

   package:
      A required perl package is not installed on your system. In some cases, it is possible to ignore this message and continue - however, certain features will be disabled in that case.

   parallel:
      various types of errors related to parallelism - *i.e.*, a child process died due to an error. The corresponding error message appears in the log file immediately before the *parallel* error. If you see an error related to parallel execution that seems invalid, it may be a good idea to remove the --parallel flag and try again. If removing the flag leads to a different result, please report the issue (along with a testcase) so that the tool can be fixed.

   path:
      File name found in ``--diff-file`` file but does not appear in either baseline or current trace data. These may be mapping issues - different pathname in the tracefile vs. the diff file.

   range:
      Coverage data refers to a line number which is larger than the number of lines in the source file. This can be caused by a version mismatch or by an issue in the *gcov* data.

   source:
      The source code file for a data set could not be found.

   unmapped:
      Coverage data for a particular line cannot be found, possibly because the source code was not found, or because the line number mapping in the \.info file is wrong.

      This can happen if the source file used in HTML generation is not the same as the file used to generate the coverage data - for example, lines have been added or removed.

   unreachable:
      a coverpoint (line, branch, function, or MC/DC) within an "unreachable" region is executed (hit); either the code, directive placement, or both are wrong. If the error is ignored, the offending coverpoint is retained (not excluded) or not, depending on the value of the *retain_unreachable_coverpoints_if_executed* configuration parameter. See :manpage:`lcovrc(5)` and the *"Exclusion markers"* section of :manpage:`geninfo(1)` for more information.

   unsupported:
      The requested feature is not supported for this tool configuration. For example, function begin/end line range exclusions use some GCOV features that are not available in older GCC releases.

   unused:
      The include/exclude/erase/substitute/omit pattern did not match any file pathnames.

   usage:
      unsupported usage detected - *e.g.* an unsupported option combination.

   utility:
      a tool called during processing returned an error code (*e.g.*, 'find' encountered an unreadable directory).

   version:
      --version-script comparison returned non-zero mismatch indication. It likely that the version of the file which was used in coverage data extraction is different than the source version which was found. File annotations may be incorrect.

   Note that certain error messages are caused by issues that you probably cannot fix by yourself - for example, bugs in your tool chain which result in *inconsistent* coverage DB data (see above). In those cases, after reviewing the messages you may want to exclude the offending code or the entire offending file, or you may simply ignore the messages - either by converting to warning or suppressing entirely. Another alternative is to tell ``genhtml`` about the number of messages you expect - so that it can warn you if something changes such that the count differs, such that you know to review the messages again. See the *--expect-message-count* flag, below.

   Also see ':manpage:`lcovrc(5)`' for a discussion of the 'max_message_count' parameter which can be used to control the number of warnings which are emitted before all subsequent messages are suppressed. This can be used to reduce log file volume.

``--expect-message-count message_type:expr[,message_type:expr]``
   Give ``genhtml`` a constraint on the number of messages of one or more types which are expected to be produced during execution. Note that the total includes _all_ messages of the given type - including those which have been suppressed. If the constraint is not true, an error of type *count* (see above) is generated. *message_type* is one of the message mnemonics described above, and *expr* may be either

   -  an integer - interpreted to mean that there should be exactly that number of messages of the corresponding type, or

   -  a Perl expression containing the substring ``%C``; %C is replaced with the total number of messages of the corresponding type and then evaluated. The constraint is met if the result is non-zero and is not met otherwise.

   For example:

   ::

      --expect-message-count inconsistent:5

   says that we expect exactly 5 messages of type 'inconsistent'.

   ::

      --expect-message-count inconsistent:%C==5

   also says that we expect exactly 5 messages of this type, but specified using expression syntax.

   ::

      --expect-message-count 'inconsistent : %C > 6 && %C <= 10'

   says that we expect the number of messages to be in the range (6:10]. (Note that quoting may be necessary, to protect whitespace from interpretation by your shell, if you want to improve expression readability by adding spaces to your expression.)

   Multiple constraints can be specified using a comma-separated list or by using the option multiple times.

   This flag is equivalent to the *expect_message_count* configuration option. See :manpage:`lcovrc(5)` for more details on the expression syntax and how expressions are interpreted. The number of messages of the particular type is substituted into the expression before it is evaluated.

``--keep-going``
   Do not stop if error occurs: attempt to generate a result, however flawed.

   This command line option corresponds to the *stop_on_error* lcovrc option. See :manpage:`lcovrc(5)` for more details.

``--config-file`` *config-file*
   Specify a configuration file to use. See :manpage:`lcovrc(5)` for details of the file format and options. Also see the *config_file* entry in the same man page for details on how to include one config file into another.

   When this option is specified, neither the system-wide configuration file /etc/lcovrc, nor the per-user configuration file ~/.lcovrc is read.

   This option may be useful when there is a need to run several instances of ``genhtml`` with different configuration file options in parallel.

   Note that this option must be specified in full - abbreviations are not supported.

``--profile`` [ *profile-data-file* ]
   Tell the tool to keep track of performance and other configuration data. If the optional *profile-data-file* is not specified, then the profile data is written to a file named *genhtml.json* in the output directory.

   Profile data is useful if you are trying to optimize the ``lcov`` implementation (see ``$LCOV_ROOT/share/lcov/support-scripts/spreadsheet.py``), and can also enable faster 'genhtml --parallel' execution (see the "--history-script" section of this man page).

``--history-script`` *script*
   Tell the tool to use performance data from a prior job to predict resource usage by the current job. This may allow better segmentation to enable more balanced workloads between parallel threads - thus improving wall clock execution time.

   A common source for the *previous-profile-data-file* is the profile data generated by a prior regression suite execution. See ``$LCOV_ROOT/share/lcov/example`` and ``$LCOV_ROOT/share/lcov/support-scripts/history.pm`` in the installed release (or ``.../example`` in the source repository).

``--rc`` *keyword* = *value*
   Override a configuration directive.

   Use this option to specify a *keyword* = *value* statement which overrides the corresponding configuration statement in the lcovrc configuration file. You can specify this option more than once to override multiple configuration statements. See :manpage:`lcovrc(5)` for a list of available keywords and their meaning.

``--precision`` *num*
   Show coverage rates with *num* number of digits after the decimal point.

   Default value is 1.

   This option can also be configured permanently using the configuration file option *genhtml_precision*.

``--merge-aliases``
   Functions whose file/line is the same are considered to be aliases; ``genhtml`` uses the shortest name in the list of aliases (fewest characters) as the leader.

   This option counts each alias group as a single object - so the 'function' count will be the number of distinct function groups rather than the total number of aliases of all functions - and displays them as groups in the 'function detail table.

   Note that this option has an effect only if ``"--filter function"`` has been applied to the coverage DB.

   This parameter an be configured via the configuration file *merge_function_aliases* option. See ``man(5) lcovrc``.

``--suppress-aliases``
   Suppress list of aliases in function detail table.

   Functions whose file/line is the same are considered to be aliases; ``genhtml`` uses the shortest name in the list of aliases (fewest characters) as the leader.

   The number of aliases can be large, for example due to instantiated templates - which can make function coverage results difficult to read. This option removes the list of aliases, making it easier to focus on the overall function coverage number, which is likely more interesting.

   Note that this option has an effect only if ``"--filter function"`` has been applied to the coverage DB.

   This parameter an be configured via the configuration file *merge_function_aliases* option. See ``man(5) lcovrc``.

``--forget-test-names``
   If non-zero, ignore testcase names in .info file - *i.e.*, treat all coverage data as if it came from the same testcase. This may improve performance and reduce memory consumption if user does not need per-testcase coverage summary in coverage reports.

   This option can also be configured permanently using the configuration file option *forget_testcase_names*.

``--missed``
   Show counts of missed lines, functions, branches, and MC/DC expressions.

   Use this option to change overview pages to show the count of lines, functions, branches, or MC/DC expressions that were not hit. These counts are represented by negative numbers.

   When specified together with --sort-tables, file and directory views will be sorted by missed counts.

   This option can also be configured permanently using the configuration file option *genhtml_missed*.

``--dark-mode``
   Use a light-display-on-dark-background color scheme rather than the default dark-display-on-light-background.

   The idea is to reduce eye strain due to viewing dark text on a bright screen - particularly at night.

``--tempdir`` *dirname*
   Write temporary and intermediate data to indicated directory. Default is "/tmp".

``--preserve``
   Preserve intermediate data files generated by various steps in the tool - *e.g.*, for debugging. By default, these files are deleted.

``--save``
   Copy *unified-diff-file, baseline_trace_files,* and *tracefile(s)* to output-directory.

   Keeping copies of the input data files may help to debug any issues or to regenerate report files later.

``--sort-input``
   Specify whether to sort file names before capture and/or aggregation. Sorting reduces certain types of processing order-dependent output differences. See the *sort_input* section in :manpage:`lcovrc(5)`.

``--serialize`` *file_name*
   Save coverage database to *file_name*.

   The file is in Perl "Storable" format.

   Note that this option may significantly increase *genhtml* memory requirements, as a great deal of data must be retained.


FILES
-----

*/etc/lcovrc*
   The system-wide configuration file.

*~/.lcovrc*
   The per-user configuration file.

Sample *--diff-file* data creation scripts:

   ``scripts/p4udiff``
      Sample script for use with ``--diff-file`` that creates a unified diff file via **Perforce**.

   ``scripts/gitdiff``
      Sample script for use with ``--diff-file`` that creates a unified diff file via **git**.

Sample *--annotate-script* callback Perl modules:

   ``scripts/p4annotate.pm``
      Sample script written as Perl module for use with ``--annotate-script`` that provides annotation data via **Perforce**.

   ``scripts/gitblame.pm``
      Sample script written as Perl module for use with ``--annotate-script`` that provides annotation data via git.

Sample *--criteria-script* callback Perl modules:

   ``scripts/criteria.pm``
      Sample script written as Perl module for use with ``--criteria-script`` that implements a check for "UNC + LBC + UIC == 0".

   ``scripts/threshold.pm``
      Sample script written as Perl module to check for minimum acceptable line and/or branch and/or and/or MC/DC function coverage. For example, the

      *"genhtml --fail_under_lines 75 ..."*

      feature can instead be realized by

      *"genhtml --criteria-script scripts/threshold.pm,--line,75 ..."*

Sample *--simplify-script* callback Perl module:

   ``scripts/simplify.pm``
      Sample script written as Perl module for use with ``--simplify-script`` that implements regular expression substitutions for function name simplification.

Sample *--version-script* callback Perl modules and scripts:

   ``scripts/getp4version``
      Sample script for use with ``--version-script`` that obtains version IDs via **Perforce**.

   ``scripts/P4version.pm``
      A perl module with similar functionality to **getp4version** but higher performance.

   ``scripts/get_signature``
      Sample script for use with ``--version-script`` that uses md5hash as version IDs.

   ``scripts/gitversion.pm``
      A perl module with for use with ``--version-script`` which retrieves version IDs from **git**.

   ``scripts/batchGitVersion.pm``
      A perl module with similar functionality to **gitversion.pm** but higher performance.


AUTHORS
-------

Peter Oberparleiter <Peter.Oberparleiter@de.ibm.com>

Henry Cox <henry.cox@mediatek.com>
   Differential coverage and date/owner binning, filtering, error management, parallel execution sections,


SEE ALSO
--------

:manpage:`lcov(1)`, :manpage:`lcovrc(5)`, :manpage:`geninfo(1)`, :manpage:`llvm2lcov(1)`, :manpage:`perl2lcov(1)`, :manpage:`py2lcov(1)`, :manpage:`gendesc(1)`, :manpage:`gcov(1)`

*https://github.com/linux-test-project/lcov*
