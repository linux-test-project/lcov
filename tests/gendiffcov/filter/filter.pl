#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;

use lib "$FindBin::Bin/../../../lib";
use lcovutil;

foreach my $example (glob('*.c')) {
    print("checking conditional in $example\n");
    my $file = ReadCurrentSource->new($example);

    die("failed to filter bogus conditional in $example")
        if $file->containsConditional(1);
}

# check effect of configurations..
my $length = ReadCurrentSource->new("expr1.c");

$lcovutil::source_filter_lookahead = 5;
print("checking conditional in expr1.c with lookahead " .
      $lcovutil::source_filter_lookahead . " and bitwise " .
      $lcovutil::source_filter_bitwise_are_conditional . "\n");
die("source_filter_lookahad had no effect")
    unless $length->containsConditional(1);

$lcovutil::source_filter_lookahead               = 10;
$lcovutil::source_filter_bitwise_are_conditional = 1;
print("checking conditional in expr1.c with lookahead " .
      $lcovutil::source_filter_lookahead . " and bitwise " .
      $lcovutil::source_filter_bitwise_are_conditional . "\n");
die("source_filter_lookahad had no effect")
    unless $length->containsConditional(1);

exit(0);
