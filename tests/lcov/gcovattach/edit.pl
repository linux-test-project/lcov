#!/usr/bin/env perl

# Rewrite the gcov output for 't.c' as though the compiler had said:
#   - the second operand of the '&&' on line 4 is on line 5, which has no count
#     - its branches and its MC/DC condition move to a line 5 of their own;
#   - line 8 has the count of line 7 and an unexecuted block, but no branch;
#   - line 9 has an unexecuted block, but no branch, and (JSON) no function
#     name.
# With EDIT_LAYOUT=far (JSON only), the gcov output instead says:
#   - the second operand of the '&&' on line 4 is on line 8, which has no
#     count - so line 7 is the nearest statement before it;
#   - line 9 has an unexecuted block, but no branch.
# gcov 14 and later write the block ids of each line, and the source and target
#   block of each branch;  the edits keep them consistent.
# 'edit.pl json' filters the JSON intermediate format from stdin to stdout;
#   'edit.pl text file.gcov' edits the text format in place.

use strict;
use warnings;
use JSON::PP;

my $mode = shift;
if ($mode eq 'json') {
    local $/;
    my $data = JSON::PP->new()->decode(<STDIN>);
    foreach my $file (@{$data->{files}}) {
        next unless $file->{file} =~ /(^|\/)t\.c$/;
        my %line   = map({ $_->{line_number} => $_ } @{$file->{lines}});
        my $l4     = $line{4};
        my @br     = @{$l4->{branches}};
        my $half   = scalar(@br) / 2;
        my $blocks = exists($l4->{block_ids});
        my $far    = ($ENV{EDIT_LAYOUT} // '') eq 'far';
        my $moved  = $far ? 8 : 5;
        $line{$moved} = {
                         line_number      => $moved,
                         function_name    => $l4->{function_name},
                         unexecuted_block => JSON::PP::false,
                         branches         => [splice(@br, $half)],
                         calls            => [],
                         conditions       => $l4->{conditions} // []
        };
        $line{$moved}->{block_ids} = [] if $blocks;
        $l4->{branches}            = \@br;
        $l4->{conditions}          = [];

        if (!$far) {
            $line{8} = {
                        line_number      => 8,
                        function_name    => $l4->{function_name},
                        count            => $line{7}->{count},
                        unexecuted_block => JSON::PP::true,
                        branches         => [],
                        calls            => [],
                        conditions       => []
            };
            if ($blocks) {
                # line 8 holds the target of the untaken branch of line 7
                my ($untaken) =
                    grep({ 0 == $_->{count} } @{$line{7}->{branches}});
                my $to = $untaken->{destination_block_id};
                $line{7}->{block_ids} =
                    [grep({ $_ != $to } @{$line{7}->{block_ids}})];
                $line{8}->{block_ids} = [$to];
            }
        }
        $line{9}->{unexecuted_block} = JSON::PP::true;
        # gcov does not always name the function of a line, and then its block
        #   ids say nothing - so line 9 is judged by the statement before it
        delete($line{9}->{function_name}) unless $far;
        $file->{lines} = [map({ $line{$_} } sort({ $a <=> $b } keys(%line)))];
    }
    print(JSON::PP->new()->encode($data));
    exit(0);
}

die("usage: edit.pl json | edit.pl text file.gcov") unless $mode eq 'text';
my $name = shift;
open(my $in, '<', $name) or die("$name: $!");
my @lines = <$in>;
close($in);

if (grep({ /^file:/ } @lines)) {
    # the intermediate text format.  Only gcov 8 marks unexecuted blocks:
    #   'lcount:<line>,<count>,<has_unexecuted_block>'
    my (@result, $mine, @br4, $count7);
    foreach my $l (@lines) {
        if ($l =~ /^file:(.*)$/) {
            $mine = $1 =~ /(^|\/)t\.c$/;
        } elsif ($mine && $l =~ /^lcount:5,/) {
            next;
        } elsif ($mine && $l =~ /^lcount:7,(\d+),\d+$/) {
            $count7 = $1;
        } elsif ($mine && defined($count7) && $l =~ /^lcount:9,(\d+),\d+$/) {
            push(@result, "lcount:8,$count7,1\n");
            $l = "lcount:9,$1,1\n";
        } elsif ($mine && $l =~ /^branch:4,/) {
            push(@br4, $l);
            next;
        } elsif ($mine && @br4 && $l !~ /^branch:4,/) {
            my $half  = scalar(@br4) / 2;
            my @moved = splice(@br4, $half);
            s/^branch:4,/branch:5,/ foreach (@moved);
            push(@result, @br4, @moved);
            @br4 = ();
        }
        push(@result, $l);
    }
    open(my $out, '>', $name) or die("$name: $!");
    print $out @result;
    close($out);
    exit(0);
}
my $src = qr/^\s*([^:]+):\s*(\d+):/;
my (@out, @moved);
my $current = 0;
foreach my $l (@lines) {
    if ($l =~ /^\s*\S+:\s*(\d+)-block\s+\d+/) {
        # a block leader:  remember where the last one of line 4 starts
        push(@moved, scalar(@out)) if $current == 4;
    } elsif ($l =~ $src && $2 != 0) {
        $current = $2;
    }
    push(@out, $l);
}
# the last block of line 4 which holds branches moves to line 5
my @chunk;
foreach my $start (reverse(@moved)) {
    my $end = $start + 1;
    ++$end while ($end < @out && $out[$end] =~ /^branch\s/);
    next if $end == $start + 1;
    @chunk = splice(@out, $start, $end - $start);
    $chunk[0] =~ s/\b4-block/5-block/;
    last;
}
my @result;
my $count7;
foreach my $l (@out) {
    if ($l =~ $src) {
        my ($count, $line) = ($1, $2);
        $count7 = $1 if ($line == 7 && $count =~ /^\s*(\d+)/);
        if ($line == 5) {
            $l =~ s/^(\s*)[^:]+:/$1-:/;
            push(@result, $l, @chunk);
            next;
        } elsif ($line == 8) {
            $l =~ s/^(\s*)[^:]+:/$1${count7}*:/;
        } elsif ($line == 9) {
            $l =~ s/^(\s*)(\d+):/$1$2*:/;
        }
    }
    push(@result, $l);
}
open(my $out, '>', $name) or die("$name: $!");
print $out @result;
close($out);
