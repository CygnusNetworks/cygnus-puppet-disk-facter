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
	attr_accessor :disks
	def initialize(device)
		@device = device
		@disks = []
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

class SmartDiskInfo < DiskInfo
	attr_accessor :smartdev
	attr_accessor :smarttype
	attr_accessor :model
	attr_accessor :serial
	def initialize(devid, smartdev, smarttype)
		super(devid)
		@smartdev = smartdev
		@smarttype = smarttype
		run_smartctl
	end
	def run_smartctl
		output = Facter::Util::Resolution.exec("smartctl -i -d #{@smarttype} /dev/#{@smartdev}")
		raise "missing smartctl?" unless output
		@model = output[/^Device Model: +(.*)/,1]
		@model = output[/^Product: +(.*)/,1] unless @model
		@serial = output[/^Serial [Nn]umber: +(.*)/,1]
		raise "model not found for #{devid}" unless @model
		raise "serial not found for #{devid}" unless @serial
	end
	def model
		run_smartctl unless @model
		return @model
	end
	def serial
		run_smartctl unless @serial
		return @serial
	end
end

if Facter.value(:kernel) == "Linux"
	blockdevs = []
	Dir.glob("/sys/block/sd?") do |path|
		begin
			device = BlockInfo.new(path[/sd./])
			blockdevs << device

			case device.driver
			when "ahci"
				device.disks << SmartDiskInfo.new(device.device, device.device, "ata")
			#when vendor == IBM-ESXS and driver == mptspi
			#	device.disks << SmartDiskInfo(device.device, device.device, "scsi")
			when "3w-9xxx"
				raise "unknown backing device #{device} for 3w-9xxx" unless device.device == "sda"
				(0..127).each do |n|
					device.disks << SmartDiskInfo.new("#{device.device}_#{n}", "twa0", "3ware,#{n}")
				end
			when "megaraid_sas"
				(0..32).each do |n|
					begin
						device.disks << SmartDiskInfo.new("#{device.device}_#{n}", device.device, "megaraid,#{n}")
					rescue
					end
				end
				raise "no disks found for #{device.device}" unless device.disks
			# TODO: when vendor == LSI and driver == 3w-sas, devices apparently only expose serials via tw-cli
			# TODO: when vendor == LSILOGIC and driver == mptspi run smartctl on the sgN backing devices
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
		device.disks.each do |disk|
			Facter.add("disk_model_#{disk.devid}") { setcode { disk.model } }
			Facter.add("disk_serial_#{disk.devid}") { setcode { disk.serial } }
		end
	end
end
