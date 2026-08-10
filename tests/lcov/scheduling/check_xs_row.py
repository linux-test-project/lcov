#!/usr/bin/env python3

# Check the 'XS enabled' row spreadsheet.py writes on a tool sheet.
#
# usage: check_xs_row.py <xlsx> <sheet> <0|1>
#   e.g. check_xs_row.py mem.xlsx geninfo_prof.json 1
#
# Which implementation of the coverage data classes ran is the one config entry
#   worth reading first - it explains times which are otherwise inexplicable -
#   so it is written as its own labelled row immediately below the 'tool' row
#   rather than being left where the alphabetical config order puts it.  This
#   checks exactly that:  the row right after the one naming 'tool' holds the
#   label 'XS enabled' in column B and the expected 1/0 in column C.
#   A profile which does not record it at all - one from a release predating
#   config{xs} - must still get the row, reading 0:  the pure Perl fallback is
#   silent, so 'not recorded' and 'did not load' amount to the same thing here.
#
# Reads the .xlsx with the standard library only - see check_peakmem_columns.py,
#   whose reader this shares.

import sys

from check_peakmem_columns import loadSheet

LABEL = 'XS enabled'


def main(path, sheetname, expect):
    rows = loadSheet(path, sheetname)[0]
    tool = next((r for r in sorted(rows) if rows[r].get('B') == 'tool'), None)
    if tool is None:
        print("FAIL: no 'tool' config row on sheet '%s'" % (sheetname))
        return 1
    cells = rows.get(tool + 1, {})
    if cells.get('B') != LABEL:
        print("FAIL: %s: row %d (just below 'tool') is labelled '%s',"
              " expected '%s'" % (sheetname, tool + 1, cells.get('B'), LABEL))
        return 1
    got = cells.get('C')
    if got is None or int(float(got)) != int(expect):
        print("FAIL: %s: '%s' is '%s', expected %s" % (
            sheetname, LABEL, got, expect))
        return 1
    print("OK: %s: '%s' is %s, in row %d just below 'tool'" % (
        sheetname, LABEL, expect, tool + 1))
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("usage: %s <xlsx> <sheet> <0|1>" % (sys.argv[0]))
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
