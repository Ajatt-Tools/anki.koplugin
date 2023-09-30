--[[
-- By default, the plugin saves the text selected to do the lookup in the `word_field`
-- This plugin modifies that behavior, by getting the word from the dictionary definition instead.
--
-- NOTE: this has Japanese specific logic
--]]
return function(self, note)
	if not self.popup_dict.is_extended then
        self.popup_dict.results = require("langsupport/ja/dictwrapper").extend_dictionaries(self.popup_dict.results, self.conf)
        self.popup_dict.is_extended = true
	end
    local selected = self.popup_dict.results[self.popup_dict.dict_index]

    -- TODO pick the kanji representation which matches the one we looked up
	local parsed_word = popup_wrapper:get_kanji_words()[1] or popup_wrapper:get_kana_words()[1]
	if parsed_word then
		note.fields[self.conf.word_field:get_value()] = parsed_word
	end
	return note
end
