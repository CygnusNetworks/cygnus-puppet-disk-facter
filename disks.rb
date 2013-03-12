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

def get_driver(device)
	devpath = File.readlink("/sys/block/#{device}")
	raise "device #{device} not found" unless devpath
	parts = devpath.split(/\//)
	raise "bad link for #{device}" unless parts.shift == ".."
	raise "bad link for #{device}" unless parts.shift == "devices"
	raise "non-pci device #{device}" unless parts.first.start_with?("pci")
	driverlink = ["", "sys", "devices", parts.shift]
	driverlink.concat(parts.take_while { |p| p.match(/^[0-9a-f:.]+$/i) })
	driverlink << "driver"
	driverpath = File.readlink(driverlink.join("/"))
	raise "no driver for #{device}" unless driverpath
	return driverpath.split(/\//).last
end

class BlockInfo
	attr_accessor :device
	attr_accessor :raidtype
	attr_accessor :disks
	def initialize(device)
		@device = device
		@disks = []
		@raidtype = nil
	end
	def driver
		@driver ||= get_driver(@device)
	end
	def vendor
		@vendor ||= File.read("/sys/block/#{device}/device/vendor").rstrip
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
		output = Facter::Util::Resolution.exec("smartctl -i -d #{@smarttype} /dev/#{@smartdev}")
		raise "missing smartctl?" unless output
		self.vendor_model = output[/^Device Model: +(.*)/,1]
		self.vendor_model = output[/^Product: +(.*)/,1] unless @model
		@serial = output[/^Serial [Nn]umber: +(.*)/,1]
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
	raidtype = twcli_exec("#{cpath} show unitstatus")[/^u[0-9]+ +RAID-([0-9]+)/,1]
	raise "unable to detect raidtype for #{cpath}" unless raidtype
	return raidtype
end

def twcli_query_disks(devicename, controller)
	output = twcli_exec("/c#{controller} show drivestatus")
	disks = []
	output.scan(/^p([0-9]+) +OK/) do |port,|
		portpath = "/c#{controller}/p#{port}"
		Facter.debug "found port #{portpath}"
		model = twcli_exec("#{portpath} show model")[/ = (.*)/,1]
		raise "no model found for tw-cli #{portpath}" unless model
		serial = twcli_exec("#{portpath} show serial")[/ = (.*)/,1]
		raise "no serial found for tw-cli #{portpath}" unless model
		disks << DumbDiskInfo.new("#{devicename}_#{port}", nil, model, serial)
	end
	return disks
end

if Facter.value(:kernel) == "Linux"
	blockdevs = []
	Dir.glob("/sys/block/sd?") do |path|
		begin
			device = BlockInfo.new(path[/sd./])
			blockdevs << device

			case device.driver
			when "ahci", "ata_piix", "sata_via"
				device.disks << SmartDiskInfo.new(device.device, device.device, "ata")
			when "megaraid_sas"
				(0..32).each do |n|
					begin
						device.disks << SmartDiskInfo.new("#{device.device}_#{n}", device.device, "megaraid,#{n}")
					rescue
					end
				end
				raise "no disks found for #{device.device}" unless device.disks
			when "3w-9xxx", "3w-sas", "3w-xxxx"
				raise "unknown backing device #{device.device} for #{device.driver}" unless device.device == "sda"
				controllers = twcli_query_controllers
				raise "no tw-cli controllers found" unless controllers
				# guessing that sda maps to the first existent controller
				controller = controllers.first
				device.raidtype = twcli_query_raidtype(controller)
				device.disks = twcli_query_disks("sda", controller)
			when "mptspi"
				# can be raid or plain scsi device. guess plain scsi device.
				device.disks << SmartDiskInfo.new(device.device, device.device, "scsi")
				# when no serial is found, this likely is a raid
				# TODO: run smartctl on the backing sgN devices
			when "ehci_hcd", "uhci_hcd"
				blockdevs.pop # ignore pluggable usb devices
			else
				Facter.debug "unknown driver #{device.driver} for #{device.device}"
			end
		rescue
			Facter.debug "exception while processing #{device.device}: " + $!.to_s
		end
	end
	Facter.add(:block_devices) { setcode { (blockdevs.collect(&:device)).join(",") } }
	blockdevs.each do |device|
		Facter.add("block_vendor_#{device.device}") { setcode { device.vendor } }
		Facter.add("block_driver_#{device.device}") { setcode { device.driver } }
		Facter.add("block_disks_#{device.device}") { setcode { (device.disks.collect(&:devid)).join(",") } }
		if device.disks.length > 0 then
			Facter.add("block_is_raid_#{device.device}") { setcode { (device.disks.length > 1).to_s } }
		end
		Facter.add("block_raidtype_#{device.device}") { setcode { device.raidtype } } if device.raidtype
		device.disks.each do |disk|
			Facter.add("disk_vendor_#{disk.devid}") { setcode { disk.vendor } } if disk.vendor
			Facter.add("disk_model_#{disk.devid}") { setcode { disk.model } }
			Facter.add("disk_serial_#{disk.devid}") { setcode { disk.serial } }
		end
	end
end
