#!/usr/bin/perl
# SPDX-License-Identifier: Apache-2.0

####################################################################
#                                                                  #
# This tool is used add common utility function to parse           #
# generated intermediate xml                                       #
#                                                                  #
####################################################################

use File::Basename;
use Data::Dumper;
my $currDir = dirname($0);
require "$currDir/utils.pl";

my $verbose = "NA";
sub initVerbose
{
    $verbose = $_[0];
}

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
    global                      => '$',
    hasStringConversion         => '$',
    hbOnly                      => '$',
    hwpfToAttrMap               => '@',
    ignoreEkb                   => '$',
    mrwRequired                 => '$',
    no_export                   => '$',
    persistency                 => '$',
    range                       => '@',
    readable                    => '$',
    virtual                     => '$',
    writeable                   => '$',
    notRequiredInDevTree        => '$',
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

sub getAttrsDef
{
    my $inXMLFile = $_[0];
    my $filterFile = $_[1];

    my %attributeDefList;

    my $inXMLData = XML::LibXML->load_xml(location => $inXMLFile);

    if ( $filterFile ne "" )
    {
print "deepa: filterFile :: $filterFile\n";
        my %reqAttrsList = getReqAllAttrsFilterList($filterFile);
        foreach my $rAttr ( sort ( keys %reqAttrsList))
        {
print "deepa: rAttr :: $rAttr\n";
            my $attrDefPath = '//attributes/attribute/id[text()=\''.$rAttr.'\']/ancestor::attribute';

            foreach my $attrDefData ( $inXMLData->findnodes($attrDefPath) )
            {
                my @ret = parseAttributeDefinition($attrDefData, $inXMLData);
                $attributeDefList{$ret[0]} = $ret[1];
            }
        }
    }
    else
    {
print "deepa: ELSEEEEEEEEEEEEEEE filterFile :: $filterFile\n";        
        my $attrDefPath = '//attributes/attribute';
        my @attribute_nodes = $inXMLData->findnodes('//attributes/attribute');
        #for my $attrDefData ( $inXMLData->findnodes($attrDefPath) )
        foreach my $attrDefData (@attribute_nodes)
        {

            my @ret = parseAttributeDefinition($attrDefData, $inXMLData);
            $attributeDefList{$ret[0]} = $ret[1];
        }
    }
    print "############################## deepa ####################\n";
    #print Dumper(\%attributeDefList);
    return (%attributeDefList)
}

sub parseAttributeDefinition
{
    my $attrDef = $_[0];
    my $inXMLData = $_[1];

    my $attrID = $attrDef->findvalue('id');
    print "deepa :: parseAttributeDefinition :: $attrID\n";
    if ( $attrID eq "" )
    {
        print "deepa :: empty\n";
        print "CRITICAL: AttributeDef ID missing in xml\n" if isVerboseReq('C');
        
        last;
    }

    if ( exists $attributeDefList{$attrID} )
    {
        print "deepa already exists\n";
        print "WARNING: AttributeDef ID: $attrID is already exists\n" if isVerboseReq('W');
        last;
    }

    my $attributeDefinition = AttributeDefinition->new(simpleType=> new SimpleType());
    my $global =  $attrDef->findvalue('global');
    if( $global ne "" )
    {
        $attributeDefinition->global($global);
    }

    my $hasStringConversion = $attrDef->findvalue('hasStringConversion');
    if( $hasStringConversion ne "")
    {
        $attributeDefinition->hasStringConversion($hasStringConversion);
    }

    my $hbOnly = $attrDef->findvalue('hbOnly');
    if( $hbOnly ne "" )
    {
        $attributeDefinition->hbOnly($hbOnly);
    }

    if( $attrDef->exists('hwpfToAttrMap') )
    {
        my $id = $attrDef->findvalue('hwpfToAttrMap/id');
        my $macro = $attrDef->findvalue('hwpfToAttrMap/macro');
        $attributeDefinition->hwpfToAttrMap($id, $macro);
    }
    my $ignoreEkb = $attrDef->findvalue('ignoreEkb');
    if( $ignoreEkb ne "")
    {
        $attributeDefinition->ignoreEkb($ignoreEkb);
    }

    my $mrwRequired = $attrDef->findvalue('mrwRequired');
    if ( $mrwRequired ne "")
    {
        $attributeDefinition->mrwRequired($mrwRequired);
    }

    my $no_export = $attrDef->findvalue('no_export');
    if ( $no_export ne "" )
    {
        $attributeDefinition->no_export($no_export);
    }

    my $persistency = $attrDef->findvalue('persistency');
    if ( $persistency ne "")
    {
        $attributeDefinition->persistency($persistency);
    }

    if ( $attrDef->exists('range') )
    {
        my $max = $attrDef->findvalue('range/max');
        my $min = $attrDef->findvalue('range/min');
        $attributeDefinition->range($max, $min);
    }

    my $virtual = $attrDef->findvalue('virtual');
    if ( $virtual ne "" )
    {
        $attributeDefinition->virtual($virtual);
    }

    if ( $attrDef->findnodes('readable')->size > 0)
    {
        $attributeDefinition->readable(1);
    }

    if ( $attrDef->findnodes('writeable')->size > 0)
    {
        $attributeDefinition->writeable(1);
    }

    if ( $attrDef->findnodes('notRequiredInDevTree')->size > 0)
    {
        $attributeDefinition->notRequiredInDevTree(1);
    }

    if( $attrDef->exists('nativeType') )
    {
        $attributeDefinition->datatype("nativeType");

        my $nativeType = NativeType->new();
        $nativeType->name($attrDef->findvalue('nativeType/name'));
        $nativeType->default($attrDef->findvalue('nativeType/default'));

        $attributeDefinition->nativeType($nativeType);
    }
    elsif ( $attrDef->exists('complexType') )
    {
        $attributeDefinition->datatype("complexType");
        my $complexType = ComplexType->new();
        $complexType->arrayDimension($attrDef->findvalue('complexType/array'));

        foreach my $field ( $attrDef->findnodes('.//complexType/field'))
        {
            my $ComplexTypeField = ComplexTypeField->new();
            $ComplexTypeField->name($field->findvalue('name'));
            $ComplexTypeField->type($field->findvalue('type'));
            $ComplexTypeField->default($field->findvalue('default'));
            $ComplexTypeField->bits($field->findvalue('bits'));

            push(@{$complexType->listOfComplexTypeFields}, $ComplexTypeField);
        }
        $attributeDefinition->complexType($complexType);
    }
    elsif ( $attrDef->exists('simpleType') )
    {
        $attributeDefinition->datatype("simpleType");
        my $SimpleType = SimpleType->new();

        if( $attrDef->exists('simpleType/Target_t') )
        {
            $SimpleType->default($attrDef->findvalue('simpleType/Target_t/default'));
            $SimpleType->DataType("Target_t");
        }
        elsif( $attrDef->exists('simpleType/hbmutex'))
        {
            $SimpleType->default($attrDef->findvalue('simpleType/hbmutex/default'));
            $SimpleType->DataType("hbmutex");
        }
        elsif( $attrDef->exists('simpleType/hbrecursivemutex'))
        {
            $SimpleType->DataType("hbrecursivemutex");
        }
        else
        {
            my $type = "";
            if( $attrDef->exists('simpleType/array') )
            {
                $type = "array";
                $SimpleType->arrayDimension($attrDef->findvalue('simpleType/array'));
                my $strsize = $SimpleType->arrayDimension;
                $SimpleType->DataType("array");
            }
            elsif( $attrDef->exists('simpleType/enumeration') )
            {
                $type = "enum";
                $SimpleType->default($attrDef->findvalue('simpleType/enumeration/default'));
                $SimpleType->enumId($attrDef->findvalue('simpleType/enumeration/id'));
                $SimpleType->DataType($type);

                my $enumDefPath = '/attributes/enumerationType/id[text()=\''.$attrID.'\']/ancestor::enumerationType';
                my $enumDefData = $inXMLData->find($enumDefPath);
                if ( $enumDefData->size() > 0 )
                {
                    $SimpleType->enumDefinition(parseEnumerationTypes($enumDefData));
                }
            }

            my $primitivePath = "simpleType/int8_t | simpleType/int16_t | simpleType/int32_t | simpleType/int64_t | ";
            $primitivePath .= "simpleType/uint8_t | simpleType/uint16_t | simpleType/uint32_t | simpleType/uint64_t | ";
            $primitivePath .= "simpleType/string";

            my $primitiveType;
            foreach my $primitiveTypeTag ($attrDef->findnodes($primitivePath))
            {
                $primitiveType = $primitiveTypeTag->nodeName;
                $SimpleType->default($primitiveTypeTag->findvalue('default'));
            }

            # If attribute type is array then considering primitiveType as array value type
            if( $type eq "array" )
            {
                if ($primitiveType ne "")
                {
                    # Checking if array have enum type then enum have primitive type as well so cancat enum plus primitive type
                    if( $attrDef->exists('simpleType/enumeration') )
                    {
                        $primitiveType = "enum_".$primitiveType if $attrDef->exists('simpleType/enumeration');
                        $SimpleType->default($attrDef->findvalue('simpleType/enumeration/default'));
                        $SimpleType->enumId($attrDef->findvalue('simpleType/enumeration/id'));

                        my $enumDefPath = '/attributes/enumerationType/id[text()=\''.$attrID.'\']/ancestor::enumerationType';
                        my $enumDefData = $inXMLData->find($enumDefPath);
                        if ( $enumDefData->size() > 0 )
                        {
                            $SimpleType->enumDefinition(parseEnumerationTypes($enumDefData));
                        }
                    }
                    $SimpleType->subType($primitiveType);
                    $SimpleType->stringSize($attrDef->findvalue('simpleType/string/sizeInclNull')) if $primitiveType eq "string";;
                }
                else
                {
                    print "CRITICAL: array value data type is not found for attribute $attrID\n" if isVerboseReq('C');
                    last;
                }
            }
            elsif ( $type eq "enum" )
            {
                if ($primitiveType ne "")
                {
                    $SimpleType->subType($primitiveType);
                }
                else
                {
                    print "CRITICAL: array value data type is not found for attribute $attrID\n" if isVerboseReq('C');
                    last;
                }
            }
            else
            {
                if( $primitiveType ne "" )
                {
                    $SimpleType->DataType($primitiveType);
                    $SimpleType->stringSize($attrDef->findvalue('simpleType/string/sizeInclNull')) if $primitiveType eq "string";;
                }
                else
                {
                    print "CRITICAL: Subtype is not found for simpleType of attribute $attrID\n" if isVerboseReq('C');
                    last;
                }
            }
        }

        if( $SimpleType->default eq "")
        {
            $SimpleType->default($attrDef->findvalue('simpleType/default'));
        }
        $attributeDefinition->simpleType($SimpleType);
    }
    else
    {
        print "CRITICAL: Supported Datatype is not found for attribute $attrID\n" if isVerboseReq('C');
        last;
    }

    print "DEBUG: Attribute: $attrID\n" if isVerboseReq('D');

    return ($attrID, $attributeDefinition);
}

sub parseEnumerationTypes
{
    print "deepa parseEnumerationTypes\n";
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
        print "deepa: enumDef $enumDef\n";
        return ($enumDef);
    }
}

# Preparing struct type for MRW targets

struct MRWTarget => {
    targetType          => '$',
    targetAttrList      => '%',
};

# Preparing struct type for FAPI targets

struct FAPITarget => {
    targetParent        => '$',
    targetAttrList      => '%',
};

# Preparing struct type for Targets attribute data
struct AttributeData => {
    valueDataType          => '$',
    value                  => '$',
    complexFieldValues     => '%',
};

sub getTargetsData
{
    my $inXMLFile = $_[0];
    my $filterFile = $_[1];

    my $inXMLData = XML::LibXML->load_xml(location => $inXMLFile);

    my %mrwTargetList;
    my %fapiTargetList;

    if( $filterFile ne "" )
    {
        my %reqTgtsList = getRequiredTgts($filterFile);

        foreach my $rTgt ( sort ( keys %reqTgtsList) )
        {
            # Parse MRW Targets
            my $mrwTgtPath = '//attributes/targetInstance/type[text()=\''.$rTgt.'\']/ancestor::targetInstance';
            my $mrwTgtData = $inXMLData->findnodes($mrwTgtPath);

            if ( $mrwTgtData->size() > 0 )
            {
                foreach my $MRWTargetData ($mrwTgtData->get_nodelist)
                {
                    @ret = parseMRWTargetsData($MRWTargetData);
                    $mrwTargetList{$ret[0]} = $ret[1];
                }
            }
            else
            {
                print "CRITICAL: Required MRW target $rTgt data is not found in xml\n" if isVerboseReq('C');
            }

            # Parse FAPI Targets
            my $fapiTgtPath = '//attributes/targetType/id[text()=\''.$rTgt.'\']/ancestor::targetType';
            my $fapiTgtData = $inXMLData->findnodes($fapiTgtPath);
            if ($fapiTgtData->size() > 0 )
            {
                foreach my $FAPITargetData ($fapiTgtData->get_nodelist)
                {
                    my @ret = parseFAPITargetsData($FAPITargetData);
                    $fapiTargetList{$ret[0]} = $ret[1];
                }
            }
        }
    }
    else # Parse all MRW and FAPI targets from xml if required targets list doesn't given
    {
        my $mrwTgtPath = '//attributes/targetInstance';
        foreach my $mrwTgtData ( $inXMLData->findnodes($mrwTgtPath) )
        {
            @ret = parseMRWTargetsData($mrwTgtData);
            $mrwTargetList{$ret[0]} = $ret[1];
        }

        my $fapiTgtPath = '//attributes/targetType';
        foreach my $fapiTgtData ( $inXMLData->findnodes($fapiTgtPath) )
        {
            my @ret = parseFAPITargetsData($fapiTgtData);
            $fapiTargetList{$ret[0]} = $ret[1];
        }
    }

    return (\%mrwTargetList, \%fapiTargetList);
}

sub parseMRWTargetsData
{
    my $MRWTargetData = $_[0];

    my $MRWTargetID = $MRWTargetData->findvalue('id');
    if( $MRWTargetID eq "")
    {
        print "CRITICAL: Target \"id\" is missing for MRW target in xml\n" if isVerboseReq('C');
        last;
    }

    my $mrwTarget = MRWTarget->new();
    $mrwTarget->targetType($MRWTargetData->findvalue('type'));
    if( $mrwTarget->targetType eq "")
    {
        print "CRITICAL: Target \"type\" is missing for MRW target: $MRWTargetID in xml\n" if isVerboseReq('C');
        last;
    }

    foreach my $MRWTargetAttrData ($MRWTargetData->findnodes('.//attribute'))
    {
        my $AttrID = $MRWTargetAttrData->findvalue('id');
        if( $AttrID eq "")
        {
            print "ERROR: Attribute \"id\" is missing for MRW target: $MRWTargetID in xml\n";
            next;
        }

        my $attributeData = AttributeData->new();
        if( $MRWTargetAttrData->exists('default/field') ) # Complex type attribute
        {
            $attributeData->valueDataType("complexType");
            foreach my $field ( $MRWTargetAttrData->findnodes('.//default/field'))
            {
                my $fieldID = $field->findvalue('id');
                if( $fieldID eq "")
                {
                    print "CRITICAL: Field \"id\" is missing for complex attribute $AttrID for MRW target: $MRWTargetID in xml\n" if isVerboseReq('C');
                    next;
                }

                my $fieldValue = $field->findvalue('value');
                if( $fieldValue eq "")
                {
                    print "WARNING: Field \"value\" is missing to field id: $fieldID for attribute: $AttrID of MRW target: $MRWTargetID in xml\n" if isVerboseReq('W');
                }
                ${$attributeData->complexFieldValues}{$fieldID} = $fieldValue;
            }
            ${$mrwTarget->targetAttrList}{$AttrID} = $attributeData;
        }
        else
        {
            $attributeData->valueDataType("simpleType");
            $attributeData->value($MRWTargetAttrData->findvalue('default'));
            ${$mrwTarget->targetAttrList}{$AttrID} = $attributeData;
        }
    }

    return ( $MRWTargetID, $mrwTarget);
}

sub parseFAPITargetsData
{
    my $FAPITargetData = $_[0];

    my $FAPITargetID = $FAPITargetData->findvalue('id');
    if( $FAPITargetID eq "")
    {
        print "CRITICAL: FAPI target \"id\" is missing in xml\n" if isVerboseReq('C');
        last;
    }
    my $fapiTarget = FAPITarget->new();

    $fapiTarget->targetParent($FAPITargetData->findvalue('parent'));
    if( $fapiTarget->targetParent eq "" and $FAPITargetID ne "base")
    {
        print "ERROR: Parent \"value\" is missing for FAPI target: $FAPITargetID in xml\n" if isVerboseReq('E');
        # TODO: Need uncomment below line once common plats xml used. To add fapi targets commenting because plat specific xml doesn't contains all targets, so parent tag may not present for fapi targets which is not in plat xml.
        #last;
    }

    foreach my $FAPITargetAttrData ($FAPITargetData->findnodes('.//attribute'))
    {
        my $AttrID = $FAPITargetAttrData->findvalue('id');
        if( $AttrID eq "")
        {
            print "ERROR: Attribute \"id\" is missing for FAPI target: $FAPITargetID in xml\n" if isVerboseReq('E');
            next;
        }

        my $attributeData = AttributeData->new();
        if( $FAPITargetAttrData->exists('default/field') ) # Complex type attribute
        {
            $attributeData->valueDataType("complexType");
            foreach my $field ( $FAPITargetAttrData->findnodes('.//default/field'))
            {
                my $fieldID = $field->findvalue('id');
                if( $fieldID eq "")
                {
                    print "ERROR: Field \"id\" is missing for attribute: $AttrID for FAPI target: $FAPITargetID in xml\n" if isVerboseReq('E');
                    next;
                }

                my $fieldValue = $field->findvalue('value');
                if( $fieldValue eq "")
                {
                    print "WARNING: Field \"value\" is missing to field id: $fieldID for attribute: $AttrID of FAPI target: $FAPITargetID in xml\n" if isVerboseReq('W');
                }
                ${$attributeData->complexFieldValues}{$fieldID} = $fieldValue;
            }
            ${$fapiTarget->targetAttrList}{$AttrID} = $attributeData;
        }
        else
        {
            $attributeData->valueDataType("simpleType");
            $attributeData->value($FAPITargetAttrData->findvalue('default'));
            ${$fapiTarget->targetAttrList}{$AttrID} = $attributeData;
        }
    }

    return ($FAPITargetID, $fapiTarget);
}

# need to return 1 for other modules to include this
1;
