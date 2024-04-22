# -*- Makefile -*-
# vim:set ft=make:

VARIANT_DIRS-variant-nofpu = pkg/uvmm pkg/bootstrap

CARCHFLAGS-variant-nofpu += $(GCCNOFPU_$(ARCH))
DEFINES-variant-nofpu    += -DBID_VARIANT_FLAG_NOFPU
BID_DEFINE-variant-nofpu  = BID_VARIANT_FLAG_NOFPU=y
