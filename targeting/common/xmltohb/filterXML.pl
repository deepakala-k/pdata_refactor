#!/usr/bin/perl
# SPDX-License-Identifier: Apache-2.0

############################################################################
#                                                                          #
#   This script is used to filter only required targets and attributes     #
#   from input xml file                                                    #
#                                                                          #
############################################################################

use XML::LibXML;
use Getopt::Long;
use strict;

# If getting "Can't locate utils.pl" error
# during execution of this script then follow below steps.
# export PERL5LIB=pathoffilterXML.pl
# or 
# perl -I pathoffilterXML.pl path/filterXML.pl
# because perl will check in @INC for all perl modules existence
# and utils.pl script is this project specific so, need include path
# to resolve error
require 'utils.pl';

# Global variables list begin

# To mention this tool name in log if unsupported things tried
my $tool = $0;
# To store commandline arguments
my $inXMLFile;
my $filterAttrsFile;
my $filterTgtsFile;
my $outXMLFile;
my $help;
my $filterType;

my $inXMLData;
my %reqAttrsList;
my $outFH;
my %reqTgtsList;
# Global variables list end

# Process commandline options

GetOptions( "inXML:s"        => \$inXMLFile,
            "outXML:s"       => \$outXMLFile,
            "filterType:s"   => \$filterType,
            "filterAttrsFile:s"   => \$filterAttrsFile,
            "filterTgtsFile:s"    => \$filterTgtsFile,
            "help"           => \$help
          );

if ( $help )
{
    printUsage();
    exit 0;
}
if ( $inXMLFile eq "" )
{
    print "--inXML is required with input xml file for filter.\nPlease use --help to get know more about this tool\n";
    exit 1;
}
if ( $filterType eq "" )
{
    print "--filterType is required to mention input xml format.\nPlease use --help to get know supported xml format type for filter\n";
    exit 1;
}
# Checking given filter type to check its supported or not
if ( $filterType ne "ekbAttrsXML" and $filterType ne "customAttrsXML" and $filterType ne "customTgtXML" and $filterType ne "systemXML" )
{
    print "The given filterType : \"$filterType\" is not supported.\nPlease check by --help to get know supported xml format type for filter\n";
    exit 1;
}
elsif ( $filterType eq "customTgtXML" )
{
    if ( $filterTgtsFile eq "" )
    {
        print "--filterTgtsFile is required with targets list file to filter targets along with attributes.\nPlease check by --help to get know file format\n";
        exit 1;
    }
}
if ( $filterAttrsFile eq "" )
{
    print "--filterAttrsFile is required with attributes list file to filter attribute.\nPlease check by --help to get know file format\n";
    exit 1;
}
if ( $outXMLFile eq "" )
{
    print "--outXML is required with output xml file to store requested filtered data\n";
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

    *   This script is used to filter only required targets and attributes from input xml file.\n" if $help;

    print "
Usage of $tool:

    --inXML           : [M] :  Used to give input xml file to filter.
                               E.g. : --inXML <inputXMLFile.xml>
    --outXML          : [M] :  Used to give output xml file to store filtered data.
                               E.g. : --outXML <outputXMLFile.xml>

    --filterType      : [M] :  Used to give filter type i.e input xml file format.
                               Supported filter type
                                - ekbAttrsXML    -> To filter ekb hwp attributes xml file
                                - customAttrsXML -> To filter custom plats attributes definition
                                - customTgtXML   -> To filter custom plats targets xml file
                                - systemXML      -> To filter system xml file
                               E.g. : --filterType <ekbAttrsXML/customAttrsXML/customTgtXML/systemXML> 
    --filterAttrsFile : [M] :  Used to give required attributes list in lsv file.
                               FAPI Attribute should be prefix with \"FA:\"
                               Non-FAPI Attribute should be prefix with \"CA:\"
                               E.g. : --filterAttrsFile <systemName_FilterAttrsList.lsv>

    --filterTgtsFile  : [C] :  Used to give required targets list in lsv file.
                               This is conditional argument based --filterType i.e if type is
                               customTgtXML or systemXML then this is required
                               E.g. : --filterTgtsFile <systemName_FilterTgtsList.lsv>

    --help            : [O] :  To print the tool usage
";
}

sub main
{
    my $tmpFile = $outXMLFile.".tmp";
    open $outFH, '>', $tmpFile or die "Could not open $tmpFile\"$!\"";
    $inXMLData = XML::LibXML->load_xml(location => $inXMLFile);

    print {$outFH} "<attributes>\n";

    if ( $filterType eq "ekbAttrsXML" )
    {
        %reqAttrsList = getEKBAttrsFilterList($filterAttrsFile);
        filterEKBAttrsDef();
    }
    elsif ( $filterType eq "customAttrsXML" )
    {
        %reqAttrsList = getReqCustomAttrsList($filterAttrsFile);
        filterCustomAttrs();
    }
    elsif ( $filterType eq "customTgtXML" )
    {
        %reqTgtsList = getRequiredTgts($filterTgtsFile);
        %reqAttrsList = getReqAllAttrsFilterList($filterAttrsFile);
        filterCustomTgts();
    }
    elsif ( $filterType eq "systemXML" )
    {
        %reqTgtsList = getRequiredTgts($filterTgtsFile);
        %reqAttrsList = getReqAllAttrsFilterList($filterAttrsFile);
        filterSystemTgts();
    }

    print {$outFH} "</attributes>";

    close $outFH;
    alignPreparedXML($tmpFile);
    # Removing tmp file
    unlink $tmpFile;
}

sub filterEKBAttrsDef
{
    foreach my $rAttr ( sort ( keys %reqAttrsList))
    {
        my $attrDefPath = '/attributes/attribute/id[text()=\''.$rAttr.'\']/ancestor::attribute';
        getReqData($attrDefPath, 'attribute');
    }
}

sub filterCustomAttrs
{
    foreach my $rAttr ( sort ( keys %reqAttrsList))
    {
        my $attrDefPath = '/attributes/attribute/id[text()=\''.$rAttr.'\']/ancestor::attribute';
        getReqData($attrDefPath, 'attribute');
    }
}

sub filterCustomTgts
{
    foreach my $rTgt ( sort ( keys %reqTgtsList ) )
    {
        my $tgtPath = '/attributes/targetType/id[text()=\''.$rTgt.'\']/ancestor::targetType';
        getReqData($tgtPath, 'targetType');
    }
}

sub filterSystemTgts
{
    print {$outFH} "<version>".$inXMLData->findvalue('/attributes/version')."</version>";
    foreach my $rTgt ( sort ( keys %reqTgtsList ) )
    {
        my $tgtPath = '/attributes/targetInstance/type[text()=\''.$rTgt.'\']/ancestor::targetInstance';
        getReqData($tgtPath, 'targetInstance');
    }
}

sub getReqData
{
    my $path = $_[0];
    my $endPathTagName = $_[1];

    my $attrIsEnum;
    my $attrID;

    foreach my $node ( $inXMLData->findnodes($path) )
    {
        print {$outFH} "<$endPathTagName>\n";
        foreach my $nodeEle ( $node->childNodes() )
        {
            if( $nodeEle->nodeName eq "attribute")
            {
                $attrID = $nodeEle->findvalue('id');

                if ( !exists $reqAttrsList{$attrID} )
                {
                    next;
                }
            }

            if ( $filterType eq "customAttrsXML" )
            {
                if ( $nodeEle->nodeName eq "id" )
                {
                    $attrID = $nodeEle->textContent;
                }
                if ( $nodeEle->nodeName eq "simpleType" )
                {
                    $attrIsEnum = $nodeEle->find('enumeration')->size;
                }
            }

            my $eleData = $nodeEle->toString();
            print {$outFH} "$eleData\n";
        }
        print {$outFH} "</$endPathTagName>\n";
    }

    if ( $attrIsEnum > 0 )
    {
        my $enumDefPath = '/attributes/enumerationType/id[text()=\''.$attrID.'\']/ancestor::enumerationType';

        my $enumDef = $inXMLData->find($enumDefPath);
        if ( $enumDef->size == 1 )
        {
           my $enumDefData = $enumDef->get_node(1);
           print {$outFH} "$enumDefData\n";
        }
    }
}

sub alignPreparedXML
{
    my $preparedXMLFile = $_[0];

    my $outXMLData = XML::LibXML->load_xml(location => $preparedXMLFile, { no_blanks => 1 });

    open $outFH, '>', $outXMLFile or die "Could not open $outXMLFile\"$!\"";

    print {$outFH} $outXMLData->toString(1);

    close $outFH;
}

###############################
#      Subroutine End         #
###############################
