#!/usr/bin/env python3

# Check that every column of the capture summary table spreadsheet.py writes
#   points at the right cell of the capture sheet it summarizes.
#
# usage: check_summary_refs.py <xlsx> [<summary sheet>]
#   e.g. check_summary_refs.py mem.xlsx
#
# The summary sheet holds one row per capture, and every data cell in that row
#   is a reference to a cell of that capture's own sheet ("='geninfo.json'!B18").
#   Nothing in the file says whether the reference is the right one, so this
#   re-derives the answer from the capture sheet's own labels - which row is
#   labelled 'total', which sub-table names that key in its column title row -
#   and compares.  That is the check which matters:  an offset-based reference
#   still looks perfectly well-formed when it lands on the wrong number.
#
# The columns, in order, are the scalar statistics of the run - see SCALARS -
#   and then, per sub-table, two columns for each of its keys:  that key's
#   column total (or its maximum, for a key whose total is deliberately left
#   empty because summing the peaks of concurrently running jobs means nothing)
#   and its average.  A statistic the profile does not have, or a sub-table it
#   does not have at all - the chunk table of a serial capture, the filter table
#   of a capture which did not fork filter workers - must leave its columns
#   empty rather than referring to some other cell.
# Also checked:  the average and stddev rows above the cases must cover every
#   column of the table - they used to be written over the wrong ones - and the
#   case rows must be colorized against them.
#
# Reads the .xlsx with the standard library only - see check_peakmem_columns.py,
#   whose reader this shares.

import re
import sys

from check_peakmem_columns import loadSheet, STATS, columnNumber, covers

# The scalar statistics of a capture, and where each is written on the capture
#   sheet:
#     'scalar'  its own labelled row - the name in column A, the value in B
#     'config'  the config block - the key in column B, the value in C
#     'peak'    the whole-run 'peak mem' block, whose columns are titled
#               '<key> (MB)' and whose single 'max' row holds the values
#   In the order the summary table must present them.  Deliberately spelled out
#   rather than read back from the sheet:  this is the layout the summary
#   promises, so changing it should mean changing this list too.
SCALARS = (('total', 'scalar', 'total'),
           ('peakVM (MB)', 'peak', 'peakVM'),
           ('peakRSS (MB)', 'peak', 'peakRSS'),
           ('parallel', 'scalar', 'parallel'),
           ('maxParallel', 'config', 'maxParallel'),
           ('filter', 'scalar', 'filter'),
           ('write', 'scalar', 'write'),
           ('history', 'scalar', 'history'))

# rows below a sub-table's column title row that each of its statistics is on
statOffset = {label: 1 + i for i, (label, fn) in enumerate(STATS)}

# a data cell of the summary table refers to one cell of one capture sheet
REFERENCE = re.compile(r"^='([^']+)'!([A-Z]+\d+)$")


def columnLetter(n):
    s = ''
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(ord('A') + r) + s
    return s


def titles(rows, titleRow=1):
    # [(column letter, title)] of the summary table's column titles, in column
    #   order, skipping the 'case' column the capture names are in
    return [(c, rows[titleRow][c])
            for c in sorted(rows[titleRow], key=columnNumber)
            if columnNumber(c) > columnNumber('A')]


def caseRows(rows):
    # {row: capture sheet name} for the rows which summarize one capture each:
    #   a row is one when its cells refer to another sheet.  The average and
    #   stddev rows above them refer only to the summary sheet itself.
    cases = {}
    for r in sorted(rows):
        refs = set()
        for v in rows[r].values():
            m = REFERENCE.match(str(v))
            if m:
                refs.add(m.group(1))
        if not refs:
            continue
        if len(refs) > 1:
            print("FAIL: summary row %d refers to more than one sheet: %s" % (
                r, ' '.join(sorted(refs))))
            return None
        cases[r] = refs.pop()
    return cases


def scalarCell(rows, label):
    # a scalar statistic:  its name in column A and its value in column B.  An
    #   absent one still gets its label row, so require the value.
    r = next((r for r in sorted(rows)
              if rows[r].get('A') == label and 'B' in rows[r]), None)
    return None if r is None else 'B%d' % (r)


def configCell(rows, key):
    # a config entry:  the block starts at the row whose column A holds
    #   'config' and runs while each row names a key in column B
    start = next((r for r in sorted(rows) if rows[r].get('A') == 'config'),
                 None)
    r = start
    while r is not None and 'B' in rows.get(r, {}) and (r == start or
                                                        'A' not in rows[r]):
        if rows[r]['B'] == key:
            return 'C%d' % (r) if 'C' in rows[r] else None
        r += 1
    return None


def peakCell(rows, key):
    # the whole-run 'peak mem' block:  a title row naming it in column A with
    #   its columns titled from C on, then a single row of values below
    r = next((r for r in sorted(rows) if rows[r].get('A') == 'peak mem'), None)
    if r is None:
        return None
    col = next((c for c, v in rows[r].items() if v == key + ' (MB)'), None)
    return None if col is None else '%s%d' % (col, r + 1)


def subTables(rows):
    # {key: (title row, column letter)} for every key of every sub-table on the
    #   sheet.  A sub-table title row names its section in column A and its keys
    #   from column C on, with column B empty - a scalar key of the same name
    #   has its value in column B instead.
    keys = {}
    for r in sorted(rows):
        if 'A' not in rows[r] or 'B' in rows[r] or 'C' not in rows[r]:
            continue
        for c, v in rows[r].items():
            if columnNumber(c) < columnNumber('C'):
                continue
            if v in keys:
                print("FAIL: '%s' names key '%s', which sub-table %s already"
                      " does - the summary cannot tell which is meant" % (
                          rows[r]['A'], v, keys[v]))
                return None
            keys[v] = (r, c)
    return keys


def expected(rows, tables, title):
    # (cell, why) the summary column titled 'title' must refer to on this
    #   capture sheet, or (None, why) when this capture has no such statistic
    #   and the column must be left empty
    for name, kind, key in SCALARS:
        if title != name:
            continue
        if kind == 'scalar':
            return (scalarCell(rows, key), "the '%s' row" % (key))
        if kind == 'config':
            return (configCell(rows, key), "config '%s'" % (key))
        return (peakCell(rows, key), "the 'peak mem' block's %s" % (key))

    # otherwise a per-element key:  '<key>' is its column total, '<key> max'
    #   its maximum - for a key whose total is deliberately empty - and
    #   '<key> avg' its average
    key, _, suffix = title.rpartition(' ')
    if suffix not in ('avg', 'max'):
        key, suffix = title, 'total'
    if key not in tables:
        return (None, "no sub-table names '%s'" % (key))
    header, col = tables[key]
    cell = '%s%d' % (col, header + statOffset[suffix])
    return (cell, "'%s' %s in column %s" % (key, suffix, col))


def checkNonAdditive(rows, tables, key, suffix):
    # A key whose column total is deliberately left empty - the peak memory of
    #   jobs which ran concurrently, whose sum means nothing - must be
    #   summarized by its maximum, and an ordinary one by its total.  Both cells
    #   are empty for a key which had no data at all in that sub-table, and then
    #   either is fine.
    if suffix == 'avg' or key not in tables:
        return 0
    header, col = tables[key]
    hasTotal = '%s%d' % (col, header + statOffset['total']) and \
        rows.get(header + statOffset['total'], {}).get(col) is not None
    hasMax = rows.get(header + statOffset['max'], {}).get(col) is not None
    want = 'max' if (hasMax and not hasTotal) else 'total' if hasTotal else None
    if want is not None and suffix != want:
        print("FAIL: '%s' is summarized by its %s, but the sub-table's %s cell"
              " is %s" % (key, suffix, want,
                          'empty' if want == 'max' else 'a total'))
        return 1
    return 0


def checkCase(summary, path, row, sheetname, cols):
    rows = loadSheet(path, sheetname)[0]
    tables = subTables(rows)
    if tables is None:
        return 1
    status = 0
    for col, title in cols:
        want, why = expected(rows, tables, title)
        got = summary[row].get(col)
        if want is None:
            if got is not None:
                print("FAIL: %s: '%s' should be empty (%s), found '%s'" % (
                    sheetname, title, why, got))
                status = 1
            continue
        ref = "='%s'!%s" % (sheetname, want)
        if got != ref:
            print("FAIL: %s: '%s' should refer to %s (%s), found '%s'" % (
                sheetname, title, want, why, got))
            status = 1
            continue
        key, _, suffix = title.rpartition(' ')
        if suffix in ('avg', 'max'):
            status |= checkNonAdditive(rows, tables, key, suffix)
        elif not any(title == name for name, kind, k in SCALARS):
            status |= checkNonAdditive(rows, tables, title, 'total')
    if status == 0:
        print("OK: %s: all %d summary columns refer to the right cells" % (
            sheetname, len(cols)))
    return status


def checkTitles(cols):
    # the scalar statistics come first, in order, and every per-element key
    #   contributes exactly two columns:  its total (or maximum) and its average
    status = 0
    got = [t for c, t in cols[:len(SCALARS)]]
    want = [name for name, kind, key in SCALARS]
    if got != want:
        print("FAIL: summary table starts with %s, expected %s" % (
            ', '.join(got), ', '.join(want)))
        return 1
    rest = [t for c, t in cols[len(SCALARS):]]
    if len(rest) % 2:
        print("FAIL: %d per-element summary columns - they must come in"
              " total/average pairs" % (len(rest)))
        return 1
    for i in range(0, len(rest), 2):
        first, second = rest[i], rest[i + 1]
        key = first[:-4] if first.endswith(' max') else first
        if second != key + ' avg':
            print("FAIL: summary column '%s' is followed by '%s', expected"
                  " '%s avg'" % (first, second, key))
            status = 1
    return status


def checkStatRows(rows, formatted, cols, cases):
    # the average and stddev rows must cover every column of the table, over
    #   exactly the case rows, and those must be colorized against them
    first, last = min(cases), max(cases)
    status = 0
    for label, fn, r in (('average', 'AVERAGE', 2), ('stddev', 'STDEV', 3)):
        for col, title in cols:
            want = '=+%s(%s%d:%s%d)' % (fn, col, first, col, last)
            got = rows.get(r, {}).get(col)
            if got != want:
                print("FAIL: %s of '%s' (column %s): expected '%s', found"
                      " '%s'" % (label, title, col, want, got))
                status = 1
    if status:
        return status
    if not any(covers(rng, [c for c, t in cols], first, last)
               for rng in formatted):
        print("FAIL: summary rows %d-%d are not colorized (have: %s)" % (
            first, last, ' '.join(formatted)))
        return 1
    print("OK: average/stddev over rows %d-%d in all %d columns, colorized" % (
        first, last, len(cols)))
    return 0


def main(path, sheetname):
    rows, formatted, fonts = loadSheet(path, sheetname)
    cols = titles(rows)
    if not cols:
        print("FAIL: no column titles on sheet '%s'" % (sheetname))
        return 1
    cases = caseRows(rows)
    if cases is None:
        return 1
    if not cases:
        print("FAIL: no capture rows on sheet '%s'" % (sheetname))
        return 1
    status = checkTitles(cols)
    for row in sorted(cases):
        status |= checkCase(rows, path, row, cases[row], cols)
    status |= checkStatRows(rows, formatted, cols, cases)
    return status


if __name__ == '__main__':
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        print("usage: %s <xlsx> [<summary sheet>]" % (sys.argv[0]))
        sys.exit(2)
    sys.exit(main(sys.argv[1],
                  sys.argv[2] if len(sys.argv) > 2 else 'capture_summary'))
