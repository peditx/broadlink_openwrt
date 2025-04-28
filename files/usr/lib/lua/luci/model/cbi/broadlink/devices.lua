-- files/usr/lib/lua/luci/model/cbi/broadlink/devices.lua
local uci = luci.model.uci.cursor()

m = Map("broadlink", "Broadlink Devices")
m.redirect = luci.dispatcher.build_url("admin/services/broadlink")

s = m:section(TypedSection, "device", "Configured Devices")
s.addremove = true
s.anonymous = false

s:option(Value, "name", "Device Name")
mac = s:option(Value, "mac", "MAC Address")
mac.datatype = "macaddr"
ip = s:option(Value, "ip", "IP Address")
ip.datatype = "ip4addr"

s:option(ListValue, "type", "Device Type")
s:option(Flag, "enable", "Enabled")

return m
