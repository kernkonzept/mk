# -*- Makefile -*-
# vim:set ft=make:
#
# L4Re Buildsystem
#
# Makefile-Include for install-rules
#
# INSTALL_TARGET and INSTALL_TARGET_$(ARCH) contain the targets to be
# installed. If they are both empty, and NOTARGETSTOINSTALL is not set,
# they are set to TARGET and TARGET_$(ARCH).
#
# INSTALLDIR and INSTALLDIR_LOCAL is the dir the files will be installed
# in and must be set prior to including this file. INSTALLDIR is used by the
# target "install" and "INSTALLDIR_LOCAL" by the target "all".
#
# The target "all" is made depending on the installed files in
# INSTALLDIR_LOCAL. "install" on the files in INSTALLDIR. Another
# difference is that "all" results in using the variable
# $(INSTALLFILE_LOCAL) to install the files and "install" in using
# $(INSTALLFILE). This allows the difference between linking and actually
# copying (with stripping for bins).

ifndef INSTALL_TARGET_$(OSYSTEM)
ifndef NOTARGETSTOINSTALL
INSTALL_TARGET?=$(TARGET)
endif
endif
INSTALL_TARGET += $(INSTALL_TARGET_$(OSYSTEM))

target_dir_local=$(or $(INSTALLDIR_LOCAL_$1),$(INSTALLDIR_LOCAL))
target_dir=$(or $(INSTALLDIR_$1),$(INSTALLDIR))

all::     $(EXTRA_INSTALL_GOALS)
install:: $(foreach t,$(INSTALL_TARGET),$(call target_dir,$t)/$(t))
install:: $(EXTRA_INSTALL_GOALS)

ifeq ($(ROLE),prog.mk)
# with prog.mk, we copy

# Set the provided target as a prerequisite for all and generate the install
# rule for it
# args:
#  1: target file
#  2: source file
define local_install_rule
all:: $(1)

$(1):$(2)
	@$(call INSTALL_LOCAL_MESSAGE,$(notdir $(1)))
	$(VERBOSE)$(if $(INSTALLFILE_LOCAL),$(MKDIR) $$(dir $$@))
	$(VERBOSE)$(call INSTALLFILE_LOCAL,$$<,$$@)
endef

# generate local install rule for variant directory
$(foreach t,$(INSTALL_TARGET), $(eval $(call local_install_rule,$(INSTALLDIR_LOCAL)/$t,$t)))
# generate local install rule for variant target in base directory
$(foreach t,$(INSTALL_TARGET),                                                  \
  $(eval $(call local_install_rule,$(INSTALLDIR_LOCAL_BASE)/$t.$(VARIANT),$t)))

# variant is std or empty
VARIANT_IS_STD      := $(filter std,$(or $(VARIANT),std))
# there only is one variant (which is this one)
ONLY_ONE_VARIANT    := $(filter 1,$(words $(VARIANTS)))
# variant is the first in the list of not modified variants
FIRST_IN_UNMODIFIED := $(filter $(VARIANT),                                                  \
                         $(firstword $(foreach v,$(VARIANTS),$(if $(findstring +,$v),,$v))))

INSTALL_AS_DEFAULT  := $(or $(VARIANT_IS_STD),$(ONLY_ONE_VARIANT),$(FIRST_IN_UNMODIFIED))

ifneq ($(INSTALL_AS_DEFAULT),)
  # generate local install rule for default target in base directory
  $(foreach t,$(INSTALL_TARGET),                                       \
    $(eval $(call local_install_rule,$(INSTALLDIR_LOCAL_BASE)/$t,$t)))
endif

FIRST_COV    := $(firstword $(filter %+cov, $(VARIANTS)))
IS_FIRST_COV := $(filter $(VARIANT),$(FIRST_COV))

ifneq ($(IS_FIRST_COV),)
  # generate local install rule for default cov target in base directory
  $(foreach t,$(INSTALL_TARGET),                                           \
    $(eval $(call local_install_rule,$(INSTALLDIR_LOCAL_BASE)/$t.cov,$t)))
endif

else
# with others, we symlink
# we check for each locally installed lib if either the symlink is correct or
# if we really need to update the target by executing INSTALLFILE_LOCAL.

# Set the provided target as a prerequisite for all and generate the install
# rule for it
# args:
#  1: target file
#  2: source file
define local_install_rule
all:: $(1)

.PHONY: $(1)
$(1):$(2)
	$(VERBOSE)$(if $(INSTALLFILE_LOCAL),              \
	  if [ ! $$< -ef $$@ -a $$< -nt $$@ ]; then       \
	    $(call INSTALL_LOCAL_MESSAGE,$$(@F));         \
	    $(INSTALL) -d $$(@D);                         \
	    $$(call INSTALLFILE_LOCAL,$$<,$$@);           \
	  fi)
endef

# generate local install rule for regular target
$(foreach t,$(INSTALL_TARGET),                                             \
  $(eval $(call local_install_rule,$(call target_dir_local,$t)/$t,$t)))
endif

define install_rule
$(call target_dir,$(1))/$(1):$(1)
	@$(INSTALL_MESSAGE)
	$(VERBOSE)$(if $(INSTALLFILE),$(MKDIR) $$(dir $$@))
	$(VERBOSE)$$(call INSTALLFILE,$$<,$$@)
endef

$(foreach t,$(INSTALL_TARGET),$(eval $(call install_rule,$(t))))

# unconditionally install on "make install"
.PHONY: $(foreach t,$(INSTALL_TARGET),$(call target_dir,$t)/$(t))

.general.d: $(L4DIR)/mk/install.inc

