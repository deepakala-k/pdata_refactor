#!/usr/bin/perl
# SPDX-License-Identifier: Apache-2.0

###############################################################
#                                                             #
# This tool will generate attributes info db file which will  #
# contain required attributes info to read/write from device  #
# tree file by using attribut tool.                           #
#                                                             #
###############################################################

use File::Basename;
use XML::LibXML;
use Getopt::Long;
use strict;
use Class::Struct;

my $currDir = dirname($0);

require "$currDir/parseIntermediateXMLUtils.pl";

my $tool = basename($0);
# To store commandline arguments
my $inXMLFile;
my $attrsInfoDbFileName;
my $filterAttrsFile;
my $help;
my $myVerbose;

# To store xml data
my %attributeDefList;

my $attrPrefix = "ATTR_";
my $AInfoDBFH;
my %infoDBAttrsList;

struct InfoDBAttrMetaData => {
    datatype         => '$',
    dimType          => '$',
    dimList          => '@',
    stringLen        => '$',
    complexTypeSpec  => '$',
    enumCount        => '$',
    enumValList      => '@',
    isDefined        => '$',
    defaultVal       => '$',
    index            => '$',
};

# Process commandline options

GetOptions( "inXML:s"            => \$inXMLFile,
            "outInfoDB:s"        => \$attrsInfoDbFileName,
            "help"               => \$help,
            "verbose=s",         => \$myVerbose
          );


if ( $help )
{
    printUsage();
    exit 0;
}
if ( $inXMLFile eq "")
{
    print "--inXML is required with xml file which should contain all fapi and non-fapi attributes to generate infodb file\n";
    exit 1;
}
if ( $attrsInfoDbFileName eq "" )
{
    print "--outInfoDB is required with output infodb file name to store generated required attribute meta data\n";
    exit 1;
}
if ( ( $attrsInfoDbFileName ne "") and !($attrsInfoDbFileName =~ m/\.db/) )
{
    print "The given infodb file name \"$attrsInfoDbFileName\" is not with expected extension. So please use .db\n";
    exit 1;
}

# Start from main function
main();

###############################
#      Subroutine Begin       #
###############################

sub printUsage
{
    print "
Description:

    *   This tool will generate attributes meta data infodb file which will contain
        required attributes info to read/write from device tree file and generated infodb
        will use for attribute tool.
        Note: This tool will expect MRW attributes definition format.\n" if $help;

    print "
Usage of $tool:

    -i|--inXML          : [M] :  Used to give xml name which is contains attributes
                                 information.
                                 Note: This tool will expect MRW attributes definition
                                 format.
                                 E.g.: --inXML <xml_file>

    -o|--outInfoDB      : [M] :  Used to give output infodb file name
                                 E.g.: --outInfoDB <attributes_info.db>

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

    %attributeDefList = getAttrsDef( $inXMLFile, $filterAttrsFile );

    createInfodbFile();
    my $fileName = substr($attrsInfoDbFileName, rindex($attrsInfoDbFileName, "/") + 1);
    print "\n$fileName is successfully created...\n";
}

sub createInfodbFile
{
    open $AInfoDBFH , '>', $attrsInfoDbFileName or die "Could not open \"$attrsInfoDbFileName\": \"$!\"";

    prepareInfoDBFile();

    close $AInfoDBFH;
}

sub prepareInfoDBFile
{
    addAttrsData();
    addTgtsData();
}

sub addAttrsData
{
    getInfoDBAttrsData();
    my $attrsNameList = "all";
    my $allAttrsMetaData;

    foreach my $attr (sort(keys %infoDBAttrsList))
    {
        $attrsNameList .= " $attrPrefix$attr";
        $allAttrsMetaData .= "$attrPrefix$attr";

        my $datatype = $infoDBAttrsList{$attr}->datatype;
        $datatype =~ s/_t//g; # Removing _t for primitive type i.e int8_t => int8
        $allAttrsMetaData .= " ".$datatype;

        if($infoDBAttrsList{$attr}->datatype eq "complex")
        {
            $allAttrsMetaData .= " ".$infoDBAttrsList{$attr}->complexTypeSpec;
        }
        if($infoDBAttrsList{$attr}->datatype eq "str")
        {
            $allAttrsMetaData .= " ".$infoDBAttrsList{$attr}->stringLen;
        }
        if($infoDBAttrsList{$attr}->dimType ne "") # array type
        {
            $allAttrsMetaData .= " ".$infoDBAttrsList{$attr}->dimType;
            $allAttrsMetaData .= " @{$infoDBAttrsList{$attr}->dimList}";
        }
        else
        {
            $allAttrsMetaData .= " 0"; # If attribute is not array type
        }
        if($infoDBAttrsList{$attr}->enumCount ne "") # enum type
        {
            $allAttrsMetaData .= " ".$infoDBAttrsList{$attr}->enumCount;
            foreach my $enumpair ( @{$infoDBAttrsList{$attr}->enumValList} )
            {
                $allAttrsMetaData .= " $enumpair->[0] $enumpair->[1]";
            }
        }
        elsif(($infoDBAttrsList{$attr}->datatype ne "str") and
            ($infoDBAttrsList{$attr}->datatype ne "complex"))
        {
            $allAttrsMetaData .= " 0"; # If attribute is not enum,string and complex
        }
        $allAttrsMetaData .= " 0"; # default value not added into info db

        # Continue next attribute to get all attributes data for add into info db
        $allAttrsMetaData .= "\n";
    }

    # Adding attribute list with name
    print {$AInfoDBFH} "$attrsNameList\n";
    # Adding all attribute meta data
    print {$AInfoDBFH} "$allAttrsMetaData";
}

sub getInfoDBAttrsData
{
    my $index = 0;
    foreach my $attr (sort(keys %attributeDefList))
    {
        # Don't add the attributes if that not required in the device tree
        # attributes list.
        if (defined $attributeDefList{$attr}->notRequiredInDevTree && 
        $attributeDefList{$attr}->notRequiredInDevTree eq "1")
        {
            next;
        }

        my $infoDBAttrMetaData = InfoDBAttrMetaData->new();
        if ($attributeDefList{$attr}->datatype eq "simpleType")
        {
            if ($attributeDefList{$attr}->simpleType->DataType eq "array")
            {
                if ($attributeDefList{$attr}->simpleType->subType =~ m/enum_/)
                {
                    my $attrDataType = $attributeDefList{$attr}->simpleType->subType;
                    $attrDataType =~ s/enum_//g;
                    $infoDBAttrMetaData->datatype($attrDataType);

                    $infoDBAttrMetaData->enumCount(scalar(@{$attributeDefList{$attr}->simpleType->enumDefinition->enumeratorList}));
                    $infoDBAttrMetaData->enumValList(\@{$attributeDefList{$attr}->simpleType->enumDefinition->enumeratorList});
                }
                elsif($attributeDefList{$attr}->simpleType->subType =~ m/string/)
                {
                    $infoDBAttrMetaData->datatype("str");
                    $infoDBAttrMetaData->stringLen($attributeDefList{$attr}->simpleType->stringSize);
                }
                else
                {
                    $infoDBAttrMetaData->datatype($attributeDefList{$attr}->simpleType->subType);
                }

                my @dimList = split(',', $attributeDefList{$attr}->simpleType->arrayDimension);
                $infoDBAttrMetaData->dimType(scalar(@dimList));
                $infoDBAttrMetaData->dimList(\@dimList);
            }
            elsif ($attributeDefList{$attr}->simpleType->DataType eq "enum")
            {
                $infoDBAttrMetaData->datatype($attributeDefList{$attr}->simpleType->subType);
                $infoDBAttrMetaData->enumCount(scalar(@{$attributeDefList{$attr}->simpleType->enumDefinition->enumeratorList}));
                $infoDBAttrMetaData->enumValList(\@{$attributeDefList{$attr}->simpleType->enumDefinition->enumeratorList});
            }
            elsif ($attributeDefList{$attr}->simpleType->DataType eq "string")
            {
                $infoDBAttrMetaData->datatype("str");
                $infoDBAttrMetaData->stringLen($attributeDefList{$attr}->simpleType->stringSize);
            }
            else
            {
                $infoDBAttrMetaData->datatype($attributeDefList{$attr}->simpleType->DataType);
            }
        }
        elsif ($attributeDefList{$attr}->datatype eq "complexType")
        {
            $infoDBAttrMetaData->datatype("complex");
            my ($spec, $defVal) = getSpecAndDefValForComplexTypeAttr(\@{$attributeDefList{$attr}->complexType->listOfComplexTypeFields}, $attributeDefList{$attr}->complexType->arrayDimension);
            $infoDBAttrMetaData->complexTypeSpec($spec);

            if ($attributeDefList{$attr}->complexType->arrayDimension ne "")
            {
                my @dimList = split(',', $attributeDefList{$attr}->complexType->arrayDimension);
                $infoDBAttrMetaData->dimType(scalar(@dimList));
                $infoDBAttrMetaData->dimList(\@dimList);
            }
        }
        else
        {
            print "ERROR: Unsupported type for $attr...skipping\n" if isVerboseReq('E');
            next;
        }
        $infoDBAttrMetaData->index($index++);
        $infoDBAttrsList{$attr} = $infoDBAttrMetaData;
    }
}

sub addTgtsData
{
    my %uniqueTgts = %{getInfoDBTgtsData()};

    my $tgtsList = "targets";
    my $tgtsAttsIndex;
    foreach my $tgt (sort(keys %uniqueTgts))
    {
        $tgtsList .= " $tgt";
        $tgtsAttsIndex .= "$tgt";
        foreach my $attr (sort (keys %{$uniqueTgts{$tgt}}))
        {
            $tgtsAttsIndex .= " ".$uniqueTgts{$tgt}{$attr};
        }
        $tgtsAttsIndex .= "\n";
    }

    # Adding targets list with name
    print {$AInfoDBFH} "$tgtsList\n";
    # Adding all targets with attributes index which are consumed by respective targets
    print {$AInfoDBFH} "$tgtsAttsIndex";
}

sub getInfoDBTgtsData
{
    my @ret = getTargetsData($inXMLFile, "");
    my %mrwTargetList = %{$ret[0]};
    my %fapiTargetList = %{$ret[1]};

    my %uniqueTgts;

    # Note: No need to process MRW targets, because generating info
    # db does not required attributes value.
    # Preparing FAPI targets with attributes index
    foreach my $FAPITgt (keys %fapiTargetList)
    {
        foreach my $attr (keys %{$fapiTargetList{$FAPITgt}->targetAttrList})
        {
            # Don't add the attributes if that not required in the device tree
            # attributes list.
            if (defined $attributeDefList{$attr} &&
            $attributeDefList{$attr}->notRequiredInDevTree &&
            $attributeDefList{$attr}->notRequiredInDevTree eq "1")
            {
                next;
            }
            if (!exists $uniqueTgts{$FAPITgt}{$attr})
            {
                if (defined $attributeDefList{$attr}) {
                    $uniqueTgts{$FAPITgt}{$attr} = $infoDBAttrsList{$attr}->index;
                }
            }
        }
    }

    return \%uniqueTgts;
}
