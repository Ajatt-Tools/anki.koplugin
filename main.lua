local ButtonDialog = require("ui/widget/buttondialog")
local CustomContextMenu = require("customcontextmenu")
local DataStorage = require("datastorage")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local MenuBuilder = require("menubuilder")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local Widget = require("ui/widget/widget")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")

local lfs = require("libs/libkoreader-lfs")
local AnkiConnect = require("ankiconnect")
local AnkiNote = require("ankinote")
local UserConfig = require("configwrapper")

local AnkiWidget = Widget:extend {
    -- this contains all the user configurable options
    -- to access them: conf.xxx:get_value()
    user_config = UserConfig:new{}
}

function AnkiWidget:show_config_widget()
    local note_count = #self.anki_connect.local_notes
    local with_custom_tags_cb = function()
        self.current_note:add_tags(self.user_config.custom_tags:get_value())
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
                callback = function() self:show_custom_context_widget() end
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
                    local buttons, to_skip = {}, { ['.'] = true, ['..'] = true }
                    for entry in lfs.dir(DataStorage:getFullDataDir() .. "/plugins/anki.koplugin/profiles") do
                        if not to_skip[entry] then
                            table.insert(buttons, { { text = entry, provider = entry, checked = self.active_profile == entry } })
                        end
                    end
                    self.profile_change_widget = RadioButtonWidget:new{
                        title_text = "Change user profile",
                        info_text = "Use a different anki configuration",
                        cancel_text = "Cancel",
                        ok_text = "Accept",
                        width_factor = 0.9,
                        radio_buttons = buttons,
                        callback = function(radio)
                            local profile = radio.provider:gsub(".lua$", "", 1)
                            local user_config = UserConfig:new { profile = profile }
                            print("new profile: ", profile, user_config)
                            self:load_profile(user_config)
                            self.profile_change_widget:onClose()
                        end,
                    }
                    UIManager:show(self.profile_change_widget)
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
    local builder = MenuBuilder:new{
        user_config = self.user_config,
        extensions = self.extensions,
        ui = self.ui
    }
    menu_items.anki_settings = { text = "Anki Settings", sub_item_table = builder:build() }
end

function AnkiWidget:load_extensions()
    self.extensions = {} -- contains filenames by numeric index, loaded modules by value
    local ext_directory = DataStorage:getFullDataDir() .. "/plugins/anki.koplugin/extensions/"

    for file in lfs.dir(ext_directory) do
        if file:match("EXT_.*%.lua") then
            table.insert(self.extensions, file)
            local ext_module = assert(loadfile(ext_directory .. file))()
            self.extensions[file] = ext_module
        end
    end
    table.sort(self.extensions)
end

function AnkiWidget:load_profile(user_profile)
    self.anki_connect = AnkiConnect:new {
        conf = user_profile,
        ui = self.ui
    }
    self:load_extensions()
    self.anki_note = AnkiNote:extend {
        ext_modules = self.extensions,
        conf = user_profile,
        ui = self.ui
    }
end

-- This function is called automatically for all tables extending from Widget
function AnkiWidget:init()
    self:load_profile(self.user_config)

    -- this holds the latest note created by the user!
    self.current_note = nil

    self.ui.menu:registerToMainMenu(self)
    self:handle_events()
    -- Insert new button in the popup dictionary to allow adding anki cards
    -- TODO disable button if lookup was not contextual
    DictQuickLookup.tweak_buttons_func = function(popup_dict, buttons)
        self.add_to_anki_btn = {
            id = "add_to_anki",
            text = _("Add to Anki"),
            font_bold = true,
            callback = function()
                self.current_note = self.anki_note:new(popup_dict)
                self.anki_connect:add_note(self.current_note)
            end,
            hold_callback = function()
                self.current_note = self.anki_note:new(popup_dict)
                self:show_config_widget()
            end,
        }
        table.insert(buttons, 1, { self.add_to_anki_btn })
    end
end

function AnkiWidget:extend_doc_settings()
    local doc = self.ui.document
    local _, file = util.splitFilePathName(doc.file)
    local file_pattern = "^%[([^%]]-)%]_(.-)_%[([^%]]-)%]%.[^%.]+"
    local f_author, f_title, f_extra = file:match(file_pattern)
    local file_properties = {
        title = f_title,
        author = f_author,
        description = f_extra,
    }
    local document_properties = doc:getProps()
    local get_prop = function(property)
        local d_p, f_p = document_properties[property], file_properties[property]
        local d_len, f_len = d_p and #d_p or 0, f_p and #f_p or 0
        -- if our custom f_p match is more exact, pick that one
        -- e.g. for PDF the title is usually the full filename
        local f_p_more_precise = d_len == 0 or d_len > f_len and f_len ~= 0
        return f_p_more_precise and f_p or d_p
    end
    local metadata = {
        title = get_prop('title'),
        author = get_prop('author') or get_prop('authors'),
        description = get_prop('description'),
        current_page = function() return self.ui.view.state.page end,
        pages = doc.info.number_of_pages or "N/A"
    }
    local metadata_mt = {
        __index = function(t, k) return rawget(t, k) or "N/A" end
    }
    self.ui.document._anki_metadata = setmetatable(metadata, metadata_mt)
end

function AnkiWidget:handle_events()
    -- these all return false so that the event goes up the chain, other widgets might wanna react to these events
    self.onCloseWidget = function()
        self.user_config:save()
    end

    self.onSuspend = function()
        self.user_config:save()
    end

    self.onNetworkConnected = function()
        self.anki_connect.wifi_connected = true
    end

    self.onNetworkDisconnected = function()
        self.anki_connect.wifi_connected = false
    end

    self.onReaderReady = function()
        self:extend_doc_settings()
    end
end

return AnkiWidget
