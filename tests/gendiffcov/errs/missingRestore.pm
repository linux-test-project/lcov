#!/usr/bin/env perl

# test 'missing restore callback' message

package missingRestore;

sub new
{
    my $class = shift;
    my $self  = [@_];    # don't die if callback name is in list...
    return bless $self, $class;
}

sub simplify
{
    my ($self, $data) = @_;
    return $data;
}

sub start
{
    die("die in simplify");
}

sub save
{
    die("die in save");
}

1;
