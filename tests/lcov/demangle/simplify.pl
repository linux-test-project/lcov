#!/usr/bin/env perl
use strict;

my $name = shift;
$name =~ s/Animal::Animal/subst1/;
$name =~ s/Cat::Cat/subst2/;
$name =~ s/subst2/subst3/;

print $name;
exit 0;

