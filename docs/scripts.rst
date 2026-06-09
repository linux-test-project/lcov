.. _scripts:

============================
|TOOL_NAME| Callback Scripts
============================

This section documents the callback scripts provided with |TOOL_NAME| for integration
with version control systems, coverage criteria checking, and report customization.

Note that these are intended as examples of possible callback implementations -
but the intent is that users may want or need to write their own in order
to support specific requirements and/or development environments.

.. contents:: Section Contents
   :local:
   :depth: 1
   :backlinks: none


Annotate Scripts: ``--annotate-script`` option
==============================================

These scripts extract file annotation data (author, date, version) for age/ownership
tracking in differential coverage reports.

.. _gitblame:

gitblame.pm
-----------

Run ``git blame`` for a file and format the result to match the diffcov(1) 
annotation specification.

::

    use gitblame;
    my $callback = gitblame->new([options]);
    $callback->annotate(filename);

**Options:**

``--p4``
   Assume the GIT repo is cloned from Perforce - look for the changelist ID
   in the commit log message.

``--prefix`` *path*
   Prepend *path* to pathname before processing.

``--abbrev`` *regexp*
   Specify regexp patterns to compute user name abbreviations.

``--cache`` *dir*
   Cache directory for storing previous results to improve performance.

``--verify``
   Do additional consistency checking when merging local edits.

``--log`` *logfile*
   File for annotation-related log messages (useful for debugging).

``--domain`` *name*
   Strip domain from author addresses; treat users outside matching domain
   as "External".

Note that ``gitblame`` is a stand-alone executable which does the same thing
as ``gitblame.pm`` - except that it is called as an executable rather than
as a module.


.. _p4annotate:

p4annotate.pm
-------------

Run ``p4 annotate`` for a file and format the result to match the diffcov(1)
annotation specification.

::

    use p4annotate;
    my $callback = p4annotate->new([options]);
    $callback->annotate(filename);

**Options:**

``--cache`` *dir*
   Cache directory for storing previous results.

``--verify``
   Do additional consistency checking when merging local edits.

``--log`` *logfile*
   File for annotation-related log messages.

Note that ``p4annotate`` is a stand-alone executable which does the same thing
as ``p4annotate.pm`` - except that it is called as an executable rather than
as a module.
   

Version Scripts: ``--version-script`` option
============================================

These scripts extract file version information for verifying that merged
coverage data comes from the same source version.

Version checking is useful as it is easy to inadvertently mix data
from different branches or different products and then create misleading or
inconsistent reports which can be difficult to debug.

.. _gitversion:

gitversion.pm
-------------

Use git commands to determine the version of a file.

::

    use gitversion;
    my $callback = gitversion->new([options]);
    $version = $callback->version($filepath);
    $callback->compare_version($v1, $v2, $filepath);

**Options:**

``--p4``
   Assume the GIT repo is cloned from Perforce.

``--md5``
   Return MD5 signature for files not in git.

``--local-change``
   Check for local uncommitted changes.

``--prefix`` *path*
   Prepend *path* to pathname before processing.


Note that ``gitversion`` is a stand-alone executable which does the same thing
as ``gitversion.pm`` - except that it is called as an executable rather than
as a module.


.. _batchGitVersion:

batchGitVersion.pm
------------------

Optimized version extraction that creates an initial database of version
stamps for all files, then queries during execution.

::

    use batchGitVersion;
    my $callback = batchGitVersion->new([options]);
    $version = $callback->extract_version(pathname);

**Options:**

``--md5``
   Use MD5 for files not in repo.

``--allow-missing``
   Don't error if file is not in git.

``--repo`` *repo*
   Repository directory.

``--prepend`` *path*
   Prepend path to filenames.

``--prefix`` *dir*
   Prefix directory.

``--token`` *string*
   Token prefix for version strings.

.. _P4version:

P4version.pm
------------

Use Perforce commands to determine file versions.

::

    use P4version;
    my $callback = P4version->new([options]);
    $version = $callback->extract_version($filepath);

**Options:**

``--md5``
   Return MD5 for files not in depot.

``--allow-missing``
   Don't error if file is not in depot.

``--local-edit``
   Check for local edits.

``--prefix`` *path*
   Prepend *path* to pathname.

Note that ``getp4version`` is a stand-alone executable which does the same thing
as ``P4version.pm`` - except that it is called as an executable rather than
as a module.
   

Diff Scripts: ``--diff-file`` option
====================================

These scripts extract unified diffs between versions for differential coverage.

.. _p4udiff:

p4udiff
-------

Extract unified-diff between two Perforce changelists.

::

    p4udiff [options] old_cl new_cl

**Options:**

``--depot`` *path*
   Depot path prefix.

``--sandbox`` *path*
   Local sandbox path.

``--exclude`` *pattern*
   Exclude files matching pattern.

``--include`` *pattern*
   Include only files matching pattern.

``--verbose``
   Print debug messages.

.. _gitdiff:

gitdiff
-------

Extract unified-diff between two git SHAs.

::

    gitdiff [options] base_SHA current_SHA

**Options:**

``--repo`` *directory*
   Git repository directory. Default: current directory.

``--prefix`` *path*
   Leading path to strip from file pathnames.

``--exclude`` *regexp*
   Exclude files matching pattern.

``--include`` *regexp*
   Include only files matching pattern.

``--no-unchanged``
   Remove unchanged file references from diff.

``-b``, ``--blank``
   Ignore whitespace changes.

``--verbose``
   Print debug messages.

Criteria Scripts: ``--criteria-script`` option
==============================================

These scripts implement coverage criteria callbacks for pass/fail decisions.

.. _criteria:

criteria.pm
-----------

Sample criteria script that checks "UNC + LBC + UIC == 0".

::

    genhtml --criteria-script 'criteria.pm [--signoff] [--function] [--branch] [--mcdc]'

**Options:**

``--signoff``, ``--suppress``
   Exit with status 0 even if criteria not met.

``--function``
   Check function coverage.

``--branch``
   Check branch coverage.

``--mcdc``
   Check MC/DC coverage.

Note that ``criteria`` is a stand-alone executable which does the same thing
as ``criteria.pm`` - except that it is called as an executable rather than
as a module.
   

.. _threshold:

threshold.pm
------------

Check that coverage exceeds specified thresholds.

::

    genhtml --criteria-script 'threshold.pm,--line,85,--branch,70,--function,100'

**Options:**

``--line`` *percent*
   Minimum line coverage percentage.

``--branch`` *percent*
   Minimum branch coverage percentage.

``--function`` *percent*
   Minimum function coverage percentage.

``--signoff``
   Exit 0 even if thresholds not met.

Subset Selection/Code Review: ``--select-script`` option
========================================================

.. _select:

select.pm
---------

Select a subset of source code to include in the HTML report.

This is useful for code review - say, between releases or of a particular
commit or range of commits - or when you are interested in code authored or
owned by your team and do not want to look at the entire project.

::

    genhtml --select-script 'select.pm,--tla,LBC;UNC,--range,5:10'

**Options:**

``--tla`` *categories*
   Comma-separated differential categories to retain (UNC, LBC, UIC, etc.).

``--sha`` *id*
   Git SHAs to retain (comma-separated).

``--cl`` *id*
   Perforce changelists to retain (comma-separated).

``--range`` *min:max*
   Age range in days to retain.

``--owner`` *regexp*
   Regular expression to match owner names.

``--separator`` *char*
   Character to separate list arguments.


Find source files - in nontrivial build environment:  ``--resolve-script`` option
=================================================================================

.. _resolve:

In a complicated build environment - for example, to build the LLVM toolchain -
it can be difficult to tell |TOOL_NAME| how to find your source
code using only ``--build-directory``, ``--source-directory``, and
``--substitute`` options.
The ``--resolve-script`` callback can be easier to understand.



Modify appearance of displayed code:  ``--simplify-script`` option
==================================================================

.. _simplify:

simplify.pm
-----------

Simplify function names in the function detail tables - say, to use
regexps to shorten very long C++ template names.

::

    genhtml --simplify-script 'simplify.pm,--re,regexp'

**Options:**

``--file`` *pattern_file*
   File containing Perl regexps (one per line).

``--re`` *regexp*
   Perl regexp or separator-separated list of regexps.

``--separator`` *char*
   Separator character for regexp lists.

.. _unreach:


Tag unreachable coverpoints:  ``--unreach-script`` option
=========================================================

unreach.pm
----------

Identify unreachable branches and MC/DC conditions so that they do
not appear in coverage reports.

::

    genhtml --unreachable-script 'unreach.pm,--branch,--mcdc'

**Options:**

``--branch``
   Support branch filtering.

``--mcdc``
   Support MC/DC filtering.

**Comment Format:**

- Branch: ``// LCOV_UNREACHABLE_BRANCH (expressionId[,blockId])+``
- MC/DC: ``// LCOV_UNREACHABLE_MCDC (conditionId)+``


Load balancing:  ``--history-script`` option
============================================

.. _history:

history.pm
----------

Reuse profile history from prior tool execution for better load balancing
during parallel execution

::

    genhtml --history-script history.pm --profile previous_profile.json


Environment/context:  ``--context-script`` option
=================================================

.. _context:


context.pm
----------

Collect and store context data for infrastructure debugging/tracking.

::

    genhtml --context-script context.pm



Performance monitoring and optimization
=======================================

spreadsheet.py
--------------

Generate Excel spreadsheets from |TOOL_NAME| profile data for performance analysis.

::

    spreadsheet.py [--verbose] profile.json output.xlsx

Creates sheets for:

- Capture summary
- Processing times
- Chunk analysis
- Filtering statistics


Other Scripts
=============

These are additional utility scripts provided for specific workflows.

.. _analyzeInfoFiles:

analyzeInfoFiles
----------------

Check for consistency across a set of .info files for the same code base.

::

    analyzeInfoFiles [options] infoFile infoFile ...

**Arguments:**

*infoFile*
    .info file (ending in ".info") or data file containing names of .info files.
    Data file comment character is '#'.

**Options:**

``--include`` *glob*
    glob pattern to match source filenames to check.

``--exclude`` *glob*
    glob pattern to match source filenames to skip.

``--substitute`` *regexp*
    Munge source file path when reading .info files.

``--keep-going``
    Do not stop after mismatch found.

``--all``
    Print all regions (not just regions with conflicting votes).

``--drop``
    Ignore .info file if it does not contain some source file - continue to
    check consistency in the .info files which do contain the file.

``--compact``
    Compact printing of source code region.

``--sort``
    Sort by region size.

``--verbose``, ``-v``
    Be chatty.

``--help``, ``-h``
    Print usage message.

**Checks:**

- Is every source file present in every .info file?
- For every source file that is not dropped:
  - Is the version ID the same in all the .info files?
  - Do all the .info files agree about the status of every line?

.. _getp4version:

getp4version
------------

Use Perforce commands to determine the version of a file.
This is the same as the ``P4version.pm`` module described above - except
that it is called as an executable rather than a module.

::

    getp4version [--md5] [--allow-missing] filename

    getp4version --compare old_version new_version filename

**Options:**

``--md5``
    Append MD5 checksum to the P4 version string.

``--allow-missing``
    Do not error if file is not in depot.

``--compare``
    Compare two version strings.

``--help``
    Print usage message.

**Output:**

Returns version information (revision number or \"@head\") for files in the depot,
or modification time for files not in depot. If ``--md5`` is specified, includes
MD5 checksum.

.. _get_signature:

get_signature
-------------

Compute MD5 signature for a file.

::

    get_signature [--allow-missing] filename

    get_signature --compare old_version new_version filename

**Options:**

``--allow-missing``
    Do not error if file does not exist.

``--compare``
    Compare two signature strings.

``--help``
    Print usage message.

**Output:**

Returns MD5 checksum of the specified file.


AUTHOR
======

Henry Cox <henry.cox@mediatek.com>

SEE ALSO
========

:manpage:`genhtml(1)`, :manpage:`lcov(1)`, :manpage:`geninfo(1)`, :manpage:`llvm2lcov(1)`, :manpage:`perl2lcov(1)`
