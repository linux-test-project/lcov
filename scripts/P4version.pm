#!/usr/bin/env perl
#   Copyright (c) MediaTek USA Inc., 2022-2024
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
#   along with this program;  if not, see
#   <http://www.gnu.org/licenses/>.
#
#
# P4version.pm [--md5] [--allow-missing] [--local-edit] [--prefix path] depot_path
#
#   Called as:
#       $callback = P4version->new(@args)                            : constructor
#       $version = $callback->version($filepath)                     : extract version
#       $callback->compare_version($version1, $version2, $filepath)  : compare versions
#
#   Options:
#     depot_path:
#         Root of P4 repository
#     --allow-missing
#         If set, do not error out if called with file which is not in git.
#         Default is to error out.
#     --local-edit
#         Look for - and support - local edit
#     --prefix
#         If specified, 'path' is prependied to 'pathname' (as 'path/pathname')
#         before processing.
#     --md5
#         Return MD5 signature for files that are not in git

#   This is a sample script which uses p4 commands to determine
#   the version of the filename parameter.
#   Version information (if present) is used during ".info" file merging
#   to verify that the data the user is attempting to merge is for the same
#   source code/same version.
#   If the version is not the same - then line numbers, etc. may be different
#   and some very strange errors may occur.

package P4version;

use strict;
use POSIX qw(strftime);
use File::Spec;
use Cwd qw(abs_path);
use File::Basename qw(dirname basename);
use Getopt::Long qw(GetOptionsFromArray);

use annotateutil qw(get_modify_time compute_md5);

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(new extract_version compare_version);

use constant {
              ALLOW_MISSING => 0,
              LOCAL_EDIT    => 1,
              MD5           => 2,
              PREFIX        => 3,
              DEPOT         => 4,
              HASH          => 5,

              FULLNAME   => 0,
              DEPOT_PATH => 1,
              TRIMMED    => 2,
              VERSION    => 3,
};

sub usage
{
    my $exe = shift;
    #$exe = basename($exe);
    if (@_) {
        print(STDERR "ERROR:\n  $exe ", join(' ', @_), "\n");
    }
    print(STDERR<<EOF);
usage: $exe [--md5] [--prefix path] [--local-edit] [--allow-missing] depot_root
EOF
}

sub new
{
    my $class  = shift;
    my $script = shift;

    my @args = @_;
    my $use_md5;    # if set, append md5 checksum to the P4 version string
    my $prefix;
    my $depot;
    my $allow_missing;
    my $help;
    my $local_edit;

    if (!GetOptionsFromArray(\@_,
                             "--md5"           => \$use_md5,
                             '--prefix:s'      => \$prefix,
                             '--allow-missing' => \$allow_missing,
                             '--local-edit'    => \$local_edit,
                             '--help'          => \$help) ||
        $help ||
        scalar(@_) > 1
    ) {
        usage($script, @args);
        exit(defined($help) ? 0 : 1) if ($script eq $0);
        return undef;
    }
    my $depot = '';
    my $cd    = '';
    my $dots  = '...';
    if (@_) {
        $depot = $_[0];
        die("depot root '$depot' is not a directory") unless -d $depot;
        $cd   = "cd $depot ; ";
        $dots = '/...';
    }
    my $root = Cwd::abs_path($depot ? $depot : '.');
    my $len  = length($root);

    my %filehash;
    open(P4, '-|', "$cd p4 have $depot$dots") or
        die("unable to execute 'p4 have': $!");
    while (<P4>) {
        if (/^(.+?)#([0-9]+) - (.+)$/) {
            my $depot_path = $1;
            my $version    = $2 ? "#$2" : '@head';
            my $filename   = $3;
	    next unless -e $filename; # filename has ben deleted
            my $full       = Cwd::abs_path($filename);
            die("unexpected depot filename $filename")
                unless $root eq substr($filename, 0, $len);
            my $trimmed = substr($filename, $len);
            die("unexpected duplicate $trimmed") if exists($filehash{$trimmed});
            my $data = [$full, $depot_path, $trimmed, $version];
            $filehash{$trimmed}    = $data;
            $filehash{$depot_path} = $data;
            next if $full eq $trimmed;
            die("unexpected duplicate '$full' for '$filename'")
                if exists($filehash{$full});
            $filehash{$full} = $data;
        } else {
            die("unexpected p4 have line '$_'");
        }
    }
    close(P4) or die("error on close 'p4 have' pipe: $!");

    # check for local edits...
    open(EDITS, '-|', "$cd p4 opened $depot$dots") or
        die("unable to execute p4 opened: $!");
    while (<EDITS>) {
        if (
           /^(.+?)(#[0-9]+) - (edit|add|delete) (default change|change (\S+)) /)
        {
            # file is locally edited...append modify time or MD5 signature to the version ID
            my $data = $filehash{$1};
            if (!$local_edit) {
                die("$1$2 has local changes - see '--local-edit' flag");
            }
            my $fullpath = $data->[FULLNAME];
            my $version  = $1
                .
                ($use_md5 ? (' md5:' . compute_md5($fullpath)) :
                     (' edited ' . get_modify_time($fullpath)));
            $data->[VERSION] = $version;
        } else {
            die("unexpected 'p4 opened' line '$_'");
        }
    }
    close(EDITS) or die("error on clos 'p4 opened' pipe: $!");

    my $self =
        [$allow_missing, $local_edit, $use_md5, $prefix, $depot, \%filehash];
    return bless $self, $class;
}

sub extract_version
{
    my ($self, $filename) = @_;

    if (!File::Spec->file_name_is_absolute($filename) &&
        defined($self->[PREFIX])) {
        $filename = File::Spec->catfile($self->[PREFIX], $filename);
    }

    unless (-e $filename) {
        if ($self->[ALLOW_MISSING]) {
            return '';    # empty string
        }
        die("Error: $filename does not exist - perhaps you need the '--allow-missing' flag"
        );
    }
    my $pathname = abs_path($filename);

    return $self->[HASH]->{$pathname}->[VERSION]
        if (exists($self->[HASH]->{$pathname}));

    # not in P4 - just print the modify time, so we have a prayer of
    #  noticing file differences
    my $version = $self->[MD5] ? ('md5:' . compute_md5($pathname)) :
        get_modify_time($pathname);
    return $version;
}

sub compare_version
{
    my ($self, $new, $old, $filename) = @_;

    return ($old ne $new);    # for the moment, just look for exact match
}

1;
