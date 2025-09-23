#!/usr/bin/perl

#################################################################################
#
#   * This perl script generate device tree structure from final xml
#     which is contain TargetInstance, TargetType and attributes.
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
my $help;
my $myVerbose;
my $inXMLData;

# To store xml data
my %attributeDefList;
my %targetTypeList;
my %targetInstanceList;


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

    *   This tool will generate device tree structure from final xml
        which is contain TargetInstance, TargetType targets and attributes.
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
    $inXMLData = XML::LibXML->load_xml(location => $inXMLFile);
    initVerbose($myVerbose);
    init();
    loadTargetTypeDefaultIfNoTargetInstanceDefault();
    prepareDeviceTreeHierarchy();
    createDTSFile();
}

sub init
{
    my ($targetInstanceListRef, $targetTypeListRef) = 
        getTargetInstanceAndTargetTypeData($inXMLData, $filterTgtsFile);
    %targetInstanceList = %{$targetInstanceListRef};
    %targetTypeList = %{$targetTypeListRef};
    %attributeDefList = getAttrsDef( $inXMLData, $filterAttrsFile );
    my $noOfTargetInstance = keys %targetInstanceList;
    my $noOfTargetType = keys %targetTypeList;
    my $attrsSize = keys %attributeDefList;
    print "INFO: noOfTargetInstance: $noOfTargetInstance noOfTargetType: $noOfTargetType attrsSize: $attrsSize\n" if isVerboseReq('I');
}

sub loadTargetTypeDefaultIfNoTargetInstanceDefault {
    foreach my $targetInstanceID (keys %targetInstanceList) {
        my $targetInstance = $targetInstanceList{$targetInstanceID};
        my $targetTypeID   = $targetInstance->TargetInstance::targetType;

        # Skip if no matching target type
        next unless exists $targetTypeList{$targetTypeID};

        my $instanceAttrs = $targetInstance->targetAttrList;   # hashref
        my $typeAttrs     = $targetTypeList{$targetTypeID}->TargetType::targetAttrList; # hashref

        foreach my $attr (sort { numericalSort($a, $b) } keys %$typeAttrs) {
            # Replace only if missing or empty
            if (!exists $instanceAttrs->{$attr}
                || $instanceAttrs->{$attr}->AttributeData::valueDataType eq "") {
                $instanceAttrs->{$attr} = $typeAttrs->{$attr};
            }
        }

        # update instance with modified attrs
        $targetInstance->targetAttrList($instanceAttrs);
    }
}

sub prepareDeviceTreeHierarchy {
    my @sortedKeys = sort { numericalSort($a, $b) } keys %targetInstanceList;

    foreach my $targetInstanceID (@sortedKeys) {
        my $attrList = $targetInstanceList{$targetInstanceID}->targetAttrList;

        unless (exists $attrList->{'PHYS_PATH'}) {
            print "CRITICAL: \"PHYS_PATH\" attribute is not found for TargetInstance Target : \"$targetInstanceID\". So Ignoring\n"
                if isVerboseReq('C');
            next;
        }

        my $deviceTreeHierarchy = $attrList->{'PHYS_PATH'}->value;

        # remove everything up to and including the first colon
        $deviceTreeHierarchy =~ s/^[^:]+://;

        my @parts = split '/', $deviceTreeHierarchy;
        processTargetPath($targetInstanceID, \@parts);
    }
}

#returns the number at the end of the string if found, else returns 0
sub getNumAtTheEnd {
    my ($str) = @_;

    #expression to extract the number at the end of the string
    my ($number) = $str =~ /(\d+)$/;

    return $number || 0;
}

# Sort comparator that orders strings in "natural" style:
# - If two strings share the same non-numeric prefix and both end in numbers,
#   compare them by those numeric suffixes (e.g. "core2" < "core10").
# - Otherwise, fall back to standard alphabetical comparison.
sub numericalSort {
    my ($a, $b) = @_;

    # Capture prefix and optional numeric suffix
    my ($prefixA, $numA) = $a =~ /^(.*?)(\d+)?$/;
    my ($prefixB, $numB) = $b =~ /^(.*?)(\d+)?$/;

    if ($prefixA eq $prefixB && defined $numA && defined $numB) {
        return $numA <=> $numB;
    }
    return $a cmp $b;
}

sub processTargetPath {
    my ($TargetID, $splittedPathRef) = @_;
    my $refDTreeNodesList = \%headOfDTree;
    my $lastNode;
    my $parentNode;

    foreach my $key (@$splittedPathRef) {
        # Create node if it does not exist
        $refDTreeNodesList->{$key} //= createNode($key);

        $parentNode = $lastNode;                # track parent while walking
        $lastNode   = $refDTreeNodesList->{$key};
        $refDTreeNodesList = $lastNode->Node::childNodes;
    }

    # Assign attributes to the last node
    my $instance = $targetInstanceList{$TargetID};
    $lastNode->compatible($instance->TargetInstance::targetType);
    $lastNode->attributeList($instance->TargetInstance::targetAttrList);

    # Add I2C-specific properties if I2C_ADDRESS exists
    if (my $i2cAttr = $lastNode->attributeList->{"I2C_ADDRESS"}) {
        $lastNode->reg($i2cAttr->value);

        if ($parentNode) {
            # Since I2C_ADDRESS is uint8, use fixed cells
            $parentNode->address_cells(0x01);
            $parentNode->size_cells(0x00);
        }
    }
}

sub createNode {
    my ($name) = @_;

    my $node = Node->new();
    $node->nodeName($name);
    $node->compatible('');
    $node->attributeList({});
    $node->childNodes({});
    $node->address_cells("");
    $node->size_cells("");
    $node->reg('');
    return $node;
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

sub addNodesIntoDTSFile {
    my ($nodes) = @_;

    my @sortedKeys = sort { numericalSort($a, $b) } keys %$nodes;

    foreach my $key (@sortedKeys) {
        # pdbg expectations:
        my $addDevTreeNode = ($key !~ /sys/);

        my $node = $nodes->{$key};
        my $nodeName = $node->Node::nodeName;

        # TODO - why to remove all the "-"?
        # remove "-" except for i2c- nodes
        $nodeName =~ s/-//g unless $nodeName =~ /^i2c-/;

        if ($addDevTreeNode) {
            print {$dtsFHandle} "\n$nodeName {\n";
        }

        addTargetDataIntoDTSFile($node);
        addNodesIntoDTSFile($node->Node::childNodes);

        if ($addDevTreeNode) {
            print {$dtsFHandle} "};\n";
        }
    }
}

# Main function
sub addTargetDataIntoDTSFile {
    my ($devTreeNode) = @_;

    my %attributeList = %{$devTreeNode->attributeList};

    # Add basic properties
    addBasicProperties($devTreeNode);

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
        elsif ($attrType eq "nativeType") {
            my $attrVal = $attributeList{$AttrID}->AttributeData::value;
            handleNativeType($AttrID, $attrVal);
        }
    }
}

# Add basic device tree node properties
sub addBasicProperties {
    my ($devTreeNode) = @_;

    print {$dtsFHandle} "compatible = \"$devTreeNode->{'Node::compatible'}\";\n"
        if defined $devTreeNode->{'Node::compatible'} and $devTreeNode->{'Node::compatible'} ne "";

    print {$dtsFHandle} "reg = <$devTreeNode->{'Node::reg'}>;\n"
        if defined $devTreeNode->{'Node::reg'} and $devTreeNode->{'Node::reg'} ne "";

    print {$dtsFHandle} "#address-cells = <$devTreeNode->{'Node::address_cells'}>;\n"
        if defined $devTreeNode->{'Node::address_cells'} and $devTreeNode->{'Node::address_cells'} ne "";

    print {$dtsFHandle} "#size-cells = <$devTreeNode->{'Node::size_cells'}>;\n"
        if defined $devTreeNode->{'Node::size_cells'} and $devTreeNode->{'Node::size_cells'} ne "";
}

sub handleNativeType {
    my ($AttrID, $attrVal) = @_;

    my $nativeTypeEquivalentSimpleType = bless(
        {
            'SimpleType::stringSize'     => undef,
            'SimpleType::enumId'         => undef,
            'SimpleType::default'        => '',
            'SimpleType::DataType'       => 'array',
            'SimpleType::subType'        => 'uint8_t',
            'SimpleType::arrayDimension' => '21'
        },
        'SimpleType'
    );

    $attrVal = getBinaryFormatForPath($attrVal, $nativeTypeEquivalentSimpleType);
    if($attrVal ne "" && $AttrID ne "PARENT_PERVASIVE")
    {
        handleArrayType($AttrID, $attrVal, $nativeTypeEquivalentSimpleType);
    }
}

# Handle array-type attributes:
# - Calculate total number of elements from array dimensions
# - Extract values based on subtype (string, enum, numeric)
# - Resolve enum strings to numeric values if enum
# - Pad missing elements with 0
# - Push final array into DTS
sub handleArrayType {
    my ($AttrID, $attrVal, $simpleType) = @_;

    # Compute total element count from array dimensions
    my $eleCnt = 1;
    my @dims = split /,/, $simpleType->arrayDimension;
    $eleCnt *= $_ for @dims;

    my @arrayValues;

    if ($simpleType->subType eq 'string') {
        # Extract all quoted strings
        @arrayValues = $attrVal =~ /"(.*?)"/g;
    }
    elsif ($simpleType->subType =~ /^enum_/) {
        # Use provided values or default from enum definition
        my $enumNames = $attrVal ne '' ? $attrVal : $simpleType->enumDefinition->default;
        @arrayValues = split /,/, $enumNames;

        # Convert enum names to numeric values
        for my $i (0..$#arrayValues) {
            my $enumVal = getEnumVal(\@{$simpleType->enumDefinition->enumeratorList}, $arrayValues[$i]);
            $enumVal = getEnumVal(\@{$simpleType->enumDefinition->enumeratorList}, '') if $enumVal eq '';
            $arrayValues[$i] = $enumVal;
        }
    }
    else {
        # Numeric or mixed types
        @arrayValues = split /,/, $attrVal;

        for my $i (0..$#arrayValues) {
            my $val = $arrayValues[$i];

            # Resolve non-numeric values via enum if defined
            if (defined $val && $val ne '' && $val !~ /^-?\d+$/ && $val !~ /^0x[0-9A-Fa-f]+$/) {
                my $enumDefPath = "/attributes/enumerationType/id[text()='$AttrID']/ancestor::enumerationType";
                my $enumDefData = $inXMLData->find($enumDefPath);

                if ($enumDefData->size > 0) {
                    my $enumDef = parseEnumerationTypes($enumDefData);
                    $simpleType->enumDefinition($enumDef);

                    my $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, $val);
                    $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, '') if $enumVal eq '';
                    $arrayValues[$i] = $enumVal;
                }
            }
        }
    }

    # Pad missing elements with 0
    push @arrayValues, (0) x ($eleCnt - @arrayValues) if @arrayValues < $eleCnt;

    # Set array into DTS with full type info
    setDTSFormatValueForSimpleAttr(
        $AttrID,
        $simpleType->DataType . "_" . $simpleType->subType,
        \@arrayValues,
        $eleCnt
    );
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

# Handle numeric-type attributes:
# - Normalize boolean strings ("true"/"false") into 1/0
# - Accept integers and hex values directly
# - If non-numeric, try resolving through enumeration definitions
# - Finally, set the DTS value in the correct format
sub handleNumericType {
    my ($AttrID, $attrVal, $simpleType) = @_;

    # Normalize booleans into numeric form
    my $val = ($attrVal eq 'true')  ? 1
            : ($attrVal eq 'false') ? 0
            : $attrVal;

    # If value is non-empty and not already a valid integer or hex
    if (defined $val && $val ne "" && $val !~ /^-?\d+$/ && $val !~ /^0x[0-9A-Fa-f]+$/) {
        
        # XPath: find the enumerationType node for this AttrID
        my $enumDefPath = "/attributes/enumerationType/id[text()='$AttrID']/ancestor::enumerationType";
        my $enumDefData = $inXMLData->find($enumDefPath);

        if ($enumDefData->size > 0) {
            # Parse enumeration definition and attach to the type
            my $enumDef = parseEnumerationTypes($enumDefData);
            $simpleType->enumDefinition($enumDef);

            # Try to resolve enum string to numeric value
            my $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, $val);

            # Fallback to default (empty string case) if unresolved
            $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, "") if $enumVal eq "";

            $val = $enumVal;
        }
    }
    # Push final resolved value into DTS representation
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

# Format and print a simple attribute value into DTS syntax
sub setDTSFormatValueForSimpleAttr {
    my ($attrName, $type, $valuesRef, $eleCnt) = @_;
    my @values = @$valuesRef;

    # Extract base type if input contains array/enum prefixes
    # e.g. "enum_uint32_t" -> "uint32", "array_enum_uint32_t" -> "uint32"
    if ($type =~ /array/ or $type =~ /enum/) {
        $type = substr($type, 0, rindex($type, "_"));
        $type = substr($type, rindex($type, "_") + 1);
    }

    my $dtsFormatedVal = '';
    my $begFormatSym = '';
    my $valSize = scalar @values;

    foreach my $pValue (@values) {
        # Treat undefined or empty values as 0
        $pValue = 0 if !defined $pValue || $pValue eq "";

        if ($type =~ /int8/) {
            $begFormatSym = "[" if $begFormatSym eq "";
            if ($pValue =~ /^0x/i) {
                $pValue =~ s/0x//i;
                $pValue = "0$pValue" if length($pValue) == 1;
            } else {
                $pValue = sprintf("%02X", $pValue);
            }
            $dtsFormatedVal .= $pValue . ($valSize > 1 ? " " : "");

        } elsif ($type =~ /int16/) {
            $begFormatSym = "[" if $begFormatSym eq "";
            if ($pValue =~ /^0x/i) {
                $pValue =~ s/0x//i;
                $pValue = ("0" x (4 - length($pValue))) . $pValue;  # pad to 4 chars
            } else {
                $pValue = sprintf("%04X", $pValue);
            }
            my $fByte = substr($pValue, 0, 2);
            my $sByte = substr($pValue, 2, 2);
            $dtsFormatedVal .= "$fByte $sByte" . ($valSize > 1 ? " " : "");

        } elsif ($type =~ /int32|int64/) {
            $begFormatSym = "<" if $begFormatSym eq "";
            $dtsFormatedVal .= "$pValue" . ($valSize > 1 ? " " : "");

        } elsif ($type =~ /string/) {
            $dtsFormatedVal .= "\"$pValue\"" . ($valSize > 1 ? ", " : "");

        } else {
            # Unsupported type
            return "";
        }
    }

    # Wrap formatted value in brackets or angle brackets
    if ($begFormatSym eq "[") {
        $dtsFormatedVal = "[ " . $dtsFormatedVal . " ]";
    } elsif ($begFormatSym eq "<") {
        $dtsFormatedVal = "<" . $dtsFormatedVal . ">";
    }

    # Print the final DTS attribute line
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
    my ($phyOrAffpath, $entityPathSimpleType) = @_;
    my ($pathType, $path) = split(/:/, $phyOrAffpath);
    my @pathElements = split(/\//, $path);
    my $pathElementsSize = @pathElements;

    # Reducing one from configured array size and dividing by 2 to get path element size
    my $configpathElementsSize = ($entityPathSimpleType->arrayDimension - 1) / 2;

    if ( $configpathElementsSize < $pathElementsSize )
    {
        print "CRITICAL: The max path element size is $configpathElementsSize but the given path element size in PHYS_DEV_PATH attribute value[$phyOrAffpath] is $pathElementsSize\n";
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
