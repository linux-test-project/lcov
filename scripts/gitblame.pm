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
#          [-b|--ignore-whitespace] [--log logfile] [domain] pathname
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
#   The '-b' (or '--ignore-whitespace') flag applies only to '--verify':  a line
#   whose only difference from the local file is whitespace - reindentation,
#   trailing blanks, tabs expanded - is not reported as a mismatch.
#
#   The '--log' flag specifies a file where the tool writes various annotation-
#   related log messages - primarily useful for debugging environment issues.
#
#   The --abbrev argument enables you to specify one or more regexp patterns
#     which are used to compute the user name abbreviation that are applied.
#
#   If specified, 'path' is prepended to 'pathname' (as 'path/pathname')
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
              P4          => 6,
              ABBREV      => 7,
              PREFIX      => 8,
              CHANGELISTS => 9,
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
    my $ignoreWhitespace;
    my $logfile;

    if (!GetOptionsFromArray(\@_,
                             ("p4"                  => \$mapP4,
                              "prefix:s"            => \$prefix,
                              'abbrev:s'            => \@abbrev,
                              'cache:s'             => \$cache_dir,
                              'verify'              => \$verify,
                              'b|ignore-whitespace' => \$ignoreWhitespace,
                              'log:s'               => \$logfile,
                              'help'                => \$help)) ||
        (scalar(@_) >= 2) ||
        $help
    ) {
        print(STDERR
                "usage: $exe [--p4] [--abbrev regexp]* [--cache dir] [--verify] [-b|--ignore-whitespace] [--log logfile] [domain] pathname\n"
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

    # Compile each '--abbrev' substitution exactly once, rather than
    # string-eval'ing it again for every distinct author name in every file:
    my @abbrevSubs;
    foreach my $re (@abbrev) {
        my $body =
            'sub { my $owner = shift; $owner =~ ' . $re . '; return $owner; }';
        my $sub = eval $body;
        die("invalid domain pattern '$re': " .
            ($@ ? $@ : "not an expression\n"))
            unless !$@ && 'CODE' eq ref($sub);
        push(@abbrevSubs, $sub);
    }

    my $self = $class->SUPER::new($exe, $cache_dir, $logfile, $verify,
                                  $ignoreWhitespace);
    # The commit->changelist map is keyed by git commit SHA, which is content-
    # addressed and globally unique, so its git-p4 CL mapping is the same no
    # matter which file references it.  Keep it on $self so the (forking)
    # 'git show -s <commit>' lookup runs at most once per commit across the
    # whole annotation run instead of once per (commit, file) pair.
    push(@$self, $mapP4, \@abbrevSubs, $prefix, {});
    return $self;
}

sub annotate_callback
{
    my ($self, $file, $version) = @_;

    # '--prefix' is a single string, not a list.
    # Prepend it the same way 'gitversion.pm' does - only to a relative name.
    my $pathname = $file;
    if (defined($pathname) &&
        defined($self->[PREFIX]) &&
        !File::Spec->file_name_is_absolute($pathname)) {
        $pathname = File::Spec->catfile($self->[PREFIX], $pathname);
    }
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

    my $null     = File::Spec->devnull();
    my $gitDir   = 'git -C ' . annotateutil::shell_quote($dir);
    my $quotedBn = annotateutil::shell_quote($basename);
    unless (0 == system("$gitDir rev-parse --show-toplevel >$null 2>&1") &&
          0 ==
          system("$gitDir ls-files --error-unmatch -- $quotedBn >$null 2>&1") &&
          open(HANDLE, "-|", "$gitDir blame -e -- $quotedBn 2>$null")) {

        # fallthrough from error conditions
        return undef;    # get from filesystem
    }

    # commit->changelist map shared across every file in this run (see new())
    my $changelists = $self->[CHANGELISTS];
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
                if (!exists($changelists->{$commit})) {
                    my $sha = $commit;
                    open(GITLOG,
                         '-|',
                         "$gitDir show -s " . annotateutil::shell_quote($commit)
                        ) or
                        die(
                         "unable to execute 'git show -s $commit'$context: $!");
                    while (my $l = <GITLOG>) {
                        # p4sync puts special comment in commit log.
                        #  pull the CL out of that.
                        if ($l =~ /git-p4:.+change = ([0-9]+)/) {
                            $commit = $1;
                            last;
                        }
                    }
                    # say which command failed, and why
                    close(GITLOG) or
                        die("'git show -s $sha' failed$context: " .
                            (0 == $? ? $! : 'exit status ' . ($? >> 8)) . "\n");
                    # Remember the resolved CL (or the SHA itself if no git-p4
                    # marker was found) so repeat commits skip the fork.
                    $changelists->{$sha} = $commit;
                } else {
                    $commit = $changelists->{$commit};
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
                foreach my $abbrev (@{$self->[ABBREV]}) {
                    ## strip domain part for internal users...
                    #  (pattern compiled once, in 'new')
                    $owner = $abbrev->($owner);
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
    # 'close' on a pipe returns false both for an I/O error - which '$!'
    #   describes - and for a child which exited non-zero, which it does not:
    #   the wait status is in '$?'.  Only the first case is a reason to die
    #   here; a failed 'git blame' is reported by returning its non-zero
    #   status, which keeps the (possibly partial) result out of the annotate
    #   cache and is passed on to the caller.
    my $closed = close(HANDLE);
    my $status = $?;
    die("unable to close git blame pipe$context: $!\n")
        if !$closed && 0 == $status;
    return [$status, \@lines, $version];
}

1;
