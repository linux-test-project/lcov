include ../../common.mak

# The former monolithic 'script.sh' was split into part1..part4 so its ~48
# genhtml invocations (the dominant cost) run as four independent tests in
# parallel.  Each part runs in its own working directory (partN.d/simple) and
# rebuilds the shared coverage inputs via setup_common.sh, so they cannot
# collide.
TESTS := part1.sh part2.sh part3.sh part4.sh

clean:
	for t in $(TESTS) ; do ./$$t --clean ; done
	rm -rf part1.d part2.d part3.d part4.d
