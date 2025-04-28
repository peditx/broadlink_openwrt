local socket = require("socket")
local crypto = require("crypto")

module("broadlink.protocol", package.seeall)

function encrypt(payload, key, iv)
    local cipher = crypto.cipher.new("aes-128-cbc")
    return cipher:encrypt(payload, key, iv)
end

function decrypt(payload, key, iv)
    local cipher = crypto.cipher.new("aes-128-cbc")
    return cipher:decrypt(payload, key, iv)
end

function learn_code(ip, code_type)
    local tcp = socket.tcp()
    tcp:settimeout(10)
    
    if not tcp:connect(ip, 80) then
        return false, "Connection failed"
    end

    local packet = string.char(
        0x5A, 0xA5, 0xAA, 0x55,
        0x5A, 0xA5, 0xAA, 0x55,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00
    )

    tcp:send(packet)

    local response = tcp:receive("*a")
    tcp:close()

    if response and #response > 0 then
        return true, parse_code(response)
    else
        return false, "No response"
    end
end

function parse_code(data)
    -- استخراج کد از داده‌های دریافتی
    return string.sub(data, 0x38, 0x38 + 64):gsub(".", function(c) return string.format("%02X", c:byte()) end)
end
