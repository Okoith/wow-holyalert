-- GlowTest v0.2.0
-- Loggt jedes Aufleuchten (GLOW_SHOW/HIDE) mit Spell-ID und Name, dazu Kampf und Spezialisierung.
-- Zweck: herausfinden, welche IDs beim Paladin (Vergeltung) nach "Goettlicher Richter" aufleuchten
-- und ob dieselben IDs auch ohne den Buff aufleuchten (Fehlalarme).
-- Log: WTF\Account\<ACCOUNT>\SavedVariables\GlowTest.lua (bei /reload oder Logout)
-- Befehle: /gt  (clear | ids)

local ADDON_NAME = ...
local VERSION = "0.2.0"
local MAX_ENTRIES = 8000
local issecret = issecretvalue or function() return false end
local loginNo = 0
local seen = {}

local function Print(msg) print("|cfff58cbaGlowTest|r: " .. msg) end

local function S(v)
  if issecret(v) then return "<SECRET>" end
  if v == nil then return "nil" end
  local t = type(v)
  if t == "number" or t == "string" or t == "boolean" then return v end
  return "<" .. t .. ">"
end

local function add(kind, data)
  local db = GlowTestLog
  if not db then return end
  data = data or {}
  data.kind = kind
  data.t = math.floor(GetTime() * 100 + 0.5) / 100
  data.login = loginNo
  local okC, c = pcall(InCombatLockdown)
  data.combat = okC and c and true or false
  local e = db.entries
  e[#e + 1] = data
  if #e > MAX_ENTRIES then
    local keep = {}
    for i = #e - (MAX_ENTRIES - 1000) + 1, #e do keep[#keep + 1] = e[i] end
    db.entries = keep
  end
end

local function spellName(id)
  if issecret(id) or type(id) ~= "number" then return nil end
  local ok, n = pcall(C_Spell.GetSpellName, id)
  if ok and not issecret(n) then return n end
  return nil
end

local function spec()
  local ok, id, name = pcall(function() return GetSpecializationInfo(GetSpecialization()) end)
  if ok then return S(id), S(name) end
  return "err", "err"
end

-- v0.2.0: Ist der Buff "Goettlicher Richter" im Kampf lesbar?
local TARGET_NAMES = { ["Göttlicher Richter"] = true, ["Divine Judge"] = true }
local knownAuraIDs = {}   -- spellId -> name (nur lesbare)
local lastAuraLog = 0

local function probeAuras(why, updateInfo)
  local out = { why = why }
  -- 1) UNIT_AURA-Payload (addedAuras)
  if updateInfo and not issecret(updateInfo) and type(updateInfo) == "table" then
    local okA, added = pcall(function() return updateInfo.addedAuras end)
    if okA and type(added) == "table" and not issecret(added) then
      local list = {}
      for i, a in ipairs(added) do
        local okI, id = pcall(function() return a.spellId end)
        local okN, nm = pcall(function() return a.name end)
        list[#list + 1] = tostring(okI and S(id) or "err") .. "|" .. tostring(okN and S(nm) or "err")
        if okI and okN and not issecret(id) and not issecret(nm) and type(id) == "number" then
          knownAuraIDs[id] = nm
        end
        if i >= 10 then break end
      end
      out.added = table.concat(list, "; ")
    elseif okA and issecret(added) then
      out.added = "<SECRET>"
    end
  end
  -- 2) Index-Durchlauf
  local found = {}
  for i = 1, 40 do
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
    if not ok then out.indexErr = tostring(aura); break end
    if issecret(aura) then out.indexSecret = true; break end
    if aura == nil then break end
    local okI, id = pcall(function() return aura.spellId end)
    local okN, nm = pcall(function() return aura.name end)
    if okI and okN and not issecret(id) and not issecret(nm) then
      knownAuraIDs[id] = nm
      if TARGET_NAMES[nm] then found[#found + 1] = id end
    elseif okN and issecret(nm) then
      out.nameSecret = true
    end
  end
  out.judgeFound = #found > 0 and table.concat(found, ",") or "no"
  -- 3) direkte Abfrage aller bisher bekannten "Richter"-IDs
  for id, nm in pairs(knownAuraIDs) do
    if TARGET_NAMES[nm] then
      local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
      if not ok then out["byID_" .. id] = "err:" .. tostring(aura)
      elseif issecret(aura) then out["byID_" .. id] = "<SECRET>"
      else out["byID_" .. id] = aura and "present" or "nil" end
      if C_Secrets and C_Secrets.GetSpellAuraSecrecy then
        local okS, v = pcall(C_Secrets.GetSpellAuraSecrecy, id)
        out["secrecy_" .. id] = okS and S(v) or "err"
      end
    end
  end
  if C_Secrets and C_Secrets.ShouldAurasBeSecret then
    local okS, v = pcall(C_Secrets.ShouldAurasBeSecret)
    out.shouldAurasBeSecret = okS and S(v) or "err"
  end
  add("aura", out)
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON_NAME then return end
    GlowTestLog = GlowTestLog or {}
    local db = GlowTestLog
    if db.version ~= VERSION then db.entries = {}; db.logins = 0; db.version = VERSION end
    db.entries = db.entries or {}
    db.logins = (db.logins or 0) + 1
    loginNo = db.logins
  elseif event == "PLAYER_LOGIN" or event == "PLAYER_SPECIALIZATION_CHANGED" then
    local sid, sname = spec()
    local version, build = GetBuildInfo()
    add("meta", { event = event, addonVersion = VERSION, gameVersion = S(version), build = S(build),
      class = select(2, UnitClass("player")), specID = sid, specName = sname })
    Print("v" .. VERSION .. " aktiv. /gt ids zeigt alle bisher gesehenen Aufleucht-IDs")
  elseif event == "PLAYER_REGEN_DISABLED" then
    add("combatStart")
  elseif event == "PLAYER_REGEN_ENABLED" then
    add("combatEnd")
  elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
    local spellID = ...
    local secret = issecret(spellID)
    local name = spellName(spellID)
    local show = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
    add(show and "glowShow" or "glowHide", { spellID = S(spellID), name = name, secret = secret })
    if show and not secret and type(spellID) == "number" then
      seen[spellID] = (seen[spellID] or 0) + 1
    end
  elseif event == "UNIT_AURA" then
    local unit, updateInfo = ...
    if unit ~= "player" then return end
    local now = GetTime()
    if now - lastAuraLog < 0.2 then return end
    lastAuraLog = now
    probeAuras("UNIT_AURA", updateInfo)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellID = ...
    if unit == "player" and not issecret(spellID) and type(spellID) == "number" then
      add("cast", { spellID = spellID, name = spellName(spellID) })
    end
  end
end)

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
  "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA" }) do
  if not pcall(f.RegisterEvent, f, e) then Print("Event unbekannt: " .. e) end
end

SLASH_GLOWTEST1 = "/gt"
SlashCmdList.GLOWTEST = function(msg)
  msg = strlower(strtrim(msg or ""))
  if msg == "clear" then
    wipe(GlowTestLog.entries); wipe(seen); Print("Log geleert")
  elseif msg == "aura" then
    probeAuras("manual"); Print("Auren geloggt")
    for id, nm in pairs(knownAuraIDs) do if TARGET_NAMES[nm] then Print("Richter-ID: " .. id) end end
  elseif msg == "ids" then
    local any = false
    for id, n in pairs(seen) do any = true; Print(id .. " " .. tostring(spellName(id)) .. " (" .. n .. "x)") end
    if not any then Print("Noch nichts aufgeleuchtet.") end
  else
    Print("/gt ids | aura | clear. Log wird bei /reload gespeichert.")
  end
end
