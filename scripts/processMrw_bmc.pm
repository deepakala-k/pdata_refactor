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
     %::hwsvmrw_plugins = (
         bmc_proc=>\&process_bmc_proc,
     );
 }
 
 #Unit type per proc for single node
 my %maxInstance = (
     "SYSREFCLKENDPT"=> 1,
     "PCICLKENDPT" => 2,
     "LPCREFCLKENDPT" => 1,
     "NV"            => 6,
 );
 
 #Unit type per proc for multinode
 my %maxInstanceMulti = (
 "SYSREFCLKENDPT"=> 2,
 "PCICLKENDPT" => 2,
 "LPCREFCLKENDPT" => 1,
 "NV"            => 6,
 );
 
 #Number of individual Unit in all proc, Single Node
 my %procTotalInstance = (
     "FSI"            => 1,
     "PSI"            => 2,
     "SYSREFCLKENDPT" => 8,
     "PCICLKENDPT"  => 8,
         );

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
     my $proc_aff        = "";
     my $sys_pos         = 0;
     my $bmc             = -1;
     my $tpm             = -1;
     my $oscrefclk       = -1;
     my $oscrefclkendpt  = -1;
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
             $targetObj->setAttribute($target, "RID",  $planerRID); #TODO: is RID needed?
             if($pos > 0)
             {
                 $targetObj->setAttribute($target, "ORDINAL_ID",    $pos - 1);
             }
             $proc_instance_per_node = -1;
             $osrefclk_instance_per_node = -1;
 
             #Add Location Code and RID for Membuf & DIMMs
             processMembufDimms($targetObj, $target, $node);
         }
         #TODO: Removed control node, get confirmation
         elsif ($type eq "PROC")
         {
             $proc++;
             #proc instance based on node
             $proc_instance_per_node++;
             $proc_aff = "affinity:".$sys_phys."/node-$node"."/proc-$proc_instance_per_node";
             print("deepa >>>>>>>>>>>>>>>>>>>>>> affinity path $proc_aff\n");
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
 
             #Collect SCOM device_path
             $targetObj->setAttribute($target, "SCOM_DEVICE_PATH", $device_path);
 
             #Collect SCAN device_path //TODO - not needed
             #Collect MBOX device_path //TODO - not needed
 
             #Collect SBEFIFO device_path
             $targetObj->setAttribute($target, "SBEFIFO_DEVICE_PATH", $device_path);
 
             #get and set the LOCATION_CODE
             $location_code = Parsers_Common::getLocationCode($targetObj, $target);
             $targetObj->setAttribute($target, "LOCATION_CODE", $location_code);
 
             #Collect SEEPROM device_path //TODO - not needed
             #set the Voltage Attributes
             #setVoltageAttributes($targetObj, $target); //TODO - not needed
         }
         elsif ($type eq "BMC")
         {
             #get and set the LOCATION_CODE
             $location_code = Parsers_Common::getLocationCode($targetObj, $target);
             $targetObj->setAttribute($target, "LOCATION_CODE", $location_code);
 
         }
         #TODO APSS - do we need this?
         elsif($type eq "TPM")
         {
             $tpm++;
 
             #get and set the LOCATION_CODE
             $location_code = 0;            #Reset the value
             $location_code = Parsers_Common::getLocationCode($targetObj, $target);
             $targetObj->setAttribute($target, "LOCATION_CODE", $location_code);
 
         }
         #TODO: I2C_PARENT_PHYS_PATH was used in BMC earlier. Need to find if it is needed?
         elsif ($type eq "OSCREFCLK")
         {
             $oscrefclk++;
             $osrefclk_instance_per_node++;
             $targetObj->{targeting}{SYS}[0]{NODES}[$node]{OSCREFCLK}[$osrefclk_instance_per_node]{KEY}= $target;
             my $oscrefclk_phys = $node_phys . "/oscrefclk-$osrefclk_instance_per_node";
             my $oscrefclk_aff  = $node_aff  . "/oscrefclk-$osrefclk_instance_per_node";
             $targetObj->setHuid($target, $sys_pos, $node);
             $targetObj->setAttribute($target, "PHYS_PATH",     $oscrefclk_phys);
             $targetObj->setAttribute($target, "AFFINITY_PATH", $oscrefclk_aff );
             $targetObj->setAttribute($target, "ORDINAL_ID",    $oscrefclk);
             $targetObj->setAttribute($target, "CHIP_UNIT",     $pos);
 
             #get and set the LOCATION_CODE
             $location_code = Parsers_Common::getLocationCode($targetObj, $target);
             $targetObj->setAttribute($target, "LOCATION_CODE", $location_code);
 
             #TODO is it needed? 
             iterateOverClkEndPnts($targetObj, $target, $sys_pos, $node, $oscrefclk);
         }

         elsif($type eq "OCMB_CHIP")
         {
            my $location_code = Parsers_Common::getLocationCode($targetObj, $target);
            my $affinityPathOCMB = $targetObj->getAttribute($target,
                         "AFFINITY_PATH");
            my $fapi_pos = $targetObj->getAttribute($target,
                         "FAPI_POS");
            print("deepa OCMB_CHIP >>>>>>>>>>>>>>>>>>>>>> affinity path $affinityPathOCMB\n");
            print("deepa OCMB_CHIP >>>>>>>>>>>>>>>>>>>>>> FAPI_POS $fapi_pos\n");

            my $server_file = $targetObj->{serverwiz_file};
            my ($filename, $dir) = fileparse($server_file);
            my $device_paths = CreateOCMBDevicePaths($filename, $fapi_pos);

            my %paths = %{$device_paths};

            foreach my $key (sort keys %paths) {
                print "caller $key => $paths{$key}\n";
                $targetObj->setAttribute($target, $key, $paths{$key});
            }

            $targetObj->setAttribute($target, "LOCATION_CODE", $location_code);
         }
     }
 
 }
 
 #####################################################################
 #Process the Clock Endpoints
 #####################################################################
 
 sub iterateOverClkEndPnts
 {
     my $targetObj     = shift;
     my $target   = shift;
     my $sys      = shift;
     my $node     = shift;
     my $clkTgt      = shift;
     my $clkendcnt   = -1;
 
     #hack to get the indexing right for clock endpoint targets
     #which was necessitated due to the swapping around of proc targets
     if($target =~ m/woodstar-connector-10/i)
     {
         $targetObj->{huid_idx}->{"PCICLKENDPT"} = 8;
         $targetObj->{huid_idx}->{"SYSREFCLKENDPT"} = 8;
     }
     if($target =~ m/woodstar-connector-11/i)
     {
         $targetObj->{huid_idx}->{"PCICLKENDPT"} = 0xC;
         $targetObj->{huid_idx}->{"SYSREFCLKENDPT"} = 0xC;
     }
 
     my $target_children  = $targetObj->getTargetChildren($target);
 
     if ($target_children eq "")
     {
         return "";
     }
     else
     {
         foreach my $child (@{ $targetObj->getTargetChildren($target) })
         {
             my $unit_ptr        = $targetObj->getTarget($child);
             my $unit_type       = $targetObj->getType($child);
             my $bus_type        = $targetObj->getAttribute($child, "BUS_TYPE");
             my $child_type        = $targetObj->getAttribute($child, "TYPE");
 
             my $unit_pos        = $targetObj->getAttribute($child, "CHIP_UNIT");
 
             if ($bus_type ne "CLK")
             {
                 next;
             }
 
             $clkendcnt++;
             if($child_type eq "NA")
             {
                 next;
             }
             else
             {
                 my $peer_target;
                 my $clkendpts = $targetObj->findConnections($target, "CLK", "");
                 if ($clkendpts eq "")
                 {
                     next;
                 }
                 else
                 {
                     my $CLK = $targetObj->getType($targetObj->getTargetParent($child));
                     push(@{$targetObj->{targeting}
                      ->{SYS}[0]{NODES}[$node]{$CLK}[$clkTgt]{$unit_type}},
                                           {KEY=> $child});
 
                     foreach my $endpts (@{$clkendpts->{CONN}})
                     {
                         my $clk_source = $endpts->{SOURCE};
                         if ($child eq $clk_source)
                         {
                             $peer_target = $endpts->{DEST};
                         }
                     }
                 }
 
                 my $parent_affinity = $targetObj->getAttribute(
                               $targetObj->getTargetParent($child),"AFFINITY_PATH");
                 my $parent_physical = $targetObj->getAttribute(
                               $targetObj->getTargetParent($child),"PHYS_PATH");
 
                 my $affinity_path   = $parent_affinity . "/" . lc $unit_type ."-". $clkendcnt;
                 my $physical_path   = $parent_physical . "/" . lc $unit_type ."-". $clkendcnt;
 
                 $targetObj->setHuid($child, $sys, $node);
                 $targetObj->setAttribute($child, "PHYS_PATH",       $physical_path);
                 $targetObj->setAttribute($child, "AFFINITY_PATH",   $affinity_path);
                 $targetObj->setAttribute($child, "ORDINAL_ID",      $clkendcnt);
                 $targetObj->setMruid($child, $node);
 
                 $targetObj->setAttribute($child, "PEER_TARGET",
                                     $targetObj->getAttribute($peer_target, "PHYS_PATH") );
                 $targetObj->setAttribute($peer_target, "PEER_TARGET",
                                     $targetObj->getAttribute($child, "PHYS_PATH") );
 
                 $targetObj->setAttribute($child, "PEER_HUID",
                                     $targetObj->getAttribute($peer_target, "HUID") );
                 $targetObj->setAttribute($peer_target, "PEER_HUID",
                                     $targetObj->getAttribute($child, "HUID") );
             }
         }
     }
 }
 
 #####################################################################
 #Process OCMB and Dimms
 #####################################################################
 
 my @sorted_membuf_LC;
 my @sorted_ocmb_LC;
 my @membuf_LC ;
 my $prev_membuf_LC;
 my @dimm_LC ;
 my @ocmb_LC ;
 my @sorted_dimmLC;
 
 sub processMembufDimms
 {
     my $targetObj     = shift;
     my $target        = shift;
     my $sys           = 0;
     my $node          = shift;
 
 
     my $nodePos        = $targetObj->{data}->{TARGETS}{$target}{TARGET}{position};
 
     foreach my $proc_child ($targetObj->getAllTargetChildren($target))
     {
         my $tgt_type       = $targetObj->getType($proc_child);
 
         if($tgt_type eq "MC")
         {
             my $mc =  $proc_child;
             foreach my $mi (@{ $targetObj->getTargetChildren($mc) })
             {
                 foreach my $mcc (@{ $targetObj->getTargetChildren($mi) })
                 {
                 	foreach my $omic (@{ $targetObj->getTargetChildren($mcc) })
                 	{
                         foreach my $omi (@{ $targetObj->getTargetChildren($omic) })
                         {
                             my $omi_conn = $targetObj->{data}->{TARGETS}{$omi}{CONNECTION}{DEST}[0];
                             if (defined($omi_conn))
                             {
                                # TODO Fix for Bonnell
                                 my $ocmb = $targetObj->{data}->{TARGETS}{$omi_conn}{PARENT};
                                 push (@ocmb_LC, $targetObj->getAttribute($targetObj->getTargetParent($targetObj->getTargetParent($ocmb) ), "LOCATION_CODE") );
                                 push (@dimm_LC, $targetObj->getAttribute($targetObj->getTargetParent($targetObj->getTargetParent($ocmb) ), "LOCATION_CODE") );
                             }# OMI connection
                         }# OMI
                     }# OMIC
                 }# MCCs
             }# MIs
         }# MCs
     }#proc children
     #collect All DIMMs per connector in sorted form
     push (@sorted_dimmLC, sort @dimm_LC);
     push (@sorted_ocmb_LC , sort @ocmb_LC);
 
     # Go through each DIMM and membuf and set LOCATION CODE
     foreach my $proc_child ($targetObj->getAllTargetChildren($target))
     {
         my $tgt_type       = $targetObj->getType($proc_child);
 
         if($tgt_type eq "MC")
         {
             my $mc =  $proc_child;
             foreach my $mi (@{ $targetObj->getTargetChildren($mc) })
             {
                 foreach my $mcc (@{ $targetObj->getTargetChildren($mi) })
                 {
                     foreach my $omic (@{ $targetObj->getTargetChildren($mcc) })
                     {
                         foreach my $omi (@{ $targetObj->getTargetChildren($omic) })
                         {
                             my $omi_conn = $targetObj->{data}->{TARGETS}{$omi}{CONNECTION}{DEST}[0];
                             if (defined($omi_conn))
                             {
                                 # found ocmb connected
                                 my $ocmb = $targetObj->{data}->{TARGETS}{$omi_conn}{PARENT};
                                 my $current_ocmb_LC = shift @sorted_ocmb_LC;
 
                                 $prev_membuf_LC = $current_ocmb_LC;
 
                                 $current_ocmb_LC = "Ufcs-P0-".$current_ocmb_LC;
 
                                 $targetObj->setAttribute($ocmb, "CHIP_ID", "0x60E9");
                                 $targetObj->setAttribute($ocmb, "EC", "0x10");
 
                                 my $dimmRelativeLC = $targetObj->getAttribute($targetObj->getTargetParent($targetObj->getTargetParent($ocmb)),"LOCATION_CODE");
                                 my $dimmLC = "Ufcs-P0-".$dimmRelativeLC;
                                 $targetObj->setAttribute($ocmb, "LOCATION_CODE", $dimmLC);
 
                                 my $current_dimm_LC = shift @sorted_dimmLC;
                                 $current_dimm_LC = $current_ocmb_LC . "-" . $current_dimm_LC;
 
                                 # populate DIMM location code
                                 my $dimm = $targetObj->getTargetParent($ocmb);
                                 foreach my $child (@{ $targetObj->getTargetChildren($dimm) })
                                 {
                                     my $childTargetType = $targetObj->getTargetType($child);
                                     if (($childTargetType eq "unit-ddr") ||
                                         ($childTargetType eq "unit-ddr4-jedec") ||
                                         ($childTargetType eq "unit-ddr5-jedec"))
                                     {
                                         #print "Adding $child of type $childTargetType\n";
                                         $targetObj->setAttribute($child, "LOCATION_CODE", $dimmLC);
                                     }
                                 }
 
                             }# OMI connection
                         }# OMIs
                     }# OMICs
                 }# MCCs
             }# MIs
         }# MCs
     }
 }
 

 my $fsiCnt = -1;
 sub process_bmc_proc
 {
     my $multinode = -1 ;
     my $node_ordinal_id = -1;
     my $max_psi_per_node = 4;
     my $psi_ordinal_id_incr = 2;
     my ($targetObj, $target)    = @_;
 
     my ($slash , $sys, $node, $rambleoN, $proc) = split('/', $target);
 
     $sys = 0;
     my $temptarget = $target;
     my $temptype = $targetObj->getTargetType($target);
     my $parent;
     while($temptype ne "NODE")
     {
       $parent = $targetObj->getTargetParent($temptarget);
       $temptype = $targetObj->getType($parent);
       $temptarget = $parent;
     }
     $node_ordinal_id = $targetObj->getAttribute($parent, "ORDINAL_ID");
     if(! $targetObj->isBadAttribute($temptarget,"POSITION"))
     {
        $node = $targetObj->getAttribute($temptarget,"POSITION");
     }
     else
     {
        $node = substr ($temptarget,-1);
     }
     if(! $targetObj->isBadAttribute($target,"POSITION"))
     {
       $proc = $targetObj->getAttribute($target,"POSITION");
     }
     else
     {
       if(! $targetObj->isBadAttribute($target,"CHIP_UNIT"))
       {
         $proc = $targetObj->getAttribute($target,"CHIP_UNIT");
       }
       else
       {
         die "\nNeither POSITION nor CHIP_UNIT available for $target\n";
       }
     }
 
     if($node > 0)
     {
         $multinode = 1;
         $node=$node-1;
     }
     else
     {
         $multinode = 0;
     }
 
     my $target_children  = $targetObj->getTargetChildren($target);
 
     if ($target_children eq "")
     {
         return "";
     }
     else
     {
         foreach my $child (@{ $targetObj->getTargetChildren($target) })
         {
             my $unit_ptr        = $targetObj->getTarget($child);
             my $unit_type       = $targetObj->getType($child);
 
             if ($unit_type eq "FSI" )
             {
                 my $unit_type_id = $targetObj->getTargetType($child);
 
                 if ($unit_type_id eq "unit-fsi-slave" )
                 {
 
                     my $src_target = ($targetObj->getTarget($child))->{CONNECTION}->{SOURCE}[0];
                     my $src_target_type = $targetObj->getTargetType($src_target);
                     if($src_target_type eq 'unit-fsi-master')
                     {
                         $fsiCnt++;
                         push(@{$targetObj->{targeting}
                             ->{SYS}[0]{NODES}[$node]{PROCS}[$proc]{$unit_type}},
                         { 'KEY' => $child });
                     }
                 }
             }
             elsif ($unit_type eq "SYSREFCLKENDPT" || $unit_type eq "PCICLKENDPT" || $unit_type eq "LPCREFCLKENDPT")
             {
                  push(@{$targetObj->{targeting}
                       ->{SYS}[0]{NODES}[$node]{PROCS}[$proc]{$unit_type}},
                       { 'KEY' => $child });
 
             }
 
             # DUmp only for FSI AND PSI AND clock end points
             if ($unit_type eq "PSI"  || $unit_type eq "FSI" ||
                 $unit_type eq "SYSREFCLKENDPT" || $unit_type eq "PCICLKENDPT" || $unit_type eq "LPCREFCLKENDPT")
             {
             my $pos             = $targetObj->getAttribute($child, "CHIP_UNIT");
             my $unit_pos        = $pos;
             my $ordinal_id        = $pos;
 
             my $parent_affinity = $targetObj->getAttribute(
                                   $targetObj->getTargetParent($child),"AFFINITY_PATH");
             my $parent_physical = $targetObj->getAttribute(
                                   $targetObj->getTargetParent($child),"PHYS_PATH");
 
             my $affinity_path   = $parent_affinity . "/" . lc $unit_type ."-". $unit_pos;
             my $physical_path   = $parent_physical . "/" . lc $unit_type ."-". $unit_pos;
             my $fapi_name       = $targetObj->getFapiName($unit_type, $node, $proc, $pos);
 
             #unique offset per system
             my $offset = -1;
             if($multinode == 1)
             {
 
                 $offset = ($proc * $maxInstanceMulti{$unit_type}) + $pos;
 
             }
             else
             {
                 $offset = ($proc * $maxInstance{$unit_type}) + $pos;
             }
 
             if ($unit_type eq "PSI")
             {
                 # See iterateOverBmcTargets for a note about PSI links'
                 # ordinal id computation. The algorithm used here is
                 # uses the node ordinal id as the base, and to that is
                 # added the processor ordinal id factored by the increment(2).
                 # The +1 is because the first processor side link has the ordinal
                 # id of 1.
                 $ordinal_id = ($node_ordinal_id * $max_psi_per_node) +
                               (($proc * $psi_ordinal_id_incr) + 1);
             }
 
             $targetObj->{huid_idx}->{$unit_type} = $offset;
             $targetObj->setHuid($child, $sys, $node);
             $targetObj->setAttribute($child, "FAPI_NAME",       $fapi_name);
             $targetObj->setAttribute($child, "PHYS_PATH",       $physical_path);
             $targetObj->setAttribute($child, "AFFINITY_PATH",   $affinity_path);
             $targetObj->setAttribute($child, "ORDINAL_ID",      $ordinal_id);
             $targetObj->setAttribute($child, "FAPI_POS",        $offset);
             $targetObj->setAttribute($child, "REL_POS",         $pos);
 
             process_bmc_proc($targetObj, $child);
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
        sbefifo_device_path  => "/dev/sbefifo$devIndex",
        kernel_device_path   => "/dev/scom$devIndex",
        fsi_device_path      => "$fsi_prefix/slave\@$fsi_address:00/raw:$hex_fsi_port",
    );
    return \%device_paths;
}

sub CreateOCMBDevicePaths {
    my ($inputXMLFileName, $fapi_pos) = @_;
    print ("deepa CreateOCMBDevicePaths $inputXMLFileName\n");
    print ("deepa CreateOCMBDevicePaths fapi_pos :: $fapi_pos\n");
    # fapi pos has the proc index as the first byte, so extract it
    # Convert to hex string (uppercase, no '0x' prefix)
    my $hex = sprintf("%02X", $fapi_pos);  # e.g., 26 → "1A"
    print ("deepa CreateOCMBDevicePaths hex:: $hex\n");
    # Extract the most significant hex digit to get the proc index
    my $proc_id = substr($hex, 0, 1);  # "1"
    my $ocmb_port_value;
    # on the OCMB index, the numbers go from 0-7 for proc0, and continue 8-15 for proc 1
    # so use the mod 8 value to get the relative index 
    my $index = hex($fapi_pos);
    #remove the first nibble
    $index = $index & 0x0f;
    $index = $index % 8;

    $ocmb_port_value = $ocmb_device_path_method_registry{$inputXMLFileName}->($proc_id, $index);

    my %device_paths = (
        sbefifo_device_path  => "/dev/sbefifo$ocmb_port_value",
        kernel_device_path   => "/dev/scom$ocmb_port_value",
        fsi_device_path      => "/i2cr$ocmb_port_value/slave@00:00/raw",
    );

    foreach my $key (sort keys %device_paths) {
        print "$key => $device_paths{$key}\n";
    }
    return \%device_paths;
}

 
 return 1;
 

