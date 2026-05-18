PKGDIR = .
L4DIR  ?= ../..

SRC_DOX_REF = l4re.cfg
ADD_FILES_TO_HTML = $(SRC_DIR)/images/header-bg.png

include $(L4DIR)/mk/doc.mk

export L4DIR
export OBJ_BASE

PHONY += regen regen_cfg regen_html

regen: regen_cfg regen_html

regen_cfg:
	$(DOXYGEN) -u l4re.cfg
	rm -f l4re.cfg.bak

regen_html: regen_cfg
	$(DOXYGEN) -w html l4re-header.html l4re-footer.html l4re.css l4re.cfg
	rm -r l4re-footer.html.bak l4re-header.html.bak l4re.css.bak
