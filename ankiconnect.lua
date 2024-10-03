local http = require("socket.http")
local socket = require("socket")
local socketutil = require("socketutil")
local logger = require("logger")
local json = require("rapidjson")
local ltn12 = require("ltn12")
local util = require("util")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local DataStorage = require("datastorage")
local forvo = require("forvo")
local u = require("lua_utils/utils")

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

function AnkiConnect:post_request(json_payload)
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
        return string.format("Invalid return code: %s.", http_return_code)
    else
        local json_err = json.decode(request_data)['error']
        -- this turns a json NULL in a userdata instance, actual error will be a string
        if type(json_err) == "string" then
            return json_err
        end
    end
end

function AnkiConnect:set_forvo_audio(word, language)
    local field = self.conf.audio_field:get_value()
    if not field then
        return true
    end
    local ok, forvo_url = forvo.get_pronunciation_url(word, language)
    if not ok then
        return false, "Could not connect to forvo."
    end
    return true, forvo_url and {
        url = forvo_url,
        filename = string.format("forvo_%s.ogg", word),
        fields = { field }
    } or nil
end

function AnkiConnect:set_image_data(img_path)
    local field = self.conf.image_field:get_value()
    if not field then
        return true
    end
    if not img_path then
        return true
    end
    local _,filename = util.splitFilePathName(img_path)
    local img_f = io.open(img_path, 'rb')
    if not img_f then
        return true
    end
    local data = forvo.base64e(img_f:read("*a"))
    logger.info(("added %d bytes of base64 encoded data"):format(#data))
    os.remove(img_path)
    return true, {
        data = data,
        filename = filename,
        fields = { field }
    }
end

function AnkiConnect:sync_offline_notes()
    local can_sync, err = self:is_running()
    if not can_sync then
        return self:show_popup(string.format("Synchronizing failed!\n%s", err), 3, true)
    end

    local synced, failed, errs = {}, {}, u.defaultdict(0)
    for _,note in ipairs(self.local_notes) do
        local modifiers = note.params.note._field_callbacks
        local mod_error = nil
        for param, mod in pairs(modifiers) do
            local _, ok, result_or_err = pcall(self[mod.func], self, unpack(mod.args))
            if not ok then
                mod_error = result_or_err
                errs[mod_error] = errs[mod_error] + 1
                break
            end
            note.params.note[param] = result_or_err
        end
        if not mod_error then
            -- we have to remove the _field_callbacks field before saving the note so anki-connect doesn't complain
            note.params.note._field_callbacks = nil
            local _, request_err = self:post_request(json.encode(note))
            if request_err then
                mod_error = request_err
                errs[mod_error] = errs[mod_error] + 1
                -- if it failed we want reinsert the _field_callbacks field
                note.params.note._field_callbacks = modifiers
            end
        end
        table.insert(mod_error and failed or synced, note)
    end
    self.local_notes = failed
    local failed_as_json = {}
    for _,note in ipairs(failed) do
        table.insert(failed_as_json, json.encode(note))
        local id = note.params.note.fields[self.conf.word_field:get_value()]
        if id then
            self.local_notes[id] = true
        end
    end
    -- called even when there's no failed notes, this way it also gets rid of the notes which we managed to sync, no need to keep those around
    u.open_file(self.notes_filename, 'w', function(f) f:write(table.concat(failed_as_json, '\n')) end)
    local sync_message_parts = {}
    if #synced > 0 then
        -- if any notes were synced succesfully, reset the latest added note (since it's not actually latest anymore)
        -- no point in saving the actual latest synced note, since the user won't know which note that was anyway
        self.latest_synced_note = nil
        table.insert(sync_message_parts, ("Finished synchronizing %d note(s)."):format(#synced))
    end
    if #failed > 0 then
        table.insert(sync_message_parts, ("%d note(s) failed to sync:"):format(#failed))
        for error_msg, count in pairs(errs) do
            table.insert(sync_message_parts, (" - %s (%d)"):format(error_msg, count))
        end
        return UIManager:show(ConfirmBox:new {
            text = table.concat(sync_message_parts, "\n"),
            icon = "notice-warning",
            font = Font:getFace("smallinfofont", 9),
            ok_text = "Discard failures",
            cancel_text = "Keep",
            ok_callback = function()
                os.remove(self.notes_filename)
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
    logger.info(("Displaying popup with message: '%s'"):format(text))
    self.last_message_text = text
    UIManager:show(InfoMessage:new { text = text, timeout = timeout })
end

function AnkiConnect:delete_latest_note()
    local latest = self.latest_synced_note
    if not latest then
        return
    end
    if latest.state == "online" then
        local can_sync, err = self:is_running()
        if not can_sync then
            return self:show_popup(("Could not delete synced note: %s"):format(err), 3, true)
        end
        -- don't use rapidjson, the anki note ids are 64bit integers, they are turned into different numbers by the json library
        -- presumably because 32 vs 64 bit architecture
        local delete_request = ([[{"action": "deleteNotes", "version": 6, "params": {"notes": [%d]} }]]):format(latest.id)
        local _, err = self:post_request(delete_request)
        if err then
            return self:show_popup(("Couldn't delete note: %s!"):format(err), 3, true)
        end
        self:show_popup(("Removed note (id: %s)"):format(latest.id), 3, true)
    else
        table.remove(self.local_notes, #self.local_notes)
        self.local_notes[latest.id] = nil
        local entries_on_disk = {}
        u.open_file(self.notes_filename, 'r', function(f)
            for line in f:lines() do
                table.insert(entries_on_disk, line)
            end
        end)
        table.remove(entries_on_disk)
        u.open_file(self.notes_filename, 'w', function(f)
            f:write(table.concat(entries_on_disk, '\n'))
            if #entries_on_disk > 0 then
                f:write('\n')
            end
        end)
        self:show_popup(("Removed note (word: %s)"):format(latest.id), 3, true)
    end
    self.latest_synced_note = nil
end

function AnkiConnect:add_note(anki_note)
    local ok, note = pcall(anki_note.build, anki_note)
    if not ok then
        return self:show_popup(string.format("Error while creating note:\n\n%s", note), 10, true)
    end

    local can_sync, err = self:is_running()
    if not can_sync then
        return self:store_offline(note, err)
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
    for param, mod in pairs(note.params.note._field_callbacks) do
        local _, ok, result_or_err = pcall(self[mod.func], self, unpack(mod.args))
        if not ok then
            return self:store_offline(note, result_or_err)
        end
        note.params.note[param] = result_or_err
    end
    note.params.note._field_callbacks = nil

    local result, request_err = self:post_request(json.encode(note))
    if request_err then
        return self:show_popup(string.format("Error while synchronizing note:\n\n%s", request_err), 3, true)
    end
    self.latest_synced_note = { state = "online", id = json.decode(result).result }
    self.last_message_text = "" -- if we manage to sync once, a following error should be shown again
    logger.info("note added succesfully: " .. result)
end

function AnkiConnect:store_offline(note, reason, show_always)
    -- word stored as key as well so we can have a simple duplicate check for offline notes
    local id = note.params.note.fields[self.conf.word_field:get_value()]
    if self.local_notes[id] then
        return self:show_popup("Cannot store duplicate note offline!", 6, true)
    end
    self.local_notes[id] = true
    table.insert(self.local_notes, note)
    u.open_file(self.notes_filename, 'a', function(f) f:write(json.encode(note) .. '\n') end)
    self.latest_synced_note = { state = "offline", id = id }
    return self:show_popup(string.format("%s\nStored note offline", reason), 3, show_always or false)
end

function AnkiConnect:load_notes()
    u.open_file(self.notes_filename, 'r', function(f)
        for note_json in f:lines() do
            local note, err = json.decode(note_json)
            assert(note, ("Could not parse note '%s': %s"):format(note_json, err))
            table.insert(self.local_notes, note)
            -- store unique identifier in local_notes tabel for basic duplicates check
            local note_id = note.params.note.fields[self.conf.word_field:get_value()]
            -- when the user creates notes with different settings then the current word_field might not be present
            -- on all locally stored notes, we'll just not have the duplicates check for these
            if note_id then
                self.local_notes[note_id] = true
            end
        end
    end)
    logger.dbg(string.format("Loaded %d notes from disk.", #self.local_notes))
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
    return setmetatable({} , { __index = self })
end

return AnkiConnect
