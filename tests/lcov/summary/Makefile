include ../../common.mak

# disabling some old tests because generated data is inconsistent
# (line/branch/function hit/miss stats do not match).
# Those tests have probably outlived their usefulness - so eliminating for now
# rather than enhancing the generation to become consistent
TESTS := zero.sh full.sh
DISABLED := target.sh part1.sh part2.sh concatenated.sh concatenated2.sh

clean:
	rm -f *.info *.log
