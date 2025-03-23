local conf = require("anki_configuration")
local DictEdit = {
    description = "This extension can be used to replace certain patterns in specific dictionaries.",
    enabled_dictionaries = {
        ["新明解国語辞典　第五版"] = true,
        ["スーパー大辞林　3.0"] = true,
    },
    patterns = {
        '%[[0-9]%]',
        '%[[0-9]%]:%[0-9%]'
    }
}

function DictEdit:run(note)
    local selected_dict = self.popup_dict.results[self.popup_dict.dict_index].dict
    if not self.enabled_dictionaries[selected_dict] then
        return note
    end
    local def = note.fields[conf.def_field:get_value()]
    for _,pattern in ipairs(self.patterns) do
        def = def:gsub(pattern, '')
    end
    note.fields[conf.def_field:get_value()] = def
    return note
end

return DictEdit
