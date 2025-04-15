# -*- Makefile -*-
#
# L4Re Buildsystem
#
# Makefile-Template for test directories
#
# See doc/source/build_system.dox for further documentation
#
# Makeconf is used, see there for further documentation
# binary.inc is used, see there for further documentation

ifeq ($(origin _L4DIR_MK_TEST_MK),undefined)
_L4DIR_MK_TEST_MK=y

# Helper for qemu's smp flag
ifneq ($(filter $(ARCH),x86 amd64),)
qemu_smp = -smp $(1),cores=$(1)
else
qemu_smp = -smp $(1)
endif

# auto-fill TARGET with builds for test_*.c[c] if necessary
# TARGETS_$(ARCH) - contains a list of tests specific for this architecture
ifndef TARGET
TARGETS_CC := $(patsubst $(SRC_DIR)/%.cc,%,$(wildcard $(SRC_DIR)/test_*.cc))
$(foreach t, $(TARGETS_CC), $(eval SRC_CC_$(t) += $(t).cc))
TARGETS_C := $(patsubst $(SRC_DIR)/%.c,%,$(wildcard $(SRC_DIR)/test_*.c))
$(foreach t, $(TARGETS_C), $(eval SRC_C_$(t) += $(t).c))
TARGET += $(TARGETS_CC) $(TARGETS_C) $(TARGETS_$(ARCH))
endif

SYSTEMS ?= arm-l4f arm64-l4f mips-l4f x86-l4f amd64-l4f riscv-l4f
MODE ?= $(if $(CONFIG_BID_BUILD_TESTS_SHARED),shared,static)
TEST_MODE ?= default
ROLE = test.mk

include $(L4DIR)/mk/Makeconf

# define INSTALLDIRs prior to including install.inc, where the install-
# rules are defined.
ifeq ($(MODE),host)
INSTALLDIR_BIN_LOCAL    = $(OBJ_BASE)/test/bin/host/$(TEST_GROUP)
INSTALLDIR_TEST_LOCAL   = $(OBJ_BASE)/test/t/host/$(TEST_GROUP)
else
  ifeq ($(words $(VARIANTS)),1)
    INSTALLDIR_BIN_LOCAL    = $(OBJ_BASE)/test/bin/$(BID_install_subdir_base)/$(TEST_GROUP)
  else
    INSTALLDIR_BIN_LOCAL    = $(OBJ_BASE)/test/bin/$(BID_install_subdir_var)/$(TEST_GROUP)
  endif
  INSTALLDIR_TEST_LOCAL   = $(OBJ_BASE)/test/t/$(BID_install_subdir_base)/$(TEST_GROUP)
endif

$(GENERAL_D_LOC): $(L4DIR)/mk/test.mk $(SRC_DIR)/Makefile

ifneq ($(SYSTEM),) # if we have a system, really build

# There are two kind of targets:
#  TARGET - contains binary targets that actually need to be built first
#  EXTRA_TEST - contains tests where only test scripts are created
$(foreach t, $(TARGET) $(EXTRA_TEST), $(eval TEST_SCRIPTS += $(t).t))
$(foreach t, $(TARGET) $(EXTRA_TEST), $(eval TEST_TARGET_$(t) ?= $(t)))

# L4RE_ABS_SOURCE_DIR_PATH is used in gtest-internal.h to shorten absolute path
# names to L4Re relative paths.
CPPFLAGS += -DL4RE_ABS_SOURCE_DIR_PATH='"$(L4DIR_ABS)"'

# variables that are forwarded to the test runner environment
testvars_fix    :=  ARCH NED_CFG REQUIRED_MODULES KERNEL_CONF L4LINUX_CONF \
                    TEST_TARGET TEST_SETUP TEST_EXPECTED TEST_TAGS OBJ_BASE \
                    TEST_ROOT_TASK TEST_DESCRIPTION TEST_KERNEL_ARGS SIGMA0 \
                    TEST_PLATFORM_ALLOW TEST_PLATFORM_DENY TEST_MODE L4RE_CONF \
                    TEST_EXCLUDE_FILTERS
testvars_conf   := TEST_TIMEOUT TEST_EXPECTED_REPEAT
testvars_append := QEMU_ARGS MOE_ARGS TEST_ROOT_TASK_ARGS BOOTSTRAP_ARGS \

# Variable value, only if it does not come from the environment. Otherwise empty
non_env_var = $(if $(findstring environment,$(origin $1)),,$($1))
# use either a target-specific value or the general version of a variable
targetvar = $(or $(call non_env_var,$(1)_$(2)),$(call non_env_var,$(1)))

# This is the same as INSTALLFILE_LIB_LOCAL
INSTALLFILE_TEST_LOCAL = $(LN) -sf $(abspath $(1)) $(2)
DEFAULT_TEST_STARTER = $(L4DIR)/tool/bin/default-test-starter

$(TEST_SCRIPTS):%.t: $(GENERAL_D_LOC)
	$(VERBOSE)echo -e "#!/usr/bin/env bash\n\nset -a" > $@
	$(VERBOSE)echo 'L4DIR="$(L4DIR)"' >> $@
	$(VERBOSE)echo 'SEARCHPATH="$(if $(PRIVATE_LIBDIR),$(PRIVATE_LIBDIR):)$(INSTALLDIR_BIN_LOCAL):$(OBJ_BASE)/bin/$(ARCH)_$(CPU)/plain:$(OBJ_BASE)/bin/$(ARCH)_$(CPU)/$(BUILD_ABI):$(OBJ_BASE)/lib/$(ARCH)_$(CPU)/plain:$(OBJ_BASE)/lib/$(ARCH)_$(CPU)/$(BUILD_ABI):$(SRC_DIR):$(L4DIR)/conf/test"' >> $@
	$(VERBOSE)$(foreach v,$(testvars_fix), echo '$(v)="$(subst ",\",$(call targetvar,$(v),$(notdir $*)))"' >> $@;)
	$(VERBOSE)$(foreach v,$(testvars_conf), echo ': $${$(v):=$(call targetvar,$(v),$(notdir $*))}' >> $@;)
	$(VERBOSE)$(foreach v,$(testvars_append), echo '$(v)="$${$(v):+$${$(v)} }$(subst ",\",$(call targetvar,$(v),$(notdir $*)))"' >> $@;)
	$(if $(call targetvar,TEST_TAP_PLUGINS,$(*F)),\
		$(VERBOSE)echo 'TEST_TAP_PLUGINS="$(call targetvar,TEST_TAP_PLUGINS,$(*F)) $$TEST_TAP_PLUGINS"' >> $@,\
		$(VERBOSE)echo 'TEST_TAP_PLUGINS="$(if $(call targetvar,TEST_EXPECTED,$(*F)),OutputMatching:file=$(call targetvar,TEST_EXPECTED,$(*F)),BundleMode TAPOutput) $$TEST_TAP_PLUGINS"' >> $@)
	$(VERBOSE)echo ': $${BID_L4_TEST_HARNESS_ACTIVE:=1}' >> $@
	$(VERBOSE)echo 'TEST_TESTFILE="$$0"' >> $@
	$(VERBOSE)echo ': $${TEST_STARTER:=$(DEFAULT_TEST_STARTER)}' >> $@
	$(VERBOSE)echo 'set +a' >> $@
	$(VERBOSE)echo 'exec $$TEST_STARTER "$$@"' >> $@
	$(VERBOSE)chmod 755 $@
	@$(BUILT_MESSAGE)
	@$(call INSTALL_LOCAL_MESSAGE,$@)

# Calculate the list of installed .t files
TEST_SCRIPTS_INST := $(foreach t,$(TEST_SCRIPTS), $(INSTALLDIR_TEST_LOCAL)/$(notdir $(t)))

# Add a dependency for them
all:: $(TEST_SCRIPTS_INST)

# Install rule for the .t files
$(TEST_SCRIPTS_INST):$(INSTALLDIR_TEST_LOCAL)/%: %
	$(VERBOSE)$(call create_dir,$(INSTALLDIR_TEST_LOCAL))
	$(VERBOSE)$(call INSTALLFILE_TEST_LOCAL,$<,$@)

endif	# SYSTEM is defined, really build

include $(L4DIR)/mk/prog.mk
ROLE = test.mk

clean cleanall::
	$(VERBOSE)$(RM) $(TEST_SCRIPTS)

endif	# _L4DIR_MK_TEST_MK undefined
