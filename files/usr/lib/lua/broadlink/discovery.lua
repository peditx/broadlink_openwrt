-- files/usr/lib/lua/broadlink/discovery.lua
local socket = require("socket")
local bit = require("bit")
local crypto = require("crypto")
local json = require("luci.json")

module("broadlink.discovery", package.seeall)

function discover_devices()
    local udp = socket.udp()
    udp:settimeout(2)
    udp:setsockname("*", 80)
    udp:setoption('broadcast', true)
    
    local discovery_packet = string.char(
        0x5A, 0xA5, 0xAA, 0x55,
        0x5A, 0xA5, 0xAA, 0x55,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    )
    
    udp:sendto(discovery_packet, "255.255.255.255", 80)
    
    local devices = {}
    local start_time = os.time()
    
    while os.time() - start_time < 5 do
        local data, ip = udp:receivefrom()
        if data then
            local dev = {
                mac = string.format("%02X:%02X:%02X:%02X:%02X:%02X",
                    data:byte(0x34), data:byte(0x35),
                    data:byte(0x36), data:byte(0x37),
                    data:byte(0x38), data:byte(0x39)),
                ip = ip,
                type = data:byte(0x40)
            }
            table.insert(devices, dev)
        end
    end
    
    return devices
end
