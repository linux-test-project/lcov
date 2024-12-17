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
#   When multiple selection criteria are applied (e.g., both age and owner),
#   then The coverpoint is retained if any of criteria match.
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
              AGE   => 0,
              TLA   => 1,
              OWNER => 2,
              SHA   => 3,
};

sub new
{
    my $class  = shift;
    my $script = shift;

    my (@range, @tla, @owner, @sha);
    my @args       = @_;
    my $exe        = basename($script ? $script : $0);
    my $standalone = $script eq $0;
    my $help;
    if (!GetOptionsFromArray(\@_,
                             ("range:s"  => \@range,
                              'tla:s'    => \@tla,
                              'owner:s'  => \@owner,
                              'sha|cl:s' => \@sha,
                              'help'     => \$help)) ||
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

Line is selected (return true) if any of the criteria match
EOF

        exit($help && 0 == scalar(@_) ? 0 : 1) if $standalone;
        return undef;
    }
    # precompile:
    foreach my $re (@owner) {
        eval { $re = qr($re); };
        if ($@) {
            die("Invalid 'owner' regexp $re in \"$exe " .
                join(' ', @args) . '"');
        }
    }
    @sha = split(',', join(',', @sha));
    @tla = split(',', join(',', @tla));
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
    }
    my $self = [\@range, \@tla, \@owner, \@sha];
    return bless $self, $class;
}

sub select
{
    my ($self, $lineData, $annotateData, $filename, $lineNo) = @_;

    if (defined($lineData)) {
        # this line might not have coverage data, if genhtml is checking
        # for a contiguous region of context lines (e.g., which are part
        # of some SHA) which are not code and thus have no data
        my $tla = $lineData->tla();
        return 1 if grep({ $tla eq $_ } @{$self->[TLA]});
    }

    if (defined($annotateData)) {
        my $age = $annotateData->age();
        return 1
            if grep({ $age >= $_->[0] && $age <= $_->[1] } @{$self->[AGE]});

        my $commit = $annotateData->commit();
        # match at head of commit ID string
        return 1
            if (defined($commit) &&
                '' ne $commit &&
                grep({ $commit =~ /^$_/ } @{$self->[SHA]}));

        my $fullname = $annotateData->full_name();
        return 1 if grep({ $fullname =~ $_ } @{$self->[OWNER]});
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

1;
