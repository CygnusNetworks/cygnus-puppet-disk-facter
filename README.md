Puppet Disk Facts Plugin
========================

This is a Puppet facter plugin to help to determine block devices connected to common RAID controllers and Linux software RAID arrays. The plugin will generate facts for detected RAID levels and disks. Disks connected to standard SATA/ATA (onboard controllers) are also included.
The plugin will generate a fact for the detected RAID controller and driver, try to determine the used RAID level and also generates a list of disks connected to the RAID controllers including information about vendor, disk model and serial numbers as puppet facts. The provided data might be used to inventory the provided information for documentation or other use.

The plugin relies on the vendor specific tools for RAID controllers to be installed, when using a hardware RAID controller. Currently the following hardware RAID controllers are supported:

* 3Ware (now AMCC/Avago), including 7xxx, 8xxx, 9xxx and SAS controllers
* Adaptec AAC Raid
* LSI SPI and SAS controllers
* MegaRAID (now Avago)

In addition the following software RAID and standard disks are supported:

* Linux Software RAID
* ATA/SATA disks (using ahci, ata_piix, sata_via drivers)

For support for the RAID controllers you will need to install the vendor specific tools. You need to install the raid utilities yourself. To automate things you might consider using jhoblitt Puppet modules. See:

* [jhoblitt/tw_3dm2](https://forge.puppetlabs.com/jhoblitt/tw_3dm2)
* [jhoblitt/megaraid_sm](https://forge.puppetlabs.com/jhoblitt/megaraid_sm)
* [jhoblitt/mdadm](https://forge.puppetlabs.com/jhoblitt/mdadm)

You can decide which tool you need to install by checking the variables `block_devices` and `block_driver_DEV` variables.

# Example facter output

You will get something similar to the following output, when you are using this plugin with a hardware RAID controller:

```
facter -p|egrep -e "(^disk_|^block_)"
block_devices => sda
block_disks_sda => sda_0,sda_1,sda_2,sda_3,sda_4,sda_5,sda_6,sda_7
block_driver_sda => 3w-sas
block_is_raid_sda => true
block_raidtype_sda => 6
block_vendor_sda => LSI
disk_model_sda_0 => MK2001TRKB
disk_model_sda_1 => MK2001TRKB
disk_model_sda_2 => MK2001TRKB
disk_model_sda_3 => MK2001TRKB
disk_model_sda_4 => MK2001TRKB
disk_model_sda_5 => MK2001TRKB
disk_model_sda_6 => MK2001TRKB
disk_model_sda_7 => MK2001TRKB
disk_serial_sda_0 => Y1S0********
disk_serial_sda_1 => Y1S0********
disk_serial_sda_2 => Y1S0********
disk_serial_sda_3 => Y1S0********
disk_serial_sda_4 => Y1P0********
disk_serial_sda_5 => Y1S0********
disk_serial_sda_6 => Y1C0********
disk_serial_sda_7 => Y1S0********
disk_vendor_sda_0 => TOSHIBA
disk_vendor_sda_1 => TOSHIBA
disk_vendor_sda_2 => TOSHIBA
disk_vendor_sda_3 => TOSHIBA
disk_vendor_sda_4 => TOSHIBA
disk_vendor_sda_5 => TOSHIBA
disk_vendor_sda_6 => TOSHIBA
disk_vendor_sda_7 => TOSHIBA
```

For a software RAID output should look like this:

```
facter -p|egrep "(^block_|^disk_)"
block_devices => sda,sdb,md0,md1
block_disks_md0 => sda5,sdb5
block_disks_md1 => sda6,sdb6
block_disks_sda => sda
block_disks_sdb => sdb
block_driver_md0 => swraid
block_driver_md1 => swraid
block_driver_sda => ahci
block_driver_sdb => ahci
block_is_raid_md0 => true
block_is_raid_md1 => true
block_is_raid_sda => false
block_is_raid_sdb => false
block_raidtype_md0 => 1
block_raidtype_md1 => 1
block_vendor_md0 => Linux
block_vendor_md1 => Linux
block_vendor_sda => ATA
block_vendor_sdb => ATA
disk_model_sda => SSDSC2BB120G4
disk_model_sdb => SSDSC2BB120G4
disk_serial_sda => BTWL3396**********
disk_serial_sdb => BTWL3396**********
disk_vendor_sda => INTEL
disk_vendor_sdb => INTEL
```

# Installation

```
puppet module install cygnus-disk_facter
```

# Usage

After installing the disk_facter, you will get the following variables:

 * `block_devices`: A comma separated list of found block device names with the
   leading `/dev/` removed
 * For each element in `block_devices` there are further variables.
   + `block_driver_$DEV`: The Linux kernel driver name used for this device.
   + `block_is_raid_$DEV`: true or false depending on whether the block device
     is a RAID device. If tools needed for identification are
     missing, it may wrongly contain the value false.
   + `block_disks_$DEV`: A comma separated list of identifiers enumerating the
     actual disks backing this device. For regular disks this list has just
     one element. For raid devices this list driver specific identifiers, if
     the required detection utilities are installed.
   + `block_vendor_$DEV`: Contains some kind of vendor representation.
 * For each element of `block_disks_$DEV` there are further variables.
   + `disk_vendor_$DISK`: A upper case string representing the vendor
     of the disk as read out from the device.
   + `disk_model_$DISK`: A vendor specific representation of the model of the
     disk.
   + `disk_serial_$DISK`: The serial number of the disk as read from the device.
 * `twcli_path` or `arcconf_path`: The name of the 3Ware or Adaptec arcconf binary if present on the
   system, otherwise non-existent.


