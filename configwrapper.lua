local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")

local ConfigOpt = {}
local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/ankiconnect.lua")
function ConfigOpt:get_value()
    return settings:readSetting(self.id) or self.value or self.default
end

-- this is never used on ConfigOpt directly, only on MenuConfigOpt (see menubuilder)
function ConfigOpt:update_value(new)
    return settings:saveSetting(self.id, new)
end

function ConfigOpt:new(opts)
    local new = {
        id = opts.id,
        value = opts.module[opts.id],
        is_required = opts.required or false,
        default = opts.default
    }
    return setmetatable(new, { __index = function(t, key) return rawget(t, key) or rawget(self, key) end })
end

local Config = {}

function Config:init(user_module)
    local options = {
        ConfigOpt:new{ module = user_module, id = 'url',                required = true },
        ConfigOpt:new{ module = user_module, id = 'deckName',           required = true },
        ConfigOpt:new{ module = user_module, id = 'modelName',          required = true },
        ConfigOpt:new{ module = user_module, id = 'word_field',         required = true },
        ConfigOpt:new{ module = user_module, id = 'def_field',          required = true },
        ConfigOpt:new{ module = user_module, id = 'dupe_scope',         default = 'deck' },
        ConfigOpt:new{ module = user_module, id = 'allow_dupes',        default = false },
        ConfigOpt:new{ module = user_module, id = 'custom_tags',        default = {} },
        ConfigOpt:new{ module = user_module, id = 'enabled_extensions', default = {} },
        ConfigOpt:new{ module = user_module, id = 'context_field' },
        ConfigOpt:new{ module = user_module, id = 'meta_field' },
        ConfigOpt:new{ module = user_module, id = 'audio_field' },
        ConfigOpt:new{ module = user_module, id = 'image_field' },
    }

    local missing = {}
    for _,opt in ipairs(options) do
        options[opt.id] = opt
        if opt.is_required and opt:get_value() == nil then
            table.insert(missing, opt.id)
        end
    end
    assert(#missing == 0, ("ANKI.KOPLUGIN: The following required configuration options are missing: %s"):format(table.concat(missing, ", ")))
    return options
end

function Config:save()
    settings:close()
end

function Config:new(opts)
    local config_mod = opts.profile and ("profiles/%s"):format(opts.profile) or "config"
    local config = require(config_mod)
    local options = self:init(config)
    local c_mt = {
        __index = function(t, k) return rawget(t, k) or self[k] end
    }
    return setmetatable(options, c_mt)
end

return Config
