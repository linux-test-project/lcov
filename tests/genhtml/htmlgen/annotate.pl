#!/usr/bin/env perl

# Report an owner and a fixed date for every line of the file.
#
# Odd lines are attributed to a plain name and even lines to one which is full of
#   markup:  '&', '"' and '<' are all ordinary in an organisation name, and all
#   three end up inside an HTML attribute.  Alternating them is what puts the
#   markup name through each of the renderings the source listing has for an
#   owner - the per-line tooltip, the gutter tooltip of a line in a different
#   category from the one above it, and the owner column of a line which is not
#   the start of a block (which is every non-code line).
# The markup name is also shorter than the 20-column owner field, so that it is
#   padded when it is printed in that column:  padding is a count of columns in
#   the rendered page, so it has to be applied before the name is escaped.
# The date is fixed so that nothing in these tests depends on when they run.

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
           $lineNo % 2 ? 'plain.owner' : 'R&D "lead" <boss>',
           '2024-01-15T09:30:00+00:00', $line);
}
close(SOURCE) or die("unable to close $file: $!");
