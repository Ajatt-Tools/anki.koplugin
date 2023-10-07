local logger = require("logger")
local util = require("util")
local u = require("lua_utils/utils")

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

    local delims_map = u.to_set(util.splitToChars("？」。.?!！"))
    -- calculate the slice of the `prev_context_table` array that should be prepended to the lookupword
    local prev_idx, prev_s_idx = 0, 0
    while prev_s_idx < pre_s do
        if #self.prev_context_table <= prev_idx then expand_content() end
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
    if #self.prev_context_table <= prev_idx then expand_content() end
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
        [self.word_field:get_value()] = self.popup_dict.word,
        [self.def_field:get_value()] = self:get_definition()
    }
    local optional_fields = {
        [self.context_field] = function() return self:get_word_context() end,
        [self.meta_field]    = function() return self:get_metadata() end,
    }
    for opt,fn in pairs(optional_fields) do
        local field_name = opt:get_value()
        if field_name then
            fields[field_name] = fn()
        end
    end
    local note = {
        -- some fields require an internet connection, which we may not have at this point
        -- all info needed to populate them is stored as a callback, which is called when a connection is available
        _field_callbacks = {
            audio = { func = "set_forvo_audio", args = { self.popup_dict.word, self:get_language() } },
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
    local note_extended = self:run_extensions(note)
    return { action = "addNote", params = { note = note_extended }, version = 6 }
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
    local skipped_chars = u.to_set(util.splitToChars(("\n\r")))
    local prev_c, next_c = self.ui.highlight:getSelectedWordContext(size)
    -- pass trimmed word context along to be modified
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

-- each user extension gets access to the AnkiNote table as well
function AnkiNote:load_extensions()
    self.extensions = {}
    local extension_set = u.to_set(self.enabled_extensions:get_value())
    for _, ext_filename in ipairs(self.ext_modules) do
        if extension_set[ext_filename] then
            local module = self.ext_modules[ext_filename]
            table.insert(self.extensions, setmetatable(module, { __index = function(t, v) return rawget(t, v) or self[v] end }))
        end
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
    -- used to store extension functions to run
    self.ext_modules = opts.ext_modules
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
    note:load_extensions()
    -- TODO this can be delayed
    note:init_context_buffer(note.context_size)
    note:set_custom_context(1, 0, 1, 0)
    return note
end

return AnkiNote
