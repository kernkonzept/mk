L4DIR ?= ..

TARGET     := $(wildcard gendep elf-patcher elf-util)
TARGET_doc := $(wildcard gendep)

all::
doc:
	$(if $(TARGET_doc), $(VERBOSE)set -e ; for d in $(TARGET_doc) ; do \
		$(MAKE) -C $$d $@ ; done )

include $(L4DIR)/mk/subdir.mk
