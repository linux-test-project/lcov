======================================================================
spreadsheet.py - Convert |ToolName| profile data to Excel spreadsheet
======================================================================

:Manual section: 1
:Manual group: |ToolName| Utilities

NAME
----

spreadsheet.py
 Convert |ToolName| profile data to Excel spreadsheet for performance analysis and comparison


SYNOPSIS
--------

::

    spreadsheet.py [-o output.xlsx] [options] data.json [data2.json ...]

DESCRIPTION
-----------

``spreadsheet.py`` is a utility script that converts JSON profile data from
``genhtml``, ``geninfo``, and ``lcov`` into an Excel spreadsheet for easier
analysis. The script processes performance timing data and presents it in a
tabular format with statistical analysis and conditional formatting.

The spreadsheet includes:

- **Summary sheets** for comparing multiple runs
- **Per-file timing data** for detailed analysis
- **Statistical summaries** (total, average, standard deviation)
- **Conditional formatting** to highlight outliers

Color Coding
------------

The spreadsheet uses conditional formatting to highlight timing anomalies:

- **Yellow**: Values between 1.5 and 2.0 standard deviations larger than average
  (and more than 15% above average)
- **Red**: Values more than 2.0 standard deviations larger than average
  (and more than 15% above average)
- **Green**: Values more than 2.0 standard deviations smaller than average
  (significantly better performance)

Supported Tools
---------------

The script processes profile data from:

- **geninfo**: Chunk timing, file processing, filter operations
- **genhtml**: Source parsing, HTML generation, annotation, categorization
- **lcov**: Tracefile merging, parsing, segment processing

OPTIONS
-------

``-o`` *file*, ``--out`` *file*
   Save Excel output to specified file. Default: ``stats.xlsx``.

``--threshold`` *percent*
   Minimum percentage difference from average to trigger colorization.
   Differences smaller than this threshold are not highlighted.
   Default: 15.0%.

``--low`` *multiplier*
   Standard deviation multiplier for yellow highlighting. Values between
   ``--low`` and ``--high`` standard deviations above average are colored
   yellow. Default: 1.5.

``--high`` *multiplier*
   Standard deviation multiplier for red highlighting. Values more than
   ``--high`` standard deviations above average are colored red.
   Default: 2.0.

``-v``, ``--verbose``
   Increase verbosity of the report. Includes additional timing data
   such as read and translate operations.

``--show-filter``
   Include filter operation timing data in the spreadsheet. Filter data
   shows time spent in filter chunk processing, queue operations, and
   merging.

*files*
   One or more JSON profile data files to process. Files should be generated
   using the ``--profile`` option of ``geninfo``, ``genhtml``, or ``lcov``.

EXAMPLES
--------

Basic usage with a single profile file:

::

    $ spreadsheet.py -o report.xlsx geninfo_profile.json

Compare multiple profile runs:

::

    $ spreadsheet.py -o comparison.xlsx run1.json run2.json run3.json

Include filter timing data with verbose output:

::

    $ spreadsheet.py --show-filter -v -o detailed.xlsx profile.json

Adjust sensitivity for outlier detection:

::

    $ spreadsheet.py --threshold 10 --low 1.0 --high 1.5 -o sensitive.xlsx data.json

Generating Profile Data
-----------------------

To generate profile data for analysis, use the ``--profile`` option:

::

    $ geninfo --profile geninfo_profile.json -o coverage.info ./build
    $ genhtml --profile genhtml_profile.json -o html coverage.info
    $ lcov --profile lcov_profile.json -a a.info -a b.info -o merged.info

AUTHOR
------

Henry Cox <henry.cox@mediatek.com>

SEE ALSO
--------

:manpage:`genhtml(1)`, :manpage:`geninfo(1)`, :manpage:`lcov(1)`

- xlsxwriter documentation: https://xlsxwriter.readthedocs.io
