local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")

local settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/ankiconnect.lua")
local AnkiConfigOpt = {
    id = nil,           -- id should match the key used in the main AnkiDefaults table
    name = nil,         -- pretty name for display purposes
    description = nil,  -- explanation for this config options
    default = nil,      -- default value for this config option
    conf_type = "text", -- type of data stored in this option, options: [ text ]

    get_value = function(obj)
        return settings:readSetting(obj.id) or obj.default
    end,
    update_value = function(obj, new)
        settings:saveSetting(obj.id, new)
    end,
    is_text = function(obj) return obj.conf_type == "text" end,
}

function AnkiConfigOpt:new(opt)
    return setmetatable(opt, { __index = self })
end
local general_settings = { "generic_settings", "General Settings" }
local note_settings = { "note_settings", "Anki Note Settings" }
local dictionary_settings = { "dictionary_settings", "Dictinoary Settings" }

local AnkiDefaults = {
    -- remember to expose the port ankiconnect listens on so we can connect to it
    -- also, the ankiconnect settings need to be updated to not only listen on the loopback address
    AnkiConfigOpt:new {
        id = "url",
        group = general_settings,
        name = "AnkiConnect URL",
        description = "The URL anki_connect is listening on.",
        default = "http://localhost:8765",
    },

    -- The deck the new cards will be stored in
    AnkiConfigOpt:new {
        id = "deckName",
        group = general_settings,
        name = "Anki Deckname",
        description = "The name of the deck the new notes should be added to.",
        default = "日本::3 - Mining Deck",
    },

    -- The Note Type used to build the new notes
    AnkiConfigOpt:new {
        id = "modelName",
        group = general_settings,
        name = "Anki Note Type",
        description = "The Anki note type our cards should use.",
        default = "Japanese sentences",
    },

    -- any dictionary in the map should be exported, and stored in the field stored in value
    AnkiConfigOpt:new {
        id = "dict_field_map",
        group = general_settings,
        name = "Dictionary Map",
        description = "List of key/value pairs linking a dictionary with a field on the note type",
        conf_type = "table",
        default = { ["JMdict Rev. 1.9"] = "SentEng" },
    },

    AnkiConfigOpt:new {
        id = "dict_edit",
        group = dictionary_settings,
        name = "Edit dictionary entry",
        description = [[Edit dictionary contents with a lua Pattern.
        The word or definition can be edited before use.
        For either field, a list of { pattern, replacement, count } tables can be given.
        If no replacement is present, the pattern will be removed.
        ]],
        conf_type = "multitable",
        default = {
            ["スーパー大辞林　3.0"] = {
                ["word"] = {},
                ["definition"] = {
                    { '%[[0-9]%]' },
                    { '%[[0-9]%]:%[0-9%]' },
                }
            },
            ["新明解国語辞典　第五版"] = {
                ["word"] = {},
                ["definition"] = {
                    { '%[[0-9]%]' },
                    { '%[[0-9]%]:%[0-9%]' },
                }
            }
        }
    },

    AnkiConfigOpt:new {
        id = "kana_pattern",
        group = dictionary_settings,
        name = "Kana Pattern",
        description = "lua Pattern which returns the Kana reading of a dictionary word",
        conf_type = "multitable",
        default = {
            ["JMdict Rev. 1.9"] = {"definition", ".*font color=\"green\">(.*)</font>.*"},
        }
    },

    AnkiConfigOpt:new {
        id = "kanji_pattern",
        group = dictionary_settings,
        name = "Kanji Pattern",
        description = "lua Pattern which returns the Kanji reading(s) of a dictionary word",
        conf_type = "table",
        default = {
            ["JMdict Rev. 1.9"] = ".*",
        }
    },

    -- field where the word we selected should go
    AnkiConfigOpt:new {
        id = "word_field",
        group = general_settings,
        name = "Word Field",
        description = "Anki field for selected word.",
        default = "VocabKanji",
    },

    -- field which contains the full sentence we selected the word in.
    AnkiConfigOpt:new {
        id = "context_field",
        group = note_settings,
        name = "Context Field",
        description = "Anki field for sentence selected word occured in.",
        default = "SentKanji",
    },

    -- field which contains the dictionary definition
    AnkiConfigOpt:new {
        id = "def_field",
        group = note_settings,
        name = "Glossary Field",
        description = "Anki field for dictionary glossary.",
        default = "VocabDef",
    },

    -- field to store metadata in (book source, page number, ...)
    AnkiConfigOpt:new {
        id = "meta_field",
        group = note_settings,
        name = "Metadata Field",
        description = "Anki field to store metadata about the current book.",
        default = "Notes"
    },

    AnkiConfigOpt:new {
        id = "p_a_num",
        group = note_settings,
        name = "Pitch Downstep Field",
        description = "Anki field to store Pitch Downstep data in.",
        default = "VocabPitchNum"
    },

    AnkiConfigOpt:new {
        id = "p_a_field",
        group = note_settings,
        name = "Pitch Accent Field",
        description = "Anki field to store Pitch Accent data in.",
        default = "VocabPitchPattern"
    },

    AnkiConfigOpt:new {
        id = "audio_field",
        group = note_settings,
        name = "Forvo Audio Field",
        description = "Anki field to store Forvo audio in.",
        default = "VocabAudio",
    },

    AnkiConfigOpt:new {
        id = "img_field",
        group = note_settings,
        name = "Image Field",
        description = "Anki field to store image in (used for CBZ only).",
        default = "Image",
    },

    -- TODO editable config for 'list' type
    AnkiConfigOpt:new {
        id = "custom_tags",
        group = note_settings,
        name = "Custom Note Tags",
        description = "Extra tags which can optionally be added when creating a Note",
        conf_type = "list",
        default = { "NEEDS_WORK" }
    },

    AnkiConfigOpt:new {
        id = "allow_dupes",
        group = note_settings,
        name = "Allow Duplicates",
        description = "Allow creation of duplicate notes",
        conf_type = "bool",
        default = false
    },

    AnkiConfigOpt:new {
        id = "dupe_scope",
        group = note_settings,
        name = "Duplicate Scope",
        description = "Anki Scope in which to look for duplicates",
        conf_type = "text",
        default = "deck",
    },
}

-- all config options are accessable by index AND by key
for _,opt in ipairs(AnkiDefaults) do
    AnkiDefaults[opt.id] = opt
end

function AnkiDefaults:save()
    settings:close()
end

return AnkiDefaults
