local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local user_conf = require("config")

local ConfigOpt = {
    id = nil,    -- id matching the key in config.lua
    value = nil, -- value matching the value in config.lua
}
local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/ankiconnect.lua")
function ConfigOpt:get_value()
    return settings:readSetting(self.id) or self.value
end

-- this is never used on ConfigOpt directly, only on MenuConfigOpt (see menubuilder)
function ConfigOpt:update_value(new)
    return settings:saveSetting(self.id, new)
end

function ConfigOpt:new(opt)
    return setmetatable(opt, { __index = function(t, key) return rawget(t, key) or rawget(self, key) end })
end

local Config = {}
for id,value in pairs(user_conf) do
    Config[id] = ConfigOpt:new{id = id, value = value}
end

function Config:save()
    settings:close()
end

return Config
