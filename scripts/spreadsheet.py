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
from functools import cmp_to_key

devMinThreshold = 1.5
devMaxThreshold = 2.0
thresholdPercent = 0.15

class GenerateSpreadsheet(object):

    def __init__(self, excelFile, files, args):

        s = xlsxwriter.Workbook(excelFile)

        # keep a list of sheets so we can insert a summary..
        geninfoSheets = []
        summarySheet = s.add_worksheet("capture_summary") if 1 < len(files) else None

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
        geninfoChunkKeys = ('work', 'chunk', 'queue', 'child', 'process',
                            'undump', 'merge', *memoryKeys)
        geninfoSpecialKeys = ('total', 'parallel', 'filter', 'write', 'history')

        # keys related to filtering
        filterKeys = ('filt_chunk', 'filt_queue',  'filt_child', 'filt_proc', 'filt_undump', 'filt_merge', 'derive_end')
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
            'highlight': s.add_format({'bg_color': 'yellow'}),
            'danger': s.add_format({'bg_color': 'red'}),
            'good': s.add_format({'bg_color': 'green'}),
        }
        intFormat = self.formats['intFormat']
        twoDecimal = self.formats['twoDecimal']
        stats_title = self.formats['stats_title']
        title = self.formats['title']

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

        # rows below a sub-table's title row that its total and average land on
        totalOffset = 1 + statLabels.index('total')
        avgOffset = 1 + statLabels.index('avg')

        # empty rows before each sub-table, to set it apart from whatever
        #   precedes it
        sectionGap = 2

        def sectionStart(row):
            # the title row of the next sub-table, given the first unused row
            return row + sectionGap

        def writeTitleRow(row, typename, keylist, col=2):
            # the sub-table title row:  its name (if it has one) in column A and
            #   one column title per key from 'col' on, and return the row the
            #   statistics start at.  In the 'title' format - boldface - to set
            #   the titles apart from the data below them.
            if typename is not None:
                sheet.write_string(row, 0, typename, title)
            for k in keylist:
                sheet.write_string(row, col, k, title)
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
                           required=(), intKeys=()):
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
            # Returns (first data row, last data row, first unused row) - the
            #   caller needs the data range to reference the segment column.
            row = writeTitleRow(sectionStart(row), typename, keylist)
            sumRow, maxRow, avgRow, devRow = (row, row + 1, row + 2, row + 3)
            row = writeStatLabels(row)

            dataStart = row
            sawData = {}
            for id in ids:
                label = 'segment %s' % (id)
                sheet.write_string(row, 1, label)
                d = values[id]
                col = 2
                for k in keylist:
                    if k not in d:
                        if k in required:
                            print("Warning: %s: no %s for %s" % (
                                name, k, label))
                    else:
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

        activeSheet = None
        for name in files:
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

            try:
                parallel = data['config']['maxParallel']
            except:
                parallel = 0

            row = 0
            sheet.write_string(row, 0, name)
            row += 1
            sheet.write_string(row, 0, 'config')
            for n in sorted(data['config'].keys()):
                try:
                    sheet.write_string(row, 1, n)
                    if n in ("tool", 'cmdLine', 'date', ):
                        sheet.write_string(row, 2, data['config'][n])
                    else:
                        sheet.write_number(row, 2, data['config'][n], intFormat)
                    row += 1
                except:
                    # old file format..skip it
                    pass

            if tool == 'geninfo':
                for k in ('chunkSize', 'nChunks', 'nFiles', 'interval'):
                    try:
                        sheet.write_number(row, 2, data[k], intFormat);
                        sheet.write_string(row, 1, k)
                        row += 1
                    except:
                        pass

            # every tool records its whole-run elapsed time under 'total'.
            #   'overall' is the key genhtml used for the same thing in
            #   profiles written by older releases.
            for k in ('total', 'overall'):
                if k in data:
                    sheet.write_string(row, 0, 'total')
                    sheet.write_number(row, 1, data[k], twoDecimal)
                    total = xl_rowcol_to_cell(row, 1)
                    totalRow = row
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
                    col += 1
                # there is one row of data, and it is not one job's peak but
                #   the largest seen anywhere in the process tree
                sheet.write_string(row + 1, 1, 'max', stats_title)
                row += 2

            if tool == 'lcov':
                # is this a parallel execution?
                try:
                    segments = data['config']['segments']

                    # 'parse'/'append' are not kept per segment (a child folds
                    #   them into the parent's own data), so they are not
                    #   'required' - nor is memory, which an older profile or a
                    #   platform that does not expose peak memory will lack.
                    segmentKeys = ('total', 'merge', 'undump', 'parse',
                                   'append', *memoryKeys)
                    values = {}
                    for seg in range(segments):
                        try:
                            d = data[seg]
                        except:
                            d = data[str(seg)]
                        # this segment's peak memory is not stored with its
                        #   timing data:  it is keyed by job id in the profile
                        #   'memory' section - memory{aggregate_N} for segment
                        #   N - so copy it in and let it be written like any
                        #   other key.
                        d.update(peakMemoryMB(data, 'aggregate_%d' % (seg)))
                        values[seg] = d
                    dataStart, dataEnd, row = segmentSection(
                        row, 'segments', range(segments), segmentKeys, values,
                        required=('total', 'merge', 'undump'))

                    # observed parallelism:  the segments' wall-clock summed,
                    #   over the elapsed total
                    totalCol = 2 + segmentKeys.index('total')
                    effectiveParallelism = "+SUM(%(from)s:%(to)s)/%(total)s" % {
                        'from': xl_rowcol_to_cell(dataStart, totalCol),
                        'to': xl_rowcol_to_cell(dataEnd, totalCol),
                        'total': total,
                    }
                    sheet.write_formula(totalRow, 3, effectiveParallelism, twoDecimal)


                except Exception as err:

                    # not segmented - just print everything...
                    for k in ('total', 'merge', 'undump'):
                        sheet.write_string(row, 1, k)
                        val = 'NA'
                        try:
                            val = data[k]
                            sheet.write_number(row, 2, float(val), twoDecimal)
                        except:
                            print("Warning: %s: unable to write %s for lcov[%s]" % (name, str(val), k))
                            row += 1
                    for k in ('parse', 'append'):
                        try:
                            d2 = data[k]
                            sheet.write_string(row, 1, k)
                            for f in sorted(d2.keys()):
                                sheet.write_string(row, 2, f)
                                try:
                                    sheet.write_number(row, 3, float(d2[f]), twoDecimal)
                                except:
                                    print("Warning: %s: unable to write %s for lcov[%s][%s]" % (name, str(d2[f]), k, f))
                            row += 1
                        except:
                            print("Warning: %s: failed to find key '%s'" %(name, k))

                # go on to the next file
                continue

            elif tool == 'geninfo':

                summaryKeys = (*geninfoSpecialKeys, *geninfoChunkKeys, *geninfoKeys)
                if args.show_filter:
                    summaryKeys = (*geninfoSpecialKeys, *geninfoChunkKeys, *geninfoKeys, *filterKeys)
                if summarySheet:
                    # first one - add titles, etc
                    if len(geninfoSheets) == 0:
                        summarySheet.write_string(1, 0, "average", title)
                        summarySheet.write_string(2, 0, "stddev", title)
                        titleRow = 0
                        summarySheet.write_string(titleRow, 0, "case", title)
                        col = 1
                        for k in summaryKeys:
                            if k in ('order',):
                                continue
                            summarySheet.write_string(titleRow, col, k, title)
                            col += 1
                            if k in geninfoSpecialKeys:
                                continue
                            summarySheet.write_string(titleRow, col, k + ' avg', title)
                            col += 1
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
                # already inserted the ''total' entry
                specialsStart = row - 1
                for k in geninfoSpecialKeys[1:]:
                    try:
                        sheet.write_string(row, 0, k)
                        sheet.write_number(row, 1, data[k], twoDecimal)
                    except:
                        pass
                    row += 1;

                sawData = {}
                sawData['total'] = 0
                sheet.write_string(row, 0, 'find')
                row += 1
                for dirname in sorted(data['find'].keys()):
                    sheet.write_string(row, 1, dirname)
                    sheet.write_number(row, 2, data['find'][dirname], twoDecimal)
                    row += 1

                def dataSection(typename, elements, keylist, sectionRow):
                    # one contiguous table per section, starting at 'sectionRow':
                    #   the boldface title row naming the section in column A,
                    #   the italic statistics rows over the data - total, max,
                    #   avg, stddev - then one row per element:  its id in column
                    #   B and one value per key from column C on.  The data cells
                    #   are colorized against the average and stddev just above
                    #   them, so the statistics have to be adjacent to the data
                    #   they describe.
                    # Returns the first unused row after the section.
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
                            try:
                                v = data[key][id]
                                if key in ('order',):
                                    sheet.write_number(row, col, v, intFormat)
                                else:
                                    sheet.write_number(row, col, v, twoDecimal)
                                try:
                                    sawData[key] += 1
                                except:
                                    sawData[key] = 1

                            except:
                                pass
                            col += 1
                        row += 1

                    dataEnd = row - 1

                    insertStats(keylist, sawData, sumRow, maxRow, avgRow,
                                devRow, dataStart, dataEnd, 2)
                    return dataEnd + 1

                # the row each section's title lands on, remembered so the
                #   summary sheet can find that section's total and average rows
                #   - see statLabels.  'filter' is optional, and the chunk table
                #   is absent from a serial capture, in which case the file table
                #   takes its place.
                chunkSectionRow = sectionStart(row)
                fileSectionRow = chunkSectionRow
                filterSectionRow = None
                # the observed parallelism is that first section's total time
                #   over the elapsed total;  column C for the chunk table, or
                #   column D ('file') when a serial capture leaves only files
                parallelSumRow = chunkSectionRow + totalOffset
                parallelSumCol = 3

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
                                      chunkSectionRow)
                    fileSectionRow = sectionStart(row)
                    parallelSumCol = 2
                except:
                    # no chunk data - so just insert file data
                    pass


                def cmpFile(a, b):
                    idA = int(data['order'][a])
                    idB = int(data['order'][b])
                    if idA < idB:
                        return 1
                    else:
                        return 0 if idA == idB else -1

                try:
                    row = dataSection('files', sorted(data['file'].keys(), key=cmp_to_key(cmpFile)),
                                      geninfoKeys, fileSectionRow)
                except:
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


                effectiveParallelism = "+%(sum)s/%(total)s" % {
                    'sum': xl_rowcol_to_cell(parallelSumRow, parallelSumCol),
                    'total': total,
                }
                sheet.write_formula(specialsStart + geninfoSpecialKeys.index('parallel'),
                                    1, effectiveParallelism, twoDecimal)

                if summarySheet:
                    summarySheet.write_string(summaryRow, 0, name)
                    # href to the corresponding page..
                    summarySheet.write_url(summaryRow, 0, "internal:'%s'!A1" % (
                        sheet.get_name()))
                    summaryCol = 1;

                    sheetRef = "='" + sheet.get_name() + "'!"

                    # insert total time and observed parallelism for this
                    # geninfo call
                    specialsRow = specialsStart
                    for k in geninfoSpecialKeys:
                        cell  = xl_rowcol_to_cell(specialsRow, 1)
                        summarySheet.write_formula(summaryRow, summaryCol,
                                                   sheetRef + cell, twoDecimal)
                        summaryCol += 1
                        specialsRow += 1

                    # now label this sheet's columns
                    #  and also insert reference to total time and average time
                    #  for each step into the summary sheet - each section's
                    #  total and average sit at a fixed offset below its title
                    #  row;  see totalOffset/avgOffset.
                    sections = [(geninfoChunkKeys, chunkSectionRow),
                                (geninfoKeys, fileSectionRow),]
                    if filterSectionRow is not None:
                        sections.append((filterKeys, filterSectionRow))
                    for keys, sectionRow in (sections):
                        totRow = sectionRow + totalOffset
                        avgRow = sectionRow + avgOffset
                        col = 2
                        for k in keys:
                            if k not in ('order',):
                                sum = xl_rowcol_to_cell(totRow, col)
                                summarySheet.write_formula(summaryRow, summaryCol,
                                                           sheetRef + sum, twoDecimal)
                                summaryCol +=1
                                avg = xl_rowcol_to_cell(avgRow, col)
                                summarySheet.write_formula(summaryRow, summaryCol,
                                                           sheetRef + avg, twoDecimal)
                                summaryCol +=1
                            col += 1
                continue

            elif tool == 'genhtml':

                for k in ('parse_source', 'parse_diff',
                          'parse_current', 'parse_baseline',
                          'history'):
                    if k in data:
                        try:
                            sheet.write_string(row, 0, k)
                            sheet.write_number(row, 1, data[k], twoDecimal)
                            row += 1
                        except:
                            pass # 'history' key might not be there

                # total: time from start to end of the particular unit -
                # child: time from start to end of child process
                # annotate: annotate callback time (if called)
                # load:  load source file (if no annotation)
                # synth:  generate file content (no annotation and no no file found)
                # categorize: compute owner/date bins, differenntial categories
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

                # the per-object table has no section name of its own
                row = writeTitleRow(sectionStart(row), None, genhtmlKeys, 3)
                sumRow, maxRow, avgRow, devRow = (row, row + 1, row + 2,
                                                  row + 3)
                row = writeStatLabels(row, 2)

                #print(" ".join(data.keys()))
                try:
                    if 'file' in data:
                        scopeList = data['file'].keys()
                    else:
                        scopeList = data['html'].keys()
                except:
                    print("%s:  incomplete data - skipping" % (name))
                    continue
                begin = row
                sawData = {}
                #sawData['total'] = 0
                def printDataRow(name):
                    col = 4
                    nonlocal row
                    for k in genhtmlKeys[1:]:
                        if (k in data and
                            name in data[k]):
                            try:
                                sheet.write_number(row, col, float(data[k][name]), twoDecimal)
                                if k in sawData:
                                    sawData[k] += 1
                                else:
                                    sawData[k] = 1
                            except:
                                print("Warning: %s: unable to write %s" %(name, data[k][name]))
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

                overallParallelism = "+%(from)s/%(total)s" % {
                    'from': xl_rowcol_to_cell(sumRow, 4),
                    'total': total,
                    }
                sheet.write_formula(totalRow, 2, overallParallelism, twoDecimal);
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
                #   data tables (dataSection-style) with total/max/avg/stddev
                #   stat rows and the same conditional highlighting.

                for k in ('aggregate',):
                    if k in data:
                        try:
                            sheet.write_string(row, 0, k)
                            sheet.write_number(row, 1, data[k], twoDecimal)
                            row += 1
                        except:
                            pass

                # per-item table writer, mirroring the geninfo 'dataSection':
                #   two empty rows, the boldface title row, the italic
                #   total/max/avg/stddev statistics rows, then one row per item
                #   id with one column per key, and the same conditional
                #   formatting over the data rows.
                # Returns the first unused row after the section.
                def h2lSection(typename, keylist, sectionRow):
                    ids = set()
                    for key in keylist:
                        if key in data and isinstance(data[key], dict):
                            ids.update(data[key].keys())

                    r = writeTitleRow(sectionStart(sectionRow), typename,
                                      keylist)
                    sumRow, maxRow, avgRow, devRow = (r, r + 1, r + 2, r + 3)
                    r = writeStatLabels(r)
                    dataStart = r

                    sawData = {}
                    for id in sorted(ids):
                        col = 1
                        sheet.write_string(r, col, id)
                        col += 1
                        for key in keylist:
                            try:
                                sheet.write_number(r, col, float(data[key][id]),
                                                   twoDecimal)
                                sawData[key] = sawData.get(key, 0) + 1
                            except:
                                pass
                            col += 1
                        r += 1
                    dataEnd = r - 1

                    insertStats(keylist, sawData, sumRow, maxRow, avgRow,
                                devRow, dataStart, dataEnd, 2)
                    return dataEnd + 1

                # emit each section that has data
                sections = (('source', ('source', 'check_consistency')),
                            ('diff', ('diff',)),
                            ('info', ('parse', 'append')))
                for typename, keylist in sections:
                    if not any(k in data and data[k] for k in keylist):
                        continue
                    row = h2lSection(typename, keylist, row)
                continue

            for k in data:
                if k in ('parse_source', 'parse_diff',
                         'emit', 'parse_current', 'parse_baseline'):
                    sheet.write_string(row, 0, k)
                    sheet.write_number(row, 1, data[k], twoDecimal)
                    row += 1
                elif k in ('file', 'dir', 'load', 'synth', 'check_version',
                           'annotate', 'parse', 'append', 'segment', 'undump',
                           'merge', 'gen_info', 'data', 'graph', 'find'):
                    sheet.write_string(row, 0, k)
                    d = data[k]
                    for n in sorted(d.keys()):
                        sheet.write_string(row, 1, n)
                        try:
                            sheet.write_number(row, 2, float(d[n]), twoDecimal)
                        except:
                            print("Warning: %s: unable to write %s for [%s][%s]" %(name, str(d[n]), k, n))
                        row += 1;
                    continue
                elif k in ('config', 'overall', 'total',
                           'memory', 'memoryPeak'):
                    # memory data is written above, not as a timing table
                    continue
                else:
                    print("not sure what to do with %s" % (k))

        if summarySheet:
            if len(geninfoSheets) < 2:
                activeSheet.activate()
                summarySheet.hide()

            # insert the average and variance data...
            #  (there will not be any such data if we didn't run geninfo)
            try:
                col = 1
                lastSummaryRow = firstSummaryRow + len(geninfoSheets) - 1
                avgRow = 1
                devRow = 2
                firstCol = col
                for k in (*geninfoChunkKeys, *geninfoKeys):
                    if k in ('order',):
                        continue
                    for j in ('sum', 'avg'):
                        f = xl_rowcol_to_cell(firstSummaryRow, col)
                        t = xl_rowcol_to_cell(lastSummaryRow, col)
                        avg = "+AVERAGE(%(from)s:%(to)s)" % {
                            'from': f,
                            'to': t,
                        }
                        summarySheet.write_formula(avgRow, col, avg, twoDecimal)
                        avgCell = xl_rowcol_to_cell(avgRow, col)
                        dev = "+STDEV(%(from)s:%(to)s)" % {
                            'from': f,
                            'to': t,
                        }
                        summarySheet.write_formula(devRow, col, dev, twoDecimal)
                        col += 1
                insertConditional(summarySheet, avgRow, devRow,
                                  firstSummaryRow, firstCol, lastSummaryRow, col -1)
            except:
                pass
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

    parser.add_argument('files', nargs=argparse.REMAINDER)

    try:
        args = parser.parse_args()
    except IOError as err:
        print(str(err))
        sys.exit(2)

    GenerateSpreadsheet(args.out, args.files, args)
