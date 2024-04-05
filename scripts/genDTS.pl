#!/usr/bin/env perl

#################################################################################
#
#   * This perl script generate device tree structure from intermediate xml
#     which is contain MRW, FAPI and Non-FAPI targets/attributes.
#   * This perl script also support to prepare dts with
#     required targets and attributes.
#
#################################################################################

use File::Basename;
use XML::LibXML;
use Class::Struct;
use Getopt::Long;
use strict;

my $currDir = dirname($0);
my $topSrcDir = dirname($currDir);
require "$currDir/parseIntermediateXMLUtils.pl";

# Global variables list begin

# To mention this tool name if unsupported attribute data type present in xml
my $tool = basename($0);
# To store commandline arguments
my $inXMLFile;
my $dtsFilename;
my $filterAttrsFile;
my $filterTgtsFile;
my $pdbgMapFile;
my $help;
my $myVerbose;

# To store xml data
my %attributeDefList;
my %fapiTargetList;
my %mrwTargetList;
my %pdbgCompPropMapList;
# Used for dts (device tree structure) generation
my %headOfDTree;
my $dtsFHandle;

my $attrPrefix = "ATTR_";

struct Node => {
    nodeName        => '$',
    childNodes      => '%',
    # DTS Property
    compatible      => '$',
    index           => '$',
    address_cells   => '$',
    size_cells      => '$',
    reg             => '$',
    attributeList   => '%',
};

# Process commandline options

GetOptions( "inXML:s"           => \$inXMLFile,
            "outDTS:s"          => \$dtsFilename,
            "filterAttrsFile:s" => \$filterAttrsFile,
            "filterTgtsFile:s"  => \$filterTgtsFile,
            "pdbgMapFile:s"   => \$pdbgMapFile,
            "help"            => \$help,
            "verbose=s",      => \$myVerbose
          );

if ( $help )
{
    printUsage();
    exit 0;
}
if ( $inXMLFile eq "" )
{
    print "--inXML is required with xml file which should be in MRW format xml with mrw, fapia and non-fapi attributes to generate dts file\n";
    exit 1;
}
if ( $dtsFilename eq "")
{
    print "--outDTS is required with dts file name to store generated targets with attributes in dts format\n";
    exit 1;
}
if ( ($dtsFilename ne "") and !($dtsFilename =~ m/\.dts/ ))
{
    print "The given dts file name \"$dtsFilename\" extension is not .dts\n";
    exit 1;
}
if ( $pdbgMapFile eq "")
{
    print "--pdbgMapFile is required with mrw target type name with respective pdbg compatible property name to store into dts\n";
    exit 1;
}

# Start fomr main function
main();

###############################
#      Subroutine Begin       #
###############################

sub printUsage
{
    print "
Description:

    *   This tool will generate device tree structure from intermediate xml
        which is contain MRW, FAPI and Non-FAPI targets/attributes.
    *   This tool also support to prepare dts with required
        targets and attributes.\n" if $help;

    print "
Usage of $tool:

    -i|--inXML          : [M] :  Used to give intermediate xml name which contain MRW and FAPI
                                 Targets with associated attributes.
                                 E.g.: --inXML <xml_file.xml>

    -o|--outDTS         : [M] :  Used to give device tree structure file to stored generated dts                                 data.
                                 E.g.: --outDTS <dts_file.dts>

    -p|--pdbgFile       : [M] :  Used to pass pdbg compatible property map file name
                                 to map mrw target type in compatible proberty field
                                 E.g.: --pdbgFile <pdbg_compPropList.lsv>

    -f|--filterAttrsFile: [O] :  Used to give required attributes list in lsv file.
                                 E.g. : --filterAttrsFile <systemName_FilterAttrsList.lsv>

    -f|--filterTgtsFile : [O] :  Used to give required targets list in lsv file.
                                 E.g. : --filterTgtsFile <systemName_FilterTgtsList.lsv>

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
    init();
    mergeFAPITargetAttrsIntoMRWIfFound();
    prepareDeviceTreeHierarchy();
    createDTSFile();
}

sub init
{

    my @ret = getTargetsData($inXMLFile, $filterTgtsFile);
    %mrwTargetList = %{$ret[0]};
    %fapiTargetList = %{$ret[1]};
    %attributeDefList = getAttrsDef( $inXMLFile, $filterAttrsFile );
    my $mrwSize = keys %mrwTargetList;
    my $fapiSize = keys %fapiTargetList;
    my $attrsSize = keys %attributeDefList;
    print "INFO: mrwTgtSize: $mrwSize fapiTgtSize: $fapiSize attrsSize: $attrsSize\n" if isVerboseReq('I');
    %pdbgCompPropMapList = getRequiredTgtsPdbgCompPropMapList ( $pdbgMapFile );
    my $pdbgSize = keys %pdbgCompPropMapList;
}

sub mergeFAPITargetAttrsIntoMRWIfFound
{
    foreach my $FAPITargetID ( keys %fapiTargetList )
    {
        my $found = 0;
        foreach my $MRWTargetID ( keys %mrwTargetList )
        {
            if($FAPITargetID eq $mrwTargetList{$MRWTargetID} -> MRWTarget::targetType)
            {
                $found = 1;
                my $mrwTarget = $mrwTargetList{$MRWTargetID};
                my %updMRWTgtAttrsList = %{$mrwTarget->targetAttrList};
                my %fapiTgtAttrsList = %{$fapiTargetList{$FAPITargetID} -> FAPITarget::targetAttrList};
                my @sortedKeys = sort { numericalSort($a, $b) } keys %fapiTgtAttrsList;

                foreach my $fapiAttr ( @sortedKeys )
                {
                    if( exists $updMRWTgtAttrsList{$fapiAttr} )
                    {
                        if ( $updMRWTgtAttrsList{$fapiAttr}-> AttributeData::valueDataType eq "")
                        {
                            $updMRWTgtAttrsList{$fapiAttr} = $fapiTgtAttrsList{$fapiAttr};
                        }
                    }
                    else
                    {
                        $updMRWTgtAttrsList{$fapiAttr} = $fapiTgtAttrsList{$fapiAttr};
                    }
                }
                $mrwTarget->targetAttrList(\%updMRWTgtAttrsList);
            }
        }

        if($found eq 1)
        {
            print "INFO: FAPI target: $FAPITargetID merged with MRW target. Hence removing element from FAPI targets list\n" if isVerboseReq('I');
        }
    }
}

sub prepareDeviceTreeHierarchy
{
    my %nonPervTgtsList;
    my %omiPervPath;
    my @sortedKeys = sort { numericalSort($a, $b) } keys %mrwTargetList;
    
    # Prepare for MRW targets
    foreach my $MRWTargetID ( @sortedKeys)
    {
        # Ignoring if dimm, ocmb and memport targets because those targets should come under omi and omi is pervasive target
        # but ignoring targets are not pervasive targets. Those targets device tree hierarchy will prepare based on
        # omi pervasive path which is prepared in this for loop
        if ( index( $mrwTargetList{$MRWTargetID}->targetType, "dimm") != -1 or
             index( $mrwTargetList{$MRWTargetID}->targetType, "ddr") != -1 or
             index( $mrwTargetList{$MRWTargetID}->targetType, "chip-ocmb") != -1 or
             index( $mrwTargetList{$MRWTargetID}->targetType, "unit-mem_port") != -1 or
             $mrwTargetList{$MRWTargetID}->targetType eq "unit-perv" or
             index( $mrwTargetList{$MRWTargetID}->targetType, "chip-vreg-generic") != -1 or
             index( $mrwTargetList{$MRWTargetID}->targetType, "chip-adc") != -1 or
             index( $mrwTargetList{$MRWTargetID}->targetType, "chip-PCA9554") != -1
           )
        {
            $nonPervTgtsList{$MRWTargetID} = $mrwTargetList{$MRWTargetID};
            next;
        }

        if ( !exists ${$mrwTargetList{$MRWTargetID}->targetAttrList}{'PHYS_PATH'} )
        {
            print "CRITICAL: \"PHYS_PATH\" attribute is not found for MRW Target : \"$MRWTargetID\". So Ignoring\n" if isVerboseReq('C');
            next;
        }
        my $physPath = ${$mrwTargetList{$MRWTargetID}->targetAttrList}{'PHYS_PATH'}->value;

        my $finalPath = $physPath;
        my $pervasivePath;
        # If parvasive path found for a particular target then considering that path should beto rearrange.
        # Because FAPI targets are modelled based on pervasive targets
        if ( exists ${$mrwTargetList{$MRWTargetID}->targetAttrList}{'PARENT_PERVASIVE'} )
        {
            # E.g. :
            # $pervasivePath = "physical:sys-0/node-0/proc-0/perv-32";
            # $physPath = "physical:sys-0/node-0/proc-0/eq-0/fc-0/core-0";
            # $finalPath => physical:sys-0/node-0/proc-0/perv-32/eq-0/fc-0/core-0

            $pervasivePath = ${$mrwTargetList{$MRWTargetID}->targetAttrList}{'PARENT_PERVASIVE'}->value;
            $finalPath = $pervasivePath.substr($physPath, rindex($pervasivePath, "/"), length($physPath) - rindex($pervasivePath, "/") );
        }

        # If the I2C_PARENT_PHYS_PATH attribute is found for a particular
        # target then, that target need to add under the respective I2C
        # target along with its parent.
        # For example, the OSCREFCLK (chip-SI5332) target need to be present
        # as "bmcN -> i2c-N ->oscrefclkN" in the device tree to perform
        # the i2c read and write operation on the OSCREFCLK target.
        if ( exists ${$mrwTargetList{$MRWTargetID}->targetAttrList}{'I2C_PARENT_PHYS_PATH'} )
        {
            # E.g. :
            # $i2cParentPhysPath = "physical:sys-0/node-0/bmc-0";
            # $physPath = "physical:sys-0/node-0/oscrefclk-0";
            # $finalPath => physical:sys-0/node-0/bmc-0/i2c-$i2cPort/oscrefclk-0

            my $i2cParentPhysPath = ${$mrwTargetList{$MRWTargetID}->targetAttrList}{'I2C_PARENT_PHYS_PATH'}->value;
            my $i2cPort = ${$mrwTargetList{$MRWTargetID}->targetAttrList}{'I2C_PORT'}->value;

            my $commonPathElePos;
            for my $i (0..length($i2cParentPhysPath) - 1)
            {
                my $a = substr($i2cParentPhysPath, $i, 1);
                my $b = substr($physPath, $i, 1);
                if ($a ne $b)
                {
                    $commonPathElePos = $i - 1;
                    last;
                }
            }

            # The I2C_PORT needs to decrement by one since the i2c instance
            # id will start from "0".
            $finalPath = $i2cParentPhysPath . "/i2c-" . ($i2cPort - 1);
            $finalPath .= substr($physPath, $commonPathElePos);
        }

        # Adding pervasive path for "unit-fc-*" targets based on CHIPLET_ID attribute,
        # beause to avoid dupilcate device tree hierarchy creation.
        # TODO: Need to revisit for EX targets too if required some other system
        # TODO: Index hard code value (7/6) for proc path need to revisit, it will mess if proc sequence id more than one digit
        if( index($mrwTargetList{$MRWTargetID}->targetType, "unit-fc-") != -1 )
        {
            if ( !exists ${$mrwTargetList{$MRWTargetID}->targetAttrList}{'CHIPLET_ID'} )
            {
                print "CRITICAL: \"CHIPLET_ID\" attribute is not found for MRW Target : \"$MRWTargetID\". Ignoring otherwise perv path will be duplicate" if isVerboseReq('C');
                next;
            }
            my $chipletID = ${$mrwTargetList{$MRWTargetID}->targetAttrList}{'CHIPLET_ID'}->value;
            $finalPath = substr($physPath, 0, index($physPath, 'proc') + 7)."perv-".hex($chipletID).substr($physPath, index($physPath, 'proc') + 6);
        }

        # If target path is contain proc then add pib target after proc target path
        # for scom address translation as per pdbg expectation
        # TODO: Index hard code value (7/6) for proc path need to revisit, it will mess if proc sequence id more than one digit
        if( ( index($finalPath, "proc") != -1 )  and ( index($mrwTargetList{$MRWTargetID}->targetType, "chip-processor") == -1 ) )
        {
            $finalPath = substr($finalPath, 0, index($finalPath, 'proc') + 7)."pib".substr($finalPath, index($finalPath, 'proc') + 6, length($finalPath) - ( index($finalPath, 'proc') + 6) ) ;
        }
        # Getting path value alone by ignoring "physical:"
        my @hash = split(/\//, substr($finalPath, index($finalPath, ':') + 1));
        processTargetPath($MRWTargetID, \@hash);
        # Create omi pervasive path list for use to dimm. ocmb and memport targets
        $omiPervPath{$MRWTargetID} = $finalPath if index( $mrwTargetList{$MRWTargetID}->targetType, "unit-omi") != -1;

        # Add FSI target manually under proc target if MRW target is chip-processor.
        addFSITarget($MRWTargetID, $finalPath) if index($mrwTargetList{$MRWTargetID}->targetType, "chip-processor") != -1;

        # Add PIB target manually under proc target if MRW target is chip-processor.
        addPIBTarget($MRWTargetID, $finalPath) if index($mrwTargetList{$MRWTargetID}->targetType, "chip-processor") != -1;

        # Add thread target manually under core target as per pdbg expectation for
        # register access
        addThreadTarget($MRWTargetID, $finalPath) if index($mrwTargetList{$MRWTargetID}->targetType, "unit-core") != -1;
    }

    # Prepare device tree hierarchy for non pervasive targets which need to come under proc/.../omi target hierarchy
    prepareDeviceTreeHierarchyForNonPervTgts(\%nonPervTgtsList, \%omiPervPath);
}

sub addFSITarget
{
    my $procTgtId = $_[0];
    my $procPath = $_[1];

    my $fsiIndex = substr($procPath, index($procPath, 'proc-') + 5);
    # Pdbg did not expect index along with node name
    my $fsiPath = $procPath."/fsi";
    my $fsiTgtId = $procTgtId."fsi".$fsiIndex;
    my @hash = split(/\//, substr($fsiPath, index($fsiPath, ':') + 1));
    my $fsiTgt = MRWTarget->new();
    $fsiTgt->targetType("unit-fsi");
    $fsiTgt->targetAttrList({});
    $mrwTargetList{$fsiTgtId} = $fsiTgt;
    processTargetPath($fsiTgtId, \@hash);
}

sub addPIBTarget
{
    my $procTgtId = $_[0];
    my $procPath = $_[1];

    my $pibIndex = substr($procPath, index($procPath, 'proc-') + 5);
    # Pdbg did not expect index along with node name
    my $pibPath = $procPath."/pib";
    my $pibTgtId = $procTgtId."pib".$pibIndex;
    my @hash = split(/\//, substr($pibPath, index($pibPath, ':') + 1));
    my $pibTgt = MRWTarget->new();
    $pibTgt->targetType("unit-pib");
    $pibTgt->targetAttrList({});
    $mrwTargetList{$pibTgtId} = $pibTgt;
    processTargetPath($pibTgtId, \@hash);
}

sub addThreadTarget
{
    my $procTgtId = $_[0];
    my $procPath = $_[1];

    my $threadPath = $procPath."/thread-";
    my $threadTgtId = $procTgtId."thread";
    my $maxThreads = 4;
    for(my $i = 0; $i < $maxThreads; $i++)
    {
        my $currThreadPath = $threadPath.$i;
        my $currThreadTgtId = $threadTgtId.$i;
        my @hash = split(/\//, substr($currThreadPath, index($currThreadPath, ':') + 1));
        my $threadTgt = MRWTarget->new();
        $threadTgt->targetType("unit-thread");
        $threadTgt->targetAttrList({});
        $mrwTargetList{$currThreadTgtId} = $threadTgt;
        processTargetPath($currThreadTgtId, \@hash);
    }
}

#returns the number at the end of the string if found, else returns 0
sub getNumAtTheEnd {
    my ($str) = @_;

    #expression to extract the number at the end of the string
    my ($number) = $str =~ /(\d+)$/;

    return $number || 0;
}

#Sorts two strings using number at the end if they contain the same string part.
#Or sort them alphabetically
sub numericalSort {
    my ($firstString, $secondString) = @_;
    
    my $firstStringWithoutNum = $firstString;
    my $secondStringWithoutNum = $secondString;
    
    # store the numerical value at the end to num variables
    my $firstNum = getNumAtTheEnd($firstString);
    my $secondNum = getNumAtTheEnd($secondString);

    # Removes the numerical value at the end of each of the variables
    # s/\d+$// expression chops the number at the end
    $firstStringWithoutNum =~ s/\d+$//;
    $secondStringWithoutNum =~ s/\d+$//;

    # Compares the name part without numbers
    # and if both numbers are 0, it might be possible that the original 
    # string did not have a number. Hence do a string compare
    if ($firstStringWithoutNum eq $secondStringWithoutNum 
        && $firstNum != 0 && $secondNum != 0)
    {
      return $firstNum <=> $secondNum;
    }
    else
    {
      return $firstString cmp $secondString;
    }
}

sub prepareDeviceTreeHierarchyForNonPervTgts
{
    my %nonPervTgtsList = %{$_[0]};
    my %omiTgtPervPathList = %{$_[1]};
    
    my @sortedKeys = sort { numericalSort($a, $b) } keys %nonPervTgtsList;
    
    foreach my $tgtID (@sortedKeys)
    {
        my %targetAttrList = %{$nonPervTgtsList{$tgtID}->targetAttrList};
        if ( !exists $targetAttrList{"AFFINITY_PATH"} )
        {
            print "CRITICAL: \"AFFINITY_PATH\" attribute is not found for MRW Target : \"$tgtID\". So Ignoring to add not pervasive
            under proc target\n" if isVerboseReq('C');
            next;
        }

        my $tgtPath = $targetAttrList{'AFFINITY_PATH'}->value;
        # First Ignoring affinity: from path then getting till omi path to covert as omi id for getting omi perv path
        my $omiTgtId = substr( substr($tgtPath, index($tgtPath, ':') + 1), 0, index($tgtPath, 'omi-') - 4);
        $omiTgtId =~ s/[-\/]//g;

        if ( !exists $omiTgtPervPathList{$omiTgtId} )
        {
            print "CRITICAL: \" OMI target id \"$omiTgtId\" is not found to get OMI parv path\n" if isVerboseReq('C');
            next;
        }

        my $omiTgtPervPath = $omiTgtPervPathList{$omiTgtId};

        # Getting non pervasive target path alone from AFFINITY_PATH
        my $nonPervTgtPath = substr($tgtPath, index($tgtPath, 'omi-') + 5, length($tgtPath) - ( index($tgtPath, 'omi-') + 5) );
        my $nonPervTgtPathWithOMITgtPath = $omiTgtPervPath.$nonPervTgtPath;

        # Getting path value alone by ignoring "physical:"
        my @hash = split(/\//, substr($nonPervTgtPathWithOMITgtPath, index($nonPervTgtPathWithOMITgtPath, ':') + 1));
        processTargetPath($tgtID, \@hash);
    }
}

sub processTargetPath
{
    my $TargetID = $_[0];
    my @splittedPath = @{$_[1]};
    # If Any intermediate node is not found from given path then create empty node and continue
    my $refDTreeNodesList = \%headOfDTree;
    my $lastNode;
    foreach my $key ( @splittedPath )
    {
        if ( !exists ( $refDTreeNodesList -> { $key } ) )
        {
            $refDTreeNodesList -> { $key } = createNode($key);
        }
        $lastNode = $refDTreeNodesList -> {$key};
        $refDTreeNodesList = \%{ $refDTreeNodesList -> { $key } -> Node::childNodes } ;
    }
    # Assign node member values for the last node based on last key(path name) in thn given path
    $lastNode->compatible($mrwTargetList{$TargetID} -> MRWTarget::targetType);
    $lastNode->attributeList($mrwTargetList{$TargetID} -> MRWTarget::targetAttrList);

    # Using CHIP_UNIT for index attribute if exist
    # because unit id should be unique within proc target as per pdbg
    # expectation for address translation
    if (exists ${$lastNode->attributeList}{"CHIP_UNIT"})
    {
        $lastNode->index(${$lastNode->attributeList}{"CHIP_UNIT"}->value);
    }
    # Filling index for ocmb based on omi target
    # CHIP_UNIT attribute because, those targets are not pervasive target
    if ( index( $lastNode->compatible, "chip-ocmb") != -1 )
    {
        #get the number at the end of the physical path and use that as the index
        if (exists ${$lastNode->attributeList}{"PHYS_PATH"})
        {
            my $input = ${$lastNode->attributeList}{"PHYS_PATH"}->value;
            my $index = 0;
            if ($input =~ /(\d+)$/) 
            {
                $index = $1;
            }
            $lastNode->index($index);
        }
        # Changing node name for ocmb target as per pdbg expectation.
        # Removing "_chip" from ocmb target element value from PHYS_PATH value.
        my $nodeName = $lastNode->nodeName;
        $nodeName =~ s/_chip//g;
        $lastNode->nodeName($nodeName);
    }
    #for the dimms also use the index same as its position
    elsif (index ($lastNode->compatible, "ddr") != -1)
    {
        #get the number at the end of the physical path and use that as the index
        if (exists ${$lastNode->attributeList}{"PHYS_PATH"})
        {
            my $input = ${$lastNode->attributeList}{"PHYS_PATH"}->value;
            my $index = 0;
            if ($input =~ /(\d+)$/) 
            {
                $index = $1;
            }
            $lastNode->index($index);
        }
    }
    elsif ($lastNode->compatible eq "unit-fsi")
    {
        my $index = substr($TargetID, index($TargetID, "fsi") + 3);
        $lastNode->index($index);
    }
    elsif ($lastNode->compatible eq "unit-pib")
    {
        my $index = substr($TargetID, index($TargetID, "pib") + 3);
        $lastNode->index($index);
    }
    elsif ($lastNode->compatible eq "chip-adc")
    {
        my $nodeName = $lastNode->nodeName;
        $nodeName =~ s/generic_i2c_device/adc/g;
        $lastNode->nodeName($nodeName);
        $lastNode->index(${$lastNode->attributeList}{"FAPI_POS"}->value);
    }
    elsif ($lastNode->compatible eq "chip-PCA9554")
    {
        my $nodeName = $lastNode->nodeName;
        $nodeName =~ s/generic_i2c_device/gpio_expander/g;
        $lastNode->nodeName($nodeName);
        $lastNode->index(${$lastNode->attributeList}{"FAPI_POS"}->value);
    }
    elsif ($lastNode->compatible eq "chip-vreg-generic")
    {
        $lastNode->index(${$lastNode->attributeList}{"FAPI_POS"}->value);
    }
    elsif (index ($lastNode->compatible, "unit-mem_port") != -1)
    {
        $lastNode->index(${$lastNode->attributeList}{"FAPI_POS"}->value);
    }

    # Add the reg property for the target if that contains "I2C_ADDRESS"
    # attribute to perform the i2c read and write operation on this target.
    if (exists ${$lastNode->attributeList}{"I2C_ADDRESS"})
    {
        $lastNode->reg(${$lastNode->attributeList}{"I2C_ADDRESS"}->value);

        # Get the parent target to add address and size cells properties
        # in the device tree since added the reg property so these properties
        # are required in the parent target to perform the address translation.
        my @parentPathEleKey = @splittedPath;
        pop @parentPathEleKey;

        my $parentNode;
        $refDTreeNodesList = \%headOfDTree;
        foreach my $key ( @parentPathEleKey )
        {
            $parentNode = $refDTreeNodesList -> { $key };
            $refDTreeNodesList = \%{ $refDTreeNodesList -> { $key } -> Node::childNodes } ;
        }

        # Adding address and size cells value as "0x01" and "0x00" respectively
        # since the I2C_ADDRESS attribute is uint8 type
        $parentNode->address_cells(0x01);
        $parentNode->size_cells(0x00);
    }
}

sub createNode
{
	my $node = Node->new();
	$node->nodeName($_[0]);
    $node->index(substr($node->nodeName, index($node->nodeName, '-') + 1));
    $node->compatible("");
    $node->attributeList({});
    $node->childNodes({});
    $node->address_cells("");
    $node->size_cells("");
    $node->reg("");
    return ($node);
}

sub createDTSFile
{
	open $dtsFHandle, '>', $dtsFilename or die "Could not open $dtsFilename: \"$!\"";

	# Add DTS version and staring brace
	print {$dtsFHandle} "/dts-v1/;\n\n/ {\n";

	# Add all nodes into DTS file
    addNodesIntoDTSFile(\%headOfDTree);

	# Add end brace to DTS
	print {$dtsFHandle} "};";

    close $dtsFHandle;
    my $baseDtsFileName = basename($dtsFilename);
    print "\nDevice tree structure file \"$baseDtsFileName\" is created successfully...\n";
}

sub addNodesIntoDTSFile
{
    my $nodes = $_[0];

    my $addDevTreeNode = 1;
    my $addCompProp = 1;
    my $addIndexProp = 1;
    my @sortedKeys = sort { numericalSort($a, $b) } keys %{$nodes};

    foreach my $key ( @sortedKeys)
    {
        # Don't add device tree node for below targets as per pdbg expectaion
        if ( $key =~ m/sys/ or $key =~ m/node/ )
        {
            $addDevTreeNode = 0;
        }

        # Don't add compatible property for below targets as per pdbg expectaion
        if ( $key =~ m/sys/ or $key =~ m/node/ or $key =~ m/fsi/ or
             $key =~ m/pib/ or $key =~ m/^i2c-/ )
        {
            $addCompProp = 0;
        }

        # Don't add index property for below targets as per pdbg expectaion
        if ( $key =~ m/sys/ or $key =~ m/node/ or $key =~ m/^i2c-/ )
        {
            $addIndexProp = 0;
        }

        my $nodeName = $nodes -> {$key} -> Node::nodeName;

        # Removing "-" in the node name as per pdbg expectation except
        # below targets
        if (!($nodeName =~ m/^i2c-/))
        {
            $nodeName =~ s/-//g;
        }

        print {$dtsFHandle} "\n$nodeName {\n" if $addDevTreeNode eq 1;

        addTargetDataIntoDTSFile($nodes->{$key}, $addIndexProp, $addCompProp);
        addNodesIntoDTSFile($nodes -> {$key} -> Node::childNodes);

        print {$dtsFHandle} "};\n" if $addDevTreeNode eq 1;
    }
}

sub addTargetDataIntoDTSFile
{
    my $devTreeNode = $_[0];
    my $indexReqToAdd = $_[1];
    my $compPropReqAdd = $_[2];

    my %attributeList = %{$devTreeNode->attributeList};

    if ( $compPropReqAdd eq "1" )
    {
        # Add "compatible" property
        my $pdbgCompPropertyVal;
        if ( exists $pdbgCompPropMapList{$devTreeNode->compatible} )
        {
            $pdbgCompPropertyVal = $pdbgCompPropMapList{$devTreeNode->compatible};
            # Not adding double quotes if present, to support list of compatible property
            $pdbgCompPropertyVal = "\"".$pdbgCompPropertyVal."\"" if !( $pdbgCompPropertyVal =~ m/"/);
        }
        else # If not found using mrw target type name only
        {
            $pdbgCompPropertyVal = "\"".$devTreeNode->compatible."\"";
        }

        print {$dtsFHandle} "compatible = $pdbgCompPropertyVal;\n" if $pdbgCompPropertyVal ne "\"\""; # not adding empty
    }

    if ($devTreeNode->reg ne "")
    {
        # Add reg property
        my $regPropVal = $devTreeNode->reg;
        print {$dtsFHandle} "reg = <$regPropVal>;\n";
    }

    if ($devTreeNode->address_cells ne "")
    {
        # Add "#address-cells" property
        my $addrCellsVal = $devTreeNode->address_cells;
        print {$dtsFHandle} "#address-cells = <$addrCellsVal>;\n";
    }

    if ($devTreeNode->size_cells ne "")
    {
        # Add "#size-cells" property
        my $sizeCellsVal = $devTreeNode->size_cells;
        print {$dtsFHandle} "#size-cells = <$sizeCellsVal>;\n";
    }

    if ($indexReqToAdd eq 1)
    {
        # Add index property
        my $nodeIndexHex = sprintf("<0x%02x>", $devTreeNode->index);
        print {$dtsFHandle} "index = $nodeIndexHex;\n";
    }

    # Adding PHYS_DEV_PATH and PHYS_BIN_PATH attributes value by using PHYS_PATH attribute.
    # because, PHYS_PATH type is class which is not supported in device tree.
    if (exists $attributeList{"PHYS_DEV_PATH"})
    {
        $attributeList{"PHYS_DEV_PATH"}->value($attributeList{"PHYS_PATH"}->value);
    }
    if (exists $attributeList{"PHYS_BIN_PATH"})
    {
        $attributeList{"PHYS_BIN_PATH"}->value(getBinaryFormatForPhysPath($attributeList{"PHYS_PATH"}->value));
    }

    # Attributes
    my @sortedKeys = sort { numericalSort($a, $b) } keys %attributeList;
    foreach my $AttrID ( @sortedKeys )
    {
        my $attrType = getAttributeType($AttrID);
        if ( $attrType eq "")
        {
            next;
        }

        # Don't add the attributes if that not required in the device tree
        # attributes list.
        if ($attributeDefList{$AttrID} -> AttributeDefinition::notRequiredInDevTree eq "1")
        {
            next;
        }

        # Ignoring MRW Target attributes if not found in FAPI list
        # because, MRW Target having common attributes for all targets but,
        # it may not be required to specific targets.
        # Ex: Non-FAPI targets having FAPI_POS and REL_POS and those attributes
        # are specific to fapi targets.
        if ( !exists ${$fapiTargetList{$devTreeNode->compatible}->targetAttrList}{$AttrID} )
        {
            next;
        }

        if ($attrType eq "simpleType")
        {
            my $attrVal = $attributeList{$AttrID} -> AttributeData::value;

            # TODO Need to revisit setting CHIP_UNIT_POS value from CHIP_UNIT
            # Added beacuse HWPs expecting CHIP_UNIT_POS value and its should come MRW
            # So once added in MRW need to remove
            $attrVal = $attributeList{"CHIP_UNIT"} -> AttributeData::value if $AttrID eq "CHIP_UNIT_POS";
            # Getting default value from attribute definition if not value is defined
            my $simpleType = $attributeDefList{$AttrID}-> AttributeDefinition::simpleType;
            my $simpleTypeDefault = $simpleType->default;
            $attrVal = $simpleTypeDefault if $attrVal eq "";

            my $isToolAddedDefVal = 0;
            if ( $attrVal eq "" )
            {
                $attrVal = 0;
                $isToolAddedDefVal = 1;
            }

            if( $simpleType->DataType eq "array")
            {
                my $eleCnt = 1;
                my @dims = split(/,/, $simpleType->arrayDimension);
                foreach my $dim (@dims)
                {
                    $eleCnt *= $dim;
                }

                my @arrayValues;
                if ( $simpleType->subType eq "string" )
                {
                    (@arrayValues) = $attrVal =~ m/"(.*?)"/g;
                }
                elsif( index($simpleType->subType, "enum_") != -1)
                {
                    # Resetting value as empty if tool is initialized to get enum value from enum definition
                    $attrVal = "" if $isToolAddedDefVal eq 1;
                    my $enumNames = $attrVal if $attrVal ne "";

                    # Getting default value from enum definition if value is not defined
                    my $enumDef = $simpleType->enumDefinition;
                    $enumNames = $enumDef->default if $enumNames eq "";

                    @arrayValues = split(/,/,$enumNames);
                    foreach my $enumName (@arrayValues)
                    {
                        # Getting enum value from enum name
                        my $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, $enumName);

                        # Setting first enum value as default value if not found
                        $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, "") if $enumVal eq "";
                        # Replacing enum name with value
                        $enumName = $enumVal;
                    }
                }
                else
                {
                    @arrayValues = split(/,/,$attrVal);
                }

                # Adding 0 for non available value for array element count
                my $arrayValuesSize = @arrayValues;
                for ( my $i = $arrayValuesSize; $i < $eleCnt; $i++)
                {
                    push(@arrayValues, 0)
                }
                setDTSFormatValueForSimpleAttr($AttrID, $simpleType->DataType."_".$simpleType->subType, \@arrayValues, $eleCnt)
            }
            elsif ( $simpleType->DataType eq "int8_t" or $simpleType->DataType eq "int16_t" or $simpleType->DataType eq "int32_t"  or $simpleType->DataType eq "int64_t" or 
                $simpleType->DataType eq "uint8_t" or $simpleType->DataType eq "uint16_t" or $simpleType->DataType eq "uint32_t"  or $simpleType->DataType eq "uint64_t")
            {
                my @arrayValues;
                push(@arrayValues, $attrVal);
                setDTSFormatValueForSimpleAttr($AttrID, $simpleType->DataType, \@arrayValues, 1)
            }
            elsif ( $simpleType->DataType eq "enum")
            {
                # Resetting value as empty if tool is initialized to get enum value from enum definition
                $attrVal = "" if $isToolAddedDefVal eq 1;

                my $enumName = $attrVal if $attrVal ne "";

                # Getting default value from enum definition if value is not defined
                my $enumDef = $simpleType->enumDefinition;
                $enumName = $enumDef->default if $enumName eq "";

                my $enumVal;
                if ($enumName ne "0")
                {
                    # Getting enum value from enum name
                    $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, $enumName);

                    # Setting first enum value as default value,
                    $enumVal = getEnumVal(\@{$enumDef->enumeratorList}, "") if $enumVal eq "";
                }
                else
                {
                    # FAPI (ekb) Enum attribute will may have initToZero tag
                    # so, default value will be 0
                    $enumVal = $enumName;
                }

                my @arrayValues;
                push(@arrayValues, $enumVal);
                setDTSFormatValueForSimpleAttr($AttrID, $simpleType->DataType."_".$simpleType->subType, \@arrayValues, 1)
            }
            elsif ( $simpleType->DataType eq "string")
            {
                # Reducing one byte from size to exclude NULL
                # because dtc will add null for string type
                my $size = ($simpleType->stringSize) - 1;
                my $strAttrVal = pack("Z$size", $attrVal);
                my @arrayValues;
                push(@arrayValues, $strAttrVal);
                setDTSFormatValueForSimpleAttr($AttrID, $simpleType->DataType, \@arrayValues, 1)
            }
        }
        elsif ( $attrType eq "complexType" )
        {
            my $attrValue = $attributeList{$AttrID} -> AttributeData::value;

            if ($attrValue eq "")
            {
                my @ret = getSpecAndDefValForComplexTypeAttr(\@{$attributeDefList{$AttrID}->complexType->listOfComplexTypeFields}, $attributeDefList{$AttrID}->complexType->arrayDimension);
                $attrValue = @ret[1];
            }
            my $dtsFormatedVal = "[".$attrValue." ]";
            print {$dtsFHandle} "$attrPrefix$AttrID = $dtsFormatedVal;\n";
        }
    }
}

sub getAttributeType
{
    my $attrID = $_[0];
    my $attrType;

    if( exists $attributeDefList{$attrID})
    {
        $attrType = $attributeDefList{$attrID}-> AttributeDefinition::datatype;
    }
    else
    {
        print "ERROR: Attribute: $attrID is not found in attribute definition\n" if isVerboseReq('E');
    }

    return ($attrType);
}

sub setDTSFormatValueForSimpleAttr
{
    my $attrName = $_[0];
    my $type = $_[1];
    my @values = @{$_[2]};
    my $eleCnt = $_[3];

    # Getting actual type from input type value if type contains array or enum
    # E.g : enum_uint32_t => uint32 or array_enum_uint32_t  => uint32
    if ( $type =~ m/array/ or $type =~ m/enum/ )
    {
        $type = substr($type, 0, rindex($type, "_"));
        $type = substr($type, rindex($type, "_") + 1);
    }

    my $dtsFormatedVal;
    my $begFormatSym;
    my $valSize = @values;
    foreach my $pValue (@values)
    {
        if( $type =~ m/int8/ )
        {
            if ( $pValue =~ m/0x/ )
            {
                $pValue =~ s/0x//g;
                $pValue = "0".$pValue if length($pValue) == 1;
            }
            else
            {
                $pValue = sprintf("%02X", $pValue);
            }

            $begFormatSym = "[" if $begFormatSym eq "";
            $dtsFormatedVal .= $pValue;
            $dtsFormatedVal .= " " if $valSize > 1;
        }
        elsif( $type =~ m/int16/ )
        {
            if ( $pValue =~ m/0x/ )
            {
                $pValue =~ s/0x//g;
                for ( my $x = 0; length($pValue) < 4; $x + 1) { $pValue = "0".$pValue }
            }
            else
            {
                $pValue = sprintf("%04X", $pValue);
            }

            my $fByte = substr($pValue, 0, 2);
            my $sByte = substr($pValue, 2, 2);

            $begFormatSym = "[" if $begFormatSym eq "";
            $dtsFormatedVal .= $fByte." ".$sByte;
            $dtsFormatedVal .= " " if $valSize > 1;
        }
        elsif( $type =~ m/int32/ )
        {
            $begFormatSym = "<" if $begFormatSym eq "";
            $dtsFormatedVal .= "$pValue";
            $dtsFormatedVal .= " " if $valSize > 1;
        }
        elsif( $type =~ m/int64/ )
        {
            $begFormatSym = "<" if $begFormatSym eq "";
            $dtsFormatedVal .= "$pValue";
            $dtsFormatedVal .= " " if $valSize > 1;
        }
        elsif( $type =~ m/string/ )
        {
           $dtsFormatedVal .= "\"$pValue\"";
           $dtsFormatedVal .= ", " if $valSize > 1;
        }
        else
        {
            # Unsupported type given
            return "";
        }
    }
    $dtsFormatedVal = "[ ".$dtsFormatedVal if $begFormatSym eq "[";
    $dtsFormatedVal .= " ]" if $begFormatSym eq "[";
    $dtsFormatedVal = "<".$dtsFormatedVal if $begFormatSym eq "<";
    $dtsFormatedVal .= ">" if $begFormatSym eq "<";
    print {$dtsFHandle} "$attrPrefix$attrName = $dtsFormatedVal;\n";
}

sub getEnumVal
{
    my @enumeratorList = @{$_[0]};
    my $enumName = $_[1];

    if ($enumName ne "")
    {
        # check enum name is hex in enumeratorList
        # to match with given enum name
        if ((substr($enumName, 0, 2) eq "0x") and
            (substr($enumeratorList[0][0], 0, 2) ne "0x"))
        {
            $enumName = hex($enumName);
        }

        # enumPair<enumName, enumValue>
        foreach my $enumPair ( @enumeratorList )
        {
            my $enumVal = "";
            if ($enumName eq $enumPair->[0])
            {
                $enumVal = $enumPair->[1];
            }

            # Make sure given enum name is enum value as well. Because,
            # In MRW, there may be chance to use enum value instead enum name
            # for defalut value
            if ( ($enumVal eq "") and ($enumName eq $enumPair->[1]) )
            {
                $enumVal = $enumPair->[1];
            }

            return $enumVal if ($enumVal ne "");
        }
    }
    else
    {
        # Return first enum value if enum name is empty
        return $enumeratorList[0][1];
    }

    return "";
}

sub getBinaryFormatForPhysPath
{
    my $physPath = $_[0];

    my ($pathType, $path) = split(/:/, $physPath);
    my @pathElements = split(/\//, $path);
    my $pathElementsSize = @pathElements;

    # Reducing one from configured array size and dividing by 2 to get path element size
    my $configpathElementsSize = ($attributeDefList{"PHYS_BIN_PATH"}->simpleType->arrayDimension - 1) / 2;

    if ( $configpathElementsSize < $pathElementsSize )
    {
        print "CRITICAL: The max path element size of PHYS_BIN_PATH is $configpathElementsSize but the given path element size in PHYS_DEV_PATH attribute value[$physPath] is $pathElementsSize\n" if isVerboseReq('C');
        return "";
    }

    if ( $pathType eq "physical" )
    {
        $pathType = 2;
    }
    else
    {
        print "CRITICAL: Invalid path type[$pathType] in given path [$physPath]\n" if isVerboseReq('C');
        return "";
    }

    # Device tree is big endian format. so, storing path type and size of path elements values
    # as one byte in big endian format.
    my $pathtype_size = (0xF0 & ($pathType << 4)) + (0x0F & $pathElementsSize);

    my $convertedBinaryFormat = $pathtype_size.",";

    foreach my $pathEle ( @pathElements )
    {
        # splitting path element into type and instance. e.g: sys-0 => type = sys and instance = 0
        my @pathEleFields = split(/-/, $pathEle);
        my $found = 0;
        foreach my $tgtTypeEnum ( @{$attributeDefList{"TYPE"}->simpleType->enumDefinition->enumeratorList} )
        {
            if ( uc($pathEleFields[0]) eq $tgtTypeEnum->[0] )
            {
                $found = 1;
                # storing target type and its instance value as binary format.
                # e.g.: sys-0 => 00 00 => first "00" is enum value of sys and second "00" is hex value of 0
                $convertedBinaryFormat .= $tgtTypeEnum->[1].",".$pathEleFields[1].",";
            }
        }

        if ( $found eq 0 )
        {
            print "CRITICAL: The given path element type[$pathEleFields[0]] for path[$physPath] is not found in TYPE attibute enum list.\n" if isVerboseReq('C');
            return "";
        }
    }

    # Adding zero if the path elements size which is found in given PHYS_DEV_PATH
    # is less than the config size
    if ( $configpathElementsSize > $pathElementsSize )
    {
        for (my $i = $pathElementsSize; $i < $configpathElementsSize; $i++)
        {
            # for target type field
            $convertedBinaryFormat .= "0".",";
            # for target instance field
            $convertedBinaryFormat .= "0".",";
        }
    }

    return $convertedBinaryFormat;
}
###############################
#      Subroutine End         #
###############################
