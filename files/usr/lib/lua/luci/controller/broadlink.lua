-- Broadlink NG LuCI Controller
-- Implements a modern API-based backend inspired by Air-Cast.

module("luci.controller.broadlink", package.seeall)

function index()
    -- Main entry point in LuCI menu
	entry({"admin", "services", "broadlink"}, template("broadlink_ui"), _("Broadlink NG"), 60)
    
    -- Hidden API entry point for the frontend to call
	entry({"admin", "services", "broadlink_api"}, call("api_handler")).leaf = true
end

-- Central API handler for all frontend requests
function api_handler()
    luci.http.prepare_content("application/json")
    local json = require "cjson"
    local uci = require "luci.model.uci".cursor()
    local protocol = require "broadlink.protocol"

    local action = luci.http.formvalue("action")
    local response = { success = false, message = "Invalid action" }

    if action == "get_status" then
        local status_output = luci.sys.exec("/etc/init.d/broadlink status 2>/dev/null")
        local running = (string.match(status_output, "running") ~= nil)
        local mqtt_enabled = uci:get_first("broadlink", "global", "mqtt_enabled", "0") == "1"
        response = { success = true, running = running, mqtt_enabled = mqtt_enabled }

    elseif action == "get_data" then
        -- Get both configured devices and codes
        local devices = {}
        uci:foreach("broadlink", "device", function(s)
            table.insert(devices, {
                id = s['.name'],
                name = s.name or s['.name'],
                ip = s.ip,
                mac = s.mac,
                type = s.type
            })
        end)
        local codes = {}
        uci:foreach("broadlink", "code", function(s)
             table.insert(codes, {
                id = s['.name'],
                name = s.name or s['.name'],
                device = s.device,
                code = s.code
            })
        end)
        response = { success = true, devices = devices, codes = codes }

    elseif action == "discover" then
        local discovered_devices, err = protocol.discover_devices(3)
        if discovered_devices then
            response = { success = true, devices = discovered_devices }
        else
            response = { success = false, message = "Discovery failed: " .. tostring(err) }
        end
    
    elseif action == "add_device" then
        local mac = luci.http.formvalue("mac")
        local ip = luci.http.formvalue("ip")
        local type_name = luci.http.formvalue("type")
        local name = luci.http.formvalue("name") or ("Device_" .. mac:sub(-5):gsub(":", ""))
        
        local section_id = name:gsub("%s", "_") -- Create a safe section ID
        uci:add("broadlink", "device", section_id)
        uci:set("broadlink", section_id, "name", name)
        uci:set("broadlink", section_id, "mac", mac)
        uci:set("broadlink", section_id, "ip", ip)
        uci:set("broadlink", section_id, "type", type_name)
        uci:set("broadlink", section_id, "enabled", "1")
        uci:commit("broadlink")
        response = { success = true, message = "Device added." }

    elseif action == "remove_device" then
        local id = luci.http.formvalue("id")
        uci:delete("broadlink", id)
        -- Also delete associated codes
        uci:foreach("broadlink", "code", function(s)
            if s.device == id then
                uci:delete("broadlink", s['.name'])
            end
        end)
        uci:commit("broadlink")
        response = { success = true, message = "Device and its codes removed." }

    elseif action == "learn" then
        local device_id = luci.http.formvalue("device_id")
        local device_config = uci:get_all("broadlink", device_id)
        if device_config and device_config.ip then
            local code, err = protocol.learn_code(device_config.ip, device_config.mac)
            if code then
                response = { success = true, code = code }
            else
                response = { success = false, message = "Learning failed: " .. tostring(err) }
            end
        else
            response = { success = false, message = "Device not found." }
        end

    elseif action == "save_code" then
        local device_id = luci.http.formvalue("device_id")
        local code_name = luci.http.formvalue("name")
        local code_data = luci.http.formvalue("code")
        local section_id = code_name:gsub("%s", "_")

        uci:add("broadlink", "code", section_id)
        uci:set("broadlink", section_id, "name", code_name)
        uci:set("broadlink", section_id, "device", device_id)
        uci:set("broadlink", section_id, "code", code_data)
        uci:commit("broadlink")
        response = { success = true, message = "Code saved." }

    elseif action == "remove_code" then
        local id = luci.http.formvalue("id")
        uci:delete("broadlink", id)
        uci:commit("broadlink")
        response = { success = true, message = "Code removed." }

    elseif action == "test_code" then
        local code_id = luci.http.formvalue("id")
        local code_config = uci:get_all("broadlink", code_id)
        if code_config then
            local device_config = uci:get_all("broadlink", code_config.device)
            if device_config and device_config.ip then
                local ok, err = protocol.send_code(device_config.ip, device_config.mac, code_config.code)
                if ok then
                    response = { success = true, message = "Code sent." }
                else
                    response = { success = false, message = "Send failed: " .. tostring(err) }
                end
            else
                response = { success = false, message = "Associated device not found." }
            end
        else
            response = { success = false, message = "Code not found." }
        end
    end

    luci.http.write(json.encode(response))
end
