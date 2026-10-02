# HolyAlert

<p align="center"><img src="docs/holy-alert-logo.png" alt="HolyAlert logo" width="256"></p>

World of Warcraft addon (Retail 12.1, Midnight) for **Retribution Paladins**. When the set bonus effect **Divine Arbiter** makes an ability glow, HolyAlert plays a sound:

- **Divine Storm** – use it now (lights up after you cast Final Verdict), and
- **Final Verdict** – use it now (lights up after you cast Divine Storm).

The buff runs out after a few seconds, so the glowing ability has to be used before then. Sound only, nothing is shown on the screen.

## Features

- **Two alerts** with their own sound, each can be turned on or off
- **Only with Divine Arbiter** (on by default): ignores glows that do not come from the set bonus, for example Final Verdict lighting up at the start of a fight
- **Bundled voice alerts** in English and German; the default follows your client language (German client: German voice, otherwise English)
- **Your own sounds:** up to five files in a separate folder that survives addon updates
- **LibSharedMedia:** every sound registered by other addons can be used, and HolyAlert's own sounds are registered there for other addons
- **WoW sounds:** a few built-in game sounds such as Raid Warning or Ready Check
- **Sound channel:** Master (default), SFX, Dialog, Music or Ambience
- **Only in combat** (on by default)
- **Chat messages** on login and when testing are optional (off by default)
- **Only active for Retribution Paladins;** silent for all other classes and specializations
- **Languages:** English and German

## Installation

Install HolyAlert from [CurseForge](https://curseforge.com/project/1721994) (for example with the CurseForge app), or download the zip from the [Releases](../../releases) page and extract it to `World of Warcraft\_retail_\Interface\AddOns\`.

The zip contains all required libraries. A plain copy of the repository does **not** work, because the libraries are only added by the packager.

## Usage

### Settings

Type `/holyalert` (or `/ha`, if no other addon uses it) or open *Settings > AddOns > HolyAlert*. Changes apply immediately.

- **Status line** at the top: shows the detected specialization, or a note that HolyAlert is inactive on this character (not a Retribution Paladin).
- **Divine Storm** and **Final Verdict:** turn the alert on or off, choose its sound, *Test* button.
- **General:** only with Divine Arbiter, sound channel, only in combat, chat messages, *Test both* button.
- **Custom sounds:** where to put your own files (see below).
- **Debug:** debug mode and *Clear log*.

Settings are stored per character automatically.

**Chat messages** (off by default) shows the "loaded" message on login and a message when testing. Replies to `/holyalert` commands and error hints (for example a missing custom sound) are always shown.

The sound list contains, in this order: the bundled HolyAlert sounds, your own sounds, WoW sounds and all sounds registered with LibSharedMedia by other addons. If a chosen sound is no longer available (for example because the addon that provided it was removed), it is shown as *(missing)* and the default sound is played instead; your choice is kept.

### Commands

| Command | Effect |
|---|---|
| `/holyalert` | Open the settings |
| `/ha` | Short form of `/holyalert`, only if no other addon uses `/ha` |
| `/holyalert help` | List the commands |
| `/holyalert status` | Show whether HolyAlert is active and the current settings |
| `/holyalert test [storm\|verdict]` | Play both alerts one after the other (or only one) |
| `/holyalert sounds` | List all available sounds with their numbers |
| `/holyalert sound storm\|verdict <number>` | Choose a sound from the list; `default` restores the default |
| `/holyalert toggle storm\|verdict` | Turn an alert on or off |
| `/holyalert judge on\|off` | Only with Divine Arbiter |
| `/holyalert channel master\|sfx\|dialog\|music\|ambience` | Sound channel |
| `/holyalert combat on\|off` | Only play alerts in combat |
| `/holyalert debug on\|off\|clear\|status` | Debug log (`HolyAlertDebugLog` in SavedVariables, off by default) |

Changes made with commands are shown in the open settings window right away.

### Your own sounds

1. Create the folder `World of Warcraft\_retail_\Interface\AddOns\HolyAlert_Sounds\`.
2. Put your files there as `sound1.ogg` to `sound5.ogg` (the names are fixed).
3. **Restart WoW completely.** `/reload` does not detect new files.
4. Choose them in the settings (*Custom: sound1.ogg* …) or with `/holyalert sounds` and `/holyalert sound storm <number>`.

The folder is separate from the `HolyAlert` folder, so updates do not touch your files. If a chosen file is missing, HolyAlert tells you once in the chat.

## How it works

HolyAlert listens to the spell activation glow of the game (`SPELL_ACTIVATION_OVERLAY_GLOW_SHOW`), the same glow you see on your action button:

| Alert | Glowing spell ID | Your own cast before it |
|---|---|---|
| Divine Storm | 53385 | Final Verdict 383328 or Templar's Verdict 85256 |
| Final Verdict | 383328 or 85256 (both glow together, one sound) | Divine Storm 53385 |

A sound is played only when the glow appears, not when it disappears. Each alert is blocked for 2 seconds after it played.

**Only with Divine Arbiter:** the Divine Arbiter buff cannot be read in combat. In game tests the glow always appeared in the same frame as your own cast of the other ability (`UNIT_SPELLCAST_SUCCEEDED`). With this option on, HolyAlert only plays when the two events are at most 0.3 seconds apart, in either order. Glows without that cast, such as Final Verdict lighting up together with Avenging Wrath at the start of a fight, stay silent. With the option off, every matching glow plays.

The spell IDs and the timing were worked out in game with a test addon (`docs/reference/GlowTest.lua`).

HolyAlert is active when your character is a Paladin in the Retribution specialization (ID 70). This is checked on login and again when you change your specialization or talents.

## Development

Libraries are fetched by the [BigWigs packager](https://github.com/BigWigsMods/packager) from `.pkgmeta` and are not part of the repository: LibStub, CallbackHandler-1.0, AceDB-3.0, AceGUI-3.0, AceConfig-3.0, LibSharedMedia-3.0.

### Releases

Pushing a tag `v*` (for example `v1.0.0`, test builds `v1.0.0-beta.N`) starts `.github/workflows/release.yml`. It builds a zip with all libraries, the bundled sounds and the icon, publishes it as a GitHub release and uploads it to [CurseForge](https://curseforge.com/project/1721994).

**CurseForge upload:** the packager uploads to CurseForge when both a token and a project ID are present:

- the project ID is set in `HolyAlert.toc` (`## X-Curse-Project-ID: 1721994`),
- the API token is stored as the Actions secret **`CF_API_TOKEN`** (*Settings > Secrets and variables > Actions*) and passed to the packager by the workflow. A new token can be created at <https://authors.curseforge.com/#/settings/api-tokens>.

## License

MIT, see [LICENSE](LICENSE).
