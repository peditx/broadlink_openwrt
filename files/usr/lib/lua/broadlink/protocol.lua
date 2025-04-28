local crypto = require "crypto"
local socket = require "socket"
local bit32 = require "bit32"

local _M = {}

-- رمزنگاری AES-128-CBC
function _M.encrypt(payload, key, iv)
    local cipher = crypto.cipher.new("aes-128-cbc")
    return cipher:encrypt(payload, key, iv)
end

-- رمزگشایی AES-128-CBC
function _M.decrypt(payload, key, iv)
    local cipher = crypto.cipher.new("aes-128-cbc")
    return cipher:decrypt(payload, key, iv)
end

-- ساخت پکت با پارامترهای ورودی
function _M.build_packet(device_type, payload, key, iv)
    local packet = string.char(0x5A, 0xA5) -- Magic
    packet = packet .. string.pack(">I2", #payload + 0x30)
    packet = packet .. iv or string.rep("\x00", 0x20)
    packet = packet .. _M.encrypt(payload, key, iv)
    return packet
end

-- کشف دستگاه‌ها با تبدیل نوع به نام
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
        local data, ip = udp:receivefrom()
        if not data then break end
        
        local dev = {
            ip = ip,
            mac = string.format("%02X:%02X:%02X:%02X:%02X:%02X",
                data:byte(0x34), data:byte(0x35),
                data:byte(0x36), data:byte(0x37),
                data:byte(0x38), data:byte(0x39)),
            type = _M.get_device_type(data:byte(0x40))
        }
        table.insert(devices, dev)
    end
    
    return devices
end

-- تبدیل کد نوع به نام دستگاه
function _M.get_device_type(type_code)
    local types = {
        [0x2712] = "RM4",
        [0x2737] = "RM Mini",
        [0x272a] = "SP2",
        [0x753e] = "MP1"
    }
    return types[type_code] or "Unknown"
end

return _M
