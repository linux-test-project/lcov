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

use strict;
use warnings;

package annotateutil;

use POSIX qw(strftime);
use Digest::MD5;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(get_modify_time compute_md5 shell_quote
                    call_annotate call_get_version);

# shell_quote($string)
#
#   Return $string wrapped so that a POSIX shell passes it through as one
#   word, whatever it contains:  use this on every path interpolated into a
#   command handed to a shell.  Single quotes protect everything except a
#   single quote, which has to be closed, escaped, and reopened.
#
#   Duplicate of 'lcovutil::shell_quote':  the callbacks are runnable standalone
#   e.g., for testing
#
sub shell_quote($)
{
    my $str = shift;
    $str = '' unless defined($str);
    $str =~ s/'/'\\''/g;
    return "'$str'";
}

sub get_modify_time($)
{
    my $filename = shift;
    my @stat     = stat $filename;
    die("stat failed for '$filename': $!") unless @stat;
    my $tz = strftime("%z", localtime($stat[9]));
    $tz =~ s/([0-9][0-9])$/:$1/;
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

    # 3-arg open:  a filename which begins with '>', '<' or '|' is a filename,
    #   not a mode - and 2-arg open would have obeyed it
    open(HANDLE, '<', $pathname) or
        die("unable to open '$pathname'$context: $!");
    while (my $line = <HANDLE>) {
        chomp $line;
        # Also remove CR from line-end
        $line =~ s/\015$//;

        push(@$lines, [$line, $owner, undef, $mtime, "NONE"]);
    }
    close(HANDLE) or die("unable to close '$pathname'$context: $!");
}

sub compute_md5
{
    my $filename = shift;
    die("$filename not found") unless -e $filename;
    # Hash in-process rather than forking md5sum.  md5sum prints a lowercase
    # hex digest; md5_hex produces the identical string, so the version-string
    # output is unchanged.
    open(my $fh, '<', $filename) or die("unable to open '$filename': $!");
    binmode($fh);
    my $ctx = Digest::MD5->new();
    $ctx->addfile($fh);
    close($fh);
    return $ctx->hexdigest();
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
    # '$status' is the wait status of the tool the callback ran, not an exit
    #   code:  'exit' keeps only the low 8 bits, so a child which exited 1
    #   (wait status 256) used to leave this script exiting 0 - i.e. reporting
    #   success for a failed annotation.  A child killed by a signal has a zero
    #   exit field, so report 1 for those rather than 0.
    exit($status ? (($status >> 8) || 1) : 0);
}

sub call_get_version
{
    my $cb = shift;
    my $class;
    my $filename = pop;
    eval { $class = $cb->new(@_); };
    die("$cb construction error: $@") if $@;
    my $v = $class->extract_version($filename);
    # a file need not have a version - print the empty line the consumer
    #   expects, rather than warning about an uninitialized value
    print(defined($v) ? $v : '', "\n");
    exit 0;
}

package AnnotateBase;

use Cwd qw(abs_path);
use Fcntl qw(:flock);

use constant {
              SCRIPT            => 0,
              CACHE             => 1,
              LOG               => 2,
              LOGFILE           => 3,
              VERIFY            => 4,
              IGNORE_WHITESPACE => 5,
};

sub new
{
    my $class  = shift;
    my $script = shift;
    my ($cache, $logfile, $verify, $ignoreWhitespace) = @_;

    my $self = [$script, resolve_cache_dir($cache),
                undef, $logfile,
                $verify, $ignoreWhitespace
    ];

    if ($ignoreWhitespace && !$verify) {
        lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
            "$script:  '--ignore-whitespace' has no effect without '--verify'");
    }
    bless $self, $class;

    if ($logfile) {
        open($self->[LOG], ">>", $logfile) or
            die("unable to open $logfile");
        $self->printlog(
                    "$script " . join(" ", map({ $_ // '<undef>' } @_)) . "\n");
    }
    return $self;
}

sub printlog
{
    my ($self, $msg) = @_;
    my $fh = $self->[LOG];
    return unless $fh;
    flock($fh, Fcntl::LOCK_EX) or
        die('cannot lock ' . $self->[LOGFILE] . ": $!");
    print($fh $msg);
    flock($fh, Fcntl::LOCK_UN) or
        die('cannot unlock ' . $self->[LOGFILE] . ": $!");
}

sub resolve_cache_dir
{
    my $cache_dir = shift;
    if ($cache_dir) {
        lcovutil::ignorable_warning($lcovutil::ERROR_USAGE,
            'It is unwise to use an --annotate-script callback with --cache-dir without a --version-script to verify version match.'
        ) unless $lcovutil::versionCallback;
        if (-e $cache_dir) {
            die("cache '$cache_dir' not writeable directory")
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
    my ($self, $filename) = @_;
    my $cache_dir = $self->[CACHE];
    my $version;
    my $cachepath =
        File::Spec->catfile($cache_dir,
                            File::Spec->file_name_is_absolute($filename) ?
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
                $self->printlog("cache hit: $filename:" .
                                ($cache_version // 'undef') . "\n");
            }
        };
        if ($@) {
            lcovutil::ignorable_error($lcovutil::ERROR_CORRUPT,
             "unable to deserialize $cachepath for $filename annotation: $@\n");
        }
        if (defined($lines)) {
            # pass 'silent' to version check so we don't get error on mismatch
            # 'both undefined', not 'both the same definedness':  when both are
            #   defined there is nothing to short-circuit - that is exactly the
            #   case 'checkVersionMatch' exists to decide.  The old test took
            #   any cache entry which recorded a version, whatever version it
            #   was, so a stale annotation was reused for an edited file.
            my $noVersion = !defined($version) && !defined($cache_version);
            return (0, $version, $lines)
                if (!$lcovutil::versionCallback                    ||
                    lcovutil::is_ignored($lcovutil::ERROR_VERSION) ||
                    $noVersion                                     ||
                    lcovutil::checkVersionMatch(
                        $filename, $version, $cache_version, "annotate-cache", 1
                    ));
            lcovutil::info(1, "annotate: cache version check failed\n");
            # the mismatch may be 'the file has no version now' - the log
            #   message must not itself warn about the undef which said so
            $self->printlog(
                         '  version mismatch: ' . ($version // 'undef') . "\n");
        }
    }
    return ($cachepath, $version);
}

sub store_in_cache
{
    my ($self, $cache_path, $filename, $version, $lines) = @_;
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

sub _collapse_whitespace
{
    # Leading and trailing whitespace removed, and each run of whitespace
    #   within the line reduced to one space.  Used only to decide whether two
    #   lines which are not equal differ in whitespace alone.
    my $text = shift;
    $text =~ s/^\s+//;
    $text =~ s/\s+$//;
    $text =~ s/\s+/ /g;
    return $text;
}

sub verify_annotation
{
    my ($self, $filepath, $lines) = @_;
    open(my $debug_fh, "<", $filepath) or
        die("unable to read $filepath: $!");
    my $lineNo = 0;
    while (my $line = <$debug_fh>) {
        chomp($line);
        die('mismatched annotation: local line ' .
            ($lineNo + 1) .
            " does not exist in annotated data")
            if $lineNo > $#$lines;
        my $a    = $lines->[$lineNo]->[0];
        my $same = $line eq $a;
        if (!$same && $self->[IGNORE_WHITESPACE]) {
            # The version in the repo and the version on disk may have been
            #   reindented, had trailing whitespace stripped, or had tabs
            #   expanded - none of which changes the code the line contains.
            #   Compare again with whitespace normalized, and complain only if
            #   they still differ.
            $same = _collapse_whitespace($line) eq _collapse_whitespace($a);
        }
        lcovutil::ignorable_error($lcovutil::ERROR_ANNOTATE_SCRIPT,
                                  "mismatched annotation at $filepath:" .
                                      ($lineNo + 1) .
                                      ": '$line' -> '$a'") unless $same;
        ++$lineNo;
    }
    die('mismatched annotation: local file does not contain annotated line ' .
        ($lineNo + 1))
        if $lineNo <= $#$lines;
}

sub annotate
{
    my ($self, $pathname) = @_;
    defined($pathname) or die("expected filename");

    my ($cache_path, $version, $lines, $status);
    if ($self->[CACHE]) {
        ($cache_path, $version, $lines) = $self->find_in_cache($pathname);
        return (0, $lines) if defined($lines);    # cache hit
    }

    my $rtn = $self->annotate_callback($pathname, $version);
    if (!defined($rtn)) {
        # did not find the file in the repo
        $self->printlog("  $pathname not in repo\n");
        my @lines;
        annotateutil::not_in_repo($pathname, \@lines);
        return (0, \@lines);
    }
    ($status, $lines, $version) = @$rtn;
    if ($self->[VERIFY]) {
        $self->verify_annotation($pathname, $lines);
    }
    if ($self->[CACHE] &&
        0 == $status) {
        $self->store_in_cache($cache_path, $pathname, $version, $lines);
    }
    return ($status, $lines);
}

1;
