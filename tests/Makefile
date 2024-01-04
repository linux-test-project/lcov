ifeq ($(COVERAGE), 1)
ifeq ($(COVER_DB),)
export COVER_DB := $(shell `pwd`/cover_db)
export HTML_RPT := $(shell `pwd`/perlcov)
endif
endif

.PHONY: report

all: check report

include common.mak

TESTS := genhtml lcov gendiffcov py2lcov perl2lcov

# there may or may not be some .info files generated for exported
#  tools - py2lcov, perl2lcov, etc.  We want them included in the
#  report - but they might not have been generated, so we need to
#  ignore the potential 'empty glob pattern' error message
report:
	if [ "x$(COVERAGE)" != 'x' ] ; then \
	  cover ; \
	  $(BINDIR)/perl2lcov -o perlcov.info $(COVER_DB) --version-script $(VERSION_SCRIPT) ; \
	  $(BINDIR)/genhtml -o $(HTML_RPT) perlcov.info $(COVER_DB)/*.info --show-navigation --flat --branch --show-proportion --version-script $(VERSION_SCRIPT) --annotate-script $(ANNOTATE_SCRIPT) --ignore empty,version ; \
	fi

clean:
	rm -rf *.info *.counts test.log src
ifeq ($(COVERAGE), 1)
	if [ "x$(COVER_DB)" != 'x' ] ; then rm -rf $(COVER_DB) ; fi
	if [ "x$(HTML_RPT)" != 'x' ] ; then rm -rf $(HTML_RPT) ; fi
endif
