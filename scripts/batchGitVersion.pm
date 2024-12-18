#!/usr/bin/env perl
#   Copyright (c) MediaTek USA Inc., 2023
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
#   This implementation creates an initial database to hold the version stamps
#   for all files in the repo - then simply queries that DB during
#   execution.  See 'usage' for details:#
#     .../batchGitVersion.pm --help
#
#   This is a sample script which uses git commands to determine
#   the version of the filename parameter.
#   Version information (if present) is used during ".info" file merging
#   to verify that the data the user is attempting to merge is for the same
#   source code/same version.
#   If the version is not the same - then line numbers, etc. may be different
#   and some very strange errors may occur.

package batchGitVersion;

use strict;
use Getopt::Long qw(GetOptionsFromArray);
use File::Spec;
use File::Basename qw(dirname basename);
use Cwd qw/getcwd/;

use FindBin;
use lib "$FindBin::RealBin";
use annotateutil qw(get_modify_time not_in_repo compute_md5 call_get_version);

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(new extract_version compare_version usage);

# should probably use "BLOB" as the token - so anyone we call can know that this
#  is a blob sha - and can look up the file sha, if desired
my $shaToken = 'BLOB';

sub usage
{
    my ($script, $help) = @_;
    $script = $0 unless defined $script;
    my $exe = basename $script;
    print(STDERR<<EOF);
usage: $exe->new([--md5] [--allow-missing [--repo repo] \\
          [--prepend path] [--prefix dir]* \\
          [--token string] \\			  
          [-v | --verbose]*) 
       $exe->extract_version(pathname)
       $exe->compare(old_version, new_version, pathname)
EOF

    if ($help) {
        print(STDERR<<EOF);

  The 'new' callback queries the git repo specified by 'repo'
  (or \$CWD, if --repo is not supplied) and holds the data.
     \$ $exe->new(...) # to initialize git_data

     --md5          : return MD5 signature if pathname not found in repo
     --allow-missing: if set:  return empty string if pathname not found
                      otherwise: die (fatal error)
     --repo dir     : where to find the git repo
     --prepend path : prepend path to names found in repo before storing
                      e.g., if path is 'x/y' and object 'dir/file' is found
                      in the repo, then 'x/y/dir/file' is stored.
     --prefix dir   : add dir to the list of directories to search, to find
                      pathname.
     --token string : use string as the blob sha token in the version string.
                      default value is 'BLOB' - so application can
		      distinguish between SHA types - say, to complare
		      to compare a BLOB SHA to a file SHA.
		      For backward compatibility with earlier versions of
		      this script, use '--token SHA'.
     -v | --verbose : increase verbosity

  Setting the verbosity flag causes the script to print some (hopefully useful)
  debug information - so you can see why your use is not working the way you
  might have expected.

  The second call queries DB to find 'pathname'.
    - 'pathname' may be be a file name which is found in the git repo, but
      with some prefix prepended.  For example:
         pathname: /build/directory/path/repo/dir/file
         filename: repo/dir/file
    - if script is called as
       \$ $exe --prefix /build/directory/path my_git_data \
           /build/directory/path/repo/dir/file
       $shaToken git_sha_string
    - zero or more --prefix arguments can be specified.
      $exe will look at each, in the order specified.
    - if pathname is not found in the DB:
       - if pathname does not resolve to a file:
            - '' (empty string) if '--allow-missing' flag used,
            - else, error
       - if '--md5' is passed: return MD5 checksum of the file
       - else return file creation timestamp
  NOTE: $exe DOES NOT CHECK FOR LOCAL CHANGES that are not checked in
        to your git repo - so versions will compare as identical even
        if the local file has been edited.
        Please commit your changes before running $exe.

  The third call passes two version strings which are expected to be the same.
  Under normal circumstances, the version strings will have been returned by
  some call(s) to $exe.
  Exit status is 0 when files match, 1 otherwise.

  To diagnose version mismatches using these SHAs:
    - You can git diff them to see how they are different the same way you
      'git diff' commit shas (except you do not to specify a file)
    - You can 'git log commit1..commit2' because you should also store
      the overall sha of these two points (again if the scripting just
      wants to know the delta).
  Again note: the normal git way of asking these types of questions is to
  just store a single commit shas, unlike perforce/svn that exactly
  represents the current files, 'git diff --name-status' can VERY quickly
  tell you what has changed.
  There is also a mechanism for determining which commits contain which
  blobs given a file and a starting point.  Again it is just easier
  to use 'git log commit1..commit2'
EOF
    } else {
        print(STDERR "\n  see '$exe --help' for more information\n");
    }
}

use constant {
              DB      => 0,
              PREFIX  => 1,
              MD5     => 2,
              MISSING => 3,
              VERBOSE => 4,
};

sub new
{
    my $class       = shift;
    my $script      = shift;
    my $stand_alone = $0 eq $script;
    # script should be me...
    my $use_md5;
    my $allow_missing;
    my $repo;
    my $prepend;
    my @prefix;
    my $help;
    my $verbose = 0;

    if (!GetOptionsFromArray(\@_,
                             ("md5"           => \$use_md5,
                              'prefix:s'      => \@prefix,
                              'repo:s'        => \$repo,
                              'allow-missing' => \$allow_missing,
                              'prepend:s'     => \$prepend,
                              "verbose|v+"    => \$verbose,
                              'token:s'       => \$shaToken,
                              'help'          => \$help,)) ||
        ($stand_alone && 0 != scalar(@_)) ||
        $help
    ) {
        usage($script, $help);
        exit(defined($help) && 0 == scalar(@_) ? 0 : 1) if $stand_alone;
        return undef;
    }
    my %db;
    my $cd = $repo ? "cd $repo ;" : '';
    open(GIT, '-|', "$cd git ls-tree -r --full-tree HEAD") or
        die("unable to execute git: $!");
    my @prepend;
    if ($prepend) {
        push(@prepend, $prepend);
    }
    my $errLeader = "unexpected git ls-tree entry:\n  ";
    my %submodule;
    while (<GIT>) {
        if (/^\d+\s+blob\s+(\S+)\s+(.+)$/) {
            # line format:  mode blob sha path
            $db{File::Spec->catfile(@prepend, $2)} = $1;
        } elsif (/^\d+\s+commit\s+(\S+)\s+(\S+)$/) {
            # line format:  mode commit sha path
            die("duplicate submodule etnry for $2") if exists($submodule{$2});
            $submodule{$2} = $1;
        } else {
            print(STDERR "$errLeader$_");
            $errLeader = '  ';
        }
    }
    close(GIT) or die("error on close $repo pipe: $!");
    # now look for submodules
    open(GIT, '-|',
      "$cd git submodule foreach 'git ls-tree -r --full-tree HEAD ; echo done'")
        or
        die("unable to execute git: $!");
    my $current;
    my @stack;
    my $number    = 2;
    my $countdown = $number * $verbose;
    my $prefix    = '';
    while (<GIT>) {
        if (/^\d+\s+blob\s+(\S+)\s+(.+)$/) {
            # line format:  mode blob sha path
            die("unknown current submodule") unless defined($current);
            $db{File::Spec->catfile(@prepend, $current, $2)} = $1;
            if ($countdown) {
                --$countdown;
                print("${prefix}storing " .
                      File::Spec->catfile(@prepend, $current, $2) .
                      " => $1\n");
                print("$prefix ...\n") unless $countdown;
            }
        } elsif (/^\d+\s+commit(\S+)\s+(\s+)$/) {
            # line format:  mode commit sha path
            my $s = File::Spec->catfile(@prepend, $current, $2);
            die("duplicate submodule etnry for $s") if exists($submodule{$s});
            $submodule{$s} = $1;
        } elsif (/^Entering '([^']+)'$/) {
            $current = File::Spec->catfile(@stack, $1);
            push(@stack, $1);
            die("found unexpected submodule '$current'")
                unless exists($submodule{$current});
            $countdown = $number * $verbose;
            if ($countdown) {
                print("${prefix}enter submodule $current\n");
                $prefix .= '  ';
            }
        } elsif (/^done$/) {
            die("empty stack") unless @stack;
            pop(@stack);
            if (@stack) {
                $current = File::Spec->catfile(@stack);
            } else {
                $current = undef;
            }
            if ($verbose) {
                print("${prefix}exit submodule $current\n");
                $prefix = substr($prefix, 2);
            }
        } else {
            print(STDERR "$errLeader$_");
            $errLeader = '  ';
        }
    }
    close(GIT) or die("error on close submodule pipe: $!");

    $repo = getcwd()     unless $repo;
    push(@prefix, $repo) unless grep(/^$repo/, @prefix);

    # @todo enhancement: could look for local edits and store
    #   them into the DB here
    foreach my $p (@prefix) {
        # want all the prefixes to end with dir separator so we can
        # just concat them
        $p .= '/' unless substr($p, -1) eq '/';
    }

    my $self = [\%db, \@prefix, $use_md5, $allow_missing, $verbose];
    return bless $self, $class;
}

sub extract_version
{
    my ($self, $file) = @_;
    my $db      = $self->[DB];
    my $prefix  = $self->[PREFIX];
    my $verbose = $self->[VERBOSE];
    print("extract_version($file)\n") if $verbose;
    if (@$prefix) {
        # check we we can strip the prefix off the filename - to find it in the DB
        foreach my $p (@$prefix) {
            print("  check prefix $p  ..\n") if $verbose;
            if (0 == index($file, $p)) {
                print("  .. match\n") if $verbose;
                my $tail = substr($file, length($p));
                if (exists($db->{$tail})) {
                    print("  .. found\n") if $verbose;
                    return $shaToken . ' ' . $db->{$tail};
                }
            }
        }
    }

    if (exists($db->{$file})) {
        print("  .. found\n") if $verbose;
        return $shaToken . ' ' . $db->{$file};
    }

    unless (-e $file) {
        if ($self->[MISSING]) {
            return '';    # empty string
        }
        die("Error: $file does not exist - perhaps you need the '--allow-missing' flag"
        );
    }
    my $version = get_modify_time($file);
    $version .= ' md5:' . compute_md5($file)
        if ($self->[MD5]);
    return $version;
}

sub compare_version
{
    my ($self, $new, $old, $file) = @_;

    if ($self->[MD5] &&
        $old !~ /^$shaToken/ &&
        $old =~ / md5:(.+)$/) {
        my $o = $1;
        if ($new =~ / md5:(.+)$/) {
            return ($o ne $1);
        }
        # otherwise:  'new' was not an MD5 signature - so fall through to exact match
    }
    return ($old ne $new);    # just look for exact match
}

unless (caller) {
    call_get_version("batchGitVersion", $0, @ARGV);
}

1;
