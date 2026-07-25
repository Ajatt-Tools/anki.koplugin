local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local AudioDrivers = {
    list = {},   -- ordered list of driver modules
    by_id = {},  -- id -> driver module
}

function AudioDrivers:load()
    self.list = {}
    self.by_id = {}
    local directory = DataStorage:getFullDataDir() .. "/plugins/anki.koplugin/audio_drivers/"

    if not lfs.attributes(directory, "mode") then
        logger.warn("AudioDrivers: directory not found:", directory)
        return self
    end

    local files = {}
    for file in lfs.dir(directory) do
        if file:match("%.lua$") and file ~= "README.md" then
            table.insert(files, file)
        end
    end
    table.sort(files)

    for _, file in ipairs(files) do
        local path = directory .. file
        local ok, driver_or_err = pcall(function()
            return assert(loadfile(path))()
        end)
        if not ok then
            logger.err(("AudioDrivers: failed to load %s: %s"):format(file, driver_or_err))
        elseif type(driver_or_err) ~= "table" or not driver_or_err.id then
            logger.err(("AudioDrivers: %s did not return a driver with an id"):format(file))
        elseif type(driver_or_err.get_audio) ~= "function" then
            logger.err(("AudioDrivers: %s missing get_audio method"):format(file))
        elseif self.by_id[driver_or_err.id] then
            logger.err(("AudioDrivers: duplicate driver id '%s' in %s"):format(driver_or_err.id, file))
        else
            table.insert(self.list, driver_or_err)
            self.by_id[driver_or_err.id] = driver_or_err
            logger.info(("AudioDrivers: loaded '%s' from %s"):format(driver_or_err.id, file))
        end
    end
    return self
end

function AudioDrivers:get(id)
    return self.by_id[id]
end

function AudioDrivers:choices()
    local choices = {
        { id = "none", name = "None", description = "Do not attach audio to the note." },
    }
    for _, driver in ipairs(self.list) do
        table.insert(choices, {
            id = driver.id,
            name = driver.name or driver.id,
            description = driver.description,
        })
    end
    return choices
end

return AudioDrivers
