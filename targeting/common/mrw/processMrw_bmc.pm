package processMrw_bmc;
 
 use strict;
 use XML::Simple;
 use XML::Parser;
 use Data::Dumper;
 use feature "state";
 use feature 'switch';
 use Targets;
 use List::MoreUtils qw(first_index);
 use Parsers_Common;
 use File::Basename;
 
 use parent 'Exporter';
 our @EXPORT_OK = qw(return_plugins);
 
 my $fsitmp=-1;
 my $multicecnode = -1;
 sub return_plugins
 {
    # we do not have any special processing, so empty method
 }
 
my %ocmb_device_path_method_registry = (
    "Rainier-2U-MRW.xml" => \&rainier_ocmb_device_paths,
    "Rainier-4U-MRW.xml" => \&rainier_ocmb_device_paths,
    "Everest-MRW.xml" => \&everest_ocmb_device_paths,
    "bonnell-mrw.xml" => \&default_ocmb_device_paths,
);
 
 
 my $device_path;
 my $location_code;
 
 sub loadBMC
 {
     my $targetObj = shift;
     buildBmcAffinity($targetObj);
 }
 
 
 sub buildBmcAffinity
 {
     print "Building bmc affinity...\n";
 
     my $node            = -1;
     my $sys_phys        = "";
     my $node_phys       = "";
     my $node_aff        = "";
     my $sys_pos         = 0;
     my $bmc             = -1;
     my $tpm             = -1;
     my $oscrefclk       = -1;
     my $mfrefclk        = -1;
     my $mfrefclkendpt   = -1;
     my $proc            = -1;
     my $proc_instance_per_node    = -1;
     my $osrefclk_instance_per_node    = -1;
 
     my $targetObj = shift;
     my $sysTarget;
 
     foreach my $target (sort keys %{ $targetObj->{data}->{TARGETS} })
     {
         my $type       = $targetObj->getType($target);
         my $pos        = $targetObj->{data}->{TARGETS}{$target}{TARGET}{position};
         my $planerRID = sprintf("0x%08X", 0x00000800 + $pos);
 
         if ($type eq "" || $type eq "NA")
         {
         }
         if ($type eq "SYS")
         {
             $sys_phys = $targetObj->getAttribute($target, "PHYS_PATH");
             $sys_phys = substr($sys_phys, 9);
             $sysTarget = $target;
         }
         elsif ($type eq "NODE")
         {
             if($pos > 0 )
             {
                 $multicecnode = 1;
                 $node = $pos - 1;
             }
             else
             {
                 $node++;
             }
             $node_phys = "physical:".$sys_phys."/node-$node";
             $node_aff  = "affinity:".$sys_phys."/node-$node";
             $targetObj->setAttribute($target, "RID",  $planerRID); 
             if($pos > 0)
             {
                 $targetObj->setAttribute($target, "ORDINAL_ID",    $pos - 1);
             }
             $proc_instance_per_node = -1;
             $osrefclk_instance_per_node = -1;
 
         }
         elsif ($type eq "PROC")
         {
             $proc++;
             #proc instance based on node
             $proc_instance_per_node++;
             $targetObj->setAttribute($target, "EC", "0x10");
             $targetObj->setAttribute($target, "CHIP_ID", "0x20D4");
 
             #Populate HW Topology Attribute
             #my $nodepos = $targetObj->getParentNodePos($target) ;
             my $nodepos = 0;
             my $parentnode = $target;
             while($targetObj->getAttribute($parentnode,"CLASS") ne "ENC")
             {
                 $parentnode = $targetObj->getTargetParent($parentnode);
             }
             if($parentnode ne "")
             {
               if(! $targetObj->isBadAttribute($parentnode,"POSITION"))
               {
                  $nodepos = $targetObj->getAttribute($parentnode,"POSITION");
               }
               else
               {
                 $nodepos = substr ($parentnode,-1);
               }
             }
             else
             {
                die "Cannot find parent node for $target\n";
             }

             my $modulepos = $targetObj->getAttribute($targetObj->getTargetParent($target),"POSITION");
             my $hwtopology = sprintf ("0x%04X", (($nodepos<<12) + ($proc<<8) + ($modulepos<<4)));
             $targetObj->setAttribute($target, "PROC_HW_TOPOLOGY", $hwtopology);
 
             my $device_paths = CreateProcModuleDevicePaths($proc);

             my %paths = %{$device_paths};

             foreach my $key (sort keys %paths) {
                 $targetObj->setAttribute($target, $key, $paths{$key});
             }
 
             #get and set the LOCATION_CODE
             $location_code = Parsers_Common::getLocationCode($targetObj, $target);
             $targetObj->setAttribute($target, "LOCATION_CODE", $location_code);
 
         }
         elsif ($type eq "BMC")
         {
             #get and set the LOCATION_CODE
             $location_code = Parsers_Common::getLocationCode($targetObj, $target);
             $targetObj->setAttribute($target, "LOCATION_CODE", $location_code);
 
         }
         elsif($type eq "TPM")
         {
             $tpm++;
 
             #get and set the LOCATION_CODE
             $location_code = 0;            #Reset the value
             $location_code = Parsers_Common::getLocationCode($targetObj, $target);
             $targetObj->setAttribute($target, "LOCATION_CODE", $location_code);
 
         }
         elsif ($type eq "OSCREFCLK")
         {
            $oscrefclk++;
            $osrefclk_instance_per_node++;
            # Hardcoding the sys instance as "0" since we will have only one system
            $targetObj->{targeting}{SYS}[0]{NODES}[$node]{OSCREFCLK}[$osrefclk_instance_per_node]{KEY}= $target;

            my $oscrefclk_phys = $node_phys . "/oscrefclk-$osrefclk_instance_per_node";
            $targetObj->setAttribute($target, "PHYS_PATH", $oscrefclk_phys);
            $targetObj->setAttribute($target, "AFFINITY_PATH", $oscrefclk_phys);

            # OSCREFCLK is Non-FAPI target
            $targetObj->setAttribute($target,"FAPI_NAME", "NA");

            # Add I2C_PORT, I2C_ADDRESS, and I2C_PARENT_PHYS_PATH attributes
            # based on the I2C destination connection of the retrieved target.
            # These attributes helps to add the retrieved target under
            # the respective connected (via I2C) destination target in the
            # device tree to perform the i2c read and write operation
            # on the OSCREFCLK target.
            # For example, bmc-0 -> i2c-0 -> oscrefclk-0.
            my $destConn = $targetObj->findDestConnections($target, "I2C", "");
            if($destConn ne "")
            {
                my @destConnList = @{$destConn->{CONN}};
                my $numConnections = scalar @destConnList;

                if ($numConnections != 1)
                {
                    die "Incorrect number of OSCREFCLK I2C bus connection. Expected 1 and Found $numConnections";
                }

                my $i2c_port = $targetObj->getAttribute($destConnList[0]{SOURCE}, "I2C_PORT");
                $targetObj->setAttribute($target, "I2C_PORT", $i2c_port);

                my $i2c_addr = $targetObj->getAttribute($destConnList[0]{DEST}, "I2C_ADDRESS");
                $targetObj->setAttribute($target, "I2C_ADDRESS", $i2c_addr);

                # Found the connected BMC card from the source i2c path
                my $src_parent = $destConnList[0]{SOURCE_PARENT};
                while($targetObj->getType($src_parent) ne "BMC")
                {
                    $src_parent = $targetObj->getTargetParent($src_parent);
                }
                if ($src_parent eq "")
                {
                    die "Could not find the connected BMC from the source i2c bus connection: $destConnList[0]{SOURCE}\n";
                }
                my $src_parent_phys_path = $targetObj->getAttribute($src_parent, "PHYS_PATH");
                $targetObj->setAttribute($target, "I2C_PARENT_PHYS_PATH", $src_parent_phys_path);
            }
        }

         elsif($type eq "OCMB_CHIP")
         {
            my $location_code = Parsers_Common::getLocationCode($targetObj, $target);
            my $affinityPathOCMB = $targetObj->getAttribute($target,
                         "AFFINITY_PATH");
            my $fapi_pos = $targetObj->getAttribute($target,
                         "FAPI_POS");

            my $server_file = $targetObj->{serverwiz_file};
            my ($filename, $dir) = fileparse($server_file);
            my $device_paths = CreateOCMBDevicePaths($filename, $fapi_pos);

            my %paths = %{$device_paths};

            foreach my $key (sort keys %paths) {
                $targetObj->setAttribute($target, $key, $paths{$key});
            }

            $targetObj->setAttribute($target, "LOCATION_CODE", $location_code);
         }
         elsif ($type eq "DIMM")
        {
            # The DIMM target that needs to be picked up has a new type
            # as per the new HB changes to support DDR5. They will be
            # unit-ddr* type and not lcard-dimm*. While parsing we get all
            # of them, so skip the unit-ddr*, get the location code from
            # the target with lcard type and set the location code for its
            # child targets which are again unit-ddr*
            my $target_type = $targetObj->getTargetType($target);
            if (($target_type eq "unit-ddr") ||
                ($target_type eq "unit-ddr4-jedec") ||
                ($target_type eq "unit-ddr5-jedec"))
               {
                   next;
               }

            my $location_code = Parsers_Common::getLocationCode($targetObj, $target);
            # needed for Bonnell which has older DIMM type
            $targetObj->setAttribute($target, "LOCATION_CODE", $location_code);

            foreach my $child (@{ $targetObj->getTargetChildren($target) })
            {
                my $child_target_type = $targetObj->getTargetType($child);
                if (($child_target_type eq "unit-ddr") ||
                    ($child_target_type eq "unit-ddr4-jedec") ||
                    ($child_target_type eq "unit-ddr5-jedec"))
                {
                     $targetObj->setAttribute($child, "LOCATION_CODE", $location_code);
                }
             }
        }
     }
 
 }
 
 sub everest_ocmb_device_paths {
    my ($proc_id, $ocmb_index) = @_;
    my %ocmb_port = (
        0 => {
            0 => 100, 1 => 101, 2 => 110, 3 => 111,
            4 => 112, 5 => 113, 6 => 114, 7 => 115,
        },
        1 => {
            0 => 202, 1 => 203, 2 => 210, 3 => 211,
            4 => 214, 5 => 215, 6 => 216, 7 => 217,
        },
        2 => {
            0 => 300, 1 => 301, 2 => 310, 3 => 311,
            4 => 312, 5 => 313, 6 => 314, 7 => 315,
        },
        3 => {
            0 => 402, 1 => 403, 2 => 410, 3 => 411,
            4 => 414, 5 => 415, 6 => 416, 7 => 417,
        },
        4 => {
            0 => 500, 1 => 501, 2 => 510, 3 => 511,
            4 => 512, 5 => 513, 6 => 514, 7 => 515,
        },
        5 => {
            0 => 603, 1 => 602, 2 => 610, 3 => 611,
            4 => 614, 5 => 615, 6 => 616, 7 => 617,
        },
        6 => {
            0 => 700, 1 => 701, 2 => 710, 3 => 711,
            4 => 712, 5 => 713, 6 => 714, 7 => 715,
        },
        7 => {
            0 => 802, 1 => 803, 2 => 810, 3 => 811,
            4 => 814, 5 => 815, 6 => 816, 7 => 817,
        },
    );

    return exists $ocmb_port{$proc_id} && exists $ocmb_port{$proc_id}{$ocmb_index}
        ? $ocmb_port{$proc_id}{$ocmb_index}
        : undef;  # or you can die with an error
}

sub default_ocmb_device_paths {
    my ($proc_id, $ocmb_index) = @_;

    return $proc_id;
}

sub rainier_ocmb_device_paths {
    my ($proc_id, $ocmb_index) = @_;
    my %ocmb_port = (
        0 => {
            0 => 111, 1 => 110, 2 => 112, 3 => 113,
            4 => 115, 5 => 100, 6 => 114, 7 => 101,
        },
        1 => {
            0 => 202, 1 => 210, 2 => 214, 3 => 217,
            4 => 215, 5 => 211, 6 => 203, 7 => 216,
        },
        2 => {
            0 => 311, 1 => 310, 2 => 312, 3 => 313,
            4 => 315, 5 => 300, 6 => 314, 7 => 301,
        },
        3 => {
            0 => 402, 1 => 410, 2 => 414, 3 => 417,
            4 => 415, 5 => 411, 6 => 403, 7 => 416,
        },
    );

    return exists $ocmb_port{$proc_id} && exists $ocmb_port{$proc_id}{$ocmb_index}
        ? $ocmb_port{$proc_id}{$ocmb_index}
        : undef;  # or you can die with an error
}

sub CreateProcModuleDevicePaths {
    my ($proc_id) = @_;
    my $devIndex = $proc_id + 1;
    my @fsi_port = (
        0x000000, #proc 0 does not use the port in kernel mode
        0x100000,
        0x180000,
        0x200000,
        0x280000,
        0x300000,
        0x380000,
        0x400000,
    );
    my $fsi_prefix = ($proc_id == 0) ? "/fsi0" : "/fsi1";
    my $fsi_address = sprintf("%02x", $proc_id);

    #represent port as a 6 digit hex value
    my $hex_fsi_port = sprintf("0x%06X", $fsi_port[$proc_id]);

    my %device_paths = (
        SBEFIFO_DEVICE_PATH  => "/dev/sbefifo$devIndex",
        DIRECT_ACCESS_DEVICE_PATH   => "/dev/scom$devIndex",
        FSI_DEVICE_PATH      => "$fsi_prefix/slave\@$fsi_address:00/raw",
        FSI_PORT             => "$hex_fsi_port",
        HW_ACCESS_METHOD => "SBEFIFO",
    );
    return \%device_paths;
}

sub CreateOCMBDevicePaths {
    my ($inputXMLFileName, $fapi_pos) = @_;
    # fapi pos has the proc index as the first byte, so extract it
    # Convert to hex string (uppercase, no '0x' prefix)
    my $hex = sprintf("%02X", $fapi_pos);  # e.g., 26 → "1A"
    # Extract the most significant hex digit to get the proc index
    my $proc_id = substr($hex, 0, 1);  # "1"
    my $ocmb_port_value;
    # on the OCMB index, the numbers go from 0-7 for proc0, and continue 8-15 for proc 1
    # so use the mod 8 value to get the relative index 
    my $index = hex($fapi_pos);
    #remove the first nibble
    $index = $index & 0x0f;
    $index = $index % 8;

    if ($ocmb_device_path_method_registry{$inputXMLFileName})
    {
        $ocmb_port_value = $ocmb_device_path_method_registry{$inputXMLFileName}->($proc_id, $index);
    }
    else
    {
        $ocmb_port_value = hex($proc_id) + 1;
    }
    
    my %device_paths = (
        SBEFIFO_DEVICE_PATH  => "/dev/sbefifo$ocmb_port_value",
        DIRECT_ACCESS_DEVICE_PATH   => "/dev/scom$ocmb_port_value",
        FSI_DEVICE_PATH      => "/i2cr$ocmb_port_value/slave@00:00/raw",
        HW_ACCESS_METHOD     => "SBEFIFO",
    );

    return \%device_paths;
}

 
 return 1;
 

