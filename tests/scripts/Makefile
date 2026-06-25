ifeq ($(COVERAGE), 1)
ifeq ($(COVER_DB),)
export COVER_DB := $(shell pwd)/cover_db
export PYCOV_DB := $(shell pwd)/pycov.dat
endif
endif

include ../common.mak

# separate lines - so new tests can be added without conflict
TESTS := \
  gitblame_test.sh \
  gitdiff_test.sh \
  gitversion_test.sh \
  batchgitversion_test.sh \
  p4annotate_test.sh \
  p4udiff_test.sh \
  p4version_test.sh

# runtests.py resolves test names relative to TOPDIR (tests/).
# When invoked directly from this subdirectory, prefix each name with
# the relative path from TOPDIR to here so the scripts can be found.
RELPREFIX := $(patsubst %/,%,$(TESTDIR:$(TOPDIR)%=%))
PREFIXED_TESTS := $(addprefix $(RELPREFIX)/,$(TESTS))

check:
	$(TOPDIR)/bin/runtests.py $(PREFIXED_TESTS) $(OPTS)
ifneq ($(COVER_DB),)
	if [ -d $(TOPDIR)/cover_db.d ] ; then                          \
	  cover -write $(COVER_DB) $(TOPDIR)/cover_db.d/* 2>&1 ;       \
	  cover $(COVER_DB) ;                                          \
	  $(PERL2LCOV_TOOL) -o $(COVER_DB)/perlcov.info $(COVER_DB)    \
	    --ignore-errors unsupported,unused,inconsistent,empty      \
	    --keep-going ;                                             \
	  if [ -f $(COVER_DB)/perlcov.info ] ; then                    \
	    $(GENHTML_TOOL) -o $(COVER_DB)/report $(COVER_DB)/perlcov.info \
	      --flat --show-navigation --branch                        \
	      --ignore-errors inconsistent,corrupt --keep-going ;      \
	  fi ;                                                         \
	fi
endif

clean:
	rm -f *.log
	rm -rf cover_db cover_db.dat cover_db.dat_py

.PHONY: check clean
