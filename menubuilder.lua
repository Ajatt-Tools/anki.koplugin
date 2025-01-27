local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local util = require("util")
local List = require("lua_utils.list")
local config = require("configuration")

local general_settings = { "generic_settings", "General Settings" }
local note_settings = { "note_settings", "Anki Note Settings" }
local dictionary_settings = { "dictionary_settings", "Dictionary Settings" }

-- 'raw' entries containing the strings displayed in the menu
-- keys in the list should match the id of the underlying config option
local menu_entries = {
    {
        id = "url",
        group = general_settings,
        name = "AnkiConnect URL",
        description = "The URL anki_connect is listening on.",
    },
    {
        id = "api_key",
        group = general_settings,
        name = "AnkiConnect API key",
        description = "An optional API key to secure the connection.",
    },
     {
        id = "deckName",
        group = general_settings,
        name = "Anki Deckname",
        description = "The name of the deck the new notes should be added to.",
    },
     {
        id = "modelName",
        group = general_settings,
        name = "Anki Note Type",
        description = "The Anki note type our cards should use.",
    },
     {
        id = "allow_dupes",
        group = general_settings,
        name = "Allow Duplicates",
        description = "Allow creation of duplicate notes",
        conf_type = "bool",
    },
    {
        id = "dupe_scope",
        group = general_settings,
        name = "Duplicate Scope",
        description = "Anki Scope in which to look for duplicates",
        conf_type = "text",
    },
     {
        id = "custom_tags",
        group = general_settings,
        name = "Custom Note Tags",
        description = "Provide custom tags to be added to a note.",
        conf_type = "list",
    },
     {
        id = "word_field",
        group = note_settings,
        name = "Word Field",
        description = "Anki field for selected word.",
    },
     {
        id = "context_field",
        group = note_settings,
        name = "Context Field",
        description = "Anki field for sentence selected word occured in.",
    },
    {
        id = "translated_context_field",
        group = note_settings,
        name = "Translated Context Field",
        description = "Anki Field for the translation of the sentence the selected word occured in."
    },
     {
        id = "def_field",
        group = note_settings,
        name = "Glossary Field",
        description = "Anki field for dictionary glossary.",
    },
     {
        id = "meta_field",
        group = note_settings,
        name = "Metadata Field",
        description = "Anki field to store metadata about the current book.",
    },
     {
        id = "audio_field",
        group = note_settings,
        name = "Forvo Audio Field",
        description = "Anki field to store Forvo audio in.",
    },
     {
        id = "img_field",
        group = note_settings,
        name = "Image Field",
        description = "Anki field to store image in (used for CBZ only).",
    },
    {
        id = "enabled_extensions",
        group = general_settings,
        name = "Extensions",
        description = "Custom scripts to modify created notes.",
        conf_type = "checklist",
        default_values = function(self) return self.extensions end,
    },
    {
        id = "prev_sentence_count",
        group = note_settings,
        name = "Previous Sentence Count",
        description = "Amount of sentences to prepend to the word looked up.",
    },
    {
        id = "next_sentence_count",
        group = note_settings,
        name = "Next Sentence Count",
        description = "Amount of sentences to append to the word looked up.",
    },
    --[[ TODO: we may wanna move this to the extension and insert it back in the menu somehow
     {
        id = "dict_field_map",
        group = dictionary_settings,
        name = "Dictionary Map",
        description = "List of key/value pairs linking a dictionary with a field on the note type",
        conf_type = "map",
        default_values = function(menubuilder) return menubuilder.ui.dictionary.enabled_dict_names end,
        new_entry_value = "Note field to send the definition to",
    },
    ]]
}
for i,x in ipairs(menu_entries) do menu_entries[x.id] = i end

local MenuBuilder = {}
local MenuConfigOpt = {
    user_conf = nil,     -- the underlying ConfigOpt which this menu option configures
    menu_entry = nil,    -- pretty name for display purposes
    conf_type = "text",  -- default value for optional conf_type field
}

function MenuConfigOpt:new(o)
    local new_ = { idx = o.idx, enabled = o.enabled } -- idx is used to sort the entries so they are displayed in a consistent order
    for k,v in pairs(o.user_conf) do new_[k] = v end
    for k,v in pairs(o.menu_entry) do new_[k] = v end
    local function index(t, k)
        return rawget(t, k) or self[k]
            or o.user_conf[k] -- necessary to be able to call opt:get_value()
            or MenuBuilder[k] -- necessary to get access to ui (passed in via menubuilder)
    end
    return setmetatable(new_, { __index = index })
end

local function build_single_dialog(title, input, hint, description, callback)
    local input_dialog -- saved first so we can reference it in the callbacks
    input_dialog = InputDialog:new {
        title = title,
        input = input,
        input_hint = hint,
        description = description,
        buttons = {{
            { text = "Cancel",  id = "cancel",      callback = function() UIManager:close(input_dialog) end },
            { text = "Save",    id = "save",        callback = function() callback(input_dialog) end },
        }},
    }
    return input_dialog
end

function MenuConfigOpt:build_single_dialog()
    local callback = function(dialog)
        self:update_value(dialog:getInputText())
        UIManager:close(dialog)
    end
    local input_dialog = build_single_dialog(self.name, self:get_value_nodefault(), self.name, self.description, callback)
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function MenuConfigOpt:build_multi_dialog()
    local fields = {}
    for k,v in pairs(self:get_value_nodefault() or {}) do
        table.insert(fields, { description = k, text = v })
    end

    local multi_dialog
    multi_dialog = MultiInputDialog:new {
        title = self.name,
        description = self.description,
        fields = fields,
        buttons = {{
            { text = "Cancel",  id = "cancel",      callback = function() UIManager:close(multi_dialog) end },
            { text = "Save",    id = "save",        callback = function()
                local new = {}
                for idx,v in ipairs(multi_dialog:getFields()) do
                    new[fields[idx].description] = v
                end
                self:update_value(new)
                UIManager:close(multi_dialog)
            end},
            }
        },
    }
    UIManager:show(multi_dialog)
    multi_dialog:onShowKeyboard()
end

function MenuConfigOpt:build_list_dialog()
    local callback = function(dialog)
        local new_tags = {}
        for tag in util.gsplit(dialog:getInputText(), ",") do
            table.insert(new_tags, tag)
        end
        self:update_value(new_tags)
        UIManager:close(dialog)
    end
    local description = self.description.."\nMultiple values can be listed, separated by a comma."
    local input_dialog = build_single_dialog(self.name,table.concat(self:get_value_nodefault() or {}, ","), self.name, description, callback)
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function MenuConfigOpt:build_checklist()
    local menu_items = {}
    for _, list_item in ipairs(self:default_values()) do
        table.insert(menu_items, {
            text = list_item,
            checked_func = function() return List:new(self:get_value_nodefault() or {}):contains(list_item) end,
            hold_callback = function()
                UIManager:show(InfoMessage:new { text = self.extensions[list_item].description, timeout = nil })
            end,
            callback = function()
                local l = List:new(self:get_value_nodefault() or {})
                if l:contains(list_item) then
                    l:remove(list_item)
                else
                    l:add(list_item)
                end
                self:update_value(l:get())
            end
        })
    end
    return menu_items
end

function MenuConfigOpt:build_map_dialog()
    local function is_enabled(k)
        return (self:get_value_nodefault() or {})[k] ~= nil
    end
    -- called when enabling or updating a value in the map
    local function update_map_entry(entry_key)
        local new = self:get_value_nodefault() or {}
        local cb = function(dialog)
            new[entry_key] = dialog:getInputText()
            self:update_value(new)
            UIManager:close(dialog)
        end
        local input_dialog = build_single_dialog(entry_key, new[entry_key] or "", nil, self.new_entry_value, cb)
        UIManager:show(input_dialog)
        input_dialog:onShowKeyboard()
    end

    local sub_item_table = {}
    local values = self.default_values
    if type(values) == "function" then
        values = values(self)
    end
    for _,entry_key in ipairs(values) do
        local activate_menu = {
            text = "Activate",
            keep_menu_open = true,
            checked_func = function() return is_enabled(entry_key) end,
            callback = function()
                local new = self:get_value_nodefault() or {}
                if is_enabled(entry_key) then
                    new[entry_key] = nil
                    self:update_value(new)
                else
                    -- this is hack to make the menu toggle update
                    new[entry_key] = ""
                    self:update_value(new)
                    update_map_entry(entry_key)
                end
            end
        }
        local edit_menu = {
            text = "Edit",
            keep_menu_open = true,
            enabled_func = function() return is_enabled(entry_key) end,
            callback = function() return update_map_entry(entry_key) end,
        }
        local menu_item = {
            text = entry_key,
            checked_func = function() return is_enabled(entry_key) end,
            keep_menu_open = true,
            sub_item_table = {
                activate_menu,
                edit_menu,
            }
        }
        table.insert(sub_item_table, menu_item)
    end
    return sub_item_table
end

function MenuBuilder:new(opts)
    self.ui = opts.ui -- needed to get the enabled dictionaries
    self.extensions = opts.extensions
    return self
end

function MenuBuilder:build()
    local profiles = {}
    for name, p in pairs(config.profiles) do
        local menu_options = {}
        for _, setting in ipairs(config) do
                local user_conf = setting:copy {
                    profile = p,
                    value = p.data[setting.id]
                }
                local idx = menu_entries[setting.id]
                local entry = menu_entries[idx]
                if entry then
                    table.insert(menu_options, MenuConfigOpt:new{ user_conf = user_conf, menu_entry = entry, idx = idx, enabled = p.data[setting.id] ~= nil })
                end
        end
        table.sort(menu_options, function(a,b) return a.idx < b.idx end)

        -- contains data as expected to be passed along to main config widget
        local sub_item_table = {}
        local grouping_func = function(x) return x.group[2] end
        local group_order = { ["General Settings"] = 1, ["Anki Note Settings"] = 2, ["Dictionary Settings"] = 3 }
        for group, group_entries in pairs(List:new(menu_options):group_by(grouping_func):get()) do
            local menu_group = {}
            for _,opt in ipairs(group_entries) do
                table.insert(menu_group, self:convert_opt(opt))
            end
            table.insert(sub_item_table, { text = group, sub_item_table = menu_group })
        end
        table.sort(sub_item_table, function(a,b) return group_order[a.text] < group_order[b.text] end)
        table.insert(profiles, { text = name, sub_item_table = sub_item_table })
    end
    return profiles
end

function MenuBuilder:convert_opt(opt)
    local sub_item_entry = {
        text = opt.name,
        keep_menu_open = true,
        --enabled_func = function() return opt.enabled end,
        hold_callback = function()
            -- no point in allowing deleting of stuff in the default profile
            if opt.profile.name == "default" then return end
            UIManager:show(ConfirmBox:new{
                text = "Do you want to delete this setting from the current profile?",
                ok_callback = function()
                    opt:delete()
                end
            })
        end
    }
    if opt.conf_type == "text" then
        sub_item_entry['callback'] = function() return opt:build_single_dialog() end
    elseif opt.conf_type == "table" then
        sub_item_entry['callback'] = function() return opt:build_multi_dialog() end
    elseif opt.conf_type == "bool" then
        sub_item_entry['checked_func'] = function() return opt:get_value_nodefault() == true end
        sub_item_entry['callback'] = function() return opt:update_value(not opt:get_value_nodefault()) end
    elseif opt.conf_type == "list" then
        sub_item_entry['callback'] = function() return opt:build_list_dialog() end
    elseif opt.conf_type == "checklist" then
        sub_item_entry['sub_item_table'] = opt:build_checklist()
    elseif opt.conf_type == "map" then
        sub_item_entry['sub_item_table'] = opt:build_map_dialog()
    else -- TODO multitable
        sub_item_entry['enabled_func'] = function() return false end
    end
    return sub_item_entry
end

return MenuBuilder
