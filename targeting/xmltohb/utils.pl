#!/usr/bin/perl
# SPDX-License-Identifier: Apache-2.0

sub initVerbose
{
    $verbose = $_[0];
}

####################################################################
#                                                                  #
# This tool is used add common utility function for common task    #
#                                                                  #
####################################################################

sub loadAllowedFilterList
{
    my ( $xmlFile, $allowedAttrList, $pathToLook, $filterIsActive ) = @_;

    my $parser = XML::LibXML->new();
    my $doc    = $parser->parse_file($xmlFile);

    foreach my $attrNode ( $doc->findnodes($pathToLook) )
    {
        my $id = $attrNode->findvalue('@id');
        if ( $id ne "" )
        {
            $allowedAttrList->{$id} = 1;
        }
    }
    $$filterIsActive = scalar( keys %$allowedAttrList ) > 0;
}

sub getSpecAndDefValForComplexTypeAttr
{
    my @listOfComplexObj = @{ $_[0] };
    my $arraySize        = $_[1];

    # Need to prepare spec for endianess to struct type
    # To make endiness for sturct type we need to do in memberwise
    my $structSpec;
    my $bitsCount = 0;
    foreach my $complexfield (@listOfComplexObj)
    {
        my $fieldType = $complexfield->type;
        if ( $complexfield->bits ne "" )
        {
            # Addeing each field bit field required bits count and then
            # If count is crossed 8 then making spec as one an reducing 8 and continuing
            $bitsCount += $complexfield->bits;
            if ( $bitsCount > 8 )
            {
                $bitsCount -= 8;
                $structSpec .= 1;
            }
        }
        else
        {
            my $getNumericValFromType = $fieldType;
            $getNumericValFromType =~ s/\D//g;
            $structSpec .= $getNumericValFromType / 8;
        }
    }

    # Adding spec as 1 if bit count is less than 8 after reading all fields
    if ( $bitsCount < 8 and $bitsCount != 0 )
    {
        $structSpec .= 1;
    }
    elsif ( $bitsCount >= 8 )
    {
        # Adding spec as 1 continuously till reaching byte count into 0
        # (Byte count getting by dividing bit count by 8)
        my $byteCnt = $bitsCount / 8;
        while ( $byteCnt > 0 ) { $structSpec .= 1; $byteCnt -= 1; }
    }

    # All complex type default value are zeros so adding directly as zeros based struct size
    my $structDefVal;
    for (
        my $i = 0;
        $i < ( eval( join '+', split( //, $structSpec ) ) ) * ( $arraySize eq "" ? 1 : $arraySize );
        $i++
        )
    {
        $structDefVal .= " " . sprintf( "%02X", 0 );
    }

    return ( $structSpec, $structDefVal );
}

# need to return 1 for other modules to include this
1;
