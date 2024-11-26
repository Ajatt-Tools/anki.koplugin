local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")


--[[
-- This represents a Setting defined by the user
-- e.g. Deck name, note type, etc.
--]]
local Setting = {}
local Setting_mt = {
    __index = function(t, key) return rawget(t, key) or Setting[key] end
}

function Setting:get_value_nodefault()
    return self.profile and self.profile.data[self.id]
end

function Setting:get_value()
    return self:get_value_nodefault() or self.default
end

function Setting:update_value(new)
    self.profile:update(self.id, new)
end

function Setting:delete()
    self.profile:delete(self.id)
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
-- This represents a Profile created by the user, either the default profile
-- or anything in the ./profiles directory.
--]]
local Profile = {}

function Profile:new(user_profile, full_path, data)
    return setmetatable({
        name = user_profile,
        path = full_path,
        data = data
    }, { __index = function(t, v) return rawget(t, v) or Profile[v] end })
end

function Profile:init_settings()
    if self.settings then return end
    self.settings = LuaSettings:open(self.path)
end

function Profile:update(id, new_value)
    self:init_settings()
    self.data[id] = new_value
    self.settings:saveSetting(id, new_value)
end

function Profile:delete(id)
    self:init_settings()
    self.data[id] = nil
    self.settings:delSetting(id)
end



--[[
-- This represents a Configuration, contains settings which can come from different profiles
-- These entries could be coming from the main profile, or from the default fallback profile (if present)
--]]
local Configuration = {
    profiles = {},
    active_profile = nil, -- the currently loaded configuration
    Setting:new{ id = 'url',                required = true },
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
    Setting:new{ id = 'audio_field' },
    Setting:new{ id = 'image_field' },
    Setting:new{ id = 'translated_context_field' },
    Setting:new{ id = 'prev_sentence_count', default = '1' },
    Setting:new{ id = 'next_sentence_count', default = '1' },
}
for _,s in ipairs(Configuration) do
    Configuration[s.id] = s
end

local plugin_directory = DataStorage:getFullDataDir() .. "/plugins/anki.koplugin/"

function Configuration:load_profile(profile_name)
    if self.active_profile == profile_name then return end
    local main_profile, default_profile = assert(self.profiles[profile_name], ("Non existing profile %s!"):format(profile_name)), self.profiles['default']
    local missing = {}
    for _, opt in ipairs(self) do
        if main_profile.data[opt.id] then
            opt.profile = main_profile
            opt.value = main_profile.data[opt.id]
        elseif default_profile and default_profile.data[opt.id] then
            opt.profile = default_profile
            opt.value = default_profile.data[opt.id]
        elseif opt.required then
            table.insert(missing, opt.id)
        end
    end
    assert(#missing == 0, ("The following required configuration options are missing:\n - %s"):format(table.concat(missing, "\n - ")))
    self.active_profile = profile_name
end

function Configuration:is_active(profile_name)
    return self.active_profile == profile_name
end

function Configuration:init_profiles()
    local function init_profile(user_profile)
        if user_profile == "default" then
            local default_profiles = { "profiles/default.lua", "config.lua" }
            for _, fn in ipairs(default_profiles) do
                local full_path = plugin_directory .. fn
                local mod = loadfile(full_path)
                if mod then
                    return Profile:new(user_profile, full_path, mod())
                end
            end
            return
        end

        local full_path = plugin_directory .. "profiles/" .. user_profile
        return Profile:new(user_profile, full_path, assert(loadfile(full_path), ("Could not load profile '%s' in %s"):format(user_profile, plugin_directory))())
    end

    self.profiles.default = init_profile('default')
    for entry in lfs.dir(plugin_directory .. "/profiles") do
        if entry:match(".*%.lua$") then
            local profile = entry:gsub(".lua$", "", 1)
            self.profiles[profile] = init_profile(entry)
        end
    end
end

function Configuration:save()
    for _,p in pairs(self.profiles) do
        if p.settings then
            p.settings:close()
            p.settings = nil
        end
    end

end

Configuration:init_profiles()
return Configuration
