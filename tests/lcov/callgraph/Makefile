include ../../common.mak

# The 'format' test needs to be split into multiple parts to more evenly
# balance test execution time, and especially to enable better parallelism.
# Each part runs in a unique working directory (format<N>.d) and builds the
# shared inputs via setup_common.sh, so they cannot collide.
TESTS := \
  collapse.sh \
  format1.sh \
  format2.sh \
  format3.sh \
  aliases.sh \
  resolve.sh \
  usage.sh \
  empty.sh \
  geninfo.sh \
  unsupported.sh \
  differential.sh \
  summary.sh \
  attribution.sh

clean:
	for t in $(TESTS) ; do ./$$t --clean ; done
