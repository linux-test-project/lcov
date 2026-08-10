#!/usr/bin/env python3

# Check one of the flat two-column value lists spreadsheet.py writes for a
#   profile key whose value is a hash of numbers - the capture's directory scan
#   times, or any key on the sheet a tool with no layout of its own gets.
#
# usage: check_value_list.py <xlsx> <sheet> <key> <count>
#   e.g. check_value_list.py mem.xlsx geninfo_prof.json find 1
#
# The list is the key's name in column A, then one row per entry:  the entry's
#   name in column B and its value in column C.  It is not a table - nothing
#   knows what these numbers are, so there is nothing to total or colorize - so
#   there are no statistics rows and no descriptive title.  The name shares the
#   first entry's row on a generic sheet and has a row to itself on a capture
#   sheet;  both are accepted, since which it is says nothing about whether the
#   numbers came out.
# <count> is how many entries the profile recorded, and may be 0:  a key the
#   profile does not have, or does not have a hash of numbers under, still gets
#   its label - so the sheet says what was recorded - and still keeps that row to
#   itself rather than letting whatever is written next overwrite the label.  A
#   sheet which packs its keys back to back writes the next one immediately
#   below, so what is checked is that nothing was written *into* the label's row,
#   not that the row after it is blank.
# Every value has to be a number.  A profile which quotes its numbers records
#   them as strings, which is a value that was recorded rather than a missing
#   one, so those must be converted rather than reported and skipped.
#
# Reads the .xlsx with the standard library only - see check_peakmem_columns.py,
#   whose reader this shares.

import sys

from check_peakmem_columns import loadSheet


def main(path, sheetname, key, count):
    rows = loadSheet(path, sheetname)[0]
    labelRow = next((r for r in sorted(rows) if rows[r].get('A') == key), None)
    if labelRow is None:
        print("FAIL: no '%s' label on sheet '%s'" % (key, sheetname))
        return 1

    # the entries run from the label's own row, if it shares one, to the first
    #   row which has no entry name in column B or which starts something else
    #   in column A
    first = labelRow if 'B' in rows[labelRow] else labelRow + 1
    entries = []
    for r in range(first, max(rows) + 1):
        cells = rows.get(r, {})
        if 'B' not in cells or (r != labelRow and 'A' in cells):
            break
        entries.append(r)

    if len(entries) != count:
        print("FAIL: %s: '%s' has %d entr%s, expected %d" % (
            sheetname, key, len(entries),
            'y' if len(entries) == 1 else 'ies', count))
        return 1
    extra = set(rows[labelRow]) - set('A')
    if not entries and extra:
        print("FAIL: %s: '%s' recorded nothing, but row %d - the row its label"
              " keeps - has %s" % (
                  sheetname, key, labelRow,
                  ' '.join('%s=%s' % (c, rows[labelRow][c])
                           for c in sorted(extra))))
        return 1
    for r in entries:
        got = rows[r].get('C')
        if got is None:
            print("FAIL: %s: '%s' entry '%s' in row %d has no value in column"
                  " C" % (sheetname, key, rows[r]['B'], r))
            return 1
        try:
            float(got)
        except ValueError:
            print("FAIL: %s: '%s' entry '%s' is '%s', which is not a number" % (
                sheetname, key, rows[r]['B'], got))
            return 1

    print("OK: %s: '%s' labelled in row %d, %d numeric entr%s" % (
        sheetname, key, labelRow, len(entries),
        'y' if len(entries) == 1 else 'ies'))
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 5:
        print("usage: %s <xlsx> <sheet> <key> <count>" % (sys.argv[0]))
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])))
