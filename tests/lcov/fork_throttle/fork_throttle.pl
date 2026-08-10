#!/usr/bin/env perl
#
# The memory throttle in 'lcovutil::ForkManager'.
#
# The throttle predicts what the child it is about to fork will cost from the
#   weight of the unit that child is going to run and the bytes per unit of
#   weight the children which have already finished really used - a
#   records-based predictor.
#
# Reaching that decision through a tool is not portable:  a '--memory' small
#   enough to make the fork-time decision fire is also small enough for the
#   up-front planners in 'AggregateTraces' to have already dropped
#   '--parallel' to 1 - and then nothing forks at all - while a '--memory'
#   large enough to survive them makes the decision depend on how big perl
#   happens to be on the machine.  So drive the manager directly:  the clients'
#   own 'unitWeight' callbacks are exercised by every parallel test in the
#   suite, and what is left to pin down here is the framework's arithmetic.

use strict;
use warnings;
use FindBin;
use File::Path qw(rmtree);

use lib "$FindBin::RealBin/../../../lib";    # build dir testcase
use lib (exists($ENV{LCOV_HOME}) ? $ENV{LCOV_HOME} : "../../../lib") .
    '/lib/lcov';
use lcovutil;

lcovutil::parseOptions({}, {});

my $tempdir = 'fork_throttle.tmp';
rmtree($tempdir) if -d $tempdir;
mkdir($tempdir) or die("cannot create $tempdir: $!");

my @failures;

sub check($$)
{
    my ($what, $ok) = @_;
    print(($ok ? 'passed' : 'FAILED') . ": $what\n");
    push(@failures, $what) unless $ok;
}

# What the child adds to itself, per unit of weight.  Big enough that the
#   child's peak is unambiguously above the size we were when we forked it -
#   which is the condition '_learn' insists on before it believes a
#   measurement.
my $BYTES_PER_UNIT = 1024 * 1024;

# 'info(1, ..)' is where the throttle says why it is waiting;  take the lines
#   rather than the console, so that the assertions can look at them.
my @messages;
lcovutil::set_info_callback(sub {
    my $fmt = shift;
    push(@messages, sprintf($fmt, @_));
});
$lcovutil::verbose = 1;

# Room for four children, and a ceiling which one child already breaks:  then
#   every decision from the third fork on is over the limit, and the run
#   proceeds two children at a time.  (The first two forks are not throttled:
#   the manager will not wait for a ceiling it cannot meet, so it always allows
#   a second child - see 'throttle'.)
$lcovutil::maxParallelism = 4;
$lcovutil::maxMemory      = 1;

sub run_manager
{
    my ($weights, %extra) = @_;

    my @queue = (0 .. $#$weights);
    my %merged;
    my $mgr =
        lcovutil::ForkManager->new(
        tempDir   => $tempdir,
        operation => 'throttle test',
        phase     => 'throttle',
        prefix    => 'throttle_child',
        next      => sub {
            return () unless @queue;
            my $unit = shift(@queue);
            return ($unit, $unit);
        },
        child => sub {
            my ($unit, $id) = @_;
            # grow by an amount this unit's weight predicts, so that the
            #   parent can learn a rate from it
            my $ballast = 'x' x ($weights->[$unit] * $BYTES_PER_UNIT);
            return ([$unit, length($ballast)], 0);
        },
        merge => sub {
            my ($unit, $id, $payload) = @_;
            $merged{$unit} = $payload->[1];
        },
        requeue          => sub { push(@queue, $_[0]); },
        more             => sub { return scalar(@queue); },
        forkFailWhen     => sub { return "forking unit $_[0]"; },
        retryWhen        => sub { return "unit $_[0]->{id}"; },
        mergeFailMessage => sub { return "merge of unit $_[0]->{id} failed"; },
        childFailMessage => sub { return "unit $_[0]->{id} failed"; },
        memoryThrottle   => 1,
        %extra);
    $mgr->run();
    return ($mgr, \%merged);
}

# ----------------------------------------------------------------------
# a client which can weigh its units:  the throttle learns a rate from the
#   children which finish, and says so
# ----------------------------------------------------------------------
my @weights = (2, 4, 6, 8, 10, 12);
my ($mgr, $merged) =
    run_manager(\@weights,
                unitWeight => sub { return $weights[$_[0]]; },
                remaining  => sub { return 'some'; });

check('every unit was merged', scalar(keys(%$merged)) == scalar(@weights));
my $sizes = 1;
for (my $i = 0; $i <= $#weights; ++$i) {
    $sizes = 0
        unless (exists($merged->{$i}) &&
                $merged->{$i} == $weights[$i] * $BYTES_PER_UNIT);
}
check('each unit reported the work it did', $sizes);
check('nothing is still reserved', 0 == scalar(keys(%{$mgr->{reserved}})));
check('a rate was learned',
      $mgr->{learnedWeight} > 0 && $mgr->{learnedBytes} > 0);

my @waits = grep(/memory constraint .* violated: waiting/, @messages);
check('the throttle waited', scalar(@waits) > 0);
# the first decision has nothing to predict with:  no child has finished, so
#   there is no rate, and the estimate is just our own size
check('the first wait had no rate to use', @waits && $waits[0] !~ / units at /);
my @rated = grep(/\(next: \d+ units at [0-9.]+ bytes each\)/, @waits);
check('a later wait used the learned rate', scalar(@rated) > 0);
# 'remaining' is what the client says is left, not the number of children
check('the message asked the client what is left',
      @waits && $waits[0] =~ /some remaining/);

# the rate is the marginal cost per unit of weight:  the ballast is what the
#   children really added, so the rate cannot be less than it (they also carry
#   a copy of us, and perl's own allocation is coarse, so it can be more)
my $rate = $mgr->{learnedBytes} / $mgr->{learnedWeight};
print("learned rate is $rate bytes per unit ($BYTES_PER_UNIT expected)\n");
check('the learned rate is at least the ballast', $rate >= $BYTES_PER_UNIT);

# ----------------------------------------------------------------------
# a client which cannot weigh its units:  there is nothing to learn, and the
#   estimate falls back to "a child costs what we cost", which is what every
#   client used to assume about every child
# ----------------------------------------------------------------------
@messages = ();
my @flat = (1, 1, 1, 1);
($mgr, $merged) = run_manager(\@flat);

check('every unweighted unit was merged',
      scalar(keys(%$merged)) == scalar(@flat));
check('nothing was learned without a weight',
      0 == $mgr->{learnedWeight} && 0 == $mgr->{learnedBytes});
@waits = grep(/memory constraint .* violated: waiting/, @messages);
check('the unweighted client throttled too', scalar(@waits) > 0);
check('no wait claimed a rate', 0 == scalar(grep(/ units at /, @waits)));
# no 'remaining' callback:  the message falls back to the number of children
check('the message counted children instead',
      @waits && $waits[0] =~ /(\d+) remaining/ && $1 > 0);

# ----------------------------------------------------------------------
# and with no ceiling at all, the memory question is not asked
# ----------------------------------------------------------------------
@messages            = ();
$lcovutil::maxMemory = 0;
($mgr, $merged) =
    run_manager(\@flat, unitWeight => sub { return $flat[$_[0]]; });
check('every unit was merged without a ceiling',
      scalar(keys(%$merged)) == scalar(@flat));
check('no memory constraint was reported',
      0 == scalar(grep(/memory constraint/, @messages)));

rmtree($tempdir);

if (@failures) {
    die(scalar(@failures) . " check(s) failed:\n\t" .
            join("\n\t", @failures) . "\n");
}
print("fork_throttle: all checks passed\n");
exit(0);
