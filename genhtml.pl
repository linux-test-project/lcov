#!/usr/bin/perl -w
#
#   Copyright (c) International Business Machines  Corp., 2002
#
#   This program is free software;  you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or (at
#   your option) any later version.
#
#   This program is distributed in the hope that it will be useful, but
#   WITHOUT ANY WARRANTY;  without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#   General Public License for more details.                 
#
#   You should have received a copy of the GNU General Public License
#   along with this program;  if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
#
# genhtml.pl
#
#   This script generates HTML output from .info files as created by the
#   geninfo.pl script. Call it with --help to get information on available
#   options.
#
#
# History:
#   2002-08-23 created by Peter Oberparleiter <Peter.Oberparleiter@de.ibm.com>
#                         IBM Lab Boeblingen
#        based on code by Manoj Iyer <manjo@mail.utexas.edu> and
#                         Megan Bock <mbock@us.ibm.com>
#                         IBM Austin
#   2002-08-27 / Peter Oberparleiter: implemented frame view
#   2002-08-29 / Peter Oberparleiter: implemented test description filtering
#                                     so that by default only descriptions for
#                                     test cases which actually hit some
#                                     source lines are kept.
#   2002-09-05 / Peter Oberparleiter: implemented --no-sourceview
#

use strict;
use File::Basename; 
use Getopt::Long;


# Global constants
our $tool_name		= "LTP GCOV extension";
our $title		= "$tool_name - code coverage report";
our $version_info	= "genhtml version 1.0";
our $url		= "http://ltp.sourceforge.net/lcov.php";

# Specify coverage rate limits (in %) for classifying file entries
# HI:   $hi_limit <= rate <= 100          graph color: green
# MED: $med_limit <= rate <  $hi_limit    graph color: orange
# LO:          0  <= rate <  $med_limit   graph color: red
our $hi_limit	= 50;
our $med_limit	= 15;

# When producing source code output, this constant controls the number of
# spaces to use in place for a single tabulator mark
our $tab_spaces = " "x4;

# Width of overview image
our $overview_width = 80;

# Resolution of overview navigation: this number specifies the maximum
# difference in lines between the position a user selected from the overview
# and the position the source code window is scrolled to.
our $nav_resolution = 4;

# Clicking a line in the overview image should show the source code view at
# a position a bit further up so that the requested line is not the first
# line in the window. This number specifies that offset in lines.
our $nav_offset = 10;


# Data related prototypes
sub print_usage(*);
sub gen_html();
sub process_dir($);
sub process_file($$$);
sub info(@);
sub read_infofile($);
sub get_info_entry($);
sub set_info_entry($$$$;$$);
sub get_prefix(@);
sub shorten_prefix($);
sub get_dir_list(@);
sub get_relative_base_path($);
sub read_testfile($);
sub get_date_string();
sub split_filename($);
sub create_sub_dir($);
sub subtract_counts($$);
sub add_counts($$);
sub apply_baseline($$);
sub remove_unused_descriptions();
sub get_found_and_hit($);
sub get_affecting_tests($);
sub combine_info_files($$);
sub combine_info_entries($$);
sub apply_prefix($$);


# HTML related prototypes
sub escape_html($);
sub get_bar_graph_code($$$);

sub write_png_files();
sub write_css_file();
sub write_description_file($$$);

sub write_html(*$);
sub write_html_prolog(*$$);
sub write_html_epilog(*$;$);

sub write_header(*$$$$$);
sub write_header_prolog(*$);
sub write_header_line(*$$;$$);
sub write_header_epilog(*$);

sub write_file_table(*$$$);
sub write_file_table_prolog(*$$);
sub write_file_table_entry(*$$$$);
sub write_file_table_detail_heading(*$$);
sub write_file_table_detail_entry(*$$$);
sub write_file_table_epilog(*);

sub write_test_table_prolog(*$);
sub write_test_table_entry(*$$);
sub write_test_table_epilog(*);

sub write_source($$$);
sub write_source_prolog(*);
sub write_source_line(*$$$);
sub write_source_epilog(*);

sub write_frameset(*$$$);
sub write_overview_line(*$$$);
sub write_overview(*$$$$);

# External prototype (defined in genpng.pl)
sub gen_png($$$@);


# Global variables & initialization
our %info_data;		# Hash containing all data from .info file
our $dir_prefix;	# Prefix to remove from all sub directories
our %test_description;	# Hash containing test descriptions if available
our $date = get_date_string();

our @info_filenames;	# List of .info files to use as data source
our $test_title;	# Title for output as written to each page header
our $output_directory;	# Name of directory in which to store output
our $base_filename;	# Optional name of file containing baseline data
our $desc_filename;	# Name of file containing test descriptions
our $css_filename;	# Optional name of external stylesheet file to use
our $quiet;		# If set, suppress information messages
our $help;		# Help option flag
our $version;		# Version option flag
our $show_details;	# If set, generate detailed directory view
our $no_prefix;		# If set, do not remove filename prefix
our $frames;		# If set, use frames for source code view
our $keep_descriptions;	# If set, do not remove unused test case descriptions
our $no_sourceview;	# If set, do not create a source code view for each file

our $cwd = `pwd`;	# Current working directory
chomp($cwd);
our $tool_dir = dirname($0);	# Directory where genhtml.pl tool is installed


#
# Code entry point
#

# Add current working directory if $tool_dir is not already an absolute path
if (! ($tool_dir =~ /^\/(.*)$/))
{
	$tool_dir = "$cwd/$tool_dir";
}

# Parse command line options
if (!GetOptions("output-directory=s" => \$output_directory,
		"title=s" => \$test_title,
		"description-file=s" => \$desc_filename,
		"keep-descriptions" => \$keep_descriptions,
		"css-file=s" => \$css_filename,
		"baseline-file=s" => \$base_filename,
		"prefix=s" => \$dir_prefix,
		"no-prefix" => \$no_prefix,
		"no-sourceview" => \$no_sourceview,
		"show-details" => \$show_details,
		"frames" => \$frames,
		"quiet" => \$quiet,
		"help" => \$help,
		"version" => \$version
		))
{
	print_usage(*STDERR);
	exit(1);
}

@info_filenames = @ARGV;

# Check for help option
if ($help)
{
	print_usage(*STDOUT);
	exit(0);
}

# Check for version option
if ($version)
{
	print($version_info."\n");
	exit(0);
}

# Check for info filename
if (!@info_filenames)
{
	print(STDERR "No filename specified\n");
	print_usage(*STDERR);
	exit(1);
}

# Generate a title if none is specified
if (!$test_title)
{
	if (scalar(@info_filenames) == 1)
	{
		# Only one filename specified, use it as title
		$test_title = basename($info_filenames[0]);
	}
	else
	{
		# More than one filename specified, used default title
		$test_title = "unnamed";
	}
}

# Make sure css_filename is an absolute path (in case we're changing
# directories)
if ($css_filename)
{
	if (!($css_filename =~ /^\/(.*)$/))
	{
		$css_filename = $cwd."/".$css_filename;
	}
}

# Issue a warning if --no-sourceview is enabled together with --frames
if ($no_sourceview && $frames)
{
	warn("WARNING: option --frames disabled because --no-sourceview ".
	     "was specified!\n");
	$frames = undef;
}

if ($frames)
{
	# Include genpng.pl code needed for overview image generation
	do("$tool_dir/genpng.pl");
}


# Do something
gen_html();

exit(0);



#
# print_usage(handle)
#
# Print usage information.
#

sub print_usage(*)
{
	local *HANDLE = $_[0];
	my $executable_name = basename($0);

	print(HANDLE <<END_OF_USAGE);
Usage: $executable_name [OPTIONS] INFOFILE(S)

Create HTML output for coverage data found in INFOFILE. Note that INFOFILE
may also be a list of filenames.

  -h, --help                        Print this help, then exit
  -v, --version                     Print version number, then exit
  -q, --quiet                       Do not print progress messages
  -s, --show-details                Generate detailed directory view
  -f, --frames                      Use HTML frames for source code view
  -b, --baseline-file BASEFILE      Use BASEFILE as baseline file
  -o, --output-directory OUTDIR     Write HTML output to OUTDIR
  -t, --title TITLE                 Display TITLE in header of all pages
  -d, --description-file DESCFILE   Read test case descriptions from DESCFILE
  -k, --keep-descriptions           Do not removed unused test descriptions
  -c, --css-file CSSFILE            Use external style sheet file CSSFILE
  -p, --prefix PREFIX               Remove PREFIX from all directory names
      --no-prefix                   Do not remove prefix from directory names
      --no-source                   Do not create source code view

See $url for more information on this tool.
END_OF_USAGE
	;
}


#
# gen_html()
#
# Generate a set of HTML pages from contents of .info file INFO_FILENAME.
# Files will be written to the current directory. If provided, test case
# descriptions will be read from .tests file TEST_FILENAME and included
# in ouput.
#
# Die on error.
#

sub gen_html()
{
	local *HTML_HANDLE;
	my %overview;
	my %base_data;
	my $lines_found;
	my $lines_hit;
	my $overall_found = 0;
	my $overall_hit = 0;
	my $dir_name;
	my $link_name;
	my @dir_list;
	my %new_info;

	# Read in all specified .info files
	foreach (@info_filenames)
	{
		info("Reading data file $_\n");
		%new_info = %{read_infofile($_)};

		# Combine %new_info with %info_data
		%info_data = %{combine_info_files(\%info_data, \%new_info)};
	}

	info("Found %d entries.\n", scalar(keys(%info_data)));

	# Read and apply baseline data if specified
	if ($base_filename)
	{
		# Read baseline file
		info("Reading baseline file $base_filename\n");
		%base_data = %{read_infofile($base_filename)};
		info("Found %d entries.\n", scalar(keys(%base_data)));

		# Apply baseline
		info("Subtracting baseline data.\n");
		%info_data = %{apply_baseline(\%info_data, \%base_data)};
	}

	@dir_list = get_dir_list(keys(%info_data));

	if ($no_prefix)
	{
		# User requested that we leave filenames alone
		info("User asked not to remove filename prefix\n");
	}
	elsif (!defined($dir_prefix))
	{
		# Get prefix common to most directories in list
		$dir_prefix = get_prefix(@dir_list);

		info("Found common filename prefix \"$dir_prefix\"\n");
	}
	else
	{
		info("Using user-specified filename prefix \"".
		     "$dir_prefix\"\n");
	}

	# Read in test description file if specified
	if ($desc_filename)
	{
		info("Reading test description file $desc_filename\n");
		%test_description = %{read_testfile($desc_filename)};

		# Remove test descriptions which are not referenced
		# from %info_data if user didn't tell us otherwise
		if (!$keep_descriptions)
		{
			remove_unused_descriptions();
		}
	}

	# Change to output directory if specified
	if ($output_directory)
	{
		chdir($output_directory)
			or die("ERROR: cannot change to directory ".
			"$output_directory!\n");
	}

	info("Writing .css and .png files.\n");
	write_css_file();
	write_png_files();

	info("Generating output.\n");

	# Process each subdirectory and collect overview information
	foreach $dir_name (@dir_list)
	{
		($lines_found, $lines_hit) = process_dir($dir_name);

		# Remove prefix if applicable
		if (!$no_prefix && $dir_prefix)
		{
			# Match directory names beginning with $dir_prefix
			$dir_name = apply_prefix($dir_name, $dir_prefix);
		}

		# Generate name for directory overview HTML page
		if ($dir_name =~ /^\/(.*)$/)
		{
			$link_name = substr($dir_name, 1)."/index.html";
		}
		else
		{
			$link_name = $dir_name."/index.html";
		}

		$overview{$dir_name} = "$lines_found,$lines_hit,$link_name";
		$overall_found	+= $lines_found;
		$overall_hit	+= $lines_hit;
	}

	# Generate overview page
	info("Writing overview page.\n");
	open(*HTML_HANDLE, ">index.html")
		or die("ERROR: cannot open index.html for writing!\n");
	write_html_prolog(*HTML_HANDLE, "", "GCOV - $test_title");
	write_header(*HTML_HANDLE, 0, "", "", $overall_found, $overall_hit);
	write_file_table(*HTML_HANDLE, "", \%overview, {});
	write_html_epilog(*HTML_HANDLE, "");
	close(*HTML_HANDLE);

	# Check if there are any test case descriptions to write out
	if (%test_description)
	{
		info("Writing test case description file.\n");
		write_description_file( \%test_description,
					$overall_found, $overall_hit);
	}

	info("Overall coverage rate: %d of %d lines (%.1f%%)\n",
	       $overall_hit, $overall_found, $overall_hit*100/$overall_found);

	chdir($cwd);
}


#
# process_dir(dir_name)
#

sub process_dir($)
{
	my $abs_dir = $_[0];
	my $trunc_dir;
	my $rel_dir = $abs_dir;
	my $base_dir;
	my $filename;
	my %overview;
	my $lines_found;
	my $lines_hit;
	my $overall_found=0;
	my $overall_hit=0;
	my $base_name;
	my $extension;
	my $testdata;
	my %testhash;
	local *HTML_HANDLE;

	# Remove prefix if applicable
	if (!$no_prefix)
	{
		# Match directory name beginning with $dir_prefix
	        $rel_dir = apply_prefix($rel_dir, $dir_prefix);
	}

	$trunc_dir = $rel_dir;

	# Remove leading /
	if ($rel_dir =~ /^\/(.*)$/)
	{
		$rel_dir = substr($rel_dir, 1);
	}

	$base_dir = get_relative_base_path($rel_dir);

	create_sub_dir($rel_dir);

	# Match filenames which specify files in this directory, not including
	# sub-directories
       $abs_dir =~ s/\+/\\\+/g; 
	foreach $filename (grep(/^$abs_dir\/[^\/]*$/,keys(%info_data)))
	{
		($lines_found, $lines_hit, $testdata) =
			process_file($trunc_dir, $rel_dir, $filename);

		$base_name = basename($filename);

		if ($no_sourceview)
		{
			# User asked as not to create source code view, do not
			# provide a page link
			$overview{$base_name} =
				"$lines_found,$lines_hit";
		}
		elsif ($frames)
		{
			# Link to frameset page
			$overview{$base_name} =
				"$lines_found,$lines_hit,".
				"$base_name.gcov.frameset.html";
		}
		else
		{
			# Link directory to source code view page
			$overview{$base_name} =
				"$lines_found,$lines_hit,".
				"$base_name.gcov.html";
		}

		$testhash{$base_name} = $testdata;

		$overall_found	+= $lines_found;
		$overall_hit	+= $lines_hit;
	}

	# Generate directory overview page (without details)
	open(*HTML_HANDLE, ">$rel_dir/index.html")
		or die("ERROR: cannot open $rel_dir/index.html ".
		       "for writing!\n");
	write_html_prolog(*HTML_HANDLE, $base_dir,
			  "GCOV - $test_title - $trunc_dir");
	write_header(*HTML_HANDLE, 1, $trunc_dir, $rel_dir, $overall_found,
		     $overall_hit);
	write_file_table(*HTML_HANDLE, $base_dir, \%overview, {});
	write_html_epilog(*HTML_HANDLE, $base_dir);
	close(*HTML_HANDLE);

	if ($show_details)
	{
		# Generate directory overview page including details
		open(*HTML_HANDLE, ">$rel_dir/index-detail.html")
			or die("ERROR: cannot open $rel_dir/".
			       "index-detail.html for writing!\n");
		write_html_prolog(*HTML_HANDLE, $base_dir,
				  "GCOV - $test_title - $trunc_dir");
		write_header(*HTML_HANDLE, 1, $trunc_dir, $rel_dir, $overall_found,
			     $overall_hit);
		write_file_table(*HTML_HANDLE, $base_dir, \%overview, \%testhash);
		write_html_epilog(*HTML_HANDLE, $base_dir);
		close(*HTML_HANDLE);
	}

	# Calculate resulting line counts
	return ($overall_found, $overall_hit);
}


#
# process_file(trunc_dir, rel_dir, filename)
#

sub process_file($$$)
{
	info("Processing file ".apply_prefix($_[2], $dir_prefix)."\n");

	my $trunc_dir = $_[0];
	my $rel_dir = $_[1];
	my $filename = $_[2];
	my $base_name = basename($filename);
	my $base_dir = get_relative_base_path($rel_dir);
	my $testdata;
	my $testcount;
	my $sumcount;
	my $funcdata;
	my $lines_found;
	my $lines_hit;
	my @source;
	my $pagetitle;
	local *HTML_HANDLE;

	($testdata, $sumcount, $funcdata, $lines_found, $lines_hit) =
		get_info_entry($info_data{$filename});

	# Return after this point in case user asked us not to generate
	# source code view
	if ($no_sourceview)
	{
		return ($lines_found, $lines_hit, $testdata);
	}

	# Generate source code view for this file
	open(*HTML_HANDLE, ">$rel_dir/$base_name.gcov.html")
		or die("ERROR: cannot open $rel_dir/$base_name.gcov.html ".
		       "for writing!\n");
	$pagetitle = "GCOV - $test_title - $trunc_dir/$base_name";
	write_html_prolog(*HTML_HANDLE, $base_dir, $pagetitle);
	write_header(*HTML_HANDLE, 2, "$trunc_dir/$base_name", "$rel_dir/$base_name",
		     $lines_found, $lines_hit);
	@source = write_source(*HTML_HANDLE, $filename, $sumcount);

	write_html_epilog(*HTML_HANDLE, $base_dir, 1);
	close(*HTML_HANDLE);

	# Additional files are needed in case of frame output
	if (!$frames)
	{
		return ($lines_found, $lines_hit, $testdata);
	}

	# Create overview png file
	gen_png("$rel_dir/$base_name.gcov.png", $overview_width, $tab_spaces,
		@source);

	# Create frameset page
	open(*HTML_HANDLE, ">$rel_dir/$base_name.gcov.frameset.html")
		or die("ERROR: cannot open ".
		       "$rel_dir/$base_name.gcov.frameset.html".
		       " for writing!\n");
	write_frameset(*HTML_HANDLE, $base_dir, $base_name, $pagetitle);
	close(*HTML_HANDLE);

	# Write overview frame
	open(*HTML_HANDLE, ">$rel_dir/$base_name.gcov.overview.html")
		or die("ERROR: cannot open ".
		       "$rel_dir/$base_name.gcov.overview.html".
		       " for writing!\n");
	write_overview(*HTML_HANDLE, $base_dir, $base_name, $pagetitle,
		       scalar(@source));
	close(*HTML_HANDLE);

	return ($lines_found, $lines_hit, $testdata);
}


#
# read_info(info_filename)
#
# Read in the contents of the .info file specified by INFO_FILENAME. Data will
# be returned as a reference to a hash containing the following mappings:
#
# %result: for each filename found in file -> \%data
#
# %data: "test"  -> \%testdata
#        "sum"   -> \%sumcount
#        "func"  -> \%funcdata
#        "found" -> $lines_found (number of instrumented lines found in file)
#	 "hit"   -> $lines_hit (number of executed lines in file)
#
# %testdata: name of test affecting this file -> \%testcount
#
# %testcount: line number -> execution count for a single test
# %sumcount : line number -> execution count for all tests
# %funcdata : line number -> name of function beginning at that line
# 
# Note that .info file sections referring to the same file and test name
# will automatically be combined by adding all execution counts.
#
# Note that if INFO_FILENAME ends with ".gz", it is assumed that the file
# is compressed using GZIP. If available, GUNZIP will be used to decompress
# this file.
#
# Die on error
#

sub read_infofile($)
{
	my %result;			# Resulting hash: file -> data
	my $data;			# Data handle for current entry
	my $testdata;			#       "             "
	my $testcount;			#       "             "
	my $sumcount;			#       "             "
	my $funcdata;			#       "             "
	my $line;			# Current line read from .info file
	my @lineargs;			# Result of split(",", $line)
	my $testname;			# Current test name
	my $filename;			# Current filename
	my $hitcount;			# Count for lines hit
	local *INFO_HANDLE;		# Filehandle for .info file

	# Check if file exists and is readable
	stat($_[0]);
	if (!(-r _))
	{
		die("ERROR: cannot read file $_[0]!\n");
	}

	# Check if this is really a plain file
	if (!(-f _))
	{
		die("ERROR: not a plain file: $_[0]!\n");
	}

	# Check for .gz extension
	if ($_[0] =~ /^(.*)\.gz$/)
	{
		# Check for availability of GZIP tool
		system("gunzip -h >/dev/null 2>/dev/null")
			and die("ERROR: gunzip command not available!\n");

		# Check integrity of compressed file
		system("gunzip -t $_[0] >/dev/null 2>/dev/null")
			and die("ERROR: integrity check failed for ".
				"compressed file $_[0]!\n");

		# Open compressed file
		open(INFO_HANDLE, "gunzip -c $_[0]|")
			or die("ERROR: cannot start gunzip to uncompress ".
			       "file $_[0]!\n");
	}
	else
	{
		# Open uncompressed file
		open(INFO_HANDLE, $_[0])
			or die("ERROR: cannot read file $_[0]!\n");
	}

	while (<INFO_HANDLE>)
	{
		chomp($_);
		$line = $_;
		@lineargs = split(",", substr($line, 3));

		# Switch statement
		foreach ($line)
		{
			/^TN:/ && do
			{
				# Test name information found
				$testname = substr($_, 3);
				last;
			};

			/^[SK]F:/ && do
			{
				# Filename information found
				# Retrieve data for new entry
				$filename = substr($_, 3);

				$data = $result{$filename};
				($testdata, $sumcount, $funcdata) =
					get_info_entry($data);

				if (defined($testname))
				{
					$testcount = $testdata->{$testname};
				}
				else
				{
					my %new_hash;
					$testcount = \%new_hash;
				}
				last;
			};

			/^DA:/ && do
			{
				# Execution count found, add to structure

				# Add summary counts
				$sumcount->{$lineargs[0]} += $lineargs[1];

				# Add test-specific counts
				if (defined($testname))
				{
					$testcount->{$lineargs[0]} +=
						$lineargs[1];
				}
				last;
			};

			/^FN:/ && do
			{
				# Function data found, add to structure
				$funcdata->{$lineargs[0]} = $lineargs[1];
				last;
			};

			/^end_of_record/ && do
			{
				# Found end of section marker
				if ($filename)
				{
					# Store current section data
					if (defined($testname))
					{
						$testdata->{$testname} =
							$testcount;
					}
					set_info_entry($data, $testdata,
						       $sumcount, $funcdata);
					$result{$filename} = $data;
				}

			};

			# default
			last;
		}
	}
	close(INFO_HANDLE);

	# Calculate lines_found and lines_hit for each file
	foreach $filename (keys(%result))
	{
		$data = $result{$filename};

		($testdata, $sumcount, $funcdata) = get_info_entry($data);

		$data->{"found"} = scalar(keys(%{$sumcount}));
		$hitcount = 0;

		foreach (keys(%{$sumcount}))
		{
			if ($sumcount->{$_} >0) { $hitcount++; }
		}

		$data->{"hit"} = $hitcount;

		$result{$filename} = $data;
	}

	return(\%result);
}


#
# get_info_entry(hash_ref)
#
# Retrieve data from an entry of the structure generated by read_infofile().
# Return a list of references to hashes:
# (test data hash ref, sum count hash ref, funcdata hash ref, lines found,
#  lines hit)
#

sub get_info_entry($)
{
	my $testdata_ref = $_[0]->{"test"};
	my $sumcount_ref = $_[0]->{"sum"};
	my $funcdata_ref = $_[0]->{"func"};
	my $lines_found  = $_[0]->{"found"};
	my $lines_hit    = $_[0]->{"hit"};

	return ($testdata_ref, $sumcount_ref, $funcdata_ref, $lines_found,
	        $lines_hit);
}


#
# set_info_entry(hash_ref, testdata_ref, sumcount_ref, funcdata_ref[,
#                lines_found, lines_hit])
#
# Update the hash referenced by HASH_REF with the provided data references.
#

sub set_info_entry($$$$;$$)
{
	my $data_ref = $_[0];

	$data_ref->{"test"} = $_[1];
	$data_ref->{"sum"} = $_[2];
	$data_ref->{"func"} = $_[3];

	if (defined($_[4])) { $data_ref->{"found"} = $_[4]; }
	if (defined($_[5])) { $data_ref->{"hit"} = $_[5]; }
}


#
# get_prefix(filename_list)
#
# Search FILENAME_LIST for a directory prefix which is common to as many
# list entries as possible, so that removing this prefix will minimize the
# sum of the lengths of all resulting shortened filenames.
#

sub get_prefix(@)
{
	my @filename_list = @_;		# provided list of filenames
	my %prefix;			# mapping: prefix -> sum of lengths
	my $current;			# Temporary iteration variable

	# Find list of prefixes
	foreach (@filename_list)
	{
		# Need explicit assignment to get a copy of $_ so that
		# shortening the contained prefix does not affect the list
		$current = $_;
		while ($current = shorten_prefix($current))
		{
			# Skip rest if the remaining prefix has already been
			# added to hash
			if ($prefix{$current}) { last; }

			# Initialize with 0
			$prefix{$current}="0";
		}

	}

	# Calculate sum of lengths for all prefixes
	foreach $current (keys(%prefix))
	{
		foreach (@filename_list)
		{
			# Add original length
			$prefix{$current} += length($_);

			# Check whether prefix matches
			if (substr($_, 0, length($current)) eq $current)
			{
				# Subtract prefix length for this filename
				$prefix{$current} -= length($current);
			}
		}
	}

	# Find and return prefix with minimal sum
	$current = (keys(%prefix))[0];

	foreach (keys(%prefix))
	{
		if ($prefix{$_} < $prefix{$current})
		{
			$current = $_;
		}
	}

	return($current);
}


#
# shorten_prefix(prefix)
#
# Return PREFIX shortened by last directory component.
#

sub shorten_prefix($)
{
	my @list = split("/", $_[0]);
	pop(@list);
	return join("/", @list);
}



#
# get_dir_list(filename_list)
#
# Return sorted list of directories for each entry in given FILENAME_LIST.
#

sub get_dir_list(@)
{
	my %result;

	foreach (@_)
	{
		$result{shorten_prefix($_)} = "";
	}

	return(sort(keys(%result)));
}


#
# get_relative_base_path(subdirectory)
#
# Return a relative path string which references the base path when applied
# in SUBDIRECTORY.
#
# Example: get_relative_base_path("fs/mm") -> "../../"
#

sub get_relative_base_path($)
{
	my $result = "";
	my $index;

	# Make an empty directory path a special case
	if (!$_[0]) { return(""); }

	# Count number of /s in path
	$index = ($_[0] =~ s/\//\//g);

	# Add a ../ to $result for each / in the directory path + 1
	for (; $index>=0; $index--)
	{
		$result .= "../";
	}

	return $result;
}


#
# read_testfile(test_filename)
#
# Read in file TEST_FILENAME which contains test descriptions in the format:
#
#   TN:<whitespace><test name>
#   TD:<whitespace><test description>
#
# for each test case. Return a reference to a hash containing a mapping
#
#   test name -> test description.
#
# Die on error.
#

sub read_testfile($)
{
	my %result;
	my $test_name;
	local *TEST_HANDLE;

	open(TEST_HANDLE, "<".$_[0])
		or die("ERROR: cannot open $_[0]!\n");

	while (<TEST_HANDLE>)
	{
		chomp($_);

		# Match lines beginning with TN:<whitespace(s)>
		if (/^TN:\s+(.*?)\s*$/)
		{
			# Store name for later use
			$test_name = $1;
		}

		# Match lines beginning with TD:<whitespace(s)>
		if (/^TD:\s+(.*?)\s*$/)
		{
			# Check for empty line
			if ($1)
			{
				# Add description to hash
				$result{$test_name} .= " $1";
			}
			else
			{
				# Add empty line
				$result{$test_name} .= "\n\n";
			}
		}
	}

	close(TEST_HANDLE);

	return \%result;
}


#
# escape_html(STRING)
#
# Returna a copy of STRING in which all occurrences of HTML special characters
# are escaped.
#

sub escape_html($)
{
	my $string = $_[0];

	if (!$string) { return ""; }

	$string =~ s/&/&amp;/g;		# & -> &amp;
	$string =~ s/</&lt;/g;		# < -> &lt;
	$string =~ s/>/&gt;/g;		# > -> &gt;
	$string =~ s/\"/&quot;/g;	# " -> &quot;
	$string =~ s/\t/$tab_spaces/g;	# tab -> spaces
	$string =~ s/\n/<br>/g;		# \n -> <br>

	return $string;
}


#
# get_date_string()
#
# Return the current date in the form: yyyy-mm-dd
#

sub get_date_string()
{
	my $year;
	my $month;
	my $day;

	($year, $month, $day) = (localtime())[5, 4, 3];

	return sprintf("%d-%02d-%02d", $year+1900, $month+1, $day);
}


#
# create_sub_dir(dir_name)
#
# Create subdirectory DIR_NAME if it does not already exist, including all its
# parent directories.
#
# Die on error.
#

sub create_sub_dir($)
{
	system("mkdir -p $_[0]")
		and die("ERROR: cannot create directory $_!\n");
}


#
# write_description_file(descriptions, overall_found, overall_hit)
#
# Write HTML file containing all test case descriptions. DESCRIPTIONS is a
# reference to a hash containing a mapping
#
#   test case name -> test case description
#
# Die on error.
#

sub write_description_file($$$)
{
	my %description = %{$_[0]};
	my $found = $_[1];
	my $hit = $_[2];
	my $test_name;
	local *HTML_HANDLE;

	open(HTML_HANDLE, ">descriptions.html")
		or die("ERROR: cannot open descriptions.html for writing!\n");

	write_html_prolog(*HTML_HANDLE, "", "GCOV - test case descriptions");
	write_header(*HTML_HANDLE, 3, "", "", $found, $hit);

	write_test_table_prolog(*HTML_HANDLE,
			 "Test case descriptions - alphabetical list");

	foreach $test_name (sort(keys(%description)))
	{
		write_test_table_entry(*HTML_HANDLE, $test_name,
				       escape_html($description{$test_name}));
	}

	write_test_table_epilog(*HTML_HANDLE);
	write_html_epilog(*HTML_HANDLE, "");

	close(HTML_HANDLE);
}



#
# write_png_files()
#
# Create all necessary .png files for the HTML-output in the current
# directory. .png-files are used as bar graphs.
#
# Die on error.
#

sub write_png_files()
{
	my %data;
	local *PNG_HANDLE;

	$data{"ruby.png"} =
		[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 
		 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 
		 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x00, 0x00, 0x00, 0x25, 
		 0xdb, 0x56, 0xca, 0x00, 0x00, 0x00, 0x07, 0x74, 0x49, 0x4d, 
		 0x45, 0x07, 0xd2, 0x07, 0x11, 0x0f, 0x18, 0x10, 0x5d, 0x57, 
		 0x34, 0x6e, 0x00, 0x00, 0x00, 0x09, 0x70, 0x48, 0x59, 0x73, 
		 0x00, 0x00, 0x0b, 0x12, 0x00, 0x00, 0x0b, 0x12, 0x01, 0xd2, 
		 0xdd, 0x7e, 0xfc, 0x00, 0x00, 0x00, 0x04, 0x67, 0x41, 0x4d, 
		 0x41, 0x00, 0x00, 0xb1, 0x8f, 0x0b, 0xfc, 0x61, 0x05, 0x00, 
		 0x00, 0x00, 0x06, 0x50, 0x4c, 0x54, 0x45, 0xff, 0x35, 0x2f, 
		 0x00, 0x00, 0x00, 0xd0, 0x33, 0x9a, 0x9d, 0x00, 0x00, 0x00, 
		 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0x60, 0x00, 
		 0x00, 0x00, 0x02, 0x00, 0x01, 0xe5, 0x27, 0xde, 0xfc, 0x00, 
		 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 
		 0x82];
	$data{"amber.png"} =
		[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 
		 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 
		 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x00, 0x00, 0x00, 0x25, 
		 0xdb, 0x56, 0xca, 0x00, 0x00, 0x00, 0x07, 0x74, 0x49, 0x4d, 
		 0x45, 0x07, 0xd2, 0x07, 0x11, 0x0f, 0x28, 0x04, 0x98, 0xcb, 
		 0xd6, 0xe0, 0x00, 0x00, 0x00, 0x09, 0x70, 0x48, 0x59, 0x73, 
		 0x00, 0x00, 0x0b, 0x12, 0x00, 0x00, 0x0b, 0x12, 0x01, 0xd2, 
		 0xdd, 0x7e, 0xfc, 0x00, 0x00, 0x00, 0x04, 0x67, 0x41, 0x4d, 
		 0x41, 0x00, 0x00, 0xb1, 0x8f, 0x0b, 0xfc, 0x61, 0x05, 0x00, 
		 0x00, 0x00, 0x06, 0x50, 0x4c, 0x54, 0x45, 0xff, 0xe0, 0x50, 
		 0x00, 0x00, 0x00, 0xa2, 0x7a, 0xda, 0x7e, 0x00, 0x00, 0x00, 
		 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0x60, 0x00, 
	  	 0x00, 0x00, 0x02, 0x00, 0x01, 0xe5, 0x27, 0xde, 0xfc, 0x00, 
  		 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 
  		 0x82];
	$data{"emerald.png"} =
		[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 
		 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 
		 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x00, 0x00, 0x00, 0x25, 
		 0xdb, 0x56, 0xca, 0x00, 0x00, 0x00, 0x07, 0x74, 0x49, 0x4d, 
		 0x45, 0x07, 0xd2, 0x07, 0x11, 0x0f, 0x22, 0x2b, 0xc9, 0xf5, 
		 0x03, 0x33, 0x00, 0x00, 0x00, 0x09, 0x70, 0x48, 0x59, 0x73, 
		 0x00, 0x00, 0x0b, 0x12, 0x00, 0x00, 0x0b, 0x12, 0x01, 0xd2, 
		 0xdd, 0x7e, 0xfc, 0x00, 0x00, 0x00, 0x04, 0x67, 0x41, 0x4d, 
		 0x41, 0x00, 0x00, 0xb1, 0x8f, 0x0b, 0xfc, 0x61, 0x05, 0x00, 
		 0x00, 0x00, 0x06, 0x50, 0x4c, 0x54, 0x45, 0x1b, 0xea, 0x59, 
		 0x0a, 0x0a, 0x0a, 0x0f, 0xba, 0x50, 0x83, 0x00, 0x00, 0x00, 
		 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0x60, 0x00, 
		 0x00, 0x00, 0x02, 0x00, 0x01, 0xe5, 0x27, 0xde, 0xfc, 0x00, 
		 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 
		 0x82];
	$data{"snow.png"} =
		[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 
		 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 
		 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x00, 0x00, 0x00, 0x25, 
		 0xdb, 0x56, 0xca, 0x00, 0x00, 0x00, 0x07, 0x74, 0x49, 0x4d, 
		 0x45, 0x07, 0xd2, 0x07, 0x11, 0x0f, 0x1e, 0x1d, 0x75, 0xbc, 
		 0xef, 0x55, 0x00, 0x00, 0x00, 0x09, 0x70, 0x48, 0x59, 0x73, 
		 0x00, 0x00, 0x0b, 0x12, 0x00, 0x00, 0x0b, 0x12, 0x01, 0xd2, 
		 0xdd, 0x7e, 0xfc, 0x00, 0x00, 0x00, 0x04, 0x67, 0x41, 0x4d, 
		 0x41, 0x00, 0x00, 0xb1, 0x8f, 0x0b, 0xfc, 0x61, 0x05, 0x00, 
		 0x00, 0x00, 0x06, 0x50, 0x4c, 0x54, 0x45, 0xff, 0xff, 0xff, 
		 0x00, 0x00, 0x00, 0x55, 0xc2, 0xd3, 0x7e, 0x00, 0x00, 0x00, 
		 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0x60, 0x00, 
		 0x00, 0x00, 0x02, 0x00, 0x01, 0xe5, 0x27, 0xde, 0xfc, 0x00, 
		 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 
		 0x82];
	$data{"glass.png"} =
		[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 
		 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 
		 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x00, 0x00, 0x00, 0x25, 
		 0xdb, 0x56, 0xca, 0x00, 0x00, 0x00, 0x04, 0x67, 0x41, 0x4d, 
		 0x41, 0x00, 0x00, 0xb1, 0x8f, 0x0b, 0xfc, 0x61, 0x05, 0x00, 
		 0x00, 0x00, 0x06, 0x50, 0x4c, 0x54, 0x45, 0xff, 0xff, 0xff, 
		 0x00, 0x00, 0x00, 0x55, 0xc2, 0xd3, 0x7e, 0x00, 0x00, 0x00, 
		 0x01, 0x74, 0x52, 0x4e, 0x53, 0x00, 0x40, 0xe6, 0xd8, 0x66, 
		 0x00, 0x00, 0x00, 0x01, 0x62, 0x4b, 0x47, 0x44, 0x00, 0x88, 
		 0x05, 0x1d, 0x48, 0x00, 0x00, 0x00, 0x09, 0x70, 0x48, 0x59, 
		 0x73, 0x00, 0x00, 0x0b, 0x12, 0x00, 0x00, 0x0b, 0x12, 0x01, 
		 0xd2, 0xdd, 0x7e, 0xfc, 0x00, 0x00, 0x00, 0x07, 0x74, 0x49, 
		 0x4d, 0x45, 0x07, 0xd2, 0x07, 0x13, 0x0f, 0x08, 0x19, 0xc4, 
		 0x40, 0x56, 0x10, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 
		 0x54, 0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00, 0x02, 0x00, 
		 0x01, 0x48, 0xaf, 0xa4, 0x71, 0x00, 0x00, 0x00, 0x00, 0x49, 
		 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82];

	foreach (keys(%data))
	{
		open(PNG_HANDLE, ">".$_)
			or die("ERROR: cannot create $_!\n");
		binmode(PNG_HANDLE);
		print(PNG_HANDLE map(chr,@{$data{$_}}));
		close(PNG_HANDLE);
	}
}


#
# write_css_file()
#
# Write the cascading style sheet file gcov.css to the current directory.
# This file defines basic layout attributes of all generated HTML pages.
#

sub write_css_file()
{
	local *CSS_HANDLE;

	# Check for a specified external style sheet file
	if ($css_filename)
	{
		# Simply copy that file
		system("cp $css_filename gcov.css 2>/dev/null")
			and die("ERROR: Cannot copy file $css_filename!\n");
		return;
	}

	open(CSS_HANDLE, ">gcov.css")
		or die ("ERROR: cannot open gcov.css for writing!\n");


	# *************************************************************

	my $css_data = ($_=<<"END_OF_CSS")
	/* All views: initial background and text color */
	body
	{
	  color:            #000000;
	  background-color: #FFFFFF;
	}


	/* All views: standard link format*/
	a:link
	{
	  color:           #284FA8;
	  text-decoration: underline;
	}


	/* All views: standard link - visited format */
	a:visited
	{
	  color:           #00CB40;
	  text-decoration: underline;
	}


	/* All views: standard link - activated format */
	a:active
	{
	  color:           #FF0040;
	  text-decoration: underline;
	}


	/* All views: main title format */
	td.title
	{
	  text-align:     center;
	  padding-bottom: 10px;
	  font-family:    sans-serif;
	  font-size:      20pt;
	  font-style:     italic;
	  font-weight:    bold;
	}


	/* All views: header item format */
	td.headerItem
	{
	  text-align:    right;
	  padding-right: 6px;
	  font-family:   sans-serif;
	  font-weight:   bold;
	}


	/* All views: header item value format */
	td.headerValue
	{
	  text-align:  left;
	  color:       #284FA8;
	  font-family: sans-serif;
	  font-weight: bold;
	}


	/* All views: color of horizontal ruler */
	td.ruler
	{
	  background-color: #6688D4;
	}


	/* All views: version string format */
	td.versionInfo
	{
	  text-align:   center;
	  padding-top:  2px;
	  font-family:  sans-serif;
	  font-style:   italic;
	}


	/* Directory view/File view (all)/Test case descriptions:
	   table headline format */
	td.tableHead
	{
	  text-align:       center;
	  color:            #FFFFFF;
	  background-color: #6688D4;
	  font-family:      sans-serif;
	  font-size:        120%;
	  font-weight:      bold;
	}


	/* Directory view/File view (all): filename entry format */
	td.coverFile
	{
	  text-align:       left;
	  padding-left:     10px;
	  padding-right:    20px; 
	  color:            #284FA8;
	  background-color: #DAE7FE;
	  font-family:      monospace;
	}


	/* Directory view/File view (all): bar-graph entry format*/
	td.coverBar
	{
	  padding-left:     10px;
	  padding-right:    10px;
	  background-color: #DAE7FE;
	}


	/* Directory view/File view (all): bar-graph outline color */
	td.coverBarOutline
	{
	  background-color: #000000;
	}


	/* Directory view/File view (all): percentage entry for files with
	   high coverage rate */
	td.coverPerHi
	{
	  text-align:       right;
	  padding-left:     10px;
	  padding-right:    10px;
	  background-color: #DAE7FE;
	  font-weight:      bold;
	}


	/* Directory view/File view (all): line count entry for files with
	   high coverage rate */
	td.coverNumHi
	{
	  text-align:       right;
	  padding-left:     10px;
	  padding-right:    10px;
	  background-color: #DAE7FE;
	}


	/* Directory view/File view (all): percentage entry for files with
	   medium coverage rate */
	td.coverPerMed
	{
	  text-align:       right;
	  padding-left:     10px;
	  padding-right:    10px;
	  background-color: #FFEA20;
	  font-weight:      bold;
	}


	/* Directory view/File view (all): line count entry for files with
	   medium coverage rate */
	td.coverNumMed
	{
	  text-align:       right;
	  padding-left:     10px;
	  padding-right:    10px;
	  background-color: #FFEA20;
	}


	/* Directory view/File view (all): percentage entry for files with
	   low coverage rate */
	td.coverPerLo
	{
	  text-align:       right;
	  padding-left:     10px;
	  padding-right:    10px;
	  background-color: #FF0000;
	  font-weight:      bold;
	}


	/* Directory view/File view (all): line count entry for files with
	   low coverage rate */
	td.coverNumLo
	{
	  text-align:       right;
	  padding-left:     10px;
	  padding-right:    10px;
	  background-color: #FF0000;
	}


	/* File view (all): "show/hide details" link format */
	a.detail:link
	{
	  color: #B8D0FF;
	}


	/* File view (all): "show/hide details" link - visited format */
	a.detail:visited
	{
	  color: #B8D0FF;
	}


	/* File view (all): "show/hide details" link - activated format */
	a.detail:active
	{
	  color: #FFFFFF;
	}


	/* File view (detail): test name table headline format */
	td.testNameHead
	{
	  text-align:       right;
	  padding-right:    10px;
	  background-color: #DAE7FE;
	  font-family:      sans-serif;
	  font-weight:      bold;
	}


	/* File view (detail): test lines table headline format */
	td.testLinesHead
	{
	  text-align:       center;
	  background-color: #DAE7FE;
	  font-family:      sans-serif;
	  font-weight:      bold;
	}


	/* File view (detail): test name entry */
	td.testName
	{
	  text-align:       right;
	  padding-right:    10px;
	  background-color: #DAE7FE;
	}


	/* File view (detail): test percentage entry */
	td.testPer
	{
	  text-align:       right;
	  padding-left:     10px;
	  padding-right:    10px; 
	  background-color: #DAE7FE;
	}


	/* File view (detail): test lines count entry */
	td.testNum
	{
	  text-align:       right;
	  padding-left:     10px;
	  padding-right:    10px; 
	  background-color: #DAE7FE;
	}


	/* Test case descriptions: test name format*/
	dt
	{
	  font-family: sans-serif;
	  font-weight: bold;
	}


	/* Test case descriptions: description table body */
	td.testDescription
	{
	  padding-top:      10px;
	  padding-left:     30px;
	  padding-bottom:   10px;
	  padding-right:    30px;
	  background-color: #DAE7FE;
	}


	/* Source code view: source code format */
	pre.source
	{
	  font-family: monospace;
	  white-space: pre;
	}

	/* Source code view: line number format */
	span.lineNum
	{
	  background-color: #EFE383;
	}


	/* Source code view: format for lines which were executed */
	span.lineCov
	{
	  background-color: #CAD7FE;
	}


	/* Source code view: format for lines which were not executed */
	span.lineNoCov
	{
	  background-color: #FF6230;
	}
END_OF_CSS
	;

	# *************************************************************


	# Remove leading tab from all lines
	$css_data =~ s/^\t//gm;

	print(CSS_HANDLE $css_data);

	close(CSS_HANDLE);
}


#
# get_bar_graph_code(base_dir, cover_found, cover_hit)
#
# Return a string containing HTML code which implements a bar graph display
# for a coverage rate of cover_hit * 100 / cover_found.
#

sub get_bar_graph_code($$$)
{
	my $rate;
	my $alt;
	my $width;
	my $remainder;
	my $png_name;
	my $graph_code;

	# Check number of instrumented lines
	if ($_[1] == 0) { return ""; }

	$rate		= $_[2] * 100 / $_[1];
	$alt		= sprintf("%.1f", $rate)."%";
	$width		= sprintf("%.0f", $rate);
	$remainder	= sprintf("%d", 100-$width);

	# Decide which .png file to use
	if ($rate < $med_limit)		{ $png_name = "ruby.png"; }
	elsif ($rate < $hi_limit)	{ $png_name = "amber.png"; }
	else				{ $png_name = "emerald.png"; }

	if ($width == 0)
	{
		# Zero coverage
		$graph_code = (<<END_OF_HTML)
	        <table border=0 cellspacing=0 cellpadding=1><tr><td class="coverBarOutline"><img src="$_[0]snow.png" width=100 height=10 alt="$alt"></td></tr></table>
END_OF_HTML
		;
	}
	elsif ($width == 100)
	{
		# Full coverage
		$graph_code = (<<END_OF_HTML)
		<table border=0 cellspacing=0 cellpadding=1><tr><td class="coverBarOutline"><img src="$_[0]$png_name" width=100 height=10 alt="$alt"></td></tr></table>
END_OF_HTML
		;
	}
	else
	{
		# Positive coverage
		$graph_code = (<<END_OF_HTML)
		<table border=0 cellspacing=0 cellpadding=1><tr><td class="coverBarOutline"><img src="$_[0]$png_name" width=$width height=10 alt="$alt"><img src="$_[0]snow.png" width=$remainder height=10 alt="$alt"></td></tr></table>
END_OF_HTML
		;
	}

	# Remove leading tabs from all lines
	$graph_code =~ s/^\t+//gm;
	chomp($graph_code);

	return($graph_code);
}


#
# write_html(filehandle, html_code)
#
# Write out HTML_CODE to FILEHANDLE while removing a leading tabulator mark
# in each line of HTML_CODE.
#

sub write_html(*$)
{
	local *HTML_HANDLE = $_[0];
	my $html_code = $_[1];

	# Remove leading tab from all lines
	$html_code =~ s/^\t//gm;

	print(HTML_HANDLE $html_code)
		or die("ERROR: cannot write HTML data ($!)\n");
}


#
# write_html_prolog(filehandle, base_dir, pagetitle)
#
# Write an HTML prolog common to all HTML files to FILEHANDLE. PAGETITLE will
# be used as HTML page title. BASE_DIR contains a relative path which points
# to the base directory.
#

sub write_html_prolog(*$$)
{
	my $pagetitle = $_[2];


	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">

	<html lang="en">

	<head>
	  <meta http-equiv="Content-Type" content="text/html; charset=ISO-8859-1">
	  <title>$pagetitle</title>
	  <link rel="stylesheet" type="text/css" href="$_[1]gcov.css">
	</head>

	<body>

END_OF_HTML
	;

	# *************************************************************
}


#
# write_header_prolog(filehandle, base_dir)
#
# Write beginning of page header HTML code.
#

sub write_header_prolog(*$)
{
	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	  <table width="100%" border=0 cellspacing=0 cellpadding=0>
	    <tr><td class="title">$title</td></tr>
	    <tr><td class="ruler"><img src="$_[1]glass.png" width=3 height=3 alt=""></td></tr>

	    <tr>
	      <td width="100%">
	        <table cellpadding=1 border=0 width="100%">
END_OF_HTML
	;

	# *************************************************************
}


#
# write_header_line(filehandle, item1, value1, [item2, value2])
#
# Write a header line, containing of either one or two pairs "header item"
# and "header value".
#

sub write_header_line(*$$;$$)
{
	my $item1 = $_[1];
	my $value1 = $_[2];

	# Use GOTO to prevent indenting HTML with more than one tabs
	if (scalar(@_) > 3) { goto two_items }

	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	        <tr>
	          <td class="headerItem" width="20%">$item1:</td>
	          <td class="headerValue" width="80%" colspan=4>$value1</td>
	        </tr>
END_OF_HTML
	;

	return();

	# *************************************************************


two_items:
	my $item2 = $_[3];
	my $value2 = $_[4];


	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
        <tr>
          <td class="headerItem" width="20%">$item1:</td>
          <td class="headerValue" width="20%">$value1</td>
          <td width="20%"></td>
          <td class="headerItem" width="20%">$item2:</td>
          <td class="headerValue" width="20%">$value2</td>
        </tr>
END_OF_HTML
	;

	# *************************************************************
}


#
# write_header_epilog(filehandle, base_dir)
#
# Write end of page header HTML code.
#

sub write_header_epilog(*$)
{
	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	        </table>
	      </td>
	    </tr>
	    <tr><td class="ruler"><img src="$_[1]glass.png" width=3 height=3 alt=""></td></tr>
	  </table>

END_OF_HTML
	;

	# *************************************************************
}


#
# write_file_table_prolog(filehandle, left_heading, right_heading)
#
# Write heading for file table.
#

sub write_file_table_prolog(*$$)
{
	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	  <center>
	  <table width="80%" cellpadding=2 cellspacing=1 border=0>

	    <tr>
	      <td width="50%"><br></td>
	      <td width="15%"></td>
	      <td width="15%"></td>
	      <td width="20%"></td>
	    </tr>

	    <tr>
	      <td class="tableHead">$_[1]</td>
	      <td class="tableHead" colspan=3>$_[2]</td>
	    </tr>

END_OF_HTML
	;

	# *************************************************************
}


#
# write_file_table_entry(filehandle, cover_filename, cover_bar_graph,
#                        cover_found, cover_hit)
#
# Write an entry of the file table.
#

sub write_file_table_entry(*$$$$)
{
	my $rate;
	my $rate_string;
	my $classification = "Lo";

	if ($_[3]>0)
	{
		$rate = $_[4] * 100 / $_[3];
		$rate_string = sprintf("%.1f", $rate)."&nbsp;%";

		if ($rate < $med_limit)		{ $classification = "Lo"; }
		elsif ($rate < $hi_limit)	{ $classification = "Med"; }
		else				{ $classification = "Hi"; }
	}
	else
	{
		$rate_string = "undefined";
	}

	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	    <tr>
	      <td class="coverFile">$_[1]</td>
	      <td class="coverBar" align="center">
	        $_[2]
	      </td>
	      <td class="coverPer$classification">$rate_string</td>
	      <td class="coverNum$classification">$_[4]&nbsp;/&nbsp;$_[3]&nbsp;lines</td>
	    </tr>

END_OF_HTML
	;

	# *************************************************************
}


#
# write_file_table_detail_heading(filehandle, left_heading, right_heading)
#
# Write heading for detail section in file table.
#

sub write_file_table_detail_heading(*$$)
{
	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	    <tr>
	      <td class="testNameHead" colspan=2>$_[1]</td>
	      <td class="testLinesHead" colspan=2>$_[2]</td>
	    </tr>

END_OF_HTML
	;

	# *************************************************************
}


#
# write_file_table_detail_entry(filehandle, test_name, cover_found, cover_hit)
#
# Write entry for detail section in file table.
#

sub write_file_table_detail_entry(*$$$)
{
	my $rate;
	my $name = $_[1];
	
	if ($_[2]>0)
	{
		$rate = sprintf("%.1f", $_[3]*100/$_[2])."&nbsp;%";
	}
	else
	{
		$rate = "undefined";
	}

	if ($name eq "")
	{
		$name = "<span style=\"font-style:italic\">&lt;unnamed&gt;</span>";
	}

	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	    <tr>
	      <td class="testName" colspan=2>$name</td>
	      <td class="testPer">$rate</td>
	      <td class="testNum">$_[3]&nbsp;/&nbsp;$_[2]&nbsp;lines</td>
	    </tr>

END_OF_HTML
	;

	# *************************************************************
}


#
# write_file_table_epilog(filehandle)
#
# Write end of file table HTML code.
#

sub write_file_table_epilog(*)
{
	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	  </table>
	  </center>
	  <br>

END_OF_HTML
	;

	# *************************************************************
}


#
# write_test_table_prolog(filehandle, table_heading)
#
# Write heading for test case description table.
#

sub write_test_table_prolog(*$)
{
	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	  <center>
	  <table width="80%" cellpadding=2 cellspacing=1 border=0>

	    <tr>
	      <td><br></td>
	    </tr>

	    <tr>
	      <td class="tableHead">$_[1]</td>
	    </tr>

	    <tr>
	      <td class="testDescription">
	        <dl>
END_OF_HTML
	;

	# *************************************************************
}


#
# write_test_table_entry(filehandle, test_name, test_description)
#
# Write entry for the test table.
#

sub write_test_table_entry(*$$)
{
	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
          <dt>$_[1]<a name="$_[1]">&nbsp;</a></dt>
          <dd>$_[2]<br><br></dd>
END_OF_HTML
	;

	# *************************************************************
}


#
# write_test_table_epilog(filehandle)
#
# Write end of test description table HTML code.
#

sub write_test_table_epilog(*)
{
	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	        </dl>
	      </td>
	    </tr>
	  </table>
	  </center>
	  <br>

END_OF_HTML
	;

	# *************************************************************
}


#
# write_source_prolog(filehandle)
#
# Write start of source code table.
#

sub write_source_prolog(*)
{
	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	  <table cellpadding=0 cellspacing=0 border=0>
	    <tr>
	      <td><br></td>
	    </tr>
	    <tr>
	      <td><pre class="source">
END_OF_HTML
	;

	# *************************************************************
}


#
# write_source_line(filehandle, line_num, source, hit_count)
#
# Write formatted source code line. Return a line in a format as needed
# by gen_png()
#

sub write_source_line(*$$$)
{
	my $source_format;
	my $count;
	my $result;
	my $anchor_start = "";
	my $anchor_end = "";

	if (!(defined$_[3]))
	{
		$result		= "";
		$source_format	= "";
		$count		= " "x15;
	}
	elsif ($_[3] == 0)
	{
		$result		= $_[3];
		$source_format	= '<span class="lineNoCov">';
		$count		= sprintf("%15d", $_[3]);
	}
	else
	{
		$result		= $_[3];
		$source_format	= '<span class="lineCov">';
		$count		= sprintf("%15d", $_[3]);
	}

	$result .= ":".$_[2];

	# Write out a line number navigation anchor every $nav_resolution
	# lines if necessary
	if ($frames && (($_[1] - 1) % $nav_resolution == 0))
	{
		$anchor_start	= "<a name=\"$_[1]\">";
		$anchor_end	= "</a>";
	}


	# *************************************************************

	write_html($_[0],
		   $anchor_start.
		   '<span class="lineNum">'.sprintf("%8d", $_[1]).
		   " </span>$source_format$count : ".
		   escape_html($_[2]).($source_format?"</span>":"").
		   $anchor_end."\n");

	# *************************************************************

	return($result);
}


#
# write_source_epilog(filehandle)
#
# Write end of source code table.
#

sub write_source_epilog(*)
{
	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	</pre>
	      </td>
	    </tr>
	  </table>
	  <br>

END_OF_HTML
	;

	# *************************************************************
}


#
# write_html_epilog(filehandle, base_dir[, break_frames])
#
# Write HTML page footer to FILEHANDLE. BREAK_FRAMES should be set when
# this page is embedded in a frameset, clicking the URL link will then
# break this frameset.
#

sub write_html_epilog(*$;$)
{
	my $break_code = "";

	if (defined($_[2]))
	{
		$break_code = " target=\"_parent\"";
	}

	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	  <table width="100%" border=0 cellspacing=0 cellpadding=0>
	  <tr><td class="ruler"><img src="$_[1]glass.png" width=3 height=3 alt=""></td></tr>
	  <tr><td class="versionInfo">Generator: <a href="$url"$break_code>$tool_name</a> ($version_info)</td></tr>
	  </table>
	  <br>

	</body>
	</html>
END_OF_HTML
	;

	# *************************************************************
}


#
# write_frameset(filehandle, basedir, basename, pagetitle)
#
#

sub write_frameset(*$$$)
{
	my $frame_width = $overview_width + 40;

	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Frameset//EN">

	<html lang="en">

	<head>
	  <meta http-equiv="Content-Type" content="text/html; charset=ISO-8859-1">
	  <title>$_[3]</title>
	  <link rel="stylesheet" type="text/css" href="$_[1]gcov.css">
	</head>

	<frameset cols="$frame_width,*">
	  <frame src="$_[2].gcov.overview.html" name="overview">
	  <frame src="$_[2].gcov.html" name="source">
	  <noframes>
	    <center>Frames not supported by your browser!<br></center>
	  </noframes>
	</frameset>

	</html>
END_OF_HTML
	;

	# *************************************************************
}


#
# sub write_overview_line(filehandle, basename, line, link)
#
#

sub write_overview_line(*$$$)
{
	my $y1 = $_[2] - 1;
	my $y2 = $y1 + $nav_resolution - 1;
	my $x2 = $overview_width - 1;

	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	    <area shape="rect" coords="0,$y1,$x2,$y2" href="$_[1].gcov.html#$_[3]" target="source" alt="overview">
END_OF_HTML
	;

	# *************************************************************
}


#
# write_overview(filehandle, basedir, basename, pagetitle, lines)
#
#

sub write_overview(*$$$$)
{
	my $index;
	my $max_line = $_[4] - 1;
	my $offset;

	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">

	<html lang="en">

	<head>
	  <title>$_[3]</title>
	  <meta http-equiv="Content-Type" content="text/html; charset=ISO-8859-1">
	  <link rel="stylesheet" type="text/css" href="$_[1]gcov.css">
	</head>

	<body>
	  <map name="overview">
END_OF_HTML
	;

	# *************************************************************

	# Make $offset the next higher multiple of $nav_resolution
	$offset = ($nav_offset + $nav_resolution - 1) / $nav_resolution;
	$offset = sprintf("%d", $offset ) * $nav_resolution;

	# Create image map for overview image
	for ($index = 1; $index <= $_[4]; $index += $nav_resolution)
	{
		# Enforce nav_offset
		if ($index < $offset + 1)
		{
			write_overview_line($_[0], $_[2], $index, 1);
		}
		else
		{
			write_overview_line($_[0], $_[2], $index, $index - $offset);
		}
	}

	# *************************************************************

	write_html($_[0], <<END_OF_HTML)
	  </map>

	  <center>
	  <a href="$_[2].gcov.html#top" target="source">Top</a><br><br>
	  <img src="$_[2].gcov.png" width=$overview_width height=$max_line alt="Overview" border=0 usemap="#overview">
	  </center>
	</body>
	</html>
END_OF_HTML
	;

	# *************************************************************
}


#
# write_header(filehandle, type, trunc_file_name, rel_file_name, lines_found,
# lines_hit)
#
# Write a complete standard page header. TYPE may be (0, 1, 2, 3)
# corresponding to (overview header, directory overview header, file header,
# test case description header)
#

sub write_header(*$$$$$)
{
	local *HTML_HANDLE = $_[0];
	my $type = $_[1];
	my $trunc_name = $_[2];
	my $rel_filename = $_[3];
	my $lines_found = $_[4];
	my $lines_hit = $_[5];
	my $base_dir;
	my $view;
	my $test;
	my $rate;
	my $base_name;

	# Calculate coverage rate
	if ($lines_found>0)
	{
		$rate = sprintf("%.1f", $lines_hit * 100 / $lines_found)." %";
	}
	else
	{
		$rate = "-";
	}

	$base_name = basename($rel_filename);

	# Prepare text for "current view" field
	if ($type == 0)
	{
		# Main overview
		$base_dir = "";
		$view = "overview";
	}
	elsif ($type == 1)
	{
		# Directory overview
		$base_dir = get_relative_base_path($rel_filename);
		$view = "<a href=\"$base_dir"."index.html\">overview</a> - ".
			"$trunc_name";
	}
	elsif ($type == 2)
	{
		# File view
		my $dir_name = dirname($rel_filename);

		

		$base_dir = get_relative_base_path($dir_name);
		if ($frames)
		{
			# Need to break frameset when clicking any of these
			# links
			$view = "<a href=\"$base_dir"."index.html\" ".
				"target=\"_parent\">overview</a> - ".
				"<a href=\"index.html\" target=\"_parent\">".
				"$dir_name</a> - $base_name";
		}
		else
		{
			$view = "<a href=\"$base_dir"."index.html\">".
				"overview</a> - ".
				"<a href=\"index.html\">".
				"$dir_name</a> - $base_name";
		}
	}
	elsif ($type == 3)
	{
		# Test description header
		$base_dir = "";
		$view = "<a href=\"$base_dir"."index.html\">overview</a> - ".
			"test case descriptions";
	}

	# Prepare text for "test" field
	$test = escape_html($test_title);

	# Append link to test description page if available
	if (%test_description && ($type != 3))
	{
		if ($frames && ($type == 2))
		{
			# Need to break frameset when clicking this link
			$test .= " ( <a href=\"$base_dir".
				 "descriptions.html\" target=\"_parent\">".
				 "view test case descriptions</a> )";
		}
		else
		{
			$test .= " ( <a href=\"$base_dir".
				 "descriptions.html\">".
				 "view test case descriptions</a> )";
		}
	}

	# Write header
	write_header_prolog(*HTML_HANDLE, $base_dir);
	write_header_line(*HTML_HANDLE, "Current&nbsp;view", $view);
	write_header_line(*HTML_HANDLE, "Test", $test);
	write_header_line(*HTML_HANDLE, "Date", $date,
			  "Instrumented&nbsp;lines", $lines_found);
	write_header_line(*HTML_HANDLE, "Code&nbsp;covered", $rate,
			  "Executed&nbsp;lines", $lines_hit);
	write_header_epilog(*HTML_HANDLE, $base_dir);
}


#
# split_filename(filename)
#
# Return (path, filename, extension) for a given FILENAME.
#

sub split_filename($)
{
	if (!$_[0]) { return(); }
	my @path_components = split('/', $_[0]);
	my @file_components = split('\.', pop(@path_components));
	my $extension = pop(@file_components);

	return (join("/",@path_components), join(".",@file_components),
		$extension);
}


#
# write_file_table(filehandle, base_dir, overview, testhash)
#
# Write a complete file table. OVERVIEW is a reference to a hash containing
# the following mapping:
#
#   filename -> "lines_found,lines_hit,page_link"
#
# TESTHASH is a reference to the following hash:
#
#   filename -> \%testdata
#   %testdata: name of test affecting this file -> \%testcount
#   %testcount: line number -> execution count for a single test
#

sub write_file_table(*$$$)
{
	local *HTML_HANDLE = $_[0];
	my $base_dir = $_[1];
	my %overview = %{$_[2]};
	my %testhash = %{$_[3]};
	my $filename;
	my $bar_graph;
	my $hit;
	my $found;
	my $page_link;
	my $testname;
	my $testdata;
	my $testcount;
	my %affecting_tests;
	my $coverage_heading = "Coverage";

	# Provide a link to details/non-detail list if this is directory
	# overview and we are supposed to create a detail view
	if (($base_dir ne "") && $show_details)
	{
		if (%testhash)
		{
			# This is the detail list, provide link to standard
			# list
			$coverage_heading .= " ( <a class=\"detail\" href=\"".
					     "index.html\">hide ".
					     "details</a> )";
		}
		else
		{
			# This is the standard list, provide link to detail
			# list
			$coverage_heading .= " ( <a class=\"detail\" href=\"".
					     "index-detail.html\">show ".
					     "details</a> )";
		}
	}

	write_file_table_prolog(*HTML_HANDLE, "Filename", $coverage_heading);

	foreach $filename (sort(keys(%overview)))
	{
		($found, $hit, $page_link) = split(",", $overview{$filename});
		$bar_graph = get_bar_graph_code($base_dir, $found, $hit);

		$testdata = $testhash{$filename};

		# Add anchor tag in case a page link is provided
		if ($page_link)
		{
			$filename = "<a href=\"$page_link\">$filename</a>";
		}

		write_file_table_entry(*HTML_HANDLE, $filename, $bar_graph,
				       $found, $hit);

		# Check whether we should write test specific coverage
		# as well
		if (!($show_details && $testdata)) { next; }

		# Filter out those tests that actually affect this file
		%affecting_tests = %{ get_affecting_tests($testdata) };

		# Does any of the tests affect this file at all?
		if (!%affecting_tests) { next; }

		# Write test details for this entry
		write_file_table_detail_heading(*HTML_HANDLE, "Test name",
						"Lines hit");

		foreach $testname (keys(%affecting_tests))
		{
			($found, $hit) =
				split(",", $affecting_tests{$testname});

			# Insert link to description of available
			if ($test_description{$testname})
			{
				$testname = "<a href=\"$base_dir".
					    "descriptions.html#$testname\">".
					    "$testname</a>";
			}

			write_file_table_detail_entry(*HTML_HANDLE, $testname,
				$found, $hit);
		}
	}

	write_file_table_epilog(*HTML_HANDLE);
}


#
# get_found_and_hit(hash)
#
# Return the count for entries (found) and entries with an execution count
# greater than zero (hit) in a hash (linenumber -> execution count) as
# a list (found, hit)
#

sub get_found_and_hit($)
{
	my %hash = %{$_[0]};
	my $found = 0;
	my $hit = 0;

	# Calculate sum
	$found = 0;
	$hit = 0;
			
	foreach (keys(%hash))
	{
		$found++;
		if ($hash{$_}>0) { $hit++; }
	}

	return ($found, $hit);
}


#
# get_affecting_tests(hashref)
#
# HASHREF contains a mapping filename -> (linenumber -> exec count). Return
# a hash containing mapping filename -> "lines found, lines hit" for each
# filename which has a nonzero hit count.
#

sub get_affecting_tests($)
{
	my %hash = %{$_[0]};
	my $testname;
	my $testcount;
	my %result;
	my $found;
	my $hit;

	foreach $testname (keys(%hash))
	{
		# Get (line number -> count) hash for this test case
		$testcount = $hash{$testname};

		# Calculate sum
		($found, $hit) = get_found_and_hit($testcount);

		if ($hit>0)
		{
			$result{$testname} = "$found,$hit";
		}
	}

	return(\%result);
}


#
# write_source(filehandle, source_filename, count_data)
#
# Write an HTML view of a source code file. Returns a list containing
# data as needed by gen_png().
#
# Die on error.
#

sub write_source($$$)
{
	local *HTML_HANDLE = $_[0];
	local *SOURCE_HANDLE;
	my $source_filename = $_[1];
	my %count_data;
	my $line_number;
	my @result;

	if ($_[2])
	{
		%count_data = %{$_[2]};
	}

	open(SOURCE_HANDLE, "<".$source_filename)
		or die("ERROR: cannot open $source_filename for reading!\n");
	
	write_source_prolog(*HTML_HANDLE);

	for ($line_number = 1; <SOURCE_HANDLE> ; $line_number++)
	{
		chomp($_);
		push (@result,
		      write_source_line(HTML_HANDLE, $line_number,
					$_, $count_data{$line_number}));
	}

	close(SOURCE_HANDLE);
	write_source_epilog(*HTML_HANDLE);
	return(@result);
}


#
# info(printf_parameter)
#
# Use printf to write PRINTF_PARAMETER to stdout only when the $quiet flag
# is not set.
#

sub info(@)
{
	if (!$quiet)
	{
		# Print info string
		printf(@_);
	}
}


#
# subtract_counts(data_ref, base_ref)
#

sub subtract_counts($$)
{
	my %data = %{$_[0]};
	my %base = %{$_[1]};
	my $line;
	my $data_count;
	my $base_count;
	my $hit = 0;
	my $found = 0;

	foreach $line (keys(%data))
	{
		$found++;
		$data_count = $data{$line};
		$base_count = $base{$line};

		if (defined($base_count))
		{
			$data_count -= $base_count;

			# Make sure we don't get negative numbers
			if ($data_count<0) { $data_count = 0; }
		}

		$data{$line} = $data_count;
		if ($data_count > 0) { $hit++; }
	}

	return (\%data, $found, $hit);
}


#
# add_counts(data1_ref, data2_ref)
#
# DATA1_REF and DATA2_REF are references to hashes containing a mapping
#
#   line number -> execution count
#
# Return a list (RESULT_REF, LINES_FOUND, LINES_HIT) where RESULT_REF
# is a reference to a hash containing the combined mapping in which
# execution counts are added.
#

sub add_counts($$)
{
	my %data1 = %{$_[0]};	# Hash 1
	my %data2 = %{$_[1]};	# Hash 2
	my %result;		# Resulting hash
	my $line;		# Current line iteration scalar
	my $data1_count;	# Count of line in hash1
	my $data2_count;	# Count of line in hash2
	my $found = 0;		# Total number of lines found
	my $hit = 0;		# Number of lines with a count > 0

	foreach $line (keys(%data1))
	{
		$data1_count = $data1{$line};
		$data2_count = $data2{$line};

		# Add counts if present in both hashes
		if (defined($data2_count)) { $data1_count += $data2_count; }

		# Store sum in %result
		$result{$line} = $data1_count;

		$found++;
		if ($data1_count > 0) { $hit++; }
	}

	# Add lines unique to data2
	foreach $line (keys(%data2))
	{
		# Skip lines already in data1
		if (defined($data1{$line})) { next; }

		# Copy count from data2
		$result{$line} = $data2{$line};

		$found++;
		if ($result{$line} > 0) { $hit++; }
	}

	return (\%result, $found, $hit);
}


#
# apply_baseline(data_ref, baseline_ref)
#
# Subtract the execution counts found in the baseline hash referenced by
# BASELINE_REF from actual data in DATA_REF.
#

sub apply_baseline($$)
{
	my %data_hash = %{$_[0]};
	my %base_hash = %{$_[1]};
	my $filename;
	my $testname;
	my $data;
	my $data_testdata;
	my $data_funcdata;
	my $data_count;
	my $base;
	my $base_testdata;
	my $base_count;
	my $sumcount;
	my $found;
	my $hit;

	foreach $filename (keys(%data_hash))
	{
		# Get data set for data and baseline
		$data = $data_hash{$filename};
		$base = $base_hash{$filename};

		# Get set entries for data and baseline
		($data_testdata, undef, $data_funcdata) =
			get_info_entry($data);
		($base_testdata, $base_count) = get_info_entry($base);

		# Sumcount has to be calculated anew
		$sumcount = {};

		# For each test case, subtract test specific counts
		foreach $testname (keys(%{$data_testdata}))
		{
			# Get counts of both data and baseline
			$data_count = $data_testdata->{$testname};

			$hit = 0;

			($data_count, undef, $hit) =
				subtract_counts($data_count, $base_count);

			# Check whether this test case did hit any line at all
			if ($hit > 0)
			{
				# Write back resulting hash
				$data_testdata->{$testname} = $data_count;
			}
			else
			{
				# Delete test case which did not impact this
				# file
				delete($data_testdata->{$testname});
			}

			# Add counts to sum of counts
			($sumcount, $found, $hit) =
				add_counts($sumcount, $data_count);
		}

		# Write back resulting entry
		set_info_entry($data, $data_testdata, $sumcount,
			       $data_funcdata, $found, $hit);

		$data_hash{$filename} = $data;
	}

	return (\%data_hash);
}


#
# remove_unused_descriptions()
#
# Removes all test descriptions from the global hash %test_description which
# are not present in %info_data.
#

sub remove_unused_descriptions()
{
	my $filename;		# The current filename
	my %test_list;		# Hash containing found test names
	my $test_data;		# Reference to hash test_name -> count_data
	my $before;		# Initial number of descriptions
	my $after;		# Remaining number of descriptions
	
	$before = scalar(keys(%test_description));

	foreach $filename (keys(%info_data))
	{
		($test_data) = get_info_entry($info_data{$filename});
		foreach (keys(%{$test_data}))
		{
			$test_list{$_} = "";
		}
	}

	# Remove descriptions for tests which are not in our list
	foreach (keys(%test_description))
	{
		if (!defined($test_list{$_}))
		{
			delete($test_description{$_});
		}
	}

	$after = scalar(keys(%test_description));
	info("Removed ".($before - $after).
	     " descriptions, $after remaining.\n");
}


#
# combine_info_entries(entry_ref1, entry_ref2)
#
# Combine .info data entry hashes referenced by ENTRY_REF1 and ENTRY_REF2.
# Return reference to resulting hash.
#

sub combine_info_entries($$)
{
	my $entry1 = $_[0];	# Reference to hash containing first entry
	my $testdata1;
	my $sumcount1;
	my $funcdata1;

	my $entry2 = $_[1];	# Reference to hash containing second entry
	my $testdata2;
	my $sumcount2;
	my $funcdata2;

	my %result;		# Hash containg combined entry
	my %result_testdata;
	my $result_sumcount = {};
	my %result_funcdata;
	my $lines_found;
	my $lines_hit;

	my $testname;

	# Retrieve data
	($testdata1, $sumcount1, $funcdata1) = get_info_entry($entry1);
	($testdata2, $sumcount2, $funcdata2) = get_info_entry($entry2);

	# Combine funcdata
	foreach (keys(%{$funcdata1}))
	{
		$result_funcdata{$_} = $funcdata1->{$_};
	}

	foreach (keys(%{$funcdata2}))
	{
		$result_funcdata{$_} = $funcdata2->{$_};
	}
	
	# Combine testdata
	foreach $testname (keys(%{$testdata1}))
	{
		if (defined($testdata2->{$testname}))
		{
			# testname is present in both entries, requires
			# combination
			($result_testdata{$testname}) =
				add_counts($testdata1->{$testname},
					   $testdata2->{$testname});
		}
		else
		{
			# testname only present in entry1, add to result
			$result_testdata{$testname} = $testdata1->{$testname};
		}

		# update sum count hash
		($result_sumcount, $lines_found, $lines_hit) =
			add_counts($result_sumcount,
				   $result_testdata{$testname});
	}

	foreach $testname (keys(%{$testdata2}))
	{
		# Skip testnames already covered by previous iteration
		if (defined($testdata1->{$testname})) { next; }

		# testname only present in entry2, add to result hash
		$result_testdata{$testname} = $testdata2->{$testname};

		# update sum count hash
		($result_sumcount, $lines_found, $lines_hit) =
			add_counts($result_sumcount,
				   $result_testdata{$testname});
	}
	
	# Calculate resulting sumcount

	# Store result
	set_info_entry(\%result, \%result_testdata, $result_sumcount,
		       \%result_funcdata, $lines_found, $lines_hit);

	return(\%result);
}


#
# combine_info_files(info_ref1, info_ref2)
#
# Combine .info data in hashes referenced by INFO_REF1 and INFO_REF2. Return
# reference to resulting hash.
#

sub combine_info_files($$)
{
	my %hash1 = %{$_[0]};
	my %hash2 = %{$_[1]};
	my $filename;

	foreach $filename (keys(%hash2))
	{
		if ($hash1{$filename})
		{
			# Entry already exists in hash1, combine them
			$hash1{$filename} =
				combine_info_entries($hash1{$filename},
						     $hash2{$filename});
		}
		else
		{
			# Entry is unique in both hashes, simply add to
			# resulting hash
			$hash1{$filename} = $hash2{$filename};
		}
	}

	return(\%hash1);
}


#
# apply_prefix(filename, prefix)
#
# If FILENAME begins with PREFIX, remove PREFIX from FILENAME and return
# resulting string, otherwise return FILENAME.
#

sub apply_prefix($$)
{
	if (defined($_[1]) && ($_[1] ne ""))
	{
		if ($_[0] =~ /^$_[1]\/(.*)$/)
		{
			return $1;
		}
	}

	return $_[0];
}
