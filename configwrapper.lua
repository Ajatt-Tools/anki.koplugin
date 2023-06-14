local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")

local ConfigOpt = {}
local plugin_directory = DataStorage:getFullDataDir() .. "/plugins/anki.koplugin/"
local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/ankiconnect.lua")

function ConfigOpt:get_value()
    return settings:readSetting(self.id) or self.value or self.default
end

-- this is never used on ConfigOpt directly, only on MenuConfigOpt (see menubuilder)
-- TODO save options for different profiles
function ConfigOpt:update_value(new)
    return settings:saveSetting(self.id, new)
end

function ConfigOpt:new(opts)
    local new = {
        id = opts.id,
        value = nil,
        is_required = opts.required or false,
        default = opts.default
    }
    return setmetatable(new, { __index = function(t, key) return rawget(t, key) or rawget(self, key) end })
end

-- TODO we cannot use the menu when no profile is initialized yet
local Config = {
    current_profile = nil,
}

local Config_mt = {
    __index = function(t, v) return rawget(t, v) or (rawget(Config, 'current_profile') and rawget(rawget(Config, 'current_profile'), v) or nil) end
}

function Config:init(user_module, default_module)
    local options = {
        ConfigOpt:new{ id = 'url',                required = true },
        ConfigOpt:new{ id = 'deckName',           required = true },
        ConfigOpt:new{ id = 'modelName',          required = true },
        ConfigOpt:new{ id = 'word_field',         required = true },
        ConfigOpt:new{ id = 'def_field',          required = true },
        ConfigOpt:new{ id = 'dupe_scope',         default = 'deck' },
        ConfigOpt:new{ id = 'allow_dupes',        default = false },
        ConfigOpt:new{ id = 'custom_tags',        default = {} },
        ConfigOpt:new{ id = 'enabled_extensions', default = {} },
        ConfigOpt:new{ id = 'context_field' },
        ConfigOpt:new{ id = 'meta_field' },
        ConfigOpt:new{ id = 'audio_field' },
        ConfigOpt:new{ id = 'image_field' },
        ConfigOpt:new{ id = 'prev_sentence_count', default = 1 },
        ConfigOpt:new{ id = 'next_sentence_count', default = 1 },
    }
    local missing = {}
    for _,opt in ipairs(options) do
        if user_module[opt.id] then
            opt.value = user_module[opt.id]
        elseif default_module[opt.id] then
            opt.value = default_module[opt.id]
            opt.from_default = true
        else
            opt.value = opt.default
        end
        options[opt.id] = opt
        if opt.is_required and opt.value == nil then
            table.insert(missing, opt.id)
        end
    end
    assert(#missing == 0, ("ANKI.KOPLUGIN: The following required configuration options are missing: %s"):format(table.concat(missing, ", ")))
    return options
end

function Config:save()
    settings:close()
end

function Config:load_profile(user_profile)
    self.active_profile = user_profile
    local default_fn, default_profile_mod
    for _, fn in ipairs({ "profiles/default.lua", "config.lua" }) do
        local mod = loadfile(plugin_directory .. fn)
        if mod then
            default_fn = fn
            default_profile_mod = mod
        end
    end
    local default_profile = default_profile_mod and default_profile_mod() or {}
    if user_profile == "default" then
        self.current_profile = self:init(default_profile, default_profile)
    else
        local filename = ("profiles/%s.lua"):format(user_profile)
        local profile = assert(loadfile(plugin_directory .. filename))()
        self.current_profile = self:init(profile, default_profile)
    end
end

return setmetatable(Config, Config_mt)
