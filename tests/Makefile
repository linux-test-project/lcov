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

TESTS := genhtml lcov gendiffcov py2lcov perl2lcov

# there may or may not be some .info files generated for exported
#  tools - py2lcov, perl2lcov, etc.  We want them included in the
#  report - but they might not have been generated, so we need to
#  ignore the potential 'empty glob pattern' error message and a
#  potential remote repo timestamp issue
report:
	if [ "x$(COVERAGE)" != 'x' ] ; then \
	  cover ; \
	  $(BINDIR)/perl2lcov -o perlcov.info $(COVER_DB) --version-script $(VERSION_SCRIPT) ; \
	  if [ -f $(PYCOV_DB) ] ; then \
	    $(BINDIR)/py2lcov -o pycov.info $(PYCOV_DB) --version-script $(VERSION_SCRIPT) ; \
	  fi ; \
	  $(BINDIR)/genhtml -o $(HTML_RPT) perlcov.info pycov.i* $(COVER_DB)/*.info --show-navigation --flat --branch --show-proportion --version-script $(VERSION_SCRIPT) --annotate-script $(ANNOTATE_SCRIPT) --ignore empty,inconsistent ; \
	  echo "Wrote HTML report to ${HTML_RPT}" ; \
	fi

clean:
	rm -rf *.info *.counts test.log src
ifeq ($(COVERAGE), 1)
	if [ "x$(COVER_DB)" != 'x' ] ; then rm -rf $(COVER_DB) ; fi
	if [ "x$(HTML_RPT)" != 'x' ] ; then rm -rf $(HTML_RPT) ; fi
endif
