# Changelog

## 1.1.1

- Compatible with patch 12.1.5 (Interface 120105)
- The addon version is shown in the settings

## 1.1.0

- **New alert: Blade of Justice** (off by default). Plays a sound when Blade of Justice (spell 184575) becomes available again through a proc, for example Art of War, and starts to glow. Only when the glow appears, with a 2-second block. "Only with Divine Arbiter" does not apply to this alert.
- Bundled English and German voice alerts for Blade of Justice, also registered with LibSharedMedia.
- Settings: new group *Blade of Justice* with on/off, sound and *Test*. *Test both* is now *Test all*. The tooltip of "Only with Divine Arbiter" says that it only applies to Divine Storm and Final Verdict.
- Chat commands `test`, `sound` and `toggle` accept `blade`.
- Debug log: your own Blade of Justice casts and the time since the last cast on each glow.

## 1.0.0-beta.1

First test build.

- **Alerts:** plays a sound when Divine Storm (spell 53385) or Final Verdict (spells 383328 and 85256, one sound) starts to glow. Only when the glow appears, with a 2-second block per alert.
- **Only with Divine Arbiter** (on by default): the buff cannot be read in combat, so HolyAlert only plays when the glow comes within 0.3 seconds of your own cast of the other ability (Final Verdict lights up Divine Storm and the other way round). Glows without that cast, for example at the start of a fight, stay silent.
- **Retribution only:** active for Paladins in the Retribution specialization; silent for all other classes and specializations. Checked on login, specialization change and spell changes.
- **Sounds:** bundled English and German voice alerts (default follows the client language), up to five own sounds in `Interface\AddOns\HolyAlert_Sounds\`, all LibSharedMedia sounds and a few WoW sounds. The bundled sounds are registered with LibSharedMedia.
- **Settings** under *Settings > AddOns > HolyAlert* or with `/holyalert`: per alert on/off, sound and *Test* button; only with Divine Arbiter, sound channel (Master by default), only in combat (on by default), chat messages (off by default) and *Test both*; note on custom sounds; debug mode and *Clear log*. Settings are stored per character.
- **Chat commands** `/holyalert` (short form `/ha` if no other addon uses it): `help`, `status`, `test`, `sounds`, `sound`, `toggle`, `judge`, `channel`, `combat`, `debug`.
- **Debug mode** (off by default) that writes a log to the SavedVariables, including the measured time between glow and cast.
- **Addon icon** in the AddOns list.
- **Languages:** English and German.
