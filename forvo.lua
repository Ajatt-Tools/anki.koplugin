--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Utils for downloading pronunciations from Forvo
]]

local http = require("socket.http")
local socket = require("socket")
local ltn12 = require("ltn12")

local function GET(url)
    local sink = {}
    local request = {
        url = url,
        method = "GET",
        headers = {
            ["Content-Type"] = "application/json"
        },
        sink = ltn12.sink.table(sink),
    }
    local code, _, status = socket.skip(1, http.request(request))
    if code == 200 then
        return table.concat(sink)
    end
end

-- http://lua-users.org/wiki/BaseSixtyFour
-- character table string
local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64e(data)
    return ((data:gsub('.', function(x) 
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

local function base64d(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end


local function url_encode(url)
    -- https://gist.github.com/liukun/f9ce7d6d14fa45fe9b924a3eed5c3d99
    local char_to_hex = function(c)
        return string.format("%%%02X", string.byte(c))
    end
    if url == nil then
        return
    end
    url = url:gsub("\n", "\r\n")
    url = url:gsub("([^%w _%%%-%.~])", char_to_hex)
    url = url:gsub(" ", "+")
    return url
end

local function get_pronunciation_url(word, language)
    local forvo_url = ('https://forvo.com/search/%s/%s'):format(url_encode(word), language)
    local forvo_page = GET(forvo_url)
    if not forvo_page then
        return false
    end
    local play_params = string.match(forvo_page, "Play%((.-)%);")

    local word_url = nil
    if play_params then
        local iter = string.gmatch(play_params, "'(.-)'")
        local formats = { mp3 = iter(), ogg = iter() }
        word_url = string.format('https://audio00.forvo.com/%s/%s', "ogg", base64d(formats["ogg"]))
    end
    return true, word_url
end

return {
    get_pronunciation_url = get_pronunciation_url,
    base64e = base64e,
}
