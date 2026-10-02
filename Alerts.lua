local ADDON_NAME, ns = ...
local L = ns.L

-- Erkennung (SPEC 3) und Aktivierung nur für Paladin Vergeltung (SPEC 3.3). Aufbau aus VoidAlert,
-- eigener Cast nach dem Muster von KickCall (OnPlayerSpell).
--   SPELL_ACTIVATION_OVERLAY_GLOW_SHOW (Spell-ID)       -> Alarm auslösen (oder auf Kopplung warten)
--   UNIT_SPELLCAST_SUCCEEDED (player, Gegenzauber-ID)   -> Zeitpunkt merken, wartenden Alarm auslösen
-- Der Buff "Göttlicher Richter" ist im Kampf nicht lesbar (SPEC 2) und wird nie abgefragt.

local Alerts = {}
ns.Alerts = Alerts

local issecret = issecretvalue or function() return false end

-- Spell-IDs im Spiel getestet (SPEC 2, docs/reference/GlowTest.lua)
Alerts.DIVINE_STORM_ID = 53385       -- Göttlicher Sturm
Alerts.FINAL_VERDICT_ID = 383328     -- Letztes Urteil
Alerts.TEMPLARS_VERDICT_ID = 85256   -- Urteil des Templers (Basis-ID, leuchtet mit 383328 zusammen)
Alerts.RETRIBUTION_SPEC_ID = 70      -- im Test bestätigt (SPEC 3.3)

Alerts.LOCKOUT = 2             -- Sekunden Sperre pro Alarm (SPEC 3.1)
Alerts.COUPLING_WINDOW = 0.3   -- Sekunden zwischen Gegenzauber und Leuchten (SPEC 3.2)

-- Leuchtende Spell-ID -> Alarm (SPEC 3.1)
Alerts.BY_GLOW = {
  [Alerts.DIVINE_STORM_ID] = "storm",
  [Alerts.FINAL_VERDICT_ID] = "verdict",
  [Alerts.TEMPLARS_VERDICT_ID] = "verdict",
}
-- Eigener Cast (Gegenzauber) -> Alarm, den er auslöst: Urteil -> Sturm leuchtet, Sturm -> Urteil
Alerts.BY_CAST = {
  [Alerts.FINAL_VERDICT_ID] = "storm",
  [Alerts.TEMPLARS_VERDICT_ID] = "storm",
  [Alerts.DIVINE_STORM_ID] = "verdict",
}
Alerts.ORDER = { "storm", "verdict" }

Alerts.active = false
local lastPlayed = {}    -- Alarm -> GetTime() des letzten Abspielens
local lastCounter = {}   -- Alarm -> { t = GetTime(), spellID = ... } des letzten passenden Gegenzaubers
local pending = {}       -- Alarm -> { t = GetTime(), spellID = ... }: Leuchten kam vor dem Gegenzauber

-- Abstand in Sekunden, auf 1/1000 gerundet (fürs Log)
local function round(v)
  if type(v) ~= "number" then return nil end
  return math.floor(v * 1000 + 0.5) / 1000
end

local function now()
  return GetTime()
end

---------------------------------------------------------------------------
-- Spezialisierung (alles in pcall, Secret Values nie vergleichen). Aus VoidAlert.
---------------------------------------------------------------------------

-- true/false, nil wenn die API fehlt, fehlschlägt oder einen Secret Value liefert. Nur fürs Log.
local function safeKnown(spellID)
  local func = C_SpellBook and C_SpellBook.IsSpellKnown
  if not func then return nil end
  local ok, known = pcall(func, spellID)
  if not ok then
    ns.Debug:Error("IsSpellKnown", known)
    return nil
  end
  if issecret(known) then return nil end
  return known
end

-- Aktuelle Spezialisierung: specID, specName (nil, wenn nicht ermittelbar)
function Alerts:GetSpec()
  local ok, index = pcall(GetSpecialization)
  if not ok or issecret(index) or type(index) ~= "number" then return nil, nil end
  local okInfo, specID, specName = pcall(GetSpecializationInfo, index)
  if not okInfo or issecret(specID) or type(specID) ~= "number" then return nil, nil end
  if issecret(specName) then specName = nil end
  return specID, specName
end

-- Alle Spezialisierungen der eigenen Klasse (ID und Name) fürs Debug-Log
function Alerts:ClassSpecs()
  local out = {}
  if type(self.classID) ~= "number" then return out end
  local okNum, num = pcall(GetNumSpecializationsForClassID, self.classID)
  if not okNum or issecret(num) or type(num) ~= "number" then return out end
  for i = 1, num do
    local ok, id, name = pcall(GetSpecializationInfoForClassID, self.classID, i)
    if ok and type(id) == "number" and not issecret(id) and not issecret(name) then
      out["spec" .. i] = tostring(id) .. " " .. tostring(name)
    end
  end
  return out
end

-- Bei PLAYER_LOGIN, dann ist die Klasse sicher bekannt
function Alerts:Init()
  local ok, _, class, classID = pcall(UnitClass, "player")
  if ok then
    if not issecret(class) then self.class = class end
    if not issecret(classID) then self.classID = classID end
  end
end

-- Aktiv bei Klasse PALADIN und Spec-ID 70 (SPEC 3.3). Liefert die Spec-API kein Ergebnis
-- (Fehler, Secret Value, Spec noch 0), bleibt ein Paladin wie in VoidAlert aktiv (reason
-- "unclear"): Die Alarm-IDs leuchten ohnehin nur bei Vergeltung. Wird im Log vermerkt.
-- Rückgabe: true, wenn sich Status oder Spec-ID geändert hat.
function Alerts:Update()
  local specID, specName = self:GetSpec()
  local active, reason
  if self.class ~= "PALADIN" then
    active, reason = false, "class"
  elseif specID == self.RETRIBUTION_SPEC_ID then
    active, reason = true, "specID"
  elseif specID == nil then
    active, reason = true, "unclear"
  else
    active, reason = false, "notRetribution"
  end
  local changed = active ~= self.active or specID ~= self.specID
  self.active, self.reason = active, reason
  self.specID, self.specName = specID, specName
  if not active then
    wipe(pending)
    wipe(lastCounter)
  end
  return changed
end

-- Spec-Eintrag fürs Debug-Log (SPEC 6)
function Alerts:LogSpec(why)
  if not ns.Debug:IsEnabled() then return end
  local out = self:ClassSpecs()
  out.why = why
  out.class = self.class
  out.specID = self.specID
  out.specName = self.specName
  out.retributionSpecID = self.RETRIBUTION_SPEC_ID
  out.divineStormKnown = safeKnown(self.DIVINE_STORM_ID)
  out.finalVerdictKnown = safeKnown(self.FINAL_VERDICT_ID)
  out.templarsVerdictKnown = safeKnown(self.TEMPLARS_VERDICT_ID)
  out.active = self.active
  out.reason = self.reason
  ns.Debug:Add("spec", out)
end

---------------------------------------------------------------------------
-- Abspielen
---------------------------------------------------------------------------

function Alerts:SpellName(spellID)
  if issecret(spellID) or type(spellID) ~= "number" then return nil end
  local ok, name = pcall(C_Spell.GetSpellName, spellID)
  if ok and type(name) == "string" and not issecret(name) then return name end
  return nil
end

-- Sound für einen Alarm abspielen. Ist der gespeicherte Schlüssel nicht mehr auflösbar
-- (z. B. LSM-Sound eines entfernten Addons), wird der Standard verwendet.
function Alerts:Play(alert, why)
  local p = ns.db.profile
  local key = p.alerts[alert].sound
  local Sounds = ns.Sounds
  local fallback
  if not Sounds:Resolve(key) then
    fallback = key
    key = Sounds.DEFAULTS[alert]
  end
  local result = Sounds:Play(key, p.channel)
  result.alert = alert
  result.why = why
  result.fallbackFrom = fallback
  ns.Debug:Add("sound", result)
  return result
end

-- Entscheidung ins Log (SPEC 6): decision = play | skip | wait, reason bei skip,
-- delta = Leuchten minus Gegenzauber in Sekunden (positiv: Gegenzauber kam zuerst)
local function logDecision(alert, spellID, decision, reason, delta, counterID)
  if not ns.Debug:IsEnabled() then return end
  ns.Debug:Add("decision", {
    alert = alert, spellID = spellID, decision = decision, reason = reason,
    delta = round(delta), counterID = counterID,
    judgeOnly = ns.db.profile.judgeOnly, window = Alerts.COUPLING_WINDOW,
  })
end

-- Gründe, die unabhängig von der Kopplung gelten
local function commonSkip(alert)
  if not Alerts.active then return "inactive" end
  if not ns.db.profile.alerts[alert].enabled then return "disabled" end
  if ns.db.profile.combatOnly and not ns.inCombat then return "notInCombat" end
  return nil
end

local function isLocked(alert, t)
  return lastPlayed[alert] ~= nil and t - lastPlayed[alert] < Alerts.LOCKOUT
end

local function fire(alert, spellID, delta, counterID)
  lastPlayed[alert] = now()
  logDecision(alert, spellID, "play", nil, delta, counterID)
  Alerts:Play(alert, "glow")
end

---------------------------------------------------------------------------
-- Leuchten (SPEC 3.1): nur GLOW_SHOW spielt einen Sound
---------------------------------------------------------------------------

-- Wartenden Alarm verfallen lassen, wenn der Gegenzauber nicht im Fenster kam (Debug: noCoupling)
local function expire(alert, entry)
  if pending[alert] ~= entry then return end   -- inzwischen ausgelöst oder ersetzt
  pending[alert] = nil
  local counter = lastCounter[alert]
  local delta = counter and (entry.t - counter.t) or nil
  logDecision(alert, entry.spellID, "skip", "noCoupling", delta, counter and counter.spellID)
end

function Alerts:OnGlowShow(spellID)
  if issecret(spellID) then
    ns.Debug:Add("glowShow", { spellID = spellID })   -- wird als "<SECRET>" gespeichert
    return
  end
  local alert = self.BY_GLOW[spellID]
  if ns.Debug:IsEnabled() then
    ns.Debug:Add("glowShow", { spellID = spellID, name = self:SpellName(spellID), alert = alert })
  end
  if not alert then return end

  local t = now()
  local counter = lastCounter[alert]
  local delta = counter and (t - counter.t) or nil
  local counterID = counter and counter.spellID

  local skip = commonSkip(alert)
  if not skip and isLocked(alert, t) then skip = "lockout" end
  if skip then
    logDecision(alert, spellID, "skip", skip, delta, counterID)
    return
  end

  if not ns.db.profile.judgeOnly then
    fire(alert, spellID, delta, counterID)
    return
  end

  -- Kopplung (SPEC 3.2): Gegenzauber höchstens COUPLING_WINDOW zurück -> Sound
  if delta and delta >= 0 and delta <= self.COUPLING_WINDOW then
    pending[alert] = nil
    fire(alert, spellID, delta, counterID)
    return
  end

  -- Sonst warten: Die Reihenfolge im selben Frame ist nicht garantiert. 383328 und 85256 kommen
  -- gleichzeitig, darum einen schon wartenden Alarm nicht ersetzen.
  local entry = pending[alert]
  if entry and t - entry.t <= self.COUPLING_WINDOW then
    logDecision(alert, spellID, "wait", "alreadyWaiting", delta, counterID)
    return
  end
  entry = { t = t, spellID = spellID }
  pending[alert] = entry
  logDecision(alert, spellID, "wait", nil, delta, counterID)
  local ok = C_Timer and C_Timer.After and pcall(C_Timer.After, self.COUPLING_WINDOW + 0.05, function()
    local okExpire, err = pcall(expire, alert, entry)
    if not okExpire then ns.Debug:Error("expire", err) end
  end)
  if not ok then ns.Debug:Error("C_Timer.After", "unavailable") end
end

function Alerts:OnGlowHide(spellID)
  if not ns.Debug:IsEnabled() then return end
  if issecret(spellID) then
    ns.Debug:Add("glowHide", { spellID = spellID })
    return
  end
  ns.Debug:Add("glowHide", { spellID = spellID, name = self:SpellName(spellID), alert = self.BY_GLOW[spellID] })
end

---------------------------------------------------------------------------
-- Eigener Cast (SPEC 3.2): UNIT_SPELLCAST_SUCCEEDED für "player", Muster aus KickCall
---------------------------------------------------------------------------

local secretCastLogged = false

function Alerts:OnPlayerSpell(unit, spellID)
  if issecret(unit) or unit ~= "player" then return end
  if issecret(spellID) then
    -- Nur einmal pro Sitzung loggen, sonst füllt jeder Cast das Log
    if ns.Debug:IsEnabled() and not secretCastLogged then
      secretCastLogged = true
      ns.Debug:Add("cast", { spellID = spellID })   -- als "<SECRET>"
    end
    return
  end
  local alert = self.BY_CAST[spellID]
  if not alert then return end

  local t = now()
  lastCounter[alert] = { t = t, spellID = spellID }
  if ns.Debug:IsEnabled() then
    ns.Debug:Add("cast", { spellID = spellID, name = self:SpellName(spellID), couples = alert })
  end

  -- Leuchten kam zuerst: wartenden Alarm jetzt auslösen
  local entry = pending[alert]
  if not entry then return end
  pending[alert] = nil
  local delta = entry.t - t   -- negativ: Leuchten vor dem Gegenzauber
  if -delta > self.COUPLING_WINDOW then
    logDecision(alert, entry.spellID, "skip", "noCoupling", delta, spellID)
    return
  end
  -- Zustand kann sich seit dem Leuchten geändert haben (Spec, Einstellung, Kampf, Sperre)
  local skip = commonSkip(alert)
  if not skip and isLocked(alert, t) then skip = "lockout" end
  if skip then
    logDecision(alert, entry.spellID, "skip", skip, delta, spellID)
    return
  end
  fire(alert, entry.spellID, delta, spellID)
end

---------------------------------------------------------------------------
-- Test: spielt einen oder beide Alarme, unabhängig von an/aus, Kampf, Kopplung und Sperre.
-- Beide nacheinander, damit sie sich nicht überlagern.
---------------------------------------------------------------------------

local TEST_GAP = 2

function Alerts:Test(which)
  local list = which and { which } or self.ORDER
  for i, alert in ipairs(list) do
    local function run()
      local ok, err = pcall(function()
        local result = self:Play(alert, "test")
        if ns.db.profile.chatMessages then
          ns.Print(L["TEST_PLAYING"]:format(L["ALERT_" .. alert], ns.Sounds:Label(result.sound)))
        end
      end)
      if not ok then ns.Debug:Error("Test", err) end
    end
    if i == 1 then
      run()
    else
      local ok = pcall(C_Timer.After, (i - 1) * TEST_GAP, run)
      if not ok then ns.Debug:Error("C_Timer.After", "test") end
    end
  end
end
