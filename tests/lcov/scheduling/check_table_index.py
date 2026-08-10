#!/usr/bin/env python3

# Check the index of sub-tables spreadsheet.py writes at the top of a sheet
#   which has several of them.
#
# usage: check_table_index.py <xlsx> <sheet> [index|noindex]
#   e.g. check_table_index.py prof.xlsx prof_split.json index
#
# A sheet whose tables cannot all be seen at once leads with one line per
#   table:  the table's brief label in column A, hyperlinked to its descriptive
#   title, and the sentence which explains it in column B.  A reader should not
#   have to scroll past a 40-row table to find out what the next one reports.  A
#   sheet with a single table needs no index, and neither does one whose tables
#   are all short.
# This re-derives that from the sheet itself.  Its tables are found by their
#   descriptive titles - the only rows which have a boldface column A, a
#   non-boldface column B and nothing else - and each table's length by counting
#   the rows below its statistics.  If two or more tables are found and one is
#   longer than <minRows> (20, the same threshold spreadsheet.py applies), the
#   index must be there:  one line per table, in table order, in consecutive
#   rows, each linking to the right descriptive title and repeating both its
#   label and its explanation, separated from the data above by one empty row
#   and from the first table by the two which set every table apart.  Otherwise
#   there must be no index at all.
# The optional third argument asserts which of those two the sheet is expected
#   to be, so that a bug which suppresses the index everywhere cannot pass.
#
# Reads the .xlsx with the standard library only - see check_peakmem_columns.py,
#   whose reader this shares.

import re
import sys

from check_peakmem_columns import loadSheet, loadLinks, STATS

# a sheet gets an index only when one of its tables has more rows than this
minRows = 20


def descriptiveTitles(rows, fonts):
    # the rows holding a sub-table's descriptive title, in order:  a boldface
    #   label in column A, a non-boldface explanation in column B, and nothing
    #   else.  Every other boldface row on a sheet is a column title row, which
    #   has column titles from column C on;  the index lines have the same two
    #   columns but a link rather than a boldface label in column A;  and a
    #   scalar metric row has its name in column A and a number in column B,
    #   neither of them boldface.
    return [r for r in sorted(rows)
            if set(rows[r]) == {'A', 'B'} and (r, 'A') in fonts['bold'] and
            (r, 'B') not in fonts['bold']]


def elementRows(rows, titles, i):
    # how many element rows table 'i' has:  everything below its descriptive
    #   title, its column titles and its statistics, up to the empty rows which
    #   set the next table apart
    first = titles[i] + 2 + len(STATS)
    limit = titles[i + 1] if i + 1 < len(titles) else max(rows) + 1
    return len([r for r in range(first, limit) if rows.get(r)])


def main(path, sheetname, expected=None):
    rows, formatted, fonts = loadSheet(path, sheetname)
    links = loadLinks(path, sheetname)
    titles = descriptiveTitles(rows, fonts)
    if not titles:
        print("FAIL: sheet '%s' has no sub-table with a descriptive title" % (
            sheetname))
        return 1
    counts = [elementRows(rows, titles, i) for i in range(len(titles))]
    want = len(titles) > 1 and max(counts) > minRows

    if expected is not None and want != (expected == 'index'):
        print("FAIL: sheet '%s' has %d table(s) of %s row(s), which needs %s"
              " index - expected '%s'" % (
                  sheetname, len(titles), '/'.join(str(c) for c in counts),
                  'an' if want else 'no', expected))
        return 1

    # links in column A above the first table:  the index, if there is one
    indexed = sorted(int(m.group(1)) for m in
                     (re.match(r'^A(\d+)$', ref) for ref in links)
                     if m and int(m.group(1)) < titles[0])
    if not want:
        if indexed:
            print("FAIL: sheet '%s' has %d table(s) of %s row(s) and needs no"
                  " index, but row(s) %s link to one" % (
                      sheetname, len(titles),
                      '/'.join(str(c) for c in counts),
                      ' '.join(str(r) for r in indexed)))
            return 1
        print("OK: sheet '%s': %d table(s) of %s row(s), no index needed" % (
            sheetname, len(titles), '/'.join(str(c) for c in counts)))
        return 0

    # one link per table, in consecutive rows, one blank row below the data
    #   above them and the usual two above the first table
    first = titles[0] - len(titles) - 2
    if indexed != list(range(first, first + len(titles))):
        print("FAIL: sheet '%s': expected an index in rows %d-%d, found link(s)"
              " in %s" % (sheetname, first, first + len(titles) - 1,
                          ' '.join(str(r) for r in indexed) or 'no row'))
        return 1
    if rows.get(first - 1):
        print("FAIL: sheet '%s': row %d is not empty - the index must be"
              " separated from the data above it by one blank row" % (
                  sheetname, first - 1))
        return 1
    for i, r in enumerate(indexed):
        want = "'%s'!A%d" % (sheetname, titles[i])
        got = links['A%d' % (r)]
        if got != want:
            print("FAIL: sheet '%s': index row %d points at '%s' - expected"
                  " '%s', the title of table %d" % (
                      sheetname, r, got, want, i + 1))
            return 1
        for col, what in (('A', 'label'), ('B', 'explanation')):
            if rows[r].get(col) != rows[titles[i]].get(col):
                print("FAIL: sheet '%s': index row %d has %s '%s' - expected"
                      " that of the title it points at, '%s'" % (
                          sheetname, r, what, rows[r].get(col),
                          rows[titles[i]].get(col)))
                return 1
    print("OK: sheet '%s': %d table(s) of %s row(s), indexed in rows %d-%d" % (
        sheetname, len(titles), '/'.join(str(c) for c in counts),
        indexed[0], indexed[-1]))
    return 0


if __name__ == '__main__':
    if len(sys.argv) not in (3, 4):
        print("usage: %s <xlsx> <sheet> [index|noindex]" % (sys.argv[0]))
        sys.exit(2)
    sys.exit(main(*sys.argv[1:4]))
