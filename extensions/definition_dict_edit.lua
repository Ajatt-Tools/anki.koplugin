--[[
-- This extension can be used to replace certain patterns in specific dictionaries.
-- for each dict listed in `enabled_dictionaries`, all patterns in `patterns` are deleted
--]]
return function(self, definition)
    local enabled_dictionaries = {
        ["新明解国語辞典　第五版"] = true,
        ["スーパー大辞林　3.0"] = true,
    }
    local selected_dict = self.popup_dict.results[self.popup_dict.dict_index].dict
    if not enabled_dictionaries[selected_dict] then
        return definition
    end
    local patterns = {
        '%[[0-9]%]',
        '%[[0-9]%]:%[0-9%]'
    }
    for _,pattern in ipairs(patterns) do
        definition = definition:gsub(pattern, '')
    end
    return definition
end
