#!/usr/bin/perl
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

# Preparing structure type for targetInstance attribute definition
# This can used for ekb xml if ekb xml converted into targetInstance format
use Class::Struct;

struct ComplexTypeField => {
    name    => '$',
    type    => '$',
    default => '$',
    bits    => '$',
};

struct ComplexType => {
    arrayDimension          => '$',
    listOfComplexTypeFields => '@',
};

struct NativeType => {
    name    => '$',
    default => '$',
};

struct EnumDefinition => {
    default        => '$',
    enumeratorList => '@',
};

struct SimpleType => {
    DataType       => '$',
    default        => '$',
    arrayDimension => '$',
    subType        => '$',
    enumId         => '$',
    stringSize     => '$',
    enumDefinition => 'EnumDefinition',
};

struct AttributeDefinition => {
    datatype    => '$',
    nativeType  => 'NativeType',
    simpleType  => 'SimpleType',
    complexType => 'ComplexType',
};

sub isVerboseReq
{
    my $verboseLevel = $_[0];

    my $isReq = 0;
    if ( ( index( $verbose, $verboseLevel ) > -1 ) or ( index( $verbose, 'A' ) > -1 ) )
    {
        $isReq = 1;
    }
    return ($isReq);
}

sub getAttrsDef
{
    my ( $inXMLData, $filterFile ) = @_;

    my %attributeDefList;

    my @attrNodes;

    if ($filterFile)
    {
        my %reqAttrsList = getReqAllAttrsFilterList($filterFile);

        loadAllowedFilterList( $filterFile, \%reqAttrsList, "/allowedAttributes/attribute" );

        for my $rAttr ( sort keys %reqAttrsList )
        {
            my $path = "/attributes/attribute/id[text()='$rAttr']/ancestor::attribute";
            push @attrNodes, $inXMLData->findnodes($path);
        }
    }
    else
    {
        @attrNodes = $inXMLData->findnodes('/attributes/attribute');
    }

    for my $attrDefData (@attrNodes)
    {
        my ( $id, $def ) = parseAttributeDefinition( $attrDefData, $inXMLData );
        $attributeDefList{$id} = $def;
    }

    return %attributeDefList;
}

sub parseAttributeDefinition
{
    my ( $attrDef, $inXMLData ) = @_;

    my $attrID = $attrDef->findvalue('id');
    if ( $attrID eq "" )
    {
        print "CRITICAL: AttributeDef ID missing in xml\n";
        return;
    }

    if ( exists $attributeDefList{$attrID} )
    {
        print "WARNING: AttributeDef ID: $attrID already exists\n";
        return;
    }

    my $attributeDefinition = AttributeDefinition->new( simpleType => new SimpleType() );

    if ( $attrDef->exists('nativeType') )
    {
        handle_native_type( $attributeDefinition, $attrDef );
    }
    elsif ( $attrDef->exists('complexType') )
    {
        handle_complex_type( $attributeDefinition, $attrDef );
    }
    elsif ( $attrDef->exists('simpleType') )
    {
        handle_simple_type( $attributeDefinition, $attrDef, $inXMLData, $attrID );
    }
    else
    {
        print "CRITICAL: Supported Datatype is not found for attribute $attrID\n";
        return;
    }

    print "DEBUG: Attribute: $attrID\n" if isVerboseReq('D');
    return ( $attrID, $attributeDefinition );
}

# ----------------------------
# Helpers
# ----------------------------

sub handle_native_type
{
    my ( $attributeDefinition, $attrDef ) = @_;

    $attributeDefinition->datatype("nativeType");

    my $nativeType = NativeType->new();
    $nativeType->name( $attrDef->findvalue('nativeType/name') );
    $nativeType->default( $attrDef->findvalue('nativeType/default') );

    $attributeDefinition->nativeType($nativeType);
}

sub handle_complex_type
{
    my ( $attributeDefinition, $attrDef ) = @_;

    $attributeDefinition->datatype("complexType");
    my $complexType = ComplexType->new();
    $complexType->arrayDimension( $attrDef->findvalue('complexType/array') );

    foreach my $field ( $attrDef->findnodes('complexType/field') )
    {
        my $ComplexTypeField = ComplexTypeField->new();
        $ComplexTypeField->name( $field->findvalue('name') );
        $ComplexTypeField->type( $field->findvalue('type') );
        $ComplexTypeField->default( $field->findvalue('default') );
        $ComplexTypeField->bits( $field->findvalue('bits') );
        push( @{ $complexType->listOfComplexTypeFields }, $ComplexTypeField );
    }

    $attributeDefinition->complexType($complexType);
}

sub handle_simple_type
{
    my ( $attributeDefinition, $attrDef, $inXMLData, $attrID ) = @_;

    $attributeDefinition->datatype("simpleType");
    my $SimpleType = SimpleType->new();

    if ( $attrDef->exists('simpleType/Target_t') )
    {
        $SimpleType->default( $attrDef->findvalue('simpleType/Target_t/default') );
        $SimpleType->DataType("Target_t");
    }
    else
    {
        my $type = "";
        if ( $attrDef->exists('simpleType/array') )
        {
            handle_array_type( $SimpleType, $attrDef, $inXMLData, $attrID );
            $type = "array";
        }
        elsif ( $attrDef->exists('simpleType/enumeration') )
        {
            handle_enum_type( $SimpleType, $attrDef, $inXMLData, $attrID );
            $type = "enum";
        }

        my $primitivePath = join " | ",
            "simpleType/int8_t",  "simpleType/int16_t",  "simpleType/int32_t",  "simpleType/int64_t",
            "simpleType/uint8_t", "simpleType/uint16_t", "simpleType/uint32_t", "simpleType/uint64_t",
            "simpleType/string";

        my $primitiveType;
        foreach my $primitiveTypeTag ( $attrDef->findnodes($primitivePath) )
        {
            $primitiveType = $primitiveTypeTag->nodeName;
            $SimpleType->default( $primitiveTypeTag->findvalue('default') );
        }

        handle_primitive_type( $SimpleType, $attrDef, $inXMLData, $attrID, $type, $primitiveType );
    }

    if ( $SimpleType->default eq "" )
    {
        $SimpleType->default( $attrDef->findvalue('simpleType/default') );
    }

    $attributeDefinition->simpleType($SimpleType);
}

sub handle_array_type
{
    my ( $SimpleType, $attrDef, $inXMLData, $attrID ) = @_;
    $SimpleType->arrayDimension( $attrDef->findvalue('simpleType/array') );
    $SimpleType->DataType("array");
}

sub handle_enum_type
{
    my ( $SimpleType, $attrDef, $inXMLData, $attrID ) = @_;

    $SimpleType->default( $attrDef->findvalue('simpleType/enumeration/default') );
    $SimpleType->enumId( $attrDef->findvalue('simpleType/enumeration/id') );
    $SimpleType->DataType("enum");

    my $enumDefPath = "/attributes/enumerationType/id[text()='$attrID']/ancestor::enumerationType";
    my $enumDefData = $inXMLData->find($enumDefPath);
    if ( $enumDefData->size() > 0 )
    {
        $SimpleType->enumDefinition( parseEnumerationTypes($enumDefData) );
    }
}

sub handle_primitive_type
{
    my ( $SimpleType, $attrDef, $inXMLData, $attrID, $type, $primitiveType ) = @_;

    if ( $type eq "array" )
    {
        if ( $primitiveType ne "" )
        {
            if ( $attrDef->exists('simpleType/enumeration') )
            {
                $primitiveType = "enum_$primitiveType";
                $SimpleType->default( $attrDef->findvalue('simpleType/enumeration/default') );
                $SimpleType->enumId( $attrDef->findvalue('simpleType/enumeration/id') );

                my $enumDefPath = "/attributes/enumerationType/id[text()='$attrID']/ancestor::enumerationType";
                my $enumDefData = $inXMLData->find($enumDefPath);
                if ( $enumDefData->size() > 0 )
                {
                    $SimpleType->enumDefinition( parseEnumerationTypes($enumDefData) );
                }
            }
            $SimpleType->subType($primitiveType);
            $SimpleType->stringSize( $attrDef->findvalue('simpleType/string/sizeInclNull') )
                if $primitiveType eq "string";
        }
        else
        {
            print "CRITICAL: array value data type is not found for attribute $attrID\n";
            return;
        }
    }
    elsif ( $type eq "enum" )
    {
        if ( $primitiveType ne "" )
        {
            $SimpleType->subType($primitiveType);
        }
        else
        {
            $primitiveType = "uint32_t";
            $SimpleType->subType($primitiveType);
            print "DEBUG: Using default uint32_t type\n" if isVerboseReq('D');
        }
    }
    else
    {
        if ( $primitiveType ne "" )
        {
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

            $SimpleType->stringSize( $attrDef->findvalue('simpleType/string/sizeInclNull') )
                if $primitiveType eq "string";
        }
        else
        {
            print "CRITICAL: Subtype is not found for simpleType of attribute $attrID\n" if isVerboseReq('C');
            return;
        }
    }
}

sub parseEnumerationTypes
{
    my $enumDefData = $_[0];

    foreach my $enumAttrData ( $enumDefData->get_nodelist )
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
        foreach my $enumerator ( $enumAttrData->findnodes('enumerator') )
        {
            my $enumName = $enumerator->findvalue('name');
            my $enumVal  = $enumerator->findvalue('value');

            if ( $enumName eq "" )
            {
                print "ERROR: enumName is missing for enumID: $enumAttrID in xml\n" if isVerboseReq('E');
                next;
            }

            if ( $enumVal eq "" )
            {
                print "CRITICAL: enumVal is missing for enumName: $enumName to enumID: $enumAttrID in xml\n"
                    if isVerboseReq('C');
                next;
            }
            my @enumPair = ( $enumName, $enumVal );
            push( @{ $enumDef->enumeratorList }, \@enumPair );
        }

        return ($enumDef);
    }
}

# Preparing struct type for targetInstance targets

struct TargetInstance => {
    targetType     => '$',
    targetAttrList => '%',
};

# Preparing struct type for targettype targets

struct TargetType => {
    targetParent   => '$',
    targetAttrList => '%',
};

# Preparing struct type for Targets attribute data
struct AttributeData => {
    valueDataType      => '$',
    value              => '$',
    complexFieldValues => '%',
};

# Parse targetInstance and targetType data from XML
# If a filter file is provided, only required targets are parsed; otherwise, parse all
sub getTargetInstanceAndTargetTypeData
{
    my ( $inXMLData, $filterFile ) = @_;

    my ( %targetInstanceList, %targetTypeList );

    if ( $filterFile ne '' )
    {
        # Get required targets from filter file
        my %reqTgtsList = getRequiredTgts($filterFile);

        foreach my $rTgt ( sort keys %reqTgtsList )
        {

            # ------------------------
            # Parse targetInstance targets
            # ------------------------
            my $targetInstanceXPath = "/attributes/targetInstance/type[text()='$rTgt']/ancestor::targetInstance";
            my $targetInstanceNodes = $inXMLData->findnodes($targetInstanceXPath);

            if ( $targetInstanceNodes->size > 0 )
            {
                foreach my $node ( $targetInstanceNodes->get_nodelist )
                {
                    my ( $id, $obj ) = parseTargetInstanceData($node);
                    $targetInstanceList{$id} = $obj;
                }
            }
            else
            {
                print "CRITICAL: Required targetInstance target '$rTgt' not found in XML\n"
                    if isVerboseReq('C');
            }

            # ------------------------
            # Parse targetType targets
            # ------------------------
            my $targetTypeXPath = "/attributes/targetType/id[text()='$rTgt']/ancestor::targetType";
            my $targetTypeNodes = $inXMLData->findnodes($targetTypeXPath);

            if ( $targetTypeNodes->size > 0 )
            {
                foreach my $node ( $targetTypeNodes->get_nodelist )
                {
                    my ( $id, $obj ) = parseTargetTypeData($node);
                    $targetTypeList{$id} = $obj;
                }
            }
        }
    }
    else
    {
        # No filter: parse all targetInstance nodes
        foreach my $node ( $inXMLData->findnodes('/attributes/targetInstance') )
        {
            my ( $id, $obj ) = parseTargetInstanceData($node);
            $targetInstanceList{$id} = $obj;
        }

        # Parse all targetType nodes
        foreach my $node ( $inXMLData->findnodes('/attributes/targetType') )
        {
            my ( $id, $obj ) = parseTargetTypeData($node);
            $targetTypeList{$id} = $obj;
        }
    }

    return ( \%targetInstanceList, \%targetTypeList );
}

sub parseTargetInstanceData
{
    my ($eachTargetInstanceData) = @_;

    my $TargetInstanceID = $eachTargetInstanceData->findvalue('id');
    unless ($TargetInstanceID)
    {
        print "CRITICAL: Target \"id\" is missing for targetInstance target in xml\n" if isVerboseReq('C');
        return;
    }

    my $targetType = $eachTargetInstanceData->findvalue('type');
    unless ($targetType)
    {
        print "CRITICAL: Target \"type\" is missing for targetInstance target: $TargetInstanceID in xml\n"
            if isVerboseReq('C');
        return;
    }

    my $targetInstance = TargetInstance->new( targetType => $targetType );

    foreach my $TargetInstanceAttrData ( $eachTargetInstanceData->findnodes('attribute') )
    {
        my $AttrID = $TargetInstanceAttrData->findvalue('id');
        unless ($AttrID)
        {
            print "ERROR: Attribute \"id\" is missing for targetInstance target: $TargetInstanceID in xml\n";
            next;
        }

        my $attributeData;
        if ( $TargetInstanceAttrData->exists('default/field') )
        {
            $attributeData = parse_complex_attribute( $TargetInstanceID, $AttrID, $TargetInstanceAttrData );
        }
        else
        {
            $attributeData = parse_simple_attribute($TargetInstanceAttrData);
        }

        ${ $targetInstance->targetAttrList }{$AttrID} = $attributeData if $attributeData;
    }

    return ( $TargetInstanceID, $targetInstance );
}

# ----------------------------
# Helpers
# ----------------------------

sub parse_complex_attribute
{
    my ( $TargetInstanceID, $AttrID, $TargetInstanceAttrData ) = @_;

    my $attributeData = AttributeData->new( valueDataType => "complexType" );

    foreach my $field ( $TargetInstanceAttrData->findnodes('default/field') )
    {
        my $fieldID = $field->findvalue('id');
        unless ($fieldID)
        {
            print
                "CRITICAL: Field \"id\" is missing for complex attribute $AttrID of targetInstance target: $TargetInstanceID in xml\n"
                if isVerboseReq('C');
            next;
        }

        my $fieldValue = $field->findvalue('value');
        unless ($fieldValue)
        {
            print
                "WARNING: Field \"value\" is missing for field id: $fieldID in attribute: $AttrID of targetInstance target: $TargetInstanceID\n"
                if isVerboseReq('W');
        }

        ${ $attributeData->complexFieldValues }{$fieldID} = $fieldValue;
    }

    return $attributeData;
}

sub parse_simple_attribute
{
    my ($TargetInstanceAttrData) = @_;

    my $attributeData = AttributeData->new( valueDataType => "simpleType" );
    $attributeData->value( $TargetInstanceAttrData->findvalue('default') );

    return $attributeData;
}

sub parseTargetTypeData
{
    my ($TargetTypeData) = @_;

    my $TargetTypeID = $TargetTypeData->findvalue('id');
    unless ($TargetTypeID)
    {
        print "CRITICAL: targettype target \"id\" is missing in xml\n" if isVerboseReq('C');
        return;    # use return instead of last
    }

    my $targetTypeTarget = TargetType->new();
    $targetTypeTarget->targetParent( $TargetTypeData->findvalue('parent') );

    if ( $targetTypeTarget->targetParent eq "" and $TargetTypeID ne "base" )
    {
        print "ERROR: Parent \"value\" is missing for targettype target: $TargetTypeID in xml\n"
            if isVerboseReq('E');

        # TODO: Uncomment return when common plats xml is used
        # return;
    }

    foreach my $TargetTypeAttrData ( $TargetTypeData->findnodes('attribute') )
    {
        my $AttrID = $TargetTypeAttrData->findvalue('id');
        unless ($AttrID)
        {
            print "ERROR: Attribute \"id\" is missing for targettype target: $TargetTypeID in xml\n"
                if isVerboseReq('E');
            next;
        }

        my $attributeData = AttributeData->new();
        my $isComplex     = $TargetTypeAttrData->exists('default/field');

        if ($isComplex)
        {
            $attributeData->valueDataType("complexType");

            foreach my $field ( $TargetTypeAttrData->findnodes('default/field') )
            {
                my $fieldID = $field->findvalue('id');
                unless ($fieldID)
                {
                    print "ERROR: Field \"id\" is missing for attribute: $AttrID "
                        . "for targettype target: $TargetTypeID in xml\n"
                        if isVerboseReq('E');
                    next;
                }

                my $fieldValue = $field->findvalue('value');
                print "WARNING: Field \"value\" is missing for field id: $fieldID "
                    . "in attribute: $AttrID of targettype target: $TargetTypeID in xml\n"
                    if $fieldValue eq "" and isVerboseReq('W');

                ${ $attributeData->complexFieldValues }{$fieldID} = $fieldValue;
            }
        }
        else
        {
            $attributeData->valueDataType("simpleType");
            $attributeData->value( $TargetTypeAttrData->findvalue('default') );
        }

        ${ $targetTypeTarget->targetAttrList }{$AttrID} = $attributeData;
    }

    return ( $TargetTypeID, $targetTypeTarget );
}

# need to return 1 for other modules to include this
1;
