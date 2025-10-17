#!/usr/bin/env perl

# die() when callback is called - to enable error message testing

package parallelFail;

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
    my $self = shift;
    if (grep(/start/, @$self)) {
        return;
    }
    die("die in simplify");
}

sub save
{
    my $self = shift;
    if (grep(/save/, @$self)) {
        return 'abc';
    }
    die("die in save");
}

sub restore
{
    my $self = shift;
    if (grep(/restore/, @$self)) {
        return;
    }
    die("die in save");
}

sub finalize
{
    my $self = shift;
    if (grep(/finalize/, @$self)) {
        return;
    }
    die("die in finalize");
}

1;
