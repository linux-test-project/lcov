#!/usr/bin/env python3

# Check the colorizing thresholds spreadsheet.py wrote into a sheet.
#
# usage: check_thresholds.py <xlsx> <sheet> <threshold> <low> <high>
#   e.g. check_thresholds.py mem.xlsx geninfo_prof.json 0.15 1.5 2.0
#
# Every data table gets three conditional formatting rules, comparing each cell
#   against its own column's average and standard deviation rows:  yellow from
#   'low' standard deviations out, red from 'high', green 'high' out on the
#   faster side, and none of them for a difference smaller than 'threshold' as a
#   fraction of the average.  Those three numbers are what --low, --high and
#   --threshold set, and they are baked into the rule formulas - so this is the
#   only place a caller can see whether the options had any effect.  They were
#   parsed and then ignored for as long as the options existed, which is what
#   this exists to catch.
#
# The rules are read structurally rather than by matching whole formulas:  each
#   comparison in a rule multiplies either the standard deviation cell or the
#   average cell, and which one it is says what the multiplier means.  So this
#   does not have to know the exact text, only its shape.
#
# The summary sheet also states the same two deviation figures in prose, in its
#   colour legend;  those are checked too when the sheet has one, since a legend
#   which disagrees with the colours is worse than no legend.
#
# Reads the .xlsx with the standard library only - see check_peakmem_columns.py,
#   whose reader this shares.

import re
import sys

from check_peakmem_columns import NS, openSheet, loadSheet

# one comparison of a rule:  the data cell less the average cell, optionally
#   under ABS(), against a multiple of some cell.  The multiplied cell is what
#   distinguishes a deviation band from the relative-difference threshold, and
#   the leading '-' is what distinguishes the green band from the red one.
COMPARE = re.compile(r'(ABS)?\((\$?[A-Z]+\$?[0-9]+) - (\$?[A-Z]+\$?[0-9]+)\)'
                     r'\s*(<=|>=|<|>)\s*'
                     r'\(([0-9]+\.[0-9]+) \* (-?)(\$?[A-Z]+\$?[0-9]+)\)')

# the two deviation figures as the summary sheet's legend states them
LEGEND = (('YELLOW', re.compile(r'\[([0-9.]+),([0-9.]+)\)'), ('low', 'high')),
          ('RED', re.compile(r'more than ([0-9.]+) '), ('high',)),
          ('GREEN', re.compile(r'more than ([0-9.]+) '), ('high',)))


def ruleFormulas(path, sheetname):
    # [[formula, ...], ...] - one list per conditionally formatted range, in
    #   sheet order.  A range with no rules is not returned:  xlsxwriter writes
    #   the element only when it has some.
    ws = openSheet(path, sheetname)[1]
    ranges = []
    for cf in ws.iter(NS + 'conditionalFormatting'):
        formulas = [f.text or '' for rule in cf.iter(NS + 'cfRule')
                    for f in rule.iter(NS + 'formula')]
        if formulas:
            ranges.append((cf.get('sqref'), formulas))
    return ranges


def readRule(formula):
    # {'low': m} / {'high': m} / {'threshold': m} for one rule's formula, or
    #   None if it is not one of the three bands.
    # Which band it is follows from its comparisons:  the yellow one brackets
    #   the difference between two multiples of the deviation, the green one
    #   compares against a negated deviation, and the red one is what is left.
    found = {}
    dev = []
    for abs_, data, avg, op, mult, sign, cell in COMPARE.findall(formula):
        if cell == avg:
            found['threshold'] = float(mult)
        else:
            dev.append((op, sign, float(mult)))
    if 'threshold' not in found or not dev:
        return None
    if len(dev) == 2:
        # yellow:  '> low * stddev' and '<= high * stddev'
        for op, sign, mult in dev:
            found['low' if op == '>' else 'high'] = mult
    else:
        # red ('> high * stddev') or green ('< high * -stddev')
        found['high'] = dev[0][2]
    return found


def checkRange(sheetname, sqref, formulas, expect):
    status = 0
    got = {}
    for formula in formulas:
        read = readRule(formula)
        if read is None:
            print("FAIL: %s: %s: cannot read a threshold out of '%s'" % (
                sheetname, sqref, formula))
            status = 1
            continue
        for name, mult in read.items():
            if name in got and got[name] != mult:
                print("FAIL: %s: %s: two rules disagree on %s: %g and %g" % (
                    sheetname, sqref, name, got[name], mult))
                status = 1
            got[name] = mult
    if status:
        return status
    for name in ('threshold', 'low', 'high'):
        if name not in got:
            print("FAIL: %s: %s: no rule sets %s" % (sheetname, sqref, name))
            status = 1
        elif got[name] != expect[name]:
            print("FAIL: %s: %s: %s is %g, expected %g" % (
                sheetname, sqref, name, got[name], expect[name]))
            status = 1
    return status


def checkLegend(path, sheetname, expect):
    # the summary sheet states the deviation thresholds in prose.  A sheet
    #   without a legend is not a failure - only the summary has one.
    rows = loadSheet(path, sheetname)[0]
    text = [cells['A'] for r, cells in sorted(rows.items())
            if isinstance(cells.get('A'), str)]
    status = 0
    seen = 0
    for colour, pattern, names in LEGEND:
        line = next((t for t in text if t.startswith(colour + ':')), None)
        if line is None:
            continue
        seen += 1
        m = pattern.search(line)
        if m is None:
            print("FAIL: %s: cannot read a threshold out of '%s'" % (
                sheetname, line))
            status = 1
            continue
        for name, got in zip(names, m.groups()):
            if abs(float(got) - expect[name]) > 0.005:
                print("FAIL: %s: legend says %s is %s, expected %g" % (
                    sheetname, name, got, expect[name]))
                status = 1
    if seen and not status:
        print("OK: %s: colour legend agrees with the rules" % (sheetname))
    return status


def main(path, sheetname, threshold, low, high):
    expect = {'threshold': threshold, 'low': low, 'high': high}
    ranges = ruleFormulas(path, sheetname)
    if not ranges:
        print("FAIL: %s: sheet '%s' has no conditional formatting rules" % (
            path, sheetname))
        return 1
    status = 0
    for sqref, formulas in ranges:
        status |= checkRange(sheetname, sqref, formulas, expect)
    if not status:
        print("OK: %s: %d colorized ranges, all at threshold %g, low %g, "
              "high %g" % (sheetname, len(ranges), threshold, low, high))
    status |= checkLegend(path, sheetname, expect)
    return status


if __name__ == '__main__':
    if len(sys.argv) != 6:
        print("usage: %s <xlsx> <sheet> <threshold> <low> <high>" % (
            sys.argv[0]))
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], *[float(a)
                                             for a in sys.argv[3:]]))
