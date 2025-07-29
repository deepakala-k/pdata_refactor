#!/usr/bin/perl
# SPDX-License-Identifier: Apache-2.0

####################################################################
#                                                                  #
# This tool is used add common utility function for common task    #
#                                                                  #
####################################################################

sub getEKBAttrsFilterList
{
    my $filterFile = $_[0];

    open my $fd, $filterFile or die "Could not open $filterFile: \"$!\"";

    my %reqAttrsList;
    while ( my $line = <$fd> )
    {
        # skip comment line
        if ( $line =~ m/#/ )
        {
            next;
        }
        chomp $line;
        if ( ( substr $line, 0, 3 ) eq "FA:" )
        {
            my $attrID = substr $line, 3;
            $reqAttrsList{$attrID} = undef;
        }
    }

    close $fd;

    return (%reqAttrsList);
}

sub getReqCustomAttrsList
{
    my $filterFile = $_[0];

    open my $fd, $filterFile or die "Could not open $filterFile: \"$!\"";

    my %reqCustomAttrsList;
    while ( my $line = <$fd> )
    {
        # skip comment line
        if ( $line =~ m/#/ )
        {
            next;
        }
        chomp $line;
        if ( ( substr $line, 0, 3 ) eq "CA:" )
        {
            my $attrID = substr $line, 3;
            $reqCustomAttrsList{$attrID} = undef;
        }
    }

    close $fd;

    return (%reqCustomAttrsList);
}

sub getRequiredTgts
{
    my $filterFile = $_[0];

    open my $fd, $filterFile or die "Could not open $filterFile: \"$!\"";

    my %reqTgtsList;
    while ( my $line = <$fd> )
    {
        # skip comment line
        if ( $line =~ m/#/ )
        {
            next;
        }
        chomp $line;
        $reqTgtsList{$line} = undef;
    }

    close $fd;

    return (%reqTgtsList);
}

sub getReqAllAttrsFilterList
{
    my $filterFile = $_[0];

    open my $fd, $filterFile or die "Could not open $filterFile: \"$!\"";

    my %reqAttrsList;
    while ( my $line = <$fd> )
    {
        # skip comment line
        if ( $line =~ m/#/ )
        {
            next;
        }
        chomp $line;
        if ( ( substr $line, 0, 3 ) eq "FA:" )
        {
            # Skipping "FA:ATTR_" because target xml wont contain "ATTR_" as
            # prefix with attribute id
            my $attrID = substr $line, 8;
            $reqAttrsList{$attrID} = undef;
        }
        elsif ( ( substr $line, 0, 3 ) eq "CA:" )
        {
            my $attrID = substr $line, 3;
            $reqAttrsList{$attrID} = undef;
        }
    }

    close $fd;

    return (%reqAttrsList);
}

sub getRequiredTgtsPdbgCompPropMapList
{
    my $pdbgCompProMapFile = $_[0];

    open my $fd, $pdbgCompProMapFile or die "Could not open $pdbgCompProMapFile: \"$!\"";

    my %reqPdbgMapList;
    while ( my $line = <$fd> )
    {
        # skip comment line
        if ( $line =~ m/#/ )
        {
            next;
        }
        chomp $line;
        my @reqTgtsInfo = split( ':', $line );
        $reqPdbgMapList{$reqTgtsInfo[0]} = $reqTgtsInfo[1];
    }

    close $fd;

    return (%reqPdbgMapList);
}

sub getSpecAndDefValForComplexTypeAttr
{
    my @listOfComplexObj = @{$_[0]};
    my $arraySize = $_[1];

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
            if ( $bitsCount > 8)
            {
                $bitsCount -= 8;
                $structSpec .= 1;
            }
        }
        else
        {
            my $getNumericValFromType = $fieldType;
            $getNumericValFromType =~ s/\D//g;
            $structSpec .= $getNumericValFromType/8;
        }
    }

    # Adding spec as 1 if bit count is less than 8 after reading all fields
    if ( $bitsCount < 8 and $bitsCount != 0)
    {
        $structSpec .= 1;
    }
    elsif ( $bitsCount >= 8 )
    {
        # Adding spec as 1 continuously till reaching byte count into 0
        # (Byte count getting by dividing bit count by 8)
        my $byteCnt = $bitsCount / 8;
        while( $byteCnt > 0 ) { $structSpec .= 1; $byteCnt -= 1; }
    }

    # All complex type default value are zeros so adding directly as zeros based struct size
    my $structDefVal;
    for(my $i = 0; $i < (eval(join '+', split(//, $structSpec))) * ($arraySize eq "" ? 1 : $arraySize); $i++)
    {
        $structDefVal .= " ".sprintf("%02X", 0);
    }

    return ($structSpec, $structDefVal);
}
# need to return 1 for other modules to include this
1;
