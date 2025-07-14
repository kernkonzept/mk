# -*- Makefile -*-
# vim:set ft=make:
#
# L4Re Buildsystem
#
# This file holds rules, variables and functionality that is provided
# unconditionally so that everything in here can just be used at will. All
# makefiles in the build system should include this implicitly because it is
# included in Makeconf. If Makeconf is not wanted or needed, this file should
# be included explicitly.

# Only include this file once.
ifeq ($(origin _L4DIR_MK_UTIL),undefined)
_L4DIR_MK_UTIL=y

# Variables #
#############

# a nasty workaround for make-3.79/make-3.80. The former needs an additional
# $$ for $-quotation when calling a function.
BID_IDENT = $(1)
ifeq ($(call BID_IDENT,$$),)
  BID_DOLLARQUOTE = $$
endif

BID_COMMA  := ,
BID_POUND  := \#
BID_EMPTY  :=
BID_SPACE  := $(BID_EMPTY) $(BID_EMPTY)
BID_SQUOTE := '
BID_DQUOTE := "


# Strings #
###########

# Compare two strings, return something if they are unequal
# 1: string
# 2: string
BID_cmp_str_ne = $(filter-out _$(subst $(BID_SPACE),_SPC_,$1),_$(subst $(BID_SPACE),_SPC_,$2))

# Strip leading and trailing double quotes.
# 1: words to strip quotes from
strip_quotes = $(patsubst "%,%,$(patsubst %",%,$(1)))#"


# Commands #
############

# Print version info for a command
#  $1: command
#  $2: (optional, default = -v) argument to get version
#  $3: (optional, default = none) redirects
define ver_fun
  @echo "$1 $(or $2,-v):"
  @$1 $(or $2,-v) $3 || true
  @echo

endef

# Print version info for command contained in variable, incl. variable name
#  Arguments: see ver_fun
define ver_fun_var
  @echo -n "$1: "
  $(call ver_fun,$($1),$2,$3)
endef

# Variants of the above two to print multiple
ver_fun_vars=$(foreach v,$1,$(call ver_fun_var,$v,$2,$3))
ver_funs=$(foreach v,$1,$(call ver_fun,$v,$2,$3))

# Files #
#########

# Get all L4Re packages in a provided directory.
# 1: directory to locate projects in
BID_PRJ_DIR_MAX_DEPTH ?= 4
find_prj_dirs = $(shell $(L4DIR)/mk/pkgfind $(1) $(BID_PRJ_DIR_MAX_DEPTH))

# Create the directory if it does not exist yet.
# This only forks to a shell if target directory does not exist.
# The semicolon ensures that this can be used in a statement sequence.
# Make sure to place no additional semicolon after using this.
lessfork_mkdir = $(if $(wildcard $(1)),,$(MKDIR) $(1);)

# Create a directory.
# DEPRECATED: If you consider using this: Don't. This just exists for backwards
# compatibility.
# 1: directory name
define create_dir
  mkdir -p $(1)
endef

# Strip binary $(1) to $(2) and set target file mode to $(3)
# 1: binary to strip
# 2: stripped binary destination
# 3: target file mode
define copy_stripped_binary
  $(call lessfork_mkdir,$(dir $(2))/.debug) \
  ln -sf $(abspath $(1)) $(dir $(2))/.debug/$(1); \
  $(OBJCOPY) --strip-unneeded --add-gnu-debuglink=$(1) \
             $(1) $(2) >/dev/null 2>&1 \
    || ln -sf $(abspath $(1)) $(2); \
  chmod $(3) $(2)
endef

# Move $(2) to $(1) if content of both files differ
# 1: destination
# 2: source
define move_if_changed
  if test ! -r "$(1)" || ! cmp -s $(1) $(2); then \
    mv $(2) $(1); \
  else \
    rm $(2); \
  fi
endef

# Check if a provided path is absolute and exit with an error if not.
# 1: variable name (for error)
# 2: path to check
define check_path_absolute
  $(if $(patsubst /%,,$(2)),$(error Path $(1)=$(2) is not absolute),$(2))
endef

# DEPRECATED
# This function only exists for backwards compatibility.
# Please use abspath directly instead of this indirection.
# synonym for "abspath"
# 1: relative path
#
# Note: We need the backslash after the warning for the function to still work.
#       Otherwise there would be a line break.
define absfilename
  $(warning DEPRECATED: using absfilename in a Makefile is deprecated. Please use abspath directly.) \
  $(abspath $(1))
endef

findfile = $(firstword $(wildcard $(addsuffix /$(1),$(2))) $(1)_NOT_FOUND)

is_dir = $(shell test -d '$(1)' && echo yes)

# Generate the dotted name of a file name.
# That is "<directoryname>.<filename>"
# 1: filename
BID_dot_fname = $(dir $1).$(notdir $1)

endif # _L4DIR_MK_UTIL undefined

