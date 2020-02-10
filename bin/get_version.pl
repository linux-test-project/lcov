#!/usr/bin/env perl
#
# Usage: get_version.pl --version|--release|--full
#
# Print lcov version or release information as provided by Git, .version
# or a fallback.

use strict;
use warnings;

use File::Basename;
use Cwd qw /abs_path/;

our $version_opt = $ARGV[0];

# Fallback default values
our $version = "1.0";
our $release = "1";
our $full = $version;

our $git_ver = `git describe --tags 2>/dev/null`;

if ($git_ver eq "") {
	our $git_dir = dirname(abs_path(dirname($0)));
	our $version_filename = "$git_dir/.version";
	if (-e $version_filename) {
		require $version_filename;
    }
}
else {
	# Get version information from git
	$full = substr $git_ver, 1;
	$version = $full;
	$version =~ s/^([^-]*)-.*/$1/;

	if ($full =~ /^[^-]*-([^-]*)-(.*)$/) {
		$release = "$1.$2";
	}
}

if (defined $version_opt) {
	if ($version_opt eq "--version") {
		print($version);
	}
	elsif ($version_opt eq "--release") {
		print($release);
	}
	elsif ($version_opt eq "--full") {
		print($full);
	}
}
