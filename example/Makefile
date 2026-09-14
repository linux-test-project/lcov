#
# Makefile for the LCOV example program.
#
# Make targets:
#   - output:       run test cases on example program and create HTML output
#   - example:      compile the example program
#   - example_java: Java coverage example - needs a JDK and JaCoCo, and does
#                   nothing if not available.
#   - clean:        clean up directory
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
# The example GIT repo:  one repo holding the sources of all testcases.
# One multi-language project is more realistic than using multiple repos
# for different tests.
# Repo is built once, by whichever test runs first (see  $(REPO_STAMP) below).
# Reop removed by 'clean'
# Override 'REPO' variable if you want the data to be written somewhere else.
REPO = exampleRepo
# Use a file for timestamp marker: directory's timestamp is not useful, and
#   the presence of '.git' would not tell us whether sources had been added
REPO_STAMP = $(REPO)/.initialized
HTML_example_dir = htmlDir
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
HTML2LCOV := $(EXEC_COVER) $(BINDIR)/html2lcov $(LCOV_FLAGS)
GENDESC := $(EXEC_COVER) $(BINDIR)/gendesc
GENPNG  := $(EXEC_COVER) $(BINDIR)/genpng
SCRIPTDIR = $(shell if [ -d ../scripts ] ; then echo $(SCRIPTS) ; else echo $(LCOV_HOME)/share/lcov/support-scripts ; fi)

GITDIFF  := $(EXEC_COVER) $(SCRIPTDIR)/gitdiff

# ---------------------------------------------------------------------------
# The Java/JaCoCo example.  Coverage for the Java program comes from the JaCoCo
#   agent - so this part of the example needs a JDK and a JaCoCo installation.
# script 'java_avail.sh' checks for availability and complains if something
# is missing.
JACOCO2LCOV := $(EXEC_COVER) $(BINDIR)/jacoco2lcov
# JaCoCo records line, branch and method coverage and nothing else:  there is no
#   MC/DC data in a JaCoCo report, so this asks genhtml for what there is rather
#   than using $(LCOV_FLAGS), which adds --mcdc-coverage when the C compiler can
#   produce it.
JAVA_GENHTML := $(EXEC_COVER) $(BINDIR)/genhtml --branch-coverage

# The JDK from JAVA_HOME if that variable is set, else whatever is on PATH:  an
#   environment which sets JAVA_HOME means that JDK to be used, even when an
#   older java is on PATH in front of it.  './java_avail.sh' decides whether
#   these exist, by the same rule.
JAVA  := $(if $(JAVA_HOME),$(JAVA_HOME)/bin/java,java)
JAVAC := $(if $(JAVA_HOME),$(JAVA_HOME)/bin/javac,javac)

# The agent jar - the one the JVM loads to collect the data.  jacoco2lcov finds
#   jacococli.jar for itself, and looks in the same two places this does;  see
#   man jacoco2lcov(1).  './java_avail.sh' looks in the same two places as well.
JACOCO_AGENT := $(shell                                       \
	if [ -n "$(JACOCO_HOME)" ] ; then                     \
	  for f in lib/jacocoagent.jar jacocoagent.jar ; do   \
	    if [ -f "$(JACOCO_HOME)/$$f" ] ; then             \
	      echo "$(JACOCO_HOME)/$$f" ;                     \
	      break ;                                         \
	    fi ;                                              \
	  done ;                                              \
	fi )

# Whether the Java example can run at all.  './java_avail.sh' is silent and
#   succeeds when java, javac and JaCoCo are all where they have to be, and says
#   what is missing and fails when they are not - so when this is not 'yes', the
#   recipe below runs the script for the explanation and does nothing else.  A
#   release built on a machine which has no Java on it still runs the rest of
#   the examples to completion.
JAVA_AVAIL_SCRIPT := $(EG_SRCDIR)/java_avail.sh
JAVA_AVAIL := $(shell $(JAVA_AVAIL_SCRIPT) > /dev/null 2>&1 && echo yes)
# ---------------------------------------------------------------------------

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
	example_differential example_html2lcov example_java FORCE

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

output: example descriptions example_noargs example_2_to_2000 example_overflow example_differential example_html2lcov example_java
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

all_tests: example example_noargs example_2_to_2000 example_overflow example_differential example_html2lcov example_java

example_noargs:
	@echo
	@echo '*'
	@echo '* Test case 1: running ./example without parameters'
	@echo '*'
	@echo
	$(LCOV) --zerocounters --directory .
	./example
	$(LCOV) --capture --directory . --output-file trace_noargs.info --test-name example_noargs --no-external

example_2_to_2000:
	@echo
	@echo '*'
	@echo '* Test case 2: running ./example 2 2000'
	@echo '*'
	@echo
	$(LCOV) --zerocounters --directory .
	./example 2 2000
	$(LCOV) --capture --directory . --output-file trace_args.info --test-name example_2_to_2000 --no-external $(EXTRA_IGNORE)

example_overflow:
	@echo
	@echo '*'
	@echo '* Test case 3: running ./example 0 100000 (causes an overflow)'
	@echo '*'
	@echo
	$(LCOV) --zerocounters --directory .
	./example 0 100000 || true
	$(LCOV) --capture --directory . --output-file trace_overflow.info --test-name "example_overflow" --no-external $(EXTRA_IGNORE)

# The example repo, shared by the testcases below which need revision control.
#   Every source any of them wants is checked in when the repo is made, so that
#   whichever of them runs first finds what it needs and the second one finds the
#   repo already there.
$(REPO_STAMP):
	@echo
	@echo "Initialize the example GIT repo with the source of every testcase"
	@echo "  which needs one (C and Java - one repo, as a project with more"
	@echo "  than one language in it has)"
	@$(RM) -rf $(REPO)
	@git init $(REPO)
	@(cd $(REPO) ;                                            \
	cp -f $(EG_SRCDIR)/*.h $(EG_SRCDIR)/example.c . ;         \
	mkdir methods ;                                           \
	cp -f $(EG_SRCDIR)/methods/gauss.c methods ;              \
	cp -f $(EG_SRCDIR)/methods/iterate.c methods ;            \
	mkdir -p src/hello ;                                      \
	cp -f $(EG_SRCDIR)/HelloWorld.java src/hello ;            \
	find . \( -name '*.h' -o -name '*.c' -o -name '*.java' \) \
	  -exec git add {} \; ;                                   \
	git commit -m baseline ; git tag baseline )
	@touch $@

# This test pretends to write some code, run some tests, then modify
#   code and rerun some tests.
# The differential coverage report is categorizes the code based on
#   what changed in the source code and what changed in the tests.
# Note that we are using perl module for callbacks here - but could use
#   script or executable if desired.
# Could use --verbose and --quiet flags to make the execution less noisy -
#   but verbosity can help to debug configuration issues.
# See the lcov README and man pages for more details.
example_differential: $(REPO_STAMP)
	@echo
	@echo '*'
	@echo '* Test case 4: differential coverage example'
	@echo '*'
	@echo
	@echo "Step 1: Put the example repo back at its baseline revision"
	@echo "  (this testcase modifies the sources below and commits them as"
	@echo "  'current', and the repo is built once and shared - so start by"
	@echo "  undoing that.  There is nothing to undo the first time.)"
# 'git restore' unconditionally, rather than asking what state the repo is in:
#   it does nothing when there is nothing to do, which is the usual case.
	@(cd $(REPO) ;                                            \
	git restore --source=baseline --staged --worktree -- . ;  \
	git tag -d current > /dev/null 2>&1 ;                     \
	git reset -q --soft baseline ;                            \
	find . \( -name '*.gcda' -o -name '*.gcno' \) -delete )
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
	find . \( -name '*.gcda' -o -name '*.gcno' \) -delete ; \
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

# This test uses the same source code and same scenario as 'example_differential',
# above - but pretends to modify code that is not under revision control,
# or to model a change that is not under revision control.
#
# The scenario looks like:
#   - user writes or modifies some source code, collects coverage, and
#      generates a coverage report.
#   - user makes more changes to the source code (and/or adds tests, 
#     changes Makefiles,  or whatever) - and now wants a differential
#     coverage report, to see the effect of these changes.
#
# Unlike the 'example_differential' scenario:  this time, the user cannot
# retrieve differences - because the 'baseline' was never checked in. :-(
# Instead: we use the html2lcov tool to deduce differences between the
# code found in the coverage report and the new source code - and generate
# a differential report from that.
#
# Note that - if this code was checked in a repo, then we could use
# genhtml with --annotate-script, --version-script, etc.
# The 'html2lcov' path enables us to generate differential coverage report
# without requiring revision control integration - but we can use the
# revision control integration, if it desired.
# See the lcov README and man pages for more details.
example_html2lcov:
	@echo
	@echo '*'
	@echo '* Test case 5: differential coverage using html2lcov'
	@echo '*'
	@echo
	@echo "Step 1: Compile initial project source code, run tests"
	@$(RM) -rf $(HTML_example_dir)
	@(mkdir $(HTML_example_dir) ;                     \
	cd $(HTML_example_dir) ;                          \
	cp -f $(EG_SRCDIR)/*.h $(EG_SRCDIR)/example.c . ; \
	mkdir methods ;                                   \
	cp -f $(EG_SRCDIR)/methods/gauss.c methods ;      \
	cp -f $(EG_SRCDIR)/methods/iterate.c methods )

	@echo "Build example and run some tests"
	(cd $(HTML_example_dir) ;                                  \
	$(CC) -o example $(CFLAGS) $(C99) -I.           \
	  example.c methods/gauss.c methods/iterate.c ; \
	./example ;                                     \
	./example 2 1000 ;                              \
	./example 2 100000 || true )

	@echo "Step 2: Capture initial coverage and generate coverage report"
	(cd $(HTML_example_dir) ;                                    \
	$(LCOV) --capture -o baseline.info --profile -d . )

	@echo "generate coverage report"
	@echo "  Note that we have to '--save' the coverage .info file."
	@echo " (the code might not be in a repo - in which case, it would"
	@echo " not be annotated)"
	(cd $(HTML_example_dir) ;                                  \
	$(GENHTML) -o baseline_rpt baseline.info --save --profile  \
	   --title "Coverage report for initial code" )

	@echo "point your browser to `realpath $(HTML_example_dir)`/baseline_rpt/index.html"

	@echo "Step 3: Modify source code"
	@echo "  Note that this time: we do not commit the changes"
	@echo "  (this is similar to the case that the code is not revision controlled)"

	@(cd $(HTML_example_dir) ; \
	cp -f $(EG_SRCDIR)/example_mod.c example.c ; \
	cp -f $(EG_SRCDIR)/methods/iterate_mod.c methods/iterate.c )

	@echo "Step 5: Rebuild and run tests (fewer tests this time)"
	( cd $(HTML_example_dir) ;                              \
	find . \( -name '*.gcda' -o -name '*.gcno' \) -delete ; \
	$(CC) -o example $(CFLAGS) $(C99) -I.                   \
	example.c methods/gauss.c methods/iterate.c ;           \
	./example )

	@echo "Step 4: Capture new coverage (after source changes)"
	(cd $(HTML_example_dir) ;                                    \
	$(LCOV) --capture -o current.info -d . --profile             \
		--history $(SCRIPTDIR)/history.pm,baseline.info.json )

	@echo "Step 5: Compute source diffs from baseline coverage report"
	@echo "  '-o recovered' names a base:  the universal diff lands in"
	@echo "  'recovered.udiff' (and the recovered coverage in 'recovered.info')."
	(cd $(HTML_example_dir) ;                     \
	$(HTML2LCOV) ./baseline_rpt -o recovered      \
	  --current current.info --source-directory . )

	@echo "Step 6: Generate differential coverage report from captured data"
	@echo "  Note: this scenario models code that is NOT revision controlled,"
	@echo "  so there is no annotation source and we do not pass '--show-owners'."

	(cd $(HTML_example_dir) ;                                 \
	$(GENHTML) -o differential2 --baseline-file baseline.info \
	  --title "Differential coverage example (html2lcov)"     \
	  --diff-file recovered.udiff --profile -- current.info )

	@echo "point your browser to `realpath $(HTML_example_dir)`/differential2/index.html"

	@echo "Step 7: Generate subset report for code review:"
	@echo "  (html2lcov-derived data can be used to generate reports for code"
	@echo "  review - similar to step 7 of the 'example_differential' example,"
	@echo "  above.  The same '--select-script' options can be used with data"
	@echo "  derived from html2lcov; here we reuse the execution profile"
	@echo "  captured in the previous step.)"
	(cd $(HTML_example_dir) ;                                  \
	$(GENHTML) -o review2 --baseline-file baseline.info         \
	  --diff-file recovered.udiff                               \
	  --title "Differential report for code review (html2lcov)" \
	  --select-script $(SCRIPTDIR)/select.pm                    \
	  --select-script --tla --select-script UNC,UIC,LBC         \
	  --history-script $(SCRIPTDIR)/history.pm                  \
	  --history-script ./differential2/genhtml.json             \
          -- current.info )

	@echo "point your browser to `realpath $(HTML_example_dir)`/review2/index.html"


# The same 'compile, run the tests, capture, report' flow as the examples above,
#   for a Java program:  the coverage data is collected by the JaCoCo agent in
#   the JVM rather than written by instrumented code, and 'jacoco2lcov'
#   translates what JaCoCo collected into an LCOV .info file which is no
#   different from the ones captured from gcov data above.
#
# The report uses the same annotate and version callbacks as the
#   'example_differential' example - so the source is checked into a repo.
#   There is no second revision and no diff, so this is not a differential
#   report - just a vanilla, annotated report with version checking.
#
# See man jacoco2lcov(1) details, and the 'JaCoCo conversion notes'
#   section of man xml2lcov(1) for what JaCoCo data does and does not tell us.
#
# The repo is a prerequisite only when there is something to run:  a machine with
#   no Java on it has no reason to build a repo for a testcase which is about to
#   say that it is skipping itself.
ifeq ($(JAVA_AVAIL),yes)
example_java: $(REPO_STAMP)
endif
example_java:
	@echo
	@echo '*'
	@echo '* Test case 6: Java coverage example (JaCoCo)'
	@echo '*'
	@echo
ifneq ($(JAVA_AVAIL),yes)
	@echo "Skipping the Java example:"
	@echo
	@$(JAVA_AVAIL_SCRIPT) || true
	@echo
	@echo "  This example needs a JDK and a JaCoCo installation.  Put them where"
	@echo "  '$(JAVA_AVAIL_SCRIPT)' can find them"
	@echo "  and run 'make example_java' again;  running that script by itself"
	@echo "  says whether they are there yet."
else
	@echo "Step 1: Compile and run the test"
	@echo "  (the source is already in the example repo, which is built once"
	@echo "  for whichever testcase needs it first)"
	@echo "  ('javac -g': JaCoCo reads the line number table which that"
	@echo "  writes - without it, there are no line numbers to report)"
# 'git restore' unconditionally - it does nothing when there is nothing to do -
#   because the report step below verifies the annotations and the version
#   against the file on disk, and would report a local edit left behind by
#   something else as an error rather than quietly using it.
# The old .exec file has to go:  the JaCoCo agent appends to the file it is
#   given, so a second run in a directory which was not cleaned would otherwise
#   report the counts of both runs.  The class files go with it, so that 'bin'
#   holds what this source compiled to and nothing else.
	(cd $(REPO) ;                                             \
	git restore -- src/hello/HelloWorld.java ;                \
	$(RM) -rf bin hello.exec ;                                \
	$(JAVAC) -g -d bin src/hello/HelloWorld.java ;            \
	$(JAVA) -javaagent:$(JACOCO_AGENT)=destfile=hello.exec    \
	  -cp bin hello.HelloWorld )

	@echo "Step 2: Capture coverage"
	@echo "  (jacoco2lcov runs 'jacococli report' to turn the .exec file into"
	@echo "  JaCoCo XML, then xml2lcov to translate that into an .info file)"
# '--version-script' is what puts VER: records in the .info file, and the report
#   step below needs them:  it computes a version for the source it reads, and
#   stops with a 'version' error when the data it is shown has nothing to compare
#   against.  A JaCoCo report does not say which version of the source it
#   describes - unlike a gcov capture, there is no version in the data to carry
#   through - so jacoco2lcov computes it from the source with this callback.
	(cd $(REPO) ;                                             \
	$(JACOCO2LCOV) -o hello.info -s src -c bin                \
	  --test-name helloworld                                  \
	  --version-script $(SCRIPTDIR)/gitversion.pm hello.exec )

	@echo "Step 3: Generate the coverage report"
	@echo "      - annotate the source with author and date data from git"
	@echo "      - verify the revision control data against local edits"
	@echo "      - check the source against the version it was captured from"
	(cd $(REPO) ;                                                     \
	$(JAVA_GENHTML) -o jacoco_report --show-owners                    \
	  --title "Java coverage example (JaCoCo)"                        \
	  --annotate $(SCRIPTDIR)/gitblame.pm,--cache,./my_cache,--verify \
	  --version-script $(SCRIPTDIR)/gitversion.pm --profile           \
	  -- hello.info )

	@echo "point your browser to `realpath $(REPO)`/jacoco_report/index.html"
endif


clean:
	$(call echocmd,"  CLEAN   lcov/example")
	rm -rf *.o *.bb *.bbg *.da *.gcno *.gcda *.info output example descriptions \
	  $(REPO) $(HTML_example_dir) hierarchical $(COMPILER_STAMP)
