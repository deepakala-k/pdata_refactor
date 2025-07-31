#!/bin/sh

TARGETING_XMLTOHB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_TARGETING_PATH="$(dirname "$TARGETING_XMLTOHB_DIR")"
GENDIR="${ROOT_TARGETING_PATH}/obj/genfiles"
COMMON_XMLTOHB_REL_PATH="${ROOT_TARGETING_PATH}/common/xmltohb"
TARGETING_XMLTOHB_REL_PATH="${ROOT_TARGETING_PATH}/xmltohb"

export PERL5LIB="$COMMON_XMLTOHB_REL_PATH"

[ -d "$GENDIR" ] && rm -rf "$GENDIR"

mkdir -p "$GENDIR"

# XML source files
TEMP_DEFAULTS_XML="tempdefaults.xml"
HB_TEMP_DEFAULTS_XML="hb_temp_defaults.xml"
EKB_CUSTOMIZED_ATTRS_XML="ekb_customized_attrs.xml"
EKB_CUSTOMIZED_ATTRS_XML_BMC="ekb_customized_attrs_bmc.xml"

# Header files
ATTRIBUTE_SERVICE_H="plat_attribute_service.H"

# XML inputs
XMLTOHB_MERGED_XML="merged.xml"
XMLTOHB_FILTERED_MERGED_XML="filtered_merged.xml"
XMLTOHB_FAPI_XML="fapiattrs.xml"

# Script files
XMLTOHB_MERGE_SCRIPT="mergexml.sh"
XMLTOHB_COMPILER_SCRIPT="xmltohb.pl"
XMLTOHB_EKB_TARGATTR_SCRIPT="create_ekb_targattr.pl"
XMLTOHB_DUPLICATE_SCRIPT="handle_duplicate.pl"
XMLTOHB_SWAP_MAPPED_ATTR_SCRIPT="handle_fapi_attr_mapping.pl"
XMLTOHB_REMOVE_HB_MAPPED_ATTR_SCRIPT="remove_hb_fapi_maps.pl"

# Temp defaults XML sources used by updatetempsxml.pl script
TEMP_DEFAULTS_XML="tempdefaults.xml"
BMC_TEMP_DEFAULTS_XML="bmc_customized_ekb_attrs.xml"
EKB_CUSTOMIZED_ATTRS_XML="ekb_customized_attrs.xml"

filter_attr="filter_AttributesList.lsv"
filter_target="filter_TargetsList.lsv"

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

# BMC only
XMLTOHB_BMC_ATTRIBUTE_TYPES="attribute_types_obmc.xml"
XMLTOHB_BMC_TARGET_TYPES="target_types_obmc.xml"
XMLTOHB_BMC_TARGET_TYPES_EXTENSION="target_types_extension_obmc.xml"
XMLTOHB_TARGET_TYPES_MERGED="target_types_merged.xml"

XMLTOHB_TARGET_TYPES_SOURCES+=" ${COMMON_XMLTOHB_REL_PATH}/${XMLTOHB_COMMON_TARGET_TYPES}"
XMLTOHB_TARGET_TYPES_SOURCES+=" ${TARGETING_XMLTOHB_REL_PATH}/${XMLTOHB_BMC_TARGET_TYPES}"

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
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES+=" ${COMMON_XMLTOHB_REL_PATH}/${EKB_CUSTOMIZED_ATTRS_XML}"
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES+=" ${COMMON_XMLTOHB_REL_PATH}/${EKB_CUSTOMIZED_ATTRS_XML_BMC}"

# SRC attribute sources
XMLTOHB_SRC_ATTRIBUTE_SOURCES=""
XMLTOHB_SRC_ATTRIBUTE_SOURCES+=" ${COMMON_XMLTOHB_REL_PATH}/${XMLTOHB_COMMON_ATTRIBUTE_TYPES}"
XMLTOHB_SRC_ATTRIBUTE_SOURCES+=" ${TARGETING_XMLTOHB_REL_PATH}/${XMLTOHB_BMC_ATTRIBUTE_TYPES}"

# Customize target file combines targetTypeExtension files
XMLTOHB_SRC_CUSTOMIZE_TARGET_SOURCES="target_types_customize_src.xml"
XMLTOHB_CONFIG_CUSTOMIZE_TARGET_SOURCES="target_types.customize_config.xml"

# Define XMLTOHB_MERGED_SOURCES
XMLTOHB_MERGED_SOURCES=""
XMLTOHB_MERGED_SOURCES+=" ${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}"
XMLTOHB_MERGED_SOURCES+=" ${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}"

# Temp default sources
TEMP_DEFAULT_SOURCES="tempdefaults.xml"

# XML merge scripts
XMLTOHB_TARGET_MERGE_SCRIPT="updatetargetxml.pl"
XMLTOHB_TEMPS_MERGE_SCRIPT="updatetempsxml.pl"

# Header path
VMM_CONSTS_FILE="${ROOTPATH}/src/include/usr/vmmconst.h"

# Final generated files
GENFILES="${XMLTOHB_TARGETS}"

echo "Running: $COMMON_XMLTOHB_REL_PATH/$XMLTOHB_MERGE_SCRIPT $XMLTOHB_SRC_ATTRIBUTE_SOURCES > ${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES}"
$COMMON_XMLTOHB_REL_PATH/$XMLTOHB_MERGE_SCRIPT $XMLTOHB_SRC_ATTRIBUTE_SOURCES > ${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES}

echo "Merging target sources into: ${GENDIR}/${XMLTOHB_TARGET_TYPES_MERGED}"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_TARGET_TYPES_SOURCES} > "${GENDIR}/${XMLTOHB_TARGET_TYPES_MERGED}"

echo "Running: $COMMON_XMLTOHB_REL_PATH/$XMLTOHB_TARGET_MERGE_SCRIPT --common=${COMMON_XMLTOHB_REL_PATH}/${XMLTOHB_COMMON_TARGET_TYPES} --plat=${TARGETING_XMLTOHB_REL_PATH}/${XMLTOHB_BMC_TARGET_TYPES_EXTENSION} > ${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}"
"$COMMON_XMLTOHB_REL_PATH/$XMLTOHB_TARGET_MERGE_SCRIPT" \
  --common="${GENDIR}/${XMLTOHB_TARGET_TYPES_MERGED}" \
  --plat="${TARGETING_XMLTOHB_REL_PATH}/${XMLTOHB_BMC_TARGET_TYPES_EXTENSION}" \
  > "${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}"

LSV_FILE="${TARGETING_XMLTOHB_REL_PATH}/reqEkbAttrsXmlFileList.lsv"

XMLTOHB_FAPIATTR_SOURCES=$(<"$LSV_FILE")

#this has to access from hostfw repo
EKB="/gsa/ausgsa-p10/03/indiateam04/deepa/Projects/dts/pub-ekb"
XMLTOHB_FAPIATTR_SOURCES=""
while read -r line; do
    XMLTOHB_FAPIATTR_SOURCES+="$EKB/${line} "  # or "${line}.xml", etc.
done < "$LSV_FILE"

# Merge all FAPI attribute files into one
echo "Merging FAPI attribute sources into: ${GENDIR}/${XMLTOHB_FAPI_XML}"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_FAPIATTR_SOURCES} > "${GENDIR}/${XMLTOHB_FAPI_XML}"


TEMP_DEFAULTS_XML="tempdefaults.xml"
BMC_TEMP_DEFAULTS_XML="bmc_customized_ekb_attrs.xml"
EKB_CUSTOMIZED_ATTRS_XML="ekb_customized_attrs.xml"

#Note that order matters here , we want hb_customized_attrs to be first so it's defaults get picked up first
#if there are duplicates
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES="${COMMON_XMLTOHB_REL_PATH}/${TEMP_DEFAULTS_XML} "
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES+="${TARGETING_XMLTOHB_REL_PATH}/${BMC_TEMP_DEFAULTS_XML} "
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES+="${COMMON_XMLTOHB_REL_PATH}/${EKB_CUSTOMIZED_ATTRS_XML}"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES} > "${GENDIR}/${XMLTOHB_ATTRIBUTE_CUSTOMIZATION}"

# convert FAPI attrs to plat attrs
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_EKB_TARGATTR_SCRIPT}" \
    --fapi=${GENDIR}/${XMLTOHB_FAPI_XML} \
    --attr=${GENDIR}/${XMLTOHB_EKB_ATTRIBUTE_TYPES} \
    --targ=${GENDIR}/${XMLTOHB_EKB_TARGET_TYPES} \
    --default=${GENDIR}/${XMLTOHB_ATTRIBUTE_CUSTOMIZATION}


#Print command for debug/logging
echo "Running: $script --ekbXmlFile=${GENDIR}/${XMLTOHB_EKB_ATTRIBUTE_TYPES} --hbXmlFile=${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES}
 --fapi2Header=${TARGETING_XMLTOHB_REL_PATH}/attribute_service.H --outFile=${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}"

# Execute the Perl script
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_DUPLICATE_SCRIPT}" \
    --ekbXmlFile=${GENDIR}/${XMLTOHB_EKB_ATTRIBUTE_TYPES} \
    --hbXmlFile=${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES} \
    --fapi2Header=${TARGETING_XMLTOHB_REL_PATH}/attribute_service.H \
    --outFile=${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}


echo "Deepa Running target merge script and $XMLTOHB_SWAP_MAPPED_ATTR_SCRIPT... to create $XMLTOHB_FULL_TARGET_TYPES"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_TARGET_MERGE_SCRIPT}" \
    --plat="${GENDIR}/${XMLTOHB_EKB_TARGET_TYPES}" \
    --common="${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}" > "${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}"

echo "-------------- Running $COMMON_XMLTOHB_REL_PATH/${XMLTOHB_SWAP_MAPPED_ATTR_SCRIPT}" \
    --srcTargetXml="${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}" \
    --ekbTargetXml="${GENDIR}/${XMLTOHB_EKB_TARGET_TYPES}" \
    --fullAttrXml="${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}" \
    --fullTargetXml="${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}" \
    --fapi2Header="${TARGETING_XMLTOHB_REL_PATH}/attribute_service.H"

"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_SWAP_MAPPED_ATTR_SCRIPT}" \
    --srcTargetXml="${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}" \
    --ekbTargetXml="${GENDIR}/${XMLTOHB_EKB_TARGET_TYPES}" \
    --fullAttrXml="${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}" \
    --fullTargetXml="${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}" \
    --fapi2Header="${TARGETING_XMLTOHB_REL_PATH}/attribute_service.H"

file="${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}"

# Create a temp file and wrap with <attributes> tags
{
  echo "<attributes>"
  cat "$file"
  echo "</attributes>"
} > "${file}.tmp" && mv "${file}.tmp" "$file"

# trim leading whitespace if any
XMLTOHB_MERGED_SOURCES="${XMLTOHB_MERGED_SOURCES#" "}"

# Merge all FAPI attribute files into one
echo "Merging merged sources $XMLTOHB_MERGED_SOURCES into: ${GENDIR}/${XMLTOHB_MERGED_XML}"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_MERGED_SOURCES} > "${GENDIR}/${XMLTOHB_MERGED_XML}"

XMLTOHB_RAN_INDICATION="${GENDIR}/.called_xmltohb_compiler"

"$COMMON_XMLTOHB_REL_PATH/filterXML.pl" \
    --inXML "${GENDIR}/${XMLTOHB_MERGED_XML}" \
    --outXML "${GENDIR}/${XMLTOHB_FILTERED_MERGED_XML}" \
    --filterAttrsFile "${TARGETING_XMLTOHB_REL_PATH}/$filter_attr" \
    --filterTgtsFile "${TARGETING_XMLTOHB_REL_PATH}/$filter_target" \
    --filterType customTgtXML


# create the header files, only needs generic xml
if [[ ! -f "$XMLTOHB_RAN_INDICATION" ]]; then
  echo "Running: ${XMLTOHB_COMPILER_SCRIPT}"

  "$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_COMPILER_SCRIPT}" \
    --hb-xml-file="${GENDIR}/${XMLTOHB_MERGED_XML}" \
    --fapi-attributes-xml-file="${GENDIR}/${XMLTOHB_FAPI_XML}" \
    --src-output-dir="${GENDIR}" \
    --img-output-dir=none \
    --img-output-file=none

#   TODO: Not needed. To confirm it. echo "Copying plugin headers..."
#   cp "${GENDIR_ERRL}/errludattributeP_gen.H" "${GENDIR_PLUGINS}"
#   cp "${GENDIR_ERRL}/errludtarget.H" "${GENDIR_PLUGINS}"

#  touch "$XMLTOHB_RAN_INDICATION"
  echo "XMLTOHB compile completed and marker touched."
else
  echo "Already ran: Skipping ${XMLTOHB_COMPILER_SCRIPT}"
fi

echo "Generating $BMC_XML from:"
#"$MERGE_SCRIPT" "$SYSTEM_XML" "$GENERIC_XML" "$MRW_XML" > "$BMC_XML"





