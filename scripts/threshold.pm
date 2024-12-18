#!/usr/bin/env perl

#   Copyright (c) MediaTek USA Inc., 2024
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
# threshold
#
#   This is a simple example of a '--criteria-script' to be used by
#   lcov/geninfo/genhtml.
#   It can be called at any level of hierarchy - but is really expected to be
#   called at the 'file' or 'top' level, in lcov or geninfo.
#   It simply checks that the 'type' coverage (line, branch, function) exceeds
#   the threshold.
#
#   Format of the JSON input is:
#     {"line":{"found":10,"hit:2,..},"function":{...},"branch":{}"
#   Only non-zero elements are included.
#   See the 'criteria-script' section in "man genhtml" for details.
#
#   If passed the "--suppress" flag, this script will exit with status 0,
#   even if the coverage criteria is not met.
#
#   Example usage:
#
#    - minimum acceptable line coverage = 85%, branch coveage = 70%,
#      function coverage (of unique functions) = 100%
#      "--rc criteria_callback_levels=top" parameter causes genhtml to execute
#      the callback only at the top level (i.e., not also at every file)
#

#     genhtml --criteria-script $LCOV_HOME/share/lcov/support-scripts/threshold.pm,--line,85,--branch,70,--function,100 --rc criteria_callback_levels=top ...
#
#   It is not hard to envision much more complicated coverage criteria.

package threshold;

use strict;
use JSON;
use Getopt::Long qw(GetOptionsFromArray);
use Scalar::Util qw/looks_like_number/;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(new);

use constant {SIGNOFF => 0,};

sub new
{
    my $class      = shift;
    my $signoff    = 0;
    my $script     = shift;
    my $standalone = $script eq $0;
    my @options    = @_;
    my ($line, $function, $branch, $mcdc);

    if (!GetOptionsFromArray(\@_,
                             ('signoff'    => \$signoff,
                              'line=s'     => \$line,
                              'branch=s'   => \$branch,
                              'mcdc=s'     => \$mcdc,
                              'function=s' => \$function,)) ||
        (!$standalone && @_)
    ) {
        print(STDERR "Error: unexpected option:\n  " .
                join(' ', @options) .
                "\nusage: name type json-string [--signoff] [--line l_threshold] [--branch b_threshold] [--function f_threshold] [--mcdc -m_threshold]\n"
        );
        exit(1) if $standalone;
        return undef;
    }
    my %thresh;
    $thresh{line}     = $line if defined($line);
    $thresh{branch}   = $branch if defined($branch);
    $thresh{function} = $function if defined($function);
    $thresh{mcdc}     = $mcdc if defined($mcdc);
    die("$script:  must specify at least of of --line, --branch, --function, --mcdc"
    ) unless (%thresh);
    foreach my $key (keys %thresh) {
        my $v = $thresh{$key};
        die("unexpected $key threshold '$v'")
            unless looks_like_number($v) && 0 < $v && $v <= 100;
    }
    my $self = [$signoff, \%thresh];

    return bless $self, $class;
}

sub check_criteria
{
    my ($self, $name, $type, $db) = @_;

    my $fail = 0;
    my @messages;

    foreach my $key (sort keys %{$self->[1]}) {
        next unless exists($db->{$key});

        my $map   = $db->{$key};
        my $found = $map->{found};
        next if $found == 0;
        my $hit    = $map->{hit};
        my $v      = 100.0 * $hit / $found;
        my $thresh = $self->[1]->{$key};

        if ($v < $thresh) {
            $fail = 1;
            push(@messages, sprintf("$key: %0.2f < %0.2f", $v, $thresh));
        }
    }
    return ($fail && !$self->[SIGNOFF], \@messages);
}

1;
