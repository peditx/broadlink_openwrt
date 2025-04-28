local mqtt = require "mqtt"
local uci = require "luci.model.uci".cursor()
local json = require "luci.json"

local _M = {}

function _M.start()
    local broker = uci:get("broadlink", "mqtt", "broker")
    local port = uci:get("broadlink", "mqtt", "port") or 1883
    local client_id = uci:get("broadlink", "mqtt", "client_id") or "broadlink-"..os.time()
    
    local client = mqtt.Client{
        id = client_id,
        clean = true,
        username = uci:get("broadlink", "mqtt", "username"),
        password = uci:get("broadlink", "mqtt", "password")
    }
    
    client:on("connect", function()
        client:subscribe("broadlink/+/command", 0)
        client:subscribe("broadlink/discovery", 0)
    end)
    
    client:on("message", function(topic, payload)
        local parts = {}
        for part in topic:gmatch("[^/]+") do
            table.insert(parts, part)
        end
        
        if parts[2] == "discovery" then
            handle_discovery(client)
        else
            local mac = parts[2]
            local command = json.decode(payload)
            execute_command(mac, command)
        end
    end)
    
    client:connect(broker, port)
end

function handle_discovery(client)
    local devices = _M.discover()
    client:publish("broadlink/discovery/results", json.encode(devices))
end

return _M
