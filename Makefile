#
# Makefile for the LTP GCOV extension (LCOV)
#
# Make targets:
#   - install:   install LCOV tools and man pages on the system
#   - uninstall: remove tools and man pages from the system
#   - dist:      create files required for distribution, i.e. the lcov.tar.gz
#                and the lcov.rpm file. Just make sure to adjust the VERSION
#                and RELEASE variables below - both version and date strings
#                will be updated in all necessary files.
#   - clean:     remove all generated files
#

VERSION := 1.1
RELEASE := 1
DATE    := $(shell date +%Y-%m-%d)

BIN_DIR := $(PREFIX)/usr/local/bin
MAN_DIR := $(PREFIX)/usr/share/man/man1
TMP_DIR := /tmp/lcov-tmp.$(shell echo $$$$)
FILES   := $(wildcard bin/*) $(wildcard man/*) README CHANGES Makefile \
	   $(wildcard rpm/*)

.PHONY: all info clean install uninstall

all: info

info:
	@echo try "'make install'", "'make uninstall'" or "'make dist'"

clean:
	rm -f lcov-*.tar.gz
	rm -f lcov-*.noarch.rpm
	make -C example clean

install:
	bin/install.sh bin/lcov $(BIN_DIR)/lcov
	bin/install.sh bin/genhtml $(BIN_DIR)/genhtml
	bin/install.sh bin/geninfo $(BIN_DIR)/geninfo
	bin/install.sh bin/genpng $(BIN_DIR)/genpng
	bin/install.sh bin/gendesc $(BIN_DIR)/gendesc
	bin/install.sh man/lcov.1 $(MAN_DIR)/lcov.1
	bin/install.sh man/genhtml.1 $(MAN_DIR)/genhtml.1
	bin/install.sh man/geninfo.1 $(MAN_DIR)/geninfo.1
	bin/install.sh man/genpng.1 $(MAN_DIR)/genpng.1
	bin/install.sh man/gendesc.1 $(MAN_DIR)/gendesc.1

uninstall:
	bin/install.sh --uninstall bin/lcov $(BIN_DIR)/lcov
	bin/install.sh --uninstall bin/genhtml $(BIN_DIR)/genhtml
	bin/install.sh --uninstall bin/geninfo $(BIN_DIR)/geninfo
	bin/install.sh --uninstall bin/genpng $(BIN_DIR)/genpng
	bin/install.sh --uninstall bin/gendesc $(BIN_DIR)/gendesc
	bin/install.sh --uninstall man/lcov.1 $(MAN_DIR)/lcov.1
	bin/install.sh --uninstall man/genhtml.1 $(MAN_DIR)/genhtml.1
	bin/install.sh --uninstall man/geninfo.1 $(MAN_DIR)/geninfo.1
	bin/install.sh --uninstall man/genpng.1 $(MAN_DIR)/genpng.1
	bin/install.sh --uninstall man/gendesc.1 $(MAN_DIR)/gendesc.1

dist: lcov-$(VERSION).tar.gz lcov-$(VERSION)-$(RELEASE).noarch.rpm

lcov-$(VERSION).tar.gz: $(FILES)
	mkdir $(TMP_DIR)
	mkdir $(TMP_DIR)/lcov-$(VERSION)
	cp -r * $(TMP_DIR)/lcov-$(VERSION)
	make -C $(TMP_DIR)/lcov-$(VERSION) clean
	bin/updateversion.pl $(TMP_DIR)/lcov-$(VERSION) $(VERSION) $(DATE)
	cd $(TMP_DIR) ; \
	tar cfz $(TMP_DIR)/lcov-$(VERSION).tar.gz lcov-$(VERSION)
	mv $(TMP_DIR)/lcov-$(VERSION).tar.gz .
	rm -rf $(TMP_DIR)

lcov-$(VERSION)-$(RELEASE).noarch.rpm: lcov-$(VERSION).tar.gz
	mkdir $(TMP_DIR)
	mkdir $(TMP_DIR)/BUILD
	mkdir $(TMP_DIR)/RPMS
	mkdir $(TMP_DIR)/SOURCES
	cp lcov-$(VERSION).tar.gz $(TMP_DIR)/SOURCES
	rpmbuild --define '_topdir $(TMP_DIR)' \
		 --define 'LCOV_VERSION $(VERSION)' \
		 --define 'LCOV_RELEASE $(RELEASE)' -bb rpm/lcov.spec
	mv $(TMP_DIR)/RPMS/noarch/lcov-$(VERSION)-$(RELEASE).noarch.rpm .
	rm -rf $(TMP_DIR)
