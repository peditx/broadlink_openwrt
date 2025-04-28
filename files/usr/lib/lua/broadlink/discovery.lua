local socket = require("socket")
local bit = require("bit")

module("broadlink.discovery", package.seeall)

function discover_devices()
    local udp = socket.udp()
    udp:settimeout(2)
    udp:setsockname("*", 80)
    udp:setoption("broadcast", true)

    local packet = string.char(
        0x5A, 0xA5, 0xAA, 0x55,
        0x5A, 0xA5, 0xAA, 0x55,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    )

    udp:sendto(packet, "255.255.255.255", 80)

    local devices = {}
    local start_time = os.time()

    while os.time() - start_time < 5 do
        local data, ip = udp:receivefrom()
        if data and #data >= 0x40 then
            local dev = {
                ip = ip,
                mac = string.format("%02X:%02X:%02X:%02X:%02X:%02X",
                    data:byte(0x34), data:byte(0x35),
                    data:byte(0x36), data:byte(0x37),
                    data:byte(0x38), data:byte(0x39)),
                type = get_device_type(data:byte(0x40))
            }
            table.insert(devices, dev)
        end
    end

    return devices
end

function get_device_type(type_code)
    local types = {
        [0x2712] = "RM4 Pro",
        [0x2737] = "RM Mini",
        [0x272a] = "SP2",
        [0x753e] = "MP1"
    }
    return types[type_code] or "Unknown"
end
