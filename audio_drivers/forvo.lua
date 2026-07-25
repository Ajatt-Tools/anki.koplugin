--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Forvo audio driver — scrapes forvo.com for a pronunciation URL.
]]

local http = require("socket.http")
local socket = require("socket")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local base64 = require("lua_utils/base64")
local logger = require("logger")

local Forvo = {
    id = "forvo",
    name = "Forvo",
    description = "Fetch pronunciation audio from forvo.com",
    settings = {},
}

local function GET(url)
    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local request = {
        url = url,
        method = "GET",
        headers = {
            ['User-Agent'] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36",
            ['Host'] = 'forvo.com',
            ['Accept-Language'] = "en-US,en;q=0.9",
            ['Accept'] = "*/*"
        },
        sink = ltn12.sink.table(sink),
    }
    local code, _, status = socket.skip(1, http.request(request))
    if code == 200 then
        return table.concat(sink)
    end
    if code == 403 then
        return false, "FORVO_403"
    end
    return false, ("[%d]: %s"):format(code or -1, status or "")
end

local function url_encode(url)
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
    -- logger.info(("Forvo: GET %s"):format(forvo_url))
    local forvo_page, err = GET(forvo_url)
    if not forvo_page then
        return false, err
    end
    local play_params = string.match(forvo_page, "Play%((.-)%);")

    local word_url = nil
    if play_params then
        local iter = string.gmatch(play_params, "'(.-)'")
        local formats = { mp3 = iter(), ogg = iter() }
        if formats["ogg"] then
            word_url = string.format('https://audio00.forvo.com/%s/%s', "ogg", base64.decode(formats["ogg"]))
        end
    else
        logger.warn("Forvo: page fetched but no Play(...) pronunciation found (page may be blocked or empty)")
    end
    return true, word_url
end

-- ctx: { word, language, field, settings }
-- returns: ok, audio_or_nil_or_err
function Forvo:get_audio(ctx)
    local ok, forvo_url = get_pronunciation_url(ctx.word, ctx.language)
    if not ok then
        if forvo_url == "FORVO_403" then
            -- Blocked by Forvo: continue note creation without audio
            logger.warn("Forvo returned 403 - continuing without audio")
            return true, nil
        end
        return false, ("Could not connect to forvo: %s"):format(forvo_url)
    end
    if not forvo_url then
        logger.warn(("Forvo: no pronunciation URL for '%s' (%s) - continuing without audio"):format(ctx.word, ctx.language))
        return true, nil
    end
    logger.info(("Forvo: using audio URL %s"):format(forvo_url))
    return true, {
        url = forvo_url,
        filename = string.format("forvo_%s.ogg", ctx.word),
    }
end

return Forvo
