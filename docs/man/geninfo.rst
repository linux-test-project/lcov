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
           [--callgraph-coverage]
           [--callgraph-partial-data]
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
           [--expect-message-count *message_type* = *expr*
                                   [,*message_type* = *expr* ..]]
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

Use ``geninfo`` to create |ToolName| tracefiles from GCC and LLVM/Clang coverage
data files (see ``--gcov-tool`` for considerations when working with LLVM). You
can use ``genhtml`` to create an HTML report from a tracefile.

Note that ``geninfo`` is called by ``lcov --capture``, so there is typically no
need to call it directly.

Unless the ``--output-filename`` option is specified ``geninfo`` writes its
output to one file with .info filename extension per input file.

Note also that the current user needs write access to both *directory* as well
as to the original source code location. This is necessary because some
temporary files have to be created there during the conversion process.

By default, ``geninfo`` collects line and function coverage data but not branch,
MC/DC, or callgraph coverage.  The coverage classes can be enabled using command
line options ``--branch-coverage``, ``--mcdc-coverage`` and
``--callgraph-coverage`` and/or configuration file options
``branch_coverage = 1``, ``mcdc_coverage = 1`` and ``callgraph_coverage = 1``,
respectively. See :manpage:`lcovrc(5)` for details.

File types
~~~~~~~~~~

A ``tracefile`` is a coverage data file in the format used by all |ToolName|
tools such as ``geninfo``, ``lcov``, and ``genhtml``. By convention, tracefiles
have a .info filename extension. See "Tracefile format" below for a description
of the file format.

A ``.gcda file`` is a compiler-specific file containing run-time coverage data.
It is created and updated when a program compiled with GCC/LLVM's ``--coverage``
option is run to completion. ``geninfo`` reads .gcda files in its default mode
of operation. Note: earlier compiler versions used the .da filename extension
for this file type.

A ``.gcno file`` is a compiler-specific file containing static, compile-time
coverage data. It is created when source code is compiled with GCC/LLVM's
``--coverage`` option. ``geninfo`` reads .gcno files when option ``--initial``
is specified. Note: earlier compiler versions used .bb and .bbg filename
extensions for this file type.

A ``.gcov file`` is a textual or JSON representation of the data found in .gcda
and .gcno files. It is created by the ``gcov`` tools that is part of GCC (see
``--gcov-tool`` for LLVM considerations). There are multiple gcov file format
versions, including textual, intermediate, and JSON format. ``geninfo``
internally uses ``gcov`` to extract coverage data from .gcda and .gcno files
using the best supported gcov file format.

See the ``gcov`` man page for more information on .gcda, .gcno and .gcov output
formats.

Exclusion markers
~~~~~~~~~~~~~~~~~

To exclude specific lines of code from a tracefile, you can add exclusion
markers to the source code. Similarly, you can mark specific regions of code as
"unreachable". An "unreachable" error message is generated if any coverpoints in
unreachable regions are executed (*i.e.,* have non-zero hit counts. See the
*retain_unreachable_coverpoints_if_executed* section in :manpage:`lcovrc(5)` for
a description of the actions taken in this case.

Additionally you can exclude specific branches or MC/DC expressions without
excluding the involved lines from line and function coverage.

Exclusion markers are keywords which can for example be added in the form of a
comment. See :manpage:`lcovrc(5)` how to override the exclusion keywords
(*e.g.,* to reuse markers inserted for other tools or to generate reports with
different sets of excluded regions).

The following markers are recognized by geninfo:

``LCOV_EXCL_LINE``
    Lines containing this marker will be excluded.

``LCOV_EXCL_START``
    Marks the beginning of an excluded section. The current line is part of this
    section.

``LCOV_EXCL_STOP``
    Marks the end of an excluded section. The current line not part of this
    section.

``LCOV_UNREACHABLE_LINE``
    If the marked line is 'hit', then generate an error: we believe the marked
    code is unreachable and so there is a bug in the code, the placement of the
    directive, or both. Lines containing this marker will be excluded from
    reporting. Apart from error reporting, this directive is equivalent to
    *LCOV_EXCL_LINE.*

``LCOV_UNREACHABLE_START``
    Marks the beginning of an unreachable section of code. The current line in
    part of this region. As described in the *LCOV_UNREACHABLE_LINE* section,
    above: an error is generated if any code in the region is hit, but the code
    is excluded from reporting.

``LCOV_UNREACHABLE_STOP``
    Marks the end of the region of unreachable code. The current line not part
    of this section.

``LCOV_EXCL_BR_LINE``
    Lines containing this marker will be excluded from branch coverage.

``LCOV_EXCL_BR_START``
    Marks the beginning of a section which is excluded from branch coverage. The
    current line is part of this section.

``LCOV_EXCL_BR_STOP``
    Marks the end of a section which is excluded from branch coverage. The
    current line not part of this section.

``LCOV_EXCL_EXCEPTION_BR_LINE``
    Lines containing this marker will be excluded from exception branch
    coverage: Exception branches will be ignored, but non-exception branches
    will not be affected.

``LCOV_EXCL_EXCEPTION_BR_START``
    Marks the beginning of a section which is excluded from exception branch
    coverage. The current line is part of this section.

``LCOV_EXCL_EXCEPTION_BR_STOP``
    Marks the end of a section which is excluded from exception branch coverage.
    The current line not part of this section.

``LCOV_EXCL_CALLGRAPH_LINE``
    Call sites on lines containing this marker will be excluded from callgraph
    coverage. Line, branch, MC/DC and function coverage are not affected.

``LCOV_EXCL_CALLGRAPH_START``
    Marks the beginning of a section which is excluded from callgraph coverage:
    the call sites in the section are removed. The current line is part of this
    section.

``LCOV_EXCL_CALLGRAPH_STOP``
    Marks the end of a section which is excluded from callgraph coverage. The
    current line not part of this section.

In addition, ``geninfo`` also supports the *"--unreachable-script"* option. This
provides a mechanism to exclude particular branch expressions and/or MC/DC
conditions from coverage reports. A simple sample callback can be found in:

    ``bin``/unreach.pm.

This sample callback adds support for branch-specific and condition-specific
exclusion, specified by end-of-line annotations in the source code:

``LCOV_EXCLUDE_BRANCH  (expressionId[,blockId])+``
    One or more space-separated branch exclusions may specified.

    ``expressionId``:
        decimal integer which specifies which branch to exclude. An error is
        generated if the index is invalid

    ``blockId``
        decimal integer which specified the block index which contains the
        excluded expression. An error is generated if the block index is
        invalid. If there is only one branch block at this location, then the
        block ID does not need to be specified

    The annotation applies to the blocks written on the annotated line,
    including blocks which are held by the line of an earlier statement - see
    *<location>* in the ``BRDA:`` record, below. When the block ID is not
    specified, the first block written on the line is used.

``LCOV_UNREACHABLE_COND ([groupSize,]conditionId(t|f))+``
    One or more space-separated MC/DC exclusions may specified.

    ``groupSize``
        decimal integer which specified the group which contains the excluded
        condition. An error is generated if the groupSize is invalid. If there
        is only one MC/DC group at this location, then the groupSize does not
        need to be specified. As for branches, the annotation applies to the
        groups written on the annotated line.

    ``conditionId``
        decimal integer which specifies which condition to exclude. An error is
        generated if the index is invalid

    ``sense``
        't' or 'f': the value of the condition which is unreachable

For example, the line:

::

    code // LCOV_EXCLUDE_BRANCH 0,1 3 LCOV_EXCLUDE_CONDITION 0f

will exclude branch expressions 1 and 3 from block 0 (or generate an error if
there is more than one branch block on this line), and the 'false' sense of
condition 0 (or generate an error if there is more than one MC/DC group on this
line).

One way to determine the branch and/or condition ID in order to exclude them is
to generate an HTML report without exclusions then hover the mouse over the
colorized branch/condition region and read the IDs from the tooltip popup.
Another way is to simply read the BRDA/MCDC entries in coverage data file.

See the comment at the top of the sample script for more details.

Data consistency
~~~~~~~~~~~~~~~~

When *check_data_consistency* is enabled (the default - see
:manpage:`lcovrc(5)`), the tools check that the coverage data of each source
file makes sense - for example, that a function which is hit contains at least
one line which is hit, and that a line which is not hit has no branch which has
been. A failed check is reported as an *inconsistent* error (see the
*inconsistent* entry under ``--ignore-errors``).
In tools can also be instructed to modify the coverage data to make it
consistent.

The checks are performed when the tracefile is captured or read (*e.g.*, 
in ``geninfo``, ``lcov``, ``jacoco2lcov``, *etc.*).

The settings which control checking and data modification are:

*check_data_consistency*
   If 0, then no checks are performed and no data modifications occur.
   The data is used as is.

*merge_continuation_lines*
   Disabled (0) by default.  No data is modified.

   If enabled, the data of a statement which spans several lines is reported on
   its *leader* - typically, the first line: branch and MC/DC data on a line
   which has no line
   coverpoint is moved to that line (see *Statement merging*, below), and a
   line coverpoint on a later line of a statement is removed, if its hit count
   is 0, or if both it and the statement are hit and its hit count is less
   than or equal to that of the statement (see *Line merging*, below). The line
   coverpoint of the multi-line statement is placed on its first line, and
   records the statement's last line (see *Statement spans*, below).
   Applied only if *check_data_consistency* is enabled.

*ignore_lambda_consistency*
   Disabled (0) by default.

   If enabled, then branch/line/function 'hit' count consistency checks are
   *not* performed on lines which contain a lambda function - see *Lambdas*,
   below.
   If 0 (the default), then those checks *are* performed.

``--ignore-errors inconsistent``
   Turns an *inconsistent* error into a warning (or, if given twice, suppresses
   it), so that processing continues. The data is then corrected as the
   message says - for example, a function whose hit count does not agree with
   the lines it contains is marked 'hit' or 'not hit' to agree with them.

All the settings except ``--ignore-errors`` are configuration file options; set
them in the lcovrc file or with *--rc name=value*. See :manpage:`lcovrc(5)`.

**Statement merging**

Some compilers and coverage tools report a branch or MC/DC coverpoint on a
line which has no line coverpoint - typically, a later line of a condition
which is split across lines:

::

    10:  if (a &&
    11:      b)

Here, line 10 has a line coverpoint, but the branches of *b* are reported on
line 11, which does not. Without statement merging, such a line is reported as
*location has branchcov but no linecov data* and, if that message is ignored,
a line coverpoint is generated for line 11 with the hit count of its branches.
(An MC/DC coverpoint on a line without a line coverpoint gets a line
coverpoint in the same way, without a message.)

With *merge_continuation_lines* enabled, the branch and MC/DC data of line 11
is moved to line 10 instead. The data is moved to the first line of
the statement if that line has a line coverpoint, else to the last line of the
statement if that one has. That line is called the *anchor* below. The branch
blocks moved to the anchor are numbered after the blocks which are already
there. Each moved block and MC/DC group is held by the anchor - it is counted,
categorized and checked with the anchor's statement - but keeps its
*location*, the line it is written at: that is the line the report shows it at
and links to, the line whose exclusion markers apply to it, and the line
messages about it name. Its location is written in the ``^<location>`` field
of its ``BRDA:`` or ``MCDC:`` record, below. Data is moved only if every block
and group on the line can keep its location: it must be within 127 lines of
the anchor.

An MC/DC group which is moved to an anchor which already has a group of the
same size and location is merged into that group: the counts of each
expression are added, and an expression is excluded if it was excluded on
either line. Groups of the same size at different locations stay separate.

geninfo does the same for the data it reads from gcov, whether or not
*merge_continuation_lines* is enabled and without reading the source: branch
and MC/DC data which gcov reports on a line without a line coverpoint is held
by a line before it which has one, and keeps its own line as its location.
Data for which there is no such line within 127 lines is left where it is.

Which line holds the data depends on the gcov version:

- gcov 14 and later (the JSON intermediate format, version 2) write the basic
  blocks of each line and the source and target block of each branch. The
  data is held by the nearest line before it which has a line coverpoint and
  holds one of its blocks or a branch to one of them. If there is no such
  line, it is held by the nearest line before it which has a line coverpoint.
- earlier versions write no block information, and the data is held by the
  nearest line before it which has a line coverpoint. This is a guess, which
  is usually right: it is wrong when another statement lies between the
  statement and the data, such as an inner statement of a multiline loop
  condition.

The block information also decides the *unexecuted block* check (see
*geninfo_unexecuted_blocks* in :manpage:`lcovrc(5)`): with gcov 14 and later,
a line with a non-zero count and an unexecuted block but no branch is
consistent if one of its blocks is the target of an untaken branch. With
earlier versions, it is consistent if the nearest line before it which has a
line coverpoint holds branch data. The gcov 5 to 7 intermediate text format
does not mark lines with an unexecuted block, so the check is not made for it.

Data is moved only when the tool is able to analyze the source code and
prove to itself that it has found a multiline statement.  If it cannot
prove it (*e.g.*, due to tool limitations), the data is left unmodified
and the consistency checks described above may fire.
Coverage data is not moved if:

- the source file cannot be found;
- the statement cannot be delimited from its source - see below;
- the statement extends more than *filter_lookahead* lines (see
  :manpage:`lcovrc(5)`) on either side of the line;
- neither the first nor the last line of the multiline statement has a line
  coverpoint;
- the line, the anchor or a line between them is excluded from branch
  coverage, or holds an exclusion or unreachable marker (see *Exclusion
  markers*, above).

How a statement is delimited depends on the language of the file -
see the ``c_file_extenstions``, ``perl_file_extensions``,
``java_file_extensions``, ``python_file_extensions`` sections in
:manpage:`lcovrc(5)`:

C/C++ and Java
   A statement starts after the nearest *;*, *{* or *}* before the line which
   is not inside parentheses or brackets, and ends at the next *;* or *{* which
   is not. The condition of an *if*, *while*, *for*, *switch* or *catch* is a
   statement of its own (the whole header, in the case of a *for*); *else* and
   *do* are not part of the statement which follows them. A statement
   which begins on the line of the *}* which closes the block before it
   (*} else if (...)*) is recognized. The statement is not known if:

   - a line of it is a compiler directive, or is in a comment or string which
     spans lines;
   - it shares a line with another statement;
   - it contains a brace or a *;* inside parentheses (a lambda, or a GNU
     statement expression), or a *}* before its end (an initializer list);
   - it is a *case*, a *default* or a label.

   In an XS file, the line of a section keyword (*CODE:*, *PPCODE:*,
   *OUTPUT:*, *etc.*) ends the statement before it, and is not part of a
   statement itself.

Perl
   The same rules, except that an *if*, *while*, *etc.* statement runs to the
   *{* which opens the block it controls, and that a line which holds a
   construct the rule does not read - a quote-like operator, a regular
   expression, a heredoc or POD - is not known. A */* (or *//*, *//=*, */=*)
   which follows a variable, a number, *)*, *]* or *}* is read as an
   operator; any other */* is taken to start a regular expression. A block
   which is the first argument of *sort*, *map* or *grep* and which ends on
   the line it starts on is part of the expression.

Python
   The language's own rule: a logical line continues onto the next physical
   line after a *\\*, or while a *(*, *[* or *{* is open. A logical line which
   holds a string spanning physical lines is not known.

Other languages
   No data is moved.

After coverage data is moved, all the branch and MC/DC data on the anchor - the
anchor's own, as well as the moved data - is considered to belong to the
anchor's statement, and is checked against its line hit count:

- C/C++: no branch is taken more often than the line is executed, and some
  branch is taken if the line is executed;
- Python and Java (which hold only a Boolean 'hit' or 'not hit' flag rather
  than an integer count): a branch is taken exactly if the line is executed
  and vice versa;
- Perl: a branch is taken only if the line is executed and vice versa;
- any language: an MC/DC condition is sensitized only if the line is
  executed.

A failed check is reported once for the anchor, as an *inconsistent* error
which names the lines the data came from and each check which failed. If the
error is ignored, then the data stays merged.

Note that the first of these checks can fail on correct data for a loop
condition which is split across lines: the compiler may count a branch each
time the condition is evaluated, but count the anchor only when the loop is
entered. In this case, ignore the message; the data is merged anyway.

Statement merging is done for branch data only if branch coverage is enabled,
and for MC/DC data only if MC/DC coverage is enabled. The merge actions are
reported in 'verbose' mode - if you are curious to see what is happening
or need to debug a tool issue or tool limitation.

**Line merging**

Some compilers and coverage tools report a line coverpoint on a later line of
a multi-line statement - such that an interior line has a hit count of its own.
The count 
of such a line may be 0 although the statement was executed - for example,
Devel::Cover data for a Perl *foreach* whose list is on the line after the
keyword:

::

    5:  DA:440   foreach
    6:  DA:0         my $row (sort({ $a->[0] cmp $b->[0] } @{$rows{$w} // []}))
    7:               {

Or the count may be less than or equal to that of the first line of the
statement, while the branches of
the statement are split between several lines - for example, gcc data for

::

    10:  DA:6   w = make_alias(intern_sv(name),       BRDA: 0, 0
    11:                        sv_to_count(count),
    12:  DA:6                  SvOK(count) ? 1 : 0);  BRDA: 0, 6, 0, 0

where line 10 holds two branches of the conditional on line 12 which were not
taken, so that it is reported as *line is hit but no branches on line have been
evaluated*, though line 12 shows that the conditional was evaluated.

With *merge_continuation_lines* enabled, such a line coverpoint is removed, so
that the statement is reported once, at its anchor, and any branch and MC/DC
data of the line is moved to the anchor, as described above. A line
coverpoint is removed if:

- its hit count is 0, or both it and the hit count of the anchor are not 0
  and it is less than or equal to that of the anchor - in the data of each
  testcase, as well as in the summary.  A line which is hit more often than
  the anchor - *e.g.*, the condition of a loop whose header is split across
  lines - is retained: its branches would otherwise be taken more often
  than the line they are moved to is executed;
- the source shows which statement the line belongs to, and the line is not
  the anchor of that statement - the statement and its anchor are found as
  described under *Statement merging*, above;
- the line, the anchor and the lines between them are not excluded, and hold
  no exclusion or unreachable marker;
- the line is not the start line of a function; and
- if the line has branch or MC/DC data, the lines from the line to the anchor
  are not excluded from branch coverage either.

The coverpoint is removed from the data of each testcase, as well as from the
summary. The hit count of the anchor does not change. Line merging is done
before the other checks and corrections described in this section, so that, in
the second example, the branches of line 12 are moved to line 10 and checked
together with the branches already there. Each removed coverpoint is reported
in verbose mode.

A line whose count differs from that of the anchor (and is not 0) is kept: it
has some control flow of its own. Note that the later lines of a condition are
merged as well: for example, if *a* is false each time the C/C++ statement

::

    10:  if (a &&
    11:      b)

is executed, then the line coverpoint of line 11, if it has one, has a hit
count of 0, and is removed. Whether *b* was evaluated is shown by the branch
and MC/DC data of the statement.

When callgraph coverage is enabled, a call written on a line of a statement
which has no line coverpoint - because it was merged, or because the tool did
not give it one - is assigned to the anchor of the statement: it is counted and
categorized with the anchor's line, but still shown where it is written (see
*<statement line>* in the ``FNC:`` record, below). The call is assigned only
if the source shows which statement it belongs to and the anchor is within
127 lines of the call. Each assignment is reported in verbose mode.

Note also that whether a line coverpoint is removed depends on its count, so
that a line may have a coverpoint in one set of data and not in another - in
the baseline and the current data of a differential report, for example, or in
two tracefiles which are merged. In the latter case, the merged data is
checked again, and the line coverpoint is removed if its merged count meets
the conditions above; if it does not, then its count is that of the data in
which it was kept.

**Statement spans**

When *merge_continuation_lines* is enabled, the line coverpoint of a statement
which spans several lines also records the statement's extent - its
:term:`span <statement span>`:
the lines from its first to its last line. The span is written as the
*<end>* field of the ``DA:`` record, below, and is used by
:manpage:`genhtml(1)` to decide whether the statement was changed, when it
was changed, and by whom (see *Statement spans* in :manpage:`genhtml(1)`).
A statement is
found from its source as described under *Statement merging*, above. A line
at the end of the statement which holds nothing but a brace - ``{`` or ``}``,
once comments are removed - and has no line coverpoint is not part of the
statement: for example, the ``{`` on the line after a function's declaration
or after an ``if`` header. A brace line whose coverpoint is removed by a
filter (``--filter brace``, ``--omit-lines``, an exclusion marker) is not part
of it either: the spans of the data are checked again after filtering. A line
which holds more than the brace - ``{}``, ``};``, ``} else {`` - is part of the
statement. A statement which is left with a single line has no span.
The span holds every line from the first to the last, including comment and
blank lines inside the statement.

The line coverpoint of a statement is placed on the statement's first line:
if the coverpoint which remains after line merging is on a later line, then it
is moved to the first line, together with its testcase data. Its branch, MC/DC
and call site data remain where the data capture tool (*e.g.*, ``gcov``)
declared them to be - possibly on an interior line of the multi-line
statement. The coverpoint is not moved if it is
the start line of a function, or if its branch or MC/DC data could not retain
their locations (see *Statement merging*, above); the span then starts at the
coverpoint. Each move is reported in verbose mode.

If the line coverpoints of a statement cannot all be merged - because the hit
counts disagree, or a line is the start line of a function - then the
statement is partitioned: each line coverpoint which is retained starts a
:term:`segment` which runs to the line before the next one, and each segment is a
statement of its own, with its own span. A segment of one line has no span.
Each partition is reported in verbose mode, as *statement <first>-<last>
partitioned into <segment>, ...*.

A single-line statement does not have a span - nor does a
statement whose extent the source does not show (*e.g.*, source code
unavailable or line outside of the range of the file) does not have a span.

Spans which are read from a tracefile are retained whether or not
*merge_continuation_lines* is enabled in this particular tool execution
and are not recomputed if the control is enabled.
This enables the user to pay once for multi-line statement identification once
during capture and aggregation and then reuse it during report generation
without paying again.

Spans which disagree - in one tracefile, or in two which
are merged - raise an *inconsistent* error; if the error is ignored, the span
of that line coverpoint is dropped (when merging) or replaced by the later one
(when reading). The maximum span length is 127; a span which is not a 
complete statement after the maximum length raises a *format* error.
If the error is ignored, the span is dropped and the coverpoint is
retained where it was initially found (*e.g.*, in the ``gcov`` data).

**Lambdas**

A lambda body may be on the line which defines it, in which case the line
count and the branch counts of that line need not be about the same code: the
line may be executed without the lambda being called, for example.
Similarly, the hit count of the lambda function itself - the number of
times it is called - need not math the hit count of the line where it is
declared.

If *ignore_lambda_consistency* is 1, then the *line is hit but no branches on
line have been evaluated* and *line is not hit but at least one branch on line
has been evaluated* checks, and the checks done after a statement merge, are
not done on a line which holds a lambda. This applies to C/C++ and Java. A
line holds a lambda if:

- a function which is a lambda starts on that line - a C/C++ function whose
  demangled name contains *{lambda(* or whose mangled name contains a closure
  type (*Ul...E_*), or a Java function whose name contains *lambda$*; or
- the source line, if the source file is found, contains a C++ lambda
  (*[captures](params) {* or *[captures](params) -> type {*) or a Java lambda
  (*params ->*).

A suppressed check is reported in verbose mode.

OPTIONS
-------

In general, (almost) all ``geninfo`` options can also be specified in your
personal, group, project, or site configuration file - see the *--config-file*
section, below, and :manpage:`lcovrc(5)` for details.

``-b``, ``--base-directory`` *directory*
   Use *directory* as base directory for relative paths.

    Use this option to specify the base directory of a build-environment when
    geninfo produces error messages like:

    ::

        ERROR: could not read source file /home/user/project/subdir1/subdir2/subdir1/subdir2/file.c

    In this example, use /home/user/project as base directory.

    This option is required when using geninfo on projects built with libtool or
    similar build environments that work with a base directory, *i.e.*
    environments, where the current working directory when invoking the compiler
    is not the same directory in which the source code file is located.

    Note that this option will not work in environments where multiple base
    directories are used. In that case use configuration file setting
    ``geninfo_auto_base=1`` (see :manpage:`lcovrc(5)`).

``--build-directory`` *build_dir*
    Search for .gcno data files from *build_dir* rather finding them only
    adjacent to the corresponding .o and/or .gcda file.

    By default, geninfo expects to find the .gcno and .gcda files (compile- and
    run-time data, respectively) in the same directory.

    When this option is used:

    ::

        geninfo path1 --build-directory path2 ...

    then geninfo will look for .gcno file

    ::

        path2/relative/path/to/da_base.gcno

    when it finds .gcda file

    ::

        path1/relative/path/to/da_base.gcda.

    Use this option when you have used the *GCOV_PREFIX* environment variable to
    direct the gcc or llvm runtime environment to write coverage data files to
    somewhere other than the directory where the code was originally compiled.
    See :manpage:`gcc(1)` and/or search for *GCOV_PREFIX* and
    *GCOV_PREFIX_STRIP*.

    This option can be used several times to specify multiple alternate
    directories to look for .gcno files. This may be useful if your application
    uses code which is compiled in many separate locations - for example, common
    libraries that are shared between teams.

``--source-directory`` *dirname*
    Add 'dirname' to the list of places to look for source files.

    For relative source file paths found in the gcov data - possibly after
    substitutions have been applied, ``geninfo`` will first look for the path
    from 'cwd' (where genhtml was invoked) and then from each alternate
    directory name in the order specified. The first location matching location
    is used.

    This option can be specified multiple times, to add more directories to the
    source search path.

``--branch-coverage``
    Collect and retain branch coverage data.

    This is equivalent to using the option "--rc branch_coverage=1"; the option
    was added to better match the genhtml interface.

``--mcdc-coverage``
    Collect and retain MC/DC data.

    This is equivalent to using the option "--rc mcdc_coverage=1". MC/DC
    coverage capture is supported for GCC versions 14.2 and higher, or LLVM
    versions 18.1 and higher.

    See *llvm2lcov --help* for details on MC/DC data capture in LLVM.

    See the MC/DC section of :manpage:`genhtml(1)` for more details.

``--callgraph-coverage``, ``--callgraph``
    Collect callee (call site) coverage data: for each call in the source, which
    function it calls and how many times that call was executed.

    This is equivalent to using the option "--rc callgraph_coverage=1".

    See the ``--callgraph-coverage`` section of :manpage:`genhtml(1)` for the
    callgraph model this metric is defined in terms of, for the resolution rule
    and for its appearance in an HTML report, and see "Tracefile format" below
    for the records it is written as.

    Capture requires gcc 14 or newer, and a compile command line containing
    ``-fcallgraph-info=su,da``, which makes the compiler write its
    :term:`callgraph info` to a ``.ci`` file beside each object's ``.gcno``. If
    a ``.ci`` file is missing - *e.g.*, because some files were not
    instrumented - callgraph data is still collected from files which were
    instrumented.  An error is generated if there are no such files.

    The errors above are reported where the cause is found: per object for a
    missing ``.ci`` or a ``gcov`` which is too old, and per caller for a pairing
    failure. If they are ignored and the run ends up having captured no call
    site at all, ``geninfo`` says so and turns the metric off for that run, and
    the tracefile it writes contains no ``FNC``, ``FNCF:`` or ``FNCH:`` record -
    not even a zero total. Ignoring an error means continuing, not claiming to
    have measured something: a zero total would tell a reader that this code
    makes no calls, rather than that the calls were never measured. A run in
    which *some* object has the data is unaffected, which is what these errors
    being per object is for.

    For each function, ``geninfo`` pairs the calls the ``.ci`` lists with the
    calls ``gcov`` counted - see the description in :term:`pairing` of what that
    process entails and the ways that it can fail. In the event of such a
    failure, the mismatch is reported as an ``inconsistent`` error, once per
    caller. If the message is ignored (``--ignore-errors inconsistent``), then
    the callgraph data of the *whole* function is then discarded by default; the
    ``--callgraph-partial-data`` flag is used to retain data for the calls which
    did pair.

    Compile with ``-O0``, or with ``-fno-inline -fno-ipa-pure-const``, to
    collect callgraph data reliably. ``-fno-inline`` alone is not enough:
    ``-fipa-pure-const`` is on from ``-O1``, and at ``-O2`` the exceptional edge
    it deletes is much the more common of the two ways an arc goes missing. The
    ``.ci`` does not say which sites were inlined, so a mismatch cannot be
    repaired after the fact. The other two ways a call can fail to pair are not
    affected by the optimization setting.

    Note that a call to a function declared ``pure`` or ``const``
    (``__attribute__((pure))``, ``__attribute__((const))``, or the
    ``[[gnu::pure]]`` / ``[[gnu::const]]`` spelling) is never counted by
    ``gcov``, regardless of optimization setting. The ``.ci`` lists such a call
    anyway, so ``geninfo`` reads the callee's declaration - the ``.ci`` says
    which file and line it is on - and drops the call rather than reporting it
    as a mismatch. Run with ``--verbose`` to see how many calls were dropped and
    which callees they went to.

    The 'drop' decision is made from the declaration the compiler pointed to -
    the *definition* when the callee is defined in the unit being compiled - so
    a callee whose ``pure`` or ``const`` attribute is only on a prototype
    elsewhere in the code (say, in a header its callers include) will not be
    recognized, and calls to it will be reported as ``inconsistent``.  To work
    around: declare the attribute on the definition as well as the declaration,
    or ignore the error.

    A call need not be written in the file where its caller is defined: a call
    in an ``#include``\ d fragment belongs to the function which includes it,
    but its line and column are those of the fragment. Such a site is recorded
    with the fragment named as well - see the ``FNC:`` record and the ``SF:``
    index in "Tracefile format", below - and is counted by the file where the
    caller is defined, which is the file the ``.gcda`` describes. The fragment
    gets a section of its own, so that the report has a source view to show the
    call; it counts no callee of its own, because no function is defined there.

    A ``geninfo --initial`` capture reads the ``.ci`` beside the ``.gcno`` and
    records every call site with a count of zero.

    A capture records every call it sees, including calls to functions that will
    not be reported - standard library functions such as ``printf``, an
    implicitly instantiated ``std::`` template, a library the report excludes,
    *etc.*  Which of those callees the report defines is decided during
    aggregation - after capture is complete.  If the callee is not defined in
    the report, then the call site is dropped and the *has external callee*
    property is set on the caller (the ``c`` flag of the caller's ``FNL:``
    record). See :manpage:`genhtml(1)`.

    The ``.ci`` file also says which of the unit's symbols have external
    linkage - it file-qualifies the name of one which does not - and ``geninfo``
    records that as the ``e`` flag of the symbol's ``FNA:`` record. ``gcov``
    does not report it, and a report needs it: a call site names its callee by
    symbol, so a name which several files define can be attributed to one of
    them only by ruling out the definitions no other file could have called. In
    the callgraph the metric measures, the flag says that this function can be
    the *destination* of a call whose *source* is in another file.

``--callgraph-partial-data``
    Keep the call sites of a function whose calls did not all pair, rather than
    discarding that function's callgraph data. See :term:`pairing`.

    This is equivalent to using the option "--rc callgraph_partial_data=1".

    With the option enabled, the calls which did pair keep their counts, and an
    unpaired call which the ``.ci`` lists is written with a count of ``-``. Such
    a site is counted in the callee total but never in the callee hits, exactly
    as an untaken ``BRDA:`` branch is, and merging it with a site which does
    have a count yields that count. A call ``gcov`` counted which the ``.ci``
    does not list is still dropped: there is no callee name to record it under.

    Because pairing is by line, one unpaired call leaves every site on its line
    with an unknown count, and the ``inconsistent`` message says how many
    further sites were voided that way. An unknown count says what is known,
    where a count which belongs to another call on the line would say something
    false; a line of nested calls therefore reads as entirely unmeasured rather
    than as partly wrong.

    Sites left with an unknown count can be removed where the report is
    assembled rather than here; see ``--filter unknown_callee_count`` in
    :manpage:`genhtml(1)`.

    The option says only what to retain: the ``inconsistent`` error is raised
    either way, so it is normally used together with
    ``--ignore-errors inconsistent``. The two are independent on purpose - the
    error can be ignored without keeping the partial data, and the partial data
    can be kept while the error still stops the capture.

``--checksum``, ``--no-checksum``
   Specify whether to generate checksum data when writing tracefiles.

    Use ``--checksum`` to enable checksum generation or ``--no-checksum`` to
    disable it. Checksum generation is ``disabled`` by default.

    When checksum generation is enabled, a checksum will be generated for each
    source code line and stored along with the coverage data. This checksum will
    be used to prevent attempts to combine coverage data from different source
    code versions.

    If you don't work with different source code versions, disable this option
    to speed up coverage data processing and to reduce the size of tracefiles.

    Note that this options is somewhat subsumed by the ``--version-script``
    option - which does something similar, but at the 'whole file' level.

``--compat`` *mode* = *value* [,*mode* = *value*,...]
    Set compatibility mode.

    Use ``--compat`` to specify that geninfo should enable one or more
    compatibility modes when capturing coverage data. You can provide a
    comma-separated list of mode=value pairs to specify the values for multiple
    modes.

    Valid *values* are:

    ``on``
        Enable compatibility mode.

    ``off``
        Disable compatibility mode.

    ``auto``
        Apply auto-detection to determine if compatibility mode is required.
        Note that auto-detection is not available for all compatibility modes.

    If no value is specified, 'on' is assumed as default value.

    Valid *modes* are:

    ``libtool``
        Enable this mode if you are capturing coverage data for a project that
        was built using the libtool mechanism. See also ``--compat-libtool``.

        The default value for this setting is 'on'.

    ``hammer``
        Enable this mode if you are capturing coverage data for a project that
        was built using a version of GCC 3.3 that contains a modification
        (hammer patch) of later GCC versions. You can identify a modified GCC
        3.3 by checking the build directory of your project for files ending in
        the extension .bbg. Unmodified versions of GCC 3.3 name these files .bb.

        The default value for this setting is 'auto'.

    ``split_crc``
        Enable this mode if you are capturing coverage data for a project that
        was built using a version of GCC 4.6 that contains a modification (split
        function checksums) of later GCC versions. Typical error messages when
        running geninfo on coverage data produced by such GCC versions are 'out
        of memory' and 'reached unexpected end of file'.

        The default value for this setting is 'auto'.

``--compat-libtool``, ``--no-compat-libtool``
   Specify whether to enable libtool compatibility mode.

    Use ``--compat-libtool`` to enable libtool compatibility mode or
    ``--no-compat-libtool`` to disable it. The libtool compatibility mode is
    ``enabled`` by default.

    When libtool compatibility mode is enabled, geninfo will assume that the
    source code relating to a .gcda file located in a directory named ".libs"
    can be found in its parent directory.

    If you have directories named ".libs" in your build environment but don't
    use libtool, disable this option to prevent problems when capturing coverage
    data.

``--config-file`` *config-file*
    Specify a configuration file to use. See :manpage:`lcovrc(5)` for details of
    the file format and options. Also see the *config_file* entry in the same
    man page for details on how to include one config file into another.

    When this option is specified, neither the system-wide configuration file
    /etc/lcovrc, nor the per-user configuration file ~/.lcovrc is read.

    This option may be useful when there is a need to run several instances of
    ``geninfo`` with different configuration file options in parallel.

    Note that this option must be specified in full - abbreviations are not
    supported.

``--profile`` [*profile-data-file*]
    Tell the tool to keep track of performance and other configuration data. If
    the optional *profile-data-file* is not specified, then the profile data is
    written to a file named with the same basename as the *--output-filename*,
    with suffix *".json"* appended.

    Profile data is useful if you are trying to optimize the ``geninfo``
    implementation (see
    ``$LCOV_ROOT/share/lcov/support-scripts/spreadsheet.py``), and can also
    enable faster 'geninfo --parallel' execution (see the "--history-script"
    section of this man page).

``--history-script`` *callback*
    Tell the tool to use performance data from a prior job to predict resource
    usage by the current job. This may allow better segmentation to enable more
    balanced workloads between parallel threads - thus improving wall clock
    execution time.

    A common source for the performance history is the
    *previous-profile-data-file* generated by the *"--profile"* argument.

    See a sample callback implementation in
    ``$LCOV_ROOT/share/lcov/support-scripts/history.pm`` and its use in
    ``$LCOV_ROOT/share/lcov/example`` in the installed release (or
    ``.../example`` and ``.../scripts/history.pm`` in the source repository).

    See :manpage:`genhtml(1)` for more details.

``--external``, ``--no-external``
   Specify whether to capture coverage data for external source files.

    External source files are files which are not located in one of the
    directories specified by *--directory* or *--base-directory.* Use
    *--external* to include coverpoints in external source files while capturing
    coverage data or *--no-external* to exclude them. If your *--directory* or
    *--base-directory* path contains a soft link, then actual target directory
    is not considered to be "internal" unless the *--follow* option is used.

    The *--no-external* option is somewhat of a blunt instrument; the
    *--exclude* and *--include* options provide finer grained control over which
    coverage data is and is not included if your project structure is complex
    and/or *--no-external* does not do what you want.

    Data for external source files is ``included`` by default.

``-f``, ``--follow``
   Follow links when searching .gcda files, as well as to decide whether a
   particular (symbolically linked) source directory is "internal" to the
   project or not - see the *--no-external* option, above, for more information.
   The *--follow* command line option is equivalent to the
   *geninfo_follow_symlinks* config file option. See :manpage:`lcovrc(5)` for
   more information.

``--sort-input``
    Specify whether to sort file names before capture and/or aggregation.
    Sorting reduces certain types of processing order-dependent output
    differences. See the ``sort_input`` section in :manpage:`lcovrc(5)`.

``--gcov-tool`` *tool*
    Specify the location of the gcov tool.

    If the ``--gcov-tool`` option is used multiple times, then the arguments are
    concatenated when the callback is executed - similar to how the gcc
    ``-Xlinker`` parameter works. This provides a possibly easier way to pass
    arguments to your tool, without requiring a wrapper script. In that case,
    your callback will be executed as: *tool-0 'tool-1; ... 'filename'*'. Note
    that the second and subsequent arguments are quoted when passed to the
    shell, in order to handle parameters which contain spaces.

    The ``--gcov-tool`` argument may be a *split_char* separated string - see
    ``man(4) lcovrc``.

    A common use for this option is to enable LLVM:

    ::

        geninfo --gcov-tool llvm-cov --gcov-tool gcov ...
        geninfo --gcov-tool llvm-cov,gcov ...

    Note: 'llvm-cov gcov da_file_name' will generate output in gcov-compatible
    format as required by lcov.

    If not specified, 'gcov' is used by default.

``-h``, ``--help``
   Print a short help text, then exit.

``--include`` *pattern*
    Include source files matching *pattern*.

    Use this switch if you want to include coverage data for only a particular
    set of source files matching any of the given patterns. Multiple patterns
    can be specified by using multiple ``--include`` command line switches. The
    *patterns* will be interpreted as shell wildcard patterns (note that they
    may need to be escaped accordingly to prevent the shell from expanding them
    first).

    See :manpage:`lcov(1)` for details.

``--exclude`` *pattern*
    Exclude source files matching *pattern*.

    Use this switch if you want to exclude coverage data from a particular set
    of source files matching any of the given patterns. Multiple patterns can be
    specified by using multiple ``--exclude`` command line switches. The
    *patterns* will be interpreted as shell wildcard patterns (note that they
    may need to be escaped accordingly to prevent the shell from expanding them
    first). Note: The pattern must be specified to match the ``absolute`` path
    of each source file.

    Can be combined with the ``--include`` command line switch. If a given file
    matches both the include pattern and the exclude pattern, the exclude
    pattern will take precedence.

    See :manpage:`lcov(1)` for details.

``--erase-functions`` *regexp*
    Exclude coverage data from lines which fall within a function whose name
    matches the supplied regexp. Note that this is a mangled or demangled name,
    depending on whether the --demangle-cpp option is used or not.

    Note that this option requires that you use a gcc version which is new
    enough to support function begin/end line reports or that you configure the
    tool to derive the required data - see the ``derive_function_end_line``
    discussion in :manpage:`lcovrc(5)`.

``--substitute`` *regexp_pattern*
    Apply Perl regexp *regexp_pattern* to source file names found during
    processing. This is useful when the path name reported by gcov does not
    match your source layout and the file is not found. See :manpage:`lcov(1)`
    for more details.

``--omit-lines`` *regexp*
    Exclude coverage data from lines whose content matches *regexp*.

    Use this switch if you want to exclude line, branch, and MC/DC coverage data
    for some particular constructs in your code (*e.g.*, some complicated
    macro). See :manpage:`lcov(1)` for details.

``--forget-test-names``
    If non-zero, ignore testcase names in tracefile - *i.e.,* treat all coverage
    data as if it came from the same testcase. This may improve performance and
    reduce memory consumption if user does not need per-testcase coverage
    summary in coverage reports.

    This option can also be configured permanently using the configuration file
    option *forget_testcase_names*.

``--msg-log`` [*log_file_name*]
    Specify location to store error and warning messages (in addition to writing
    to STDERR). If *log_file_name* is not specified, then default location is
    used.

``--ignore-errors`` *errors*
    Specify a list of errors after which to continue processing.

    Use this option to specify a list of one or more classes of errors after
    which ``geninfo`` should continue processing instead of aborting. Note that
    the tool will generate a warning (rather than a fatal error) unless you
    ignore the error two (or more) times:

    ::

        geninfo ... --ignore-errors unused,unused

    *errors* can be a comma-separated list of the following keywords:

    ``branch``
        branch ID (2nd field in the .info file 'BRDA' entry) does not follow
        expected integer sequence.

    ``callback``
        Version script error.

    ``child``
        child process returned non-zero exit code during *--parallel* execution.
        This typically indicates that the child encountered an error: see the
        log file immediately above this message. In contrast: the ``parallel``
        error indicates an unexpected/unhandled exception in the child process -
        not a 'typical' lcov error.

    ``corrupt``
        corrupt/unreadable file found.

    ``count``
        An excessive number of messages of some class have been reported -
        subsequent messages of that type will be suppressed. The limit can be
        controlled by the 'max_message_count' variable.
	See :manpage:`lcovrc(5)`.

    ``deprecated``
        You are using a deprecated option. This option will be removed in an
        upcoming release - so you should change your scripts now.

    ``empty``
        the .info data file is empty (*e.g.*, because all the code was 'removed'
        or excluded.

    ``excessive``
        your coverage data contains a suspiciously large 'hit' count which is
        unlikely to be correct - possibly indicating a bug in your toolchain.

        See the *excessive_count_threshold* section in :manpage:`lcovrc(5)` for
        details.

    ``fork``
        Unable to create child process during *--parallel* execution. If the
        message is ignored (*--ignore-errors fork*), then genhtml will wait a
        brief period and then retry the failed execution. If you see continued
        errors, either turn off or reduce parallelism, set a memory limit, or
        find a larger server to run the task.

    ``format``
        Unexpected syntax or value found in .info file - for example, negative
        number or zero line number encountered.

        A count field which is not a legal integer (for example 'nan' or 'inf')
        is likewise treated as zero if this message is ignored;  a count which
        is a number but not an integer is truncated toward zero, and one too
        large to store is clamped at 9223372036854775807.

    ``gcov``
        the gcov tool returned with a non-zero return code.

    ``graph``
        the graph file could not be found or is corrupted.

    ``inconsistent``
        your coverage data is internally inconsistent: it makes two or more
        mutually exclusive claims. For example, some expression is marked as
        both an exception branch and not an exception branch. (See
        :manpage:`genhtml(1)` for more details.

        The data consistency checks, and the settings which control them and
        the corrections made when this message is ignored, are described in
        the *Data consistency* section above.

    ``internal``
        internal tool issue detected. Please report this bug along with a
        testcase.

    ``mismatch``
        Incorrect information found in coverage data and/or source code - for
        example, the source code contains overlapping exclusion directives.

    ``missing``
        File does not exist or is not readable.

    ``negative``
        negative 'hit' count found.

        A negative count is not a legal value for any cover type, so if this
        message is ignored, the count is treated as zero.

        Note that negative counts may be caused by a known GCC bug - see

        ::

            https://gcc.gnu.org/bugzilla/show_bug.cgi?id=68080

        and try compiling with "-fprofile-update=atomic". You will need to
        recompile, re-run your tests, and re-capture coverage data.

    ``package``
        a required perl package is not installed on your system. In some cases,
        it is possible to ignore this message and continue - however, certain
        features will be disabled in that case.

    ``parallel``
        various types of errors related to parallelism - *i.e.,* a child process
        died due to an error. The corresponding error message appears in the log
        file immediately before the *parallel* error.

        If you see an error related to parallel execution that seems invalid, it
        may be a good idea to remove the --parallel flag and try again. If
        removing the flag leads to a different result, please report the issue
        (along with a testcase) so that the tool can be fixed.

    ``parent``
        the parent process exited while child was active during *--parallel*
        execution. This happens when the parent has encountered a fatal error -
        *e.g.* an error in some other child which was not ignored. This child
        cannot continue working without its parent - and so will exit.

    ``path``
        some file paths were not resolved - *e.g.*, .gcno file corresponding to
        some .gcda was not found see *--build-directory* option for additional
        information.

    ``range``
        Coverage data refers to a line number which is larger than the number of
        lines in the source file. This can be caused by a version mismatch or by
        an issue in the *gcov* data.

    ``source``
        the source code file for a data set could not be found.

    ``unreachable``
        a coverpoint (line, branch, function, or MC/DC) within an "unreachable"
        region is executed (hit); either the code, directive placement, or both
        are wrong. If the error is ignored, the offending coverpoint is retained
        (not excluded) or not, depending on the value of the
        *retain_unreachable_coverpoints_if_executed* configuration parameter.
        See :manpage:`lcovrc(5)` and the *"Exclusion markers"* section, above.

    ``unsupported``
        the requested feature is not supported for this tool configuration. For
        example, function begin/end line range exclusions use some GCOV features
        that are not available in older GCC releases.

    ``unused``
        the include/exclude/erase/omit/substitute pattern did not match any file
        pathnames.

    ``usage``
        unsupported usage detected - *e.g.* an unsupported option combination.

    ``utility``
        a tool called during processing returned an error code (*e.g.*, 'find'
        encountered an unreadable directory).

    ``version``
        revision control IDs of the file which we are trying to merge are not
        the same - line numbering and other information may be incorrect.

    Also see the *--ignore-errors* section in :manpage:`genhtml(1)`. The
    description there may be more complete and/or more fully explained.

    See :manpage:`lcovrc(5)` for a discussion of the 'max_message_count'
    parameter which can be used to control the number of warnings which are
    emitted before all subsequent messages are suppressed. This can be used to
    reduce log file volume.

``--expect-message-count`` *message_type* = *expr* [,*message_type* = *expr*]
    Give ``geninfo`` a constraint on the number of messages of one or more types
    which are expected to be produced during execution. If the constraint is not
    true, then generate an error of type *"count"* (see above).

    See :manpage:`genhtml(1)` for more details about the flag, as well as the
    *"expect_message_count"* section in :manpage:`lcovrc(5)` for a description
    of the equivalent configuration file option.

``--keep-going``
    Do not stop if error occurs: attempt to generate a result, however flawed.

    This command line option corresponds to the *stop_on_error [0|1]* lcovrc
    option. See :manpage:`lcovrc(5)` for more details.

``--fail-under-lines`` *percentage*
    Use this option to tell geninfo to exit with a status of 1 if the total line
    coverage is less than *percentage.* See :manpage:`lcov(1)` for more details.

``--preserve``
    Preserve intermediate data files (*e.g.*, for debugging).

    By default, intermediate files are deleted.

``--filter`` *filters*
    Specify a list of coverpoint filters to apply to input data.
    See :manpage:`genhtml(1)` for details.

``--demangle-cpp`` [param]
    Demangle C++ method and function names in captured output.
    See :manpage:`genhtml(1)` for details.

``-i``, ``--initial``
   Capture initial zero coverage data.

    Run geninfo with this option on the directories containing .bb, .bbg or
    .gcno files before running any test case. The result is a "baseline"
    coverage data file that contains zero coverage for every instrumented line
    and function. Combine this data file (using lcov -a) with coverage data
    files captured after a test run to ensure that the percentage of total lines
    covered is correct even when not all object code files were loaded during
    the test. Also see the *--all* flag, below.

    Note: the ``--initial`` option is not supported for gcc versions less than
    6, and does not generate branch coverage information for gcc versions less
    than 8.

``--all``
    Capture coverage data from both compile time (.gcno) data files which do not
    have corresponding runtime (.gcda) data files, as well as from those that
    *do* have corresponding runtime data. There will be no runtime data unless
    some executable which links the corresponding object file has run to
    completion.

    Note that the execution count of coverpoints found only in files which do
    not have any runtime data will be zero.

    This flag is ignored if the *--initial* flag is set.

    Using the ``--all`` flag is equivalent to executing both *geninfo --initial
    ...* and *geninfo ...* and merging the result.

    Also see the *geninfo_capture_all* entry in ``man(5) lcovrc``.

``--no-markers``
    Unless the *--no-markers* option is used, ``geninfo`` will apply the
    *region* filter to the captured coverage data - and the *branch_region*
    filter if branch coverage is enabled, and the *callgraph_region* filter if
    callgraph coverage is enabled. Use this
    option if you want to get coverage data without regard to exclusion markers
    in the source code file.

    If any *--filter* options are applied, then the default region filters are
    not used.

    *--no-markers* should not be specified along with *--filter*.

``--no-recursion``
    Use this option if you want to get coverage data for the specified directory
    only without processing subdirectories.

``-o``, ``--output-filename`` *output-filename*
   Write all data to *output-filename*.

    If you want to have all data written to a single file (for easier handling),
    use this option to specify the respective filename. By default, one
    tracefile will be created for each processed .gcda file.

``--context-script`` *script*
    Use *script* to collect additional tool execution context information - to
    aid in infrastructure debugging and/or tracking.

    See :manpage:`genhtml(1)` for more details on the context script.

``--criteria-script`` *script*
    Use *script* to test for coverage acceptance criteria.

    See :manpage:`genhtml(1)` for more details on the criteria script. Note that
    geninfo does not keep track of date and owner information (see the
    *--annotate-script* entry in :manpage:`genhtml(1)`) - so this information is
    not passed to the geninfo callback.

``--resolve-script`` *script*
    Use *script* to find the file path for some source or GCNO file which
    appears in an input data file if the file is not found after applying
    *--substitute* patterns and searching the *--source-directory* or
    *--build-directory* list.

    This option is equivalent to the ``resolve_script`` config file option. In
    addition, the *geninfo_follow_path_links* config file option can be used to
    resolve source paths to their actual target.

    See :manpage:`lcovrc(5)` for details.

``--version-script`` *script*
    Use *script* to get a source file's version ID from revision control when
    extracting data. The ID is used for error checking when merging .info files.

    See :manpage:`genhtml(1)` for more details on the version script.

``--unreachable-script`` *module*
    Use *module* to decide whether particular branch expressions and/or MC/DC
    conditions should be removed from the coverage report. This option is
    equivalent to the ``unreachable_script`` config file option. See
    :manpage:`lcovrc(5)` for details.

    Note that *"module"* is required to be a Perl module.

    See :manpage:`genhtml(1)` and the *"Exclusion markers"* section, above, for
    more information.

``-v``, ``--verbose``
   Increment informational message verbosity. This is mainly used for script
   and/or flow debugging - *e.g.*, to figure out which data file are found,
   where. Also see the ``--quiet`` flag.

    Messages are sent to stdout unless there is no output file (*i.e.*, if the
    coverage data is written to stdout rather than to a file) and to stderr
    otherwise.

``-q``, ``--quiet``
   Decrement informational message verbosity.

    Decreased verbosity will suppress 'progress' messages for example - while
    error and warning messages will continue to be printed.

``--debug``
    Increment 'debug messages' verbosity. This is useful primarily to developers
    who want to enhance the lcov tool suite.

``--comment`` *comment_string*
    Append *comment_string* to list of comments emitted into output result file.
    This option may be specified multiple times. Comments are printed at the top
    of the file, in the order they were specified.

    Comments can be useful to document the conditions under which the trace file
    was generated: host, date, environment, *etc.*

``--parallel`` [*integer*], ``-j`` [*integer*]
   Specify parallelism to use during processing (maximum number of forked child
   processes). If the optional integer parallelism parameter is zero or is
   missing, then use to use up the number of cores on the machine. Default is to
   use a single process (no parallelism).

    The *--large-file* option described below may be necessary to enable
    parallelism to succeed in the presence of data files which consume excessive
    memory in ``gcov``.

    Note that ``geninfo`` writes coverage data ('.info') files rather than
    reading them, so the parallel '.info' file read controlled by the
    *parallel_parse_min_lines* and *parallel_parse_chunks_per_worker* entries in
    :manpage:`lcovrc(5)` does not apply here; see the ``--parallel`` sections of
    :manpage:`lcov(1)` and :manpage:`genhtml(1)`.

    Also see the *memory, memory_percentage, max_fork_fails, fork_fail_timeout,
    geninfo_chunk_size, geninfo_dedicate_segment_size,
    dedicate_segment_threshold, dedicate_segment_line_estimate* and
    *geninfo_interval_update* entries in :manpage:`lcovrc(5)` for a description
    of some options which may aid in parameter tuning and performance
    optimization. In particular, *geninfo_dedicate_segment_size* (and, when
    *--history-script* data is available, *dedicate_segment_threshold*) arrange
    for a large compilation unit to be given its own child process and scheduled
    first, so it does not serialize the tail of the run. A previously generated
    execution profile may help to enable better utilization and faster parallel
    execution. See the *"--profile"* and *"--history-script"* sections of this
    man page.

``--large-file`` *regexp*
    GCDA files whose name matches a *--large-file* regexp are processed
    serially - not in parallel with other files - so that their ``gcov`` process
    can use all available system memory.

    Use this option is you see errors related to memory allocation from gcov.

    This feature is exactly as if you had moved the matching GCDA files to
    another location and processed them serially, then processed remaining
    GCDA files in parallel and merged the results.

    Note that this is a memory-safety control, distinct from the
    latency-oriented *geninfo_dedicate_segment_size*: a *--large-file* match
    runs serially in the parent process, whereas a file that only exceeds
    *geninfo_dedicate_segment_size* is still forked (in its own dedicated child)
    and processed in parallel. A file matched by *--large-file* is never also
    given a dedicated child.

    This option may be used multiple times to specify more than one regexp.

``--memory`` *integer*
    Specify the maximum amount of memory to use during parallel processing, in
    Mb. Effectively, the process will not fork() if this limit would be
    exceeded. Default is 0 (zero) - which means that there is no limit.

    This option may be useful if the compute farm environment imposes strict
    limits on resource utilization such that the job will be killed if it tries
    to use too many parallel children - but the user does not know a priori what
    the permissible maximum is. This option enables the tool to use maximum
    parallelism - up to the limit imposed by the memory restriction.

    The configuration file *memory_percentage* option provided another way to
    set the maximum memory consumption. See :manpage:`lcovrc(5)` for details.

``--rc`` *keyword* = *value*
    Override a configuration directive.

    Use this option to specify a *keyword = value* statement which overrides the
    corresponding configuration statement in the lcovrc configuration file. You
    can specify this option more than once to override multiple configuration
    statements. See :manpage:`lcovrc(5)` for a list of available keywords and
    their meaning.

``-t``, ``--test-name`` *testname*
   Use test case name *testname* for resulting data. Valid test case names can
   consist of letters, decimal digits and the underscore character ('_').

    This proves useful when data from several test cases is merged (*i.e.* by
    simply concatenating the respective tracefiles) in which case a test name
    can be used to differentiate between data from each test case.

``--version``
    Print version number, then exit.

``--tempdir`` *dirname*
    Write temporary and intermediate data under the indicated directory. Default
    is the platform temporary directory: $TMPDIR, $TEMP or $TMP if one of them
    names a writeable directory, otherwise "/tmp" on Unix or "C:\\temp" on
    Windows.

    A uniquely named subdirectory of *dirname* is created for the run, and the
    data is written there - so several runs can share one *dirname* without
    colliding. *dirname* itself is created if it does not exist.

    Unless *--preserve* is specified, the generated subdirectory and its
    contents are removed when ``geninfo`` exits.

    This option can also be configured permanently using the configuration file
    option *lcov_tmp_dir*.

TRACEFILE FORMAT
----------------

Following is a quick description of the tracefile format as used by ``genhtml``,
``geninfo`` and ``lcov``.

A tracefile is made up of several human-readable lines of text, divided into
sections.

Where a record appears is part of the format, and not merely a convention:

::

    tracefile := ( comment | blank )*  section*
    section   := 'TN:'?  'SF:'  ( coverpoint | 'VER:' | comment | blank )*
                 'end_of_record'

That is:

-   A section begins with an ``SF:`` record (``KF:`` is accepted as a synonym)
    and ends with an ``end_of_record`` record.

-   An optional ``TN:`` record *precedes* the ``SF:`` record of the section
    whose data it names. ``TN:`` identifies the testcase which the section's
    data belongs to, so it cannot appear after the data it applies to.

-   The ``VER:`` record and all coverpoint records (``FNL:``, ``FNA:``,
    ``FNDA:``, ``FNC:``, ``BRDA:``, ``MCDC:``, ``DA:`` and the corresponding
    ``*F:``/``*H:`` summary records) appear *within* a section, in any order,
    except that the ``FNL`` record must appear before any corresponding ``FNA``
    record, and neither ``FNC`` nor ``FNM`` records can appear before the
    corresponding ``FNA``.

-   A section which holds any coverpoint record of a cover type also holds
    both of that type's summary records:  ``LF:``/``LH:`` beside ``DA:``,
    ``FNF:``/``FNH:`` beside ``FN:``, ``FNDA:``, ``FNL:`` or ``FNA:``,
    ``BRF:``/``BRH:`` beside ``BRDA:``, ``MCF:``/``MCH:`` beside ``MCDC:``, and
    ``FNCF:``/``FNCH:`` beside ``FNC:``. Only their presence is checked - the
    values are recomputed from the coverpoints - and the requirement holds even
    when the cover type is turned off. The reverse is not required: a summary
    pair with no coverpoints beside it, such as ``BRF:0``, is a measurement of
    none.

-   A comment record or a blank line may appear anywhere - inside a section or
    outside one.

Anything else - a coverpoint record outside any section, a ``TN:`` record inside
one, a second ``SF:`` with no intervening ``end_of_record``, an
``end_of_record`` with no section open, or end of file with a section still
open, or a missing summary record - is reported as a ``format`` error. See the ``--ignore-errors format``
discussion in :manpage:`lcov(1)`. If that error is ignored, the reader recovers
by discarding the misplaced record (or, in the unterminated-section cases, by
closing the section that is open) and keeping the data which was in the right
place.

Records of a cover type which is turned off are discarded as soon as they are
recognized - so their content is not examined and any malformed record is not
detected. For example, a malformed ``BRDA:`` record is dropped in silence rather
than reported as a ``format`` error. Recognizing the tag is enough to know that
the data was there, though: once a set of tracefiles has been read, and before
the tool does anything with the result, it prints a note naming each cover type
which the input carried and the command line discarded, together with the
``--<type>-coverage`` option which would have kept it. Such data is far more
often lost to a missing option than discarded on purpose. The same point is
where the tool complains that a cover type is enabled and the input held no
coverpoints of that type at all.

The count records are the exception to "the content is not examined": a zero one
is a measurement. ``BRF:0`` says that the producer counted this file's branches
and found none, which is a different statement from a file which carries no
``BRF:`` record. So the counts are summed as the input is read, and a report
which ends up with none of a cover type is complained about only where that sum
is not zero - the coverpoints were there and this run removed them - or where no
input carried the record at all. The sum is also why a tracefile this tool
writes repeats a zero pair it was given: dropping it would turn a measured
report into one which merely looks uncaptured. See the ``--ignore-errors empty``
discussion in :manpage:`lcov(1)`.

A comment record is:

::

    #comment_string

There is no space before or after the *#* character. Comment records are ignored
when a tracefile is read: they are not coverage data, so nothing is retained and
nothing is written back out. If the ``--comment comment_string`` option is
supplied, then a comment record appears at the top of the tracefile which the
tool writes.

If available, a tracefile begins with the *testname* which is stored in the
following format:

::

    TN:<test name>

For each source file referenced in the .gcda file, there is a section containing
filename and coverage data:

::

    SF:[<index>,]<path to the source file>

*<index>*
    is optional: a non-negative integer, numbered from zero within this
    tracefile, used by ``FNC:`` records to identify a call site file.  Within a
    particular |ToolName| data file, it is a unique file identifier.  However,
    two tracefiles which describe the same file may number it differently or not
    number it at all, so the index is resolved while the tracefile is read and
    is not part of the data: the tool which writes the next tracefile numbers
    whatever needs numbering there.

    Which files are indexed, and in what order, is not stable and should not be
    relied on. An index is written only if something in the tracefile needs it:
    a tracefile with no call site written in a file other than its caller's own
    contains no index at all.

    A file name which itself begins with digits and a comma - ``12,odd.c`` - is
    the one name a reader could not tell from an index. Such a file is given an
    index whether or not any record names it, which makes its record unambiguous
    without altering the name: the name is the field which takes the rest of the
    line.

An optional source code version ID follows:

::

    VER:<version ID>

If present, the version ID is compared before file entries are merged (see
``lcov --add-tracefile``), and before the 'source detail' view is generated by
genhtml. See the ``--version-script callback_script`` documentation and the
sample usage in the lcov regression test examples.

Function coverage data follows. Note that the format of the function coverage
data has changed from LCOV 2.2 onward. The tool continues to be able to read the
old format but now writes only the new format. This change was made so that
``function`` filter outcome is persistent in the generated tracefile.

Functions and their aliases are recorded contiguously:

First, the leader:

::

    FNL:<index>[<flags>],<line number of function start>[,<line number of function end>]

*<flags>*
    is optional: a string of lower-case letters immediately after the index,
    with no comma before them - ``FNL:3c,10,20``.

    Each letter corresponds to a property of the function, and are written only
    when callgraph coverage is enabled. The flags are on the ``FNL:`` record
    rather than on an ``FNA:`` record because they are properties of the
    function body - of the code all of its aliases share - rather than of a
    particular symbol. There is currently one such letter, ``c`` - indicating
    *has external callee* - that is "this function calls some function which is
    outside the callgraph boundary".

Then the aliases of the function; there will be at least one alias. All aliases
of a particular function share the same index.

::

    FNA:<index>[<flags>],<execution count>,<name>

*<flags>*
    is optional: a string of lower-case letters immediately after the index,
    with no comma before them - ``FNA:3ex5,1234,foo``.  The ``x`` letter may
    be followed by a count.

    The flags encode properties of call sites of this alias which cross the
    callgraph boundary:

    - ``e`` indicates "external linkage": the edge has ends in different files
    - ``x`` indicates "is called from outside the callgraph boundary",
      optionally followed by the number of calls made from there,
    - ``d`` indicates "has a deduced external caller": the alias was entered
      more often than its recorded call sites and its ``x`` count account
      for.  Advisory - see
      below - and written after the other letters, and
    - ``c`` indicates that the function calls a destination which is outside
      the callgraph boundary.  (Note that this flag is placed on the ``FNL``
      record - see above.)

    See *Callgraph coverage*, below, for a discussion of the meaning of each
    flag, and the ``--callgraph-coverage`` section of :manpage:`genhtml(1)` for
    the callgraph model they are defined in.

An alias which other aliases of the function were merged into (see the
*collapse_callgraph_alias* setting in :manpage:`lcovrc(5)`) is followed by one
record for each name merged into it, in sort order:

::

    FNM:<index>#<position>,<execution count>,<merged name>

*<position>* is the position of the retained among the ``FNA:`` records of
*<index>*, counted from zero in the order the section has them - as the alias
positions of an ``FNC:`` record are. *<execution count>* is the merged name's
own share of the execution count of the retained alias: the rest of that count is
the retained name's. The merged name is the last field and may contain commas.
A record whose alias has not been defined by an ``FNA:`` record read before it
is a ``format`` error; ignored, the record is dropped. When data is combined,
the merged names of an alias are the union of the names each input merged into
it, and the count of a name is the sum of its counts; the alias's own name is
never one of them.

The now-obsolete function data format (still understood by |ToolName| - but now
deprecated) is:

::

    FN:<line number of function start>,[<line number of function end>,]<function name>

The 'end' line number is optional, and is generated only if the
compiler/toolchain version is recent enough to generate the data (*e.g.*, gcc 9
or newer). This data is used to support the ``--erase-functions`` and
``--show-proportions`` options. If the function end line data is not available,
then these features will not work.

Next, there is a list of execution counts for each instrumented function:

::

    FNDA:<execution count>,<function name>

This list is followed by two lines containing the number of functions found and
hit:

::

    FNF:<number of functions found>
    FNH:<number of function hit>

Note that, as of LCOV 2.2, these numbers count function groups - not the
individual aliases.

If callgraph coverage is enabled, the call sites of each function follow its
aliases - the ``FNL:`` and ``FNA:`` records above - because a site is recorded
against the function which *contains* it and names that function by index:

::

    FNC:<index>[@<source file index>][#<alias position>[.<alias position>...]][^<statement line>],<line number>,<column>,<ordinal>,<execution count>,<callee name>

Each ``FNC:`` record is one edge of the callgraph the metric measures:
*<index>* and the location fields are its *source* - which function makes
the call, and where - and *<callee name>* is its *destination*. The record
is written in the section of the file its source is defined, that file's
:term:`translation unit` is the only one which knows the call was made,
so an edge which crosses out of the boundary the tracefile draws is captured
in full on this side of it; in contrast, an edge which crosses *in* has no
record here and instead is indicated by the ``x`` flag on the ``FNA`` record.
A record whose destination is outside the boundary has no callee in the
captured data - and is instead indicated by the ``c`` flag on the ``FNL``
record of the caller.

*<index>*
    is the index of the ``FNL:`` record of the function the call is *in* - the
    caller, the source of the edge.
    Call sites belong to the caller -  not to the callee - so a call to a
    function which is defined in some other file (or outside the callgraph
    boundary and so not present in the report)
    is recorded here exactly like any other.
    Whether such a call has a callee in the report is determined after all
    the report records are read (or after all the gcov data is processed).

*<source file index>*
    is optional: the ``SF:`` index (see ``SF:``, above) of the file the call
    is *written* in, when that is not the file this section describes. It
    rides on the caller's index, after an ``@`` delimiter.

    The two indices differ when the caller's body comes from somewhere else -
    a call in an ``#include``'d fragment, which the compiler attributes to
    the fragment's line while the function containing it is defined in the
    including file. Such a site is still a site of its caller, and so of
    this section. Only the location is elsewhere, and *<line number>* and
    *<column>* are then lines and columns of that other file.

    A section's own file is not indexed for this purpose, so the field is
    absent for the ordinary case of a call written in the file it is
    compiled in.

    An edge can name as many as three files:

    - the one its source is defined in - which is the section the record is
      written in
    - the one the call is written in, which is this field, and
    - the one its destination is defined in, wherever *<callee name>* turns
      out to be defined.

    The file must have an ``SF:`` section of its own in the same tracefile,
    which may appear before or after the record which refers to it.
    An index no section defines is a ``format`` error; ignoring that error
    drops the call site.

*<alias position>*
    is optional: which of the function's aliases make the call, where that is
    not all of them. It follows the caller's index (and the source file index,
    if there is one) after a ``#`` delimiter, and lists one or more positions
    separated by ``.``.  A position counts the ``FNA:`` records of *<index>* in
    the order the section has them, starting at zero; lcov writes the ``FNA:``
    records of a function sorted by name, and so ``FNC:3#1`` is the second
    of them in that order.

    The aliases of one function share its call sites; in most cases (*e.g.*,
    in C code or non-template C++) there is only one alias for each function -
    ann all calls were of that (single) alias.  In contrast, a C++ template -
    or any other function which the compiler emits more than once from one
    body - may have multiple aliases, each at the same location and whose
    calls depend on the template parameters and may go to different callee:
    ``apply<A>`` calls ``A::operator()`` and ``apply<B>`` calls
    ``B::operator()`` from the same line and column. The *<alias position>*
    field distinguishes which instantiation made which call so the report
    can say who calls whom.

    Without the field, a call is made by every alias the section gives the
    function - which is not the same as every alias the function ends up
    with: when sections of two translation units which instantiate different
    aliases of one function are merged, each call stays with the aliases of
    the section it came from, and those of a call which both sections record
    are combined. A position for which the section has no ``FNA:`` record is a
    ``format`` error; ignoring that error drops the position, and drops the
    call site if no position is left.

    The aliases which this shows to make the same calls, and to be called from
    the same places, can be merged into one where the report is assembled; see
    the *collapse_callgraph_alias* setting in :manpage:`lcovrc(5)`. ``geninfo``
    does not apply it: the calls into a function are known only once the data
    of every file is.

*<statement line>*
    is optional: the line of the statement the call is part of, when that is
    not *<line number>* - *i.e.*, the call is on a middle line of a multiline
    statement. It follows the other flags, after a literal ``^`` delimiter.
    A call written on a later line of a multi-line statement may have no line
    coverpoint of its own to be counted with; see *Line merging* in the *Data
    consistency* section. The call is then counted, and categorized, with the
    statement's line - while *<line number>* and *<column>* tell us where it
    is written - which is where report hyperlinks lead.

    The field is absent when the call is written on its statement's line -
    the usual case. It is not used for a call written in another
    file (see *<source file index>*), and must be within 127 lines of
    *<line number>*: otherwise it will trigger ``format`` error which,
    if ignored, causes this record to be dropped.

*<line number>* and *<column>*
    are the location of the call in the source.
    The column is part of the identity of a site: two calls on one line at
    different columns are two distinct sites.

    They locate the call within the file named by *<source file index>* when
    there is one, and within this section's file otherwise.
    Two calls at the same line and column in two different files are also two
    distinct sites.

*<ordinal>*
    distinguishes sites which the compiler gave the *same* line and column -
    for example, the arguments of ``sum3(a(), b(), c())`` are typically all
    reported at the column of ``sum3``.
    It is numbered from zero, in the order the compiler lists the calls, and
    is a property of the compiled code, so two captures of the same build
    will agree.

    What it does not number is two calls to the *same* callee at one line
    **and** column: those are one site, and its count is their sum. Only an
    identical location is merged - ``freefn(x, 1) + freefn(x, 2)`` calls one
    function twice on one line at two different columns, and those remain
    distinct with distinct counts - as described above. The merge applies only
    if the column is the same as well - as then there is nothing in the report
    to distinguish them: a line, a column and a callee is the finest granularity
    the report can use, it is what the source view underlines and what a
    differential report categorizes, so two such records would be two rows a
    reader could not distinguish - and could not be told which of them was the
    one that was missed.

    The compiled code has more than one call to one callee at one place whenever
    the call needs a cleanup path: a local with a non-trivial destructor,
    together with a call which may throw, gives the destructor two calls at the
    closing brace - the normal one carrying the calls which were made and the
    unwind one carrying zero. So what is measured is a call as it is *written*,
    and a ``-fno-exceptions`` build of the same source measures the same number
    of calls as the default one.

*<execution count>*
    is how often this call was executed, summed over every call the compiled
    code makes to this callee from this location - see *<ordinal>*.
    The count may differ from the execution count of the line it is on -
    for example, due to conditional execution:  ``c ? f() : g()`` - the line
    may have been executed many times but ``g()`` never called.

    The count may also be ``-``, meaning that the compiler recorded this call
    but the coverage data carries no count for it - see
    ``--callgraph-partial-data``, above.
    Such a site counts towards ``FNCF:`` and never towards ``FNCH:``.

*<callee name>*
    is the name of the called function - the destination of the edge - mangled
    unless the data was captured with ``--demangle-cpp``. It is a name rather
    than an index because the destination need not be in the tracefile at all;
    when it is, the reader has to work out which definition of the name it is,
    which is what the ``e`` flag below is for.
    This is the last field and the only free-text one: it takes the rest of
    the line, so it may contain commas.

This list is followed by two records containing the number of call sites found
and hit:

::

    FNCF:<number of call sites found>
    FNCH:<number of call sites hit>

These count the sites *contained in* this section's functions - the same
thing the ``FNC:`` records of the section list - and not the calls made to
them from elsewhere. A site is hit if its execution count is non-zero.

The pair is written only for a section which the callgraph data says something
about: one whose functions contain a call site, or carry one of the flags
below, or are named by a call site in some other section.  ``FNCF:0`` asserts
that this file's calls were counted and that there are none, and there is no
measurement behind that for a file which was compiled without
``-fcallgraph-info`` - which is a property of the object, so one build can
hold objects with the data beside objects without it. Nothing in a tracefile
distinguishes such a file from a leaf translation unit, so neither is claimed
for it.  A section with no function of its own - an ``#include``\ d fragment,
whose calls belong to functions of the file which includes it - does carry the
pair, for the same reason it carries ``FNF:0``: there is nothing in it for a
site to belong to, so the zero is not a measurement either way.

Callgraph coverage also records properties of symbols and of callgraph
edges which cross the callgraph boundary as flag letters.  A flag is only
ever set, never cleared:

``e`` (on ``FNA:``)
    indicates that this alias has *external linkage*: that it can be the
    destination of an edge whose source is in another file, which a
    ``static`` cannot be. That is what lets an ambiguous call be attributed
    to it: a file which defines no function of the callee's name must have
    called one reachable from outside its own file. Without the assertion
    such a call cannot be resolved at all - see the resolution rule
    in :manpage:`genhtml(1)`. It comes from the compiler's callgraph
    information, so only a capture taken with a compiler which supplies it
    (gcc 14 or newer) makes it.

``x`` or ``x``\ *<count>* (on ``FNA:``)
    indicates that this alias is the destination of an edge whose source is
    outside the boundary of the callgraph represented by the tracefile: a
    call to it is written somewhere outside
    the callgraph boundary.  *<count>* is the number of calls those call
    sites made - the sum of their execution counts - and is absent where it
    is not known (for example, where the dropped site's own count was
    ``-``).  ``x0``means that such an edge exists and was not taken.

    The coverage DB does not contain any other information about the
    external callers - *e.g.*, no location - and so can report only that
    external callers exist (*i.e.*, there is at least one external caller
    but may be more) and how often they called this alias.
    The flag is set when a removal (``lcov --remove``,
    ``lcov --extract``, an ``exclude`` pattern, ``--erase-functions``, or
    an excluded call site) drops a call site, whatever count that site had,
    so that a tracefile written afterwards still says that the edge is
    there - and it is never *un*\ set.  The counts of the sites are added
    to it, so it accounts for exactly the calls the dropped sites made.

    When tracefiles are merged, the counts of the flag are summed as the
    counts of the dropped sites would have been:  an unknown count
    contributes nothing to a known one.

    The same thing happens without a removal when a call site is written
    in a file the report does not describe: the site names that file
    (see the ``FNC:`` record, above), and if no section defines it there
    is no source the site could be shown in and no file which could count
    it, so the site becomes this flag on its callee.

``d`` (on ``FNA:``)
    indicates that this alias was entered more often than the recorded
    call sites which name it and the calls counted by its ``x`` flag
    together account for: at least one call reached it
    from somewhere the tracefile does not show - an uninstrumented or
    uncaptured translation unit, a call through a function pointer, or the
    runtime itself (this is how ``main`` is called, for example).
    Where the recorded
    and the dropped sites account for every call, the alias has ``x`` and
    not ``d``.

    Unlike the other letters, ``d`` does not indicate anything that cannot
    also be deduced from the data via some simple arithmetic ("add up all
    the known call sites plus known external sites and compare to the number
    of executions of this alias").

``c`` (on ``FNL:``)
    indicates that this function is the *source* of an edge whose destination
    is outside the boundary callgraph represented by the report: it
    calls some function
    function which the report does not describe.
    This is the mirror image of ``x``, and is kept for the same reason.

    A call out of the boundary has a full ``FNC:`` record when it is
    captured, because the calling unit knew everything about it; what it
    does not have is a callee within the callgraph boundary.
    A function outside the boundary is outside by construction - it is
    in a system header, in a third party library, in a file the report
    never described, or in one the user dropped via ``lcov --remove``,
    ``lcov --extract``, an ``exclude`` pattern or ``--erase-functions``.

    The same fact is recorded whichever end of the callgraph edge the report
    contains. Removing the file which contains the *callee* sets ``c`` on
    the surviving caller; removing the file which contains the *caller*
    sets ``x`` on the surviving callee; removing both records nothing - there
    being no function left for it to be a fact about.

Absence of a flag is not the opposite claim.
  - ``e`` is absent for a ``static``,
    for a symbol which is file-local for some other reason (an inline function
    or a template instantiation, which the compiler emits in a :term:`comdat`),
    *and* for a capture which simply had nothing to say - a tracefile written
    by a tool which does not know these flags at all.
  - ``x`` is absent for a function all of whose callers are recorded sites,
    and equally for a capture which never looked.
  - ``d`` is absent for a function whose callers account for its count, for
    one where an unknown count leaves that undecided, and for any tracefile
    written without resolving the callgraph - a capture.
  - ``c`` is absent for a function all of whose calls are to functions the
    report describes, for one which makes no calls at all, and for a
    tracefile written before any boundary was drawn - a capture, where no
    site has been dropped yet.

So absence means only that nothing asserted the flag, and a reader must not read
the negative into it.

``e``, ``x`` and ``c`` are properties of the function rather than of the
run which observed it, so a flag survives ``lcov --add-tracefile``: merging a
capture which asserts it with one which does not keeps the assertion,
in either order. This is what makes it correct to capture the units of a
program separately and combine them afterwards.

Branch coverage information is stored one line per branch:

::

    BRDA:<line_number>,[<exception>][<fallthrough][<unreachable>]<block>[^<location>],<branch>,<taken>

*<line_number>*
    is the line number of the statement which holds the branch - and is
    expected to be a non-zero integer. The branch is counted and categorized
    with that line.

*<location>*
    is optional: the line the block is written from, when that is not
    *<line_number>* - *e.g.*, a middle line of a condition which is split
    across multiple lines; see *Statement merging* in the *Data consistency*
    section.
    The report shows and links to the block at *<location>*, the exclusion
    markers of *<location>* apply to it, and messages about it name
    *<location>*. It must be within 127 lines of *<line_number>*: otherwise
    it will trigger a ``format`` error which, if ignored causes this record
    to be dropped.
    All the branches of a block have the same *<location>*.

*<block>* and *<branch>*
    serve to uniquely define a particular edge in the expression tree of a
    particular conditional found on the associated line.

    Within a particular line, *<block>* is an integer numbered from zero with no
    gaps. For some languages and some coding styles, there will only be one
    block (index value zero) on any particular line.

    *<branch>* is a string which serves to uniquely identify a particular edge.
    For some languages and tools - *e.g.*, C/C++ code compiled with gcc or
    llvm - *<branch>* is an ordered integer index related to expression tree
    traversal order of the associated conditional. For others, it may be a
    meaningful string - see below. *<branch>* appears in the 'tooltip' popup of
    the associated branch in the ``genhtml`` output - so human-readable values
    are helpful to users who are trying to understand coverage results - for
    example, in order to develop additional regression tests, to improve
    coverage.

*<taken>*
    is either '-' if the corresponding expression was never evaluated (*e.g.*,
    the basic block containing the branch was never executed) or a number
    indicating how often that branch was taken.

*<exception>*
    is 'e' (single character) if this is a branch related to exception
    handling - and is not present if the branch is not related to exceptions.
    Exception branch identification requires compiler support. geninfo will be
    able to identify exception branches only if your toolchain version is new
    enough to support the feature.

*<fallthrough>*
    is 'f' (single character) if this is a branch is marked as 'fallthrough'
    (*e.g.*, in the gcov output) - and is not present if the branch is not
    marked. Fallthrough branch identification requires compiler support. geninfo
    will be able to identify fallthrough branches only if your toolchain version
    is new enough to support the feature. A branch may be marked as
    '<exception>' or '<fallthough' - but not both.

*<unreachable>*
    is 'U' (single character) if this branch is associated with an 'unreachable
    directive, and is not present if the branch is reachable. Unreachability is
    intended to mark branch expressions which are should not appear in coverage
    reports - enabling users to ignore uncovered branches which can never be
    covered, to concentrate on other areas of the coverage report.

    See the *"--unreachable-script"* discussion in :manpage:`genhtml(1)` and the
    *"ignore_unreachable_flag"* discussion in :manpage:`lcovrc(5)` for more
    information on how branch exclusion markers are set and used.

The following are example branch records whose *<branch>* expression values are
human-readable strings.

::

      BRDA:10,0,enable,1
      BRDA:10,0,!enable,0

In this case, the corresponding code from line 10 is very likely similar to:

::

       if (enable) {
         ...
       }

such that the associated testcase entered the block ('enable' evaluated to
'true').

Arbitrarily complicated branch expressions are supported - including branch
expressions which contain commas (*e.g.,* in an expression containing a function
call).

Note that particular tools may or may not suppress expressions which are
statically true or statically false - *e.g.,* expressions using template
parameters. This makes it potentially complicated to compare coverage data
generated by two different tools.

A note on branch identification, matching, and merging:

As noted previously: lcov merely presents coverage data which is identified by
other tools such as gcov. Unfortunately, gcov (and other tools) do not produce
sufficient information to uniquely identify branch expressions - so lcov is
forced to use a heuristic solution based on the order of appearance as well as
the number and type of individual branch elements - say, in the gcov output.

lcov computes a 'signature' for each "<block>". If the block ID and signature
found while capturing data from multiple files or while merging coverage data -
then the block is considered identical and corresponding expression counts are
combined.

Within a particular line, there may be one or more blocks with the same
signature - for example, corresponding to independent branch expressions in
function call arguments on that line, or to different macro or template
expansion. lcov keeps track of the order that branch blocks were found (say, in
the gcov output or in an lcov .info file).

When merging branch data on a particular line:

-   Blocks which have different signatures, or which are written at different
    locations, are considered to be distinct.

-   Blocks which have identical signatures are matched in order: the zeroth
    block with signature *s1* in coverage DB A is merged with the zeroth block
    with signature *s1* in coverage DB B - and so on.

-   If one or the other DB does not contain some signature, or one DB contains
    more blocks with the same signature: then those non-matching blocks are
    simply copied to the merged output.

This heuristic can cause ambiguity in the generated report - especially for
cases that a particular line expands in different ways in different compilation
units - *e.g.,* due to template or macro expansion. In such cases, it may not be
possible for lcov to know that some block whose signature and order appear to
match, is not actually the same block. It may be possible to refactor the code
slightly to introduce explicit temporaries (on their own line) to resolve the
ambiguity.

Branch coverage summaries are stored in two lines:

::

    BRF:<number of branches found>

Note that this count does not include 'excluded' branches. Excluded branches
*do* appear as BRDA records.

::

    BRH:<number of branches hit>

Note that this count does not include 'excluded' branches. Excluded branches
*do* appear as BRDA records.

MC/DC information is stored one line per expression:

::

    MCDC:<line_number>,[<unreachable>]<groupSize>[^<location>],<sense>,<taken>,<index>,<expression>

where:

*<line_number>*
    is the line number of the statement which holds the condition - and is
    expected to be a non-zero integer.

*<location>*
    is optional: the line the group is written at, when that is not
    *<line_number>* - as for the ``BRDA:`` record, above. A group is identified
    by its *<groupSize>* and its *<location>* together: two groups of the
    same size on one line are distinct if they are written at different
    lines.

*<groupSize>* and *<index>*
    serve to uniquely define a particular element in the expression tree of a
    particular conditional found on the associated line.

    Within a particular line and group,

*<index>*
    is an integer numbered from zero to *<groupSize> - 1* with no gaps. For some
    languages and some coding styles, there will only be one group on any
    particular line.

*<sense>*
    is either *"f"* or *"t"*, indicating whether the condition is sensitive to
    the indicated change - that is, does the condition outcome change if the
    corresponding changes from 'false' to 'true' or from 'true to false,
    respectively.

*<taken>*
    is a count - 0 (zero) if the expression was not sensitized, non-zero if it
    was sensitized. Note that some tools may treat *<taken>* as the number of
    times that the expression was sensitized where others may treat it as a
    boolean - 1:sensitized or 0: not sensitized.

*<expression>*
    is an arbitrary string, intended to be a meaningful string which will help
    the user to understand the condition context - see below. *<expression>*
    appears in the 'tooltip' popup of the associated MC/DC condition in the
    ``genhtml`` output - so human-readable values are helpful to users who are
    trying to understand coverage results - for example, in order to develop
    additional regression tests, to improve coverage.

    For a given <groupSize> and <index>, the <expression> should be identical
    for both "t" and "f" senses.

*<unreachable>*
    is 'U' (single character) if this condition is associated with an
    'unreachable directive, and is not present if the condition is reachable.
    Unreachability is intended to mark conditions which should not appear in
    coverage reports - enabling users to ignore uncovered conditions which can
    never be covered, to concentrate on other areas of the coverage report.

    See the *"--unreachable-script"* discussion in :manpage:`genhtml(1)` and the
    *"ignore_unreachable_flag"* discussion in :manpage:`lcovrc(5)` for more
    information on how branch exclusion markers are set and used.

The following are example MC/DC records whose *<expression>* values are
human-readable strings.

::

      MCDC:10,2,f,0,0,enable
      MCDC:10,2,t,1,0,enable
      ...

In this case, the corresponding code from line 10 is very likely similar to:

::

       if (enable ...) {
         ...
       }

such that the associated testcase was sensitive to a change of 'enable' from
true to false (but not the converse).

Arbitrarily complicated expressions are supported - including expressions which
contain commas (*e.g.,* in an expression containing a function call).

Note that particular tools may or may not suppress expressions which are
statically true or statically false - *e.g.,* expressions using template
parameters. This makes it potentially complicated to compare coverage data
generated by two different tools.

MCDC coverage summaries are stored in two lines:

::

    MCF:<number of conditions found>

Note that this count does not include 'excluded' conditions. Excluded branches
*do* appear as MCDC records.

::

    MCH:<number of condition hit>

Note that this count does not include 'excluded' conditions. Excluded branches
*do* appear as MCDC records.

Then there is a list of execution counts for each instrumented line (*i.e.* a
line which resulted in executable code):

::

    DA:<line number>,<execution count>[,[<checksum>][,<end>]]

Note that there may be an optional checksum present for each instrumented line.
The current ``geninfo`` implementation uses an MD5 hash as checksumming
algorithm.

*<end>* is the optional last line of the multi-line statement which starts
on *<line_number>*: *<line number>* is the
statement's first line, and *<end>* is greater than *<line number>* by at most
127. The checksum field may be empty: *DA:3,1,,5*. See *Statement spans*,
above.

At the end of a section, there is a summary about how many lines were found and
how many were actually instrumented:

::

    LH:<number of lines with a non-zero execution count>
    LF:<number of instrumented lines>

Each sections ends with:

::

    end_of_record

In addition to the main source code file there are sections for all #included
files which also contain executable code.

Note that the absolute path of a source file is generated by interpreting the
contents of the respective .gcno file (see :manpage:`gcov(1)` for more
information on this file type). Relative filenames are prefixed with the
directory in which the .gcno file is found.

Note also that symbolic links to the .gcno file will be resolved so that the
actual file path is used instead of the path to a link. This approach is
necessary for the mechanism to work with the /proc/gcov files.

FILES
-----

*/etc/lcovrc*
    The system-wide configuration file.

*~/.lcovrc*
    The per-user configuration file.

``bin``/getp4version
    Sample script for use with ``--version-script`` that obtains version IDs via
    Perforce.

``bin``/get_signature
    Sample script for use with ``--version-script`` that uses md5hash as version
    IDs.

AUTHOR
------

Peter Oberparleiter <Peter.Oberparleiter@de.ibm.com>

Henry Cox <henry.cox@mediatek.com>
    Filtering, error management, parallel execution, MC/DC, and callee sections.

SEE ALSO
--------

:manpage:`genhtml(1)`, :manpage:`lcov(1)`, :manpage:`lcovrc(5)`,
:manpage:`gcov(1)`,
:manpage:`llvm2lcov(1)`

https://github.com/linux-test-project/lcov
