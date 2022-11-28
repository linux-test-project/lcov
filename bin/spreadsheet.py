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

class GenerateSpreadsheet(object):

    def __init__(self, excelFile, files):

        s = xlsxwriter.Workbook(excelFile)

        # keep a list of sheets so we can insert a summary..
        geninfoSheets = []
        summarySheet = s.add_worksheet("geninfo_summary")
        geninfoKeys = ('process',  'parse', 'append', 'child', 'exec', 'merge', 'undump')

        self.formats = {
            'twoDecimal': s.add_format({'num_format': '0.00'}),
            'intFormat': s.add_format({'num_format': '0'}),
            'title': s.add_format({'bold': True,
                                   'align': 'center',
                                   'valign': 'vcenter',
                                   'text_wrap': True}),
            'italic': s.add_format({'italic': True,
                                    'align': 'center',
                                    'valign': 'vcenter'}),
            'highlight': s.add_format({'bg_color': 'yellow'}),
            'danger': s.add_format({'bg_color': 'red'}),
        }
        intFormat = self.formats['intFormat']
        twoDecimal = self.formats['twoDecimal']

        def insertStats(keys, sawData, sumRow, avgRow, devRow, beginRow, endRow, col):
            firstCol = col
            col -= 1
            for key in keys:
                col += 1
                f = xl_rowcol_to_cell(beginRow, col)
                t = xl_rowcol_to_cell(endRow, col)

                if key not in sawData:
                    continue
                sum = "+SUM(%(from)s:%(to)s)" % {
                    "from" : f,
                    "to": t
                }
                sheet.write_formula(sumRow, col, sum, twoDecimal)
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

                # absolute row, relative column
                avgCell = xl_rowcol_to_cell(avgRow, col, True, False)
                devCell = xl_rowcol_to_cell(devRow, col, True, False)
                # relative row, relative column
                dataCell = xl_rowcol_to_cell(beginRow, col, False, False)
                # absolute value of differnce from the average
                diff = 'ABS(%(cell)s - %(avg)s)' % {
                    'cell' : dataCell,
                    'avg' : avgCell,
                }

                # min difference is difference > 15% of average
                #  only look at positive difference:  taking MORE than average time
                threshold = '(%(cell)s - %(avg)s) > (%(percent)s * %(avg)s)' % {
                    'cell' : dataCell,
                    'avg' : avgCell,
                    'percent': "0.15",
                }

                # cell not blank and difference > 2X std.dev and > 15% of average
                dev2 = '=AND(NOT(OR(ISBLANK(%(cell)s),ISBLANK(%(dev)s))), %(diff)s > (2.0 * %(dev)s), %(threshold)s)' % {
                    'diff' : diff,
                    'threshold' : threshold,
                    'cell' : dataCell,
                    'avg' : avgCell,
                    'dev' : devCell,
                }
                dev1 = '=AND(NOT(OR(ISBLANK(%(cell)s),ISBLANK(%(dev)s))), %(diff)s >  %(dev)s, %(diff)s <= (2.0 * %(dev)s), %(threshold)s) ' % {
                    'diff' : diff,
                    'threshold' : threshold,
                    'cell' : dataCell,
                    'avg' : avgCell,
                    'dev' : devCell,
                }
                # yellow if between 1 and 2 standard deviations away
                sheet.conditional_format(firstRow, col, endRow, col,
                                         { 'type': 'formula',
                                           'criteria': dev1,
                                           'format' : self.formats['highlight'],
                                         })
                # red if more than 2 2 standard deviations away
                sheet.conditional_format(firstRow, col, endRow, col,
                                         { 'type': 'formula',
                                           'criteria': dev2,
                                           'format' : self.formats['danger'],
                                         })

        for name in files:
            try:
                with open(name) as f:
                    data = json.load(f)
            except Exception as err:
                print("%s: unable to parse: %s" % (name, str(err)))

            try:
                tool = data['config']['tool']
            except:
                tool = 'unknown'
                print("%s: unknown tool" %(name))

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
            try:
                sheet.write_string(row, 0, 'config')
                for n in sorted(data['config'].keys()):
                    sheet.write_string(row, 1, n)
                    if n in ("tool", ):
                        sheet.write_string(row, 1, data['config'][n])
                    else:
                        sheet.write_number(row, 2, data['config'][n], intFormat)
                    row += 1
            except:
                # old file format..skip it
                pass

            for k in ('total', 'overall'):
                if k in data:
                    sheet.write_string(row, 0, 'total')
                    sheet.write_number(row, 1, data[k], twoDecimal)
                    total = xl_rowcol_to_cell(row, 1)
                    totalRow = row
                    row += 1

            if tool == 'lcov':
                # is this a parallel execution?
                try:
                    segments = data['config']['segments']

                    effectiveParallelism = ""
                    sep = "+("
                    for seg in range(segments):
                        sheet.write_string(row, 0, 'segment %d' % (seg))
                        try:
                            d = data[seg]
                        except:
                            d = data[str(seg)]

                        start = row
                        for k in ('total', 'merge', 'undump'):
                            sheet.write_string(row, 1, k)
                            try:
                                sheet.write_number(row, 2, float(d[k]), twoDecimal)
                                if k == 'total':
                                    effectiveParallelism += sep + xl_rowcol_to_cell(row, 2)
                                    sep = "+"
                            except:
                                print("%s: failed to write %s for lcov[seg %d][%s]" % (
                                    name, str(d[k]) if k in d else "??", seg, k))
                            row += 1
                        begin = row
                        for k in ('parse', 'append'):
                            try:
                                # don't crash on partially corrupt profile data
                                d2 = d[k]
                                sheet.write_string(row, 1, k)
                                for f in sorted(d2.keys()):
                                    sheet.write_string(row, 2, f)
                                    try:
                                        sheet.write_number(row, 3, float(d2[f]), twoDecimal)
                                    except:
                                        print("%s: failed to write %s for lcov[seg %d][%s][$s]" % (name, str(d2[f]), seg, k, f))
                                row += 1
                            except:
                                print("%s: failed to write %s for lcov[seg %d]" % (name, k, seg))
                    effectiveParallelism += ")/%(total)s" % {
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
                            print("%s: failed to write %s for lcov[%s]" % (name, str(val), k))
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
                                    print("%s: failed to write %s for lcov[%s][$s]" % (name, str(d2[f]), k, f))
                            row += 1
                        except:
                            print("%s: failed to find key '%s'" %(name, k))

                # go on to the next file
                continue

            elif tool == 'geninfo':

                if len(geninfoSheets) == 0:
                    # first one - add titles, etc
                    title = self.formats['title']
                    summarySheet.write_string(1, 0, "average", title)
                    summarySheet.write_string(2, 0, "stddev", title)
                    titleRow = 0
                    summarySheet.write_string(titleRow, 0, "case", title)
                    col = 1
                    for k in ('total', *geninfoKeys):
                        summarySheet.write_string(titleRow, col, k, title)
                        col += 1
                        if k == 'total':
                            summarySheet.write_string(titleRow, col, 'parallel', title)
                        else:
                            summarySheet.write_string(titleRow, col, k + ' avg', title)
                        col += 1
                    summarySheet.write_string(3, 0, "Value between [1,2) standard deviations from average colored yellow", self.formats['highlight'])
                    summarySheet.write_string(4, 0, "Value between more than 2 standard deviations from average colored red", self.formats['danger'])
                    firstSummaryRow = 6
                    
                # want rows for average and variance - leave a blank row
                summaryRow = firstSummaryRow + len(geninfoSheets)
                geninfoSheets.append(sheet)
                
                d = data['gen_info']
                for k in ('emit', ):
                    try:
                        sheet.write_number(row, 3, data[k], twoDecimal)
                        sheet.write_string(row, 2, k)
                        row += 1
                    except:
                        pass

                sawData = {}
                sawData['total'] = 0
                summarySheet.write_string(summaryRow, 0, name)
                # href to the corresponding page..
                summarySheet.write_url(summaryRow, 0, "internal:'%s'!A1" % (
                    sheet.get_name()))
                summaryCol = 1;
                
                sheetRef = "='" + sheet.get_name() + "'!"
                
                # insert total time and observed parallelism for this
                # geninfo call
                sum = xl_rowcol_to_cell(totalRow, 1)
                summarySheet.write_formula(summaryRow, summaryCol,
                                           sheetRef + sum)
                summaryCol += 1
                parallel = xl_rowcol_to_cell(totalRow, 2)
                summarySheet.write_formula(summaryRow, summaryCol,
                                           sheetRef + parallel)
                summaryCol += 1
                col = 4;
                # now label this sheet's columns
                #  and also insert reference to total time and average time
                #  for each step into the summary sheet.
                for k in geninfoKeys:
                    sheet.write_string(row, col, k)
                    sum = xl_rowcol_to_cell(row+1, col)
                    summarySheet.write_formula(summaryRow, summaryCol,
                                               sheetRef + sum)
                    summaryCol +=1
                    avg = xl_rowcol_to_cell(row+2, col)
                    summarySheet.write_formula(summaryRow, summaryCol,
                                               sheetRef + avg)
                    summaryCol +=1
                    col += 1
                row += 1
                sumRow = row
                sheet.write_string(row, 2, "total")
                row += 1
                avgRow = row
                sheet.write_string(row, 2, "average")
                row += 1
                devRow = row
                sheet.write_string(row, 2, "stddev")
                row += 1

                firstRow = row + 2
                for dirname in sorted(d.keys()):
                    sheet.write_string(row, 0, 'gen_info')
                    sheet.write_string(row, 1, dirname)
                    sheet.write_number(row, 2, d[dirname], twoDecimal)
                    row += 1

                    start = row
                    sheet.write_string(row, 2, 'find')
                    sheet.write_number(row, 3, data['find'][dirname], twoDecimal)
                    row += 1

                    for type in ('data', 'graph'):
                        if type not in data:
                            continue

                        d2 = data[type][dirname]
                        for f in sorted(d2.keys()):
                            d3 = d2[f]
                            fname = f[len(dirname):]
                            sheet.write_string(row, 2, fname)
                            try:
                                # this is the total time from fork in the parent
                                #  to end of child merge
                                sheet.write_number(row, 3, float(d3), twoDecimal)
                                sawData['total'] += 1
                            except:
                                print("%s: failed to write %s for geninfo[%s][%s]" % (name, str(d3), type, f))
                            col = 4
                            # process: time from immediately before fork in parent
                            #          to immediately after 'process_one_file' in
                            #          child (can't record 'dumper' call time
                            #          because that also dumps the profile
                            # child:   time from child coming to life after fork
                            #          to immediately afer 'process_one_file'
                            # exec: time take to by 'gcov' call
                            # merge: time to merge child process (undump, read
                            #       trace data, append to summary, etc.)
                            # undump: dumper 'eval' call + stdout/stderr recovery
                            # parse: time to read child tracefile.info
                            # append: time to merge that into parent master report

                            for key in geninfoKeys:
                                try:
                                    val = float(data[key][dirname][f])
                                    sheet.write_number(row, col, val, twoDecimal)
                                    if key in sawData:
                                        sawData[key] += 1
                                    else:
                                        sawData[key] = 1
                                except:
                                    pass # no such key
                                col += 1
                            row += 1

                effectiveParallelism = "+%(sum)s/%(total)s" % {
                    'sum': xl_rowcol_to_cell(sumRow, 4),
                    'total': total,
                }
                sheet.write_formula(totalRow, 2, effectiveParallelism, twoDecimal)
                insertStats(geninfoKeys, sawData, sumRow, avgRow, devRow,
                            firstRow, row-1, 4)

                continue

            elif tool == 'genhtml':

                for k in ('parse_source', 'parse_diff',
                          'parse_current', 'parse_baseline'):
                    if k in data:
                        sheet.write_string(row, 0, k)
                        sheet.write_number(row, 1, data[k], twoDecimal)
                        row += 1

                # total: time from start to end of the particular unit -
                # child: time from start to end of child process
                # annotate: annotate callback time (if called)
                # load:  load source file (if no annotation)
                # synth:  generate file content (no annotation and no no file found)
                # categorize: compute owner/date bins, differenntial categories
                # process:  time to generate data and write HTML for file
                # synth:  generate file content (no file found)
                # source:
                genhtmlKeys = ('total', 'child', 'annotate', 'synth', 'categorize', 'source', 'check_version', 'html')
                col = 3
                for k in genhtmlKeys:
                    sheet.write_string(row, col, k)
                    col += 1
                row += 1
                sumRow = row
                sheet.write_string(row, 2, "total")
                row += 1
                avgRow = row
                sheet.write_string(row, 2, "average")
                row += 1
                devRow = row
                sheet.write_string(row, 2, "stddev")
                row += 1

                #print(" ".join(data.keys()))
                try:
                    dirData = data['directory']
                except:
                    dirData = data['dir']
                fileData = data['file']
                begin = row
                sawData = {}
                sawData['total'] = 0
                def printDataRow(name):
                    col = 4
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
                                print("%s: failed to write %s" %(name, data[k][name]))
                        col += 1
                

                for dirname in sorted(dirData.keys()):
                    sheet.write_string(row, 0, "directory")
                    sheet.write_string(row, 1, dirname)
                    sheet.write_number(row, 3, dirData[dirname], twoDecimal)
                    #pdb.set_trace()
                    printDataRow(dirname)
                    row += 1

                    start = row

                    for f in sorted(fileData.keys()):
                        pth, name = os.path.split(f)
                        if pth != dirname:
                            continue
                        sheet.write_string(row, 2, name)
                        sheet.write_number(row, 3, fileData[f], twoDecimal)
                        sawData['total'] += 1
                        printDataRow(f)
                        row += 1

                insertStats(genhtmlKeys, sawData, sumRow, avgRow, devRow, begin,
                           row-1, 3)

                overallParallelism = "+%(from)s/%(total)s" % {
                    'from': xl_rowcol_to_cell(sumRow, 3),
                    'total': total,
                    }
                sheet.write_formula(totalRow,2, overallParallelism, twoDecimal);
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
                            print("%s: failed to write %s for [%s][%s]" %(name, str(d[n]), k, n))
                        row += 1;
                    continue
                elif k in ('config', 'overall', 'total'):
                    continue
                else:
                    print("not sure what to do with %s" % (k))

        if len(geninfoSheets) < 2:
            # can't delete the sheet after creation - but we can hide it
            summarySheet.hide()
        else:
            # insert the average and variance data...
            col = 1
            lastSummaryRow = firstSummaryRow + len(geninfoSheets) - 1
            avgRow = 1
            devRow = 2
            firstCol = col
            for k in ('total', *geninfoKeys):
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

                    # absolute row, relative column
                    avgCell = xl_rowcol_to_cell(avgRow, col, True)
                    devCell = xl_rowcol_to_cell(devRow, col, True)
                    # relative row, relative column
                    dataCell = xl_rowcol_to_cell(firstRow, col)
                    # absolute value of differnce from the average
                    diff = 'ABS(%(cell)s - %(avg)s)' % {
                        'cell' : dataCell,
                        'avg' : avgCell,
                    }
                    # min difference is difference > 15% of average
                    # NOTE:  not using ABS(diff) - so we only colorize larger values
                    threshold = '(%(cell)s - %(avg)s) > (%(percent)s * %(avg)s)' % {
                        'cell' : dataCell,
                        'avg' : avgCell,
                        'percent': "0.15",
                    }

                    # cell not blank and difference > 2X std.dev and > 15% of average
                    dev2 = '=AND(NOT(OR(ISBLANK(%(cell)s),ISBLANK(%(dev)s))), %(diff)s > (2.0 * %(dev)s), %(threshold)s)' % {
                        'diff' : diff,
                        'threshold' : threshold,
                        'cell' : dataCell,
                        'avg' : avgCell,
                        'dev' : devCell,
                    }
                    dev1 = '=AND(NOT(OR(ISBLANK(%(cell)s),ISBLANK(%(dev)s))), %(diff)s >  %(dev)s, %(diff)s <= (2.0 * %(dev)s), %(threshold)s) ' % {
                        'diff' : diff,
                        'threshold' : threshold,
                        'cell' : dataCell,
                        'avg' : avgCell,
                        'dev' : devCell,
                    }
                    # yellow if between 1 and 2 standard deviations away
                    summarySheet.conditional_format(firstRow, col, lastSummaryRow, col,
                                                    { 'type': 'formula',
                                                      'criteria': dev1,
                                                      'format' : self.formats['highlight'],
                                                    })
                    # red if more than 2 2 standard deviations away
                    summarySheet.conditional_format(firstRow, col, lastSummaryRow, col,
                                                    { 'type': 'formula',
                                                      'criteria': dev2,
                                                      'format' : self.formats['danger'],
                                                    })
                    col += 1
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
    parser.add_argument('files', nargs=argparse.REMAINDER)

    try:
        args = parser.parse_args()
    except IOError as err:
        print(str(err))
        sys.exit(2)


    GenerateSpreadsheet(args.out, args.files)
