# Anki plugin for KOReader

KOReader plugin enabling Anki card generations for words looked up in the internal dictionary.

## Installation

1) Install [AnkiConnect](https://ankiweb.net/shared/info/2055492159) to enable this plugin to communicate with Anki.

   **NOTE:** as mentioned in the Anki-Connect [documentation](https://foosoft.net/projects/anki-connect/), you will not be able to connect to Anki-Connect from your e-reader without updating the default settings.

   > By default, Anki-Connect will only bind the HTTP server to the 127.0.0.1 IP address, so that you will only be able to access it from the same host on which it is running.
   > If you need to access it over a network, you can change the binding address in the configuration.
   > Go to Tools->Add-ons->AnkiConnect->Config and change the “webBindAddress” value.
   > For example, you can set it to 0.0.0.0 in order to bind it to all network interfaces on your host. This also requires a restart for Anki.

2) On GNU+Linux, run the following command.

   ```
   git clone "https://github.com/Ajatt-Tools/anki.koplugin.git" ~/.config/koreader/plugins/anki.koplugin
   ```

   On other systems replace the destination path.
3) To install the plugin on your e-reader, mount the device on your PC and locate the plugin folder
   - connect the reader via USB
   - use KOreader's built-in SSH server
   
   Enable the SSH server in the network tab on your device, it listens on port 2222 by default.
   
   The reader should inform you of the local IP address it's using as well.
   
   This snippet below assumes the plugin has been saved to the destination path from step 2.
   ```sh
   ssh -p 2222 root@<IP-address>:/mnt/onboard/.adds/koreader <local_folder>
   # be careful to not add a trailing / to the source directory, this creates the folder on your device
   rsync -Pruv --exclude=".git/" ~/.config/koreader/plugins/anki.koplugin <local_folder>/plugins/
   ```

## Usage

When the plugin has been installed succesfully, there will be an extra button present on the reader's dictionary popup window, which allows the user to create an Anki card.

When pressed, the add-on will try generating a card, using the selected dictionary entry.

![image](https://user-images.githubusercontent.com/34285115/228915515-b6d3eef6-d9e3-4899-9922-db040a29f2b3.png)
![image](https://user-images.githubusercontent.com/34285115/226706999-0ad0f63f-c1f9-4bf1-af86-180e4acc0bca.png)

### Features
Based on the word selected and the dictionary popup, some extra info can be sent to specific fields on an anki note.
The fields used are stored in `config.lua`. Each key mentioned below (e.g. `word_field`, `def_field`) are defined in this file, and refer to the actual name of the field the user's choice.

#### Sentence context
The plugin will parse the full sentence which the lookup word occurred in, this text can be sent to the `context_field`
#### Audio
The plugin will query Forvo to get audio for the lookupword, this audio can be stored in the `audio_field`
#### Metadata
The plugin will store some metadata about the document, this text can be sent to the `meta_field`.

The metadata is retrieved from the EPUB's metadata, or by parsing the filename with a Lua pattern (`"^%[([^%]]-)%]_(.-)_%[([^%]]-)%]%.[^%.]+"`)

The pattern expects filenames with the following format: `[Author]_Title_[extra_info].epub`. The extension can be anything.

#### Dictionary options
The plugin will send the word and definition of the currently selected dictionary to `word_field` and `def_field` respectively.

On top of that, it is also possible to send certain dictionary entries to specific fields on the anki note. This can be helpful if you want to send monolingual dictionary definitions to one field, and bilingual ones to another field.

The dictionaries for which this should happen can be stored in `dict_field_map`.

##### Overwrite content of dictionary definition
It's also possible to customize a dictionary's definition before storing it on a note. This can be done by providing a Lua pattern which should be replaced (or removed) from the definition. Another option is to provide a Lua function, taking the definition as a parameter, and which returns the new updated definition. 

Examples for both are present in `config.lua`

#### Offline usage
When the ereader's WiFi connection is turned off, or the PC where Anki is running on can't be reached, syncing the notes isn't possible.

In this scenario, the notes will be stored in JSON format locally on the device. When the connection becomes available again, these notes can be synced.

The plugin will notify the user when this is the case, prompting them to sync the notes. It's also possible to sync them manually by pressing and holding the 'Add to Anki' button. This will display an extra popup window with some extra options.

![image](https://user-images.githubusercontent.com/34285115/226709541-878ea391-7cab-429b-9583-804852375cc3.png)


## Configuration

User configuration is stored in the `config.lua` file. Take care not to break the Lua syntax!

Do not delete any keys (e.g. `word_field`, `kana_pattern`, ...) from the file. The plugin expects each key to be present, so stuff may break when  removed.

If you don't want a certain note field or override option to be applied, leave the option blank (either the empty string `""` or an empty table `{}`).
Fields which are not present on the chosen Anki note type, will be silently ignored, so they can also be left as-is.

### Edit configuration within KOreader
There is code in place to create a menu, with which some of the fields can be edited on the reader itself. Adding an option in the KOreader's menu isn't possible from within a standalone plugin, but it can be done with a [user patch](https://github.com/koreader/koreader/wiki/User-patches).

Save the code snippet below in a file with the name `2-anki-menu-patch.lua`. This file should be stored in `koreader/patches`.

```lua
local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")
local ReaderMenuOrder = require("ui/elements/reader_menu_order")

table.insert(FileManagerMenuOrder.search, 5, "anki_settings")
table.insert(ReaderMenuOrder.search, 5, "anki_settings")
```

If everything goes right, this should add an extra option to the search menu:
![2023-03-30_19-57](https://user-images.githubusercontent.com/34285115/228923486-bc6f87ec-f65a-4789-bcb5-e053ba36aa5c.png)

**NOTE**

When updating one of the settings on the reader itself, this setting will be stored in KOreader's `settings` folder, under the name `ankiconnect.lua`.
This means that the value in `config.lua` may not be the one that's used by the plugin. KOreader's settings folder takes precedence.

This `ankiconnect.lua` file can safely be deleted, in which case the 'default' settings from `config.lua` will be used again.
