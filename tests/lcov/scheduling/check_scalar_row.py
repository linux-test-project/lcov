#!/usr/bin/env python3

# Check a scalar metric row spreadsheet.py writes on a tool sheet.
#
# usage: check_scalar_row.py <xlsx> <sheet> <key>...
#   e.g. check_scalar_row.py extract.xlsx extract_prof.json parse
#
# Most 'lcov' metrics are recorded per input file or per forked job, and are
#   written as a table.  A few of the same names are recorded as a single number
#   instead - 'lcov --extract'/'--remove' read one file, so their 'parse' is a
#   scalar rather than a hash of them - and those get a labelled row of their
#   own:  the key in column A and its value in column B.  Both shapes reach the
#   same code, so this checks the scalar one is not simply dropped.
#
# The numbers which describe how a run was set up rather than what it cost - a
#   capture's chunk size and file and chunk counts - are indented one column
#   further, under the configuration block they belong with, so a label in column
#   B with its value in column C is accepted too.  Which of the two a key is
#   written as says nothing about whether it came out.
#
# Reads the .xlsx with the standard library only - see check_peakmem_columns.py,
#   whose reader this shares.

import sys

from check_peakmem_columns import loadSheet


def checkKey(rows, sheetname, key):
    # a table would name its section in column A and its column titles from
    #   column C on, leaving column B empty - see check_table_layout.py.  A
    #   table's descriptive title does occupy both columns, but its label is
    #   prose ('trace filter', "'.info' processing") and never a metric key, so
    #   it cannot be found here.
    # column A first:  the statistics rows over a table are labelled in column B,
    #   and one of those labels is 'total', which is also the name of the
    #   whole-run elapsed time in column A
    for label, value in (('A', 'B'), ('B', 'C')):
        row = next((r for r in sorted(rows) if rows[r].get(label) == key), None)
        if row is not None:
            break
    if row is None:
        print("FAIL: no '%s' row on sheet '%s'" % (key, sheetname))
        return 1
    got = rows[row].get(value)
    if got is None:
        print("FAIL: %s: '%s' in row %d has no value in column %s" % (
            sheetname, key, row, value))
        return 1
    try:
        float(got)
    except ValueError:
        print("FAIL: %s: '%s' is '%s', which is not a number" % (
            sheetname, key, got))
        return 1
    print("OK: %s: scalar '%s' is %s, in %s%d" % (
        sheetname, key, got, value, row))
    return 0


def main(path, sheetname, keys):
    rows = loadSheet(path, sheetname)[0]
    status = 0
    for key in keys:
        status |= checkKey(rows, sheetname, key)
    return status


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("usage: %s <xlsx> <sheet> <key>..." % (sys.argv[0]))
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3:]))
