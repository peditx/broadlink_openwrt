local uci = luci.model.uci.cursor()

m = Map("broadlink", "Broadlink Devices")
m.redirect = luci.dispatcher.build_url("admin/services/broadlink")

s = m:section(TypedSection, "device", "Configured Devices")
s.addremove = true
s.anonymous = false

s:option(Value, "name", "Device Name")
s:option(Value, "mac", "MAC Address"):matches("%x+:%x+:%x+:%x+:%x+:%x+")
s:option(Value, "ip", "IP Address"):ipaddr()
s:option(ListValue, "type", "Device Type") -- این خط باید مقادیر مجاز را تعریف کند
s.option:value("RM4", "RM4 Pro")
s.option:value("RM_Mini", "RM Mini")
s.option:value("SP2", "Smart Plug SP2")
s.option:value("MP1", "Multi Plug MP1")
s:option(Flag, "enable", "Enabled")

return m
