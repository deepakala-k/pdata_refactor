#!/usr/bin/perl
# IBM_PROLOG_BEGIN_TAG
# This is an automatically generated prolog.
#
# $Source: src/usr/targeting/common/xmltohb/xmltohb.pl $
#
# OpenPOWER HostBoot Project
#
# Contributors Listed Below - COPYRIGHT 2012,2023
# [+] International Business Machines Corp.
# [+] YADRO
#
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied. See the License for the specific language governing
# permissions and limitations under the License.
#
# IBM_PROLOG_END_TAG

#
# Purpose:
#   Process the attribute xml files, generate code, create binaries, etc
#
# Change Log **********************************************************
#
# End Change Log ******************************************************

use strict;

################################################################################
# Use of the following packages
################################################################################

use Carp;
use Getopt::Long;
use Pod::Usage;
use XML::Simple;
use Text::Wrap;
use Data::Dumper;
use POSIX;
use Env;
use XML::LibXML;
use Scalar::Util qw(looks_like_number);


# Provides object deep copy capability to support virtual
# attribute removal
use Storable 'dclone';

################################################################################
# Set PREFERRED_PARSER to XML::Parser. Otherwise it uses XML::SAX which contains
# bugs that result in XML parse errors that can be fixed by adjusting white-
# space (i.e. parse errors that do not make sense).
################################################################################
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

################################################################################
# Process command line parameters, issue help text if needed
################################################################################

sub main{ }
my $cfgSrcOutputDir = ".";
my $cfgImgOutputDir = ".";
my $cfgHbXmlFile = "./hb.xml";
my $cfgVmmConstsFile = "../../../include/usr/vmmconst.h";
my $cfgFapiAttributesXmlFile = "";
my $cfgImgOutputFile = "./targeting.bin";
my $cfgHelp = 0;
my $cfgMan = 0;
my $cfgVerbose = 0;
my $cfgShortEnums = 0;
my $cfgBigEndian = 1;
my $cfgIncludeFspAttributes = 0;
my $CfgSMAttrFile = "";
my $cfgAddVersionPage = 0;
my $nonSyncAttribFile = "";
my $filterAttrFile = "";
my $filterTargetFile = "";

my $cfgBiosXmlFile = undef;
my $cfgBiosSchemaFile = undef;
my $cfgBiosOutputFile = undef;

my $MAX_4_BYTE_VALUE = 0xFFFFFFFF;
my $buildBmc = 0;

GetOptions("hb-xml-file:s" => \$cfgHbXmlFile,
           "src-output-dir:s" =>  \$cfgSrcOutputDir,
           "img-output-dir:s" =>  \$cfgImgOutputDir,
           "fapi-attributes-xml-file:s" => \$cfgFapiAttributesXmlFile,
           "img-output-file:s" =>  \$cfgImgOutputFile,
           "vmm-consts-file:s" =>  \$cfgVmmConstsFile,
           "short-enums!" =>  \$cfgShortEnums,
           "big-endian!" =>  \$cfgBigEndian,
           "smattr-output-file:s" => \$CfgSMAttrFile,
           "include-fsp-attributes!" =>  \$cfgIncludeFspAttributes,
           "version-page!" => \$cfgAddVersionPage,
           "bios-xml-file:s" => \$cfgBiosXmlFile,
           "bios-schema-file:s" => \$cfgBiosSchemaFile,
           "bios-output-file:s" => \$cfgBiosOutputFile,
           "non-sync-attrib-file:s" => \$nonSyncAttribFile,
           "filter-attr-file:s" => \$filterAttrFile,
           "filter-target-file:s" => \$filterTargetFile,
           "build-bmc!" => \$buildBmc,
           "help" => \$cfgHelp,
           "man" => \$cfgMan,
           "verbose" => \$cfgVerbose ) || pod2usage(-verbose => 0);

pod2usage(-verbose => 1) if $cfgHelp;
pod2usage(-verbose => 2) if $cfgMan;

# Remove extraneous '/' from end of path names; use temporary version of $/ for
# the chomp
{
    local $/ = '/';
    chomp($cfgSrcOutputDir);
    $cfgSrcOutputDir .= "/";

    chomp($cfgImgOutputDir);
    $cfgImgOutputDir .= "/";
}

if($cfgVerbose)
{
    print STDOUT "Host boot intemediate XML model = $cfgHbXmlFile\n";
    print STDOUT "Fapi attributes XML file = $cfgFapiAttributesXmlFile\n";
    print STDOUT "Source output dir = $cfgSrcOutputDir\n";
    print STDOUT "Image output dir = $cfgImgOutputDir\n";
    print STDOUT "VMM constants file = $cfgVmmConstsFile\n";
    print STDOUT "Short enums = $cfgShortEnums\n";
    print STDOUT "Big endian = $cfgBigEndian\n";
    print STDOUT "include-fsp-attributes = $cfgIncludeFspAttributes\n",
    print STDOUT "version-page = $cfgAddVersionPage\n",
    print STDOUT "bios-schema-file = $cfgBiosSchemaFile\n";
    print STDOUT "bios-xml-file = $cfgBiosXmlFile\n";
    print STDOUT "bios-output-file = $cfgBiosOutputFile\n";
    print STDOUT "Non Sync Attributes file = $nonSyncAttribFile\n";
    print STDOUT "filter-attr-file = $filterAttrFile\n";
    print STDOUT "filter-target-file = $filterTargetFile\n";
}

################################################################################
# Initialize some globals
################################################################################

use constant INVALID_HUID=>0xffffffff;
use constant PEER_HUID_NOT_PRESENT=>0xfffffffe;

# When computing associations between targets, always store the association list
# pointers in this exact order within each target object.  It also must be the
# case that the ASSOCIATION_TYPE enum in the target service header must declare
# the corresponding enum values in this order as well
use constant PARENT_BY_CONTAINMENT => "ParentByContainment";
use constant CHILD_BY_CONTAINMENT => "ChildByContainment";
use constant PARENT_BY_AFFINITY => "ParentByAffinity";
use constant CHILD_BY_AFFINITY => "ChildByAffinity";
use constant PERVASIVE_CHILD => "PervasiveChild";
use constant PARENT_PERVASIVE => "ParentPervasive";
use constant OMIC_PARENT => "OmicParent";
use constant OMI_CHILD => "OmiChild";
use constant PAUC_CHILD => "PaucChild";
use constant PAUC_PARENT => "PaucParent";
my @associationTypes = ( PARENT_BY_CONTAINMENT,
    CHILD_BY_CONTAINMENT, PARENT_BY_AFFINITY, CHILD_BY_AFFINITY,
    PERVASIVE_CHILD, PARENT_PERVASIVE, OMIC_PARENT, OMI_CHILD, PAUC_CHILD,
    PAUC_PARENT );

# Constants for attribute names (minus ATTR_ prefix)
use constant ATTR_OMIC_PARENT => "OMIC_PARENT";
use constant ATTR_PAUC_PARENT => "PAUC_PARENT";
use constant ATTR_PARENT_PERVASIVE => "PARENT_PERVASIVE";
use constant ATTR_PHYS_PATH => "PHYS_PATH";
use constant ATTR_AFFINITY_PATH => "AFFINITY_PATH";
use constant ATTR_UNKNOWN => "UnknownAttributeName";
use constant ATTR_POSITION => "POSITION";
use constant ATTR_CHIP_UNIT => "CHIP_UNIT";
use constant ATTR_CLASS => "CLASS";
use constant ATTR_TYPE => "TYPE";
use constant ATTR_MODEL => "MODEL";

# Data manipulation constants
use constant BITS_PER_BYTE => 8;
use constant LOW_BYTE_MASK => 0xFF;
use constant BYTE_RIGHT_BIT_INDEX => BITS_PER_BYTE - 1;
use constant BYTES_PER_ABSTRACT_POINTER => 8;

# This is the maximum total sum of (compute nodes + control nodes) possible for
# any known system using this attribute compiler.  It is used to reserve
# space in each system target's CHILD + CHILD_BY_AFFINITY association lists
# so that FSP can link a system target to multiple nodes
use constant MAX_COMPUTE_AND_CONTROL_NODE_SUM => 5;

# These constants describe the persistencies of different targeting attributes.
# NOTE: keep this list in sync with the data that gets written out in writeHeaderFormatHeaderFile!
use constant
{
    SECTION_TYPE_PNOR_RO => 0,
    SECTION_TYPE_PNOR_RW => 1,
    SECTION_TYPE_HEAP_PNOR_INIT => 2,
    SECTION_TYPE_HEAP_ZERO_INIT => 3,
    SECTION_TYPE_FSP_P0_ZERO_INIT => 4,
    SECTION_TYPE_FSP_P0_FLASH_INIT => 5,
    SECTION_TYPE_FSP_P3_RO => 6,
    SECTION_TYPE_FSP_P3_RW => 7,
    SECTION_TYPE_FSP_P1_ZERO_INIT => 8,
    SECTION_TYPE_FSP_P1_FLASH_INIT => 9,
    SECTION_TYPE_HB_HEAP_ZERO_INIT => 0xa,
    SECTION_TYPE_HB_METADATA => 0xb,
    SECTION_TYPE_BAD_VALUE => 255
};

my $xml = new XML::Simple (KeyAttr=>[]);
use Digest::MD5 qw(md5_hex);

# Until full machine parseable workbook parsing splits out all the input files,
# use the intermediate representation containing the full host boot model.
# Aborts application if file name not found.
# NOTE: the attribute list initially contains both real and virtual attributes
my $allAttributes = $xml->XMLin($cfgHbXmlFile,
    forcearray => ['enumerationType','enumerator','attribute','hwpfToHbAttrMap',
                   'compileAttribute','range']);


my $fapiAttributes = {};
if ($cfgFapiAttributesXmlFile ne "")
{
    $fapiAttributes = $xml->XMLin($cfgFapiAttributesXmlFile,
        forcearray => ['attribute']);
}

my @nonSyncAttributes = {};
my @fspAccesCheck = {};
if ($nonSyncAttribFile ne "")
{
    my $nsa = $xml->XMLin($nonSyncAttribFile, ForceArray=>['attribute']);
    foreach my $attr (@{$nsa->{attribute}})
    {
        my $attrName = $attr->{id};
        if (!defined($attr->{fspaccess_nosync}))
        {
            push(@fspAccesCheck, $attrName);
        }
        push(@nonSyncAttributes, $attrName);
    }
}

# save attributes defined as Target_t type
my %Target_t = ();

# Perform some sanity validation of the model (so we don't have to later)
# Subject virtual attributes to same sanity checks
validateAttributes($allAttributes);
validateTargetInstances($allAttributes);
validateTargetTypes($allAttributes);
validateTargetTypesExtension($allAttributes);

# Clone the attributes and strip out any references to virtual
# attributes, then continue forward using the result as the typical
# working attribute set.  The original set containing virtual attributes
# will be used for very specific tasks, like computing associations
my $attributes = dclone $allAttributes;
my %virtualAttrIds = ();

# if a attribute filter file is provided, remove the attributes that are not
# present in the set.Filter it before doing any operations.
# $allAttributes to contain the actual list

# TODO, need to check if $allAttributes also needs to be filtered??
if ($filterAttrFile ne "")
{
    $attributes = filterAttributes($attributes, $filterAttrFile);
}

for my $attr (reverse 0..((scalar @{$attributes->{attribute}})-1) )
{
    if(exists $attributes->{attribute}[$attr]->{virtual})
    {
        # Found a virtual attribute; note it and remove
        $virtualAttrIds{$attributes->{attribute}[$attr]->{id}} = 1;
        splice @{$attributes->{attribute}}, $attr, 1;
    }
}

foreach my $targetType (@{$attributes->{targetType}})
{
    if(exists $targetType->{attribute})
    {
        for my $attr (reverse 0..((scalar
            @{$targetType->{attribute}})-1))
        {
            my $currentAttr = $targetType->{attribute}[$attr];
            if(   exists $currentAttr->{id}
               && exists $virtualAttrIds{$currentAttr->{id}} )
            {
                # A targetType refers to the virtual attribute
                # so remove it
                splice @{$targetType->{attribute}}, $attr, 1;
            }
        }
    }
}

if($cfgIncludeFspAttributes)
{
    handleTgtPtrAttributesFsp(\$attributes, \%Target_t);
}
else
{
    handleTgtPtrAttributesHb(\$attributes, \%Target_t);
}

# Open the output files and write them
if( !($cfgSrcOutputDir =~ "none") )
{
    # secureboot validation of RW persistent attributes
    generateRWPersistValidations($cfgSrcOutputDir, $attributes);

    open(ATTR_TARG_MAP_FILE,">$cfgSrcOutputDir"."targAttrOverrideData.H")
      or croak("Target Attribute data file: \"$cfgSrcOutputDir"
        . "targAttrOverrideData.H\" could not be opened.");
    my $targAttrFile = *ATTR_TARG_MAP_FILE;
    writeTargAttrMap($attributes, $targAttrFile);
    close $targAttrFile;

    open(ATTR_ID_MAP_H_FILE,">$cfgSrcOutputDir"."targAttrIdToName.H")
      or croak("Target Attribute ID to Name map H file: \"$cfgSrcOutputDir"
        . "targAttrIdToName.H\" could not be opened.");
    my $targAttrIdNameHFile = *ATTR_ID_MAP_H_FILE;
    writeAttrIdNameHFile($targAttrIdNameHFile);
    open(ATTR_ID_MAP_C_FILE,">$cfgSrcOutputDir"."targAttrIdToName.C")
      or croak("Target Attribute ID to Name map C file: \"$cfgSrcOutputDir"
        . "targAttrIdToName.C\" could not be opened.");
    my $targAttrIdNameCFile = *ATTR_ID_MAP_C_FILE;
    writeAttrIdNameCFileHeader($targAttrIdNameCFile);
    writeAttrIdNameMap($attributes, $targAttrIdNameCFile, 1); # RW-only attr map
    writeAttrIdNameMap($attributes, $targAttrIdNameCFile, 0); # All attr map
    close $targAttrIdNameHFile;
    close $targAttrIdNameCFile;

    open(MUTEX_ATTR_FILE, ">$cfgSrcOutputDir"."mutexattributes.H")
      or croak ("Mutex Attribute file: \"$cfgSrcOutputDir"
        . "mutexattributes.H\" could not be opened.");
    my $mutexFile = *MUTEX_ATTR_FILE;
    writeMutexFileHeader($mutexFile);
    writeMutexFileAttrs($attributes,$mutexFile);
    writeMutexFileFooter($mutexFile);
    close $mutexFile;


    open(TRAIT_FILE,">$cfgSrcOutputDir"."attributetraits.H")
      or croak ("Trait file: \"$cfgSrcOutputDir"
        . "attributetraits.H\" could not be opened.");
    my $traitFile = *TRAIT_FILE;
    writeTraitFileHeader($attributes,$traitFile);
    writeTraitFileTraits($attributes,$traitFile);
    writeTraitFileFooter($traitFile);
    close $traitFile;

    open(ATTR_FILE,">$cfgSrcOutputDir"."attributeenums.H")
      or croak ("Attribute enum file: \"$cfgSrcOutputDir"
        . "attributeenums.H\" could not be opened.");
    my $enumFile = *ATTR_FILE;
    writeEnumFileHeader($enumFile);
    writeEnumFileAttrIdEnum($attributes,$enumFile);
    writeEnumFileAttrEnums($attributes,$enumFile);
    writeEnumFileFooter($enumFile);
    close $enumFile;

    open(STRING_HEADER_FILE,">$cfgSrcOutputDir"."attributestrings.H")
      or croak ("Attribute string header file: \"$cfgSrcOutputDir"
        . "attributestrings.H\" could not be opened.");
    my $stringHeaderFile = *STRING_HEADER_FILE;
    writeStringHeaderFileHeader($stringHeaderFile);
    writeStringHeaderFileStrings($attributes,$stringHeaderFile);
    writeStringHeaderFileFooter($stringHeaderFile);
    close $stringHeaderFile;

    open(STRING_IMPLEMENTATION_FILE,">$cfgSrcOutputDir"."attributestrings.C")
      or croak ("Attribute string source file: \"$cfgSrcOutputDir"
        . "attributestrings.C\" could not be opened.");
    my $stringImplementationFile = *STRING_IMPLEMENTATION_FILE;
    writeStringImplementationFileHeader($stringImplementationFile);
    writeStringImplementationFileStrings($attributes,$stringImplementationFile);
    writeStringImplementationFileFooter($stringImplementationFile);
    writeTestEntityPath($attributes);
    close $stringImplementationFile;

    open(STRUCTS_HEADER_FILE,">$cfgSrcOutputDir"."attributestructs.H")
      or croak ("Attribute struct file: \"$cfgSrcOutputDir"
        . "attributestructs.H\" could not be opened.");
    my $structFile = *STRUCTS_HEADER_FILE;
    writeStructFileHeader($structFile);
    writeStructFileStructs($attributes,$structFile);
    writeStructFileFooter($structFile);
    close $structFile;

    open(PNOR_HEADER_DEF_FILE,">$cfgSrcOutputDir"."pnortargeting.H")
      or croak ("Targeting header definition header file: \"$cfgSrcOutputDir"
        . "pnortargeting.H\" could not be opened.");
    my $pnorHeaderDefFile = *PNOR_HEADER_DEF_FILE;
    writeHeaderFormatHeaderFile($pnorHeaderDefFile);
    close $pnorHeaderDefFile;

    open(FAPI2_PLAT_ATTR_MACROS_FILE,">$cfgSrcOutputDir"."fapi2platattrmacros.H")
      or croak ("FAPI2 platform attribute macro header file: \"$cfgSrcOutputDir"
        . "fapi2platattrmacros.H\" could not be opened.");
    my $fapi2PlatAttrMacrosHeaderFile = *FAPI2_PLAT_ATTR_MACROS_FILE;
    writeFapi2PlatAttrMacrosHeaderFileHeader ($fapi2PlatAttrMacrosHeaderFile);
    writeFapi2PlatAttrMacrosHeaderFileContent($attributes,$fapiAttributes,
        $fapi2PlatAttrMacrosHeaderFile);
    writeFapi2PlatAttrMacrosHeaderFileFooter ($fapi2PlatAttrMacrosHeaderFile);
    close $fapi2PlatAttrMacrosHeaderFile;

    open(ATTR_ATTRERRL_C_FILE,">$cfgSrcOutputDir"."errludattribute_gen.C")
      or croak ("Attribute errlog C file: \"$cfgSrcOutputDir"
        . "errludattribute_gen.C\" could not be opened.");
    my $attrErrlCFile = *ATTR_ATTRERRL_C_FILE;
    writeAttrErrlCFile($attributes,$attrErrlCFile);
    close $attrErrlCFile;

    mkdir("$cfgSrcOutputDir/errl");
    open(ATTR_ATTRERRL_H_FILE,">$cfgSrcOutputDir"."errl/errludattributeP_gen.H")
      or croak ("Attribute errlog H file: \"$cfgSrcOutputDir"
        . "errl/errludattributeP_gen.H\" could not be opened.");
    my $attrErrlHFile = *ATTR_ATTRERRL_H_FILE;

    open(ATTR_ATTRERRL_PY_FILE,">$cfgSrcOutputDir"."errl/errludattributeP_gen.py")
    or croak ("Attribute errlog PY file: \"$cfgSrcOutputDir"
        . "errl/errludattributeP_gen.py\" could not be opened.");
    my $attrErrlPYFile = *ATTR_ATTRERRL_PY_FILE;

    writeAttrErrlHFile($attributes,$attrErrlHFile,$attrErrlPYFile);
    close $attrErrlHFile;

    open(ATTR_TARGETERRL_C_FILE,">$cfgSrcOutputDir"."errludtarget.C")
      or croak ("Target errlog C file: \"$cfgSrcOutputDir"
        . "errludtarget.C\" could not be opened.");
    my $targetErrlCFile = *ATTR_TARGETERRL_C_FILE;
    writeTargetErrlCFile($attributes,$targetErrlCFile);
    close $targetErrlCFile;

    open(ATTR_TARGETERRL_H_FILE,">$cfgSrcOutputDir"."errl/errludtarget.H")
      or croak ("Target errlog H file: \"$cfgSrcOutputDir"
        . "errl/errludtarget.H\" could not be opened.");
    my $targetErrlHFile = *ATTR_TARGETERRL_H_FILE;
    open(ATTR_ENTITYPATH_PY_FILE,">$cfgSrcOutputDir"."errl/entityPath.py")
      or croak ("Target errlog Python file: \"$cfgSrcOutputDir"
        . "errl/entityPath.py\" could not be opened.");
    my $entityPathPYFile = *ATTR_ENTITYPATH_PY_FILE;
    open(ATTR_TARGETERRL_PY_FILE,">$cfgSrcOutputDir"."errl/errludtarget.py")
      or croak ("Target errlog Python file: \"$cfgSrcOutputDir"
        . "errl/errludtarget.py\" could not be opened.");
    my $targetErrlPYFile = *ATTR_TARGETERRL_PY_FILE;
    writeTargetErrlHFile($attributes,$targetErrlHFile,$entityPathPYFile,$targetErrlPYFile);
    close $targetErrlHFile;

    open(ATTR_INFO_CSV_FILE,">$cfgSrcOutputDir"."targAttrInfo.csv")
      or croak ("Attribute info csv file: \"$cfgSrcOutputDir"
        . "targAttrInfo.csv\" could not be opened.");
    my $attrInfoCsvFile = *ATTR_INFO_CSV_FILE;
    writeAttrInfoCsvFile($attributes,$attrInfoCsvFile);
    close $attrInfoCsvFile;

    open(MAP_ATTR_METADATA_H_FILE,">$cfgSrcOutputDir"."mapattrmetadata.H")
      or croak ("Attribute metadata map file Header: \"$cfgSrcOutputDir"
        . "mapattrmetadata.H\" could not be opened.");
    my $attrMetadataMapHFile = *MAP_ATTR_METADATA_H_FILE;
    writeAttrMetadataMapHFile($attrMetadataMapHFile);
    close $attrMetadataMapHFile;

    open(MAP_ATTR_METADATA_C_FILE,">$cfgSrcOutputDir"."mapattrmetadata.C")
      or croak ("Attribute metadata map C file: \"$cfgSrcOutputDir"
        . "mapattrmetadata.C\" could not be opened.");
    my $attrMetadataMapCFile = *MAP_ATTR_METADATA_C_FILE;
    writeAttrMetadataMapCFileHeader($attrMetadataMapCFile);
    writeAttrMetadataMapCFile($attributes,$attrMetadataMapCFile);
    writeAttrMetadataMapCFileFooter($attrMetadataMapCFile);
    close $attrMetadataMapCFile;

    open(MAP_ATTR_SIZE_H_FILE,">$cfgSrcOutputDir"."mapsystemattrsize.H")
      or croak ("Attribute size map file Header: \"$cfgSrcOutputDir"
        . "mapsystemattrsize.H\" could not be opened.");
    my $attrSizeMapHFile = *MAP_ATTR_SIZE_H_FILE;
    writeAttrSizeMapHFile($attrSizeMapHFile);
    close $attrSizeMapHFile;

    open(MAP_ATTR_SIZE_C_FILE,">$cfgSrcOutputDir"."mapsystemattrsize.C")
      or croak ("Attribute size map file: \"$cfgSrcOutputDir"
        . "mapsystemattrsize.C\" could not be opened.");
    my $attrSizeMapCFile = *MAP_ATTR_SIZE_C_FILE;
    writeAttrSizeMapCFileHeader($attrSizeMapCFile);
    writeAttrSizeMapCFile($attributes,$attrSizeMapCFile);
    writeAttrSizeMapCFileFooter($attrSizeMapCFile);
    close $attrSizeMapCFile;

    open(ATTR_SIZES_H_FILE, ">$cfgSrcOutputDir"."attrsizesdata.H")
      or croak ("Attribute size file: \"$cfgSrcOutputDir"
        . "attrsizesdata.H\" could not be opened.");
    my $attrSizesDataHFile = *ATTR_SIZES_H_FILE;
    writeAttrSizesHFile($attrSizesDataHFile);
    open(ATTR_SIZES_C_FILE, ">$cfgSrcOutputDir"."attrsizesdata.C")
      or croak ("Attribute size file: \"$cfgSrcOutputDir"
        . "attrsizesdata.C\" could not be opened.");
    my $attrSizesDataCFile = *ATTR_SIZES_C_FILE;
    writeAttrSizesCFile($attributes, $attrSizesDataCFile, "attrsizesdata.H");
    close $attrSizesDataHFile;
    close $attrSizesDataCFile;
}

use constant ATTRID => 0;
use constant HUID   => 1;
use constant DATA   => 2;
use constant SECTION => 3;
use constant TARGET => 4;
use constant ATTRNAME => 5;
my @attrDataforSM = ();

#Flag which indicates if the script needs to add the 4096 bytes of version
#checksum as first page in the binary file generated.
my $addRO_Section_VerPage = 0;
if( !($cfgImgOutputDir =~ "none") )
{
    #Version page will be added only if the script is called in with the flag
    #--version-page
    if ($cfgAddVersionPage)
    {
        $addRO_Section_VerPage = 1;
    }

    # Different portions of the targeting data split up.
    my $combinedData;
    my $protectedData;
    my $unprotectedData;

    #Pass the $addRO_Section_VerPage into the sub rotuine
    generateTargetingImage($cfgVmmConstsFile,$attributes,\%Target_t,
                           $addRO_Section_VerPage,$allAttributes,
                           \$combinedData,
                           \$protectedData,
                           \$unprotectedData);

    # Generate combined targeting file
    open(PNOR_TARGETING_FILE,">$cfgImgOutputDir".$cfgImgOutputFile)
      or croak ("Targeting image file: \"$cfgImgOutputDir"
        . "$cfgImgOutputFile\" could not be opened.");
    binmode(PNOR_TARGETING_FILE);
    print PNOR_TARGETING_FILE "$combinedData";
    close(PNOR_TARGETING_FILE);

    # Generate protected payload file
    open(PNOR_TARGETING_FILE,">$cfgImgOutputDir"."$cfgImgOutputFile.protected")
      or fatal ("Targeting image file: \"$cfgImgOutputDir"
        . "$cfgImgOutputFile.protected\" could not be opened.");
    binmode(PNOR_TARGETING_FILE);
    print PNOR_TARGETING_FILE "$protectedData";
    close(PNOR_TARGETING_FILE);

    # Generate unprotected payload file
    open(PNOR_TARGETING_FILE,
         ">$cfgImgOutputDir"."$cfgImgOutputFile.unprotected")
      or fatal ("Targeting image file: \"$cfgImgOutputDir"
        . "$cfgImgOutputFile.unprotected\" could not be opened.");
    binmode(PNOR_TARGETING_FILE);
    print PNOR_TARGETING_FILE "$unprotectedData";
    close(PNOR_TARGETING_FILE);

    if ($CfgSMAttrFile ne "")
    {
        generateXMLforSM();
    }

}

exit(0);

# sub generateRWPersistValidations
# Generates code to validate the values of persistent read/write attributes
# @param[in] rwAttrOutputDir - The directory to place the output files
# @param[in] attributes - The list of attributes to generate code from
# @return none
sub generateRWPersistValidations {

#intentionally not indenting the top level of this function for readability
my ($rwAttrOutputDir, $attributes) = @_;

# Begin secure boot verification codegen for R/W persistent attributes
# Set up csv output file R/W persistent attributes
open(my $rwAttrFile, ">$rwAttrOutputDir"."PersistRwAttrList.csv")
      or croak("R/W data file 'PersistRwAttrList.csv' could not be opened.");

print $rwAttrFile <<VERBATIM;
# PersistRwAttrList.csv
# This file is generated by perl script xmltohb.pl
# It lists all non-volatile read/write attributes that persist in PNOR
# and can be manipulated at will.
VERBATIM

my @rwPersistAttrs; # store the persistent attributes in an array
my %attrEnumTypes; # store enum types in a hash table

foreach my $attrs (@{$attributes->{attribute}})
{
    if (exists $attrs->{readable} &&
        exists $attrs->{writeable} &&
        exists $attrs->{persistency} &&
        $attrs->{persistency} eq "non-volatile")
    {
        print $rwAttrFile "$attrs->{id}\n";
        push @rwPersistAttrs, $attrs;

        # do a little bit of validation for the range tag
        if (exists $attrs->{range})
        {
            if (!exists $attrs->{simpleType})
            {
                die "Attribute $attrs->{id} must be simpleType to use range tag.";
            }
            elsif (exists $attrs->{simpleType}->{enumeration})
            {
                die "Enumeration and range tags cannot coexist. See $attrs->{id}";
            }
        }
    }
}

foreach my $atype (@{$attributes->{enumerationType}})
{
    $attrEnumTypes{$atype->{id}}=$atype;
}

close $rwAttrFile;

# Set up header/cpp output file for secure boot verification codegen
open(my $rwAttrHFile, ">$rwAttrOutputDir"."persistrwattrcheck.H")
      or croak("R/W H gen file 'persistrwattrcheck.H' could not be opened.");

open(my $rwAttrCFile, ">$rwAttrOutputDir"."persistrwattrcheck.C")
      or croak("R/W C gen file 'persistrwattrcheck.C' could not be opened.");

print $rwAttrHFile <<VERBATIM;
/**
 *  \@file persistrwattrcheck.H
 *
 *  \@brief Verify enum attribute values are correct.
 */

#ifndef PERSISTRWATTRCHECK_H
#define PERSISTRWATTRCHECK_H

VERBATIM

print $rwAttrCFile <<VERBATIM;
/**
 *  \@file persistrwattrcheck.C
 *
 *  \@brief Verify enum attribute values are correct.
 */

#include <targeting/common/target.H>

namespace TARGETING
{

#ifndef __HOSTBOOT_RUNTIME

VERBATIM

foreach my $attr (@rwPersistAttrs)
{
    if (exists $attr->{simpleType} &&
        exists $attr->{simpleType}->{enumeration})
    {
        my $typeId = $attr->{simpleType}->{enumeration}->{id};
        if (!exists $attrEnumTypes{$typeId})
        {
            die "Attribute $attr->{id} is nonexistent enumerated type $typeId";
        }
        my $atype = $attrEnumTypes{$typeId};

        # forward declare in header file
        print $rwAttrHFile "template<>\n"
        . "bool Target::tryGetAttr<ATTR_$attr->{id}>("
        . "typename AttributeTraits<ATTR_$attr->{id}>::Type& o_attrValue)"
        . " const;\n\n";

        # implement in C file
        print $rwAttrCFile "template<>\n"
        . "bool Target::tryGetAttr<ATTR_$attr->{id}>("
        . "typename AttributeTraits<ATTR_$attr->{id}>::Type& o_attrValue)"
        . " const\n"
        . "{\n"
        . "    bool l_read = _tryGetAttrUnsafe(ATTR_$attr->{id},"
        .          "sizeof(o_attrValue),&o_attrValue);\n"
        . "    if (l_read)\n"
        . "    {\n";
        my $arrayPrefix = "";
        my $arraySuffix = "";
        my $isArrayType = exists $attr->{simpleType}->{array};
        if ($isArrayType)
        {
            my $arrayTag = "$attr->{simpleType}->{array}";
            my $arraySize = getArrayTagTotalSize($arrayTag);
            my $numDimensions = getArrayNumDimensions($arrayTag);
            $arraySuffix = "[i]";

            for (my $i=0; $i < $numDimensions - 1; $i++)
            {
                $arrayPrefix =  "$arrayPrefix*";
            }

            print $rwAttrCFile ""
            . "        for(int i=0; i<$arraySize; i++)\n"
            . "        {\n"
            . "            switch( (${arrayPrefix}o_attrValue)[i] )\n"
            . "            {\n";
        }
        else
        {
            print $rwAttrCFile ""
            . "        switch( o_attrValue )\n"
            . "        {\n";
        }
        foreach my $enumerations (@{$atype->{enumerator}})
        {
            print $rwAttrCFile ""
            . "            case $atype->{id}_$enumerations->{name}:\n";
        }
        print $rwAttrCFile "            case $atype->{id}_INVALID:\n";
        print $rwAttrCFile "                break;\n"
        . "            default:\n"
        . "                handleEnumCheckFailure(this, ATTR_$attr->{id}, "
        .                      "(${arrayPrefix}o_attrValue)$arraySuffix);\n";
        if ($isArrayType)
        {
            printf $rwAttrCFile ""
            . "            }\n";
        }
        printf $rwAttrCFile ""
        . "        }\n"
        . "    }\n"
        . "    return l_read;\n"
        . "}\n\n";
    }
}
print $rwAttrCFile "#endif // !__HOSTBOOT_RUNTIME\n";

print $rwAttrCFile <<VERBATIM;

bool Target::_tryGetAttr(ATTRIBUTE_ID i_attr, uint32_t i_size,
                                                       void* io_attrData) const
{
    #ifndef __HOSTBOOT_RUNTIME
    switch(i_attr)
    {
VERBATIM
foreach my $attr (@rwPersistAttrs)
{
    if (exists $attr->{simpleType} &&
        exists $attr->{simpleType}->{enumeration})
    {
        print $rwAttrCFile <<VERBATIM;
        case (ATTR_$attr->{id}):
            return tryGetAttr<ATTR_$attr->{id}>(
                * reinterpret_cast<
                    typename AttributeTraits<ATTR_$attr->{id}>::Type*
                >(io_attrData)
            );
VERBATIM
    }
}
# throw in any range checked attributes
foreach my $attr (@rwPersistAttrs)
{
    if (exists $attr->{range})
    {
        print $rwAttrCFile <<VERBATIM;
        case (ATTR_$attr->{id}):
            return tryGetAttr<ATTR_$attr->{id}>(
                * reinterpret_cast<
                    typename AttributeTraits<ATTR_$attr->{id}>::Type*
                >(io_attrData)
            );
VERBATIM
    }
}
print $rwAttrCFile <<VERBATIM;
        default:
            return _tryGetAttrUnsafe(i_attr, i_size, io_attrData);
    }
    #else
        return _tryGetAttrUnsafe(i_attr, i_size, io_attrData);
    #endif
}

#if !defined(__HOSTBOOT_RUNTIME) && defined(__HOSTBOOT_MODULE)
VERBATIM
foreach my $attr (@rwPersistAttrs)
{
    if (exists $attr->{range})
    {
        print $rwAttrHFile "template<>\n"
        . "bool Target::tryGetAttr<ATTR_$attr->{id}>("
        . "typename AttributeTraits<ATTR_$attr->{id}>::Type& o_attrValue)"
        . " const;\n\n";
        print $rwAttrCFile "template<>\n"
        . "bool Target::tryGetAttr<ATTR_$attr->{id}>("
        . "typename AttributeTraits<ATTR_$attr->{id}>::Type& o_attrValue)"
        . " const\n"
        . "{\n"
        . "    bool l_read = _tryGetAttrUnsafe(ATTR_$attr->{id},"
        .          "sizeof(o_attrValue),&o_attrValue);\n"
        . "    if (l_read)\n"
        . "    {\n";
        my $valueString = "";
        my $extraIndent = "";
        # persence of simpleType tag confirmed previously
        my $isArrayType = exists $attr->{simpleType}->{array};
        if ($isArrayType)
        {
            my $arrayTag = "$attr->{simpleType}->{array}";
            my $arraySize = getArrayTagTotalSize($arrayTag);
            my $numDimensions = getArrayNumDimensions($arrayTag);
            my $arrayPrefix = "";
            $extraIndent = "    ";
            for (my $i=0; $i < $numDimensions - 1; $i++)
            {
                $arrayPrefix =  "$arrayPrefix*";
            }
            print $rwAttrCFile ""
            . "        for(int i=0; i<$arraySize; i++)\n"
            . "        {\n";
            $valueString = "(${arrayPrefix}o_attrValue)[i]";
        }
        else
        {
            $valueString = "o_attrValue";
        }
        if (exists $attr->{range})
        {
            my @ranges = validateRangeMinsAndMaxes($attr->{range}, $attr->{id});
            print $rwAttrCFile "$extraIndent"
            . "        do {\n$extraIndent";
            for my $range (@ranges)
            {
                if (exists $range->{min} || exists $range->{max})
                {
                    print $rwAttrCFile "            if (";
                }
                if (exists $range->{min})
                {
                    print $rwAttrCFile "$valueString >= $range->{min}";
                }
                if (exists $range->{min} && exists $range->{max})
                {
                    print $rwAttrCFile " && ";
                }
                if (exists $range->{max})
                {
                    print $rwAttrCFile "$valueString <= $range->{max}";
                }
                if (exists $range->{min} || exists $range->{max})
                {
                    print $rwAttrCFile ")\n$extraIndent"
                        . "            {\n$extraIndent"
                        . "                break;\n$extraIndent"
                        . "            }\n";
                }
            }
            print $rwAttrCFile "$extraIndent"
                . "            handleRangeCheckFailure(this,ATTR_$attr->{id},"
                . "$valueString);\n$extraIndent"
                . "       } while(0);\n";
        }
        if ($isArrayType)
        {
            print $rwAttrCFile "        }\n";
        }
        print $rwAttrCFile ""
        . "   }\n"
        . "   return l_read;\n"
        . "}\n";
    }
}
print $rwAttrCFile <<VERBATIM;
void validateAllRwNvAttr(const Target* i_pTarget)
{
VERBATIM
foreach my $attr (@rwPersistAttrs)
{
    if (exists $attr->{simpleType} &&
        exists $attr->{simpleType}->{enumeration})
    {
        my $lowerCaseValue = lc "o_$attr->{id}_value";
        print $rwAttrCFile ""
        . "    AttributeTraits<ATTR_$attr->{id}>::Type $lowerCaseValue;\n"
        . "    i_pTarget->tryGetAttr<ATTR_$attr->{id}>($lowerCaseValue);\n\n";
    }
}
foreach my $attr (@rwPersistAttrs)
{
    if (exists $attr->{range})
    {
        my $lowerCaseValue = lc "o_$attr->{id}_value";
        print $rwAttrCFile ""
        . "    AttributeTraits<ATTR_$attr->{id}>::Type $lowerCaseValue;\n"
        . "    i_pTarget->tryGetAttr<ATTR_$attr->{id}>($lowerCaseValue);\n\n";
    }
}
print $rwAttrCFile <<VERBATIM;
}
#endif // !__HOSTBOOT_RUNTIME &&__HOSTBOOT_MODULE
} // namespace TARGETING

VERBATIM
print $rwAttrHFile "#endif\n";
close $rwAttrHFile;
close $rwAttrCFile;
}

# sub getArrayTagTotalSize
# Calculates the total array size from an array tag that contains individual
# sizes of each array dimension
# @param[in] thearray - an array of sizes for each dimension
# @return total size
sub getArrayTagTotalSize {
    my ($thearray) = @_;
    my $arraySize = 1;
    my @bounds = split(/,/,$thearray);

    foreach my $bound (@bounds)
    {
        $arraySize *= $bound;
    }
    return $arraySize;
}

# sub getArrayNumDimensions
# Calculates the number of array dimensions from an array tag that contains
# individual sizes of each array dimension
# @param[in] thearray - an array of sizes for each dimension
# @return number of dimensions
sub getArrayNumDimensions {
    my ($thearray) = @_;
    my @bounds = split(/,/,$thearray);
    my $dims = scalar @bounds;

    return $dims;
}

# sub validateRangeMinsAndMaxes
# Looks at the supplied range tag to determine if it was authored correctly.
# @param[in] range - The range tag and all of its sub elements
# @param[in] attr_id - The attribute id string used for better error messages.
sub validateRangeMinsAndMaxes {
    my ($range, $attr_id) = @_;

    # first check: make sure there is only one unbounded max and only one
    # unbounded min
    my $unboundedMins = 0;
    my $unboundedMaxes = 0;
    foreach my $i (@{$range})
    {
        if (!exists $i->{min} && exists $i->{max})
        {
            $unboundedMaxes++;
        }
        if (!exists $i->{max} && exists $i->{min})
        {
            $unboundedMins++;
        }
        if (!exists $i->{max} && !exists $i->{min})
        {
            die "empty range tag!";
        }
    }
    if ($unboundedMins > 1)
    {
        die "$attr_id has > 1 unbounded min in range tag: $unboundedMins";
    }
    if ($unboundedMaxes > 1)
    {
        die "$attr_id has > 1 unbounded max in range tag: $unboundedMaxes";
    }

    # sort by mins
    # if an item has no min tag assume lowest number possible
    # if an item has no max tag assume highest number possible
    # this puts the unbounded max at beginning and unbounded min at the end
    my @rangeArray = sort { (!exists $a->{min}? "-inf":
                             !exists $a->{max}? "inf": $a->{min} ) <=>
                            (!exists $b->{min}? "-inf":
                             !exists $b->{max}? "inf": $b->{min} )
                          } @$range;

    my $i=0;
    # if the first range is an unbounded max then it stands alone
    my $prevMax = "-inf"; # default prevMax is negative infinity
    if (!exists $rangeArray[$i]->{min})
    {
        if (!exists $rangeArray[$i]->{max})
        {
            die "$attr_id has range tag with no min or max!";
        }
        $prevMax = $rangeArray[$i]->{max};
        $i++;
    }

    # go through the list and check for undesired overlap of ranges
    while (exists $rangeArray[$i]->{min} && exists $rangeArray[$i]->{max})
    {
        if ($rangeArray[$i]->{max} < $rangeArray[$i]->{min})
        {
            print Dumper($rangeArray[$i]);
            die "Min/max pair in <range> tag inverted!";
        }
        if ($prevMax > $rangeArray[$i]->{min})
        {
            print "Previous max: $prevMax\n";
            print Dumper($rangeArray[$i]);
            die "Range overlap! Previous <max> tag $prevMax "
            . "exceeds <min> tag value! $rangeArray[$i]->{min}";
        }
        $prevMax = $rangeArray[$i]->{max};
        $i++;
    }

    # check for stray min tag at the end
    if (exists $rangeArray[$i]->{min})
    {
        # make sure trailing min is greater than previous max
        if ($prevMax > $rangeArray[$i]->{min})
        {
            print "Previous max: $prevMax\n";
            print Dumper($rangeArray[$i]);
            die "Range overlap! Previous <max> tag $prevMax "
            . "exceeds <min> tag value! $rangeArray[$i]->{min}";
        }
    }

    return @rangeArray;
}

sub VALIDATION_FUNCTIONS { }

################################################################################
# Validates sub-elements of an element against criteria
################################################################################

sub validateSubElements {
    my($name,$mustBeHash,$element,$criteria) = @_;

    if($mustBeHash && (ref($element) ne "HASH"))
    {
        print "name=$name, mustBeHash=$mustBeHash, element=$element, criteria=$criteria \n";
        croak("$name must be in the form of a hash.");
    }

    # print keys %{$element} . "\n";

    for my $subElementName (sort(keys %{$element}))
    {
        if(!exists $criteria->{$subElementName})
        {
            croak("$name element cannot have child element of type "
                  . "\"$subElementName\".");
        }
    }

    for my $subElementName (sort(keys %{$criteria}))
    {
        if(   ($criteria->{$subElementName}{required} == 1)
           && (!exists $element->{$subElementName}))
        {
            croak("$name element missing required child element "
                  . "\"$subElementName\".");
        }

        if(exists $element->{$subElementName}
           && ($criteria->{$subElementName}{isscalar} == 1)
             && (ref ($element->{$subElementName}) eq "HASH"))
        {
            croak("$name element child element \"$subElementName\" should be "
                  . "scalar, but is a hash.");
        }
    }
}


################################################################################
# Validates attribute element for correctness
################################################################################

sub validateAttributes {
    my($attributes) = @_;

    my %elements = ( );
    $elements{"id"}                     = { required => 1, isscalar => 1};
    $elements{"description"}            = { required => 1, isscalar => 1};
    $elements{"persistency"}            = { required => 1, isscalar => 1};
    $elements{"fspOnly"}                = { required => 0, isscalar => 0};
    $elements{"hbOnly"}                 = { required => 0, isscalar => 0};
    $elements{"readable"}               = { required => 0, isscalar => 0};
    $elements{"simpleType"}             = { required => 0, isscalar => 0};
    $elements{"complexType"}            = { required => 0, isscalar => 0};
    $elements{"nativeType"}             = { required => 0, isscalar => 0};
    $elements{"writeable"}              = { required => 0, isscalar => 0};
    $elements{"hasStringConversion"}    = { required => 0, isscalar => 0};
    $elements{"hwpfToHbAttrMap"}        = { required => 0, isscalar => 0};
    $elements{"display-name"}           = { required => 0, isscalar => 1};
    $elements{"virtual"}                = { required => 0, isscalar => 0};
    $elements{"tempAttribute"}          = { required => 0, isscalar => 0};
    $elements{"serverwizReadonly"}      = { required => 0, isscalar => 0};
    $elements{"serverwizShow"}          = { required => 0, isscalar => 1};
    $elements{"global"}                 = { required => 0, isscalar => 0};
    $elements{"range"}                  = { required => 0, isscalar => 0};
    $elements{"ignoreEkb"}              = { required => 0, isscalar => 0};
    $elements{"mrwRequired"}            = { required => 0, isscalar => 0};

    # do NOT export attribute & its associated enum to serverwiz
    $elements{"no_export"}              = { required => 0, isscalar => 0};
    $elements{"isVolatile"}             = { required => 0, isscalar => 0};

    foreach my $attribute (@{$attributes->{attribute}})
    {
        validateSubElements("attribute",1,$attribute,\%elements);
    }
}

################################################################################
# Validates field element for correctness
################################################################################

sub validateFieldElement {
    my($field) = @_;

    my %elements = ( );
    $elements{"type"}        = { required => 1, isscalar => 1};
    $elements{"name"}        = { required => 1, isscalar => 1};
    $elements{"description"} = { required => 1, isscalar => 1};
    $elements{"default"}     = { required => 1, isscalar => 1};
    $elements{"bits"}        = { required => 0, isscalar => 1};

    validateSubElements("field",1,$field,\%elements);
}

################################################################################
# Validates target type extension elements for correctness
################################################################################

sub validateTargetTypesExtension {
    my($attributes) = @_;

    my %elements = ( );
    $elements{"id"}          = { required => 1, isscalar => 1};
    $elements{"attribute"}   = { required => 1, isscalar => 1};

    foreach my $targetTypeExtension (@{$attributes->{targetTypeExtension}})
    {
        validateSubElements("targetTypeExtension",1,
                            $targetTypeExtension,\%elements);
    }
}

################################################################################
# Validates target type elements for correctness
################################################################################

sub validateTargetTypes {
    my($attributes) = @_;

    my %elements = ( );
    $elements{"id"}               = { required => 1, isscalar => 1};
    $elements{"parent"}           = { required => 0, isscalar => 1};
    $elements{"attribute"}        = { required => 0, isscalar => 0};
    $elements{"fspOnly"}          = { required => 0, isscalar => 0};
    $elements{"compileAttribute"} = { required => 0, isscalar => 0};
    $elements{"parent_type"}      = { required => 0, isscalar => 0};


    foreach my $targetType (@{$attributes->{targetType}})
    {
        validateSubElements("targetType",1,$targetType,\%elements);
    }
}

################################################################################
# Validates target instance elements for correctness
################################################################################

sub validateTargetInstances{
    my($attributes) = @_;

    my %elements = ( );
    $elements{"id"}               = { required => 1, isscalar => 1};
    $elements{"type"}             = { required => 1, isscalar => 1};
    $elements{"attribute"}        = { required => 0, isscalar => 0};
    $elements{"compileAttribute"} = { required => 0, isscalar => 0};

    foreach my $targetInstance (@{$attributes->{targetInstance}})
    {
        validateSubElements("targetInstance",1,$targetInstance,\%elements);
    }
}

################################################################################
# Convert Target_t PHYS_PATH into Peer target's HUID - FSP Specific
################################################################################

sub handleTgtPtrAttributesFsp
{
    my($attributes) = @_;

    # replace PEER_TARGET attribute<PHYS_PATH> value with PEER's HUID
    foreach my $targetInstance (@{${$attributes}->{targetInstance}})
    {
        foreach my $attr (@{$targetInstance->{attribute}})
        {
            if (exists $attr->{default})
            {
                if(   ($attr->{default} ne "NULL")
                   && ($attr->{id} eq "PEER_TARGET") )
                {
                    my $peerHUID = INVALID_HUID;
                    $peerHUID = getPeerHuid($targetInstance);
                    if($peerHUID == INVALID_HUID)
                    {
                        croak("HUID for Peer Target not found for "
                            . "Peer Target [$attr->{default}]\n");
                    }
                    elsif($peerHUID == PEER_HUID_NOT_PRESENT)
                    {
                        # Might require this for debug, so keeping it.
                        #print STDOUT "****PEER HUID Attribut not present for "
                        #    . "Peer Target [$attr->{default}]... Skip\n";
                        $attr->{default} = "NULL";
                    }
                    else
                    {
                        $attr->{default} =
                            sprintf("0x%X",(hex($peerHUID) << 32));
                    }
                }
            }
        }
    }
}

################################################################################
# Convert PHYS_PATH into index for Target_t attribute's value
################################################################################

sub handleTgtPtrAttributesHb{
    my($attributes, $Target_t) = @_;

    my $aId = 0;
    ${$Target_t}{'NULL'} = $aId;
    foreach my $attribute (@{${$attributes}->{attribute}})
    {
        $aId++;
        if(exists $attribute->{simpleType} &&
           exists $attribute->{simpleType}->{'Target_t'})
        {
            ${$Target_t}{"$attribute->{id}"} = $aId;
        }
    }

    my %TargetList = ();
    my $index = 1;
    # Mapping instance's PHYS_PATH to index (1-base)
    foreach my $targetInstance (@{${$attributes}->{targetInstance}})
    {
        foreach my $attr (@{$targetInstance->{attribute}})
        {
            if ($attr->{id} eq "PHYS_PATH")
            {
                $TargetList{$attr->{default}} = $index++;
                last;
            }
        }
    }
    # replace Target_t attribute's value with instance's index
    foreach my $targetInstance (@{${$attributes}->{targetInstance}})
    {
        foreach my $attr (@{$targetInstance->{attribute}})
        {
            # An instance has a Target_t attribute
            if(exists ${$Target_t}{$attr->{id}})
            {
                if (exists $TargetList{$attr->{default}})
                {
                    $attr->{default} = $TargetList{$attr->{default}};
                }
                # Only inspect the default value if it is not already NULL
                elsif ($attr->{default} ne "NULL")
                {
                    # Get the node number from the input file and PHYS_PATH for comparison
                    my $fileNodeNumber = $cfgHbXmlFile;
                    # Extract the node number from the file name
                    $fileNodeNumber =~ s/^.*node.([0-9]).*/$1/;

                    my $attributeNodeNumber = $attr->{default};
                    # Extract the node number from the PHYS_PATH
                    $attributeNodeNumber =~ s/^.*node.([0-9]).*/$1/;

                    # Make sure the data are valid numbers before doing the comparison
                    if ( looks_like_number($fileNodeNumber)         &&
                         looks_like_number($attributeNodeNumber)    &&
                        ($fileNodeNumber != $attributeNodeNumber) )
                    {
                        # If working with a file that is dealing with only NODE
                        # X data, then it will not find a PHYS_PATH that is in
                        # NODE Y, therefore no need to inform caller of a
                        # non-issue.  Just set the default value to NULL.
                        $attr->{default} = "NULL";
                    }
                    else
                    {
                        print STDOUT ("$attr->{id} attribute has an unknown value "
                            . "$attr->{default}\n"
                            . "It must be NULL or a valid PHYS_PATH\n");
                        $attr->{default} = "NULL";
                    } # if ($fileNodeNumber != $attributeNodeNumber)
                } # if (exists $TargetList{$attr->{default}})
            } # if(exists ${$Target_t}{$attr->{id}})
        } # foreach my $attr (@{$targetInstance->{attribute}})
    } # foreach my $targetInstance (@{${$attributes}->{targetInstance}})
}

sub getPeerHuid
{
    my($targetInstance) = @_;

    my $peerHUID = PEER_HUID_NOT_PRESENT;
    if(exists $targetInstance->{compileAttribute})
    {
        foreach my $compileAttribute (@{$targetInstance->{compileAttribute}})
        {
            if($compileAttribute->{id} eq "PEER_HUID")
            {
                $peerHUID = $compileAttribute->{default};
                last;
            }
        }
    }

    return $peerHUID;
}

sub SOURCE_FILE_GENERATION_FUNCTIONS { }


# FAPI2 ATTRIBUTE SUPPORT
################################################################################
# Writes the FAPI2 plat attribute macros header file header
################################################################################
sub writeFapi2PlatAttrMacrosHeaderFileHeader {
    my($outFile) = @_;

    print $outFile <<VERBATIM;

#ifndef FAPI2_FAPIPLATATTRMACROS_H
#define FAPI2_FAPIPLATATTRMACROS_H

/**
 *  \@file fapi2platattrmacros.H
 *
 *  \@brief FAPI2 -> HB attribute mappings.  This file is autogenerated and
 *      should not be altered.
 */

//******************************************************************************
// Includes
//******************************************************************************

// STD
#include <stdint.h>

//******************************************************************************
// Macros
//******************************************************************************


namespace fapiToTargeting
{
namespace fapi2
{

enum {

VERBATIM
}

################################################################################
# Writes the FAPI2 plat attribute macros
################################################################################

sub writeFapi2PlatAttrMacrosHeaderFileContent {
    my($attributes,$fapiAttributes,$outFile) = @_;

    my $macroSection = "";
    my $attrSection = "";
    my $typeSection = "";

    foreach my $attribute (@{$attributes->{attribute}})
    {
        foreach my $hwpfToHbAttrMap (@{$attribute->{hwpfToHbAttrMap}})
        {
            if(   !exists $hwpfToHbAttrMap->{id}
               || !exists $hwpfToHbAttrMap->{macro})
            {
                croak("id,macro fields required\n");
            }

            my $fapiReadable  = 0;
            my $fapiWriteable = 0;
            my $instantiated = 0;

            if ($cfgFapiAttributesXmlFile eq "")
            {
                if ($attribute->{id} ~~ @fspAccesCheck)
                {
                    next;
                }
                #No FAPI attributes xml file specified
                if(exists $attribute->{readable})
                {
                    $macroSection .= '    #define ' .  $hwpfToHbAttrMap->{id} .
                        "_GETMACRO(ID,PTARGET,VAL) \\\n" .
                        "        FAPI2_PLAT_ATTR_SVC_GETMACRO_" .
                        $hwpfToHbAttrMap->{macro} . "(ID,PTARGET,VAL)\n";
                    $instantiated = 1;
                }

                if(exists $attribute->{writeable})
                {
                    $macroSection .= '    #ifndef ' .  $hwpfToHbAttrMap->{id} .
                        "_SETMACRO\n";
                    $macroSection .= '    #define ' .  $hwpfToHbAttrMap->{id} .
                        "_SETMACRO(ID,PTARGET,VAL) \\\n" .
                        "        FAPI2_PLAT_ATTR_SVC_SETMACRO_" .
                        $hwpfToHbAttrMap->{macro} . "(ID,PTARGET,VAL)\n";
                    $macroSection .= "    #endif\n";
                    $instantiated = 1;
                }
            }
            else
            {
                #FAPI attribute xml file specified - validate against FAPI attrs
                foreach my $fapiAttr (@{$fapiAttributes->{attribute}})
                {
                    if(   (exists $fapiAttr->{id})
                       && ($fapiAttr->{id} eq $hwpfToHbAttrMap->{id}) )
                    {
                        # Check that non-platInit attributes are in the
                        # volatile-zeroed section and have a direct mapping
                        if (! exists $fapiAttr->{platInit})
                        {
                            my $persistency = $attribute->{persistency};
                            if ($hwpfToHbAttrMap->{macro} ne "DIRECT")
                            {
                                croak("FAPI non-platInit attr " .
                                      "'$hwpfToHbAttrMap->{id}' is " .
                                      "'$hwpfToHbAttrMap->{macro}', " .
                                      "it must be DIRECT");
                            }

                            if ( (exists $fapiAttr->{persistent}))
                            {
                                if ($attribute->{persistency} ne "non-volatile")
                                {
                                    croak("FAPI non-platInit attr " .
                                          "'$hwpfToHbAttrMap->{id}' is " .
                                          "'$attribute->{persistency}', " .
                                          "it must be non-volatile");
                                }
                            }
                            else
                            {
                                # Check that platInit attributes
                                # do not have a volatile persistency
                                if( ($persistency ne "volatile-zeroed")
                                    && ($persistency ne "volatile") )
                                {
                                     croak("FAPI non-platInit attr " .
                                      "'$hwpfToHbAttrMap->{id}' is " .
                                      "'$attribute->{persistency}', " .
                                      "it must be volatile-zeroed");
                                }
                            }

                        }

                        # All FAPI attributes are readable
                        $fapiReadable = 1;

                        if(exists $fapiAttr->{writeable})
                        {
                            $fapiWriteable = 1;
                        }

                        if(exists $attribute->{simpleType}->{enumeration})
                        {
                            die "Do not use enumerations for FAPI types! ".
                              $attribute->{id}."\n";
                        }
                        else
                        {
                            $typeSection .= "    static_assert(sizeof(TARGETING::ATTR_". $attribute->{id}."_type) ==
                                            sizeof(fapi2::". $fapiAttr->{id}."_Type), \"Size of attribute ATTR_". $attribute->{id}."_type is not equal to the size of ".
                                            $fapiAttr->{id}."_Type , types dont match \" );\n";
                        }
                        last;
                    }
                }

                if($fapiReadable)
                {
                    if(exists $attribute->{readable})
                    {
                        $macroSection .= '    #define ' .  $hwpfToHbAttrMap->{id} .
                            "_GETMACRO(ID,PTARGET,VAL) \\\n" .
                            "        FAPI2_PLAT_ATTR_SVC_GETMACRO_" .
                            $hwpfToHbAttrMap->{macro} . "(ID,PTARGET,VAL)\n";
                        $instantiated = 1;
                    }
                    else
                    {
                        croak("FAPI attribute $hwpfToHbAttrMap->{id} requires " .
                            "platform supply readable attribute.");
                    }
                }

                if($fapiWriteable)
                {
                    if(exists $attribute->{writeable})
                    {
                        $macroSection .= '    #define ' .  $hwpfToHbAttrMap->{id} .
                            "_SETMACRO(ID,PTARGET,VAL) \\\n" .
                            "        FAPI2_PLAT_ATTR_SVC_SETMACRO_" .
                            $hwpfToHbAttrMap->{macro} . "(ID,PTARGET,VAL)\n";
                        $instantiated = 1;
                    }
                    else
                    {
                        croak("FAPI attribute $hwpfToHbAttrMap->{id} requires "
                            . "platform supply writeable attribute.");
                    }
                }

            }

            if($instantiated)
            {
                $attrSection .=
                    $hwpfToHbAttrMap->{id} .           " = " .
                    "        TARGETING::ATTR_" .
                    $attribute->{id} . ",\n";
            }
        }
    }

    print $outFile $attrSection;
    print $outFile "};\n\n";
    print $outFile "} // End namespace platAttrSvc\n\n";
    print $outFile "} // End namespace fapi2\n\n";

    print $outFile $typeSection;
    print $outFile "\n\n";
    print $outFile $macroSection;
    print $outFile "\n";
}

################################################################################
# Writes the plat attribute macros header file footer
################################################################################

sub writeFapi2PlatAttrMacrosHeaderFileFooter {
    my($outFile) = @_;

print $outFile <<VERBATIM;

#endif // FAPI_FAPIPLATATTRMACROS_H

VERBATIM

}

################################################################################
# Writes the pnor targeting header format file
################################################################################

sub writeHeaderFormatHeaderFile {
    my($outFile) = @_;

    print $outFile <<VERBATIM;

#ifndef TARG_PNORHEADER_H
#define TARG_PNORHEADER_H

/**
 *  \@file pnorheader.H
 *
 *  \@brief Definition for structure of targeting's PNOR image header.  This
 *      file is autogenerated and should not be altered.
 */

//******************************************************************************
// Includes
//******************************************************************************

// STD
#include <builtins.h>
#include <stdint.h>
#include <targeting/adapters/types.H>
#include <targeting/common/pointer.H>

// Targeting component

//******************************************************************************
// Complex Types
//******************************************************************************

namespace TARGETING
{
    const uint32_t PNOR_TARG_EYE_CATCHER = 0x54415247;

    enum SECTION_TYPE : uint8_t
    {
        // Targeting read-only section backed to PNOR.  Always the 0th section.
        SECTION_TYPE_PNOR_RO        = @{[SECTION_TYPE_PNOR_RO]},

        // Targeting read-write section backed to PNOR
        SECTION_TYPE_PNOR_RW        = @{[SECTION_TYPE_PNOR_RW]},

        // Targeting heap section initialized out of PNOR
        SECTION_TYPE_HEAP_PNOR_INIT = @{[SECTION_TYPE_HEAP_PNOR_INIT]},

        // Targeting heap section intialized to zero
        SECTION_TYPE_HEAP_ZERO_INIT = @{[SECTION_TYPE_HEAP_ZERO_INIT]},

        // FSP section

        // Initialized to zero on Fsp Reset / Obliterate on Fsp Reset or R/R
        SECTION_TYPE_FSP_P0_ZERO_INIT = @{[SECTION_TYPE_FSP_P0_ZERO_INIT]},

        // Initialized from Flash / Obliterate on Fsp Reset or R/R
        SECTION_TYPE_FSP_P0_FLASH_INIT = @{[SECTION_TYPE_FSP_P0_FLASH_INIT]},

        // This section remains across fsp power cycle, fixed, never updates
        SECTION_TYPE_FSP_P3_RO = @{[SECTION_TYPE_FSP_P3_RO]},

        // This section persist changes across Fsp Power cycle
        SECTION_TYPE_FSP_P3_RW = @{[SECTION_TYPE_FSP_P3_RW]},

        // Initialized to zero on hard reset, else existing P1 memory
        // copied on R/R
        SECTION_TYPE_FSP_P1_ZERO_INIT = @{[SECTION_TYPE_FSP_P1_ZERO_INIT]},

        // Intialized to default from P3 on hard reset, else existing P1
        // memory copied on R/R
        SECTION_TYPE_FSP_P1_FLASH_INIT = @{[SECTION_TYPE_FSP_P1_FLASH_INIT]},

        // HOSTBOOT section

        // Targeting heap section intialized to zero
        SECTION_TYPE_HB_HEAP_ZERO_INIT = @{[SECTION_TYPE_HB_HEAP_ZERO_INIT]},

        // Attribute metadata section
        SECTION_TYPE_HB_METADATA = @{[SECTION_TYPE_HB_METADATA]},

    };

    struct TargetingSection
    {
        // Type of targeting section
        const SECTION_TYPE sectionType : 8;

        // Offset of the section within the PNOR targeting image from byte zero
        // of the targeting header
        const uint32_t     sectionOffset;

        // Size of the section within the PNOR targeting image
        const uint32_t     sectionSize;

    } PACKED;

    struct TargetingHeader
    {
        // Eyecatcher to quickly verify correct population of targeting PNOR
        // data
        const uint32_t         eyeCatcher;

        // Major version of the PNOR targeting image
        const uint16_t         majorVersion;

        // Minor version of the PNOR targeting image
        const uint16_t         minorVersion;

        // Total size of the targeting header (from beginning of header).  The
        // PNOR RO targeting data is located immediately following the header
        const uint32_t         headerSize;

        // Virtual memory offset from the virtual memory address of the previous
        // section where the attribute resource provider must load the next
        // section.  If there is no previous section, it will represent the
        // offset from the virtual memory base address (typically 0)
        const uint32_t         vmmSectionOffset;

        // Virtual memory base address where the attribute resource provider
        // must load the 0th (PNOR RO) section
        AbstractPointer<void>    vmmBaseAddress;

        // Size of each TargetingSection record
        const uint32_t         sizeOfSection;

        // Number of TargetingSection records
        const uint32_t         numSections;

        // Offset to the first TargetingSection record, from the end of this
        // field
        const uint32_t         offsetToSections;

        // Pad, in bytes, given by "offsetToSections"

        // const TargetingSection sections[numSections];

    } PACKED;

} // End namespace TARGETING

#endif // TARG_PNORHEADER_H

VERBATIM

}

################################################################################
# Writes the string implementation file header
################################################################################

sub writeStringImplementationFileHeader {
    my($outFile) = @_;

    print $outFile <<VERBATIM;

/**
 *  \@file attributestrings.C
 *
 *  \@brief Attribute string implementation.  This file is autogenerated and
 *      should not be altered.
 */

//******************************************************************************
// Includes
//******************************************************************************

// STD
#include <stdint.h>
#include <stdlib.h>

// Targeting component
#include <targeting/common/attributes.H>

namespace TARGETING {

VERBATIM

}

################################################################################
# Writes test for toString entity path function
################################################################################

sub writeTestEntityPath {
    my($attributes) = @_;

    open EP_TEST_FILE, ">", "$cfgSrcOutputDir"."test_ep.H" or die $!;

    print EP_TEST_FILE "#include <attributeenums.H>\n";
    print EP_TEST_FILE "using namespace TARGETING;\n";
    print EP_TEST_FILE "EntityPath l_path;\n";
    print EP_TEST_FILE "const char * name = NULL;\n";
    print(EP_TEST_FILE "const char * test_string = \"Unknown path" .
                       " type\";\n");
    print EP_TEST_FILE "size_t size = strlen( test_string );\n";

    foreach my $attribute (@{$attributes->{attribute}})
    {
        if(exists $attribute->{simpleType})
        {
            my $simpleType = $attribute->{simpleType};
            if(exists $simpleType->{enumeration})
            {
                my $enumeration = $simpleType->{enumeration};

                my $enumerationType = getEnumerationType($attributes,
                    $enumeration->{id});

                foreach my $enumerator (@{$enumerationType->{enumerator}})
                {
                    if( $attribute->{id} eq "TYPE" )
                    {
                        print(EP_TEST_FILE "name = " .
                            "l_path.pathElementTypeAsString( " .
                            "TYPE_$enumerator->{name} );\n");
                        print EP_TEST_FILE "size = strlen( name );\n";

                        if( $enumerator->{name} eq "LAST_IN_RANGE" )
                        {
                            print(EP_TEST_FILE "if( memcmp( name, " .
                                "test_string, size ))\n{\n");

                            print(EP_TEST_FILE "TS_FAIL(\"type " .
                                "attribute TYPE_$enumerator->{name}" .
                                " - did not return expected error " .
                                "message. - update entitypath.C\");\n}\n");

                        }
                        elsif( $enumerator->{name} eq "TEST_FAIL" )
                        {
                            #TEST_FAIL is not defined in the function
                            #pathElementTypeAsString - validate error string
                            print(EP_TEST_FILE "if( memcmp( name, " .
                                "test_string, size ))\n{\n");

                            print(EP_TEST_FILE "TS_FAIL(\"type " .
                                "attribute TYPE_$enumerator->{name}" .
                                " - did not return expected error " .
                                "message. - update entitypath.C\");\n}\n");
                        }
                        else
                        {
                            print(EP_TEST_FILE "if( !memcmp( name, " .
                                "test_string, size ))\n{\n");

                            print(EP_TEST_FILE "TS_FAIL(\"undefined TYPE " .
                                "attribute TYPE_$enumerator->{name}" .
                                " - update entitypath.C\");\n}\n");
                        }
                    }
                }
            }
        }
    }
close EP_TEST_FILE;
}


################################################################################
# Writes string implementation
################################################################################

sub writeStringImplementationFileStrings {
    my($attributes,$outFile) = @_;

    foreach my $attribute (@{$attributes->{attribute}})
    {
        my $does_not_have_invalid = 1;
        if(exists $attribute->{simpleType})
        {
            my $simpleType = $attribute->{simpleType};
            if(exists $simpleType->{enumeration})
            {
                my $enumeration = $simpleType->{enumeration};

                print $outFile "//*********************************************"
                    . "*********************************\n";
                print $outFile "// attrToString<ATTR_", $attribute->{id}, ">\n";
                print $outFile "//*********************************************"
                    . "*********************************\n\n";
                print $outFile "template<>\n";
                print $outFile "const char* attrToString<ATTR_",
                    $attribute->{id},"> (\n";
                print $outFile "    AttributeTraits<ATTR_",$attribute->{id},
                    ">::Type const& i_attrValue)\n";
                print $outFile "{\n";
                print $outFile "    switch(i_attrValue)\n";
                print $outFile "    {\n";
                my $enumerationType = getEnumerationType($attributes,
                    $enumeration->{id});

                foreach my $enumerator (@{$enumerationType->{enumerator}})
                {
                    print $outFile "        case ", $attribute->{simpleType}->{enumeration}->{id}, "_",
                        $enumerator->{name},":\n";
                    print $outFile "            return \"",
                        $enumerator->{name},"\";\n";
                    $does_not_have_invalid &&= not($enumerator->{name} =~m/INVALID/);
                }
                # add case for INVALIDs
                if($does_not_have_invalid and not($enumerationType->{id}=~m/^TYPE$/))
                {
                    print $outFile "        case ", $attribute->{simpleType}->{enumeration}->{id}, "_INVALID:\n";
                    print $outFile "            return \"INVALID\";\n";
                }

                print $outFile "        default:\n";
                print $outFile "            return \"Cannot decode ",
                    $attribute->{id}, "\";\n";
                print $outFile "    }\n";
                print $outFile "}\n\n";
           }
        }
    }
}

################################################################################
# Locate generic attribute definition, given an enumeration ID
################################################################################

sub getEnumerationType {

    my($attributes,$id) = @_;
    my $matchingEnumeration;

    foreach my $enumerationType (@{$attributes->{enumerationType}})
    {
        if($id eq $enumerationType->{id})
        {
            $matchingEnumeration = $enumerationType;
            last;
        }
    }

    if(!exists $matchingEnumeration->{id})
    {
        croak("Could not find enumeration with ID of " . $id . "\n");
    }

    return $matchingEnumeration;
}

################################################################################
# Writes the string implementation file footer
################################################################################

sub writeStringImplementationFileFooter {
    my($outFile) = @_;

print $outFile <<VERBATIM;
} // End namespace TARGETING

VERBATIM
}

################################################################################
# Writes the struct file -er
################################################################################

sub writeStructFileHeader {
    my($outFile) = @_;

print $outFile <<VERBATIM;

#ifndef TARG_ATTRIBUTESTRUCTS_H
#define TARG_ATTRIBUTESTRUCTS_H

/**
 *  \@file attributestructs.H
 *
 *  \@brief Complex structures for host boot attributes.  This file is
 *      autogenerated and should not be altered.
 */

//******************************************************************************
// Includes
//******************************************************************************

// STD
#include <stdint.h>
#include <stdlib.h>

// Targeting component
#include <builtins.h>
@{[ $buildBmc ? "" : "#include <targeting/common/attributes.H>\n" ]}
#include <targeting/common/entitypath.H>

//******************************************************************************
// Complex Types
//******************************************************************************

namespace TARGETING
{

VERBATIM

}

################################################################################
# Writes struct header file structs
################################################################################

sub writeStructFileStructs {
    my($attributes,$outFile) = @_;

    foreach my $attribute (@{$attributes->{attribute}})
    {
        if(exists $attribute->{complexType})
        {
            my $complexType = $attribute->{complexType};
            if(!exists $complexType->{description})
            {
                croak("ERROR: Complex type requires a 'description'.");
            }

            print $outFile "/**\n";
            print $outFile wrapBrief($complexType->{description});
            print $outFile " */\n";

            print $outFile "struct ",
                calculateStructName($attribute->{id}), "\n";
            print $outFile "{\n";

            my $complex = $attribute->{complexType};
            foreach my $field (@{$complex->{field}})
            {
                validateFieldElement($field);

                my $bits = "";
                if($field->{bits})
                {
                    $bits = " : " . $field->{bits};
                }

                print $outFile wrapComment($field->{description});
                print $outFile "    ", $field->{type}, " ", $field->{name},
                    $bits, "; \n\n";
            }

            print $outFile "} PACKED;\n\n";
        }
    }
}

################################################################################
# Writes the struct file footer
################################################################################

sub writeStructFileFooter {
    my($outFile) = @_;

print $outFile <<VERBATIM;
} // End namespace TARGETING

#endif // TARG_ATTRIBUTESTRUCTS_H

VERBATIM

}

################################################################################
# Writes the string header file header
################################################################################

sub writeStringHeaderFileHeader {
    my($outFile) = @_;

print $outFile <<VERBATIM;

#ifndef TARG_ATTRIBUTESTRINGS_H
#define TARG_ATTRIBUTESTRINGS_H

/**
 *  \@file attributestrings.H
 *
 *  \@brief Attribute string conversion routines.  This file is autogenerated
 *      and should not be altered.
 */

//******************************************************************************
// Includes
//******************************************************************************

// STD
#include <stdint.h>
#include <stdlib.h>

namespace TARGETING
{

/**
 *  \@brief Class used to clarify compiler error when caller attempts to
 *      stringify an unsupported attribute
 */
class InvalidAttributeForStringification;

/**
 *  \@brief Return attribute as a string
 *
 *  \@param[in] i_attrValue Value of the attribute
 *
 *  \@return String which decodes the attribute value
 */
template<const ATTRIBUTE_ID A>
const char* attrToString(
    typename AttributeTraits<A>::Type const& i_attrValue)
{
    // Default behavior is to fail the compile if caller attempts to print an
    // unsupported string
    #ifdef __HOSTBOOT_MODULE
        static_assert(A != A, \"Must use an explicitly supported template \"
                              \"specialization\");
    #else
        char mustUseTemplateSpecialization[A != A ? 1 : -1];
    #endif

    const char* retVal = NULL;
    return retVal;
}

VERBATIM

}

################################################################################
# Writes string interfaces
################################################################################

sub writeStringHeaderFileStrings {
    my($attributes,$outFile) = @_;

    foreach my $attribute (@{$attributes->{attribute}})
    {
        if(exists $attribute->{simpleType})
        {
            my $simpleType = $attribute->{simpleType};
            if(exists $simpleType->{enumeration})
            {
                my $enumeration = $simpleType->{enumeration};
                print $outFile "/**\n";
                print $outFile " *  \@brief See "
                    . "attrToString<const ATTRIBUTE_ID A>\n";
                print $outFile " */\n";
                print $outFile "template<>\n";
                print $outFile "const char* attrToString<ATTR_",
                    $attribute->{id},">(\n";
                print $outFile "    AttributeTraits<ATTR_",$attribute->{id},
                    ">::Type const& i_attrValue);\n";
                print $outFile "\n";
            }
        }
    }
}

################################################################################
# Writes the string header file footer
################################################################################

sub writeStringHeaderFileFooter {
    my($outFile) = @_;

print $outFile <<VERBATIM;

} // End namespace TARGETING

#endif // TARG_ATTRIBUTESTRINGS_H

VERBATIM
}

################################################################################
# Writes the enum file header
################################################################################

sub writeEnumFileHeader {
    my($outFile) = @_;

print $outFile <<VERBATIM;

#ifndef TARG_ATTRIBUTEENUMS_H
#define TARG_ATTRIBUTEENUMS_H

/**
 *  \@file attributeenums.H
 *
 *  \@brief Defined enums for platform attributes
 *
 *  This header file contains enumerations for supported platform attributes
 *  (as opposed to HWPF attributes).  This file is automatically
 *  generated and should not be altered.
 */

//******************************************************************************
// Includes
//******************************************************************************

#include <stdint.h>
#include <stdlib.h>

//******************************************************************************
// Enumerations
//******************************************************************************

namespace TARGETING
{

VERBATIM

}

################################################################################
# Writes the enum file attribute enumeration
################################################################################

sub writeEnumFileAttrIdEnum {
    my($attributes,$outFile) = @_;

    print $outFile <<VERBATIM;
/**
 *  \@brief Platform attribute IDs
 *
 *  Enumeration defining every possible platform attribute that can be
 *  associated with a target. This file is autogenerated and should not be
 *  altered.
 */
enum ATTRIBUTE_ID
{
VERBATIM

    my $attrId;
    my $hexVal;

    # Format below intentionally > 80 chars for clarity

    format ATTRENUMFORMAT =
    ATTR_@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< = @<<<<<<<<<<
    $attrId,                                                         $hexVal .","
.
    select($outFile);
    $~ = 'ATTRENUMFORMAT';

    my $attributeIdEnumeration = getAttributeIdEnumeration($attributes);
    foreach my $enumerator (@{$attributeIdEnumeration->{enumerator}})
    {
        $hexVal = $enumerator->{value};
        $attrId = $enumerator->{name};

        # enforce the implicit length requirement since the format command
        #  does not throw an error if we overrun
        my $enumsize = length($attrId);
        if( $enumsize > 55 )
        {
            print "    $attrId = $hexVal,\n";
        }
        else
        {
            write;
        }
    }

    print $outFile "};\n\n";
}

################################################################################
# Writes other enumerations to enumeration file
################################################################################

sub writeEnumFileAttrEnums {
    my($attributes,$outFile) = @_;

    my $enumName = "";
    my $enumHex = "";
    my $enumHexValue = 0;
    # number of '<' in the 'format ENUMFORMAT' below
    my $MAX_ENUM_LENGTH = 58;
    # Format below intentionally > 80 chars for clarity

    format ENUMFORMAT =
    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< = @<<<<<<<<<<<<<<<<<<<<<
    $enumName,                                                       $enumHex .","
.
    select($outFile);
    $~ = 'ENUMFORMAT';

    foreach my $enumerationType (@{$attributes->{enumerationType}})
    {
        my $does_not_have_invalid = 1;

        print $outFile "/**\n";
        print $outFile wrapBrief( $enumerationType->{description} );
        print $outFile " */\n";
        print $outFile "enum ", $enumerationType->{id}, "\n";

        print $outFile "{\n";

        foreach my $enumerator (@{$enumerationType->{enumerator}})
        {
            $enumHexValue =
                          enumNameToValue($enumerationType,$enumerator->{name});


            #If the enum is bigger than 0xFFFFFFFF, then we need to append 'LL'
            #or 'ULL' to it to prevent compiler errors.
            if($enumHexValue > $MAX_4_BYTE_VALUE)
            {
                # find type
                my $simpleType = getAttributeType($enumerationType->{id},
                                                  $attributes);

                if (exists $simpleType->{'uint64_t'})
                {
                    $enumHex = sprintf "0x%08XULL", $enumHexValue;
                }
                else
                {
                    $enumHex = sprintf "0x%08XLL", $enumHexValue;
                }
            }
            else
            {
                $enumHex = sprintf "0x%08X", $enumHexValue;
            }
            $enumName = $enumerationType->{id} . "_" . $enumerator->{name};

            # enforce the implicit length requirement since the format command
            #  does not throw an error if we overrun
            my $enumsize = length($enumName);
            if($enumsize > $MAX_ENUM_LENGTH)
            {
               print "    $enumName = $enumHex,\n";
            }
            else
            {
               write;
            }

            # set flag if there is already an enum with an INVALID enumerator
            $does_not_have_invalid &&= not($enumerator->{name} =~m/INVALID/);
        }

        # Add default invalid enum value
        # - Place default invalid enum value at the end of list of enum values above
        # - Calculate the number of bytes needed to store the largest enumerator per enum
        #     and attempt to assign an INVALID with that size
        # - Skip enums that already have enumerators with an INVALID
        # - Skip enums that already have all F's assigned to an enumerator of the largest word size

        my $stringMaxEValue = sprintf "%X", maxEnumValue($enumerationType);

        my $attributeType = getAttributeType($enumerationType->{id}, $attributes);

        # assume 8 nibbles (4 bytes) long for enums that are not of type
        # (u)int8_t ... (u)int64_t
        my $numF = 8;
        # check the type hash list for int or uint type
        foreach my $key (keys %{$attributeType})
        {
            if($key =~ m/int/)
            {
                # extract the number of bits from the type
                # and convert to number of nibbles for the following sprintf
                ($numF) = $key =~ m/([0-9]+)/;
                $numF /= 4;
                last;
            }
        }

        my $invalidEnumHex = sprintf "%${numF}X", 0xFF;
        $invalidEnumHex  =~ tr/ /F/;
        if($invalidEnumHex ne $stringMaxEValue and $does_not_have_invalid)
        {
            if (exists $attributeType->{'uint64_t'})
            {
               $enumHex = sprintf "0x%${numF}sULL", $invalidEnumHex;
            }
            elsif (exists $attributeType->{'int64_t'})
            {
               $enumHex = sprintf "0x%${numF}sLL", $invalidEnumHex;
            }
            elsif($enumerationType->{id}=~m/^TYPE$/)
            {
               # special case for the TYPE enum because in pldm_fru.C
               # its size is restricted to 7 bits
               $enumHex = sprintf "0x%08X", 0x0000007F;
            }
            else
            {
               # fill the remaining digits with 0's if needed
               $enumHex = sprintf "0x%08s", $invalidEnumHex;
            }

            $enumName = $enumerationType->{id} . "_INVALID";
            my $enumsize = length($enumName);
            if($enumsize > $MAX_ENUM_LENGTH)
            {
               print "    $enumName = $enumHex,\n";
            }
            else
            {
               write;
            }
        }

        print $outFile "};\n\n";
    }
}

################################################################################
# Helper function to count the number of simple numeric attributes
################################################################################
sub getAttrSizesArrLength {
    my $attributeCount = 0;
    foreach my $attribute (@{$attributes->{attribute}})
    {
        if(isSimpleNumericAttribute($attribute))
        {
            $attributeCount++;
        }
    }
    return $attributeCount;
}

################################################################################
# Writes the enum file footer
################################################################################

sub writeEnumFileFooter {
    my($outFile) = @_;

print $outFile <<VERBATIM;
} // End namespace TARGETING

#endif // TARG_ATTRIBUTEENUMS_H

VERBATIM
}

sub writeAttrSizesHFile
{
    my ($outFile) = @_;

    my $numEntries = getAttrSizesArrLength();
print $outFile <<VERBATIM;

#ifndef TARG_ATTR_SIZES
#define TARG_ATTR_SIZES

#include <stdint.h>
#include <vector>
#include <array>

/**
 * \@file attrsizesdata.H
 *
 * \@brief The file contains the data structure that holds the sizes and types
 *         of different attributes. Attributes represented as arrays also have
 *         dimensions associated with the array.
 */

namespace TARGETING
{

enum ATTR_DATA_TYPE
{
    UINT8_T_TYPE,
    INT8_T_TYPE,
    UINT16_T_TYPE,
    INT16_T_TYPE,
    UINT32_T_TYPE,
    INT32_T_TYPE,
    UINT64_T_TYPE,
    INT64_T_TYPE
};

enum ATTR_DATA_SIZE
{
    UINT8_T_SIZE = sizeof(uint8_t),
    INT8_T_SIZE = sizeof(int8_t),
    UINT16_T_SIZE = sizeof(uint16_t),
    INT16_T_SIZE = sizeof(int16_t),
    UINT32_T_SIZE = sizeof(uint32_t),
    INT32_T_SIZE = sizeof(int32_t),
    UINT64_T_SIZE = sizeof(uint64_t),
    INT64_T_SIZE = sizeof(int64_t)
};

typedef struct
{
    uint32_t attrHash;
    ATTR_DATA_TYPE dataType;
    ATTR_DATA_SIZE dataSize;
    bool isArray;
    std::vector<uint32_t>dimensions;

} attrSizeData_t;

constexpr bool ARRAY = true;
constexpr bool NOT_ARRAY = false;

// Array format:
// {attr hash, attr data type, attr data size, array or not, array dimensions}
extern const std::array<attrSizeData_t, $numEntries>g_attrSizesArr;

} // namespace TARGETING
#endif // #ifndef TARG_ATTR_SIZES
VERBATIM

}

sub getAttrDataTypeSize
{
    my ($attribute) = @_;
    my $dataTypeStr = "";
    my $dataSizeStr = "";

    if(exists $attribute->{simpleType}->{uint8_t})
    {
        $dataSizeStr = "UINT8_T_SIZE";
        $dataTypeStr = "UINT8_T_TYPE";
    }
    elsif(exists $attribute->{simpleType}->{int8_t})
    {
        $dataSizeStr = "INT8_T_SIZE";
        $dataTypeStr = "INT8_T_TYPE";
    }
    elsif(exists $attribute->{simpleType}->{uint16_t})
    {
        $dataSizeStr = "UINT16_T_SIZE";
        $dataTypeStr = "UINT16_T_TYPE";
    }
    elsif(exists $attribute->{simpleType}->{int16_t})
    {
        $dataSizeStr = "INT16_T_SIZE";
        $dataTypeStr = "INT16_T_TYPE";
    }
    elsif(exists $attribute->{simpleType}->{uint32_t})
    {
        $dataSizeStr = "UINT32_T_SIZE";
        $dataTypeStr = "UINT32_T_TYPE";
    }
    elsif(exists $attribute->{simpleType}->{int32_t})
    {
        $dataSizeStr = "INT32_T_SIZE";
        $dataTypeStr = "INT32_T_TYPE";
    }
    elsif(exists $attribute->{simpleType}->{uint64_t})
    {
        $dataSizeStr = "UINT64_T_SIZE";
        $dataTypeStr = "UINT64_T_TYPE";
    }
    elsif(exists $attribute->{simpleType}->{int64_t})
    {
        $dataSizeStr = "INT64_T_SIZE";
        $dataTypeStr = "INT64_T_TYPE";
    }
    return ($dataTypeStr, $dataSizeStr);
}

sub isSimpleNumericAttribute
{
    my ($attribute) = @_;

    return ( (exists $attribute->{simpleType}) and
             ( exists $attribute->{simpleType}->{uint8_t} or
               exists $attribute->{simpleType}->{int8_t} or
               exists $attribute->{simpleType}->{uint16_t} or
               exists $attribute->{simpleType}->{int16_t} or
               exists $attribute->{simpleType}->{uint32_t} or
               exists $attribute->{simpleType}->{int32_t} or
               exists $attribute->{simpleType}->{uint64_t} or
               exists $attribute->{simpleType}->{int64_t}));
}

sub writeAttrSizesCFile
{
    my ($attributes, $outFile, $hFileName) = @_;

    my $numEntries = getAttrSizesArrLength();

    print $outFile <<VERBATIM;
#include <$hFileName>

namespace TARGETING
{

const std::array<attrSizeData_t, $numEntries>g_attrSizesArr =
{{
VERBATIM

    # Sort the attributes by hash value for ease of search later
    foreach my $attribute ( sort { getAttributeIdHashStr($a->{id}) cmp getAttributeIdHashStr($b->{id}) } @{$attributes->{attribute}})
    {
        # Only process simple-type attribute types
        if(isSimpleNumericAttribute($attribute))
        {
            my $dimensionsString = "";
            my $attrHash = getAttributeIdHashStr($attribute->{id});
            my $isArray = exists $attribute->{simpleType}->{array};
            # If it's an array, populate the array dimensions
            if($isArray)
            {
                my @arrayDimensions = split(/,/,$attribute->{simpleType}->{array});
                foreach my $dimension (@arrayDimensions)
                {
                    $dimensionsString = $dimensionsString . "$dimension, ";
                }
                # Remove the last trailing space and comma after the last dimension
                chop($dimensionsString);
                chop($dimensionsString);
            }

            # Write array entry. The format is { hash, dataType, isArray, {dimensions}}
            # Note that even though ARRAY and NOT_ARRAY are strings here, they translate
            # to bools in the code (see the const definition at the start of file).
            my $isArrayStr = $isArray ? "ARRAY" : "NOT_ARRAY";
            my ($dataTypeStr, $dataSizeStr) = getAttrDataTypeSize($attribute);
            print $outFile "    {0x$attrHash, $dataTypeStr, $dataSizeStr, $isArrayStr, {$dimensionsString}},\n";
        }
    }
    print $outFile "}}; // end of array\n";
    print $outFile "} // end namespace TARGETING\n";
}

###############################################################################
# Writes code to populate Attribute Data Map
###############################################################################
sub writeTargAttrMap {
    my($attributes,$outFile) = @_;


    my $attributeIdEnum = getAttributeIdEnumeration($attributes);

    print $outFile "const AttributeData g_TargAttrs[] = {\n";

    # loop through every attribute
    foreach my $attribute
        (sort { $a->{id} cmp $b->{id} } @{$attributes->{attribute}})
    {


        # Only (initially) support attributes with simple integer types
        if (isSimpleNumericAttribute($attribute))
        {


            foreach my $enum (@{$attributeIdEnum->{enumerator}})
            {
                if($enum->{name} eq $attribute->{id})
                {
                        # struct AttributeData
                    print $outFile "\t{\n";
                        # iv_name
                    print $outFile "\t\t\"ATTR_$attribute->{id}\",\n";
                        # iv_attrId
                    print $outFile "\t\t$enum->{value},\n";
                        # iv_attrElemSizeBytes
                    my @sizes = ( "uint8_t", "uint16_t",
                                  "uint32_t", "uint64_t",
                                  "int8_t", "int16_t",
                                  "int32_t", "int64_t");

                    foreach my $size (@sizes)
                    {
                        if (exists $attribute->{simpleType}->{$size})
                        {
                            print $outFile "\t\tsizeof($size),\n";
                            last;
                        }
                    }

                        # iv_dims
                    my @dims = ();
                    if (exists $attribute->{simpleType}->{array})
                    {
                        # Remove leading whitespace
                        my $dimText = $attribute->{simpleType}->{array};
                        $dimText =~ s/^\s+//;

                        # Split on commas or whitespace
                        @dims = split(/\s*,\s*|\s+/, $dimText);
                    }
                    until ($#dims == 3)
                    {
                        push @dims, 1;
                    }
                    print $outFile "\t\t{ ".join(", ",@dims)." } \n";

                        # end AttributeData
                    print $outFile "\t},\n";

                }


            }

        }


    }

    print $outFile "};\n";
}

###############################################################################
# Writes code to populate the header of the Attribute Name Map H File
###############################################################################
sub writeAttrIdNameHFile
{
    my ($outFile) = @_;

    # file description
    print $outFile "// Attribute ID -> Attribute Name Map File\n";

    # includes
    if($buildBmc) {
     print $outFile "#include <cstdint>\n";
    }
    print $outFile "#include <map>\n\n";

    print $outFile "extern const std::map<uint32_t,const char*>g_nonRwAttrIdToNameMap;\n";
    print $outFile "extern const std::map<uint32_t,const char*>g_rwAttrIdToNameMap;\n";
}

###############################################################################
# Writes code to populate the header of the Attribute Name Map C File
###############################################################################
sub writeAttrIdNameCFileHeader
{
    my ($outFile) = @_;

    print $outFile "#include <targAttrIdToName.H>\n\n";
}

###############################################################################
# Writes code to populate Attribute ID to Attribute Name Map File
###############################################################################
sub writeAttrIdNameMap
{
    my($attributes,$outFile,$rwOnly) = @_;

    my $attributeIdEnum = getAttributeIdEnumeration($attributes);
    my $mapName = "g_nonRwAttrIdToNameMap";

    if($rwOnly)
    {
        print $outFile "// g_rwAttrIdToNameMap only includes writeable attributes\n\n";
        $mapName = "g_rwAttrIdToNameMap";
    }
    else
    {
        print $outFile "// g_nonRwAttrIdToNameMap includes non-RW attributes\n\n";
    }

    # attribute id -> attribute info map
    print $outFile
        "const std::map<uint32_t,const char*>$mapName = {\n";

    # loop through every attribute
    foreach my $attribute
        (sort { $a->{id} cmp $b->{id} } @{$attributes->{attribute}})
    {

        # Only want to add writeable attr for RW-only map and all others
        # (non-RW) for the non-RW map
        if ( ($rwOnly and
             !(exists $attribute->{writeable}))
            or
             (!$rwOnly and
              (exists $attribute->{writeable})))
        {
            next;
        }

        # Simple or complex types
        if ((exists $attribute->{simpleType}) ||
            (exists $attribute->{complexType}) ||
            (exists $attribute->{nativeType}) )
        {
            # This loops through all attributes to add id and name
            # not just enumerated attributes
            foreach my $enum (@{$attributeIdEnum->{enumerator}})
            {
                if($enum->{name} eq $attribute->{id})
                {
                    # start attribute map data
                    print $outFile "\t{\n";
                    # attribute id
                    print $outFile "\t\t$enum->{value},\n";
                    # attribute name
                    print $outFile "\t\t\"ATTR_$attribute->{id}\"\n";
                    # end attribute map data
                    print $outFile "\t},\n";
                }
            }
        }
    }

    # end of map
    print $outFile "};\n\n";
}

sub writeMutexFileHeader {
    my($outFile) = @_;

print $outFile <<VERBATIM;

#ifndef TARG_MUTEXATTRIBUTES_H
#define TARG_MUTEXATTRIBUTES_H

/**
 *  \@file mutexattributes.H
 *
 *  \@brief Array of attributes Ids whose type is hbmutex
 *
 *  This header file contains a single array that lists out all of the hbmutex
 *  attributes. This is used on the MPIPL path to know which attributes we need
 *  to reset.  This file is autogenerated and should not be altered.
 */

//******************************************************************************
// Includes
//******************************************************************************

// STD
#include <stdint.h>
VERBATIM
}

sub writeMutexFileAttrs {
    my($attributes,$outFile) = @_;

print $outFile <<VERBATIM;

//******************************************************************************
// Array
//******************************************************************************

namespace TARGETING
{

/**
 *  \@brief HB Mutex Attribute IDs
 *
 *  Array defining all attribute ids found that are of type hbMutex.
 *  This file is autogenerated and should not be altered.
 */
const struct {uint32_t id; bool isRecursive;} hbMutexAttrIds[] = {
VERBATIM

    my @mutexAttrIds;

    foreach my $attribute (@{$attributes->{attribute}})
    {
        #check if hbmutex tag is present
        #check that attr is readable/writeable
        if(   (exists $attribute->{simpleType})
                && (exists $attribute->{simpleType}->{hbmutex}
                ||  exists $attribute->{simpleType}->{hbrecursivemutex})
                && (exists $attribute->{readable})
                && (exists $attribute->{writeable}))
        {
            my $recursiveType = "false";
            if (exists $attribute->{simpleType}->{hbrecursivemutex})
            {
                $recursiveType = "true";
            }

            push @mutexAttrIds, ([ $attribute->{id}, $recursiveType ]);
        }
    }

    # variables that can be used for writing the enums to the file
    my $attrId;
    my $hexVal;
    my $recursiveVal;

    # Format below intentionally > 80 chars for clarity
    format ATTRMUTEXFORMAT =
                                  @>>>>>>>>>>>>>>>>>>>>
    "{ ". $hexVal .", ". $recursiveVal ." },"
.
    select($outFile);
    $~ = 'ATTRMUTEXFORMAT';

    my $attrIdEnum = getAttributeIdEnumeration($attributes);

    foreach my $enumerator (@{$attrIdEnum->{enumerator}})
    {
        $hexVal = $enumerator->{value};
        $attrId = $enumerator->{name};
        foreach my $mutexAttrId (@mutexAttrIds)
        {
            $recursiveVal = $mutexAttrId->[1];

            if( $mutexAttrId->[0] eq $attrId )
            {
                write;
                last;
            }
        }
    }

    print $outFile "};\n\n";
}

sub writeMutexFileFooter {
    my($outFile) = @_;
    print $outFile <<VERBATIM;
} // End namespace TARGETING

#endif // TARG_MUTEXATTRIBUTES_H

VERBATIM
}

################################################################################
# Writes the trait file header
################################################################################

sub writeTraitFileHeader {
    my($attributes,$outFile) = @_;

print $outFile <<VERBATIM;

#ifndef TARG_ATTRIBUTETRAITS_H
#define TARG_ATTRIBUTETRAITS_H

/**
 *  \@file attributetraits.H
 *
 *  \@brief Templates which map attributes to their type/properties
 *
 *  This header file contains templates which map attributes to their
 *  type/properties.  This file is autogenerated and should not be altered.
 */

//******************************************************************************
// Includes
//******************************************************************************

// STD
#include <stdint.h>
#include <stdlib.h>

// std::array support is dependent on the compiler supporting c++11
#if __cplusplus >= 201103L
#include <array>
#endif

@{[ $buildBmc ? "#include <targeting/xmltohb/attributestructs.H>" : "" ]}

VERBATIM

foreach my $attribute (@{$attributes->{attribute}})
{
    #check if fspmutex is present?
    if(   (exists $attribute->{simpleType})
            && (exists $attribute->{simpleType}->{fspmutex}) )
    {
        print $outFile "#include <utilmutex.H>\n";
        last; # don't need to look at any others.
    }
}

print $outFile <<VERBATIM;
#include <targeting/common/entitypath.H>

namespace TARGETING
{

//******************************************************************************
// Attribute Property Mappings
//******************************************************************************

/**
 *  \@brief Template associating a specific attribute with a type and other
 *      properties, such as whether it is readable/writable
 *
 *      This is automatically generated
 *
 *      enum {
 *          disabled = Special value for the basic, unused wildcard attribute
 *          readable = Attribute is readable
 *          writable = Attribute is writable
 *          hasStringConversion = Attribute has debug string conversion
 *      }
 *
 *      typedef <type> TYPE // <type> is the Attribute's valid type
 */
template<const ATTRIBUTE_ID A>
class AttributeTraits
{
    private:
        enum { disabled };
        typedef void* Type;
};

VERBATIM

}

################################################################################
# Writes computed traits to trait file
################################################################################

sub writeTraitFileTraits {
    my($attributes,$outFile) = @_;

    my $typedefs = "";
    my $sizefunc = "";

    my %attrValHash;

    foreach my $attribute (@{$attributes->{attribute}})
    {
        # Build boolean traits

        my $traits = "";
        foreach my $trait ("writeable","readable","hasStringConversion","isVolatile")
        {
            if(exists $attribute->{$trait})
            {
                $traits .= " $trait,";
            }
        }

        # Mark the attribute as being a host boot mutex or non-host boot mutex
        if(   (exists $attribute->{simpleType})
            && (exists $attribute->{simpleType}->{hbmutex}
                || exists $attribute->{simpleType}->{hbrecursivemutex}) )
        {
            $traits .= " hbMutex,";
        }
        else
        {
            $traits .= " notHbMutex,";
        }

        # Mark the attribute as being a fsp mutex or non-fsp mutex
        if(   (exists $attribute->{simpleType})
            && (exists $attribute->{simpleType}->{fspmutex}) )
        {
            $traits .= " fspMutex,";
        }
        else
        {
            $traits .= " notFspMutex,";
        }

        if (!($attribute->{id} ~~ @fspAccesCheck))
        {
            $traits .= " fspAccessible,";
        }

        # Build value type

        my $type = "";
        my $dimensions = "";
        my $stdArrAddOn = ""; # Only used if attr holds array type
        my $isEnumerationType = 0;
        if(exists $attribute->{simpleType})
        {
            my $simpleType = $attribute->{simpleType};
            my $simpleTypeProperties = simpleTypeProperties();
            for my $typeName (sort(keys %{$simpleType}))
            {
                if(exists $simpleTypeProperties->{$typeName})
                {
                    if(    $simpleTypeProperties->{$typeName}{typeName}
                        eq "XMLTOHB_USE_PARENT_ATTR_ENUMERATION_ID")
                    {
                        $type = $attribute->{simpleType}->{enumeration}->{id};
                        $isEnumerationType = 1;
                    }
                    else
                    {
                        $type = $simpleTypeProperties->{$typeName}{typeName};
                    }
                    # Set char array
                    if(exists $simpleType->{string})
                    {
                        # Note: A 1-dimensional char array (noted as a "<string>..." type in an XML)
                        # won't trigger the std::array setup below, therefore it must be setup as a
                        # std::array here.
                        # A multidimensional array that holds type char (also using "<string>...")
                        # will not process the char array-dimensions below, so that set up is
                        # started here.
                        if(exists $simpleType->{string}->{sizeInclNull})
                        {
                            # Use the char dimension
                            my $charDimension = $simpleType->{string}->{sizeInclNull};
                            $dimensions = "[$charDimension]";
                            $stdArrAddOn = "std::array<$type, $charDimension>";
                        }
                    }

                    # Setup for a 1,2,3...N-dimensional std::array.
                    if(   (exists $simpleType->{array})
                        && ($simpleTypeProperties->{$typeName}{supportsArray}) )
                    {

                        my @revBounds = reverse split(/,/,$simpleType->{array});

                        for my $idx (0 .. $#revBounds)
                        {
                            $dimensions = "[@revBounds[$idx]]$dimensions";
                            # If $stdArrAddOn is already filled, then we need to append even more
                            # dimensions to the outside of it.
                            if ($stdArrAddOn ne "")
                            {
                                $stdArrAddOn = "std::array<$stdArrAddOn, "
                                    ."@revBounds[$idx]>";
                            }
                            else
                            {
                                $stdArrAddOn = "std::array<$type, "
                                    ."@revBounds[$idx]>";
                            }
                        }

                    }

                    last;
                }
            }

            if($type eq "")
            {
                croak("Unsupported simpleType child element for "
                    . "attribute $attribute->{id}.  Keys are ("
                    . join(',',sort(keys %{$simpleType})) . ")");
            }
        }
        elsif(exists $attribute->{nativeType})
        {
            $type = $attribute->{nativeType}->{name};
        }
        elsif(exists $attribute->{complexType})
        {
            $type = calculateStructName($attribute->{id});
        }
        else
        {
            croak("Could not determine attribute data type for attribute "
                . "$attribute->{id}.");
        }

        chop($traits);

        # if it already exists skip it
        if( !exists($attrValHash{$attribute->{id}}))
        {
            # keep track of the ones we add to our file
            $attrValHash{$attribute->{id}} = 1;

            # Add traits definition to output

            print $outFile "template<>\n";
            print $outFile "class AttributeTraits<ATTR_",$attribute->{id},">\n";
            print $outFile "{\n";
            print $outFile "    public:\n";
            print $outFile "        enum {",$traits," };\n";
            print $outFile "        typedef ", $type, " Type$dimensions;\n";

            # In addition, add a default invalid value to traits definition for
            # uint8_t ... uint64_t, int8_t ... int64_t
            print $outFile "#if __cplusplus >= 201103L \n";
            my $qualifiers = "static constexpr";

            if ($isEnumerationType)
            {
                if ($attribute->{id}=~m/^TYPE$/)
                {
                    # special case for TYPE attr because in pldm_fru.C
                    # its size is restricted to 7 bits
                    print $outFile "        $qualifiers uint32_t $attribute->{id}_INVALID = 0x7F;\n";
                }
                else
                {
                    # otherwise, use default 32 bit sizing for enums
                    print $outFile "        $qualifiers uint32_t $attribute->{id}_INVALID = 0xFFFFFFFF;\n";
                }
            }
            else
            {
                my ($unsigned, $sizeInBytes) = ($type =~ /(u*)int(\d+)/);
                # skip non-integer types
                if ($type=~m/int/)
                {
                    $sizeInBytes /= 8; # convert number of bits to number of bytes
                    my $suffix = "";
                    if ($sizeInBytes >= 8)
                    {
                        # if attr type is 8 bytes large,
                        # append a suffix
                        $suffix = uc($unsigned)."LL";
                    }
                    print $outFile "        $qualifiers $type $attribute->{id}_INVALID = 0x", ("FF" x $sizeInBytes), "$suffix;\n";
                }
            }

            # Append typedef for std::array if attr holds array value
            if ($stdArrAddOn ne "")
            {
                print $outFile "        typedef $stdArrAddOn TypeStdArr;\n";
            }
            print $outFile "#endif\n";
            print $outFile "};\n\n";

            $typedefs .= "// Type aliases and/or sizes for ATTR_"
                . "$attribute->{id} attribute\n";

            $typedefs .= "typedef " . $type .
                " $attribute->{id}" . "_ATTR" . $dimensions . ";\n";

            # Append a more friendly type alias for attribute
            $typedefs .= "typedef " . $type .
                " ATTR_" . "$attribute->{id}" . "_type" . $dimensions . ";\n";

            if ($stdArrAddOn ne "")
            {
                $typedefs .= "#if __cplusplus >= 201103L \n";
                $typedefs .= "typedef $stdArrAddOn "
                    ."ATTR_$attribute->{id}_typeStdArr;\n";
                $typedefs .= "#endif\n";
            }

            # If a string, append max # of characters for the string
            if(   (exists $attribute->{simpleType})
                && (exists $attribute->{simpleType}->{string}))
            {
                my $size = $attribute->{simpleType}->{string}->{sizeInclNull}-1;
                $typedefs .= "const size_t ATTR_"
                    .  "$attribute->{id}" . "_max_chars = "
                    .  "$size"
                    . ";\n";
            }
            $typedefs .= "\n";

            # Create case definitions for attrSizeLookup function

            $sizefunc .= "    // Get size for ATTR_$attribute->{id}" .
                " attribute\n";
            $sizefunc .= "    case ATTR_$attribute->{id}:\n";
            $sizefunc .= "        l_attrSize = sizeof(ATTR_" .
                "$attribute->{id}_type);\n";
            $sizefunc .= "        break;\n";
            $sizefunc .= "\n";
        }
    };

    print $outFile "/**\n";
    print $outFile wrapBrief("Mapping of alias type name to underlying type");
    print $outFile " */\n";
    print $outFile $typedefs ."\n";

    # Create attrSizeLookup function

    print $outFile <<VERBATIM;
/**
 *  \@brief Function to return size of specified attribute
 *
 *  \@param[in] i_attrId Attribute ID for attribute to look up size
 *  \@return uint32_t Size of the attribute
 *
 *  \@retval Size of the attribute if succeeded
 *  \@retval 0 if failed
 *
 */
inline uint32_t attrSizeLookup(ATTRIBUTE_ID i_attrId)
{
    uint32_t l_attrSize = 0;

    switch(i_attrId) {
VERBATIM
    print $outFile $sizefunc;
    print $outFile <<VERBATIM;
    default:
        break;
    }

    return l_attrSize;
}

VERBATIM
}

################################################################################
# Writes the trait file footer
################################################################################

sub writeTraitFileFooter {
    my($outFile) = @_;

    print $outFile <<VERBATIM;
} // End namespace TARGETING

#endif // TARG_ATTRIBUTETRAITS_H

VERBATIM
}

######
#Create a .C file to put attributes into the errlog
#####
sub writeAttrErrlCFile {
    my($attributes,$outFile) = @_;

    print $outFile "\n";
    print $outFile "namespace ERRORLOG\n";
    print $outFile "{\n";
    print $outFile "using namespace TARGETING;\n";
    print $outFile "extern TARG_TD_t g_trac_errl;\n";

    # build function that takes adds 1 attribute to the output
    print $outFile "\n";
    print $outFile "void ErrlUserDetailsAttribute::addData(\n";
    print $outFile "    uint32_t i_attr)\n";
    print $outFile "{\n";
    print $outFile "    char *tmpBuffer = NULL;\n";
    print $outFile "    uint32_t attrSize = 0;\n";
    print $outFile "\n";
    print $outFile "    switch (i_attr) {\n";


    # List of attributes we want to explicitly support
    my @allowed_attributes = (
         "SERIAL_NUMBER",
         "PART_NUMBER",
         "PEC_PCIE_HX_KEYWORD_DATA",
         "ECID",
         "HUID",
         "BOOT_PAU_DPLL_BYPASS",
         "MASTER_MBOX_SCRATCH"
    );

    # loop through every attribute to make the switch/case
    foreach my $attribute (@{$attributes->{attribute}})
    {
        my $skippedattr = 0;
        if( grep { $_ eq $attribute->{id} } @allowed_attributes )
        {
            print "Allowing $attribute->{id}\n";
        }
        else
        {
            print $outFile "#if 0 //Modify writeAttrErrlCFile in xmltohb.pl to add this attribute\n";
            $skippedattr = 1;
        }

        # things we'll skip:
        if(!(exists $attribute->{readable}) ||  # write-only attributes
           (exists $attribute->{simpleType} && (
           (exists $attribute->{simpleType}->{hbmutex}) ||
           (exists $attribute->{simpleType}->{hbrecrusivemutex}) ||
           (exists $attribute->{simpleType}->{fspmutex}))) # mutex attributes
          ) {
            print $outFile "        case (ATTR_",$attribute->{id},"): { break; }\n";
        }
        # any complicated types just get dumped as raw hex binary
        elsif(exists $attribute->{complexType}) {
            print $outFile "        case (ATTR_",$attribute->{id},"): {\n";
            print $outFile "            TRACDCOMP( g_trac_errl, \"ErrlUserDetailsAttribute: ",$attribute->{id}," skipped -- complexType\");\n";
            print $outFile "            attrSize = 0;\n";
            print $outFile "            break;\n";
            print $outFile "        }\n";
        }
        # Enums
        elsif(exists $attribute->{simpleType} && (exists $attribute->{simpleType}->{enumeration}) ) {
            print $outFile "        case (ATTR_",$attribute->{id},"): { // simpleType:enum\n";
            print $outFile "            //TRACDCOMP( g_trac_errl, \"ErrlUserDetailsAttribute: ",$attribute->{id}," entry\");\n";
            print $outFile "            AttributeTraits<ATTR_",$attribute->{id},">::Type tmp;\n";
            print $outFile "            if( iv_pTarget->tryGetAttr<ATTR_",$attribute->{id},">(tmp) ) {\n";
            print $outFile "                tmpBuffer = new char[sizeof(tmp)];\n";
            print $outFile "                memcpy(tmpBuffer, &tmp, sizeof(tmp));\n";
            print $outFile "                attrSize = sizeof(tmp);\n";
            print $outFile "            }\n";
            print $outFile "            break;\n";
            print $outFile "        }\n";
        }
        # signed and unsigned ints

        elsif(isSimpleNumericAttribute($attribute))
        {
            print $outFile "        case (ATTR_",$attribute->{id},"): { //simpleType:uint, :int...\n";
            print $outFile "            //TRACDCOMP( g_trac_errl, \"ErrlUserDetailsAttribute: ",$attribute->{id}," entry\");\n";
            print $outFile "            AttributeTraits<ATTR_",$attribute->{id},">::Type tmp;\n";
            print $outFile "            if( iv_pTarget->tryGetAttr<ATTR_",$attribute->{id},">(tmp) ) {\n";
            print $outFile "                tmpBuffer = new char[sizeof(tmp)];\n";
            print $outFile "                memcpy(tmpBuffer, &tmp, sizeof(tmp));\n";
            print $outFile "                attrSize = sizeof(tmp);\n";
            print $outFile "            }\n";
            print $outFile "            break;\n";
            print $outFile "        }\n";
        }
        # dump the enums for EntityPaths
        elsif(exists $attribute->{nativeType} && ($attribute->{nativeType}->{name} eq "EntityPath")) {
            print $outFile "        case (ATTR_",$attribute->{id},"): { //nativeType:EntityPath\n";
            print $outFile "            //TRACDCOMP( g_trac_errl, \"ErrlUserDetailsAttribute: ",$attribute->{id}," entry\");\n";
            print $outFile "            AttributeTraits<ATTR_",$attribute->{id},">::Type tmp;\n";
            print $outFile "            if( iv_pTarget->tryGetAttr<ATTR_",$attribute->{id},">(tmp) ) {\n";
            print $outFile "                // data is PATH_TYPE, Number of elements, [ Element, Instance# ]\n";
            print $outFile "                EntityPath::PATH_TYPE lPtype = tmp.type();\n";
            print $outFile "                uint8_t lSize = tmp.size();\n";
            print $outFile "                tmpBuffer = new char[sizeof(lPtype) + lSize + lSize * sizeof(EntityPath::PathElement)];\n";
            print $outFile "                memcpy(tmpBuffer + attrSize,&lPtype,sizeof(lPtype));\n";
            print $outFile "                attrSize += sizeof(lPtype);\n";
            print $outFile "                memcpy(tmpBuffer + attrSize,&lSize,sizeof(lSize));\n";
            print $outFile "                attrSize += sizeof(lSize);\n";
            print $outFile "                for (uint32_t i=0;i<lSize;i++) {\n";
            print $outFile "                    EntityPath::PathElement lType = tmp[i];\n";
            print $outFile "                    memcpy(tmpBuffer + attrSize,&lType,sizeof(lType));\n";
            print $outFile "                    attrSize += sizeof(lType);\n";
            print $outFile "                }\n";
            print $outFile "            }\n";
            print $outFile "            break;\n";
            print $outFile "        }\n";
        }
        # any other nativeTypes are just decimals...  (I never saw one)
        elsif(exists $attribute->{nativeType}) {
            print $outFile "        case (ATTR_",$attribute->{id},"): { nativeType\n";
            print $outFile "            //TRACDCOMP( g_trac_errl, \"ErrlUserDetailsAttribute: ",$attribute->{id}," entry\");\n";
            print $outFile "            AttributeTraits<ATTR_",$attribute->{id},">::Type tmp;\n";
            print $outFile "            if( iv_pTarget->tryGetAttr<ATTR_",$attribute->{id},">(tmp) ) {\n";
            print $outFile "                tmpBuffer = new char[sizeof(tmp)];\n";
            print $outFile "                memcpy(tmpBuffer, &tmp, sizeof(tmp));\n";
            print $outFile "                attrSize = sizeof(tmp);\n";
            print $outFile "            }\n";
            print $outFile "            break;\n";
            print $outFile "        }\n";
        }

        if( $skippedattr )
        {
            print $outFile "#endif\n";
        }
    }

    print $outFile "        default: { //Shouldn't be anything here!!\n";
    print $outFile "            TRACDCOMP( g_trac_errl, \"ErrlUserDetailsAttribute: UNKNOWN i_attr %x\", i_attr);\n";
    print $outFile "            break;\n";
    print $outFile "        }\n";


    print $outFile "    } //switch\n";
    print $outFile "\n";

    print $outFile "    // if we generated one, copy the string into the buffer\n";
    print $outFile "    if (attrSize) { // we have something to output\n";
    print $outFile "        // resize buffer and copy string into it\n";
    print $outFile "        uint8_t * pBuf;\n";
    print $outFile "        pBuf = reinterpret_cast<uint8_t *>(reallocUsrBuf(iv_dataSize + attrSize + sizeof(i_attr) ));\n";
    print $outFile "        memcpy(pBuf + iv_dataSize, &i_attr, sizeof(i_attr)); // first dump the attr enum\n";
    print $outFile "        iv_dataSize += sizeof(i_attr);\n";
    print $outFile "        memcpy(pBuf + iv_dataSize, tmpBuffer, attrSize); // copy into iv_pBuffer\n";
    print $outFile "        iv_dataSize += attrSize;\n";
    print $outFile "    }\n";
    print $outFile "    delete [] tmpBuffer;\n";
    print $outFile "}\n";
    print $outFile "\n";

    # build internal function that dumps all attributes
    print $outFile "//------------------------------------------------------------------------------\n";
    print $outFile "void ErrlUserDetailsAttribute::dumpAll()\n";
    print $outFile "{\n";
    print $outFile "    // write out the HUID first and always\n";
    print $outFile "    addData(ATTR_HUID);\n";

    # loop through every attribute to make the swith/case
    foreach my $attribute (@{$attributes->{attribute}})
    {
        # skip the HUID that we already added
        if( $attribute->{id} =~ /HUID/ ) {
            next;
        }
        # things we'll skip:
        if(!(exists $attribute->{readable}) ||  # write-only attributes
           !(exists $attribute->{writeable}) || # read-only attributes
           (exists $attribute->{simpleType} && (
           (exists $attribute->{simpleType}->{hbmutex}) ||
           (exists $attribute->{simpleType}->{hbrecursivemutex}) ||
           (exists $attribute->{simpleType}->{fspmutex}))) # mutex attributes
          ) {
            next;
        }
        print $outFile "    addData(ATTR_",$attribute->{id},");\n";
    }
    print $outFile "}\n";

    print $outFile "\n";

    print $outFile "} // namespace\n\n";
} # sub writeAttrErrlCFile


######
#Create a .H and an equivalent .py file to parse attributes out of the errlog
#####
sub writeAttrErrlHFile {
    my($attributes,$outFile,$outFilePY) = @_;

    # Included by errludattributeP.H
    print $outFile "\n";
    print $outFile "namespace ERRORLOG\n";
    print $outFile "{\n";
    print $outFile "class ErrlUserDetailsParserAttribute : public ErrlUserDetailsParser {\n";
    print $outFile "public:\n";
    print $outFile "\n";
    print $outFile "    ErrlUserDetailsParserAttribute() {}\n";
    print $outFile "\n";
    print $outFile "    virtual ~ErrlUserDetailsParserAttribute() {}\n";
    print $outFile "  /**\n";
    print $outFile "   *  \@brief Parses Attribute user detail data from an error log\n";
    print $outFile "   *  \@param  i_version Version of the data\n";
    print $outFile "   *  \@param  i_parse   ErrlUsrParser object for outputting information\n";
    print $outFile "   *  \@param  i_pBuffer Pointer to buffer containing detail data\n";
    print $outFile "   *  \@param  i_buflen  Length of the buffer\n";
    print $outFile "   */\n";
    print $outFile "  virtual void parse(errlver_t i_version,\n";
    print $outFile "                        ErrlUsrParser & i_parser,\n";
    print $outFile "                        void * i_pBuffer,\n";
    print $outFile "                        const uint32_t i_buflen) const\n";
    print $outFile "  {\n";
    print $outFile "    const char *pLabel = NULL;\n";
    print $outFile "    uint8_t *l_ptr = static_cast<uint8_t *>(i_pBuffer);\n";
    print $outFile "    std::vector<char> l_traceEntry(64);\n";
    print $outFile "    i_parser.PrintString(\"Target Attributes\", NULL);\n";
    print $outFile "\n";

    print $outFile "    for (; (l_ptr + sizeof(uint32_t)) <= ((uint8_t*)i_pBuffer + i_buflen); )\n";
    print $outFile "    {\n";
    print $outFile "        // first 4 bytes is the attr enum\n";
    print $outFile "        uint32_t attrEnum = ntohl(UINT32_FROM_PTR(l_ptr));\n";
    print $outFile "        l_ptr += sizeof(attrEnum);\n";
    print $outFile "        char* tmplabel = NULL;\n";
    print $outFile "\n";
    print $outFile "        switch (attrEnum) {\n";

    print $outFilePY "# The content of this file, errludattributeP_gen.py, is automatically\n";
    print $outFilePY "# generated by src/usr/targeting/common/xmltohb/xmltohb.pl and output to\n";
    print $outFilePY "# obj/genfiles/errl/errludattributeP_gen.py.\n\n";

    print $outFilePY "# At this time, the generated file must be manually copied from the\n";
    print $outFilePY "# obj/genfiles/errl directory to the src/usr/errl/plugins/ebmc/b0100 directory and\n";
    print $outFilePY "# then manually checked in to be picked up by the Hostboot build.\n\n";

    print $outFilePY "# To pull the parser change into a BMC image, update the commit pointer in the\n";
    print $outFilePY "# openbmc project's meta-openpower/recipes-phosphor/logging/hostboot-pel-parsers_git.bb\n";
    print $outFilePY "# file to reference the Hostboot commit with the change.\n\n";

    print $outFilePY "import json\n";
    print $outFilePY "from udparsers.helpers.errludP_Helpers import intConcat, hexConcat\n\n";
    print $outFilePY "\"\"\" User Details Parser Attribute called by b0100.py\n\n";
    print $outFilePY "\@param[in] ver: int value of subsection version\n";
    print $outFilePY "\@param[in] data: memoryview object of data to be parsed\n";
    print $outFilePY "\@returns: JSON string of parsed data\n";
    print $outFilePY "\"\"\"\n";
    print $outFilePY "def ErrlUserDetailsParserAttribute(ver, data):\n";
    print $outFilePY "    d = dict()\n";
    print $outFilePY "    subd = dict()\n";
    print $outFilePY "    i = 0\n\n";
    print $outFilePY "    while (i+4) <= len(data):\n";
    print $outFilePY "        #First 4 bytes is the attr enum\n";
    print $outFilePY "        attrEnum,i=intConcat(data, i, i+4)\n";
    print $outFilePY "        traceEntry = []\n";
    print $outFilePY "        label = \'\'\n\n";


    my $attributeIdEnum = getAttributeIdEnumeration($attributes);
    my $isFirst = 1;

    # Sort the attributes by attribute ID so they are in deterministic
    # order, making comparing emitted output across releases easier.
    # First map each attribute ID to the attribute in a hash, then
    # work from the sorted hash.
    my %sortedAttrs;
    foreach my $attribute (@{$attributes->{attribute}})
    {
        my $attrVal;
        foreach my $enum (@{$attributeIdEnum->{enumerator}})
        {
            if ($enum->{name} eq $attribute->{id})
            {
                $attrVal = $enum->{value};
                last; # don't need to look at any others.
            }
        }
        $sortedAttrs{hex($attrVal)} = $attribute;
    }

    # loop through every attribute to make the switch/case
    foreach my $attributeId (sort { $a <=> $b} keys %sortedAttrs)
    {
        my $attribute = $sortedAttrs{$attributeId};
        my $attrVal;
        foreach my $enum (@{$attributeIdEnum->{enumerator}})
        {
            if ($enum->{name} eq $attribute->{id})
            {
                $attrVal = $enum->{value};
                last; # don't need to look at any others.
            }
        }
        print $outFile "          case ",$attrVal,": {\n";

        if ($isFirst) {
            print $outFilePY "        if attrEnum == $attrVal:\n";
            $isFirst = 0;
        }
        else {
            print $outFilePY "        elif attrEnum == $attrVal:\n";
        }

        # things we'll skip:
        if(!(exists $attribute->{readable}) ||  # write-only attributes
           (exists $attribute->{simpleType} && (
           (exists $attribute->{simpleType}->{hbmutex}) ||
           (exists $attribute->{simpleType}->{hbrecursivemutex}) ||
           (exists $attribute->{simpleType}->{fspmutex}))) # mutex attributes
          ) {
            print $outFile "              //not readable\n";

            print $outFilePY "            pass #not readable\n";
        }
        # Enums have strings defined already, use them
        elsif(exists $attribute->{simpleType} && (exists $attribute->{simpleType}->{enumeration}) ) {
            print $outFile "              //simpleType:enum\n";
            print $outFile "              pLabel = \"",$attribute->{id},"\";\n";

            print $outFilePY "            #simpleType:enum\n";
            print $outFilePY "            label = \"",$attribute->{id},"\"\n";

            foreach my $enumerationType (@{$attributes->{enumerationType}})
            {
                if ($enumerationType->{id} eq $attribute->{id})
                {

                print $outFile "              switch (*((uint32_t*)l_ptr)) {\n";

                print $outFilePY "            attr, i=intConcat(data, i, i+4)\n";
                my $isFirst = 1;

                foreach my $enumerator (@{$enumerationType->{enumerator}})
                {
                    my $enumName = $attribute->{id} . "_" . $enumerator->{name};
                    my $enumHex = sprintf "0x%08X", enumNameToValue($enumerationType,$enumerator->{name});
                    print $outFile "                  case ",$enumHex,": {\n";
                    print $outFile "                      sprintf(&(l_traceEntry[0]), \"",$enumName,"\");\n";
                    print $outFile "                      l_ptr += sizeof(uint32_t);\n";
                    print $outFile "                      break;\n";
                    print $outFile "                  }\n";

                    if ($isFirst) {
                        print $outFilePY "            if attr == $enumHex:\n";
                        $isFirst = 0;
                    }
                    else {
                        print $outFilePY "            elif attr == $enumHex:\n";
                    }

                    print $outFilePY "                 traceEntry.append(\"$enumName\")\n";

                }
                print $outFile "                  default: break;\n";
                print $outFile "              }\n";
                }
            }
        }
        # makes no sense to dump mutex attributes, so skipping
        elsif(exists $attribute->{simpleType} && (exists $attribute->{simpleType}->{hbmutex}) || (exists $attribute->{simpleType}->{hbrecursivemutex}) ) {
            print $outFile "            //Mutex attributes - skipping\n";

            print $outFilePY "            pass #Mutex attributes - skipping\n";
        }
        # makes no sense to dump fsp mutex attributes, so skipping
        elsif(   (exists $attribute->{simpleType})
              && (exists $attribute->{simpleType}->{fspmutex}) )
        {
            print $outFile "            //Mutex attributes - skipping\n";

            print $outFilePY "            pass #Mutex attributes - skipping\n";
        }
        # any complicated types just get dumped as raw hex binary
        elsif(exists $attribute->{complexType}) {
            #print $outFile "         //complexType\n";
            #print $outFile "         uint32_t<ATTR_",$attribute->{id},">::Type tmp;\n";
            #print $outFile "         if( i_pTarget->tryGetAttr<ATTR_",$attribute->{id},">(tmp) ) {\n";
            #print $outFile "           sprintf(i_buffer, \" \", &tmp, sizeof(tmp));\n";
            #print $outFile "         }\n";
            print $outFile "              //complexType - skipping\n";

            print $outFilePY "            pass #complexType - skipping\n";
        }
        # unsigned ints dump as hex, signed as decimals
        elsif(isSimpleNumericAttribute($attribute))
        {
            print $outFile "              //simpleType:uint\n";
            print $outFile "              pLabel = \"",$attribute->{id},"\";\n";

            print $outFilePY "            #simpleType:uint\n";
            print $outFilePY "            label = \"",$attribute->{id},"\"\n";

            my @bounds;
            if(exists $attribute->{simpleType}->{array})
            {
                # remove any whitespace from simpleType array
                $attribute->{simpleType}->{array} =~ s/\s+//g;
                    @bounds = split(/,/,$attribute->{simpleType}->{array});
            }
            else
            {
                $bounds[0] = 1;
            }
            my $total_count = 1;
            foreach my $bound (@bounds)
            {
                $total_count *= $bound;
            }
            my $size = scalar(@bounds);
            if (($size == 1) && ( $bounds[0] > 1))
            {
                print $outFile "              uint32_t offset = sprintf(&(l_traceEntry[0]), \"[$bounds[0]]:\");\n";

                print $outFilePY "            traceEntry.append(\"[$bounds[0]]:\")\n";
            }
            elsif ($size == 2)
            {
                print $outFile "              uint32_t offset = sprintf(&(l_traceEntry[0]), \"[$bounds[0]][$bounds[1]]:\");\n";

                print $outFilePY "            traceEntry.append(\"[$bounds[0]][$bounds[1]]:\")\n";
            }
            elsif ($size == 3)
            {
                print $outFile "              uint32_t offset = sprintf(&(l_traceEntry[0]), \"[$bounds[0]][$bounds[1]][$bounds[2]]:\");\n";

                print $outFilePY "            traceEntry.append(\"[$bounds[0]][$bounds[1]][$bounds[2]]:\")\n";
            }
            else
            {
                print $outFile "              uint32_t offset = 0;\n";
            }
            if (exists $attribute->{simpleType}->{uint8_t})
            {
                print $outFile "              l_traceEntry.resize(10+offset + $total_count * 5);\n";
                print $outFile "              for (uint32_t i = 0;i<$total_count;i++) {\n";
                print $outFile "                  sprintf(&(l_traceEntry[offset+i*5]), \"0x%.2X \", *(((uint8_t *)l_ptr)+i));\n";
                print $outFile "              }\n";
                print $outFile "              l_ptr += $total_count * sizeof(uint8_t);\n";

                print $outFilePY "            for x in range($total_count):\n";
                print $outFilePY "                traceEntry.append(hexConcat(data, i, i+1)[0])\n";
                print $outFilePY "                i += 1\n";
            }
            elsif (exists $attribute->{simpleType}->{uint16_t}) {
                print $outFile "              l_traceEntry.resize(10+offset + $total_count * 7);\n";
                print $outFile "              for (uint32_t i = 0;i<$total_count;i++) {\n";
                print $outFile "                  sprintf(&(l_traceEntry[offset+i*7]), \"0x%.4X \", ntohs(UINT16_FROM_PTR(reinterpret_cast<const uint16_t*>(l_ptr) + i)));\n";
                print $outFile "              }\n";
                print $outFile "              l_ptr += $total_count * sizeof(uint16_t);\n";

                print $outFilePY "            for x in range($total_count):\n";
                print $outFilePY "                traceEntry.append(hexConcat(data, i, i+2)[0])\n";
                print $outFilePY "                i += 2\n";
            }
            elsif (exists $attribute->{simpleType}->{uint32_t}) {
                print $outFile "              l_traceEntry.resize(10+offset + $total_count * 11);\n";
                print $outFile "              for (uint32_t i = 0;i<$total_count;i++) {\n";
                print $outFile "                  sprintf(&(l_traceEntry[offset+i*11]), \"0x%.8X \", ntohl(UINT32_FROM_PTR(reinterpret_cast<const uint32_t*>(l_ptr)+i)));\n";
                print $outFile "              }\n";
                print $outFile "              l_ptr += $total_count * sizeof(uint32_t);\n";

                print $outFilePY "            for x in range($total_count):\n";
                print $outFilePY "                traceEntry.append(hexConcat(data, i, i+4)[0])\n";
                print $outFilePY "                i += 4\n";
            }
            elsif (exists $attribute->{simpleType}->{uint64_t}) {
                print $outFile "              l_traceEntry.resize(10+offset + $total_count * 19);\n";
                print $outFile "              for (uint32_t i = 0;i<$total_count;i++) {\n";
                print $outFile "                  sprintf(&(l_traceEntry[offset+i*19]), \"0x%.16llX \", ntohll(UINT64_FROM_PTR(reinterpret_cast<const uint64_t*>(l_ptr)+i)));\n";
                print $outFile "              }\n";
                print $outFile "              l_ptr += $total_count * sizeof(uint64_t);\n";

                print $outFilePY "            for x in range($total_count):\n";
                print $outFilePY "                traceEntry.append(hexConcat(data, i, i+8)[0])\n";
                print $outFilePY "                i += 8\n";
            }
            elsif (exists $attribute->{simpleType}->{int8_t}) {
                print $outFile "              l_traceEntry.resize(10+offset + $total_count * 5);\n";
                print $outFile "              for (uint32_t i = 0;i<$total_count;i++) {\n";
                print $outFile "                  sprintf(&(l_traceEntry[offset+i*5]), \"0x%.2X \", *(((int8_t *)l_ptr)+i));\n";
                print $outFile "              }\n";
                print $outFile "              l_ptr += $total_count * sizeof(uint8_t);\n";

                print $outFilePY "            for x in range($total_count):\n";
                print $outFilePY "                traceEntry.append(hexConcat(data, i, i+1)[0])\n";
                print $outFilePY "                i += 1\n";
            }
            elsif (exists $attribute->{simpleType}->{int16_t}) {
                print $outFile "              l_traceEntry.resize(10+offset + $total_count * 7);\n";
                print $outFile "              for (uint32_t i = 0;i<$total_count;i++) {\n";
                print $outFile "                  sprintf(&(l_traceEntry[offset+i*7]), \"0x%.4X \", ntohs(INT16_FROM_PTR(reinterpret_cast<const int16_t*>(l_ptr)+i)));\n";
                print $outFile "              }\n";
                print $outFile "              l_ptr += $total_count * sizeof(int16_t);\n";

                print $outFilePY "            for x in range($total_count):\n";
                print $outFilePY "                traceEntry.append(hexConcat(data, i+x, i+2)[0])\n";
                print $outFilePY "                i += 2\n";
            }
            elsif (exists $attribute->{simpleType}->{int32_t}) {
                print $outFile "              l_traceEntry.resize(10+offset + $total_count * 11);\n";
                print $outFile "              for (uint32_t i = 0;i<$total_count;i++) {\n";
                print $outFile "                  sprintf(&(l_traceEntry[offset+i*11]), \"0x%.8X \", ntohl(INT32_FROM_PTR(reinterpret_cast<const int32_t*>(l_ptr)+i)));\n";
                print $outFile "              }\n";
                print $outFile "              l_ptr += $total_count * sizeof(int32_t);\n";

                print $outFilePY "            for x in range($total_count):\n";
                print $outFilePY "                traceEntry.append(hexConcat(data, i, i+4)[0])\n";
                print $outFilePY "                i += 4\n";
            }
            elsif (exists $attribute->{simpleType}->{int64_t}) {
                print $outFile "              l_traceEntry.resize(10+offset + $total_count * 19);\n";
                print $outFile "              for (uint32_t i = 0;i<$total_count;i++) {\n";
                print $outFile "                  sprintf(&(l_traceEntry[offset+i*19]), \"0x%.16llX \", ntohll(INT64_FROM_PTR(reinterpret_cast<const int64_t*>(l_ptr)+i)));\n";
                print $outFile "              }\n";
                print $outFile "              l_ptr += $total_count * sizeof(int64_t);\n";

                print $outFilePY "            for x in range($total_count):\n";
                print $outFilePY "                traceEntry.append(hexConcat(data, i, i+8)[0])\n";
                print $outFilePY "                i += 8\n";
            }
        }
        # EntityPaths
        elsif(exists $attribute->{nativeType} && ($attribute->{nativeType}->{name} eq "EntityPath")) {
            print $outFile "              //nativeType:EntityPath\n";
            print $outFile "              pLabel = \"",$attribute->{id},"\";\n";

            print $outFilePY "            #nativeType:EntityPath\n";
            print $outFilePY "            label = \"$attribute->{id}\"\n";

            # data is PATH_TYPE, Number of elements, [ Element, Instance# ]
            # output is PathType:/ElementInstance/ElementInstance/ElementInstance
            print $outFile "              const char *pathString;\n";
            print $outFile "              // from targeting/common/entitypath.[CH]\n";
            print $outFile "              const uint8_t lPtype = *l_ptr; // PATH_TYPE\n";
            print $outFile "              switch (lPtype) {\n";
            print $outFile "                  case 0x01: pathString = \"Logical:\"; break;\n";
            print $outFile "                  case 0x02: pathString = \"Physical:\"; break;\n";
            print $outFile "                  case 0x03: pathString = \"Device:\"; break;\n";
            print $outFile "                  case 0x04: pathString = \"Power:\"; break;\n";
            print $outFile "                  default:   pathString = \"Unknown:\"; break;\n";
            print $outFile "              }\n";
            print $outFile "              l_traceEntry.resize(strlen(pathString) + 128);\n";
            print $outFile "              uint32_t dataSize = sprintf(&(l_traceEntry[0]), \"%s\",pathString);\n";
            print $outFile "              const uint8_t lSize = *(l_ptr + 1); // number of elements\n";
            print $outFile "              uint8_t *lElementInstance = (l_ptr + 2);\n";
            print $outFile "              for (uint32_t i=0;i<lSize;i += 2) {\n";
            print $outFile "                  switch (lElementInstance[i]) {\n";

            print $outFilePY "            pathType = { 0x01: \"Logical:\",\n";
            print $outFilePY "                         0x02: \"Physical:\",\n";
            print $outFilePY "                         0x03: \"Device:\",\n";
            print $outFilePY "                         0x04: \"Power:\" }\n\n";
            print $outFilePY "            elementInstance = {\n";

            foreach my $enumerationType (@{$attributes->{enumerationType}})
            {
                if( $enumerationType->{id} eq "TYPE" ) {
                    foreach my $enumerator (@{$enumerationType->{enumerator}})
                    {
                        my $enumHex = sprintf "0x%02X",
                            enumNameToValue($enumerationType,$enumerator->{name});
                        my $enumName = $enumerator->{name};
                        if ($enumName eq "SYS") {
                            $enumName = "Sys";
                        } elsif ($enumName eq "PROC") {
                            $enumName = "Proc";
                        } elsif ($enumName eq "NODE") {
                            $enumName = "Node";
                        } elsif ($enumName eq "CORE") {
                            $enumName = "Core";
                        } elsif ($enumName eq "MEMBUF") {
                            $enumName = "Membuf";
                        }
                        print $outFile "                      case $enumHex: { pathString = \"/$enumName\"; break; }\n";

                        print $outFilePY "                              $enumHex: \"/$enumName\",\n";
                    }
                }
            } # enumerationType
            print $outFile "                      default:   { pathString = \"/UNKNOWN\"; break; }\n";
            print $outFile "                  } // switch\n";
            print $outFile "                  // copy next part in, overwritting previous terminator\n";
            print $outFile "                  dataSize += sprintf(&(l_traceEntry[0]) + dataSize, \"%s%d\",pathString,lElementInstance[i+1]);\n";
            print $outFile "                  l_ptr += 2 * sizeof(uint8_t);\n";
            print $outFile "              } // for\n";

            print $outFilePY "                              }\n";
            print $outFilePY "            pType = data[i]\n";
            print $outFilePY "            i += 1\n";
            print $outFilePY "            start+=1\n";
            print $outFilePY "            pathString = pathType.get(pType, \"Unknown:\")\n";
            print $outFilePY "            pathSize = data[i]\n";
            print $outFilePY "            i += 1\n";
            print $outFilePY "            for x in range(0, pathSize, 2):\n";
            print $outFilePY "                pathString += elementInstance.get(data[start], \"/UNKNOWN\")\n";
            print $outFilePY "                pathString += str(data[start+1])\n";
            print $outFilePY "                start+=2\n\n";
            print $outFilePY "            return pathString, start+1\n";
        }
        # any other nativeTypes are just decimals...  (I never saw one)
        elsif(exists $attribute->{nativeType}) {
            print $outFile "              //nativeType\n";
            print $outFile "              pLabel = \"",$attribute->{id},"\";\n";
            print $outFile "              sprintf(&(l_traceEntry[0]), \"%d\", *((int32_t *)l_ptr));\n";
            print $outFile "              l_ptr += sizeof(uint32_t);\n";

            print $outFilePY "            #nativeType\n";
            print $outFilePY "            label = \"$attribute->{id}\"\n";
            print $outFilePY "            traceEntry.append(intConcat(data, i, i+4))\n";
            print $outFilePY "            i += 1\n";
        }
        # just in case, nothing..
        else
        {
            #print $outFile "              //unknown attributes\n";
            print $outFilePY "            pass\n";
        }


        print $outFile "              break;\n";
        print $outFile "          }\n";

    }
    print $outFile "          default: {\n";
    print $outFile "              tmplabel = new char[30];\n";
    print $outFile "              sprintf( tmplabel, \"Unknown [0x%x]\", attrEnum );\n";
    print $outFile "              pLabel = tmplabel;\n";
    print $outFile "              break;\n";
    print $outFile "          }\n";
    print $outFile "        } // switch\n";
    print $outFile "\n";
    print $outFile "        // pointing to something - print it.\n";
    print $outFile "        if (pLabel != NULL) {\n";
    print $outFile "            i_parser.PrintString(pLabel, &(l_traceEntry[0]));\n";
    print $outFile "        }\n";
    print $outFile "        if( tmplabel != NULL ) { delete[] tmplabel; }\n";
    print $outFile "    } // for\n";
    print $outFile "  } // parse\n\n";
    print $outFile "private:\n";
    print $outFile "\n";
    print $outFile "// Disabled\n";
    print $outFile "ErrlUserDetailsParserAttribute(const ErrlUserDetailsParserAttribute &);\n";
    print $outFile "ErrlUserDetailsParserAttribute & operator=(const ErrlUserDetailsParserAttribute &);\n";
    print $outFile "};\n";
    print $outFile "} // namespace\n\n";

    print $outFilePY "        else:\n";
    print $outFilePY "            label=\"Unknown\"\n";
    print $outFilePY "            traceEntry.append(hex(attrEnum))\n";
    print $outFilePY "\n        if label:\n";
    print $outFilePY "            subd[label]=traceEntry\n\n";
    print $outFilePY "    d[\'Target Attributes\']=subd\n";
    print $outFilePY "    jsonStr = json.dumps(d)\n";
    print $outFilePY "    return jsonStr\n";
} # sub writeAttrErrlHFile

######
#Create a .csv file to parse attribute overrides/syncs
#####
sub writeAttrInfoCsvFile {
    my($attributes,$outFile) = @_;

    # Print the file header
    print $outFile "# targAttrInfo.csv\n";
    print $outFile "# This file is generated by perl script xmltohb.pl\n";
    print $outFile "# It lists information about TARG attributes and is used to\n";
    print $outFile "# process FAPI Attribute text files (overrides/syncs)\n";
    print $outFile "# Format:\n";
    print $outFile "# <FAPI-ATTR-ID-STR>,<LAYER-ATTR-ID-STR>,<ATTR-ID-VAL>,<ATTR-TYPE>\n";

    my $attributeIdEnum = getAttributeIdEnumeration($attributes);

    # loop through every attribute
    foreach my $attribute (@{$attributes->{attribute}})
    {
        # Only (initially) support attributes with simple integer types
        if (isSimpleNumericAttribute($attribute))
        {
            my $fapiId = "NO-FAPI-ID";

            if (exists $attribute->{hwpfToHbAttrMap}[0])
            {
                $fapiId = $attribute->{hwpfToHbAttrMap}[0]->{id};
            }

            foreach my $enum (@{$attributeIdEnum->{enumerator}})
            {
                if ($enum->{name} eq $attribute->{id})
                {
                    print $outFile "$fapiId,";
                    print $outFile "ATTR_$attribute->{id}";
                    print $outFile ",$enum->{value},";

                    if (exists $attribute->{simpleType}->{uint8_t})
                    {
                        print $outFile "u8";
                    }
                    elsif (exists $attribute->{simpleType}->{uint16_t})
                    {
                        print $outFile "u16";
                    }
                    elsif (exists $attribute->{simpleType}->{uint32_t})
                    {
                        print $outFile "u32";
                    }
                    elsif (exists $attribute->{simpleType}->{uint64_t})
                    {
                        print $outFile "u64";
                    }
                    elsif (exists $attribute->{simpleType}->{int8_t})
                    {
                        print $outFile "s8";
                    }
                    elsif (exists $attribute->{simpleType}->{int16_t})
                    {
                        print $outFile "s16";
                    }
                    elsif (exists $attribute->{simpleType}->{int32_t})
                    {
                        print $outFile "s32";
                    }
                    elsif (exists $attribute->{simpleType}->{int64_t})
                    {
                        print $outFile "s64";
                    }

                    if (exists $attribute->{simpleType}->{array})
                    {
                        # Remove leading whitespace
                        my $dimText = $attribute->{simpleType}->{array};
                        $dimText =~ s/^\s+//;

                        # Split on commas or whitespace
                        my @vals = split(/\s*,\s*|\s+/, $dimText);

                        foreach my $val (@vals)
                        {
                            print $outFile "[$val]";
                        }
                    }
                    print $outFile "\n";
                }
            }
        }
    }
} # sub writeAttrInfoCsvFile

################################################################################
# Writes the unordered/Ordered map of all target attribute  metadata
# C file header
################################################################################

sub writeAttrMetadataMapCFileHeader {
    my($outFile) = @_;

print $outFile <<VERBATIM;

/**
 *  \@file mapattrmetadata.C
 *
 *  \@brief Interface to get the unordered/ordered map of all target attributes
 *  with respective attribute size and read/write properties. This file is
 *  autogenerated and should not be altered.
 */

// TARG
#include <mapattrmetadata.H>

//******************************************************************************
// Macros
//******************************************************************************

#undef TARG_NAMESPACE
#undef TARG_CLASS
#undef TARG_FUNC

//******************************************************************************
// Implementation
//******************************************************************************

namespace TARGETING
{

#define TARG_NAMESPACE "TARGETING::"
#define TARG_CLASS "MapAttrMetadata::"

// Persistency defines
static __attribute__((unused)) const char * P0_PERSISTENCY = "p0";
static __attribute__((unused)) const char * P1_PERSISTENCY = "p1";
static __attribute__((unused)) const char * P3_PERSISTENCY = "p3";

//******************************************************************************
// TARGETING::mapAttrMetadata
//******************************************************************************

TARGETING::MapAttrMetadata& mapAttrMetadata()
{
    #define TARG_FN "mapAttrMetadata()"

    return TARG_GET_SINGLETON(TARGETING::theMapAttrMetadata);

    #undef TARG_FN
}

//******************************************************************************
// TARGETING::MapAttrMetadata::~MapAttrMetadata
//******************************************************************************

MapAttrMetadata::~MapAttrMetadata()
{
    #define TARG_FN "~MapAttrMetadata()"
    #undef TARG_FN
}

//******************************************************************************
// TARGETING::MapAttrMetadata::getMapMetadataForAllAttributes
//******************************************************************************

const AttrMetadataMapper&
MapAttrMetadata::getMapMetadataForAllAttributes() const
{
    #define TARG_FN "getMapMetadataForAllAttributes()"
    TARG_ENTER();

    TARG_EXIT();
    return iv_mapAttrMetadata;

    #undef TARG_FN
}

//******************************************************************************
// TARGETING::MapAttrMetadata::MapAttrMetadata
//******************************************************************************

MapAttrMetadata::MapAttrMetadata()
{
    #define TARG_FN "MapAttrMetadata()"
VERBATIM

}

################################################################################
# Create a .C file to put All Target Attributes along with there respective
# Size and read/write properties in a unordered/ordered map variable
################################################################################

sub writeAttrMetadataMapCFile{
    my($attributes,$outFile) = @_;
    my %finalAttrhash = ();

    # look for all attributes in the XML
    foreach my $attribute (@{$attributes->{attribute}})
    {
        $finalAttrhash{$attribute->{id}} = $attribute;
    }

    my $mapAttrMetadataPairs = "\n    static const Pair_t l_pair[] = {\n";
    my $hbOnlyMapAttrMetadataPairs = '';

    foreach my $key ( keys %finalAttrhash)
    {
        # Fetch the Size of the attribute
        my $keySize = "ATTR_"."$key"."_type";

        if (!(exists $finalAttrhash{$key}->{hbOnly})
            && ((exists $finalAttrhash{$key}->{simpleType})
                || (exists $finalAttrhash{$key}->{complexType})
                || (exists $finalAttrhash{$key}->{nativeType})))
        {
            # We're good to go
        }
        else
        {
            $hbOnlyMapAttrMetadataPairs .=
                "        std::make_pair( ATTR_$key, AttrMetadataStr(sizeof($keySize), false, NULL, false )),\n";
            next;
        }

        $mapAttrMetadataPairs .= "        std::make_pair( ATTR_".$key.",";
        $mapAttrMetadataPairs .= " AttrMetadataStr(sizeof($keySize),";

        # Fetch Read/Writeable Property
        if(exists $finalAttrhash{$key}->{writeable})
        {
            $mapAttrMetadataPairs .= " true,";
        }
        else
        {
            $mapAttrMetadataPairs .= " false,";
        }

        if(!(exists $finalAttrhash{$key}->{persistency}))
        {
            croak("Attribute[$key] should have persistency by default");
        }
        if($finalAttrhash{$key}->{persistency} eq "non-volatile")
        {
            $mapAttrMetadataPairs .= " P3_PERSISTENCY,";
        }
        elsif(($finalAttrhash{$key}->{persistency} eq
               "semi-non-volatile-zeroed") ||
              ($finalAttrhash{$key}->{persistency} eq "semi-non-volatile"))
        {
            $mapAttrMetadataPairs .= " P1_PERSISTENCY,";
        }
        elsif(($finalAttrhash{$key}->{persistency} eq "volatile") ||
              ($finalAttrhash{$key}->{persistency} eq "volatile-zeroed"))
        {
            $mapAttrMetadataPairs .= " P0_PERSISTENCY,";
        }
        else
        {
            croak("Not a defined" .
                  "Persistency[$finalAttrhash{$key}->{persistency}] for" .
                  "attribute [$key]");
        }

        if ($finalAttrhash{$key}->{id} ~~ @nonSyncAttributes)
        {
            $mapAttrMetadataPairs .= " true) ),\n";
        }
        else
        {
            $mapAttrMetadataPairs .= " false) ),\n";
        }
    }

    print $outFile $mapAttrMetadataPairs;

    # The HB-only attributes are only compiled in for hostboot to save space.
    print $outFile "#ifdef __HOSTBOOT_MODULE\n";
    print $outFile "// ******** WARNING ********\n";
    print $outFile "// The synchronized, read-write, and persistency fields\n";
    print $outFile "// for the following entries are potentially INCORRECT\n";
    print $outFile "// because Hostboot has not yet needed to consume them.\n";
    print $outFile "// Edit xmltohb.pl to calculate these values if necessary.\n";

    print $outFile $hbOnlyMapAttrMetadataPairs;
    print $outFile "#endif\n";

    print $outFile "    };\n";
    print $outFile "    iv_mapAttrMetadata\.insert( l_pair,\n";
    print $outFile "        l_pair + (sizeof(l_pair)/sizeof(l_pair[0])) );\n\n";
}

################################################################################
# Writes the map all attr size C file Footer
################################################################################

sub writeAttrMetadataMapCFileFooter {
    my($outFile) = @_;

    print $outFile <<VERBATIM;
    #undef TARG_FN
}

}// namespace TARGETING

VERBATIM
}

################################################################################
# Create a .H file to put All Target Attributes along with their respective
# Size and read/write properties in a unordered/ordered map variable
################################################################################

sub writeAttrMetadataMapHFile{
    my($outFile) = @_;
    print $outFile <<VERBATIM;

#ifndef MAPATTRMETADATA_H
#define MAPATTRMETADATA_H

/**
 *  \@file mapattrmetadata.H
 *
 *  \@brief Interface to get the unordered/ordered map of all target attributes
 *  respective attribute size and read/write properties. This file is
 *  autogenerated and should not be altered.
 */

// STD
#ifndef __HOSTBOOT_MODULE
#include <tr1/unordered_map>
#else
#include <map>
#endif

// TARG
#include <targeting/common/trace.H>
#include <targeting/common/target.H>

//******************************************************************************
// Macros
//******************************************************************************

#undef TARG_NAMESPACE
#undef TARG_CLASS
#undef TARG_FUNC

//******************************************************************************
// Interface
//******************************************************************************

#ifndef __HOSTBOOT_MODULE
/*
 * \@brief Specialized Hash function Template to be inserted with unordered_map
 */
namespace std
{

namespace tr1
{
    template <>
    struct hash<TARGETING::ATTRIBUTE_ID> : public unary_function<
                                            TARGETING::ATTRIBUTE_ID, size_t>
    {
        size_t operator()(const TARGETING::ATTRIBUTE_ID& attrId) const
        {
            return attrId;
        }
    };
}

}
#endif

namespace TARGETING
{

/*
 * \@brief - Data Struct to contain attribute related info
 *
 * Field Description
 * \@field1 - Size: Size of the attribute
 * \@field2 - readWriteable: true if read and writeable else false only readable
 * \@field3 - Persistency level of the attribute
 */
struct attrMetadataStr
{
    uint32_t size;
    bool readWriteable;
    const char* persistency;
    bool noSync;

    attrMetadataStr() :
        size(0), readWriteable(false), persistency(NULL), noSync(false) {}

    attrMetadataStr(uint32_t i_size, bool i_rw, const char* i_persistency, \
        bool i_sync) :
        size(i_size), readWriteable(i_rw), persistency(i_persistency),\
        noSync(i_sync) {}
};

/*
 * \@brief Typedef for struct attrMetadataStr
 */
typedef struct attrMetadataStr AttrMetadataStr;

/*
 * \@brief Typedef for pair<ATTRIBUTE_ID, AttrMetadataStr>
 */
typedef std::pair<ATTRIBUTE_ID, AttrMetadataStr> Pair_t;

#ifndef __HOSTBOOT_MODULE
/*
 * \@brief Typedef std::tr1::unordered_map <attr, struct attrMetadataStr,
 *      hash_method>
 */
typedef std::tr1::unordered_map<ATTRIBUTE_ID, AttrMetadataStr, \
    std::tr1::hash<TARGETING::ATTRIBUTE_ID> > AttrMetadataMapper;
#else
/*
 * \@brief Typedef std::map <attr, struct attrMetadataStr>
 */
typedef std::map<ATTRIBUTE_ID, AttrMetadataStr> AttrMetadataMapper;
#endif

class MapAttrMetadata
{
    public:
        /**
         *  \@brief Destroy the MapAttrMetadata class
         */
        ~MapAttrMetadata();

        /**
         *  \@brief Create the MapAttrMetadata class
         */
        MapAttrMetadata();

        /*
         *  \@brief returns the unordered/ordered map of all attributes as
         *  key and struct attrMetadataStr as value, which contains the size
         *  of the attribute along with read/writeable properties
         *
         *  \@return, returns the unordered/ordered map which has the all
         *  attributes as key and struct attrMetadataStr as value pair,
         *  variable <ATTRIBUTE_ID::struct attrMetadataStr>
         *
         * ******** WARNING ********
         * The attribute information in the map about persistency, synchronization,
         * and read-write for HB-only attributes may be INCORRECT because Hostboot
         * hasn't needed that info yet. If you need it to be correct, edit
         * xmltohb.pl to calculate it correctly.

         */
         const AttrMetadataMapper& getMapMetadataForAllAttributes() const;

     private:

        /* Unordered/Ordered map variable for All Attribute Ids vs Size &
         * Read/Write properties */
        AttrMetadataMapper iv_mapAttrMetadata;

        /* Disable Copy constructor and assignment operator */
        MapAttrMetadata(
            const MapAttrMetadata& i_right);

        MapAttrMetadata& operator = (
            const MapAttrMetadata& i_right);
};

/**
 *  \@brief Provide singleton access to the MapAttrMetadata
 */
TARG_DECLARE_SINGLETON(TARGETING::MapAttrMetadata, theMapAttrMetadata);

#undef TARG_CLASS
#undef TARG_NAMESPACE


}// namespace TARGETING

#endif // MAPATTRMETADATA_H

VERBATIM

}

######
#Create a .C file to put target into the errlog
#####
sub writeTargetErrlCFile {
    my($attributes,$outFile) = @_;

    #First setup the includes and function definition
    print $outFile "#include <stdint.h>\n";
    print $outFile "#include <stdio.h>\n";
    print $outFile "#include <string.h>\n";
    print $outFile "#include <errl/errludtarget.H>\n";
    print $outFile "#include <errl/errlreasoncodes.H>\n";
    print $outFile "#include <targeting/common/target.H>\n";
    print $outFile "#include <targeting/common/targetservice.H>\n";
    print $outFile "#include <targeting/common/trace.H>\n";
    print $outFile "\n";
    print $outFile "namespace ERRORLOG\n";
    print $outFile "{\n";
    print $outFile "using namespace TARGETING;\n";
    print $outFile "extern TARG_TD_t g_trac_errl;\n";

    print $outFile "//------------------------------------------------------------------------------\n";
    print $outFile "ErrlUserDetailsTarget::ErrlUserDetailsTarget(\n";
    print $outFile "    const Target * i_pTarget,\n";
    print $outFile "    const char* i_label)\n";
    print $outFile "{\n";
    print $outFile "    // Set up ErrlUserDetails instance variables\n";
    print $outFile "    iv_CompId = ERRL_COMP_ID;\n";
    print $outFile "    iv_Version = 1;\n";
    print $outFile "    iv_SubSection = ERRL_UDT_TARGET;\n";
    print $outFile "    // override the default of false\n";
    print $outFile "    iv_merge = true;\n";
    print $outFile "\n";
    print $outFile "    uint8_t* label_buf = NULL;\n";
    print $outFile "\n";
    print $outFile "    if (i_pTarget == TARGETING::MASTER_PROCESSOR_CHIP_TARGET_SENTINEL) {\n";
    print $outFile "        label_buf = reallocUsrBuf(sizeof(uint32_t)\n";
    print $outFile "                                +sizeof(TargetLabel_t));\n";
    print $outFile "        uint32_t *pBuffer = reinterpret_cast<uint32_t*>\n";
    print $outFile "          (label_buf+sizeof(TargetLabel_t));\n";
    print $outFile "        // copy 0xFFFFFFFF to indicate MASTER just as gethuid() does\n";
    print $outFile "        *pBuffer = 0xFFFFFFFF;\n";
    print $outFile "    } else {\n";
    print $outFile "        uint32_t bufSize = 0;\n";
    print $outFile "        uint8_t *pTargetString = i_pTarget->targetFFDC(bufSize);\n";
    print $outFile "        label_buf = reallocUsrBuf(bufSize+sizeof(TargetLabel_t));\n";
    print $outFile "        uint8_t* pBuffer = (label_buf+sizeof(TargetLabel_t));\n";
    print $outFile "        memcpy(pBuffer, pTargetString, bufSize);\n";
    print $outFile "        free (pTargetString);\n";
    print $outFile "    }\n";
    print $outFile "\n";
    print $outFile "    // Prepend a label\n";
    print $outFile "    TargetLabel_t label;\n";
    print $outFile "    if( i_label )\n";
    print $outFile "    {\n";
    print $outFile "        strcpy( label.x, i_label );\n";
    print $outFile "    }\n";
    print $outFile "    else // no label, put a generic one in there\n";
    print $outFile "    {\n";
    print $outFile "        strcpy( label.x, \"Target\" );\n";
    print $outFile "    }\n";
    print $outFile "    memcpy( label_buf, &label, sizeof(label) );\n";
    print $outFile "}\n";
    print $outFile "\n";

    print $outFile "\n";

    print $outFile "//------------------------------------------------------------------------------\n";
    print $outFile "ErrlUserDetailsTarget::~ErrlUserDetailsTarget()\n";
    print $outFile "{ }\n";
    print $outFile "} // namespace\n";
} # sub writeTargetErrlCFile


######
#Create a .H file to parse attributes out of the errlog
#####
sub writeTargetErrlHFile {
    my($attributes,$outFile,$pathOutFilePY,$targetOutFilePY) = @_;

    #First setup the includes and function definition
    print $outFile "\n";
    print $outFile "#ifndef ERRL_UDTARGET_H\n";
    print $outFile "#define ERRL_UDTARGET_H\n";
    print $outFile "\n";
    print $outFile "#include <string.h>\n";
    print $outFile "\n";
    print $outFile "namespace ERRORLOG\n";
    print $outFile "{\n";
    print $outFile "typedef struct TargetLabel_t\n";
    print $outFile "{\n";
    print $outFile "    static const uint32_t LABEL_TAG = 0xEEEEEEEE;\n";
    print $outFile "    uint32_t tag;\n";
    print $outFile "    char x[24]; //space to left of divider\n";
    print $outFile "    TargetLabel_t() : tag(0xEEEEEEEE)\n";
    print $outFile "    {\n";
    print $outFile "        memset(x,'\\0',sizeof(x));\n";
    print $outFile "    };\n";
    print $outFile "} TargetLabel_t;\n";
    print $outFile "}\n";
    print $outFile "#if !defined(PARSER) && !defined(LOGPARSER)\n";
    print $outFile "\n";
    print $outFile "#include <errl/errluserdetails.H>\n";
    print $outFile "\n";
    print $outFile "namespace TARGETING // Forward reference\n";
    print $outFile "{ class Target; }\n";
    print $outFile "\n";
    print $outFile "namespace ERRORLOG\n";
    print $outFile "{\n";
    print $outFile "class ErrlUserDetailsTarget : public ErrlUserDetails {\n";
    print $outFile "public:\n";
    print $outFile "\n";
    print $outFile "    ErrlUserDetailsTarget(const TARGETING::Target * i_pTarget,\n";
    print $outFile "                          const char* i_label = NULL);\n";
    print $outFile "    virtual ~ErrlUserDetailsTarget();\n";
    print $outFile "\n";
    print $outFile "private:\n";
    print $outFile "\n";
    print $outFile "    // Disabled\n";
    print $outFile "    ErrlUserDetailsTarget(const ErrlUserDetailsTarget &);\n";
    print $outFile "    ErrlUserDetailsTarget & operator=(const ErrlUserDetailsTarget &);\n";
    print $outFile "};\n";
    print $outFile "}\n";
    print $outFile "#else // if LOGPARSER defined\n";
    print $outFile "\n";
    print $outFile "#include \"errluserdetails.H\"\n";
    print $outFile "#include <string.h>\n";
    print $outFile "\n";
    print $outFile "namespace ERRORLOG\n";
    print $outFile "{\n";

    # local function used by Target and Callout to print the entity path

    print $outFile "  static uint8_t *errlud_parse_entity_path(uint8_t *i_ptr, char *o_ptr)\n";
    print $outFile "  {\n";
    print $outFile "      uint8_t *l_ptr = i_ptr;\n";

    print $outFile "      // from targeting/common/entitypath.[CH]\n";
    print $outFile "      // entityPath is PATH_TYPE:4, NumberOfElements:4,\n";
    print $outFile "      //          [Element, Instance#]\n";
    print $outFile "      // PATH_TYPE\n";
    print $outFile "      const char *pathString;\n";
    print $outFile "      const uint8_t pathTypeLength = *l_ptr;\n";
    print $outFile "      l_ptr++;\n";
    print $outFile "      const uint8_t pathType = (pathTypeLength & 0xF0) >> 4;\n";
    print $outFile "      switch (pathType) {\n";
    print $outFile "          case 0x01: pathString = \"Logical:\"; break;\n";
    print $outFile "          case 0x02: pathString = \"Physical:\"; break;\n";
    print $outFile "          case 0x03: pathString = \"Device:\"; break;\n";
    print $outFile "          case 0x04: pathString = \"Power:\"; break;\n";
    print $outFile "          default:   pathString = \"Unknown:\"; break;\n";
    print $outFile "      }\n";
    print $outFile "      uint32_t dataSize = sprintf(o_ptr, \"%s\",pathString);\n";
    print $outFile "      const uint8_t pathSize = (pathTypeLength & 0x0F) * 2;\n";
    print $outFile "      uint8_t *lElementInstance = l_ptr;\n";
    print $outFile "      l_ptr += pathSize * sizeof(uint8_t);\n";
    print $outFile "      for (uint32_t j=0;j<pathSize;j += 2) {\n";
    print $outFile "          switch (lElementInstance[j]) {\n";

    # Python version of local function used by Target and Callout to print the entity path

    print $pathOutFilePY "# The content of this file, entityPath.py, is automatically\n";
    print $pathOutFilePY "# generated by src/usr/targeting/common/xmltohb/xmltohb.pl and output to\n";
    print $pathOutFilePY "# obj/genfiles/errl/entityPath.py.\n\n";

    print $pathOutFilePY "# At this time, the generated file must be manually copied from the\n";
    print $pathOutFilePY "# obj/genfiles/errl directory to the src/build/tools/ebmc directory and\n";
    print $pathOutFilePY "# then manually checked in to be picked up by the Hostboot build.\n\n";

    print $pathOutFilePY "# To pull the parser change into a BMC image, update the commit pointer in the\n";
    print $pathOutFilePY "# openbmc project's meta-openpower/recipes-phosphor/logging/hostboot-pel-parsers_git.bb\n";
    print $pathOutFilePY "# file to reference the Hostboot commit with the change.\n\n";

    print $pathOutFilePY "\"\"\" Creates the entity path for the given data\n";
    print $pathOutFilePY "Function is used by ErrlUserDetailsParserCallout and\n";
    print $pathOutFilePY "ErrlUserDetailsParserTarget in b0100.py\n\n";
    print $pathOutFilePY "\@param[in] data: memoryview object to get the data from\n";
    print $pathOutFilePY "\@param[in] start: starting index of data to use for entity path\n";
    print $pathOutFilePY "\@returns: a string of the entity path, and the offset value for the data following\n";
    print $pathOutFilePY "          the entity path data\n";
    print $pathOutFilePY "\"\"\"\n";
    print $pathOutFilePY "def errlud_parse_entity_path(data, start):\n";
    print $pathOutFilePY "    pathType = { 0x01: \"Logical:\",\n";
    print $pathOutFilePY "                 0x02: \"Physical:\",\n";
    print $pathOutFilePY "                 0x03: \"Device:\",\n";
    print $pathOutFilePY "                 0x04: \"Power:\" }\n\n";
    print $pathOutFilePY "    elementInstance = {\n";

    foreach my $enumerationType (@{$attributes->{enumerationType}})
    {
      if( $enumerationType->{id} eq "TYPE" ) {
        foreach my $enumerator (@{$enumerationType->{enumerator}})
        {
            my $enumHex = sprintf "0x%02X",
                enumNameToValue($enumerationType,$enumerator->{name});
            #my $enumName = $enumerationType->{id} . "_" . $enumerator->{name};
            my $enumName = $enumerator->{name};
            if ($enumName eq "SYS") {
                $enumName = "Sys";
            } elsif ($enumName eq "PROC") {
                $enumName = "Proc";
            } elsif ($enumName eq "NODE") {
                $enumName = "Node";
            } elsif ($enumName eq "CORE") {
                $enumName = "Core";
            } elsif ($enumName eq "MEMBUF") {
                $enumName = "Membuf";
            }
            print $outFile "              case $enumHex: { pathString = \"/$enumName\"; break; }\n";
            print $pathOutFilePY "                        $enumHex: \"/$enumName\",\n";
        }
      }
    } # enumerationType
    print $outFile "              default:   { pathString = \"/UKNOWN\"; break; }\n";

    print $outFile "          } // switch\n";
    print $outFile "          // copy next part in, overwritting previous terminator\n";
    print $outFile "          dataSize += sprintf(o_ptr + dataSize,\n";
    print $outFile "                              \"%s%d\", pathString,\n";
    print $outFile "                              lElementInstance[j+1]);\n";
    print $outFile "      } // for\n";
    print $outFile "      return l_ptr;\n";
    print $outFile "} // errlud_parse_entity_path \n";

    print $pathOutFilePY "                      }\n\n";
    print $pathOutFilePY "    # Entity Path Layout\n";
    print $pathOutFilePY "    # 1 byte  : PATH_TYPE:4, NumberOfElements:4\n";
    print $pathOutFilePY "    # N number of [Element, Instance#] pairs\n";
    print $pathOutFilePY "    # 1 byte  : Element\n";
    print $pathOutFilePY "    # 1 byte  : Instance #\n";
    print $pathOutFilePY "    #\n";
    print $pathOutFilePY "    # Output is PathType:/ElementInstance#/ElementInstance#/ElementInstance#\n";
    print $pathOutFilePY "    pathTypeLength = data[start]\n";
    print $pathOutFilePY "    start+=1\n\n";
    print $pathOutFilePY "    pathString = pathType.get((pathTypeLength & 0xF0) >> 4, \"Unknown:\")\n";
    print $pathOutFilePY "    pathSize = (pathTypeLength & 0x0F) * 2\n\n";
    print $pathOutFilePY "    for x in range(0, pathSize, 2):\n";
    print $pathOutFilePY "        pathString += elementInstance.get(data[start], \"/UNKNOWN\")\n";
    print $pathOutFilePY "        start += 1\n";
    print $pathOutFilePY "        pathString += str(data[start])\n";
    print $pathOutFilePY "        start += 1\n\n";
    print $pathOutFilePY "    return pathString, start\n";


    print $outFile "class ErrlUserDetailsParserTarget : public ErrlUserDetailsParser {\n";
    print $outFile "public:\n";
    print $outFile "\n";
    print $outFile "    ErrlUserDetailsParserTarget() {}\n";
    print $outFile "\n";
    print $outFile "    virtual ~ErrlUserDetailsParserTarget() {}\n";
    print $outFile "/**\n";
    print $outFile " *  \@brief Parses Target user detail data from an error log\n";
    print $outFile " *  \@param  i_version Version of the data\n";
    print $outFile " *  \@param  i_parse   ErrlUsrParser object for outputting information\n";
    print $outFile " *  \@param  i_pBuffer Pointer to buffer containing detail data\n";
    print $outFile " *  \@param  i_buflen  Length of the buffer\n";
    print $outFile " */\n";
    print $outFile "  virtual void parse(errlver_t i_version,\n";
    print $outFile "                        ErrlUsrParser & i_parser,\n";
    print $outFile "                        void * i_pBuffer,\n";
    print $outFile "                        const uint32_t i_buflen) const\n";
    print $outFile "  {\n";
    print $outFile "    const char *attrData;\n";
    print $outFile "    char l_label[24];\n";
    print $outFile "    sprintf(l_label,\"Target\");\n";
    print $outFile "    uint32_t *l_ptr32 = reinterpret_cast<uint32_t *>(i_pBuffer);\n";
    print $outFile "    // while there is still at least 1 word of data left\n";
    print $outFile "    for (; (l_ptr32 + 1) <= (uint32_t *)((uint8_t*)i_pBuffer + i_buflen); )\n";
    print $outFile "    {\n";
    print $outFile "      if (*l_ptr32 == 0xFFFFFFFF) { // special - master\n";
    print $outFile "        i_parser.PrintString(\"Target\", \"MASTER_PROCESSOR_CHIP_TARGET_SENTINEL\");\n";
    print $outFile "        l_ptr32++; // past the marker\n";
    print $outFile "      } else if (*l_ptr32 == TargetLabel_t::LABEL_TAG) {\n";
    print $outFile "        TargetLabel_t* tmp_label = reinterpret_cast<TargetLabel_t*>(l_ptr32);\n";
    print $outFile "        memcpy( l_label, tmp_label->x, sizeof(l_label)-1 );\n";
    print $outFile "        l_ptr32 += (sizeof(TargetLabel_t)/sizeof(uint32_t));\n";
    print $outFile "      } else { \n";

    print $outFile "        // first 4 are always the same\n";
    print $outFile "        if ((l_ptr32 + 4) <= (uint32_t *)((uint8_t*)i_pBuffer + i_buflen)) {\n";
    print $outFile "            i_parser.PrintNumber( l_label, \"HUID = 0x%08X\", ntohl(UINT32_FROM_PTR(l_ptr32)) );\n";
    print $outFile "            l_ptr32++;\n";

    print $targetOutFilePY "# The content of this file, errludtarget.py, is automatically\n";
    print $targetOutFilePY "# generated by src/usr/targeting/common/xmltohb/xmltohb.pl and output to\n";
    print $targetOutFilePY "# obj/genfiles/errl/errludtarget.py.\n\n";

    print $targetOutFilePY "# At this time, the generated file must be manually copied from the\n";
    print $targetOutFilePY "# obj/genfiles/errl directory to the src/usr/errl/plugins/ebmc/b0100 directory and\n";
    print $targetOutFilePY "# then manually checked in to be picked up by the Hostboot build.\n\n";

    print $targetOutFilePY "# To pull the parser change into a BMC image, update the commit pointer in the\n";
    print $targetOutFilePY "# openbmc project's meta-openpower/recipes-phosphor/logging/hostboot-pel-parsers_git.bb\n";
    print $targetOutFilePY "# file to reference the Hostboot commit with the change.\n\n";

    print $targetOutFilePY "import json\n";
    print $targetOutFilePY "from udparsers.helpers.errludP_Helpers import hexConcat, intConcat, findNull, strConcat\n";
    print $targetOutFilePY "from udparsers.helpers.entityPath import errlud_parse_entity_path\n\n";
    print $targetOutFilePY "\"\"\" User Details Parser Target called by b0100.py\n\n";
    print $targetOutFilePY "\@param[in] ver: int value of subsection version\n";
    print $targetOutFilePY "\@param[in] data: memoryview object of data to be parsed\n";
    print $targetOutFilePY "\@returns: JSON string of parsed data\n";
    print $targetOutFilePY "\"\"\"\n";
    print $targetOutFilePY "def ErrlUserDetailsParserTarget(ver, data):\n";
    print $targetOutFilePY "    LABEL_TAG = 0xEEEEEEEE\n";
    print $targetOutFilePY "    MASTER_LABEL_TAG = 0xFFFFFFFF\n";

    print $targetOutFilePY "    i = 0\n\n";
    print $targetOutFilePY "    attrClass = {\n";

    # find CLASS
    print $outFile "            switch (ntohl(UINT32_FROM_PTR(l_ptr32))) { // CLASS\n";
    foreach my $enumerationType (@{$attributes->{enumerationType}})
    {
      if( $enumerationType->{id} eq "CLASS" ) {
        foreach my $enumerator (@{$enumerationType->{enumerator}})
        {
            my $enumHex = sprintf "0x%02X",
                enumNameToValue($enumerationType,$enumerator->{name});
            my $enumName = $enumerationType->{id} . "_" . $enumerator->{name};
            print $outFile "                case $enumHex: { attrData = \"$enumName\"; break; }\n";

            print $targetOutFilePY "                  $enumHex: \"$enumName\",\n";
        }
      }
    } # enumerationType
    print $outFile "                default:   { attrData = \"UNKNOWN_CLASS\"; break; }\n";
    print $outFile "            } // switch\n";
    print $outFile "            i_parser.PrintString(\"  ATTR_CLASS\", attrData);\n";
    print $outFile "            l_ptr32++;\n";

    print $targetOutFilePY "                }\n\n";
    print $targetOutFilePY "    attrType = {\n";

    # find TYPE
    print $outFile "            switch (ntohl(UINT32_FROM_PTR(l_ptr32))) { // TYPE\n";
    foreach my $enumerationType (@{$attributes->{enumerationType}})
    {
      if( $enumerationType->{id} eq "TYPE" ) {
        foreach my $enumerator (@{$enumerationType->{enumerator}})
        {
            my $enumHex = sprintf "0x%02X",
                enumNameToValue($enumerationType,$enumerator->{name});
            my $enumName = $enumerationType->{id} . "_" . $enumerator->{name};
            print $outFile "                case $enumHex: { attrData = \"$enumName\"; break; }\n";

            print $targetOutFilePY "                 $enumHex: \"$enumName\",\n";
        }
      }
    } # enumerationType
    print $outFile "                default:   { attrData = \"UNKNOWN_TYPE\"; break; }\n";
    print $outFile "            } // switch\n";
    print $outFile "            i_parser.PrintString(\"  ATTR_TYPE\", attrData);\n";
    print $outFile "            l_ptr32++;\n";

    print $targetOutFilePY "                }\n\n";
    print $targetOutFilePY "    attrModel = {\n";

    # find MODEL
    print $outFile "            switch (ntohl(UINT32_FROM_PTR(l_ptr32))) { // MODEL\n";
    foreach my $enumerationType (@{$attributes->{enumerationType}})
    {
      if( $enumerationType->{id} eq "MODEL" ) {
        foreach my $enumerator (@{$enumerationType->{enumerator}})
        {
            my $enumHex = sprintf "0x%02X",
                enumNameToValue($enumerationType,$enumerator->{name});
            my $enumName = $enumerationType->{id} . "_" . $enumerator->{name};
            print $outFile "                case $enumHex: { attrData = \"$enumName\"; break; }\n";
            print $targetOutFilePY "                  $enumHex: \"$enumName\",\n";
        }
      }
    } # enumerationType
    print $outFile "                default:   { attrData = \"UNKNOWN_MODEL\"; break; }\n";
    print $outFile "            } // switch\n";
    print $outFile "            i_parser.PrintString(\"  ATTR_MODEL\", attrData);\n";
    print $outFile "            l_ptr32++;\n";
    print $outFile "            // 2 Entity Paths next\n";
    print $outFile "            for (uint32_t k = 0;k < 2; k++)\n";
    print $outFile "            {\n";

    my $attrPhysPath;
    my $attrAffinityPath;

    # need the attribute id's for ATTR_PHYS_PATH and ATTR_AFFINITY_PATH:
    my $attributeIdEnumeration = getAttributeIdEnumeration($attributes);
    foreach my $enumerator (@{$attributeIdEnumeration->{enumerator}})
    {
        if ($enumerator->{name} eq "PHYS_PATH")
        {
            $attrPhysPath = $enumerator->{value};
        }
        elsif ($enumerator->{name} eq "AFFINITY_PATH")
        {
            $attrAffinityPath = $enumerator->{value};
        }
    }

    print $targetOutFilePY "                }\n\n";
    print $targetOutFilePY "    label = \"Target\"\n";
    print $targetOutFilePY "    dictArray = []\n";
    print $targetOutFilePY "    while (i+4) <= len(data):\n";
    print $targetOutFilePY "        subd = dict()\n";
    print $targetOutFilePY "        word, i=intConcat(data, i, i+4)\n";
    print $targetOutFilePY "        if word == MASTER_LABEL_TAG:\n";
    print $targetOutFilePY "            subd[\"Target\"]=\"MASTER_PROCESSOR_CHIP_TARGET_SENTINEL\"\n";
    print $targetOutFilePY "        elif word == LABEL_TAG:\n";
    print $targetOutFilePY "            # Data Layout\n";
    print $targetOutFilePY "            #  4 bytes  : Label Tag (word)\n";
    print $targetOutFilePY "            # 24 bytes  : Label\n\n";
    print $targetOutFilePY "            label=strConcat(data, i, findNull(data, i, i+24))[0]\n";
    print $targetOutFilePY "            i += 24 #skip over any trailing null chars\n";
    print $targetOutFilePY "        else:\n";
    print $targetOutFilePY "            if i+(4*4) <= len(data):\n";
    print $targetOutFilePY "                # Data Layout\n";
    print $targetOutFilePY "                # 4 bytes  : HUID (word)\n";
    print $targetOutFilePY "                # 4 bytes  : Class\n";
    print $targetOutFilePY "                # 4 bytes  : Type\n";
    print $targetOutFilePY "                # 4 bytes  : Model\n";
    print $targetOutFilePY "                # N bytes  : Entity Path 1\n";
    print $targetOutFilePY "                # N bytes  : Entity Path 2\n\n";
    print $targetOutFilePY "                subd[label]=\"HUID = \" + f\'0x{word:08X}\'\n";
    print $targetOutFilePY "                subd[\"  ATTR_CLASS\"]=attrClass.get(intConcat(data, i, i+4)[0], \"UNKNOWN_CLASS\")\n";
    print $targetOutFilePY "                i += 4\n";
    print $targetOutFilePY "                subd[\"  ATTR_TYPE\"]=attrType.get(intConcat(data, i, i+4)[0], \"UNKNOWN_TYPE\")\n";
    print $targetOutFilePY "                i += 4\n";
    print $targetOutFilePY "                subd[\"  ATTR_MODEL\"]=attrModel.get(intConcat(data, i, i+4)[0], \"UNKNOWN_MODEL\")\n";
    print $targetOutFilePY "                i += 4\n";
    print $targetOutFilePY "                for x in range(2):\n";
    print $targetOutFilePY "                    pathType,i=intConcat(data, i, i+4)\n";
    print $targetOutFilePY "                    if (pathType == $attrPhysPath or #ATTR_PHYS_PATH\n";
    print $targetOutFilePY "                        pathType == $attrAffinityPath): #ATTR_AFFINITY_PATH\n";
    print $targetOutFilePY "                        outString, i=errlud_parse_entity_path(data, i)\n";
    print $targetOutFilePY "                        if pathType == $attrPhysPath:\n";
    print $targetOutFilePY "                            subd[\"  ATTR_PHYS_PATH\"]=outString\n";
    print $targetOutFilePY "                        if pathType == $attrAffinityPath:\n";
    print $targetOutFilePY "                            subd[\"  ATTR_AFFINITY_PATH\"]=outString\n";
    print $targetOutFilePY "            dictArray.append(subd)\n";
    print $targetOutFilePY "    jsonStr = json.dumps(dictArray)\n";
    print $targetOutFilePY "    return jsonStr\n";

    print $outFile "                uint32_t l_pathType = ntohl(UINT32_FROM_PTR(l_ptr32));\n";
    print $outFile "                if ((l_pathType == $attrPhysPath) || // ATTR_PHYS_PATH\n";
    print $outFile "                    (l_pathType == $attrAffinityPath))   // ATTR_AFFINITY_PATH\n";
    print $outFile "                {\n";
    print $outFile "                    l_ptr32++;\n";
    print $outFile "                    uint8_t *l_ptr = reinterpret_cast<uint8_t *>(l_ptr32);\n";
    print $outFile "                    char outString[128];\n";
    print $outFile "                    l_ptr = errlud_parse_entity_path(l_ptr,outString);\n";
    print $outFile "                    if (l_pathType == $attrPhysPath)\n";
    print $outFile "                    {\n";
    print $outFile "                      i_parser.PrintString(\"  ATTR_PHYS_PATH\", outString);\n";
    print $outFile "                    }\n";
    print $outFile "                    if (l_pathType == $attrAffinityPath)\n";
    print $outFile "                    {\n";
    print $outFile "                      i_parser.PrintString(\"  ATTR_AFFINITY_PATH\", outString);\n";
    print $outFile "                    } // else don't print anything\n";
    print $outFile "                    l_ptr32 = reinterpret_cast<uint32_t *>(l_ptr);\n";
    print $outFile "                } else {\n";
    print $outFile "                    l_ptr32++;\n";
    print $outFile "                }\n";
    print $outFile "            } // for\n";
    print $outFile "        } // if\n";
    print $outFile "      }\n";
    print $outFile "    } // for\n";
    print $outFile "  } // parse()\n\n";
    print $outFile "private:\n";
    print $outFile "\n";
    print $outFile "// Disabled\n";
    print $outFile "ErrlUserDetailsParserTarget(const ErrlUserDetailsParserTarget &);\n";
    print $outFile "ErrlUserDetailsParserTarget & operator=(const ErrlUserDetailsParserTarget &);\n";
    print $outFile "};\n";
    print $outFile "} // namespace\n";
    print $outFile "#endif\n";
    print $outFile "#endif\n";
} # sub writeTargetErrlHFile

################################################################################
# Writes the map system attr size C file header
################################################################################

sub writeAttrSizeMapCFileHeader {
    my($outFile) = @_;

print $outFile <<VERBATIM;

/**
 *  \@file mapsystemattrsize.C
 *
 *  \@brief Interface to get the map of system target attributes with respective
 *  attribute size
 */

// STD
#include <map>

// TARG
#include <mapsystemattrsize.H>


//******************************************************************************
// Macros
//******************************************************************************

#undef TARG_NAMESPACE
#undef TARG_CLASS
#undef TARG_FUNC

//******************************************************************************
// Implementation
//******************************************************************************

namespace TARGETING
{


#define TARG_NAMESPACE "TARGETING::"
#define TARG_CLASS "MapSystemAttrSize::"

//******************************************************************************
// TARGETING::mapSystemAttrSize
//******************************************************************************

TARGETING::MapSystemAttrSize& mapSystemAttrSize()
{
    #define TARG_FN "mapSystemAttrSize()"

    return TARG_GET_SINGLETON(TARGETING::theMapSystemAttrSize);

    #undef TARG_FN
}

//******************************************************************************
// TARGETING::MapSystemAttrSize::~MapSystemAttrSize
//******************************************************************************

MapSystemAttrSize::~MapSystemAttrSize()
{
    #define TARG_FN "~MapSystemAttrSize()"
    #undef TARG_FN
}

//******************************************************************************
// TARGETING::MapSystemAttrSize::getMapForWriteableSystemAttributes
//******************************************************************************

const AttrSizeMapper&
MapSystemAttrSize::getMapForWriteableSystemAttributes() const
{
    #define TARG_FN "getMapForWriteableSystemAttributes()"
    TARG_ENTER();

    TARG_EXIT();
    return iv_mapSysAttrSize;

    #undef TARG_FN
}

//******************************************************************************
// TARGETING::MapSystemAttrSize::MapSystemAttrSize
//******************************************************************************

MapSystemAttrSize::MapSystemAttrSize()
{
    #define TARG_FN "MapSystemAttrSize()"
VERBATIM

}

######
# Create a .C file to put System Target Attributes along with their respective
# Size in a map file
######
sub writeAttrSizeMapCFile{
    my($attributes,$outFile) = @_;
    my %finalAttrhash = ();

    # look for type sys-sys-power8 and store all attributes associated
    foreach my $targetType (@{$attributes->{targetType}})
    {
        if($targetType->{id} =~ m/^sys-sys-/)
        {
            my %attrhash = ();
            getTargetAttributes($targetType->{id}, $attributes,\%attrhash);
            foreach my $key ( keys %attrhash )
            {
                foreach my $attr (@{$attributes->{attribute}})
                {
                    if($attr->{id} eq $key)
                    {
                        if((exists $attr->{writeable}) &&
                            (!(exists $attr->{hbOnly})))
                        {
                            # we have the attr here.. calculate the size
                            my $keyVal = "ATTR_"."$key"."_type";
                            if( (exists $attr->{simpleType}) ||
                                (exists $attr->{complexType}) ||
                                (exists $attr->{nativeType}) )
                            {
                                $finalAttrhash{$key} = $keyVal;
                            }
                            else
                            {
                                print STDOUT "\t// Attribute $key is writable "
                                    . "& Not Supported \n";
                            }
                        }
                    }
                }
            }
        }
    }
    print $outFile "\n";
    foreach my $key ( keys %finalAttrhash)
    {
        print $outFile "    iv_mapSysAttrSize[ATTR_"
            . "$key] = sizeof($finalAttrhash{$key});\n";
    }
    print $outFile "\n";
}

################################################################################
# Writes the map system attr size C file Footer
################################################################################

sub writeAttrSizeMapCFileFooter {
    my($outFile) = @_;

    print $outFile <<VERBATIM;
    #undef TARG_FN
}

}// namespace TARGETING

VERBATIM
}

######
# Create a .H file to put System Target Attributes along with their respective
# Size in a map file
######
sub writeAttrSizeMapHFile{
    my($outFile) = @_;
    print $outFile <<VERBATIM;

#ifndef MAPSYSTEMATTRSIZE_H
#define MAPSYSTEMATTRSIZE_H

/**
 *  \@file mapsystemattrsize.H
 *
 *  \@brief Interface to get the map of system target attributes with respective
 *  attribute size
 */

// STD
#include <map>

// TARG
#include <targeting/common/trace.H>
#include <targeting/common/target.H>

//******************************************************************************
// Macros
//******************************************************************************

#undef TARG_NAMESPACE
#undef TARG_CLASS
#undef TARG_FUNC

//******************************************************************************
// Interface
//******************************************************************************

namespace TARGETING
{

class MapSystemAttrSize;

/**
 *  \@brief Return the MapSystemAttrSize singleton instance
 *
 *  \@return Reference to the MapSystemAttrSize singleton
 */
TARGETING::MapSystemAttrSize& mapSystemAttrSize();


#define TARG_NAMESPACE "MAPSYSTEMATTRSIZE::"

#define TARG_CLASS "MapSystemAttrSize::"

/*
 * \@brief Typedef map <attr, attSize>
 */
typedef std::map<ATTRIBUTE_ID, uint32_t> AttrSizeMapper;

class MapSystemAttrSize
{

    public:
        /**
         *  \@brief Destroy the MapSystemAttrSize class
         */
        ~MapSystemAttrSize();

        /**
         *  \@brief Create the MapSystemAttrSize class
         */
        MapSystemAttrSize();

        /*
         *  \@brief returns the map of Writeable System attributes as Key and
         *  size of the attributes as value.
         *
         *  \@return, returns the map which has the Writeable Sytem attributes
         *  as key and size as value pair, variable <SYSTEM_ATTRIBUTE_ID::Size>
         */
         const AttrSizeMapper& getMapForWriteableSystemAttributes() const;

     private:

        /* Map variable for System Attribute Ids Vs the Size */
        AttrSizeMapper iv_mapSysAttrSize;

        /* Disable Copy constructor and assignment operator */
        MapSystemAttrSize(
            const MapSystemAttrSize& i_right);

        MapSystemAttrSize& operator = (
            const MapSystemAttrSize& i_right);
};

/**
 *  \@brief Provide singleton access to the MapSystemAttrSize
 */
TARG_DECLARE_SINGLETON(TARGETING::MapSystemAttrSize, theMapSystemAttrSize);

#undef TARG_CLASS
#undef TARG_NAMESPACE


}// namespace TARGETING

#endif // MAPSYSTEMATTRSIZE_H

VERBATIM

}

sub UTILITY_FUNCTIONS { }

################################################################################
# Get the hash hex string for an attribute name (ID).
################################################################################
sub getAttributeIdHashStr
{
    my ($attrId) = @_;
    return substr(md5_hex($attrId),0,7);
}

################################################################################
# Get generated enumeration describing attribute IDs
################################################################################

sub getAttributeIdEnumeration {
  my($attributes) = @_;

    my $attributeValue = 1;
    my $enumeration = { } ;
    my %attrValHash;
    my $env_chip = $ENV{'CHIP'};

    # add the N/A value
    $enumeration->{description} = "Internal enum for attribute IDs\n";
    $enumeration->{default} = "NA";
    $enumeration->{enumerator}->[0]->{name} = "NA";
    $enumeration->{enumerator}->[0]->{value} = 0;

    foreach my $attribute (@{$attributes->{attribute}})
    {
        my $attributeHexVal28bit = getAttributeIdHashStr($attribute->{id});

        # check if this Id has already been processed
        if(exists($attrValHash{$attributeHexVal28bit}))
        {
            # fatal error if multiple IDs hash to same value
            if ( $attribute->{id} ne $attrValHash{$attributeHexVal28bit} )
            {
               croak(
                 "Error:Duplicate AttributeId hashvalue for $attribute->{id} "
                     . "and $attrValHash{$attributeHexVal28bit}");
            }
            # fatal error if attribute has been defined more than once.
            # Could be defined twice in same file or defined in two files
            # that have been merged, such as attributes_types.xml and
            # attribute_types_hb.xml or attributes_types_fsp.
            else
            {
                croak("Error: AttributeId $attribute->{id} "
                    . "defined multiple times\n\n");
            }
        }
        else
        {
            # add the name here so we can check for duplicate names
            $attrValHash{$attributeHexVal28bit}= $attribute->{id};

            $enumeration->{enumerator}->[$attributeValue]->{name}
            = $attribute->{id};
            $enumeration->{enumerator}->[$attributeValue]->{value}
            = sprintf "0x%s",$attributeHexVal28bit;
            $attribute->{value} = $attributeValue;
            $attributeValue++;
        }
    }

    return $enumeration;
}

################################################################################
# If value is hex, convert to regular number
###############################################################################

sub unhexify {
    my($val) = @_;
    if($val =~ m/^0[xX][01234567890A-Fa-f]+$/)
    {
        $val = hex($val);
    }
    return $val;
}

################################################################################
# Pack mutex
################################################################################

sub packMutex {
    my $length = 24;
    my $binaryData .= pack ("C".$length);

    return $binaryData;
}

################################################################################
# Pack 8 byte value into a buffer using configured endianness
################################################################################

sub pack8byte {
    my($quad) = @_;

    my $value = unhexify($quad);
    my $binaryData;
    if($cfgBigEndian)
    {
        $binaryData = pack("NN" , (($value >> 32) & 0xFFFFFFFF),
                                    ($value & 0xFFFFFFFF));
    }
    else # Little endian
    {
        # Invert the words, then reverse them individually
        $binaryData = pack("VV" , ($value & 0xFFFFFFFF),
                                     (($value >> 32) & 0xFFFFFFFF));
    }

    return $binaryData;
}

sub pack64bitsDecimal {
    my($quad) = @_;

    my $package = unpack("H*", pack8byte($quad));
    if(!$cfgBigEndian)
    {
        my $val1 = sprintf("%08x", ((hex($package) >> 32)  & 0xFFFFFFFF));
        my $val2 = sprintf("%08x", (hex($package) & 0xFFFFFFFF));
        $package = $val1.$val2;
    }
    return hex($package);
}


################################################################################
# Pack 4 byte value into a buffer using configured endianness
################################################################################

sub pack4byte {
    my($value) = @_;

    my $binaryData;
    if($cfgBigEndian)
    {
        $binaryData = pack("N",$value);
    }
    else # Little endian
    {
        $binaryData = pack("V",$value);
    }

    return $binaryData;
}

################################################################################
# Pack 2 byte value into a buffer using configured endianness
################################################################################

sub pack2byte {
    my($value) = @_;

    my $binaryData;
    if($cfgBigEndian)
    {
        $binaryData = pack("n",$value);
    }
    else # Little endian
    {
        $binaryData = pack("v",$value);
    }

    return $binaryData;
}

################################################################################
# Pack 1 byte value into a buffer using configured endianness
################################################################################

sub pack1byte {
    my($value) = @_;

    my $binaryData = pack("C",$value);

    return $binaryData;
}

################################################################################
# Pack string into buffer
################################################################################

sub packString{
    my($value,$attribute) = @_;

    # Proper attribute tags already verified, no need to do checking again
    my $sizeInclNull = $attribute->{simpleType}->{string}->{sizeInclNull};

    # print "String content (before fixup) is [$value]\n";

    # For sanity, remove all white space from front and end of string
    $value =~ s/^\s+//g;
    $value =~ s/\s+$//g;

    my $length = length($value);

    # print "String content (after fixup) is [$value]\n";
    # print "String length is $length\n";
    # print "String container size is $sizeInclNull\n";

    if(($length + 1) > $sizeInclNull)
    {
        croak("ERROR: Supplied string exceeds allows length");
    }

    return pack("Z$sizeInclNull",$value);
}

################################################################################
# Get space required to store an enum, based on the max value
################################################################################

sub enumSpace {
    my($maxEnumVal) = @_;
    if($maxEnumVal == 0)
    {
        # Enum needs at least one byte
        $maxEnumVal++;
    }

    # NOTE: Pass --noshort-enums command line option to force the code generator
    # to generate 4-byte enums instead of optimized enums.  Note there are a few
    # enumerations (primarily in PNOR header, etc.) that do not change size.
    # That is intentional in order to make this the single point of control over
    # binary compatibility.  Note that both FSP and Hostboot should always have
    # this policy in sync.  Also note that when Hostboot and FSP use optimized
    # enums, they must also be compiled with -fshort-enums compile option

    my $space = ($cfgShortEnums == 1) ?
        ceil(log($maxEnumVal+1) / (8 * log(2))) : 4;

    return $space;
}

################################################################################
# Get mininum # of bytes, in block size chunks, able to contain the input data
################################################################################

sub sizeBlockAligned {
    my ($size,$blockSize,$oneBlockMinimum) = @_;

    if( (!defined $size)
       || (!defined $blockSize)
       || (!defined $oneBlockMinimum) )
    {
        croak("Caller must specify 'size', 'blockSize', 'oneBlockMinimum' "
            . "args.");
    }

    if(!$blockSize)
    {
        croak("'blockSize' arg must be > 0.");
    }

    if(($size % $blockSize) || (($size==0) && $oneBlockMinimum) )
    {
        $size += ($blockSize - ($size % $blockSize));
    }

    return $size;
}

################################################################################
# Strips off leading and trailing whitespace from a string and returns it
################################################################################

sub stripLeadingAndTrailingWhitespace {
    my($string) = @_;

    $string =~ s/^\s+|\s+$//g;

    return $string;
}

################################################################################
# Optimize white space for C++/doxygen documentation
################################################################################

sub optWhiteSpace {
    my($text) = @_;

    # Remove leading, trailing white space, then collapse excess internal
    # whitespace
    $text =~ s/^\s+|\s+$//g;
    $text =~ s/\s+/ /g;

    return $text;
}

################################################################################
# Wrap text into a C++/doxygen brief description
################################################################################

sub wrapBrief {
    my($text) = @_;

    my $brief_start      = " *  \@brief ";
    my $brief_continue   = " *      ";

    return wrap($brief_start,$brief_continue, optWhiteSpace($text))."\n";
}

################################################################################
# Wrap text into a C++ style comment
################################################################################

sub wrapComment {
    my($text) = @_;

    my $comment_start    = "    // ";
    my $comment_continue = "    // ";

    return wrap($comment_start,$comment_continue,optWhiteSpace($text))."\n";
}

################################################################################
# Calculate struct type name for a header file, based on its ID
################################################################################

sub calculateStructName {
    my($id) = @_;

    my $type = "";

    # Struct name is original ID with underscores removed and first letter of
    # each word capitalized
    my @words = split(/_/,$id);
    foreach my $word (@words)
    {
        $type .= ucfirst( lc($word) );
    }

    return $type;
}

################################################################################
# Return array containing only distinct target types that are actally in use
################################################################################

sub getInstantiatedTargetTypes {
    my($attributes) = @_;

    my %seen = ();
    my @uniqueTargetTypes = ();
    my $targetCount = 0;
    my $moveSysTarget = 0;

    # To simplify the iterator code, always move a system target that appears as
    # the first target to the next position
    foreach my $targetInstance (@{$attributes->{targetInstance}})
    {
        if(($targetInstance->{type} =~ m/^sys-sys-/) && ($targetCount == 0))
        {
            $targetCount = $targetCount + 1;
            $moveSysTarget = 1;
        }
        push (@uniqueTargetTypes, $targetInstance->{type})
            unless $seen{$targetInstance->{type}}++;
    }
    if($moveSysTarget == 1)
    {
        @uniqueTargetTypes[0,1] = @uniqueTargetTypes[1,0];
    }
    return @uniqueTargetTypes;
}

################################################################################
# Return default value of zero for an attribute which is a POD numerical type
################################################################################

sub defaultZero {
    my($attributes,$typeInstance) = @_;

    # print STDOUT "Attribute's default value is 0\n";

    return 0;
}

################################################################################
# Return string default (empty string)
################################################################################

sub defaultString {
    my($attributes,$typeInstance) = @_;

    return "";
}

################################################################################
# Return default value for an attribute whose type is 'enumeration'
################################################################################

sub defaultEnum {
    my($attributes,$enumerationInstance) = @_;

    my $enumerationType = getEnumerationType(
        $attributes,$enumerationInstance->{id});

    # print STDOUT "Attribute enumeration's " .
    #    "(\"$enumerationType->{id}\") default is: " .
    #        $enumerationType->{default} . "\n";

    return $enumerationType->{default};
}

################################################################################
# Do nothing
################################################################################

sub null {

}

################################################################################
# Enforce special fsp mutex restrictions
################################################################################

sub enforceFspMutex {
    my($attribute,$value) = @_;

    if($value != 0)
    {
        croak("FSP mutex attribute default must always be 0, "
              . "was $value instead.");
    }

    if($attribute->{persistency} ne "volatile-zeroed")
    {
        croak("FSP mutex attribute persistency must be volatile-zeroed, "
              . "was $attribute->{persistency} instead");
    }
}

################################################################################
# Enforce special host boot mutex restrictions
################################################################################

sub enforceHbMutex {
    my($attribute,$value) = @_;

    if($value != 0)
    {
        croak("HB mutex attribute default must always be 0, "
              . "was $value instead.");
    }

    if($attribute->{persistency} ne "volatile-zeroed")
    {
        croak("HB mutex attribute persistency must be volatile-zeroed, "
              . "was $attribute->{persistency} instead");
    }
}

################################################################################
# Enforce string restrictions
################################################################################

sub enforceString {
    my($attribute,$value) = @_;

    if(!exists $attribute->{simpleType})
    {
        croak("ERROR: Tried to enforce string policies on a non-simple type");
    }

    if(!exists $attribute->{simpleType}->{string})
    {
        croak("ERROR: Did not find expected string element");
    }

    if(!exists $attribute->{simpleType}->{string}->{sizeInclNull})
    {
        croak("ERROR: Did not find expected string sizeInclNull element");
    }

    my $size = $attribute->{simpleType}->{string}->{sizeInclNull};
    if($size <= 1)
    {
        croak("ERROR: String size must be > 1 (string of size one is "
            . "only big enough to hold the empty string, which is not "
            . "useful)");
    }
}

################################################################################
# Get hash ref to supported simple types and their properties
################################################################################
my $g_simpleTypeProperties_cache = 0;

sub simpleTypeProperties {

    return $g_simpleTypeProperties_cache if ($g_simpleTypeProperties_cache);

    my %typesHoH = ();

    # Intentionally didn't wrap these to 80 columns to keep them lined up and
    # more readable/editable
    $typesHoH{"string"}      = { supportsArray => 1, canBeHex => 0, complexTypeSupport => 0, typeName => "char"                       , bytes => 1, bits => 8 , default => \&defaultString, alignment => 1, specialPolicies =>\&enforceString,  packfmt =>\&packString};
    $typesHoH{"int8_t"}      = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 1, typeName => "int8_t"                     , bytes => 1, bits => 8 , default => \&defaultZero  , alignment => 1, specialPolicies =>\&null,           packfmt => "C" };
    $typesHoH{"int16_t"}     = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 1, typeName => "int16_t"                    , bytes => 2, bits => 16, default => \&defaultZero  , alignment => 1, specialPolicies =>\&null,           packfmt =>\&pack2byte};
    $typesHoH{"int32_t"}     = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 1, typeName => "int32_t"                    , bytes => 4, bits => 32, default => \&defaultZero  , alignment => 1, specialPolicies =>\&null,           packfmt =>\&pack4byte};
    $typesHoH{"int64_t"}     = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 1, typeName => "int64_t"                    , bytes => 8, bits => 64, default => \&defaultZero  , alignment => 1, specialPolicies =>\&null,           packfmt =>\&pack8byte};
    $typesHoH{"uint8_t"}     = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 1, typeName => "uint8_t"                    , bytes => 1, bits => 8 , default => \&defaultZero  , alignment => 1, specialPolicies =>\&null,           packfmt => "C" };
    $typesHoH{"uint16_t"}    = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 1, typeName => "uint16_t"                   , bytes => 2, bits => 16, default => \&defaultZero  , alignment => 1, specialPolicies =>\&null,           packfmt =>\&pack2byte};
    $typesHoH{"uint32_t"}    = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 1, typeName => "uint32_t"                   , bytes => 4, bits => 32, default => \&defaultZero  , alignment => 1, specialPolicies =>\&null,           packfmt =>\&pack4byte};
    $typesHoH{"uint64_t"}    = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 1, typeName => "uint64_t"                   , bytes => 8, bits => 64, default => \&defaultZero  , alignment => 1, specialPolicies =>\&null,           packfmt =>\&pack8byte};
    $typesHoH{"enumeration"} = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 0, typeName => "XMLTOHB_USE_PARENT_ATTR_ENUMERATION_ID" , bytes => 0, bits => 0 , default => \&defaultEnum  , alignment => 1, specialPolicies =>\&null,           packfmt => "packEnumeration"};
    $typesHoH{"hbmutex"}     = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 0, typeName => "mutex_t*"                   , bytes => 24, bits => 192, default => \&defaultZero  , alignment => 8, specialPolicies =>\&enforceHbMutex, packfmt =>\&packMutex};
    $typesHoH{"hbrecursivemutex"}     = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 0, typeName => "mutex_t*"                   , bytes => 24, bits => 192, default => \&defaultZero  , alignment => 8, specialPolicies =>\&enforceHbMutex, packfmt =>\&packMutex};
    $typesHoH{"Target_t"}    = { supportsArray => 0, canBeHex => 1, complexTypeSupport => 0, typeName => "TARGETING::Target*"         , bytes => 8, bits => 64, default => \&defaultZero  , alignment => 8, specialPolicies =>\&null,           packfmt =>\&pack8byte};
    $typesHoH{"fspmutex"}     = { supportsArray => 1, canBeHex => 1, complexTypeSupport => 0, typeName => "util::Mutex*"              , bytes => 8, bits => 64, default => \&defaultZero  , alignment => 8, specialPolicies =>\&enforceFspMutex, packfmt =>\&pack8byte};

    $g_simpleTypeProperties_cache = \%typesHoH;

    return $g_simpleTypeProperties_cache;
}

################################################################################
# Get attribute type
################################################################################
sub getAttributeType {
    my($attributeId,$attributes) = @_;
    my $attrType;

    foreach my $attribute (@{$attributes->{attribute}})
    {
        if ($attribute->{id} eq $attributeId)
        {
            if(exists $attribute->{simpleType})
            {
                $attrType = $attribute->{simpleType};
            }
            elsif (exists $attribute->{complexType})
            {
                $attrType = $attribute->{complexType};
            }
            elsif (exists $attribute->{nativeType})
            {
                $attrType = $attribute->{nativeType};
            }
            else
            {
                $attrType = "unknown type";
            }
            last;
        }
    }
    return $attrType;
}

################################################################################
# Get attribute default
################################################################################

sub getAttributeDefault {
    my($attributeId,$attributes) = @_;

    my $default = "";
    my $simpleTypeProperties = simpleTypeProperties();

    foreach my $attribute (@{$attributes->{attribute}})
    {
        if ($attribute->{id} eq $attributeId)
        {
            if(exists $attribute->{simpleType})
            {
                for my $type (sort(keys %{$simpleTypeProperties}))
                {
                    # Note: must check for 'type' before 'default', otherwise
                    # might add value to the hash
                    if(exists $attribute->{simpleType}->{$type} )
                    {
                        # If attribute exists, or is not a HASH val (which can
                        # occur if the default element is omitted), then just
                        # grab the supplied value, otherwise use the default for
                        # the type
                        if(   (exists $attribute->{simpleType}->{$type}->
                                   {default})
                           && (ref ($attribute->{simpleType}->{$type}->
                                   {default})
                               ne "HASH") )
                        {
                            $default =
                                $attribute->{simpleType}->{$type}->{default};
                        }
                        else
                        {
                           $default = $simpleTypeProperties->{$type}{default}->(
                                $attributes,$attribute->{simpleType}->{$type} );
                        }
                        last;
                    }
                }
            }
            elsif(exists $attribute->{complexType})
            {
                my $cplxDefault = { } ;
                my $i = 0;
                foreach my $field (@{$attribute->{complexType}->{field}})
                {
                    $cplxDefault->{field}->[$i]->{id} = $field->{name};
                    $cplxDefault->{field}->[$i]->{value} = $field->{default};
                    $i++;
                }
                return $cplxDefault;
            }
            elsif(exists $attribute->{nativeType})
            {
                if(   exists $attribute->{nativeType}->{name}
                   && ($attribute->{nativeType}->{name} eq "EntityPath"))
                {
                    if( exists $attribute->{nativeType}->{default} )
                    {
                        $default = $attribute->{nativeType}->{default};
                    }
                    else
                    {
                        $default =  "MustBeOverriddenByTargetInstance";
                    }
                }
                else
                {
                    croak("Cannot provide default for unsupported nativeType.");
                }
            }
            else
            {
                croak("Unrecognized value type.");
            }

            last;
        }
    }

    return $default;
}

################################################################################
# Merge the fields of two complex attributes
################################################################################

# This function will merge the fields of two complex attributes.
#
# The field's value from $newAttrFields will be merged into $currentAttrFields.
# $currentAttrFields must have, at a minimum, all the fields that are in
# $newAttrFields.  If not then this function will halt execution with an error
# message.  Fields that are in $currentAttrFields that have no associated value
# within $newAttrFields will be left as is.
#
# param [in] - $newAttrFields - These are the new fields with new values that
#                        are to be merged.
#
# param [in] - $currentAttrFields - These are the current fields which, at a
#                        minimum, include ALL the fields from $newAttrFields.
#                        There may be more.
#
# return - The two fields successfully merged
#
sub mergeComplexAttributeFields {
    my($newAttrFields, $currentAttrFields) = @_;

    # Make a deep copy of the current fields, don't want to modify
    # $currentAttrFields - leave as is.  This copy will contain the merger of
    # the two fields.
    my $mergedFields = dclone $currentAttrFields;

    # If the merged field's (an alias for the current attribute fields)
    # hash is empty, then just assign it the new attribute field's value -
    # no merge necessary
    if ($mergedFields->{default} == 0)
    {
        $mergedFields->{default} = $newAttrFields->{default};
    }
    # Only proceed if both attribute pairs have values to merge
    elsif ($newAttrFields->{default} != 0)
    {
        # Iterate over the fields of $newField and look for their corresponding
        # id in $currentAttrFields.  All the fields in $newField should exist in
        # $currentAttrFields, if not, then there is a problem

        # There's an issue that $newAttrFields->{default}->{field} may not be an array.
        # To address that issue, we can check type of it:
        my @newFieldArr = ();
        if (ref $newAttrFields->{default}->{field} ne "ARRAY")
        {
            # If it's not an array, then append it to newFieldArr as if it is the only array entry
            @newFieldArr = ($newAttrFields->{default}->{field});
        }
        else
        {
            # If it is an array, then @newFieldArr will be a reference to it
            @newFieldArr = @{$newAttrFields->{default}->{field}};
        }

        foreach my $newField (@newFieldArr)
        {
            my $foundField = 0;

            # Do not try to merge in a field with no value
            if (ref($newField->{value}) eq "HASH")
            {
                #print STDOUT "Skip $newField->{id}\n";
                next;
            }

            # Iterate over $mergedFields (really $currentAttrFields) looking
            # for the $newField of @newFieldArr
            foreach my $currentField (@{$mergedFields->{default}->{field}})
            {
                # Found the field in question
                if ($currentField->{id} eq $newField->{id})
                {
                   # Merge in the new value from $newField
                   $currentField->{value} = $newField->{value};
                   $foundField = 1;
                   last;
                }
            } # end foreach my $currentField ...

            # A field was not found ... halt execution
            if ($foundField == 0)
            {
               croak("Field $newField is not supported.")
            }
        } # end foreach my $newField ...
    }
    # else new attribute fields is empty - nothing to merge

    return $mergedFields;
}
