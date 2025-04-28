module("luci.controller.broadlink", package.seeall)

function index()
    entry({"admin", "services", "broadlink"}, firstchild(), _("Broadlink"), 60).dependent = false
    entry({"admin", "services", "broadlink", "learn"}, template("broadlink/learn"), _("Learn Codes"), 1)
    entry({"admin", "services", "broadlink", "devices"}, cbi("broadlink/devices"), _("Devices"), 2)
    entry({"admin", "services", "broadlink", "discover"}, call("action_discover"))
    entry({"admin", "services", "broadlink", "learn_action"}, call("action_learn"))
end

function action_discover()
    local bl = require "broadlink.discovery"
    local devices = bl.discover_devices() or {}
    luci.http.prepare_content("application/json")
    luci.http.write_json(devices)
end

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

    -- یادگیری کد
    local success, code = pcall(bl.learn_code, device.ip, code_type)
    if success and code then
        http.prepare_content("application/json")
        http.write_json({success = true, code = code})
    else
        http.status(500, "Learning failed: " .. tostring(code))
    end
end
