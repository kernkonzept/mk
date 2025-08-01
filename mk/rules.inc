# vi:ft=make
#
# L4Re Buildsystem
#
# This makefile contains the generator for our basic pattern rules.
# These generators allow easy instantiation of own rule sets.

include $(L4DIR)/mk/util.mk

# variables for instantiating make rules.
# for C++ compile (CXX) use $(CXX), $(INT_CXX_NAME), and $(CXXFLAGS)
BID_CXX_COMPILER = CXX
BID_CXX_COMPILER_INT_NAME = INT_CXX_NAME
# for C compile (C) use $(CC), $(INT_CPP_NAME), and $(CFLAGS)
BID_C_COMPILER = CC
BID_C_COMPILER_INT_NAME = INT_CPP_NAME
# for F compile (Fortran) use $(FC)
BID_F_COMPILER = FC
BID_F_COMPILER_INT_NAME = FC
# for AS compile (AS) use $(CC), $(INT_CPP_NAME), and $(ASFLAGS)
BID_AS_COMPILER = CC
BID_AS_COMPILER_INT_NAME = INT_CPP_NAME
# for Ada compile use $(ADAC), $(INT_ADAC_NAME), and $(ADAFLAGS)
BID_ADAC_COMPILER = ADAC
BID_ADAC_COMPILER_INT_NAME = INT_ADAC_NAME


# Template for our make rules.
# arg1: the target or target pattern (e.g., %.o)
# arg2: the prerequisites (e.g., %.c)
# arg3: the compiler pattern, used for determining the compiler
#       variables and default flags (e.g., CXX). The rule uses
#       $($(BID_<arg3>_COMPILER)) as compiler,
#       $($(BID_<arg3>_COMPILER_INT_NAME)) for gendep, and
#       $(<arg3>FLAGS) as flags
# arg4: extra command line flags for the compile
#
# The check for BID_OBJ_SRC_$@ ensures that we only compile files within our
# current set of source files. Due to dependency tracking it might happen
# that a .d file contains a dependency to a .o file that is not in our
# current set of files to compile (it might not work due to config changes).
define BID_MAKE_RULE_template_gendep
$(1): $(2) $(GENERAL_D_LOC)
	@$$(COMP_MESSAGE)
	$$(VERBOSE)$$(call lessfork_mkdir,$$(@D))
	$$(VERBOSE)$$(if $$(BID_OBJ_SRC_$$@),$$(call \
	  MAKEDEP,$$($(BID_$(3)_COMPILER_INT_NAME))) $$($(BID_$(3)_COMPILER)) \
	  -c $$(DEPEND_FLAG) $$(CPPFLAGS) $$($(3)FLAGS_EARLY) $$($(3)FLAGS) $(4) $$< \
	  -o $$@)
	$$(DEPEND_VERBOSE)$$(if $$(BID_OBJ_SRC_$$@),$$(call \
	  DEPEND_EXTEND_FUNC, $$(*F).d, $$(dir $$@).$$(notdir $$@).d))
endef

prereqs_changed = $(filter-out FORCE .general.d,$?)

escape_cmd = $(subst $$,$$$$,$(subst $(BID_POUND),\$(BID_POUND),$(subst $(BID_SQUOTE),'\$(BID_SQUOTE)',$1)))

buildinfo_missing = $(if $(filter $(origin deps_$@),undefined),build-deps-$@)$(if $(source_$@),,build-source-$@)

ifneq ($(BID_TRACE),)
  bid_trace = $(if $(wildcard $@), \
                $(if $(prereqs_changed), because prerequisites '$(prereqs_changed)' changed, \
                  $(if $(buildinfo_missing), because build info missing, \
                    $(if $(call BID_cmp_str_ne,$1,$(savedcmd_$@)), because command changed))), \
                because target missing)
endif

define BID_call_compiler_default
  $(if $(buildinfo_missing)$(prereqs_changed)$(call BID_cmp_str_ne,$1,$(savedcmd_$@)), \
      $(call COMP_MESSAGE,$(bid_trace));                                      \
      $(call lessfork_mkdir,$(@D))                                            \
      set +o pipefail;                                                        \
      $1 || exit 1;                                                           \
      $(FIXDEP) $(call BID_dot_fname,$@).d                                    \
                   $@ '$(call escape_cmd,$1)' > $(call BID_dot_fname,$@).cmd; \
      $(RM) $(call BID_dot_fname,$@).d)
endef

BID_call_compiler_F = $(call COMP_MESSAGE); $(call lessfork_mkdir,$(@D)) $1

BID_call_compiler_ADAC = $(call COMP_MESSAGE); $(call lessfork_mkdir,$(@D)) $1

# Arg and further descriptions: See BID_MAKE_RULE_template_gendep
#
# BID_call_compiler_default works only for gcc/clang as gfortran generates
# different deps file that fixdep cannot process. For this reason we compile
# Fortran the traditional way of depending on $(GENERAL_D_LOC).
# The comma placement is on purpose to avoid a leading space in the command.
# Template for our make rules (make rules that do not use gendep)
# The $\ statement after the $(if ...) statement must be kept to omit a space
# prior to the BID_$(3)_COMPILER statement.
define BID_MAKE_RULE_template_nongendep
$1: $2 $(if $(BID_call_compiler_$3),$(GENERAL_D_LOC),FORCE)
	$$(VERBOSE)$$(if $$(BID_OBJ_SRC_$$@),$$(call \
	              $(if $(BID_call_compiler_$3),\
		        BID_call_compiler_$3,\
	                BID_call_compiler_default),$\
	              $$($(BID_$(3)_COMPILER)) \
		      -c $(if $(filter y Y 1,$(NO_CPP_$(3))),,$$(strip \
	                      $$(DEPFLAGS) $$(DEPFLAGS_$(3)) $$(CPPFLAGS))) \
	              $$($(3)FLAGS_EARLY) $$($(3)FLAGS) $(4) $$< -o $$@ \
	              $$($(3)_COLLECT_REDIR)))
endef

# which template rule do we really use
BID_MAKE_RULE_template = $(BID_MAKE_RULE_template_nongendep)

#
# Generate the default set of make rules.
# targets: .o, .s.o, .pr.o, and .pr.s.o
#
define BID_GENERATE_DEFAULT_MAKE_RULES
  $(call BID_MAKE_RULE_template,$(1).o,$(2),$(3),$(4) $$(call BID_mode_var,NOPICFLAGS))
  $(call BID_MAKE_RULE_template,$(1).s.o,$(2),$(3),$(4) $$(PICFLAGS))
  $(call BID_MAKE_RULE_template,$(1).pr.o,$(2),$(3),$(4) $$(call BID_mode_var,NOPICFLAGS) -DPROFILE -pg)
  $(call BID_MAKE_RULE_template,$(1).pr.s.o,$(2),$(3),$(4) $$(PICFLAGS) -DPROFILE -pg)
endef

#
# Generate the C++ set of make rules.
# prerequisites: %.<arg1>  (usually %.cc)
# targets: %.o, %.s.o, %.ne.o, %.s.ne.o, %.pr.o, and %.pr.s.o
#
define BID_GENERATE_CXX_MAKE_RULES
  $(call BID_GENERATE_DEFAULT_MAKE_RULES,%,%.$(1),CXX)
  $(call BID_MAKE_RULE_template,%.ne.o,%.$(1),CXX,$$(CXXFLAGS_NOEXC) $$(call BID_mode_var,NOPICFLAGS))
  $(call BID_MAKE_RULE_template,%.s.ne.o,%.$(1),CXX,$$(CXXFLAGS_NOEXC) $$(PICFLAGS))
endef

#
# Generate the C set of make rules.
# prerequisites: %.<arg1> (usually %.c)
# targets: %.o, %.s.o, %.pr.o, and %.pr.s.o
#
define BID_GENERATE_C_MAKE_RULES
  $(call BID_GENERATE_DEFAULT_MAKE_RULES,%,%.$(1),C)
endef

#
# Generate the F set of make rules.
# prerequisites: %.<arg1> (usually %.f90)
# targets: %.o, %.s.o, %.pr.o, and %.pr.s.o
#
define BID_GENERATE_F_MAKE_RULES
  $(call BID_GENERATE_DEFAULT_MAKE_RULES,%,%.$(1),F)
endef

#
# Generate the ADA set of make rules.
# prerequisites: %.<arg1> (usually %.adb or %.ads)
# targets: %.o
define BID_GENERATE_ADA_MAKE_RULES
  $(call BID_MAKE_RULE_template,%.o %.i,%.$(1),ADAC)
endef

#
# Generate the ASM set of make rules.
# prerequisites: %.<arg1> (usually %.S)
# targets: %.o, %.s.o, %.pr.o, and %.pr.s.o
#
define BID_GENERATE_ASM_MAKE_RULES
  $(call BID_GENERATE_DEFAULT_MAKE_RULES,%$(BID_S_INFIX),%.$(1),AS,$(if \
    $(filter .$(1),$(BID_ASM_CPP_FILE_EXTENSIONS)),-x assembler-with-cpp,))
endef

#
# arg 1: target pattern
#     2: source pattern
#     3: compiler
#     4: compiler options
define BID_GENERATE_I_MAKE_RULE
$(1): $(2) FORCE
	@$$(COMP_MESSAGE)
	$$(VERBOSE)$$(call lessfork_mkdir,$$(@D))
	$$(VERBOSE)$(3) -E -H -dD $$(CPPFLAGS) $(4) $$(abspath $$<) -o $$@
	$$(VERBOSE)$$(if $$(DO_SHOW_RESULT_FILE),$$(PAGER) $$@)
endef

#
# arg 1: source pattern
#     2: compiler
#     3: compiler options
define BID_GENERATE_S_MAKE_RULE
%.S: $(1) FORCE
	@$$(COMP_MESSAGE)
	$$(VERBOSE)$$(call lessfork_mkdir,$$(@D))
	$$(VERBOSE)$(2) -S $(3) $(CPPFLAGS) $$(abspath $$<) -fverbose-asm -o $$@
endef
