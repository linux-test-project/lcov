#!/usr/bin/env perl

#   Copyright (c) MediaTek USA Inc., 2020-2024
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
# annotateutil.pm:  some common utilities used by sample 'annotate' scripts
#
package annotateutil;

use strict;
use POSIX qw(strftime);
use Cwd qw(abs_path);

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(get_modify_time compute_md5 not_in_repo
                    resolve_cache_dir find_in_cache store_in_cache
                    call_annotate call_get_version);

sub get_modify_time($)
{
    my $filename = shift;
    my @stat     = stat $filename;
    my $tz       = strftime("%z", localtime($stat[9]));
    $tz =~ s/([0-9][0-9])$/:\1/;
    return strftime("%Y-%m-%dT%H:%M:%S", localtime($stat[9])) . $tz;
}

sub not_in_repo
{
    my ($pathname, $lines) = @_;
    my $context = '';
    eval { $context = MessageContext::context(); };
    my $mtime = get_modify_time($pathname);   # when was the file last modified?
        # who does the filesystem think owns it?
    my $owner = getpwuid((stat($pathname))[4]);

    open(HANDLE, $pathname) or die("unable to open '$pathname'$context: $!");
    while (my $line = <HANDLE>) {
        chomp $line;
        # Also remove CR from line-end
        s/\015$//;

        push(@$lines, [$line, $owner, undef, $mtime, "NONE"]);
    }
    close(HANDLE) or die("unable to close '$pathname'$context");
}

sub compute_md5
{
    my $filename = shift;
    die("$filename not found") unless -e $filename;
    my $null = File::Spec->devnull();
    my $md5  = `md5sum $filename 2>$null`;
    $md5 =~ /^(\S+)/;
    return $1;
}

sub call_annotate
{
    my $cb = shift;
    my $class;
    my $filename = pop;
    eval { $class = $cb->new(@_); };
    die("$cb construction error: $@") if $@;
    my ($status, $list) = $class->annotate($filename);
    foreach my $line (@$list) {
        my ($text, $abbrev, $full, $when, $cl) = @$line;
        print("$cl|$abbrev", $full ? ";$full" : '', "|$when|$text\n");
    }
    exit $status;
}

sub call_get_version
{
    my $cb = shift;
    my $class;
    my $filename = pop;
    eval { $class = $cb->new(@_); };
    die("$cb construction error: $@") if $@;
    my $v = $class->extract_version($filename);
    print($v, "\n");
    exit 0;
}

sub resolve_cache_dir
{
    my $cache_dir = shift;
    if ($cache_dir) {
        lcovutil::ignorable_warning($lcovutil::ERROR_USAGE,
            'It is unwise to use an --annotate-script callback with --cache-dir without a --version-script to verify version match.'
        ) unless $lcovutil::versionCallback;
        if (-e $cache_dir) {
            die("cache '$cache_dir' not writable directory")
                unless -d $cache_dir && -w $cache_dir;
        } else {
            File::Path::make_path($cache_dir) or
                die("unable to create '$cache_dir': $!");
        }
        $cache_dir = abs_path($cache_dir);
    }
    return $cache_dir;
}

sub find_in_cache
{
    my ($cache_dir, $filename) = @_;

    my ($cachepath, $version);
    my $cachepath = File::Spec->catfile($cache_dir,
                                        File::Spec->file_name_is_absolute(
                                                                    $filename) ?
                                            substr($filename, 1) :
                                            $filename);
    if (-f $cachepath) {
        # matching version?
        my ($cache_version, $lines);
        eval {
            my $data = Storable::retrieve($cachepath);
            if (defined($data)) {
                ($cache_version, $lines) = @$data;
                $version = lcovutil::extractFileVersion($filename);
            }
        };
        if ($@) {
            lcovutil::ignorable_error($lcovutil::ERROR_CORRUPT,
             "unable to deserialize $cachepath for $filename annotation: $@\n");
        }
        if (defined($lines)) {
            # pass 'silent' to version check so we don't get error on mismatch
            return (0, $version, $lines)
                if (!$lcovutil::versionCallback ||
                    lcovutil::is_ignored($lcovutil::ERROR_VERSION) ||
                    !(defined($version) != defined($cache_version))
                    ||
                    lcovutil::checkVersionMatch(
                        $filename, $version, $cache_version, "annotate-cache", 1
                    ));
            lcovutil::info(1, "annotate: cache version check failed\n");
        }
    }
    return ($cachepath, $version);
}

sub store_in_cache
{
    my ($cache_path, $filename, $version, $lines) = @_;

    $version = lcovutil::extractFileVersion($filename)
        unless $version;
    my $parent = File::Basename::dirname($cache_path);
    unless (-d $parent) {
        File::Path::make_path($parent) or
            die("unable to create cache directory $parent: $!");
    }
    Storable::store([$version, $lines], $cache_path) or
        die("unable to store $cache_path");
}

1;
