# -*- Makefile -*-
#
# L4Re Buildsystem
#
# Makefile-Template for library directories
#
# install.inc is used, see there for further documentation
# binary.inc is used, see there for further documentation


ifeq ($(origin _L4DIR_MK_LIB_MK),undefined)
_L4DIR_MK_LIB_MK=y

ROLE = lib.mk

ifeq ($(CONFIG_MMU),)
TARGET := $(filter-out %.so,$(TARGET))
endif

include $(L4DIR)/mk/Makeconf

# define INSTALLDIRs prior to including install.inc, where the install-
# rules are defined. Same for INSTALLDIR.
ifeq ($(MODE),host)
INSTALLDIR_LIB		?= $(DROPS_STDDIR)/lib/host
INSTALLDIR_LIB_LOCAL	?= $(OBJ_BASE)/lib/host
else
INSTALLDIR_LIB		?= $(DROPS_STDDIR)/lib/$(subst -,/,$(SYSTEM))
INSTALLDIR_LIB_LOCAL	?= $(OBJ_BASE)/lib/$(subst -,/,$(SYSTEM))
endif

do_strip=$(and $(CONFIG_BID_STRIP_BINARIES),$(filter %.so,$(1)))
INSTALLFILE_LIB         ?= $(if $(call do_strip,$(1)),                      \
                                $(call copy_stripped_binary,$(1),$(2),644), \
                                $(INSTALL) -m 644 $(1) $(2))
INSTALLFILE_LIB_LOCAL   ?= $(if $(call do_strip,$(1)),                      \
                                $(call copy_stripped_binary,$(1),$(2),644), \
                                $(LN) -sf $(abspath $(1)) $(2))

INSTALLFILE		= $(INSTALLFILE_LIB)
INSTALLDIR		= $(INSTALLDIR_LIB)
INSTALLFILE_LOCAL	= $(INSTALLFILE_LIB_LOCAL)
INSTALLDIR_LOCAL	= $(INSTALLDIR_LIB_LOCAL)

# our mode
MODE			?= lib

# sanity check for proper mode
ifneq ($(filter-out lib host,$(MODE)),)
$(error MODE=$(MODE) not possible when building libraries)
endif

# all libraries are built using the wraped utcb-getter
CPPFLAGS          += -DL4SYS_USE_UTCB_WRAP=1

# include all Makeconf.locals, define common rules/variables
include $(L4DIR)/mk/binary.inc
$(GENERAL_D_LOC): $(L4DIR)/mk/lib.mk

ifneq ($(SYSTEM),) # if we are a system, really build

TARGET_LIB        := $(TARGET) $(TARGET_$(OSYSTEM))
TARGET_SHARED     := $(filter     %.so,$(TARGET_LIB))
TARGET_PIC        := $(filter     %.p.a,$(TARGET_LIB))

TARGET_STANDARD   := $(filter-out $(TARGET_SHARED) $(TARGET_PIC), $(TARGET_LIB))

$(call GENERATE_PER_TARGET_RULES,$(TARGET_STANDARD))
$(call GENERATE_PER_TARGET_RULES,$(TARGET_PIC) $(TARGET_SHARED),.s)

TARGET_PROFILE  := $(patsubst %.a,%.pr.a,\
			$(filter $(BUILD_PROFILE),$(TARGET_STANDARD)))
TARGET_PROFILE_SHARED := $(filter %.so,$(TARGET_PROFILE))
TARGET_PROFILE_PIC := $(patsubst %.a,%.p.a,\
			$(filter $(BUILD_PIC),$(TARGET_PROFILE)))

$(call GENERATE_PER_TARGET_RULES,$(TARGET_PROFILE),.pr)
$(call GENERATE_PER_TARGET_RULES,$(TARGET_PROFILE_PIC) $(TARGET_PROFILE_SHARED),.pr)

TARGET	+= $(TARGET_$(OSYSTEM))
TARGET	+= $(TARGET_PROFILE) $(TARGET_PROFILE_SHARED) $(TARGET_PROFILE_PIC)

# define some variables different for lib.mk and prog.mk
LDFLAGS += $(addprefix -L, $(PRIVATE_LIBDIR) $(PRIVATE_LIBDIR_$(OSYSTEM)) $(PRIVATE_LIBDIR_$@) $(PRIVATE_LIBDIR_$@_$(OSYSTEM)))
LDFLAGS += $(addprefix -L, $(L4LIBDIR))
LDFLAGS += $(LIBCLIBDIR)
LDFLAGS_SO += -shared $(call BID_mode_var,LDFLAGS_SO)


LDSCRIPT       = $(LDS_so)
LDSCRIPT_INCR ?= /dev/null

# install.inc eventually defines rules for every target
include $(L4DIR)/mk/install.inc

# Ada needs the binder file, if we bind the ada lib.
# Request binding by setting ADA_BIND_LIB=y. The binder file will correspond to
# the name of the target and the expectation is that there was an ALI file with
# the target name. It is expected that the entry object of libfoo is called foo
# The binder file is added to the objects of the target.
ifneq ($(strip $(SRC_ADA)$(foreach t,$(TARGET),$(SRC_ADA_$(t)))),)
ifneq ($(ADA_BIND_LIB),)
$(foreach t,$(TARGET),$(if $(SRC_ADA_$(t))$(SRC_ADA),\
            $(eval OBJS_$(t) += b~$(basename $(t)).o)\
            $(eval $(t): b~$(basename $(t)).o)))

b~lib%.o: %.ali
	@$(call COMP_MESSAGE, from $(<F))
	$(VERBOSE)$(ADAC) $(ADACFLAGS) -g -z -b $* -bargs -L$* -n
	$(VERBOSE)$(ADAC) -g -c b~$*
	$(VERBOSE)mv b~$*.o b~lib$*.o
endif
endif

ifeq ($(NOTARGETSTOINSTALL),)
PC_LIBS     ?= $(sort $(patsubst lib%.so,-l%,$(TARGET_SHARED) \
                      $(patsubst lib%.a,-l%,$(TARGET_STANDARD))))

PC_FILENAME  ?= $(PKGNAME)
PC_FILENAMES ?= $(PC_FILENAME)
PC_FILES     := $(if $(filter std,$(VARIANT)),$(foreach pcfile,$(PC_FILENAMES),$(OBJ_BASE)/pc/$(pcfile).pc))

PC_LIBS_PIC ?= $(patsubst lib%.p.a,-l%.p,$(TARGET_PIC))

# 1: basename
# 2: pcfilename
# 3: optional prefix
get_cont = $(if $($(1)_$(2)),$(3)$($(1)_$(2)),$(if $($(1)),$(3)$($(1))))

# 1: pcfile
get_extra = $(call get_cont,PC_EXTRA,$(1))$\
            $(call get_cont,PC_LIBS_PIC,$(1),$(newline)Libs_pic= )$\
            $(call get_cont,PC_LINK_LIBS,$(1),$(newline)Link_Libs= )$\
            $(call get_cont,PC_LINK_LIBS_PIC,$(1),$(newline)Link_Libs_pic= )

# Ths must contain all the contents of all possible PC files as used in
# below generate_pcfile
PC_FILES_CONTENTS := $(strip $(foreach pcfile,$(PC_FILENAMES),\
  $(call get_cont,CONTRIB_INCDIR,$(pcfile)) \
  $(call get_cont,PC_LIBS,$(pcfile)) \
  $(call get_cont,REQUIRES_LIBS,$(pcfile)) \
  $(call get_cont,PC_CFLAGS,$(pcfile)) $(call get_extra,$(pcfile))))

ifneq ($(PC_FILES_CONTENTS),)

# when adding something to generate_pcfile it must also be added to the
# PC_FILES_CONTENTS above, otherwise PC files may not be generated
$(patsubst %,$(OBJ_BASE)/pc/%.pc,$(PC_FILENAMES)):$(OBJ_BASE)/pc/%.pc: $(GENERAL_D_LOC)
	@$(call GEN_MESSAGE,$(@F))
	$(VERBOSE)$(call generate_pcfile,$*,$@,$(call get_cont,CONTRIB_INCDIR,$*),$(call get_cont,PC_LIBS,$*),$(call get_cont,REQUIRES_LIBS,$*),$(call get_cont,PC_CFLAGS,$*),$(call get_extra,$*))

all:: $(PC_FILES)

endif
endif

DEPS	+= $(foreach file,$(TARGET), $(call BID_LINK_DEPS,$(file)))

$(filter-out $(LINK_INCR) %.so %.ofl %.o.a %.o.pr.a, $(TARGET)):%.a: $(OBJS) $(GENERAL_D_LOC)
	@$(AR_MESSAGE)
	$(VERBOSE)$(call create_dir,$(@D))
	$(VERBOSE)$(RM) $@
	$(VERBOSE)$(AR) crs$(if $(filter %.thin.a,$@),T) $@ \
	  $(foreach o,$(OBJS),$(if $(filter %.ofl,$o),$(file <$o),$o))
	@$(BUILT_MESSAGE)

# Object File List - just a list of object file paths for later static linking
$(filter %.ofl, $(TARGET)):%.ofl: $(OBJS) $(GENERAL_D_LOC)
	@$(AR_MESSAGE)
	$(VERBOSE)$(call create_dir,$(@D))
	$(VERBOSE)printf '%s ' $(realpath $(OBJS)) > $@
	@$(BUILT_MESSAGE)

# shared lib
$(filter %.so, $(TARGET)):%.so: $(OBJS) $(LIBDEPS) $(GENERAL_D_LOC)
	@$(LINK_SHARED_MESSAGE)
	$(VERBOSE)$(call create_dir,$(@D))
	$(VERBOSE)$(call MAKEDEP,$(LD)) $(BID_LINK) -MD -MF $(call BID_link_deps_file,$@) -o $@ $(LDFLAGS_SO) \
	  $(LDFLAGS) $(OBJS) $(addprefix -PC,$(REQUIRES_LIBS))
	@$(BUILT_MESSAGE)

# build an object file (which looks like a lib to a later link-call), which
# is either later included as a whole or not at all (important for static
# constructors)
LINK_INCR_TARGETS = $(filter $(LINK_INCR) %.o.a %.o.pr.a, $(TARGET))
$(LINK_INCR_TARGETS):%.a: $(OBJS) $(LIBDEPS) $(foreach x,$(LINK_INCR_TARGETS),$(LINK_INCR_ONLYGLOBSYMFILE_$(x)))
	@$(LINK_PARTIAL_MESSAGE)
	$(VERBOSE)$(call create_dir,$(@D))
	$(VERBOSE)$(call MAKEDEP,$(LD)) $(LD) \
	   -T $(LDSCRIPT_INCR) \
	   -o $@ -r $(OBJS) $(LDFLAGS)
	$(if $(LINK_INCR_ONLYGLOBSYM_$@)$(LINK_INCR_ONLYGLOBSYMFILE_$@), \
	   $(VERBOSE)$(OBJCOPY) \
	   $(foreach f,$(LINK_INCR_ONLYGLOBSYMFILE_$@),--keep-global-symbols=$(f)) \
	   $(foreach f,$(LINK_INCR_ONLYGLOBSYM_$@),-G $(f)) \
	   $@)
	@$(BUILT_MESSAGE)

endif	# architecture is defined, really build

.PHONY: all clean cleanall config help install oldconfig txtconfig
-include $(DEPSVAR)
help::
	@echo "  all            - compile and install the libraries locally"
ifneq ($(SYSTEM),)
	@echo "                   to $(INSTALLDIR_LOCAL)"
endif
	@echo "  install        - compile and install the libraries globally"
ifneq ($(SYSTEM),)
	@echo "                   to $(INSTALLDIR)"
endif
	@echo "  scrub          - delete backup and temporary files"
	@echo "  clean          - delete generated object files"
	@echo "  cleanall       - delete all generated, backup and temporary files"
	@echo "  help           - this help"
	@echo
ifneq ($(SYSTEM),)
	@echo "  libraries are: $(TARGET)"
else
	@echo "  build for architectures: $(TARGET_SYSTEMS)"
endif

endif	# _L4DIR_MK_LIB_MK undefined
