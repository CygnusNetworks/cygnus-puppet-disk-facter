class DiskInfo
	attr_accessor :devid
	attr_accessor :device
	attr_accessor :vendor
	attr_accessor :model
	attr_accessor :serial
	def initialize(devid, device, vendor, type, smartdev)
		@devid = devid
		@device = device
		@vendor = vendor
		output = Facter::Util::Resolution.exec("smartctl -i -d #{type} /dev/#{smartdev}")
		raise "missing smartctl?" unless output
		@model = output[/^Device Model: +(.*)/,1]
		@model = output[/^Product: +(.*)/,1] unless @model
		@serial = output[/^Serial [Nn]umber: +(.*)/,1]
		raise "model not found for #{devid}" unless @model
		raise "serial not found for #{devid}" unless @serial
	end
end


if Facter.value(:kernel) == "Linux"
	disks = []
	Dir.glob("/sys/block/sd?/device/vendor") do |path|
		begin
			device = path[/sd./]
			vendor = File.read(path).rstrip
			case vendor
			when "ATA"
				disks << DiskInfo.new(device, device, vendor, "ata", device)
			when "IBM-ESXS"
				disks << DiskInfo.new(device, device, vendor, "scsi", device)
			when "AMCC"
				if device == "sda" then
					(0..127).each do |n|
						disks << DiskInfo.new("#{device}_#{n}", device, vendor, "3ware,#{n}", "twa0")
					end
				end
			when "LSI"
				(0..32).each do |n|
					begin
						disks << DiskInfo.new("#{device}_#{n}", device, vendor, "megaraid,#{n}", device)
					rescue
					end
				end
			when "TEAC" # Ignore CD drives
			else
				Facter.debug "unknown vendor #{vendor} for #{device}"
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
	end
end
