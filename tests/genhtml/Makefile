include ../common.mak

# disabling some old tests because generated data is inconsistent
# (line/branch/function hit/miss stats do not match).
# Those tests have probably outlived their usefulness - so eliminating for now
# rather than enhancing the generation to become consistent
TESTS := full.sh zero.sh demangle.sh relative lambda

DISABLED := part1.sh part2.sh target.sh

clean:
	rm -rf *.log out_* *.tmp
