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
# lcov.pl
#
#   This is a wrapper script which provides a single interface for accessing
#   coverage data.
#
#
# History:
#   2002-08-29 created by Peter Oberparleiter <Peter.Oberparleiter@de.ibm.com>
#                         IBM Lab Boeblingen
#   2002-09-05 / Peter Oberparleiter: implemented --kernel-directory + multiple
#                                     directories
#

use strict;
use File::Basename; 
use Getopt::Long;


# Global constants
our $version_info	= "LTP GCOV extension version 1.0";
our $url		= "http://ltp.sourceforge.net/lcov.php";

# The location of the insmod tool
our $insmod_tool	= "/sbin/insmod";

# The location of the rmmod tool
our $rmmod_tool		= "/sbin/rmmod";

# Where to create temporary directories
our $tmp_dir		= ".";

# How to prefix a temporary directory name
our $tmp_prefix		= "tmpdir";


# Prototypes
sub print_usage(*);
sub userspace_reset();
sub userspace_capture();
sub kernel_reset();
sub kernel_capture();
sub info(@);
sub unload_module();
sub check_and_load_kernel_module();
sub create_temp_dir();


# Global variables & initialization
our @directory;		# Specifies where to get coverage data from
our @kernel_directory;	# If set, uses only the specified kernel subdirs during capture
our $reset;		# If set, reset all coverage data to zero
our $capture;		# If set, capture data
our $output_filename;	# Name for file to write coverage data to
our $test_name = "";	# Test case name
our $quiet = "";	# If set, suppress information messages
our $help;		# Help option flag
our $version;		# Version option flag
our $need_unload;	# If set, unload gcov-proc module
our $temp_dir_name;	# Name of temporary directory
our $cwd = `pwd`;	# Current working directory
chomp($cwd);
our $tool_dir = dirname($0);	# Directory where genhtml.pl tool is installed

# Add current working directory if $tool_dir is not already an absolute path
if (! ($tool_dir =~ /^\/(.*)$/))
{
	$tool_dir = "$cwd/$tool_dir";
}


#
# Code entry point
#

# Parse command line options
if (!GetOptions("directory=s" => \@directory,
		"kernel-directory=s" => \@kernel_directory,
		"capture" => \$capture,
		"output-file=s" => \$output_filename,
		"test-name=s" => \$test_name,
		"reset" => \$reset,
		"quiet" => \$quiet,
		"help" => \$help,
		"version" => \$version
		))
{
	print_usage(*STDERR);
	exit(1);
}

# Check for help option
if ($help)
{
	print_usage(*STDOUT);
	exit(0);
}

# Check for version option
if ($version)
{
	print("$version_info\n");
	exit(0);
}

# Check for output filename
if ($capture)
{
	if ($output_filename && ($output_filename ne "-"))
	{
		$output_filename = "--output-filename $output_filename";
	}
	else
	{
		# Need to supress progress messages when no output filename is
		# specified because stdout will be used to write data to
		$quiet = 1;

		# Option that tells geninfo to write to stdout
		$output_filename = "--output-filename -";
	}
}

# Check for test name
if ($test_name)
{
	$test_name = "--test-name $test_name";
}

# Check for quiet option
if ($quiet)
{
	$quiet = "--quiet";
}


# Check for requested functionality
if ($reset)
{
	# Only one of these options is allowed at a time
	if ($capture)
	{
		die("ERROR: cannot reset and capture at the same time!\n");
	}

	# Differentiate between user space and kernel reset
	if (@directory)
	{
		userspace_reset();
	}
	else
	{
		kernel_reset();
	}
}
elsif ($capture)
{
	# Differentiate between user space and kernel 
	if (@directory)
	{
		userspace_capture();
	}
	else
	{
		kernel_capture();
	}
}
else
{
	print(STDERR
	      "Need one of the options --capture or --reset\n");
	print_usage(*STDERR);
	exit(2);
}

info("Done.\n");
exit(0);


#
# print_usage(handle)
#
# Print usage information.
#

sub print_usage(*)
{
	local *HANDLE = $_[0];
	my $tool_name = basename($0);

	print(HANDLE <<END_OF_USAGE);
Usage: $tool_name [OPTIONS]

Access GCOV code coverage data. By default, tries to access kernel coverage
data (requires kernel module gcov-proc to be installed separately). Use the
--directory option to get coverage data from a user space program.

  -h, --help                      Print this help, then exit
  -v, --version                   Print version number, then exit
  -q, --quiet                     Do not print progress messages
  -r, --reset                     Reset all execution counts
  -c, --capture                   Capture coverage data
  -t, --test-name NAME            Specify test name to be stored with data
  -o, --output-file FILENAME      Write data to FILENAME instead of stdout
  -d, --directory DIR(s)          Use .da files in DIR instead of kernel
  -k, --kernel-directory KDIR(s)  Capture kernel coverage data only from KDIR

See $url for more information on this tool.
END_OF_USAGE
	;
}


#
# userspace_reset()
#
# Reset coverage data found in DIRECTORY by deleting all contained .da files.
#
# Die on error.
#

sub userspace_reset()
{
	my $current_dir;
	my @file_list;

	foreach $current_dir (@directory)
	{
		info("Deleting all .da files in $current_dir and subdirectories\n");
		@file_list =
			`find $current_dir -follow -name \\*.da -type f 2>/dev/null`;
		chomp(@file_list);
		foreach (@file_list)
		{
			unlink($_) or die("ERROR: cannot remove file $_!\n");
		}
	}
}


#
# userspace_capture()
#
# Capture coverage data found in DIRECTORY and write it to OUTPUT_FILENAME
# if specified, otherwise to STDOUT.
#
# Die on error.
#

sub userspace_capture()
{
	my $file_list = join(" ", @directory);
	info("Capturing coverage data from $file_list\n");
	system("$tool_dir/geninfo.pl $file_list ".
	       "$output_filename ".
	       "$test_name ".
	       "$quiet") and exit($? >> 8);
}


#
# kernel_reset()
#
# Reset kernel coverage data by writing "0" to /proc/gcov/vmlinux.
#
# Die on error.
#

sub kernel_reset()
{
	check_and_load_kernel_module();

	info("Resetting kernel execution counters\n");
	system("echo \"0\" >/proc/gcov/vmlinux") and
		die("ERROR: cannot write to /proc/gcov/vmlinux!\n");

	# Unload module if we loaded it in the first place
	if ($need_unload)
	{
		unload_module();
	}
}


#
# kernel_capture()
#
# Capture kernel coverage data and write it to OUTPUT_FILENAME if specified,
# otherwise stdout.
#

sub kernel_capture()
{
	check_and_load_kernel_module();

	# Make sure the temporary directory is removed upon script termination
	END
	{
		if ($temp_dir_name)
		{
			stat($temp_dir_name);
			if (-r _)
			{
				info("Removing temporary directory ".
				     "$temp_dir_name\n");

				# Remove temporary directory
				system("rm -rf $temp_dir_name")
					and warn("WARNING: cannot remove ".
						 "temporary directory ".
						 "$temp_dir_name!\n");
			}
		}
	}

	# Get temporary directory
	$temp_dir_name = create_temp_dir();

	info("Copying kernel data to temporary directory $temp_dir_name\n");

	if (!@kernel_directory)
	{
		# Copy files from /proc/gcov
		system("cp -dr /proc/gcov $temp_dir_name")
			and die("ERROR: cannot copy files from /proc/gcov!\n");
	}
	else
	{
		# Add /proc/gcov to list of kernel files
		my $file_list = join(" ", map {"/proc/gcov/$_";} @kernel_directory);

		# Copy files from /proc/gcov
		system("cp -dr $file_list $temp_dir_name")
			and die("ERROR: cannot copy files from $file_list!\n");
	}

	# Make directories writeable
	system("find $temp_dir_name -type d -exec chmod u+w \\{\\} \\;")
		and die("ERROR: cannot modify access rights for ".
			"$temp_dir_name!\n");

	# Make directories writeable
	system("find $temp_dir_name -type f -exec chmod u+w \\{\\} \\;")
		and die("ERROR: cannot modify access rights for ".
			"$temp_dir_name!\n");

	# Capture data
	info("Capturing coverage data from $temp_dir_name\n");
	system("$tool_dir/geninfo.pl $temp_dir_name ".
	       "$output_filename ".
	       "$test_name ".
	       "$quiet") and exit($? >> 8);


	# Unload module if we loaded it in the first place
	if ($need_unload)
	{
		unload_module();
	}
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
# Check if kernel module gcov-proc.o is loaded. If it is, exit, if not, try
# to load it.
#
# Die on error.
#

sub check_and_load_kernel_module()
{
	# Is it loaded already?
	stat("/proc/gcov");
	if (-r _) { return(); }

	info("Load required kernel module gcov-proc.o\n");

	# Do we have access to the insmod tool?
	stat($insmod_tool);
	if (!-x _)
	{
		die("ERROR: cannot execute insmod tool at $insmod_tool!\n");
	}

	# Try to load module from system wide module directory /lib/modules
	if (!system("$insmod_tool gcov-proc 2>/dev/null >/dev/null"))
	{
		# Suceeded
		$need_unload = 1;
		return();
	}

	# Try to load module from tool directory
	if (!system("$insmod_tool $tool_dir/gcov-proc.o 2>/dev/null ".
		    ">/dev/null"))
	{
		# Succeeded
		$need_unload = 1;
		return();
	}

	# Hm, loading failed - maybe we aren't root?
	if ($> != 0)
	{
		die("ERROR: need root to load kernel module!\n");
	}

	die("ERROR: cannot load required kernel module gcov-proc.o!\n");
}


#
# unload_module()
#
# Unload the gcov-proc module.
#

sub unload_module()
{
	info("Unloading kernel module\n");

	# Do we have access to the rmmod tool?
	stat($rmmod_tool);
	if (!-x _)
	{
		warn("WARNING: cannot execute rmmod tool at $rmmod_tool - ".
		     "module still laoded!\n");
	}

	# Unload gcov-proc
	system("$rmmod_tool gcov-proc 2>/dev/null")
		and warn("WARNING: cannot unload kernel module gcov-proc!\n");
}


#
# create_temp_dir()
#
# Create a temporary directory and return its path.
#
# Die on error.
#

sub create_temp_dir()
{
	my $dirname;
	my $number = sprintf("%d", rand(1000));

	# Endless loops are evil
	while ($number++ < 1000)
	{
		$dirname = "$tmp_dir/$tmp_prefix$number";
		stat($dirname);
		if (-e _) { next; }

		mkdir($dirname)
			or die("ERROR: cannot create temporary directory ".
			       "$dirname!\n");

		return($dirname);
	}

	die("ERROR: cannot create temporary directory in $tmp_dir!\n");
}
