#!/usr/bin/perl
# SPDX-License-Identifier: Apache-2.0

#
# Purpose:
#
#   This scripts are useful to convert required ekb attributes xml into mrw
#   attributes and targets type xml format, because ekb and mrw attributes
#   xml files are different format, so it will be difficult to process
#   xml's for getting FAPI and Non-FAPI attributes info to generate device tree.
#   Hence this scripts are used to convert ekb attributes xml format into
#   mrw attibutes and targets type xml format.
#
# Ex:
# ekb attributes format:
#
# <attributes>
#  <attribute>
#    <id>ATTR_BACKUP_SEEPROM_SELECT</id>
#    <targetType>TARGET_TYPE_PROC_CHIP</targetType>
#    <description>Select Primary or Backup SEEPROM</description>
#    <valueType>uint8</valueType>
#    <enum>PRIMARY = 0x0,SECONDARY = 0x1</enum>
#    <platInit/>
#    <mrwHide/>
#  </attribute>
# </attributes>
#
# MRW attribute format:
#
# <attributes>
#   <attribute>
#     <description>Select Primary or Backup SEEPROM</description>
#     <hwpfToAttrMap>
#      <id>ATTR_BACKUP_SEEPROM_SELECT</id>
#      <macro>DIRECT</macro>
#     </hwpfToAttrMap>
#    <id>BACKUP_SEEPROM_SELECT</id>
#    <no_export></no_export>
#    <persistency>non-volatile</persistency>
#    <readable></readable>
#    <simpleType>
#     <enumeration></enumeration>
#     <uint8_t></uint8_t>
#    </simpleType>
#   </attribute>
#
#   <enumerationType>
#     <description>Select Primary or Backup SEEPROM</description>
#     <enumerator>
#     <name>PRIMARY</name>
#     <value>0x0</value>
#     </enumerator>
#     <enumerator>
#      <name>SECONDARY</name>
#      <value>0x1</value>
#     </enumerator>
#     <id>BACKUP_SEEPROM_SELECT</id>
#    </enumerationType>
# </attributes>
#
# MRW target format:
#
# <attributes>
#  <targetTypeExtension>
#   <attribute>
#    <id>BACKUP_SEEPROM_SELECT</id>
#   </attribute>
#  </targetTypeExtension>
# </attributes>
#

use Digest::MD5 qw(md5_hex);
use strict;
use XML::Simple;

require 'utils.pl';

$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

#Global variables for Command line arguments
my $ekbAttrsXMLPath = "";
my $ekbAttrsXMLFileList = "";
my $targ_filename = "";
my $attr_filename = "";
my $ekbCustomize_filename = "";
my $fapiTargetMapFile = "";
my $filterAttrsFile;
my %reqAttrsList;
my @reqekbAttrsXmlFiles;
my %reqTgtsTrans;
my $ekbCustomizeXml;
my $allTargetExt = {};
my $usage = 0;
my $ATTR_FH;
my $TARG_FH;
my $xml;

use Getopt::Long;
GetOptions( "inEkbAttrsXMLPath:s"       => \$ekbAttrsXMLPath,
            "inEkbAttrsXMLFilesList:s" => \$ekbAttrsXMLFileList,
            "outEkbAttrsXML:s"  => \$attr_filename,
            "outEkbTgtsXML:s"   => \$targ_filename,
            "fapiTgtNameMap:s"  => \$fapiTargetMapFile,
            "filterAttrsFile:s" => \$filterAttrsFile,
            "addEkbCustomVal:s" => \$ekbCustomize_filename,
            "help"              => \$usage, );

if ($usage)
{
    display_help();
    exit 0;
}
if( $ekbAttrsXMLPath eq "" )
{
    print "--inEkbAttrsXMLPath is required to get required ekb attributes xml file from ekb xml file path\n";
    exit 1;
}
if( $ekbAttrsXMLFileList eq "" )
{
    print "--inEkbAttrsXMLFilesList is required to get required ekb attributes xml file for converting into MRW format.\nPlese use --help to get know more about this tool.\n";
    exit 1;
}
if( $fapiTargetMapFile eq "" )
{
    print "--fapiTgtNameMap is required with FAPITarget type name with respective MRWtarget type name as lsv file to change fapi target name into mrw target name\n";
    exit 1;
}
if ( $filterAttrsFile eq "" )
{
    print "--filterAttrsFile is required with attributes list file to filter attribute.\nPlease check by --help to get know file format\n";
    exit 1;
}
if( $attr_filename eq "" )
{
    print "--outEkbAttrsXML is required with xml file name to store converted mrw attribute data format from ekb attribute data\n";
    exit 1;
}
if( $targ_filename eq "" )
{
    print "--outEkbTgtsXML is required with xml file name to store converted mrw target data with attribute from ekb attribute data\n";
    exit 1;
}

main();

sub display_help
{
    use File::Basename;
    my $scriptname = basename($0);
    print "
Description:

    This scripts are useful to convert requried ekb attributes xml into mrw
    attributes and targets type xml format, because ekb and mrw attributes
    xml files are different format, so it will be difficult to process
    xml's for getting FAPI and Non-FAPI attributes info to generate
    device tree blob file. Hence this scripts are used to generate ekb
    attributes xml into mrw attibutes and targets type xml.

Usage:

    --inEkbAttrsXMLPath      : [M] : Used to give input ekb path to get required ekb attributes
                                     file which needs to convert into mrw format.
                                     E.g: --inEkbAttrsXMLPath <ekb_path>

    --inEkbAttrsXMLFilesList : [M] : Used to give filename which is contains required ekb
                                     attributes xml file list in the lsv format.

    --outEkbAttrsXML         : [M] : Used to give output atttibute xml file name to store
                                     converted mrw format attributes data from ekb attributes.
                                     E.g: --outEkbAttrsXML <output_ekbAttrsXML>

    --outEkbTgtsXML          : [M] : Used to give output target xml file name to store converted                                     mrw format targets data from ekb attributes.
                                     E.g: --outEkbTgtsXML <output_ekbTgtsXML>

    --fapiTgtNameMap         : [M] : Used to give FAPItarget name map file which is contain
                                     respective mrw target type name as lsv value to change fapi
                                     target name into mrw target name.

    --addEkbCustomVal        : [O] : Used to give xml file which is contains custom values to
                                     override ekb default values or need to add any
                                     additional tag.
                                     Note: attribute id should be same as ekb attribute id.
                                     <attributes>
                                        <attribute>
                                            <id>ekb_attr_id</id>
                                            <default>valueTooverride</default>
                                            <newTag>value</newTag>
                                        </attribute>
                                     </attributes:

    --help                   : [O] : Used to get tool usage
\n";
}

sub main
{
    init();
    prepareMRWFormatEkbAttrsXML();
    prepareMRWFormatEkbTgtsXML();
}

sub init
{
    getReqEkbAttrsXMLFileList();
    getFAPITargetMRWName();
    %reqAttrsList = getEKBAttrsFilterList($filterAttrsFile);

    #use the XML::Simple tool to convert the xml files into hashmaps
    $xml = new XML::Simple (KeyAttr=>[]);

    if ( $ekbCustomize_filename ne "" )
    {
        $ekbCustomizeXml = $xml->XMLin("$ekbCustomize_filename" ,
            forcearray => ['attribute'],
            NoAttr => 1);
    }

    open ($ATTR_FH, ">$attr_filename") ||
    die "ERROR: unable to open $attr_filename\n";

    open ($TARG_FH, ">$targ_filename") ||
    die "ERROR: unable to open $targ_filename\n";
}

sub getReqEkbAttrsXMLFileList
{
    open my $fd, $ekbAttrsXMLFileList or die "Could not open $ekbAttrsXMLFileList: \"$!\"";

    while ( my $line = <$fd> )
    {
        # skip comment line
        if ( $line =~ m/#/ )
        {
            next;
        }
        chomp $line;
        push (@reqekbAttrsXmlFiles, $ekbAttrsXMLPath."/".$line);
    }
    close $fd;
}

sub getFAPITargetMRWName
{
    # Getting FAPI target name list to convert into MRW name
    open my $fd, $fapiTargetMapFile or die "Could not open $fapiTargetMapFile: \"$!\"";
    while ( my $line = <$fd> )
    {
        # skip comment line
        if ( $line =~ m/#/ )
        {
            next;
        }
        chomp $line;
        my @reqTgtsInfo = split( ':', $line);
        $reqTgtsTrans{$reqTgtsInfo[0]} = $reqTgtsInfo[1];
    }
    close $fd;
}

sub prepareMRWFormatEkbAttrsXML
{
    print $ATTR_FH "<attributes>\n\n";

    foreach my $fapi_filename ( @reqekbAttrsXmlFiles )
    {
        #data from the ekb fapi attributes
        my $fapiXml = $xml->XMLin("$fapi_filename" ,
            forcearray => ['attribute'],
            NoAttr => 1);

        # Walk attribute definitions in fapiattrs.xml
        foreach my $FapiAttr ( @{$fapiXml->{attribute}} )
        {
            # Checking attributes in required
            if ( ! exists $reqAttrsList{$FapiAttr->{id}} )
            {
                next;
            }

            #we dont need to worry about EC FEATURE attributes
            if( $FapiAttr->{id} =~ /_EC_FEATURE/ )
            {
                next;
            }

            #Check if there are any custom defaults values need to add to fapi attrs before splitting
            foreach my $customizedAttr(@{$ekbCustomizeXml->{attribute}})
            {
                #if we find a match, then add update the attribute w/ customized values
                if ($customizedAttr->{id} eq $FapiAttr->{id})
                {
                    if(exists $customizedAttr->{default})
                    {
                        $FapiAttr->{default} = $customizedAttr->{default};
                    }
                }
            }

            #use utility functions to generate enum xml, if possible
            my $enum = createEnumFromAttr($FapiAttr);
            #use utility functions to generate attribute xml
            my $attr = createAttrFromFapi($FapiAttr);

            # Add enumeration inside simple type if attirbute is enum type
            if($enum ne "0"  && $enum ne "")
            {
                $attr->{simpleType}->{enumeration} = {};
            }
            #Check if there are additional tags besides default we need to add to fapi attrs
            foreach my $customizedAttr(@{$ekbCustomizeXml->{attribute}})
            {
                #if we find a match, then add update the attribute w/ customized values
                if ($customizedAttr->{id} eq $attr->{hwpfToAttrMap}->{id})
                {
                    foreach my $tag (keys %$customizedAttr)
                    {
                        if($tag ne "default" && $tag ne "id" )
                        {
                            $attr->{$tag} = $customizedAttr->{$tag};
                        }
                    }
                    #Do not exit loop yet, continue in case there are more than 1 attr customization tags
                }
            }

            #not all attribute have enumaterated values, so enums are optional
            if($enum ne "0"  && $enum ne "")
            {
                printTargEnum($ATTR_FH, $enum);
            }

            #write to the attribute xml file
            printTargAttr($ATTR_FH,$attr);
            print $ATTR_FH "\n";

            createTargetExtensionFromFapi($FapiAttr,$allTargetExt);
        }
    }
    print $ATTR_FH "</attributes>\n\n";
    close $ATTR_FH;

}

sub prepareMRWFormatEkbTgtsXML
{
    #begin writing the file
    print $TARG_FH "<attributes>\n\n";

    # Print out all the generated stuff
    foreach my $targ (@{$allTargetExt->{targetTypeExtension}})
    {
        printTargExt($TARG_FH,$targ);
        print $TARG_FH "\n";
    }
    print $TARG_FH "</attributes>";
    close $TARG_FH;
}

sub convertValuereqTgtsTrans
{
    my $fapitype = shift;
    my $targtype = $fapitype;

    $targtype =~ s/(uint\d+)/$1_t/ if($fapitype =~ /^uint\d+$/);
    $targtype =~ s/(int\d+)/$1_t/  if($fapitype =~ /^int\d+$/);

    return $targtype;
}

sub createEnumFromAttr(\%)
{
    my($fapiattr) = @_;
    my @enums;

    if (exists $fapiattr->{enum})
    {
        # description: passed as-is
        my $fapiattr_id = $fapiattr->{id};
        my $id = $fapiattr_id;
        $id =~ s/ATTR_//;
        my $description = $fapiattr->{description};
        $description =~ s/^\s+|\s+$//g;

        my $enum = $fapiattr->{enum};
        my @enumerators = split( /,/, $enum);
        my @enumeratorHashArray;

        foreach my $enumerator (@enumerators)  {
            my %enumeratorHash;
            chomp($enumerator);
            $enumerator =~ s/^\s+|\s+$//g;

            my @nameVal = split( /=/, $enumerator);

            my $name = $nameVal[0];
            $name =~ s/^\s+|\s+$//g;
            my $value = $nameVal[1];
            $value =~ s/^\s+|\s+$//g;

            my %enumeratorHash = (
                name => $name,
                value => $value
            );

            push @enumeratorHashArray, \%enumeratorHash;
        }

        my %enumToAdd = (
            id => $id,
            description => $description,
        );
        $enumToAdd{'enumerator'} = [@enumeratorHashArray];
        return \%enumToAdd
    }
}

sub createAttrFromFapi(\%)
{
    my($fapiattr) = @_;
    my $targattr = {};

    # id: passed as-is
    my $fapiattr_id = $fapiattr->{id};
    my $id = $fapiattr_id;
    $id =~ s/ATTR_//;
    $targattr->{id} = $id;

    # description: passed as-is
    my $description = $fapiattr->{description};
    if(ref $fapiattr->{description} && eval {keys %{$fapiattr->{description}} == 0} )
    {
        $targattr->{description} = "place holder description";
    }
    else
    {
        $targattr->{description} = $description;
    }

    # valueType: convert
    my $valueType = convertValuereqTgtsTrans($fapiattr->{valueType});
    $targattr->{simpleType}->{$valueType} = {};

    # writeable: passed as-is
    if( exists $fapiattr->{writeable} )
    {
        $targattr->{writeable} = {};
    }

    #default: modifies simpleType
    if( exists $fapiattr->{default} )
    {
        $targattr->{simpleType}->{$valueType}->{default} =
            $fapiattr->{default};
    }
    elsif (exists $fapiattr->{initToZero})
    {
        $targattr->{simpleType}->{$valueType}->{default} = 0;
    }

    #array: modifies simpleType
    if( exists $fapiattr->{array} )
    {
        my @dimensions = split(' ',$fapiattr->{array});
        my $dimensions_cs = @dimensions[0];
        for my $i ( 1 .. $#dimensions )
        {
            $dimensions_cs .= ",$dimensions[$i]";
        }
        $dimensions_cs =~ s/,,/,/g;
        $targattr->{simpleType}->{array} = $dimensions_cs;
    }

    #platInit: influences persistency
    #initToZero: influences persistency
    #overrideOnly: influences persistency
    if( exists $fapiattr->{platInit} )
    {
        if( exists $fapiattr->{overrideOnly} )
        {
            if( exists $fapiattr->{default} )
            {
                $targattr->{persistency} = "volatile";
            }
            else
            {
                $targattr->{persistency} = "volatile-zeroed";
            }
        }
        else
        {
            $targattr->{persistency} = "non-volatile";
        }
    }
    elsif( exists $fapiattr->{initToZero} )
    {
        if( exists $fapiattr->{default} )
        {
            print "WARN: $fapiattr_id has initToZero and a default\n";
        }
        $targattr->{persistency} = "volatile-zeroed";
    }
    elsif( exists $fapiattr->{default} )
    {
        $targattr->{persistency} = "volatile";
    }
    else
    {
        $targattr->{persistency} = "volatile-zeroed";
    }

    #mrwHide:  convert to no_export to hide from ServerWiz
    if( exists $fapiattr->{mrwHide} )
    {
        $targattr->{no_export} = {};
    }

    #mssUnits: ignore
    #mssAccessorName: ignore
    #odmVisible: ignore
    #odmChangeable: ignore
    #persistent: ignore
    #persistRuntime: ignore

    #enum: ignored here
    #targetType: ignored here

    #always add these
    $targattr->{readable} = {};
    $targattr->{hwpfToAttrMap}->{id} = $fapiattr_id;
    $targattr->{hwpfToAttrMap}->{macro} = "DIRECT";

    return $targattr;
}

sub createTargetExtensionFromFapi(\%,\%)
{
    my($fapiattr,$alltargext) = @_;
    open my $FHSTDOUT, ">&STDOUT";

    # Loop through all of the targets that this attribute
    #  is needed on (per fapi xml)
    my @types = split(',',$fapiattr->{targetType});
    foreach my $type(@types)
    {
        my $foundmatch = 0;
        $type =~ s/\s//g;
        # Added only attributes only for required targets
        if ( !exists $reqTgtsTrans{$type} )
        {
            next;
        }
        my @targtypes = split(',', $reqTgtsTrans{$type});
        foreach my $targtype (@targtypes)
        {
            my $attrid = $fapiattr->{id};
            $attrid =~ s/ATTR_//;

            # create new attribute element
            my $newattr = {};
            $newattr->{id} = $attrid;

            # look for an existing targetTypeExtension entry
            #  to modify with new attribute
            foreach my $targ (@{$alltargext->{targetTypeExtension}})
            {
                if( $targ->{id} =~ $targtype )
                {
                    $foundmatch = 1;
                    my $attrlist = $targ->{attribute};
                    push @$attrlist, $newattr;
                    last;
                }
            }

            # no existing entry for this kind of target, make a new one
            if( $foundmatch == 0 )
            {
                my $newext = {};
                $newext->{id} = $targtype;
                my $newarray = [];
                push @$newarray, $newattr;
                $newext->{attribute} = $newarray;
                my $allext = $alltargext->{targetTypeExtension};
                push @$allext, $newext;
            }
        }
    }
}

sub printTargAttr
{
    my($FH1,$targattr) = @_;
    print $FH1 $xml->XMLout( $targattr, RootName => 'attribute', NoAttr => 1 );
}

sub printTargEnum
{
    my($FH1,$targattr) = @_;
    print $FH1 $xml->XMLout( $targattr, RootName => 'enumerationType', NoAttr => 1 );
}

sub printTargExt
{
    my($FH1,$targtarg) = @_;
    print $FH1 $xml->XMLout( $targtarg, RootName => 'targetTypeExtension', NoAttr => 1 );
}
