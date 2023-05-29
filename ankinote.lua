local logger = require("logger")
local util = require("util")
local u = require("lua_utils/utils")
local DictEntryWrapper = require("dictentrywrapper")

local AnkiNote = {
    -- if true, save ALL dictionary entries returned for a given word
    save_all_override = false,
    -- bunch of DOM element templates used to display pitch accent
    pitch_pattern = "<span style=\"display:inline;\">%s</span>",
    mark_accented = "<span style=\"display:inline-block;position:relative;\"><span style=\"display:inline;\">%s</span><span style=\"border-color:currentColor;display:block;user-select:none;pointer-events:none;position:absolute;top:0.1em;left:0;right:0;height:0;border-top-width:0.1em;border-top-style:solid;\"></span></span>",
    mark_downstep = "<span style=\"display:inline-block;position:relative;padding-right:0.1em;margin-right:0.1em;\"><span style=\"display:inline;\">%s</span><span style=\"border-color:currentColor;display:block;user-select:none;pointer-events:none;position:absolute;top:0.1em;left:0;right:0;height:0;border-top-width:0.1em;border-top-style:solid;right:-0.1em;height:0.4em;border-right-width:0.1em;border-right-style:solid;\"></span></span>",
    unmarked_char = "<span style=\"display:inline-block;position:relative;\"><span style=\"display:inline;\">%s</span><span style=\"border-color:currentColor;\"></span></span>",
}

local function Set(data)
    local set = {}
    for _,v in pairs(util.splitToChars(data)) do
        set[v] = true
    end
    return set
end

--[[
-- Determine trimmed word context for consecutive lookups.
-- When a user updates the text in a dictionary popup window and thus gets a new popup
-- the word selected in the book won't reflect the word in the dictionary.
-- We want to know if last dict lookup is contained in first dict lookup.
-- e.g.: '広大な' -> trimmed to '広大' -> context is '' (before), 'な' (after)
--]]
function AnkiNote:set_word_trim()
    local list = self.popup_dict.window_list
    if #list == 1 then
        return
    end
    local orig, last = list[1].word, list[#list].word
    logger.dbg(("first popup dict: %s, last dict : %s"):format(orig, last))
    local s_idx, e_idx = orig:find(last, 1, true)
    if not s_idx then
        self.contextual_lookup = false
    else
        self.word_trim = { before = orig:sub(1, s_idx-1), after = orig:sub(e_idx+1, #orig) }
    end
end


function AnkiNote:convert_to_HTML(opts)
    local wrapper_template = opts.wrapper_template or "<div class=\"%s\"><ol>%s</ol></div>"
    local entry_template = opts.entry_template or "<li dict=\"%s\">%s</li>"
    local list_items = {}
    for _,entry in ipairs(opts.entries) do
        table.insert(list_items, opts.build(entry, entry_template))
    end
    return wrapper_template:format(opts.class, table.concat(list_items))
end

-- [[
-- Convert a table of dictionaries to a single HTML <div> tag
-- ]]
function AnkiNote:convert_dict_to_HTML(dictionaries)
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

function AnkiNote:convert_pitch_to_HTML(accents, fields)
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
    fields[self.p_a_num:get_value()] = converter("pitch_num")
    fields[self.p_a_field:get_value()] = converter("pitch_accent")
end

function AnkiNote:get_pitch_accents(dict_result)
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
            logger.dbg("AnkiNote#get_pitch_accent(): determined marking for mora: ", idx, table.concat(mora), marking)
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

function AnkiNote:split_morae(word)
    local small_aeio = Set("ゅゃぃぇょゃ")
    local morae = u.defaultdict(function() return {} end)
    for _,ch in ipairs(util.splitToChars(word)) do
        local is_small = small_aeio[ch] or false
        table.insert(morae[is_small and #morae or #morae+1], ch)
    end
    logger.info(string.format("AnkiNote#split(): split word %s into %d morae: ", word, #morae))
    return morae
end

-- [[
-- Wrap a dictionary entry in another table, which adds extra functionality to it.
-- All original dictionary fields are still accessible
-- ]]
function AnkiNote:extend_dict(dictionary_entry)
    return DictEntryWrapper:new {
        dict = dictionary_entry,
        conf = self.conf
    }
end

-- [[
-- Create metadata string about the document the word came from.
-- ]]
function AnkiNote:get_metadata()
    local meta = self.ui.document._anki_metadata
    return string.format("%s - %s (%d/%d)", meta.author, meta.title, meta:current_page(), meta.pages)
end

function AnkiNote:get_word_context()
    if not self.contextual_lookup then
        return self.popup_dict.word
    end
    local provider = self.ui.document.provider
    if provider == "crengine" then -- EPUB
        local before, after = self:get_custom_context(unpack(self.context))
        return before .. "<b>" .. self.popup_dict.word .. "</b>" .. after
    elseif provider == "mupdf" then -- CBZ
        local ocr_text = self.ui['Mokuro'] and self.ui['Mokuro']:get_selection()
        logger.info("selected text: ", ocr_text)
        -- TODO is trim relevant here?
        return ocr_text or self.popup_dict.word
    end
end

--[[
-- Returns the context before and after the lookup word, the amount of context depends on the following parameters
-- @param pre_s: amount of sentences prepended
-- @param pre_c: amount of characters prepended
-- @param post_s: amount of sentences appended
-- @param post_c: amount of characters appended
--]]
function AnkiNote:get_custom_context(pre_s, pre_c, post_s, post_c)
    logger.info("AnkiNote#get_custom_context()", pre_s, pre_c, post_s, post_c)
    -- called when initial size `self.context_size` becomes too small.
    local function expand_content()
        self.context_size = self.context_size + self.context_size
        self:init_context_buffer(self.context_size)
    end

    local delims_map = Set("？」。.?!！")
    -- calculate the slice of the `prev_context_table` array that should be prepended to the lookupword
    local prev_idx, prev_s_idx = 0, 0
    while prev_s_idx < pre_s do
        if #self.prev_context_table < prev_idx then expand_content() end
        local idx = #self.prev_context_table - prev_idx
        local ch = self.prev_context_table[idx]
        assert(ch ~= nil, ("Something went wrong when parsing previous context! idx: %d, context_table size: %d"):format(idx, #self.prev_context_table))
        if delims_map[ch] then
            prev_s_idx = prev_s_idx + 1
        end
        prev_idx = prev_idx + 1
    end
    if prev_idx > 0 then
        -- do not include the trailing character (if we parsed any sentences above)
        prev_idx = prev_idx - 1
    end
    prev_idx = prev_idx + pre_c
    if #self.prev_context_table < prev_idx then expand_content() end
    local i, j = #self.prev_context_table - prev_idx + 1, #self.prev_context_table
    local prepended_content = table.concat(self.prev_context_table, "", i, j)

    -- calculate the slice of the `next_context_table` array that should be appended to the lookupword
    -- `next_idx` starts at 1 because that's the first index in the table
    local next_idx, next_s_idx = 1, 0
    while next_s_idx < post_s do
        if next_idx > #self.next_context_table then expand_content() end
        local ch = self.next_context_table[next_idx]
        assert(ch ~= nil, ("Something went wrong when parsing next context! idx: %d, context_table size: %d"):format(next_idx, #self.next_context_table))
        if delims_map[ch] then
            next_s_idx = next_s_idx + 1
        end
        next_idx = next_idx + 1
    end
    -- do not include the trailing character
    next_idx = next_idx - 1
    next_idx = next_idx + post_c
    if next_idx > #self.next_context_table then expand_content() end
    local appended_content = table.concat(self.next_context_table, "", 1, next_idx)
    -- These 2 variables can be used to detect if any content was prepended / appended
    self.has_prepended_content = prev_idx > 0
    self.has_appended_content = next_idx > 0
    return prepended_content, appended_content
end

function AnkiNote:get_picture_context()
    local meta = self.ui.document._anki_metadata
    if not meta then
        return
    end
    local provider, plugin = self.ui.document.provider, self.ui['Mokuro']
    -- we only add pictures for CBZ (handled by ocr_popup widget)
    if provider == "mupdf" and plugin then
        local fn = string.format("%s/%s_%s.jpg", self.settings_dir, meta.title, os.date("%Y-%m-%d %H-%M-%S"))
        return plugin:get_context_picture(fn) and fn or nil
    end
end

function AnkiNote:build()
    -- TODO: we should highlight the WHOLE word that was selected by the JP plugin
    -- e.g. 垣間見える -> don't just select 垣間見
    -- not sure this happens always but surely sometimes
    local popup_wrapper = self:extend_dict(self.popup_dict.results[self.popup_dict.dict_index])
    logger.info(string.format("AnkiNote#create_note(): (%d results), %s", #self.popup_dict.results, popup_wrapper:as_string()))

    -- TODO pick the kanji representation which matches the one we looked up
    local word = popup_wrapper:get_kanji_words()[1] or popup_wrapper:get_kana_words()[1] or self.popup_dict.word
    local fields = {
        [self.context_field:get_value()] = self:get_word_context(),
        [self.word_field:get_value()] = word,
        [self.meta_field:get_value()] = self:get_metadata()
    }

    local pitch_accents = {}
    -- map of note fields with all dictionary entries which should be combined and saved in said field
    local field_dict_map = u.defaultdict(function() return {} end)
    for idx, raw_result in ipairs(self.popup_dict.results) do
        local result = self:extend_dict(raw_result)
        -- don't add definitions where the dict word does not match the selected dict's word
        -- e.g.: 罵る vs 罵り -> noun vs verb -> we only add defs for the one we selected
        -- the info will be mostly the same, and the pitch accent might differ between noun and verb form
        if popup_wrapper:get_kana_words():contains_any(result:get_kana_words()) then
            logger.info(string.format("AnkiNote#create_note(): handling result: %s", result:as_string()))
            local is_selected = idx == self.popup_dict.dict_index
            local field = (is_selected or self.save_all_override) and self.def_field:get_value() or self.dict_field_map:get_value()[result.dict]
            if field then
                local field_defs = field_dict_map[field]
                -- make sure that the selected dictionary is always inserted in the beginning
                table.insert(field_defs, is_selected and 1 or #field_defs+1, result)
            end
            for num, accent in self:get_pitch_accents(result) do
                if not pitch_accents[num] then
                    pitch_accents[num] = true -- add as k/v pair too so we can detect uniqueness
                    table.insert(pitch_accents, { pitch_num = num, pitch_accent = accent })
                end
            end
        else
            local skip_msg = "Skipping %s dict entry: kana word '%s' ~= selected dict word '%s'"
            logger.info(skip_msg:format(result.dict, result:get_kana_words(), popup_wrapper:get_kana_words()))
        end
    end
    for field, dicts in pairs(field_dict_map) do
        fields[field] = self:convert_dict_to_HTML(dicts)
    end
    -- this inserts the HTML-ified entries in fields directly
    self:convert_pitch_to_HTML(pitch_accents, fields)

    local note = {
        -- The caller is responsible to fill in potential audio/image fields
        -- the _modifiers table contains info on how to populate them
        _modifiers = {
            audio = { func = "set_forvo_audio", args = { word, self:get_language() } },
            picture = { func = "set_image_data", args = { self:get_picture_context() } },
        },
        deckName = self.deckName:get_value(),
        modelName = self.modelName:get_value(),
        fields = fields,
        options = {
            allowDuplicate = self.allow_dupes:get_value(),
            duplicateScope = self.dupe_scope:get_value(),
        },
        tags = self.tags,
    }
    return { action = "addNote", params = { note = note }, version = 6 }
end

function AnkiNote:get_language()
    local ifo_lang = self.selected_dict.ifo_lang
    return ifo_lang and ifo_lang.lang_in or self.ui.document:getProps().language
end

function AnkiNote:init_context_buffer(size)
    logger.info(("(re)initializing context buffer with size: %d"):format(size))
    if self.prev_context_table and self.next_context_table then
        logger.info(("before reinit: prev table = %d, next table = %d"):format(#self.prev_context_table, #self.next_context_table))
    end
    local skipped_chars = Set("\n\r 　")
    local prev_c, next_c = self.ui.highlight:getSelectedWordContext(size)
    -- pass trimmed word context along to be modified
    logger.info("look at word trim context real quick:", self.word_trim)
    prev_c = prev_c .. self.word_trim.before
    next_c = self.word_trim.after .. next_c
    self.prev_context_table = {}
    for _, ch in ipairs(util.splitToChars(prev_c)) do
        if not skipped_chars[ch] then table.insert(self.prev_context_table, ch) end
    end
    self.next_context_table = {}
    for _, ch in ipairs(util.splitToChars(next_c)) do
        if not skipped_chars[ch] then table.insert(self.next_context_table, ch) end
    end
    logger.info(("after reinit: prev table = %d, next table = %d"):format(#self.prev_context_table, #self.next_context_table))
end

function AnkiNote:set_custom_context(pre_s, pre_c, post_s, post_c)
    self.context = { pre_s, pre_c, post_s, post_c }
end

function AnkiNote:add_tags(tags)
    for _,t in ipairs(tags) do
        table.insert(self.tags, t)
    end
end

-- This function should be called before using the 'class' at all
function AnkiNote:extend(opts)
    -- conf table is passed along to DictEntryWrapper
    self.conf = opts.conf
    -- settings are inserted in self table directly for easy access
    for k,v in pairs(opts.conf) do
        self[k] = v
    end
    -- dict containing various settings about the current state
    self.ui = opts.ui
    -- used to save screenshots in (CBZ only)
    self.settings_dir = opts.settings_dir
    return self
end


function AnkiNote:new(popup_dict)
    local new = {
        context_size = 50,
        popup_dict = popup_dict,
        selected_dict = popup_dict.results[popup_dict.dict_index],
        -- indicates that popup_dict relates to word in book
        contextual_lookup = true,
        word_trim = { before = "", after = "" },
        tags = { "KOReader" },
    }
    local new_mt = {}
    function new_mt.__index(t, v)
        return rawget(t, v) or self[v]
    end

    local note = setmetatable(new, new_mt)
    note:set_word_trim()
    -- TODO this can be delayed
    note:init_context_buffer(note.context_size)
    note:set_custom_context(1, 0, 1, 0)
    return note
end

return AnkiNote
