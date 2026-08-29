#!/usr/bin/env perl

# Print one line per row of a PNG written by 'genpng':
#
#   <row> <background color> <column of the first text pixel, or -1>
#
# genpng draws one pixel per source character - the background color of the line's
#   differential category for a space and for the padding past the end of the
#   line, and that category's text color for every other character.  So the
#   background color of a row is the category the line was drawn in, the number of
#   rows is the number of source lines the image was built from, and the first
#   pixel which is not the background color is the column the line's text starts
#   in.  That is everything the genpng tests need to look at.
# Reading the image back with GD rather than comparing the file against a stored
#   PNG keeps the tests independent of how the PNG happens to be compressed, and
#   of the exact palette - the expected colors are read from lcovutil.

use strict;
use warnings;
use GD;

my $file = $ARGV[0];
my $img  = GD::Image->newFromPng($file) or
    die("unable to read $file\n");

my ($width, $height) = $img->getBounds();
for (my $y = 0; $y < $height; ++$y) {
    # the last pixel of a row is always background:  every line is padded out to
    #   the full width of the image
    my $background = $img->getPixel($width - 1, $y);
    my $first      = -1;
    for (my $x = 0; $x < $width; ++$x) {
        next if $img->getPixel($x, $y) == $background;
        $first = $x;
        last;
    }
    printf("%d %02x%02x%02x %d\n", $y, $img->rgb($background), $first);
}
