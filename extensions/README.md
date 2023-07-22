# Extensions

The user is able to modify a note before it is saved by creating a lua function and saving it in a file in the `extensions` directory.
The name of the file should start with either `definition_` or `note_` (depending on the type of modifier, see below), and end with the `.lua` extension.

When multiple files are present. The definition modifiers are run first, then the note modifiers are run. Each category is run in alphabetical order.

## Definition modifiers
This type of modifier allows the user to make changes to the definition (`def_field`) of a note before it is saved.

This modifier is a function which takes 2 parameters:
 - self: this is a note instance created by the plugin. This can be used to:
    * get the dictionary name of the current lookup
    * get the value of any user configurable field
    * ...
 - definition: this is the text stored in the `def_field` of the note.

 The function returns a string, which will become the new updated text in the `def_field`.

### examples

This function does a simple find and replace on the definition.
```lua
return function(_, definition)
    local updated_definition = string.gsub(definition, "[a-Z]+", "replacement")
    return updated_definition
end
```

This function adds the name of the dictionary to the definition's text.
```lua
return function(self, definition)
    local dictionary_name = self.selected_dict.dict
    return ("FROM DICTIONARY '%s': %s"):format(dictionary_name, definition)
end
```

## Note modifiers
This type of modifier allows the user to arbitrarily modify any of the data stored on the note.


This type of modifier is a function which takes 2 parameters:

 - self: this is a note instance created by the plugin.
 - note: this a Lua table representing the note in the format anki-connect expects it to be. This is converted to JSON later on.
    An example of this table can be seen by looking at the 'note' parameter in the [sample request|https://github.com/FooSoft/anki-connect#addnote] of the `addNote` action for anki-connect itself.

 The function returns a table, which will become the updated note.

### examples

This function updates the created note by adding an extra tag to the note.
```lua
    return function(self, note)
        table.insert(note.tags, "SUPER_CUSTOM_TAG")
        return note
    end
```
