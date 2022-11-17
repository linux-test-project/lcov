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
        }
        intFormat = self.formats['intFormat']
        twoDecimal = self.formats['twoDecimal']

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
                d = data['gen_info']
                for k in ('emit', ):
                    try:
                        sheet.write_number(row, 3, data[k], twoDecimal)
                        sheet.write_string(row, 2, k)
                        row += 1
                    except:
                        pass

                dataKeys = ('process',  'parse', 'append', 'child', 'exec', 'merge', 'undump')
                col = 4;
                for k in dataKeys:
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
                sheet.write_string(row, 2, "variance")
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
                            except:
                                print("%s: failed to write %s for geninfo[%s][%s]" % (name, str(d3), type, f))
                            col = 4
                            try:
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

                                for key in dataKeys:
                                    try:
                                        val = float(data[key][dirname][f])
                                        sheet.write_number(row, col, val, twoDecimal)
                                    except:
                                        pass # no such key
                                    col += 1
                            except:
                                # get here if this file/directory was not processed in parallel
                                pass
                            row += 1

                        effectiveParallelism = "+SUM(%(from)s:%(to)s)/%(total)s" % {
                            'from': xl_rowcol_to_cell(start, 3),
                            'to': xl_rowcol_to_cell(row-1, 3),
                            'total': xl_rowcol_to_cell(start-1, 2),
                        }
                        sheet.write_formula(start-1, 3, effectiveParallelism, twoDecimal)
                        col = 4
                        for key in dataKeys:
                            f = xl_rowcol_to_cell(firstRow, col)
                            t = xl_rowcol_to_cell(row-1, col)

                            total = "+SUM(%(from)s:%(to)s)" % {
                                "from" : f,
                                "to": t
                            }
                            sheet.write_formula(sumRow, col, total, twoDecimal)
                            avg = "+AVERAGE(%(from)s:%(to)s)" % {
                                'from': f,
                                'to': t,
                            }
                            sheet.write_formula(avgRow, col, avg, twoDecimal)
                            var = "+STDEV(%(from)s:%(to)s) / AVERAGE(%(from)s:%(to)s)" % {
                                'from': f,
                                'to': t,
                            }
                            sheet.write_formula(devRow, col, var, twoDecimal)
                            col += 1

                continue

            elif tool == 'genhtml':

                for k in ('parse_source', 'parse_diff',
                          'parse_current', 'parse_baseline'):
                    if k in data:
                        sheet.write_string(row, 0, k)
                        sheet.write_number(row, 1, data[k], twoDecimal)
                        row += 1
                #print(" ".join(data.keys()))
                dirData = data['directory']

                fileData = data['file']
                begin = row
                for dirname in sorted(dirData.keys()):
                    sheet.write_string(row, 0, "directory")
                    sheet.write_string(row, 1, dirname)
                    sheet.write_number(row, 2, dirData[dirname], twoDecimal)
                    row += 1

                    start = row

                    for f in sorted(fileData.keys()):
                        pth, name = os.path.split(f)
                        if pth != dirname:
                            continue
                        sheet.write_string(row, 2, name)
                        sheet.write_number(row, 3, fileData[f], twoDecimal)

                        col = 4
                        for k in ('check_version', 'synth', 'load', 'annotate',
                                  'categorize', 'source'):
                            if (k in data and
                                f in data[k]):
                                sheet.write_string(row, col, k)
                                try:
                                    sheet.write_number(row, col+1, float(data[k][f]), twoDecimal)
                                except:
                                    print("%s: failed to write %s" %(name, data[k][f]))
                                col += 2
                        row += 1
                    effectiveParallelism = "+SUM(%(from)s:%(to)s)/%(total)s" % {
                        'from': xl_rowcol_to_cell(start, 3),
                        'to': xl_rowcol_to_cell(row-1, 3),
                        'total': xl_rowcol_to_cell(start-1, 2),
                    }
                    sheet.write_formula(start-1, 4, effectiveParallelism, twoDecimal)

                overallParallelism = "+SUM(%(from)s:%(to)s)/%(total)s" % {
                    'from': xl_rowcol_to_cell(begin, 3),
                    'to': xl_rowcol_to_cell(row-1, 3),
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
