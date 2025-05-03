local socket = require("socket")
local crypto = require("crypto")
local bit32 = require("bit32")

local _M = {}

-- تنظیمات پیشفرض برای دستگاه‌های مختلف
local device_profiles = {
    ["RM4 Pro"] = {
        key = "\x09\x76\x28\x34\x3F\xE9\x9E\x23\x89\x54\xD3\x1A\xB7\x8F\xF6\x9A",
        iv = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    },
    ["RM Mini"] = {
        key = "\x09\x76\x28\x34\x3F\xE9\x9E\x23\x89\x54\xD3\x1A\xB7\x8F\xF6\x9A",
        iv = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    },
    ["SP2"] = {
        key = "\x09\x76\x28\x34\x3F\xE9\x9E\x23\x89\x54\xD3\x1A\xB7\x8F\xF6\x9A",
        iv = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    },
    ["MP1"] = {
        key = "\x09\x76\x28\x34\x3F\xE9\x9E\x23\x89\x54\xD3\x1A\xB7\x8F\xF6\x9A",
        iv = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    }
}

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
function _M.build_packet(device_type, payload)
    local profile = device_profiles[device_type] 
    if not profile then
        return nil, "Unsupported device type: " .. tostring(device_type)
    end
    
    local header = string.char(0x5A, 0xA5)
    local size = string.pack(">I2", #payload + 0x30)
    local encrypted = _M.encrypt(payload, profile.key, profile.iv)
    
    return header .. size .. profile.iv .. encrypted
end

-- ارسال کد به دستگاه (نسخه بهبود یافته)
function _M.send_code(ip, code)
    local tcp = socket.tcp()
    tcp:settimeout(5)
    
    -- اتصال به دستگاه
    local ok, err = tcp:connect(ip, 80)
    if not ok then
        return false, "Connection failed: " .. tostring(err)
    end
    
    -- ساخت پکت
    local packet, err = _M.build_packet("RM4 Pro", code)
    if not packet then
        tcp:close()
        return false, "Packet build failed: " .. tostring(err)
    end
    
    -- ارسال داده
    local bytes, err = tcp:send(packet)
    tcp:close()
    
    if bytes == #packet then
        return true
    else
        return false, "Send failed: " .. tostring(err)
    end
end

-- یادگیری کد از دستگاه
function _M.learn_code(ip, code_type)
    local tcp = socket.tcp()
    tcp:settimeout(10)
    
    local ok, err = tcp:connect(ip, 80)
    if not ok then
        return false, "Connection failed: " .. tostring(err)
    end
    
    local packet = string.char(0x5A, 0xA5, 0xAA, 0x55, 0x5A, 0xA5, 0xAA, 0x55)
    local bytes, err = tcp:send(packet)
    
    if bytes ~= #packet then
        tcp:close()
        return false, "Send failed: " .. tostring(err)
    end
    
    local response, err = tcp:receive("*a")
    tcp:close()
    
    if response then
        local hex_code = response:gsub(".", function(c) 
            return string.format("%02X", c:byte()) 
        end)
        return true, hex_code:sub(1, 128)  -- بازگشت 64 بایت اول
    else
        return false, "No response: " .. tostring(err)
    end
end

-- کشف دستگاه‌های موجود در شبکه
function _M.discover_devices()
    local udp = socket.udp()
    udp:settimeout(5)
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
        local data, ip, port = udp:receivefrom()
        if data and #data >= 0x34 then
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
    end
    
    return devices
end

-- تشخیص نوع دستگاه بر اساس کد
function _M.get_device_type(type_code)
    local device_types = {
        [0x2712] = "RM4 Pro",
        [0x2737] = "RM Mini",
        [0x272a] = "SP2",
        [0x753e] = "MP1"
    }
    return device_types[type_code] or "Unknown (0x" .. string.format("%04X", type_code) .. ")"
end

return _M
