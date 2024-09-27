#!/usr/bin/env perl

package brokenCallback;

sub new
{
    my $class = shift;
    my $self  = [@_];
    return bless $self, $class;
}

sub resolve
{
    my ($self, $path) = @_;
    die("dying in resolve") if scalar(@$self) <= 1 || $self->[1] eq 'die';
    return scalar(@$self) > 2 && $self->[2] eq 'present' ? $path : undef;
}

1;
