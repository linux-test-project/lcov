#!/usr/bin/env python3

# Check which columns a sub-table spreadsheet.py wrote has.
#
# usage: check_table_column.py <xlsx> <sheet> <section> <key>...
#   e.g. check_table_column.py prof.xlsx prof_split.json info scan -parse
#
# A key names a column which the section must have and which every one of its
#   data rows must carry a number in;  a key written '-<key>' names one the
#   section must NOT have.  The absent form is the point of this checker:  a
#   column which is there but empty reads as "this cost nothing", and a metric
#   which does not apply to the way a run divided its work has to be left out
#   rather than written blank - so a test has to be able to say so.
# check_table_layout.py checks the shape every sub-table has;  this checks what
#   one of them is about.
#
# Reads the .xlsx with the standard library only - see check_peakmem_columns.py,
#   whose reader this shares.

import sys

from check_peakmem_columns import loadSheet, columnNumber, STATS
from check_table_layout import isTitleRow


def dataRows(rows, header):
    # the section's data rows:  from below its statistics rows to the first row
    #   which has no id in column B or which starts something new in column A.
    #   See check_table_layout.py, which derives them the same way.
    first = header + 1 + len(STATS)
    last = first - 1
    for r in range(first, max(rows) + 1):
        cells = rows.get(r, {})
        if 'B' not in cells or 'A' in cells:
            break
        last = r
    return range(first, last + 1)


def checkColumn(rows, sheetname, section, header, key):
    # the column titles live from column C on;  column A holds the section name
    titles = {str(v): c for c, v in rows[header].items()
              if columnNumber(c) >= columnNumber('C')}
    wanted = not key.startswith('-')
    key = key if wanted else key[1:]
    col = titles.get(key)
    if not wanted:
        if col is not None:
            print("FAIL: %s: '%s' has a '%s' column (%s%d), which it must not"
                  % (sheetname, section, key, col, header))
            return 1
        print("OK: %s: '%s' has no '%s' column" % (sheetname, section, key))
        return 0
    if col is None:
        print("FAIL: %s: '%s' has no '%s' column (have: %s)" % (
            sheetname, section, key, ' '.join(sorted(titles))))
        return 1
    n = 0
    for r in dataRows(rows, header):
        try:
            float(rows[r][col])
        except (KeyError, TypeError, ValueError):
            print("FAIL: %s: '%s' row %d has no %s in its '%s' column (%s)" % (
                sheetname, section, r, key, key, col))
            return 1
        n += 1
    if not n:
        print("FAIL: %s: '%s' has no data rows below its statistics" % (
            sheetname, section))
        return 1
    print("OK: %s: '%s' column '%s' (%s) is populated in %d row(s)" % (
        sheetname, section, key, col, n))
    return 0


def main(path, sheetname, section, keys):
    rows = loadSheet(path, sheetname)[0]
    # the section's title row - not a scalar metric row which happens to have
    #   the same name in column A, which is what 'isTitleRow' tells apart
    header = next((r for r in sorted(rows)
                   if rows[r].get('A') == section and isTitleRow(rows[r])),
                  None)
    if header is None:
        print("FAIL: no '%s' section in sheet '%s'" % (section, sheetname))
        return 1
    status = 0
    for key in keys:
        status |= checkColumn(rows, sheetname, section, header, key)
    return status


if __name__ == '__main__':
    if len(sys.argv) < 5:
        print("usage: %s <xlsx> <sheet> <section> <key>..." % (sys.argv[0]))
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]))
