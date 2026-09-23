#!/usr/bin/env perl

#   Copyright (c) MediaTek USA Inc., 2026
#
#   This program is free software;  you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or (at
#   your option) any later version.
#
#   This program is distributed in the hope that it will be useful, but
#   WITHOUT ANY WARRANTY;  without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#   General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program;  if not, see
#   <http://www.gnu.org/licenses/>.
#
#
# unreach.pm --branch --mcdc --callgraph
#
#   This is a sample '--unreachable-script' callback - used to decide whether
#   a particular branch, MC/DC condition or call site is unreachable or not.
#   Unreachable coverpoints do not appear in the coverage report:  they are
#   not included in coverage percentages, not categorized as 'gained' or
#   lost, etc.
#   Effectively:  they are excluded from the coverage report.
#
#   Unlike line and function coverpoints, lcov _does_ retain information
#   about unreachable branches and MC/DC expressions because they are needed
#   in order for users to properly interpret the coverage report.  For example,
#   report indicates exactly which branch in some particular statement is
#   unreachable so users can determine the testcase needed to cover the
#   branches which are not hit but are reachable.
#
#   In contrast, call sites are removed when they are excluded - which is
#   also why the attribute is ``LCOV_EXCLUDE_CALL`` rather than
#   ``LCOV_UNREACHABLE_CALL``.
#
#   An unreachable branch which was taken is a contradiction
#   lcov reports - see '--ignore-errors unreachable' - whereas an excluded call
#   may or may not have happened - but we don't care.  An excluded
#   coverpoint is outside the boundary of the report by definition - so the
#   callee is recorded as having been called externally (from outside the
#   boundary).  The call site itself is excluded, so the report can no
#   longer say how many external call sites for that callee there were.
#
#   This is a trivial implementation which works with GCC and LLVM - which
#   indicate branches and MC/DC conditions as integers (based on expression
#   tree visit order in the compiler).
#   A tool which identifies branches differently - e.g., with expression
#   strings - may require a more complicated script (for example: to handle
#   function calls with commas in the expression).
#
#   --branch: support branch filtering:
#             handle "$callback->exclude('branch', ...)" callbacks
#   --mcdc:   support MC/DC filtering:
#             handle "$callback->exclude('mcdc', ...)" callbacks
#   --callgraph: support call site filtering:
#             handle "$callback->exclude('callgraph', ...)" callbacks
#
#   If none of the --branch, --mcdc and --callgraph flags is specified, then we
#   look for all of them (this is expected to be the common case).
#
#   Branch, MC/DC and call site exclusion filtering are all extremely simple:
#   they look for a specific comment format which specifies the
#   group and expression indices which should be excluded:
#
#       - branch exclusion:
#           // LCOV_UNREACHABLE_BRANCH (expressionId[,blockId])+
#           - expressionId
#               - decimal integer which specifies which branch to exclude
#                 An error is generated if an the index is invalid
#           - blockId
#               - decimal integer which specified the block index which
#                 contains the excluded expression.
#                 An error is generated if the block index is invalid
#               - If there is only one branch block at this location,
#                 then the block ID does not need to be specified
#            One or more space-separated branch exclusions may specified.
#
#       - MC/DC exclusion:
#           // LCOV_UNREACHABLE_COND ([groupSize,]conditionId[tf])+
#           - conditionId
#               - decimal integer which specifies which condition to exclude
#                 An error is generated if an the index is invalid
#           - sense
#               - 't' or 'f': the value of the condition which is unreachable
#           - groupSize
#               - decimal integer which specified the group which contains
#                 the excluded condition.
#                 An error is generated if the groupSize is invalid
#               - If there is only one MC/DC group at this location,
#                 then the groupSize does not need to be specified.
#            One or more space-separated MC/DC exclusions may specified.
#
#       - call site exclusion:
#           // LCOV_EXCLUDE_CALL (callee[,column])*
#           - callee
#               - the name of the called function, exactly as the coverage data
#                 spells it - which is the mangled name, unless the data was
#                 collected with demangling enabled
#               - If no callee is specified, then every call written on the line
#                 is excluded
#           - column
#               - decimal integer which specifies the column the call is in
#               - If no column is specified, then every call to this callee on
#                 the line is excluded
#            Zero or more semicolon-separated call exclusions may specified.
#            Whatever follows the annotation on the line is taken to be that
#            list, so an annotation which is meant to exclude the whole line
#            must be the final entry.
#            An annotation which matches no call site is not an error:  another
#            filter may have removed the site already, and a call which is not
#            in the report is exactly the outcome the annotation asks for.
#            '--verbose' reports each call which was excluded, which is how a
#            misspelled callee name is found.
#
#    Branch, MC/DC and call site exclusion annotations can all occur on the
#    same line.
#
#    One way to determine the branch and/or condition ID in order to
#    exclude them is to generate an HTML report without exclusions then
#    hover the mouse over the colorized branch/condition region and read
#    the IDs from the tooltip popup.
#    Another way is to simply read the BRDA/MCDC entries in coverage data
#    file.

package unreach;
use strict;
use warnings;
use File::Basename qw(dirname basename);
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use Scalar::Util qw(looks_like_number);
use lcovutil;

# The coverpoint types we know how to exclude, in the order the end-of-run
#   summary reports them:  the type name lcov asks about, the name to call it in
#   a message, and the suffix which makes that name plural.
# A list rather than three named scalars because everything below - the enable
#   flags, the saved counters, the summary - is the same operation once per type
use constant TYPES => (['branch', 'branch', 'es'],
                       ['mcdc', 'MC/DC condition', 's'],
                       ['callgraph', 'call', 's']);

sub new
{
    my $class  = shift;
    my $script = shift;

    my ($branch, $mcdc, $callgraph);
    my @args       = @_;
    my $exe        = basename($script ? $script : $0);
    my $standalone = $script eq $0;
    my $help;
    if (!GetOptionsFromArray(\@_,
                             ("branch"    => \$branch,
                              "mcdc"      => \$mcdc,
                              "callgraph" => \$callgraph,
                              'help'      => \$help)) ||
        $help ||
        scalar(@_)
    ) {
        print(STDERR <<EOF);
usage: $exe
       [--branch]
       [--mcdc]
       [--callgraph]*

Branch, MC/DC and call site filtering are all selected if none of the flags is
specified.
See the comment at the top of $script for more details.
EOF

        exit($help && 0 == scalar(@_) ? 0 : 1) if $standalone;
        return undef;
    }
    unless (defined($branch) || defined($mcdc) || defined($callgraph)) {
        $branch    = $lcovutil::br_coverage;
        $mcdc      = $lcovutil::mcdc_coverage;
        $callgraph = $lcovutil::callgraph_coverage;
    }
    unless ($lcovutil::br_coverage ||
            $lcovutil::mcdc_coverage ||
            $lcovutil::callgraph_coverage) {
        lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
            "--unreachable-script has no effect without --branch, --mcdc or --callgraph-coverage"
        );
    }

    # Each type we are going to answer for:  the annotation which names its
    #   exclusions, and the [coverpoint, line] counters the summary prints.
    #   A type which is switched off - by us or by the tool - is simply absent
    my $self = {};
    $self->{branch} = [
        qr/LCOV_UNREACHABLE_BRANCH\s+([0-9]+(,[0-9]+)?\s*(;\s*[0-9]+(,[0-9]+)?)*)/,
        [0, 0]
        ]
        if $branch && $lcovutil::br_coverage;
    $self->{mcdc} = [
        qr/LCOV_UNREACHABLE_COND\s+([0-9]+(,[0-9]+)?([tf])\s*(;\s*[0-9]+(,[0-9]+)?[tf])*)/,
        [0, 0]
        ]
        if $mcdc && $lcovutil::mcdc_coverage;
    # The callee name is a symbol rather than an integer, so it is matched as
    #   'anything but a separator'
    # The whole list is optional. an annotation with nothing after it excludes
    #   every call on the line
    my $callRe =
        qr/LCOV_EXCLUDE_CALL\s*([^\s,;]+(,[0-9]+)?(\s*;\s*[^\s,;]+(,[0-9]+)?)*)?/;
    $self->{callgraph} = [$callRe, [0, 0]]
        if $callgraph && $lcovutil::callgraph_coverage;

    return bless $self, $class;
}

sub exclude_branch
{
    # 'offset' is the location of the annotated line, relative to 'leader',
    #   the line which holds 'brdata' - see BranchBlock::locationOffset.  The
    #   default block is the first one written there
    my ($self, $map, $brdata, $blockId, $idx, $leader, $offset) = @_;
    my $line = $leader + $offset;
    unless (defined($blockId)) {
        my ($first) =
            grep({ $_->locationOffset() == $offset } $brdata->blocks(1));
        return 0 unless defined($first);
        $blockId = $first->idx();
    }
    my $block = $brdata->getBlock($blockId);
    my $br    = $block->getElement($idx);
    my $rtn   = 0;
    if ($br->set_excluded()) {
        lcovutil::info(1, "$line: excluded branch $blockId, $idx\n");
        $map->adjust_counts(-1, (0 != $br->count()) ? -1 : 0);
        $rtn = 1;
    }
    return $rtn;
}

sub exclude_cond
{
    # 'offset' is the location of the annotated line - see exclude_branch and
    #   MCDC_Block::groupKey
    my ($self, $map, $mcdc, $groupSize, $expr, $sense, $leader, $offset) = @_;
    my $line = $leader + $offset;
    unless (defined($groupSize)) {
        my @keys =
            grep({ (MCDC_Block::parseGroupKey($_))[1] == $offset }
                 keys(%{$mcdc->groups()}));
        return 0 unless @keys;
        die("$line: must specify group size if multiple groups exist")
            unless 1 == scalar(@keys);
        $groupSize = $keys[0];
    } else {
        $groupSize = MCDC_Block::groupKey($groupSize, $offset);
    }
    my $size  = (MCDC_Block::parseGroupKey($groupSize))[0];
    my $group = $mcdc->expressions($groupSize);
    die("$line: invalid group $size") unless defined($group);

    my $cond = $mcdc->expr($groupSize, $expr);
    my $rtn  = 0;
    if ($cond->set_excluded($sense)) {
        lcovutil::info(1, "$line: excluded cond $size,$expr,$sense\n");
        $map->adjust_counts(-1, (0 != $cond->count()) ? -1 : 0);
        $rtn = 1;
    }
    return $rtn;
}

sub exclude_calls
{
    # The 'callgraph' pass:  drop each call site whose line carries an
    #   annotation naming the callee it calls.
    # Walk the call sites and look at the line each one is on, rather than
    #   walking the source and looking for an annotated line:  most lines have no
    #   call on them, and a file's sites are already indexed by where they are.
    # Unlike the branch and MC/DC passes, this is called once for the whole
    #   file rather than once per testcase - removing a site is destructive, so
    #   asking again per testcase would be asking about sites which are gone -
    #   and so it removes from the per-testcase maps itself, through
    #   'lcovutil::excludeCallSite'
    my ($self, $re, $count, $reader, $testdata, $summary) = @_;
    my $changed = 0;
    my %lines;
    foreach my $funcKey ($summary->keylist()) {
        my $entry = $summary->findKey($funcKey);
        next unless defined($entry);
        foreach my $siteKey ($entry->sortedCallSiteKeys()) {
            my ($line, $column, $ordinal, $siteCount, $callee, $file) =
                $entry->callSiteData($siteKey);
            # A call written in some other file - an inline function's body, say.
            #   '$line' is a line of that file, and the source we were handed is
            #   not that file:  we have nothing to read the annotation from
            next if !defined($line) || defined($file);
            my $source = $reader->getLine($line);
            next unless defined($source) && $source =~ $re;
            # An annotation with no list excludes every call on the line, which
            #   is the empty list of names matching anything rather than nothing
            my @exclude = defined($1) ? split(/\s*;\s*/, $1) : ();
            my $match   = !@exclude;
            foreach my $e (@exclude) {
                $e =~ /^\s*([^\s,]+)(,([0-9]+))?\s*$/ or
                    die("did not match call regexp: $e");
                next unless $1 eq $callee;
                next if defined($3) && $3 != $column;
                $match = 1;
                last;
            }
            next unless $match;
            next
                unless lcovutil::excludeCallSite($testdata, $summary,
                                                 $funcKey, $siteKey);
            lcovutil::info(1,
                      "excluded call to '$callee' at $line:$column:$ordinal\n");
            $changed = 1;
            ++$count->[0];
            $lines{$line} = 1;
        }
    }
    $count->[1] += scalar(keys(%lines));
    return $changed;
}

sub exclude
{
    my ($self, $type, $reader, $testdata, $summary) = @_;
    my $d = $self->{$type};
    return 0
        unless ($reader->notEmpty() && defined($d));
    my ($re, $count) = @$d;

    return $self->exclude_calls($re, $count, $reader, $testdata, $summary)
        if $type eq 'callgraph';

    my $changed = 0;
    foreach my $leader ($summary->keylist()) {
        # the annotation is on the line the block or group is written at,
        #   which is not always the line which holds it - see
        #   BranchBlock::locationOffset
        my $data    = $summary->value($leader);
        my %offsets = (0 => 1);
        $offsets{$_} = 1
            foreach ($type eq 'branch' ?
                     map({ $_->locationOffset() } $data->blocks()) :
                     $data->locationOffsets());
        foreach my $offset (sort({ $a <=> $b } keys(%offsets))) {
            $changed = 1
                if $self->_excludeAt($type, $re, $count, $reader, $testdata,
                                     $summary, $leader, $offset);
        }
    }
    return $changed;
}

sub _excludeAt
{
    # apply the annotation of line 'leader + offset' to the data of line
    #   'leader' which is written there
    my ($self, $type, $re, $count, $reader,
        $testdata, $summary, $leader, $offset) = @_;
    my $changed = 0;
    my $line    = $leader + $offset;
    my $source  = $reader->getLine($line);
    return 0
        unless (defined($source) && $source =~ $re);
    my @exclude = split(/\s*;\s*/, $1);
    die("no $type regexp match in line $line '$source'") unless @exclude;
    my $found = 0;

    if ($type eq 'branch') {
        lcovutil::info(1,
              "$line: exclude_branch $line str: " . join(' ', @exclude) . "\n");
        foreach my $e (@exclude) {
            $e =~ /^\s*(([0-9]+),)?([0-9]+)\s*$/ or
                die("did not match branch regexp: $e");
            my $block = defined($1) ? $2 : undef;
            my $expr  = $3;
            if ($self->exclude_branch($summary, $summary->value($leader),
                                      $block, $expr,
                                      $leader, $offset
            )) {
                $changed = 1;
                ++$count->[1]
                    unless $found;
                $found = 1;
                ++$count->[0];
            }
            foreach my $testname ($testdata->keylist()) {
                my $d  = $testdata->value($testname);
                my $br = $d->value($leader);
                # this testcase might not contain the branch
                next unless defined($br);
                $changed = 1
                    if $self->exclude_branch($d, $br, $block, $expr, $leader,
                                             $offset);
            }
        }
    } else {
        lcovutil::info(1,
                       "exclude_cond $line str: " . join(' ', @exclude) . "\n");
        foreach my $e (@exclude) {
            $e =~ /^\s*(([0-9]+),)?([0-9]+)([tf])\s*$/ or
                die("did not match MC/DC regexp: $e");
            my $group = defined($1) ? $2 : undef;
            my $idx   = $3;
            my $sense = $4 eq 't';

            if ($self->exclude_cond($summary, $summary->value($leader),
                                    $group, $idx, $sense, $leader, $offset)) {
                $changed = 1;
                ++$count->[1]
                    unless $found;
                $found = 1;
                ++$count->[0];
            }
            foreach my $testname ($testdata->keylist()) {
                my $d    = $testdata->value($testname);
                my $cond = $d->value($leader);
                next unless defined($cond);
                $changed = 1
                    if $self->exclude_cond($d, $cond, $group, $idx, $sense,
                                           $leader, $offset);
            }
        }
    }
    return $changed;
}

sub _counters
{
    # my [coverpoint, line] counters, for the types which are enabled, in TYPES
    #   order - which is what makes 'save' and 'restore' agree about which
    #   counter is which
    my $self = shift;
    return
        map({ $self->{$_->[0]}->[1] }
            grep({ defined($self->{$_->[0]}) } TYPES));
}

sub start
{
    my $self = shift;
    foreach my $c ($self->_counters()) {
        $c->[0] = 0;
        $c->[1] = 0;
    }
}

sub save
{
    my $self = shift;
    return [$self->_counters()];
}

sub restore
{
    my ($self, $data) = @_;
    foreach my $count ($self->_counters()) {
        my $d = shift(@$data);
        $count->[0] += $d->[0];
        $count->[1] += $d->[1];
    }
}

sub finalize
{
    my $self = shift;
    foreach my $t (TYPES) {
        my ($type, $name, $plural) = @$t;
        my $l = $self->{$type};
        next unless defined($l);
        my $count = $l->[1];
        my $pt    = $count->[0] != 1 ? $plural : '';
        my $pl    = $count->[1] != 1 ? 's' : '';
        lcovutil::info("Excluded " .
                       $count->[0] .
                       " $name$pt from " .
                       $count->[1] .
                       " line$pl.\n");
    }
}

1;
