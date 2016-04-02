# Copyright (C) 2013  Cygnus Networks GmbH <info@cygnusnetworks.de>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

class BlockInfo
  attr_accessor :device
  attr_accessor :raidtype
  attr_accessor :disks
  attr_accessor :controller

  def initialize(device)
    @device = device
    @disks = []
    @raidtype = nil
    @controller = nil
  end

  def devpath
    return "/dev/" + @device.sub(/_/, "/")
  end

  def syspath
    return "/sys/block/" + @device.sub(/_/, "!")
  end

  def driver
    return @driver if @driver
    devpath = File.readlink(syspath)
    raise "device #{device} not found" unless devpath
    parts = devpath.split(/\//)
    raise "bad link for #{device}" unless parts.shift == ".."
    raise "bad link for #{device}" unless parts.shift == "devices"
    if parts.first == "virtual" then
      if @device.start_with?('md') then
        @driver = "swraid"
      else
        raise "Unknown driver for virtual device #{device}"
      end
    elsif parts.first == "platform" then
      Facter.debug("device #{device} is on a pseudo bus, ignoring")
    else
      raise "non-pci device #{device}" unless parts.first.start_with?("pci")
      driverlink = ["", "sys", "devices", parts.shift]
      driverlink.concat(parts.take_while { |p| p.match(/^[0-9a-f:.]+$/i) })
      driverlink << "driver"
      driverpath = File.readlink(driverlink.join("/"))
      raise "no driver for #{device}" unless driverpath
      @driver = driverpath.split(/\//).last
    end
  end

  def vendor
    if @driver == "swraid" then
      @vendor = "Linux"
    else
      @vendor ||= File.read(syspath + "/device/vendor").rstrip
    end
  end
end

class DiskInfo
  attr_accessor :devid

  def initialize(devid)
    @devid = devid
  end
end

def split_vendor(string)
  known_vendors = ["HITACHI", "INTEL", "SAMSUNG", "SEAGATE", "TOSHIBA", "VBOX", "WDC"]
  parts = string.partition(/ /)
  return [nil, string] unless parts.first
  vendor = parts.first.upcase
  return [vendor, parts[2]] if known_vendors.include? vendor
  parts = string.rpartition(/ /)
  vendor = parts.last.upcase
  return [vendor, parts[0]] if known_vendors.include? vendor
  return [nil, string]
end

class DumbDiskInfo < DiskInfo
  attr_accessor :vendor
  attr_accessor :model
  attr_accessor :serial

  def initialize(devid, vendor, model, serial)
    super(devid)
    @vendor = vendor
    if not vendor then
      @vendor, @model = split_vendor(model)
    else
      @model = model
    end
    @serial = serial
  end
end

class SmartDiskInfo < DiskInfo
  attr_accessor :smartdev
  attr_accessor :smarttype

  def initialize(devid, smartdev, smarttype)
    super(devid)
    @smartdev = smartdev
    @smarttype = smarttype
    run_smartctl
  end

  def run_smartctl
    output = Facter::Util::Resolution.exec("smartctl -i -d #{@smarttype} #{@smartdev}")
    raise "missing smartctl?" unless output
    self.vendor_model = output[/^Device Model: +(.*)/, 1]
    self.vendor_model = output[/^Product: +(.*)/, 1] unless @model
    @serial = output[/^Serial [Nn]umber: +(.*)/, 1]
    raise "model not found for #{devid}" unless @model
    raise "serial not found for #{devid}" unless @serial
  end

  def vendor
    run_smartctl unless @model # @vendor may be legitimately nil
    return @vendor
  end

  def model
    run_smartctl unless @model
    return @model
  end

  def serial
    run_smartctl unless @serial
    return @serial
  end

  def vendor_model=(string)
    @vendor, @model = split_vendor(string) if string
  end
end

def find_path(tool)
  minimal_path = ["/bin", "/sbin", "/usr/bin", "/usr/sbin"]
  (Facter.value(:path).split(":") + minimal_path).each do |dir|
    toolpath = "#{dir}/#{tool}"
    return toolpath if FileTest.executable?(toolpath)
  end
  nil
end

Facter.add(:twcli_path) do
  confine :kernel => "Linux"
  setcode { find_path("tw-cli") || find_path("tw_cli") }
end

Facter.add(:arcconf_path) do
  confine :kernel => "Linux"
  setcode { find_path("arcconf") }
end

def twcli_exec(command)
  twcli = Facter.value(:twcli_path)
  raise "no tw-cli tool found" unless twcli
  output = Facter::Util::Resolution.exec("#{twcli} #{command}")
  raise "no output from tw-cli #{command}. binary missing?" unless output
  return output
end

def twcli_query_controllers()
  twcli_exec("show").scan(/^c([0-9]+)/).collect(&:first)
end

def twcli_query_raidtype(controller)
  cpath = "/c#{controller}"
  raidtype = twcli_exec("#{cpath} show unitstatus")[/^u[0-9]+ +RAID-([0-9]+)/, 1]
  raise "unable to detect raidtype for #{cpath}" unless raidtype
  return raidtype
end

def twcli_query_disks(devicename, controller)
  output = twcli_exec("/c#{controller} show drivestatus")
  disks = []
  output.scan(/^p([0-9]+) +OK/) do |port,|
    portpath = "/c#{controller}/p#{port}"
    Facter.debug "found port #{portpath}"
    model = twcli_exec("#{portpath} show model")[/ = (.*)/, 1]
    raise "no model found for tw-cli #{portpath}" unless model
    serial = twcli_exec("#{portpath} show serial")[/ = (.*)/, 1]
    raise "no serial found for tw-cli #{portpath}" unless serial
    disks << DumbDiskInfo.new("#{controller}_#{port}", nil, model, serial)
  end
  return disks
end

def arcconf_exec(controller, command, param)
  arcconf = Facter.value(:arcconf_path)
  raise "no arcconf tool found" unless arcconf
  output = Facter::Util::Resolution.exec("#{arcconf} #{command} #{controller} #{param}")
  raise "no output from arcconfig #{command}. Binary missing?" unless output
  return output
end

def aacraid_query_raidtype(controller)
  raidtype = arcconf_exec(controller, "GETCONFIG", "LD")[/^\W+RAID level\W+: ([0-9]+)/, 1]
  raise "unable to detect raidtype for controller #{controller}" unless raidtype
  return raidtype
end

def aacraid_query_disks(devicename, controller)
  output = arcconf_exec(controller, "GETCONFIG", "PD")
  disks = []
  output.split(/(?=Device #)/).each do |raid_device|
    if raid_device =~ /Device is a Hard drive/
      port = raid_device.match(/^Device #([0-9])$/m)[1]
      Facter.debug "found port #{port}"
      model = raid_device.match(/^\W+Model\W+: (.*?)$/m)[1]
      raise "no model found for aacraid #{port}" unless model
      serial = raid_device.match(/^\W+Serial number\W+: (.*?)$/m)[1]
      raise "no serial found for aacraid #{port}" unless serial
      disks << DumbDiskInfo.new("#{devicename}_#{port}", nil, model, serial)
    else
      Facter.debug "Device is not a hard drive"
    end
  end
  return disks
end

def discover_blockdevs
  bdevs = []
  Dir.glob("/sys/block/sd?") do |path|
    bdevs << BlockInfo.new(path[/sd./])
  end
  Dir.glob("/sys/block/md?") do |path|
    bdevs << BlockInfo.new(path[/md./])
  end
  Dir.glob("/sys/block/cciss!c?d?") do |path|
    bdevs << BlockInfo.new(path[/cciss!..../].sub(/!/, "_"))
  end
  return bdevs
end

if Facter.value(:kernel) == "Linux"
  blockdevs = []
  Facter.debug "Calling discover_blockdevs"
  discover_blockdevs().each do |device|
    begin
      Facter.debug "Running for device #{device.device}"
      blockdevs << device

      case device.driver
        when "ahci", "ata_piix", "sata_via"
          Facter.debug "Device #{device.device} is standard (s)ata"
          device.disks << SmartDiskInfo.new(device.device, device.devpath, "ata")
        when "aacraid"
          Facter.debug "Device #{device} is aacraid"
          raise "unknown backing device #{device.device} for #{device.driver}" unless device.device == "sda"
          # guessing that sda maps to controller 1
          controller = 1
          device.raidtype = aacraid_query_raidtype(controller)
          Facter.debug "Raid Type is RAID-#{device.raidtype}"
          device.disks = aacraid_query_disks(device.device, controller)
          Facter.debug "Raid disks are #{device.disks}"
        when "megaraid_sas"
          Facter.debug "Device #{device} is megaraid_sas"
          (0..32).each do |n|
            begin
              device.disks << SmartDiskInfo.new("#{device.device}_#{n}", device.devpath, "megaraid,#{n}")
            rescue
            end
          end
          raise "no disks found for #{device.device}" unless device.disks
        when "3w-9xxx", "3w-sas", "3w-xxxx"
          Facter.debug "Device #{device} is 3ware"
          raise "unknown backing device #{device.device} for #{device.driver}" unless device.device == "sda"
          controllers = twcli_query_controllers
          Facter.debug "3Ware found controllers #{controllers}"
          raise "no tw-cli controllers found" unless controllers
          # guessing that sda maps to the first existent controller
          controller = controllers.first
          device.raidtype = twcli_query_raidtype(controller)
          Facter.debug "Raid Type is RAID-#{device.raidtype}"
          device.disks = twcli_query_disks("sda", controller)
          Facter.debug "Raid disks are #{device.disks}"
	  device.controller = controller
          Facter.debug "Controller is #{device.controller}"
        when "mpt2sas"
          Facter.debug "Device #{device} is mpt2sas"
          device.disks << SmartDiskInfo.new(device.device, device.devpath, "auto")
        when "mptspi"
          Facter.debug "Device #{device} is mpt"
          # can be raid or plain scsi device. guess plain scsi device.
          begin
            device.disks << SmartDiskInfo.new(device.device, device.devpath, "scsi")
          rescue
            Facter.debug "mptspi device #{device.device} appears not to be a disk: " + $!.to_s
            # maybe the serial was not found, because it is not a disk
            # we assume that this is a raid and all unassigned sg devices belong to it
            Dir.glob("/sys/class/scsi_generic/sg?/device") do |sgpath|
              nth = sgpath[/sg(.)/, 1]
              unless FileTest.exist?("#{sgpath}/block") then
                begin
                  device.disks << SmartDiskInfo.new("#{device.device}_#{nth}", "/dev/sg#{nth}", "scsi")
                rescue
                  # ignore processors and such
                end
              end
            end
          end
        when "swraid"
          Facter.debug "Device #{device.device} is swraid"
          device.raidtype ||= File.read(device.syspath + "/md/level")[/^raid(\d+)/, 1]
          Facter.debug "Raid Type is RAID-#{device.raidtype}"
          Dir.glob(device.syspath + "/slaves/*") do |path|
            device.disks << DiskInfo.new(path.split(/\//).last)
          end
          Facter.debug "Raid disks are #{device.disks}"
        when "ehci_hcd", "uhci_hcd"
          Facter.debug "Device #{device.device} is usb device. ignoring"
          blockdevs.pop # ignore pluggable usb devices
        else
          Facter.debug "unknown driver #{device.driver} for #{device.device}"
      end
    rescue
      Facter.debug "exception while processing #{device.device}: " + $!.to_s
    end
    Facter.debug "Finished information retrieval for device #{device.device}. Adding facts"
  end
  Facter.add(:block_devices) { setcode { (blockdevs.collect(&:device)).join(",") } }
  blockdevs.each do |device|
    Facter.debug "Adding facts for device '#{device.device}' vendor '#{device.vendor}' driver '#{device.driver}' controller '#{device.controller}'"
    Facter.add("block_vendor_#{device.device}") { setcode { device.vendor } }
    Facter.add("block_driver_#{device.device}") { setcode { device.driver } }
    if !device.controller.nil?
      Facter.add("block_controller_#{device.device}") { setcode { device.controller } }
    end
    Facter.add("block_disks_#{device.device}") { setcode { (device.disks.collect(&:devid)).join(",") } }
    if device.disks.length > 0 then
      Facter.add("block_is_raid_#{device.device}") { setcode { (device.disks.length > 1).to_s } }
    end
    Facter.add("block_raidtype_#{device.device}") { setcode { device.raidtype } } if device.raidtype
    unless device.driver == "swraid" then
      device.disks.each do |disk|
        Facter.add("disk_vendor_#{disk.devid}") { setcode { disk.vendor } } if disk.vendor
        Facter.add("disk_model_#{disk.devid}") { setcode { disk.model } }
        Facter.add("disk_serial_#{disk.devid}") { setcode { disk.serial } }
      end
    end
    Facter.debug "adding facts finished for device #{device.device}"
  end
end
