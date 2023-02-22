#!/bin/env perl

use strict;
use warnings;
use DateTime;
use POSIX qw(strftime);

my $file      = $ARGV[0];
my $annotated = $file . ".annotated";
my $now       = DateTime->now();

if (open(HANDLE, '<', $annotated)) {
    while (my $line = <HANDLE>) {
        chomp $line;
        $line =~ s/\r//g;    # remove CR from line-end
        my ($commit, $who, $days, $text) = split(/\|/, $line, 4);
        my $duration = DateTime::Duration->new(days => $days);
        my $date     = $now - $duration;

        printf("%s|%s|%s|%s\n", $commit, $who, $date, $text);
    }
    close(HANDLE) or die("unable to close $annotated: $!");
} else {
    die("unable to open $annotated: $!");
}
