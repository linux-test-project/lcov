#
# Makefile for the LCOV example program.
#
# Make targets:
#   - example: compile the example program
#   - output:  run test cases on example program and create HTML output
#   - clean:   clean up directory
#

CC      := gcc
CFLAGS  := -Wall -I. --coverage
LDFLAGS  := --coverage

LCOV_FLAGS = --branch-coverage

ifneq ($(COVER_DB),)
export PERL_COVER_ARGS := -MDevel::Cover=-db,$(COVER_DB),-coverage,statement,branch,condition,subroutine,-silent,1
EXEC_COVER := perl ${PERL_COVER_ARGS}
endif

# MC/DC enabled in gcc/14 and above.  Ask $(CC):  everything here is C, so
#   $(CXX) does not decide what these objects can be built with.
ENABLE_MCDC := $(shell test `$(CC) -dumpversion | cut -d. -f1` -ge 14 && echo 1 || echo 0)

ifeq ($(ENABLE_MCDC), 1)
CFLAGS += -fcondition-coverage
LDFLAGS += -fcondition-coverage
LCOV_FLAGS += --mcdc-coverage
endif

# path differs depending on whether we are in the install dir or not
# run with "make LCOV_HOME=/path/to/my/release" if necessary

ifeq ($(LCOV_HOME),)
LCOV_HOME := $(shell if [ -d ../bin ] ; then echo `realpath ..` ; else echo `realpath ../../..` ; fi)
endif

EG_SRCDIR = $(shell if [ -d $(LCOV_HOME)/example ] ; then echo $(LCOV_HOME)/example ; else echo $(LCOV_HOME)/share/lcov/example ; fi)
# override this variable to write the differential testcase data someplace
#  else
REPO = exampleRepo
BINDIR = $(LCOV_HOME)/bin
SCRIPTS = $(LCOV_HOME)/scripts

# Keep the gcov this captures with matched to the compiler it builds with.
#   Those are the same toolchain only by convention:  'module load gcc/N' puts a
#   matching gcc and gcov on PATH together, but 'make CC=/usr/bin/gcc' leaves
#   lcov reading gcc 8's .gcno with whatever 'gcov' PATH finds first, and the
#   capture stops on the version tag instead of producing a report.  The gcov
#   which goes with a compiler is its sibling in the same directory;  when that
#   agrees with the one on PATH - the usual case - this is empty and nothing
#   about the run changes.  An explicit '--gcov-tool' still overrides it.
GCOV_TOOL_RC := $(shell                                                  \
	CC_PATH=`command -v $(firstword $(CC)) 2>/dev/null` ;            \
	PATH_GCOV=`command -v gcov 2>/dev/null` ;                        \
	if [ -n "$$CC_PATH" ] && [ -n "$$PATH_GCOV" ] ; then             \
	  SIBLING=`dirname "$$CC_PATH"`/gcov ;                           \
	  if [ -x "$$SIBLING" ] && [ "$$SIBLING" != "$$PATH_GCOV" ] &&   \
	     [ "`$$SIBLING --version 2>/dev/null | head -1`" !=          \
	       "`$$PATH_GCOV --version 2>/dev/null | head -1`" ] ; then  \
	    echo "--rc geninfo_gcov_tool=$$SIBLING" ;                    \
	  fi ;                                                           \
	fi )
ifneq ($(GCOV_TOOL_RC),)
$(info example: $(GCOV_TOOL_RC) - to match compiler '$(firstword $(CC))')
endif

LCOV    := $(EXEC_COVER) $(BINDIR)/lcov $(LCOV_FLAGS) $(GCOV_TOOL_RC)
GENHTML := $(EXEC_COVER) $(BINDIR)/genhtml $(LCOV_FLAGS)
GENDESC := $(EXEC_COVER) $(BINDIR)/gendesc
GENPNG  := $(EXEC_COVER) $(BINDIR)/genpng
SCRIPTDIR = $(shell if [ -d ../scripts ] ; then echo $(SCRIPTS) ; else echo $(LCOV_HOME)/share/lcov/support-scripts ; fi)

GITDIFF  := $(EXEC_COVER) $(SCRIPTDIR)/gitdiff

# Depending on the presence of the GD.pm perl module, we can use the
# special option '--frames' for genhtml
USE_GENPNG := $(shell $(GENPNG) --help >/dev/null 2>/dev/null; echo $$?)

ifeq ($(USE_GENPNG),0)
  FRAMES := --frames
else
  FRAMES :=
endif

ifeq ("${V}","1")
	echocmd=
else
	echocmd=echo $1 ;
.SILENT: clean
endif

# old version of gcc has inconsistent line/function data
EXTRA_IGNORE = $(shell VER=`$(CC) -dumpversion | perl -pe 's/^(\d+)\..+$$/$$1/'` ; if [ $$VER -lt 5 ] ; then echo "--ignore inconsistent" ; fi )

C99 = $(shell VER=`$(CC) -dumpversion | perl -pe 's/^(\d+)\..+$$/$$1/'` ; if [ $$VER -lt 5 ] ; then echo "-std=c99" ; fi )

# An object file does not record which compiler built it, and the sources have
#   not changed, so 'make CC=/usr/bin/gcc' after a plain 'make' rebuilds nothing
#   and then captures the previous compiler's .gcno with this one's gcov - the
#   same version mismatch $(GCOV_TOOL_RC) exists to prevent, arriving by a route
#   no gcov setting can help with.  So keep the compiler in a stamp file which
#   the objects depend on.  The stamp is considered every time (that is what the
#   FORCE prerequisite is for) but rewritten only when $(CC) has changed, so it
#   is newer than the objects exactly when they were built by a different
#   compiler and the .gcno have to be made again.  The .gcda need no such care:
#   every testcase below runs 'lcov --zerocounters' before it runs the program.
COMPILER_STAMP := .compiler

.PHONY: clean output example_noargs example_2_to_2000 example_overflow \
	example_differential FORCE

all: output

# below 'all', because the first eligible target in the file is the default goal
#   and 'FORCE' would otherwise become it - leaving a bare 'make' here silently
#   doing nothing at all.  ('.compiler' is not eligible:  make passes over a
#   target whose name begins with a period and holds no slash.)
FORCE:

$(COMPILER_STAMP): FORCE
	@if [ "`cat $@ 2>/dev/null`" != '$(CC)' ] ; then \
	    echo '$(CC)' > $@ ;                          \
	fi

example: example.o iterate.o gauss.o
	$(CC) $^ -o $@ $(LDFLAGS)

example.o: example.c iterate.h gauss.h $(COMPILER_STAMP)
	$(CC) $(CFLAGS) -c example.c -o example.o

iterate.o: methods/iterate.c iterate.h $(COMPILER_STAMP)
	$(CC) $(CFLAGS) -c methods/iterate.c -o iterate.o

gauss.o: methods/gauss.c gauss.h $(COMPILER_STAMP)
	$(CC) $(CFLAGS) -c methods/gauss.c -o gauss.o

output: example descriptions test_noargs test_2_to_2000 test_overflow test_differential
	@echo
	@echo '*'
	@echo '* Generating HTML output from data captured from tests'
	@echo '*'
	@echo
	$(GENHTML) trace_noargs.info trace_args.info trace_overflow.info \
		   --output-directory output --title "Basic example" \
		   --show-details --description-file descriptions $(FRAMES) \
		   --legend $(EXTRA_IGNORE)
	@echo
	@echo '*'
	@echo '* See '`pwd`/output/index.html
	@echo '*'
	@echo
	@echo "Generate HTML with hierarchical report and additional navigation features (same testcase data)"
	@echo '*'
	$(GENHTML) trace_noargs.info trace_args.info trace_overflow.info \
		   --output-directory hierarchical \
		   --title "Basic example - hierarchical" \
		   --show-details --hierarchical --show-navigation \
		   --description-file descriptions $(FRAMES) \
		   --legend $(EXTRA_IGNORE)
	@echo
	@echo '* See '`pwd`/hierarchical/index.html

descriptions: descriptions.txt
	$(GENDESC) descriptions.txt -o descriptions

all_tests: example test_noargs test_2_to_2000 test_overflow differential

test_noargs:
	@echo
	@echo '*'
	@echo '* Test case 1: running ./example without parameters'
	@echo '*'
	@echo
	$(LCOV) --zerocounters --directory .
	./example
	$(LCOV) --capture --directory . --output-file trace_noargs.info --test-name test_noargs --no-external

test_2_to_2000:
	@echo
	@echo '*'
	@echo '* Test case 2: running ./example 2 2000'
	@echo '*'
	@echo
	$(LCOV) --zerocounters --directory .
	./example 2 2000
	$(LCOV) --capture --directory . --output-file trace_args.info --test-name test_2_to_2000 --no-external $(EXTRA_IGNORE)

test_overflow:
	@echo
	@echo '*'
	@echo '* Test case 3: running ./example 0 100000 (causes an overflow)'
	@echo '*'
	@echo
	$(LCOV) --zerocounters --directory .
	./example 0 100000 || true
	$(LCOV) --capture --directory . --output-file trace_overflow.info --test-name "test_overflow" --no-external $(EXTRA_IGNORE)

# This test pretends to write some code, run some tests, then modify
#   code and rerun some tests.
# The differential coverage report is categorizes the code based on
#   what changed in the source code and what changed in the tests.
# Note that we are using perl module for callbacks here - but could use
#   script or executable if desired.
# Could use --verbose and --quiet flags to make the execution less noisy -
#   but verbosity can help to debug configuration issues.
# See the lcov README and man pages for more details.
test_differential:
	@echo
	@echo '*'
	@echo '* Test case 4: differential coverage example'
	@echo '*'
	@echo
	@echo "Step 1: Initialize GIT repo with example source"
	@$(RM) -rf $(REPO)
	@git init $(REPO) ;
	@(cd $(REPO) ; \
	cp -f $(EG_SRCDIR)/*.h $(EG_SRCDIR)/example.c . ; \
	mkdir methods ; \
	cp -f $(EG_SRCDIR)/methods/gauss.c methods ; \
	cp -f $(EG_SRCDIR)/methods/iterate.c methods ; \
	find . \( -name '*.h' -o -name '*.c' \) -exec git add {} \; ; \
	git commit -m baseline ; git tag baseline )
	@echo "Build example and run some tests"
	(cd $(REPO) ; \
	$(CC) -o example $(CFLAGS) $(C99) -I. example.c methods/gauss.c methods/iterate.c ; \
	./example ; \
	./example 2 1000 ; \
	./example 2 100000 || true )

	@echo "Step 2: Capture initial coverage"
	(cd $(REPO) ; \
	$(LCOV) --capture -o baseline.info -d . \
		--version-script $(SCRIPTDIR)/gitversion.pm --profile )

	@echo "Step 3: Modify source code"
	@(cd $(REPO) ; \
	cp -f $(EG_SRCDIR)/example_mod.c example.c ; \
	cp -f $(EG_SRCDIR)/methods/iterate_mod.c methods/iterate.c ; \
	git add example.c methods/iterate.c ; \
	git commit -m current ; \
	git tag current )

	@echo "Step 4: Rebuild and run tests (fewer tests this time)"
	( cd $(REPO) ; \
	find . -name '*.gc*' -delete ; \
	$(CC) -o example $(CFLAGS) $(C99) -I. example.c methods/gauss.c methods/iterate.c ; \
	./example )

	@echo "Step 5: Capture new coverage (after source changes)"
	@echo "   (note that this example is too tiny for history reuse"
	@echo "   to affect runtime performance)"
	(cd $(REPO) ; \
	$(LCOV) --capture -o current.info -d .              \
		--version-script $(SCRIPTDIR)/gitversion.pm \
		--profile                                   \
		--history $(SCRIPTDIR)/history.pm,baseline.info.json )
	@echo "Compute source diffs"
	(cd $(REPO) ;                                          \
	$(GITDIFF) -b . `git rev-list -n 1 baseline` \
	  `git rev-list -n 1 current` > udiff.txt )

	@echo "Step 6: Generate differential coverage report"
	@echo "      - caching revision control data may result in improved runtime performance)"
	@echo "      - verify revision control data vs local edits"
	@echo "      - capture 'genhtml' execution profile that we can use later"
	(cd $(REPO) ;                                            \
	$(GENHTML) -o differential --baseline-file baseline.info \
	  --diff-file udiff.txt --show-owners                    \
	  --title "Differential coverage example"                \
	  --annotate $(SCRIPTDIR)/gitblame.pm,--cache,./my_cache,--verify \
	  --version-script $(SCRIPTDIR)/gitversion.pm --profile  \
	  -- current.info )

	@echo "point your browser to `realpath $(REPO)`/differential/index.html"

	@echo "Step 7: Generate subset report for code review:"
	@echo "      - reuse execution profile and cached revision control data"
	@echo "        captured in previous step"
	(cd $(REPO) ;                                            \
	$(GENHTML) -o review --baseline-file baseline.info       \
	  --diff-file udiff.txt --show-owners                    \
	  --title "Differential report for code review"          \
	  --annotate $(SCRIPTDIR)/gitblame.pm,--cache,./my_cache,--verify \
	  --version-script $(SCRIPTDIR)/gitversion.pm            \
	  --select-script $(SCRIPTDIR)/select.pm                 \
	  --select-script --tla --select-script UNC,UIC,LBC      \
	  --history-script $(SCRIPTDIR)/history.pm               \
	  --history-script ./differential/genhtml.json --profile \
          -- current.info )

	@echo "point your browser to `realpath $(REPO)`/review/index.html"


clean:
	$(call echocmd,"  CLEAN   lcov/example")
	rm -rf *.o *.bb *.bbg *.da *.gcno *.gcda *.info output example descriptions \
	  $(REPO) $(HTML_example_dir) hierarchical $(COMPILER_STAMP)
