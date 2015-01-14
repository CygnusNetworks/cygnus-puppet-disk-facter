puppet-disk_facter
==================

This facter plugin only works on Linux with smartmontools installed. Some RAID
controllers need the vendor RAID utilities installed to gather additional
information (for example tw-cli for 3Ware RAID controllers).

This module requires
[jhoblitt/smartd](https://forge.puppetlabs.com/jhoblitt/smartd).  You will need
to `include '::smartd'` on your Linux nodes to make sure that smartmontools is
installed.  Additionally, the following RAID utilities can be installed from
the Puppet Forge to enhance these facts:

* [jhoblitt/tw_3dm2](https://forge.puppetlabs.com/jhoblitt/tw_3dm2)
* [jhoblitt/megaraid_sm](https://forge.puppetlabs.com/jhoblitt/megaraid_sm)
* [jhoblitt/mdadm](https://forge.puppetlabs.com/jhoblitt/mdadm)

#Installation

```
puppet module install CygnusNetworks-disk_facter
```

#Usage

After installing the disk-facter, you will get the following variables:

 * `block_devices`: A comma separated list of block device names with the
   leading `/dev/` removed.
 * `twcli_path`: The name of the `tw-cli` or `tw_cli` binary if present on the
   system, otherwise empty.
 * For each element in `block_devices` there are further variables.
   + `block_vendor_$DEV`: Contains some kind of vendor representation. The
     usefulness of this variable is limited.
   + `block_driver_$DEV`: The Linux kernel driver name used to support this
     device.
   + `block_is_raid_$DEV`: true or false depending on whether the block device
     is backed by multiple disks. If tools needed for identification are
     missing, it may wrongly contain the value false.
   + `block_disks_$DEV`: A comma separated list of identifiers enumerating the
     actual disks backing this device. For regular disks this list has just
     one element. For raid devices this list driver specific identifiers if
     the required detection utilities are installed.
 * For each element of `block_disks_$DEV` there are further variables.
   + `disk_vendor_$DISK`: A usually upper case string representing the vendor
     of the disk. Usually correct.
   + `disk_model_$DISK`: A vendor specific representation of the model of the
     disk.
   + `disk_serial_$DISK`: A vendor specific representation of the serial
     number of the disk.

To effectively use the disk facter it makes sense to either install twcli on
every machine or install it based on the listed `block_driver_$DEV` contents.
Drivers starting with "3w-" require twcli. See
[jhoblitt/tw_3dm2](https://forge.puppetlabs.com/jhoblitt/tw_3dm2) for details
on how to get PUppet to deploy twcli.

