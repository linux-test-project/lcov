#!/usr/bin/perl
#
# Generate source files and a matching '.info' file for the parallel-parse
#   test.  Everything is written into the current directory.
#
# usage: gen_info.pl out.info nFiles nLines [mode] [skew]
#
#   out.info  - the tracefile to write
#   nFiles    - number of source files
#   nLines    - number of code lines in each source file
#   mode      - 'plain':    one 'TN:' per section, one section per source file
#                           (the default)
#               'inherit':  a single 'TN:' at the top of the file, so that
#                           every section but the first inherits it - and so
#                           that every chunk but the first has to be told what
#                           it is
#               'repeat':   three testnames, each with a section for every
#                           source file:  one source file appears in three
#                           places in the file
#               'scatter':  the same, except that the sections are emitted in
#                           an irregular order and some source file/testname
#                           pairs appear more than once with different counts.
#                           A source file's sections are then scattered through
#                           the file at no particular interval - the partitioner
#                           has to collect them all into one chunk, and the
#                           chunk's byte ranges are not contiguous
#   skew      - multiply the first file's line count by this, to make one
#               source file dominate the tracefile
#
# The generated sources contain blank lines and a lone closing brace, and the
#   generated data has (unhit) records for them, so that the 'blank' and
#   'brace' filters have something to remove.

use strict;
use warnings;
use Cwd qw(getcwd);

my ($out, $nFiles, $nLines, $mode, $skew) = @ARGV;
die("usage: $0 out.info nFiles nLines [mode] [skew]\n")
    unless (defined($nLines));
$mode = 'plain' unless defined($mode);
$skew = 1       unless defined($skew);
my $cwd = getcwd();
# Name the sources after the tracefile:  every tracefile has a different number
#   of files and lines, so a shared name would leave the earlier tracefile
#   pointing at a source file which is now too short (the filters read it).
my $base = $out;
$base =~ s/\.info$//;

my @files;    # per source file: [name, [code lines], [blank lines], brace line]
for (my $f = 0; $f < $nFiles; ++$f) {
    my $src   = "${base}_f$f.c";
    my $count = $nLines * (0 == $f ? $skew : 1);
    my @src   = ("/* $src */", "int fn$f(int x)", '{');
    my (@code, @blank);
    for (my $l = 0; $l < $count; ++$l) {
        if (0 == $l % 4) {
            push(@src, '');
            push(@blank, scalar(@src));
        }
        push(@src, "  x += $l;");
        push(@code, scalar(@src));
    }
    push(@src, '  return x;');
    push(@code, scalar(@src));
    push(@src, '}');
    my $brace = scalar(@src);

    open(SRC, '>', $src) or die("unable to write $src: $!\n");
    print(SRC "$_\n") foreach (@src);
    close(SRC) or die("unable to close $src: $!\n");

    push(@files, [$src, \@code, \@blank, $brace]);
}

sub section($;$)
{
    # the '.info' section for source file $_[0], with every hit count bumped by
    #   $_[1] - so that two sections for the same file and testname have to be
    #   summed rather than merely appear
    my ($f, $bump) = @_;
    $bump = 0 unless defined($bump);
    my ($src, $code, $blank, $brace) = @{$files[$f]};

    my ($found, $hit) = (0, 0);
    my $text = "SF:$cwd/$src\n";
    $text .= "FN:2,$brace,fn$f\n";
    $text .= 'FNDA:' . (3 + $bump) . ",fn$f\n";
    $text .= "FNF:1\nFNH:1\n";
    foreach my $l (@$code) {
        my $c = ($l % 3) ? $l : 0;
        # bump only what was already hit, so that 'LH:' does not depend on $bump
        $c += $bump if $c;
        $text .= "DA:$l,$c\n";
        ++$found;
        ++$hit if $c;
    }
    # the filters will take these away
    foreach my $l (@$blank, $brace) {
        $text .= "DA:$l,0\n";
        ++$found;
    }
    $text .= "LF:$found\nLH:$hit\nend_of_record\n";
    return $text;
}

open(OUT, '>', $out) or die("unable to write $out: $!\n");
if ('inherit' eq $mode) {
    print(OUT "TN:tinherit\n");
    print(OUT section($_)) foreach (0 .. $#files);
} elsif ('repeat' eq $mode) {
    foreach my $test ('t1', 't2', 't3') {
        print(OUT "TN:$test\n" . section($_)) foreach (0 .. $#files);
    }
} elsif ('scatter' eq $mode) {
    # Step through the files by 3 and the testnames by 2, so that a file's
    #   sections land at irregular distances from each other - and emit one
    #   round twice, with different counts, so that some file/testname pair
    #   appears more than once.
    my @tests = ('t1', 't2', 't3');
    for (my $round = 0; $round < 2 * scalar(@tests); ++$round) {
        my $test = $tests[($round * 2) % scalar(@tests)];
        for (my $i = 0; $i < $nFiles; ++$i) {
            my $f = ($round + $i * 3) % $nFiles;
            print(OUT "TN:$test\n" . section($f, $round));
        }
    }
} else {
    print(OUT "TN:tmain\n" . section($_)) foreach (0 .. $#files);
}
close(OUT) or die("unable to close $out: $!\n");
