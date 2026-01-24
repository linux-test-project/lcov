#!/usr/bin/env perl

#   Copyright (c) MediaTek USA Inc., 2023
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
# select.pm [--tla tla[,tla]*]* [--range min_days:mex_days] \
#    [--owner regexp]* [--(sha|cl) id]* line_data annotate_data
#
#   This is a sample 'genhtml --select-script' callback - used to decide
#   whether a particular line information is interesting - and thus should
#   be included in the coverage report or not.
#
#   --tla: is a (possibly comma-separated list of) differential categories
#     which should be retained:
#        select.pm --tla LBC,UNC,UIC ...
#
#   --sha/--cl:  is a (possibly comma-separated list of) git SHAs or
#     perforce changelists which should be retained.
#     Match checks that the provided string matches the leading characters
#     of the full SHA or changelist.
#
#   --range: is a time period such that only code written or changed
#     within the specified period is retained.
#     One or more ranges may be specified either by using the argument
#     multiple times or by passing a comma-separted list of ranges.
#      select.pm --range 5:10,12:15 ...
#
#   --owner: is a regular expression.  A coverpoint is retained if its
#     "full name" field matches the regexp.
#
#   --separator: is a character/regexp used to split 'list' arguments
#     (such as '--tla ..', '--sha ...', etc.
#     This may be useful to pass a delimited list to select.pm arguments
#     in a comma-separated list of genhaml arguments - for example:
#        genhtml ... --select-script select,pm,--sep,;,--tla,LBC;UNC
#
#   When multiple selection criteria are applied (e.g., both age and owner),
#   then The coverpoint is retained if any of criteria match.
#
#   Note that the count of total coverpoints in the final summary includes
#   both deleted (DCB, DUB) and excluded (ECB, EUB) coverpoints, and so
#   may be a higher number than you expect if you had been looking only
#   at the line coverage percentage in the complete report
#
#   Note that you --owner and --age require that source data is annotated -
#     see the --annotate-script section of the genhtml man page.
#

package select;
use strict;
use File::Basename qw(dirname basename);
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use Scalar::Util qw(looks_like_number);
use lcovutil;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(new);

use constant {
              AGE       => 0,
              OWNER     => 1,
              SHA       => 2,
              TLA       => 3,
              COUNTS    => 4,
              PLAINTEXT => 5,
              TOTAL     => 6,
};

sub intersect
{
    my $l = shift;
    my $m = shift;

    my %contains;
    @contains{@$l} = (1) x @$l;

    return grep { $contains{$_} } @$m;
}

sub new
{
    my $class  = shift;
    my $script = shift;

    my (@range, @tla, @owner, @sha);
    my @args       = @_;
    my $exe        = basename($script ? $script : $0);
    my $standalone = $script eq $0;
    my $help;
    my $delim = ',';
    if (!GetOptionsFromArray(\@_,
                             ("range:s"     => \@range,
                              'tla:s'       => \@tla,
                              'owner:s'     => \@owner,
                              'sha|cl:s'    => \@sha,
                              'separator:s' => \$delim,
                              'help'        => \$help)) ||
        $help ||
        (!$standalone && 0 != scalar(@_)) ||
        0 == scalar(@args)    # expect at least one selection  criteria
    ) {
        print(STDERR <<EOF);
usage: $exe
       [--range min_days:max_days]
       [--owner regexp]*
       [--tla tla]*
       [--sha sha]*
       [--cl changelist]*
       [--separator char]

Line is selected (return true) if any of the criteria match
EOF

        exit($help && 0 == scalar(@_) ? 0 : 1) if $standalone;
        return undef;
    }
    my @plaintext = ([], [], []);
    # precompile:
    @sha = split($delim, join($delim, @sha));
    foreach my $d (['owner', OWNER, \@owner], ['sha', SHA, \@sha]) {

        my ($name, $idx, $list) = @$d;
        my $matchHead = $idx == SHA ? '^' : '';
        foreach my $re (@$list) {
            push(@{$plaintext[$idx]}, $re);
            eval { $re = qr($matchHead$re); };
            if ($@) {
                die("Invalid '$name' regexp $re in \"$exe " .
                    join(' ', @args) . '"');
            }
        }
    }
    @tla   = split($delim, join($delim, @tla));
    @range = split($delim, join($delim, @range));
    foreach my $tla (@tla) {
        die("invalid tla '$tla' in \"$exe " . join(' ', @args) . '"')
            unless grep(/$tla/, keys(%lcovutil::tlaColor));
    }
    foreach my $range (@range) {
        my ($min, $max) = split(':', $range, 2);
        foreach my $d ($min, $max) {
            die("expected number of days - found '$d' in \"$exe " .
                join(' ', @args) . '"')
                unless looks_like_number($d);
        }
        die("expected $min <= $max in \"$exe " . join(' ', @args) . '"')
            unless $min <= $max;
        $range = [$min, $max];
        push(@{$plaintext[1]}, "$min - $max days");
    }
    # some error checking:
    #  - can't look for date range, CL/SHA, or owner if there are no
    #    annotations (so verify that there is an annotation script).
    #  - without baseline data, there will be no coverage data other
    #    than GNC, UNC.
    #  - without 'diff' data, there will be no coverage data in
    #    GNC, UNC, DUB, or DCB categories
    if (!@SourceFile::annotateScript && (@range || @owner || @sha)) {
        lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                    "cannot select date/owner/SHA without '--annotate-script'");
    }
    my @intersect = intersect(['UBC', 'GBC', 'LBC', 'CBC', 'ECB', 'EUB',
                               'GIC', 'UIC', 'DCB', 'DUB'
                              ],
                              \@tla) unless @main::base_filenames;
    lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
        "Will never see TLA other than 'UNC', 'GNC' without 'baseline' coverage data"
    ) if (@intersect);

    my @intersect2 = intersect(['GNC', 'UNC', 'DCB', 'DUB'], \@tla)
        unless $main::diff_filename;
    lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                              "Will never see '" .
                                  join("', '", @intersect2) . "' " .
                                  ($#intersect2 ? 'categories' : 'category') .
                                  ' without --diff-file data')
        if (@intersect2);

    my $self = [\@range,
                \@owner,
                \@sha,
                \@tla,
                [[(0) x scalar(@range)],
                 [(0) x scalar(@tla)],
                 [(0) x scalar(@owner)],
                 [(0) x scalar(@sha)]
                ],
                \@plaintext,
                0
    ];

    return bless $self, $class;
}

sub _check_match
{
    my ($self, $matches, $idx) = @_;
    if (@$matches) {
        my $counts = $self->[COUNTS]->[$idx];
        foreach my $i (@$matches) {
            ++$counts->[$i];
        }
        return 1;
    }
    return 0;
}

sub select
{
    my ($self, $lineData, $annotateData, $filename, $lineNo) = @_;

    if (defined($lineData)) {
        # this line might not have coverage data, if genhtml is checking
        # for a contiguous region of context lines (e.g., which are part
        # of some SHA) which are not code and thus have no data
        ++$self->[TOTAL];    # increment count of coverpoints we saw
        my $tla     = $lineData->tla();
        my $list    = $self->[TLA];
        my @matches = grep({ $list->[$_] eq $tla } 0 .. $#$list);
        return 1 if $self->_check_match(\@matches, TLA);
    }

    if (defined($annotateData)) {
        my $age     = $annotateData->age();
        my $list    = $self->[AGE];
        my @matches = grep({ $list->[$_] == $age } 0 .. $#$list);
        return 1 if $self->_check_match(\@matches, AGE);

        # match at head of commit ID string
        my $commit = $annotateData->commit();
        if (defined($commit) &&
            '' ne $commit) {
            my $list    = $self->[SHA];
            my @matches = grep({ $commit =~ $list->[$_] } 0 .. $#$list);
            return 1 if $self->_check_match(\@matches, SHA);
        }

        my $fullname = $annotateData->full_name();
        my $list     = $self->[OWNER];
        @matches = grep({ $fullname =~ $list->[$_] } 0 .. $#$list);
        return 1 if $self->_check_match(\@matches, OWNER);
    }
    lcovutil::info(1,
                   "drop "
                       .
                       (defined($lineData) ?
                            $lineData->type() . ' ' . $lineData->tla() :
                            "$filename:$lineNo") .
                       "\n");
    # no match - not interesting
    return 0;
}

sub save
{
    my $self = shift;
    return [$self->[TOTAL], $self->[COUNTS]];
}

sub restore
{
    my ($self, $data) = @_;
    $self->[TOTAL] += $data->[TOTAL];
    foreach my $i (0 .. $#$data) {
        my $l = $self->[COUNTS]->[$i];
        foreach my $j (0 .. $#$l) {
            $l->[$j] += $data->[$i]->[$j];
        }
    }
}

sub finalize
{
    my $self = shift;
    lcovutil::info(-1,
                   "select.pm criteria match counts:\n  saw " .
                       $self->[TOTAL] . ' coverpoint' .
                       (1 == $self->[TOTAL] ? '' : 's') . "\n");
    foreach my $d (['tla', TLA, $self->[TLA]],
                   ['range', AGE, $self->[PLAINTEXT]->[AGE]],
                   ['sha', SHA, $self->[PLAINTEXT]->[SHA]],
                   ['owner', OWNER, $self->[PLAINTEXT]->[OWNER]]
    ) {
        my ($name, $idx, $strings) = @$d;
        my $list = $self->[$idx];
        next unless @$list;

        my $counts = $self->[COUNTS]->[$idx];
        lcovutil::info(-1, "  $name:\n");
        for my $i (0 .. $#$list) {
            lcovutil::info(-1,
                        '    ' . $strings->[$i] . ' : ' . $counts->[$i] . "\n");
        }
    }
}

1;
