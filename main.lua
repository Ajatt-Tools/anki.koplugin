local ButtonDialog = require("ui/widget/buttondialog")
local CustomContextMenu = require("customcontextmenu")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local MenuBuilder = require("menubuilder")
local lfs = require("libs/libkoreader-lfs")
local Widget = require("ui/widget/widget")
local UIManager = require("ui/uimanager")
local util = require("util")
local u = require("lua_utils.utils")
local _ = require("gettext")

local AnkiWidget = Widget:extend {
    -- this contains all the user configurable options
    -- to access them: conf.xxx:get_value()
    user_config = require("configwrapper")
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
            {{ text = "Show parsed dictionary data", id = "preview", callback = function() self.anki_connect:display_preview(self.current_note) end }},
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
    local extensions = {}
    local enabled_extensions = u.to_set(self.user_config.enabled_extensions:get_value())
    local ext_dir = "plugins/anki.koplugin/extensions/"
    for x in lfs.dir(ext_dir) do
        if enabled_extensions[x] then
            table.insert(extensions, x)
        end
    end
    table.sort(extensions, function(a, b) return a < b end)
    local def_modifiers, note_modifiers = {}, {}
    for _, ext_fn in ipairs(extensions) do
        if ext_fn:match("definition_.*.lua") then
            local def_chunk = assert(loadfile(ext_dir .. ext_fn))
            table.insert(def_modifiers, def_chunk())
        elseif ext_fn:match("note_.*.lua") then
            local note_chunk = assert(loadfile(ext_dir .. ext_fn))
            table.insert(note_modifiers, note_chunk())
        end
    end
    self.anki_note = require("ankinote"):extend{
        definition_modifiers = def_modifiers,
        note_modifiers = note_modifiers,
        conf = self.user_config,
        ui = self.ui
    }
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
