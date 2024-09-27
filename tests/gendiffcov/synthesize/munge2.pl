# remove a line coverpoint where branch is found to test synthesis method

use strict;
my $filterLine;
while (<>) {
  if (/LF:(\d+)$/) {
    print("LF:", $1 -1, "\n");
  } elsif (/(BR|FN|L)H:(\d+)$/) {
    print($1, "H:", $2 + 1, "\n");
  } elsif (/BRDA:(\d+),/) {
    $filterLine = $1 unless defined($filterLine);
    print;
  } elsif (defined($filterLine) && /^DA:$filterLine,/) {
    next;
  } else {
    print;
  }
}
