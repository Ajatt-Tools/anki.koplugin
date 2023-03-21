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
![image](https://user-images.githubusercontent.com/34285115/226706945-27d58e16-98cf-4f60-a43a-1bf69f533f77.png)


When pressing the button, the add-on will create a card with the word you looked up, with the sentence as context, and with some metadata parsed from the epub itself.

![image](https://user-images.githubusercontent.com/34285115/226706999-0ad0f63f-c1f9-4bf1-af86-180e4acc0bca.png)

The add-on will also parse Pitch Accent info from the dictionary if it's present, and if it's configured correctly (see section below).

The add-on will also query forvo, and add audio to your note if it found any.

It is also possible to send specific dictionaries to specific fields on an Anki note if so desired.
This is convenient if you like to also have an English definition as backup.

### Offline usage
When the add-on isn't able to reach Anki, it will store the note locally on the device. 

The notes will then be synced later when possible, the user will be prompted if they want to sync their notes. This prompt occurs the first time the user creates a note which was able to be synced succesfully.

It's also possible to attempt syncing your locally stored notes manually, by pressing and holding the 'Add to Anki' button.
![image](https://user-images.githubusercontent.com/34285115/226709541-878ea391-7cab-429b-9583-804852375cc3.png)


## Configuration

Editing the default configuration can be done by editing the `AnkiDefaults` table in the `ankidefaults.lua` file.

```lua
local AnkiDefaults = {
    -- remember to expose the port ankiconnect listens on so we can connect to it
    -- also, the ankiconnect settings need to be updated to not only listen on the loopback address
    AnkiConfigOpt:new {
        id = "url",
        group = general_settings,
        name = "AnkiConnect URL",
        description = "The URL anki_connect is listening on.",
        default = "http://localhost:8765",
    },
```
the `default` field in each `AnkiConfigOpt` entry can be modified to the user's preference. 

The `description` provided should make this pretty self explanatory.
