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
   
   This snippet belows assumed you've downloaded the plugin already to the destination path from step 2.
   ```sh
   ssh -p 2222 root@<IP-address>:/mnt/onboard/.adds/koreader <local_folder>
   # be careful to not add a trailing / to the source directory, this creates the folder on your device
   rsync -Pruv --exclude=".git/" ~/.config/koreader/plugins/anki.koplugin <local_folder>/plugins/
   ```
