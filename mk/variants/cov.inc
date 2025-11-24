# -*- Makefile -*-
# vim:set ft=make:

COV_FLAGS_gcc             = -ftest-coverage -fprofile-arcs
COV_FLAGS_clang           = -fprofile-instr-generate -fcoverage-mapping -fcoverage-mcdc \
                            $(if $(NO_ATOMIC_COV),,-mllvm -instrprof-atomic-counter-update-all)
COV_FLAGS                 = $(COV_FLAGS_$(BID_COMPILER_TYPE))

CFLAGS-variant-cov       += $(COV_FLAGS)
CXXFLAGS-variant-cov     += $(COV_FLAGS)

# We want all test packages to be built for coverage. But at the time of
# generating the dependency tree we don't know which packages contain tests. So
# we generate a .Packages.tests file in the object directory that contains all
# packages in the tests directory.
$(OBJ_BASE)/.Packages.tests:
	$(VERBOSE)echo "TEST_PACKAGES = $(shell find $(SRC_DIR)/tests -name '.git' $\
	                                             -prune -o -name Control -type f $\
	                                             -printf 'tests/%P\n' $\
	                                        | sed 's#/Control$$##')" > $@

include $(OBJ_BASE)/.Packages.tests

COV_COMPONENTS += $(TEST_PACKAGES)

$(OBJ_BASE)/.Package.deps: $(OBJ_BASE)/.Packages.tests

# Add coverage modification to all cov components
PKGDEPS_FLAGS-variant-cov  = -M cov $(COV_COMPONENTS) -ME -D cov libcov -DE

# Add libumalloc as dependency for bootstrap and sigma0
PKGDEPS_FLAGS-variant-cov += -E pkg/bootstrap libumalloc -EE
PKGDEPS_FLAGS-variant-cov += -E pkg/l4re-core/sigma0 libumalloc -EE

NO_ABI = $(if $(filter $(SYSTEMS_PLAIN),$(SYSTEMS)),1)

define generate_cov_rules
COV_PATH_TARGET-$(1) := $(addsuffix -covpath.o, $(1))
$$(COV_PATH_TARGET-$(1)):
	@$$(COMP_MESSAGE)
	$(VERBOSE)echo 'char const *__COV_PATH="$(OBJ_DIR)/OBJ-$(SYSTEM)/$(1)";' | $(CC) -o $$@ -c -xc -
$(1): $$(COV_PATH_TARGET-$(1))

# Packages with both, libraries and progs might end up with a cov variant
# becasuse of dependencies on the library. There is, however, no dependency on
# the libcov, which might lead to errors when trying to link the prog. That's
# why we have to check again whether to link against libcov.
LDFLAGS_$(1) += $$(if $$(or $(filter $(abspath $(PKGDIR)),$(COV_COMPONENTS_ABS)),\
                            $$(filter test.mk,$$(ROLE))),-PClibcov) \
                $(if $(filter sigma0,$(MODE))$(DS_API),-PClibumalloc) $$(COV_PATH_TARGET-$(1))
endef

define PROG_TARGET_HOOK-variant-cov
$(foreach b,$(TARGET),$(eval $(call generate_cov_rules,$(b))))
endef

DEFINES-variant-cov   += -DL4_COV_ENABLED
BID_DEFINE-variant-cov = BID_VARIANT_FLAG_COV=y
