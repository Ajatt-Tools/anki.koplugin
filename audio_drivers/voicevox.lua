--[[
VOICEVOX audio driver — synthesizes pronunciation via a VOICEVOX Engine HTTP API.

API flow (plain text):
  1. POST /audio_query?speaker=<id>&text=<word>  → AudioQuery JSON
  2. POST /synthesis?speaker=<id>  (JSON body) → WAV bytes

API flow (AquesTalk-style kana with pitch accent):
  1. POST /accent_phrases?speaker=<id>&is_kana=true&text=<kana'> → accent phrases
  2. Wrap phrases in an AudioQuery and POST /synthesis
]]

local http = require("socket.http")
local socket = require("socket")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local base64 = require("lua_utils/base64")
local u = require("lua_utils/utils")
local util = require("util")
local json = require("rapidjson")
local logger = require("logger")

local VoiceVox = {
    id = "voicevox",
    name = "VOICEVOX",
    description = "Synthesize pronunciation audio via a VOICEVOX Engine server.",
    settings = {
        {
            id = "url",
            name = "Engine URL",
            conf_type = "text",
            description = "Base URL of the VOICEVOX Engine (e.g. http://192.168.0.1:50121).",
        },
        {
            id = "speaker_id",
            name = "Speaker Id",
            conf_type = "text",
            description = "VOICEVOX style/speaker id used for synthesis (e.g. 10000).",
        },
        {
            id = "word_field",
            name = "Word Field",
            conf_type = "text",
            description = "Anki field to use as the synthesis text (e.g. KanaReading). Leave blank to use the looked-up word.",
        },
        {
            id = "pitch_field",
            name = "Pitch Accent Field",
            conf_type = "text",
            description = "Anki field containing the pitch accent number (e.g. VocabPitchNum with a value like [1]). Leave blank to use the looked-up word.",
        },
        {
            id = "speedScale",
            name = "Speed (速度)",
            conf_type = "text",
            default = "1.0",
            description = "Speaking speed.",
        },
        {
            id = "pitchScale",
            name = "Pitch (音高)",
            conf_type = "text",
            default = "0.0",
            description = "Overall pitch.",
        },
        {
            id = "intonationScale",
            name = "Intonation (抑揚)",
            conf_type = "text",
            default = "1.0",
            description = "Intonation strength.",
        },
        {
            id = "volumeScale",
            name = "Volume (音量)",
            conf_type = "text",
            default = "1.0",
            description = "Volume.",
        },
        {
            id = "prePhonemeLength",
            name = "Pre-silence (開始無音)",
            conf_type = "text",
            default = "0.1",
            description = "Silence before speech (seconds).",
        },
        {
            id = "postPhonemeLength",
            name = "Post-silence (終了無音)",
            conf_type = "text",
            default = "0.1",
            description = "Silence after speech (seconds).",
        },
    },
}

local HIRAGANA = util.splitToChars(
    "ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとどなにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんゔ"
)
local KATAKANA = util.splitToChars(
    "ァアィイゥウェエォオカガキギクグケゲコゴサザシジスズセゼソゾタダチヂッツヅテデトドナニヌネノハバパヒビピフブプヘベペホボポマミムメモャヤュユョヨラリルレロヮワヰヱヲンヴ"
)
local HIRA_TO_KATA = {}
for i, hira in ipairs(HIRAGANA) do
    HIRA_TO_KATA[hira] = KATAKANA[i]
end

local KANA_CHARS = u.to_set(KATAKANA)
KANA_CHARS["ー"] = true

-- Small kana that attach to the previous mora (katakana + hiragana for safety).
local SMALL_KANA = u.to_set(util.splitToChars("ャュョァィゥェォゃゅょぁぃぅぇぉヮゎ"))

local function url_encode(str)
    local char_to_hex = function(c)
        return string.format("%%%02X", string.byte(c))
    end
    if str == nil then
        return
    end
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w _%%%-%.~])", char_to_hex)
    str = str:gsub(" ", "+")
    return str
end

local function normalize_base_url(url)
    return (url:gsub("/+$", ""))
end

local function http_post(url, body, content_type)
    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local headers = {
        ["Accept"] = "*/*",
    }
    local source = nil
    if body then
        headers["Content-Type"] = content_type or "application/json"
        headers["Content-Length"] = #body
        source = ltn12.source.string(body)
    else
        headers["Content-Length"] = 0
    end
    local request = {
        url = url,
        method = "POST",
        headers = headers,
        sink = ltn12.sink.table(sink),
        source = source,
    }
    local code, _, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    if code == 200 then
        return true, table.concat(sink)
    end
    if type(code) == "string" then
        return false, code
    end
    return false, ("[%s]: %s"):format(tostring(code or -1), status or "")
end

local function sanitize_filename(word)
    -- Strip path separators / control chars; keep Unicode so Japanese words stay unique.
    local cleaned = word:gsub("[/\\%z\r\n]", "_"):gsub("%s+", "_"):gsub("'", "")
    if cleaned == "" then
        cleaned = "word"
    end
    return cleaned
end

local function strip_html(text)
    if not text or text == "" then
        return text
    end
    return (text:gsub("<[^>]+>", ""))
end

local function to_katakana(text)
    local out = {}
    for _, ch in ipairs(util.splitToChars(text)) do
        table.insert(out, HIRA_TO_KATA[ch] or ch)
    end
    return table.concat(out)
end

local function sanitize_reading(raw)
    if not raw or raw == "" then
        return nil
    end
    local text = strip_html(raw)
    text = text:gsub("・", "")
    text = text:gsub("%s+", "")
    text = text:gsub("['%[%]%d]", "") -- drop any leftover pitch markup
    if text == "" then
        return nil
    end
    return to_katakana(text)
end

local function is_pure_katakana(text)
    if not text or text == "" then
        return false
    end
    for _, ch in ipairs(util.splitToChars(text)) do
        if not KANA_CHARS[ch] then
            return false
        end
    end
    return true
end

local function extract_pitch_number(raw)
    if not raw or raw == "" then
        return nil
    end
    local text = strip_html(raw)
    -- Prefer bracketed form like [1]; otherwise take the first digit sequence.
    local num = text:match("%[(%d+)%]") or text:match("(%d+)")
    if not num then
        return nil
    end
    return tonumber(num)
end

local function split_morae(word)
    local morae = {}
    for _, ch in ipairs(util.splitToChars(word)) do
        if SMALL_KANA[ch] and #morae > 0 then
            table.insert(morae[#morae], ch)
        else
            table.insert(morae, { ch })
        end
    end
    return morae
end

-- Insert an AquesTalk-style accent apostrophe after the given mora.
-- Pitch 0 (heiban): apostrophe after the final mora.
-- Pitch N>0: apostrophe after the Nth mora.
local function apply_pitch_accent(katakana, pitch_num)
    local morae = split_morae(katakana)
    if #morae == 0 then
        return katakana
    end

    local accent_after = pitch_num
    if pitch_num == 0 or pitch_num > #morae then
        accent_after = #morae
    end

    local parts = {}
    for idx, mora in ipairs(morae) do
        table.insert(parts, table.concat(mora))
        if idx == accent_after then
            table.insert(parts, "'")
        end
    end
    return table.concat(parts)
end

local function resolve_synthesis_text(ctx)
    local settings = ctx.settings or {}
    local fields = ctx.fields or {}
    local word_field = settings.word_field
    local pitch_field = settings.pitch_field

    -- The katakana + pitch path requires BOTH a kana reading and a pitch number.
    -- If either is missing we fall back to the original dictionary word so VOICEVOX
    -- can infer the reading and pitch on its own.
    local reading = nil
    if word_field and word_field ~= "" and fields[word_field] and fields[word_field] ~= "" then
        reading = sanitize_reading(fields[word_field])
        if reading and not is_pure_katakana(reading) then
            logger.warn(("VOICEVOX: reading '%s' is not kana; falling back to dictionary word"):format(reading))
            reading = nil
        end
    end

    local pitch_num = nil
    if pitch_field and pitch_field ~= "" then
        pitch_num = extract_pitch_number(fields[pitch_field])
    end

    if reading and pitch_num ~= nil then
        return apply_pitch_accent(reading, pitch_num), true
    end

    -- Fall back to the original dictionary word (e.g. kanji).
    return ctx.word, false
end

-- Defaults for user-configurable AudioQuery fields.
local AUDIO_QUERY_DEFAULTS = {
    speedScale = 1.0,
    pitchScale = 0.0,
    intonationScale = 1.0,
    volumeScale = 1.0,
    prePhonemeLength = 0.1,
    postPhonemeLength = 0.1,
}

local function resolve_number_setting(settings, id, default)
    local raw = settings[id]
    if raw == nil or raw == "" then
        return default
    end
    local num = tonumber(raw)
    if not num then
        logger.warn(("VOICEVOX: invalid %s '%s'; using default %s"):format(id, tostring(raw), tostring(default)))
        return default
    end
    return num
end

local function resolve_audio_query_params(settings)
    settings = settings or {}
    return {
        speedScale = resolve_number_setting(settings, "speedScale", AUDIO_QUERY_DEFAULTS.speedScale),
        pitchScale = resolve_number_setting(settings, "pitchScale", AUDIO_QUERY_DEFAULTS.pitchScale),
        intonationScale = resolve_number_setting(settings, "intonationScale", AUDIO_QUERY_DEFAULTS.intonationScale),
        volumeScale = resolve_number_setting(settings, "volumeScale", AUDIO_QUERY_DEFAULTS.volumeScale),
        prePhonemeLength = resolve_number_setting(settings, "prePhonemeLength", AUDIO_QUERY_DEFAULTS.prePhonemeLength),
        postPhonemeLength = resolve_number_setting(settings, "postPhonemeLength", AUDIO_QUERY_DEFAULTS.postPhonemeLength),
    }
end

-- Overlay user synthesis params onto an AudioQuery JSON body.
local function apply_audio_query_params(query_json, params)
    local query, decode_err = json.decode(query_json)
    if not query then
        return false, ("VOICEVOX audio_query returned invalid JSON: %s"):format(tostring(decode_err))
    end
    for key, value in pairs(params) do
        query[key] = value
    end
    return true, json.encode(query)
end

local function build_audio_query_from_kana(base_url, speaker, kana_text)
    local accent_url = ("%s/accent_phrases?speaker=%s&is_kana=true&text=%s"):format(
        base_url, speaker, url_encode(kana_text)
    )
    logger.info(("VOICEVOX: requesting accent_phrases (is_kana) for '%s'"):format(kana_text))
    local ok, phrases_or_err = http_post(accent_url, nil)
    if not ok then
        return false, ("VOICEVOX accent_phrases failed: %s"):format(phrases_or_err)
    end

    local phrases, decode_err = json.decode(phrases_or_err)
    if not phrases then
        return false, ("VOICEVOX accent_phrases returned invalid JSON: %s"):format(tostring(decode_err))
    end

    -- /accent_phrases returns phrases only; we wrap them in an AudioQuery.
    -- outputSamplingRate / outputStereo are required by the /synthesis schema (no omit-default),
    -- so use the same values /audio_query would fill in. Configurable params are overlaid later.
    local query = {
        accent_phrases = phrases,
        speedScale = AUDIO_QUERY_DEFAULTS.speedScale,
        pitchScale = AUDIO_QUERY_DEFAULTS.pitchScale,
        intonationScale = AUDIO_QUERY_DEFAULTS.intonationScale,
        volumeScale = AUDIO_QUERY_DEFAULTS.volumeScale,
        prePhonemeLength = AUDIO_QUERY_DEFAULTS.prePhonemeLength,
        postPhonemeLength = AUDIO_QUERY_DEFAULTS.postPhonemeLength,
        outputSamplingRate = 24000,
        outputStereo = false,
        kana = kana_text,
    }
    return true, json.encode(query)
end

local function build_audio_query_from_text(base_url, speaker, text)
    local query_url = ("%s/audio_query?speaker=%s&text=%s"):format(base_url, speaker, url_encode(text))
    logger.info(("VOICEVOX: requesting audio_query for '%s'"):format(text))
    return http_post(query_url, nil)
end

-- ctx: { word, language, field, fields, settings }
function VoiceVox:get_audio(ctx)
    local settings = ctx.settings or {}
    local base_url = settings.url
    local speaker_id = settings.speaker_id

    if not base_url or base_url == "" then
        return false, "VOICEVOX Engine URL is not configured"
    end
    if not speaker_id or speaker_id == "" then
        return false, "VOICEVOX Speaker Id is not configured"
    end

    local text, use_kana = resolve_synthesis_text(ctx)
    if not text or text == "" then
        return true, nil
    end

    base_url = normalize_base_url(base_url)
    local speaker = url_encode(tostring(speaker_id))

    local ok, query_or_err
    if use_kana then
        ok, query_or_err = build_audio_query_from_kana(base_url, speaker, text)
    else
        ok, query_or_err = build_audio_query_from_text(base_url, speaker, text)
    end
    if not ok then
        if use_kana then
            return false, query_or_err
        end
        return false, ("VOICEVOX audio_query failed: %s"):format(query_or_err)
    end

    local params = resolve_audio_query_params(settings)
    ok, query_or_err = apply_audio_query_params(query_or_err, params)
    if not ok then
        return false, query_or_err
    end

    local synthesis_url = ("%s/synthesis?speaker=%s"):format(base_url, speaker)
    logger.info(("VOICEVOX: requesting synthesis for '%s'"):format(text))
    local synth_ok, wav_or_err = http_post(synthesis_url, query_or_err, "application/json")
    if not synth_ok then
        return false, ("VOICEVOX synthesis failed: %s"):format(wav_or_err)
    end
    if not wav_or_err or #wav_or_err == 0 then
        return false, "VOICEVOX synthesis returned empty audio"
    end

    local filename_word = ctx.word
    if not filename_word or filename_word == "" then
        filename_word = text
    end
    return true, {
        data = base64.encode(wav_or_err),
        filename = string.format("voicevox_%s.wav", sanitize_filename(filename_word)),
    }
end

return VoiceVox
