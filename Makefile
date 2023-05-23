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

# Set this variable during 'make install' to specify the interpreters used in
# installed scripts, or leave empty to keep the current interpreter.
export LCOV_PERL_PATH   := /usr/bin/perl
export LCOV_PYTHON_PATH := /usr/bin/python3

PREFIX  := /usr/local

CFG_DIR := $(PREFIX)/etc
BIN_DIR := $(PREFIX)/bin
LIB_DIR := $(PREFIX)/lib/lcov
MAN_DIR := $(PREFIX)/share/man
SCRIPT_DIR := $(PREFIX)/share/lcov/support-scripts
TMP_DIR := $(shell mktemp -d)
FILES   := $(wildcard bin/*) $(wildcard man/*) README Makefile \
	   $(wildcard rpm/*) lcovrc

EXES = lcov genhtml geninfo genpng gendesc
SCRIPTS = p4udiff p4annotate getp4version get_signature gitblame gitdiff \
	criteria analyzeInfoFiles spreadsheet.py py2lcov
LIBS = lcovutil.pm
MANPAGES = man1/lcov.1 man1/genhtml.1 man1/geninfo.1 man1/genpng.1 \
	man1/gendesc.1 man5/lcovrc.5

# Program for checking coding style
CHECKSTYLE = $(CURDIR)/bin/checkstyle.sh

INSTALL = install
FIX = $(realpath bin/fix.pl)
RM = rm

export V
ifeq ("${V}","1")
	echocmd=
else
	echocmd=echo $1 ;
.SILENT:
endif

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
	$(call echocmd,"  CLEAN   lcov")
	rm -f lcov-*.tar.gz
	rm -f lcov-*.rpm
	$(MAKE) -C example -s clean
	$(MAKE) -C tests -s clean
	find . -name '*.tdy' -o -name '*.orig' | xargs rm -f

install:
	$(INSTALL) -d -m 755 $(DESTDIR)$(BIN_DIR)
	for b in $(EXES) ; do \
		$(call echocmd,"  INSTALL $(DESTDIR)$(BIN_DIR)/$$b") \
		$(INSTALL) -m 755 bin/$$b $(DESTDIR)$(BIN_DIR)/$$b ; \
		$(FIX) --version $(VERSION) --release $(RELEASE) \
		       --libdir $(LIB_DIR) --bindir $(BIN_DIR) \
		       --fixinterp --fixver --fixlibdir --fixbindir \
		       --exec $(DESTDIR)$(BIN_DIR)/$$b ; \
	done
	$(INSTALL) -d -m 755 $(DESTDIR)$(SCRIPT_DIR)
	for s in $(SCRIPTS) ; do \
		$(call echocmd,"  INSTALL $(DESTDIR)$(SCRIPT_DIR)/$$s") \
		$(INSTALL) -m 755 bin/$$s $(DESTDIR)$(SCRIPT_DIR)/$$s ; \
		$(FIX) --version $(VERSION) --release $(RELEASE) \
		       --libdir $(LIB_DIR) --bindir $(BIN_DIR) \
		       --fixinterp --fixver --fixlibdir --fixbindir \
		       --exec $(DESTDIR)$(SCRIPT_DIR)/$$s ; \
	done
	$(INSTALL) -d -m 755 $(DESTDIR)$(LIB_DIR)
	for l in $(LIBS) ; do \
		$(call echocmd,"  INSTALL $(DESTDIR)$(LIB_DIR)/$$l") \
		$(INSTALL) -m 644 lib/$$l $(DESTDIR)$(LIB_DIR)/$$l ; \
		$(FIX) --version $(VERSION) --release $(RELEASE) \
		       --libdir $(LIB_DIR) --bindir $(BIN_DIR) \
		       --fixinterp --fixver --fixlibdir --fixbindir \
		       --exec $(DESTDIR)$(LIB_DIR)/$$l ; \
	done
	$(INSTALL) -d -m 755 $(DESTDIR)$(MAN_DIR)/man1
	$(INSTALL) -d -m 755 $(DESTDIR)$(MAN_DIR)/man5
	for m in $(MANPAGES) ; do \
		$(call echocmd,"  INSTALL $(DESTDIR)$(MAN_DIR)/$$m") \
		$(INSTALL) -m 644 man/`basename $$m` $(DESTDIR)$(MAN_DIR)/$$m ; \
		$(FIX) --version $(VERSION) --fixver --fixdate \
		       --fixscriptdir --scriptdir $(SCRIPT_DIR) \
		       --manpage $(DESTDIR)$(MAN_DIR)/$$m ; \
	done
	$(INSTALL) -d -m 755 $(DESTDIR)$(CFG_DIR)
	$(call echocmd,"  INSTALL $(DESTDIR)$(CFG_DIR)/lcovrc")
	$(INSTALL) -m 644 lcovrc $(DESTDIR)$(CFG_DIR)/lcovrc

uninstall:
	for b in $(EXES) ; do \
		$(call echocmd,"  UNINST  $(DESTDIR)$(BIN_DIR)/$$b") \
		$(RM) -f $(DESTDIR)$(BIN_DIR)/$$b ; \
	done
	for s in $(SCRIPTS) ; do \
		$(call echocmd,"  UNINST  $(DESTDIR)$(SCRIPT_DIR)/$$s")  \
		$(RM) -f $(DESTDIR)$(SCRIPT_DIR)/$$s ; \
	done
	for l in $(LIBS) ; do \
		$(call echocmd,"  UNINST  $(DESTDIR)$(LIB_DIR)/$$l") \
		$(RM) -f $(DESTDIR)$(LIB_DIR)/$$l ; \
	done
	for m in $(MANPAGES) ; do \
		$(call echocmd,"  UNINST  $(DESTDIR)$(MAN_DIR)/$$m") \
		$(RM) -f $(DESTDIR)$(MAN_DIR)/$$m ; \
	done
	$(call echocmd,"  UNINST  $(DESTDIR)$(CFG_DIR)/lcovrc")
	$(RM) -f $(DESTDIR)$(CFG_DIR)/lcovrc

dist: lcov-$(VERSION).tar.gz lcov-$(VERSION)-$(RELEASE).noarch.rpm \
      lcov-$(VERSION)-$(RELEASE).src.rpm

lcov-$(VERSION).tar.gz: $(FILES)
	$(call echocmd,"  DIST    lcov-$(VERSION).tar.gz")
	mkdir -p $(TMP_DIR)/lcov-$(VERSION)
	cp -r . $(TMP_DIR)/lcov-$(VERSION)
	rm -rf $(TMP_DIR)/lcov-$(VERSION)/.git
	bin/copy_dates.sh . $(TMP_DIR)/lcov-$(VERSION)
	$(MAKE) -s -C $(TMP_DIR)/lcov-$(VERSION) clean >/dev/null
	cd $(TMP_DIR)/lcov-$(VERSION) ; \
	$(FIX) --version $(VERSION) --release $(RELEASE) \
	       --verfile .version --fixver --fixdate \
	       $(patsubst %,bin/%,$(EXES)) $(patsubst %,bin/%,$(SCRIPTS)) \
	       $(patsubst %,lib/%,$(LIBS)) \
	       $(patsubst %,man/%,$(notdir $(MANPAGES))) README rpm/lcov.spec
	bin/get_changes.sh > $(TMP_DIR)/lcov-$(VERSION)/CHANGES
	cd $(TMP_DIR) ; \
	tar cfz $(TMP_DIR)/lcov-$(VERSION).tar.gz lcov-$(VERSION) \
	    --owner root --group root
	mv $(TMP_DIR)/lcov-$(VERSION).tar.gz .
	rm -rf $(TMP_DIR)

lcov-$(VERSION)-$(RELEASE).noarch.rpm: rpms
lcov-$(VERSION)-$(RELEASE).src.rpm: rpms

rpms: lcov-$(VERSION).tar.gz
	$(call echocmd,"  DIST    lcov-$(VERSION)-$(RELEASE).noarch.rpm")
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
		 -ba $(TMP_DIR)/BUILD/lcov-$(VERSION)/rpm/lcov.spec --quiet
	mv $(TMP_DIR)/RPMS/noarch/lcov-$(VERSION)-$(RELEASE).noarch.rpm .
	$(call echocmd,"  DIST    lcov-$(VERSION)-$(RELEASE).src.rpm")
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
	CHECKFILES=`find . -path ./.git -prune -o \( \( -type f -exec grep -q '^#!.*perl' {} \; \) -o -name '*.pm' \) -not \( -name '*.tdy' -o -name '*.orig' -o -name '*~' \) -print `; \
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
	$(FIX) --version $(VERSION) --release $(RELEASE) \
	       --fixver --fixdate $(patsubst %,man/%,$(notdir $(MANPAGES))) \
	       README rpm/lcov.spec
	git commit -a -s -m "lcov: Finalize release $(VERSION)"
	git tag v$(VERSION) -m "LCOV version $(VERSION)"
	@echo "**********************************************"
	@echo "Release tag v$(VERSION) successfully created"
	@echo "Next steps:"
	@echo " - Review resulting commit and tag"
	@echo " - Publish with: git push origin master v$(VERSION)"
	@echo "**********************************************"

