module("luci.controller.broadlink", package.seeall)

function index()
    entry({"admin", "services", "broadlink"}, firstchild(), "Broadlink", 60).dependent = false
    entry({"admin", "services", "broadlink", "learn"}, template("broadlink/learn"), "Learn", 1)
    entry({"admin", "services", "broadlink", "devices"}, cbi("broadlink/devices"), "Devices", 2)
    entry({"admin", "services", "broadlink", "discover"}, call("action_discover"), nil, 3)
    entry({"admin", "services", "broadlink", "learn_action"}, call("action_learn"), nil, 4)
end

function action_discover()
    local bl = require "broadlink.discovery"
    local devices = bl.discover_devices()
    luci.http.prepare_content("application/json")
    luci.http.write_json(devices)
end

function action_learn()
    local http = require "luci.http"
    local bl = require "broadlink.protocol"
    
    local mac = http.formvalue("mac")
    local code_type = http.formvalue("type")
    
    -- دریافت دستگاه از UCI
    local uci = luci.model.uci.cursor()
    local device = uci:get_all("broadlink", mac)
    
    if device then
        local success, code = bl.learn_code(device.ip, code_type)
        http.prepare_content("application/json")
        http.write_json({
            success = success,
            code = code or ""
        })
    else
        http.status(404, "Device not found")
    end
end
