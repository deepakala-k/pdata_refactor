sub get_everest_ocmb_port_value {
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


sub get_rainier_ocmb_port_value {
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
    my ($inXMLFile, $fapi_pos, $index) = @_;
    # fapi pos has the proc index as the first byte, so extract it
    # Convert to hex string (uppercase, no '0x' prefix)
    my $hex = sprintf("%02X", $fapi_pos);  # e.g., 26 → "1A"
    # Extract the most significant hex digit to get the proc index
    my $proc_id = substr($hex, 0, 1);  # "1"
    my $ocmb_port_value;
    # on the OCMB index, the numbers go from 0-7 for proc0, and continue 8-15 for proc 1
    # so use the mod 8 value to get the relative index 
    $index = $index % 8;
    if ($inXMLFile =~ /rain/i) {
        $ocmb_port_value = get_rainier_ocmb_port_value($proc_id, $index);
    }
    else
    {
        $ocmb_port_value = get_everest_ocmb_port_value($proc_id, $index);
    }

    my %device_paths = (
        sbefifo_device_path  => "/dev/sbefifo$ocmb_port_value",
        kernel_device_path   => "/dev/scom$ocmb_port_value",
        fsi_device_path      => "/i2cr$ocmb_port_value/slave@00:00/raw",
    );

    return \%device_paths;
}

1;  # <- Required true value for require()
