include ../common.mak

# disabling some old tests because generated data is inconsistent
# (line/branch/function hit/miss stats do not match).
# Those tests have probably outlived their usefulness - so eliminating for now
# rather than enhancing the generation to become consistent
# List long-running tests first - so parallel execution picks them up as
#   early as possible
TESTS := \
  simple errs insensitive synthesize \
  relative lambda exception filter function \
  full.sh zero.sh demangle.sh 

DISABLED := part1.sh part2.sh target.sh

clean: clean_echo clean_subdirs
	rm -rf *.log out_* *.tmp
