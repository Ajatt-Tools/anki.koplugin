# Extensions

Custom behavior for note creation.

Any .lua file present in the ./extensions folder will be loaded by the add-on, provided the filename starts with the "EXT_" prefix.

## Format

An extension has the following format:

```lua
local CustomExtension = {
    definition = "This extension does a thing to the note!" -- this can be left out
}
-- this is called when user creates a note
function CustomExtension:run(note)
    -- make some additions to note we are about to save..
    return note
end
return CustomExtension
```

### The `note` parameter

the `run` function shown above takes a `note` parameter.
This parameter is a Lua table containing all the data that will be sent to Anki.
The contents of this table are based on the 'note' parameter in the JSON request that is sent to anki-connect.
An example can be seen in the [documentation](https://github.com/FooSoft/anki-connect#addnote) of the `addNote` action.
The 'note' parameter in the example request has the same fields as the Lua table parameter.

### AnkiNote context

On loading the user extensions, the user is also given access to the AnkiNote table as well (see ankinote.lua).

This code can be accessed through the `self` parameter.

In the example below, the extension prints the dictionary name received through this paramter.

```lua
local Extension = {}
function Extension:run(note)
    local selected_dict = self.popup_dict.results[self.popup_dict.dict_index].dict
    print(("Currently selected dictionary: %s"):format(selected_dict))
    return note
end
return Extension
```
