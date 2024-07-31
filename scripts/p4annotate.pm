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
#
# p4annotate.pm
#
#   This script runs "p4 annotate" for the specified file and formats the result
#   to match the diffcov(1) 'annotate' callback specification:
#      use p4annotate;
#      my $callback = p4annotate->new([--log logfile] [--cache cache_dir] [--verify]);
#      $callback->annotate(filename);
#
#   If the '--cache' flag is used:
#     Goal is to improve runtime performance by not calling GIT if file is
#     unchanged and previous result is available.
#       - First look into the provided cache before calling GIT.
#         Hope to find that we already have data for the file we wanted.
#       - If we do call GIT - then store the result back into cache.
#     Note that this callback uses the `--version-script' (if specified)
#     to extract and compare file versions.
#     Also note that ignoring "version" errors will disable version checking
#     of cached files - and may result in out-of-sync annotated file data.
#
#   The '--verify' flag tells the tool to do some additional consistency
#   checking whe merging local edits into the annoted file.
#
#   The '--log' flag specifies a file where the tool writes various annotation-
#   related log messages.
#
#   This utility is implemented so that it can be loaded as a Perl module such
#   that the callback can be executed without incurring an additional process
#   overhead - which appears to be large and hightly variable in our compute
#   farm environment.
#
#   It can also be called directly, as
#       p4annotate [--log logfile] [--verify] filename

package p4annotate;

use strict;
use File::Basename;
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use Fcntl qw(:flock);
use annotateutil qw(get_modify_time not_in_repo call_annotate
                    resolve_cache_dir find_in_cache store_in_cache);

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(new);

use constant {
              SCRIPT  => 0,
              CACHE   => 1,
              VERIFY  => 2,
              LOGFILE => 3,
              LOG     => 4,
};

sub printlog
{
    my ($self, $msg) = @_;
    my $fh = $self->[LOG];
    return unless $fh;
    flock($fh, LOCK_EX) or die('cannot lock ' . $self->[LOGFILE] . ": $!");
    print($fh $msg);
    flock($fh, LOCK_UN) or die('cannot unlock ' . $self->[LOGFILE] . ": $!");
}

sub new
{
    my $class  = shift;
    my @args   = @_;
    my $script = shift;    # this should be 'me'
                           #other arguments are as passed...
    my $logfile;
    my $cache_dir;
    my $verify     = 0;   # if set, check that we merged local changes correctly
    my $exe        = basename($script ? $script : $0);
    my $standalone = $0 eq $script;

    if (exists($ENV{LOG_P4ANNOTATE})) {
        $logfile = $ENV{LOG_P4ANNOTATE};
    }
    my $help;
    if (!GetOptionsFromArray(\@_,
                             ("verify"  => \$verify,
                              "log=s"   => \$logfile,
                              'cache:s' => \$cache_dir,
                              'help'    => \$help)) ||
        (!$standalone && scalar(@_)) ||
        $help
    ) {
        print(STDERR ($help ? '' : ("unexpected arg: $script " . join(@_, ' '))
              ),
              "usage: $exe [--log logfile] [--cache dir] [--verify] filename\n"
        );
        exit(scalar(@_) == 0 && $help ? 0 : 1) if $standalone;
        return undef;
    }

    my @notset;
    foreach my $var ("P4USER", "P4PORT", "P4CLIENT") {
        push(@notset, $var) unless exists($ENV{$var});
    }
    if (@notset) {
        die("$exe requires environment variable" .
            (1 < scalar(@notset) ? 's' : '') . ' ' .
            join(' ', @notset) . " to be set.");
    }
    $cache_dir = resolve_cache_dir($cache_dir);

    my $self = [$exe, $cache_dir, $verify];
    bless $self, $class;
    if ($logfile) {
        open(LOGFILE, ">>", $logfile) or
            die("unable to open $logfile");

        $self->[LOG]     = \*LOGFILE;
        $self->[LOGFILE] = $logfile;
        $self->printlog("$exe " . join(" ", @args) . "\n");
    }
    return $self;
}

sub annotate
{
    my ($self, $pathname) = @_;
    defined($pathname) or die("expected filename");

    my ($cache_path, $version);
    if ($self->[CACHE]) {
        my $lines;
        ($cache_path, $version, $lines) =
            find_in_cache($self->[CACHE], $pathname);
        return (0, $lines) if defined($lines);    # cache hit
    }

    if (-e $pathname && -l $pathname) {
        $pathname = File::Spec->catfile(File::Basename::dirname($pathname),
                                        readlink($pathname));
        my @c;
        foreach my $component (split(m@/@, $pathname)) {
            next unless length($component);
            if ($component eq ".")  { next; }
            if ($component eq "..") { pop @c; next }
            push @c, $component;
        }
        $pathname = File::Spec->catfile(@c);
    }

    my $null = File::Spec->devnull();    # more portable
    my @lines;
    my $status;
    if (0 == system(
               "p4 files $pathname 2>$null|grep -qv -- '- no such file' >$null")
    ) {
        # this file is in p4..
        my $version;
        my $have = `p4 have $pathname`;
        if ($have =~ /#([0-9]+) - /) {
            $version = "#$1";
        } else {
            $version = '@head';
        }
        $self->printlog("  have $pathname:$version\n");

        my @annotated;
        # check if this file is open in the current sandbox...
        #  redirect stderr because p4 print "$path not opened on this client" if file not opened
        my $opened = `p4 opened $pathname 2>$null`;
        my %localAdd;
        my %localDelete;
        my ($localChangeList, $owner, $now);
        if ($opened =~ /edit (default change|change (\S+)) /) {
            $localChangeList = $2 ? $2 : 'default';

            $self->printlog("  local edit in CL $localChangeList\n");

            $owner = $ENV{P4USER};    # current user is responsible for changes
            $now   = get_modify_time($pathname)
                ;    # assume changes happened when file was liast modified

            # what is different in the local file vs the one we started with
            if (open(PIPE, "-|", "p4 diff $pathname")) {
                my $line = <PIPE>;    # eat first line
                die("unexpected content '$line'")
                    unless $line =~ m/^==== /;
                my ($action, $fromStart, $fromEnd, $toStart, $toEnd);
                while ($line = <PIPE>) {
                    chomp $line;
                    # Also remove CR from line-end
                    s/\015$//;
                    if ($line =~
                        m/^([0-9]+)(,([0-9]+))?([acd])([0-9]+)(,([0-9]+))?/) {
                        # change
                        $action    = $4;
                        $fromStart = $1;
                        $fromEnd   = $3 ? $3 : $1;
                        $toStart   = $5;
                        $toEnd     = $7 ? $7 : $5;
                    } elsif ($line =~ m/^> (.*)$/) {
                        $localAdd{$toStart++} = $1;
                    } elsif ($line =~ m/^< (.*)$/) {
                        $localDelete{$fromStart++} = $1;
                    } else {
                        die("unexpected line '$line'")
                            unless $line =~ m/^---$/;
                    }
                }
                close(PIPE) or die("unable to close p4 diff pipe: $!\n");
                if (0 != $?) {
                    $? & 0x7F &
                        die("p4 pipe died from signal ", ($? & 0x7F), "\n");
                    die("p4 pipe exited with error ", ($? >> 8), "\n");
                }
            } else {
                die("unable to open pipe to p4 diff $pathname");
            }
        }
        # -i: follow history across branches
        # -I: follow history across integrations
        #     (seem to be able to use -i or -I - but not both, together)
        # -u: print user name
        # -c: print changelist rather than file version ID
        # -q: quiet - suppress the 1-line header for each line
        my $annotateLineNo = 1;
        my $emitLineNo     = 1;
        if (open(HANDLE, "-|", "p4 annotate -Iucq $pathname$version")) {
            while (my $line = <HANDLE>) {

                if (exists $localDelete{$annotateLineNo++}) {
                    next;    # line was deleted .. skip it
                }
                while (exists $localAdd{$emitLineNo}) {
                    my $l = $localAdd{$emitLineNo};
                    push(@lines, [$l, $owner, undef, $now, $localChangeList]);
                    push(@annotated, $l) if ($self->[VERIFY]);
                    delete $localAdd{$emitLineNo};
                    ++$emitLineNo;
                }

                chomp $line;
                # Also remove CR from line-end
                s/\015$//;

                if ($line =~ m/([0-9]+):\s+(\S+)\s+([0-9\/]+)\s(.*)/) {
                    my $changelist = $1;
                    my $owner      = $2;
                    my $when       = $3;
                    my $text       = $4;
                    $owner =~ s/^.*<//;
                    $owner =~ s/>.*$//;
                    $when  =~ s:/:-:g;
                    $when  =~ s/$/T00:00:00-05:00/;
                    push(@lines, [$text, $owner, undef, $when, $changelist]);
                    push(@annotated, $text) if ($self->[VERIFY]);
                } else {
                    push(@lines, [$line, 'NONE', undef, 'NONE', 'NONE']);
                    push(@annotated, $line) if ($self->[VERIFY]);
                }
                ++$emitLineNo;
            }    # while (HANDLE)

            # now handle lines added at end of file
            die("lost track of lines")
                unless (0 == scalar(%localAdd) ||
                        exists($localAdd{$emitLineNo}));

            while (exists $localAdd{$emitLineNo}) {
                my $l = $localAdd{$emitLineNo};
                push(@lines, [$l, $owner, undef, $now, $localChangeList]);
                delete $localAdd{$emitLineNo};
                push(@annotated, $l) if ($self->[VERIFY]);
                ++$emitLineNo;
                die("lost track of lines")
                    unless (0 == scalar(%localAdd) ||
                            exists($localAdd{$emitLineNo}));
            }
            if ($self->[VERIFY]) {
                if (open(DEBUG, "<", $pathname)) {
                    my $lineNo = 0;
                    while (my $line = <DEBUG>) {
                        chomp($line);
                        my $a = $annotated[$lineNo];
                        die("mismatched annotation at $pathname:$lineNo: '$line' -> '$a'"
                        ) unless $line eq $a;
                        ++$lineNo;
                    }
                }
            }
            close(HANDLE) or die("unable to close p4 annotate pipe: $!\n");
            $status = $?;
        }
        if ($self->[CACHE] &&
            0 == $status) {
            store_in_cache($cache_path, $pathname, $version, \@lines);
        }
    } else {
        $self->printlog("  $pathname not in P4\n");
        not_in_repo($pathname, \@lines);
    }
    return ($status, \@lines);
}

unless (caller) {
    call_annotate("p4annotate", @ARGV);
}

1;

