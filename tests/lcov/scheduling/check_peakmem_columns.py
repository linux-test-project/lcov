#!/usr/bin/env python3

# Check that spreadsheet.py emitted 'peakVM' and 'peakRSS' columns immediately
#   right of an expected anchor column in a named section of a generated
#   spreadsheet, and that every data row of that section carries a positive
#   number in both.
#
# usage: check_peakmem_columns.py <xlsx> <sheet> <section> <anchor>
#   e.g. check_peakmem_columns.py report.xlsx geninfo.json chunks merge
#
# Every section which carries peak memory has the same layout:  the section
#   name in column A of a column-title row, then one row per job - its id in
#   column B and one value per key from column C on.  So peakVM/peakRSS are
#   always the two columns just right of <anchor>.  Pass <anchor> as 'none' for
#   a section whose first key IS peakVM (the whole-run 'peak mem' block, which
#   has a single 'max' row rather than one row per job).
# A key can legitimately have no value in a given row, so only the two memory
#   columns are required to be populated;  check_table_column.py is where a test
#   says which of the others it expects.
# A per-job table also carries 'total'/'max'/'avg'/'stddev' statistics rows
#   between its title row and its first data row, and colorizes its data cells
#   against those.  Those are checked too:  the column titles above them must be
#   boldface, each statistics row must be labelled in italic and hold the
#   matching formula over exactly the data rows, and the data range must carry
#   conditional formatting rules.  The exception is the 'total' of a peak memory
#   column:  summing the peaks of jobs which ran concurrently means nothing, so
#   that cell must be empty - the 'max' row below it is the number of interest.
#   The whole-run block has no statistics to check, just the same boldface titles
#   and italic row label.
#
# Reads the .xlsx with zipfile + ElementTree rather than a spreadsheet module,
#   so this needs nothing beyond the standard library:  xlsxwriter (which
#   spreadsheet.py needs) only writes, and the reader modules are not
#   necessarily installed.

import re
import sys
import zipfile
import xml.etree.ElementTree as ET

NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'


def fontStyles(z):
    # {'italic': {style index...}, 'bold': {...}} - the cell style indices whose
    #   font has that attribute.  A cell names its style in the 's' attribute;
    #   that indexes 'cellXfs', whose entry names the font, and an italic/bold
    #   font carries an <i/>/<b/> element.
    attrs = {'italic': 'i', 'bold': 'b'}
    found = {name: set() for name in attrs}
    if 'xl/styles.xml' not in z.namelist():
        return found
    styles = ET.fromstring(z.read('xl/styles.xml'))
    fonts = list(styles.find(NS + 'fonts') or [])
    xfs = list(styles.find(NS + 'cellXfs') or [])
    for name, tag in attrs.items():
        has = [f.find(NS + tag) is not None for f in fonts]
        for i, xf in enumerate(xfs):
            fid = int(xf.get('fontId') or 0)
            if fid < len(has) and has[fid]:
                found[name].add(i)
    return found


def openSheet(path, sheetname):
    # (the workbook zip, the parsed XML of one of its sheets, by name)
    z = zipfile.ZipFile(path)
    wb = ET.fromstring(z.read('xl/workbook.xml'))
    names = [sh.get('name') for sh in wb.iter(NS + 'sheet')]
    if sheetname not in names:
        print("FAIL: no '%s' sheet in %s (have: %s)" % (
            sheetname, path, ' '.join(names)))
        sys.exit(1)
    # sheet1.xml is the first sheet in the workbook, and so on
    return (z, ET.fromstring(z.read('xl/worksheets/sheet%d.xml' % (
        names.index(sheetname) + 1))))


def loadLinks(path, sheetname):
    # {cell: target} for the internal hyperlinks of one worksheet, e.g.
    #   {'C26': "'glossary'!A11"}.  A link to another sheet of the same workbook
    #   is written as a 'location' attribute rather than as a relationship, so
    #   it is all in the sheet XML.
    z, ws = openSheet(path, sheetname)
    return {h.get('ref'): h.get('location')
            for h in ws.iter(NS + 'hyperlink') if h.get('location')}


def loadWidths(path, sheetname):
    # {columnLetter: width} for the columns of one worksheet whose width was set
    #   explicitly.  A <col> element can cover a span of columns, and a column
    #   which is not covered by one has the sheet default width - which is not
    #   recorded here, since the caller only ever asks about a column the writer
    #   sized on purpose.
    z, ws = openSheet(path, sheetname)
    widths = {}
    for col in ws.iter(NS + 'col'):
        if col.get('width') is None:
            continue
        for n in range(int(col.get('min')), int(col.get('max')) + 1):
            widths[columnLetter(n)] = float(col.get('width'))
    return widths


def loadSheet(path, sheetname):
    # ({rowNumber: {columnLetter: value}}, [conditionally formatted ranges],
    #  {'italic': {(rowNumber, columnLetter)...}, 'bold': {...}}) for one
    #   worksheet.  A cell holding a formula is returned as its formula text
    #   ('=+AVERAGE(C15:C16)'), since xlsxwriter writes no cached value for one.
    z, ws = openSheet(path, sheetname)
    strings = []
    if 'xl/sharedStrings.xml' in z.namelist():
        for si in ET.fromstring(z.read('xl/sharedStrings.xml')):
            strings.append(''.join(t.text or '' for t in si.iter(NS + 't')))
    styleIds = fontStyles(z)
    rows = {}
    fonts = {name: set() for name in styleIds}
    for row in ws.iter(NS + 'row'):
        cells = {}
        r = int(row.get('r'))
        for c in row.iter(NS + 'c'):
            col = re.match(r'[A-Z]+', c.get('r')).group(0)
            f = c.find(NS + 'f')
            v = c.find(NS + 'v')
            if f is not None:
                cells[col] = '=' + (f.text or '')
            elif v is not None:
                cells[col] = (strings[int(v.text)] if c.get('t') == 's'
                              else v.text)
            s = int(c.get('s') or 0)
            for name, ids in styleIds.items():
                if s in ids:
                    fonts[name].add((r, col))
        rows[r] = cells
    # ranges which have conditional formatting rules attached
    formatted = [cf.get('sqref') for cf in ws.iter(NS + 'conditionalFormatting')
                 if cf.find(NS + 'cfRule') is not None]
    return (rows, formatted, fonts)


def isTitleRow(cells):
    # a sub-table title row names its section in column A and its keys from
    #   column C on, with column B empty.  Two other kinds of row have something
    #   in column A, and both put something in column B too:  a scalar key of
    #   the same name (the whole-job 'filter' time of an lcov run which filtered
    #   as a step of its own, say, on the same sheet as the table of the workers
    #   which did it), whose value goes there, and the table's own descriptive
    #   title, whose explanation does.  So column A alone does not identify the
    #   title row.
    return 'B' not in cells and 'C' in cells


def columnNumber(col):
    n = 0
    for ch in col:
        n = n * 26 + (ord(ch) - ord('A') + 1)
    return n


def columnLetter(n):
    # the inverse of columnNumber:  1 -> 'A', 27 -> 'AA'
    s = ''
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(ord('A') + r) + s
    return s


def nextColumn(col):
    return columnLetter(columnNumber(col) + 1)


def covers(sqref, cols, first, last):
    # does this conditionally formatted range (e.g. 'C15:I16') span all of
    #   rows first..last in every one of 'cols'?
    # A table of one element with one column is one cell, and is written as
    #   'C15' rather than as 'C15:C15'.
    for rng in sqref.split():
        m = re.match(r'([A-Z]+)(\d+)(?::([A-Z]+)(\d+))?$', rng)
        if not m:
            continue
        c0, r0 = columnNumber(m.group(1)), int(m.group(2))
        c1 = columnNumber(m.group(3)) if m.group(3) else c0
        r1 = int(m.group(4)) if m.group(4) else r0
        if (r0 <= first and last <= r1 and
                all(c0 <= columnNumber(c) <= c1 for c in cols)):
            return True
    return False


# the statistics rows a sub-table leads with, in order, and the formula each
#   holds.  'total' has none here because this checker only ever looks at the
#   peak memory columns, whose total must be an empty cell;  check_table_layout,
#   which looks at every column, reads it as 'SUM' for the additive ones.
STATS = (('total', None), ('max', 'MAX'), ('avg', 'AVERAGE'),
         ('stddev', 'STDEV'))


def checkTitleRow(rows, fonts, section, header):
    # every populated cell of the title row must be boldface - that is what sets
    #   the column titles apart from the data below them.
    for col in sorted(rows[header]):
        if (header, col) not in fonts['bold']:
            print("FAIL: '%s' title cell %s%d ('%s') is not boldface" % (
                section, col, header, rows[header][col]))
            return 1
    return 0


def checkStatLabels(rows, fonts, section, header, col='B'):
    # the statistics labels must sit immediately below the title row, in order,
    #   and be italic - that is what sets them apart from the data rows below.
    labels = [str(rows.get(header + 1 + i, {}).get(col, ''))
              for i in range(len(STATS))]
    if labels != [s[0] for s in STATS]:
        print("FAIL: '%s' title row %d is not followed by %s - found %s" % (
            section, header, '/'.join(s[0] for s in STATS), '/'.join(labels)))
        return 1
    for i, (label, fn) in enumerate(STATS):
        if (header + 1 + i, col) not in fonts['italic']:
            print("FAIL: '%s' %s label at %s%d is not italic" % (
                section, label, col, header + 1 + i))
            return 1
    return 0


def checkStats(rows, formatted, fonts, section, header, first, last, cols):
    # a section whose title row is followed by the statistics rows must compute
    #   each of those over exactly its data rows, in every column which has
    #   data, and must colorize that data range.
    if checkTitleRow(rows, fonts, section, header):
        return 1
    if checkStatLabels(rows, fonts, section, header):
        return 1
    for i, (label, fn) in enumerate(STATS):
        r = header + 1 + i
        want = None if fn is None else '=+%s(%%s%d:%%s%d)' % (fn, first, last)
        for c in cols:
            got = rows[r].get(c)
            if want is None:
                if got is not None:
                    print("FAIL: '%s' %s in column %s: expected an empty cell,"
                          " found '%s'" % (section, label, c, got))
                    return 1
                continue
            if got != want % (c, c):
                print("FAIL: '%s' %s in column %s: expected '%s', found '%s'"
                      % (section, label, c, want % (c, c), got))
                return 1
    if not any(covers(rng, cols, first, last) for rng in formatted):
        print("FAIL: '%s' data rows %d-%d are not colorized (have: %s)" % (
            section, first, last, ' '.join(formatted)))
        return 1
    print("OK: '%s' %s over rows %d-%d, colorized" % (
        section, '/'.join(s[0] for s in STATS), first, last))
    return 0


def main(path, sheetname, section, anchor):
    rows, formatted, fonts = loadSheet(path, sheetname)

    # the section's header row is the one whose column A holds its name - and
    #   which is a title row rather than a scalar metric of the same name
    header = next((r for r in sorted(rows) if rows[r].get('A') == section and
                   isTitleRow(rows[r])), None)
    if header is None:
        print("FAIL: no '%s' section in sheet '%s'" % (section, sheetname))
        return 1
    cells = rows[header]
    if anchor == 'none':
        # the section has no timing keys - peak memory is the first column
        anchorCol = 'B'
    else:
        anchorCol = next((c for c, v in cells.items() if v == anchor), None)
        if anchorCol is None:
            print("FAIL: no '%s' column in the '%s' header" % (anchor, section))
            return 1

    vmCol = nextColumn(anchorCol)
    rssCol = nextColumn(vmCol)
    # the whole-run block labels its columns 'peakVM (MB)'/'peakRSS (MB)'
    got = [str(cells.get(c, '')).replace(' (MB)', '') for c in (vmCol, rssCol)]
    if got != ['peakVM', 'peakRSS']:
        print("FAIL: expected peakVM,peakRSS right of '%s' in '%s'"
              " - found '%s','%s'" % (anchor, section, got[0], got[1]))
        return 1

    # a per-job table leads with the statistics rows, so its data starts below
    #   them.  The whole-run 'peak mem' block has no statistics at all - just
    #   its single 'max' row - so there the data starts immediately.
    perJob = anchor != 'none'
    dataRow = header + 1 + (len(STATS) if perJob else 0)

    # every data row must have positive memory in both columns.  A data row
    #   carries its id in column B and nothing in column A, so the section ends
    #   at the first row which breaks either rule - column A holds the next
    #   section's name (or the next scalar key).
    count = 0
    first = None
    for r in sorted(rows):
        if r < dataRow:
            continue
        if 'B' not in rows[r] or 'A' in rows[r]:
            break    # end of this section's data
        for col, label in ((vmCol, 'peakVM'), (rssCol, 'peakRSS')):
            if col not in rows[r] or float(rows[r][col]) <= 0:
                print("FAIL: '%s' row %d: %s is not positive" % (
                    section, r, label))
                return 1
        if first is None:
            first = r
        count += 1
    if count < 1:
        print("FAIL: no '%s' data rows carrying peak memory" % (section))
        return 1

    print("OK: '%s' has peakVM,peakRSS right of '%s' in %d row(s)" % (
        section, anchor, count))
    if not perJob:
        # the whole-run block has just the one row, but the same formatting:
        #   boldface column titles and an italic 'max' label
        if checkTitleRow(rows, fonts, section, header):
            return 1
        if (first, 'B') not in fonts['italic']:
            print("FAIL: '%s' max label at B%d is not italic" % (section, first))
            return 1
        return 0
    return checkStats(rows, formatted, fonts, section, header, first,
                      first + count - 1, [vmCol, rssCol])


if __name__ == '__main__':
    if len(sys.argv) != 5:
        print("usage: %s <xlsx> <sheet> <section> <anchor>" % (sys.argv[0]))
        sys.exit(2)
    sys.exit(main(*sys.argv[1:5]))
