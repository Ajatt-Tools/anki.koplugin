# Anki plugin for KOReader

[![Chat](https://img.shields.io/badge/chat-join-green?style=for-the-badge&logo=Telegram&logoColor=green)](https://ajatt.top/blog/join-our-community.html)

KOReader plugin enabling Anki note generation for words looked up in the internal dictionary.

Since [Ajatt-Tools](https://github.com/Ajatt-Tools) is a distributed effort, we **highly welcome new contributors**!
[Join the organization](https://github.com/Ajatt-Tools/.github/blob/main/profile/README.md#join-us),
feel free to browse the [issue tracker](https://github.com/Ajatt-Tools/anki.koplugin/issues) and submit pull requests.
You can also find us on [DJT](https://ajatt.top/blog/join-our-community.html).

## Installation

1) Install [AnkiConnect](https://ankiweb.net/shared/info/2055492159) to enable this plugin to communicate with Anki.

   **NOTE:** as mentioned in the Anki-Connect [documentation](https://foosoft.net/projects/anki-connect/), you will not be able to connect to Anki-Connect from your e-reader without updating the default settings.

   > By default, Anki-Connect will only bind the HTTP server to the 127.0.0.1 IP address, so that you will only be able to access it from the same host on which it is running.
   > If you need to access it over a network, you can change the binding address in the configuration.
   > Go to Tools->Add-ons->AnkiConnect->Config and change the “webBindAddress” value.
   > For example, you can set it to 0.0.0.0 in order to bind it to all network interfaces on your host. This also requires a restart for Anki.

2) Download the plugin, unzip it in the `koreader/plugins` directory, make sure the folder is named `anki.koplugin`, this is necessary for KOReader to load it.

   Alternatively, use KOReader's built in SSH server:

   ```sh
   git clone "https://github.com/Ajatt-Tools/anki.koplugin.git" ./anki.koplugin
   sshfs -p 2222 root@<IP-address>:/mnt/onboard/.adds/koreader <local_folder>
   # be careful to not add a trailing / to the source directory, this creates the folder on your device
   rsync -Pruv --exclude=".git/" ./anki.koplugin <local_folder>/plugins/
   ```

## Usage

When the plugin has been installed succesfully, there will be an extra button present on the reader's dictionary popup window, allowing the user to create an Anki note.

The plugin can be configured via the menu, under Search (looking glass icon) - Settings - Anki Settings. This is where you configure the anki-connect URL and optional [API key](https://git.sr.ht/~foosoft/anki-connect#authentication).


![image](https://user-images.githubusercontent.com/34285115/228915515-b6d3eef6-d9e3-4899-9922-db040a29f2b3.png)

When pressed, the add-on will generate a note for the looked up word.

![image](https://github.com/Ajatt-Tools/anki.koplugin/assets/34285115/641bbb46-d23f-488f-9c1a-72c2e9db4125)

## Features
The information extracted from the dictionary and book is sent to separate fields on the note.

Below is a list of all fields, along with the setting that defines which field on your note it ends up on.
These settings are configured via a user profile, see [Profiles](profiles/README.md) for more info.

<details>
  <summary>Available fields</summary>
  
  #### Selected word (`word_field`)
  The word selected in the book.
  #### Sentence context (`context_field`)
  The full sentence that the word occured in, extracted from the book.
  #### Translated Sentence (`translated_context_field`)
  The translation of the sentence context mentioned above. The target language is inherited from the translation settings in KOReader itself.
  #### Previous sentence count (`prev_sentence_count`)
  Define the amount of sentences which should be prepended to the word you looked up. Set this to `1` to have it complete the sentence the word occured in.
  #### Next sentence count (`next_sentence_count`)
  Define the amount of sentences which should be appended to the word you looked up. Set this to `1` to have it complete the sentence the word occured in.
  
  
  The exact context stored can be modified by pressing and holding the 'Add to Anki' button, and choosing the 'custom context' entry on the menu that pops up.
  
  #### Dictionary definition (`def_field`)
  The dictionary entry that was selected when pressing the button.
  #### Audio (`word_audio_field` / `sentence_audio_field` / drivers)
  When audio fields and drivers are configured, the plugin fetches pronunciation audio and attaches it to the note.

  - `word_audio_field` — Anki field that receives **word** audio (falls back to legacy `audio_field` if unset)
  - `sentence_audio_field` — Anki field that receives **sentence** audio
  - `word_audio_driver` / `sentence_audio_driver` — source to use (`forvo` by default for word, `none` for sentence). Set to `none` to skip. Additional drivers can be added under [`audio_drivers/`](audio_drivers/README.md).
  - `word_audio_driver_settings` / `sentence_audio_driver_settings` — per-driver options (e.g. VOICEVOX URL)

  In the KOReader menu these live under **General Settings → Audio → Word Audio / Sentence Audio**.

  The language used is determined by the dictionary's language, or by the book's language as fallback. Drivers may return either a remote URL or base64-encoded audio data for AnkiConnect.
  #### Metadata (`meta_field`)
  Some information about the book: author, title and page number.
  
  This info is retrieved from the EPUB's metadata, or by parsing the filename with a Lua pattern (`"^%[([^%]]-)%]_(.-)_%[([^%]]-)%]%.[^%.]+"`)
  
  The pattern expects filenames with the following format: `[Author]_Title_[extra_info].epub`. The extension can be anything.
</details>

### Offline usage
Notes are saved locally on the device when the remotely running Anki isn't available. When it becomes available again, the user will be reminded they have unsynced notes. 

This can also be done manually through the aforementioned settings.

### Extra options

As mentioned earlier, when pressing and holding the 'Add to Anki' button, a separate menu is shown:

![image](https://github.com/Ajatt-Tools/anki.koplugin/assets/34285115/932df377-c9fe-4083-8964-8536780b2920)

##### Custom tags
This allows the user to allows the user to create a card with custom tags.
##### Custom context
By default, the complete sentence the word occured in is stored on the note. In cases where this is too little or too much context, the user can modify it by pressing this button. This pops up a menu where the exact amount of text can be selected.
#### Undo latest note
It's also possible to undo the creation of the latest card, which can be handy when deciding you want to add some extra context to the note.
#### Change profile
Link the currently opened document with a different user profile.

## Configuration

Configuration is done by defining profiles, See [Profiles](profiles/README.md) for more info. This can also be done through the menu settings

When editing a profile which is *not* the default one, it's possible to 'unset' a setting (meaning it falls back on whatever is present in the `default.lua` profile). This is done by pressing and holding the setting you would like to reset.

## FAQ

<details>
  <summary>Plugin can't detect the language of the word</summary> 
  When the user has defined a value for `word_audio_field` (or legacy `audio_field`) or `sentence_audio_field` and selected an audio driver other than `none`, the plugin needs to know the language of the word you looked up, so it can look for the correct audio file.


  It looks for this language in 2 places
  - Stardict's `.ifo` file
  
    Each dictionary installed has its own folder consisting of, among other files, an `.ifo` file with some info about this dictionary, looking something like this:
    ```
    StarDict's dict ifo file
    version=2.4.2
    wordcount=18244
    idxfilesize=405703
    bookname=Dutch-English dictionary
    date=2009.01.30
    sametypesequence=x
    description=Copyright: Converted by swaj under GNU Public License; Version: 1.1
    ```
    In this case (Dutch-English), add the following line: `ifo_lang=nl-en` (just `ifo_lang=nl` would work too).
  
    This field is parsed by KOReader, and used by this plugin when available. This should already be present for dictionaries downloaded internally.
  
  - the language of the document
  
    In some documents, like `.epub` files, it is possible to define the language of the text with it. When this info is available, the plugin will use it.
  
    KOReader also allows you to edit a document's metadata manually, by opening the top menu > Hamburger menu > Book information > Tap and hold "Language" > Set custom.
  
    The expected format of this language is, like above, the ISO2 code. For example, to specify French, fill in 'fr'
  
  If you don't care about having audio, leave the audio fields blank or set the drivers to `none`. This will cause this step to be skipped completely.
    
</details>
