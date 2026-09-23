#!/usr/bin/env perl

# Report one owner and one fixed date for every line of the file.
#
# '--new-file-as-baseline' asks how old the file is, and the answer comes from
#   the annotation data - so the date has to be older than the baseline '.info'
#   the test writes, and it has to be the same date on every run, or the
#   date-based assertions in 'differential.sh' would depend on when the suite
#   ran.

use strict;
use warnings;

my $file = $ARGV[0];

open(SOURCE, '<', $file) or die("unable to open $file: $!");
my $lineNo = 0;
while (my $line = <SOURCE>) {
    chomp($line);
    $line =~ s/\015$//;    # remove CR from line end
    ++$lineNo;
    printf("%s|%s|%s|%s\n",
           'commit' . $lineNo,
           'an.owner', '2024-01-15T09:30:00+00:00', $line);
}
close(SOURCE) or die("unable to close $file: $!");
