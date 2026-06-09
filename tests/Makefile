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

TESTS := genhtml lcov llvm2lcov py2lcov perl2lcov xml2lcov

# there may or may not be some .info files generated for exported
#  tools - py2lcov, perl2lcov, etc.  We want them included in the
#  report - but they might not have been generated, so we need to
#  ignore the potential 'empty glob pattern' error message and a
#  potential remote repo timestamp issue
EXCLUDES = genError.pm filter.pl brokenCallback.pm MsgContext.pm \
	 missingRestore.pm parallelFail.pm 
EXCL_OPTS = $(foreach e, $(EXCLUDES), --exclude $(e))
OMIT_OPTS = --omit-lines 'ERROR_INTERNAL' --omit-lines '\bdie\b'
IGNORE_OPTS = --ignore unsupported,unused,inconsistent

excel:
	$(SPREADSHEET_TOOL) -o report.xlsx `find . -name "*.json"`

info:
	if [ "x$(COVERAGE)" != 'x' ] ; then                          \
	  if [ -d cover_db.d ] ; then                                \
	    rm -f cover_db.d/*.log ;                                 \
	    DBS=cover_db.d/* ;                                       \
	    cover -write $(COVER_DB) $$DBS 2>&1 > cover.log ;        \
	    if [ "x$(PER_TEST_COVERAGE)" != 'x' ] ; then             \
	      mkdir -p $(PER_TEST_COVERAGE) ;                        \
              for db in $$DBS ; do                                   \
	         echo ----- $$db ------------- ;                     \
	         cover $$db 2>&1 > $$db.log ;                        \
	         $(PERL2LCOV_TOOL)                                   \
	           -o $(PER_TEST_COVERAGE)/`basename $$db`_cov.info $$db \
                   --version-script $(VERSION_SCRIPT)                \
		   $(EXCL_OPTS) $(OMIT_OPTS) $(IGNORE_OPTS)          \
                   --filter region ;                                 \
	      done ;                                                 \
	      ( cd $(PER_TEST_COVERAGE);                             \
	        $(LCOV_TOOL) -o total.info                           \
		  --branch --keep-going                              \
		  --version-script $(VERSION_SCRIPT)                 \
		  $(foreach f, $(shell ls *.info), -a $$f)           \
	      ) ;                                                    \
	    fi ;                                                     \
	  fi ;                                                       \
	  cover $(COVER_DB) ;                                        \
	  $(PERL2LCOV_TOOL) -o perlcov.info $(COVER_DB)              \
               --version-script $(VERSION_SCRIPT)                    \
	       $(EXCL_OPTS) $(OMIT_OPTS) $(IGNORE_OPTS)              \
               --filter region ;                                     \
	  if [ -f $(PYCOV_DB) ] ; then                               \
	    $(PY2LCOV_TOOL) -o pycov.info $(PYCOV_DB)                \
                 --version-script $(VERSION_SCRIPT) ;                \
	  fi ;                                                       \
	  if [ "x$(PER_TEST_COVERAGE)" != 'x' ] ; then               \
	    cp perlcov.info $(PER_TEST_COVERAGE) ;                   \
	    if [ -f $(PYCOV_DB) ] ; then                             \
	      cp pycov.info $(PER_TEST_COVERAGE) ;                   \
	    fi                                                       \
	  fi                                                         \
	fi

report: excel info
	if [ "x$(COVERAGE)" != 'x' ] ; then                          \
	  $(GENHTML_TOOL) --parallel -o $(HTML_RPT)                  \
              perlcov.info pycov.info                                \
              --save --title 'LCOV regression tests'                 \
              --show-navigation --flat --branch --show-proportion    \
              --version-script $(VERSION_SCRIPT)                     \
	      --annotate-script $(ANNOTATE_SCRIPT)                   \
	      --filter region                                        \
              --ignore empty,inconsistent --keep-going ;             \
	  if [ -d $(HTML_RPT) ] ; then                               \
	      cp p*cov.info $(HTML_RPT) ;                            \
          fi ;                                                       \
	  echo "Wrote HTML report to ${HTML_RPT}" ;                  \
	fi

clean: clean_echo clean_subdirs
	rm -f *.info *.log *.counts *.gcov test.log test.time report.xlsx \
	    $(PYCOV_DB)
	rm -rf $(COVER_DB) $(HTML_RPT) $(PER_TEST_COVERAGE) cover_db.d src
