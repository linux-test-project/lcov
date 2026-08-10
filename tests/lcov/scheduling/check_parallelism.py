#!/usr/bin/env python3

# Check the observed-parallelism formula on a genhtml sheet:  that it divides
#   the total of the right column of the per-object table by the whole-run
#   elapsed total.
#
# usage: check_parallelism.py <xlsx> <sheet> <key>
#   e.g. check_parallelism.py noscope.xlsx nofile_prof.json html
#
# The figure is written beside the elapsed total - the 'total' scalar row near
#   the top of the sheet, whose label is in column A and whose value is in
#   column B - as '+<sum cell>/<total cell>'.  <key> is the per-object metric
#   whose total that sum has to be:  'file', the time spent on one source file
#   or directory, or 'html' for a profile old enough to have recorded only the
#   time to write each page.
# Which column that key landed in depends on which per-object metrics the
#   profile recorded at all, so this looks the column up by its title rather
#   than by counting:  the per-object table is the one table on these sheets
#   with no name of its own, so its title row is the boldface row which has a
#   column title in column D and nothing in A, B or C.  Its four statistics rows
#   follow immediately, so the total it must divide is on the row below the
#   titles - and that cell has to hold the sum, not be one of the empty cells a
#   column with no data gets.
#
# Reads the .xlsx with the standard library only - see check_peakmem_columns.py,
#   whose reader this shares.

import sys

from check_peakmem_columns import loadSheet, STATS

# the row the elapsed total is written on, by its label in column A
totalLabel = 'total'

# the column the parallelism figure goes in, beside that total
parallelCol = 'C'


def objectTitleRow(rows, fonts):
    # the column title row of the per-object table:  the one table which is not
    #   named in column A, so it is identified by what it does have - boldface
    #   column titles starting in column D, which is the spacer the file rows
    #   are labelled in, and nothing at all to the left of that
    found = [r for r in sorted(rows)
             if 'D' in rows[r] and (r, 'D') in fonts['bold'] and
             not set(rows[r]) & set('ABC')]
    if len(found) != 1:
        print("FAIL: expected one per-object table title row, found %d (%s)" % (
            len(found), ' '.join(str(r) for r in found) or 'none'))
        return None
    return found[0]


def main(path, sheetname, key):
    rows, formatted, fonts = loadSheet(path, sheetname)

    totalRow = next((r for r in sorted(rows)
                     if rows[r].get('A') == totalLabel and 'B' in rows[r]),
                    None)
    if totalRow is None:
        print("FAIL: no '%s' row in sheet '%s'" % (totalLabel, sheetname))
        return 1

    header = objectTitleRow(rows, fonts)
    if header is None:
        return 1
    keyCol = next((c for c, v in rows[header].items() if v == key), None)
    if keyCol is None:
        print("FAIL: no '%s' column in the per-object table (have: %s)" % (
            key, ' '.join('%s=%s' % (c, rows[header][c])
                          for c in sorted(rows[header]))))
        return 1

    # the statistics rows sit between the column titles and the data, in the
    #   order STATS names them, so the total is the first of them
    statRow = header + 1
    if str(rows.get(statRow, {}).get(parallelCol, '')) != STATS[0][0]:
        print("FAIL: row %d is not the per-object table's '%s' row" % (
            statRow, STATS[0][0]))
        return 1
    summed = rows[statRow].get(keyCol)
    if summed is None or not summed.startswith('=+SUM('):
        print("FAIL: %s%d, the '%s' of '%s', is '%s' rather than a sum" % (
            keyCol, statRow, STATS[0][0], key, summed))
        return 1

    want = '=+%s%d/B%d' % (keyCol, statRow, totalRow)
    got = rows[totalRow].get(parallelCol)
    if got != want:
        print("FAIL: observed parallelism at %s%d: expected '%s' (the total of"
              " '%s'), found '%s'" % (
                  parallelCol, totalRow, want, key, got))
        return 1

    print("OK: observed parallelism at %s%d is %s, the '%s' of '%s' over the"
          " elapsed total" % (parallelCol, totalRow, want[1:], STATS[0][0],
                              key))
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("usage: %s <xlsx> <sheet> <key>" % (sys.argv[0]))
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
