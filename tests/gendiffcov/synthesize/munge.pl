use strict;

while (<>) {
  if (/LF:(\d+)$/) {
    print("DA:71,1\nDA:74,0\nLF:", $1 + 2, "\n");
  } elsif (/(BR|FN|L)H:(\d+)$/) {
    print($1, "H:", $2 + 1, "\n");
  } elsif (/FNF:([0-9]+)$/) {
    print("FN:71,73,outOfRangeFnc\nFNDA:1,outOfRangeFnc\nFNF:", $1 + 1, "\n");
  } elsif (/BRF:([0-9]+)$/) {
    print("BRDA:71,0,0,0\nBRDA:71,0,1,1\nBRF:", $1 + 2, "\n");
  } else {
    print;
  }
}
