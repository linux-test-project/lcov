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
# hacky callback to generate an error - to test error handling of
# --expect-message-count callback.

package MsgContext;

use strict;
use Getopt::Long qw(GetOptionsFromArray);
use lcovutil;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(new);

our $call_count = 0;

sub new
{
    my $class      = shift;
    my $script     = shift;
    my $standalone = $script eq $0;
    my @options    = @_;
    my $comment;

    my $self = [$script];

    return bless $self, $class;
}

sub test
{
    my $v = shift;
    ++$call_count;

    die("trying to die in callback") if $call_count > 1;
    return 1;    # otherwise OK
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
