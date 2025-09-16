#!/bin/sh

TARGETING_XMLTOHB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_TARGETING_PATH="$(dirname "$TARGETING_XMLTOHB_DIR")"
GENDIR="${ROOT_TARGETING_PATH}/obj/genfiles"
COMMON_XMLTOHB_REL_PATH="${ROOT_TARGETING_PATH}/common/xmltohb"
TARGETING_XMLTOHB_REL_PATH="${ROOT_TARGETING_PATH}/xmltohb"
COMMON_MRW_REL_PATH="${ROOT_TARGETING_PATH}/common/mrw"

check_var () {
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
XMLTOHB_FAPI_XML="fapiattrs.xml"

# Script files
XMLTOHB_MERGE_SCRIPT="mergexml.sh"
XMLTOHB_COMPILER_SCRIPT="xmltohb.pl"
XMLTOHB_EKB_TARGATTR_SCRIPT="create_ekb_targattr.pl"
XMLTOHB_DUPLICATE_SCRIPT="handle_duplicate.pl"
XMLTOHB_REMOVE_HB_MAPPED_ATTR_SCRIPT="remove_hb_fapi_maps.pl"
XMLTOHB_SWAP_MAPPED_ATTR_SCRIPT="handle_fapi_attr_mapping.pl"

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

# step 1: Merge the contents of common attributes and the bmc attributes into
# XMLTOHB_SRC_ATTRIBUTE_TYPES
printf "Running: $COMMON_XMLTOHB_REL_PATH/$XMLTOHB_MERGE_SCRIPT $XMLTOHB_SRC_ATTRIBUTE_SOURCES > \
    ${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES} \n\n"
$COMMON_XMLTOHB_REL_PATH/$XMLTOHB_MERGE_SCRIPT $XMLTOHB_SRC_ATTRIBUTE_SOURCES > \
    ${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES}

if [ $? -ne 0 ]; then
    echo "${XMLTOHB_MERGE_SCRIPT} script failed to create ${XMLTOHB_SRC_ATTRIBUTE_TYPES}"
    exit 1
fi

# step 2: Merge the contents of common targettype, obmc targettype and obmc
# targetTypeExtenstion into XMLTOHB_TARGET_TYPES_MERGED
printf "Merging target sources into: ${GENDIR}/${XMLTOHB_TARGET_TYPES_MERGED}"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_TARGET_TYPES_SOURCES} > \
    "${GENDIR}/${XMLTOHB_TARGET_TYPES_MERGED}"

if [ $? -ne 0 ]; then
    echo "${XMLTOHB_MERGE_SCRIPT} script failed to create ${XMLTOHB_TARGET_TYPES_MERGED}"
    exit 1
fi

# step 3: Run the target merge script, which takes attributes from all these
# <targetType> and appends it to the targetType in XMLTOHB_SRC_TARGET_TYPES
printf "Running: $COMMON_XMLTOHB_REL_PATH/$XMLTOHB_TARGET_MERGE_SCRIPT \
      --common=${COMMON_XMLTOHB_REL_PATH}/${XMLTOHB_COMMON_TARGET_TYPES} \
      --plat=${TARGETING_XMLTOHB_PROC_REL_PATH}/${XMLTOHB_BMC_TARGET_TYPES_EXTENSION} > \
      ${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}\n\n"

"$COMMON_XMLTOHB_REL_PATH/$XMLTOHB_TARGET_MERGE_SCRIPT" \
  --common="${GENDIR}/${XMLTOHB_TARGET_TYPES_MERGED}" \
  --plat="${TARGETING_XMLTOHB_PROC_REL_PATH}/${XMLTOHB_BMC_TARGET_TYPES_EXTENSION}" \
  > "${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}"

if [ $? -ne 0 ]; then
    echo "${XMLTOHB_TARGET_MERGE_SCRIPT} script failed to create ${XMLTOHB_SRC_TARGET_TYPES}"
    exit 1
fi

# step 4: Get the list of all the ekb attribute info file names into
# XMLTOHB_FAPIATTR_SOURCES
XML_FILE="${TARGETING_XMLTOHB_PROC_REL_PATH}/ekbFileList.xml"

XMLTOHB_FAPIATTR_SOURCES=$(xmllint --xpath "/ekbFileList/file/@id" "$XML_FILE" \
    | sed -E 's/id="([^"]+)"/\1\n/g' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | sed "s|^|$EKB/|" \
    | tr '\n' ' ' | sed 's/ *$//')

echo "Files: $XMLTOHB_FAPIATTR_SOURCES"

# step 5: Merge the contents of all the ekb attribute info file into
# XMLTOHB_FAPI_XML
printf "Merging FAPI attribute sources into: ${GENDIR}/${XMLTOHB_FAPI_XML}\n\n"

"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_FAPIATTR_SOURCES} > \
"${GENDIR}/${XMLTOHB_FAPI_XML}"

if [ $? -ne 0 ]; then
    echo "${XMLTOHB_MERGE_SCRIPT} script failed to create ${XMLTOHB_FAPI_XML}"
    exit 1
fi

# Note that order matters here, we want hb_customized_attrs to be first so it's
# defaults get picked up first if there are duplicates
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES="${COMMON_XMLTOHB_REL_PATH}/${TEMP_DEFAULTS_XML} "
XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES+="${TARGETING_XMLTOHB_PROC_REL_PATH}/${BMC_TEMP_DEFAULTS_XML} "

# step 6: Merge the contents of attribute customization
# (default value for specific FAPI attribute)
# files into XMLTOHB_ATTRIBUTE_CUSTOMIZATION
printf "Merging customization sources into: ${GENDIR}/${XMLTOHB_ATTRIBUTE_CUSTOMIZATION}\n\n"

"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_ATTRIBUTE_CUSTOMIZATION_SOURCES} > \
    "${GENDIR}/${XMLTOHB_ATTRIBUTE_CUSTOMIZATION}"

if [ $? -ne 0 ]; then
    echo "${XMLTOHB_MERGE_SCRIPT} script failed to create ${XMLTOHB_ATTRIBUTE_CUSTOMIZATION}"
    exit 1
fi

# step 7: Create ekb attributes using the contents of XMLTOHB_FAPI_XML
# and apply customized default values if mentioned
printf "Creating ekb target and attributes: ${GENDIR}/${XMLTOHB_EKB_ATTRIBUTE_TYPES} \n\n"
# convert FAPI attrs to plat attrs
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_EKB_TARGATTR_SCRIPT}" \
    --fapi=${GENDIR}/${XMLTOHB_FAPI_XML} \
    --attr=${GENDIR}/${XMLTOHB_EKB_ATTRIBUTE_TYPES} \
    --targ=${GENDIR}/${XMLTOHB_EKB_TARGET_TYPES} \
    --default=${GENDIR}/${XMLTOHB_ATTRIBUTE_CUSTOMIZATION}

if [ $? -ne 0 ]; then
    echo "${XMLTOHB_EKB_TARGATTR_SCRIPT} script failed!"
    exit 1
fi

# Print command for debug/logging
printf "Running: --ekbXmlFile=${GENDIR}/${XMLTOHB_EKB_ATTRIBUTE_TYPES} \
      --hbXmlFile=${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES} \
      --fapi2Header=${TARGETING_XMLTOHB_PROC_REL_PATH}/attribute_service.H \
      --outFile=${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}"

# step 8: Generate XMLTOHB_FULL_ATTRIBUTE_TYPES
# This step merges together attribute_types_ekb and attribute_types_src
# into one output file XMLTOHB_FULL_ATTRIBUTE_TYPES.
# We don't want the EKB attributes to override fapi-mapped attributes
# we have already defined in hostboot's xml.
# TODO: EMPTY attribute_service.H file
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_DUPLICATE_SCRIPT}" \
    --ekbXmlFile=${GENDIR}/${XMLTOHB_EKB_ATTRIBUTE_TYPES} \
    --hbXmlFile=${GENDIR}/${XMLTOHB_SRC_ATTRIBUTE_TYPES} \
    --fapi2Header=${TARGETING_XMLTOHB_PROC_REL_PATH}/attribute_service.H \
    --outFile=${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}

if [ $? -ne 0 ]; then
    echo "${XMLTOHB_DUPLICATE_SCRIPT} script failed!"
    exit 1
fi

# step 9: Generate XMLTOHB_FULL_TARGET_TYPES
# This step merges the attributes defined under targetTypeExtension in the
# XMLTOHB_EKB_TARGET_TYPES with the targetType defined in the
# XMLTOHB_SRC_TARGET_TYPES
printf "Running merge target script to merge ekb and src targets\n\n"
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_TARGET_MERGE_SCRIPT}" \
    --plat="${GENDIR}/${XMLTOHB_EKB_TARGET_TYPES}" \
    --common="${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}" > "${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}"

cp "${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}" "${GENDIR}/temp_full_target_types.xml"
cp "${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}" "${GENDIR}/temp_full_attribute_types.xml"

if [ $? -ne 0 ]; then
    echo "${XMLTOHB_TARGET_MERGE_SCRIPT} script failed!"
    exit 1
fi

# step 10: Update XMLTOHB_FULL_TARGET_TYPES to contain the hostboot version
# of the name and not the Fapi2 version
# ATTR_EC -> EC (ATTR removed)
# ATTR_CHIP_UNIT_POS -> CHIP_UNIT (Special name applied)
printf "Running $XMLTOHB_SWAP_MAPPED_ATTR_SCRIPT script\n\n"

"${COMMON_XMLTOHB_REL_PATH}/${XMLTOHB_SWAP_MAPPED_ATTR_SCRIPT}" \
    --srcTargetXml="${GENDIR}/${XMLTOHB_SRC_TARGET_TYPES}" \
    --ekbTargetXml="${GENDIR}/${XMLTOHB_EKB_TARGET_TYPES}" \
    --fullAttrXml="${GENDIR}/${XMLTOHB_FULL_ATTRIBUTE_TYPES}" \
    --fullTargetXml="${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}" \
    --fapi2Header="${TARGETING_XMLTOHB_PROC_REL_PATH}/attribute_service.H"

if [ $? -ne 0 ]; then
    echo "${XMLTOHB_SWAP_MAPPED_ATTR_SCRIPT} script failed!"
    exit 1
fi

# step 11: Enclose the contents of XMLTOHB_FULL_TARGET_TYPES within <attributes> tag
# This is expected by all the scripts.
# TODO: Can this be moved into one of the above scripts? Doing that now will break the flow
echo '<attributes>' | cat - ${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES} > tempFull && \
    mv tempFull ${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}
echo '</attributes>' | cat ${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES} - > tempFull && \
    mv tempFull ${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}

"$TARGETING_XMLTOHB_REL_PATH/expandTargetTypes.pl" \
    --fromTgtXml "${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES}" \
    --filter-tgt-file "${TARGETING_XMLTOHB_PROC_REL_PATH}/$filter_target" \
    --filter-attr-file "${TARGETING_XMLTOHB_PROC_REL_PATH}/$filter_attr" \
    --outXml "${GENDIR}/${XMLTOHB_FULL_TARGET_TYPES_EXPANDED}" 

# remove empty lines created because of filtering and removing the attributes
#move it back to full target type file
grep -v '^[[:space:]]*$' "$GENDIR/${XMLTOHB_FULL_TARGET_TYPES_EXPANDED}" > \
    $GENDIR/${XMLTOHB_FULL_TARGET_TYPES}

# trim leading whitespace if any
XMLTOHB_MERGED_SOURCES="${XMLTOHB_MERGED_SOURCES#" "}"

# Merge all FAPI attribute files into one
printf "Merging attributes and targets $XMLTOHB_MERGED_SOURCES into: \
    ${GENDIR}/${XMLTOHB_ATTRIBUTES_TARGETS_MERGED_XML}"

# step 12: Merge the contents of XMLTOHB_FULL_ATTRIBUTE_TYPES and
# XMLTOHB_FULL_TARGET_TYPES into XMLTOHB_ATTRIBUTES_TARGETS_MERGED_XML
"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_MERGE_SCRIPT}" ${XMLTOHB_MERGED_SOURCES} \
  > "${GENDIR}/${XMLTOHB_ATTRIBUTES_TARGETS_MERGED_XML}"

if [ $? -ne 0 ]; then
    echo "${XMLTOHB_MERGE_SCRIPT} script failed to create ${XMLTOHB_ATTRIBUTES_TARGETS_MERGED_XML}"
    exit 1
fi

# step 13: Create required header files with the MERGED XML.
printf "Running: ${XMLTOHB_COMPILER_SCRIPT}\n\n"

"$COMMON_XMLTOHB_REL_PATH/${XMLTOHB_COMPILER_SCRIPT}" \
--hb-xml-file="${GENDIR}/${XMLTOHB_ATTRIBUTES_TARGETS_MERGED_XML}" \
--filter-attr-file="${TARGETING_XMLTOHB_PROC_REL_PATH}/$filter_attr" \
--build-bmc \
--src-output-dir="${GENDIR}" \
--img-output-dir=none \
--img-output-file=none

if [ $? -ne 0 ]; then
    echo "${XMLTOHB_COMPILER_SCRIPT} script failed to create header file\n"
    exit 1
fi

printf "Successfully generated header files\n"

# TODO: enable it for filtering MRW during device tree generation
for system_mrw_xml in $SYSTEMS_MRW_XML; do
    # Error if we can't find the file
    if [ ! -f "$system_mrw_xml" ]; then
        echo "Error: Can't find MRW xml " $system_mrw_xml
        exit 1
    fi

    system_name=$(basename "$system_mrw_xml" .xml)

    echo "Processing system xml " $(basename "$system_mrw_xml")
    "$COMMON_MRW_REL_PATH/processMrw.pl" \
        -x "$system_mrw_xml" \
        -b bmc \
        -o "$GENDIR/${system_name}_bmc_mrw.xml"

    # step 14: Filter the processed mrw output file
    "$COMMON_XMLTOHB_REL_PATH/filter_out_unwanted_attributes.pl" \
        --mrw-xml "$GENDIR/${system_name}_bmc_mrw.xml" \
        --tgt-xml "$GENDIR/$XMLTOHB_FULL_TARGET_TYPES" \
        --filter-attr-file "${TARGETING_XMLTOHB_PROC_REL_PATH}/$filter_attr" \
        --filter-tgt-file "${TARGETING_XMLTOHB_PROC_REL_PATH}/$filter_target"

    if [ $? -ne 0 ]; then
        echo "filter_out_unwanted_attributes.pl script failed\n"
        exit 1
    fi

    # remove empty lines created because of filtering and removing the attributes
    grep -v '^[[:space:]]*$' "$GENDIR/${system_name}_bmc_mrw.xml.updated" > \
        $GENDIR/${system_name}_bmc_mrw_filtered.xml

    final_merged_xml_file_name="${system_name/-MRW/}.xml"
    echo "creating final merged file $final_merged_xml_file_name"

    # Step 15: Merge the contents of processed MRW output file, attributes
    # and targets full file into the final system xml file
    $COMMON_XMLTOHB_REL_PATH/$XMLTOHB_MERGE_SCRIPT \
        "$GENDIR/${system_name}_bmc_mrw_filtered.xml" ${GENDIR}/$XMLTOHB_ATTRIBUTES_TARGETS_MERGED_XML > \
        ${GENDIR}/${final_merged_xml_file_name}

    if [ $? -ne 0 ]; then
        echo "${XMLTOHB_MERGE_SCRIPT} script failed to create ${final_merged_xml_file_name}"
        exit 1
    fi
done
