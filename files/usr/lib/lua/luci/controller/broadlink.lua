-- files/usr/lib/lua/luci/controller/broadlink.lua
module("luci.controller.broadlink", package.seeall)

function index()
    entry({"admin", "services", "broadlink"}, firstchild(), _("Broadlink"), 60).dependent = false
    entry({"admin", "services", "broadlink", "devices"}, cbi("broadlink/devices"), _("Devices"), 10)
    entry({"admin", "services", "broadlink", "learn"}, template("broadlink/learn"), _("Learn Codes"), 20)
    entry({"admin", "services", "broadlink", "discover"}, call("action_discover"), nil, 30)
end

function action_discover()
    local bl = require "broadlink.discovery"
    local devices = bl.discover_devices()
    luci.http.prepare_content("application/json")
    luci.http.write_json(devices)
end
