export TOPDIR       := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
export TESTDIR      := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
export PARENTDIR    := $(dir $(patsubst %/,%,$(TOPDIR)))
export RELDIR       := $(TESTDIR:$(PARENTDIR)%=%)

# Path to artificial info files
export ZEROINFO     := $(TOPDIR)zero.info
export ZEROCOUNTS   := $(TOPDIR)zero.counts
export FULLINFO     := $(TOPDIR)full.info
export FULLCOUNTS   := $(TOPDIR)full.counts
export TARGETINFO   := $(TOPDIR)target.info
export TARGETCOUNTS := $(TOPDIR)target.counts
export PART1INFO    := $(TOPDIR)part1.info
export PART1COUNTS  := $(TOPDIR)part1.counts
export PART2INFO    := $(TOPDIR)part2.info
export PART2COUNTS  := $(TOPDIR)part2.counts
export INFOFILES    := $(ZEROINFO) $(FULLINFO) $(TARGETINFO) $(PART1INFO) \
		       $(PART2INFO)
export COUNTFILES   := $(ZEROCOUNTS) $(FULLCOUNTS) $(TARGETCOUNTS) \
		       $(PART1COUNTS) $(PART2COUNTS)

# Use pre-defined lcovrc file
LCOVRC       := $(TOPDIR)lcovrc

# Specify size for artificial info files (small, medium, large)
SIZE         := small
CC           := gcc

# Specify programs under test
export PATH    := $(TOPDIR)/../bin:$(TOPDIR)/bin:$(PATH)
export LCOV    := lcov --config-file $(LCOVRC) $(LCOVFLAGS)
export GENHTML := genhtml --config-file $(LCOVRC) $(GENHTMLFLAGS)

# Ensure stable output
export LANG    := C

# Suppress output in non-verbose mode
ifneq ($(V),2)
.SILENT:
endif

# Do not pass TESTS= specified on command line to subdirectories to allow
#   make TESTS=subdir
MAKEOVERRIDES := $(filter-out TESTS=%,$(MAKEOVERRIDES))

# Default target
check:
	runtests "$(MAKE)" $(TESTS)

ifeq ($(_ONCE),)

# Do these only once during initialization
export _ONCE := 1

check: checkdeps prepare

checkdeps:
	checkdeps $(TOPDIR)/../bin/* $(TOPDIR)/bin/*

prepare: $(INFOFILES) $(COUNTFILES)

# Create artificial info files as test data
$(INFOFILES) $(COUNTFILES):
	cd $(TOPDIR) && mkinfo profiles/$(SIZE) -o src/

endif

clean: clean_echo clean_subdirs

clean_echo:
	echo "  CLEAN   $(patsubst %/,%,$(RELDIR))"

clean_subdirs:
	cleantests "$(MAKE)" $(TESTS)

.PHONY: check prepare clean clean_common
