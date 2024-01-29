# example used to test perl2lcov coverage data extract

use strict;

sub global1 {
  print("called global1 function\n");
  if (exists($ENV{NO_SUCH_VARIABLE})) {
    print("unexercised statement in un-hit branch\n");
  }
}

package space1;
# LCOV_EXCL_START
sub packageFunc {
  print("this is a function in space1 - not exercised\n");
}
# LCOV_EXCL_STOP
sub packageFunc2 {
  my $val = shift;
  if (exists($ENV{NO_SUCH_VARIABLE}) &&
      ($ENV{NO_SUCH_VARIABLE} eq 'a' ||
       $ENV{NO_SUCH_VARIABLE} < 3)) {
    print("unexercised statement in more complex conditional\n");
  }
  print("packageFunc2 called\n");
}

package space2;

sub packageFunc {
  print("this is a function in space2 - not exercised\n");
}

sub packageFunc2 {
  if (exists($ENV{NO_SUCH_VARIABLE}) &&
      ($ENV{NO_SUCH_VARIABLE} eq 'a' ||
       $ENV{NO_SUCH_VARIABLE} < 3)) {
    print("unexercised statement in more complex conditional\n");
  }
  print("packageFunc2 called\n");
}

package main;
# LCOV_EXCL_BR_START
print "simple perl testcase\n";
global1();

space1::packageFunc2(1);

space2::packageFunc();
unless (@ARGV) {
  print("no args so we entered the branch\n");
}
exit 0;
# LCOV_EXCL_BR_STOP
