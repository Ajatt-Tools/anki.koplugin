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

function AnkiNote:convert_to_HTML(opts)
	local wrapper_template = opts.wrapper_template or "<div style=\"text-align: left;\"><ol>%s</ol></div>"
	local entry_template = opts.entry_template or "<li dict=\"%s\">%s</li>"
	local list_items = {}
	for _,entry in ipairs(opts.entries) do
		table.insert(list_items, opts.build(entry, entry_template))
	end
	return wrapper_template:format(table.concat(list_items))
end

-- [[
-- Convert a table of dictionaries to a single HTML <div> tag
-- ]]
function AnkiNote:convert_dict_to_HTML(dictionaries)
	return self:convert_to_HTML {
		entries = dictionaries,
		build = function(entry, entry_template)
			-- use user provided patterns to clean up dictionary definitions
			local def, patterns = entry.definition, self.dict_edit:get_value()[entry.dict]
			if patterns and patterns.definition then
				for _,pattern in ipairs(patterns.definition) do
					def = string.gsub(def, pattern[1], pattern[2] or '', pattern[3] or nil)
				end
			end
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
		converter = function(field) return nil end
	elseif #accents == 1 then
		converter = function(field) return accents[1][field] end
	else
		converter = function(field) return self:convert_to_HTML {
			entries = accents,
			build = function(accent) return string.format("<li>%s</li>", accent[field]) end
		}
		end
	end
	fields[self.p_a_num:get_value()] = converter("pitch_num")
	fields[self.p_a_field:get_value()] = converter("pitch_accent")
end

-- [[
-- Trim the context string so it can be appended/prepended to the word we want to save.
-- @param context: string to be split up in different sentences
-- @param: is_preceding: boolean indicating whether this context comes before or after the word.
-- ]]
function AnkiNote:trim_context(context, is_preceding)
	local delims_map = Set("「…？」。.?!！")
	local chars_to_skip = Set("\n\r　")
	local matches = {}
	local sentence = {}
	for _, ch in ipairs(util.splitToChars(context)) do
		if chars_to_skip[ch] then
			-- skipping
		elseif delims_map[ch] then
			if is_prev then
				table.insert(sentence, ch)
			end
			table.insert(matches, table.concat(sentence))
			sentence = {}
		else
			table.insert(sentence, ch)
		end
	end
	if #sentence > 0 then
		table.insert(matches, table.concat(sentence))
	end
	return matches[is_preceding and #matches or 1]
end

-- [[
-- Create metadata string about the document the word came from.
-- ]]
function AnkiNote:create_metadata()
	local meta = self.ui.document._anki_metadata
	return string.format("%s - %s (%d/%d)", meta.author, meta.title, meta:current_page(), meta.pages)
end

function AnkiNote:get_pitch_accents(dict_result)
	local morae = self:split_morae(dict_result:get_word_in_kana())

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

function AnkiNote:get_word_context(word)
	local provider = self.ui.document.provider
	if provider == "crengine" then -- EPUB
		local prev_context, next_context = self.ui.highlight:getSelectedWordContext(50)
		local prev_trimmed, next_trimmed = self:trim_context(prev_context, true), self:trim_context(next_context, false)
		logger.dbg(string.format("AnkiNote#create_note(): word context: before=>'%s' after=>'%s'", prev_trimmed, next_trimmed))
		return prev_trimmed .. "<b>" .. word .. "</b>" .. next_trimmed
	elseif provider == "mupdf" then -- CBZ
		local ocr_text = self.ui['Mokuro'] and self.ui['Mokuro']:get_selection()
		logger.info("selected text: ", ocr_text)
		return ocr_text or word
	end
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

--[[
-- Create an Anki note for the currently selected word. all necessary info is stored in 'popup_dict'
-- @param popup_dict: the DictQuickLookup object
--]]
function AnkiNote:create_note(popup_dict, tags)
	-- TODO: we should highlight the WHOLE word that was selected by the JP plugin
	-- e.g. 垣間見える -> don't just select 垣間見
	-- not sure this happens always but surely sometimes
	local popup_wrapper = self:extend_dict(popup_dict.results[popup_dict.dict_index])
	logger.info(string.format("AnkiNote#create_note(): add_note (%d results), %s", #popup_dict.results, popup_wrapper:as_string()))

	-- context is only relevant if we looked up a word on the page.
	-- When looking up a word in a dictionary entry, this context is not relevant
	local trim = '' -- contains char(s) which were trimmed
	local function with_context()
		local list = popup_dict.window_list
		if #list == 1 then
			return true
		elseif #list == 2 then
			-- word's context is still wanted if top dict is the last word trimmed
			-- e.g.: '広大な' -> trimmed to '広大' -> we still want the context of the orig. sentence
			local top, below = list[#list].word, list[#list-1].word
			local below_trimmed = below:sub(1, #top)
			trim = below:sub(#top+1)
			logger.dbg(string.format("top popup dict: %s, popup dict below: %s", top, below))
			logger.dbg(string.format("below trimmed: %s, trim leftover: %s", below_trimmed, trim))
			return below_trimmed == top
		else
			return false
		end
	end
	local note_needs_context = with_context()
	local word = popup_wrapper:get_word_in_kanji()[1] or popup_wrapper:get_word_in_kana() or popup_dict.word
	local fields = {
		[self.context_field:get_value()] = note_needs_context and self:get_word_context(popup_dict.word .. trim) or popup_dict.word,
		[self.word_field:get_value()] = word,
		[self.meta_field:get_value()] = self:create_metadata()
	}

	local pitch_accents = {}
	-- map of note fields with all dictionary entries which should be combined and saved in said field
	local field_dict_map = u.defaultdict(function() return {} end)
	for idx, raw_result in ipairs(popup_dict.results) do
		local result = self:extend_dict(raw_result)
		-- don't add definitions where the dict word does not match the selected dict's word
		-- e.g.: 罵る vs 罵り -> noun vs verb -> we only add defs for the one we selected
		-- the info will be mostly the same, and the pitch accent might differ between noun and verb form
		-- TODO a dict entry can have multiple kana defs!
		if popup_wrapper:get_word_in_kana() == result:get_word_in_kana() then
			logger.info(string.format("AnkiNote#create_note(): handling result: %s", result:as_string()))
			local is_selected = idx == popup_dict.dict_index
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
			logger.info(skip_msg:format(result.dict, result:get_word_in_kana(), popup_wrapper:get_word_in_kana()))
		end
	end
	for field, dicts in pairs(field_dict_map) do
		fields[field] = self:convert_dict_to_HTML(dicts)
	end
	-- this inserts the HTML-ified entries in fields directly
	self:convert_pitch_to_HTML(pitch_accents, fields)

	-- The default 'KOReader' tag should be there no matter what
	table.insert(tags, 1, "KOReader")
	local note = {
		deckName = self.deckName:get_value(),
		modelName = self.modelName:get_value(),
		fields = fields,
		options = {
			allowDuplicate = false,
			duplicateScope = "deck"
		},
		tags = tags,
		-- this gets converted later, currently it's just a path to an image
		_pic = note_needs_context and self:get_picture_context(),
	}
	return { action = "addNote", params = { note = note }, version = 6 }
end

function AnkiNote:new(opts)
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

return AnkiNote
