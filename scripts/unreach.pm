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
# unreach.pm --branch --mcdc
#
#   This is a sample '--unreachable-script' callback - used to decide whether
#   a particular branch or MC/DC condition is unreachable or not.
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
#
#   If neither --branch nor --mcdc flags is specified, then we look for
#   both (this is expected to be the common case).
#
#   Both branch and MC/DC exclusion filtering are extremely simple:
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
#    Both branch and MC/DC exclusion annotations can occur on the same line.
#
#    One way to determine the branch and/or condition ID in order to
#    exclude them is to generate an HTML report without exclusions then
#    hover the mouse over the colorized branch/condition region and read
#    the IDs from the tooltip popup.
#    Another way is to simply read the BRDA/MCDC entries in coverage data
#    file.

package unreach;
use strict;
use File::Basename qw(dirname basename);
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use Scalar::Util qw(looks_like_number);
use lcovutil;

sub new
{
    my $class  = shift;
    my $script = shift;

    my ($branch, $mcdc);
    my @args       = @_;
    my $exe        = basename($script ? $script : $0);
    my $standalone = $script eq $0;
    my $help;
    my $delim = ',';
    if (!GetOptionsFromArray(\@_,
                             ("branch" => \$branch,
                              "mcdc"   => \$mcdc,
                              'help'   => \$help)) ||
        $help ||
        scalar(@_)
    ) {
        print(STDERR <<EOF);
usage: $exe
       [--branch]
       [--mcdc]*

Both branch and MC/DC filtering is selected if neither flags is specified.
See the comment at the top of $script for more details.
EOF

        exit($help && 0 == scalar(@_) ? 0 : 1) if $standalone;
        return undef;
    }
    unless (defined($branch) || defined($mcdc)) {
        $branch = $lcovutil::br_coverage;
        $mcdc   = $lcovutil::mcdc_coverage;
    }
    lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                "--unreachable-script has no effect without --branch or --mcdc")
        unless $lcovutil::br_coverage || $lcovutil::mcdc_coverage;

    my $self = [undef, undef];
    $self->[0] = [
        qr/LCOV_UNREACHABLE_BRANCH\s+([0-9]+(,[0-9]+)?\s*(;\s*[0-9]+(,[0-9]+)?)*)/,
        [0, 0]
        ]
        if $branch && $lcovutil::br_coverage;
    $self->[1] = [
        qr/LCOV_UNREACHABLE_COND\s+([0-9]+(,[0-9]+)?([tf])\s*(;\s*[0-9]+(,[0-9]+)?[tf])*)/,
        [0, 0]
        ]
        if $mcdc && $lcovutil::mcdc_coverage;

    return bless $self, $class;
}

sub exclude_branch
{
    my ($self, $map, $brdata, $blockId, $expr, $testdata, $summary) = @_;
    my $block = $brdata->getBlock($blockId);
    die("invalid branch expr '$expr' for branch $blockId")
        if $expr > $#$block;
    my $br  = $block->[$expr];
    my $rtn = 0;
    unless ($br->is_excluded()) {
        $br->set_excluded();
        lcovutil::info(1, "excluded branch $blockId, $expr\n");
        --$map->[BranchMap::FOUND];
        --$map->[BranchMap::HIT] if 0 != $br->count();
        $rtn = 1;
    }
    return $rtn;
}

sub exclude_cond
{
    my ($self, $map, $mcdc, $groupSize, $expr, $sense) = @_;
    unless (defined($groupSize)) {
        die("must specify group size if multiple groups exist")
            unless $mcdc->num_groups() == 1;
        $groupSize = (keys(%{$mcdc->groups()}))[0];
    }
    my $group = $mcdc->expressions($groupSize);
    die("invalid group $groupSize") unless defined($group);

    my $cond = $mcdc->expr($groupSize, $expr);
    my $rtn  = 0;
    unless ($cond->is_excluded($sense)) {
        $cond->set_excluded($sense);
        lcovutil::info(1, "excluded cond $groupSize,$expr,$sense\n");
        --$map->[BranchMap::FOUND];
        --$map->[BranchMap::HIT] if 0 != $cond->count();
        $rtn = 1;
    }
    return $rtn;
}

sub exclude
{
    my ($self, $type, $reader, $testdata, $summary) = @_;
    my $d = $self->[$type eq 'mcdc'];
    return 0
        unless ($reader->notEmpty() && defined($d));
    my ($re, $count) = @$d;

    my $changed = 0;
    foreach my $line ($summary->keylist()) {
        my $source = $reader->getLine($line);
        next
            unless ($source =~ $re);
        my @exclude = split(/\s*;\s*/, $1);
        die("no $type regexp match in line $line '$source'") unless @exclude;
        my $found = 0;
        if ($type eq 'branch') {
            lcovutil::info(1,
                           "$line: exclude_branch $line str: " .
                               join(' ', @exclude) . "\n");
            foreach my $e (@exclude) {
                $e =~ /^\s*(([0-9]+),)?([0-9]+)\s*$/ or
                    die("did not match MC/DC regexp: $e");
                my $block = defined($1) ? $2 : 0;
                my $expr  = $3;
                if ($self->exclude_branch($summary, $summary->value($line),
                                          $block, $expr)) {
                    $changed = 1;
                    ++$count->[1]
                        unless $found;
                    $found = 1;
                    ++$count->[0];
                }
                foreach my $testname ($testdata->keylist()) {
                    my $d  = $testdata->value($testname);
                    my $br = $d->value($line);
                    # this testcase might not contain the branch
                    next unless defined($br);
                    $changed = 1
                        if $self->exclude_branch($d, $br, $block, $expr);
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

                if ($self->exclude_cond($summary, $summary->value($line),
                                        $group, $idx,
                                        $sense
                )) {
                    $changed = 1;
                    ++$count->[1]
                        unless $found;
                    $found = 1;
                    ++$count->[0];
                }
                foreach my $testname ($testdata->keylist()) {
                    my $d    = $testdata->value($testname);
                    my $cond = $d->value($line);
                    next unless defined($cond);
                    $changed = 1
                        if $self->exclude_cond($d, $cond, $group, $idx, $sense);
                }
            }
        }
    }
    return $changed;
}

sub start
{
    my $self = shift;
    foreach my $p (@$self) {
        next unless defined($p);
        my $c = $p->[1];
        $c->[0] = 0;
        $c->[1] = 0;
    }
}

sub save
{
    my $self = shift;
    my @data;
    foreach my $p (@$self) {
        push(@data, $p->[1]) if defined($p);
    }
    return \@data;
}

sub restore
{
    my ($self, $data) = @_;
    for (my $i = 0; $i <= $#$self; ++$i) {
        my $p = $self->[$i];
        next unless defined($p);
        my $count = $p->[1];
        my $d     = shift(@$data);
        $count->[0] += $d->[0];
        $count->[1] += $d->[1];
    }
}

sub finalize
{
    my $self = shift;
    foreach my $d (['branch', $self->[0]], ['MC/DC condition', $self->[1]]) {
        my ($type, $l) = @$d;
        next unless defined($l);
        my $count = $l->[1];
        my $pt    = $count->[0] != 1 ? ($type eq 'branch' ? 'es' : 's') : '';
        my $pl    = $count->[1] != 1 ? 's' : '';
        lcovutil::info("Excluded " .
                 $count->[0] . " $type$pt from " . $count->[1] . " line$pl.\n");
    }
}

1;
