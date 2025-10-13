#!/usr/bin/end perl

#   Copyright (c) MediaTek USA Inc., 2025
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
# simplify.pm [--file pattern_file] [--re regexp] [--separator sep_char]
#
#   This is a sample 'genhtml --simplify-script' callback - used to decide
#   whether shorten the (possibly demangled) function names displayed in the
#   'function detail' tables.
#   Note that the simplified names are ONLY used in the table - the
#   coverage DB is not affected - so, for example '--erase-function'
#   regexps must match the actual (possibly demangled) name of the function.
#
#   --file: is the name of a file containing Perl regexpe, one per line
#
#   --re:  is a perl regexp or 'sep_char' separated list of regexps.
#
#   --separator: is the character used to separate the list of regexpe.
#               (',' is probably a poor choice as perl regexps often contain
#               comma.

package simplify;

use strict;
use Getopt::Long qw(GetOptionsFromArray);
use File::Basename qw(dirname basename);
use lcovutil;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(new);

sub new
{
    my $class  = shift;
    my $script = shift;
    my (@patterns, $file, $sep);
    my @args       = @_;
    my $exe        = basename($script ? $script : $0);
    my $standalone = $script eq $0;
    my $help;
    if (!GetOptionsFromArray(\@_,
                             ("file:s"      => \$file,
                              'separator:s' => \$sep,
                              're:s'        => \@patterns,
                              'help'        => \$help)) ||
        $help                             ||
        (!$standalone && 0 != scalar(@_)) ||
        0 == scalar(@args)                ||    # expect at least one pattern
        (@patterns && $file)              || !(@patterns || $file)
    ) {
        print(STDERR <<EOF);
usage: $exe
       [--file regexp_file_name]
       OR
       [--re regexp]*
       [--separator separator_char]

Regexps are applied in order of specificication.
EOF

        exit($help && 0 == scalar(@_) ? 0 : 1) if $standalone;
        return undef;
    }

    if ($file) {
        open(HANDLE, "<", $file) or
            die("cannot open pattern file $file: $!\n");
        while (<HANDLE>) {
            chomp;
            next if /^#/ || !$_;    # skip comment and blank
            push(@patterns, $_);
        }
        close(HANDLE) or die("unable to close pattern file handle: $!\n");
    } elsif (defined($sep)) {
        @patterns = split($sep, join($sep, @patterns));
    }

    # verify that the patterns are valid...
    lcovutil::verify_regexp_patterns($script, \@patterns);
    my @munged = map({ [$_, 0]; } @patterns);

    return bless \@munged, $class;
}

sub simplify
{
    my ($self, $name) = @_;

    foreach my $p (@$self) {
        my $orig = $name;
        # sadly, no support for pre-compiled patterns
        eval "\$name =~ $p->[0] ;";    # apply pattern that user provided...
            # $@ should never match:  we already checked pattern validity during
            #   initialization - above.  Still: belt and braces.
        die("invalid 'simplify' regexp '$p->[0]': $@")
            if ($@);
        ++$p->[1]
            if ($name ne $orig);
    }
    return $name;
}

sub start
{
    my $self = shift;
    foreach my $p (@$self) {
        $p->[1] = 0;
    }
}

sub save
{
    my $self = shift;
    my @data;
    foreach my $p (@$self) {
        push(@data, $p->[1]);
    }
    return \@data;
}

sub restore
{
    my ($self, $data) = @_;
    die("unexpected restore: (" .
        join(' ', @$self) . ") <- [" .
        join(' ', @$data) . "]\n")
        unless $#$self == $#$data;
    for (my $i = 0; $i <= $#$self; ++$i) {
        $self->[$i]->[-1] += $data->[$i];
    }
}

sub finalize
{
    my $self = shift;
    lcovutil::warn_pattern_list("simplify", $self);
}

1;
