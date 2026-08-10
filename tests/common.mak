
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

LCOVLIBDIR := $(ROOT_DIR)/lib/LcovUtil
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

IS_GIT := $(shell git -C $(TOPDIR) rev-parse 2>&1 > /dev/null ; if [ 0 -eq $$? ]; then echo 1 ; else echo 0 ; fi)
IS_P4 = $(shell p4 have ... 2>&1 > /dev/null ; if [ 0 -eq $$? ]; then echo 1 ; else echo 0 ; fi)

ifeq (1,$(IS_GIT))
ANNOTATE_SCRIPT=$(SCRIPTDIR)/gitblame.pm,--verify,-b
VERSION_SCRIPT=$(SCRIPTDIR)/gitversion.pm
else
ANNOTATE_SCRIPT=$(SCRIPTDIR)/p4annotate.pm,--verify,-b
VERSION_SCRIPT=$(SCRIPTDIR)/P4version.pm,--local-edit,$(ROOT_DIR)
endif

ifneq ($(COVER_DB),)
export PERL_COVER_ARGS := -MDevel::Cover=-db,$(COVER_DB),-coverage,statement,branch,condition,subroutine,-silent,1
EXEC_COVER := perl ${PERL_COVER_ARGS}
export COVERAGE_COMMAND = $(shell which coverage 2>&1 > /dev/null ; if [ 0 -eq $$? ] ; then echo coverage ; else echo python3-coverage ; fi )
PYCOVER = COVERAGE_FILE=$(PYCOV_DB) ${COVERAGE_COMMAND} run --branch --append
#$(warning assigned PYCOVER='$(PYCOVER)')
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
export CC    ?= gcc

# 'make CC=/usr/bin/gcc check' names a toolchain, not just a C compiler.  The
#   C++ testcases have to build with the same one, because a run captures with a
#   single gcov - see the 'geninfo_gcov_tool' block in common.tst - and one gcov
#   cannot read both gcc 8's and gcc 16's .gcno.  So a $(CC) named on the command
#   line, which is a deliberate choice, selects its sibling g++ as well.  What
#   that overrides is an inherited environment $(CXX), which is what 'module load
#   gcc/N' leaves behind and is the weaker signal of the two;  naming $(CXX) on
#   the command line too still wins.  If $(CC) has no sibling g++ there is
#   nothing to derive, and common.tst reports whatever mismatch is left.
ifeq ($(origin CC),command line)
ifneq ($(origin CXX),command line)
CC_SIBLING_CXX := $(shell C=`command -v $(firstword $(CC)) 2>/dev/null` ;  \
	if [ -n "$$C" ] ; then                                             \
	    D=`dirname "$$C"` ;                                            \
	    if [ -x "$$D/g++" ] ; then echo "$$D/g++" ; fi ;               \
	fi )
ifneq ($(CC_SIBLING_CXX),)
CXX := $(CC_SIBLING_CXX)
endif
endif
endif

export CXX   ?= g++

# --------------------------------------------------------------------------
# Ask for MC/DC only when this toolchain can actually produce and read it.
#
# Two things have to be true:
#   - the objects must have been compiled with '-fcondition-coverage':
#     gcc 14 and later;
#   - the gcov which reads the result must understand '--conditions', which is
#     the same vintage.  A capture is not free to skip that:  geninfo asked for
#     MC/DC by a gcov which cannot supply it raises ERROR_USAGE, so unless the
#     caller ignores 'usage' the whole capture fails and the run loses its line
#     and branch coverage too, not just the MC/DC part of it.  '--filter mcdc'
#     with MC/DC off is a warning of the same class.
# So a makefile which captures real coverage should write '--branch
#   $(MCDC_OPTS)' and '--filter <list>$(MCDC_FILTER)' rather than naming
#   '--mcdc' and 'mcdc' outright, and an older toolchain then still gets
#   everything else.  The equivalent for a test script is the '$CC -dumpversion'
#   test several of them already do for themselves;  these variables are
#   deliberately not exported, because a script which decides for itself must
#   not have that answer overridden by the environment.
#
# $(LCOV_CXX) first, because that is the override lib/LcovUtil/Makefile.PL reads
#   before $(CXX);  whichever of them built the objects is the one to ask.
# --------------------------------------------------------------------------
MCDC_CXX := $(if $(LCOV_CXX),$(LCOV_CXX),$(CXX))
ENABLE_MCDC := $(shell                                                     \
	V=`$(firstword $(MCDC_CXX)) -dumpversion 2>/dev/null` ;            \
	if [ "$${V%%.*}" -ge 14 ] 2>/dev/null &&                           \
	   gcov --help 2>/dev/null | grep -q -- '--conditions' ; then       \
	  echo 1 ;                                                         \
	fi)
ifeq ($(ENABLE_MCDC),1)
MCDC_OPTS = --mcdc
MCDC_FILTER = ,mcdc
else
MCDC_OPTS =
MCDC_FILTER =
endif

export LCOV_TOOL := $(EXEC_COVER) $(BINDIR)/lcov
export GENHTML_TOOL := $(EXEC_COVER) $(BINDIR)/genhtml
export GENINFO_TOOL := $(EXEC_COVER) $(BINDIR)/geninfo
export PERL2LCOV_TOOL := $(EXEC_COVER) $(BINDIR)/perl2lcov
export LLVM2LCOV_TOOL := $(EXEC_COVER) $(BINDIR)/llvm2lcov
export PY2LCOV_TOOL := $(PYCOVER) $(BINDIR)/py2lcov
export XML2LCOV_TOOL := $(PYCOVER) $(BINDIR)/xml2lcov
export SPREADSHEET_TOOL := $(PYCOVER) $(SCRIPTDIR)/spreadsheet.py

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
OPTS += --coverage $(COVER_DB)
endif
ifneq ($(TESTCASE_ARGS),)
OPTS += --script-args "$(TESTCASE_ARGS)"
endif

# Parallel execution support
ifneq ($(PARALLEL),)
OPTS += --parallel $(PARALLEL)
endif

# Do not pass TESTS= specified on command line to subdirectories to allow
#   make TESTS=subdir
MAKEOVERRIDES := $(filter-out TESTS=%,$(MAKEOVERRIDES))

# Default target
check:
	#echo "found tests '$(TESTS)'"
	$(TOPDIR)/bin/runtests.py $(TESTS) $(OPTS)

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
	$(TOPDIR)/bin/cleantests.py $(TESTS)

.PHONY: check prepare clean clean_common
