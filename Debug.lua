local ADDON_NAME, ns = ...

-- Debug-Log in der SavedVariable HolyAlertDebugLog (Ringpuffer), übernommen aus VoidAlert.
-- Regel: Secret Values werden nie gespeichert, nur als "<SECRET>" markiert (SPEC 6).

local Debug = {}
ns.Debug = Debug

local MAX_ENTRIES = 5000
local ERROR_REPEAT_SECONDS = 5

local issecret = issecretvalue or function() return false end

local loginNo = 0
local lastErrors = {}   -- Meldungstext -> Zeitpunkt, drosselt identische Fehler

-- Wandelt einen Wert in etwas Speicherbares um. Secret Values -> "<SECRET>".
local function S(v)
  if issecret(v) then return "<SECRET>" end
  if v == nil then return "nil" end
  local t = type(v)
  if t == "number" or t == "string" or t == "boolean" then return v end
  return "<" .. t .. ">"
end
Debug.S = S

function Debug:Init()
  if type(HolyAlertDebugLog) ~= "table" then HolyAlertDebugLog = {} end
  local log = HolyAlertDebugLog
  if type(log.entries) ~= "table" then log.entries = {} end
  log.logins = (tonumber(log.logins) or 0) + 1
  loginNo = log.logins
end

function Debug:IsEnabled()
  return ns.db ~= nil and ns.db.global.debug == true
end

function Debug:SetEnabled(enabled)
  ns.db.global.debug = enabled and true or false
  if enabled then self:LogMeta() end
end

function Debug:Count()
  local log = HolyAlertDebugLog
  return (log and log.entries) and #log.entries or 0
end

function Debug:Clear()
  local log = HolyAlertDebugLog
  if log and log.entries then wipe(log.entries) end
end

-- data: flache Tabelle mit festen String-Schlüsseln; jeder Wert wird mit S() bereinigt.
function Debug:Add(kind, data)
  if not self:IsEnabled() then return end
  local log = HolyAlertDebugLog
  if not log or not log.entries then return end

  local entry = {}
  if data then
    for k, v in pairs(data) do entry[k] = S(v) end
  end
  entry.kind = kind
  entry.t = math.floor(GetTime() * 100 + 0.5) / 100
  entry.time = date("%H:%M:%S")
  entry.login = loginNo
  local okC, combat = pcall(InCombatLockdown)
  entry.combat = okC and not issecret(combat) and combat and true or false

  local e = log.entries
  e[#e + 1] = entry
  while #e > MAX_ENTRIES do table.remove(e, 1) end
end

-- Fehler aus pcall. Gleiche Meldungen höchstens alle paar Sekunden.
function Debug:Error(where, err)
  if not self:IsEnabled() then return end
  local msg = S(err)
  if type(msg) ~= "string" then msg = tostring(msg) end
  local key = where .. ":" .. msg
  local now = GetTime()
  if lastErrors[key] and now - lastErrors[key] < ERROR_REPEAT_SECONDS then return end
  lastErrors[key] = now
  self:Add("error", { where = where, err = msg })
end

-- Version, Build, Sprache, Klasse, Spezialisierung, Einstellungen, Soundquellen (SPEC 6)
function Debug:LogMeta()
  if not self:IsEnabled() then return end
  local okBuild, gameVersion, build, buildDate, toc = pcall(GetBuildInfo)
  if not okBuild then gameVersion, build, buildDate, toc = "error", nil, nil, nil end
  local okLocale, locale = pcall(GetLocale)
  local Alerts = ns.Alerts
  local specID, specName = Alerts:GetSpec()
  local p = ns.db.profile
  local out = {
    addonVersion = ns.VERSION,
    gameVersion = gameVersion, build = build, buildDate = buildDate, toc = toc,
    locale = okLocale and locale or nil,
    class = Alerts.class,
    specID = specID,
    specName = specName,
    active = Alerts.active,
    reason = Alerts.reason,
    stormEnabled = p.alerts.storm.enabled,
    stormSound = p.alerts.storm.sound,
    verdictEnabled = p.alerts.verdict.enabled,
    verdictSound = p.alerts.verdict.sound,
    judgeOnly = p.judgeOnly,
    couplingWindow = Alerts.COUPLING_WINDOW,
    lockout = Alerts.LOCKOUT,
    channel = p.channel,
    combatOnly = p.combatOnly,
    chatMessages = p.chatMessages,
    slashHa = ns.slashHa,
    hasIsSecretValue = issecretvalue ~= nil,
    hasCTimer = (C_Timer and C_Timer.After) ~= nil,
    hasIsKnownFile = (C_UIFileAsset and C_UIFileAsset.IsKnownFile) ~= nil,
    hasLSM = ns.Sounds.LSM ~= nil,
  }
  self:Add("meta", out)
  self:Add("sounds", ns.Sounds:DebugInfo())
end
