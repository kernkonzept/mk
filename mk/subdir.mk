# -*- Makefile -*-
#
# L4Re Buildsystem
#
# Makefile-Template for directories containing only subdirs
#
# 05/2002 Jork Loeser <jork.loeser@inf.tu-dresden.de>

include $(L4DIR)/mk/Makeconf

ifeq ($(PKGDIR),.)
TARGET ?= $(patsubst %/Makefile,%,$(wildcard $(addsuffix /Makefile, \
	include src lib server examples doc assets)))
$(if $(wildcard include/Makefile), lib server examples: include)
$(if $(wildcard lib/Makefile), server examples: lib)
else
TARGET ?= $(patsubst %/Makefile,%,$(wildcard $(addsuffix /Makefile, \
	src lib server examples doc)))
endif

is_in_tree := $(filter-out $(PKGDIR_ABS),$(PKGDIR_ABS:$(L4DIR_ABS)/%=%))
write_once = $(file >$1,$(sort $2 $(file <$1)))
ifeq ($(is_in_tree),)
ifneq ($(wildcard Control),)
register:
	@echo -e $(EMPHSTART)Registering $(PKGDIR_ABS) for $(OBJ_BASE)$(EMPHSTOP)
	$(call write_once,$(OBJ_BASE)/.Package.deps.ext_pkgs,$(PKGDIR_ABS))
	$(MAKE) -C $(OBJ_BASE)
else
register:
	$(error Only external packages with a Control file may be registered)
endif
endif


TARGET += $(if $(CONFIG_BID_BUILD_TESTS),$(TARGET_test))

SUBDIR_TARGET	:= $(if $(filter doc,$(MAKECMDGOALS)),$(TARGET),    \
			$(filter-out doc,$(TARGET)))

all::	$(SUBDIR_TARGET) $(SUBDIRS)
install::

lib: include
server: include

clean cleanall scrub::
	$(VERBOSE)set -e; $(foreach d,$(TARGET), test -f $d/broken || \
	    if [ -f $d/Makefile ] ; then PWD=$(PWD)/$d $(MAKE) -C $d $@ $(MKFLAGS) $(MKFLAGS_$(d)); fi; )

install oldconfig txtconfig relink::
	$(VERBOSE)set -e; $(foreach d,$(TARGET), test -f $d/broken -o -f $d/obsolete || \
	    if [ -f $d/Makefile ] ; then PWD=$(PWD)/$d $(MAKE) -C $d $@ $(MKFLAGS) $(MKFLAGS_$(d)); fi; )

# first the subdir-targets (this is where "all" will be built, e.g. in lib
# or server).
$(SUBDIR_TARGET): %:
	$(VERBOSE)test -f $@/broken -o -f $@/obsolete ||		\
	    if [ -f $@/Makefile ] ; then PWD=$(PWD)/$@ $(MAKE) -C $@ $(MKFLAGS) ; fi
# Second, the rules for going down into sub-pkgs with "lib" and "server"
# targets. Going down into sub-pkgs.
	$(if $(SUBDIRS),$(if $(filter $@,include lib server examples doc),\
		$(VERBOSE)set -e; for s in $(SUBDIRS); do \
			PWD=$(PWD)/$$s $(MAKE) -C $$s $@ $(MKFLAGS); done ))

idl include lib server examples doc:

install-symlinks:
	$(warning target install-symlinks is obsolete. Use 'include' instead (warning only))
	$(VERBOSE)$(MAKE) include

help::
	@echo "  all            - build subdirs: $(SUBDIR_TARGET)"
	$(if $(filter doc,$(TARGET)), \
	@echo "  doc            - build documentation")
	@echo "  scrub          - call scrub recursively"
	@echo "  clean          - call clean recursively"
	@echo "  cleanall       - call cleanall recursively"
	$(if $(is_in_tree),,\
	@echo "  register       - register external package into the buildtree")
	@echo "  install        - build subdirs, install recursively then"
	@echo "  oldconfig      - call oldconfig recursively"
	@echo "  txtconfig      - call txtconfig recursively"

.PHONY: $(TARGET) all clean cleanall help install oldconfig txtconfig
