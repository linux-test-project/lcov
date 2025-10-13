ifeq ($(COVERAGE), 1)
ifeq ($(COVER_DB),)
export COVER_DB := $(shell echo `pwd`/cover_db)
export PYCOV_DB := $(shell echo `pwd`/pycov.dat)
export HTML_RPT := $(shell echo `pwd`/lcov_coverage)
endif
endif

.PHONY: report

all: check report

include common.mak

TESTS := genhtml lcov gendiffcov llvm2lcov py2lcov perl2lcov xml2lcov

# there may or may not be some .info files generated for exported
#  tools - py2lcov, perl2lcov, etc.  We want them included in the
#  report - but they might not have been generated, so we need to
#  ignore the potential 'empty glob pattern' error message and a
#  potential remote repo timestamp issue
report:
	$(SPREADSHEET_TOOL) -o report.xlsx `find . -name "*.json"`
	if [ "x$(COVERAGE)" != 'x' ] ; then                         \
	  cover $(COVER_DB) ;                                       \
	  $(BINDIR)/perl2lcov -o perlcov.info $(COVER_DB)           \
               --version-script $(VERSION_SCRIPT)                   \
	       --exclude genError.pm --exclude filter.pl            \
               --exclude brokenCallback.pm --exclude MsgContext.pm  \
	       --exclude missingRestore.pm --exclude parallelFail.pm \
               --omit-lines 'ERROR_INTERNAL' --omit-lines '\bdie\b' \
	       --ignore unsupported,unused,inconsistent             \
               --filter region ;                                    \
	  if [ -f $(PYCOV_DB) ] ; then                              \
	    $(BINDIR)/py2lcov -o pycov.info $(PYCOV_DB)             \
                 --version-script $(VERSION_SCRIPT) ;               \
	  fi ;                                                      \
	  $(BINDIR)/genhtml --parallel -o $(HTML_RPT)               \
              perlcov.info pycov.info                               \
              --save --title 'LCOV regression tests'                \
              --show-navigation --flat --branch --show-proportion   \
              --version-script $(VERSION_SCRIPT)                    \
	      --annotate-script $(ANNOTATE_SCRIPT)                  \
	      --filter region                                       \
              --ignore empty,inconsistent ;                         \
	  cp p*cov.info $(HTML_RPT) ;                               \
	  echo "Wrote HTML report to ${HTML_RPT}" ;                 \
	fi

clean:
	rm -rf *.info *.counts test.log src report.xlsx \
		$(COVER_DB) $(HTML_RPT) $(PYCOV_DB)
