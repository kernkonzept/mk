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

all::	$(foreach t,$(INSTALL_TARGET),$(call target_dir_local,$t)/$(t))
all:: $(EXTRA_INSTALL_GOALS)
install:: $(foreach t,$(INSTALL_TARGET),$(call target_dir,$t)/$(t))
install:: $(EXTRA_INSTALL_GOALS)

# with prog.mk, we copy
ifeq ($(ROLE),prog.mk)
$(foreach f,$(INSTALL_TARGET),$(INSTALLDIR_LOCAL)/$(f)):$(INSTALLDIR_LOCAL)/%:%
	@$(INSTALL_LOCAL_MESSAGE)
	$(VERBOSE)$(if $(INSTALLFILE_LOCAL),$(call create_dir,$(dir $@)))
	$(VERBOSE)$(call INSTALLFILE_LOCAL,$<,$@)
else
# with others, we symlink
# we check for each locally installed lib if either the symlink is correct or
# if we really need to update the target by executing INSTALLFILE_LOCAL.
.PHONY: $(foreach t,$(INSTALL_TARGET),$(call target_dir_local,$t)/$t)

define local_install_rule
$(call target_dir_local,$(1))/$(1):$(1)
	@$(if $(INSTALLFILE_LOCAL), \
		f="$$@"; \
		if [ ! $$< -ef $$@ -a $$< -nt $$@ ]; then \
		  $(if $(INSTALL_LOCAL_MESSAGE),$(INSTALL_LOCAL_MESSAGE);) \
		  $(INSTALL) -d $$(dir $$@); \
		  $$(call INSTALLFILE_LOCAL,$$<,$$@); \
		fi)
endef

$(foreach t,$(INSTALL_TARGET),$(eval $(call local_install_rule,$(t))))
endif

define install_rule
$(call target_dir,$(1))/$(1):$(1)
	@$(INSTALL_MESSAGE)
	$(VERBOSE)$(if $(INSTALLFILE),$(call create_dir,$$(dir $$@)))
	$(VERBOSE)$$(call INSTALLFILE,$$<,$$@)
endef

$(foreach t,$(INSTALL_TARGET),$(eval $(call install_rule,$(t))))

# unconditionally install on "make install"
.PHONY: $(foreach t,$(INSTALL_TARGET),$(call target_dir,$t)/$(t))

.general.d: $(L4DIR)/mk/install.inc

