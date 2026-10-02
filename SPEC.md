# HolyAlert – Spezifikation v1.0

Stand: 02.10.2026 · WoW Retail 12.1.0 (Interface `120100`)

## 1. Ziel

HolyAlert spielt für Paladine in der Spezialisierung **Vergeltung** (Spec-ID 70) einen Sound, sobald durch den Set-Bonus-Effekt **Göttlicher Richter** eine Fähigkeit aufleuchtet:

- **A) Göttlicher Sturm** soll jetzt eingesetzt werden
- **B) Letztes Urteil** soll jetzt eingesetzt werden

Der Mechanismus geht über Kreuz: Proct Göttlicher Richter beim Einsatz von **Letztes Urteil**, leuchtet danach **Göttlicher Sturm** auf, und umgekehrt. Der Buff läuft nach einigen Sekunden ab (Dauer im Tooltip sichtbar). Bis dahin muss die aufleuchtende Fähigkeit benutzt werden. Nur Sound, keine Anzeige auf dem Bildschirm.

## 2. Getestete Fakten (Testaddon `docs/reference/GlowTest.lua`, Paladin Vergeltung, 3 Kämpfe)

| Was | Ergebnis | Folge |
|---|---|---|
| `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` | Spell-ID im Kampf **lesbar** | Auslöser |
| Göttlicher Sturm leuchtet | ID **53385** | Alarm A |
| Letztes Urteil leuchtet | ID **383328**, immer gleichzeitig mit **85256** (Urteil des Templers, Basis-ID) | Alarm B, beide IDs zählen, nur ein Sound |
| `UNIT_SPELLCAST_SUCCEEDED` für `player` | Spell-ID lesbar (53385, 383328 bestätigt) | Kopplung, siehe 3.2 |
| Buff „Göttlicher Richter“ | im Kampf **nicht lesbar**: `GetAuraDataByIndex` meldet „Auras cannot be accessed when secret while tainted“, `addedAuras` im `UNIT_AURA`-Payload ist geheim, `C_Secrets.ShouldAurasBeSecret()` = true | Buff **nicht** abfragen |
| Andere Leuchten | 184575 Klinge der Gerechtigkeit, 24275/1241413/1279408 Hammer des Zorns | ignorieren |
| Letztes Urteil leuchtet auch **ohne** Göttlicher Richter | z. B. zu Kampfbeginn zusammen mit Zornige Vergeltung (31884), ohne vorherigen Göttlichen Sturm | durch Kopplung herausfiltern |

Zeitliche Kopplung aus den Logs (gleicher Zeitstempel auf 0,01 s):

```
Letztes Urteil gewirkt   7.92  →  GLOW_SHOW 53385 (Sturm)  7.92
Letztes Urteil gewirkt  22.63  →  GLOW_SHOW 53385          22.63
Göttlicher Sturm gewirkt 25.91 →  GLOW_SHOW 383328 (Urteil) 25.91
Göttlicher Sturm gewirkt 75.63 →  GLOW_SHOW 383328          75.63
```

Das Leuchten endet mit `GLOW_HIDE`, sobald die Fähigkeit benutzt wird.

## 3. Erkennung

### 3.1 Alarme

| Alarm | Leuchten (`GLOW_SHOW`) | Gegenzauber (eigener Cast) |
|---|---|---|
| `storm` | 53385 | 383328 oder 85256 |
| `verdict` | 383328 oder 85256 | 53385 |

- Spell-ID vor jedem Vergleich mit `issecretvalue` prüfen.
- Sound nur bei `GLOW_SHOW`, nicht bei `GLOW_HIDE`.
- Pro Alarm Sperre von 2 s (383328 und 85256 kommen gleichzeitig, nur ein Sound).

### 3.2 Option „Nur bei Göttlicher Richter“ (Standard: **an**)

Weil der Buff nicht lesbar ist, wird er über die zeitliche Kopplung erkannt:

- Bei jedem eigenen `UNIT_SPELLCAST_SUCCEEDED` (unit `"player"`) mit einer Gegenzauber-ID den Zeitpunkt `GetTime()` merken.
- Bei `GLOW_SHOW` eines Alarms: Liegt der passende Gegenzauber höchstens **0,3 s** zurück → Sound.
- Die Reihenfolge der beiden Ereignisse im selben Frame ist nicht garantiert. Deshalb zusätzlich: Kommt das Leuchten zuerst, den Alarm 0,3 s als „wartend“ merken. Kommt in dieser Zeit der passende Gegenzauber → Sound. Sonst verfällt der Alarm (Debug: `noCoupling`).
- Ist die Option **aus**, wird bei jedem passenden Leuchten gespielt.
- Fenster 0,3 s als Konstante, im Debug-Log immer den gemessenen Abstand mitschreiben.

### 3.3 Aktiv nur für Vergeltung

- Aktiv, wenn Klasse `PALADIN` und Spec-ID **70** (im Test bestätigt: 70 = Vergeltung). Prüfung bei `PLAYER_LOGIN`, `PLAYER_SPECIALIZATION_CHANGED`, `SPELLS_CHANGED` (bei `ADDON_LOADED` ist die Spec noch 0, Erfahrung aus VoidAlert).
- Sonst still. Im Menü Hinweis „Nur für Paladine (Vergeltung)“.

## 4. Sounds (wie VoidAlert)

Eine gemeinsame Auswahlliste aus:

1. **Mitgelieferte Sprachansagen** in `sounds/`: `storm_de.ogg`, `storm_en.ogg`, `verdict_de.ogg`, `verdict_en.ogg` (Ogg Vorbis, mono, 44,1 kHz, je ca. 1,8 s). Zusätzlich bei LibSharedMedia registrieren, Namen z. B. „HolyAlert: Divine Storm (DE)“.
2. **Eigene Sounds** in `Interface\AddOns\HolyAlert_Sounds\sound1.ogg` bis `sound5.ogg`
3. **LibSharedMedia-3.0** (Typ `sound`)
4. **WoW-Sounds** über `SOUNDKIT`, nur wenn zur Laufzeit vorhanden

Standard nach Client-Sprache: `deDE` → `_de`, sonst `_en`. Abspielen mit `PlaySoundFile`/`PlaySound` in `pcall`, Kanal wählbar.

## 5. Einstellungen (AceConfig, Einstellungen → AddOns → HolyAlert)

- Hinweis oben: Status (aktiv / „Nur für Paladine (Vergeltung)“)
- **Göttlicher Sturm:** an/aus, Sound, Testen
- **Letztes Urteil:** an/aus, Sound, Testen
- **Allgemein:**
  - „Nur bei Göttlicher Richter“ (Standard an), Tooltip erklärt die Kopplung in einem Satz
  - Kanal: Master (Standard), SFX, Dialog, Music, Ambience
  - Nur im Kampf (Standard an)
  - Chat-Meldungen (Standard aus: Login- und Testmeldung. Antworten auf Befehle und Fehlerhinweise immer sichtbar)
  - Beide testen
- **Eigene Sounds:** Hinweistext mit Pfad `HolyAlert_Sounds`, Dateinamen, nach neuen Dateien WoW komplett neu starten
- **Debug:** Debugmodus an/aus, Log leeren
- **Keine Profile-Seite.** AceDB, Einstellungen pro Charakter (wie VoidAlert).
- `/holyalert` öffnet das Menü (`AceConfigDialog:Open`), zusätzlich `/ha`, falls nicht belegt. `/holyalert test`, `/holyalert status`, `/holyalert help`, `/holyalert debug on|off|clear`.
- Sprachen: enUS (Standard), deDE

## 6. Debugmodus

Ringpuffer in `HolyAlertDebugLog`, max. 5000 Einträge, Secret Values nur als `"<SECRET>"`. Inhalt: Version, Build, Klasse, Spec, aktiv ja/nein, jedes `GLOW_SHOW`/`GLOW_HIDE` mit Spell-ID und Name, jeder eigene Cast einer der drei IDs, jede Entscheidung (play / skip mit Grund: `inactive`, `disabled`, `notInCombat`, `lockout`, `noCoupling`) mit Abstand zum Gegenzauber, jeder Sound mit Quelle und Rückgabe.

## 7. Technik

- Kein Frame auf dem Bildschirm
- Bibliotheken per `.pkgmeta`: LibStub, CallbackHandler-1.0, AceDB-3.0, AceGUI-3.0, AceConfig-3.0, LibSharedMedia-3.0 (kein AceDBOptions)
- TOC: `## Interface: 120100`, `## Version: @project-version@`, `## SavedVariables: HolyAlertDB, HolyAlertDebugLog`, `## IconTexture: Interface\AddOns\HolyAlert\media\icon.png`, CurseForge-ID als auskommentierte Zeile vorbereiten
- `media/icon.png` aus `docs/holy-alert_logo.png`: transparente Ränder abschneiden, quadratisch, **64 × 64 px**, PNG mit Alpha
- `sounds/` und `media/` ins Paket, `docs/`, `SPEC.md`, `CLAUDE.md` nicht

## 8. Veröffentlichung

MIT (LICENSE liegt bereits im Repo), CHANGELOG und README auf Englisch, Release-Workflow bei Tag `v*` mit BigWigs Packager, Secret `CF_API_TOKEN`.
