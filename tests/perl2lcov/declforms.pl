# The 'package' and 'sub' declaration forms perl2lcov's source scan has to
#   recognise.  Devel::Cover reports a fully qualified subroutine name;  the
#   scan is what tells perl2lcov where each package and each subroutine begins,
#   which is how the end line of the one before it is worked out.
use strict;

sub plain {
    print("plain\n");
}

# a prototype, so the name does not end at whitespace
sub prototyped($) {
    my $x = shift;
    print("prototyped $x\n");
}

# the block form:  no semicolon after the package name
package Block::Form {

    sub inBlock {
        print("inBlock\n");
    }
}

# a version, so the name is not followed by the semicolon either
package Versioned 1.23;

sub versioned {
    print("versioned\n");
}

# everything from here to '=cut' below looks like a declaration and is not one.
#   The name perl2lcov reports each of the subroutines under is what says so:
#   a package it reads out of this text prefixes every subroutine after it
sub beforeText {
    print("beforeText\n");
}

our $text = <<'END_TEXT';
package NotAPackage;
sub notASub {
END_TEXT

sub afterHeredoc {
    print("afterHeredoc\n");
}

=pod

package InPod;

sub inPod {

__END__

=cut

# '<<' followed immediately by an identifier is a heredoc to perl, so the scan
#   has to treat one in a string as text - and there is no terminator for this
#   one anywhere below, which is how it can tell
our $shifty = 'the perl operator is <<NOSUCHTAG in this string';

sub afterPod {
    print("afterPod ", length($text) + length($shifty), "\n");
}

package main;

plain();
prototyped(1);
Block::Form::inBlock();
Versioned::versioned();
Versioned::beforeText();
Versioned::afterHeredoc();
Versioned::afterPod();
exit 0;

__END__

package AfterEnd;

sub afterEnd {
