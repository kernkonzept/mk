# vim: ft=make


# Only include this file once
ifeq ($(origin _L4DIR_MK_VARIANTS),undefined)
_L4DIR_MK_VARIANTS=y

include $(OBJ_BASE)/.Package.deps

ifeq ($(filter-out prog.mk test.mk, $(ROLE)),)
  VARIANTS ?= std
endif

# Building variants:
ifeq ($(filter-out lib.mk prog.mk test.mk assets.mk, $(ROLE)),)

  VARIANTS_lib.mk += std
  # If there is a variants variable for the src dir, we use it. Otherwise, we
  # fall back to the pkgdir one. If there is neither, use std.
  SRC_VARIANTS    += $(VARIANTS_$(SRC_DIR:$(L4DIR_ABS)/%=%))
  PKGDIR_VARIANTS  = $(VARIANTS_$(PKGDIR_ABS:$(L4DIR_ABS)/%=%))
  VARIANTS        += $(or $(SRC_VARIANTS), $(PKGDIR_VARIANTS), std)
endif

# Add coverage variant modification if necessary
COV_COMPONENTS_ABS = $(COV_COMPONENTS:%=$(abspath $(L4DIR))/%)
ifneq ($(filter-out host targetsys,$(MODE)),)
ifeq ("$(CONFIG_COV)","y")
  # When building for coverage, all tests are built with coverage. Also, tests
  # are always std, so we add std+cov
  VARIANTS_test.mk = std+cov
  # ifneq ($(filter $(abspath $(PKGDIR)),$(COV_COMPONENTS_ABS)),)
  #   # progs and libs should only be built for coverage if they are in
  #   # $COV_COMPONENTS. We add cov to existing variants.
  #   $(info variants: $(VARIANTS))
  #   VARIANTS_prog.mk := $(or $(VARIANTS:%=%+cov),std+cov)
  #   VARIANTS_lib.mk := $(or $(VARIANTS:%=%+cov),std+cov)
  # endif
endif
endif


VARIANTS        += $(VARIANTS_$(ROLE))
VARIANTS        := $(sort $(VARIANTS))

$(if $(VARIANTS),,$(error No variants defined))

endif # _L4DIR_MK_VARIANTS undefined
