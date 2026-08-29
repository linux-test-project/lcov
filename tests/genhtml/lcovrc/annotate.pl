#!/usr/bin/env perl

# Annotate each line of the file with the owner named on the corresponding line
#   of '<file>.owners', so that the test controls exactly which owners have
#   un-exercised code and which have none.
# The date is the same for every line:  these tests are about the owner tables,
#   and a fixed date keeps the age bins out of the comparison.

use strict;
use warnings;

my $file   = $ARGV[0];
my $owners = $file . '.owners';

open(OWNERS, '<', $owners) or die("unable to open $owners: $!");
my @owner = <OWNERS>;
close(OWNERS) or die("unable to close $owners: $!");
chomp(@owner);

open(SOURCE, '<', $file) or die("unable to open $file: $!");
my $lineNo = 0;
while (my $line = <SOURCE>) {
    chomp($line);
    $line =~ s/\015$//;    # remove CR from line end
    die("no owner for $file:" . ($lineNo + 1)) unless $lineNo <= $#owner;
    printf("%s|%s|%s|%s\n",
           'commit' . ($lineNo + 1), $owner[$lineNo],
           '2024-01-15T09:30:00+00:00', $line);
    ++$lineNo;
}
close(SOURCE) or die("unable to close $file: $!");
