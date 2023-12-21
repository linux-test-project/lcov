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
#    [--owner regexp]* line_data annotate_data
#
#   This is a sample 'genhtml --select-script' callback - used to decide
#   whether a particular line information is interesting - and thus should
#   be included in the coverage report or not.
#
#   --tla: is a (possibly comma-separated list of) differential categories
#     which should be retained:
#        select.pm --tla LBC,UNC,UIC ...
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
};

sub new
{
    my $class  = shift;
    my $script = shift;

    my (@range, @tla, @owner);
    my @args = @_;
    my $exe  = basename($script ? $script : $0);
    my $help;
    if (!GetOptionsFromArray(\@_,
                             ("range:s" => \@range,
                              'tla:s'   => \@tla,
                              'owner:s' => \@owner,
                              'help'    => \$help)) ||
        $help ||
        0 == scalar(@args)    # expect at least one selection  criteria
    ) {
        print(STDERR
                "usage: $exe [--range min_days:max_days] [--owner regexp]* [--tla tla]*\n"
        );
        exit($help ? 0 : 1) if ($script eq $0);
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
    my $self = [\@range, \@tla, \@owner];
    return bless $self, $class;
}

sub select
{
    my ($self, $lineData, $annotateData) = @_;

    my $tla = $lineData->tla();
    return 1 if grep(/$tla/, @{$self->[TLA]});

    if (defined($annotateData)) {
        my $age = $annotateData->age();
        foreach my $a (@{$self->[AGE]}) {
            return 1
                if ($age >= $a->[0] &&
                    $age <= $a->[1]);
        }

        foreach my $re (@{$self->[OWNER]}) {
            return 1 if $annotateData->full_name() =~ $re;
        }
    }
    lcovutil::info(1, "drop " . $lineData->type() . " $tla\n");
    # no match - not interesting
    return 0;
}

1;
