local util = require("util")
local List = require("lua_utils.list")
-- utility which wraps a dictionary sub-entry (the popup shown when looking up a word)
-- with some extra functionality which isn't there by default
DictEntryWrapper = {
    -- currently unused but might come in handy, scavenged from yomichan
    kana = 'うゔ-かが-きぎ-くぐ-けげ-こご-さざ-しじ-すず-せぜ-そぞ-ただ-ちぢ-つづ-てで-とど-はばぱひびぴふぶぷへべぺほぼぽワヷ-ヰヸ-ウヴ-ヱヹ-ヲヺ-カガ-キギ-クグ-ケゲ-コゴ-サザ-シジ-スズ-セゼ-ソゾ-タダ-チヂ-ツヅ-テデ-トド-ハバパヒビピフブプヘベペホボポ',
    kana_word_pattern = "(.*)【.*】",
    kanji_word_pattern = "【(.*)】",
    kanji_sep_chr = '・',
    pitch_downstep_pattern = "(%[([0-9])%])",
}

local function get_first_line(linestring)
    local start_idx = linestring:find('\n', 1, true)
    return start_idx and linestring:sub(1, start_idx + 1) or linestring
end

function DictEntryWrapper:new(opts)
    self.conf = opts.conf

    local index = function(table, k)
        return rawget(table, k) or rawget(self, k) or rawget(table.dictionary, k)
    end
    local kana_dictionary_field, kana_pattern = unpack(self.conf.kana_pattern:get_value()[opts.dict.dict] or {})
    local kanji_dictionary_field, kanji_pattern  = unpack(self.conf.kanji_pattern:get_value()[opts.dict.dict] or {})
    local data = {
        dictionary = opts.dict,
        kana_pattern = kana_pattern or self.kana_word_pattern,
        kana_dict_field = kana_dictionary_field or "word",
        kanji_pattern = kanji_pattern or self.kanji_word_pattern,
        kanji_dict_field = kanji_dictionary_field or "word",
    }
    return setmetatable(data, { __index = function(table, k) return index(table, k) end })
end

function DictEntryWrapper:get_kana_words()
    local dictionary_field, kana_pattern = self.kana_dict_field, self.kana_pattern
    if dictionary_field then
        return List:from_iter(self.dictionary[dictionary_field]:gmatch(kana_pattern))
    end
    -- if no custom config was present, we assume the kana is present in the 'word' field
    -- if the pattern doesn't match, return the plain word, chances are it's already in kana
    return List:new({ self.dictionary.word:match(self.kana_word_pattern) or self.dictionary.word })
end

function DictEntryWrapper:get_kanji_words()
    local kanji_entries_str = self.dictionary[self.kanji_dict_field]:match(self.kanji_pattern)
    local brackets = { ['('] = 0, [')'] = 0, ['（'] = 0, ['）'] = 0 }
    -- word entries often look like this: ある【有る・在る】
    -- the kanji_match_pattern will give us: 有る・在る
    -- these 2 entries still need to be separated
    local kanji_entries, current = {}, {}
    for _,ch in pairs(util.splitToChars(kanji_entries_str)) do
        if ch == self.kanji_sep_chr then
            table.insert(kanji_entries, table.concat(current))
            current = {}
        elseif brackets[ch] then
            -- some entries look like this: '振（り）方', the brackets should be ignored
        else
            table.insert(current, ch)
        end
    end
    if #current > 0 then
        table.insert(kanji_entries, table.concat(current))
    end
    return List:new(kanji_entries)
end

function DictEntryWrapper:get_pitch_downsteps()
    -- only look for pitch pattern in first line of defition ( TODO this could be configurable )
    return string.gmatch(get_first_line(self.dictionary.definition), self.pitch_downstep_pattern)
end

function DictEntryWrapper:as_string()
    local fmt_string = "DictEntryWrapper: (%s) word: %s, kana: %s, kanji: %s"
    return fmt_string:format(self.dictionary.dict, self.dictionary.word, self:get_kana_words(), self:get_kanji_words())
end

return DictEntryWrapper
