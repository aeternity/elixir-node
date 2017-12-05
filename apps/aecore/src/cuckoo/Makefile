EXECUTABLES = \
	$(CURDIR)/bin/mean16 \
	$(CURDIR)/bin/lean16 \
	$(CURDIR)/bin/verify16 \
	$(CURDIR)/bin/mean28 \
	$(CURDIR)/bin/lean28 \
	$(CURDIR)/bin/verify28 \
	$(CURDIR)/bin/mean30 \
	$(CURDIR)/bin/lean30 \
	$(CURDIR)/bin/verify30

CURDIR := $(abspath $(shell pwd)/../../priv/cuckoo)
LIBBLAKE = $(CURDIR)/lib/libblake2b.so

SRC_EXECUTABLES = $(subst $(CURDIR)/bin, c_src/src, $(EXECUTABLES))

SRC_LIBBLAKE = $(subst $(CURDIR)/lib, c_src/src, $(LIBBLAKE))

SRC_ARCH_FLAGS = -m64

REPO = https://github.com/aeternity/cuckoo.git
COMMIT = d1b8b77

.PHONY: all
all: $(LIBBLAKE) $(EXECUTABLES)
	@: # Silence the `Nothing to be done for 'all'.` message when running `make all`.

.PHONY: clean
clean:
	rm -f $(SRC_EXECUTABLES) $(EXECUTABLES) $(SRC_LIBBLAKE) $(LIBBLAKE)

.PHONY: distclean
distclean:
	rm -rf c_src priv

# Use `.LOW_RESOLUTION_TIME` for preventing unnecessary target
# recomputation caused by inability of `cp -p `to set high resolution
# timestamp on certain filesystems.
.LOW_RESOLUTION_TIME: $(LIBBLAKE)
$(LIBBLAKE): $(SRC_LIBBLAKE) | $(CURDIR)/lib
	cp -p $< $@

# Use `.LOW_RESOLUTION_TIME` for preventing unnecessary target
# recomputation caused by inability of `cp -p `to set high resolution
# timestamp on certain filesystems.
.LOW_RESOLUTION_TIME: $(EXECUTABLES)
$(EXECUTABLES): $(CURDIR)/bin/%: c_src/src/% | $(CURDIR)/bin
	cp -p $< $@

$(CURDIR) $(CURDIR)/lib $(CURDIR)/bin:
	mkdir -p $@

# Do not silence the recursive make call, in order to show compiler
# flags used.
$(SRC_LIBBLAKE): | c_src/.git
	( cd $(@D) && \
		$(MAKE) $(@F) \
			GCC_ARCH_FLAGS=$(SRC_ARCH_FLAGS) \
			GPP_ARCH_FLAGS=$(SRC_ARCH_FLAGS); )

# Do not silence the recursive make call, in order to show compiler
# flags used.
$(SRC_EXECUTABLES): c_src/src/%: | c_src/.git
	( cd $(@D) && \
		$(MAKE) libblake2b.so $* \
			GCC_ARCH_FLAGS=$(SRC_ARCH_FLAGS) \
			GPP_ARCH_FLAGS=$(SRC_ARCH_FLAGS); )

# Clone without checking out, so that recipe interrupted after clone
# does not leave working directory distinct from the expected commit.
c_src/.git:
	git clone -n $(REPO) $(@D)
	( cd $(@D) && git checkout $(COMMIT); )
