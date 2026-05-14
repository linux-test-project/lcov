#!/usr/bin/env perl

use strict;
use warnings;
use DateTime;
use POSIX qw(strftime);

sub get_modify_time($)
{
    my $filename = shift;
    my @stat     = stat $filename;
    my $tz       = strftime("%z", localtime($stat[9]));
    $tz =~ s/([0-9][0-9])$/:$1/;
    return strftime("%Y-%m-%dT%H:%M:%S", localtime($stat[9])) . $tz;
}

my $file      = $ARGV[0];
my $annotated = $file . ".annotated";
my $now       = DateTime->now();

if (open(HANDLE, '<', $annotated)) {
    my @annotations;
    while (my $line = <HANDLE>) {
        chomp $line;
        $line =~ s/\r//g;    # remove CR from line-end
        my ($commit, $who, $days) = split(/\|/, $line, 4);
        my $duration = DateTime::Duration->new(days => $days);
        my $date     = $now - $duration;

        push(@annotations, sprintf("%s|%s|%s|", $commit, $who, $date));
    }
    close(HANDLE)       or die("unable to close $annotated: $!");
    open(HANDLE, $file) or die("unable to open $file: $!");
    my $idx = 0;
    while (my $line = <HANDLE>) {
        chomp $line;
        # Also remove CR from line-end
        $line =~ s/\015$//;
        die("mismatched annotations") unless $idx <= $#annotations;
        print($annotations[$idx++] . $line . "\n");
    }
    close(HANDLE) or die("unable to close $file: $!");
    die("mismatched annotation length") unless $idx == scalar(@annotations);
} elsif (open(HANDLE, $file)) {
    my $mtime = get_modify_time($file);    # when was the file last modified?
    my $owner =
        getpwuid((stat($file))[4]);    # who does the filesystem think owns it?
    while (my $line = <HANDLE>) {
        chomp $line;
        # Also remove CR from line-end
        $line =~ s/\015$//;
        printf("%s|%s|%s|%s\n", "NONE", $owner, $mtime, $line);
    }
    close(HANDLE) or die("unable to close $file: $!");
} else {
    die("unable to open $file: $!");
}
