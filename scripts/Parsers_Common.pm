# IBM_PROLOG_BEGIN_TAG
# This is an automatically generated prolog.
#
# fips1110 src/fwsm/mrw_parser/Parsers_Common.pm 1.10.1.1
#
# IBM CONFIDENTIAL
#
# OBJECT CODE ONLY SOURCE MATERIALS
#
# COPYRIGHT International Business Machines Corp. 2017,2022
# All Rights Reserved
#
# The source code for this program is not published or otherwise
# divested of its trade secrets, irrespective of what has been
# deposited with the U.S. Copyright Office.
#
# IBM_PROLOG_END_TAG
############################  Change Logs  ####################################
#
#  PTR/DCR#  Userid    Date        Description
#  --------  --------  ----------  ------------------------------------------
#  SWxxxxxx  xxxxxxxx  mm/dd/yyyy  <CHANGE_DESCRIPTION>
#  SW385962  gikrish1  04/28/2017   File created.
#  SW390790  puranik   06/15/2017   Add API to get location parser.
#  SW397304  kswaroop  07/28/2017   Handling "ASSEMBLY" location code type.
#  SW389735  puranik   09/16/2017   APIs to get device paths
#  SW408071  puranik   11/15/2017   Add sbefifo support, fix bug in i2c port
#                                   handling.
#  SW409117  kswaroop  01/24/2018   Add function verifyFruPath for validating
#                                   the target paths.
#  SW423932  jthomas7  04/10/2018   Added function to get GPIO Pin number.
#  SW426832  jthomas7  04/27/2018   Added function to get number of nodes and
#                                   Added function to know if it is multinode.
#  SW428983  jthomas7  05/15/2018   Added function to check if passed target
#                                   is in control node or not.
#  SW431119  gikrish1  05/25/2018   Added cfam bus type for device paths
#  SW551568  gikrish1  07/15/2022   Removal of smartmatch operator warning.
#
###############################################################################
# FILE: File contains common parser functions.
###############################################################################

package Parsers_Common;
use strict;

our $debug = 0;
our $return_code = 0;

use constant IIC_PATH => "iic";
use constant GPIO_PATH => "gpio";
use constant CFAM_PATH => "cfam";
use constant SCAN_PATH => "scan";
use constant SCOM_PATH => "scom";
use constant DEV_PREFIX => "/dev/";

#** @function printWrapper ($string)
# @brief This is the function which wraps the print with file name
#
# @params $string           required    print statements
#*
sub printWrapper
{
    printf("%s: %s\n", $0, @_);
}

#** @function printDebug ($string)
# @brief This is the function which wraps the debug message.
#
# @params $string           required    debugging statements
#*
sub printDebug
{
    my $str = shift;
    if ($debug == 1)
    {
        printWrapper("DEBUG: ". $str. "\n");
    }
}

#** @function printWarn ($string)
# @brief This is the function which wraps the warning message.
#
# @params $string           required    warning statements
#*
sub printWarn
{
    my $str = shift;
    printWrapper("WARNING: ". $str. "\n");
}

#** @function printErr($string)
# @brief This is the function which wraps the Error message and sets error
# return_code.
#
# @params $string           required    Error statements
#*
sub printErr
{
    my $str = shift;
    printWrapper( "ERROR: ". $str. "\n");
    $return_code =1;
}

#** @function printUsage ()
# @brief This is the function which prints the usage.
#
#*
sub printUsage
{
    print "
    $0 -i [XML filename] -o [Output filename] -p [Platform name] [OPTIONS]
Options:
    -f = force output file creation even when errors
    -d = debug mode
    -v = verbose mode - for verbose o/p from Targets.pm
        \n";
        exit(1);
}

#** @function getLocationCode ()
# @brief Returns the location code for a given target.
#
# @params $targetIface required The Targets interface
# @params $target required The target for which location code is needed.
#
# @return The location code for the target, empty if error.
#*
sub getLocationCode
{
    my $targetObj = shift;
    my $tempTarget = shift;

    my @locationCodeArray = "";
    my $arrayIndex = 0;
    my $locationCode = "Ufcs";
    my $locationCodeType = '';
    my $tempLocationCode = '';

    if($targetObj->getTargetParent($tempTarget) eq '')
    {
        $locationCode = 'Ufcs';
    }
    else
    {
        my $finish = 1;
        do
        {
            if(!defined $tempTarget)
            {
                $finish = 0;
            }
            else
            {
                if(!$targetObj->isBadAttribute($tempTarget, "LOCATION_CODE"))
                {
                    $tempLocationCode = $targetObj->getAttribute($tempTarget,
                        "LOCATION_CODE");
                }
                else
                {
                    $tempLocationCode = '';
                }
                if(!$targetObj->isBadAttribute($tempTarget,
                        "LOCATION_CODE_TYPE"))
                {
                    $locationCodeType = $targetObj->getAttribute($tempTarget,
                        "LOCATION_CODE_TYPE");
                }
                else
                {
                    $locationCodeType = '';
                }
                if($locationCodeType eq '' || $locationCodeType eq 'ASSEMBLY' ||
                    $tempLocationCode eq '')
                {
                    $tempTarget = $targetObj->getTargetParent($tempTarget);
                }
                elsif($locationCodeType eq 'RELATIVE')
                {
                    $locationCodeArray[$arrayIndex++] = $tempLocationCode;
                    $tempTarget = $targetObj->getTargetParent($tempTarget);
                }
                elsif($locationCodeType eq 'ABSOLUTE')
                {
                    $locationCodeArray[$arrayIndex++] = $tempLocationCode;
                    $finish = 0;
                }
            }
        }while($finish);
    }

    for(my $i = $arrayIndex; $i > 0; $i--)
    {
        $locationCode = $locationCode."-".$locationCodeArray[$i-1];
    }
    return $locationCode;

}

#** @function getAttributeSafe ()
# @brief Simple wrapper over getAttribute that returns an empty string if
#        attribute value is "bad"
#
# @params $targetIface required The Targets interface
# @params $target required The target for which attribute is required
# @params $attrName required The attribute requested
#
# @return Attribute value as string, if one is found, else ""
#*
sub getAttributeSafe
{
    my $targetIface = shift;
    my $target = shift;
    my $attrName = shift;

    my $attr = "";

    if(!$targetIface->isBadAttribute($target, $attrName))
    {
        $attr = $targetIface->getAttribute($target, $attrName);
    }
    else
    {
        printWarn("Bad attribute: $attrName on target $target");
    }

    return $attr;
}

#** @function getParentByClass ()
# @brief Returns the first parent up the hierarchy of the target by class
#
# @params $targetIface required The Targets interface
# @params $target required The target for which the parent is requested
# @params $class required The CLASS of parent needed
#
# @return The required parent target. undef if none is found
#*
sub getParentByClass
{
    my $targetIface = shift;
    my $target = shift;
    my $class = shift;

    my $ancestor = undef;
    my $parent = $target;

    while(defined $parent)
    {
        if(getAttributeSafe($targetIface, $parent, "CLASS") eq $class)
        {
            $ancestor = $parent;
            goto END;
        }
        else
        {
            $parent = $targetIface->getTargetParent($parent);
        }
    }
END:
    return $ancestor;
}

#** @function getParentCard ()
# @brief Returns the first parent card up the hierarchy
#
# @params $targetIface required The Targets interface
# @params $target required The target for which the parent is requested
#
# @return The required parent target. undef if none is found
#*
sub getParentCard
{
    my $targetIface = shift;
    my $target = shift;

    return getParentByClass($targetIface, $target, "CARD");
}

#** @function getParentConnector ()
# @brief Returns the first parent connector up the hierarchy
#
# @params $targetIface required The Targets interface
# @params $target required The target for which the parent is requested
#
# @return The required parent target. undef if none is found
#*
sub getParentConnector
{
    my $targetIface = shift;
    my $target = shift;

    return getParentByClass($targetIface, $target, "CONNECTOR");
}

#** @function getParentNode ()
# @brief Returns the first parent node up the hierarchy
#
# @params $targetIface required The Targets interface
# @params $target required The target for which the parent is requested
#
# @return The required parent target. undef if none is found
#*
sub getParentNode
{
    my $targetIface = shift;
    my $target = shift;

    return getParentByClass($targetIface, $target, "ENC");
}

#** @function getParentChip ()
# @brief Returns the first parent chip up the hierarchy
#
# @params $targetIface required The Targets interface
# @params $target required The target for which the parent is requested
#
# @return The required parent target. undef if none is found
#*
sub getParentChip
{
    my $targetIface = shift;
    my $target = shift;

    return getParentByClass($targetIface, $target, "CHIP");
}

#** @function getFsiPathToMyCfam ()
# @brief Returns the FSI path to the CFAM contained within the input chip target
#
# @params $targetIface required The Targets interface
# @params $target required The chip target which contains the CFAM. Only
#                          supported targets are the FSP, CFAM-S, DPSS,
#                          processor chip, and membuf chip
#
# @return Returns a tuple with the FSP A path and FSP B path (if applicable,
#         else empty)
#*
sub getFsiPathToMyCfam
{
    my $targetIface = shift;
    my $target = shift;

    my $fspAPath = "";
    my $fspBPath = "";

    if(getAttributeSafe($targetIface, $target, "CLASS") ne "CHIP")
    {
        printWarn("Input target $target is not a CHIP class");
        goto END;
    }
    if(0 == _isCfamChip($targetIface, $target))
    {
        printWarn("Input chip target: $target does not have a CFAM ");
        goto END;
    }

    my $tmp = 0;
    ($fspAPath, $fspBPath) = _buildFsiPathRecursively($targetIface, $target,
                                                      "", undef, \$tmp);
END:
    return ($fspAPath, $fspBPath);
}

#** @brief Returns paths to the given engine type, given a chip
#
# @params $targetIface required The Targets interface
# @params $target required The chip target for which the engine path is
#                          requested
# @params $engineType required Engine type requested
#
# @return Returns a tuple with FSP A path and FSP B path (where applicable)
#         respectively
#*
sub getEnginePath
{
    my $targetIface = shift;
    my $target = shift;
    my $engineType = shift;

    my $fspAPath = "";
    my $fspBPath = "";
    my %engine = ('scan' => 1, 'scom' => 1, 'mtd' => 1, 'mtdblock' => 1, 'mbx' => 1, 'sbefifo' => 1);

    unless(exists($engine{$engineType}))
    {
        printWarn("Supplied engine: $engineType not suported");
        goto END;
    }

    if(0 == _checkEngineAndChipType($targetIface, $target, $engineType))
    {
        printWarn("The input target $target does not support the supplied ".
                  "engine");
        goto END;
    }

    ($fspAPath, $fspBPath) = getFsiPathToMyCfam($targetIface, $target);

    my $pathPrefix = DEV_PREFIX;
    my $engineAndPort = "";

    $pathPrefix = $pathPrefix . "$engineType/";
    if($engineType eq 'scan')
    {
        $engineAndPort = "E03P00";
    }
    elsif($engineType eq 'scom')
    {
        $engineAndPort = "E04P00";
    }
    elsif($engineType eq 'mbx')
    {
        $engineAndPort = "E10P00";
    }
    elsif($engineType eq 'sbefifo')
    {
        $engineAndPort = "E09P00";
    }
    else #($engineType eq 'mtd' or $engineType eq 'mtdblock')
    {
        $pathPrefix = $pathPrefix . "sfc.";
        $engineAndPort = "E03P00";
    }

    if($fspAPath ne "")
    {
        $fspAPath = $pathPrefix . $fspAPath . $engineAndPort;
    }

    if($fspBPath ne "")
    {
        $fspBPath = $pathPrefix . $fspBPath . $engineAndPort;
    }
END:
    return ($fspAPath, $fspBPath);
}

#** @brief Returns FSP device paths to the given end device. The end device must
#        lie on an endpoint of a connection. In case of IIC, it must me the
#        destination of an IIC connection, in case of a GPIO it can be either
#        the source or the endpoint.
#
# @params $targetIface required The Targets interface
# @params $target required The chip target for which the engine path is
# @params $engineType required Engine type requested. Only 'iic' and 'gpio' are
#                              supported
#
# @return Returns a tuple of arrays with FSP A paths and FSP B paths
#         (where applicable) respectively
#*
sub getFspDevicePaths
{
    my $targetIface = shift;
    my $target = shift;
    my $engineType = shift;

    my @fspAPaths;
    my @fspBPaths;

    if(($engineType ne 'iic') and ($engineType ne 'gpio') and ($engineType ne
            'psi') and ($engineType ne 'cfam'))
    {
        printWarn("This API does not support engine: $engineType");
        goto END;
    }

    my $pathPrefix = DEV_PREFIX . "$engineType/";
    my $busType = uc($engineType);
    my @engines;

    if(($engineType eq 'cfam'))
    {
        $busType = $targetIface->getBusType($target);
        if(($busType ne 'FSIM') and ($busType ne 'FSICM'))
        {
            printErr("Wrong bus type for CFAM: Bus type must be FSIM or FSICM");
        }
    }
    if($engineType eq 'iic')
    {
        $busType = 'I2C';
    }

    # Look for a connection with this as the endpoint
    my $destConnections =
        $targetIface->findDestConnections(
            $targetIface->getTargetParent($target),
            $busType, "");

    if($destConnections ne "")
    {
        foreach my $destConnection (@{$destConnections->{CONN}})
        {
            if($destConnection->{DEST} eq $target)
            {
                push (@engines, $destConnection->{SOURCE});
            }
        }
    }

    if($engineType eq 'gpio') # Only GPIOs can be sources
    {
        # Look for a connection with this as the source
        my $sourceConnections =
            $targetIface->findConnections(
                $targetIface->getTargetParent($target),
                uc($engineType), "");

        if($sourceConnections ne "")
        {
            foreach my $sourceConnection (@{$sourceConnections->{CONN}})
            {
                if($sourceConnection->{SOURCE} eq $target)
                {
                    push (@engines, $sourceConnection->{DEST});
                }
            }
        }
    }

    # Iterate over each engine to extract the engine and port values. In case of
    # non-iou engines, it is just the port
    foreach my $engine (@engines)
    {
        printDebug("Processing engine: $engine");
        if($engineType eq 'iic')
        {
            if(getAttributeSafe($targetIface, $engine, "I2C_CONNECTION_TYPE") eq
               'PIB')
            {
                printDebug("Ignoring PIB engine: $engine");
                next;
            }
        }

        # For GPIOs, only support engines of FSP or CFAMs
        if($engineType eq 'gpio')
        {
            my $engineChip = getParentChip($targetIface, $engine);
            my $engineChipType = $targetIface->getTargetType($engineChip);

            unless(($engineChipType =~ 'chip-sp-fsp2') or ($engineChipType =~
                'chip-sp-cfams'))
            {
                printWarn("GPIO engines not supported on chip: $engineChip " .
                    "of type $engineChipType");
                next;
            }
        }

        my ($enginePort, $isNonIou, $fspPos) =
            _getEngineAndPort($targetIface, $engine, $engineType);

        if(1 == $isNonIou)
        {
            printDebug("This is a non-iou engine on fsp pos: $fspPos");
            my $finalPath = $pathPrefix;
            $finalPath = $finalPath . $enginePort;
            if($fspPos == 0)
            {
                push (@fspAPaths, $finalPath);
                push (@fspBPaths, "");
            }
            else
            {
                push (@fspBPaths, $finalPath);
                push (@fspAPaths, "");
            }
        }
        else
        {
            printDebug("This is a IOU engine");
            my $finalAPath = "";
            my $finalBPath = "";
            my $engineChip = getParentChip($targetIface, $engine);
            my ($fsiAPath, $fsiBPath) = getFsiPathToMyCfam($targetIface,
                                                           $engineChip);

            if($fsiAPath ne "")
            {
                $finalAPath = $pathPrefix . $fsiAPath . $enginePort;
            }
            if($fsiBPath ne "")
            {
                $finalBPath = $pathPrefix . $fsiBPath . $enginePort;
            }

            push(@fspAPaths, $finalAPath);
            push(@fspBPaths, $finalBPath);
        }
    }
END:
    return (\@fspAPaths, \@fspBPaths);
}

# Internal function to validate chip type agsinst engine type
sub _checkEngineAndChipType
{
    my $targetIface = shift;
    my $target = shift;
    my $engine = shift;

    my $isCheckOK = 0;

    if(getAttributeSafe($targetIface, $target, "CLASS") ne 'CHIP')
    {
        printWarn("Input target $target is not of class CHIP");
        goto END;
    }

    my $chipType = $targetIface->getTargetType($target);

    if($chipType =~ 'chip-processor')
    {
        unless(($engine eq 'scan') or ($engine eq 'scom') or
            ($engine eq 'mbx') or ($engine eq 'sbefifo'))
        {
            printWarn("Bad engine $engine on chip $chipType");
            goto END;
        }
    }
    elsif($chipType =~ 'chip-membuf')
    {
        unless(($engine eq 'scan') or ($engine eq 'scom'))
        {
            printWarn("Bad engine $engine on chip $chipType");
            goto END;
        }
    }
    elsif($chipType =~ 'chip-dpss')
    {
        unless(($engine eq 'mtd') or ($engine eq 'mtdblock'))
        {
            printWarn("Bad engine $engine on chip $chipType");
            goto END;
        }
    }
    else
    {
        printWarn("Unsupported chip type: $chipType");
        goto END;
    }

    # OK if we made it this far
    $isCheckOK = 1;

END:
    return $isCheckOK;
}

# Internal function to check if a give chip contains a CFAM
sub _isCfamChip
{
    my $targetIface = shift;
    my $target = shift;

    my $isCfamChip = 0;
    my @allChildren = $targetIface->getAllTargetChildren($target);

    foreach my $child (@allChildren)
    {
        if(($targetIface->getTargetType($child) eq 'unit-fsi-slave') or
           ($targetIface->getTargetType($child) eq 'unit-fsicm-slave'))
       {
           $isCfamChip = 1;
           goto END;
       }
    }

END:
    return $isCfamChip;
}


# Internal function to get engine and port number portion of the device path
sub _getEngineAndPort
{
    my $targetIface = shift;
    my $engine = shift;
    my $engineType = shift;

    my $enginePort = "";
    my $isNonIou = 0;
    my $fspPos = 0; # Only for noniou paths
    my $engineParent = $targetIface->getTargetParent($engine);
    my $engineNum = 0;
    my $portNum = 0;
    my $engineChip = getParentChip($targetIface, $engineParent);
    my $chipType = $targetIface->getTargetType($engineChip);

    # Validate that the engine is on a supported chip
    unless(($chipType =~ 'chip-sp-fsp2') or ($chipType =~ 'chip-sp-cfams') or
           ($chipType =~ 'chip-processor') or ($chipType =~ 'chip-membuf'))
    {
        printWarn("Unsupported chip: $engineChip with type: $chipType");
        goto END;
    }


    # Handle non-iou paths
    if(($targetIface->getTargetType($engineParent) =~
        'unit-noniomux_config-fsp2') and ($engineParent !~
        'fsp_i2c_boe_noniomux_group'))
    {
        $isNonIou = 1;
        $fspPos = _getFspPosition($targetIface, $engineChip);

        if($engineType eq 'gpio')
        {
            $engineNum = 0;
            $portNum = getAttributeSafe($targetIface, $engine, "PIN_NUM");
            $enginePort = sprintf("%d,%d", $engineNum, $portNum);
        }
        elsif($engineType eq 'iic')
        {
            $engineNum = getAttributeSafe($targetIface, $engine, "I2C_ENGINE");
            $enginePort = $engineNum;
        }
        elsif($engineType eq 'psi')
        {
            $engineNum = getAttributeSafe($targetIface, $engine, "PSI_ENGINE");
            $enginePort = $engineNum;
        }
        else
        {
            printWarn("Unsupported engine type $engineType for $engine");
            goto END;
        }
        goto END;
    }

    if($engineType eq 'cfam')
    {
        $enginePort = sprintf("E%02d",0);
    }
    # Special handling for BOE I2C engine, Processor and Centaur engines
    if(($chipType =~ 'chip-processor') or ($chipType =~ 'chip-membuf') or
       ($engineParent =~ 'fsp_i2c_boe_noniomux_group') or
       ($engineParent =~ 'cfams_noniomux_i2c_group'))
    {
        unless($engineType eq 'iic')
        {
            printWarn("Engine type $engineType not supported on $chipType");
            goto END;
        }
        $engineNum = getAttributeSafe($targetIface, $engine, "I2C_ENGINE");
        $portNum = getAttributeSafe($targetIface, $engine, "I2C_PORT");
        $enginePort = sprintf("E%02dP%02d", $engineNum, $portNum);
        goto END;
    }

    # Only remaining options are the FSP or CFAM-S engines
    if($engineType eq 'iic')
    {
        my ($ioNum) = $engine =~ m/i2c_m[d]?([0-9])$/g;
        $engineNum = getAttributeSafe($targetIface, $engineParent,
                                      "SP_ENGINE_NUM[$ioNum]");
        my $ioName = getAttributeSafe($targetIface, $engineParent,
                                      "SP_IO_NAME[$ioNum]");

        printDebug("IO Name: $ioName");

        ($portNum) = $ioName =~ m/i2c_m[d]?[0-3],(?:I2C|I2CMD[2]?)_(?:SCL|SDA)\[([0-9]+)\]/;

        if(not defined $portNum)
        {
            $portNum = 0;
        }

        printDebug("Port num: $portNum");

        $enginePort = sprintf("E%02dP%02d", $engineNum, $portNum);
    }
    elsif($engineType eq 'gpio')
    {
        my ($ioNum) = $engine =~ m/gpio_([0-9])$/g;
        $engineNum = getAttributeSafe($targetIface, $engineParent,
                                      "SP_ENGINE_NUM[$ioNum]");
        $portNum = 0;

        my $dioStart = getAttributeSafe($targetIface, $engineParent,
                                        "DIO_START");

        printDebug("DIO Start: $dioStart");
        printDebug("IO num: $ioNum");
        my $pinNum = $dioStart + $ioNum;

        $pinNum = $pinNum % 32;
        $enginePort = sprintf("E%02dP%02d,%d", $engineNum, $portNum, $pinNum);
        goto END;
    }
    elsif($engineType eq 'cfam')
    {
        $enginePort = sprintf("E%02d", 0);
    }
    else
    {
        printWarn("Unsupported engine type $engineType");
        goto END;
    }
END:
    return ($enginePort, $isNonIou, $fspPos);
}

# Internal function that builds FSI path recursively leading up to the FSP.
sub _buildFsiPathRecursively
{
    my $targetIface = shift;
    my $target = shift;
    my $pathSegment = shift;
    my $visitedChipsArr = shift;
    my $numOfProcs = shift;

    my $chipType = $targetIface->getTargetType($target);
    my $fspAPath = "";
    my $fspBPath = "";

    if($chipType =~ 'chip-processor')
    {
        printDebug("Number of processors in path is now: $$numOfProcs");
        $$numOfProcs++;
        printDebug("Number of processors in path is now: $$numOfProcs");
    }

    printDebug("Start: buildFsiPathRecursively");

    if(($pathSegment ne "") and ($chipType eq 'chip-sp-fsp2'))
    {
        printDebug("Reached the FSP!");
        # Reached the FSP. Check if this is FSP A or FSP B
        my $fspPosition = _getFspPosition($targetIface, $target);

        if($fspPosition == 0)
        {
            $fspAPath = $pathSegment;
        }
        elsif($fspPosition == 1)
        {
            $fspBPath = $pathSegment;
        }
    }
    else
    {
        printDebug("Looking for FSI connections to $target");
        # Look for FSI connections where input target is the destination
        my $connectionType = "FSIM";

        if($chipType =~ 'chip-membuf')
        {
            $connectionType = "FSICM";
        }

        my $connections = $targetIface->findDestConnections($target,
            $connectionType, "");

        if($connections ne "")
        {
            foreach my $connection (@{$connections->{CONN}})
            {
                my $source = $connection->{SOURCE};
                my $destination = $connection->{DEST};
                my $sourceChip = getParentChip($targetIface, $source);
                my $sourceChipType = $targetIface->getTargetType($sourceChip);

                printDebug("Connection source: $source");
                printDebug("Connection destination: $destination");

                # Have we already visited this chip?
                if(isElementinList($sourceChip,$visitedChipsArr))
                {
                    printDebug("Chip $sourceChip already handled in this " .
                        "flow!");
                    next;
                }

                # Cannot have more than two processors in a chain
                if(($$numOfProcs > 1) and ($sourceChipType =~ 'chip-processor'))
                {
                    printDebug("Already have $$numOfProcs processors in the FSI chain");
                    next;
                }

                # Pull out FSI link and engine number from the connection
                my $fsiLink = getAttributeSafe($targetIface, $source,
                                               "FSI_LINK");
                my $fsiEngine = getAttributeSafe($targetIface, $source,
                                                 "FSI_ENGINE");
                my $thisPathSegment = "";

                # No need to add engine if the source is the FSP chip
                if($targetIface->getTargetType($sourceChip) eq 'chip-sp-fsp2')
                {
                    $fsiEngine = "";
                    $thisPathSegment = sprintf("L%02dC0", $fsiLink);
                }
                else
                {
                    $thisPathSegment = sprintf("E%02d:L%dC0", $fsiEngine,
                                               $fsiLink);
                }

                $thisPathSegment = $thisPathSegment . $pathSegment;

                unless(isElementinList($target,$visitedChipsArr))
                {
                    push (@{$visitedChipsArr}, $target);
                }
                unless(isElementinList($sourceChip,$visitedChipsArr))
                {
                    push (@{$visitedChipsArr}, $sourceChip);
                }

                my $oldNumOfProcs = $$numOfProcs;

                my ($retAPath, $retBPath) =
                        _buildFsiPathRecursively($targetIface,
                                                 $sourceChip,
                                                 $thisPathSegment,
                                                 $visitedChipsArr,
                                                 $numOfProcs);
               $$numOfProcs = $oldNumOfProcs;

               if($retAPath ne "")
               {
                   $fspAPath = $retAPath;
               }

               if($retBPath ne "")
               {
                   $fspBPath = $retBPath;
               }
            }
        }
    }
END:
    return ($fspAPath, $fspBPath);
}

sub isElementinList
{
   my $source = shift;
   my $list = shift;

   foreach my $element (@$list)
   {
       if($element eq $source)
       {
          return 1;
       }
   }
   return 0;
}

# Internal function, which given an FSP chip target, will get return it's
# position. Position 0 == FSP A, position 1 == FSP B.
sub _getFspPosition
{
    my $targetIface = shift;
    my $fspChip = shift;

    my $position = undef;
    my $fspConnector = getParentConnector($targetIface, $fspChip);

    $position = getAttributeSafe($targetIface, $fspConnector, "POSITION");

    return $position;
}

#** @brief This function validates the target path.
#
# @params $targetIface required The Targets interface
# @params $path required The Targets path which needs to be validated.
#
# @return Returns
#   true (1)  : When passed in target path is valid.
#   false (0) : When passed in target path is invalid.
#*
sub verifyFruPath
{
    my $targetIface = shift;
    my $path = shift;
    my $valid = 1;

    my $targetPtr = $targetIface->getTarget($path);
    if(not defined $targetPtr)
    {
        $valid = 0;
    }

    return $valid;
}

#** @brief This function Gets the gpio pin number.
#
# @params $targetIface required The Targets interface
# @params $gpioPath required The gpio path whose pin number is to be retrieved.
#
# @return The gpio pin number if supported else ''.
 #*
sub getGpioPinNumber
{
    my $targetIface = shift;
    my $gpioPath = shift;
    my $pinNum = '';
    my $parent = $targetIface->getTargetParent($gpioPath);
    my $engineParentType = $targetIface->getTargetType($parent);

    if ($engineParentType =~ 'unit-iomux_config-fsp2')
    {
        my ($ioNum) = $gpioPath =~ m/gpio_([0-9])$/g;
        my $dioStart = $targetIface->getAttribute($parent,
        "DIO_START");
        $pinNum = $dioStart + $ioNum;
        $pinNum = $pinNum % 32;
    }
    else
    {
        printErr("Unsupported parent Engine type [$engineParentType] ")
    }

    return $pinNum;
}

#** @brief This function gets the max number of nodes on the system.
#
# @params $targetIface required The Targets interface
#
# @return The max number of nodes suported by the system.
#*
sub getNumberOfNodes
{
    my $targetIface = shift;
    my $nodes = 0;
    foreach my $target (sort keys %{$targetIface->getAllTargets()})
    {
        if($targetIface->getAttribute($target, "CLASS") eq 'ENC')
        {
            $nodes++;
        }
    }

    if($nodes == 0)
    {
        printErr("No Enclosure Nodes found");
        exit(0);
    }

    return $nodes;
}

#** @brief This function checks if the system is multinode or not.
#
# @return true if system supports multinode else false.
#*
sub isMultiNodeSystem
{
    my $targetIface = shift;
    my $multiNodeSystem = 'false';

    if(getNumberOfNodes($targetIface)  gt '1')
    {
        $multiNodeSystem = 'true';
    }
    return $multiNodeSystem;
}

#** @brief This function checks if the target is within a control node or not.
#
# @params $targetIface required The Targets interface
# @params $target required The Target to check
#
# @return true if target is on control node in multinode or on
#         cec node in single node.
#*
sub isInControlNode
{
    my $targetIface = shift;
    my $target = shift;
    my $state = "";

    if(isMultiNodeSystem($targetIface) eq 'false')
    {
        $state = "true";
    }
    else
    {
        my $parentNode = getParentNode($targetIface, $target);
        my $targetType = getAttributeSafe($targetIface, $parentNode, "ENC_TYPE");
        if(lc$targetType eq "control")
        {
            $state = "true";
        }
        else
        {
            $state = "false";
        }
    }
    return $state;
}

1;
