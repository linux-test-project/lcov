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

exit(0);
