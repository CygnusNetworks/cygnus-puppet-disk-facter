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

class DiskInfo
	attr_accessor :devid
	attr_accessor :device
	attr_accessor :model
	attr_accessor :serial
	def initialize(devid, device, type, smartdev)
		@devid = devid
		@device = device
		output = Facter::Util::Resolution.exec("smartctl -i -d #{type} /dev/#{smartdev}")
		raise "missing smartctl?" unless output
		@model = output[/^Device Model: +(.*)/,1]
		@model = output[/^Product: +(.*)/,1] unless @model
		@serial = output[/^Serial [Nn]umber: +(.*)/,1]
		raise "model not found for #{devid}" unless @model
		raise "serial not found for #{devid}" unless @serial
	end

	def driver
		return get_driver(@device)
	end

	def vendor
		return File.read("/sys/block/#{device}/device/vendor").rstrip
	end
end

if Facter.value(:kernel) == "Linux"
	disks = []
	Dir.glob("/sys/block/sd?/device/vendor") do |path|
		begin
			device = path[/sd./]
			driver = get_driver(device)

			case driver
			when "ahci"
				disks << DiskInfo.new(device, device, "ata", device)
			#when vendor == IBM-ESXS and driver == mptspi
			#	disks << DiskInfo.new(device, device, "scsi", device)
			when "3w-9xxx"
				raise "unknown backing device #{device} for 3w-9xxx" unless device == "sda"
				(0..127).each do |n|
					disks << DiskInfo.new("#{device}_#{n}", device, "3ware,#{n}", "twa0")
				end
			when "megaraid_sas"
				(0..32).each do |n|
					begin
						disks << DiskInfo.new("#{device}_#{n}", device, "megaraid,#{n}", device)
					rescue
					end
				end
			# TODO: when vendor == LSI and driver == 3w-sas, devices apparently only expose serials via tw-cli
			# TODO: when vendor == LSILOGIC and driver == mptspi run smartctl on the sgN backing devices
			else
				Facter.debug "unknown driver #{driver} for #{device}"
			end
		rescue
			Facter.debug "exception while processing #{device}: " + $!.to_s
		end
	end
	Facter.add(:disks) { setcode { (disks.collect(&:devid)).join(",") } }
	disks.each do |disk|
		Facter.add("disk_vendor_#{disk.devid}") { setcode { disk.vendor } }
		Facter.add("disk_model_#{disk.devid}") { setcode { disk.model } }
	Facter.add("disk_serial_#{disk.devid}") { setcode { disk.serial } }
	Facter.add("disk_driver_#{disk.devid}") { setcode { disk.driver } }
	end
end
