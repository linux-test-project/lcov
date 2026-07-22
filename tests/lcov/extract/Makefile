include ../../common.mak

# The former monolithic 'extract.sh' was split into extract1.sh + extract2.sh
# so its ~55 capture invocations (the dominant cost) run as two independent
# tests in parallel.  Each part runs in its own working directory (partN.d) and
# rebuilds the shared inputs via setup_common.sh, so they cannot collide.
TESTS := extract1.sh extract2.sh

clean:
	for t in $(TESTS) ; do ./$$t --clean ; done
	for d in part1.d part2.d ; do \
	    if [ -d $$d ] ; then chmod -R u+rwx $$d 2>/dev/null ; rm -rf $$d ; fi ; \
	done
