#
# GLOBAL Makefile for the whole L4 tree
#

L4DIR         ?= .

PRJ_SUBDIRS   := pkg tests $(wildcard l4linux)
BUILD_DIRS    := tool
install-dirs  := tool pkg
clean-dirs    := tool pkg tests doc sysroot
cleanall-dirs := tool pkg tests doc sysroot

BUILD_TOOLS    = bash bison flex gawk perl tput \
                 $(foreach v,CC CXX LD HOST_CC HOST_CXX HOST_LD, \
                   $(firstword $(foreach x,$($(v)),\
                     $(if $(findstring =,$(x)),,$(x)))))
BUILD_TOOLS_pkg/uvmm  := dtc

CMDS_WITHOUT_OBJDIR := help checkbuild checkbuild.% check_build_tools
CMDS_PROJECT_MK     := all clean cleanall install scrub cont doc help sysroot \
                       $(wildcard $(MAKECMDGOALS))

# Hack, see project.mk
BID_DCOLON_TARGETS := all clean cleanall install scrub DROPSCONF_CONFIG_MK_POST_HOOK olddefconfig oldconfig config

# This goes very early
# TODO: should be done in mk/Makeconf to catch all make invocations (maybe
#        there's a better way?)
ifneq ($(if $(B)$(BID_SANDBOX_IN_PROGRESS),,$(SANDBOX_ENABLE)),)

.PHONY: $(MAKECMDGOALS) do-all-make-targets

do-all-make-targets:
	$(VERBOSE)BID_SANDBOX_IN_PROGRESS=1 \
	   $(L4DIR)/tool/bin/sandbox \
	              --sys-dir "$(or $(SANDBOX_SYSDIR),/)" \
	              --dir-rw "$(OBJ_DIR)" \
	              --dir-ro "$(if $(L4DIR_ABS),$(L4DIR_ABS),$(PWD))" \
	              --cmd "$(MAKE) -C $(OBJ_DIR) $(MAKECMDGOALS)"

include $(L4DIR)/mk/Makeconf

$(filter-out $(BID_DCOLON_TARGETS),$(MAKECMDGOALS)):  do-all-make-targets
$(filter     $(BID_DCOLON_TARGETS),$(MAKECMDGOALS)):: do-all-make-targets

else
all::

#####################
# config-tool

DROPSCONF               = y
TEMPLDIR	       := mk/defconfig
DFL_TEMPLATE           := amd64
DROPSCONF_DEFCONFIG    ?= $(TEMPLDIR)/config.$(DFL_TEMPLATE)
KCONFIG_FILE            = $(OBJ_BASE)/Kconfig.generated
KCONFIG_FILE_DEPS       = $(OBJ_BASE)/.Kconfig.generated.d
KCONFIG_FILE_SRC        = $(L4DIR)/mk/Kconfig
DROPSCONF_CONFIG        = $(OBJ_BASE)/include/config/auto.conf
DROPSCONF_CONFIG_H      = $(OBJ_BASE)/include/generated/autoconf.h
DROPSCONF_CONFIG_MK     = $(OBJ_BASE)/.config.all
DROPSCONF_DONTINC_MK    = y
DROPSCONF_HELPFILE      = $(L4DIR)/mk/config.help

# separation in "dependent" (ie opts the build output depends on) and
# "independent" (ie opts the build output does not depend on) opts
CONFIG_MK_INDEPOPTS     = BID_LIBGENDEP_PATHS CONFIG_BID_COLORED_PHASES \
                          CONFIG_BID_GENERATE_MAPFILE CONFIG_BID_STRIP_PROGS \
                          CONFIG_DEPEND_VERBOSE CONFIG_INT_CPP_.*_NAME \
                          CONFIG_INT_CPP_NAME_SWITCH CONFIG_INT_CXX_.*_NAME \
                          CONFIG_INT_LD_.*_NAME CONFIG_INT_LD_NAME_SWITCH \
                          CONFIG_VERBOSE CONFIG_VERBOSE_SWITCH
CONFIG_MK_PLATFORM_OPTS = CONFIG_PLATFORM_.*
CONFIG_MK_REAL          = $(OBJ_BASE)/.config
CONFIG_MK_INDEP         = $(OBJ_BASE)/.config.indep
CONFIG_MK_PLATFORM      = $(OBJ_BASE)/.config.platform

INCLUDE_BOOT_CONFIG    := optional

# Do not require Makeconf if *all* targets work without a builddir.
# The default target does not!
ifeq ($(filter-out $(CMDS_WITHOUT_OBJDIR),$(MAKECMDGOALS)),)
ifneq ($(MAKECMDGOALS),)
IGNORE_MAKECONF_INCLUDE=1
endif
endif

ifneq ($(B)$(BUILDDIR_TO_CREATE),)
IGNORE_MAKECONF_INCLUDE=1
endif

ifeq ($(IGNORE_MAKECONF_INCLUDE),)
ifneq ($(filter help config oldconfig olddefconfig silentoldconfig,$(MAKECMDGOALS)),)
# tweek $(L4DIR)/mk/Makeconf to use the intermediate file
export BID_IGN_ROOT_CONF=y
BID_ROOT_CONF=$(DROPSCONF_CONFIG_MK)
endif

# $(L4DIR)/mk/Makeconf shouln't include Makeconf.local twice
MAKECONFLOCAL = /dev/null


# Use project.mk if we use the default goal (MAKECMDGOALS is empty)
# or any of the goals listed in CMDS_PROJECT_MK, this saves us
# from running the time consuming project.mk find operations.
ifeq ($(MAKECMDGOALS),)
  include $(L4DIR)/mk/project.mk
else
  ifneq ($(filter $(CMDS_PROJECT_MK),$(MAKECMDGOALS)),)
    include $(L4DIR)/mk/project.mk
  else
    include $(L4DIR)/mk/Makeconf
  endif
endif

PKGDEPS_IGNORE_MISSING :=
export DROPS_STDDIR

# after having absfilename, we can export BID_ROOT_CONF
ifneq ($(filter config oldconfig olddefconfig silentoldconfig gconfig nconfig xconfig, $(MAKECMDGOALS)),)
export BID_ROOT_CONF=$(call absfilename,$(OBJ_BASE))/.config.all
endif
endif

#####################
# rules follow

ifneq ($(strip $(B)),)
BUILDDIR_TO_CREATE := $(B)
endif

ifneq ($(strip $(BUILDDIR_TO_CREATE)),)

# Use custom default configuration file if T is specified
ifneq ($(T),)
  DROPSCONF_DEFCONFIG_CANDIDATE=$(TEMPLDIR)/config.$(T)
  ifneq ($(wildcard $(DROPSCONF_DEFCONFIG_CANDIDATE)),)
    DROPSCONF_DEFCONFIG=$(DROPSCONF_DEFCONFIG_CANDIDATE)
  else
    $(error ERROR: Default configuration file $(DROPSCONF_DEFCONFIG_CANDIDATE) (derived from T=$(T)) not found)
  endif
endif

all::
	@echo "Creating build directory \"$(BUILDDIR_TO_CREATE)\"..."
	@if [ -e $(BUILDDIR_TO_CREATE) ]; then \
	   echo "Already exists, aborting.";   \
	   exit 1;                             \
	fi
	@mkdir -p $(BUILDDIR_TO_CREATE)
	@cp $(DROPSCONF_DEFCONFIG) $(BUILDDIR_TO_CREATE)/.kconfig
	@echo CONFIG_PLATFORM_TYPE_$(PT)=y >> $(BUILDDIR_TO_CREATE)/.kconfig
ifneq ($(DROPSCONF_DEFCONFIG_OVERLAY),)
	@cat $(DROPSCONF_DEFCONFIG_OVERLAY) >> $(BUILDDIR_TO_CREATE)/.kconfig
endif
	@$(MAKE) B= BUILDDIR_TO_CREATE= O=$(BUILDDIR_TO_CREATE) olddefconfig \
	  || ( $(RM) -r $(BUILDDIR_TO_CREATE) ; exit 1 )
	@echo "done."
else

all:: $(BUILD_DIRS) $(if $(S),,l4defs regen_compile_commands_json)

endif


#
# The following targets do work without explicit subdirs
# ('S=...') only.
#
ifeq ($(S),)

# some special cases for dependencies follow:
# L4Linux depends on the availability of the l4defs
l4linux: l4defs
l4linux/l4-build: l4defs

# hack for examples, they virtually depend on anything else
pkg/examples: $(filter-out pkg/examples,$(BUILD_SUBDIRS))

# some more dependencies
tool: $(DROPSCONF_CONFIG_MK)
$(BUILD_SUBDIRS):  $(DROPSCONF_CONFIG_MK) tool

ifneq ($(CONFIG_BID_BUILD_DOC),)
install-dirs += doc
all:: doc
endif

tool:
	$(VERBOSE)if [ -r $@/Makefile ]; then PWD=$(PWD)/$@ $(MAKE) -C $@; fi

doc:
	$(VERBOSE)if [ -r doc/source/Makefile ]; then PWD=$(PWD)/doc/source $(MAKE) -C doc/source; fi

BID_POST_CONT_HOOK := $(MAKE) regen_l4defs

.PHONY: all clean cleanall clean-test-scripts install doc
.PHONY: $(BUILD_DIRS) doc check_build_tools cont cleanfast

cleanfast:
	$(VERBOSE)if [ -f $(OBJ_BASE)/include/generated/autoconf.h ]; then \
	            cp -a $(OBJ_BASE)/include/generated/autoconf.h         \
	                  $(OBJ_BASE)/.tmp.bid_config.h;                   \
	          fi
	$(VERBOSE)$(RM) -r $(addprefix $(OBJ_BASE)/,bin include pkg tests    \
	                               doc ext-pkg pc lib test               \
	                               .Makeconf.phys_reloc sysroot )        \
	                               $(L4DEFS_FILES)                       \
	                               $(IMAGES_DIR)
	$(VERBOSE)if [ -f $(OBJ_BASE)/.tmp.bid_config.h ]; then  \
	            mkdir -p $(OBJ_BASE)/include/generated;      \
	            mv $(OBJ_BASE)/.tmp.bid_config.h             \
	               $(OBJ_BASE)/include/generated/autoconf.h; \
	          fi

cleanall::
	$(VERBOSE)rm -f *~

clean-test-scripts:
	$(VERBOSE)$(RM) -r $(OBJ_BASE)/test/t

clean cleanall install::
	$(VERBOSE)set -e; for i in $($@-dirs) ; do                     \
	            if [ -r $$i/Makefile -o -r $$i/GNUmakefile ]; then \
	              PWD=$(PWD)/$$i $(MAKE) -C $$i $@; fi; done

l4defs_file  = $(OBJ_BASE)/l4defs$(if $(filter std,$(1)),,-$(1)).$(2).inc

L4DEFS_FILES = $(foreach v,std $(VARIANTS_AVAILABLE),$(call l4defs_file,$(v),mk) $(call l4defs_file,$(v),sh) $(call l4defs_file,$(v),pl))

l4defs: $(L4DEFS_FILES)

generate_l4defs_files_step = \
	tmpdir=$(OBJ_BASE)/l4defs.gen.dir &&                 \
	mkdir -p $$tmpdir &&                                           \
	echo "L4DIR = $(L4DIR_ABS)"                      > $$tmpdir/Makefile && \
	echo "OBJ_BASE = $(OBJ_BASE)"                   >> $$tmpdir/Makefile && \
	echo "L4_BUILDDIR = $(OBJ_BASE)"                >> $$tmpdir/Makefile && \
	echo "SRC_DIR = $$tmpdir"                       >> $$tmpdir/Makefile && \
	echo "PKGDIR_ABS = $(L4DIR_ABS)/l4defs.gen.dir" >> $$tmpdir/Makefile && \
	echo "VARIANT = $(2)"                           >> $$tmpdir/Makefile && \
	echo "BUILD_MESSAGE ="                          >> $$tmpdir/Makefile && \
	cat $(L4DIR)/mk/export_defs.inc                 >> $$tmpdir/Makefile && \
	PWD=$$tmpdir $(MAKE) -C $$tmpdir -f $$tmpdir/Makefile          \
	  CALLED_FOR=$(1) L4DEF_FILE_MK=$(call l4defs_file,$(2),mk) L4DEF_FILE_SH=$(call l4defs_file,$(2),sh) L4DEF_FILE_PL=$(call l4defs_file,$(2),pl) && \
	$(RM) -r $$tmpdir

generate_l4defs_files = \
	$(call generate_l4defs_files_step,static,$(1)); \
	$(call generate_l4defs_files_step,minimal,$(1)); \
	$(call generate_l4defs_files_step,shared,$(1)); \
	$(call generate_l4defs_files_step,sharedlib,$(1)); \
	$(call generate_l4defs_files_step,finalize,$(1))

$(firstword $(L4DEFS_FILES)): $(OBJ_DIR)/.Package.deps pkg/l4re-core \
                 $(DROPSCONF_CONFIG_MK) $(L4DIR)/mk/export_defs.inc
	+$(VERBOSE)$(foreach v,std $(VARIANTS_AVAILABLE),$(call generate_l4defs_files,$(v));)

$(wordlist 2,$(words $(L4DEFS_FILES)),$(L4DEFS_FILES)): $(firstword $(L4DEFS_FILES))

regen_l4defs:
	+$(VERBOSE)$(foreach v,std $(VARIANTS_AVAILABLE),$(call generate_l4defs_files,$(v));)

COMPILE_COMMANDS_JSON = compile_commands.json

$(COMPILE_COMMANDS_JSON):
	$(GEN_MESSAGE)
	$(VERBOSE)$(L4DIR)/tool/bin/gen_ccj $(OBJ_DIR) $@

# Automatically regenerate compile_commands.json if the file is already
# there and if we build the build-directory the compile_commands.json file
# was originally created from.
regen_compile_commands_json:
	$(VERBOSE)if [ -e "$(COMPILE_COMMANDS_JSON)" ]; then               \
	  if grep -qF "$(OBJ_DIR)" $(COMPILE_COMMANDS_JSON); then          \
	    $(call GEN_MESSAGE,$(COMPILE_COMMANDS_JSON));                  \
	    $(L4DIR)/tool/bin/gen_ccj $(OBJ_DIR) $(COMPILE_COMMANDS_JSON); \
	  fi;                                                              \
	fi

# Build a typical sysroot for use with external tooling such as a
# L4Re-specific cross-compiler
SYSROOT_LIBS = libgcc_s lib4re lib4re-c lib4re-c-util lib4re-util-nortti lib4re-util libc libc_be_l4re libc_be_l4refile libc_be_socket_noop libc_be_sig libc_be_sig_noop libc_support_misc libdl libl4re-vfs.o libl4sys libl4util libld-l4 libm_support libpthread libc_nonshared.p libssp_nonshared.p libmount
sysroot: $(foreach p,l4re l4re_c l4re_vfs l4sys l4util ldso libc_backends uclibc,pkg/l4re-core/$(p))
	$(GEN_MESSAGE)
	$(VERBOSE)$(RM) -r $(OBJ_DIR)/sysroot
	$(VERBOSE)$(MKDIR) $(OBJ_DIR)/sysroot
	$(VERBOSE)$(MKDIR) $(OBJ_DIR)/sysroot/usr/include/l4
	$(VERBOSE)$(MKDIR) $(OBJ_DIR)/sysroot/usr/include/l4-arch/l4
	$(VERBOSE)$(MKDIR) $(OBJ_DIR)/sysroot/usr/lib
	$(VERBOSE)$(CP) -Lr $(OBJ_DIR)/include/$(BUILD_ARCH)/l4/sys \
	                    $(OBJ_DIR)/include/$(BUILD_ARCH)/l4/util \
	                    $(OBJ_DIR)/sysroot/usr/include/l4-arch/l4
	$(VERBOSE)$(CP) -Lr $(OBJ_DIR)/include/$(BUILD_ARCH)/l4f/l4 \
	          $(OBJ_DIR)/sysroot/usr/include/l4-arch/
	$(VERBOSE)$(CP) -Lr $(OBJ_DIR)/include/l4/{crtn,cxx,l4re_vfs,libc_backends,re,sys,util,bid_config.h} \
	                    $(OBJ_DIR)/sysroot/usr/include/l4/
	$(VERBOSE)$(CP) -Lr $(OBJ_DIR)/include/uclibc/* $(OBJ_DIR)/sysroot/usr/include/
	$(VERBOSE)$(CP) -Lr $(OBJ_DIR)/lib/$(BUILD_ARCH)_$(CPU)/std/plain/crt* $(OBJ_DIR)/sysroot/usr/lib
	$(VERBOSE)$(CP) -Lr $(wildcard $(foreach l,$(SYSROOT_LIBS),$(OBJ_DIR)/lib/$(BUILD_ARCH)_$(CPU)/std/l4f/$(l).a $(OBJ_DIR)/lib/$(BUILD_ARCH)_$(CPU)/std/l4f/$(l).so)) \
	                    $(OBJ_DIR)/sysroot/usr/lib
	$(VERBOSE)mv $(OBJ_DIR)/sysroot/usr/lib/libc_nonshared.p.a  $(OBJ_DIR)/sysroot/usr/lib/libc_nonshared.a
	$(VERBOSE)mv $(OBJ_DIR)/sysroot/usr/lib/libm_support.a  $(OBJ_DIR)/sysroot/usr/lib/libm.a
	$(VERBOSE)mv $(OBJ_DIR)/sysroot/usr/lib/libm_support.so $(OBJ_DIR)/sysroot/usr/lib/libm.so


.PHONY: l4defs regen_l4defs compile_commands.json regen_compile_commands_json
endif # empty $(S)

#####################
# config-rules follow

HOST_SYSTEM := $(shell uname | tr 'A-Z' 'a-z')
export HOST_SYSTEM

# 'make config' results in a config file, which must be postprocessed. This is
# done in config.inc. Then, we evaluate some variables that depend on the
# postprocessed config file. The variables are defined in mk/Makeconf, which
# sources Makeconf.bid.local. Hence, we have to 1) postprocess, 2) call make
# again to get the variables.
BID_DCOLON_TARGETS += DROPSCONF_CONFIG_MK_POST_HOOK
DROPSCONF_CONFIG_MK_POST_HOOK:: check_build_tools $(OBJ_DIR)/Makefile
        # libgendep must be done before calling make with the local helper
	$(VERBOSE)$(MAKE) libgendep
	$(VERBOSE)$(MAKE) Makeconf.bid.local-helper || \
	    (rm -f $(DROPSCONF_CONFIG_MK) $(CONFIG_MK_REAL) $(CONFIG_MK_INDEP); false)
	$(VEROBSE)$(LN) -snf $(L4DIR_ABS) $(OBJ_BASE)/source
	$(VERBOSE)$(MAKE) checkconf

$(KCONFIG_FILE).defines: FORCE
	$(VERBOSE)echo "# Automatically generated. Don't edit" >$@.tmp
	$(VERBOSE)echo "BID_COMPILER_TYPE := $(call BID_COMPILER_TYPE_f)" >>$@.tmp
	$(VERBOSE)$(call move_if_changed,$@,$@.tmp)

KCONFIGS_ARCH     := $(wildcard $(L4DIR)/mk/arch/Kconfig.*.inc)
KCONFIG_PLATFORMS := $(wildcard $(L4DIR)/mk/platforms/*.conf $(L4DIR)/conf/platforms/*.conf)

# Cannot use $^ inside the $(KCONFIG_FILE).platforms recipe to refer to its
# dependencies, as this would include obsolete dependencies stored in
# $(KCONFIG_FILE_DEPS).platforms from the previous generation of it.
KCONFIG_FILE_PLATFORMS_DEPS_CURRENT = $(KCONFIG_PLATFORMS) Makefile $(L4DIR)/tool/bin/gen_kconfig_includes

$(addprefix $(KCONFIG_FILE)%,platform_types platforms platforms.list): \
            $(KCONFIG_FILE_PLATFORMS_DEPS_CURRENT)
	$(file >$(KCONFIG_FILE_DEPS).platforms,$@: $(KCONFIG_FILE_PLATFORMS_DEPS_CURRENT))
	$(foreach f,$(KCONFIG_FILE_PLATFORMS_DEPS_CURRENT),$(file >>$(KCONFIG_FILE_DEPS).platforms,$(f):))
	$(VERBOSE)MAKE="$(MAKE)"; $(L4DIR)/tool/bin/gen_kconfig_includes $(KCONFIG_FILE) $(KCONFIG_PLATFORMS)

# Kconfig.L4 files must be next to the Control file
PKG_DIRS := $(call find_prj_dirs,$(SRC_DIR))
PKG_KCONFIG_L4_FILES := $(wildcard $(addsuffix /Kconfig.L4,$(PKG_DIRS)))

# Cannot use $^ inside the $(KCONFIG_FILE) recipe to refer to its dependencies,
# as this would include obsolete dependencies stored in $(KCONFIG_FILE_DEPS)
# from the previous generation of it.
KCONFIG_FILE_DEPS_CURRENT = $(KCONFIG_FILE_SRC) $(PKG_KCONFIG_L4_FILES) Makefile \
                            $(KCONFIGS_ARCH) $(L4DIR)/tool/bin/gen_kconfig

$(KCONFIG_FILE): $(KCONFIG_FILE_DEPS_CURRENT) \
                 | $(KCONFIG_FILE).platform_types $(KCONFIG_FILE).platforms \
                   $(KCONFIG_FILE).platforms.list $(KCONFIG_FILE).defines
	$(file >$(KCONFIG_FILE_DEPS),$(KCONFIG_FILE): $(KCONFIG_FILE_DEPS_CURRENT))
	$(foreach f,$(KCONFIG_FILE_DEPS_CURRENT),$(file >>$(KCONFIG_FILE_DEPS),$(f):))
	$(VERBOSE)$(L4DIR)/tool/bin/gen_kconfig \
	         --kconfig-src-file $(KCONFIG_FILE_SRC) \
	         --kconfig-obj-file $(KCONFIG_FILE) \
	         $(foreach f,$(KCONFIGS_ARCH),--kconfig-arch-file $(f)) \
	         $(foreach f,$(PKG_KCONFIG_L4_FILES),--kconfig-pkg-file $(f))
	$(VERBOSE)$(L4DIR)/mk/pkgdeps -I -K $(OBJ_BASE)/Kconfig.generated.pkgs \
	         genkconfig $(SRC_DIR) $(PKG_DIRS)

# Include dependencies from the previous generation of $(KCONFIG_FILE) and
# $(KCONFIG_FILE).platforms to detect if one of these dependencies has been
# removed, in which case the files need to be regenerated.
-include $(KCONFIG_FILE_DEPS) $(KCONFIG_FILE_DEPS).platforms

ifeq ($(filter y 1,$(DISABLE_CC_CHECK)),)
override DISABLE_CC_CHECK :=
endif

checkconf:
	$(VERBOSE)if [ -n "$(GCCDIR)" -a ! -e $(GCCDIR)/include/stddef.h ]; then \
	  $(ECHO); \
	  $(ECHO) "$(GCCDIR) seems wrong (stddef.h not found)."; \
	  $(ECHO) "Does it exist?"; \
	  $(ECHO); \
	  $(if $(DISABLE_CC_CHECK),,exit 1;) \
	fi
	$(VERBOSE)if [ -z "$(filter $(CC_WHITELIST-$(BID_COMPILER_TYPE)), \
	                            $(GCCVERSION))" ]; then \
	  $(ECHO); \
	  $(ECHO) "$(BID_COMPILER_TYPE)-$(GCCVERSION) is not supported."; \
	  $(ECHO) "Please use a $(BID_COMPILER_TYPE) of the following" \
	          "versions: $(CC_WHITELIST-$(BID_COMPILER_TYPE))"; \
	  $(ECHO); \
	  $(if $(DISABLE_CC_CHECK),,exit 1;) \
	fi
	$(VERBOSE)if [ -n "$(filter $(CC_BLACKLIST-$(BUILD_ARCH)-gcc), \
	                            $(GCCVERSION).$(GCCPATCHLEVEL))" ]; then \
	  $(ECHO); \
	  $(ECHO) "GCC-$(GCCVERSION).$(GCCPATCHLEVEL) is blacklisted" \
	          "because it showed to produce wrong results."; \
	  $(ECHO) "Please upgrade to a more recent version."; \
	  $(ECHO); \
	  $(if $(DISABLE_CC_CHECK),,exit 1;) \
	fi
ifeq ($(CONFIG_COMPILER_RT_USE_TOOLCHAIN_LIBGCC),y)
	$(VERBOSE)if ! $(OBJDUMP) -f $$(grep GCCLIB_HOST= $(DROPSCONF_CONFIG_MK) | cut -d= -f2) | grep -q $(OFORMAT); then \
	  $(ECHO); \
	  $(ECHO) "Missing the cross-compiler's libgcc variant for the target ($(OFORMAT))."; \
	  $(ECHO) "Install it, or disable the \"Use libgcc from toolchain\" (BID_USE_TOOLCHAIN_LIBGCC) config option."; \
	  $(ECHO); \
	  exit 1; \
	fi
	$(VERBOSE)if ! $(OBJDUMP) -f $$(grep GCCLIB_EH_HOST= $(DROPSCONF_CONFIG_MK) | cut -d= -f2) | grep -q $(OFORMAT); then \
	  $(ECHO); \
	  $(ECHO) "Missing the cross-compiler's libgcc_eh variant for the target ($(OFORMAT))."; \
	  $(ECHO) "Install it, or disable the \"Use libgcc from toolchain\" (BID_USE_TOOLCHAIN_LIBGCC) config option."; \
	  $(ECHO); \
	  exit 1; \
	fi
endif


# caching of some variables. Others are determined directly.
# The contents of the variables to cache is already defined in mk/Makeconf.
.PHONY: Makeconf.bid.local-helper Makeconf.bid.local-internal-names \
        libgendep checkconf
CC := $(if $(filter sparc,$(ARCH)),$(if $(call GCCIS_sparc_leon_f),sparc-elf-gcc,$(CC)),$(CC))
LD := $(if $(filter sparc,$(ARCH)),$(if $(call GCCIS_sparc_leon_f),sparc-elf-ld,$(LD)),$(LD))
add_if_f = $(if $($(1)_f),$(1))
Makeconf.bid.local-helper:
	$(VERBOSE)echo BUILD_SYSTEMS="$(strip $(ARCH)_$(CPU)-plain            \
	               $(ARCH)_$(CPU)-$(BUILD_ABI))" >> $(DROPSCONF_CONFIG_MK)
	$(VERBOSE)$(foreach v, BID_COMPILER_TYPE BID_LD_TYPE \
	              CONDITIONAL_WARNINGS_FULL CONDITIONAL_WARNINGS_MEDIUM \
	              GCCDIR GCCFORTRANAVAIL GCC_HAS_ATOMICS GCCINCFIXEDPATH \
	              GCCLIBCAVAIL GCCLIB_EH_HOST GCCLIB_HOST \
	              GCCMAJORVERSION GCCMINORVERSION GCCNOSTACKPROTOPT \
	              GCCPATCHLEVEL GCCPREFIXOPT GCCSTACKPROTALLOPT \
	              GCCSTACKPROTOPT GCCSYSLIBDIRS GCCVERSION \
	              GCCWNOC99DESIGNATOR GCCWNONOEXCEPTTYPE GCCWNOPSABI \
	              GCCWNOUNUSEDPRIVATEFIELD LDNOWARNRWX LDVERSION \
	              RISCV_ZICSR_ZIFENCEI CLANGVISNEWDELETEHIDDEN \
	              $(call add_if_f,GCCARMV5TEFPOPT_$(ARCH)) \
	              $(call add_if_f,GCCARMV6FPOPT_$(ARCH)) \
	              $(call add_if_f,GCCARMV6T2FPOPT_$(ARCH)) \
	              $(call add_if_f,GCCARMV6ZKFPOPT_$(ARCH)) \
	              $(call add_if_f,GCCARMV7AFPOPT_$(ARCH)) \
	              $(call add_if_f,GCCARMV7RFPOPT_$(ARCH)) \
	              $(call add_if_f,GCCARMV7VEFPOPT_$(ARCH)) \
	              $(call add_if_f,GCCARM64OUTLINEATOMICSOPT_$(ARCH)) \
	              $(call add_if_f,GCCNOFPU_$(ARCH)) \
	              $(call add_if_f,GCCIS_$(ARCH)_leon), \
	            echo $(v)=$(call $(v)_f,$(ARCH)) \
	            >>$(DROPSCONF_CONFIG_MK);)
	$(VERBOSE)echo '#include <generated/autoconf.h>' >$(OBJ_BASE)/include/l4/bid_config.h
	$(VERBOSE)$(foreach v, LD_GENDEP_PREFIX, echo $v=$($(v)) >>$(DROPSCONF_CONFIG_MK);)
	$(VERBOSE)echo "HOST_SYSTEM=$(HOST_SYSTEM)" >>$(DROPSCONF_CONFIG_MK)
	$(VERBOSE)# we need to call make again, because HOST_SYSTEM (set above) must be
	$(VERBOSE)# evaluated for LD_PRELOAD to be set, which we need in the following
	$(VERBOSE)$(MAKE) Makeconf.bid.local-internal-names
	$(VERBOSE)sort <$(DROPSCONF_CONFIG_MK) >$(CONFIG_MK_REAL).tmp
	$(VERBOSE)echo -e "# Automatically generated. Don't edit\n" >$(CONFIG_MK_INDEP)
	$(VERBOSE)echo -e "# Automatically generated. Don't edit\n" >$(CONFIG_MK_PLATFORM)
	$(VERBOSE)grep $(addprefix -e ^,$(CONFIG_MK_INDEPOPTS) )    <$(CONFIG_MK_REAL).tmp >>$(CONFIG_MK_INDEP)
	$(VERBOSE)grep $(addprefix -e ^,$(CONFIG_MK_PLATFORM_OPTS)) <$(CONFIG_MK_REAL).tmp >>$(CONFIG_MK_PLATFORM)
	$(VERBOSE)echo -e "# Automatically generated. Don't edit\n" >$(CONFIG_MK_REAL).tmp2
	$(VERBOSE)grep -v $(addprefix -e ^,$$ # $(CONFIG_MK_INDEPOPTS) $(CONFIG_MK_PLATFORM_OPTS)) \
	          <$(CONFIG_MK_REAL).tmp >>$(CONFIG_MK_REAL).tmp2
	$(VERBOSE)echo -e 'include $(call absfilename,$(CONFIG_MK_INDEP))' >>$(CONFIG_MK_REAL).tmp2
	$(VERBOSE)echo -e 'include $(call absfilename,$(CONFIG_MK_PLATFORM))' >>$(CONFIG_MK_REAL).tmp2
	$(VERBOSE)if [ -e "$(CONFIG_MK_REAL)" ]; then \
	            diff --brief -I ^COLOR_TERMINAL $(CONFIG_MK_REAL) $(CONFIG_MK_REAL).tmp2 || \
	            mv $(CONFIG_MK_REAL).tmp2 $(CONFIG_MK_REAL); \
	           else \
	            mv $(CONFIG_MK_REAL).tmp2 $(CONFIG_MK_REAL); \
	           fi
	$(VERBOSE)$(RM) $(CONFIG_MK_REAL).tmp $(CONFIG_MK_REAL).tmp2

# Scan the output of `ld --help` for `supported emulations:` and chose one of
# the listed items in $(LD_EMULATION_CHOICE_$(ARCH)).
define determine_emulation_gnu_ld =
        emulations=$$($(callld) --help                         \
                   | grep -i "supported emulations:"           \
                   | sed -e 's/.*supported emulations: //');   \
        for e in $$emulations; do                              \
          for c in $(LD_EMULATION_CHOICE_$(ARCH)); do          \
            if [ "$$e" = "$$c" ]; then                         \
              echo LD_EMULATION=$$e >> $(DROPSCONF_CONFIG_MK); \
              exit 0;                                          \
            fi;                                                \
          done;                                                \
        done;                                                  \
        echo "No known ld emulation found";                    \
        exit 1
endef

# l.lld does not provide a list of supported emulations.
# Just use the first item of $(LD_EMULATION_CHOICE_$(ARCH)).
define determine_emulation_lld_ld =
        echo LD_EMULATION=$(firstword $(LD_EMULATION_CHOICE_$(ARCH))) \
          >> $(DROPSCONF_CONFIG_MK)
endef

Makeconf.bid.local-internal-names:
ifneq ($(CONFIG_INT_CPP_NAME_SWITCH),)
	$(VERBOSE)set -e; X="$(OBJ_BASE)/tmp.$$$$$$RANDOM.c" ;               \
	          echo 'int main(void){}'>$$X ;                              \
	          rm -f $$X.out; $(LD_GENDEP_PREFIX) GENDEP_SOURCE=$$X       \
	          GENDEP_OUTPUT=$$X.out $(CC) $(CARCHFLAGS) $(CCXX_FLAGS) -c $$X -o $$X.o; \
	          if [ ! -e $$X.out ]; then                                  \
	            echo -e "\n\033[1;31mGendep did not generate output. Is the compiler ($(CC)) statically linked?\033[0m"; \
	            echo -e "Please use a dynamically linked compiler.\n"; exit 1; \
	          fi; echo INT_CPP_NAME=`cat $$X.out` >>$(DROPSCONF_CONFIG_MK); \
	          rm -f $$X $$X.{o,out};
	$(VERBOSE)set -e; X="$(OBJ_BASE)/tmp.$$$$$$RANDOM.cc" ;        \
	          echo 'int main(void){}'>$$X;                         \
	          rm -f $$X.out; $(LD_GENDEP_PREFIX) GENDEP_SOURCE=$$X \
	          GENDEP_OUTPUT=$$X.out $(CXX) -c $$X -o $$X.o;        \
	          test -e $$X.out; echo INT_CXX_NAME=`cat $$X.out`     \
	           >>$(DROPSCONF_CONFIG_MK);                           \
	          rm -f $$X $$X.{o,out};
endif
ifneq ($(CONFIG_INT_LD_NAME_SWITCH),)
	$(VERBOSE)set -e; echo INT_LD_NAME=$$($(callld) 2>&1 \
	          | perl -p -e 's,^(.+/)?([^:]+):.+,$$2,') >> $(DROPSCONF_CONFIG_MK)
endif
	$(VERBOSE)$(if $(filter LLD,$(shell $(callld) --version)),\
	             $(determine_emulation_lld_ld),\
	             $(determine_emulation_gnu_ld))

libgendep:
	$(VERBOSE)if [ ! -r tool/gendep/Makefile ]; then    \
	            echo "=== l4/tool/gendep missing! ==="; \
	            exit 1;                                 \
		  fi
	$(VERBOSE)PWD=$(PWD)/tool/gendep $(MAKE) -C tool/gendep

DIRS_FOR_BUILD_TOOLS_CHECKS = $(patsubst BUILD_TOOLS_%,%,    \
                                         $(filter BUILD_TOOLS_%,$(.VARIABLES)))
BUILD_TOOLS += $(foreach dir,$(DIRS_FOR_BUILD_TOOLS_CHECKS), \
                         $(if $(wildcard $(L4DIR)/$(dir)),   \
                              $(BUILD_TOOLS_$(dir))))

check_build_tools:
	@unset mis;                                                \
	for i in $(sort $(BUILD_TOOLS)); do                        \
	  if ! command -v $$i >/dev/null 2>&1; then                \
	    [ -n "$$mis" ] && mis="$$mis ";                        \
	    mis="$$mis$$i";                                        \
	  fi                                                       \
	done;                                                      \
	if [ -n "$$mis" ]; then                                    \
	  echo -e "\033[1;31mProgram(s) \"$$mis\" not found, please install!\033[0m"; \
	  exit 1;                                                  \
	else                                                       \
	  echo "All build tools checked ok.";                      \
	fi

define common_envvars
	ARCH="$(ARCH)" PLATFORM_TYPE="$(PLATFORM_TYPE)"
endef
define tool_envvars
	L4DIR=$(L4DIR)                                           \
	SEARCHPATH="$(MODULE_SEARCH_PATH):$(BUILDDIR_SEARCHPATH)"
endef
define set_ml
	unset ml; ml=$(L4DIR_ABS)/conf/modules.list;             \
	   [ -n "$(MODULES_LIST)" ] && ml=$(MODULES_LIST)
endef
define entryselection
	   unset e;                                              \
	   $(set_ml);                                            \
	   [ -n "$(ENTRY)"       ] && e="$(ENTRY)";              \
	   [ -n "$(E)"           ] && e="$(E)";                  \
	   if [ -z "$$e" ]; then                                 \
	     BACKTITLE="No entry given. Use                      \
	                'make $@ E=entryname' to avoid menu."    \
	       L4DIR=$(L4DIR) $(common_envvars)                  \
	       $(L4DIR)/tool/bin/entry-selector menu $$ml        \
	         2> $(OBJ_BASE)/.entry-selector.tmp;             \
	     if [ $$? != 0 ]; then                               \
	       cat $(OBJ_BASE)/.entry-selector.tmp;              \
	       exit 1;                                           \
	     fi;                                                 \
	     e=$$(cat $(OBJ_BASE)/.entry-selector.tmp);          \
	     $(RM) $(OBJ_BASE)/.entry-selector.tmp;              \
	   fi
endef

# 1: list of allowed architectures
define check_for_arch
	$(if $(filter $(ARCH),$1),,$(error ERROR: Architecture '$(ARCH)' is not supported for target $@))
endef

define genimage
	+$(VERBOSE)$(entryselection);                                                 \
	$(MKDIR) $(IMAGES_DIR);                                                       \
	PWD=$(PWD)/pkg/bootstrap/server/src $(common_envvars)                         \
	    QEMU_BINARY_NAME=$(if $(QEMU_PATH),$(QEMU_PATH),$(QEMU_ARCH_MAP_$(ARCH))) \
	    $(MAKE) -C pkg/bootstrap/server/src ENTRY="$$e"                           \
	            BOOTSTRAP_MODULES_LIST=$$ml $(1)                                  \
	            BOOTSTRAP_MODULE_PATH_BINLIB="$(BUILDDIR_SEARCHPATH)"             \
	            BOOTSTRAP_SEARCH_PATH="$(MODULE_SEARCH_PATH)"
endef

# Contains PHYS_RELOC_DIR_LIST
-include $(OBJ_BASE)/.Makeconf.phys_reloc

define switch_ram_base_func
	echo "  ... Regenerating RAM_BASE settings"; set -e; \
	echo "# File semi-automatically generated by 'make switch_ram_base'" > $(OBJ_BASE)/Makeconf.ram_base; \
	echo "RAM_BASE := $(1)"                                             >> $(OBJ_BASE)/Makeconf.ram_base; \
	echo "RAM_BASE_SWITCH_PLATFORM_TYPE := $(PLATFORM_TYPE)"            >> $(OBJ_BASE)/Makeconf.ram_base; \
	$(foreach pkg,$(PHYS_RELOC_DIR_LIST), $(MAKE) -C "$(pkg)" E="" ENTRY="" PLATFORM_TYPE=$(PLATFORM_TYPE) RAM_BASE=$(1) || exit $$?; ) \
	echo "RAM_BASE_SWITCH_OK := yes"                                    >> $(OBJ_BASE)/Makeconf.ram_base
endef

QEMU_KERNEL_TYPE          ?= elfimage
QEMU_KERNEL_FILE-elfimage  = $(IMAGES_DIR)/bootstrap.elf
QEMU_KERNEL_FILE-uimage    = $(IMAGES_DIR)/bootstrap.uimage
QEMU_KERNEL_FILE-itb       = $(IMAGES_DIR)/bootstrap.itb
QEMU_KERNEL_FILE-rawimage  = $(IMAGES_DIR)/bootstrap.raw
QEMU_KERNEL_FILE          ?= $(QEMU_KERNEL_FILE-$(QEMU_KERNEL_TYPE))

FVP_KERNEL_FILE	 = $(IMAGES_DIR)/bootstrap.elf

FASTBOOT_BOOT_CMD    ?= fastboot boot

check_and_adjust_ram_base:
	$(VERBOSE)if [ -z "$(PLATFORM_RAM_BASE)" ]; then          \
	  echo "ERROR: Platform \"$(PLATFORM_TYPE)\" not known."; \
	  echo "Available platforms:";                            \
	  $(MAKE) listplatforms;                                  \
	  exit 1;                                                 \
	fi
	$(VERBOSE)if [ -z "$(filter $(ARCH),$(PLATFORM_ARCH))" ]; then     \
	  echo "Platform \"$(PLATFORM_TYPE)\" not available for $(ARCH)."; \
	  exit 1;                                                          \
	fi
	+$(VERBOSE)if [ -n "$(RAM_BASE_SWITCH_OK)" ] && [ "$(RAM_BASE_SWITCH_PLATFORM_TYPE)" != "$(PLATFORM_TYPE)" ] && [ $$(($(RAM_BASE))) != $$(($(PLATFORM_RAM_BASE))) ] \
	                || [ -z "$(RAM_BASE)" ] || [ -z "$(RAM_BASE_SWITCH_OK)" ]; then \
	  echo "=========== Updating RAM_BASE for platform $(PLATFORM_TYPE) to $(PLATFORM_RAM_BASE) =========" ; \
	  $(call switch_ram_base_func,$(PLATFORM_RAM_BASE)); \
	fi

listentries:
	$(VERBOSE)$(set_ml); $(common_envvars) \
	  L4DIR=$(L4DIR) $(L4DIR)/tool/bin/entry-selector list $$ml

shellcodeentry:
	$(VERBOSE)$(entryselection);                                      \
	 SHELLCODE="$(SHELLCODE)" $(common_envvars) $(tool_envvars)       \
	  $(L4DIR)/tool/bin/shell-entry $$ml "$$e"

elfimage: check_and_adjust_ram_base
	$(call genimage,BOOTSTRAP_DO_UIMAGE= BOOTSTRAP_DO_RAW_IMAGE=)
	$(VERBOSE)$(if $(POST_IMAGE_CMD),$(call POST_IMAGE_CMD,$(IMAGES_DIR)/bootstrap.elf))

uimage: check_and_adjust_ram_base
	$(call genimage,BOOTSTRAP_DO_UIMAGE=y BOOTSTRAP_DO_RAW_IMAGE=)
	$(VERBOSE)$(if $(POST_IMAGE_CMD),$(call POST_IMAGE_CMD,$(IMAGES_DIR)/bootstrap.uimage))

itb: check_and_adjust_ram_base
	$(call genimage,BOOTSTRAP_DO_ITB=y)
	$(VERBOSE)$(if $(POST_IMAGE_CMD),$(call POST_IMAGE_CMD,$(IMAGES_DIR)/bootstrap.itb))

rawimage: check_and_adjust_ram_base
	$(call genimage,BOOTSTRAP_DO_UIMAGE= BOOTSTRAP_DO_RAW_IMAGE=y)
	$(VERBOSE)$(if $(POST_IMAGE_CMD),$(call POST_IMAGE_CMD,$(IMAGES_DIR)/bootstrap.raw))

fastboot fastboot_rawimage: rawimage
	$(VERBOSE)$(FASTBOOT_BOOT_CMD) \
	  $(if $(FASTBOOT_IMAGE),$(FASTBOOT_IMAGE),$(IMAGES_DIR)/bootstrap.raw)

fastboot_uimage: uimage
	$(VERBOSE)$(FASTBOOT_BOOT_CMD) \
	  $(if $(FASTBOOT_IMAGE),$(FASTBOOT_IMAGE),$(IMAGES_DIR)/bootstrap.uimage)

efiimage: check_and_adjust_ram_base
	$(call check_for_arch,x86 amd64 arm64)
	$(call genimage,BOOTSTRAP_DO_UIMAGE= BOOTSTRAP_DO_RAW_IMAGE= BOOTSTRAP_DO_UEFI=y)

ifneq ($(filter $(ARCH),x86 amd64),)
qemu:
	$(VERBOSE)$(entryselection);                                      \
	 qemu=$(QEMU_PATH);   \
	 $(if $(filter -serial "-serial",$(QEMU_OPTIONS)),,echo "Warning: No -serial in QEMU_OPTIONS." >&2;) \
	 QEMU=$$qemu QEMU_OPTIONS="$(QEMU_OPTIONS)"                       \
	  $(tool_envvars) $(common_envvars)                               \
	  $(L4DIR)/tool/bin/qemu-x86-launch $$ml "$$e"
else
qemu: $(QEMU_KERNEL_TYPE)
	$(VERBOSE)qemu=$(if $(QEMU_PATH),$(QEMU_PATH),$(QEMU_ARCH_MAP_$(ARCH))); \
	if [ -z "$$qemu" ]; then echo "Set QEMU_PATH!"; exit 1; fi;              \
	$(if $(filter -serial "-serial",$(QEMU_OPTIONS)),,echo "Warning: No -serial in QEMU_OPTIONS." >&2;) \
	echo QEMU-cmd: $$qemu -kernel $(QEMU_KERNEL_FILE) $(QEMU_OPTIONS);    \
	$$qemu -kernel $(QEMU_KERNEL_FILE) $(QEMU_OPTIONS)
endif

ifneq ($(filter $(ARCH),arm arm64),)
fvp: elfimage
	echo FVP-cmd: $(FVP_PATH) -a "cluster0*="$(FVP_KERNEL_FILE) $(FVP_OPTIONS);    \
	$(FVP_PATH) -a "cluster0*="$(FVP_KERNEL_FILE) $(FVP_OPTIONS)
endif

vbox: $(if $(VBOX_ISOTARGET),$(VBOX_ISOTARGET),grub2iso)
	$(call check_for_arch,x86 amd64)
	$(VERBOSE)if [ -z "$(VBOX_VM)" ]; then                                 \
	  echo "Need to set name of configured VirtualBox VM im 'VBOX_VM'.";   \
	  exit 1;                                                              \
	fi
	$(VERBOSE)VirtualBox                    \
	    --startvm $(VBOX_VM)                \
	    --cdrom $(IMAGES_DIR)/.current.iso  \
	    --boot d                            \
	    $(VBOX_OPTIONS)

kexec:
	$(VERBOSE)$(entryselection);                        \
	 $(tool_envvars) $(common_envvars)                  \
	  $(L4DIR)/tool/bin/kexec-launch $$ml "$$e"

ux:
	$(VERBOSE)if [ "$(ARCH)" != "x86" ]; then                   \
	  echo "This mode can only be used with architecture x86."; \
	  exit 1;                                                   \
	fi
	$(VERBOSE)$(entryselection);                                 \
	$(tool_envvars)  $(common_envvars)                           \
	  $(if $(UX_GFX),UX_GFX="$(UX_GFX)")                         \
	  $(if $(UX_GFX_CMD),UX_GFX_CMD="$(UX_GFX_CMD)")             \
	  $(if $(UX_NET),UX_NET="$(UX_NET)")                         \
	  $(if $(UX_NET_CMD),UX_NET_CMD="$(UX_NET_CMD)")             \
	  $(if $(UX_GDB_CMD),UX_GDB_CMD="$(UX_GDB_CMD)")             \
	  $(L4DIR)/tool/bin/ux-launch $$ml "$$e" $(UX_OPTIONS)

GRUB_TIMEOUT ?= 0

ISONAME_SUFFIX ?= .iso

define geniso
	$(call check_for_arch,x86 amd64)
	$(VERBOSE)$(entryselection);                                         \
	 $(MKDIR) $(IMAGES_DIR);                                             \
	 ISONAME=$(IMAGES_DIR)/$$(echo $$e | tr '[ A-Z]' '[_a-z]')$(ISONAME_SUFFIX);      \
	 $(tool_envvars) $(common_envvars)                                   \
	  $(L4DIR)/tool/bin/gengrub$(1)iso --timeout=$(GRUB_TIMEOUT) $$ml    \
	     $$ISONAME "$$e"                                                 \
	  && $(LN) -f $$ISONAME $(IMAGES_DIR)/.current.iso
endef

grub1iso:
	$(call geniso,1)

grub2iso:
	$(call geniso,2)

exportpack: $(if $(filter $(ARCH),x86 amd64),,$(QEMU_KERNEL_TYPE))
	$(if $(EXPORTPACKTARGETDIR),, \
	  @echo Need to specific target directory as EXPORTPACKTARGETDIR=dir; exit 1)
	$(VERBOSE)$(entryselection);                                      \
	 TARGETDIR=$(EXPORTPACKTARGETDIR);                                \
	 qemu=$(if $(QEMU_PATH),$(QEMU_PATH),$(QEMU_ARCH_MAP_$(ARCH)));   \
	 QEMU=$$qemu L4DIR=$(L4DIR) QEMU_OPTIONS="$(QEMU_OPTIONS)"        \
	 OUTPUT_DIR="$(BOOTSTRAP_OUTPUT_DIR)"                             \
	 IMAGE_FILE="$(QEMU_KERNEL_FILE)"                                 \
	 $(tool_envvars) $(common_envvars)                                \
	  $(L4DIR)/tool/bin/genexportpack --timeout=$(GRUB_TIMEOUT)       \
	                                  --grubpathprefix="$(GRUB_PATHPREFIX)" \
	                                  --grubentrytitle="$(GRUB_ENTRY_TITLE)" \
	                                   $$ml $$TARGETDIR $$e;

help::
	@echo
	@echo "Image generation targets:"
	@echo "  efiimage   - Generate an EFI image, containing all modules."
	@echo "  elfimage   - Generate an ELF image, containing all modules."
	@echo "  rawimage   - Generate a raw image (memory dump), containing all modules."
	@echo "  uimage     - Generate a uimage for u-boot, containing all modules."
	@echo "  itb        - Generate a FIT image for u-boot, containing all modules."
	@echo "  grub1iso   - Generate an ISO using GRUB1 in images/<name>.iso [x86, amd64]" 
	@echo "  grub2iso   - Generate an ISO using GRUB2 in images/<name>.iso [x86, amd64]" 
	@echo "  qemu       - Use Qemu to run 'name'." 
	@echo "  fvp        - Use Arm FVP to run 'name'. [arm, arm64]"
	@echo "  exportpack - Export binaries with launch support." 
	@echo "  vbox       - Use VirtualBox to run 'name'." 
	@echo "  fastboot   - Call fastboot with the created rawimage."
	@echo "  fastboot_rawimage - Call fastboot with the created rawimage."
	@echo "  fastboot_uimage   - Call fastboot with the created uimage."
	@echo "  ux         - Run 'name' under Fiasco/UX. [x86]" 
	@echo "  kexec      - Issue a kexec call to start the entry." 
	@echo " Add 'E=name' to directly select the entry without using the menu."
	@echo " Modules are defined in conf/modules.list."

listplatforms: $(KCONFIG_FILE).platforms.list
	$(VERBOSE)sed -nE "s/^\[$(BUILD_ARCH)\](.*)/\1/p" $(KCONFIG_FILE).platforms.list | sort -b


.PHONY: elfimage rawimage uimage qemu vbox ux switch_ram_base \
        grub1iso grub2iso listentries shellcodeentry exportpack \
        fastboot fastboot_rawimage fastboot_uimage \
	check_and_adjust_ram_base listplatforms itb fvp

switch_ram_base:
	$(VERBOSE)$(call switch_ram_base_func,$(RAM_BASE))

check_base_dir:
	@if [ -z "$(CHECK_BASE_DIR)" ]; then                                  \
	  echo "Need to set CHECK_BASE_DIR variable";                         \
	  exit 1;                                                             \
	fi

BID_CHECKBUILD_LOG_REDIR_f = $(if $(BID_CHECKBUILD_LOG), 1>>$(BID_CHECKBUILD_LOG).$(strip $(1)).log) \
                             $(if $(BID_CHECKBUILD_LOG), 2>&1) #>$(BID_CHECKBUILD_LOG).$(strip $(1)).log)

.PRECIOUS: $(CHECK_BASE_DIR)/config.%/.kconfig
.PRECIOUS: $(CHECK_BASE_DIR)/config.%/.config.all
.PHONY: FORCE

checkbuild_prepare.%:
	$(if $(CHECK_INCREMENTAL),,rm -rf $(CHECK_BASE_DIR)/$(patsubst checkbuild_prepare.%,config.%,$@))

$(CHECK_BASE_DIR)/config.%/.kconfig: $(TEMPLDIR)/config.% checkbuild_prepare.%
	mkdir -p $(@D)
	cp $< $@

$(CHECK_BASE_DIR)/config.%/.config.all: $(CHECK_BASE_DIR)/config.%/.kconfig FORCE
	find $(@D) -xtype l -delete
	rm -rf $(@D)/pc
	$(MAKE) -j 1 O=$(@D) olddefconfig $(call BID_CHECKBUILD_LOG_REDIR_f, $*)

checkbuild.%: $(CHECK_BASE_DIR)/config.%/.config.all $(CHECK_BASE_DIR)/config.%/.kconfig check_base_dir
	$(MAKE) O=$(<D) BID_CHECKBUILD=1 report $(call BID_CHECKBUILD_LOG_REDIR_f, $*)
	$(MAKE) O=$(<D) BID_CHECKBUILD=1 tool $(call BID_CHECKBUILD_LOG_REDIR_f, $*)
	$(MAKE) O=$(<D) BID_CHECKBUILD=1 USE_CCACHE=$(strip $(USE_CCACHE)) BID_MESSAGE_TAG='$$(PKGNAME_DIRNAME) | $$(BUILD_ARCH)' $(CHECK_MAKE_ARGS) $(call BID_CHECKBUILD_LOG_REDIR_f, $*)
	$(VERBOSE)if [ -e $(<D)/ext-pkg ]; then \
	  echo "$(<D)/ext-pkg created. That must not happen in checkbuild."; \
	  exit 1; \
	fi
	$(if $(CHECK_REMOVE_OBJDIR),rm -rf $(<D))

checkbuild: $(if $(USE_CONFIGS),$(addprefix checkbuild.,$(USE_CONFIGS)),$(patsubst mk/defconfig/config.%, checkbuild.%, $(wildcard mk/defconfig/config.*)))

# Print version info for a command
#  $1: command
#  $2: (optional, default = -v) argument to get version
#  $3: (optional, default = none) redirects
define _ver_fun
	 @echo "$1 $(or $2,-v):"
	 @$1 $(or $2,-v) $3 || true
	 @echo

endef

# Print version info for command contained in variable, incl. variable name
#  Arguments: see _ver_fun
define _ver_fun_var
	@echo -n "$1: "
	$(call _ver_fun,$($1),$2,$3)
endef

# Variants of the above two to print multiple
_ver_fun_vars=$(foreach v,$1,$(call _ver_fun_var,$v,$2,$3))
_ver_funs=$(foreach v,$1,$(call _ver_fun,$v,$2,$3))

report:
	@echo -e $(EMPHSTART)"============================================================="$(EMPHSTOP)
	@echo -e $(EMPHSTART)" Note, this report might disclose private information"$(EMPHSTOP)
	@echo -e $(EMPHSTART)" Please review (and edit) before making it public"$(EMPHSTOP)
	@echo -e $(EMPHSTART)"============================================================="$(EMPHSTOP)
	@echo
	$(call _ver_fun,make)
	$(call _ver_fun_vars,CC CXX HOST_CC HOST_CXX,-v, 2>&1)
	$(call _ver_fun_var,LD)
	$(call _ver_funs,perl)
	$(call _ver_funs,python python2 python3,-V)
	$(call _ver_funs,svn git doxygen,--version)
	@echo "Shell is:"
	@ls -la /bin/sh || true
	@echo
	@echo "uname -a: "; uname -a
	@echo
	@echo "Distribution"
	@if [ -e "/etc/debian_version" ]; then                 \
	  if grep -qi ubuntu /etc/issue; then                  \
	    echo -n "Ubuntu: ";                                \
	    cat /etc/issue;                                    \
	  else                                                 \
	    echo -n "Debian: ";                                \
	  fi;                                                  \
	  cat /etc/debian_version;                             \
	elif [ -e /etc/gentoo-release ]; then                  \
	  echo -n "Gentoo: ";                                  \
	  cat /etc/gentoo-release;                             \
	elif [ -e /etc/SuSE-release ]; then                    \
	  echo -n "SuSE: ";                                    \
	  cat /etc/SuSE-release;                               \
	elif [ -e /etc/fedora-release ]; then                  \
	  echo -n "Fedora: ";                                  \
	  cat /etc/fedora-release;                             \
	elif [ -e /etc/redhat-release ]; then                  \
	  echo -n "Redhat: ";                                  \
	  cat /etc/redhat-release;                             \
	  if [ -e /etc/redhat_version ]; then                  \
	    echo "  Version: `cat /etc/redhat_version`";       \
	  fi;                                                  \
	elif [ -e /etc/slackware-release ]; then               \
	  echo -n "Slackware: ";                               \
	  cat /etc/slackware-release;                          \
	  if [ -e /etc/slackware-version ]; then               \
	    echo "  Version: `cat /etc/slackware-version`";    \
	  fi;                                                  \
	elif [ -e /etc/mandrake-release ]; then                \
	  echo -n "Mandrake: ";                                \
	  cat /etc/mandrake-release;                           \
	else                                                   \
	  echo "Unknown distribution";                         \
	fi
	@lsb_release -a || true
	@echo
	@echo "Running as PID / User"
	@id || true
	@echo
	@echo Locale info:
	@locale
	@echo
	@echo "Archive information:"
	@echo "SVN:"
	@svn info || true
	@echo "Git:"
	@git describe || true
	@echo
	@echo "CC       = $(CC) $(CARCHFLAGS) $(CCXX_FLAGS)"
	@echo "CXX      = $(CXX) $(CARCHFLAGS) $(CCXX_FLAGS)"
	@echo "HOST_CC  = $(HOST_CC)"
	@echo "HOST_CXX = $(HOST_CXX)"
	@echo "LD       = $(LD)"
	@echo "Paths"
	@echo "Current:   $$(pwd)"
	@echo "L4DIR:     $(L4DIR)"
	@echo "L4DIR_ABS: $(L4DIR_ABS)"
	@echo "OBJ_BASE:  $(OBJ_BASE)"
	@echo "OBJ_DIR:   $(OBJ_DIR)"
	@echo
	@for i in pkg \
	          ../kernel/fiasco/src/kern/ia32 \
	          ../kernel/fiasco/tool/preprocess/src/preprocess; do \
	  if [ -e $$i ]; then \
	    echo Path $$i found ; \
	  else                \
	    echo PATH $$i IS NOT AVAILABLE; \
	  fi \
	done
	@echo
	@echo Configuration:
	@for i in $(OBJ_DIR)/.config.all $(OBJ_DIR)/.kconfig   \
	          $(OBJ_DIR)/Makeconf.local                    \
	          $(L4DIR_ABS)/Makeconf.local                  \
	          $(OBJ_DIR)/conf/Makeconf.boot                \
	          $(L4DIR_ABS)/conf/Makeconf.boot; do          \
	  if [ -e "$$i" ]; then                                \
	    echo "______start_______________________________:";\
	    echo "$$i:";                                       \
	    cat $$i;                                           \
	    echo "____________________________end___________"; \
	  else                                                 \
	    echo "$$i not found";                              \
	  fi                                                   \
	done
	@echo -e $(EMPHSTART)"============================================================="$(EMPHSTOP)
	@echo -e $(EMPHSTART)" Note, this report might disclose private information"$(EMPHSTOP)
	@echo -e $(EMPHSTART)" Please review (and edit) before making it public"$(EMPHSTOP)
	@echo -e $(EMPHSTART)"============================================================="$(EMPHSTOP)

help::
	@echo
	@echo "Miscellaneous targets:"
	@echo "  switch_ram_base RAM_BASE=0xaddr"
	@echo "                   - Switch physical RAM base of build to 'addr'."
	@echo "  cont             - Continue building after fixing a build error."
	@echo "  clean            - Call 'clean' target recursively."
	@echo "  cleanfast        - Delete all directories created during build."
	@echo "  doc              - Generate documentation."
	@echo "                     The default behavior is building HTML with"
	@echo "                     graphics. To change the default behavior,"
	@echo "                     set DOC_VARIANT to one of the following values:"
	@echo "                     * DOC_VARIANT=fast: Build HTML without graphics."
	@echo "                     * DOC_VARIANT=full: Build HTML and a PDF with graphics."
	@echo "                       The PDF is named doc/source/l4re/latex/refman.pdf."
	@echo "                     * DOC_VARIANT=release: Build everything like 'full'"
	@echo "                       excluding internal information."
	@echo "  report           - Print out host configuration information."
	@echo "  help             - Print this help text."
	@echo "  test             - Run user-land tests and optionally also kernel tests."
	@echo "                     In order to run kernel tests, TEST_KUNIT_DIR must be set to"
	@echo "                     the directory containing test binaries (usually 'utest' in"
	@echo "                     the kernel build directory)."
	@echo "                     Use make's -jX parameter to run tests in parallel."
	@echo "  listplatforms    - List available platforms."

MAKE_J = $(patsubst -j%,%,$(filter -j%,$(MAKEFLAGS)))

TESTS := bid-tests/ $(if $(TEST_KUNIT_DIR),kunit-tests/)

.PHONY: test
test:
	$(VERBOSE)taparchive="$(TAPARCHIVE)"; \
	if [ -n "$${taparchive%%/*}" ]; then \
	  echo "ERROR: TAPARCHIVE must be an absolute path."; \
	  exit 1; \
	fi
	$(VERBOSE)if [ -z "$(TEST_KUNIT_DIR)" ]; then \
	  echo "INFO: TEST_KUNIT_DIR not provided. No kernel tests."; \
	fi
	$(VERBOSE)test_tmp_dir=$$(mktemp -d); \
	\
	ln -fs "$(OBJ_BASE)/test/t/$(ARCH)_$(CPU)/$(BUILD_ABI)" \
	       "$${test_tmp_dir}/bid-tests"; \
	\
	$(if $(TEST_KUNIT_DIR),\
	  $(L4DIR)/tool/bin/gen_kunit_test --ddir=$${test_tmp_dir}/kunit-tests \
	    --sdir=$(TEST_KUNIT_DIR) --obj-base=$(OBJ_BASE);) \
	\
	(cd $${test_tmp_dir} && \
	 prove $(if $(TAPARCHIVE),-a $(TAPARCHIVE)) $(if $(VERBOSE),,-v) \
	       $(if $(MAKE_J),-j $(MAKE_J)) \
	       -m -r \
	       $(filter bid-tests/% kunit-tests/%,$(TESTS)) \
	       $(addprefix bid-tests/,$(filter-out bid-tests/% kunit-tests/%,$(TESTS))) \
	       ); \
	rm -fr "$${test_tmp_dir}"

endif
