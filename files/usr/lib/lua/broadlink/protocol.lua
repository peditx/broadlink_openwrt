local crypto = require "crypto"
local socket = require "socket"
local bit32 = require "bit32"

local _M = {}

function _M.encrypt(payload, key, iv)
    local cipher = crypto.cipher.new("aes-128-cbc")
    return cipher:encrypt(payload, key, iv)
end

function _M.decrypt(payload, key, iv)
    local cipher = crypto.cipher.new("aes-128-cbc")
    return cipher:decrypt(payload, key, iv)
end

function _M.build_packet(device_type, payload)
    local packet = string.char(0x5A, 0xA5) -- Magic
    packet = packet .. string.pack(">I2", #payload + 0x30)
    packet = packet .. string.rep("\x00", 0x20) -- IV
    packet = packet .. _M.encrypt(payload, device_key, device_iv)
    return packet
end

function _M.discover(timeout)
    local udp = socket.udp()
    udp:settimeout(timeout or 5)
    udp:setsockname("*", 80)
    udp:setoption('broadcast', true)
    
    local packet = string.char(
        0x5A, 0xA5, 0xAA, 0x55,
        0x5A, 0xA5, 0xAA, 0x55,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    )
    
    udp:sendto(packet, "255.255.255.255", 80)
    
    local devices = {}
    while true do
        local data, ip, port = udp:receivefrom()
        if not data then break end
        
        local dev = {
            ip = ip,
            mac = data:sub(0x34, 0x39):gsub(".", function(c) return string.format("%02X:", c:byte()) end):sub(1,-2),
            type = data:sub(0x40, 0x40):byte()
        }
        table.insert(devices, dev)
    end
    
    return devices
end

return _M
