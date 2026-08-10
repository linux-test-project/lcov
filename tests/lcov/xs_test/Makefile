include ../../common.mak

# The intent here is to have a stand-alone test which exercises every
# reachable line in the XS implementation.
#
# The former monolithic 'xs_test.sh' ran 233 perl fragments, each one twice (XS
# and LCOV_PURE_PERL=1) and, under --coverage, each of those under Devel::Cover.
# That was the whole cost of the test and it was strictly serial.  The fragments
# share no state, so the file was split into xs1..xs6 (~39 fragments each) which
# the harness runs in parallel.  Each part runs in its own working directory
# (xsN.d) via setup_common.sh, so they cannot collide on the fixed coverage
# output names.
#

# xs7 is not one of those six:  it tests the loading of the extension rather
# than the classes it provides, and so is the one part which has something to
# check even when the extension is not built at all.
TESTS := xs1.sh xs2.sh xs3.sh xs4.sh xs5.sh xs6.sh xs7.sh

clean:
	for t in $(TESTS) ; do ./$$t --clean ; done
	rm -f *.log *.dat
	rm -rf xs1.d xs2.d xs3.d xs4.d xs5.d xs6.d xs7.d
