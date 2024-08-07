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
# context
#
#   This script is used as a lcov/geninfo/genhtml "--context-script context" callback.
#   It is called at the end of tool execution to collect and store data which
#   might be useful for infrastructure debugging and/or tracking.
#
#   The result is a hash of key/value pairs - see man genhtml(1) for more
#    details.
#
#   You may want to collect and entirely different set of data.
#   You can also add operations to the constructor to do something earlier in
#   processing - e.g., to write data to some other files(s), etc.

package context;

use strict;
use Getopt::Long qw(GetOptionsFromArray);
use lcovutil;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(new);

sub new
{
    my $class      = shift;
    my $script     = shift;
    my $standalone = $script eq $0;
    my @options    = @_;
    my $comment;

    if (!GetOptionsFromArray(\@_, ('comment' => \$comment)) ||
        (!$standalone && @_)) {
        print(STDERR "Error: unexpected option:\n  " .
              join(' ', @options) . "\nusage: [--comment]\n");
        exit(1) if $standalone;
        return undef;
    }
    my $self = [$script];

    $self = bless $self, $class;
    if ($comment) {
        # 'genhtml' and certain 'lcov' modes do not write a '.info' file
        # so the comments won't go anywhere
        my $data = $self->context();
        foreach my $key (sort keys %$data) {
            push(@lcovutil::comments, $key . ': ' . $data->{$key});
        }
    }

    return $self;
}

sub context
{
    my $self = shift;

    my %data;
    $data{user}         = `whoami`;
    $data{perl_version} = $^V->{original};
    $data{perl}         = `which perl`;
    $data{PERL5LIB}     = $ENV{PERL5LIB}
        if exists($ENV{PERL5LIB});

    foreach my $k (keys %data) {
        chomp($data{$k});
    }

    return \%data;
}

1;
