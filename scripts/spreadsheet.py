#!/usr/bin/env python3

import xlsxwriter
import argparse
import json
import pdb
import datetime
import os.path
import os
import sys

from xlsxwriter.utility import xl_rowcol_to_cell
from collections import namedtuple

devMinThreshold = 1.5
devMaxThreshold = 2.0
thresholdPercent = 0.15

# What each metric on the other sheets means:  the 'glossary' sheet is written
#   from this, as (section, tool, ((term, keys, meaning), ...)).
# One section per tool, because the same profile key does not mean the same
#   thing in every tool:  'parse' is one gcov file in a geninfo profile, one
#   '.info' file in an lcov one, and one HTML page in an html2lcov one.  A term
#   which does mean the same thing everywhere is in the common section, whose
#   tool is None, and is not repeated per tool.
# 'keys' names the profile data which puts the term on a sheet:  an entry is
#   written only if some sheet in this workbook shows at least one of them - see
#   noteMetrics - so the glossary describes the workbook in hand rather than
#   every metric the tools can produce.  An empty 'keys' means the term is not a
#   metric at all but part of every sheet's layout.
# Every time is in seconds and every memory figure in MB, so the entries do not
#   repeat the unit;  the section lead-in says it once.
GLOSSARY = (
    ('reading a sheet', None, (
        ('config', (),
         "the run being profiled:  the command line, host, tool, version, the"
         " parallelism it was allowed ('maxParallel'), and 'XS enabled' - 1 if"
         " the C++ extension loaded, 0 if the run used pure Perl instead."),
        ('sections', (),
         "each sheet is a stack of tables:  a title line - a brief label in"
         " column A, which links to the entry here for whatever the table"
         " reports, and a sentence beside it saying what one row of the table"
         " is - then a title row naming the table in column A and its columns,"
         " each of which links to its entry here, then four statistics rows"
         " over the data, then one row per element (a source file, a forked"
         " job, ..) with one column per metric."),
        ('table index', (),
         "a sheet whose tables do not fit on the screen together leads with the"
         " label and explanation of each of them, the label linking to the"
         " table."),
        ('total / max / avg / stddev', (),
         "the statistics rows of a table, computed down each column over the"
         " element rows below them.  A column whose values are peaks rather"
         " than durations ('peakVM', 'peakRSS') has no total:  summing the peak"
         " memory of jobs which ran at the same time means nothing, so read the"
         " 'max' row instead."),
        ('yellow / red / green', (),
         "an element which differs from the average of its column by more than"
         " a threshold number of standard deviations - slower (yellow, then"
         " red) or faster (green).  The thresholds are on the summary sheet and"
         " can be changed with '--low', '--high' and '--threshold'."),
        ('capture_summary', ('capture_summary',),
         "one row per input profile, so several capture runs can be compared"
         " directly;  written only when more than one profile is given.  Each"
         " cell references the corresponding capture sheet, and the average and"
         " standard deviation at the top are taken over the runs."),
    )),
    ('common metrics - every tool (seconds, MB)', None, (
        ('total', ('total',),
         "elapsed wall-clock time of the whole run.  Older genhtml profiles"
         " call this 'overall'."),
        ('peakVM / peakRSS', ('peakVM', 'peakRSS'),
         "peak virtual size and peak resident set, in MB.  The 'peak mem' row"
         " under 'total' is the largest seen anywhere in the run - the parent"
         " or any worker - and not their sum;  the same two names in a per-job"
         " table are that one job's peaks."),
        ('parallel', ('parallel',),
         "the concurrency actually achieved:  the sum of the workers' own"
         " elapsed times over the elapsed time of the run.  Compare it against"
         " 'maxParallel' - a much smaller number means the phase was waiting,"
         " not computing."),
        ('maxParallel', ('maxParallel',),
         "the worker count the run was allowed ('--parallel'), from the config"
         " block.  What 'parallel' is measured against."),
        ('undump', ('undump',),
         "time the parent spent deserializing one worker's result:  reading the"
         " temporary file the worker wrote and turning it back into coverage"
         " data objects."),
        ('merge', ('merge',),
         "time the parent spent folding one worker's result into its own"
         " running total, from the point the worker was reaped.  It therefore"
         " includes that worker's 'undump'."),
        ('queue', ('queue',),
         "time a finished worker's result sat waiting for the parent to get to"
         " it.  Time lost to the parent being busy, so it bounds what more"
         " workers could buy."),
        ('child', ('child',),
         "elapsed time inside one worker, from the top of the forked process to"
         " just before it serializes its result.  The productive part of a"
         " worker's life."),
        ('filter', ('filter',),
         "time spent applying the coverage filters (see '--filter').  On its own"
         " line, the whole job:  a step of its own, after the data was captured,"
         " or read and merged.  In a per-job table, that one job's share - an"
         " 'lcov' run which split its read has no separate step, because each"
         " reader filters its own chunk as it reads it, so the number appears"
         " there as a column of the 'chunks' table and is a part of that chunk's"
         " 'total'."),
        ('filt_chunk / filt_queue / filt_child / filt_proc / filt_undump /'
         ' filt_merge', ('filt_chunk', 'filt_queue', 'filt_child', 'filt_proc',
          'filt_undump', 'filt_merge'),
         "the same fork/join breakdown as the per-job keys above, for the"
         " workers which apply the filters:  total cost to the parent, wait"
         " before merging, time in the worker, time in the worker's processing"
         " routine, deserialize, and merge.  An 'lcov' sheet reports these in"
         " its 'filter' table;  a 'geninfo' sheet shows them only with"
         " '--show-filter'."),
        ('derive_end', ('derive_end',),
         "time spent computing function end lines which the input did not"
         " state, per source file.  See 'derive_function_end_line' in"
         " lcovrc(5)."),
        ('version', ('version',),
         "time in the '--version-script' callback for one source file."),
        ('resolve', ('resolve',),
         "time in the '--resolve-script' callback for one source file path."),
        ('check_consistency', ('check_consistency',),
         "time spent checking one source file's data for self-consistency (line"
         " and function coverpoints which contradict each other).  See"
         " 'check_data_consistency' in lcovrc(5)."),
    )),
    ('geninfo metrics - capture', 'geninfo', (
        ('find', ('find',),
         "time to walk one directory looking for '.gcda'/'.gcno' files."),
        ('nFiles / nChunks / chunkSize', ('nFiles', 'nChunks', 'chunkSize', 'interval'),
         "how the data files found were divided up:  the number of files, the"
         " number of batches they were split into, and the number of files per"
         " batch.  'interval' is the progress-report interval."),
        ('order', ('order',),
         "the position of this data file in the processing order - not a time."
         " Read it against 'file' to see whether the expensive files were"
         " scheduled early, which is what determines the length of the tail."),
        ('file', ('file',),
         "total time to process one '.gcda' file:  the sum of 'exec', 'parse'"
         " and 'append' for it."),
        ('exec', ('exec',),
         "time spent running 'gcov' on one data file - an external process, so"
         " this is the part of a capture lcov does not control."),
        ('parse', ('parse',),
         "time to read the data 'gcov' produced for one file and turn it into"
         " coverage data.  With '-v', 'read' and 'translate' break this into"
         " the time to read the text and the time to interpret it."),
        ('append', ('append',),
         "time to merge one file's coverage data into the worker's running"
         " total."),
        ('work', ('work',),
         "productive time for one capture chunk:  processing its data files"
         " plus merging its result into the parent.  What 'chunk' would cost if"
         " nothing were waiting."),
        ('chunk', ('chunk',),
         "everything one capture chunk cost the parent, from fork() to the"
         " cleanup after its result was merged."),
        ('process', ('process',),
         "time the worker spent in the routine which processes its chunk's"
         " files - 'child' less the worker's own setup and teardown."),
        ('write', ('write',),
         "whole-job time spent writing the output '.info' file."),
        ('history', ('history',),
         "whole-job time spent in the '--history-script' callback, which is"
         " what makes the next run's scheduling predictions exact."),
    )),
    ('genhtml metrics - report', 'genhtml', (
        ('segment', ('segment',),
         "everything one forked report job cost the parent, from fork() to the"
         " end of the merge of its result."),
        ('nJobs', ('nJobs',),
         "the number of source files this report job was given - not a time."
         " Read it against 'segment' to see whether the work was evenly"
         " divided."),
        ('startDelay', ('startDelay',),
         "time between the parent deciding to fork this job and the job"
         " starting work."),
        ('mergeDelay', ('mergeDelay',),
         "time between this job finishing and the parent starting to merge its"
         " result."),
        ('merge_segment', ('merge_segment',),
         "time the parent spent merging one report job's result."),
        ('file', ('file',),
         "total time to produce the report for one source file."),
        ('source', ('source',),
         "time to read one source file."),
        ('load', ('load',),
         "time to load one source file's content when there is no annotation"
         " callback to get it from."),
        ('synth', ('synth',),
         "time spent synthesizing content for a source file which could not be"
         " found."),
        ('annotate', ('annotate',),
         "time in the '--annotate-script' callback for one source file - the"
         " per-line author/date data."),
        ('check_version', ('check_version',),
         "time in the '--version-script' callback for one source file."),
        ('categorize', ('categorize',),
         "time to bin one file's lines by owner and date and to assign the"
         " differential-coverage categories."),
        ('html', ('html',),
         "time to write one source file's HTML page."),
        ('criteria', ('criteria',),
         "time in the '--criteria-script' callback, which decides whether the"
         " coverage criteria are met."),
        ('parse_current / parse_baseline', ('parse_current', 'parse_baseline'),
         "time to read the current and the baseline '.info' file."),
        ('parse_source / parse_diff', ('parse_source', 'parse_diff'),
         "time to read the source files and to read the '--diff-file' patch."),
        ('emit', ('emit',),
         "time to write the report:  the pages, the directory indexes and the"
         " top-level index."),
    )),
    ('lcov metrics - aggregate, extract, remove', 'lcov', (
        ('segments', ('segments',),
         "the number of forked jobs the input files were divided into - one job"
         " per input file, or several files per job.  The 'segments' table"
         " reports each one.  A run divides its work this way or into 'chunks',"
         " never both."),
        ('chunks', ('chunks',),
         "the number of pieces the inputs were split into for reading, from the"
         " config block.  The 'chunks' table reports each one, in the same"
         " shape the 'segments' table has:  the two are alternatives, since a"
         " reader filters its own piece and so leaves the parent nothing to"
         " divide into segments.  That is also why a 'chunks' row reports what"
         " reading, merging and filtering its piece cost - 'parse', 'append' and"
         " 'filter' - where a 'segments' row does not:  a segment job is handed"
         " whole input files, so what reading one of them cost is reported"
         " against that file, in the 'info' table."),
        ('scan', ('scan',),
         "time spent pre-scanning one '.info' file for its 'end_of_record'"
         " boundaries, which is what makes splitting the read across several"
         " readers possible.  The scan is what the decision to split is made"
         " from, so it is there even when the answer was not to split - but"
         " only when the run could have split at all;  see"
         " 'parallel_parse_min_lines' in lcovrc(5)."),
        ('parse', ('parse',),
         "time spent reading '.info' data.  In the 'info' table, one input file;"
         " in the 'chunks' table, the piece of the inputs one reader read.  The"
         " two are alternatives:  a chunk holds only a part of each input it"
         " names, and the chunks holding the rest of it read at the same time, so"
         " a split read has no per-input read time to report - only a per-chunk"
         " one, which is a part of that chunk's 'total'."),
        ('append', ('append',),
         "time to merge what was read into the running total:  per input file in"
         " the 'info' table, and per reader - into that reader's own total - in"
         " the 'chunks' table.  A split read has no separate merge of its own"
         " afterwards;  the parent merges each chunk as it arrives, and what that"
         " costs is the 'merge' column of the same table."),
    )),
    ('html2lcov metrics - scrape an HTML report', 'html2lcov', (
        ('aggregate', ('aggregate',),
         "time to merge the saved '.info' files into the scraped data."),
        ('source', ('source',),
         "time to scrape one HTML source page."),
        ('diff', ('diff',),
         "time to diff one scraped file against the current source."),
        ('parse', ('parse',),
         "time to read one saved '.info' file."),
        ('append', ('append',),
         "time to merge one saved '.info' file into the total."),
    )),
)

# The descriptive title of each sub-table, as (label, explanation, glossary
#   key).  It goes on the row immediately above the table's own title row:  the
#   brief label in column A, naming the table in words rather than by the terse
#   section name its title row carries, and the explanation beside it in column
#   B, saying what one row of the table is.  Splitting the two keeps the label
#   short enough to scan down - the same label is what this sheet's index of
#   tables shows - while leaving room for a sentence a reader who did not write
#   the tool actually needs.
# The glossary key is what the label links to, so that the label is a way in to
#   the explanation of the thing the table reports;  None for a table whose
#   subject the glossary has no entry for.
# Keyed by (tool, section name):  the same name does not mean the same thing in
#   two tools, and the two ways an 'lcov' run can divide its work are reported
#   by the same table code under different names.  A table which is not here -
#   the whole-run 'peak mem' block, which is one row rather than a table of
#   elements - gets no descriptive title.
SECTION_TITLES = {
    ('lcov', 'segments'): (
        "aggregation jobs",
        "the input '.info' files divided between forked jobs, one row per job",
        'segments'),
    ('lcov', 'chunks'): (
        "read jobs",
        "one '.info' file divided at record boundaries between forked readers,"
        " one row per reader",
        'chunks'),
    ('lcov', 'info'): (
        "'.info' processing",
        "one row per input file",
        None),
    ('lcov', 'filter'): (
        "trace filter",
        "the merged data divided between forked filter workers, one row per"
        " worker",
        'filter'),
    ('lcov', 'source'): (
        "source files",
        "one row per source file the inputs name",
        None),
    ('geninfo', 'chunks'): (
        "capture jobs",
        "the GCDA/GCNO files divided between forked jobs, one row per job",
        'chunk'),
    ('geninfo', 'files'): (
        "GCDA/GCNO processing",
        "one row per data file",
        'file'),
    ('geninfo', 'filter'): (
        "trace filter",
        "the captured data divided between forked jobs, one row per job",
        'filter'),
    ('genhtml', 'segments'): (
        "report jobs",
        "the source files divided between forked jobs, one row per job",
        'segment'),
    ('genhtml', None): (
        "HTML generation",
        "one row per source file and directory of the report",
        'file'),
    ('html2lcov', 'source'): (
        "HTML page scraping",
        "one row per source page of the report",
        'source'),
    ('html2lcov', 'diff'): (
        "source comparison",
        "one row per file diffed against the current source",
        'diff'),
    ('html2lcov', 'info'): (
        "'.info' processing",
        "one row per saved input file",
        'parse'),
}

# How wide to make column A of a data sheet.  A label in column A has a
#   non-empty column B beside it - that is the point of the split - so, unlike
#   the sentence in B, it cannot spill into its neighbour and is simply clipped
#   at the column width.  The default width holds about 8 characters, which
#   would cut 'GCDA/GCNO processing' down to 'GCDA/GCN'.  Derive the width from
#   the labels themselves rather than writing a number here, so that a label
#   added above cannot silently be truncated;  the two extra characters are the
#   padding Excel leaves at each edge of a cell.
sectionLabelWidth = max(len(t[0]) for t in SECTION_TITLES.values()) + 2

# The profile keys the sheet a tool with no layout of its own gets can write:
#   the first group as a labelled row of one number, the second as a flat
#   two-column list of one number per item.  Which group a key is in says what
#   the key means and so which shape to look for first;  it does not decide how
#   the value in hand is written, since the same key has either shape depending
#   on how the run was invoked - see the fall-through at the end of the file loop.
genericScalarKeys = ('parse_source', 'parse_diff', 'emit', 'parse_current',
                     'parse_baseline')
genericTableKeys = ('file', 'dir', 'load', 'synth', 'check_version', 'annotate',
                    'parse', 'append', 'segment', 'undump', 'merge', 'gen_info',
                    'data', 'graph', 'find')

class GenerateSpreadsheet(object):

    def __init__(self, excelFile, files, args):

        s = xlsxwriter.Workbook(excelFile)

        # keep a list of sheets so we can insert a summary..
        geninfoSheets = []
        summarySheet = s.add_worksheet("capture_summary") if 1 < len(files) else None
        # ..and what the metrics on the sheets mean, immediately to the right of
        #   the summary if there is one (sheets appear in creation order), so
        #   that a reader meets the summary and then its glossary before the
        #   per-profile detail.  Filled in at the end - it does not depend on
        #   the data.
        glossarySheet = s.add_worksheet("glossary")

        # order:  order of processing
        # file: time to process one GCDA file
        # parse:  time to generate and read gcov data
        # exec: time to execute gcov
        # append: to merge file info into parent
        geninfoKeys = ['order', 'file', 'parse', 'exec', 'append']

        # peakVM/peakRSS: this job's peak virtual size and peak resident set,
        #   in MB - not a time, so these go last in any list of per-job keys
        memoryKeys = ('peakVM', 'peakRSS')

        # work: productive time: process_one_chunk + merge chunk
        # chunk: everything from fork() to end of filesystem cleanup after child merge
        # child: time from entering child process to immediately before serialize
        # process: time to call process_one_chunk
        # undump:  time to deserialize chunk data into master
        # queue: time between child finish and start of merge in parent
        # merge: time to merge returned chunk info
        geninfoChunkKeys = ('work', *memoryKeys, 'chunk', 'queue', 'child',
                            'process', 'undump', 'merge')

        # the scalar statistics of a capture:  one number for the whole job,
        #   as opposed to one per chunk or per file.  In the order the summary
        #   table presents them:
        #     total             elapsed wall-clock time of the capture
        #     parallel          observed parallelism - productive time over
        #                       elapsed time (a formula, not profile data)
        #     maxParallel       the parallelism the run was allowed, from the
        #                       config block:  what 'parallel' is measured
        #                       against
        #     peakVM/peakRSS    peak virtual size and peak resident set of the
        #                       run, in MB:  the largest seen in the parent or
        #                       any worker - profile key 'memoryPeak'
        #     filter/write/history
        #                       the remaining whole-job phase times
        #   Unlike the per-job key lists above, the memory keys are not last
        #   here:  'total', 'parallel' and the two peaks are the headline
        #   numbers of a run and belong together, while 'filter'/'write'/
        #   'history' are sub-phase times.
        geninfoSpecialKeys = ('total', *memoryKeys, 'parallel', 'maxParallel',
                              'filter', 'write', 'history')

        # of the above, the ones the geninfo branch writes for itself.  'total'
        #   and the memory keys are on the sheet already - every tool gets
        #   them - and 'parallel' is a formula which cannot be written until
        #   the chunk table's location is known.
        geninfoScalarKeys = ('parallel', 'filter', 'write', 'history')

        # scalar statistics which are counts rather than times or sizes, so
        #   they read as '32' in the summary table and not '32.00'
        summaryIntKeys = ('maxParallel',)

        # keys related to filtering
        filterKeys = ('filt_chunk', 'filt_queue',  'filt_child', 'filt_proc', 'filt_undump', 'filt_merge', 'derive_end')

        # the same per-worker breakdown, as the 'lcov' filter table reports it:
        #   one row per forked filter worker, and its peak memory last, as in
        #   every other per-job table here.  'derive_end' is not in it - that is
        #   per source file, not per worker - and the memory columns are not in
        #   the geninfo list above because the two tools' filter workers share
        #   the numeric id space of their capture chunks, so the memory of one
        #   cannot be flattened into a table keyed the same way as the other.
        filterJobKeys = ('filt_chunk', 'filt_queue', 'filt_child', 'filt_proc',
                         'filt_undump', 'filt_merge', *memoryKeys)

        # the read of one input '.info' file, as 'lcov' records it - aggregate,
        #   extract or remove:
        #     scan       pre-scan for the 'end_of_record' boundaries which are
        #                what makes splitting the read possible
        #     parse      time to read the file
        #     append     time to merge the file's data into the running total
        # 'parse'/'append' are here only when the run read whole input files - so
        #   a split read has neither, because a chunk is a part of an input and
        #   the chunks holding the rest of it read at the same time.  There, both
        #   are per chunk, in the 'chunks' table;  'scan' stays here, since the
        #   pre-scan which decided how to split is per input file either way.
        # Filtering is not here at all:  a source file is filtered once, no
        #   matter how many of the inputs had something to say about it, so there
        #   is no per-input filter time - see 'lcovScalarKeys' and the 'chunks'
        #   table.
        infoKeys = ('scan', 'parse', 'append')

        # whole-job times an 'lcov' run records:  one number for the run rather
        #   than one per input file or per forked job.
        #     filter     the separate filter step, over everything which was read
        #                and merged.  A split read has no such step - each of its
        #                readers filters the chunk it read, and reports what that
        #                cost as its own 'filter' in the 'chunks' table.
        lcovScalarKeys = ('filter',)

        # per-source-file data 'lcov' can record:  the version and path
        #   resolution callbacks, the function end lines it had to derive, and
        #   the data consistency check
        sourceKeys = ('version', 'resolve', 'derive_end', 'check_consistency')
        if args.verbose:
            geninfoKeys.extend(['read', 'translate'])

        self.formats = {
            'twoDecimal': s.add_format({'num_format': '0.00'}),
            'intFormat': s.add_format({'num_format': '0'}),
            'title': s.add_format({'bold': True,
                                   'align': 'center',
                                   'valign': 'vcenter',
                                   'text_wrap': True}),
            'stats_title': s.add_format({'italic': True,
                                    'align': 'center',
                                    'valign': 'vcenter'}),
            # a sub-table's brief label - see SECTION_TITLES.  Boldface like
            #   the column titles below it, but left aligned and not wrapped:
            #   it is a phrase in column A, not a column heading
            'section_title': s.add_format({'bold': True,
                                           'align': 'left',
                                           'valign': 'vcenter'}),
            # the same label when it links to its glossary entry:  boldface
            #   plus the blue underline a reader expects of a link
            'section_link': s.add_format({'bold': True,
                                          'align': 'left',
                                          'valign': 'vcenter',
                                          'font_color': 'blue',
                                          'underline': 1}),
            # the sentence beside that label, in column B.  Deliberately not
            #   boldface:  it is prose to be read once, not a heading, and the
            #   contrast is what lets the eye run down the labels alone.  Not
            #   wrapped either, so it spills across the empty cells to its
            #   right rather than making the row tall.
            'section_text': s.add_format({'align': 'left',
                                          'valign': 'vcenter'}),
            # a column title which links to its glossary entry:  the 'title'
            #   format plus the blue underline a reader expects of a link
            'title_link': s.add_format({'bold': True,
                                        'align': 'center',
                                        'valign': 'vcenter',
                                        'text_wrap': True,
                                        'font_color': 'blue',
                                        'underline': 1}),
            # a link in the index at the top of a sheet which has several
            #   tables, to one table's descriptive title
            'index_link': s.add_format({'align': 'left',
                                        'valign': 'vcenter',
                                        'font_color': 'blue',
                                        'underline': 1}),
            # the glossary is prose, so it is left-aligned and top-aligned and
            #   wraps - unlike the numeric tables everywhere else
            'glossary_section': s.add_format({'bold': True,
                                              'align': 'left',
                                              'valign': 'top'}),
            'glossary_term': s.add_format({'align': 'left',
                                           'valign': 'top',
                                           'text_wrap': True}),
            'glossary_text': s.add_format({'align': 'left',
                                           'valign': 'top',
                                           'text_wrap': True}),
            'highlight': s.add_format({'bg_color': 'yellow'}),
            'danger': s.add_format({'bg_color': 'red'}),
            'good': s.add_format({'bg_color': 'green'}),
        }
        intFormat = self.formats['intFormat']
        twoDecimal = self.formats['twoDecimal']
        stats_title = self.formats['stats_title']
        title = self.formats['title']
        section_title = self.formats['section_title']
        section_link = self.formats['section_link']
        section_text = self.formats['section_text']
        title_link = self.formats['title_link']
        index_link = self.formats['index_link']

        def insertConditional(sheet, avgRow, devRow,
                              beginRow, beginCol, endRow, endCol):
            # absolute row, relative column
            avgCell = xl_rowcol_to_cell(avgRow, beginCol, True, False)
            devCell = xl_rowcol_to_cell(devRow, beginCol, True, False)
            # relative row, relative column
            dataCell = xl_rowcol_to_cell(beginRow, beginCol, False, False)
            # absolute value of difference from the average
            diff = 'ABS(%(cell)s - %(avg)s)' % {
                'cell' : dataCell,
                'avg' : avgCell,
            }

            # min difference is difference > 15% of average
            #  only look at positive difference:  taking MORE than average time
            threshold = '(%(cell)s - %(avg)s) > (%(percent)f * %(avg)s)' % {
                'cell' : dataCell,
                'avg' : avgCell,
                'percent': thresholdPercent,
            }

            # cell not blank and difference > 2X std.dev and > 15% of average
            dev2 = '=AND(NOT(OR(ISBLANK(%(cell)s),ISBLANK(%(dev)s))), %(diff)s > (%(devMaxThresh)f * %(dev)s), %(threshold)s)' % {
                'diff' : diff,
                'threshold' : threshold,
                'cell' : dataCell,
                'avg' : avgCell,
                'dev' : devCell,
                'devMaxThresh': devMaxThreshold,
            }
            # yellow if between 1.5 and 2 standard deviations away
            dev1 = '=AND(NOT(OR(ISBLANK(%(cell)s),ISBLANK(%(dev)s))), %(diff)s >  (%(devMinThresh)f * %(dev)s), %(diff)s <= (%(devMaxThresh)f * %(dev)s), %(threshold)s) ' % {
                'diff' : diff,
                'threshold' : threshold,
                'cell' : dataCell,
                'avg' : avgCell,
                'dev' : devCell,
                'devMaxThresh': devMaxThreshold,
                'devMinThresh': devMinThreshold,
            }
            # yellow if between 1 and 2 standard deviations away
            sheet.conditional_format(beginRow, beginCol, endRow, endCol,
                                     { 'type': 'formula',
                                       'criteria': dev1,
                                       'format' : self.formats['highlight'],
                                   })
            # red if more than 2 2 standard deviations away
            sheet.conditional_format(beginRow, beginCol, endRow, endCol,
                                     { 'type': 'formula',
                                       'criteria': dev2,
                                       'format' : self.formats['danger'],
                                   })
            # green if more than 1.5 standard deviations better
            good = '=AND(NOT(OR(ISBLANK(%(cell)s),ISBLANK(%(dev)s))), (%(cell)s - %(avg)s) < (%(devMaxThresh)f * -%(dev)s), %(threshold)s)' % {
                'cell' : dataCell,
                'threshold' : threshold,
                'avg' : avgCell,
                'dev' : devCell,
                'devMaxThresh': devMaxThreshold,
            }
            sheet.conditional_format(beginRow, beginCol, endRow, endCol,
                                     { 'type': 'formula',
                                       'criteria': good,
                                       'format' : self.formats['good'],
                                   })

        # the statistics rows every sub-table leads with, in order, and the
        #   keys whose column total is not additive:  summing the peak memory
        #   of jobs which ran concurrently means nothing, so their 'total' cell
        #   is left empty and the 'max' row below it is the interesting number.
        statLabels = ('total', 'max', 'avg', 'stddev')
        nonAdditiveKeys = memoryKeys

        # rows below a sub-table's title row that each statistic lands on
        statOffset = {label: 1 + i for i, label in enumerate(statLabels)}
        totalOffset = statOffset['total']
        avgOffset = statOffset['avg']

        # empty rows before each sub-table, to set it apart from whatever
        #   precedes it
        sectionGap = 2

        def sectionStart(row):
            # the title row of the next sub-table, given the first unused row
            return row + sectionGap

        # The summary table cross-references each capture sheet cell by cell.
        #   Deriving those addresses from row offsets does not work:  what
        #   precedes a statistic varies from profile to profile - an older
        #   profile has no peak memory rows, 'history' is only there if history
        #   was computed - so an offset which is right for one input silently
        #   points at an unrelated number in the next.  Instead, every scalar
        #   the summary wants is registered here as (row, col) at the point it
        #   is written.  Keyed by the names in geninfoSpecialKeys, and reset
        #   for each input file.
        specialCells = {}

        def recordSpecial(key, row, col):
            # remember where 'key' was just written on the sheet being built,
            #   and return the row - so this can wrap a row assignment
            specialCells[key] = (row, col)
            return row

        def specialCell(key):
            # the A1 address 'key' was written at on the sheet being built, or
            #   None if this profile had no such statistic - in which case the
            #   summary leaves that column empty rather than pointing at
            #   whatever else happens to sit on that row
            rc = specialCells.get(key)
            return xl_rowcol_to_cell(rc[0], rc[1]) if rc else None

        # one column of the capture summary table;  see summaryLayout
        SummaryColumn = namedtuple('SummaryColumn',
                                   ('title', 'key', 'section', 'stat'))

        def summaryLayout():
            # The columns of the capture summary table, in order.  Built once,
            #   so the title row, each capture's data row, and the average and
            #   stddev rows below them are all generated from one description:
            #   three loops over three separately maintained key lists is what
            #   let the statistics row drift out of step with the data it
            #   describes.
            # 'stat' is None for a scalar statistic:  it takes a single column,
            #   read from the cell the capture sheet registered for 'key'.
            #   Otherwise 'stat' names the statistics row of section 'section'
            #   to read 'key' from - a per-element key contributes two columns,
            #   its column total and its average.  A non-additive key
            #   contributes its maximum instead of a total:  summing the peak
            #   memory of jobs which ran concurrently means nothing, and that
            #   column's total cell is deliberately left empty.  See
            #   nonAdditiveKeys, statLabels.
            # Which column of that section holds the key is not recorded here:
            #   this layout describes the whole workbook, and each capture sheet
            #   drops the keys its own profile has nothing under - so the column
            #   is looked up per sheet, in sectionCols.
            layout = [SummaryColumn(k + ' (MB)' if k in memoryKeys else k,
                                    k, None, None)
                      for k in geninfoSpecialKeys]
            sections = [('chunks', geninfoChunkKeys), ('files', geninfoKeys)]
            if args.show_filter:
                sections.append(('filter', filterKeys))
            for section, keys in sections:
                for k in keys:
                    if k in ('order',):
                        continue
                    for stat in ('max' if k in nonAdditiveKeys else 'total',
                                 'avg'):
                        title = k if stat == 'total' else '%s %s' % (k, stat)
                        layout.append(
                            SummaryColumn(title, k, section, stat))
            return layout

        summaryColumns = summaryLayout()

        # Which metrics some sheet in this workbook actually shows, so that the
        #   glossary can describe the workbook in hand rather than everything
        #   the tools can produce.  Keyed by tool, because the same name does
        #   not mean the same thing in two of them;  the common section of the
        #   glossary is matched against the union.
        seenMetrics = {}

        def noteMetrics(tool, data):
            # Record what this profile puts on its sheet.  Every top-level
            #   profile key names a metric which is written either as a scalar
            #   row or as a column of a per-element table - except the three
            #   which are written as something else entirely (the config block
            #   and the 'peak mem' row).
            keys = seenMetrics.setdefault(tool, set())
            keys.update(set(data.keys()) - {'config', 'memory', 'memoryPeak'})
            cfg = data.get('config') if isinstance(data.get('config'),
                                                  dict) else {}
            keys.update(k for k in ('maxParallel', 'segments', 'chunks')
                        if k in cfg)
            if (isinstance(data.get('memoryPeak'), dict) or
                    isinstance(data.get('memory'), dict)):
                keys.update(memoryKeys)
            if 'overall' in keys:
                keys.add('total')    # what older genhtml profiles called it
            if tool == 'geninfo':
                # these get a label row whether the profile has them or not,
                #   and the filter columns are only written when asked for
                keys.update(geninfoScalarKeys)
                if not args.show_filter:
                    keys -= set(filterKeys)
            elif tool == 'genhtml':
                keys.add('parallel')    # a formula, not profile data
            elif tool == 'lcov':
                # 'merge' and 'undump' are recorded per forked job, so they are
                #   on the sheet only when the run forked - and the observed
                #   parallelism is a formula over that same table
                if 'segments' in cfg or 'chunks' in cfg:
                    keys.update(('merge', 'undump', 'parallel'))
                # what a reader spent reading, merging and filtering its own
                #   chunk is a column of the 'chunks' table rather than a
                #   top-level key, so the loop above did not see any of it
                if 'chunks' in cfg:
                    keys.update(('parse', 'append', 'filter'))

        def glossarySections():
            # the glossary sections and their surviving entries, in order:  an
            #   entry whose keys no sheet shows is dropped, and a section with
            #   nothing left in it - or for a tool this workbook has no profile
            #   of - is dropped with it.
            # Each entry is yielded with the keys which triggered it, and each
            #   section with the tool it describes, because that is what the
            #   column titles which link to it are keyed by - see
            #   resolveGlossaryLinks.
            if not seenMetrics:
                return
            union = set().union(*seenMetrics.values())
            if summarySheet:
                union.add('capture_summary')
            for section, tool, entries in GLOSSARY:
                if tool is not None and tool not in seenMetrics:
                    continue
                keys = union if tool is None else seenMetrics[tool]
                rows = [(term, trigger, meaning)
                        for term, trigger, meaning in entries
                        if not trigger or keys.intersection(trigger)]
                if rows:
                    yield section, tool, rows

        # Every column title, and every sub-table label, is a link to the
        #   glossary entry which explains it, so a reader who does not know what
        #   'undump' is can get from the number to the explanation.  Which
        #   entries the glossary has - and so what row each of them lands on -
        #   is not known until every profile has been read, so each is written
        #   as a plain string as its table is laid out and remembered here as
        #   (sheet, row, col, tool, text, key, link format);  the links are
        #   written over them at the end.  See resolveGlossaryLinks.
        deferredLinks = []

        # the row each glossary entry ends up on, keyed by (tool, profile key) -
        #   filled in as the glossary is written, read by resolveGlossaryLinks
        glossaryRows = {}

        def glossaryLink(sheet, row, col, label, fmt, tool, key=None,
                         linkFmt=None):
            # write a column title, and remember it for the glossary link which
            #   will be written over it.  'key' is the profile key the glossary
            #   describes it under, for a title which is not that key itself,
            #   and 'linkFmt' the format the link takes if there is one - the
            #   column title format by default.
            sheet.write_string(row, col, label, fmt)
            deferredLinks.append((sheet, row, col, tool, label, key or label,
                                  linkFmt or title_link))

        def resolveGlossaryLinks():
            # turn every column title the glossary describes into a link to its
            #   entry, now that each entry's row is known.  A title the glossary
            #   says nothing about - a placeholder column, or a metric with no
            #   entry yet - is left as the plain string it was written as.
            for sheet, row, col, tool, label, key, linkFmt in deferredLinks:
                # the whole-run memory block titles its columns '<key> (MB)'
                key = key.replace(' (MB)', '')
                # a tool's own entry for a key wins over the common one:
                #   'parse' is one gcov data file in a geninfo profile and one
                #   '.info' file in an lcov one
                target = glossaryRows.get((tool, key))
                if target is None:
                    target = glossaryRows.get((None, key))
                if target is None:
                    continue
                sheet.write_url(row, col, "internal:'%s'!%s" % (
                    glossarySheet.get_name(), xl_rowcol_to_cell(target, 0)),
                    linkFmt, label)

        # A sheet with several tables leads with an index of links to them, so
        #   that a reader does not have to scroll past one table to find out
        #   what the next one is.  These are the rows reserved for it - one per
        #   table, in the order the tables are written - which writeTitleRow
        #   consumes as it writes each table's label and explanation.  Empty
        #   when this sheet has no index;  see planTables.
        indexRows = []

        # a sheet gets that index only when one of its tables is longer than
        #   this - a table the next one is visible past needs no link
        indexMinRows = 20

        def sectionTitle(typename):
            # the descriptive title of this sheet's 'typename' table as (label,
            #   explanation, glossary key), or None for a table which has none -
            #   see SECTION_TITLES
            return SECTION_TITLES.get((tool, typename))

        def columnTitleRow(sectionRow, typename):
            # the column title row of the table which starts at 'sectionRow':
            #   the row below its descriptive title, if it has one.  The
            #   statistics rows are counted from the column titles - see
            #   statOffset - so anything cross-referencing them has to go
            #   through this rather than assume a table starts with them.
            return sectionRow + (0 if sectionTitle(typename) is None else 1)

        def planTables(row, tables):
            # Reserve the rows for the index of this sheet's sub-tables, and
            #   return the first row the tables themselves may use.  'tables' is
            #   ((section name, number of element rows), ...) in the order
            #   they will be written;  a table which will not be written at all
            #   is not in the list.
            # The index is one line per table - the table's label in column A,
            #   linking to it, and its explanation in column B - separated from
            #   the data above it by a blank row and from the first table by the
            #   two which set every table apart - see sectionStart.
            # A sheet with a single table needs no index - the reader is
            #   looking at that table already - and neither does one whose
            #   tables are all short enough to be on the screen together.
            del indexRows[:]
            if len(tables) < 2 or max(n for t, n in tables) <= indexMinRows:
                return row
            indexRows.extend(range(row + 1, row + 1 + len(tables)))
            return indexRows[-1] + 1

        def writeTitleRow(row, typename, keylist, col=2):
            # the sub-table title row:  its name (if it has one) in column A and
            #   one column title per key from 'col' on, and return the row the
            #   statistics start at.  In the 'title' format - boldface - to set
            #   the titles apart from the data below them.
            # A table which has a descriptive title spends the row above its
            #   column titles on it:  the brief label in column A and the
            #   sentence which explains it in column B.  The label also claims
            #   the next line of this sheet's index (if it has one), which
            #   repeats the pair with the label pointing back at this row - see
            #   SECTION_TITLES, planTables.
            # Each column title, and the label itself, is a link to its glossary
            #   entry - see glossaryLink.
            desc = sectionTitle(typename)
            if desc is not None:
                label, explanation, glossaryKey = desc
                if glossaryKey is None:
                    sheet.write_string(row, 0, label, section_title)
                else:
                    glossaryLink(sheet, row, 0, label, section_title, tool,
                                 glossaryKey, section_link)
                sheet.write_string(row, 1, explanation, section_text)
                if indexRows:
                    indexRow = indexRows.pop(0)
                    sheet.write_url(indexRow, 0, "internal:'%s'!%s" % (
                        sheet.get_name(), xl_rowcol_to_cell(row, 0)),
                        index_link, label)
                    sheet.write_string(indexRow, 1, explanation, section_text)
                row += 1
            if typename is not None:
                sheet.write_string(row, 0, typename, title)
            for k in keylist:
                glossaryLink(sheet, row, col, k, title, tool)
                col += 1
            return row + 1

        def writeStatLabels(row, col=1):
            # label the 4 statistics rows which start at 'row', and return the
            #   row the data starts at.  Italic, to set them apart from the
            #   element rows below them.
            for i, label in enumerate(statLabels):
                sheet.write_string(row + i, col, label, stats_title)
            return row + len(statLabels)

        def insertStats(keys, sawData, sumRow, maxRow, avgRow, devRow,
                        beginRow, endRow, col):
            # fill in the four statistics rows written by writeStatLabels, one
            #   formula per column which has data over exactly rows
            #   beginRow..endRow, and colorize that data range against the
            #   average and standard deviation.
            # a non-additive column gets no total - see nonAdditiveKeys - and a
            #   column with a single sample gets no standard deviation.
            firstCol = col
            col -= 1
            for key in keys:
                col += 1
                if key in ('order',):
                    continue
                if key not in sawData:
                    continue

                f = xl_rowcol_to_cell(beginRow, col)
                t = xl_rowcol_to_cell(endRow, col)

                if key not in nonAdditiveKeys:
                    sum = "+SUM(%(from)s:%(to)s)" % {
                        "from" : f,
                        "to": t
                    }
                    sheet.write_formula(sumRow, col, sum, twoDecimal)
                mx = "+MAX(%(from)s:%(to)s)" % {
                    'from': f,
                    'to': t,
                }
                sheet.write_formula(maxRow, col, mx, twoDecimal)
                avg = "+AVERAGE(%(from)s:%(to)s)" % {
                    'from': f,
                    'to': t,
                }
                sheet.write_formula(avgRow, col, avg, twoDecimal)
                if sawData[key] < 2:
                    continue
                dev = "+STDEV(%(from)s:%(to)s)" % {
                    'from': f,
                    'to': t,
                }
                sheet.write_formula(devRow, col, dev, twoDecimal)

            insertConditional(sheet, avgRow, devRow,
                              beginRow, firstCol, endRow, col)

        def peakMemoryMB(data, job):
            # the named job's peak memory as {'peakVM': ..., 'peakRSS': ...} in
            #   MB, or an empty dict if this profile has no such data (an older
            #   profile, or a platform which does not expose peak memory).
            # 'job' is the phase-qualified job id the profile memory data is
            #   keyed by - e.g. 'capture_3' for the chunk whose timing data is
            #   child{3}, or 'aggregate_3' for segment 3.
            mem = data.get('memory')
            entry = mem.get(job) if isinstance(mem, dict) else None
            if not isinstance(entry, dict):
                return {}
            return {label: entry[mk] / (1 << 20)
                    for label, mk in zip(memoryKeys, ('vsize', 'rss'))
                    if mk in entry}

        def segmentSection(row, typename, ids, keylist, values,
                           required=(), intKeys=(), rowLabel='segment'):
            # one row per forked segment, in the same table shape every other
            #   sub-table here uses:  two empty rows, the boldface title row
            #   naming the section in column A, the italic statistics rows, then
            #   each segment's id in column B and one value per key from column
            #   C on.
            # the statistics are computed over all the segment rows and, as in
            #   every other table here, the data cells are colorized against
            #   them:  yellow/red for a segment more than the threshold slower
            #   than the average.
            # 'required' names the keys to warn about when a segment does not
            #   have them;  the rest are legitimately absent in some profiles.
            # 'rowLabel' names what one row is - the jobs of a split read are
            #   chunks rather than segments - and is what the warnings above
            #   call it too.
            # Returns (first data row, last data row, first unused row) - the
            #   caller needs the data range to reference the segment column.
            # A key which none of these rows has a value for gets no column at
            #   all rather than an empty one to read past:  an empty cell reads
            #   as 'this cost nothing', which is not what 'this does not apply to
            #   the way this run divided its work' means.  The warning about a
            #   missing required key comes first, over the keys the caller asked
            #   for, so that a key missing everywhere is still reported rather
            #   than quietly dropped.  elementSection drops an absent key the
            #   same way.
            for id in ids:
                for k in required:
                    if k not in values[id]:
                        print("Warning: %s: no %s for %s %s" % (
                            name, k, rowLabel, id))
            keylist = [k for k in keylist if any(k in values[id] for id in ids)]
            row = writeTitleRow(sectionStart(row), typename, keylist)
            sumRow, maxRow, avgRow, devRow = (row, row + 1, row + 2, row + 3)
            row = writeStatLabels(row)

            dataStart = row
            sawData = {}
            for id in ids:
                label = '%s %s' % (rowLabel, id)
                sheet.write_string(row, 1, label)
                d = values[id]
                col = 2
                for k in keylist:
                    if k in d:
                        try:
                            # don't crash on partially corrupt profile data
                            sheet.write_number(
                                row, col, float(d[k]),
                                intFormat if k in intKeys else twoDecimal)
                            sawData[k] = sawData.get(k, 0) + 1
                        except:
                            print("Warning: %s: unable to write %s for %s[%s]"
                                  % (name, str(d[k]), label, k))
                    col += 1
                row += 1

            insertStats(keylist, sawData, sumRow, maxRow, avgRow, devRow,
                        dataStart, row - 1, 2)
            return (dataStart, row - 1, row)

        def elementIds(keylist):
            # the ids the given keys are recorded for:  the elements the table
            #   of those keys will have a row for.  Shared with elementSection,
            #   so that the index at the top of the sheet and the table itself
            #   agree on whether there is a table at all and on how long it
            #   is.
            ids = set()
            for key in keylist:
                if data.get(key) and isinstance(data[key], dict):
                    ids.update(data[key].keys())
            return ids

        def filterJobIds():
            # the forked filter workers this profile has data for, in id order.
            #   Numerically when the ids are numbers, which they are at the top
            #   level;  lexically when they are not, because a worker forked by a
            #   worker is identified by the label of the job which forked it
            #   ('aggregate_1_0') rather than by a number - see
            #   'lcovutil::_filterChunkId'.  Sorting the two kinds together
            #   would compare a string against an int, so keep the numbered ones
            #   first as a group.
            ids = set()
            for key in filterJobKeys:
                if isinstance(data.get(key), dict):
                    ids.update(data[key].keys())
            return sorted(ids, key=lambda i: (0, int(i), '')
                          if str(i).isdigit() else (1, 0, str(i)))

        def elementSection(typename, keylist, sectionRow):
            # the same table shape as segmentSection above, for data which is
            #   keyed by element name rather than by job id:  two empty rows,
            #   the boldface title row, the italic total/max/avg/stddev
            #   statistics rows, then one row per element - its id in column B
            #   and one value per key from column C on - colorized against
            #   those statistics.
            # The elements are the union of the ids the keys are recorded for,
            #   so a key which was recorded for only some of them simply leaves
            #   those cells empty;  a key this profile does not have at all gets
            #   no column, rather than an empty one to read past.
            # Returns the first unused row after the section - 'sectionRow'
            #   unchanged if there is nothing to write.
            ids = elementIds(keylist)
            keylist = [k for k in keylist if data.get(k) and
                       isinstance(data[k], dict)]
            if not ids:
                return sectionRow

            r = writeTitleRow(sectionStart(sectionRow), typename, keylist)
            sumRow, maxRow, avgRow, devRow = (r, r + 1, r + 2, r + 3)
            r = writeStatLabels(r)
            dataStart = r

            sawData = {}
            for id in sorted(ids):
                col = 1
                sheet.write_string(r, col, id)
                col += 1
                for key in keylist:
                    if id in data[key]:
                        try:
                            sheet.write_number(r, col, float(data[key][id]),
                                               twoDecimal)
                            sawData[key] = sawData.get(key, 0) + 1
                        except (TypeError, ValueError):
                            # a key which was not recorded for this element is
                            #   ordinary, and simply leaves the cell empty - a
                            #   value which cannot be written is not
                            print("Warning: %s: unable to write %s for %s.%s"
                                  % (name, str(data[key][id]), id, key))
                    col += 1
                r += 1
            dataEnd = r - 1

            insertStats(keylist, sawData, sumRow, maxRow, avgRow, devRow,
                        dataStart, dataEnd, 2)
            return dataEnd + 1

        activeSheet = None
        for name in files:
            # the registry is per sheet - see specialCells
            specialCells.clear()
            # ..and so is the index:  a reserved row which the table it was
            #   reserved for turned out not to have (a profile too truncated to
            #   write the table from) is dropped here rather than left for the
            #   next sheet's first table to claim
            del indexRows[:]
            # ..and so are the cell and the row the elapsed total landed on,
            #   which the observed parallelism of a report is divided by and
            #   written beside.  A profile truncated before that total was
            #   written has neither, and leaving the previous sheet's behind
            #   pointed this sheet's formula at another sheet's row
            total = None
            totalRow = None
            try:
                with open(name) as f:
                    data = json.load(f)
            except Exception as err:
                print("%s: unable to parse: %s" % (name, str(err)))
                continue

            try:
                cfg = data['config']

                try:
                    tool = data['config']['tool']
                    if (tool == 'lcov' and
                        -1 != data['config']['cmdLine'].find('--call-from-lcov')):
                        tool = 'geninfo'
                except:
                    tool = 'unknown'
                    print("%s: unknown tool" %(name))
            except:
                print("%s: no 'config' data key - I think this is not lcov performance data - skipping" % (name))
                continue

            noteMetrics(tool, data)

            p, f = os.path.split(name)
            if os.path.splitext(f)[0] == tool:
                sheetname = os.path.split(p)[1] # the directory
            else:
                sheetname = f
            if len(sheetname) > 30:
                # take the tail of the string..
                sheetname = sheetname[-30:]
            sn = sheetname
            for i in range(1000):
                try:
                    sheet = s.add_worksheet(sn[-31:])
                    if activeSheet == None:
                        activeSheet = sheet
                    break
                except:
                    sn = sheetname + "_" + str(i)
            else:
                print("%s in use..giving up" % (sheetname))
                sys.exit(1)

            # wide enough for the sub-table labels which go in column A - see
            #   sectionLabelWidth
            sheet.set_column(0, 0, sectionLabelWidth)

            row = 0
            sheet.write_string(row, 0, name)
            row += 1
            sheet.write_string(row, 0, 'config')
            for n in sorted(data['config'].keys()):
                sheet.write_string(row, 1, n)
                v = data['config'][n]
                try:
                    # write a numeric config value as a number, so it can be
                    #   compared and averaged.  Go by whether the value
                    #   converts rather than by its JSON type:  the profile
                    #   writer quotes some of these ('maxParallel' comes
                    #   through as the string "32"), and a config entry which
                    #   failed to convert used to be dropped from the sheet
                    #   altogether - along with its row, so the next key
                    #   overwrote it
                    sheet.write_number(row, 2, float(v), intFormat)
                    # a config value the summary table wants - the parallelism
                    #   this run was allowed, which is what makes the
                    #   parallelism it achieved interpretable
                    if n in geninfoSpecialKeys:
                        recordSpecial(n, row, 2)
                except (TypeError, ValueError):
                    sheet.write_string(row, 2, str(v))
                row += 1
                if n == 'tool':
                    # which implementation of the coverage data classes actually
                    #   ran, right below the tool which ran them:  1 if the C++
                    #   XS extension loaded, 0 if the run fell back to (or was
                    #   forced to) pure Perl.  A profile from a release which
                    #   did not record this reads as 0 - the fallback is silent,
                    #   so 'not recorded' and 'did not load' amount to the same
                    #   thing from here.
                    xs = data['config'].get('xs')
                    try:
                        # a profile writer which quotes its numbers hands this
                        #   over as the string "0", which is not false in python
                        enabled = 1 if float(xs) else 0
                    except (TypeError, ValueError):
                        enabled = 1 if xs else 0
                    sheet.write_string(row, 1, 'XS enabled')
                    sheet.write_number(row, 2, enabled, intFormat)
                    row += 1

            if tool == 'geninfo':
                # how the data files found were divided up.  A capture which did
                #   not record one of these simply does not have the row;  one
                #   which recorded something unwritable under it keeps the row
                #   and is reported - the write used to be tried before the
                #   label and before the row advanced, so a value which failed
                #   took its own label with it and let the next key overwrite the
                #   row, silently
                for k in ('chunkSize', 'nChunks', 'nFiles', 'interval'):
                    if k not in data:
                        continue
                    sheet.write_string(row, 1, k)
                    try:
                        # a profile writer which quotes its numbers hands these
                        #   over as strings
                        sheet.write_number(row, 2, float(data[k]), intFormat)
                    except (TypeError, ValueError):
                        print("Warning: %s: unable to write %s for %s" % (
                            name, str(data[k]), k))
                    row += 1

            # every tool records its whole-run elapsed time under 'total'.
            #   'overall' is the key genhtml used for the same thing in
            #   profiles written by older releases.
            for k in ('total', 'overall'):
                if k not in data:
                    continue
                sheet.write_string(row, 0, 'total')
                try:
                    # a profile writer which quotes its numbers hands this over
                    #   as a string, and one truncated part way through can have
                    #   something which is not a number at all under the key -
                    #   which used to raise here and take the whole run with it.
                    #   Without a cell there is no parallelism figure to write
                    #   either;  see the genhtml layout, below
                    sheet.write_number(row, 1, float(data[k]), twoDecimal)
                    total = xl_rowcol_to_cell(row, 1)
                    totalRow = recordSpecial('total', row, 1)
                except (TypeError, ValueError):
                    print("Warning: %s: unable to write %s for total" % (
                        name, str(data[k])))
                row += 1
                break

            # peak memory (bytes), reported by lcovutil profile as
            #   memoryPeak = { rss: <peak resident set>, vsize: <peak virtual> }
            #   (max over the parent and all forked workers).  Emit a boldface
            #   'peak mem' title row immediately after the 'total' row, then a
            #   single italic-labelled row of values, in MB - the same table
            #   shape the per-job memory columns use, but with only the one row,
            #   so there are no statistics over it.
            peak = data.get('memoryPeak')
            peakVals = [(label, peak[mk] / (1 << 20))
                        for label, mk in zip(memoryKeys, ('vsize', 'rss'))
                        if mk in peak] if isinstance(peak, dict) else []
            if peakVals:
                writeTitleRow(row, 'peak mem',
                              [label + ' (MB)' for label, v in peakVals])
                col = 2
                for label, v in peakVals:
                    sheet.write_number(row + 1, col, v, twoDecimal)
                    # the summary table wants these - and cannot find them by
                    #   counting rows, since this whole block is absent from a
                    #   profile which has no memory data
                    recordSpecial(label, row + 1, col)
                    col += 1
                # there is one row of data, and it is not one job's peak but
                #   the largest seen anywhere in the process tree
                sheet.write_string(row + 1, 1, 'max', stats_title)
                row += 2

            if tool == 'lcov':
                # The metrics this run recorded as a single number rather than as
                #   a table:  the whole-job filter step, and - for 'lcov
                #   --extract'/'--remove', which read one file - the 'parse' and
                #   'append' of that one file, which a run with several inputs
                #   reports per input in the 'info' table below.  Both shapes
                #   reach the same code, so write whichever one this profile has.
                # These go above the index of tables, with the rest of the
                #   whole-run numbers:  the index belongs immediately above the
                #   tables it indexes.
                for k in infoKeys + lcovScalarKeys:
                    if k not in data or isinstance(data[k], dict):
                        continue
                    sheet.write_string(row, 0, k)
                    try:
                        sheet.write_number(row, 1, float(data[k]), twoDecimal)
                    except (TypeError, ValueError):
                        print("Warning: %s: unable to write %s for %s" % (
                            name, str(data[k]), k))
                    row += 1

                # A parallel run divides the work one of two ways, and never
                #   both in the same run:
                #     - the input files are dealt out to forked jobs, each of
                #       which aggregates its share:  'segments' in the config
                #       block
                #     - or one read is split, when the inputs are big enough to
                #       be worth several readers:  'chunks'.  Those readers
                #       filter their own piece, so there is nothing left for the
                #       parent to divide into segments.
                #   Both record the same keys under the same top-level numeric
                #   job ids, and both key their peak memory memory{aggregate_N},
                #   so one table describes either;  only its name and where the
                #   job count comes from differ.
                #   Memory is absent from an older profile, or on a platform
                #   which does not expose peak memory.
                # 'parse'/'append'/'filter' are what a job spent reading its own
                #   share, merging what it read into its own total, and filtering
                #   the result - so only the readers of a split read have them.
                #   The jobs of a segmented read are handed whole input files,
                #   which the 'info' table reports, and do not filter at all;  the
                #   parent does that afterwards and reports the whole-job 'filter'
                #   above.  In that table these three simply get no column, as any
                #   other key nothing was recorded under does - see
                #   segmentSection.
                jobKeys = ('total', 'parse', 'append', 'filter', 'merge',
                           'undump', *memoryKeys)
                jobTable = None
                for typename in ('segments', 'chunks'):
                    try:
                        # a profile writer which quotes its numbers hands this
                        #   over as the string "2"
                        jobTable = (typename, int(cfg[typename]))
                        break
                    except (KeyError, TypeError, ValueError):
                        continue

                # the index of this sheet's tables, if it needs one:  the forked
                #   jobs (a serial run has none), the read of each input file,
                #   the filter workers (only a separate filter step which forked
                #   has any), and the source files the inputs name
                filterIds = filterJobIds()
                tables = [jobTable] if jobTable else []
                for typename, ids in (('info', elementIds(infoKeys)),
                                      ('filter', filterIds),
                                      ('source', elementIds(sourceKeys))):
                    if ids:
                        tables.append((typename, len(ids)))
                row = planTables(row, tables)

                if jobTable:
                    typename, nJobs = jobTable
                    values = {}
                    for job in range(nJobs):
                        # a json object key is a string, so the numeric job ids
                        #   can come back either way
                        d = data.get(job, data.get(str(job)))
                        d = dict(d) if isinstance(d, dict) else {}
                        # a job's peak memory is not stored with its timing
                        #   data:  it is keyed by job id in the profile 'memory'
                        #   section - memory{aggregate_N} for job N - so copy it
                        #   in and let it be written like any other key.
                        d.update(peakMemoryMB(data, 'aggregate_%d' % (job)))
                        values[job] = d
                    # which of those keys the table actually got a column for -
                    #   the ones no job recorded are dropped, so the position of
                    #   a column has to be read from this rather than from
                    #   'jobKeys' itself.  See segmentSection, which applies the
                    #   same rule.
                    written = [k for k in jobKeys
                               if any(k in d for d in values.values())]
                    dataStart, dataEnd, row = segmentSection(
                        row, typename, range(nJobs), jobKeys, values,
                        rowLabel=typename[:-1],
                        required=('total', 'merge', 'undump'))

                    # observed parallelism:  the jobs' wall-clock summed, over
                    #   the elapsed total.  Needs that total, which a truncated
                    #   profile can lack - either the whole-run one or the jobs'.
                    if 'total' in specialCells and 'total' in written:
                        totalCol = 2 + written.index('total')
                        effectiveParallelism = \
                            "+SUM(%(from)s:%(to)s)/%(total)s" % {
                                'from': xl_rowcol_to_cell(dataStart, totalCol),
                                'to': xl_rowcol_to_cell(dataEnd, totalCol),
                                'total': total,
                            }
                        sheet.write_formula(totalRow, 3, effectiveParallelism,
                                            twoDecimal)

                # ...and then the read itself, per input file:  what reading and
                #   merging each of them cost, when the run read whole files, and
                #   the pre-scan either way.  A split read reports its read
                #   against the chunk which did it, in the table above, so only
                #   the 'scan' column is left here.
                row = elementSection('info', infoKeys, row)

                # ...then the separate filter step, when there was one and it
                #   forked:  one row per filter worker, with the same parent/child
                #   breakdown the reader table above has - what the worker cost
                #   the parent, how long its result waited, what it spent inside,
                #   the parent's deserialize and merge, and its own peak memory.
                #   The whole-job 'filter' row above is what those workers add up
                #   to;  this is where a filter step which cost more than it
                #   looks like it should is explained.
                #   A split read has no such table:  its readers filtered the
                #   chunk they read as they read it, and what that cost is a
                #   column of the 'chunks' table above rather than a table of its
                #   own.
                if filterIds:
                    values = {}
                    for id in filterIds:
                        d = {k: data[k][id] for k in filterJobKeys
                             if isinstance(data.get(k), dict) and id in data[k]}
                        # ..and its peak memory, which like every other job's is
                        #   keyed by job label in the profile 'memory' section -
                        #   memory{filter_<id>} for the worker whose timing data
                        #   is filt_child{<id>}
                        d.update(peakMemoryMB(data, 'filter_%s' % (id)))
                        values[id] = d
                    # only the next free row is of interest here - the data range
                    #   matters to a table some formula refers to
                    row = segmentSection(row, 'filter', filterIds, filterJobKeys,
                                         values, rowLabel='filter',
                                         required=('filt_chunk',
                                                   'filt_child'))[2]

                # the per-source-file callbacks and checks, which are recorded
                #   the same way and which no lcov sheet used to show at all
                row = elementSection('source', sourceKeys, row)

                # go on to the next file
                continue

            elif tool == 'geninfo':

                if summarySheet:
                    # first one - add titles, etc
                    if len(geninfoSheets) == 0:
                        summarySheet.write_string(1, 0, "average", title)
                        summarySheet.write_string(2, 0, "stddev", title)
                        titleRow = 0
                        summarySheet.write_string(titleRow, 0, "case", title)
                        # each column title links to the glossary entry for the
                        #   metric it reports, as the capture sheets' own column
                        #   titles do.  The title is not always the profile
                        #   key - a per-element metric contributes a 'total' and
                        #   an 'avg' column - so the key to look up is passed
                        #   explicitly.
                        for col, c in enumerate(summaryColumns, 1):
                            glossaryLink(summarySheet, titleRow, col, c.title,
                                         title, 'geninfo', c.key)
                        summarySheet.write_string(3, 0, "YELLOW: Value between [%(devMinThresh)0.2f,%(devMaxThresh)0.2f) standard deviations larger than average" % {
                            'devMinThresh': devMinThreshold,
                            'devMaxThresh': devMaxThreshold,
                        }, self.formats['highlight'])
                        summarySheet.write_string(4, 0, "RED: Value more than %(devMaxThresh)0.2f standard deviations larger than average" % {
                            'devMaxThresh': devMaxThreshold,
                        }, self.formats['danger'])
                        summarySheet.write_string(5, 0, "GREEN: Value more than %(devMaxThresh)0.2f standard deviations smaller than average" % {
                            'devMaxThresh': devMaxThreshold,
                        }, self.formats['good'])
                        firstSummaryRow = 7

                    # want rows for average and variance - leave a blank row
                    summaryRow = firstSummaryRow + len(geninfoSheets)

                geninfoSheets.append(sheet)
                # the scalar capture statistics which are not on the sheet yet:
                #   'total' and the peak memory rows were written above, for
                #   every tool, and registered as they went.  'parallel' claims
                #   its row here and is filled in below, once the chunk table's
                #   location is known.  A key this profile does not have still
                #   gets its label row - so the sheet says so - but no
                #   registered cell, which leaves its summary column empty
                #   instead of reporting the blank as a zero.
                for k in geninfoScalarKeys:
                    sheet.write_string(row, 0, k)
                    if k == 'parallel':
                        recordSpecial(k, row, 1)
                    elif k in data:
                        try:
                            # a profile writer which quotes its numbers hands
                            #   these over as strings, which is a value that was
                            #   recorded rather than a missing one - so convert
                            #   it rather than report it and leave the cell, and
                            #   with it that key's summary column, empty
                            sheet.write_number(row, 1, float(data[k]),
                                               twoDecimal)
                            recordSpecial(k, row, 1)
                        except (TypeError, ValueError):
                            print("Warning: %s: unable to write %s for %s" % (
                                name, str(data[k]), k))
                    row += 1

                # the directory scan times:  a flat two-column list under a label
                #   row of its own, not a table - nothing here knows what these
                #   numbers are, so there is nothing worth a total or an average
                #   over them and nothing to colorize an outlier against.
                # A capture interrupted before it finished scanning recorded none
                #   of them, and a corrupt profile can have something which is
                #   not a hash of numbers under the key at all;  reading it
                #   without asking took the sheet, the profiles after it and the
                #   workbook with it.  The label keeps its row either way, so the
                #   sheet says what the capture recorded.
                sheet.write_string(row, 0, 'find')
                row += 1
                find = data.get('find')
                if not isinstance(find, dict):
                    if find is not None:
                        print("Warning: %s: unable to write %s for find" % (
                            name, str(find)))
                    find = {}
                for dirname in sorted(find.keys()):
                    sheet.write_string(row, 1, dirname)
                    try:
                        # a profile writer which quotes its numbers hands these
                        #   over as strings
                        sheet.write_number(row, 2, float(find[dirname]),
                                           twoDecimal)
                    except (TypeError, ValueError):
                        print("Warning: %s: unable to write %s for [find][%s]" %
                              (name, str(find[dirname]), dirname))
                    row += 1

                # {section name: {key: the column it landed in}} for the tables
                #   written below.  A key none of a section's elements has a
                #   value for gets no column, so which column a key is in is
                #   not its position in that section's key list - and the
                #   summary sheet, whose layout is built once for the whole
                #   workbook, has to be told where this capture actually put it.
                sectionCols = {}

                def dataSection(typename, elements, keylist, sectionRow):
                    # one contiguous table per section, starting at 'sectionRow':
                    #   the boldface title row naming the section in column A,
                    #   the italic statistics rows over the data - total, max,
                    #   avg, stddev - then one row per element:  its id in column
                    #   B and one value per key from column C on.  The data cells
                    #   are colorized against the average and stddev just above
                    #   them, so the statistics have to be adjacent to the data
                    #   they describe.
                    # A key which none of these elements has a value for gets no
                    #   column at all rather than an empty one to read past:  an
                    #   empty cell reads as 'this cost nothing', which is not the
                    #   same as 'this run did not do that'.
                    # Returns the first unused row after the section.
                    keylist = [k for k in keylist
                               if isinstance(data.get(k), dict) and
                               any(id in data[k] for id in elements)]
                    sectionCols[typename] = {
                        k: col for col, k in enumerate(keylist, 2)}
                    row = writeTitleRow(sectionRow, typename, keylist)
                    sumRow, maxRow, avgRow, devRow = (row, row + 1, row + 2,
                                                      row + 3)
                    row = writeStatLabels(row)
                    dataStart = row

                    sawData = {}
                    for id in elements:
                        col = 1
                        sheet.write_string(row, col, id)
                        col += 1

                        for key in keylist:
                            if id in data[key]:
                                try:
                                    # a profile writer which quotes its numbers
                                    #   hands these over as strings, and a partly
                                    #   corrupt one can have something which is
                                    #   not a number at all.  That is not the
                                    #   same as a key which was simply not
                                    #   recorded for this element - which leaves
                                    #   the cell empty, and legitimately - so say
                                    #   so rather than leaving the same hole
                                    sheet.write_number(
                                        row, col, float(data[key][id]),
                                        intFormat if key in ('order',)
                                        else twoDecimal)
                                    sawData[key] = sawData.get(key, 0) + 1
                                except (TypeError, ValueError):
                                    print("Warning: %s: unable to write %s for"
                                          " %s.%s" % (name, str(data[key][id]),
                                                      id, key))
                            col += 1
                        row += 1

                    dataEnd = row - 1

                    insertStats(keylist, sawData, sumRow, maxRow, avgRow,
                                devRow, dataStart, dataEnd, 2)
                    return dataEnd + 1

                # the row each section's title lands on, remembered so the
                #   summary sheet can find that section's statistics rows - see
                #   statOffset.  'filter' is optional, and the chunk table is
                #   absent from a serial capture, in which case the file table
                #   takes its place;  a section which was not written stays
                #   None, and its summary columns are left empty rather than
                #   reading the wrong table by position.
                # the index of this sheet's tables, if it needs one:  the
                #   capture jobs (a serial capture has none), the data files,
                #   and the filter jobs (only when those were asked for)
                tables = []
                for typename, key in (('chunks', 'child'), ('files', 'file'),
                                      ('filter', 'filt_child')):
                    if typename == 'filter' and not args.show_filter:
                        continue
                    if isinstance(data.get(key), dict) and data[key]:
                        tables.append((typename, len(data[key])))
                row = planTables(row, tables)

                tableRow = sectionStart(row)
                chunkSectionRow = None
                fileSectionRow = tableRow
                filterSectionRow = None

                # first the chunk data...
                # process: time from immediately before fork in parent
                #          to immediately after 'process_one_file' in
                #          child (can't record 'dumper' call time
                #          because that also dumps the profile
                # child:   time from child coming to life after fork
                #          to immediately after 'process_one_file'
                # exec: time take to by 'gcov' call
                # merge: time to merge child process (undump, read
                #       trace data, append to summary, etc.)
                # undump: dumper 'eval' call + stdout/stderr recovery
                # parse: time to read child tracefile.info
                # append: time to merge that into parent master report
                try:
                    chunks = sorted(data['child'].keys(), key=int, reverse=True)
                    # peak memory is keyed by job id in the profile 'memory'
                    #   section - memory{capture_N} for the chunk whose timing
                    #   data is child{N} - so flatten it into the same
                    #   id-keyed shape the timing keys have, and dataSection
                    #   picks it up like any other key.
                    for id in chunks:
                        for label, v in peakMemoryMB(
                                data, 'capture_%s' % (id)).items():
                            data.setdefault(label, {})[id] = v
                    row = dataSection('chunks', chunks, geninfoChunkKeys,
                                      tableRow)
                    chunkSectionRow = tableRow
                    fileSectionRow = sectionStart(row)
                except:
                    # no chunk data - so just insert file data
                    pass

                # the observed parallelism is the first section's total time over
                #   the elapsed total:  the 'work' column of the chunk table, or
                #   'file' when a serial capture leaves only the file table.
                #   Which section that is is not known until the chunk table has
                #   been written or skipped, the statistics rows are counted from
                #   a section's column titles rather than from its descriptive
                #   title - see columnTitleRow - and which column the key landed
                #   in is what that section wrote rather than where it is in the
                #   key list - see sectionCols
                if chunkSectionRow is not None:
                    parallelSumRow = columnTitleRow(chunkSectionRow, 'chunks')
                    parallelSumSection, parallelSumKey = ('chunks', 'work')
                else:
                    parallelSumRow = columnTitleRow(fileSectionRow, 'files')
                    parallelSumSection, parallelSumKey = ('files', 'file')
                parallelSumRow += totalOffset


                def fileOrder(f):
                    # where the capture came to 'f' in its processing order, for
                    #   the sort which puts the file it read last at the top of
                    #   the file table.
                    # A file the profile recorded no usable order for goes to the
                    #   end of that order and is named:  the table is what the
                    #   sheet is for, so it is written in whatever order can be
                    #   made out rather than dropped whole - which is what letting
                    #   the lookup raise did, under a message which said the
                    #   capture had no file data at all.
                    try:
                        return -int(data['order'][f])
                    except (KeyError, TypeError, ValueError):
                        print("Warning: %s: no processing order for %s" % (
                            name, f))
                        return 1

                try:
                    row = dataSection('files',
                                      sorted(data['file'].keys(),
                                             key=fileOrder),
                                      geninfoKeys, fileSectionRow)
                except (KeyError, AttributeError, TypeError):
                    # there may be no files - if dataset was empty
                    print("No 'file' data in %s" % (name))

                # now the filter data - if any
                if args.show_filter:
                    try:
                        chunks = sorted(data['filt_child'].keys(), key=int, reverse=True)
                        filterSectionRow = sectionStart(row)
                        row = dataSection('filter', chunks, filterKeys,
                                          filterSectionRow)

                    except:
                        filterSectionRow = None


                # observed parallelism:  productive time over elapsed time.
                #   Needs the elapsed total, which a truncated profile can lack,
                #   and the column whose total that is, which a profile with
                #   nothing recorded under that key does not have
                parallelSumCol = sectionCols.get(parallelSumSection, {}).get(
                    parallelSumKey)
                if 'total' in specialCells and parallelSumCol is not None:
                    effectiveParallelism = "+%(sum)s/%(total)s" % {
                        'sum': xl_rowcol_to_cell(parallelSumRow,
                                                 parallelSumCol),
                        'total': specialCell('total'),
                    }
                    parallelRow, parallelCol = specialCells['parallel']
                    sheet.write_formula(parallelRow, parallelCol,
                                        effectiveParallelism, twoDecimal)
                else:
                    del specialCells['parallel']

                if summarySheet:
                    summarySheet.write_string(summaryRow, 0, name)
                    # href to the corresponding page..
                    summarySheet.write_url(summaryRow, 0, "internal:'%s'!A1" % (
                        sheet.get_name()))
                    sheetRef = "='" + sheet.get_name() + "'!"
                    # each section's column title row, which is what its
                    #   statistics rows are counted from - the descriptive title
                    #   above it is not part of that count
                    sectionRows = {
                        t: None if r is None else columnTitleRow(r, t)
                        for t, r in (('chunks', chunkSectionRow),
                                     ('files', fileSectionRow),
                                     ('filter', filterSectionRow))}

                    # cross-reference this capture's numbers into its summary
                    #   row, one column per entry of summaryColumns:  a scalar
                    #   statistic - the elapsed total, the observed
                    #   parallelism, the run's peak VM and RSS - by the cell the
                    #   capture sheet registered it at, and a per-element key by
                    #   the statistics row of the section it belongs to.  A
                    #   statistic this profile does not have, or a section which
                    #   was not written at all, leaves its column empty.
                    for summaryCol, c in enumerate(summaryColumns, 1):
                        col = sectionCols.get(c.section, {}).get(c.key)
                        if c.stat is None:
                            cell = specialCell(c.key)
                        elif sectionRows[c.section] is None or col is None:
                            cell = None
                        else:
                            cell = xl_rowcol_to_cell(
                                sectionRows[c.section] + statOffset[c.stat],
                                col)
                        if cell is not None:
                            summarySheet.write_formula(
                                summaryRow, summaryCol, sheetRef + cell,
                                intFormat if (c.stat is None and
                                              c.key in summaryIntKeys)
                                else twoDecimal)
                continue

            elif tool == 'genhtml':

                # the whole-run phase times.  A run which did not do one of these
                #   - there is no '--history-script' to time unless one was
                #   given - simply does not have the row;  one which recorded
                #   something unwritable under it keeps the row and is reported,
                #   rather than leaving the label for the next key to overwrite
                for k in ('parse_source', 'parse_diff',
                          'parse_current', 'parse_baseline',
                          'history'):
                    if k not in data:
                        continue
                    sheet.write_string(row, 0, k)
                    try:
                        sheet.write_number(row, 1, float(data[k]), twoDecimal)
                    except (TypeError, ValueError):
                        print("Warning: %s: unable to write %s for %s" % (
                            name, str(data[k]), k))
                    row += 1

                # total: time from start to end of the particular unit -
                # child: time from start to end of child process
                # annotate: annotate callback time (if called)
                # load:  load source file (if no annotation)
                # synth:  generate file content (no annotation and no no file found)
                # categorize: compute owner/date bins, differential categories
                # process:  time to generate data and write HTML for file
                # synth:  generate file content (no file found)
                # source:
                genhtmlKeys = ['  '] # placeholder key
                # these keys are computed for segments
                #   nJobs: number of files this segment was given
                genhtml_chunkyKeys = ['nJobs', 'child', 'startDelay',
                                      'mergeDelay', 'merge_segment', 'segment',
                                      *memoryKeys]
                filter_keys = ['filt_undump', 'filt_merge', 'filt_queue', 'filt_chunk']

                # what the report covers:  one row per source file and
                #   directory.  Older profiles recorded no per-file total, only
                #   the time to write each page.  Which of the two this is is
                #   also which key the observed parallelism below is the total
                #   of, so keep the name and not just the value.
                for scopeKey in ('file', 'html'):
                    scope = data.get(scopeKey)
                    if isinstance(scope, dict):
                        break

                # the index of this sheet's tables, if it needs one:  the report
                #   jobs (a serial run has none) and the per-object table, which
                #   has no section name of its own
                tables = []
                if isinstance(data.get('segment'), dict):
                    tables.append(('segments', len(data['segment'])))
                if isinstance(scope, dict):
                    tables.append((None, len(scope)))
                row = planTables(row, tables)

                # the same per-segment table (title row, statistics rows, then
                #   one row per segment, colorized against the average) the
                #   lcov branch writes.  A serial run has no segment data at
                #   all, so skip the section entirely in that case.
                if isinstance(data.get('segment'), dict):
                    segIds = sorted(data['segment'].keys(), key=int)
                    values = {}
                    for seg in segIds:
                        # this segment's peak memory is not stored with its
                        #   timing data:  it is keyed by job id in the profile
                        #   'memory' section - memory{segment_N} for segment N -
                        #   so merge it in and write it like any other key.
                        d = dict(peakMemoryMB(data, 'segment_%s' % (seg)))
                        for k in genhtml_chunkyKeys:
                            if (k not in d and isinstance(data.get(k), dict)
                                    and seg in data[k]):
                                d[k] = data[k][seg]
                        values[seg] = d
                    row = segmentSection(row, 'segments', segIds,
                                         genhtml_chunkyKeys, values,
                                         required=('segment', 'child'),
                                         intKeys=('nJobs',))[2]

                perObj_keys = ['file', 'source', 'categorize', 'annotate', 'check_version',
                               'html', 'load', 'criteria', 'synth']

                for k in perObj_keys:
                    if k in data:
                        genhtmlKeys.append(k)

                if not isinstance(scope, dict):
                    print("%s:  incomplete data - skipping" % (name))
                    continue
                scopeList = scope.keys()

                # the per-object table has no section name of its own
                row = writeTitleRow(sectionStart(row), None, genhtmlKeys, 3)
                sumRow, maxRow, avgRow, devRow = (row, row + 1, row + 2,
                                                  row + 3)
                row = writeStatLabels(row, 2)
                begin = row
                sawData = {}
                #sawData['total'] = 0
                def printDataRow(obj):
                    # 'obj' rather than 'name':  the profile being read is
                    #   'name', and shadowing it left the warning below naming
                    #   the source file instead of the profile the bad value is
                    #   in - and not naming the metric at all, which is the other
                    #   half of what a reader needs to find it
                    col = 4
                    nonlocal row
                    for k in genhtmlKeys[1:]:
                        if (k in data and
                            obj in data[k]):
                            try:
                                sheet.write_number(row, col,
                                                   float(data[k][obj]),
                                                   twoDecimal)
                                if k in sawData:
                                    sawData[k] += 1
                                else:
                                    sawData[k] = 1
                            except (TypeError, ValueError):
                                # a key which was not recorded for this object
                                #   is ordinary and leaves the cell empty;  a
                                #   value which cannot be written is not
                                print("Warning: %s: unable to write %s for %s.%s"
                                      % (name, str(data[k][obj]), obj, k))
                        col += 1

                def visitScope(f):
                    nonlocal row
                    if '' == f:
                        sheet.write_string(row, 1, 'top')
                    else:
                        pth, name = os.path.split(f)
                        if name == '':
                            # this is a directory..
                            sheet.write_string(row, 0, 'directory')
                            sheet.write_string(row, 1, pth)
                        else:
                            sheet.write_string(row, 3, name)
                    # there really is no 'total' data for any file or directory
                    printDataRow(f)
                    row += 1
                    return 1

                for f in sorted(scopeList):
                    visitScope(f)

                insertStats(genhtmlKeys, sawData, sumRow, maxRow, avgRow,
                            devRow, begin, row - 1, 3)

                # observed parallelism:  the per-object times summed, over the
                #   elapsed total.  Which column that sum is in is which column
                #   the per-object total landed in, and that depends on which of
                #   the per-object keys this profile recorded at all - so ask the
                #   key list which was laid out rather than count columns here:
                #   column 4 is the first of them, which is the right one only
                #   for a profile which has them all.  A report which recorded
                #   'source' but no 'file' divided the time spent reading the
                #   source by the elapsed total of the whole report.
                # That elapsed total can be missing too, from a profile truncated
                #   before it was written or with something unreadable under the
                #   key:  then there is no cell to divide by and none to write
                #   the result beside, so there is no figure - see the lcov
                #   layout above, which has always checked this.  Dividing by a
                #   cell which was never written used to raise here and take the
                #   sheet, the profiles after it and the workbook with it.
                sumCol = (3 + genhtmlKeys.index(scopeKey)
                          if scopeKey in genhtmlKeys else None)
                if totalRow is not None and sumCol is not None:
                    overallParallelism = "+%(from)s/%(total)s" % {
                        'from': xl_rowcol_to_cell(sumRow, sumCol),
                        'total': total,
                        }
                    sheet.write_formula(totalRow, 2, overallParallelism,
                                        twoDecimal)
                continue

            elif tool == 'html2lcov':

                # html2lcov is single-process;  its profile records a few scalar
                #   phase timings plus per-item timing dicts:
                #     aggregate                  - merge the saved .info file(s)
                #     source[srcpath]            - scrape each HTML source page
                #     check_consistency[srcpath] - per-file consistency check
                #     diff[relpath]              - diff each current file
                #     parse[infofile]            - read each saved .info
                #     append[infofile]           - merge each .info into the total
                #   ('total' was already written above.)
                # Modeled on the geninfo branch:  scalar keys, then per-item
                #   data tables ('elementSection') with total/max/avg/stddev
                #   stat rows and the same conditional highlighting.

                for k in ('aggregate',):
                    if k not in data:
                        continue
                    sheet.write_string(row, 0, k)
                    try:
                        sheet.write_number(row, 1, float(data[k]), twoDecimal)
                    except (TypeError, ValueError):
                        # ..and report a value which cannot be written, rather
                        #   than dropping it along with its row and letting the
                        #   next thing written overwrite the label
                        print("Warning: %s: unable to write %s for %s" % (
                            name, str(data[k]), k))
                    row += 1

                # emit each section that has data - see 'elementSection',
                #   which is the per-item table shared with the lcov sheet
                sections = (('source', ('source', 'check_consistency')),
                            ('diff', ('diff',)),
                            ('info', ('parse', 'append')))
                # the index of those tables, if this sheet needs one - a section
                #   with no data at all is not written
                row = planTables(row, [(typename, len(elementIds(keylist)))
                                       for typename, keylist in sections
                                       if elementIds(keylist)])
                for typename, keylist in sections:
                    row = elementSection(typename, keylist, row)
                continue

            # A profile from a tool there is no layout for:  write what can be
            #   recognized by shape alone - a number as a labelled row, a hash of
            #   numbers as a flat two-column list - and say so for anything else,
            #   so that a profile key nothing here knows about is noticed rather
            #   than silently dropped.
            # Which of the two lists names a key does not decide which shape it
            #   is written as:  a key has either shape depending on how the run
            #   was invoked - 'lcov --extract' records one 'parse' number where a
            #   normal run records one per input file - and writing a hash as a
            #   number, or a number as a hash, raised and took the whole run with
            #   it.
            for k in data:
                if k in ('config', 'overall', 'total',
                         'memory', 'memoryPeak'):
                    # written above, not as a timing table
                    continue
                if k not in genericScalarKeys and k not in genericTableKeys:
                    print("not sure what to do with %s" % (k))
                elif isinstance(data[k], dict):
                    sheet.write_string(row, 0, k)
                    d = data[k]
                    if not d:
                        # the label keeps its row even with nothing under it -
                        #   the sheet says the key was recorded and empty -
                        #   rather than being overwritten by the next key
                        row += 1
                    for n in sorted(d.keys()):
                        sheet.write_string(row, 1, n)
                        try:
                            sheet.write_number(row, 2, float(d[n]), twoDecimal)
                        except (TypeError, ValueError):
                            print("Warning: %s: unable to write %s for [%s][%s]" %(name, str(d[n]), k, n))
                        row += 1;
                else:
                    sheet.write_string(row, 0, k)
                    try:
                        sheet.write_number(row, 1, float(data[k]), twoDecimal)
                    except (TypeError, ValueError):
                        print("Warning: %s: unable to write %s for %s" % (
                            name, str(data[k]), k))
                    row += 1

        if summarySheet:
            if len(geninfoSheets) < 2:
                # ..and open the workbook on the one data sheet there is, if
                #   there is one at all:  every input can turn out to be
                #   unreadable, and the empty workbook that asks for is a better
                #   answer than crashing over the sheet which was never written
                if activeSheet is not None:
                    activeSheet.activate()
                summarySheet.hide()

            # insert the average and variance data, and colorize each case
            #   against them - over every column of the table, driven off the
            #   same layout the data was written from, so the statistics cannot
            #   land on a different column than the data they describe.
            #   (there will not be any such data if we didn't run geninfo)
            if geninfoSheets:
                lastSummaryRow = firstSummaryRow + len(geninfoSheets) - 1
                avgRow = 1
                devRow = 2
                firstCol = 1
                lastCol = firstCol + len(summaryColumns) - 1
                for col in range(firstCol, lastCol + 1):
                    f = xl_rowcol_to_cell(firstSummaryRow, col)
                    t = xl_rowcol_to_cell(lastSummaryRow, col)
                    avg = "+AVERAGE(%(from)s:%(to)s)" % {
                        'from': f,
                        'to': t,
                    }
                    summarySheet.write_formula(avgRow, col, avg, twoDecimal)
                    dev = "+STDEV(%(from)s:%(to)s)" % {
                        'from': f,
                        'to': t,
                    }
                    summarySheet.write_formula(devRow, col, dev, twoDecimal)
                insertConditional(summarySheet, avgRow, devRow,
                                  firstSummaryRow, firstCol, lastSummaryRow,
                                  lastCol)

        # the glossary:  one boldface row per section, then one row per term -
        #   the term in column A and what it means in column B.  Written from
        #   GLOSSARY so that the text lives with the key lists it describes
        #   rather than in a separate document which nothing keeps in step, and
        #   restricted to the metrics this workbook shows - see glossarySections
        glossarySheet.set_column(0, 0, 24)
        glossarySheet.set_column(1, 1, 100)
        row = 0
        glossarySheet.write_string(row, 0, 'metric', self.formats['title'])
        glossarySheet.write_string(row, 1, 'meaning', self.formats['title'])
        row += 2
        for section, sectionTool, terms in glossarySections():
            glossarySheet.write_string(row, 0, section,
                                       self.formats['glossary_section'])
            row += 1
            for term, keys, meaning in terms:
                glossarySheet.write_string(row, 0, term,
                                          self.formats['glossary_term'])
                glossarySheet.write_string(row, 1, meaning,
                                          self.formats['glossary_text'])
                # where the column titles which report these keys link to.  An
                #   entry with no keys describes the layout rather than a
                #   metric, and so is nothing's target.  Should two entries of
                #   one section claim the same key, the first of them takes it.
                for k in keys:
                    glossaryRows.setdefault((sectionTool, k), row)
                row += 1
            row += 1

        # ..and now that every entry's row is known, the column titles which
        #   point at them
        resolveGlossaryLinks()

        s.close()

if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter, epilog="""
Simple utility to turn genhtml/geninfo/lcov "profile" JSON output files into a somewhat readable spreadsheet for easier analysis.

Example usage:
  $ spreadsheet.py -o foo.xlsx data.json data2.json data3.json ...
""")

    parser.add_argument("-o", dest='out', action='store',
                        default='stats.xlsx',
                        help='save excel to file')
    parser.add_argument("--threshold", dest='thresholdPercent', type=float,
                        help="difference from average smaller than this percentage is ignored (not colorized).  Default %0.2f" % (thresholdPercent))
    parser.add_argument("--low", dest='devMinThreshold', type=float,
                        help="difference from average larger than this * stddev colored yellow.  Default: %0.2f" %(devMinThreshold))
    parser.add_argument("--high", dest='devMaxThreshold', type=float,
                        help="difference from average larger than this * stddev colored red.  Default: %0.2f" %(devMaxThreshold))
    parser.add_argument('-v', '--verbose', dest='verbose', default=0,
                        action='count', help='verbosity of report: more data');
    parser.add_argument('--show-filter', dest='show_filter', default=False,
                        action='store_true', help='include filter keys in table');

    # the profiles to read.  'nargs=*' rather than argparse.REMAINDER:
    #   REMAINDER stops parsing at the first thing which is not an option, so
    #   every flag after the first profile name - which is where a shell history
    #   naturally leaves one - was silently collected as a filename and then
    #   reported as unparsable.
    parser.add_argument('files', nargs='*')

    try:
        args = parser.parse_args()
    except IOError as err:
        print(str(err))
        sys.exit(2)

    # The colorizing thresholds are read from module scope - by the conditional
    #   formatting rules of every table and by the summary sheet's colour
    #   legend - so an option which is only parsed into 'args' does nothing at
    #   all, which is what each of these three did.  Take the option where it
    #   was given and leave the default where it was not.
    if args.thresholdPercent is not None:
        thresholdPercent = args.thresholdPercent
    if args.devMinThreshold is not None:
        devMinThreshold = args.devMinThreshold
    if args.devMaxThreshold is not None:
        devMaxThreshold = args.devMaxThreshold

    GenerateSpreadsheet(args.out, args.files, args)
