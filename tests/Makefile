ifeq ($(COVERAGE), 1)
ifeq ($(COVER_DB),)
export COVER_DB := $(shell echo `pwd`/cover_db)
export PYCOV_DB := $(shell echo `pwd`/pycov.dat)
export HTML_RPT := $(shell echo `pwd`/lcov_coverage)
endif
# set to directory name - where to put individual testcase data
PER_TEST_COVERAGE =
endif

.PHONY: excel info report

all: check report

include common.mak

TESTS := genhtml scripts lcov llvm2lcov py2lcov perl2lcov xml2lcov html2lcov

# there may or may not be some .info files generated for exported
#  tools - py2lcov, perl2lcov, etc.  We want them included in the
#  report - but they might not have been generated, so we need to
#  ignore the potential 'empty glob pattern' error message and a
#  potential remote repo timestamp issue
EXCLUDES =                                            \
	genError.pm brokenCallback.pm MsgContext.pm   \
	missingRestore.pm parallelFail.pm naivecb.pm  \
	filter.pl reader.pl writer.pl writer_modeb.pl \
	'*/tmp*' 'tests/*' scheduling
EXCL_OPTS = $(foreach e, $(EXCLUDES), --exclude $(e))
OMIT_OPTS = --omit-lines 'ERROR_INTERNAL' --omit-lines '\bdie\b'
IGNORE_OPTS = --ignore unsupported,unused,inconsistent

# The coverage recipes below are each one long shell command, joined with ';' -
#  so only the exit status of the last thing they run would reach make, and one
#  of our own tools failing part way through would leave a truncated report and
#  a build which claimed to have succeeded.  Every call is followed by
#  'checkrc <what> $$?' instead:  it names what failed, where it failed, and
#  remembers that it did, so the recipe still runs to the end - the rest of the
#  report is worth having - and then exits non-zero.
#  Note the LcovUtil capture in 'info', which deliberately does not use this:
#  a '.gcda' which the gcov on PATH cannot read is expected there, and is
#  warned about rather than treated as a failure.
CHECK_RC = rc=0 ;                                                    \
	checkrc() {                                                  \
	  if [ 0 != $$2 ] ; then                                     \
	    echo "*** ERROR: $$1 failed (exit $$2)" ;                \
	    rc=$$2 ;                                                 \
	  fi ;                                                       \
	} ;

excel:
	$(SPREADSHEET_TOOL) -o report.xlsx `find . -name "*.json"`

# note that there may be no GCDA files in the lib/LcovUtil
#  directory - if all tests ran with LCOV_PURE_PERL=1
# a run which was killed can leave a zero-length 'digests' in one of the
#  per-test databases;  'cover' cannot read that (see the comment in
#  common.tst), so drop it here too rather than lose the whole report
#  because one testcase was interrupted
# $(MCDC_OPTS)/$(MCDC_FILTER) come from common.mak and are empty unless the
#  toolchain which built the extension can produce MC/DC data and the gcov
#  which reads it can report it;  see the comment there

info:
	$(CHECK_RC)                                                  \
	if [ "x$(COVERAGE)" != 'x' ] ; then                          \
	  if [ -d cover_db.d ] ; then                                \
	    rm -f cover_db.d/*.log ;                                 \
	    find cover_db.d $(COVER_DB) -maxdepth 2 -name digests    \
	        -empty -print -delete 2>/dev/null ;                  \
	    DBS=cover_db.d/* ;                                       \
	    cover -write $(COVER_DB) $$DBS > cover.log 2>&1 ;        \
	    checkrc "cover -write $(COVER_DB)" $$? ;                 \
	    if [ "x$(PER_TEST_COVERAGE)" != 'x' ] ; then             \
	      mkdir -p $(PER_TEST_COVERAGE) ;                        \
              for db in $$DBS ; do                                   \
	         echo ----- $$db ------------- ;                     \
	         cover $$db > $$db.log 2>&1 ;                        \
	         checkrc "cover $$db" $$? ;                          \
	         $(PERL2LCOV_TOOL) $(CAPTURE_OPTS)                   \
	           -o $(PER_TEST_COVERAGE)/`basename $$db`_cov.info $$db \
                   --version-script $(VERSION_SCRIPT)                \
		   $(EXCL_OPTS) $(OMIT_OPTS) $(IGNORE_OPTS)          \
                   --filter region ;                                 \
	         checkrc "perl2lcov $$db" $$? ;                      \
	      done ;                                                 \
	      ( cd $(PER_TEST_COVERAGE);                             \
	        $(LCOV_TOOL) $(CAPTURE_OPTS) -o total.info           \
		  --branch --keep-going                              \
		  --version-script $(VERSION_SCRIPT)                 \
		  $(foreach f, $(shell ls *.info), -a $$f)           \
	      ) ;                                                    \
	      checkrc "lcov -a in $(PER_TEST_COVERAGE)" $$? ;        \
	    fi ;                                                     \
	  fi ;                                                       \
	  cover $(COVER_DB) > cover.log 2>&1 ;                       \
	  checkrc "cover $(COVER_DB)" $$? ;                          \
	  $(PERL2LCOV_TOOL) $(CAPTURE_OPTS)                          \
	       -o perlcov.info $(COVER_DB)                           \
               --version-script $(VERSION_SCRIPT)                    \
	       $(EXCL_OPTS) $(OMIT_OPTS) $(IGNORE_OPTS)              \
               --filter region --include $(ROOT_DIR) ;               \
	  checkrc 'perl2lcov -o perlcov.info' $$? ;                  \
	  if [ -f $(PYCOV_DB) ] ; then                               \
	    $(PY2LCOV_TOOL) $(CAPTURE_OPTS) -o pycov.info $(PYCOV_DB)\
                 --version-script $(VERSION_SCRIPT) ;                \
	    checkrc 'py2lcov -o pycov.info' $$? ;                    \
	  fi ;                                                       \
	  if [ "x$(PER_TEST_COVERAGE)" != 'x' ] ; then               \
	    cp perlcov.info $(PER_TEST_COVERAGE) ;                   \
	    if [ -f $(PYCOV_DB) ] ; then                             \
	      cp pycov.info $(PER_TEST_COVERAGE) ;                   \
	    fi                                                       \
	  fi ;                                                       \
	  if ls $(LCOVLIBDIR)/*.gcda >/dev/null 2>&1 ; then          \
	    if [ "x$(ENABLE_MCDC)" != 'x1' ] ; then                  \
	      echo "*** NOTE: capturing XS coverage without MC/DC - '$(MCDC_CXX)'" ; \
	      echo "***   or the gcov on PATH is older than 14" ;    \
	    fi ;                                                     \
	    $(LCOV_TOOL) $(CAPTURE_OPTS) -c -d $(LCOVLIBDIR)         \
	        -o LcovUtil.info --branch $(MCDC_OPTS)               \
		--version-script $(VERSION_SCRIPT)                   \
		--rc c_file_extensions=xs,h,c,cpp,icc,hpp            \
		--filter brace,branch,exception,region$(MCDC_FILTER) \
		--exclude 'tests/*' --exclude scheduling             \
		--omit croak_xs --omit std::runtime_error            \
		--include $(LCOVLIBDIR)                              \
	        --ignore inconsistent,empty,unused ;                 \
	    if [ 0 != $$? ] ; then                                   \
	      rm -f LcovUtil.info ;                                  \
	      echo "*** WARNING: skipping XS coverage - cannot read the .gcda in $(LCOVLIBDIR) with:" ; \
	      gcov --version | head -1 ;                             \
	      echo "***   the extension's .gcda can only be read by the gcov matching the g++" ; \
	      echo "***   which compiled it" ;                        \
	    fi ;                                                     \
	  fi ;                                                       \
	fi ;                                                         \
	exit $$rc

report: excel info
	$(CHECK_RC)                                                  \
	if [ "x$(COVERAGE)" != 'x' ] ; then                          \
	  INFO="perlcov.info pycov.info" ;                           \
	  if [ -f LcovUtil.info ] ; then                             \
	     INFO="$$INFO LcovUtil.info" ;                           \
	  fi ;                                                       \
	  $(GENHTML_TOOL) --parallel -o $(HTML_RPT) $$INFO           \
              --save --title 'LCOV regression tests'                 \
              --show-navigation --flat --branch $(MCDC_OPTS)         \
	      --show-proportion                                      \
              --version-script $(VERSION_SCRIPT)                     \
	      --annotate-script $(ANNOTATE_SCRIPT)                   \
	      --filter region $(REPORT_OPTS)                         \
              --ignore empty,inconsistent --keep-going ;             \
	  checkrc 'genhtml -o $(HTML_RPT)' $$? ;                     \
	  if [ -d $(HTML_RPT) ] ; then                               \
	      cp $$INFO $(HTML_RPT) ;                                \
	      checkrc "cp $$INFO $(HTML_RPT)" $$? ;                  \
          fi ;                                                       \
	  echo "Wrote HTML report to ${HTML_RPT}" ;                  \
	fi ;                                                         \
	exit $$rc

clean: clean_echo clean_subdirs
	rm -f *.info *.log *.counts *.gcov test.log test.time report.xlsx \
	    $(PYCOV_DB)
	rm -rf $(COVER_DB) $(HTML_RPT) $(PER_TEST_COVERAGE) cover_db.d src
