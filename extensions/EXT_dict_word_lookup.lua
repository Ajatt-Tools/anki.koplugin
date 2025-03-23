local conf = require("anki_configuration")
local CustomWordLookup = {
    description = "This plugin modifies the default addon behavior. Instead of saving the word selected in the book, it selects the headword in the dictionary entry itself."
}

function CustomWordLookup:run(note)
    if not self.popup_dict.is_extended then
        self.popup_dict.results = require("langsupport/ja/dictwrapper").extend_dictionaries(self.popup_dict.results, self.conf)
        self.popup_dict.is_extended = true
    end
    local selected = self.popup_dict.results[self.popup_dict.dict_index]

    -- TODO pick the kanji representation which matches the one we looked up
    local parsed_word = selected:get_kanji_words()[1] or selected:get_kana_words()[1]
    if parsed_word then
        note.fields[conf.word_field:get_value()] = parsed_word
    end
    return note
end

return CustomWordLookup
