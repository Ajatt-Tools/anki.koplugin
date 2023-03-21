local http = require("socket.http")
local socket = require("socket")
local socketutil = require("socketutil")
local logger = require("logger")
local json = require("rapidjson")
local ltn12 = require("ltn12")
local util = require("util")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local DataStorage = require("datastorage")
local forvo = require("forvo")

local AnkiConnect = {
    settings_dir = DataStorage:getSettingsDir(),
}

function AnkiConnect:with_timeout(timeout, func)
    socketutil:set_timeout(timeout)
    local res = { func() } -- store all values returned by function
    socketutil:reset_timeout()
    return unpack(res)
end

function AnkiConnect:is_running()
    if not self.wifi_connected then
        return false, "WiFi disconnected."
    end
    local result, code, headers = self:with_timeout(1, function() return http.request(self.conf.url:get_value()) end)
    logger.dbg(string.format("AnkiConnect#is_running = code: %s, headers: %s, result: %s", code, headers, result))
    return code == 200, string.format("Unable to reach AnkiConnect.\n%s", result or code)
end

function AnkiConnect:post_request(note)
    local json_payload = json.encode(note)
    logger.dbg("AnkiConnect#post_request: building POST request with payload: ", json_payload)
    local output_sink = {} -- contains data returned by request
    local request = {
        url = self.conf.url:get_value(),
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = #json_payload,
        },
        sink = ltn12.sink.table(output_sink),
        source = ltn12.source.string(json_payload),
    }
    local code, headers, status = socket.skip(1, http.request(request))
    logger.info(string.format("AnkiConnect#post_request: code: %s, header: %s, status: %s\n", code, headers, status))
    local result = table.concat(output_sink)
    return result, self:get_request_error(code, result)
end

function AnkiConnect:get_request_error(http_return_code, request_data)
    if http_return_code ~= 200 then
        return string.format("Invalid return code %d.")
    else
        local json_err = json.decode(request_data)['error']
        -- this turns a json NULL in a userdata instance, actual error will be a string
        if type(json_err) == "string" then
            return json_err
        end
    end
end

--[[
-- @return nil if nothing went wrong, else error message
-- ]]
function AnkiConnect:set_forvo_audio(note)
    if note.params.note.audio then
        return
    end
    local word = note.params.note.fields[self.conf.word_field:get_value()]
    local ok, forvo_url = forvo.get_pronunciation_url(word)
    if not ok then
        return "Could not connect to forvo."
    end
    if forvo_url then
        note.params.note.audio = {
            url = forvo_url,
            filename = string.format("forvo_%s.ogg", word),
            fields = { self.conf.audio_field:get_value() }
        }
    end
end

function AnkiConnect:set_image_data(note)
    if note.params.note.picture then
        return -- already correct format
    end
    local img_path = note.params.note._pic
    if not img_path then
        return
    end
    note.params.note._pic = nil
    local _,filename = util.splitFilePathName(img_path)
    local img_f = io.open(img_path, 'rb')
    if img_f then
        note.params.note.picture = {
            data = forvo.base64e(img_f:read("*a")),
            filename = filename,
            fields = { self.conf.img_field:get_value() }
        }
        logger.info(string.format("added %d bytes of base64 encoded data", #note.params.note.picture.data))
        os.remove(img_path)
    end
end

function AnkiConnect:sync_offline_notes()
    local can_sync, err = self:is_running()
    if not can_sync then
        return self:show_popup(string.format("Synchronizing failed!\n%s", err), 3, true)
    end

    local request, err
    local synced, failed, errs = {}, {}, {}
    for _,note in ipairs(self.local_notes) do
        self:set_image_data(note)
        if not self:set_forvo_audio(note) then
            err = "Could not connect to forvo."
        else
            request, err = self:post_request(note)
        end
        table.insert(err and failed or synced, note)
        if err and not errs[err] then
            table.insert(errs, err)
            errs[err] = true
        end
    end
    self.local_notes = failed
    local sync_message_parts = {}
    if #synced > 0 then
        table.insert(sync_message_parts, string.format("Finished synchronizing %d note(s).", #synced))
    end
    if #failed > 0 then
        table.insert(sync_message_parts, string.format("Couldn't sync %d note(s)\nReason(s):\n - %s.", #failed, table.concat(errs, "\n - ")))
        return UIManager:show(ConfirmBox:new {
            text = table.concat(sync_message_parts, "\n") .. "\nDiscard failures?",
            ok_text = "Discard",
            cancel_text = "Keep",
            ok_callback = function()
                self.local_notes = {}
            end
        })
    end
    self:show_popup(table.concat(sync_message_parts, " "), 3, true)
end

function AnkiConnect:show_popup(text, timeout, show_always)
    -- don't reinform the user for something we already showed them
    if not (show_always or false) and self.last_message_text == text then
        return
    end
    self.last_message_text = text
    UIManager:show(InfoMessage:new { text = text, timeout = timeout })
end

--[[
-- Create and store note, either locally or in the remotely
-- @param popup_dict: the DictQuickLookup object
--]]
function AnkiConnect:add_note(popup_dict, custom_tags)
    local note = self.anki_note:create_note(popup_dict, custom_tags)

    local can_sync, err = self:is_running()
    if not can_sync then
        return self:store_offline(popup_dict, note, err)
    end

    if #self.local_notes > 0 then
        UIManager:show(ConfirmBox:new {
            text = "There are offline notes which can be synced!",
            ok_text = "Synchronize",
            cancel_text = "Cancel",
            ok_callback = function()
                self:sync_offline_notes()
            end
        })
    end
    local forvo_err = self:set_forvo_audio(note)
    if forvo_err then
        return self:store_offline(popup_dict, note, forvo_err)
    end

    self:set_image_data(note)
    local result, request_err = self:post_request(note)
    if request_err then
        return self:show_popup(string.format("Couldn't synchronize note: %s!", request_err), 3, true)
    end
    logger.info("note added succesfully: " .. result)
end

function AnkiConnect:store_offline(popup_dict, note, reason, show_always)
    -- word stored as key as well so we can have a simple duplicate check for offline notes
    if self.local_notes[popup_dict.lookupword] then
        return self:show_popup("Cannot store duplicate note offline!", 3, true)
    end
    self.local_notes[popup_dict.lookupword] = true
    table.insert(self.local_notes, note)
    return self:show_popup(string.format("%s\nStored note offline", reason), 3, show_always or false)
end

function AnkiConnect:save_notes()
    if #self.local_notes == 0 then
        return nil
    end
    logger.dbg(string.format("AnkiConnect#save_notes(): Saving %d notes to disk.", #self.local_notes))
    local f = io.open(self.notes_filename, "w")
    f:write(json.encode(self.local_notes))
    f:close()
end

function AnkiConnect:load_notes()
    local f = io.open(self.notes_filename, "r")
    if not f then
        return nil
    end
    self.local_notes = {}
    for _,note in ipairs(json.decode(f:read("*a"))) do
        table.insert(self.local_notes, note)
    end
    logger.dbg(string.format("AnkiConnect#load_notes(): Loading %d notes from disk.", #self.local_notes))
    os.remove(self.notes_filename)
end

-- [[
-- required args:
-- * url: to connect to remote AnkiConnect session
-- * conf: default configs which are used everywhere
-- * ui: necessary to get context of word in AnkiNote
-- ]]
function AnkiConnect:new(opts)
    self.conf = opts.conf
    -- reference to the button inserted on the dictionary popup window
    self.btn = opts.btn
    -- NetworkMgr func is device dependent, assume it's true when not implemented.
    self.wifi_connected = NetworkMgr.isWifiOn and NetworkMgr:isWifiOn() or true
    -- contains notes which we could not sync yet
    self.local_notes = {}
    -- path of notes stored locally when WiFi isn't available
    self.notes_filename = self.settings_dir .. "/anki.koplugin_notes.json"
    self:load_notes()
    -- helper class to create the notes
    self.anki_note = require("ankinote"):new {
        conf = opts.conf,
        ui = opts.ui,
        settings_dir = self.settings_dir,
    }
    return setmetatable({} , { __index = self })
end

return AnkiConnect
