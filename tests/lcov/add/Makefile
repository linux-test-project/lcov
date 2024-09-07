include ../../common.mak

# disabling some old tests because generated data is inconsistent
# (line/branch/function hit/miss stats do not match).
# Those tests have probably outlived their usefulness - so eliminating for now
# rather than enhancing the generation to become consistent
TESTS := zero.sh zero2.sh full.sh full2.sh  prune.sh track.sh
DISABLED: part.sh part2.sh concatenated4.sh

clean:
	rm -f *.info prune prune2 prune3 track
