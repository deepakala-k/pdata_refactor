#!/usr/bin/perl
# SPDX-License-Identifier: Apache-2.0

############################################################################
#                                                                          #
#   This script is used expand the targetType to look                      #
#   into the parent targetType and adds all the attributes under parent    #
#   into the child target recursively                                      #
#                                                                          #
############################################################################
#
# Example:
# expandTargetTypes.pl -fromTgtXml target_types_merged.xml
#                 --outXml target_types_expanded.xml 
#
# Similarly for "customTgt" but xml format will be different i.e
# "targetType" instead of "targetTypeExtension" tag

use FindBin;
require "$FindBin::Bin/utils.pl";

use XML::LibXML;
use Getopt::Long;
use strict;
use File::Basename;

# Global variables list begin

# To mention this tool name in log if unsupported things tried
my $tool = $0;
# To store commandline arguments
my $fromXMLFile;
my $outXMLFile;
my $filterTgtsFile;
my $filterAttrFile;
my $help;
my $myVerbose;

# Global variables list end
my $toXMLData;
my $fromXMLData;
my $isTgtMapped = 0;
my %reqTgts;
my %reqAttr;
my $user_provided_tgt_filter_is_active;
my $user_provided_attr_filter_is_active;

# Process commandline options
GetOptions( "fromTgtXml:s"    => \$fromXMLFile,
            "outXml:s"        => \$outXMLFile,
            "filter-tgt-file:s" => \$filterTgtsFile,
            "filter-attr-file:s" => \$filterAttrFile,
            "verbose:s"       => \$myVerbose,
            "help"            => \$help
          );

if ( $help )
{
    printUsage();
    exit 0;
}
if ( $fromXMLFile eq "" )
{
    print "--fromTgtXml is required.\nPlease use --help to get know more about tool.\n";
    exit 1;
}
if ( $filterTgtsFile eq "" )
{
    print "--filter-tgt-file is required with required targets list to get required targets\n";
    exit 1;
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

         This scripts merged the parent target attributes to the child target 
         to created the expanded targettype" if $help;

    print "\nUsage of $tool:

    --fromTgtXml   : [M] : Used to pass xml file for expanding targetType attributes by looking
                           --toTgtXml file.
                           E.g. : --fromTgtXml <target_types_<unexpanded>.xml>

    --outXml       : [M] : Used to pass output xml file to store all mapped and new targets
                           with attributes
                           E.g. : --outXml <target_types_<expanded>.xml>


    --filter-tgt-file : [C] : Used to give required targets list.

    --filter-attr-file: [C] : Used to give required attribute list

    --verbose      : [O] : Use to print debug information
                              To print different level of log use following format
                              -v|--verbose A,C,E,W,I
                               A - All, C - CRITICAL, E - ERROR, W - WARNING, I - INFO 

    --help         : [O] : To print the tool usage\n";
}

sub main
{
    init();

    expandTargetType() ;

    filterAttribute();

    pushUpdatedTgtsAttrsIntoOutXMLFile();
}

sub init
{
    initVerbose($myVerbose);
    $fromXMLData = XML::LibXML->load_xml(location => $fromXMLFile);

    loadAllowedFilterList( $filterTgtsFile, 
        \%reqTgts,
        "/allowedTargets/targetType",
        \$user_provided_tgt_filter_is_active );

    loadAllowedFilterList( $filterAttrFile, 
        \%reqAttr,
        "/allowedAttributes/attribute",
        \$user_provided_attr_filter_is_active );
}

sub isVerboseReq
{
    my $verboseLevel = $_[0];

    my $isReq = 0;
    if ( ( index($myVerbose, $verboseLevel ) > -1) or ( index($myVerbose, 'A') > -1 ) )
    {
        $isReq = 1;
    }
    $isReq = 0;
    return ( $isReq )
}

sub filterAttribute {
    my $tgtPath = '/attributes/targetType';
    foreach my $tgtNode ($fromXMLData->findnodes($tgtPath)) {
        my $tgtId = $tgtNode->findvalue('id');

        foreach my $attrNode ($tgtNode->findnodes('attribute')) {
            my $attrId = $attrNode->findvalue('id');

            # If not in allowed list → remove it
            if (!exists $reqAttr{$attrId} && $user_provided_attr_filter_is_active) {
                $tgtNode->removeChild($attrNode);
            }
        }
    }
}

sub expandTargetType
{
    my $fromTgtPath = '/attributes/targetType';
    my @removeTgtFromXML;
    foreach my $fromTgt ( $fromXMLData->findnodes($fromTgtPath) )
    {
        my $fromTgtId = $fromTgt->findvalue('id');
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

sub pushUpdatedTgtsAttrsIntoOutXMLFile
{
    open my $outFH, '>', $outXMLFile or die "Could not open $outXMLFile: \"$!\"";

    print {$outFH} $toXMLData->toString();
    
    close $outFH;
}
