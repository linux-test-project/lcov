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
visualizae the data.
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
Note that not all tools support all options.  For example, `--diff-file` and ``--annotate-script`` are supported ``genhtml`` only.

Getting Started
===============

  #. Point your environment to your installation of {ToolName} -  or install {ToolName} using ``make install``

  #. Prepare your executables:

     - C/C++: compile and link with coverage flags: ``--coverage`` or ``-fprofile-arcs -ftest-coverage``.

     - Perl, Python, *etc.* - see the other tools in this release.

  #. Run your tests

  #. Capture coverage

     - C/C++: ``lcov --capture --directory . --output-file coverage.info``

     - Other languages: see other tools in this release and/or consult your toolchain documentation.

  #. Generate HTML report: ``genhtml coverage.info --output-directory out``

  #. Read the man pages and/or the HTML documentation to discover other capabilities and options.

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
