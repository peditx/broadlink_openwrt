-- Broadlink Protocol Library
-- Merged, fixed, and improved version for Broadlink NG.
-- Handles device discovery, code learning, and command sending.

local socket = require("socket")
local crypto = require("openssl.crypto") -- Using lua-openssl for better compatibility
local util = require("luci.util")

local _M = {}

-- Key and IV are shared across many devices
local AES_KEY = "\x09\x76\x28\x34\x3f\xe9\x9e\x23\x89\x54\xd3\x1a\xb7\x8f\xf6\x9a"
local AES_IV  = "\x56\x2e\x17\x99\x6d\x09\x3d\x28\xdd\xb3\xba\x69\x5a\x2e\x6f\x58"

-- Device types mapping from hex code to name
local DEVICE_TYPES = {
    [0x2712] = "RM2",
    [0x2737] = "RM Mini",
    [0x273d] = "RM Pro",
    [0x2787] = "RM4 Mini",
    [0x27c2] = "RM4",
    [0x27c7] = "RM4 Pro",
    [0x51da] = "RM4",
    [0x5f36] = "RM Mini",
    [0x6026] = "RM4 Pro",
    [0x61a2] = "RM4 Pro",
    [0x62bc] = "RM4 Mini",
    [0x653a] = "RM4 Mini"
}

-- Private helper function for AES encryption
local function aes_encrypt(payload)
    -- PKCS7 padding is handled by lua-openssl automatically
    return crypto.encrypt("aes-128-cbc", payload, AES_KEY, AES_IV)
end

-- Private helper function for AES decryption
local function aes_decrypt(payload)
    return crypto.decrypt("aes-128-cbc", payload, AES_KEY, AES_IV)
end

-- Private function to build a command packet
local function build_packet(command, payload)
    local packet = string.rep("\x00", 0x38)
    packet = packet:sub(1, 0x25) .. string.char(command) .. packet:sub(0x27)
    packet = packet:sub(1, 0x33) .. "\x01\x00\x00\x00" .. packet:sub(0x38) -- Placeholder for checksum
    packet = packet:sub(1, #packet) .. payload

    -- Calculate checksum
    local checksum = 0xbeaf
    for i = 1, #packet do
        checksum = checksum + packet:byte(i)
    end
    checksum = checksum & 0xffff

    -- Write checksum back into the packet
    packet = packet:sub(1, 0x19) .. string.pack("<I2", checksum) .. packet:sub(0x1C)
    
    -- Encrypt the payload part
    local encrypted_payload = aes_encrypt(payload)
    packet = packet:sub(1, 0x37) .. encrypted_payload
    
    return packet
end

-- Discover devices on the local network
function _M.discover_devices(timeout)
    timeout = timeout or 2
    local udp = socket.udp()
    if not udp then return nil, "Failed to create UDP socket" end

    udp:settimeout(timeout)
    udp:setsockname("*", 0)
    udp:setoption("broadcast", true)

    local address = util.get_ifenv("lan").ipaddr or "127.0.0.1"
    local local_ip_bytes = {socket.dns.toip(address)}

    local packet = string.rep("\x00", 0x30)
    packet = "\x5a\xa5\xaa\x55\x5a\xa5\xaa\x55" .. packet:sub(9)
    packet = packet:sub(1, 0x17) .. "\x06" .. packet:sub(0x19) -- Command: discover
    packet = packet:sub(1, 0x23) .. string.char(local_ip_bytes[1], local_ip_bytes[2], local_ip_bytes[3], local_ip_bytes[4]) .. packet:sub(0x28)
    packet = packet:sub(1, 0x27) .. string.pack("<I2", 80) .. packet:sub(0x2a) -- Port

    -- Checksum calculation
    local checksum = 0xbeaf
    for i=1, #packet do
        checksum = checksum + packet:byte(i)
    end
    packet = packet:sub(1, 0x1f) .. string.pack("<I2", checksum & 0xffff) .. packet:sub(0x22)

    udp:sendto(packet, "255.255.255.255", 80)

    local devices = {}
    local start_time = socket.gettime()
    while socket.gettime() - start_time < timeout do
        local data, ip, port = udp:receivefrom()
        if data and #data >= 0x38 then
            -- **FIXED**: Correct offsets for device type and MAC address
            local dev_type_code = data:byte(0x35) * 256 + data:byte(0x34)
            local mac_addr = string.format("%02x:%02x:%02x:%02x:%02x:%02x",
                data:byte(0x3f), data:byte(0x3e), data:byte(0x3d),
                data:byte(0x3c), data:byte(0x3b), data:byte(0x3a))

            local dev = {
                ip = ip,
                mac = mac_addr:upper(),
                type_code = dev_type_code,
                type_name = DEVICE_TYPES[dev_type_code] or "Unknown"
            }
            -- Avoid duplicates
            if not devices[dev.mac] then
                devices[dev.mac] = dev
            end
        end
    end
    udp:close()
    
    -- Convert map to array
    local result_array = {}
    for _, v in pairs(devices) do
        table.insert(result_array, v)
    end
    return result_array
end

-- Enter learning mode
function _M.learn_code(ip, mac)
    local payload = string.rep("\x00", 16)
    payload = "\x03" .. payload:sub(2) -- Command: enter learning
    local packet = build_packet(0x6a, payload)

    local tcp = socket.tcp()
    tcp:settimeout(10)
    local ok, err = tcp:connect(ip, 80)
    if not ok then return nil, "Connection failed: " .. tostring(err) end
    
    tcp:send(packet)
    local response = tcp:receive(1024)
    tcp:close()

    if not response or #response < 0x38 then return nil, "Invalid response from device" end
    
    local err_code = response:byte(0x22) + response:byte(0x23) * 256
    if err_code ~= 0 then return nil, "Device returned error: " .. err_code end

    -- Now poll for the learned code
    local attempts = 0
    while attempts < 15 do
        socket.sleep(1) -- Wait 1 second
        local code, poll_err = _M.check_learned_code(ip, mac)
        if code then
            return code, nil
        end
        attempts = attempts + 1
    end
    return nil, "Learning timed out. No code received."
end

-- Check for learned code data
function _M.check_learned_code(ip, mac)
    local payload = string.rep("\x00", 16)
    payload = "\x04" .. payload:sub(2) -- Command: check learned data
    local packet = build_packet(0x6a, payload)

    local tcp = socket.tcp()
    tcp:settimeout(5)
    local ok, err = tcp:connect(ip, 80)
    if not ok then return nil, "Connection failed: " .. tostring(err) end

    tcp:send(packet)
    local response = tcp:receive(1024)
    tcp:close()

    if not response or #response < 0x38 then return nil, "Invalid response" end

    local err_code = response:byte(0x22) + response:byte(0x23) * 256
    if err_code ~= 0 then return nil, "Device returned error" end
    
    local encrypted_payload = response:sub(0x38)
    local decrypted_payload = aes_decrypt(encrypted_payload)
    
    if decrypted_payload and #decrypted_payload > 4 then
        -- The first 4 bytes are header, the rest is the code
        local code_data = decrypted_payload:sub(5)
        return util.tohex(code_data)
    end

    return nil, "No code data yet"
end

-- Send a previously learned code
function _M.send_code(ip, mac, hex_code)
    local code_bytes = util.hex_to_string(hex_code)
    local payload = "\x02\x00\x00\x00" .. code_bytes -- Command: send data
    local packet = build_packet(0x6a, payload)
    
    local tcp = socket.tcp()
    tcp:settimeout(5)
    local ok, err = tcp:connect(ip, 80)
    if not ok then return false, "Connection failed: " .. tostring(err) end

    tcp:send(packet)
    local response = tcp:receive(1024)
    tcp:close()

    if not response or #response < 0x38 then return false, "Invalid response from device" end

    local err_code = response:byte(0x22) + response:byte(0x23) * 256
    if err_code == 0 then
        return true
    else
        return false, "Device returned error: " .. err_code
    end
end

return _M
