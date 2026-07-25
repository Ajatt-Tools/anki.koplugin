local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")


--[[
-- This represents a Setting defined by the user
-- e.g. Deck name, note type, etc.
--]]
local Setting = {
    active_luasettings = nil,  -- currently loaded profile
    default_luasettings = nil, -- default profile (if existing)
}
local Setting_mt = {
    __index = function(t, key) return rawget(t, key) or Setting[key] end
}

function Setting:get_value_nodefault()
    for _, ls in ipairs({self.active_luasettings, self.default_luasettings}) do
        if ls and ls:has(self.id) then
            return ls:readSetting(self.id)
        end
    end
end

function Setting:get_value()
    return self:get_value_nodefault() or self.default
end

-- updating/deleting settings only happens in the menu, where there is just one luasettings file in play, always the active one
function Setting:update_value(new)
    if type(new) == "string" and #new == 0 then
        self.active_luasettings:delSetting(self.id)
    else
        self.active_luasettings:saveSetting(self.id, new)
    end
end

function Setting:delete()
    -- this can be nil when deleting a setting that was never set
    self.active_luasettings:delSetting(self.id)
end

function Setting:new(opts)
    return setmetatable(opts, Setting_mt)
end

function Setting:copy(opts)
    local new = {}
    for k,v in pairs(self) do
        new[k] = v
    end
    for k,v in pairs(opts) do
        new[k] = v
    end
    return setmetatable(new, Setting_mt)
end



--[[
-- This represents a Configuration, contains settings which can come from different profiles
-- These entries could be coming from the main profile, or from the default fallback profile (if present)
--]]
local Configuration = {
    profiles = {},
    active_luasettings = nil, -- the currently loaded configuration
    url = Setting:new{ id = 'url',          required = true },
    api_key = Setting:new{ id = 'api_key',  required = false },
    Setting:new{ id = 'deckName',           required = true },
    Setting:new{ id = 'modelName',          required = true },
    Setting:new{ id = 'word_field',         required = true },
    Setting:new{ id = 'def_field',          required = true },
    Setting:new{ id = 'dupe_scope',         default = 'deck' },
    Setting:new{ id = 'allow_dupes',        default = false },
    Setting:new{ id = 'custom_tags',        default = {} },
    Setting:new{ id = 'enabled_extensions', default = {} },
    Setting:new{ id = 'context_field' },
    Setting:new{ id = 'meta_field' },
    Setting:new{ id = 'audio_field' }, -- legacy alias for word_audio_field
    Setting:new{ id = 'word_audio_field' },
    Setting:new{ id = 'sentence_audio_field' },
    Setting:new{ id = 'word_audio_driver', default = 'forvo' },
    Setting:new{ id = 'word_audio_driver_settings', default = {} },
    Setting:new{ id = 'sentence_audio_driver', default = 'none' },
    Setting:new{ id = 'sentence_audio_driver_settings', default = {} },
    Setting:new{ id = 'image_field' },
    Setting:new{ id = 'translated_context_field' },
    Setting:new{ id = 'prev_sentence_count', default = '1' },
    Setting:new{ id = 'next_sentence_count', default = '1' },
}
for _,s in ipairs(Configuration) do
    Configuration[s.id] = s
end

--- Word audio Anki field. Prefers word_audio_field; falls back to legacy audio_field.
function Configuration:get_word_audio_field()
    local field = self.word_audio_field:get_value()
    if field and field ~= "" then
        return field
    end
    return self.audio_field:get_value()
end

--- Word audio driver id.
function Configuration:get_word_audio_driver()
    return self.word_audio_driver:get_value()
end

--- Sentence audio driver id.
function Configuration:get_sentence_audio_driver()
    return self.sentence_audio_driver:get_value()
end

--- Return the settings table for a given audio driver id.
-- @param driver_id string
-- @param kind "word"|"sentence" (default "word")
function Configuration:get_audio_driver_settings(driver_id, kind)
    kind = kind or "word"
    local setting = kind == "sentence" and self.sentence_audio_driver_settings or self.word_audio_driver_settings
    local all = setting:get_value() or {}
    return all[driver_id] or {}
end

local plugin_directory = DataStorage:getFullDataDir() .. "/plugins/anki.koplugin/"

function Configuration:load_profile(profile_name)
    if self.active_luasettings == profile_name then return end
    local main_profile, default_luasettings = assert(self.profiles[profile_name], ("Non existing profile %s!"):format(profile_name)), self.profiles['default']
    local missing = {}
    for _, opt in ipairs(self) do
        opt.active_luasettings = main_profile
        opt.default_luasettings = default_luasettings
        if main_profile.data[opt.id] then
            opt.value = main_profile.data[opt.id]
        elseif default_luasettings and default_luasettings.data[opt.id] then
            opt.value = default_luasettings.data[opt.id]
        elseif opt.required then
            table.insert(missing, opt.id)
        end
    end
    assert(#missing == 0, ("The following required configuration options are missing:\n - %s"):format(table.concat(missing, "\n - ")))
    self.active_luasettings = profile_name
end

function Configuration:is_active(profile_name)
    return self.active_luasettings == profile_name
end

function Configuration:init_profiles()
    local function init_profile(user_profile)
        if user_profile == "default" then
            local default_luasettingss = { "profiles/default.lua", "config.lua" }
            for _, fn in ipairs(default_luasettingss) do
                local full_path = plugin_directory .. fn
                local mod = loadfile(full_path)
                if mod then
                    return LuaSettings:open(full_path)
                end
            end
            return
        end

        local full_path = plugin_directory .. "profiles/" .. user_profile
        local mod, err = loadfile(full_path)
        if not mod then
            error(("Could not load profile '%s' in %s: %s"):format(user_profile, plugin_directory, err))
        end
        return LuaSettings:open(full_path)
    end

    self.profiles.default = init_profile('default')
    for entry in lfs.dir(plugin_directory .. "/profiles") do
        if entry:match(".*%.lua$") then
            local profile = entry:gsub(".lua$", "", 1)
            self.profiles[profile] = init_profile(entry)
        end
    end
    -- this is horrible
    local anki_connect_path = DataStorage:getSettingsDir() .. "/ankiconnect.lua"
    self.anki_connect_luasettings = LuaSettings:open(anki_connect_path)
    self.url.active_luasettings = self.anki_connect_luasettings
    self.api_key.active_luasettings = self.anki_connect_luasettings
end

function Configuration:save()
    for _,p in pairs(self.profiles) do
        p:close()
    end
    self.anki_connect_luasettings:close()
end

Configuration:init_profiles()
return Configuration
