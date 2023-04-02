local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local util = require("util")

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
        description = "Extra tags which can optionally be added when creating a Note",
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
        id = "p_a_num",
        group = note_settings,
        name = "Pitch Downstep Field",
        description = "Anki field to store Pitch Downstep data in.",
    },
     {
        id = "p_a_field",
        group = note_settings,
        name = "Pitch Accent Field",
        description = "Anki field to store Pitch Accent data in.",
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
        id = "kana_pattern",
        group = dictionary_settings,
        name = "Kana Pattern",
        description = "lua Pattern which returns the Kana reading of a dictionary word",
        conf_type = "multitable",
    },
     {
        id = "kanji_pattern",
        group = dictionary_settings,
        name = "Kanji Pattern",
        description = "lua Pattern which returns the Kanji reading(s) of a dictionary word",
        conf_type = "multitable",
    },
     {
        id = "dict_field_map",
        group = dictionary_settings,
        name = "Dictionary Map",
        description = "List of key/value pairs linking a dictionary with a field on the note type",
        conf_type = "map",
    },
}
for i,x in ipairs(menu_entries) do menu_entries[x.id] = i end

local MenuConfigOpt = {
    user_conf = nil,     -- the underlying ConfigOpt which this menu option configures
    menu_entry = nil,    -- pretty name for display purposes
    conf_type = "text",  -- default value for optional conf_type field
}

function MenuConfigOpt:new(o)
    local new_ = { idx = o.idx } -- idx is used to sort the entries so they are displayed in a consistent order
    for k,v in pairs(o.user_conf) do new_[k] = v end
    for k,v in pairs(o.menu_entry) do new_[k] = v end
    return setmetatable(new_, { __index = function(t, k) return rawget(t, k) or self[k] or o.user_conf[k] end })
end

function MenuConfigOpt:build_single_dialog()
    local input_dialog -- saved first so we can reference it in the callbacks
    input_dialog = InputDialog:new {
        title = self.name,
        input = self:get_value(),
        input_hint = self.name,
        description = self.description,
        buttons = {{
            { text = "Cancel",  id = "cancel",      callback = function() UIManager:close(input_dialog) end },
            { text = "Save",    id = "save",        callback = function()
                self:update_value(input_dialog:getInputText())
                UIManager:close(input_dialog)
            end },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function MenuConfigOpt:build_multi_dialog()
    local fields = {}
    for k,v in pairs(self:get_value()) do
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
    local input_dialog
    input_dialog = InputDialog:new {
        title = self.name,
        -- items in list are concatenated, separated by comma's
        input = table.concat(self:get_value(), ","),
        input_hint = self.name,
        description = self.description .. "\nMultiple tags can be given, separated by commas.",
        buttons = {{
            { text = "Cancel",  id = "cancel",      callback = function() UIManager:close(input_dialog) end },
            { text = "Save",    id = "save",        callback = function()
                local new_tags = {}
                for tag in util.gsplit(input_dialog:getInputText(), ",") do
                    table.insert(new_tags, tag)
                end
                self:update_value(new_tags)
                UIManager:close(input_dialog)
            end },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

local MenuBuilder = {}

function MenuBuilder:convert_user_config(user_config)
    local menu_options = {}
    for id, user_conf in pairs(user_config) do
        local idx = menu_entries[id]
        local entry = menu_entries[idx]
        if entry then
            table.insert(menu_options, MenuConfigOpt:new{ user_conf = user_conf, menu_entry = entry, idx = idx })
        end
    end
    table.sort(menu_options, function(a,b) return a.idx < b.idx end)

    -- contains data as expected to be passed along to main config widget
    local sub_item_table = {}
    for i, opt in ipairs(menu_options) do
        local sub_item_entry = {
            text = opt.name,
            keep_menu_open = true,
            separator = i < #menu_options and opt.group[1] ~= menu_options[i+1].group[1]
        }
        if opt.conf_type == "text" then
            sub_item_entry['callback'] = function() return opt:build_single_dialog() end
        elseif opt.conf_type == "table" then
            sub_item_entry['callback'] = function() return opt:build_multi_dialog() end
        elseif opt.conf_type == "bool" then
            sub_item_entry['checked_func'] = function() return opt:get_value() == true end
            sub_item_entry['callback'] = function() return opt:update_value(not opt:get_value()) end
        elseif opt.conf_type == "list" then
            sub_item_entry['callback'] = function() return opt:build_list_dialog() end
        else -- TODO multitable, list
            sub_item_entry['callback'] = function()
                UIManager:show(InfoMessage:new{ text = ("Configuration of type %s can only be edited on PC!"):format(opt.conf_type), timeout = 3 })
            end
        end
        table.insert(sub_item_table, sub_item_entry)
    end
    return sub_item_table
end

return MenuBuilder
