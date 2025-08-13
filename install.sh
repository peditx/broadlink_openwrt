#!/bin/sh

echo ">>> Starting Broadlink NG Installation Script (v2.0)..."
echo ">>> This will install the complete Broadlink control package."

# 1. Install Dependencies
echo "--> Updating package lists..."
opkg update

echo "--> Installing dependencies: lua-cjson, lua-mosquitto, lua-uloop, lua-openssl"
opkg install lua-cjson lua-mosquitto lua-uloop lua-openssl

# 2. Clean up old files to ensure a fresh installation
echo "--> Cleaning up any previous installation files..."
rm -f /etc/init.d/broadlink
rm -f /etc/config/broadlink
rm -f /usr/sbin/broadlinkd
rm -f /usr/lib/lua/luci/controller/broadlink.lua
rm -f /usr/lib/lua/luci/view/broadlink_ui.htm
rm -rf /usr/lib/lua/broadlink

# 3. Create necessary directories
echo "--> Creating installation directories..."
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/lib/lua/luci/view
mkdir -p /usr/lib/lua/broadlink

# 4. Write all application files from scratch

# --- File: /etc/config/broadlink ---
echo "--> Creating UCI configuration file..."
cat > /etc/config/broadlink <<'EoL'
config broadlink 'global'
	option enabled '1'
	option mqtt_enabled '0'

config mqtt 'settings'
	option broker '127.0.0.1'
	option port '1883'
	option username ''
	option password ''
	option client_id 'broadlink-openwrt'
	option topic_prefix 'broadlink'

EoL

# --- File: /etc/init.d/broadlink ---
echo "--> Creating init.d service script..."
cat > /etc/init.d/broadlink <<'EoL'
#!/bin/sh /etc/rc.common

START=99
STOP=15
USE_PROCD=1
PROG="/usr/sbin/broadlinkd"

start_service() {
	local enabled
	config_load broadlink
	config_get_bool enabled global enabled '0'
	[ "$enabled" -eq 1 ] || return 1

	procd_open_instance
	procd_set_param command /usr/bin/lua "$PROG"
	procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param file /etc/config/broadlink
	procd_close_instance
}

reload_service() {
	stop
	start
}
EoL

# --- File: /usr/sbin/broadlinkd (The Lua Daemon) ---
echo "--> Creating the main daemon script..."
cat > /usr/sbin/broadlinkd <<'EoL'
#!/usr/bin/env lua
local uloop = require "uloop"
local uci = require "luci.model.uci".cursor()
local mqtt_service = require "broadlink.mqtt"

uloop.init()
print("Broadlink NG Daemon: Service started.")

local mqtt_enabled = uci:get_first("broadlink", "global", "mqtt_enabled", "0")

if mqtt_enabled == "1" then
	print("Broadlink NG Daemon: MQTT is enabled. Starting MQTT client...")
	local ok, err = pcall(mqtt_service.start)
	if not ok then
		print("Broadlink NG Daemon: Failed to start MQTT service - " .. tostring(err))
	end
else
	print("Broadlink NG Daemon: MQTT is disabled. Service will remain idle.")
end

uloop.run()
print("Broadlink NG Daemon: Service stopped.")
EoL

# --- File: /usr/lib/lua/broadlink/protocol.lua ---
echo "--> Creating the protocol library..."
cat > /usr/lib/lua/broadlink/protocol.lua <<'EoL'
local socket = require("socket")
local crypto = require("openssl.crypto")
local util = require("luci.util")

local _M = {}

local AES_KEY = "\x09\x76\x28\x34\x3f\xe9\x9e\x23\x89\x54\xd3\x1a\xb7\x8f\xf6\x9a"
local AES_IV  = "\x56\x2e\x17\x99\x6d\x09\x3d\x28\xdd\xb3\xba\x69\x5a\x2e\x6f\x58"

local DEVICE_TYPES = {
    [0x2712] = "RM2", [0x2737] = "RM Mini", [0x273d] = "RM Pro", [0x2787] = "RM4 Mini",
    [0x27c2] = "RM4", [0x27c7] = "RM4 Pro", [0x51da] = "RM4", [0x5f36] = "RM Mini",
    [0x6026] = "RM4 Pro", [0x61a2] = "RM4 Pro", [0x62bc] = "RM4 Mini", [0x653a] = "RM4 Mini"
}

local function aes_encrypt(payload) return crypto.encrypt("aes-128-cbc", payload, AES_KEY, AES_IV) end
local function aes_decrypt(payload) return crypto.decrypt("aes-128-cbc", payload, AES_KEY, AES_IV) end

local function build_packet(command, payload)
    local packet = string.rep("\x00", 0x38)
    packet = packet:sub(1, 0x25) .. string.char(command) .. packet:sub(0x27)
    packet = packet:sub(1, 0x33) .. "\x01\x00\x00\x00" .. packet:sub(0x38)
    packet = packet:sub(1, #packet) .. payload
    local checksum = 0xbeaf
    for i = 1, #packet do checksum = checksum + packet:byte(i) end
    checksum = checksum & 0xffff
    packet = packet:sub(1, 0x19) .. string.pack("<I2", checksum) .. packet:sub(0x1C)
    local encrypted_payload = aes_encrypt(payload)
    packet = packet:sub(1, 0x37) .. encrypted_payload
    return packet
end

function _M.discover_devices(timeout)
    timeout = timeout or 2
    local udp = socket.udp()
    if not udp then return nil, "Failed to create UDP socket" end
    udp:settimeout(timeout)
    udp:setsockname("*", 0)
    udp:setoption("broadcast", true)
    local address = util.get_ifenv("lan").ipaddr or "127.0.0.1"
    local local_ip_bytes = {socket.dns.toip(address)}
    local packet = "\x5a\xa5\xaa\x55\x5a\xa5\xaa\x55" .. string.rep("\x00", 0x28)
    packet = packet:sub(1, 0x17) .. "\x06" .. packet:sub(0x19)
    packet = packet:sub(1, 0x23) .. string.char(local_ip_bytes[1], local_ip_bytes[2], local_ip_bytes[3], local_ip_bytes[4]) .. packet:sub(0x28)
    packet = packet:sub(1, 0x27) .. string.pack("<I2", 80) .. packet:sub(0x2a)
    local checksum = 0xbeaf
    for i=1, #packet do checksum = checksum + packet:byte(i) end
    packet = packet:sub(1, 0x1f) .. string.pack("<I2", checksum & 0xffff) .. packet:sub(0x22)
    udp:sendto(packet, "255.255.255.255", 80)
    local devices = {}
    local start_time = socket.gettime()
    while socket.gettime() - start_time < timeout do
        local data, ip = udp:receivefrom()
        if data and #data >= 0x38 then
            local dev_type_code = data:byte(0x35) * 256 + data:byte(0x34)
            local mac_addr = string.format("%02x:%02x:%02x:%02x:%02x:%02x", data:byte(0x3f), data:byte(0x3e), data:byte(0x3d), data:byte(0x3c), data:byte(0x3b), data:byte(0x3a))
            local dev = { ip = ip, mac = mac_addr:upper(), type_code = dev_type_code, type_name = DEVICE_TYPES[dev_type_code] or "Unknown" }
            if not devices[dev.mac] then devices[dev.mac] = dev end
        end
    end
    udp:close()
    local result_array = {}
    for _, v in pairs(devices) do table.insert(result_array, v) end
    return result_array
end

function _M.learn_code(ip, mac)
    local packet = build_packet(0x6a, "\x03" .. string.rep("\x00", 15))
    local tcp = socket.tcp()
    tcp:settimeout(10)
    local ok, err = tcp:connect(ip, 80)
    if not ok then return nil, "Connection failed: " .. tostring(err) end
    tcp:send(packet)
    local response = tcp:receive(1024)
    tcp:close()
    if not response or #response < 0x38 or (response:byte(0x22) + response:byte(0x23) * 256) ~= 0 then return nil, "Device returned error on entering learn mode" end
    local attempts = 0
    while attempts < 15 do
        socket.sleep(1)
        local code, poll_err = _M.check_learned_code(ip, mac)
        if code then return code, nil end
        attempts = attempts + 1
    end
    return nil, "Learning timed out."
end

function _M.check_learned_code(ip, mac)
    local packet = build_packet(0x6a, "\x04" .. string.rep("\x00", 15))
    local tcp = socket.tcp()
    tcp:settimeout(5)
    local ok, err = tcp:connect(ip, 80)
    if not ok then return nil, "Connection failed" end
    tcp:send(packet)
    local response = tcp:receive(1024)
    tcp:close()
    if not response or #response < 0x38 or (response:byte(0x22) + response:byte(0x23) * 256) ~= 0 then return nil, "Device returned error" end
    local decrypted_payload = aes_decrypt(response:sub(0x38))
    if decrypted_payload and #decrypted_payload > 4 then return util.tohex(decrypted_payload:sub(5)) end
    return nil, "No code data yet"
end

function _M.send_code(ip, mac, hex_code)
    local packet = build_packet(0x6a, "\x02\x00\x00\x00" .. util.hex_to_string(hex_code))
    local tcp = socket.tcp()
    tcp:settimeout(5)
    local ok, err = tcp:connect(ip, 80)
    if not ok then return false, "Connection failed: " .. tostring(err) end
    tcp:send(packet)
    local response = tcp:receive(1024)
    tcp:close()
    if response and #response >= 0x38 and (response:byte(0x22) + response:byte(0x23) * 256) == 0 then return true
    else return false, "Device returned error on send" end
end

return _M
EoL

# --- File: /usr/lib/lua/broadlink/mqtt.lua ---
echo "--> Creating the MQTT library..."
cat > /usr/lib/lua/broadlink/mqtt.lua <<'EoL'
local mqtt = require "mosquitto"
local uci = require "luci.model.uci".cursor()
local json = require "cjson"
local protocol = require "broadlink.protocol"

local _M = {}
local client
local topic_prefix

local function find_device(identifier)
    local target_device = nil
    uci:foreach("broadlink", "device", function(s)
        if s['.name'] == identifier or (s.mac and s.mac:lower() == identifier:lower()) then
            target_device = s
        end
    end)
    return target_device
end

local function message_callback(mid, topic, payload, qos)
    print("MQTT: Received message on topic '" .. topic .. "'")
    local topic_parts = {}
    for part in topic:gmatch("[^/]+") do table.insert(topic_parts, part) end
    if #topic_parts < 3 then print("MQTT Error: Invalid topic format.") return end
    local device_id = topic_parts[2]
    local action = topic_parts[3]
    local device = find_device(device_id)
    if not device or not device.ip then print("MQTT Error: Device '" .. device_id .. "' not found.") return end
    if action == "send" then
        local data = json.decode(payload)
        if not data or not data.code then print("MQTT Error: Missing 'code' in payload.") return end
        local saved_code = uci:get_all("broadlink", data.code)
        local hex_code = (saved_code and saved_code['.type'] == 'code') and saved_code.code or data.code
        local ok, err = protocol.send_code(device.ip, device.mac, hex_code)
        if not ok then print("MQTT: Failed to send code: " .. tostring(err)) end
    elseif action == "learn" then
        print("MQTT: Entering learning mode for " .. device.name)
        local code, err = protocol.learn_code(device.ip, device.mac)
        if code then
            print("MQTT: Learned code: " .. code)
            client:publish(topic_prefix .. "/" .. device_id .. "/learn_result", code, 2, false)
        else
            print("MQTT: Failed to learn code: " .. tostring(err))
        end
    end
end

local function connect_callback(rc, msg)
    if rc == 0 then
        print("MQTT: Successfully connected to broker.")
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
    if not settings then error("MQTT settings not found") return end
    topic_prefix = settings.topic_prefix or "broadlink"
    client = mqtt.new(settings.client_id)
    client:on_message(message_callback)
    client:on_connect(connect_callback)
    if settings.username and settings.username ~= "" then
        client:username_pw_set(settings.username, settings.password)
    end
    print("MQTT: Connecting to " .. settings.broker .. ":" .. (settings.port or 1883))
    client:connect(settings.broker, tonumber(settings.port or 1883), 60)
    mqtt.loop_start(client)
end

return _M
EoL

# --- File: /usr/lib/lua/luci/controller/broadlink.lua ---
echo "--> Creating the LuCI controller..."
cat > /usr/lib/lua/luci/controller/broadlink.lua <<'EoL'
module("luci.controller.broadlink", package.seeall)

function index()
	entry({"admin", "peditxos"}, firstchild(), _("PeDitXOS Tools"), 50).dependent = false
	entry({"admin", "peditxos", "broadlink"}, template("broadlink_ui"), _("Broadlink NG"), 20).dependent = true
	entry({"admin", "services", "broadlink_api"}, call("api_handler")).leaf = true
end

function api_handler()
    luci.http.prepare_content("application/json")
    local json = require "cjson"
    local uci = require "luci.model.uci".cursor()
    local protocol = require "broadlink.protocol"
    local action = luci.http.formvalue("action")
    local response = { success = false, message = "Invalid action" }

    if action == "get_data" then
        local devices, remotes, codes = {}, {}, {}
        uci:foreach("broadlink", "device", function(s) table.insert(devices, { id = s['.name'], name = s.name or s['.name'], ip = s.ip, mac = s.mac, type = s.type }) end)
        uci:foreach("broadlink", "remote", function(s) table.insert(remotes, { id = s['.name'], name = s.name or s['.name'], device = s.device }) end)
        uci:foreach("broadlink", "code", function(s) table.insert(codes, { id = s['.name'], name = s.name or s['.name'], remote = s.remote, code = s.code }) end)
        response = { success = true, devices = devices, remotes = remotes, codes = codes }
    elseif action == "discover" then
        local discovered_devices, err = protocol.discover_devices(3)
        if discovered_devices then response = { success = true, devices = discovered_devices }
        else response = { success = false, message = "Discovery failed: " .. tostring(err) } end
    elseif action == "add_device" then
        local mac, ip, type, name = luci.http.formvalue("mac"), luci.http.formvalue("ip"), luci.http.formvalue("type"), luci.http.formvalue("name") or ("Dev_" .. luci.http.formvalue("mac"):sub(-5):gsub(":", ""))
        local id = name:gsub("[^%w_]", "")
        uci:section(id, "device", {name=name, mac=mac, ip=ip, type=type, enabled="1"})
        uci:commit("broadlink")
        response = { success = true }
    elseif action == "remove_device" then
        local id = luci.http.formvalue("id")
        uci:delete("broadlink", id)
        uci:foreach("broadlink", "remote", function(s) if s.device == id then
            uci:foreach("broadlink", "code", function(c) if c.remote == s['.name'] then uci:delete("broadlink", c['.name']) end end)
            uci:delete("broadlink", s['.name'])
        end end)
        uci:commit("broadlink")
        response = { success = true }
    elseif action == "add_remote" then
        local name, device_id = luci.http.formvalue("name"), luci.http.formvalue("device_id")
        local id = name:gsub("[^%w_]", "")
        uci:section(id, "remote", {name=name, device=device_id})
        uci:commit("broadlink")
        response = { success = true }
    elseif action == "remove_remote" then
        local id = luci.http.formvalue("id")
        uci:delete("broadlink", id)
        uci:foreach("broadlink", "code", function(s) if s.remote == id then uci:delete("broadlink", s['.name']) end end)
        uci:commit("broadlink")
        response = { success = true }
    elseif action == "learn" then
        local dev_cfg = uci:get_all("broadlink", luci.http.formvalue("device_id"))
        if dev_cfg and dev_cfg.ip then
            local code, err = protocol.learn_code(dev_cfg.ip, dev_cfg.mac)
            if code then response = { success = true, code = code }
            else response = { success = false, message = "Learning failed: " .. tostring(err) } end
        else response = { success = false, message = "Device not found." } end
    elseif action == "save_code" then
        local remote_id, name, code = luci.http.formvalue("remote_id"), luci.http.formvalue("name"), luci.http.formvalue("code")
        local id = remote_id .. "_" .. name:gsub("[^%w_]", "")
        uci:section(id, "code", {name=name, remote=remote_id, code=code})
        uci:commit("broadlink")
        response = { success = true }
    elseif action == "remove_code" then
        uci:delete("broadlink", luci.http.formvalue("id"))
        uci:commit("broadlink")
        response = { success = true }
    elseif action == "test_code" then
        local code_cfg = uci:get_all("broadlink", luci.http.formvalue("id"))
        if code_cfg and code_cfg.remote then
            local remote_cfg = uci:get_all("broadlink", code_cfg.remote)
            if remote_cfg and remote_cfg.device then
                local dev_cfg = uci:get_all("broadlink", remote_cfg.device)
                if dev_cfg and dev_cfg.ip then
                    local ok, err = protocol.send_code(dev_cfg.ip, dev_cfg.mac, code_cfg.code)
                    if ok then response = { success = true }
                    else response = { success = false, message = "Send failed: " .. tostring(err) } end
                else response = { success = false, message = "Physical device not found." } end
            else response = { success = false, message = "Associated remote not found." } end
        else response = { success = false, message = "Code not found." } end
    end
    luci.http.write(json.encode(response))
end
EoL

# --- File: /usr/lib/lua/luci/view/broadlink_ui.htm ---
echo "--> Creating the LuCI view (UI)..."
cat > /usr/lib/lua/luci/view/broadlink_ui.htm <<'EoL'
<%+header%>
<style>
	.glass-panel { background: rgba(30, 30, 40, 0.75); backdrop-filter: blur(15px); -webkit-backdrop-filter: blur(15px); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 16px; color: #f0f0f0; padding: 25px 30px; margin: 20px auto; max-width: 950px; box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.37); }
	.panel-title { font-size: 1.8em; font-weight: bold; text-align: center; margin-bottom: 20px; border-bottom: 1px solid rgba(255, 255, 255, 0.1); padding-bottom: 15px; }
	.info-row { display: flex; justify-content: space-between; align-items: center; padding: 12px 0; font-size: 1.1em; }
	.status-running { color: #28a745; font-weight: bold; } .status-stopped { color: #dc3545; font-weight: bold; }
	.data-table { width: 100%; margin-top: 20px; border-collapse: collapse; }
	.data-table th, .data-table td { padding: 12px; text-align: left; border-bottom: 1px solid rgba(255, 255, 255, 0.1); }
	.data-table th { background-color: rgba(255, 255, 255, 0.05); }
	.data-table td.actions { display: flex; gap: 5px; justify-content: flex-end; }
	.glass-btn { background: rgba(255, 255, 255, 0.1); border: 1px solid rgba(255, 255, 255, 0.2); color: #fff; padding: 8px 15px; border-radius: 8px; cursor: pointer; transition: background 0.3s, transform 0.1s; font-weight: bold; }
	.glass-btn:hover { background: rgba(255, 255, 255, 0.2); } .glass-btn:active { transform: scale(0.98); }
	.glass-btn:disabled { background: rgba(128, 128, 128, 0.2); color: #888; cursor: not-allowed; }
	.glass-btn.btn-positive { background-color: rgba(40, 167, 69, 0.5); } .glass-btn.btn-negative { background-color: rgba(220, 53, 69, 0.5); }
	.cbi-input-text, .cbi-input-select { background: rgba(0,0,0,0.2); border: 1px solid rgba(255,255,255,0.2); color: white; padding: 8px; border-radius: 6px; width: 100%; }
	.spinner { border: 4px solid rgba(255,255,255,0.1); border-left-color: #fff; border-radius: 50%; width: 24px; height: 24px; animation: spin 1s linear infinite; margin: 10px auto; }
	@keyframes spin { 100% { transform: rotate(360deg); } }
	.accordion-header { background-color: rgba(255, 255, 255, 0.05); padding: 15px; margin-top: 10px; border-radius: 8px; cursor: pointer; display: flex; justify-content: space-between; align-items: center; }
	.accordion-content { padding: 0 15px; max-height: 0; overflow: hidden; transition: max-height 0.3s ease-out; background-color: rgba(0,0,0,0.1); border-radius: 0 0 8px 8px;}
	.accordion-content.active { max-height: 500px; padding: 15px; }
	.add-form { display: flex; gap: 10px; align-items: center; margin-top: 15px; }
</style>

<div class="glass-panel">
	<div class="panel-title">Broadlink NG Control</div>
	<div class="info-row"><span>Daemon Status:</span><span id="daemonStatus">Loading...</span></div>
	<div class="info-row"><span>MQTT Service:</span><span id="mqttStatus">Loading...</span></div>
	<div class="btn-container"><button class="glass-btn" onclick="restartService()">Restart Service</button></div>
</div>

<div class="glass-panel">
	<div class="panel-title">1. Physical Device Management</div>
	<div class="btn-container"><button class="glass-btn btn-positive" id="discoverBtn" onclick="discoverDevices()">Discover Network</button></div>
	<div id="discoverySpinner" style="display:none;"><div class="spinner"></div></div>
	<table class="data-table"><thead><tr><th>Discovered Devices</th><th>MAC / IP</th><th>Type</th><th>Action</th></tr></thead><tbody id="discoveryList"></tbody></table>
	<hr style="border-color: rgba(255,255,255,0.1); margin: 20px 0;">
	<table class="data-table"><thead><tr><th>Configured Devices</th><th>Name</th><th>MAC / IP</th><th>Type</th><th>Action</th></tr></thead><tbody id="configuredDeviceList"></tbody></table>
</div>

<div class="glass-panel">
	<div class="panel-title">2. Logical Remote Management</div>
	<div class="add-form">
		<input type="text" id="newRemoteName" class="cbi-input-text" placeholder="New Remote Name" style="flex-grow: 1;">
		<select id="addRemoteDeviceSelect" class="cbi-input-select" style="flex-grow: 1;"></select>
		<button class="glass-btn btn-positive" onclick="addRemote()">Add Remote</button>
	</div>
	<table class="data-table"><thead><tr><th>Configured Remotes</th><th>Name</th><th>Controlled By</th><th>Action</th></tr></thead><tbody id="configuredRemoteList"></tbody></table>
</div>

<div class="glass-panel">
	<div class="panel-title">3. Code Learning & Management</div>
	<div id="learnSection">
		<div class="cbi-value"><label class="cbi-value-title">Select Remote to Add Code To:</label><div class="cbi-value-field"><select id="learnRemoteSelect" class="cbi-input-select"></select></div></div>
		<div class="btn-container"><button class="glass-btn btn-positive" id="learnBtn" onclick="learnCode()">Learn New Code</button></div>
		<div id="learnStatus" style="display:none; text-align:center; margin-top:15px;"><div class="spinner"></div><p>Point remote at device...</p></div>
		<div id="learnedCodeSection" style="display:none; margin-top: 20px;">
			<h4>New Code Learned!</h4><code id="learnedCodeData" style="word-break: break-all;"></code>
			<div class="cbi-value"><label class="cbi-value-title">Enter a name for this button:</label><div class="cbi-value-field"><input type="text" id="newCodeName" class="cbi-input-text" placeholder="e.g., Power"></div></div>
			<div class="btn-container"><button class="glass-btn" onclick="saveLearnedCode()">Save Code</button></div>
		</div>
	</div>
	<hr style="border-color: rgba(255,255,255,0.1); margin: 20px 0;">
	<div id="savedCodeContainer"></div>
</div>

<script type="text/javascript">
	const API_URL = '<%=luci.dispatcher.build_url("admin/services/broadlink_api")%>';
	let appData = { devices: [], remotes: [], codes: [] };

	async function apiCall(params) {
		try {
			const response = await XHR.get(API_URL, params);
			if (!response || !response.success) { console.error('API Error:', response); }
			return response;
		} catch (e) { console.error('API Exception:', e); return null; }
	}

	function renderAll() {
		apiCall({ action: 'get_data' }).then(data => {
			if(data && data.success) {
				appData = data;
				document.getElementById('configuredDeviceList').innerHTML = data.devices.map(dev => `<tr><td>${dev.name}</td><td>${dev.mac}<br>${dev.ip}</td><td>${dev.type}</td><td class="actions"><button class="glass-btn btn-negative" onclick="removeDevice(this, '${dev.id}')">Remove</button></td></tr>`).join('') || '<tr><td colspan="4" align="center">No devices configured.</td></tr>';
				document.getElementById('configuredRemoteList').innerHTML = data.remotes.map(remote => { const dev = data.devices.find(d => d.id === remote.device); return `<tr><td>${remote.name}</td><td>${dev ? dev.name : 'N/A'}</td><td class="actions"><button class="glass-btn btn-negative" onclick="removeRemote(this, '${remote.id}')">Remove</button></td></tr>` }).join('') || '<tr><td colspan="3" align="center">No remotes configured.</td></tr>';
				document.getElementById('savedCodeContainer').innerHTML = data.remotes.map(remote => { const codes = data.codes.filter(c => c.remote === remote.id); return `<div class="accordion-header" onclick="this.nextElementSibling.classList.toggle('active')"><span>${remote.name}</span><span>${codes.length} code(s) &nbsp; ▼</span></div><div class="accordion-content"><table class="data-table">${codes.map(code => `<tr><td>${code.name}</td><td class="actions"><button class="glass-btn" onclick="testCode(this, '${code.id}')">Test</button><button class="glass-btn btn-negative" onclick="removeCode(this, '${code.id}')">Remove</button></td></tr>`).join('') || '<tr><td>No codes for this remote.</td></tr>'}</table></div>` }).join('') || '<p align="center">Create a remote to add codes.</p>';
				const devSelect = document.getElementById('addRemoteDeviceSelect');
				devSelect.innerHTML = data.devices.map(dev => `<option value="${dev.id}">${dev.name}</option>`).join('') || '<option>Add a device first</option>';
				const remoteSelect = document.getElementById('learnRemoteSelect');
				remoteSelect.innerHTML = data.remotes.map(remote => `<option value="${remote.id}">${remote.name}</option>`).join('') || '<option>Create a remote first</option>';
				document.getElementById('learnBtn').disabled = data.remotes.length === 0;
			}
		});
	}

	async function discoverDevices() {
		document.getElementById('discoverBtn').disabled = true;
		document.getElementById('discoverySpinner').style.display = 'block';
		const data = await apiCall({ action: 'discover' });
		document.getElementById('discoverBtn').disabled = false;
		document.getElementById('discoverySpinner').style.display = 'none';
		if (data && data.success) {
			document.getElementById('discoveryList').innerHTML = data.devices.map(dev => `<tr><td>${dev.type_name}</td><td>${dev.mac}<br>${dev.ip}</td><td>0x${dev.type_code.toString(16)}</td><td class="actions"><button class="glass-btn" onclick="addDevice(this, '${dev.mac}', '${dev.ip}', '${dev.type_name}')">Add</button></td></tr>`).join('') || '<tr><td colspan="4" align="center">No new devices found.</td></tr>';
		}
	}

	async function addDevice(btn, mac, ip, type) {
		btn.disabled = true;
		const name = prompt(`Enter a name for this device (${mac})`, `My ${type}`);
		if (!name) { btn.disabled = false; return; }
		if (await apiCall({ action: 'add_device', mac, ip, type, name })) renderAll(); else btn.disabled = false;
	}

	async function removeDevice(btn, id) {
		if (!confirm(`Remove device "${id}" and all its remotes/codes?`)) return;
		btn.disabled = true;
		if (await apiCall({ action: 'remove_device', id })) renderAll(); else btn.disabled = false;
	}
	
	async function addRemote() {
		const name = document.getElementById('newRemoteName').value;
		const deviceId = document.getElementById('addRemoteDeviceSelect').value;
		if (!name) { alert('Please enter a name.'); return; }
		if (await apiCall({ action: 'add_remote', name, device_id: deviceId })) {
			document.getElementById('newRemoteName').value = '';
			renderAll();
		}
	}
	
	async function removeRemote(btn, id) {
		if (!confirm(`Remove remote "${id}" and all its codes?`)) return;
		btn.disabled = true;
		if (await apiCall({ action: 'remove_remote', id })) renderAll(); else btn.disabled = false;
	}

	async function learnCode() {
		const remoteId = document.getElementById('learnRemoteSelect').value;
		if (!remoteId) return;
		const remote = appData.remotes.find(r => r.id === remoteId);
		const device = appData.devices.find(d => d.id === remote.device);
		if (!device) { alert('Device for this remote not found!'); return; }
		
		document.getElementById('learnBtn').disabled = true;
		document.getElementById('learnStatus').style.display = 'block';
		document.getElementById('learnedCodeSection').style.display = 'none';

		const data = await apiCall({ action: 'learn', device_id: device.id });

		document.getElementById('learnBtn').disabled = false;
		document.getElementById('learnStatus').style.display = 'none';
		if (data && data.success) {
			document.getElementById('learnedCodeSection').style.display = 'block';
			document.getElementById('learnedCodeData').textContent = data.code;
			document.getElementById('newCodeName').value = '';
			document.getElementById('newCodeName').focus();
		} else {
			alert(`Learning failed: ${data ? data.message : 'Unknown error'}`);
		}
	}

	async function saveLearnedCode() {
		const remoteId = document.getElementById('learnRemoteSelect').value;
		const code = document.getElementById('learnedCodeData').textContent;
		const name = document.getElementById('newCodeName').value;
		if (!name) { alert('Please enter a name.'); return; }
		if (await apiCall({ action: 'save_code', remote_id: remoteId, name, code })) {
			document.getElementById('learnedCodeSection').style.display = 'none';
			renderAll();
		}
	}

	async function testCode(btn, id) {
		btn.disabled = true; btn.textContent = '...';
		await apiCall({ action: 'test_code', id });
		setTimeout(() => { btn.disabled = false; btn.textContent = 'Test'; }, 1000);
	}

	async function removeCode(btn, id) {
		if (!confirm(`Remove code "${id}"?`)) return;
		btn.disabled = true;
		if (await apiCall({ action: 'remove_code', id })) renderAll(); else btn.disabled = false;
	}
	
	function restartService() {
		luci.sys.call({ path: '/etc/init.d/broadlink', params: ['restart'], cb: () => setTimeout(renderAll, 2000) });
	}

	document.addEventListener('DOMContentLoaded', renderAll);
</script>
<%+footer%>
EoL

# 5. Set correct permissions for executable files
echo "--> Setting executable permissions..."
chmod +x /etc/init.d/broadlink
chmod +x /usr/sbin/broadlinkd

# 6. Enable and start the service
echo "--> Enabling and starting the Broadlink NG service..."
/etc/init.d/broadlink enable
/etc/init.d/broadlink restart

echo ""
echo ">>> Broadlink NG installation is complete! <<<"
echo ">>> Navigate to Services -> PeDitXOS Tools -> Broadlink NG in LuCI to configure."
echo ""

# ASCII Art for fun
cat << "EoL"
 ____  ____   __  ____  __  ____  _  _  __ _  __  __ _ 
(  _ \(  _ \ /  \(_  _)/  \(  _ \/ )( \(  ( \/  \/  ( \
 ) __/ )   /(  O ) )( (  O )) __/) __ (/    /)    /)    /
(__)  (__\_) \__/ (__) \__/(__)  \_)(_/\_)__)\_/\_/\_)__)

EoL
