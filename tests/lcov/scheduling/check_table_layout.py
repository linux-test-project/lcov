#!/usr/bin/env python3

# Check the layout of the sub-tables spreadsheet.py writes on one sheet.
#
# usage: check_table_layout.py <xlsx> <sheet> <section>...
#   e.g. check_table_layout.py mem.xlsx geninfo.json chunks files
#
# Every sub-table has the same shape:  two empty rows setting it apart from
#   whatever precedes it, then the section name in column A of a column title
#   row, then the four statistics rows - total, max, avg, stddev - computed over
#   all the elements of that table, then one row per element (its id in column B
#   and one value per key from column C on).
# For each named section this checks that shape:  two empty rows precede the
#   title row, its titles are boldface, the statistics rows are immediately
#   below it and in that order, their labels are italic - both to set them apart
#   from the data - and each holds the matching formula over exactly the element
#   rows in every column which has data.
# 'total' is not additive for every column:  a peak memory column holds the
#   peaks of jobs which ran concurrently, so summing them means nothing and that
#   cell must be empty (the 'max' row below it is the number of interest).
#
# Reads the .xlsx with the standard library only - see check_peakmem_columns.py,
#   whose reader this shares.

import sys

from check_peakmem_columns import (loadSheet, STATS, columnNumber, covers,
                                  checkStatLabels, checkTitleRow)

# columns whose 'total' cell must be empty rather than a sum, by title
nonAdditive = ('peakVM', 'peakRSS')

# columns which carry no statistics at all - an ordinal, not a measurement
noStats = ('order',)


def isTitleRow(cells):
    # a sub-table title row names its section in column A and its keys from
    #   column C on, with column B empty.  A scalar key of the same name (the
    #   geninfo 'filter' phase total, say) has its value in column B instead.
    return 'B' not in cells and 'C' in cells


def checkSection(rows, formatted, fonts, sheetname, section):
    header = next((r for r in sorted(rows)
                   if rows[r].get('A') == section and isTitleRow(rows[r])),
                  None)
    if header is None:
        print("FAIL: no '%s' section in sheet '%s'" % (section, sheetname))
        return 1

    # two empty rows must set this table apart from whatever precedes it
    for r in (header - 2, header - 1):
        if r < 1 or rows.get(r):
            print("FAIL: '%s' row %d is not empty:  a sub-table must be"
                  " preceded by two empty rows" % (section, r))
            return 1

    if checkTitleRow(rows, fonts, section, header):
        return 1
    if checkStatLabels(rows, fonts, section, header):
        return 1

    # the element rows:  from just below the statistics to the first row which
    #   has no id in column B or which starts a new section in column A
    first = header + 1 + len(STATS)
    last = first - 1
    for r in range(first, max(rows) + 1):
        cells = rows.get(r, {})
        if 'B' not in cells or 'A' in cells:
            break
        last = r
    if last < first:
        print("FAIL: '%s' has no element rows below its statistics" % (section))
        return 1

    # one column per key of the title row, from column C on.  A key can
    #   legitimately have no value in any element row (the per-segment
    #   'parse'/'append' of an lcov profile whose inputs were merged in the
    #   parent), and such a column has no statistics either.
    checked = []
    for col, key in sorted(rows[header].items(),
                           key=lambda kv: columnNumber(kv[0])):
        if columnNumber(col) < columnNumber('C') or key in noStats:
            continue
        populated = [r for r in range(first, last + 1) if col in rows[r]]
        if not populated:
            continue
        checked.append(col)
        for i, (label, fn) in enumerate(STATS):
            r = header + 1 + i
            got = rows[r].get(col)
            if fn is None and key in nonAdditive:
                if got is not None:
                    print("FAIL: '%s' %s in column %s (%s): expected an empty"
                          " cell, found '%s'" % (section, label, col, key, got))
                    return 1
                continue
            if fn is None:
                fn = 'SUM'
            if label == 'stddev' and len(populated) < 2:
                continue    # a single sample has no standard deviation
            want = '=+%s(%s%d:%s%d)' % (fn, col, first, col, last)
            if got != want:
                print("FAIL: '%s' %s in column %s (%s): expected '%s', found"
                      " '%s'" % (section, label, col, key, want, got))
                return 1

    if not checked:
        print("FAIL: '%s' has no populated data column" % (section))
        return 1
    if not any(covers(rng, checked, first, last) for rng in formatted):
        print("FAIL: '%s' element rows %d-%d are not colorized (have: %s)" % (
            section, first, last, ' '.join(formatted)))
        return 1

    print("OK: '%s' title row %d, %s, then rows %d-%d in %d column(s),"
          " colorized" % (section, header, '/'.join(s[0] for s in STATS),
                          first, last, len(checked)))
    return 0


def main(path, sheetname, sections):
    rows, formatted, fonts = loadSheet(path, sheetname)
    status = 0
    for section in sections:
        status |= checkSection(rows, formatted, fonts, sheetname, section)
    return status


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("usage: %s <xlsx> <sheet> <section>..." % (sys.argv[0]))
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3:]))
