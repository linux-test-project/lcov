#!/usr/bin/env python3

# Check the layout of the sub-tables spreadsheet.py writes on one sheet.
#
# usage: check_table_layout.py <xlsx> <sheet> <section>...
#   e.g. check_table_layout.py mem.xlsx geninfo.json chunks files
#
# Every sub-table has the same shape:  two empty rows setting it apart from
#   whatever precedes it, then a descriptive title - a brief label in column A
#   and a sentence in column B saying what one row of the table is - then the
#   section name in column A of a column title row, then the four statistics
#   rows - total, max, avg, stddev - computed over all the elements of that
#   table, then one row per element (its id in column B and one value per key
#   from column C on).
# For each named section this checks that shape:  two empty rows and then the
#   descriptive title precede the column title row, the label is boldface and
#   brief and fits the width of column A - it cannot spill into the explanation
#   beside it - and the explanation is neither boldface nor brief, the column
#   titles are boldface, the statistics rows are below them and in that order,
#   their labels are italic - both to set them apart from the data - and each
#   holds the matching formula over exactly the element rows in every column
#   which has data.
# 'total' is not additive for every column:  a peak memory column holds the
#   peaks of jobs which ran concurrently, so summing them means nothing and that
#   cell must be empty (the 'max' row below it is the number of interest).
# Each column title must also be a hyperlink to the glossary entry which
#   describes it.  The glossary sheet is the oracle for that: a title whose
#   metric the glossary describes must point at the row describing it, and one
#   the glossary says nothing about must not point anywhere.
#
# Reads the .xlsx with the standard library only - see check_peakmem_columns.py,
#   whose reader this shares.

import re
import sys

from check_peakmem_columns import (loadSheet, loadLinks, loadWidths, STATS,
                                   columnNumber, covers, checkStatLabels,
                                   checkTitleRow, isTitleRow)

# columns whose 'total' cell must be empty rather than a sum, by title
nonAdditive = ('peakVM', 'peakRSS')

# columns which carry no statistics at all - an ordinal, not a measurement
noStats = ('order',)

# a sub-table's label has to be brief to be worth having beside the sentence
#   which explains it - this is how brief
maxLabelWords = 4

# the width of a column whose width the writer did not set:  Excel's own
#   default, about 8 characters
defaultWidth = 8.43

# the sheet the column titles link into
glossarySheetName = 'glossary'


def glossaryEntries(path):
    # {metric name: [row, ...]} for the glossary sheet - what it describes and
    #   where.  One entry can cover several metrics, which it names in one
    #   slash-separated term ('peakVM / peakRSS'), and the same name can appear
    #   in two entries - the layout entry 'total / max / avg / stddev' and the
    #   metric 'total' - in which case the sheet alone does not say which of
    #   them a column title ought to point at, so any of them is accepted.
    rows = loadSheet(path, glossarySheetName)[0]
    entries = {}
    for r in sorted(rows):
        cells = rows[r]
        # a term row has the term in column A and its meaning in column B;  a
        #   section heading has only the former, and row 1 is the sheet's own
        #   'metric'/'meaning' title row
        if r == 1 or 'A' not in cells or 'B' not in cells:
            continue
        for name in str(cells['A']).split('/'):
            entries.setdefault(name.strip(), []).append(r)
    return entries


def checkSectionTitle(rows, links, entries, widths, section, fonts, header):
    # A table's descriptive title, on the row immediately above the column
    #   titles:  a brief label in column A, boldface like the column titles and
    #   short enough to scan down, and the sentence which explains it in column
    #   B, deliberately not boldface so that the labels stand out from it.
    # The label is also the way in to what the table reports, so where the
    #   glossary has an entry for that it must link there.  A label which links
    #   nowhere is accepted - not everything a table reports is a metric the
    #   glossary describes - but one which links somewhere else is not.
    row = header - 1
    desc = rows.get(row, {})
    label = str(desc.get('A', '')).strip()
    text = str(desc.get('B', '')).strip()
    if set(desc) != {'A', 'B'} or not label or len(text.split()) < 3:
        print("FAIL: '%s' row %d must hold this table's label in column A and"
              " the sentence explaining it in column B (found: %s)" % (
                  section, row,
                  ' '.join('%s=%s' % (c, desc[c]) for c in sorted(desc)) or
                  'nothing'))
        return 1
    if len(label.split()) > maxLabelWords:
        print("FAIL: '%s' label at A%d is %d words ('%s') - a table label must"
              " be at most %d, so that a column of them can be scanned" % (
                  section, row, len(label.split()), label, maxLabelWords))
        return 1
    if (row, 'A') not in fonts['bold']:
        print("FAIL: '%s' label at A%d is not boldface" % (section, row))
        return 1
    if (row, 'B') in fonts['bold']:
        print("FAIL: '%s' explanation at B%d is boldface - it must not be, so"
              " that the label beside it stands out" % (section, row))
        return 1
    # The label cannot spill into column B the way the sentence in B spills into
    #   the empty cells right of it, because B is occupied - so if column A is
    #   narrower than the label, the reader sees the label cut short.  Excel
    #   pads a cell by about a character at each edge, hence the label's own
    #   length is the floor rather than the target.
    if widths.get('A', defaultWidth) < len(label):
        print("FAIL: '%s' label at A%d is '%s' (%d characters) but column A is"
              " %g wide, so it will be clipped" % (
                  section, row, label, len(label),
                  widths.get('A', defaultWidth)))
        return 1
    target = links.get('A%d' % (row))
    if target is not None:
        known = set(r for rowList in entries.values() for r in rowList)
        m = re.match(r"^'%s'!A(\d+)$" % (glossarySheetName), target)
        if not m or int(m.group(1)) not in known:
            print("FAIL: '%s' label at A%d ('%s') links to '%s', which is not a"
                  " glossary entry" % (section, row, label, target))
            return 1
    return 0


def checkGlossaryLinks(rows, links, entries, section, header):
    # every column title the glossary describes must link to the row describing
    #   it, and a title the glossary says nothing about - a placeholder column,
    #   or a metric nobody has written an entry for - must not link anywhere
    linked = 0
    for col, key in rows[header].items():
        if columnNumber(col) < columnNumber('B'):
            continue    # column A holds the section name, not a column title
        # the whole-run memory block titles its columns '<key> (MB)'
        name = str(key).replace(' (MB)', '').strip()
        target = links.get('%s%d' % (col, header))
        if target is None:
            if len(entries.get(name, [])) == 1:
                print("FAIL: '%s' column title %s%d ('%s') does not link to its"
                      " glossary entry on row %d" % (
                          section, col, header, name, entries[name][0]))
                return 1
            continue
        m = re.match(r"^'%s'!A(\d+)$" % (glossarySheetName), target)
        if not m:
            print("FAIL: '%s' column title %s%d ('%s') links to '%s', which is"
                  " not a glossary entry" % (
                      section, col, header, name, target))
            return 1
        if int(m.group(1)) not in entries.get(name, []):
            print("FAIL: '%s' column title %s%d ('%s') links to glossary row"
                  " %s, which describes '%s'" % (
                      section, col, header, name, m.group(1),
                      ' / '.join(str(r) for r in entries.get(name, [])) or
                      'nothing - the glossary has no entry for it'))
            return 1
        linked += 1
    if not linked:
        print("FAIL: no column title of '%s' links to the glossary" % (section))
        return 1
    return 0


def checkSection(rows, formatted, fonts, links, entries, widths, sheetname,
                 section):
    header = next((r for r in sorted(rows)
                   if rows[r].get('A') == section and isTitleRow(rows[r])),
                  None)
    if header is None:
        print("FAIL: no '%s' section in sheet '%s'" % (section, sheetname))
        return 1

    if checkSectionTitle(rows, links, entries, widths, section, fonts, header):
        return 1

    # two empty rows must set this table - descriptive title and all - apart
    #   from whatever precedes it
    for r in (header - 3, header - 2):
        if r < 1 or rows.get(r):
            print("FAIL: '%s' row %d is not empty:  a sub-table must be"
                  " preceded by two empty rows" % (section, r))
            return 1

    if checkTitleRow(rows, fonts, section, header):
        return 1
    if checkGlossaryLinks(rows, links, entries, section, header):
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
    #   legitimately have no value in any element row (the peak memory of a
    #   platform which does not expose it), and such a column has no statistics
    #   either.
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

    print("OK: '%s' titled at row %d, title row %d linked to the glossary, %s,"
          " then rows %d-%d in %d column(s), colorized" % (
              section, header - 1, header, '/'.join(s[0] for s in STATS),
              first, last, len(checked)))
    return 0


def main(path, sheetname, sections):
    rows, formatted, fonts = loadSheet(path, sheetname)
    links = loadLinks(path, sheetname)
    widths = loadWidths(path, sheetname)
    entries = glossaryEntries(path)
    status = 0
    for section in sections:
        status |= checkSection(rows, formatted, fonts, links, entries, widths,
                               sheetname, section)
    return status


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("usage: %s <xlsx> <sheet> <section>..." % (sys.argv[0]))
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3:]))
