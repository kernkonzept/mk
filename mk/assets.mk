# -*- Makefile -*-
#
# L4Re Buildsystem
#

ifeq ($(origin _L4DIR_MK_ASSETS_MK),undefined)
_L4DIR_MK_ASSETS_MK=y

ROLE = assets.mk

include $(L4DIR)/mk/Makeconf
$(GENERAL_D_LOC): $(L4DIR)/mk/assets.mk

# Args: dirname, targets
define register_asset_targets
  $(foreach t,$(2), \
    $(eval INSTALLDIR_$(t) ?= $(INSTALLDIR)/$(1)) \
    $(eval INSTALLDIR_LOCAL_$(t) ?= $(INSTALLDIR_LOCAL)/$(1)))
endef

define src_asset_link
$1: $(SRC_DIR)/$1
	@$(INSTALL_MESSAGE)
	$(VERBOSE)$(call create_dir, $$(@D))
	$(VERBOSE)ln -fs $$< $$@
endef

define install_assets
  $(foreach t,$2,$(eval $(call src_asset_link,$t)))
  $(call register_asset_targets,$1,$2)
  $(eval INSTALL_TARGET += $2)
endef

INSTALLDIR_ASSETS        ?= $(DROPS_STDDIR)/assets
INSTALLDIR_ASSETS_LOCAL  ?= $(OBJ_BASE)/assets
INSTALLFILE_ASSETS       ?= $(INSTALL) -m 644 $(1) $(2)
INSTALLFILE_ASSETS_LOCAL ?= $(LN) -sf $(abspath $(1)) $(2)

INSTALLFILE               = $(INSTALLFILE_ASSETS)
INSTALLDIR                = $(INSTALLDIR_ASSETS)
INSTALLFILE_LOCAL         = $(INSTALLFILE_ASSETS_LOCAL)
INSTALLDIR_LOCAL          = $(INSTALLDIR_ASSETS_LOCAL)

MODE                     ?= assets

REQUIRE_HOST_TOOLS       ?= $(if $(SRC_DTS),dtc)

include $(L4DIR)/mk/binary.inc

ifneq ($(SYSTEM),) # if we are a system, really build

# Functionality for device-tree file handling
TARGET_DTB      = $(patsubst %.dts,%.dtb,$(SRC_DTS))
TARGET         += $(TARGET_DTB)
INSTALL_TARGET += $(TARGET)
DEPS           += $(foreach file,$(TARGET_DTB),$(call BID_dot_fname,$(file)).d)
$(call register_asset_targets,dtb,$(TARGET_DTB))

$(call install_assets,modlist/$(PKGNAME),$(SRC_ASSETS_MODLIST))
$(call install_assets,ned/$(PKGNAME),$(SRC_ASSETS_NED))
$(call install_assets,io/,$(SRC_ASSETS_IO))

include $(L4DIR)/mk/install.inc

endif # SYSTEM

.PHONY: all clean cleanall config help install oldconfig txtconfig
-include $(DEPSVAR)
help::
	@echo "  all            - generate assets locally"
ifneq ($(SYSTEM),)
	@echo "                   to $(INSTALLDIR_LOCAL)"
endif
	@echo "  install        - generate and install assets globally"
ifneq ($(SYSTEM),)
	@echo "                   to $(INSTALLDIR)"
endif
	@echo "  scrub          - delete backup and temporary files"
	@echo "  clean          - delete generated object files"
	@echo "  cleanall       - delete all generated, backup and temporary files"
	@echo "  help           - this help"

endif # _L4DIR_MK_ASSETS_MK undefined
