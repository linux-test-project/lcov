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
# gitblame [--p4] [--prefix path] [--abbrev regexp] [--cache dir] [--verify] \
#          [--log logfile] [domain] pathname
#
#   This script runs "git blame" for the specified file and formats the result
#   to match the diffcov(1) age/ownership annotation specification.
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
#   If the '--p4' flag is used:
#     we assume that the GIT repo is cloned from Perforce - and look for
#     the line in the generated commit log message which tells us the perforce
#     changelist ID that we actually want.
#
#   The '--verify' flag tells the tool to do some additional consistency
#   checking when merging local edits into the annotated file.
#
#   The '--log' flag specifies a file where the tool writes various annotation-
#   related log messages - primarily useful for debugging environment issues.
#
#   The --abbrev argument enables you to specify one or more regexp patterns
#     which are used to compute the user name abbreviation that are applied.
#
#   If specified, 'path' is prependied to 'pathname' (as 'path/pathname')
#     before processing.
#
#   If passed a domain name (or domain regexp):
#     strip that domain from the author's address, and treat all users outside
#     the matching domain as "External".

package gitblame;

use strict;
use annotateutil;

use File::Basename qw(dirname basename);
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);
use Cwd qw(abs_path);

use base 'AnnotateBase';

use constant {
              P4     => 5,
              ABBREV => 6,
              PREFIX => 7,
};

sub new
{
    my $class  = shift;
    my $script = shift;

    my $mapP4;
    my $cache_dir;
    my $prefix;
    my @abbrev;
    my $exe        = basename($script ? $script : $0);
    my $standalone = $script eq $0;
    my $help;
    my $verify;
    my $logfile;

    if (!GetOptionsFromArray(\@_,
                             ("p4"       => \$mapP4,
                              "prefix:s" => \$prefix,
                              'abbrev:s' => \@abbrev,
                              'cache:s'  => \$cache_dir,
                              'verify'   => \$verify,
                              'log:s'    => \$logfile,
                              'help'     => \$help)) ||
        (scalar(@_) >= 2) ||
        $help
    ) {
        print(STDERR
                "usage: $exe [--p4] [--abbrev regexp]* [--cache dir] [--verify] [--log logfile] [domain] pathname\n"
        );
        # exit 0 only when --help was the sole argument; any extra args means error
        exit($help && 0 == scalar(@_) ? 0 : 1) if $standalone;
        return undef;
    }
    my $internal_domain = shift;
    if ($internal_domain) {
        push(@abbrev, 's/^([^@]+)\@' . $internal_domain . '$/$1/');
        push(@abbrev, 's/^([^@]+)\@.+$/External/');
        # else leave domain in place
    }

    my $self = $class->SUPER::new($exe, $cache_dir, $logfile, $verify);
    push(@$self, $mapP4, \@abbrev, $prefix);
    return $self;
}

sub annotate_callback
{
    my ($self, $file, $version) = @_;

    my $pathname = File::Spec->catfile(@{$self->[PREFIX]}, $file);
    # if running as module, then context might be available
    my $context = '';
    eval { $context = MessageContext::context(); };
    unless (defined($pathname) &&
            (-f $pathname || -l $pathname) &&
            -r $pathname) {
        $context = ':' . $context if $context;
        die($self->[AnnotateBase::SCRIPT] .
            $context .
            ' expected readable file, found \'' .
            (defined($pathname) ? $pathname : '<undef>') . "'");
    }

    # set working directory to account for nested repos and submodules
    my $dir      = dirname($pathname);
    my $basename = basename($pathname);
    -d $dir or die("no such directory '$dir'$context");

    my $null = File::Spec->devnull();
    unless (
          0 == system("cd $dir ; git rev-parse --show-toplevel >$null 2>&1") &&
          0 ==
          system("cd $dir ; git ls-files --error-unmatch $basename >$null 2>&1")
          &&
          open(HANDLE, "-|", "cd $dir ; git blame -e $basename 2> /dev/null")) {

        # fallthrough from error conditions
        return undef;    # get from filesystem
    }

    my %changelists;
    my @lines;
    my $matched;    # matched a tracked pathname
    my %abbrev;     # user name abbreviations
    while (my $line = <HANDLE>) {
        chomp $line;
        # Also remove CR from line-end
        $line =~ s/\015$//;

        if ($line =~
            m/^(\S+)[^(]+\(<([^>]*)>\s+([-0-9]+\s+[0-9:]+\s+[-+0-9]+)\s+([0-9]+)\) (.*)$/
        ) {
            my $commit = $1;
            my $owner  = $2;    # apparently, this can be empty
            my $when   = $3;
            my $text   = $5;

            # found empty name in .../clang/include/AST/StmtOpenMP.h
            $owner = 'unknown@nowhere.com' unless $owner;

            if ($self->[P4]) {
                if (!exists($changelists{$commit})) {
                    open(GITLOG, '-|', "cd $dir ; git show -s $commit") or
                        die(
                         "unable to execute 'git show -s $commit'$context: $!");
                    while (my $l = <GITLOG>) {
                        # p4sync puts special comment in commit log.
                        #  pull the CL out of that.
                        if ($l =~ /git-p4:.+change = ([0-9]+)/) {
                            $changelists{$commit} = $1;
                            $commit = $1;
                            last;
                        }
                    }
                    close(GITLOG) or die("unable to close$context");
                } else {
                    $commit = $changelists{$commit};
                }
            }
            # line owner filtering to canonical form
            $owner =~ s/ dot /./g;
            $owner =~ s/ at /\@/;
            my $fullname = $owner;

            if (exists($abbrev{$fullname})) {
                $owner = $abbrev{$fullname};
            } else {
                # compute only once...
                foreach my $re (@{$self->[ABBREV]}) {
                    ## strip domain part for internal users...
                    eval '$owner =~ ' . $re . ';';
                    die("invalid domain pattern '$re'$context: $@")
                        if $@;
                }
                $abbrev{$fullname} = $owner;
            }
            # Convert Git date/time to diffcov canonical format
            # replace space between date and time with 'T'
            $when =~ s/\s/T/;
            # remove space between time and zone offset
            $when =~ s/\s//;
            # insert ':' between hour and minute digits of zone offset
            $when =~ s/([0-9][0-9])$/:$1/;
            # ';' is not a legal character in an email address -
            #  so use it as a delimiter
            push(@lines, [$text, $owner, $fullname, $when, $commit]);
            # expect all lines to either match the git blame regexp
            # or none of them to match
            die("$basename has both matching and not matching lines$context")
                if defined($matched) && !$matched;
            $matched = 1;
        } else {
            push(@lines, [$line, "NONE", undef, "NONE", "NONE"]);
            # expect all lines to either match the git blame regexp
            # or none of them to match
            die("$basename has both not matching and matching lines$context")
                if defined($matched) && $matched;
            $matched = 0;
        }
    }
    close(HANDLE) or
        die("unable to close git blame pipe$context: $!\n");
    my $status = $?;
    #if (0 != $?) {
    #    $? & 0x7F &
    #        die("git blame died from signal ", ($? & 0x7F), "\n");
    #    die("git blame exited with error ", ($? >> 8), "\n");
    #}
    return [$status, \@lines, $version];
}

1;
