# LCOV Documentation Configuration
# Sphinx configuration for building HTML documentation from RST sources.

import os
import re
from pathlib import Path
from datetime import date
import pdb

# Tool name - can be overridden via environment variable
#  the potentially mixed case product name
ToolName = os.environ.get('TOOL_NAME', 'LCOV')
#  the product name in upper case - used in environment variable prefixes, etc.
TOOLNAME = ToolName.upper()

# Project information
project = ToolName
copyright = f'2024-2026, {ToolName} Project'
author = f'{ToolName} Contributors'

# Build date - used in man page headers and HTML pages
# Can be overridden via: make BUILD_DATE="YYYY-MM-DD" html
build_date = os.environ.get('LCOV_BUILD_DATE', date.today().strftime('%Y-%m-%d'))

# The full version, including alpha/beta/rc tags
# Can be overridden via: make RELEASE=X.Y html
# or: sphinx-build -D release=X.Y -D version=X.Y ...
release = os.environ.get('LCOV_RELEASE', '2.5.0')
version = release  # For Sphinx, version is typically the short version

# -- General configuration ---------------------------------------------------

# Add any Sphinx extension module names here
extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.viewcode',
    'sphinx.ext.intersphinx',
]

# Date format for man pages and HTML pages
today = build_date
today_fmt = '%B %d, %Y'  # e.g., "May 19, 2026"

# Add any paths that contain templates here
templates_path = ['_templates']

# List of patterns to exclude
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']

# The suffix of source filenames.
source_suffix = '.rst'

# The master toctree document.
master_doc = 'index'

# Disable syntax highlighting - use plain fixed-width font for code blocks
highlight_language = 'none'

# Disable the smart-quotes transform.  These documents describe command line
# options and shell syntax, so the substitutions it makes are wrong more often
# than they are decorative:  '--option' becomes an en dash, and the escape
# handling drops the backslash from a literal '\'.  Sphinx already excludes the
# 'man' and 'text' builders from the transform;  this extends that to HTML.
smartquotes = False

# -- Options for HTML output -------------------------------------------------

# The theme to use for HTML and HTML Help pages.
html_theme = 'sphinx_rtd_theme'

# Theme options are theme-specific and customize the look and feel.
html_theme_options = {
    'display_version': True,
    'collapse_navigation': True,
    'sticky_navigation': True,
    'navigation_depth': 1,
}

# Show build date in HTML pages
html_last_updated_fmt = '%b %d, %Y'

# Add any paths that contain custom static files
html_static_path = ['_static']

# -- Options for manual page output ------------------------------------------
# Link external man page references to local installed man pages
# Assumes man pages are installed in ../man/ relative to HTML docs
manpages_url = 'file://../man/{page}.{section}.html'

def get_man_pages():
    """
    Generate man_pages list dynamically from RST files in man/ directory.
    
    Each entry is a tuple: (source_path, name, description, authors, section)
    """
    man_dir = Path(__file__).parent / 'man'
    man_pages = []
    
    section_pattern = re.compile(r'^:Manual section:\s*(\d+)', re.MULTILINE)
    equals_line = re.compile(r'^=+$')
    dash_line = re.compile(r'^-+$')
    
    for rst_file in sorted(man_dir.glob('*.rst')):
        content = rst_file.read_text()
        lines = content.split('\n')
        
        name = rst_file.stem
        description = f'{name} documentation'
        section = 1
        
        section_match = section_pattern.search(content)
        if section_match:
            section = int(section_match.group(1))
        
        i = 0
        while i < len(lines):
            stripped = lines[i].strip()
            if stripped.startswith('..') or not stripped:
                i += 1
            else:
                break
        
        if i < len(lines) and equals_line.match(lines[i].strip()):
            if i + 2 < len(lines):
                title = lines[i + 1].strip()
                if title and equals_line.match(lines[i + 2].strip()):
                    name = title
                    i += 3
        elif i + 1 < len(lines) and equals_line.match(lines[i + 1].strip()):
            name = lines[i].strip()
            i += 2
        
        while i < len(lines) and not lines[i].strip():
            i += 1
        
        if i < len(lines) and dash_line.match(lines[i].strip()):
            if i + 2 < len(lines):
                subtitle = lines[i + 1].strip()
                if subtitle and dash_line.match(lines[i + 2].strip()):
                    description = subtitle
        
        name_section = re.search(
            r'^NAME\s*\n([-=]+)\s*\n\s*(.+?)\s*$',
            content,
            re.MULTILINE
        )
        if name_section:
            desc_line = name_section.group(2).strip()
            if ' - ' in desc_line:
                description = desc_line.split(' - ', 1)[1].strip()
        
        if ' - ' in name:
            name = name.split(' - ')[0].strip()
        
        source = f'man/{rst_file.stem}'
        man_pages.append((source, name, description, [], section))
    
    return man_pages

man_pages = get_man_pages()

# -- Dynamic index.rst generation --------------------------------------------

def generate_index_rst(app, docname, source):
    """
    Generate index.rst content dynamically from man directory entries.
    
    This callback intercepts the index.rst read and generates:
    - The toctree with all man pages
    - The overview section with tool descriptions
    """
    if docname != 'index':
        return
    
    man_dir = Path(__file__).parent / 'man'
    
    # Get sorted list of man page names
    man_pages_list = sorted(p.stem for p in man_dir.glob('*.rst'))
    
    # Build toctree entries
    toctree_entries = '\n   '.join(f'man/{name}' for name in man_pages_list)
    
    # Get release version from config
    rel_version = app.config.release
    
    # Generate title with version
    title = f'{ToolName} Documentation ({rel_version})'
    title_underline = '=' * len(title)
    
    # Generate the full index.rst content
    content = f'''.. {ToolName} Documentation
    ===================

{title}
{title_underline}

{ToolName} is a graphical tool which collects and aggregates
coverage data from multiple sources then generates HTML reports to
visualize the data.
It supports line, function, branch and MC/DC coverage.
{ToolName} was originally written to display coverage data GCC's coverage testing tool gcov - but has been enhanced to support multiple tools and languages - including C/C++, Perl, Python, Java and SystemVerilog.

.. toctree::
   :maxdepth: 1
   :caption: Manual Pages
   :titlesonly:

   {toctree_entries}
   scripts

Callback Scripts
================

{ToolName} provides callback scripts to customize version control system integration,
coverage criteria enforcement and various other purposes:

  - **Annotate scripts**:

    - ``--annotate-script`` option
    - extract file author/date data (examples: ``gitblame.pm``, ``p4annotate.pm``)

  - **Version scripts**:

    - ``--version-script`` option
    - extract and compare file versions (examples: ``gitversion.pm``, ``batchGitVersion.pm``, ``P4version.pm``, ``get_signature``)

  - **Diff scripts**:

    - used by ``--diff-file`` option
    - generate unified source text diffs (examples:  ``gitdiff``, ``p4udiff``)

  - **Criteria scripts**:``

    - --criteria-script`` option
    - check and enforce coverage thresholds (examples: ``criteria.pm``, ``threshold.pm``)

  - **Subset/code review**:

    - ``--select-script`` option
    - generate HTML report showing only particular subset of sources (example: ``select.pm``)

  - **Unreachable code**:

    - `--unreachable-script`` option
    - tag unreachable expressions so they are not counted/do not appear in the coverage report (example: ``unreach.pm``)

  - **Modify code appearance**:

    - ``--simplify-script`` option
    - shorten very long C++ template names (example: ``simplify.pm``)

  - **Find corresponding source file** (in non-trivial build environment:

    - ``--resolve-script`` option

The callback scripts shipped with the {ToolName} release
are primarily intended only as examples of possible callback implementations.
The expectation is that users will want or need to customize the
callbacks in order
to support their specific environment and requirements.

For details, see the ``*-script`` option section in the individual tool man pages 
(``genhtml``, ``llvm2lcov``, *etc.*)
Note that not all tools support all options.  For example, ``--diff-file`` and ``--annotate-script`` are supported by ``genhtml`` only.

Getting Started
===============

  #. Point your environment to your installation of {ToolName} -  or install {ToolName} using ``make install``.

     - Note that ``sphinx-build`` is required in order to build documentation,
       but you can skip documentation building by passing passing the ``make LCOV_NO_DOC=1`` flag to your ``make`` command.

     - Similarly, you can skip building the {ToolName} XS extension by passing ``make LCOV_NO_XS=1 ...`` to your ``make`` command.

     - Note that, if you pass ``COVERAGE=1`` to your ``make`` command, then the XS implementation will be instrumented for coverage data collection. See ``.../tsts/Makefile`` for more information.

     - The XS extension is C++ and requires ``g++`` 8 or later (14 or later
       recommended - and required for ``COVERAGE=1`` to collect MC/DC data).
       If the first ``g++`` on your ``PATH`` is older than that, select the
       compiler explicitly:

       - ``make LCOV_CXX=/path/to/g++ ...`` names the compiler directly
         (``CXX`` is honored too;  ``LCOV_CXX`` wins).

       If no usable compiler is found, the build will fail.
       {ToolName} loads the extension
       when present and *silently* uses its pure-Perl implementation when it is
       not, so a failed extension build does not corrupt results - it only
       makes execution slower, with nothing to indicate why.  Check
       which implementation is in use with::

           perl -I$LCOV_HOME/lib -e 'require lcovutil; print $lcovutil::XS_LOADED ? "XS\\n" : "pure Perl\\n"'

       Setting ``LCOV_PURE_PERL=1`` forces the pure-Perl implementation at run
       time even when the extension is available.

  #. Prepare your executables:

     - C/C++: compile and link with coverage flags: ``--coverage`` or ``-fprofile-arcs -ftest-coverage``.

     - Perl, Python, *etc.* - see the other tools in this release.

  #. Run your tests

  #. Capture coverage

     - C/C++: ``lcov --capture --directory . --output-file coverage.info``

     - Other languages: see other tools in this release and/or consult your toolchain documentation.

  #. Generate HTML report: ``genhtml coverage.info --output-directory out``

  #. Read the man pages and/or the HTML documentation to discover other capabilities and options.

Windows path names
==================

A path can be written in Windows style - with a drive letter, and with either
forward or backslash separator, or a mixture of the two - even when the tool is
run by a Perl or a Python (*e.g.*, on Cygwin, MSYS, or git-bash) which only
understands Unix-style paths (forward slash, no drive).  Such a perl cannot open
``D:\\my\\local\\tools\\lcov\\bin\\genhtml`` at all - but such a path may be
written on the command line by a Windows caller, or come from an environment
variable - so {ToolName} has to handle them all.

The drives are mounted in such an installation, so the same file has a name
that perl does understand, and the tools translate Windows names to that format:
forward slashes throughout, and the mount point of the drive in front.
``D:`` is ``/d`` under MSYS and git-bash and ``/cygdrive/d`` under Cygwin, each
configurable in the installation's own ``fstab``.  So, with {ToolName} installed in
``D:\\my\\local\\tools\\lcov`` and JaCoCo on the ``Z:`` drive -

========================================  ========================================
Written as                                Used as
========================================  ========================================
``D:\\my\\local\\tools\\lcov\\bin\\genhtml``    ``/d/my/local/tools/lcov/bin/genhtml``
``D:/my/local/tools/lcov/bin/genhtml``    the same
``D:\\my\\local/tools\\lcov/bin\\genhtml``    the same
``Z:\\jacoco\\lib\\jacococli.jar``           ``/z/jacoco/lib/jacococli.jar``
``lib\\jacococli.jar``                     ``lib/jacococli.jar``
``\\\\build01\\share\\jacoco\\jacococli.jar``  ``//build01/share/jacoco/jacococli.jar``
``Q:\\jacoco\\lib\\jacococli.jar``           ``Q:/jacoco/lib/jacococli.jar``
========================================  ========================================

The last three rows are the paths which name no mounted drive.  A backslash is
the Windows separator wherever it appears, so turning the separators around is
all a relative path needs, and it is what makes a UNC name usable as well -
that is ``//host/share/...`` on these perls.  ``Q:`` in the last row is a drive
which this installation has not mounted: there is no name to translate it to,
so it is left as it stands and the drive you named is what the complaint about
it names.

Note that only the two usual mount points are checked, so a drive which your
installation's ``fstab`` mounts somewhere else - ``/mnt/d``, say - has to be
named the way that perl names it.  And a drive-relative name,
``D:jacococli.jar``, is left alone: there is no per-drive current directory to
resolve it against.

A native Windows perl - one whose ``$^O`` is ``MSWin32`` - understands a
Windows path itself: it opens one, it makes one absolute, and it splits one
into a directory and a file name.  Nothing is translated for such a perl, in
either direction, and a Windows path is what it is handed and what it hands on.
Nothing is translated on a Unix host either, where a drive letter names
nothing: what you write there is what is used.

``py2lcov`` and ``xml2lcov`` are Python rather than Perl, and do the same
thing, for the same reason: the ``os.path`` of a Cygwin or MSYS python is
``posixpath``, which does not know a drive letter either.  The same table above
describes what they do with a name, and a native Windows python - one whose
``sys.platform`` is ``win32`` - is left alone in the same way as a native
Windows perl.

Example
=======

The {ToolName} source distribution includes a complete working example in
directory ``${TOOLNAME}_HOME/share/lcov/example`` (or in the ``example`` subdirectory,
if you are using an lcov source version).

The example demonstrates:

- Compiling C/C++ code with coverage instrumentation
- Running tests and capturing coverage data
- Generating HTML coverage reports
- Using differential coverage analysis
- Using coverage and part of your code review process


.. include:: ../example/README.rst


Glossary
========

Terms of art which the man pages use without further explanation.
Where a term has a precise meaning in a compiler or a language standard,
the definition below is the one {ToolName} uses - which is sometimes
narrower than general usage.

.. glossary::
   :sorted:

   alias
      One of several function names which the coverage data reports at the
      same source file and line, and which {ToolName} treats as
      names of one function:  most often the instantiations of a C++
      template, or the several mangled names which a compiler emits for
      one source function.  The shortest name of the group is used as its
      leader;  see the ``--merge-aliases`` and ``--suppress-aliases``
      options of ``genhtml``.  In a tracefile, each alias is an ``FNA``
      record, and all the aliases of a function share the index of the
      ``FNL`` record which declares it.

   anchor
   leader
      The line of a multi-line statement which holds the statement's
      coverage data when ``merge_continuation_lines`` is enabled:  the
      line its :term:`continuation line` coverpoints are merged into, and
      where branch and MC/DC data written on its other lines is counted.
      Normally the statement's first line.  See *Statement merging* in
      :manpage:`geninfo(1)`.


   baseline
      The earlier coverage report which a :term:`differential coverage`
      report compares the current one against;  see the ``--baseline-file``
      option of ``genhtml``.

   branch coverage
      Whether each outcome of each conditional branch in the code was
      taken at least once.  Note that a single source line may contain
      several branches, and also that the compiler sometimes generates
      branches which do not correspond to code written by the programmer
      (exception cleanup, for example).
      Branch filters are used to suppress these.

   callee
      The function which a call goes to - the *destination* of the
      :term:`callgraph` edge.  See :term:`call site`.

   caller
      The function which contains a :term:`call site` - the *source* of the
      :term:`callgraph` edge.

   callgraph
      A directed graph of the calls in your code:  a node for each
      function, and an edge for each call, drawn from the :term:`caller`
      to the :term:`callee`.  An edge is a particular caller/callee pair
      at a particular :term:`call site`, so two calls to the same callee
      from two places in the same caller are two distinct edges.

      A {ToolName} report describes only part of the whole graph:  the
      part inside the :term:`callgraph boundary`.

   callgraph boundary
      The edge of the part of the :term:`callgraph` a {ToolName} report
      describes.  A function is outside the boundary either because it is
      in code which was not instrumented - third party library code, the
      runtime, a :term:`translation unit` which was never captured - or
      because the user deliberately put it outside, *this being the
      library API I care about, and everything outside it external*.

      Either the source, the destination, or both ends of an edge may be
      outside the boundary:  an edge with both ends outside simply does
      not appear in the report.
      An edge whose source (caller) is outside the boundary is recorded
      as the *has external caller* property of its destination node
      (which is within the boundary).  Similarly, an edge whose
      destination (callee) is outside the boundary is recorded as the
      *has external callee* property of its source node (which is within
      the boundary).  These properties say only that there is at least one
      external source or destination (no exact count).

      When data is available, the tools keep track of the number of times
      a particular destination within the boundary is called from a
      source outside. Additionally, 
      whether a particular boundary-crossing edge has been executed
      or not can often be deduced from line and branch coverage data
      of the corresponding statement in the coverage report - see the
      discussion in :manpage:`genhtml(1)` and :manpage:`geninfo(1)`.

   callgraph coverage
      Data about which functions called which other functions, and from
      where:  for each function, the call sites it was called from and
      the number of times each of those calls was executed.  Enabled with
      ``--callgraph-coverage``;  see :manpage:`geninfo(1)`.  Supported
      only by certain compilers.

   callgraph info
      The calls which the compiler itself recorded for a
      :term:`translation unit`:  GCC's ``-fcallgraph-info``, written beside
      the ``.gcno`` as a ``.ci`` file.  It names the :term:`callee` of each
      :term:`call site` and the file, line and column the call is written
      at - none of which the execution counts say - and it says which of
      the unit's symbols have :term:`external linkage`.  The GCC callgraph
      data holds only the compile-time structure of the callgraph - not
      runtime execution counts of the particular edges.

   pairing
      Matching each call the :term:`callgraph info` lists with the
      execution count ``gcov`` reports for it, so that a
      :term:`call site` has both a :term:`callee` and a count.  The two
      halves of :term:`callgraph coverage` come from different files which
      have to be combined to be useful;  pairing is by location, at line
      granularity, because the two input files do not necessarily record
      the same column.

      A call which cannot be matched is *unpaired*.  There are three
      ways this can happen:

      -  the compiler deleted the arc which ``gcov`` uses to count the call -
         the call was inlined, or ``-fipa-pure-const`` proved the callee
         ``nothrow`` and removed its exceptional edge - so the callgraph
         info lists a call for which there is no count;

      -  the compiler generated a call the source does not make - a copy, a
         conversion, an exception edge:  ``gcov`` counts it and the
         callgraph info has no edge for it, so there is no callee to record
         it under;

      -  ``gcov`` attributed the call to no function, and the callgraph info
         does not attribute its line to exactly one either.  This is typically
         caused by a fragment which is included into more than one function
         body (*e.g.*, via a ``#include`` within a function body, so that
         the code is included in more than one place - **don't do that!**).

      One unpaired call makes every call on its line unpaired, since
      pairing the counts which do remain with some of the calls on the line
      would put a count on the wrong callee.  An unpaired call has no count
      (recorded as a ``-`` count of an ``FNC`` record).
      The record is retained or dropped depending on the
      ``--callgraph-partial-data`` flag (default is to drop).
      A mismatch is reported as an
      ``inconsistent`` error, once per :term:`caller`.

      A call to a callee declared ``pure`` or ``const`` is not a mismatch:
      ``gcov`` never counts such a call - the compiler may make it once or
      not at all and emits no arc for it - so the call is dropped when the
      declaration the compiler pointed to says so.  See
      :manpage:`geninfo(1)`.

   call site
      A particular location in the code at which one function calls another -
      identified by source file, line, column, and, when the same line
      and column contain more than one call, an ordinal which
      distinguishes them.  A call site belongs to the :term:`caller` and
      names the :term:`callee`;  its count is the number of times that
      particular call was executed by your testcases.

   comdat
      An object file section which the compiler may emit in more than one
      object file and of which the linker then keeps a single copy.  This
      is how inline functions, template instantiations, and other
      entities whose definition may legally appear in several translation
      units are emitted.  Such a symbol is not ``static``, but because
      each translation unit that uses it contains its own definition, it
      can look file-local in the coverage data.

   continuation line
      A line of a statement which spans several lines, other than the
      statement's first line - the later lines of an expression, a
      condition or an argument list split across lines.  With
      ``merge_continuation_lines``, the line coverpoint of a continuation
      line is merged into the statement's :term:`anchor` when the hit
      counts allow.  See *Line merging* in :manpage:`geninfo(1)`.

   compilation unit
   CU
      The unit at which the compiler records debug information for the
      code it generated (a DWARF ``DW_TAG_compile_unit``).  For C and C++
      there is normally one compilation unit per
      :term:`translation unit`, but a single object file can contain
      several - with link-time optimization, for example - so the two
      terms are not interchangeable.

   condition
      One of the operands of a :term:`decision`:  a subexpression whose
      own value contributes to the value of the decision.  In
      ``if (a && (b || c))`` the conditions are ``a``, ``b`` and ``c``.

   decision
      A boolean expression which controls the flow of the program - the
      expression of an ``if``, a loop condition, a ternary, and so on.
      Also called an *expression* in the MC/DC parts of this
      documentation.

   demangle
      To turn the encoded symbol name which the compiler emitted
      (``_ZN3Foo3barEi``) back into the name which the programmer wrote
      (``Foo::bar(int)``).  See the ``--demangle-cpp`` option.

   differential coverage
      A report which compares the current coverage data against a
      :term:`baseline`, and which classifies lines, branches and
      functions by whether they are new or changed and by whether their
      coverage changed:  the ``UNC``, ``LBC``, ``UIC``, ``UBC``, ``GBC``,
      ``GIC``, ``GNC``, ``CBC``, ``EUB`` and ``ECB`` categories described
      in :manpage:`genhtml(1)`.

   external linkage
      The property of a symbol which the linker can resolve references to
      from other translation units - the opposite of a ``static``
      function, which is file-local.  In callgraph coverage this matters
      because a function with external linkage can be called from code
      which is not part of the report.

   filter
      A rule which drops coverage points that the compiler generated but
      which correspond to something the user did not write - *e.g.*,
      exception handling code - or does not care about - *e.g.*, "somebody
      else's module".  See
      the ``--filter`` option of ``geninfo`` and ``genhtml``.

   TLA
      Three letter acronym:  the code which a
      :term:`differential coverage` report attaches to each line, branch
      or function - ``UNC``, ``GNC``, ``CBC``, and the rest - encoding
      whether the code is new or changed and whether its coverage is changed
      between the baseline and now.  The full list and how they are colorized
      in the HTML report are in :manpage:`genhtml(1)`.

   found
   hit
      The two numbers behind every coverage rate:  *found* is the number
      of instrumented items of that kind (lines, functions, branches, MC/DC
      senses) and *hit* is how many of them were exercised at least once.
      The rate is *hit* / *found*.

   independence pair
      A pair of evaluations of a :term:`decision` which differ in the
      value of one :term:`condition` and in the value of the decision, and
      which therefore demonstrate that that condition can independently
      affect the outcome.  This is what :term:`MC/DC` requires of every
      condition.

   instrumentation
      The counters which the compiler (or interpreter, or simulator) adds
      to the program so that it records what it executed.  For GCC and
      LLVM this is what ``--coverage`` turns on.

   MC/DC
      Modified condition/decision coverage:  a metric which requires that
      every :term:`condition` in every :term:`decision` be shown to
      independently affect the value of that decision - see
      :term:`independence pair`.  It is stronger than branch coverage,
      which asks only that the decision itself have gone both ways.
      Enabled with ``--mcdc-coverage``;  the details of what the compilers
      report, and how {ToolName} displays it, are in
      :manpage:`genhtml(1)`.

   section
      The part of a tracefile which holds the data for one source file:
      everything from that file's ``SF`` record to the following
      ``end_of_record``.

   segment
      A part of a multi-line statement which is treated as a separate
      statement on
      its own:  when the line coverpoints of a statement cannot all be
      merged into its :term:`anchor` - because their hit counts disagree,
      or a line is the start line of a function - the statement is
      partitioned, and each line coverpoint which is kept starts a segment
      which runs to the line before the next.  Each segment has its own
      :term:`statement span`.

   sensitized
      Said of a :term:`condition` at a particular evaluation of its
      :term:`decision`:  the condition was evaluated, and had its value
      been the other one, the value of the decision would have been
      different.  A condition which was evaluated but whose value
      could not have changed the outcome - because a later operand of an
      ``||`` was already true, say - was not sensitized.

   statement span
   span
      The lines from the first to the last line of the statement - or the
      :term:`segment` - which a line coverpoint stands for, comment and
      blank lines inside it included.  Recorded, with
      ``merge_continuation_lines``, as the optional *<end>* field of the
      ``DA`` record of the coverpoint, which is on the statement's first
      line.  ``genhtml`` uses it to treat the statement as a whole:  a
      change to any line of the span makes the statement's coverpoints
      new code, and the statement's date and owner are those of the most
      recent change to any line of the span.  See *Statement spans* in
      :manpage:`geninfo(1)` and :manpage:`genhtml(1)`.

   testcase
      A named body of coverage data within a tracefile:  the name given
      by ``lcov --test-name``, under which the data of one test run is
      filed.  Merging tracefiles keeps the per-testcase data, so a report
      can show which tests reached a given line.

   tracefile
      The plain text file - conventionally ``*.info`` - in which
      {ToolName} stores coverage data.  It is the input and the output of
      ``lcov``, the output of ``geninfo`` and of the ``*2lcov``
      translators, and the input of ``genhtml``.  The record format is
      documented in :manpage:`geninfo(1)`.

   translation unit
   TU
      One source file together with everything the preprocessor pulled
      into it - that is, the text which the compiler actually compiles.
      It is the scope in which ``static`` means file-local, and the unit
      which a single compiler invocation turns into a single object file.
      Compare :term:`compilation unit`.


AUTHOR
======

Peter Oberparleiter <Peter.Oberparleiter@de.ibm.com>

  Original LCOV implementation

Henry Cox <henry.cox@mediatek.com>

  Differential coverage, age/author binning, *etc.*.

LCOV Community

  Ideas, suggestions, fixes...lots of help

License
=======

{ToolName} is licensed under the GNU General Public License. See the LICENSE file 
for details.
'''
    
    source[0] = content

# -- Options for intersphinx extension ---------------------------------------

intersphinx_mapping = {
    'python': ('https://docs.python.org/3/', None),
}

# Suppress warnings about title underline/overline length mismatches
# These occur when |TOOL_NAME| substitution changes title length
suppress_warnings = [
    'misc.highlight_overline',
    'misc.highlight_underline',
]

# -- Substitutions for all RST files -----------------------------------------
# Define substitutions that can be used as |TOOL_NAME| in all .rst files
rst_epilog = f"""
.. |TOOL_NAME| replace:: {TOOLNAME}
.. |ToolName| replace:: {ToolName}
"""

def setup(app):
    """Sphinx extension setup."""
    app.connect('source-read', generate_index_rst)

# -- Options for intersphinx extension ---------------------------------------

intersphinx_mapping = {
    'python': ('https://docs.python.org/3/', None),
}
