#!/bin/sh

TARGETING_XMLTOHB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_TARGETING_PATH="$(dirname "$TARGETING_XMLTOHB_DIR")"
GENDIR="${ROOT_TARGETING_PATH}/obj/genfiles"
COMMON_XMLTOHB_REL_PATH="${ROOT_TARGETING_PATH}/common/xmltohb"
TARGETING_XMLTOHB_REL_PATH="${ROOT_TARGETING_PATH}/xmltohb"
COMMON_MRW_REL_PATH="${ROOT_TARGETING_PATH}/common/mrw"

check_var ()
{
    var="$1"
    eval value=\$${var}
    if [ -z "$value" ] ; then
        echo "$var is not defined"
        exit 1
    fi
}

check_var TARGET_PROC
check_var EKB

check_var SYSTEMS_MRW_XML
TARGETING_XMLTOHB_PROC_REL_PATH="$TARGETING_XMLTOHB_REL_PATH/$TARGET_PROC"

export PERL5LIB="$COMMON_XMLTOHB_REL_PATH:$TARGETING_XMLTOHB_PROC_REL_PATH${PERL5LIB:+:$PERL5LIB}"

# TODO: force deleting all the generated files and creating them again
[ -d "$GENDIR" ] && rm -rf "$GENDIR"
mkdir -p "$GENDIR"

# XML inputs
XMLTOHB_ATTRIBUTES_TARGETS_MERGED_XML="attributes_targettype_merged.xml"
XMLTOHB_MRW_ATTRIBUTES_TARGETS_MERGED_XML="mrw_attributes_targets_merged.xml"
XMLTOHB_FAPI_XML="fapiattrs.xml"

# Script files
XMLTOHB_MERGE_SCRIPT="mergexml.sh"
XMLTOHB_COMPILER_SCRIPT="xmltohb.pl"
XMLTOHB_EKB_TARGATTR_SCRIPT="create_ekb_targattr.pl"
XMLTOHB_DUPLICATE_SCRIPT="handle_duplicate.pl"
XMLTOHB_REMOVE_HB_MAPPED_ATTR_SCRIPT="remove_hb_fapi_maps.pl"

# Target XML merge scripts
XMLTOHB_TARGET_MERGE_SCRIPT="updatetargetxml.pl"

# Temp defaults XML sources used by updatetempsxml.pl script
TEMP_DEFAULTS_XML="tempdefaults.xml"
BMC_TEMP_DEFAULTS_XML="bmc_customized_ekb_attrs.xml"

filter_attr="filter_AttributesList.lsv"
filter_target="filter_TargetsList.lsv"

# Manually generated sources

# Common
XMLTOHB_COMMON_ATTRIBUTE_TYPES="attribute_types.xml"
XMLTOHB_COMMON_TARGET_TYPES="target_types.xml"

# BMC only
XMLTOHB_BMC_ATTRIBUTE_TYPES="attribute_types_obmc.xml"
XMLTOHB_BMC_TARGET_TYPES="target_types_obmc.xml"
XMLTOHB_BMC_TARGET_TYPES_EXTENSION="target_types_extension_obmc.xml"

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
XMLTOHB_FULL_TARGET_TYPES_EXPANDED="target_types_full_expanded.xml"

# attribute_customization
# hb_temp_defaults.xml + hb_customized_attrs.xml ( + hb_customized_attrs_fsp.xml)
XMLTOHB_ATTRIBUTE_CUSTOMIZATION="attribute_customization.xml"

# SRC attribute sources
XMLTOHB_SRC_ATTRIBUTE_SOURCES=""
XMLTOHB_SRC_ATTRIBUTE_SOURCES+=" ${COMMON_XMLTOHB_REL_PATH}/${XMLTOHB_COMMON_ATTRIBUTE_TYPES}"
XMLTOHB_SRC_ATTRIBUTE_SOURCES+=" ${TARGETING_XMLTOHB_PROC_REL_PATH}/${XMLTOHB_BMC_ATTRIBUTE_TYPES}"

# SRC target sources
XMLTOHB_TARGET_TYPES_SOURCES+=" ${COMMON_XMLTOHB_REL_PATH}/${XMLTOHB_COMMON_TARGET_TYPES}"
XMLTOHB_TARGET_TYPES_SOURCES+=" ${TARGETING_XMLTOHB_PROC_REL_PATH}/${XMLTOHB_BMC_TARGET_TYPES}"

# SRC target merged
XMLTOHB_TARGET_TYPES_MERGED="target_types_merged.xml"

# Define XMLTOHB_MERGED_SOURCES
XMLTOHB_MERGED_SOURCES=""
XMLTOHB_MERGED_SOURCES+=" ${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}"
XMLTOHB_MERGED_SOURCES+=" ${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}"

printf "Running: $COMMON_XMLTOHB_REL_PATH/$XMLTOHB_MERGE_SCRIPT $XMLTOHB_SRC_ATTRIBUTE_SOURCES > 
    ${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES} \n\n"
$COMMON_XMLTOHB_REL_PATH/$XMLTOHB_MERGE_SCRIPT $XMLTOHB_SRC_ATTRIBUTE_SOURCES > \
    ${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES}

printf "Merging target sources into: ${GENDIR}/${XMLTOHB_TARGET_TYPES_MERGED}"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_TARGET_TYPES_SOURCES} > "${GENDIR}/${XMLTOHB_TARGET_TYPES_MERGED}"

printf "Running: $COMMON_XMLTOHB_REL_PATH/$XMLTOHB_TARGET_MERGE_SCRIPT 
      --common=${COMMON_XMLTOHB_REL_PATH}/${XMLTOHB_COMMON_TARGET_TYPES} 
      --plat=${TARGETING_XMLTOHB_PROC_REL_PATH}/${XMLTOHB_BMC_TARGET_TYPES_EXTENSION} > 
      ${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}\n\n"

"$COMMON_XMLTOHB_REL_PATH/$XMLTOHB_TARGET_MERGE_SCRIPT" \
  --common="${GENDIR}/${XMLTOHB_TARGET_TYPES_MERGED}" \
  --plat="${TARGETING_XMLTOHB_PROC_REL_PATH}/${XMLTOHB_BMC_TARGET_TYPES_EXTENSION}" \
  > "${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}"

LSV_FILE="${TARGETING_XMLTOHB_PROC_REL_PATH}/reqEkbAttrsXmlFileList.lsv"
XMLTOHB_FAPIATTR_SOURCES=$(<"$LSV_FILE")

# TODO: this has to access from hostfw repo in the future. For now, 
# mirrored the files and placed in the ekb directory
XMLTOHB_FAPIATTR_SOURCES=""
while read -r line; do
    XMLTOHB_FAPIATTR_SOURCES+="$EKB/${line} "  # or "${line}.xml", etc.
done < "$LSV_FILE"

# Merge all FAPI attribute files into one
printf "Merging FAPI attribute sources into: ${GENDIR}/${XMLTOHB_FAPI_XML}\n\n"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_FAPIATTR_SOURCES} > \
"${GENDIR}/${XMLTOHB_FAPI_XML}"

#Note that order matters here , we want hb_customized_attrs to be first so it's defaults get picked up first
#if there are duplicates
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES="${COMMON_XMLTOHB_REL_PATH}/${TEMP_DEFAULTS_XML} "
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES+="${TARGETING_XMLTOHB_PROC_REL_PATH}/${BMC_TEMP_DEFAULTS_XML} "

printf "Merging customization sources into: ${GENDIR}/${XMLTOHB_ATTRIBUTE_CUSTOMIZATION}\n\n"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES} > \
    "${GENDIR}/${XMLTOHB_ATTRIBUTE_CUSTOMIZATION}"

printf "Creating ekb target and attributes: ${GENDIR}/${XMLTOHB_EKB_ATTRIBUTE_TYPES} \n\n"
# convert FAPI attrs to plat attrs
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_EKB_TARGATTR_SCRIPT}" \
    --fapi=${GENDIR}/${XMLTOHB_FAPI_XML} \
    --attr=${GENDIR}/${XMLTOHB_EKB_ATTRIBUTE_TYPES} \
    --targ=${GENDIR}/${XMLTOHB_EKB_TARGET_TYPES} \
    --default=${GENDIR}/${XMLTOHB_ATTRIBUTE_CUSTOMIZATION}


#Print command for debug/logging
printf "Running: --ekbXmlFile=${GENDIR}/${XMLTOHB_EKB_ATTRIBUTE_TYPES} 
      --hbXmlFile=${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES}
      --fapi2Header=${TARGETING_XMLTOHB_PROC_REL_PATH}/attribute_service.H --outFile=${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}"

# Execute the Perl script
# EMPTY attribute_service.H file
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_DUPLICATE_SCRIPT}" \
    --ekbXmlFile=${GENDIR}/${XMLTOHB_EKB_ATTRIBUTE_TYPES} \
    --hbXmlFile=${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES} \
    --fapi2Header=${TARGETING_XMLTOHB_PROC_REL_PATH}/attribute_service.H \
    --outFile=${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}


printf "Running merge target script to merge ekb and src targets\n\n"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_TARGET_MERGE_SCRIPT}" \
    --plat="${GENDIR}/${XMLTOHB_EKB_TARGET_TYPES}" \
    --common="${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}" > "${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}"

# trim leading whitespace if any
XMLTOHB_MERGED_SOURCES="${XMLTOHB_MERGED_SOURCES#" "}"

# Merge all FAPI attribute files into one
printf "Merging attributes and targets $XMLTOHB_MERGED_SOURCES into: ${GENDIR}/${XMLTOHB_ATTRIBUTES_TARGETS_MERGED_XML}"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_MERGED_SOURCES} \
  > "${GENDIR}/${XMLTOHB_ATTRIBUTES_TARGETS_MERGED_XML}"

XMLTOHB_RAN_INDICATION="${GENDIR}/.called_xmltohb_compiler"

# create the header files, only needs generic xml
if [[ ! -f "$XMLTOHB_RAN_INDICATION" ]]; then
  printf "Running: ${XMLTOHB_COMPILER_SCRIPT}\n\n"

  "$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_COMPILER_SCRIPT}" \
    --hb-xml-file="${GENDIR}/${XMLTOHB_ATTRIBUTES_TARGETS_MERGED_XML}" \
    --filter-attr-file="${TARGETING_XMLTOHB_PROC_REL_PATH}/$filter_attr" \
    --build-bmc \
    --src-output-dir="${GENDIR}" \
    --img-output-dir=none \
    --img-output-file=none

printf "Successfully generated header files\n"

# TODO: enable it for filtering MRW during device tree generation
for system_mrw_xml in $SYSTEMS_MRW_XML ; do

    # Error if we can't find the file
    if [ ! -f "$system_mrw_xml" ] ; then
        echo "Error: Can't find MRW xml " $system_mrw_xml
        exit 1
    fi

    system_name=$(basename "$system_mrw_xml" .xml)

    echo "Processing system xml " $(basename "$system_mrw_xml")
    "$COMMON_MRW_REL_PATH/processMrw.pl" \
        -x "$system_mrw_xml" \
        -b bmc \
        -o "$GENDIR/${system_name}_bmc_mrw.xml"

    "$COMMON_XMLTOHB_REL_PATH/filter_out_unwanted_attributes.pl" --mrw-xml "$GENDIR/${system_name}_bmc_mrw.xml" \
    --tgt-xml "$GENDIR/$XMLTOHB_FULL_TARGET_TYPES" \
    --filter-attr-file "${TARGETING_XMLTOHB_PROC_REL_PATH}/$filter_attr" \
    --filter-tgt-file "${TARGETING_XMLTOHB_PROC_REL_PATH}/$filter_target"

    #remove empty lines created because of filtering and removing the attributes
    grep -v '^[[:space:]]*$' "$GENDIR/${system_name}_bmc_mrw.xml.updated" > $GENDIR/${system_name}_bmc_mrw_filtered.xml

    final_merged_xml_file_name="${system_name/-MRW/}.xml"
    echo "creating final merged file $final_merged_xml_file_name"
    $COMMON_XMLTOHB_REL_PATH/$XMLTOHB_MERGE_SCRIPT "$GENDIR/${system_name}_bmc_mrw_filtered.xml" ${GENDIR}/$XMLTOHB_ATTRIBUTES_TARGETS_MERGED_XML > \
    ${GENDIR}/${final_merged_xml_file_name}

done

#  touch "$XMLTOHB_RAN_INDICATION"
  echo "XMLTOHB compile completed and marker touched."
else
  echo "Already ran: Skipping ${XMLTOHB_COMPILER_SCRIPT}"
fi

#"$MERGE_SCRIPT" "$SYSTEM_XML" "$GENERIC_XML" "$MRW_XML" > "$BMC_XML"
