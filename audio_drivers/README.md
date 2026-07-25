# Audio Drivers

Pluggable pronunciation audio sources for note creation.

Any `.lua` file in this folder is loaded at plugin startup (except documentation). Each file must return a driver module.

## Format

```lua
local MyDriver = {
    id = "my_driver",           -- unique id stored in the profile
    name = "My Driver",         -- shown in the Audio Driver menu
    description = "Optional longer description (shown on hold).",
    -- optional: settings shown under Audio Driver Settings when this driver is selected
    settings = {
        {
            id = "api_key",
            name = "API Key",
            conf_type = "text",  -- "text" (default) or "bool"
            description = "API key for the service.",
        },
    },
}

-- ctx: { word, language, field, fields, settings }
--   fields = note field map after extensions have run (may be used as synthesis input)
-- returns: ok, audio_or_nil_or_err
function MyDriver:get_audio(ctx)
    local api_key = ctx.settings.api_key
    -- soft skip (no audio available):
    --   return true, nil
    -- hard failure (abort note sync):
    --   return false, "error message"

    -- URL form (Anki downloads the file):
    return true, {
        url = "https://example.com/audio.ogg",
        filename = ("my_%s.ogg"):format(ctx.word),
    }

    -- Or base64 form (Anki stores the bytes directly):
    -- return true, {
    --     data = "<base64-encoded audio bytes>",
    --     filename = ("my_%s.mp3"):format(ctx.word),
    -- }
end

return MyDriver
```

## Return values

`get_audio` must return two values:

| Result | Meaning |
|--------|---------|
| `true, { url = "...", filename = "..." }` | Attach audio via remote URL |
| `true, { data = "<base64>", filename = "..." }` | Attach audio via base64-encoded file bytes |
| `true, nil` | Soft skip — create the note without audio |
| `false, "message"` | Hard failure — surface the error to the user |

Provide either `url` or `data` (not both). Do **not** set `fields`; the plugin attaches the configured audio field.

## Settings

Driver settings are stored per profile under `audio_driver_settings[driver_id]`. Values are passed to `get_audio` as `ctx.settings`.

Supported `conf_type` values in the `settings` schema: `text`, `bool`.

## Built-in drivers

- [`forvo.lua`](forvo.lua) — scrapes forvo.com and returns an OGG URL
- [`voicevox.lua`](voicevox.lua) — synthesizes WAV audio via a VOICEVOX Engine (`url`, `speaker_id`, optional `word_field` / `pitch_field` for reading + pitch accent); returns base64 data
