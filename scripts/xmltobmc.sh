#!/bin/sh
# XML header targets
XMLTOHB_HEADER_TARGETS=(
    attributeenums.H
    attributestrings.H
    attributetraits.H
    attributestructs.H
    pnortargeting.H
    fapi2platattrmacros.H
    test_ep.H
    mapattrmetadata.H
    mapsystemattrsize.H
)

# XML source targets
XMLTOHB_SOURCE_TARGETS=(
    attributestrings.C
    attributedump.C
    errludattribute.C
    errludtarget.C
    mapattrmetadata.C
    mapsystemattrsize.C
)

XMLTOHB_TARGETS=(
    "${XMLTOHB_HEADER_TARGETS[@]}"
    "${XMLTOHB_SOURCE_TARGETS[@]}"
)

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTPATH="$(dirname "$script_dir")"
GENDIR="${ROOTPATH}/obj/genfiles"
SCRIPTS_DIR="${ROOTPATH}/scripts"
COMMON_TARGETING_REL_PATH="${ROOTPATH}/data/p10"

mkdir -p "$GENDIR"

# XML source files
TEMP_DEFAULTS_XML="tempdefaults.xml"
HB_TEMP_DEFAULTS_XML="hb_temp_defaults.xml"
EKB_CUSTOMIZED_ATTRS_XML="ekb_customized_attrs.xml"
EKB_CUSTOMIZED_ATTRS_XML_BMC="ekb_customized_attrs_bmc.xml"

# Header files
ATTRIBUTE_SERVICE_H="plat_attribute_service.H"
HB_PLAT_ATTR_SRVC_H="hb_plat_attr_srvc.H"

# XML inputs
TEMP_GENERIC_XML="temp_generic.xml"
XMLTOHB_GENERIC_XML="generic.xml"
XMLTOHB_FAPI_XML="fapiattrs.xml"

# Script files
XMLTOHB_MERGE_SCRIPT="mergexml.sh"
XMLTOHB_TEMPS_MERGE_SCRIPT="updatetempsxml.pl"
XMLTOHB_COMPILER_SCRIPT="xmltohb.pl"
XMLTOHB_EKB_TARGATTR_SCRIPT="create_ekb_targattr.pl"
XMLTOHB_DUPLICATE_SCRIPT="handle_duplicate.pl"
XMLTOHB_SWAP_MAPPED_ATTR_SCRIPT="handle_fapi_attr_mapping.pl"
XMLTOHB_REMOVE_HB_MAPPED_ATTR_SCRIPT="remove_hb_fapi_maps.pl"

# Other
VMM_CONSTS_FILE="vmmconst.h"

# Final generated code
GENERATED_CODE="${XMLTOHB_TARGETS}"

# Debug print (optional)
echo "Generated Code Files:"
for file in ${GENERATED_CODE}; do
    echo "  $file"
done

#!/bin/bash

# Manually generated sources

# Common
XMLTOHB_COMMON_ATTRIBUTE_TYPES="attribute_types.xml"
XMLTOHB_COMMON_TARGET_TYPES="target_types.xml"

# HB only
XMLTOHB_BMC_ATTRIBUTE_TYPES="attribute_types_bmc.xml"
XMLTOHB_BMC_TARGET_TYPES="target_types_bmc.xml"

# EKB
# Common generated from EKB xml
XMLTOHB_EKB_ATTRIBUTE_TYPES="attribute_types_ekb.xml"
XMLTOHB_EKB_TARGET_TYPES="target_types_ekb.xml"

# SRC
# a_src = a + a_bmc
# t_src = t + merge_extension(t_hb + t_bmc)
XMLTOHB_SRC_ATTRIBUTE_TYPES="attribute_types_src.xml"
XMLTOHB_SRC_TARGET_TYPES="target_types_src.xml"

# FULL
# a_full = a_src + a_ekb
# t_full = t_src + t_ekb
XMLTOHB_FULL_ATTRIBUTE_TYPES="attribute_types_full.xml"
XMLTOHB_FULL_TARGET_TYPES="target_types_full.xml"

# attribute_customization
# hb_temp_defaults.xml + hb_customized_attrs.xml ( + hb_customized_attrs_fsp.xml)
XMLTOHB_ATTRIBUTE_CUSTOMIZATION="attribute_customization.xml"

# Note: order matters — we want hb_customized_attrs to be first
# if there are duplicates
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES=""
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES+=" ${COMMON_TARGETING_REL_PATH}/${EKB_CUSTOMIZED_ATTRS_XML}"
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES+=" ${COMMON_TARGETING_REL_PATH}/${EKB_CUSTOMIZED_ATTRS_XML_BMC}"

# SRC attribute sources
XMLTOHB_SRC_ATTRIBUTE_SOURCES=""
XMLTOHB_SRC_ATTRIBUTE_SOURCES+=" ${COMMON_TARGETING_REL_PATH}/${XMLTOHB_COMMON_ATTRIBUTE_TYPES}"
XMLTOHB_SRC_ATTRIBUTE_SOURCES+=" ${COMMON_TARGETING_REL_PATH}/${XMLTOHB_BMC_ATTRIBUTE_TYPES}"

# Customize target file combines targetTypeExtension files
XMLTOHB_SRC_CUSTOMIZE_TARGET_SOURCES="target_types_customize_src.xml"
XMLTOHB_CONFIG_CUSTOMIZE_TARGET_SOURCES="target_types.customize_config.xml"

# External HB target sources
XMLTOHB_SRC_EXT_TARGET_SOURCES=""
XMLTOHB_SRC_EXT_TARGET_SOURCES+=" ${COMMON_TARGETING_REL_PATH}/${XMLTOHB_HB_TARGET_TYPES}"

# Define XMLTOHB_GENERIC_SOURCES
XMLTOHB_GENERIC_SOURCES=""
XMLTOHB_GENERIC_SOURCES+=" ${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}"
XMLTOHB_GENERIC_SOURCES+=" ${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}"

# Temp default sources
TEMP_DEFAULT_SOURCES="tempdefaults.xml"

# XML merge scripts
XMLTOHB_TARGET_MERGE_SCRIPT="updatetargetxml.pl"
XMLTOHB_TEMPS_MERGE_SCRIPT="updatetempsxml.pl"

# Header path
VMM_CONSTS_FILE="${ROOTPATH}/src/include/usr/vmmconst.h"

# Final generated files
GENFILES="${XMLTOHB_TARGETS}"

echo "Running: $SCRIPTS_DIR/$XMLTOHB_MERGE_SCRIPT $XMLTOHB_SRC_ATTRIBUTE_SOURCES > ${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES}"
$SCRIPTS_DIR/$XMLTOHB_MERGE_SCRIPT $XMLTOHB_SRC_ATTRIBUTE_SOURCES > ${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES}