AUTOMAKE_OPTIONS = foreign
ACLOCAL_AMFLAGS = -Im4
AM_MAKEFLAGS = --no-print-directory
AM_CFLAGS = -Wall -Werror $(ENDIAN_FLAG)

lib_LTLIBRARIES =
include_HEADERS =
datadir = ${datarootdir}/pdata
data_DATA =
CLEANFILES =

if BUILD_TOOLS
lib_LTLIBRARIES += libfdt-traverse.la libfdt-attr.la libdtree.la
include_HEADERS += libdtree/dtree.h
bin_PROGRAMS = attributes
noinst_LTLIBRARIES = libdtm.la
endif
EXTRA_PROGRAMS = attributes

if BUILD_ATTR_API
pkgconfiglibdir = ${libdir}/pkgconfig
pkgconfiglib_DATA = libdt-api/libdt-api.pc
lib_LTLIBRARIES += libdt-api.la
include_HEADERS += attributes_info.H libdt-api/dt_api.H
data_DATA += attributes_info.db
data_DATA += data/$(CHIP)/preserved_attrs_list
data_DATA += data/$(CHIP)/reinit_devtree_attrs_list
CLEANFILES += attributes_info.H attributes_info.db
endif

libfdt_traverse_la_SOURCES = \
	fdt/fdt_error.c \
	fdt/fdt_error.h \
	fdt/fdt_traverse.c \
	fdt/fdt_traverse.h

libfdt_attr_la_SOURCES = \
	fdt/fdt_attr.c \
	fdt/fdt_attr.h \
	fdt/fdt_prop.c \
	fdt/fdt_prop.h

libdtm_la_SOURCES = \
	ccan/build_assert/build_assert.h \
	ccan/check_type/check_type.h \
	ccan/container_of/container_of.h \
	ccan/list/list.c \
	ccan/list/list.h \
	libdtm/dtm.c \
	libdtm/dtm.h \
	libdtm/dtm_file.c \
	libdtm/dtm_internal.h \
	libdtm/dtm_io.c \
	libdtm/dtm_node.c \
	libdtm/dtm_nodelist.c \
	libdtm/dtm_property.c \
	libdtm/dtm_search.c \
	libdtm/dtm_traverse.c \
	libdtm/dtm_tree.c
libdtm_la_LIBADD = libfdt-traverse.la libfdt-attr.la

libdtree_la_SOURCES = \
	libdtree/dtree.h \
	libdtree/dtree_attr.c \
	libdtree/dtree_attr.h \
	libdtree/dtree_attr_list.c \
	libdtree/dtree_attr_list.h \
	libdtree/dtree_cronus.c \
	libdtree/dtree_cronus.h \
	libdtree/dtree_cronus_format.c \
	libdtree/dtree_cronus_target.c \
	libdtree/dtree_dump.h \
	libdtree/dtree_dump_format.c \
	libdtree/dtree_export.c \
	libdtree/dtree_import.c \
	libdtree/dtree_infodb.c \
	libdtree/dtree_infodb.h \
	libdtree/dtree_util.c \
	libdtree/dtree_util.h
libdtree_la_LIBADD = libdtm.la
libdtree_la_CPPFLAGS = -I$(srcdir)/libdtm

attributes_SOURCES = \
	attribute/attribute.c
attributes_LDADD = libdtree.la
attributes_LDFLAGS = -lm

AUTO_GEN_V = $(AUTO_GEN_V_$(V))
AUTO_GEN_V_ = $(AUTO_GEN_V_$(AM_DEFAULT_VERBOSITY))
AUTO_GEN_V_0 = @echo "  GEN     " $@;

# attribute_info.H and attribute_info.db cannot be built in parallel
.NOTPARALLEL:

attributes_info.H:
	$(AUTO_GEN_V)DEBUG=$(V) TARGET_PROC=$(CHIP) \
		$(srcdir)/scripts/dt_generate.sh header $@

attributes_info.db:
	$(AUTO_GEN_V)DEBUG=$(V) TARGET_PROC=$(CHIP) \
		$(srcdir)/scripts/dt_generate.sh infodb $@

libdt_api_la_SOURCES = libdt-api/dt_api.C \
                       libdt-api/dt_api.H

.PHONY: clean-gen_dt install-gen_dt uninstall-gen_dt

clean-local: clean-gen_dt
install-data-hook: install-gen_dt
uninstall-hook: uninstall-gen_dt

BUILT_SOURCES =

if BUILD_DYNAMIC_DT
BUILT_SOURCES += gen_dt
gen_dtdir = $(builddir)/gen_dt

clean-gen_dt:
	rm -rf $(gen_dtdir)

install-gen_dt:
	$(install_sh) -d -m 755 $(DESTDIR)$(datadir)
	$(install_sh) -m 644 $(gen_dtdir)/*.dtb $(DESTDIR)$(datadir)/

uninstall-gen_dt:
	rm -f $(DESTDIR)$(datadir)/*.dtb

gen_dt:
	$(AUTO_GEN_V)$(MKDIR_P) $(gen_dtdir) && \
	DEBUG=$(V) TARGET_PROC=$(CHIP) $(srcdir)/scripts/dt_generate.sh dts $(gen_dtdir) && \
	TARGET_PROC=$(CHIP) $(srcdir)/targeting/xmltohb/xmltobmc.sh && \
	( for i in $(gen_dtdir)/*.dts; do \
		$(DTC) -I dts -O dtb "$$i" > "$${i%.dts}.dtb" || exit 1; \
	done ) || ( $(MAKE) $(AM_MAKEFLAGS) clean-gen_dt; exit 1 )
endif
