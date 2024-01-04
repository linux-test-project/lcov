
# TOPDIR == root of test directory - either build dir or copied from share/lcov
TOPDIR       := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
# TESTDIR == path to this particular testcase
TESTDIR      := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))

ifeq ($(LCOV_HOME),)
ROOT_DIR = $(realpath $(TOPDIR)/..)
else
ROOT_DIR := $(LCOV_HOME)
endif
BINDIR = $(ROOT_DIR)/bin

ifneq (,$(wildcard $(ROOT_DIR)/scripts))
SCRIPTDIR := $(ROOT_DIR)/scripts
else
SCRIPTDIR := $(ROOT_DIR)/share/lcov/support-scripts
endif

ifeq ($(DEBUG),1)
$(warning TOPDIR = $(TOPDIR))
$(warning TESTDIR = $(TESTDIR))
$(warning BINDIR = $(BINDIR))
$(warning SCRIPTDIR = $(SCRIPTDIR))
endif

TESTBINDIR := $(TOPDIR)bin

IS_GIT := $(shell git -C $(TOPDIR) rev-parse 2>&1 > /dev/null ; if [ 0 == $$? ]; then echo 1 ; else echo 0 ; fi)

ifeq (1,$(IS_GIT))
ANNOTATE_SCRIPT=$(SCRIPTDIR)/gitblame.pm
VERSION_SCRIPT=$(SCRIPTDIR)/gitversion.pm
else
ANNOTATE_SCRIPT=$(SCRIPTDIR)/p4annotate.pm
VERSION_SCRIPT=$(SCRIPTDIR)/getp4version
endif

ifneq ($(COVER_DB),)
EXEC_COVER := perl -MDevel::Cover=-db,$(COVER_DB),-coverage,statement,branch,condition,subroutine,-silent,1
endif


export TOPDIR TESTDIR
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

export LCOV_TOOL := $(EXEC_COVER) $(BINDIR)/lcov
export GENHTML_TOOL := $(EXEC_COVER) $(BINDIR)/genhtml
export GENINFO_TOOL := $(EXEC_COVER) $(BINDIR)/geninfo
export PERL2LCOV_TOOL := $(EXEC_COVER) $(BINDIR)/perl2lcov

# Specify programs under test
export PATH    := $(BINDIR):$(TESTBINDIR):$(PATH)
export LCOV    := $(LCOV_TOOL) --config-file $(LCOVRC) $(LCOVFLAGS)
export GENHTML := $(GENHTML_TOOL) --config-file $(LCOVRC) $(GENHTMLFLAGS)

# Ensure stable output
export LANG    := C

# Suppress output in non-verbose mode
export V
ifeq ("${V}","1")
	echocmd=
else
	echocmd=echo $1 ;
.SILENT:
endif

ifneq ($(COVER_DB),)
#OPTS += --coverage $(COVER_DB)
endif
ifneq ($(TESTCASE_ARGS),)
OPTS += --script-args "$(TESTCASE_ARGS)"
endif

# Do not pass TESTS= specified on command line to subdirectories to allow
#   make TESTS=subdir
MAKEOVERRIDES := $(filter-out TESTS=%,$(MAKEOVERRIDES))

# Default target
check:
	#echo "found tests '$(TESTS)'"
	runtests "$(MAKE)" $(TESTS) $(OPTS)

ifeq ($(_ONCE),)

# Do these only once during initialization
export _ONCE := 1

check: checkdeps prepare

checkdeps:
	checkdeps $(BINDIR)/* $(TESTBINDIR)/*

prepare: $(INFOFILES) $(COUNTFILES)

# Create artificial info files as test data
$(INFOFILES) $(COUNTFILES):
	cd $(TOPDIR) && $(TOPDIR)/bin/mkinfo profiles/$(SIZE) -o src/

endif

clean: clean_echo clean_subdirs

clean_echo:
	$(call echocmd,"  CLEAN   lcov/$(patsubst %/,%,$(RELDIR))")

clean_subdirs:
	cleantests "$(MAKE)" $(TESTS)

.PHONY: check prepare clean clean_common
