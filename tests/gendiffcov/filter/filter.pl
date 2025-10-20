#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;

use lib "$FindBin::RealBin/../../../lib";    # build dir testcase
use lib (exists($ENV{LCOV_HOME}) ? $ENV{LCOV_HOME} : "../../../lib") . '/lib/lcov';
use lcovutil;

lcovutil::parseOptions({}, {});

foreach my $example (glob('expr*.c')) {
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

# try some trivial functions
foreach my $example (glob('*rivial*.c')) {
    print("checking trivial function in $example\n");
    my $lines = 0;
    open(FILE, $example) or die("can't open $example: $!");
    $lines++ while (<FILE>);
    close(FILE);

    my $file = ReadCurrentSource->new($example);
    if ($file->containsTrivialFunction(1, $lines)) {
        die("incorrectly found trivial function in $example")
            if $example =~ /^no/;
    } else {
        die("failed to find trivial function in $example")
            unless $example =~ /^no/;
    }
    my $info = $example;
    $info =~ s/c$/info/g;
    if (-f $info) {
        lcovutil::parse_cov_filters('trivial');
        my $trace = TraceFile->load($info, $file);
        $trace->write_info_file($info . '.filtered');
        lcovutil::parse_cov_filters();
    }
}

# problematic brace filter example...
$lcovutil::verbose                  = 3;
$lcovutil::derive_function_end_line = 1;
our $func_coverage = 1;
foreach my $example (glob('*brace*.c')) {
    print("checking brace filter for $example");
    my $info = $example;
    $info =~ s/c$/info/g;
    lcovutil::parse_cov_filters();    # turn off filtering
    my $vanilla = TraceFile->load($info);
    $vanilla->write_info_file($info . '.orig');
    my @v = $vanilla->count_totals();
    my ($lines, $hit) = @{$v[1]};
    print("$lines lines $hit hit\n");

    lcovutil::parse_cov_filters('brace');
    my $reader = ReadCurrentSource->new($example);
    my $trace  = TraceFile->load($info, $reader);
    $trace->write_info_file($info . '.filtered');
    my @counts = $trace->count_totals();
    my ($filtered, $h2) = @{$counts[1]};
    print("$filtered brace-filtered lines $h2 hit\n");
    die("failed to filter $info")
        unless ($lines > $filtered &&
                $hit > $h2);

    #simple test for compiler directive filtering
    lcovutil::parse_cov_filters();    # reset filters
    lcovutil::parse_cov_filters('directive', 'brace');
    $reader = ReadCurrentSource->new('brace.c');
    my $directive = TraceFile->load('brace.info', $reader);
    $directive->write_info_file($info . '.directive');
    @counts = $directive->count_totals();
    my ($f3, $h3) = @{$counts[1]};
    print("$f3 directive-filtered lines $h3 hit\n");
    die("failed to filter $info: $lines -> $f3, $hit -> $h3")
        unless ($lines > $f3 &&
                $hit > $h3);
}

print("passed\n");
exit(0);
