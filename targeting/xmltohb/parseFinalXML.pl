#!/usr/bin/env perl
# SPDX-License-Identifier: Apache-2.0

####################################################################
#                                                                  #
# This tool is used add common utility function to parse           #
# generated intermediate xml                                       #
#                                                                  #
####################################################################

use File::Basename;
my $currDir = dirname($0);
require "$currDir/utils.pl";

my $verbose = "";

# Preparing structure type for MRW attribute definition
# This can used for ekb xml if ekb xml converted into MRW format
use Class::Struct;

struct ComplexTypeField => {
    name        => '$',
    type        => '$',
    default     => '$',
    bits        => '$',
};

struct ComplexType => {
    arrayDimension          => '$',
    listOfComplexTypeFields => '@',
};

struct NativeType => {
    name        => '$',
    default     => '$',
};

struct EnumDefinition => {
    default             => '$',
    enumeratorList      => '@',
};

struct SimpleType => {
    DataType            => '$',
    default             => '$',
    arrayDimension      => '$',
    subType           => '$',
    enumId              => '$',
    stringSize          => '$',
    enumDefinition      => 'EnumDefinition',
};

struct AttributeDefinition => {
    datatype                    => '$',
    nativeType                  => 'NativeType',
    simpleType                  => 'SimpleType',
    complexType                 => 'ComplexType',
};

sub isVerboseReq
{
    my $verboseLevel = $_[0];

    my $isReq = 0;
    if ( ( index($verbose, $verboseLevel ) > -1) or ( index($verbose, 'A') > -1 ) )
    {
        $isReq = 1;
    }
    return ( $isReq )
}

sub getAttrsDef {
    my ($inXMLFile, $filterFile) = @_;

    my %attributeDefList;
    my $inXMLData = XML::LibXML->load_xml(location => $inXMLFile);

    my @attrNodes;

    if ($filterFile) {
        my %reqAttrsList = getReqAllAttrsFilterList($filterFile);

        loadAllowedFilterList(
            $filterFile,
            \%reqAttrsList,
            "/allowedAttributes/attribute"
        );

        for my $rAttr (sort keys %reqAttrsList) {
            my $path = "/attributes/attribute/id[text()='$rAttr']/ancestor::attribute";
            push @attrNodes, $inXMLData->findnodes($path);
        }
    }
    else {
        @attrNodes = $inXMLData->findnodes('/attributes/attribute');
    }

    for my $attrDefData (@attrNodes) {
        my ($id, $def) = parseAttributeDefinition($attrDefData, $inXMLData);
        $attributeDefList{$id} = $def;
    }

    return %attributeDefList;
}


sub parseAttributeDefinition {
    my ($attrDef, $inXMLData) = @_;

    my $attrID = $attrDef->findvalue('id');
    if ($attrID eq "") {
        print "CRITICAL: AttributeDef ID missing in xml\n";
        return;
    }

    if (exists $attributeDefList{$attrID}) {
        print "WARNING: AttributeDef ID: $attrID already exists\n";
        return;
    }

    my $attributeDefinition = AttributeDefinition->new(simpleType => new SimpleType());

    if ($attrDef->exists('nativeType')) {
        _handle_native_type($attributeDefinition, $attrDef);
    }
    elsif ($attrDef->exists('complexType')) {
        _handle_complex_type($attributeDefinition, $attrDef);
    }
    elsif ($attrDef->exists('simpleType')) {
        _handle_simple_type($attributeDefinition, $attrDef, $inXMLData, $attrID);
    }
    else {
        print "CRITICAL: Supported Datatype is not found for attribute $attrID\n";
        return;
    }

    print "DEBUG: Attribute: $attrID\n" if isVerboseReq('D');
    return ($attrID, $attributeDefinition);
}

# ----------------------------
# Helpers
# ----------------------------

sub _handle_native_type {
    my ($attributeDefinition, $attrDef) = @_;

    $attributeDefinition->datatype("nativeType");

    my $nativeType = NativeType->new();
    $nativeType->name($attrDef->findvalue('nativeType/name'));
    $nativeType->default($attrDef->findvalue('nativeType/default'));

    $attributeDefinition->nativeType($nativeType);
}

sub _handle_complex_type {
    my ($attributeDefinition, $attrDef) = @_;

    $attributeDefinition->datatype("complexType");
    my $complexType = ComplexType->new();
    $complexType->arrayDimension($attrDef->findvalue('complexType/array'));

    foreach my $field ($attrDef->findnodes('complexType/field')) {
        my $ComplexTypeField = ComplexTypeField->new();
        $ComplexTypeField->name($field->findvalue('name'));
        $ComplexTypeField->type($field->findvalue('type'));
        $ComplexTypeField->default($field->findvalue('default'));
        $ComplexTypeField->bits($field->findvalue('bits'));
        push(@{$complexType->listOfComplexTypeFields}, $ComplexTypeField);
    }

    $attributeDefinition->complexType($complexType);
}

sub _handle_simple_type {
    my ($attributeDefinition, $attrDef, $inXMLData, $attrID) = @_;

    $attributeDefinition->datatype("simpleType");
    my $SimpleType = SimpleType->new();

    if ($attrDef->exists('simpleType/Target_t')) {
        $SimpleType->default($attrDef->findvalue('simpleType/Target_t/default'));
        $SimpleType->DataType("Target_t");
    }
    else {
        my $type = "";
        if ($attrDef->exists('simpleType/array')) {
            _handle_array_type($SimpleType, $attrDef, $inXMLData, $attrID);
            $type = "array";
        }
        elsif ($attrDef->exists('simpleType/enumeration')) {
            _handle_enum_type($SimpleType, $attrDef, $inXMLData, $attrID);
            $type = "enum";
        }

        my $primitivePath = join " | ",
            "simpleType/int8_t", "simpleType/int16_t", "simpleType/int32_t", "simpleType/int64_t",
            "simpleType/uint8_t", "simpleType/uint16_t", "simpleType/uint32_t", "simpleType/uint64_t",
            "simpleType/string";

        my $primitiveType;
        foreach my $primitiveTypeTag ($attrDef->findnodes($primitivePath)) {
            $primitiveType = $primitiveTypeTag->nodeName;
            $SimpleType->default($primitiveTypeTag->findvalue('default'));
        }

        _handle_primitive_type($SimpleType, $attrDef, $inXMLData, $attrID, $type, $primitiveType);
    }

    if ($SimpleType->default eq "") {
        $SimpleType->default($attrDef->findvalue('simpleType/default'));
    }

    $attributeDefinition->simpleType($SimpleType);
}

sub _handle_array_type {
    my ($SimpleType, $attrDef, $inXMLData, $attrID) = @_;
    $SimpleType->arrayDimension($attrDef->findvalue('simpleType/array'));
    $SimpleType->DataType("array");
}

sub _handle_enum_type {
    my ($SimpleType, $attrDef, $inXMLData, $attrID) = @_;

    $SimpleType->default($attrDef->findvalue('simpleType/enumeration/default'));
    $SimpleType->enumId($attrDef->findvalue('simpleType/enumeration/id'));
    $SimpleType->DataType("enum");

    my $enumDefPath = "/attributes/enumerationType/id[text()='$attrID']/ancestor::enumerationType";
    my $enumDefData = $inXMLData->find($enumDefPath);
    if ($enumDefData->size() > 0) {
        $SimpleType->enumDefinition(parseEnumerationTypes($enumDefData));
    }
}

sub _handle_primitive_type {
    my ($SimpleType, $attrDef, $inXMLData, $attrID, $type, $primitiveType) = @_;

    if ($type eq "array") {
        if ($primitiveType ne "") {
            if ($attrDef->exists('simpleType/enumeration')) {
                $primitiveType = "enum_$primitiveType";
                $SimpleType->default($attrDef->findvalue('simpleType/enumeration/default'));
                $SimpleType->enumId($attrDef->findvalue('simpleType/enumeration/id'));

                my $enumDefPath = "/attributes/enumerationType/id[text()='$attrID']/ancestor::enumerationType";
                my $enumDefData = $inXMLData->find($enumDefPath);
                if ($enumDefData->size() > 0) {
                    $SimpleType->enumDefinition(parseEnumerationTypes($enumDefData));
                }
            }
            $SimpleType->subType($primitiveType);
            $SimpleType->stringSize($attrDef->findvalue('simpleType/string/sizeInclNull')) if $primitiveType eq "string";
        }
        else {
            print "CRITICAL: array value data type is not found for attribute $attrID\n";
            return;
        }
    }
    elsif ($type eq "enum") {
        if ($primitiveType ne "") {
            $SimpleType->subType($primitiveType);
        }
        else {
            $primitiveType = "uint32_t";
            $SimpleType->subType($primitiveType);
            print "DEBUG: Using default uint32_t type\n" if isVerboseReq('D');
        }
    }
    else {
        if ($primitiveType ne "") {
            $SimpleType->DataType($primitiveType);

            # TODO remove it
            # my $val = $SimpleType->default;
            # if (defined $val && $val ne "" &&
            #     $val !~ /^-?\d+$/ &&
            #     $val !~ /^0x[0-9A-Fa-f]+$/ &&
            #     $primitiveType ne "string") {

            #     $SimpleType->enumId($attrDef->findvalue('simpleType/enumeration/id'));
            #     my $enumDefPath = "/attributes/enumerationType/id[text()='$attrID']/ancestor::enumerationType";
            #     my $enumDefData = $inXMLData->find($enumDefPath);
            #     if ($enumDefData->size() > 0) {
            #         $SimpleType->enumDefinition(parseEnumerationTypes($enumDefData));
            #     }
            # }

            $SimpleType->stringSize($attrDef->findvalue('simpleType/string/sizeInclNull')) if $primitiveType eq "string";
        }
        else {
            print "CRITICAL: Subtype is not found for simpleType of attribute $attrID\n" if isVerboseReq('C');
            return;
        }
    }
}


sub parseEnumerationTypes
{
    my $enumDefData = $_[0];

    foreach my $enumAttrData ($enumDefData->get_nodelist)
    {
        my $enumAttrID = $enumAttrData->findvalue('id');
        if ( $enumAttrID eq "" )
        {
            print "CRITICAL: Enumeration attribute id is missing in xml\n" if isVerboseReq('C');
            next;
        }

        if ( exists $enumAttrList{$enumAttrID} )
        {
            print "WARNING: Enumeration attribute id: $enumAttrID is already exists\n" if isVerboseReq('W');
            next;
        }

        my $defaultValue = $enumAttrData->findvalue('default');

        my $enumDef = EnumDefinition->new();
        $enumDef->default($defaultValue);
        foreach my $enumerator ($enumAttrData->findnodes('enumerator'))
        {
            my $enumName = $enumerator->findvalue('name');
            my $enumVal = $enumerator->findvalue('value');

            if ( $enumName eq "")
            {
                print "ERROR: enumName is missing for enumID: $enumAttrID in xml\n" if isVerboseReq('E');
                next;
            }

            if ( $enumVal eq "")
            {
                print "CRITICAL: enumVal is missing for enumName: $enumName to enumID: $enumAttrID in xml\n" if isVerboseReq('C');
                next;
            }
            my @enumPair = ( $enumName, $enumVal );
            push (@{$enumDef->enumeratorList}, \@enumPair);
        }

        return ($enumDef);
    }
}

# Preparing struct type for MRW targets

struct TargetInstance => {
    targetType          => '$',
    targetAttrList      => '%',
};

# Preparing struct type for FAPI targets

struct TargetType => {
    targetParent        => '$',
    targetAttrList      => '%',
};

# Preparing struct type for Targets attribute data
struct AttributeData => {
    valueDataType          => '$',
    value                  => '$',
    complexFieldValues     => '%',
};

sub getTargetInstanceAndTargetTypeData
{
    my $inXMLFile = $_[0];
    my $filterFile = $_[1];

    my $inXMLData = XML::LibXML->load_xml(location => $inXMLFile);

    my %targetInstanceList;
    my %targetTypeList;

    if( $filterFile ne "" )
    {
        my %reqTgtsList = getRequiredTgts($filterFile);

        foreach my $rTgt ( sort ( keys %reqTgtsList) )
        {
            # Parse MRW Targets
            my $TargetInstanceTgtPath = '/attributes/targetInstance/type[text()=\''.$rTgt.'\']/ancestor::targetInstance';
            my $targetInstanceTargetData = $inXMLData->findnodes($TargetInstanceTgtPath);

            if ( $targetInstanceTargetData->size() > 0 )
            {
                foreach my $eachTargetInstanceData ($targetInstanceTargetData->get_nodelist)
                {
                    @ret = parseTargetInstanceData($eachTargetInstanceData);
                    $targetInstanceList{$ret[0]} = $ret[1];
                }
            }
            else
            {
                print "CRITICAL: Required MRW target $rTgt data is not found in xml\n" if isVerboseReq('C');
            }

            # Parse FAPI Targets
            my $targetTypeTargetPath = '/attributes/targetType/id[text()=\''.$rTgt.'\']/ancestor::targetType';
            my $targetTypeTargetData = $inXMLData->findnodes($targetTypeTargetPath);
            if ($targetTypeTargetData->size() > 0 )
            {
                foreach my $TargetTypeData ($targetTypeTargetData->get_nodelist)
                {
                    my @ret = parseTargetTypeData($TargetTypeData);
                    $targetTypeList{$ret[0]} = $ret[1];
                }
            }
        }
    }
    else # Parse all MRW and FAPI targets from xml if required targets list doesn't given
    {
        my $TargetInstanceTgtPath = '/attributes/targetInstance';
        foreach my $targetInstanceTargetData ( $inXMLData->findnodes($TargetInstanceTgtPath) )
        {
            @ret = parseTargetInstanceData($targetInstanceTargetData);
            $targetInstanceList{$ret[0]} = $ret[1];
        }

        my $targetTypeTargetPath = '/attributes/targetType';
        foreach my $targetTypeTargetData ( $inXMLData->findnodes($targetTypeTargetPath) )
        {
            my @ret = parseTargetTypeData($targetTypeTargetData);
            $targetTypeList{$ret[0]} = $ret[1];
        }
    }

    return (\%targetInstanceList, \%targetTypeList);
}

sub parseTargetInstanceData {
    my ($eachTargetInstanceData) = @_;

    my $MRWTargetID = $eachTargetInstanceData->findvalue('id');
    unless ($MRWTargetID) {
        print "CRITICAL: Target \"id\" is missing for MRW target in xml\n" if isVerboseReq('C');
        return;
    }

    my $targetType = $eachTargetInstanceData->findvalue('type');
    unless ($targetType) {
        print "CRITICAL: Target \"type\" is missing for MRW target: $MRWTargetID in xml\n" if isVerboseReq('C');
        return;
    }

    my $mrwTarget = TargetInstance->new(targetType => $targetType);

    foreach my $MRWTargetAttrData ($eachTargetInstanceData->findnodes('attribute')) {
        my $AttrID = $MRWTargetAttrData->findvalue('id');
        unless ($AttrID) {
            print "ERROR: Attribute \"id\" is missing for MRW target: $MRWTargetID in xml\n";
            next;
        }

        my $attributeData;
        if ($MRWTargetAttrData->exists('default/field')) {
            $attributeData = _parse_complex_attribute($MRWTargetID, $AttrID, $MRWTargetAttrData);
        } else {
            $attributeData = _parse_simple_attribute($MRWTargetAttrData);
        }

        ${ $mrwTarget->targetAttrList }{$AttrID} = $attributeData if $attributeData;
    }

    return ($MRWTargetID, $mrwTarget);
}

# ----------------------------
# Helpers
# ----------------------------

sub _parse_complex_attribute {
    my ($MRWTargetID, $AttrID, $MRWTargetAttrData) = @_;

    my $attributeData = AttributeData->new(valueDataType => "complexType");

    foreach my $field ($MRWTargetAttrData->findnodes('default/field')) {
        my $fieldID = $field->findvalue('id');
        unless ($fieldID) {
            print "CRITICAL: Field \"id\" is missing for complex attribute $AttrID of MRW target: $MRWTargetID in xml\n"
              if isVerboseReq('C');
            next;
        }

        my $fieldValue = $field->findvalue('value');
        unless ($fieldValue) {
            print "WARNING: Field \"value\" is missing for field id: $fieldID in attribute: $AttrID of MRW target: $MRWTargetID\n"
              if isVerboseReq('W');
        }

        ${ $attributeData->complexFieldValues }{$fieldID} = $fieldValue;
    }

    return $attributeData;
}

sub _parse_simple_attribute {
    my ($MRWTargetAttrData) = @_;

    my $attributeData = AttributeData->new(valueDataType => "simpleType");
    $attributeData->value($MRWTargetAttrData->findvalue('default'));

    return $attributeData;
}


sub parseTargetTypeData {
    my ($TargetTypeData) = @_;

    my $FAPITargetID = $TargetTypeData->findvalue('id');
    unless ($FAPITargetID) {
        print "CRITICAL: FAPI target \"id\" is missing in xml\n" if isVerboseReq('C');
        return; # use return instead of last
    }

    my $fapiTarget = TargetType->new();
    $fapiTarget->targetParent($TargetTypeData->findvalue('parent'));

    if ($fapiTarget->targetParent eq "" and $FAPITargetID ne "base") {
        print "ERROR: Parent \"value\" is missing for FAPI target: $FAPITargetID in xml\n"
            if isVerboseReq('E');
        # TODO: Uncomment return when common plats xml is used
        # return;
    }

    foreach my $FAPITargetAttrData ($TargetTypeData->findnodes('attribute')) {
        my $AttrID = $FAPITargetAttrData->findvalue('id');
        unless ($AttrID) {
            print "ERROR: Attribute \"id\" is missing for FAPI target: $FAPITargetID in xml\n"
                if isVerboseReq('E');
            next;
        }

        my $attributeData = AttributeData->new();
        my $isComplex = $FAPITargetAttrData->exists('default/field');

        if ($isComplex) {
            $attributeData->valueDataType("complexType");

            foreach my $field ($FAPITargetAttrData->findnodes('default/field')) {
                my $fieldID = $field->findvalue('id');
                unless ($fieldID) {
                    print "ERROR: Field \"id\" is missing for attribute: $AttrID "
                        . "for FAPI target: $FAPITargetID in xml\n"
                        if isVerboseReq('E');
                    next;
                }

                my $fieldValue = $field->findvalue('value');
                print "WARNING: Field \"value\" is missing for field id: $fieldID "
                    . "in attribute: $AttrID of FAPI target: $FAPITargetID in xml\n"
                    if $fieldValue eq "" and isVerboseReq('W');

                ${ $attributeData->complexFieldValues }{$fieldID} = $fieldValue;
            }
        } else {
            $attributeData->valueDataType("simpleType");
            $attributeData->value($FAPITargetAttrData->findvalue('default'));
        }

        ${ $fapiTarget->targetAttrList }{$AttrID} = $attributeData;
    }

    return ($FAPITargetID, $fapiTarget);
}

# need to return 1 for other modules to include this
1;
