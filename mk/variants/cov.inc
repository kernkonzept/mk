# -*- Makefile -*-
# vim:set ft=make:

COV_FLAGS_gcc             = -ftest-coverage -fprofile-arcs
COV_FLAGS_clang           = -fprofile-instr-generate -fcoverage-mapping \
                            $(if $(NO_ATOMIC_COV),,-mllvm -instrprof-atomic-counter-update-all)
COV_FLAGS                 = $(COV_FLAGS_$(BID_COMPILER_TYPE))

CFLAGS-variant-cov       += $(COV_FLAGS)
CXXFLAGS-variant-cov     += $(COV_FLAGS)

PKGDEPS_FLAGS-variant-cov = -M cov $(COV_COMPONENTS) -ME -D cov libcov -DE

DS_API = $(if $(filter sigma0,$(MODE)),,1)
NO_ABI = $(if $(filter $(SYSTEMS_PLAIN),$(SYSTEMS)),1)

COV_VARIANT = $(if $(NO_ABI),-noabi,$(if $(DS_API),-ds))

define generate_cov_rules
COV_PATH_TARGET-$(1) := $(addsuffix -covpath.o, $(1))
$$(COV_PATH_TARGET-$(1)):
	@$$(COMP_MESSAGE)
	$(VERBOSE)echo 'CHAR CONST *__cov_path="$(pwd)/$(1)";' | $(CC) -o $$@ -c -xc -
$(1): $$(COV_PATH_TARGET-$(1))
LDFLAGS_$(1) += -PClibcov$(COV_VARIANT) $$(COV_PATH_TARGET-$(1))
endef

define PROG_TARGET_HOOK-variant-cov
$(foreach b,$(TARGET),$(eval $(call generate_cov_rules,$(b))))
endef

DEFINES-variant-cov   += -DL4_COV_ENABLED
BID_DEFINE-variant-cov = BID_VARIANT_FLAG_COV=y
