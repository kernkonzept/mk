# -*- Makefile -*-
# vim:et:ts=8:ft=make:
#
# Makefile-Include for defining modes

LIBC_INCLUDE   = $(BID_NOSTDINC)                                   \
                 -I$(OBJ_BASE)/include/uclibc                      \
                 $(if $(CONFIG_USE_DROPS_STDDIR),                  \
                  -I$(DROPS_STDDIR)/include/uclibc)                \
                 $(I_GCCINCDIR)

LIBCXX_INCLUDE = -I$(OBJ_BASE)/include/contrib/libstdc++-v3        \
                 $(if $(CONFIG_USE_DROPS_STDDIR),                  \
                   -I$(DROPS_STDDIR)/include/contrib/libstdc++-v3)

# Select default compiler runtime libraries based on whether targeting system
# with L4 API. The pure compiler runtime libraries do not use L4 specific APIs.
COMPILER_RT-l4api-plain := compiler-rt-pure
COMPILER_RT-l4api-l4f   := compiler-rt
COMPILER_RT   ?= $(COMPILER_RT-l4api-$(L4API))

#############################################################################

STATIC_PIE_LDFLAGS = $(if $(or $(CONFIG_BID_PIE_ALL), \
                               $(and $(CONFIG_BID_PIE_VOLUNTARY),$(BID_CAN_PIE))), \
                       -static-pie,-static)

################################
# sigma0 mode
################################

BID_SUPPORTED_all_sigma0        = y
LIBCINCDIR_all_sigma0           = $(LIBC_INCLUDE)
REQUIRES_LIBS_all_sigma0        = $(COMPILER_RT)
LDFLAGS_all_sigma0              = $(STATIC_PIE_LDFLAGS) -gc-sections


################################
# static mode
################################

BID_SUPPORTED_all_static        = y
LIBCINCDIR_all_static           = $(LIBCXX_INCLUDE) $(LIBC_INCLUDE)
REQUIRES_LIBS_all_static        = stdlibs $(COMPILER_RT)
LDFLAGS_all_static              = $(STATIC_PIE_LDFLAGS) -gc-sections

#####################################
# shared mode -- programs are linked against shared libs
#####################################
BID_SUPPORTED_all_shared        = y
LIBCINCDIR_all_shared           = $(LIBCXX_INCLUDE) $(LIBC_INCLUDE)
REQUIRES_LIBS_all_shared        = stdlibs-sh $(COMPILER_RT)
LDFLAGS_all_shared              = -gc-sections

################################
# l4linux mode
################################

BID_SUPPORTED_all_l4linux       = y
LIBCINCDIR_all_l4linux          =
REQUIRES_LIBS_all_l4linux       = 
LDFLAGS_all_l4linux             = -gc-sections

################################
# Targetsys mode
################################

BID_SUPPORTED_all_targetsys     = y
LDFLAGS_all_targetsys           = -gc-sections

#####################################
# lib mode -- options when building libs
#####################################

BID_SUPPORTED_all_lib            = y
LIBCINCDIR_all_lib               = $(LIBCXX_INCLUDE) $(LIBC_INCLUDE)
# Libraries need include directories of compiler runtime. Cannot use
# REQUIRES_LIBS here, because a library that links against compiler-rt-pure can
# still be used by a program that links against compiler-rt. With REQUIRES_LIBS
# the program would be linked against both compiler-rt-pure and compiler-rt.
REQUIRES_CFLAGS_all_lib          = $(COMPILER_RT)
# Shared libraries need hidden symbols from compiler runtime.
LDFLAGS_SO_all_lib               = $(addprefix -PC,$(COMPILER_RT))

#####################################
# host mode -- no L4 specifics
#####################################

BID_SUPPORTED_all_host = y
LIBCINCDIR_all_host    =
REQUIRES_LIBS_all_host =
LDFLAGS_all_host       =
NOPICFLAGS_all_host   ?=
NOPIEFLAGS_all_host   ?=


#####################################
# assets building mode
#####################################

BID_SUPPORTED_all_assets = y
