-- Broadlink MQTT Service Logic
-- Connects to an MQTT broker and listens for commands.

local mqtt = require "mosquitto"
local uci = require "luci.model.uci".cursor()
local json = require "cjson"
local protocol = require "broadlink.protocol"

local _M = {}

local client
local topic_prefix

-- Find a configured device by its name or MAC
local function find_device(identifier)
    local target_device = nil
    uci:foreach("broadlink", "device", function(s)
        if s['.name'] == identifier or (s.mac and s.mac:lower() == identifier:lower()) then
            target_device = s
        end
    end)
    return target_device
end

-- Handle incoming MQTT messages
local function message_callback(mid, topic, payload, qos)
    print("MQTT: Received message on topic '" .. topic .. "'")
    local topic_parts = {}
    for part in topic:gmatch("[^/]+") do
        table.insert(topic_parts, part)
    end

    -- Expecting topic format: <prefix>/<device_name_or_mac>/<action>
    -- e.g., broadlink/RM4_LivingRoom/send
    if #topic_parts < 3 then
        print("MQTT Error: Topic format is invalid. Expected <prefix>/<device>/<action>.")
        return
    end

    local device_id = topic_parts[2]
    local action = topic_parts[3]

    local device = find_device(device_id)
    if not device or not device.ip then
        print("MQTT Error: Device '" .. device_id .. "' not found in config or has no IP.")
        return
    end

    if action == "send" then
        local data = json.decode(payload)
        if not data or not data.code then
            print("MQTT Error: 'send' action requires a JSON payload with a 'code' field.")
            return
        end
        
        local hex_code
        -- Check if it's a named code or a raw code
        local saved_code = uci:get_all("broadlink", data.code)
        if saved_code and saved_code['.type'] == 'code' then
            hex_code = saved_code.code
        else
            hex_code = data.code -- Assume it's a raw hex code
        end

        local ok, err = protocol.send_code(device.ip, device.mac, hex_code)
        if not ok then
            print("MQTT: Failed to send code to " .. device.name .. ": " .. tostring(err))
        end
    elseif action == "learn" then
        -- Note: Learning via MQTT is less practical but possible
        print("MQTT: Entering learning mode for " .. device.name)
        local code, err = protocol.learn_code(device.ip, device.mac)
        if code then
            print("MQTT: Learned code: " .. code)
            -- Publish the learned code to a result topic
            client:publish(topic_prefix .. "/" .. device_id .. "/learn_result", code, 2, false)
        else
            print("MQTT: Failed to learn code: " .. tostring(err))
        end
    end
end

-- Handle connection event
local function connect_callback(rc, msg)
    if rc == 0 then
        print("MQTT: Successfully connected to broker.")
        -- Subscribe to command topics for all configured devices
        uci:foreach("broadlink", "device", function(s)
            if s.enabled == "1" and s['.name'] then
                local command_topic = topic_prefix .. "/" .. s['.name'] .. "/#"
                print("MQTT: Subscribing to " .. command_topic)
                client:subscribe(command_topic, 2)
            end
        end)
    else
        print("MQTT: Connection failed - " .. msg)
    end
end

function _M.start()
    local settings = uci:get_all("broadlink", "settings")
    if not settings then
        error("MQTT settings not found in config")
        return
    end

    topic_prefix = settings.topic_prefix or "broadlink"
    
    client = mqtt.new(settings.client_id)
    client:on_message(message_callback)
    client:on_connect(connect_callback)
    
    if settings.username and settings.username ~= "" then
        client:username_pw_set(settings.username, settings.password)
    end

    print("MQTT: Connecting to broker at " .. settings.broker .. ":" .. (settings.port or 1883))
    client:connect(settings.broker, tonumber(settings.port or 1883), 60)

    -- Start the MQTT client loop
    -- This will run in the background managed by uloop
    mqtt.loop_start(client)
end

return _M
