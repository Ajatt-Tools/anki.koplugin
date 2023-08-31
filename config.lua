-- This file contains all the user configurable options
-- !!!! all options are required, do not delete any of the keys in the table below !!!!
-- The note fields can be left blank, fields which don't exist on your chosen note type will be ignored
local Config = {
    ----------------------------------------------
    ---- [[ GENERAL CONFIGURATION OPTIONS ]] -----
    ----------------------------------------------
    -- This refers to the IP address of the PC ankiconnect is running on
    -- Remember to expose the port ankiconnect listens on so we can connect to it
    -- The ankiconnect settings also need to be updated to not only listen on the loopback address
    url = "http://localhost:8765",
    -- name of the anki deck
    deckName = "日本::3 - Mining Deck",
    -- note type of the notes that should be created
    modelName = "Japanese sentences",
    -- Each note created by the plugin will have the tag 'KOReader', it is possible to add other custom tags
    -- A card with custom tags can be created by pressing and holding the 'Add to Anki' button, which pops up a menu with some extra options.
    custom_tags = { "NEEDS_WORK" },

    -- It is possible to toggle whether duplicate notes can be created. This can be of use if your note type contains the full sentence as first field (meaning this gets looked at for uniqueness)
    -- When multiple unknown words are present, it won't be possible to add both in this case, because the sentence would be the same.
    allow_dupes = false,
    -- The scope where ankiconnect will look to to find duplicates
    dupe_scope = "deck",


    ----------------------------------------------
    --- [[ NOTE FIELD CONFIGURATION OPTIONS ]] ---
    ----------------------------------------------
    -- The field name where the word which was looked up in a dictionary will be sent to.
    word_field = "VocabKanji",

    -- The field name where the sentence in which the word we looked up occurred will be sent to.
    context_field = "SentKanji",

    -- The field name where the dictionary definition will be sent to.
    def_field = "VocabDef",

    -- The field name where metadata (book source, page number, ...) will be sent to.
    -- This metadata is parsed from the EPUB's metadata, or from the filename
    meta_field = "Notes",

    -- The plugin can query Forvo for audio of the word you just looked up.
    -- The field name where the audio will be sent to.
    audio_field = "VocabAudio",

    -- This is currently unused.
    image_field = "Image",

    -- A pattern can be provided which for each dictionary extracts the kana reading(s) of the word which was looked up.
    -- This is used to determine which dictionary entries should be added to the card (e.g. 帰り vs 帰る: if the noun was selected, the verb is skipped)
    kana_pattern = {
        -- key: dictionary name as displayed in KOreader (received from dictionary's .ifo file)
        -- value: a table containing 2 entries:
        -- 1) the dictionary field to look for the kana reading in (either 'word' or 'description')
        -- 2) a pattern which should return the kana reading(s) (the pattern will be looked for multiple times!)
        ["JMdict Rev. 1.9"] = {"definition", "<font color=\"green\">(.-)</font>"},
    },
    -- A pattern can be provided which for each dictionary extracts the kanji reading(s) of the word which was looked up.
    -- This is used to store in the `word_field` defined above
    kanji_pattern = {
        -- key: dictionary name as displayed in KOreader (received from dictionary's .ifo file)
        -- value: a table containing 2 entries:
        -- 1) the dictionary field to look for the kanji in (either 'word' or 'description')
        -- 2) a pattern which should return the kanji
        ["JMdict Rev. 1.9"] = {"word", ".*"},
    },

    -- The dictionary entry can be modified before it is stored on your anki note.
    dict_edit = {
        -- key: dictionary name as displayed in KOreader (received from dictionary's .ifo file)
        -- value: can be either a table or a function
        -- * value (table): expected entry format { pattern, [replacement], [count] }. Multiple entries can be provided.
        --     If no replacement is provided, the matched pattern is removed.
        --     If no count is provided, all matches are replaced.
        ["新明解国語辞典　第五版"] = {
            -- replace pitch patterns occuring in definition
            { '%[[0-9]%]' },
            { '%[[0-9]%]:%[0-9%]' },
        },
        ["スーパー大辞林　3.0"] = {
            -- replace pitch patterns occuring in definition
            { '%[[0-9]%]' },
            { '%[[0-9]%]:%[0-9%]' },
        },
        -- * function: function taking in the definition as an argument, and which should return the modified definition (see example below)
        --[[ ["明鏡国語辞典　第一版"] = function(definition)
            local newline_idx = definition:find('\n', 0, true)
            local first_line = definition:sub(0, newline_idx or 0)
            if #first_line == 0 then
                return definition
            end
            local tags, tags_txt = {}, first_line:match("〘(.-)〙")
            if not tags_txt then return definition end
            local tag_fmt = '<small><span style="color:white;background:green;padding-left:3px;padding-right:3px;border-radius:0.5ex;">%s</span></small>'
            for tag in require("util").gsplit(tags_txt, '・') do
                table.insert(tags, tag_fmt:format(tag))
            end
            return definition:sub(#first_line+1) .. "<br>" .. table.concat(tags, '<font color="red"> | </font>')
        end, --]]
    }
}
return Config
