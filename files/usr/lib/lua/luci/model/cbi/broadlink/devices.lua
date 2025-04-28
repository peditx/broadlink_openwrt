local uci = luci.model.uci.cursor()

m = Map("broadlink", translate("Broadlink Devices"))
m.redirect = luci.dispatcher.build_url("admin/services/broadlink")

-- بخش دستگاه‌ها
s_devices = m:section(TypedSection, "device", translate("Configured Devices"))
s_devices.addremove = true
s_devices.anonymous = false

-- فیلدهای دستگاه
s_devices:option(Value, "name", translate("Device Name"))

mac = s_devices:option(Value, "mac", translate("MAC Address"))
mac.validate = function(self, value)
    if not value:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        return nil, translate("Invalid MAC address format!")
    end
    return value
end

ip = s_devices:option(Value, "ip", translate("IP Address"))
ip.validate = function(self, value)
    if not value:match("^%d+%.%d+%.%d+%.%d+$") then
        return nil, translate("Invalid IPv4 address!")
    end
    return value
end

device_type = s_devices:option(ListValue, "type", translate("Device Type"))
device_type:value("RM4", "RM4 Pro")
device_type:value("RM_Mini", "RM Mini")
device_type:value("SP2", "Smart Plug SP2")
device_type:value("MP1", "Multi Plug MP1")

s_devices:option(Flag, "enable", translate("Enabled"))

-- بخش کدهای ذخیره شده (جدول + دکمه تست)
s_codes = m:section(TypedSection, "code", translate("Saved Codes"))
s_codes.template = "cbi/tblsection"
s_codes.addremove = true
s_codes.anonymous = false

-- ستون‌های جدول
name = s_codes:option(DummyValue, "name", translate("Code Name"))
name.width = "30%"

device = s_codes:option(DummyValue, "device", translate("Device MAC"))
device.width = "30%"

code = s_codes:option(DummyValue, "code", translate("Code Data"))
code.width = "30%"

-- دکمه تست کد
test = s_codes:option(Button, "_test", translate("Test"))
test.inputstyle = "apply"
test.write = function(self, section)
    local code_value = self.map:get(section, "code")
    local device_mac = self.map:get(section, "device")
    luci.http.redirect(
        luci.dispatcher.build_url("admin/services/broadlink/send_code") ..
        "?mac=" .. luci.http.urlencode(device_mac) ..
        "&code=" .. luci.http.urlencode(code_value)
    )
end

return m
