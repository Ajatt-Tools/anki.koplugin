--[[
-- When trying to make the monolingual transition, it can be helpful to create a card with the language
-- in your target language, while still also inserting the definition in your native language in a separate field.
-- This field can then be hidden if so desired, meaning you can just have it as a crutch.
-- The dictionaries that should be stored in specific fields are listed in the `dict_field_map` variable below
--]]

local logger = require("logger")
local u = require("lua_utils/utils")

-- key: dictionary name as displayed in KOreader (received from dictionary's .ifo file)
-- value: field on the note this dictionary entry should be sent to
local dict_field_map = {
    -- the below example sends dictionary entries from 'JMdict'  to the field 'SentEng' on the anki note
    -- ["JMdict Rev. 1.9"] = "SentEng",
}

local function convert_dict_to_HTML(self, dictionaries)
    -- TODO no more user conversion (not here at least)
    local run_user_conversions = function(definition, converter)
        if not converter then
            return definition
        end
        if type(converter) == "table" then
            for _,pattern_t in ipairs(converter) do
                local pattern, replacement, count = unpack(pattern_t)
                definition = definition:gsub(pattern, replacement or '', count)
            end
        elseif type(converter) == "function" then
            definition = converter(definition)
        end
        return definition
    end
    return self:convert_to_HTML {
        entries = dictionaries,
        class = "definition",
        build = function(entry, entry_template)
            -- use user provided patterns to clean up dictionary definitions
            local def, converter = entry.definition, self.dict_edit:get_value()[entry.dict]
            def = run_user_conversions(def, converter)
            if entry.is_html then -- try adding dict name to opening div tag (if present)
                -- gsub wrapped in () so it only gives us the first result, and discards the index (2nd arg.)
                return (def:gsub("(<div)( ?)", string.format("%%1 dict=\"%s\"%%2", entry.dict), 1))
            end
            return entry_template:format(entry.dict, (def:gsub("\n", "<br>")))
        end
    }
end

-- allow storing more than just the selected dictionary entry on an anki note
return function(self, note)
    if not self.popup_dict.is_extended then
        self.popup_dict.results = require("langsupport/ja/dictwrapper").extend_dictionaries(self.popup_dict.results, self.conf)
        self.popup_dict.is_extended = true
    end

    local selected_dict = self.popup_dict.results[self.popup_dict.dict_index]
    -- map of note fields with all dictionary entries which should be combined and saved in said field
    local field_dict_map = u.defaultdict(function() return {} end)
    for idx, result in ipairs(self.popup_dict.results) do
        -- don't add definitions where the dict word does not match the selected dict's word
        -- e.g.: 罵る vs 罵り -> noun vs verb -> we only add defs for the one we selected
        -- the info will be mostly the same, and the pitch accent might differ between noun and verb form
        if selected_dict:get_kana_words():contains_any(result:get_kana_words()) then
            logger.info(string.format("note_multi_definition: handling result: %s", result:as_string()))
            local is_selected = idx == self.popup_dict.dict_index
            local field = is_selected and nil or dict_field_map[result.dict]
            if field then
                local field_defs = field_dict_map[field]
                -- make sure that the selected dictionary is always inserted in the beginning
                table.insert(field_defs, is_selected and 1 or #field_defs+1, result)
            end
        else
            local skip_msg = "Skipping %s dict entry: kana word '%s' ~= selected dict word '%s'"
            logger.info(skip_msg:format(result.dict, result:get_kana_words(), selected_dict:get_kana_words()))
        end
    end
    for field, dicts in pairs(field_dict_map) do
        note.fields[field] = convert_dict_to_HTML(self, dicts)
    end
    return note
end
