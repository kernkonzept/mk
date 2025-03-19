# -*- Makefile -*-
#
# L4Re Buildsystem
#
# Makefile-Template for binary directories
#
# Makeconf is used, see there for further documentation
# install.inc is used, see there for further documentation
# binary.inc is used, see there for further documentation

ifeq ($(origin _L4DIR_MK_PROG_MK),undefined)
_L4DIR_MK_PROG_MK=y

ROLE = prog.mk

include $(L4DIR)/mk/Makeconf
$(GENERAL_D_LOC): $(L4DIR)/mk/prog.mk

# our mode
MODE 			?= static

# include all Makeconf.locals, define common rules/variables
include $(L4DIR)/mk/binary.inc

# define INSTALLDIRs prior to including install.inc, where the install-
# rules are defined.
ifneq ($(filter host targetsys,$(MODE)),)
INSTALLDIR_BIN		?= $(DROPS_STDDIR)/bin/$(MODE)
INSTALLDIR_BIN_LOCAL	?= $(OBJ_BASE)/bin/$(MODE)
else
  ifeq ($(words $(VARIANTS)),1)
    INSTALLDIR_BIN		?= $(DROPS_STDDIR)/bin/$(BID_install_subdir_base)
    INSTALLDIR_BIN_LOCAL	?= $(OBJ_BASE)/bin/$(BID_install_subdir_base)
  else
    INSTALLDIR_BIN		?= $(DROPS_STDDIR)/bin/$(BID_install_subdir_var)
    INSTALLDIR_BIN_LOCAL	?= $(OBJ_BASE)/bin/$(BID_install_subdir_var)
  endif
endif
ifeq ($(CONFIG_BID_STRIP_BINARIES),y)
INSTALLFILE_BIN 	?= $(call copy_stripped_binary,$(1),$(2),755)
INSTALLFILE_BIN_LOCAL 	?= $(call copy_stripped_binary,$(1),$(2),755)
else
INSTALLFILE_BIN 	?= $(INSTALL) -m 755 $(1) $(2)
INSTALLFILE_BIN_LOCAL 	?= $(INSTALL) -m 755 $(1) $(2)
endif

INSTALLFILE		= $(INSTALLFILE_BIN)
INSTALLDIR		= $(INSTALLDIR_BIN)
INSTALLFILE_LOCAL	= $(INSTALLFILE_BIN_LOCAL)
INSTALLDIR_LOCAL	= $(INSTALLDIR_BIN_LOCAL)

ifneq ($(SYSTEM),) # if we have a system, really build

TARGET_STANDARD := $(TARGET) $(TARGET_$(OSYSTEM))
TARGET_PROFILE := $(addsuffix .pr,$(filter $(BUILD_PROFILE),$(TARGET)))

$(call GENERATE_PER_TARGET_RULES,$(TARGET_STANDARD))
$(call GENERATE_PER_TARGET_RULES,$(TARGET_PROFILE),.pr)

TARGET	+= $(TARGET_$(OSYSTEM)) $(TARGET_PROFILE)

# Ada needs the binder file for programs to be runnable
ifneq ($(strip $(SRC_ADA)$(foreach t,$(TARGET),$(SRC_ADA_$(t)))),)
  $(foreach t,$(TARGET),$(if $(SRC_ADA_$(t))$(SRC_ADA),\
              $(eval OBJS_$(t) += b~$(t).o)\
              $(eval $(t): b~$(t).o)))

b~%.o: %.adb %.ali
	@$(call COMP_MESSAGE, from $(<F))
	$(VERBOSE)$(ADAC) $(ADACFLAGS) $(ADABINDFLAGS) -g -b $* -bargs -E
	$(VERBOSE)$(ADAC) -g -c b~$*
endif

# Now that the list of targets is final, the variant hooks can be called.
$(foreach v,$(CHOSEN_VARIANTS),$(eval $(PROG_TARGET_HOOK-variant-$(v))))

# define some variables different for lib.mk and prog.mk
ifeq ($(MODE),shared)
LDFLAGS += $(LDFLAGS_DYNAMIC_LINKER)
endif
ifeq ($(CONFIG_BID_GENERATE_MAPFILE),y)
LDFLAGS += -Map $(strip $@).map
endif
LDFLAGS += $(addprefix -L, $(PRIVATE_LIBDIR) $(PRIVATE_LIBDIR_$(OSYSTEM)) $(PRIVATE_LIBDIR_$@) $(PRIVATE_LIBDIR_$@_$(OSYSTEM)))

# here because order of --defsym's is important
ifeq ($(MODE),l4linux)
  L4LX_USER_KIP_ADDR = 0xbfdfd000
  LDFLAGS += --defsym __l4sys_invoke_direct=$(L4LX_USER_KIP_ADDR)+$(L4_KIP_OFFS_SYS_INVOKE) \
             --defsym __l4sys_debugger_direct=$(L4LX_USER_KIP_ADDR)+$(L4_KIP_OFFS_SYS_DEBUGGER)
  CPPFLAGS += -DL4SYS_USE_UTCB_WRAP=1
endif

ifneq ($(HOST_LINK),1)
  # linking for our L4 platform
  LDFLAGS += $(addprefix -L, $(L4LIBDIR))
  LDFLAGS += $(addprefix $(if $(filter lld,$(BID_LD_TYPE)),-T,-dT) , $(LDSCRIPT))
  LDFLAGS += --warn-common
else
  # linking for some POSIX platform
  LDFLAGS += $(addprefix -PC,$(REQUIRES_LIBS))
  ifeq ($(MODE),host)
    # linking for the build-platform
    LDFLAGS += -L$(OBJ_BASE)/lib/host
    LDFLAGS += $(LIBS)
  else
    # linking for L4Linux, we want to look for Linux-libs before the L4-libs
    LDFLAGS += $(GCCSYSLIBDIRS)
    LDFLAGS += $(addprefix -L, $(L4LIBDIR))
    LDFLAGS += $(LIBS)
  endif
endif

# This registers directories with RELOC_PHYS enabled in a central file in the
# build directory. It allows us to specifically call make on these again when
# the RAM_BASE changes.
ifeq ($(RELOC_PHYS),y)
EXTRA_INSTALL_GOALS += register_phys_reloc
.PHONY: register_phys_reloc

register_phys_reloc:
	@line="PHYS_RELOC_DIR_LIST += $(OBJ_DIR)"; \
	depfile="$(OBJ_BASE)/.Makeconf.phys_reloc"; \
	grep -s -q -F "$$line" "$$depfile" || ( echo "$$line" >> "$$depfile" )

endif

include $(L4DIR)/mk/install.inc

DEPS	+= $(foreach file,$(TARGET), $(call BID_LINK_DEPS,$(file)))

LINK_PROGRAM-C-host-1   := $(CC)
LINK_PROGRAM-CXX-host-1 := $(CXX)

bid_call_if = $(if $(2),$(call $(1),$(2)))

LINK_PROGRAM  := $(call bid_call_if,BID_LINK_MODE_host,$(LINK_PROGRAM-C-host-$(HOST_LINK)))
ifneq ($(SRC_CC),)
LINK_PROGRAM  := $(call bid_call_if,BID_LINK_MODE_host,$(LINK_PROGRAM-CXX-host-$(HOST_LINK)))
endif

ifeq ($(LINK_PROGRAM),)
LINK_PROGRAM  := $(BID_LINK)
BID_LDFLAGS_FOR_LINKING = $(call BID_mode_var,NOPIEFLAGS) -MD -MF $(call BID_link_deps_file,$@) \
                          $(addprefix -PC,$(REQUIRES_LIBS)) $(LDFLAGS)
else
BID_LDFLAGS_FOR_LINKING = $(call BID_mode_var,NOPIEFLAGS) -MD -MF $(call BID_link_deps_file,$@) \
                          $(if $(HOST_LINK_TARGET),$(CARCHFLAGS) $(CCXX_FLAGS)) $(call ldflags_to_gcc,$(LDFLAGS))
endif

$(TARGET): $(OBJS) $(LIBDEPS)
	@$(LINK_MESSAGE)
	$(VERBOSE)$(call MAKEDEP,$(INT_LD_NAME),,,ld) $(LINK_PROGRAM) -o $@ $(BID_LDFLAGS_FOR_LINKING) $(OBJS) $(LIBS) $(EXTRA_LIBS)
	$(if $(BID_GEN_CONTROL),$(VERBOSE)echo "Requires: $(REQUIRES_LIBS)" >> $(PKGDIR)/Control)
	$(if $(BID_POST_PROG_LINK_MSG_$@),@$(BID_POST_PROG_LINK_MSG_$@))
	$(if $(BID_POST_PROG_LINK_$@),$(BID_POST_PROG_LINK_$@))
	@$(BUILT_MESSAGE)

endif	# architecture is defined, really build

-include $(DEPSVAR)
.PHONY: all clean cleanall config help install oldconfig txtconfig
help::
	@echo "  all            - compile and install the binaries"
ifneq ($(SYSTEM),)
	@echo "                   to $(INSTALLDIR_LOCAL)"
endif
	@echo "  install        - compile and install the binaries"
ifneq ($(SYSTEM),)
	@echo "                   to $(INSTALLDIR)"
endif
	@echo "  relink         - relink and install the binaries"
ifneq ($(SYSTEM),)
	@echo "                   to $(INSTALLDIR_LOCAL)"
endif
	@echo "  disasm         - disassemble first target"
	@echo "  scrub          - delete backup and temporary files"
	@echo "  clean          - delete generated object files"
	@echo "  cleanall       - delete all generated, backup and temporary files"
ifneq ($(BID_COLLECT_DIAGNOSTICS),)
	@echo "  diag           - show collected compiler diagnostics."
	@echo "                   (using format $(BID_COLLECT_DIAGNOSTICS))"
endif
	@echo "  help           - this help"
	@echo
ifneq ($(SYSTEM),)
	@echo "  binaries are: $(TARGET)"
else
	@echo "  build for architectures: $(TARGET_SYSTEMS)"
endif

endif	# _L4DIR_MK_PROG_MK undefined
