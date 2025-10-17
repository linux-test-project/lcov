#!/usr/bin/env perl

# die() when callback is called - to enable error message testing

package genError;

sub new
{
    my $class = shift;
    my $self  = [@_];    # don't die if callback name is in list...
    return bless $self, $class;
}

sub select
{
    if (grep(/select/, @$self)) {
        return 1;
    }
    die("die in select");
}

my $count;

sub extract_version
{
    my $self = shift;
    if (grep(/extract/, @$self)) {
        return $count++;    # different each time..
    }
    die("die in extract_version");
}

sub compare_version
{
    my $self = shift;
    if (grep(/compare/, @$self)) {
        return 1;
    }
    die("die in compare_version");
}

sub annotate
{
    my $self = shift;
    if (grep(/annotate/, @$self)) {
        return 'abc';
    }
    die("die in annotate");
}

sub resolve
{
    my ($self, $data) = @_;
    if (grep(/resolve/, @$self)) {
        return $data;
    }
    die("die in resolve");
}

sub check_criteria
{
    my $self = shift;
    if (grep(/criteria/, @$self)) {
        return 0;
    }
    die("die in check_criteria");
}

sub simplify
{
    my ($self, $data) = @_;
    if (grep(/simplify/, @$self)) {
        return $data;
    }
    die("die in simplify");
}

1;
