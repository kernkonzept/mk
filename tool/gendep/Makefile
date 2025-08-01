L4DIR  ?= ../..
PKGDIR ?= .
include $(L4DIR)/mk/Makeconf

VERSION	= 0.2
CSRC	= deptrack.c syscall.c
MAN	= man/man7/libgendep.so.7
MAN_SRC	= manpage.dox Doxyfile
DDIR	= gendep-$(VERSION)

CFLAGS	= -fPIC -Wall -Wextra -pedantic -g -O2

USE_M_FLAG := $(if $(call check_compiler_opt,-m32,,$(HOST_CC),c),1)

M_FLAG = $(if $(USE_M_FLAG),-m$(1))

checkbuild = $(shell if    $(HOST_CC) $(call M_FLAG,$(1)) \
                                 -c -o /dev/null $(SRC_DIR)/syscall.c 2> /dev/null \
                        && echo 'int main(){}' | $(HOST_CC) $(call M_FLAG,$(1)) \
			                               -o /dev/null -x c - \
                        > /dev/null 2>&1 ; then echo 1; fi)

OBJS96  = $(addprefix $(OBJ_DIR)/,$(CSRC:.c=.o))
OBJS32	= $(addprefix $(OBJ_DIR)/,$(CSRC:.c=.32.o))
OBJS64  = $(addprefix $(OBJ_DIR)/,$(CSRC:.c=.64.o))
LIB96   := $(OBJ_DIR)/libgendep.so
LIB32   := $(if $(call checkbuild,32),$(OBJ_DIR)/32/libgendep.so)
LIB64   := $(if $(call checkbuild,64),$(OBJ_DIR)/64/libgendep.so)


ifneq ($(filter linux freebsd,$(HOST_SYSTEM)),)
LIB     := $(if $(USE_M_FLAG),$(LIB32) $(LIB64),$(LIB96))
LIBDL-linux := -ldl
cmd_link = $(HOST_CC) $(call M_FLAG,$(2)) -shared -Wl,--no-as-needed \
           -Wl,-soname,$(1) $(LIBDL-$(HOST_SYSTEM)) -o $(1)
else
ifeq ($(HOST_SYSTEM),darwin)
LIB     := $(LIB96)
cmd_link = $(HOST_CC) -dynamiclib -o $(1)
else
$(error Your host system type "$(HOST_SYSTEM)" is not supported here. Fix me.)
endif
endif

ifeq ($(strip $(LIB)),)
$(error Neither 32 nor 64 bit version are built?!)
endif

ifeq ($(LIB96),)
ifeq ($(words $(LIB)),2)
$(info gendep: Building 32bit and 64bit variants)
else
$(info gendep: Building $(if $(LIB32),32bit)$(if $(LIB64),64bit) variant)
endif
endif

all:: $(LIB)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c $(SRC_DIR)/Makefile
	@$(COMP_MESSAGE)
	$(VERBOSE)$(MKDIR) $(@D)
	$(VERBOSE)$(HOST_CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/%.32.o: $(SRC_DIR)/%.c $(SRC_DIR)/Makefile
	@$(COMP_MESSAGE)
	$(VERBOSE)$(MKDIR) $(@D)
	$(VERBOSE)$(HOST_CC) $(CFLAGS) -m32 -c $< -o $@

$(OBJ_DIR)/%.64.o: $(SRC_DIR)/%.c $(SRC_DIR)/Makefile
	@$(COMP_MESSAGE)
	$(VERBOSE)$(MKDIR) $(@D)
	$(VERBOSE)$(HOST_CC) $(CFLAGS) -m64 -c $< -o $@

$(LIB96): $(OBJS96) $(SRC_DIR)/Makefile
	@$(LINK_MESSAGE)
	$(VERBOSE)$(call cmd_link,$@) $(OBJS96)

$(LIB32): $(OBJS32) $(SRC_DIR)/Makefile
	@$(LINK_MESSAGE)
	$(VERBOSE)$(MKDIR) $(OBJ_DIR)/32
	$(VERBOSE)$(call cmd_link,$@,32) $(OBJS32)

$(LIB64): $(OBJS64) $(SRC_DIR)/Makefile
	@$(LINK_MESSAGE)
	$(VERBOSE)$(MKDIR) $(OBJ_DIR)/64
	$(VERBOSE)$(call cmd_link,$@,64) $(OBJS64)

doc: $(MAN)

$(MAN): $(MAN_SRC)
	@$(call GEN_MESSAGE,manpages)
	$(VERBOSE)doxygen

install:: $(LIB) $(MAN)
	$(if $(DROPS_STDDIR),,$(error DROPS_STDDIR is not set. Do a 'make config' in $(L4DIR)))
	$(VERBOSE)install -d $(DROPS_STDDIR)/tool/lib
	$(VERBOSE)install -c $(LIB) $(DROPS_STDDIR)/tool/lib
	$(VERBOSE)install -d $(DROPS_STDDIR)/tool/man/man7
	$(VERBOSE)install -c $(MAN) $(DROPS_STDDIR)/tool/man/man7

test:
	GENDEP_TARGET='simple-cat' \
		GENDEP_BINARY=cpp\
		GENDEP_cpp='+\.h$$ -^/usr' \
		$(LD_PRELOAD)=$(OBJ_DIR)/libgendep.so\
		$(HOST_CC) -o $(OBJ_DIR)/simple-cat simple-cat.c
	GENDEP_TARGET='blabla' \
		GENDEP_BINARY=cpp\
		$(LD_PRELOAD)=$(OBJ_DIR)/libgendep.so\
		$(HOST_CC) -o $(OBJ_DIR)/simple-cat simple-cat.c
	GENDEP_TARGET='badexp' \
		GENDEP_BINARY=cpp\
		GENDEP_cpp='\)foo'\
		$(LD_PRELOAD)=$(OBJ_DIR)/libgendep.so\
		$(HOST_CC) -o $(OBJ_DIR)/simple-cat simple-cat.c
	@echo ==========
	cat simple-cat.dep
	cat blabla.dep

clean cleanall::
	@$(CLEAN_MESSAGE)
	$(VERBOSE)$(RM) $(OBJ_DIR)/.*.d $(OBJ_DIR)/*.o $(OBJ_DIR)/simple-cat
	$(VERBOSE)$(RM) $(OBJ_DIR)/32/*.so $(OBJ_DIR)/64/*.so
	$(VERBOSE)$(RM) -r $(OBJ_DIR)/32 $(OBJ_DIR)/64

cleanall::
	@$(CLEANALL_MESSAGE)
	$(VERBOSE)$(RM) $(LIB)
	$(VERBOSE)$(RM) -r man/ html/

dist:
	rm -rf $(DDIR)
	mkdir $(DDIR)
	ln $(CSRC) COPYING Doxyfile manpage.dox gendep.h Makefile \
		   WhatIsThis simple-cat.c $(DDIR)
	tar cfz $(DDIR).tar.gz $(DDIR)
	rm -rf $(DDIR)
