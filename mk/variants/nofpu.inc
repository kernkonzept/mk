# -*- Makefile -*-
# vim:set ft=make:

CARCHFLAGS-variant-nofpu += $(GCCNOFPU_$(ARCH))
DEFINES-variant-nofpu    += -DBID_VARIANT_FLAG_NOFPU
BID_DEFINE-variant-nofpu  = BID_VARIANT_FLAG_NOFPU=y
