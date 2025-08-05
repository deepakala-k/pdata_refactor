#!/usr/bin/perl
# SPDX-License-Identifier: Apache-2.0

############################################################################
#                                                                          #
#   This script is used add fapi and non-fapi attributes under             #
#   respective target id. The script will check each target which are      #
#   existing in given --fromTgtXml file into given --toTgtXml file.        #
#   If target id is exist in --toTgtXml file then adding both xml file     #
#   target attributes into output xml file which is given in --outXml as   #
#   a single target with all attributes.                                   #
#   If target id is not exist then considering that particular target      #
#   respective --fromTgtXml file specific target and adding as a new       #
#   target into output xml file.                                           #
#                                                                          #
############################################################################
#
# Example:
# mapTgtsAttrs.pl --tgtXMLType ekbTgt --fromTgtXml target_types_ekb.xml
#                 --toTgtXml target_types_obmc.xml --outXml target_types_mapped.xml 
#
# xml file sample for reference:
#
# target_types_ekb.xml :
#
# <targetTypeExtension>
#   <attribute>
#     <id>BACKUP_SEEPROM_SELECT</id>
#   </attribute>
#   <id>chip-processor-power10</id>
# </targetTypeExtension>
#
# target_types_obmc.xml :
#
# <targetType>
#   <attribute>
#     <id>PROC_MASTER_TYPE</id>
#   </attribute>
#   <id>chip-processor-power10</id>
#   <parent>chip-processor</parent>
# </targetType>
#
# target_types_final.xml :
# <targetType>
#   <attribute>
#    <id>PROC_MASTER_TYPE</id>
#   </attribute>
#   <attribute>
#    <id>BACKUP_SEEPROM_SELECT</id>
#   </attribute>
#   <id>chip-processor-power10</id>
#   <parent>chip-processor</parent>
# </targetType>
#
# Similarly for "customTgt" but xml format will be different i.e
# "targetType" instead of "targetTypeExtension" tag

use XML::LibXML;
use Getopt::Long;
use strict;
use File::Basename;
use Data::Dumper;
my $currDir = dirname($0);
require "$currDir/parseIntermediateXMLUtils.pl";

# Global variables list begin

# To mention this tool name in log if unsupported things tried
my $tool = $0;
# To store commandline arguments
my $fromXMLFile;
my $toXMLFile;
my $outXMLFile;
my $tgtXMLType;
my $filterTgtsFile;
my $help;
my $myVerbose;

# Global variables list end
my $toXMLData;
my $fromXMLData;
my $isTgtMapped = 0;
my %reqTgts;

# Process commandline options

GetOptions( "fromTgtXml:s"    => \$fromXMLFile,
            "toTgtXml:s"      => \$toXMLFile,
            "outXml:s"        => \$outXMLFile,
            "tgtXMLType:s"    => \$tgtXMLType,
            "filterTgtList:s" => \$filterTgtsFile,
            "verbose:s"       => \$myVerbose,
            "help"            => \$help
          );

if ( $help )
{
    printUsage();
    exit 0;
}
if ( $tgtXMLType eq "")
{
    print "--tgtXMLType is required.\nPlease use --help to get know supported type\n";
    exit 1;
}
# Checking given target map type for mapping attributes
if ( $tgtXMLType ne "customTgt" and $tgtXMLType ne "ekbTgt" )
{
    print "The given tgtXMLType: \"$tgtXMLType\" is not supported.\nPlease use --help to get know supported type\n";
    exit 1;
}
if ( $fromXMLFile eq "" )
{
    print "--fromTgtXml is required.\nPlease use --help to get know more about tool.\n";
    exit 1;
}
if ( $tgtXMLType eq "customTgt" )
{
    if ( $filterTgtsFile eq "" )
    {
        print "--filterTgtList is required with required targets list to get required targets\n";
        exit 1;
    }
}
else
{
    if ( $toXMLFile eq "" )
    {
        print "--toTgtXml is required.\nPlease use --help to get know more about tool.\n";
        exit 1;
    }
}
if ( $outXMLFile eq "" )
{
    print "--outXml is required.\nPlease use --help to get know more about tool.\n";
    exit 1;
}


# Start from main function
main();

###############################
#      Subroutine Begin       #
###############################

sub printUsage
{
    print "\nDescription:

         This script is used add fapi and non-fapi attributes under respective target id. The script will check each target which are existing in given --fromTgtXml file into given --toTgtXml file.
         If target id is exist in --toTgtXml file then adding both xml file target attributes into output xml file which is given in --outXml as a single target with all attributes.
         If target id is not exist then considering that particular target respective --fromTgtXml file specific target and adding as a new target into output xml file.\n" if $help;

    print "\nUsage of $tool:

    --tgtXMLType   : [M] : Used to pass target xml type for mapping
                              Supported Type:
                                - customTgt -> To map custom targets with it parent attributes
                                - ekbTgt    -> To map ekb targets with attributes
                           E.g. : --tgtXMLType <ekbTgt|customTgt>

    --fromTgtXml   : [M] : Used to pass xml file for map targets attributes by looking
                           --toTgtXml file.
                           E.g. : --fromTgtXml <target_types_ekb.xml>

    --outXml       : [M] : Used to pass output xml file to store all mapped and new targets
                           with attributes
                           E.g. : --outXml <target_types_mapped.xml>

    --toTgtXml     : [C] : Used to pass xml file as base reference for map --fromTgtXml file
                           targets attributes
                           Note: This is required if tgtXMLType is not customTgt
                           E.g. : --toTgtXml <target_types_obmc.xml>

    --filterTgtList: [C] : Used to give required targets list in lsv file.
                           Note: This is required if tgtXMLType is customTgt
                           E.g. : --filterTgtList <systemName_FilterTgtsList.lsv>

    --verbose      : [O] : Use to print debug information
                              To print different level of log use following format
                              -v|--verbose A,C,E,W,I
                               A - All, C - CRITICAL, E - ERROR, W - WARNING, I - INFO 

    --help         : [O] : To print the tool usage\n";
}

sub main
{
    init();

    mapCustomTgtsAttrs() if $tgtXMLType eq "customTgt";

    mapEkbTgtsAttrs() if $tgtXMLType eq "ekbTgt";

    pushUpdatedTgtsAttrsIntoOutXMLFile() if $isTgtMapped eq 1;
}

sub init
{
    initVerbose($myVerbose);
    $fromXMLData = XML::LibXML->load_xml(location => $fromXMLFile);

    if ( $tgtXMLType eq "customTgt" )
    {
        %reqTgts = getRequiredTgts($filterTgtsFile);
        print "deepa -----------\n";
        print Dumper(\%reqTgts);
    }
    else
    {
        $toXMLData = XML::LibXML->load_xml(location => $toXMLFile);
    }
}

sub isVerboseReq
{
    my $verboseLevel = $_[0];

    my $isReq = 0;
    if ( ( index($myVerbose, $verboseLevel ) > -1) or ( index($myVerbose, 'A') > -1 ) )
    {
        $isReq = 1;
    }

    return ( $isReq )
}

sub mapCustomTgtsAttrs
{
    print "deepa mapCustomTgtsAttrs \n";
    my $fromTgtPath = '/attributes/targetType';
    my @removeTgtFromXML;
    foreach my $fromTgt ( $fromXMLData->findnodes($fromTgtPath) )
    {
        my $fromTgtId = $fromTgt->findvalue('id');
        print "deepa fromTgtId::$fromTgtId \n";
        if ( $fromTgtId eq "" )
        {
            print "CRITICAL: Target id is missing in fromXML\n" if isVerboseReq("C");
            next;
        }

        if ( !exists $reqTgts{$fromTgtId} )
        {
            push(@removeTgtFromXML, $fromTgt);
            next;
        }

        my $fromTgtParent = $fromTgt->findvalue('parent');
        print "deepa fromTgtParent $fromTgtParent\n";
        if ( $fromTgtParent eq "" )
        {
            print "CRITICAL: Target parent is missing in fromXML for target: $fromTgtId\n" if isVerboseReq("C");
            next;
        }

        my $parentTgtAttrs = getParentTgtAttrs($fromTgtParent);

        foreach my $attrNode ($parentTgtAttrs->get_nodelist())
        {
            $fromTgt->appendText("\t");
            $fromTgt->addChild($attrNode->cloneNode(1));
            $fromTgt->appendText("\n");
            $fromTgt->appendText("\t");
            $isTgtMapped = 1
        }
    }

    # Remove unwanted targets from xml.
    my $attrsRoot = $fromXMLData->find('attributes');
    if ( $attrsRoot->size() == 1 )
    {
        foreach my $tgtNode (@removeTgtFromXML)
        {
            my $fromTgtId = $tgtNode->findvalue('id');
            $attrsRoot->get_node(1)->removeChild($tgtNode);
        }
    }

    $toXMLData = $fromXMLData;
}

sub getParentTgtAttrs
{
    my $parentTgtId = $_[0];

    my $attrsList;
    my $tgtParentPath = '/attributes/targetType/id[text()=\''.$parentTgtId.'\']/ancestor::targetType';

    my $tgts = $fromXMLData->findnodes($tgtParentPath);
    if ($tgts->size() == 0)
    {
        print "CRITICAL: parent[$parentTgtId] is not present in $fromXMLFile\n" if isVerboseReq("C");
        print "CRITICAL: parent[$parentTgtId] is not present in $fromXMLFile\n";
        exit 1;
    }
    else
    {
        foreach my $tgt ($fromXMLData->findnodes($tgtParentPath))
        {
            $attrsList = $tgt->findnodes('attribute');
            if( $parentTgtId ne "base")
            {
                my $tgtParent = $tgt->findvalue('parent');
                my $retAttrsList = getParentTgtAttrs($tgtParent);
                $attrsList->append($retAttrsList);
            }
        }
    }

    return $attrsList;
}

sub mapEkbTgtsAttrs
{
    my $fromTgtPath = '/attributes/targetTypeExtension';

    foreach my $fromTgt ( $fromXMLData->findnodes($fromTgtPath) )
    {
        my $fromTgtId = $fromTgt->findvalue('id');
        if ( $fromTgtId eq "" )
        {
            print "CRITICAL: Target id is missing in fromXML\n" if isVerboseReq("C");
            next;
        }

        my $toTgtPath = '/attributes/targetType/id[text()=\''.$fromTgtId.'\']/ancestor::targetType';
        my $isTgtPresent = 0;
        foreach my $toTgt ( $toXMLData->findnodes($toTgtPath))
        {
            $isTgtPresent = 1;
            foreach my $fromTgtAttr ( $fromTgt->findnodes('attribute'))
            {
                my $fromTgtAttrId = $fromTgtAttr->findvalue('id');
                my $toTgtAttrPath = 'attribute/id[text()=\''.$fromTgtAttrId.'\']';

                if ($toTgt->findvalue($toTgtAttrPath) ne "")
                {
                    print "ERROR: The fromXml target \"$fromTgtId\" attribute \"$fromTgtAttrId\" is already present\n" if isVerboseReq("E");
                    next;
                }
                $toTgt->addChild($fromTgtAttr);
                $toTgt->appendText("\n");

                $isTgtMapped = 1
            }
        }

        # TODO : Need to revisit once common non fapi attributes found
        # beacuse currently merging unpresent fapi targets attributes is
        # required due to bmc have specific targets not all targets
        # So,If target is not present considering that particular target
        # is need to add into target list
        if ( $isTgtPresent eq 0 )
        {
            my $toRootNode = $toXMLData->find('attributes');
            if ( $toRootNode->size() == 1)
            {
                my $rootNode = $toRootNode->get_node(1);
                # Changing node name targetTypeExtension into targetType
                # to make uniform name for xml process
                $fromTgt->setNodeName("targetType");
                $rootNode->addChild($fromTgt);
                $rootNode->appendText("\n");

                $isTgtMapped = 1
            }
        }
    }
}

sub pushUpdatedTgtsAttrsIntoOutXMLFile
{
    open my $outFH, '>', $outXMLFile or die "Could not open $outXMLFile: \"$!\"";

    print {$outFH} $toXMLData->toString();
    
    close $outFH;
}
