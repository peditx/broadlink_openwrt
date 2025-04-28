module("luci.controller.broadlink", package.seeall)

function index()
    entry({"admin", "services", "broadlink"}, firstchild(), _("Broadlink"), 60).dependent = false
    entry({"admin", "services", "broadlink", "learn"}, template("broadlink/learn"), _("Learn Codes"), 1)
    entry({"admin", "services", "broadlink", "devices"}, cbi("broadlink/devices"), _("Devices"), 2)
    entry({"admin", "services", "broadlink", "discover"}, call("action_discover"))
    entry({"admin", "services", "broadlink", "learn_action"}, call("action_learn"))
    entry({"admin", "services", "broadlink", "send_code"}, call("action_send_code")) -- افزودن entry برای send_code
    entry({"admin", "services", "broadlink", "save_code"}, call("action_save_code"))
end

-- کشف دستگاه‌ها
function action_discover()
    local bl = require "broadlink.discovery"
    local devices = bl.discover_devices() or {}
    luci.http.prepare_content("application/json")
    luci.http.write_json(devices)
end

-- یادگیری کد
function action_learn()
    local http = luci.http
    local bl = require "broadlink.protocol"
    local uci = luci.model.uci.cursor()

    local mac = http.formvalue("mac")
    local code_type = http.formvalue("type") or "ir"

    -- اعتبارسنجی MAC
    if not mac or not mac:match("%x+:%x+:%x+:%x+:%x+:%x+") then
        http.status(400, "Invalid MAC address")
        return
    end

    -- دریافت دستگاه از UCI
    local device = uci:get_all("broadlink", mac)
    if not device or not device.ip then
        http.status(404, "Device not found")
        return
    end

    -- اجرای یادگیری کد
    local success, code = pcall(bl.learn_code, device.ip, code_type)
    if success and code then
        http.prepare_content("application/json")
        http.write_json({success = true, code = code})
    else
        http.status(500, "Learning failed: " .. tostring(code))
    end
end

-- ارسال کد به دستگاه
function action_send_code()
    local http = require "luci.http"
    local bl = require "broadlink.protocol"
    local uci = luci.model.uci.cursor()

    local mac = http.formvalue("mac")
    local code = http.formvalue("code")

    -- اعتبارسنجی پارامترها
    if not mac or not code then
        http.status(400, "Missing parameters")
        return
    end

    -- دریافت اطلاعات دستگاه
    local device = uci:get_all("broadlink", mac)
    if not device or not device.ip then
        http.status(404, "Device not found")
        return
    end

    -- ارسال کد
    local success, err = bl.send_code(device.ip, code)
    http.prepare_content("application/json")
    http.write_json({
        success = success,
        message = success and "Code sent successfully" or "Error: " .. tostring(err)
    })
end

-- ذخیره کد در UCI
function action_save_code()
    local http = luci.http
    local uci = luci.model.uci.cursor()
    
    local mac = http.formvalue("mac")
    local code = http.formvalue("code")
    local name = http.formvalue("name")
    
    -- اعتبارسنجی داده‌ها
    if not mac or not code or not name then
        http.status(400, "Missing parameters")
        return
    end

    -- ایجاد سکشن جدید
    local code_id = uci:add("broadlink", "code", {
        name = name,
        device = mac,
        code = code
    })
    
    if code_id then
        uci:commit("broadlink")
        http.prepare_content("application/json")
        http.write_json({success = true})
    else
        http.status(500, "Failed to save code")
    end
end
