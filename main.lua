local _ = require("gettext")
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local Widget = require("ui/widget/widget")
local util = require("util")
local MenuBuilder = require("menubuilder")

local AnkiWidget = Widget:extend {
    -- this contains all the user configurable options
    -- to access them: conf.xxx:get_value()
    user_config = require("configwrapper")
}

function AnkiWidget:show_config_widget(popup_dict)
    local note_count = #self.anki_connect.local_notes
    local sync_message = string.format(string.format("Sync (%d) offline note(s)", note_count))
    self.config_widget = ButtonDialog:new {
        buttons = {
            {{ text = "Show parsed dictionary data", id = "preview", callback = function() self.anki_connect:display_preview(popup_dict) end }},
            {{ text = sync_message, id = "sync", enabled = note_count > 0, callback = function() self.anki_connect:sync_offline_notes() end }},
            {{ text = "Add with custom tags", id = "add_custom", callback = function() self.anki_connect:add_note(popup_dict, self.user_config.custom_tags:get_value()) end }},
        }
    }
    UIManager:show(self.config_widget)
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
        ui = self.ui
    }
    menu_items.anki_settings = { text = "Anki Settings", sub_item_table = builder:build() }
end

-- This function is called automatically for all tables extending from Widget
function AnkiWidget:init()
    -- this contains all the logic for creating anki cards
    self.anki_connect = require("ankiconnect"):new {
        conf = self.user_config,
        btn = self.add_to_anki_btn,
        ui = self.ui, -- AnkiConnect helper class has no access to the UI by default, so add it here
    }

    self.ui.menu:registerToMainMenu(self)
    self:handle_events()
    -- Insert new button in the popup dictionary to allow adding anki cards
    DictQuickLookup.tweak_buttons_func = function(popup_dict, buttons)
        self.add_to_anki_btn = {
            id = "add_to_anki",
            text = _("Add to Anki"),
            font_bold = true,
            callback = function() self.anki_connect:add_note(popup_dict, {}) end,
            hold_callback = function() UIManager:show(self:show_config_widget(popup_dict)) end,
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
        self.anki_connect:save_notes()
        self.user_config:save()
    end

    self.onSuspend = function()
        self.anki_connect:save_notes()
        self.user_config:save()
    end

    self.onResume = function()
        self.anki_connect:load_notes()
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
