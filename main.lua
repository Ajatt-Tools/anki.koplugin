local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local CustomContextMenu = require("customcontextmenu")
local DataStorage = require("datastorage")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local LuaSettings = require("luasettings")
local MenuBuilder = require("menubuilder")
local NetworkMgr = require("ui/network/manager")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local lfs = require("libs/libkoreader-lfs")
local AnkiConnect = require("ankiconnect")
local AnkiNote = require("ankinote")
local AudioDrivers = require("audio_drivers")
local Configuration = require("anki_configuration")

local AnkiWidget = WidgetContainer:extend {
    name = "anki_widget",
    known_document_profiles = LuaSettings:open(DataStorage:getSettingsDir() .. "/anki_profiles.lua"),
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

function AnkiWidget:set_add_to_anki_button_text(text, opts)
    opts = opts or {}
    local popup_dict = self.popup_dict
    if not popup_dict or not popup_dict.button_table then
        return
    end
    local btn = popup_dict.button_table:getButtonById("add_to_anki")
    if not btn then
        return
    end
    btn:setText(text, btn.width)
    if opts.enable == true then
        btn:enable()
    elseif opts.enable == false then
        btn:disable()
    end
    btn:refresh()
    if opts.repaint then
        UIManager:forceRePaint()
    end
end

function AnkiWidget:add_current_note()
    self:set_add_to_anki_button_text(_("Adding..."), { enable = false, repaint = true })
    local result = AnkiConnect:add_note(self.current_note)
    if result == true then
        self:set_add_to_anki_button_text(_("Added to Anki"), { enable = true, repaint = true })
    else
        -- Failure (and offline store): restore default label; errors already show a popup.
        self:set_add_to_anki_button_text(_("Add to Anki"), { enable = true, repaint = true })
    end
    return result
end

function AnkiWidget:make_add_to_anki_button(popup_dict)
    return {
        id = "add_to_anki",
        text = _("Add to Anki"),
        font_bold = true,
        callback = function()
            self:set_profile(function()
                self:check_conn(function()
                    self.popup_dict = popup_dict
                    self.current_note = AnkiNote:new(popup_dict)
                    self:add_current_note()
                end)
            end)
        end,
        hold_callback = function()
            self:set_profile(function()
                self:check_conn(function()
                    self.popup_dict = popup_dict
                    self.current_note = AnkiNote:new(popup_dict)
                    self:show_config_widget()
                end)
            end)
        end,
    }
end

function AnkiWidget:show_config_widget()
    local with_custom_tags_cb = function()
        self.current_note:add_tags(Configuration.custom_tags:get_value())
        self.config_widget:onClose()
        self:add_current_note()
    end
    self.config_widget = ButtonDialog:new {
        buttons = {
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
                enabled = AnkiConnect.latest_synced_note ~= nil,
                callback = function()
                    AnkiConnect:delete_latest_note()
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
        self.context_menu:onClose()
        self.config_widget:onClose()
        self:add_current_note()
    end
    self.context_menu = CustomContextMenu:new{
        note = self.current_note, -- to extract context out of
        on_save_cb = on_save_cb,  -- called when saving note with updated context
    }
    UIManager:show(self.context_menu)
end

function AnkiWidget:show_connection_widget()
    self.conn_settings = MultiInputDialog:new{
        title = _("Connection Settings"),
        fields = {
            {
                text = Configuration.url:get_value_nodefault() or '',
                description = "The anki-connect URL.",
                hint = "http://192.168.1.xxx:8765"
            },
            {
                text = Configuration.api_key:get_value_nodefault() or '',
                description = "The (optional) anki-connect API key.",
                hint = "You can leave me blank"
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.conn_settings)
                    end
                },
                {
                    text = _("Test"),
                    callback = function()
                        local function err(msg) return UIManager:show(InfoMessage:new { text = msg, timeout = 4 }) end
                        local fields = self.conn_settings:getFields()
                        local new_url, is_https = fields[1], false
                        local new_api_key = fields[2]
                        if #new_url == 0 then return UIManager:show(InfoMessage:new { text = "Empty URL", timeout = 4 }) end
                        new_url, is_https = AnkiConnect.sanitize_url(new_url)

                        local function when_connected()
                            local result, error = AnkiConnect:is_running(new_url)
                            if error then
                                local extra_info
                                if is_https then
                                    extra_info = "\nYou probably want to use http instead of https."
                                end
                                return err(("Failed to connect to '%s': %s%s"):format(new_url, error, extra_info or ''))
                            end
                            if result.permission ~= "granted" then
                                return err("Permission not granted")
                            elseif result.requireApikey then
                                if #new_api_key == 0 then
                                    return err("API key required but not provided!")
                                end
                                result, error = AnkiConnect:get_decknames(new_url, new_api_key)
                                if error then
                                    return err(("Could not connect: %s"):format(error))
                                end
                            end
                            return UIManager:show(InfoMessage:new { text = "Connection succesful!", timeout = 4 })
                        end

                        if NetworkMgr:willRerunWhenOnline(function() when_connected() end) then return end
                        when_connected()
                    end
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = self.conn_settings:getFields()
                        local new_url = fields[1]
                        if #new_url == 0 then
                            Configuration.url:delete()
                        elseif new_url ~= Configuration.url:get_value_nodefault() then
                            Configuration.url:update_value(AnkiConnect.sanitize_url(new_url))
                        end
                        local new_api_key = fields[2]
                        if new_api_key ~= Configuration.api_key:get_value_nodefault() then
                            Configuration.api_key:update_value(new_api_key)
                        end
                        UIManager:close(self.conn_settings)
                    end
                },
            },
        },
    }
    UIManager:show(self.conn_settings)
    self.conn_settings:onShowKeyboard()
end

-- [[
-- This function name is not chosen at random. There are 2 places where this function is called:
--  - frontend/apps/filemanager/filemanagermenu.lua
--  - frontend/apps/reader/modules/readermenu.lua
-- These call the function `pcall(widget.addToMainMenu, widget, self.menu_items)` which lets other widgets add
-- items to the dictionary menu
-- ]]
function AnkiWidget:addToMainMenu(menu_items)
    menu_items.anki_settings = { text = ("Anki Settings"), sorting_hint = "search_settings", sub_item_table = self:buildSettings() }
end

function AnkiWidget:buildSettings()
    local builder = MenuBuilder:new{
        extensions = self.extensions,
        audio_drivers = AudioDrivers,
        ui = self.ui
    }
    local function make_new_profile(start_data)
        return function()
            local input_dialog = MenuBuilder.build_single_dialog("Profile name", "", "", "Choose a name for the profile", function(obj)
                local profile = obj:getInputText()
                if Configuration.profiles[profile] then
                    return UIManager:show(InfoMessage:new { text = "Profile already exists! Pick another name.", timeout = 4 })
                end
                Configuration.profiles[profile] = LuaSettings:open(DataStorage:getFullDataDir() .. "/plugins/anki.koplugin/profiles/" .. profile .. ".lua")
                Configuration.profiles[profile].data = start_data
                if self.ui.menu.menu_items.anki_settings then
                    self.ui.menu.menu_items.anki_settings.sub_item_table = self:buildSettings()
                else
                    -- TODO this can be removed again after a while, it prevents crashes for old users that still have the patch enabled.
                    UIManager:show(InfoMessage:new { text = "Please disable the custom userpatch. Anki Settings are now available by default under Search (looking glass icon) - Settings", timeout = 20 })
                end
                UIManager:close(obj)
            end)
            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end
    end
    local profile_names = {}
    for pname,_ in pairs(Configuration.profiles) do table.insert(profile_names, {
        text = pname,
        callback = make_new_profile(util.tableDeepCopy(Configuration.profiles[pname].data))
    })
    end
    local profiles = builder:build()
    local has_profiles = #profiles > 0
    for _, menu_item in ipairs(profiles) do
        menu_item.hold_callback = function()
            UIManager:show(ConfirmBox:new{
                text = "Do you want to delete this profile? This cannot be undone.",
                ok_callback = function()
                    local profile_name = menu_item.text
                    Configuration.profiles[profile_name]:purge()
                    Configuration.profiles[profile_name] = nil
                    if self.ui.menu.menu_items.anki_settings then
                        self.ui.menu.menu_items.anki_settings.sub_item_table = self:buildSettings()
                    else
                        -- TODO this can be removed again after a while, it prevents crashes for old users that still have the patch enabled.
                        UIManager:show(InfoMessage:new { text = "Please disable the custom userpatch. Anki Settings are now available by default under Search (looking glass icon) - Settings", timeout = 20 })
                    end
                    if self.ui.menu.onTapCloseMenu then self.ui.menu:onTapCloseMenu()
                    elseif self.ui.menu.onCloseFileManagerMenu then self.ui.menu:onCloseFileManagerMenu() end
                end
            })
        end
    end
    table.insert(profiles, #profiles+1, { text = "Clone profile from ...", enabled_func = function() return has_profiles end, sub_item_table = profile_names })
    table.insert(profiles, #profiles+1, { text = "Create new profile", callback = make_new_profile({}) })
    return {
        { text = ("Edit profiles"), sub_item_table = profiles },
        { text = ("anki-connect settings"), keep_menu_open = true, callback = function() self:show_connection_widget() end },
        {
            text_func = function() return ("Sync (%d) offline note(s)"):format(#AnkiConnect.local_notes) end,
            enabled_func = function() return #AnkiConnect.local_notes > 0 end,
            callback = function() self:check_conn(function() AnkiConnect:sync_offline_notes() end) end
        },
    }
end

function AnkiWidget:check_conn(callback)
    local url = Configuration.url:get_value()
    logger.info("url is:", url)
    if url == nil or #url == 0 then
        return UIManager:show(ConfirmBox:new{
            text = "The anki-connect url does not seem to be configured yet, do you want to open the settings window?",
            ok_callback = function()
                -- TODO maybe this could take the callback and try it again on save
                return self:show_connection_widget()
            end
        })
    end
    callback()
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
    AudioDrivers:load()
    -- allow propagating events to ankiconnect, we handle wifi related stuff in there
    table.insert(self, AnkiConnect)
    AnkiConnect:load_notes()
    AnkiNote:extend {
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
        current_page = function()
            return self.ui.view.state.page
                or self.ui:getCurrentPage()
                or -1
        end,
        language = document_properties.language,
        pages = function()
            return document_properties.pages
                or self.ui.doc_settings:readSetting("doc_pages")
                or self.ui.document:getPageCount()
                or -1
        end
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

    self.onReaderReady = function(obj, doc_settings)
        -- Insert new button in the popup dictionary to allow adding anki cards
        -- TODO disable button if lookup was not contextual
        DictQuickLookup.tweak_buttons_func = function(popup_dict, buttons)
            self.add_to_anki_btn = self:make_add_to_anki_button(popup_dict)
            table.insert(buttons, 1, { self.add_to_anki_btn })
        end
        local filepath = doc_settings.data.doc_path
        self:extend_doc_settings(filepath, self.ui.doc_props)
    end

    self.onBookMetadataChanged = function(obj, updated_props)
        -- no need to try doing this when a doc was modified from the file browser, we'll redo this on doc load
        if not self.ui.document then return end
        local filepath = updated_props.filepath
        self:extend_doc_settings(filepath, updated_props.doc_props)
    end
end

function AnkiWidget:onDictButtonsReady(popup_dict, buttons)
    if self.ui and not self.ui.document then
        return
    end
    if self.ui.vocabbuilder and UIManager:isWidgetShown(self.ui.vocabbuilder.widget) then
        return
    end
    self.add_to_anki_btn = self:make_add_to_anki_button(popup_dict)
    table.insert(buttons, 1, { self.add_to_anki_btn })
end

return AnkiWidget
