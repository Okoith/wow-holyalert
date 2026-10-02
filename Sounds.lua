local ADDON_NAME, ns = ...
local L = ns.L

-- Soundquellen (SPEC 4, aus VoidAlert übernommen) in einer gemeinsamen Liste und geschütztes Abspielen.
-- Gespeichert wird nur ein Schlüssel (Text), nie ein geheimer Wert:
--   "addon:<id>"  mitgelieferte Sounds in sounds/
--   "custom:<n>"  eigene Sounds in Interface\AddOns\HolyAlert_Sounds\sound<n>.ogg
--   "kit:<NAME>"  WoW-Sound über SOUNDKIT.<NAME>
--   "lsm:<name>"  bei LibSharedMedia-3.0 registrierter Sound

local Sounds = {}
ns.Sounds = Sounds

local LSM = LibStub("LibSharedMedia-3.0", true)
Sounds.LSM = LSM

local issecret = issecretvalue or function() return false end

local ADDON_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\sounds\\"
local CUSTOM_FOLDER = "HolyAlert_Sounds"
local CUSTOM_PATH = "Interface\\AddOns\\" .. CUSTOM_FOLDER .. "\\"
Sounds.CUSTOM_FOLDER = CUSTOM_PATH
Sounds.CUSTOM_COUNT = 5

-- Mitgelieferte Sounds. lsm = Name, unter dem der Sound bei LibSharedMedia registriert wird.
Sounds.BUNDLED = {
  { id = "storm_en", file = "storm_en.ogg", label = "SOUND_STORM_EN", lsm = "HolyAlert: Divine Storm (EN)" },
  { id = "storm_de", file = "storm_de.ogg", label = "SOUND_STORM_DE", lsm = "HolyAlert: Divine Storm (DE)" },
  { id = "verdict_en", file = "verdict_en.ogg", label = "SOUND_VERDICT_EN", lsm = "HolyAlert: Final Verdict (EN)" },
  { id = "verdict_de", file = "verdict_de.ogg", label = "SOUND_VERDICT_DE", lsm = "HolyAlert: Final Verdict (DE)" },
}
local bundledByID, ownLSMNames = {}, {}
for _, s in ipairs(Sounds.BUNDLED) do
  bundledByID[s.id] = s
  ownLSMNames[s.lsm] = true
end

-- WoW-Sounds. Namen aus SoundKitConstants.lua (Gethe/wow-ui-source, 12.1.0 Build 69933);
-- angeboten wird nur, was zur Laufzeit in SOUNDKIT als Zahl vorhanden ist.
Sounds.SOUNDKITS = {
  "RAID_WARNING",
  "READY_CHECK",
  "ALARM_CLOCK_WARNING_2",
  "ALARM_CLOCK_WARNING_3",
  "RAID_BOSS_EMOTE_WARNING",
  "PVP_THROUGH_QUEUE",
}

-- Kanäle laut SPEC 5 (API PlaySoundFile/PlaySound, warcraft.wiki.gg)
Sounds.CHANNELS = { "Master", "SFX", "Dialog", "Music", "Ambience" }

-- Standard je nach Client-Sprache (SPEC 4): deDE -> _de, sonst _en
local okLocale, locale = pcall(GetLocale)
local lang = (okLocale and locale == "deDE") and "de" or "en"
Sounds.DEFAULTS = {
  storm = "addon:storm_" .. lang,
  verdict = "addon:verdict_" .. lang,
}

---------------------------------------------------------------------------
-- Registrierung bei LibSharedMedia (SPEC 4 Punkt 1). LSM:Register prüft selbst per
-- C_UIFileAsset.IsKnownFile, ob die Datei existiert, und liefert sonst false.
---------------------------------------------------------------------------

Sounds.lsmRegistered = {}
if LSM then
  for _, s in ipairs(Sounds.BUNDLED) do
    local ok, result = pcall(LSM.Register, LSM, LSM.MediaType.SOUND, s.lsm, ADDON_PATH .. s.file)
    Sounds.lsmRegistered[s.id] = ok and result or ("error: " .. tostring(result))
  end
end

---------------------------------------------------------------------------
-- Auflösen und Liste
---------------------------------------------------------------------------

local function soundKitID(name)
  if type(SOUNDKIT) ~= "table" then return nil end
  local id = SOUNDKIT[name]
  if type(id) ~= "number" then return nil end
  return id
end

local function isOfferedKit(name)
  for _, n in ipairs(Sounds.SOUNDKITS) do
    if n == name then return true end
  end
  return false
end

local function lsmFetch(name)
  if not LSM then return nil end
  local ok, data = pcall(LSM.Fetch, LSM, LSM.MediaType.SOUND, name, true)
  if not ok then
    ns.Debug:Error("LSM:Fetch", data)
    return nil
  end
  if type(data) ~= "string" and type(data) ~= "number" then return nil end
  return data
end

function Sounds:CustomPath(n)
  return CUSTOM_PATH .. "sound" .. n .. ".ogg"
end

-- Rückgabe: kind ("file" | "kit"), Wert (Pfad/FileDataID bzw. SoundKit-ID), Anzeigename.
-- nil, wenn der Schlüssel nicht (mehr) auflösbar ist.
function Sounds:Resolve(key)
  if type(key) ~= "string" then return nil end
  local source, value = key:match("^(%a+):(.+)$")
  if source == "addon" then
    local s = bundledByID[value]
    if s then return "file", ADDON_PATH .. s.file, L[s.label] end
  elseif source == "custom" then
    local n = tonumber(value)
    if n and n >= 1 and n <= self.CUSTOM_COUNT and n == math.floor(n) then
      return "file", self:CustomPath(n), L["SOUND_CUSTOM"]:format(n)
    end
  elseif source == "kit" then
    local id = isOfferedKit(value) and soundKitID(value)
    if id then return "kit", id, L["SOUND_KIT"]:format(L["KIT_" .. value]) end
  elseif source == "lsm" then
    local data = lsmFetch(value)
    if data then return "file", data, L["SOUND_LSM"]:format(value) end
  end
  return nil
end

function Sounds:Label(key)
  local _, _, label = self:Resolve(key)
  return label or tostring(key)
end

-- Gemeinsame Auswahlliste (SPEC 4), geordnet: mitgeliefert, eigene, WoW, LibSharedMedia.
-- Rückgabe: Liste von { key = ..., label = ... }
function Sounds:List()
  local list = {}
  for _, s in ipairs(self.BUNDLED) do
    list[#list + 1] = { key = "addon:" .. s.id, label = L[s.label] }
  end
  for n = 1, self.CUSTOM_COUNT do
    list[#list + 1] = { key = "custom:" .. n, label = L["SOUND_CUSTOM"]:format(n) }
  end
  for _, name in ipairs(self.SOUNDKITS) do
    if soundKitID(name) then
      list[#list + 1] = { key = "kit:" .. name, label = L["SOUND_KIT"]:format(L["KIT_" .. name]) }
    end
  end
  if LSM then
    local ok, names = pcall(LSM.List, LSM, LSM.MediaType.SOUND)
    if ok and type(names) == "table" then
      for _, name in ipairs(names) do
        -- eigene Sounds stehen schon oben, "None" ist Stille
        if not ownLSMNames[name] and name ~= "None" then
          list[#list + 1] = { key = "lsm:" .. name, label = L["SOUND_LSM"]:format(name) }
        end
      end
    end
  end
  return list
end

---------------------------------------------------------------------------
-- Abspielen (SPEC 4): PlaySoundFile für Dateien, PlaySound für SOUNDKIT, alles in pcall.
---------------------------------------------------------------------------

local warned = {}   -- Schlüssel -> true, Hinweis im Chat nur einmal pro Sitzung

local function isKnownFile(path)
  if not (C_UIFileAsset and C_UIFileAsset.IsKnownFile) then return nil end
  local ok, known = pcall(C_UIFileAsset.IsKnownFile, path)
  if not ok or issecret(known) then return nil end
  return known
end

-- Spielt den Sound zum Schlüssel. Rückgabe: Tabelle fürs Debug-Log.
function Sounds:Play(key, channel)
  local kind, value, label = self:Resolve(key)
  local result = { sound = key, channel = channel, label = label, kind = kind }
  if not kind then
    result.err = "unresolved"
    return result
  end
  result.value = value

  local ok, willPlay, handle
  if kind == "kit" then
    ok, willPlay, handle = pcall(PlaySound, value, channel)
  else
    ok, willPlay, handle = pcall(PlaySoundFile, value, channel)
  end
  result.ok = ok
  if not ok then
    result.err = willPlay
    ns.Debug:Error("PlaySound", willPlay)
  else
    result.willPlay = willPlay
    result.handle = handle
  end

  -- Fehlt eine Datei, liefert PlaySoundFile false/nil (SPEC 4 Punkt 2). nil kommt laut
  -- warcraft.wiki.gg auch bei stummgeschaltetem Kanal, darum nennt der Hinweis beides.
  local failed
  if not ok then
    failed = true
  elseif issecret(willPlay) then
    failed = false   -- nicht auswerten, nur loggen (als "<SECRET>")
  else
    failed = not willPlay
  end
  result.failed = failed
  if failed then
    if kind == "file" and type(value) == "string" then result.knownFile = isKnownFile(value) end
    if not warned[key] then
      warned[key] = true
      if key:match("^custom:") then
        ns.Print(L["CUSTOM_MISSING"]:format(label, CUSTOM_PATH))
      else
        ns.Print(L["SOUND_FAILED"]:format(label))
      end
    end
  end
  return result
end

-- Übersicht fürs Debug-Log: LSM-Registrierung, eigene Dateien laut IsKnownFile
function Sounds:DebugInfo()
  local out = { lsmVersion = LSM and select(2, LibStub:GetLibrary("LibSharedMedia-3.0", true)) }
  for id, result in pairs(self.lsmRegistered) do
    out["lsmRegister " .. id] = result
  end
  for n = 1, self.CUSTOM_COUNT do
    out["customKnown " .. n] = isKnownFile(self:CustomPath(n))
  end
  for _, name in ipairs(self.SOUNDKITS) do
    out["kit " .. name] = soundKitID(name)
  end
  if LSM then
    local ok, names = pcall(LSM.List, LSM, LSM.MediaType.SOUND)
    out.lsmSoundCount = (ok and type(names) == "table") and #names or nil
  end
  return out
end
