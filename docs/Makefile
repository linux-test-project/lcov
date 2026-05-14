# Minimal makefile for Sphinx documentation
#

# You can set these variables from the command line.
RELEASE       ?= 2.5
TOOL_NAME     ?= LCOV
BUILD_DATE    ?= $(shell date +%Y-%m-%d)
SPHINXOPTS    ?= -D release=$(RELEASE) -D version=$(RELEASE) -D today=$(BUILD_DATE)
SPHINXBUILD   ?= sphinx-build
SOURCEDIR     = .
BUILDDIR      = _build

# Put it first so that "make" without argument is like "make help".
help:
	@LCOV_BUILD_DATE=$(BUILD_DATE) LCOV_RELEASE=$(RELEASE) TOOL_NAME=$(TOOL_NAME) $(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

.PHONY: help Makefile

# Catch-all target: route all unknown targets to Sphinx using the new
# "make mode" option.  $(O) is meant as a shortcut for $(SPHINXOPTS).
%: Makefile
	@LCOV_BUILD_DATE=$(BUILD_DATE) LCOV_RELEASE=$(RELEASE) TOOL_NAME=$(TOOL_NAME) $(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)
