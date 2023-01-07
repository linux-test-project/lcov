#
# Makefile for LCOV
#
# Make targets:
#   - install:   install LCOV tools and man pages on the system
#   - uninstall: remove tools and man pages from the system
#   - dist:      create files required for distribution, i.e. the lcov.tar.gz
#                and the lcov.rpm file. Just make sure to adjust the VERSION
#                and RELEASE variables below - both version and date strings
#                will be updated in all necessary files.
#   - checkstyle: check source files for coding style issues
#                 MODE=(full|diff) [UPDATE=1]
#   - clean:     remove all generated files
#   - release:   finalize release and create git tag for specified VERSION
#   - test:      run regression tests.
#                additional Make variables:
#                  COVERGAGE=1
#                     - enable perl coverage data collection
#                  TESTCASE_ARGS=string
#                     - pass these arguments to testcase script
#                       Sample args:
#                          --update      - overwrite GOLD file with
#                                          result
#                          --parallel n  - use --parallel flag
#                          --home path   - path to lcov script
#                          --llvm        - use LLVM rather than gcc
#                         --keep-going  - don't stop on error
#                   Note that not all tests have been updated to use
#                   all flags

VERSION := $(shell bin/get_version.sh --version)
RELEASE := $(shell bin/get_version.sh --release)
FULL    := $(shell bin/get_version.sh --full)

# Set this variable during 'make install' to specify the Perl interpreter used in
# installed scripts, or leave empty to keep the current interpreter.
export LCOV_PERL_PATH := /usr/bin/perl

PREFIX  := /usr/local

CFG_DIR := $(PREFIX)/etc
BIN_DIR := $(PREFIX)/bin
LIB_DIR := $(PREFIX)/lib
MAN_DIR := $(PREFIX)/share/man
SCRIPT_DIR := $(PREFIX)/share/lcov/support-scripts
TMP_DIR := $(shell mktemp -d)
FILES   := $(wildcard bin/*) $(wildcard man/*) README Makefile \
	   $(wildcard rpm/*) lcovrc

EXES = lcov genhtml geninfo genpng gendesc
SCRIPTS = p4udiff p4annotate getp4version get_signature gitblame gitdiff \
	criteria analyzeInfoFiles spreadsheet.py
LIBS = lcovutil
MANPAGES = man1/lcov.1 man1/genhtml.1 man1/geninfo.1 man1/genpng.1 \
	man1/gendesc.1 man5/lcovrc.5

# Program for checking coding style
CHECKSTYLE = $(CURDIR)/bin/checkstyle.sh


.PHONY: all info clean install uninstall rpms test

all: info

info:
	@echo "Available make targets:"
	@echo "  install   : install binaries and man pages in DESTDIR (default /)"
	@echo "  uninstall : delete binaries and man pages from DESTDIR (default /)"
	@echo "  dist      : create packages (RPM, tarball) ready for distribution"
	@echo "  check     : perform self-tests"
	@echo "  checkstyle: check source files for coding style issues"
	@echo "  release   : finalize release and create git tag for specified VERSION"
	@echo "  test      : same as 'make check"

clean:
	rm -f lcov-*.tar.gz
	rm -f lcov-*.rpm
	make -C example clean
	make -C tests -s clean
	find . -name '*.tdy' -o -name '*.orig' | xargs rm -f

install:
	for b in $(EXES) ; do \
		bin/install.sh bin/$$b $(DESTDIR)$(BIN_DIR)/$$b -m 755 ; \
		bin/updateversion.pl $(DESTDIR)$(BIN_DIR)/$$b $(VERSION) $(RELEASE) $(FULL) ; \
	done
	for s in $(SCRIPTS) ; do \
		bin/install.sh bin/$$s $(DESTDIR)$(SCRIPT_DIR)/$$s -m 755 ; \
	done
	for l in $(LIBS) ; do \
		bin/install.sh lib/$${l}.pm $(DESTDIR)$(LIB_DIR)/$${l}.pm -m 755 ; \
		bin/updateversion.pl $(DESTDIR)$(LIB_DIR)/$${l}.pm $(VERSION) $(RELEASE) $(FULL) ; \
	done
	for m in $(MANPAGES) ; do \
		bin/install.sh man/`basename $$m` $(DESTDIR)$(MAN_DIR)/$$m -m 644 ; \
		bin/updateversion.pl $(DESTDIR)$(MAN_DIR)/$$m $(VERSION) $(RELEASE) $(FULL) ; \
	done

	bin/install.sh lcovrc $(DESTDIR)$(CFG_DIR)/lcovrc -m 644

uninstall:
	for b in $(EXES) ; do \
		bin/install.sh --uninstall bin/$$b $(DESTDIR)$(BIN_DIR)/$$b ; \
	done
	for s in $(SCRIPTS) ; do \
		bin/install.sh --uninstall bin/$$s $(DESTDIR)$(SCRIPT_DIR)/$$s ; \
	done
	for l in $(LIBS) ; do \
		bin/install.sh --uninstall lib/$${l}.pm $(DESTDIR)$(LIB_DIR)/$${l}.pm ; \
	done
	for m in $(MANPAGES) ; do \
		bin/install.sh --uninstall man/`basename $$m` $(DESTDIR)$(MAN_DIR)/$$m ; \
	done
	bin/install.sh --uninstall lcovrc $(DESTDIR)$(CFG_DIR)/lcovrc

dist: lcov-$(VERSION).tar.gz lcov-$(VERSION)-$(RELEASE).noarch.rpm \
      lcov-$(VERSION)-$(RELEASE).src.rpm

lcov-$(VERSION).tar.gz: $(FILES)
	mkdir -p $(TMP_DIR)/lcov-$(VERSION)
	cp -r * $(TMP_DIR)/lcov-$(VERSION)
	bin/copy_dates.sh . $(TMP_DIR)/lcov-$(VERSION)
	make -C $(TMP_DIR)/lcov-$(VERSION) clean
	bin/updateversion.pl $(TMP_DIR)/lcov-$(VERSION) $(VERSION) $(RELEASE) $(FULL)
	bin/get_changes.sh > $(TMP_DIR)/lcov-$(VERSION)/CHANGES
	cd $(TMP_DIR) ; \
	tar cfz $(TMP_DIR)/lcov-$(VERSION).tar.gz lcov-$(VERSION) \
	    --owner root --group root
	mv $(TMP_DIR)/lcov-$(VERSION).tar.gz .
	rm -rf $(TMP_DIR)

lcov-$(VERSION)-$(RELEASE).noarch.rpm: rpms
lcov-$(VERSION)-$(RELEASE).src.rpm: rpms

rpms: lcov-$(VERSION).tar.gz
	mkdir -p $(TMP_DIR)
	mkdir $(TMP_DIR)/BUILD
	mkdir $(TMP_DIR)/RPMS
	mkdir $(TMP_DIR)/SOURCES
	mkdir $(TMP_DIR)/SRPMS
	cp lcov-$(VERSION).tar.gz $(TMP_DIR)/SOURCES
	( \
	  cd $(TMP_DIR)/BUILD ; \
	  tar xfz ../SOURCES/lcov-$(VERSION).tar.gz \
		lcov-$(VERSION)/rpm/lcov.spec \
	)
	rpmbuild --define '_topdir $(TMP_DIR)' --define '_buildhost localhost' \
		 --undefine vendor --undefine packager \
		 -ba $(TMP_DIR)/BUILD/lcov-$(VERSION)/rpm/lcov.spec
	mv $(TMP_DIR)/RPMS/noarch/lcov-$(VERSION)-$(RELEASE).noarch.rpm .
	mv $(TMP_DIR)/SRPMS/lcov-$(VERSION)-$(RELEASE).src.rpm .
	rm -rf $(TMP_DIR)

ifeq ($(COVERAGE), 1)
# write to .../tests/cover_db
export COVER_DB := ./cover_db
endif
export TESTCASE_ARGS COVER_DB

test: check

check:
	if [ "x$(COVERAGE)" != 'x' ] && [ ! -d tests/$(COVER_DB) ]; then \
	  mkdir tests/$(COVER_DB) ; \
	fi
	@$(MAKE) -s -C tests check
	if [ "x$(COVERAGE)" != 'x' ] ; then \
	  ( cd tests ; cover ) ; \
	fi

# Files to be checked for coding style issue issues -
#   - anything containing "#!/usr/bin/env perl" or the like
#   - anything named *.pm - expected to be perl module
# ... as long as the name doesn't end in .tdy or .orig
checkstyle:
ifeq ($(MODE),full)
	@echo "Checking source files for coding style issues (MODE=full):"
else
	@echo "Checking changes in source files for coding style issues (MODE=diff):"
endif
	@RC=0 ;                                                  \
	CHECKFILES=`find . -path ./.git -prune -o \( \( -type f -exec grep -q '^\#!.*perl' {} \; \) -o -name '*.pm' \) -not \( -name '*.tdy' -o -name '*.orig' -o -name '*~' \) -print `; \
	for FILE in $$CHECKFILES ; do                            \
	  $(CHECKSTYLE) "$$FILE";                                \
	  if [ 0 != $$? ] ; then                                 \
	    RC=1;                                                \
	    echo "saw mismatch for $$FILE";                      \
	    if [[ -f $$FILE.tdy && "$(UPDATE)x" != 'x' ]] ; then \
	      echo "updating $$FILE";                            \
	      mv $$FILE $$FILE.orig;                             \
	      mv $$FILE.tdy $$FILE ;                             \
            fi                                                   \
	  fi                                                     \
	done ;                                                   \
	exit $$RC

release:
	@if [ "$(origin VERSION)" != "command line" ] ; then echo "Please specify new version number, e.g. VERSION=1.16" >&2 ; exit 1 ; fi
	@if [ -n "$$(git status --porcelain 2>&1)" ] ; then echo "The repository contains uncommited changes" >&2 ; exit 1 ; fi
	@if [ -n "$$(git tag -l v$(VERSION))" ] ; then echo "A tag for the specified version already exists (v$(VERSION))" >&2 ; exit 1 ; fi
	@echo "Preparing release tag for version $(VERSION)"
	git checkout master
	bin/copy_dates.sh . .
	for FILE in README man/* rpm/* lib/* ; do \
		bin/updateversion.pl "$$FILE" $(VERSION) 1 $(VERSION) ; \
	done
	git commit -a -s -m "lcov: Finalize release $(VERSION)"
	git tag v$(VERSION) -m "LCOV version $(VERSION)"
	@echo "**********************************************"
	@echo "Release tag v$(VERSION) successfully created"
	@echo "Next steps:"
	@echo " - Review resulting commit and tag"
	@echo " - Publish with: git push origin master v$(VERSION)"
	@echo "**********************************************"
