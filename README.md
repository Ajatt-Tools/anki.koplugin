# Anki plugin for KOReader

KOReader plugin enabling Anki note generation for words looked up in the internal dictionary.

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

When the plugin has been installed succesfully, there will be an extra button present on the reader's dictionary popup window, allowing the user to create an Anki note.


![image](https://user-images.githubusercontent.com/34285115/228915515-b6d3eef6-d9e3-4899-9922-db040a29f2b3.png)

When pressed, the add-on will generate a note for the looked up word.

![image](https://github.com/Ajatt-Tools/anki.koplugin/assets/34285115/641bbb46-d23f-488f-9c1a-72c2e9db4125)

## Features
The information extracted from the dictionary and book is sent to separate fields on the note.

Below is a list of all fields, along with the configuration option that defines which field on your note it ends up on.
The configuration options are stored in `config.lua`. Each key mentioned below (e.g. `word_field`, `def_field`) is defined in this file.


#### Selected word (`word_field`)
The word selected in the book.
#### Sentence context (`context_field`)
The full sentence that the word occured in, extracted from the book.

The exact context stored can be modified by pressing and holding the 'Add to Anki' button, and choosing the 'custom context' entry on the menu that pops up.

#### Dictionary definition (`def_field`)
The dictionary entry that was selected when pressing the button.
#### Audio (`audio_field`)
The plugin will query Forvo to get audio for the lookupword. The language used is determined by the dictionary's language, or by the book's language as fallback.
#### Metadata (`meta_field`)
Some information about the book: author, title and page number.

This info is retrieved from the EPUB's metadata, or by parsing the filename with a Lua pattern (`"^%[([^%]]-)%]_(.-)_%[([^%]]-)%]%.[^%.]+"`)

The pattern expects filenames with the following format: `[Author]_Title_[extra_info].epub`. The extension can be anything.

### Offline usage
When the e-reader can't save the card to Anki directly, because the WiFi connection is turned off, or the PC running Anki is unreachable, the created note is stored locally.

The moment Anki is reachable again, the plugin will ask the user if they want to sync the notes stored locally. This can also be done manually by pressing and holding the 'Add to Anki' button and choosing the 'Sync offline notes' option.

### Extra options

As mentioned earlier, when pressing and holding the 'Add to Anki' button, a separate menu is shown:

![image](https://github.com/Ajatt-Tools/anki.koplugin/assets/34285115/932df377-c9fe-4083-8964-8536780b2920)

##### Sync offline notes
This option can be used to send the locally stored notes to Anki.
##### Custom tags
This allows the user to allows the user to create a card with custom tags, which are defined in `config.lua`
##### Custom context
By default, the complete sentence the word occured in is stored on the note. In cases where this is too little or too much context, the user can modify it by pressing this button. This pops up a menu where the exact amount of text can be selected.
#### Undo latest note
It's also possible to undo the creation of the latest card, which can be handy when deciding you want to add some extra context to the note.

## Configuration

User configuration is stored in the `config.lua` file. Take care not to break the Lua syntax!

Do not remove any entries which are marked as REQUIRED in the explanatory comment. Doing so will cause the plugin to fail to load.
Other entries can be safely omitted, any missing fields will not be generated.

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
