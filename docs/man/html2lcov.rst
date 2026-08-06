=========================================================
html2lcov - Recover lcov data from a genhtml HTML report.
=========================================================


:Manual section: 1
:Manual group: |ToolName| Tools

NAME
----

html2lcov
 Recover lcov ``.info`` coverage data and a source diff from an HTML report

SYNOPSIS
--------

::

    html2lcov [--output filename] [--source-directory dir]+ [--current-file file]+ [options] report_directory+

DESCRIPTION
-----------

``html2lcov`` screen-scrapes a ``genhtml``-generated HTML coverage report to
recover:

- The LCOV ``.info`` coverage data that was used to produce the report.
  ``genhtml`` copies its input ``.info`` files into the top level of the
  report directory when it is run with ``--save``;  ``html2lcov`` finds and
  aggregates those files, using the same layout definition that
  ``genhtml --save`` uses to write them (so the reader and writer cannot
  drift).  It is an error if the report does not contain any such ``.info``
  file.

- The source code that was embedded in the per-file HTML pages.  This is
  compared against the source found under ``--source-directory`` to produce a
  universal diff and a human-readable difference report.
  Note that ``html2lcov`` needs to see all of the original source code: the
  input HTML report must not be a subset report containing only part of
  the source code
  (*i.e.*, not a report generated using a ``--select-script`` callback).


The source directory may contain new files that were not in the report, and
may omit files that were in the report;  these differences are documented in
the difference report rather than being treated as errors.  It is an error if
the source directory contains no file that matches any file in the report.

Because ``genhtml`` expands tabs and normalizes some whitespace when it renders
source into HTML, the comparison is run with ``diff -b``, which ignores
differences in the amount of whitespace (a tab and any run of spaces compare
equal), so re-indented or tab-vs-space-only changes do not appear as spurious
differences.

USE CASES
---------

The common use case for ``html2lcov`` is when the user has code and/or
test changes in their sandbox, has a coverage report from earlier in the day,
and now wants to see whether subsequent changes are adequately tested.
Unfortunately:  the user isn't entirely sure what the code looked like
when the report was generated - and does not have a corresponding label.
In that case:  file diffs and baseline coverage data
can be extracted from the report, and then used as the ``genhtml``
``--diff-file`` and ``--baseline-file`` inputs.

Another common case is when some or all of the source code is generated
and not under revision control - but the user wants to verify that
it is properly tested after configuration and/or generator changes.


OPTIONS
-------

``html2lcov`` supports the options that are common to the other tools in the
|ToolName| suite, and honours the corresponding ``lcovrc(5)`` settings.  In
particular:

- file selection and path manipulation:  ``--include``, ``--exclude``,
  ``--erase-functions``, ``--substitute``, ``--filter``, ``--omit-lines``,
  ``--demangle-cpp``.  These apply to the coverage data recovered from the
  report exactly as they do when the same data is read by ``lcov`` - so a
  file which is excluded is also absent from the universal diff and from the
  difference report.
- parallelism and resource limits:  ``--parallel`` (``-j``), ``--memory``,
  ``--tempdir``, ``--preserve``.  ``html2lcov`` forks children both to read
  the report's saved ``.info`` file(s) and to scrape and diff the report's
  source pages, so ``--parallel`` speeds up both phases of a large report;
  see `PARALLELISM`_.
- message control and diagnostics:  ``--ignore-errors``, ``--keep-going``,
  ``--expect-message-count``, ``--msg-log``, ``--quiet``, ``--verbose``,
  ``--debug``.
- configuration and provenance:  ``--config-file``, ``--rc``, ``--comment``,
  ``--version``, ``--help``.

The tool-specific options are:

``--output`` *filename*, ``-o`` *filename*
   Name a *base* for the output files.  Any extension is stripped from
   *filename* to form *base*, and each artifact then appends its own extension:
   the aggregated coverage is written to *base*\ ``.info``, the human-readable
   difference report to *base*\ ``.rpt``, the universal diff to *base*\
   ``.udiff`` (unless ``--diff-file`` redirects it), and the profile (if
   ``--profile`` is used) to *base*\ ``.json``.  When ``--output`` is omitted
   *base* is ``html2lcov`` and the universal diff is written to standard output.

``--source-directory`` *dir*
   Search *dir* for the current source files to diff against the report's
   embedded source.  May be used more than once.  Files are matched by their
   path relative to the report's recovered source root.  When ``--source-directory``
   is not specified it defaults to ``.`` (the current directory).

``--current-file`` *filename*
   An lcov ``.info`` file whose ``SF:`` records name the current source files.
   May be specified more than once, and each value may itself be a list
   separated by the configured list separator (see ``lcovrc(5)``).

   When any ``--current-file`` is given, its union of ``SF:`` paths becomes an
   authoritative whitelist of the current source files:

   - Only files named in a ``SF:`` record may appear in the universal diff (as
     *changed* or *added*).  Every other file found under ``--source-directory``
     is ignored.
   - A file present in the report (baseline) but **not** in the current set is
     treated as *removed*.
   - A file present in the current set but **not** in the report is treated as
     *added*.

   ``html2lcov`` uses the ``.info`` only as a file list;  its coverage data
   is not merged into any output.  The expected workflow is to feed the
   ``html2lcov`` universal diff to ``genhtml --diff-file`` and the aggregated
   ``.info`` output to ``genhtml --baseline-file``, using this same
   ``--current-file`` ``.info`` as the ``genhtml`` *current* input.

   A current ``SF:`` path is matched to a report file when it equals either the
   report file's recovered path or its report-root-relative path (after any
   ``--substitute`` rules are applied);  relative and absolute path styles are
   preserved on output.  If a file appears in both sets under names that differ
   only in path (a shared basename or path tail), ``html2lcov`` emits an
   ignorable ``mismatch`` warning.  Use ``--substitute`` (or an external tool
   such as :manpage:`sed(1)`) to reconcile path differences the tool cannot
   resolve on its own.

   If a ``SF:`` path names a file that cannot be read from disk under
   ``--source-directory``, ``html2lcov`` reports an ignorable ``source`` error;
   when that error is ignored, the file is dropped from the universal diff and
   its record is removed from the aggregated ``.info`` output.

   A missing ``--current-file`` is a fatal error;  an empty file raises an
   ignorable ``empty`` error;  a non-empty file that contains no ``SF:`` record
   is not an LCOV file and is a fatal error.

``--diff-file`` *filename*
   Write the universal diff to *filename* instead of the default *base*\
   ``.udiff`` (or standard output when ``--output`` is omitted).

``--profile`` [*filename*]
   Write timing and statistics data as JSON to *filename* (default is
   *base*\ ``.json``).

See :manpage:`lcov(1)` and :manpage:`lcovrc(5)` for details of other supported
options and configuration settings.

OUTPUTS
-------

``html2lcov`` produces up to four distinct artifacts:

- **universal diff** (*base*\ ``.udiff``) - written to *base*\ ``.udiff``, or
  to standard output when ``--output`` is omitted;  ``--diff-file`` redirects it
  elsewhere.  Standard ``diff -u`` format, so it can be consumed by ``genhtml
  --diff``.  Files only under ``--source-directory`` appear as additions (versus
  ``/dev/null``);  files only in the report appear as removals.  May be empty
  when there are no code changes.  For a changed file both diff headers (``---``
  and ``+++``) name the same path -- the source path recovered from the report,
  which is exactly the ``SF:`` record in the aggregated ``.info`` -- so
  ``genhtml`` can associate the diff with the recovered baseline coverage.

- **aggregated coverage** (*base*\ ``.info``) - the ``current`` coverage
  recovered from the report's saved ``.info`` file(s).

- **difference report** (*base*\ ``.rpt``) - a human-readable table listing
  every changed, added, removed, and unchanged file, with added/deleted line
  counts.

- **profile** (*base*\ ``.json``) - timing/statistics data, when ``--profile``
  is used.

PARALLELISM
-----------

Both of the expensive phases of ``html2lcov`` are parallelized, and both are
governed by ``--parallel`` (``-j``) and ``--memory``:

- reading the ``.info`` file(s) saved in the report - the same parallel parse
  that ``lcov --add-tracefile`` uses.

- scraping the source out of the report's HTML pages and diffing it against
  ``--source-directory``.  Each child scrapes and diffs a group of files and
  returns only the classification and the udiff text, so the recovered source
  never accumulates in the parent.  Files are grouped by the size of the HTML
  page each is scraped from, so that the groups cost roughly the same;  a
  report with only a handful of files is processed in this process rather than
  paying for a fork.

The output does not depend on ``--parallel``:  the ``.info``, ``.udiff`` and
``.rpt`` artifacts are identical for any value.

EXAMPLES
--------

Recover coverage and diff current source against a saved report:

::

    # Generate coverage and an HTML report, saving the input .info files
    $ lcov --capture -d . -o cov.info
    $ genhtml cov.info --save -o html_report

    # make code and/or test changes
    ...

    # capture new coverage data
    $ lcov --capture -d . -o current.info

    # Recover the .info data and diff the current source tree
    $ html2lcov -o changes html_report --source-directory ./src --current-file current.info

    # 'changes.udiff' is the universal diff (diff -u format)
    # 'changes.info'  is the recovered coverage data
    # 'changes.rpt'   is the human-readable difference report

    # now generate a differential report - to see what has changed:
    $ genhtml -o differential --baseline-file changes.info --diff-file changes.udiff current.info

Also see the ``example_html2lcov`` in the *example* directory ``|ToolName|_HOME/share/lcov/example``:

::

   $ cd |ToolName|_HOME/share/lcov/example
   $ make example_html2lcov

NOTES
-----

Coverage cannot be recovered from a report that was built without ``--save``,
because the ``.info`` files are not present in the report directory.
``html2lcov`` treats this as an error rather than attempting a lossy scrape of
the coverage counts from the HTML.

If the source under ``--source-directory`` is identical to the source embedded
in the report, there are no differences to emit.  This is a normal, expected
outcome (for example, when the current source has not changed since the report
was built), so ``html2lcov`` reports it as a non-fatal ``empty`` warning
(``No source code differences found``) and still exits successfully.  Use
``--ignore-errors empty`` to suppress the warning entirely.

AUTHOR
------

Henry Cox <henry.cox@mediatek.com>

SEE ALSO
--------

:manpage:`lcov(1)`, :manpage:`genhtml(1)`, :manpage:`geninfo(1)`,
:manpage:`lcovrc(5)`
