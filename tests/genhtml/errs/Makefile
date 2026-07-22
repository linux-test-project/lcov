include ../../common.mak

# The former monolithic 'msgtest.sh' was split into msgtest1..msgtest4 so its
# ~100 tool invocations (dominated by the genhtml report loops) run as four
# independent tests in parallel.  Each part runs in its own working directory
# (partN.d) and rebuilds the shared inputs via setup_common.sh, so they cannot
# collide.
TESTS := msgtest1.sh msgtest2.sh msgtest3.sh msgtest4.sh

clean:
	for i in $(TESTS) ; do \
	    ./$$i --clean ; \
	done
	rm -rf part1.d part2.d part3.d part4.d
