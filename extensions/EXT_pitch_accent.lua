local logger = require("logger")
local util = require("util")
local u = require("lua_utils/utils")

local PitchAccent = {
    description = [[
Some definitions contain pitch accent information.
e.g. さけ・ぶ [2]【叫ぶ】
this extension extracts the [2] from the definition's headword and stores it as a html representation and/or a number.
    ]],
    -- These 2 fields should be modified to point to the desired field on the card
    field_pitch_html = 'VocabPitchPattern',
    field_pitch_num = 'VocabPitchNum'
}

function PitchAccent:convert_pitch_to_HTML(accents)
    local converter = nil
    if #accents == 0 then
        converter = function(_) return nil end
    elseif #accents == 1 then
        converter = function(field) return accents[1][field] end
    else
        converter = function(field) return self:convert_to_HTML {
            entries = accents,
            class = "pitch",
            build = function(accent) return string.format("<li>%s</li>", accent[field]) end
        }
        end
    end
    return converter("pitch_num"), converter("pitch_accent")
end

function PitchAccent:split_morae(word)
    local small_aeio = u.to_set(util.splitToChars("ゅゃぃぇょゃ"))
    local morae = u.defaultdict(function() return {} end)
    for _,ch in ipairs(util.splitToChars(word)) do
        local is_small = small_aeio[ch] or false
        table.insert(morae[is_small and #morae or #morae+1], ch)
    end
    logger.info(("EXT: PitchAccent#split_morae(): split word %s into %d morae: "):format(word, #morae))
    return morae
end

function PitchAccent:get_pitch_accents(dict_result)
    local morae = self:split_morae(dict_result:get_kana_words()[1])

    local function _convert(downstep)
        local pitch_visual = {}
        local is_heiban = downstep == "0"
        for idx, mora in ipairs(morae) do
            local marking = nil
            if is_heiban then
                marking = idx == 1 and self.unmarked_char or self.mark_accented
            else
                if idx == tonumber(downstep) then
                    marking = self.mark_downstep
                else
                    marking = idx < tonumber(downstep) and self.mark_accented or self.unmarked_char
                end
            end
            -- when dealing with the downstep mora, we want the downstep to appear only on the last char of the mora
            local is_downstep = marking == self.mark_downstep
            logger.dbg("EXT: PitchAccent#get_pitch_accent(): determined marking for mora: ", idx, table.concat(mora), marking)
            for _, ch in ipairs(mora) do
                table.insert(pitch_visual, (is_downstep and self.mark_accented or marking):format(ch))
            end
            if is_downstep then
                pitch_visual[#pitch_visual] = self.mark_downstep:format(mora[#mora])
            end
        end
        return self.pitch_pattern:format(table.concat(pitch_visual))
    end

    local downstep_iter = dict_result:get_pitch_downsteps()
    return function(iter)
        local with_brackets, downstep = iter()
        if downstep then
            return with_brackets, _convert(downstep)
        end
    end, downstep_iter
end

function PitchAccent:run(note)
    if not self.popup_dict.is_extended then
        self.popup_dict.results = require("langsupport/ja/dictwrapper").extend_dictionaries(self.popup_dict.results, self.conf)
        self.popup_dict.is_extended = true
    end
    local selected = self.popup_dict.results[self.popup_dict.dict_index]

    local pitch_accents = {}
    for idx, result in ipairs(self.popup_dict.results) do
        if selected:get_kana_words():contains_any(result:get_kana_words()) then
            for num, accent in self:get_pitch_accents(result) do
                if not pitch_accents[num] then
                    pitch_accents[num] = true -- add as k/v pair too so we can detect uniqueness
                    table.insert(pitch_accents, { pitch_num = num, pitch_accent = accent })
                end
            end
        end
    end
    local pitch_num, pitch_accent = self:convert_pitch_to_HTML(pitch_accents)
    note.fields[self.field_pitch_num] = pitch_num
    note.fields[self.field_pitch_html] = pitch_accent
    return note
end

return PitchAccent