local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local user_conf = require("config")

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
        value = user_conf[opts.id],
        is_required = opts.required or false,
        default = opts.default
    }
    return setmetatable(new, { __index = function(t, key) return rawget(t, key) or rawget(self, key) end })
end

local Config = {
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
for _,opt in ipairs(Config) do
    Config[opt.id] = opt
    if opt.is_required and opt:get_value() == nil then
        table.insert(missing, opt.id)
    end
end
assert(#missing == 0, ("ANKI.KOPLUGIN: The following required configuration options are missing: %s"):format(table.concat(missing, ", ")))

function Config:save()
    settings:close()
end

return Config
