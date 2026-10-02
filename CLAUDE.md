# CLAUDE.md – Arbeitsanweisung für HolyAlert

Du baust das WoW-Addon **HolyAlert** (Retail 12.1.0, Interface `120100`) **vollständig in einem Durchgang**. Die fachliche Beschreibung steht in `SPEC.md`. Lies sie vollständig, bevor du Code schreibst.

## Rollen

- **Dominique:** testet im Spiel, mergt Pull Requests, erstellt Releases (Tags).
- **Koordinator** (Claude in Cowork): prüft Code, Builds und Debug-Logs, schreibt Folgeaufgaben.
- **Du:** setzt um, **ein** Pull Request mit dem kompletten Addon. **Keine Tags pushen.**

## Vorlage

**https://github.com/Okoith/wow-VoidAlert** (v1.0.0) ist fast dasselbe Addon und im Spiel getestet: zwei Alarme über `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW`, Sounds aus vier Quellen, Menü, Debug, Locales, Chat-Option, keine Profile-Seite, Workflow. **Übernimm Aufbau und Code von dort** und passe ihn an. Unterschiede zu VoidAlert:

1. Andere Spell-IDs und Klasse/Spec (SPEC 3)
2. **Neu:** Option „Nur bei Göttlicher Richter“ mit zeitlicher Kopplung an den eigenen Gegenzauber (SPEC 3.2)
3. Addon-Symbol (`IconTexture`), das VoidAlert 1.0.0 noch nicht hat (SPEC 7)

Für Kicks/Casts des Spielers und die Kopplung kann wow-KickCall (`Alerts.lua`, `OnPlayerSpell`) als zweite Vorlage dienen.

`docs/reference/GlowTest.lua` ist das Testaddon, mit dem die Fakten in SPEC 2 ermittelt wurden.

## Vorhandene Dateien im Repo

- `sounds/` enthält die Sprachansagen, aber mit uneinheitlichen Namen. **Per `git mv` umbenennen**, Inhalt nicht verändern:
  - `strom_de.ogg` → `storm_de.ogg`
  - `strom_en.ogg` → `storm_en.ogg`
  - `Verdict_de.ogg` → `verdict_de.ogg`
  - `Verdict_en.ogg` → `verdict_en.ogg`
- `docs/holy-alert_logo.png`: Logo (PNG mit Alpha). Daraus `media/icon.png` erzeugen (SPEC 7). Hat das Logo keinen Alphakanal, im PR darauf hinweisen.
- `LICENSE` (MIT) und `README.md` sind vorhanden. README komplett neu schreiben.

## Harte Regeln

1. Auslöser nur `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` und für die Kopplung `UNIT_SPELLCAST_SUCCEEDED` des Spielers. **Keine Auren abfragen** (im Kampf gesperrt, SPEC 2).
2. Werte, die geheim sein können, vor jedem Vergleich, jeder Verkettung und jedem Wahrheitstest mit `issecretvalue` prüfen.
3. Alle Aufrufe von Spiel-APIs und `PlaySoundFile`/`PlaySound` in `pcall`.
4. Keine geheimen Werte in SavedVariables.
5. Nichts raten: Unklare APIs defensiv absichern und im Debugmodus loggen.

## Ergebnis

- Komplettes Addon inkl. `.pkgmeta`, `.github/workflows/release.yml`, `embeds.xml`, TOC, Locales enUS/deDE, README und CHANGELOG (Englisch)
- Version im CHANGELOG: `1.0.0-beta.1`
- Ein Pull Request mit kurzer Testanleitung für Dominique (Test-Buttons, Debug an, Kampf an der Übungspuppe, `/reload`, Log)
