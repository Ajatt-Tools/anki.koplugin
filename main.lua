local ButtonDialog = require("ui/widget/buttondialog")
local CustomContextMenu = require("customcontextmenu")
local DataStorage = require("datastorage")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local MenuBuilder = require("menubuilder")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local Widget = require("ui/widget/widget")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local lfs = require("libs/libkoreader-lfs")
local AnkiConnect = require("ankiconnect")
local AnkiNote = require("ankinote")
local Configuration = require("anki_configuration")

local AnkiWidget = Widget:extend {
    known_document_profiles = LuaSettings:open(DataStorage:getSettingsDir() .. "/anki_profiles.lua"),
    anki_note = nil,
    anki_connect = nil,
}

function AnkiWidget:show_profiles_widget(opts)
    local buttons = {}
    for name, _ in pairs(Configuration.profiles) do
        table.insert(buttons, { { text = name, provider = name, checked = Configuration:is_active(name) } })
    end
    if #buttons == 0 then
        local msg = [[Failed to load profiles, there are none available, create a profile first. See the README on GitHub for more details.]]
        return UIManager:show(InfoMessage:new { text = msg, timeout = 4 })
    end

    self.profile_change_widget = RadioButtonWidget:new{
        title_text = opts.title_text,
        info_text = opts.info_text,
        cancel_text = "Cancel",
        ok_text = "Accept",
        width_factor = 0.9,
        radio_buttons = buttons,
        callback = function(radio)
            local profile = radio.provider:gsub(".lua$", "", 1)
            Configuration:load_profile(profile)
            self.profile_change_widget:onClose()
            local _, file_name = util.splitFilePathName(self.ui.document.file)
            self.known_document_profiles:saveSetting(file_name, profile)
            opts.cb()
        end,
    }
    UIManager:show(self.profile_change_widget)
end

function AnkiWidget:show_config_widget()
    local note_count = #self.anki_connect.local_notes
    local with_custom_tags_cb = function()
        self.current_note:add_tags(Configuration.custom_tags:get_value())
        self.anki_connect:add_note(self.current_note)
        self.config_widget:onClose()
    end
    self.config_widget = ButtonDialog:new {
        buttons = {
            {{ text = ("Sync (%d) offline note(s)"):format(note_count), id = "sync", enabled = note_count > 0, callback = function() self.anki_connect:sync_offline_notes() end }},
            {{ text = "Add with custom tags", id = "custom_tags", callback = with_custom_tags_cb }},
            {{
                text = "Add with custom context",
                id = "custom_context",
                enabled = self.current_note.contextual_lookup,
                callback = function() self:set_profile(function() return self:show_custom_context_widget() end) end
            }},
            {{
                text = "Delete latest note",
                id = "note_delete",
                enabled = self.anki_connect.latest_synced_note ~= nil,
                callback = function()
                    self.anki_connect:delete_latest_note()
                    self.config_widget:onClose()
                end
            }},
            {{
                text = "Change profile",
                id = "profile_change",
                callback = function()
                    self:show_profiles_widget {
                        title_text = "Change user profile",
                        info_text  = "Use a different profile",
                        cb = function() end
                    }
                end
            }}
        },
    }
    UIManager:show(self.config_widget)
end

function AnkiWidget:show_custom_context_widget()
    local function on_save_cb()
        local m = self.context_menu
        self.current_note:set_custom_context(m.prev_s_cnt, m.prev_c_cnt, m.next_s_cnt, m.next_c_cnt)
        self.anki_connect:add_note(self.current_note)
        self.context_menu:onClose()
        self.config_widget:onClose()
    end
    self.context_menu = CustomContextMenu:new{
        note = self.current_note, -- to extract context out of
        on_save_cb = on_save_cb,  -- called when saving note with updated context
    }
    UIManager:show(self.context_menu)
end

-- [[
-- This function name is not chosen at random. There are 2 places where this function is called:
--  - frontend/apps/filemanager/filemanagermenu.lua
--  - frontend/apps/reader/modules/readermenu.lua
-- These call the function `pcall(widget.addToMainMenu, widget, self.menu_items)` which lets other widgets add
-- items to the dictionary menu
-- ]]
function AnkiWidget:addToMainMenu(menu_items)
    -- TODO an option to create a new profile (based on existing ones) would be cool
    local builder = MenuBuilder:new{
        extensions = self.extensions,
        ui = self.ui
    }
    menu_items.anki_settings = { text = ("Anki Settings"), sub_item_table = builder:build() }
end

function AnkiWidget:load_extensions()
    self.extensions = {} -- contains filenames by numeric index, loaded modules by value
    local ext_directory = DataStorage:getFullDataDir() .. "/plugins/anki.koplugin/extensions/"

    for file in lfs.dir(ext_directory) do
        if file:match("^EXT_.*%.lua") then
            table.insert(self.extensions, file)
            local ext_module = assert(loadfile(ext_directory .. file))()
            self.extensions[file] = ext_module
        end
    end
    table.sort(self.extensions)
end

-- This function is called automatically for all tables extending from Widget
function AnkiWidget:init()
    self:load_extensions()
    self.anki_connect = AnkiConnect:new {
        ui = self.ui
    }
    self.anki_note = AnkiNote:extend {
        ui = self.ui,
        ext_modules = self.extensions
    }

    -- this holds the latest note created by the user!
    self.current_note = nil

    self.ui.menu:registerToMainMenu(self)
    self:handle_events()
end

function AnkiWidget:extend_doc_settings(filepath, document_properties)
    local _, file = util.splitFilePathName(filepath)
    local file_pattern = "^%[([^%]]-)%]_(.-)_%[([^%]]-)%]%.[^%.]+"
    local f_author, f_title, f_extra = file:match(file_pattern)
    local file_properties = {
        title = f_title,
        author = f_author,
        description = f_extra,
    }
    local get_prop = function(property)
        local d_p, f_p = document_properties[property], file_properties[property]
        local d_len, f_len = d_p and #d_p or 0, f_p and #f_p or 0
        -- if our custom f_p match is more exact, pick that one
        -- e.g. for PDF the title is usually the full filename
        local f_p_more_precise = d_len == 0 or d_len > f_len and f_len ~= 0
        return f_p_more_precise and f_p or d_p
    end
    local metadata = {
        title = get_prop('display_title') or get_prop('title'),
        author = get_prop('author') or get_prop('authors'),
        description = get_prop('description'),
        current_page = function() return self.ui.view.state.page end,
        language = document_properties.language,
        pages = function() return document_properties.pages or self.ui.doc_settings:readSetting("doc_pages") end
    }
    local metadata_mt = {
        __index = function(t, k) return rawget(t, k) or "N/A" end
    }
    logger.dbg("AnkiWidget:extend_doc_settings#", filepath, document_properties, metadata)
    self.ui.document._anki_metadata = setmetatable(metadata, metadata_mt)
end

function AnkiWidget:set_profile(callback)
    local _, file_name = util.splitFilePathName(self.ui.document.file)
    local user_profile = self.known_document_profiles:readSetting(file_name)
    if user_profile and Configuration.profiles[user_profile] then
        local ok, err = pcall(Configuration.load_profile, Configuration, user_profile)
        if not ok then
            return UIManager:show(InfoMessage:new { text = ("Could not load profile %s: %s"):format(user_profile, err), timeout = 4 })
        end
        return callback()
    end

    local info_text = "Choose the profile to link with this document."
    if user_profile then
        info_text = ("Document was associated with the non-existing profile '%s'.\nPlease pick a different profile to link with this document."):format(user_profile)
    end

    self:show_profiles_widget {
        title_text = "Set user profile",
        info_text = info_text,
        cb = function()
            callback()
        end
    }
end

function AnkiWidget:handle_events()
    -- these all return false so that the event goes up the chain, other widgets might wanna react to these events
    self.onCloseWidget = function()
        self.known_document_profiles:close()
        Configuration:save()
    end

    self.onSuspend = function()
        Configuration:save()
    end

    self.onNetworkConnected = function()
        self.anki_connect.wifi_connected = true
    end

    self.onNetworkDisconnected = function()
        self.anki_connect.wifi_connected = false
    end

    self.onReaderReady = function(obj, doc_settings)
        self.anki_connect:load_notes()
        -- Insert new button in the popup dictionary to allow adding anki cards
        -- TODO disable button if lookup was not contextual
        DictQuickLookup.tweak_buttons_func = function(popup_dict, buttons)
            self.add_to_anki_btn = {
                id = "add_to_anki",
                text = _("Add to Anki"),
                font_bold = true,
                callback = function()
                    self:set_profile(function()
                        self.current_note = self.anki_note:new(popup_dict)
                        self.anki_connect:add_note(self.current_note)
                    end)
                end,
                hold_callback = function()
                    self:set_profile(function()
                        self.current_note = self.anki_note:new(popup_dict)
                        self:show_config_widget()
                    end)
                end,
            }
            table.insert(buttons, 1, { self.add_to_anki_btn })
        end
        local filepath = doc_settings.data.doc_path
        self:extend_doc_settings(filepath, self.ui.bookinfo:getDocProps(filepath, doc_settings.doc_props))
    end

    self.onBookMetadataChanged = function(obj, updated_props)
        local filepath = updated_props.filepath
        self:extend_doc_settings(filepath, self.ui.bookinfo:getDocProps(filepath, updated_props.doc_props))
    end
end

function AnkiWidget:onDictButtonsReady(popup_dict, buttons)
    if self.ui and not self.ui.document then
        return
    end
    self.add_to_anki_btn = {
        id = "add_to_anki",
        text = _("Add to Anki"),
        font_bold = true,
        callback = function()
            self:set_profile(function()
                self.current_note = self.anki_note:new(popup_dict)
                self.anki_connect:add_note(self.current_note)
            end)
        end,
        hold_callback = function()
            self:set_profile(function()
                self.current_note = self.anki_note:new(popup_dict)
                self:show_config_widget()
            end)
        end,
    }
    table.insert(buttons, 1, { self.add_to_anki_btn })
end

return AnkiWidget
