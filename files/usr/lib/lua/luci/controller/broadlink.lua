-- Broadlink NG LuCI Controller v2
-- Implements hierarchical code management and moves to PeDitXOS Tools menu.

module("luci.controller.broadlink", package.seeall)

function index()
    -- Entry point moved under "PeDitXOS Tools"
	entry({"admin", "peditxos"}, firstchild(), _("PeDitXOS Tools"), 50).dependent = false
	entry({"admin", "peditxos", "broadlink"}, template("broadlink_ui"), _("Broadlink NG"), 20).dependent = true
    
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
        -- Fetch all entities: devices, remotes, and codes
        local devices = {}
        uci:foreach("broadlink", "device", function(s)
            table.insert(devices, { id = s['.name'], name = s.name or s['.name'], ip = s.ip, mac = s.mac, type = s.type })
        end)
        local remotes = {}
        uci:foreach("broadlink", "remote", function(s)
            table.insert(remotes, { id = s['.name'], name = s.name or s['.name'], device = s.device })
        end)
        local codes = {}
        uci:foreach("broadlink", "code", function(s)
             table.insert(codes, { id = s['.name'], name = s.name or s['.name'], remote = s.remote, code = s.code })
        end)
        response = { success = true, devices = devices, remotes = remotes, codes = codes }

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
        local section_id = name:gsub("[^%w_]", "") -- Create a safe section ID
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
        -- Also delete associated remotes and their codes
        uci:foreach("broadlink", "remote", function(s)
            if s.device == id then
                uci:foreach("broadlink", "code", function(c)
                    if c.remote == s['.name'] then uci:delete("broadlink", c['.name']) end
                end)
                uci:delete("broadlink", s['.name'])
            end
        end)
        uci:commit("broadlink")
        response = { success = true, message = "Device and its associated remotes/codes removed." }

    elseif action == "add_remote" then
        local name = luci.http.formvalue("name")
        local device_id = luci.http.formvalue("device_id")
        local section_id = name:gsub("[^%w_]", "")
        uci:add("broadlink", "remote", section_id)
        uci:set("broadlink", section_id, "name", name)
        uci:set("broadlink", section_id, "device", device_id)
        uci:commit("broadlink")
        response = { success = true, message = "Remote added." }

    elseif action == "remove_remote" then
        local id = luci.http.formvalue("id")
        uci:delete("broadlink", id)
        -- Also delete associated codes
        uci:foreach("broadlink", "code", function(s)
            if s.remote == id then uci:delete("broadlink", s['.name']) end
        end)
        uci:commit("broadlink")
        response = { success = true, message = "Remote and its codes removed." }

    elseif action == "learn" then
        local device_id = luci.http.formvalue("device_id")
        local device_config = uci:get_all("broadlink", device_id)
        if device_config and device_config.ip then
            local code, err = protocol.learn_code(device_config.ip, device_config.mac)
            if code then response = { success = true, code = code }
            else response = { success = false, message = "Learning failed: " .. tostring(err) } end
        else response = { success = false, message = "Device not found." } end

    elseif action == "save_code" then
        local remote_id = luci.http.formvalue("remote_id")
        local code_name = luci.http.formvalue("name")
        local code_data = luci.http.formvalue("code")
        local section_id = remote_id .. "_" .. code_name:gsub("[^%w_]", "")
        uci:add("broadlink", "code", section_id)
        uci:set("broadlink", section_id, "name", code_name)
        uci:set("broadlink", section_id, "remote", remote_id)
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
        if code_config and code_config.remote then
            local remote_config = uci:get_all("broadlink", code_config.remote)
            if remote_config and remote_config.device then
                local device_config = uci:get_all("broadlink", remote_config.device)
                if device_config and device_config.ip then
                    local ok, err = protocol.send_code(device_config.ip, device_config.mac, code_config.code)
                    if ok then response = { success = true, message = "Code sent." }
                    else response = { success = false, message = "Send failed: " .. tostring(err) } end
                else response = { success = false, message = "Physical device not found for this remote." } end
            else response = { success = false, message = "Associated remote not found." } end
        else response = { success = false, message = "Code not found or not associated with a remote." } end
    end

    luci.http.write(json.encode(response))
end
