local logger = require("logger")
local util = require("util")
local u = require("lua_utils/utils")
local conf = require("anki_configuration")

local LANG_NOT_SET_ERROR = "Neither the dictionary, nor the document have its language set. See the FAQ section in the plugin's README."
local AnkiNote = {
}

--[[
-- Determine trimmed word context for consecutive lookups.
-- When a user updates the text in a dictionary popup window and thus gets a new popup
-- the word selected in the book won't reflect the word in the dictionary.
-- We want to know if last dict lookup is contained in first dict lookup.
-- e.g.: '広大な' -> trimmed to '広大' -> context is '' (before), 'な' (after)
--]]

function AnkiNote:set_word_trim()
    local list = self.popup_dict.window_list
    if #list == 1 or conf.trust_first_dict:get_value() then
        self.popup_dict.word = list[1].word -- often useless
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
-- Create metadata string about the document the word came from.
-- ]]
function AnkiNote:get_metadata()
    local meta = self.ui.document._anki_metadata
    return string.format("%s - %s (%d/%d)", meta.author, meta.title, meta:current_page(), meta.pages())
end

function AnkiNote:get_word_context()
    if not self.contextual_lookup then
        return self.popup_dict.word
    end
    local provider = self.ui.document.provider
    if self.ui.document.getSelectedWordContext then
        local p = self.context.params
        local before, after = self:get_custom_context(p.prev_s, p.prev_c, p.post_s, p.post_c)
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
-- @param prev_s: amount of sentences prepended
-- @param prev_c: amount of characters prepended
-- @param post_s: amount of sentences appended
-- @param post_c: amount of characters appended
--]]
function AnkiNote:get_custom_context(prev_s, prev_c, post_s, post_c)
    logger.info("AnkiNote#get_custom_context()", prev_s, prev_c, post_s, post_c)
    -- called when initial buffer_size becomes too small.
    local function expand_content()
        self.context.params.buffer_size = self.context.params.buffer_size + self.context.params.buffer_size
        self:init_context_buffer(self.context.params.buffer_size)
    end

    -- apparently the mupdf provider does not add the trailing/leading spaces, so we have to do it ourselves
    local function add_spacing(context, idx)
        local context_table = { context }
        if self.ui.document.provider == 'mupdf' and #context > 0 then
            table.insert(context_table, idx or #context_table + 1, ' ')
        end
        return table.concat(context_table, "")
    end

    local delims_map = u.to_set(util.splitToChars("？」。.?!！"))
    -- calculate the slice of the `prev_context_table` array that should be prepended to the lookupword
    local prev_idx, prev_s_idx = 0, 0
    while prev_s_idx < prev_s do
        if #self.context.buffer.prev_table <= prev_idx then expand_content() end
        -- if we're still out of bounds after expanding content we're at the beginning of the doc or there's no text layer (e.g., OCR-only PDFs)
        if #self.context.buffer.prev_table <= prev_idx then break end
        local idx = #self.context.buffer.prev_table - prev_idx
        local ch = self.context.buffer.prev_table[idx]
        assert(ch ~= nil, ("Something went wrong when parsing previous context! idx: %d, context_table size: %d"):format(idx, #self.context.buffer.prev_table))
        if delims_map[ch] then
            prev_s_idx = prev_s_idx + 1
        end
        prev_idx = prev_idx + 1
    end
    self.context.buffer.prev_exhausted = prev_s_idx < prev_s
    logger.info("prev exhausted", self.context.buffer.prev_exhausted)
    local prepended_content = ""
    if not self.context.buffer.prev_exhausted then
        if prev_idx > 0 then
            -- do not include the trailing character (if we parsed any sentences above)
            prev_idx = prev_idx - 1
        end
        prev_idx = prev_idx + prev_c
        if #self.context.buffer.prev_table <= prev_idx then expand_content() end
        self.context.buffer.prev_exhausted =  #self.context.buffer.prev_table <= prev_idx
        logger.info("prev exhausted", self.context.buffer.prev_exhausted)
        local i, j = #self.context.buffer.prev_table - prev_idx + 1, #self.context.buffer.prev_table
        prepended_content = add_spacing(table.concat(self.context.buffer.prev_table, "", i, j))
    end

    -- calculate the slice of the `next_context_table` array that should be appended to the lookupword
    -- `next_idx` starts at 1 because that's the first index in the table
    local next_idx, next_s_idx = 1, 0
    while next_s_idx < post_s do
        if next_idx > #self.context.buffer.next_table then expand_content() end
        -- if we're still out of bounds after expanding content we're at the end of the doc
        if next_idx > #self.context.buffer.next_table then break end
        local ch = self.context.buffer.next_table[next_idx]
        assert(ch ~= nil, ("Something went wrong when parsing next context! idx: %d, context_table size: %d"):format(next_idx, #self.context.buffer.next_table))
        if delims_map[ch] then
            next_s_idx = next_s_idx + 1
        end
        next_idx = next_idx + 1
    end
    self.context.buffer.next_exhausted = next_s_idx < post_s
    local appended_content = ""
    if not self.context.buffer.next_exhausted then
        -- do not include the trailing character
        next_idx = next_idx - 1
        next_idx = next_idx + post_c
        if next_idx > #self.context.buffer.next_table then expand_content() end
        self.context.buffer.next_exhausted = next_idx > #self.context.buffer.next_table
        appended_content = add_spacing(table.concat(self.context.buffer.next_table, "", 1, next_idx), 1)
    end
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

function AnkiNote:run_extensions(note)
    for _, extension in ipairs(self.extensions) do
        note = extension:run(note)
    end
    return note
end

function AnkiNote:get_definition()
    return self:convert_to_HTML {
        entries = { self.popup_dict.results[self.popup_dict.dict_index] },
        class = "definition",
        build = function(entry, entry_template)
            local def = entry.definition
            if entry.is_html then -- try adding dict name to opening div tag (if present)
                -- gsub wrapped in () so it only gives us the first result, and discards the index (2nd arg.)
                return (def:gsub("(<div)( ?)", string.format("%%1 dict=\"%s\"%%2", entry.dict), 1))
            end
            return entry_template:format(entry.dict, (def:gsub("\n", "<br>")))
        end
    }
end

function AnkiNote:build()
    local fields = {
        [conf.word_field:get_value()] = self.popup_dict.word,
        [conf.def_field:get_value()] = self:get_definition()
    }
    local optional_fields = {
        [conf.context_field] = function() return self:get_word_context() end,
        [conf.meta_field]    = function() return self:get_metadata() end,
    }
    for opt,fn in pairs(optional_fields) do
        local field_name = opt:get_value()
        if field_name then
            fields[field_name] = fn()
        end
    end
    local note = {
        deckName = conf.deckName:get_value(),
        modelName = conf.modelName:get_value(),
        fields = fields,
        options = {
            allowDuplicate = conf.allow_dupes:get_value(),
            duplicateScope = conf.dupe_scope:get_value(),
        },
        tags = self.tags,
    }
    return {
        -- actual table passed to anki-connect later
        data = self:run_extensions(note),
        -- some fields require an internet connection, which we may not have at this point
        -- all info needed to populate them is stored as a callback, which is called when a connection is available
        field_callbacks = {
            audio = {
                func = "set_forvo_audio",
                field_name = conf.audio_field:get_value(),
                args = { self.popup_dict.word, self:get_language() }
            },
            picture = {
                func = "set_image_data",
                field_name = conf.image_field:get_value(),
                args = { self:get_picture_context() }
            },
            fields = {
                func = "set_translated_context",
                field_name = conf.translated_context_field:get_value(),
                args = { fields[conf.context_field:get_value()] or self:get_word_context(), self:get_language() }
            },
        },
        -- used as id to detect duplicates when storing notes offline
        identifier = conf.word_field:get_value()
    }
end

function AnkiNote:get_language()
    local ifo_lang = self.selected_dict.ifo_lang
    local language = ifo_lang and ifo_lang.lang_in or rawget(self.ui.document._anki_metadata, 'language')
    if not language then
        local selected_dict_name = self.popup_dict.results[self.popup_dict.dict_index].dict
        local document_title = rawget(self.ui.document._anki_metadata, "title")
        error(LANG_NOT_SET_ERROR:format(self.popup_dict.word, selected_dict_name, document_title), 0)
    end
    return language
end

function AnkiNote:init_context_buffer(size)
    logger.info(("(re)initializing context buffer with size: %d"):format(size))
    if self.prev_context_table and self.next_context_table then
        logger.info(("before reinit: prev table = %d, next table = %d"):format(#self.prev_context_table, #self.next_context_table))
    end
    local skipped_chars = u.to_set(util.splitToChars(("\n\r")))
    local prev_c, next_c = self.ui.highlight:getSelectedWordContext(size)
    -- pass trimmed word context along to be modified
    prev_c = (prev_c or "") .. self.word_trim.before
    next_c = self.word_trim.after .. (next_c or "")
    self.context.buffer.prev_table = {}
    for _, ch in ipairs(util.splitToChars(prev_c)) do
        if not skipped_chars[ch] then table.insert(self.context.buffer.prev_table, ch) end
    end
    self.context.buffer.next_table = {}
    for _, ch in ipairs(util.splitToChars(next_c)) do
        if not skipped_chars[ch] then table.insert(self.context.buffer.next_table, ch) end
    end
    logger.info(("after reinit: prev table = %d, next table = %d"):format(#self.context.buffer.prev_table, #self.context.buffer.next_table))
end

function AnkiNote:set_custom_context(prev_s, prev_c, post_s, post_c)
    self.context.params.prev_s = prev_s
    self.context.params.prev_c = prev_c
    self.context.params.post_s = post_s
    self.context.params.post_c = post_c
end

function AnkiNote:add_tags(tags)
    for _,t in ipairs(tags) do
        table.insert(self.tags, t)
    end
end

-- each user extension gets access to the AnkiNote table as well
function AnkiNote:load_extensions()
    self.extensions = {}
    local extension_set = u.to_set(conf.enabled_extensions:get_value())
    for _, ext_filename in ipairs(self.ext_modules) do
        if extension_set[ext_filename] then
            local module = self.ext_modules[ext_filename]
            table.insert(self.extensions, setmetatable(module, { __index = function(t, v) return rawget(t, v) or self[v] end }))
        end
    end
end

-- This function should be called before using the 'class' at all
function AnkiNote:extend(opts)
    -- dict containing various settings about the current state
    self.ui = opts.ui
    -- used to save screenshots in (CBZ only)
    self.settings_dir = opts.settings_dir
    -- used to store extension functions to run
    self.ext_modules = opts.ext_modules
    return self
end

function AnkiNote:new(popup_dict)
    local new = {
        popup_dict = popup_dict,
        selected_dict = popup_dict.results[popup_dict.dict_index],
        context = {
            -- contains what the user wants to see, amount of sentences/characters before/after each word
            -- these params are modified in customcontextwindow.lua
            params = {
                prev_s = tonumber(conf.prev_sentence_count:get_value()),
                prev_c = 0,
                post_s = tonumber(conf.next_sentence_count:get_value()),
                post_c = 0,
                -- Size of each getSelectedWordContext fetch; doubles each time we exhaust it
                -- 25 → 50 → 100 → ...
                buffer_size = 25,
            },
            -- raw data as returned by KOReader
            -- Populated by init_context_buffer, consumed by get_custom_context.
            buffer = {
                -- array of (UTF-8) characters representing context before/after the selected word
                prev_table = {},
                next_table = {},
                -- True when init_context_buffer could not grow prev or next any further
                -- (reached the start/end of the document or there's no text layer).
                prev_exhausted = false,
                next_exhausted = false,
            },
        },
        -- indicates that popup_dict relates to word in book
        -- this can still be set to false later when the user looks up a word in a book, but then modifies the looked up word
        contextual_lookup = self.ui.highlight.selected_text ~= nil,
        word_trim = { before = "", after = "" },
        tags = { "KOReader" },
    }
    local new_mt = {}
    function new_mt.__index(t, v)
        return rawget(t, v) or self[v]
    end

    local note = setmetatable(new, new_mt)
    note:set_word_trim()
    note:load_extensions()
    return note
end

return AnkiNote
