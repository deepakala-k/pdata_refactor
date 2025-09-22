#!/usr/bin/perl

#################################################################################
#
#   * This perl script generate device tree structure from intermediate xml
#     which is contain TargetInstance, TargetType and Non-TargetType targets/attributes.
#   * This perl script also support to prepare dts with
#     required targets and attributes.
#
#################################################################################

use File::Basename;
use XML::LibXML;
use Class::Struct;
use Getopt::Long;
use strict;

use FindBin;
require "$FindBin::Bin/parseFinalXML.pl";

# Global variables list begin

# To mention this tool name if unsupported attribute data type present in xml
my $tool = basename($0);
# To store commandline arguments
my $inXMLFile;
my $dtsFilename;
my $filterAttrsFile;
my $filterTgtsFile;
my $pdbgMapFile;
my $help;
my $myVerbose;

# To store xml data
my %attributeDefList;
my %targetTypeList;
my %targetInstanceList;
my %pdbgCompPropMapList;
# Used for dts (device tree structure) generation
my %headOfDTree;
my $dtsFHandle;

my $attrPrefix = "ATTR_";

struct Node => {
    nodeName        => '$',
    childNodes      => '%',
    # DTS Property
    compatible      => '$',
    index           => '$',
    address_cells   => '$',
    size_cells      => '$',
    reg             => '$',
    attributeList   => '%',
};

# Process commandline options

GetOptions( "inXML:s"           => \$inXMLFile,
            "outDTS:s"          => \$dtsFilename,
            "filterAttrsFile:s" => \$filterAttrsFile,
            "filterTgtsFile:s"  => \$filterTgtsFile,
            "help"            => \$help,
            "verbose=s",      => \$myVerbose
          );

if ( $help )
{
    printUsage();
    exit 0;
}
if ( $inXMLFile eq "" )
{
    print "--inXML is required with xml file which should be in TargetInstance format xml with mrw, fapia and non-fapi attributes to generate dts file\n";
    exit 1;
}
if ( $dtsFilename eq "")
{
    print "--outDTS is required with dts file name to store generated targets with attributes in dts format\n";
    exit 1;
}
if ( ($dtsFilename ne "") and !($dtsFilename =~ m/\.dts/ ))
{
    print "The given dts file name \"$dtsFilename\" extension is not .dts\n";
    exit 1;
}


# Start fomr main function
main();

###############################
#      Subroutine Begin       #
###############################

sub printUsage
{
    print "
Description:

    *   This tool will generate device tree structure from intermediate xml
        which is contain TargetInstance, TargetType targets/attributes.
    *   This tool also support to prepare dts with required
        targets and attributes.\n" if $help;

    print "
Usage of $tool:

    -i|--inXML          : [M] :  Used to give intermediate xml name which contain TargetInstance and TargetType
                                 Targets with associated attributes.
                                 E.g.: --inXML <xml_file.xml>

    -o|--outDTS         : [M] :  Used to give device tree structure file to stored generated dts                                 data.
                                 E.g.: --outDTS <dts_file.dts>

    -f|--filterAttrsFile: [O] :  Used to give required attributes list in lsv file.
                                 E.g. : --filterAttrsFile <systemName_FilterAttrsList.lsv>

    -f|--filterTgtsFile : [O] :  Used to give required targets list in lsv file.
                                 E.g. : --filterTgtsFile <systemName_FilterTgtsList.lsv>

    -v|--verbose        : [O] :  Use to print debug information
                                 To print different level of log use following format
                                 -v|--verbose A,C,E,W,I
                                 A - All, C - CRITICAL, E - ERROR, W - WARNING, I - INFO

    -h|--help           : [O] :  To print the tool usage

";
}

sub main
{
    initVerbose($myVerbose);
    init();
    loadTargetTypeDefaultIfNoTargetInstanceDefault();
    prepareDeviceTreeHierarchy();
    createDTSFile();
}

sub init
{

    my @ret = getTargetInstanceAndTargetTypeData($inXMLFile, $filterTgtsFile);
    %targetInstanceList = %{$ret[0]};
    %targetTypeList = %{$ret[1]};
    %attributeDefList = getAttrsDef( $inXMLFile, $filterAttrsFile );
    my $noOfTargetInstance = keys %targetInstanceList;
    my $noOfTargetType = keys %targetTypeList;
    my $attrsSize = keys %attributeDefList;
    print "INFO: noOfTargetInstance: $noOfTargetInstance noOfTargetType: $noOfTargetType attrsSize: $attrsSize\n" if isVerboseReq('I');
}

sub loadTargetTypeDefaultIfNoTargetInstanceDefault
{
    foreach my $targetTypeID ( keys %targetTypeList )
    {
        foreach my $targetInstanceID ( keys %targetInstanceList )
        {
            if($targetTypeID eq $targetInstanceList{$targetInstanceID} -> TargetInstance::targetType)
            {
                my $targetInstance = $targetInstanceList{$targetInstanceID};
                my %updatedTargetInstanceAttrsList = %{$targetInstance->targetAttrList};
                my %targetTypeAttrsList = %{$targetTypeList{$targetTypeID} -> TargetType::targetAttrList};
                my @sortedKeys = sort { numericalSort($a, $b) } keys %targetTypeAttrsList;

                foreach my $targetTypeAttr ( @sortedKeys )
                {
                    if( exists $updatedTargetInstanceAttrsList{$targetTypeAttr} )
                    {
                        if ( $updatedTargetInstanceAttrsList{$targetTypeAttr}-> AttributeData::valueDataType eq "")
                        {
                            $updatedTargetInstanceAttrsList{$targetTypeAttr} = $targetTypeAttrsList{$targetTypeAttr};
                        }
                    }
                    else
                    {
                        $updatedTargetInstanceAttrsList{$targetTypeAttr} = $targetTypeAttrsList{$targetTypeAttr};
                    }
                }
                $targetInstance->targetAttrList(\%updatedTargetInstanceAttrsList);
            }
        }
    }
}

sub prepareDeviceTreeHierarchy
{
    my %nonPervTgtsList;
    my %omiPervPath;
    my @sortedKeys = sort { numericalSort($a, $b) } keys %targetInstanceList;
    
    # Prepare for TargetInstance targets
    foreach my $targetInstanceID ( @sortedKeys)
    {
        my $attrList = $targetInstanceList{$targetInstanceID}->targetAttrList;

        if ( !exists ${$attrList}{'AFFINITY_PATH'} )
        {
            print "CRITICAL: \"AFFINITY_PATH\" attribute is not found for TargetInstance Target : \"$targetInstanceID\". So Ignoring\n" if isVerboseReq('C');
            next;
        }
        my $affinityPath = ${$attrList}{'AFFINITY_PATH'}->value;

        # Getting path value alone by ignoring "affinity:"
        my @hash = split(/\//, substr($affinityPath, index($affinityPath, ':') + 1));
        processTargetPath($targetInstanceID, \@hash);
    }
}

#returns the number at the end of the string if found, else returns 0
sub getNumAtTheEnd {
    my ($str) = @_;

    #expression to extract the number at the end of the string
    my ($number) = $str =~ /(\d+)$/;

    return $number || 0;
}

#Sorts two strings using number at the end if they contain the same string part.
#Or sort them alphabetically
sub numericalSort {
    my ($firstString, $secondString) = @_;
    
    my $firstStringWithoutNum = $firstString;
    my $secondStringWithoutNum = $secondString;
    
    # store the numerical value at the end to num variables
    my $firstNum = getNumAtTheEnd($firstString);
    my $secondNum = getNumAtTheEnd($secondString);

    # Removes the numerical value at the end of each of the variables
    # s/\d+$// expression chops the number at the end
    $firstStringWithoutNum =~ s/\d+$//;
    $secondStringWithoutNum =~ s/\d+$//;

    # Compares the name part without numbers
    # and if both numbers are 0, it might be possible that the original 
    # string did not have a number. Hence do a string compare
    if ($firstStringWithoutNum eq $secondStringWithoutNum 
        && $firstNum != 0 && $secondNum != 0)
    {
      return $firstNum <=> $secondNum;
    }
    else
    {
      return $firstString cmp $secondString;
    }
}

sub processTargetPath
{
    my $TargetID = $_[0];
    my @splittedPath = @{$_[1]};
    # If Any intermediate node is not found from given path then create empty node and continue
    my $refDTreeNodesList = \%headOfDTree;
    my $lastNode;
    foreach my $key ( @splittedPath )
    {
        if ( !exists ( $refDTreeNodesList -> { $key } ) )
        {
            $refDTreeNodesList -> { $key } = createNode($key);
        }
        $lastNode = $refDTreeNodesList -> {$key};
        $refDTreeNodesList = \%{ $refDTreeNodesList -> { $key } -> Node::childNodes } ;
    }
    # Assign node member values for the last node based on last key(path name) in thn given path
    $lastNode->compatible($targetInstanceList{$TargetID} -> TargetInstance::targetType);
    $lastNode->attributeList($targetInstanceList{$TargetID} -> TargetInstance::targetAttrList);

    # Add the reg property for the target if that contains "I2C_ADDRESS"
    # attribute to perform the i2c read and write operation on this target.
    if (exists ${$lastNode->attributeList}{"I2C_ADDRESS"})
    {
        $lastNode->reg(${$lastNode->attributeList}{"I2C_ADDRESS"}->value);

        # Get the parent target to add address and size cells properties
        # in the device tree since added the reg property so these properties
        # are required in the parent target to perform the address translation.
        my @parentPathEleKey = @splittedPath;
        pop @parentPathEleKey;

        my $parentNode;
        $refDTreeNodesList = \%headOfDTree;
        foreach my $key ( @parentPathEleKey )
        {
            $parentNode = $refDTreeNodesList -> { $key };
            $refDTreeNodesList = \%{ $refDTreeNodesList -> { $key } -> Node::childNodes } ;
        }

        # Adding address and size cells value as "0x01" and "0x00" respectively
        # since the I2C_ADDRESS attribute is uint8 type
        $parentNode->address_cells(0x01);
        $parentNode->size_cells(0x00);
    }
}

sub createNode
{
	my $node = Node->new();
	$node->nodeName($_[0]);
    $node->compatible("");
    $node->attributeList({});
    $node->childNodes({});
    $node->address_cells("");
    $node->size_cells("");
    $node->reg("");
    return ($node);
}

sub createDTSFile
{
	open $dtsFHandle, '>', $dtsFilename or die "Could not open $dtsFilename: \"$!\"";

	# Add DTS version and staring brace
	print {$dtsFHandle} "/dts-v1/;\n\n/ {\n";

	# Add all nodes into DTS file
    addNodesIntoDTSFile(\%headOfDTree);

	# Add end brace to DTS
	print {$dtsFHandle} "};";

    close $dtsFHandle;
    my $baseDtsFileName = basename($dtsFilename);
    print "\nDevice tree structure file \"$baseDtsFileName\" is created successfully...\n";
}

sub addNodesIntoDTSFile
{
    my $nodes = $_[0];

    my $addDevTreeNode = 1;
    my $addCompProp = 1;
    my @sortedKeys = sort { numericalSort($a, $b) } keys %{$nodes};

    foreach my $key ( @sortedKeys)
    {
        # Don't add device tree node for below targets as per pdbg expectaion
        if ( $key =~ m/sys/)
        {
            $addDevTreeNode = 0;
        }

        # Don't add compatible property for below targets as per pdbg expectaion
        if ( $key =~ m/sys/ or $key =~ m/node/ or $key =~ m/^i2c-/ )
        {
            $addCompProp = 0;
        }

        my $nodeName = $nodes -> {$key} -> Node::nodeName;

        # Removing "-" in the node name as per pdbg expectation except
        # below targets
        if (!($nodeName =~ m/^i2c-/))
        {
            $nodeName =~ s/-//g;
        }

        print {$dtsFHandle} "\n$nodeName {\n" if $addDevTreeNode eq 1;

        addTargetDataIntoDTSFile($nodes->{$key}, $addCompProp);
        addNodesIntoDTSFile($nodes -> {$key} -> Node::childNodes);

        print {$dtsFHandle} "};\n" if $addDevTreeNode eq 1;
    }
}

# Main function
sub addTargetDataIntoDTSFile {
    my ($devTreeNode, $compPropReqAdd) = @_;

    my %attributeList = %{$devTreeNode->attributeList};

    # Add basic properties
    addBasicProperties($devTreeNode);

    # Convert PHYS_PATH and AFFINITY_PATH attributes
    handleSpecialAttributes(\%attributeList);

    # Process each attribute
    foreach my $AttrID (sort { numericalSort($a, $b) } keys %attributeList) {
        my $attrType = getAttributeType($AttrID);
        next if $attrType eq "";

        # Skip if attribute not part of targetType
        next unless exists ${$targetTypeList{$devTreeNode->compatible}->targetAttrList}{$AttrID};

        if ($attrType eq "simpleType") {
            my $attrVal = $attributeList{$AttrID}->AttributeData::value;
            my $simpleType = $attributeDefList{$AttrID}->AttributeDefinition::simpleType;

            # Fill default value if not defined
            $attrVal = $simpleType->default if $attrVal eq "";

            # Dispatch to subtype handler
            if ($simpleType->DataType eq "array") {
                handleArrayType($AttrID, $attrVal, $simpleType);
            }
            elsif ($simpleType->DataType eq "enum") {
                handleEnumType($AttrID, $attrVal, $simpleType);
            }
            elsif ($simpleType->DataType eq "string") {
                handleStringType($AttrID, $attrVal, $simpleType);
            }
            else { # numeric types
                handleNumericType($AttrID, $attrVal, $simpleType);
            }
        }
        elsif ($attrType eq "complexType") {
            handleComplexType($AttrID, $attributeList{$AttrID}->AttributeData::value);
        }
    }
}

# Add basic device tree node properties
sub addBasicProperties {
    my ($devTreeNode) = @_;

    print {$dtsFHandle} "compatible = \"$devTreeNode->{compatible}\";\n" if $devTreeNode->{compatible} ne "";
    print {$dtsFHandle} "reg = <$devTreeNode->{reg}>;\n" if $devTreeNode->{reg} ne "";
    print {$dtsFHandle} "#address-cells = <$devTreeNode->{address_cells}>;\n" if $devTreeNode->{address_cells} ne "";
    print {$dtsFHandle} "#size-cells = <$devTreeNode->{size_cells}>;\n" if $devTreeNode->{size_cells} ne "";
}

# Handle PHYS_PATH and AFFINITY_PATH
sub handleSpecialAttributes {
    my ($attrListRef) = @_;
    if (exists $attrListRef->{"PHYS_BIN_PATH"}) {
        $attrListRef->{"PHYS_BIN_PATH"}->value(getBinaryFormatForPath($attrListRef->{"PHYS_PATH"}->value, "PHYS_BIN_PATH"));
    }
    if (exists $attrListRef->{"AFFINITY_BIN_PATH"}) {
        $attrListRef->{"AFFINITY_BIN_PATH"}->value(getBinaryFormatForPath($attrListRef->{"AFFINITY_PATH"}->value, "AFFINITY_BIN_PATH"));
    }
}

# SimpleType handlers
sub handleArrayType {
    my ($AttrID, $attrVal, $simpleType) = @_;

    my $eleCnt = 1;
    my @dims = split(/,/, $simpleType->arrayDimension);
    $eleCnt *= $_ foreach @dims;

    my @arrayValues;

    if ($simpleType->subType eq "string") {
        (@arrayValues) = $attrVal =~ m/"(.*?)"/g;
    }
    elsif (index($simpleType->subType, "enum_") != -1) {
        my $enumNames = $attrVal ne "" ? $attrVal : $simpleType->enumDefinition->default;
        @arrayValues = split(/,/, $enumNames);
        foreach my $enumName (@arrayValues) {
            my $enumVal = getEnumVal(\@{$simpleType->enumDefinition->enumeratorList}, $enumName);
            $enumVal = getEnumVal(\@{$simpleType->enumDefinition->enumeratorList}, "") if $enumVal eq "";
            $enumName = $enumVal;
        }
    }
    else {
        @arrayValues = split(/,/, $attrVal);
        # Convert enum-like string values if necessary
        foreach my $arrVal (@arrayValues) {
            if (defined $arrVal && $arrVal !~ /^-?\d+$/ && $arrVal !~ /^0x[0-9A-Fa-f]+$/ && $arrVal ne "") {
                # Fill from enum if exists
                my $inXMLData = XML::LibXML->load_xml(location => $inXMLFile);
                my $enumDefPath = '/attributes/enumerationType/id[text()=\''.$AttrID.'\']/ancestor::enumerationType';
                my $enumDefData = $inXMLData->find($enumDefPath);
                if ($enumDefData->size() > 0) {
                    my $enumDef = parseEnumerationTypes($enumDefData);
                    $simpleType->enumDefinition($enumDef);
                    my $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, $arrVal);
                    $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, "") if $enumVal eq "";
                    $arrVal = $enumVal;
                }
            }
        }
    }

    # Pad missing elements with 0
    push @arrayValues, (0) x ($eleCnt - @arrayValues) if @arrayValues < $eleCnt;

    setDTSFormatValueForSimpleAttr($AttrID, $simpleType->DataType."_".$simpleType->subType, \@arrayValues, $eleCnt);
}

sub handleEnumType {
    my ($AttrID, $attrVal, $simpleType) = @_;

    my $enumName = $attrVal ne "" ? $attrVal : $simpleType->enumDefinition->default;
    my $enumVal = $enumName ne "0" ? getEnumVal(\@{$simpleType->enumDefinition->enumeratorList}, $enumName) : $enumName;
    $enumVal = getEnumVal(\@{$simpleType->enumDefinition->enumeratorList}, "") if $enumVal eq "";

    setDTSFormatValueForSimpleAttr($AttrID, $simpleType->DataType."_".$simpleType->subType, [$enumVal], 1);
}

sub handleStringType {
    my ($AttrID, $attrVal, $simpleType) = @_;
    my $size = $simpleType->stringSize - 1;
    my $strAttrVal = pack("Z$size", $attrVal);
    setDTSFormatValueForSimpleAttr($AttrID, $simpleType->DataType, [$strAttrVal], 1);
}

sub handleNumericType {
    my ($AttrID, $attrVal, $simpleType) = @_;
    my $val = $attrVal eq 'true' ? 1 : $attrVal eq 'false' ? 0 : $attrVal;

    if (defined $val && $val ne "" && $val !~ /^-?\d+$/ && $val !~ /^0x[0-9A-Fa-f]+$/) {
        # Handle enum fallback
        my $inXMLData = XML::LibXML->load_xml(location => $inXMLFile);
        my $enumDefPath = '/attributes/enumerationType/id[text()=\''.$AttrID.'\']/ancestor::enumerationType';
        my $enumDefData = $inXMLData->find($enumDefPath);
        if ($enumDefData->size() > 0) {
            my $enumDef = parseEnumerationTypes($enumDefData);
            $simpleType->enumDefinition($enumDef);
            my $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, $val);
            $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, "") if $enumVal eq "";
            $val = $enumVal;
        }
    }

    setDTSFormatValueForSimpleAttr($AttrID, $simpleType->DataType, [$val], 1);
}

sub handleComplexType {
    my ($AttrID, $attrValue) = @_;
    if ($attrValue eq "") {
        my @ret = getSpecAndDefValForComplexTypeAttr(
            \@{$attributeDefList{$AttrID}->complexType->listOfComplexTypeFields},
            $attributeDefList{$AttrID}->complexType->arrayDimension
        );
        $attrValue = $ret[1];
    }
    print {$dtsFHandle} "$attrPrefix$AttrID = [$attrValue ];\n";
}

sub getAttributeType
{
    my $attrID = $_[0];
    my $attrType;

    if( exists $attributeDefList{$attrID})
    {
        $attrType = $attributeDefList{$attrID}-> AttributeDefinition::datatype;
    }
    else
    {
        print "ERROR: Attribute: $attrID is not found in attribute definition\n" if isVerboseReq('E');
    }

    return ($attrType);
}

sub setDTSFormatValueForSimpleAttr
{
    my $attrName = $_[0];
    my $type = $_[1];
    my @values = @{$_[2]};
    my $eleCnt = $_[3];

    # Getting actual type from input type value if type contains array or enum
    # E.g : enum_uint32_t => uint32 or array_enum_uint32_t  => uint32
    if ( $type =~ m/array/ or $type =~ m/enum/ )
    {
        $type = substr($type, 0, rindex($type, "_"));
        $type = substr($type, rindex($type, "_") + 1);
    }

    my $dtsFormatedVal;
    my $begFormatSym;
    my $valSize = @values;
    foreach my $pValue (@values)
    {
        if( $type =~ m/int8/ )
        {
            if ( $pValue =~ m/0x/ )
            {
                $pValue =~ s/0x//g;
                $pValue = "0".$pValue if length($pValue) == 1;
            }
            else
            {
                $pValue = sprintf("%02X", $pValue);
            }

            $begFormatSym = "[" if $begFormatSym eq "";
            $dtsFormatedVal .= $pValue;
            $dtsFormatedVal .= " " if $valSize > 1;
        }
        elsif( $type =~ m/int16/ )
        {
            if ( $pValue =~ m/0x/ )
            {
                $pValue =~ s/0x//g;
                for ( my $x = 0; length($pValue) < 4; $x + 1) { $pValue = "0".$pValue }
            }
            else
            {
                $pValue = sprintf("%04X", $pValue);
            }

            my $fByte = substr($pValue, 0, 2);
            my $sByte = substr($pValue, 2, 2);

            $begFormatSym = "[" if $begFormatSym eq "";
            $dtsFormatedVal .= $fByte." ".$sByte;
            $dtsFormatedVal .= " " if $valSize > 1;
        }
        elsif( $type =~ m/int32/ )
        {
            $begFormatSym = "<" if $begFormatSym eq "";
            $dtsFormatedVal .= "$pValue";
            $dtsFormatedVal .= " " if $valSize > 1;
        }
        elsif( $type =~ m/int64/ )
        {
            $begFormatSym = "<" if $begFormatSym eq "";
            $dtsFormatedVal .= "$pValue";
            $dtsFormatedVal .= " " if $valSize > 1;
        }
        elsif( $type =~ m/string/ )
        {
           $dtsFormatedVal .= "\"$pValue\"";
           $dtsFormatedVal .= ", " if $valSize > 1;
        }
        else
        {
            # Unsupported type given
            return "";
        }
    }
    $dtsFormatedVal = "[ ".$dtsFormatedVal if $begFormatSym eq "[";
    $dtsFormatedVal .= " ]" if $begFormatSym eq "[";
    $dtsFormatedVal = "<".$dtsFormatedVal if $begFormatSym eq "<";
    $dtsFormatedVal .= ">" if $begFormatSym eq "<";
    print {$dtsFHandle} "$attrPrefix$attrName = $dtsFormatedVal;\n";
}

sub getEnumVal
{
    my @enumeratorList = @{$_[0]};
    my $enumName = $_[1];

    if ($enumName ne "")
    {
        # check enum name is hex in enumeratorList
        # to match with given enum name
        if ((substr($enumName, 0, 2) eq "0x") and
            (substr($enumeratorList[0][0], 0, 2) ne "0x"))
        {
            $enumName = hex($enumName);
        }

        # enumPair<enumName, enumValue>
        foreach my $enumPair ( @enumeratorList )
        {
            my $enumVal = "";
            if ($enumName eq $enumPair->[0])
            {
                $enumVal = $enumPair->[1];
            }

            # Make sure given enum name is enum value as well. Because,
            # In TargetInstance, there may be chance to use enum value instead enum name
            # for defalut value
            if ( ($enumVal eq "") and ($enumName eq $enumPair->[1]) )
            {
                $enumVal = $enumPair->[1];
            }

            return $enumVal if ($enumVal ne "");
        }
    }
    else
    {
        # Return first enum value if enum name is empty
        return $enumeratorList[0][1];
    }

    return "";
}

sub getBinaryFormatForPath
{
    my ($phyOrAffpath, $attrToConstruct) = @_;
    my ($pathType, $path) = split(/:/, $phyOrAffpath);
    my @pathElements = split(/\//, $path);
    my $pathElementsSize = @pathElements;

    # Reducing one from configured array size and dividing by 2 to get path element size
    my $configpathElementsSize = ($attributeDefList{$attrToConstruct}->simpleType->arrayDimension - 1) / 2;

    if ( $configpathElementsSize < $pathElementsSize )
    {
        print "CRITICAL: The max path element size of $$attrToConstruct is $configpathElementsSize but the given path element size in PHYS_DEV_PATH attribute value[$phyOrAffpath] is $pathElementsSize\n";
        return "";
    }

    if ( $pathType eq "physical" )
    {
        $pathType = 2;
    }
    elsif ( $pathType eq "affinity" )
    {
        $pathType = 1;
    }
    else
    {
        print "CRITICAL: Invalid path type[$pathType] in given path [$phyOrAffpath]\n";
        return "";
    }

    # Device tree is big endian format. so, storing path type and size of path elements values
    # as one byte in big endian format.
    my $pathtype_size = (0xF0 & ($pathType << 4)) + (0x0F & $pathElementsSize);

    my $convertedBinaryFormat = $pathtype_size.",";

    foreach my $pathEle ( @pathElements )
    {
        # splitting path element into type and instance. e.g: sys-0 => type = sys and instance = 0
        my @pathEleFields = split(/-/, $pathEle);
        my $found = 0;
        foreach my $tgtTypeEnum ( @{$attributeDefList{"TYPE"}->simpleType->enumDefinition->enumeratorList} )
        {
            if ( uc($pathEleFields[0]) eq $tgtTypeEnum->[0] )
            {
                $found = 1;
                # storing target type and its instance value as binary format.
                # e.g.: sys-0 => 00 00 => first "00" is enum value of sys and second "00" is hex value of 0
                $convertedBinaryFormat .= $tgtTypeEnum->[1].",".$pathEleFields[1].",";
            }
        }

        if ( $found eq 0 )
        {
            print "CRITICAL: The given path element type[$pathEleFields[0]] for path[$path] is not found in TYPE attibute enum list.\n" if isVerboseReq('C');
            return "";
        }
    }

    # Adding zero if the path elements size which is found in given PHYS_DEV_PATH
    # is less than the config size
    if ( $configpathElementsSize > $pathElementsSize )
    {
        for (my $i = $pathElementsSize; $i < $configpathElementsSize; $i++)
        {
            # for target type field
            $convertedBinaryFormat .= "0".",";
            # for target instance field
            $convertedBinaryFormat .= "0".",";
        }
    }

    return $convertedBinaryFormat;
}
###############################
#      Subroutine End         #
###############################
