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
    die("die in compare_version");
}

sub annotate
{
    die("die in annotate");
}

sub resolve
{
    die("die in resolve");
}

sub check_criteria
{
    die("die in check_criteria");
}

sub simplify
{
    die("die in simplify");
}

1;
