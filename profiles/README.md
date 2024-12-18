# Profiles

The plugin is configured via profiles. Each profile is a `.lua` file with a single table containing all user configurable settings. 

To use the plugin, copy the code snippet below and save it in a new file, this file can be named whatever you want, as long as it has a `.lua` suffix.

It is also possible to define a default profile (this should be called `default.lua`) containing the entries that remain the same for all profiles.
You can then define multiple other profiles (e.g. `en.lua`, `jp.lua`, etc.) which contain *only* the fields that differ.

```lua
-- This file contains all the user configurable options
-- Entries which aren't marked as REQUIRED can be ommitted completely
local Config = {
    ----------------------------------------------
    ---- [[ GENERAL CONFIGURATION OPTIONS ]] -----
    ----------------------------------------------
    -- This refers to the IP address of the PC ankiconnect is running on
    -- Remember to expose the port ankiconnect listens on so we can connect to it
    -- [REQUIRED] The ankiconnect settings also need to be updated to not only listen on the loopback address
    url = "http://localhost:8765",
    -- [REQUIRED] name of the anki deck
    deckName = "日本::3 - Mining Deck",
    -- [REQUIRED] note type of the notes that should be created
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
    -- [REQUIRED] The field name where the word which was looked up in a dictionary will be sent to.
    word_field = "VocabKanji",

    -- The field name where the sentence in which the word we looked up occurred will be sent to.
    context_field = "SentKanji",

    -- Translation of the context field
    translated_context_field = "SentEng",

    -- Amount of sentences which are prepended to the word looked up. Set this to 1 to complete the current sentence.
    prev_sentence_count = 1,

    -- Amount of sentences which are appended to the word looked up. Set this to 1 to complete the current sentence.
    next_sentence_count = 1,

    -- [REQUIRED] The field name where the dictionary definition will be sent to.
    def_field = "VocabDef",

    -- The field name where metadata (book source, page number, ...) will be sent to.
    -- This metadata is parsed from the EPUB's metadata, or from the filename
    meta_field = "Notes",

    -- The plugin can query Forvo for audio of the word you just looked up.
    -- The field name where the audio will be sent to.
    audio_field = "VocabAudio",

    -- list of extensions which should be enabled, by default they are all off
    -- an extension is turned on by listing its filename in the table below
    enabled_extensions = {
        --[[
        "EXT_dict_edit.lua",
        "EXT_dict_word_lookup.lua",
        "EXT_multi_def.lua",
        "EXT_pitch_accent.lua"
        --]]
    }
}
return Config
```
