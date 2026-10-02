local ADDON_NAME, ns = ...
local L = ns.L

-- Init, AceDB, Events, Slash-Befehle. Aufbau aus VoidAlert, eigener Cast aus KickCall.

local issecret = issecretvalue or function() return false end

do
  local ok, version = pcall(function()
    return C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
  end)
  ns.VERSION = (ok and type(version) == "string") and version or "?"
end

ns.defaults = {
  profile = {
    alerts = {
      storm = { enabled = true, sound = ns.Sounds.DEFAULTS.storm },     -- Standard je nach Client-Sprache
      verdict = { enabled = true, sound = ns.Sounds.DEFAULTS.verdict },
    },
    judgeOnly = true,       -- Nur bei Göttlicher Richter (SPEC 3.2)
    channel = "Master",
    combatOnly = true,
    chatMessages = false,   -- Ladehinweis und Testmeldung im Chat (Fehlerhinweise immer)
  },
  global = {
    debug = false,
  },
}

local function Print(msg)
  print("|cfff58cbaHolyAlert|r: " .. msg)
end
ns.Print = Print

ns.inCombat = false

local function inCombatLockdown()
  local ok, combat = pcall(InCombatLockdown)
  return ok and not issecret(combat) and combat and true or false
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

-- Spezialisierung neu prüfen (SPEC 3.3). Loggen nur, wenn sich etwas geändert hat,
-- denn SPELLS_CHANGED kommt oft.
local function checkSpec(why)
  if not ns.loggedIn then return end
  if ns.Alerts:Update() then
    ns.Alerts:LogSpec(why)
    ns.Options:Notify()   -- Hinweis oben im Menü (aktiv/inaktiv) nachziehen
  end
end

local registerShortSlash   -- unten bei den Slash-Befehlen

function handlers.ADDON_LOADED(name)
  if name ~= ADDON_NAME then return end
  events:UnregisterEvent("ADDON_LOADED")

  -- Ohne dritten Parameter legt AceDB ein Profil pro Charakter an ("Name - Realm"), SPEC 5
  ns.db = LibStub("AceDB-3.0"):New("HolyAlertDB", ns.defaults)
  ns.Debug:Init()
  ns.Options:Init()
end

-- Bei ADDON_LOADED ist GetSpecialization() noch 0 (Erfahrung aus VoidAlert), darum erst hier
function handlers.PLAYER_LOGIN()
  ns.inCombat = inCombatLockdown()
  ns.Alerts:Init()
  ns.Alerts:Update()
  ns.loggedIn = true
  registerShortSlash()
  ns.Debug:LogMeta()
  ns.Alerts:LogSpec("login")
  -- Andere Klassen und Specs: Addon still (SPEC 3.3)
  if ns.Alerts.active and ns.db.profile.chatMessages then Print(L["LOADED"]:format(ns.VERSION)) end
end

function handlers.PLAYER_SPECIALIZATION_CHANGED(unit)
  if unit ~= nil and (issecret(unit) or unit ~= "player") then return end
  checkSpec("specChanged")
end

function handlers.SPELLS_CHANGED()
  checkSpec("spellsChanged")
end

function handlers.PLAYER_REGEN_DISABLED()
  ns.inCombat = true
  ns.Debug:Add("combatStart", { active = ns.Alerts.active })
end

function handlers.PLAYER_REGEN_ENABLED()
  ns.inCombat = false
  ns.Debug:Add("combatEnd")
end

function handlers.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW(spellID)
  if not ns.loggedIn then return end
  ns.Alerts:OnGlowShow(spellID)
end

function handlers.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE(spellID)
  if not ns.loggedIn then return end
  ns.Alerts:OnGlowHide(spellID)
end

local function dispatch(event, ...)
  local handler = handlers[event]
  if not handler then return end
  -- Vor ADDON_LOADED gibt es noch keine Datenbank
  if not ns.db and event ~= "ADDON_LOADED" then return end
  local ok, err = pcall(handler, ...)
  if not ok then
    if ns.db then ns.Debug:Error(event, err) end
    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
      geterrorhandler()(err)
    end
  end
end

events:SetScript("OnEvent", function(_, event, ...) dispatch(event, ...) end)

for event in pairs(handlers) do
  local ok = pcall(events.RegisterEvent, events, event)
  if not ok then Print("Event unknown: " .. event) end
end

-- Eigener Cast (SPEC 3.2): UNIT_SPELLCAST_SUCCEEDED nur für "player", wie in KickCall.
-- RegisterUnitEvent spart die Ereignisse aller anderen Einheiten; ohne die Funktion normal
-- registrieren (OnPlayerSpell prüft die Einheit ohnehin). Der Handler steht bewusst erst nach
-- der Registrierungsschleife oben, damit nur playerEvents dieses Ereignis empfängt.
-- Payload: unitTarget, castGUID, spellID
local playerEvents = CreateFrame("Frame")
handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
  if not ns.loggedIn then return end
  ns.Alerts:OnPlayerSpell(unit, spellID)
end
playerEvents:SetScript("OnEvent", function(_, event, ...) dispatch(event, ...) end)
do
  local ok = playerEvents.RegisterUnitEvent
    and pcall(playerEvents.RegisterUnitEvent, playerEvents, "UNIT_SPELLCAST_SUCCEEDED", "player")
  if not ok then
    ok = pcall(playerEvents.RegisterEvent, playerEvents, "UNIT_SPELLCAST_SUCCEEDED")
  end
  if not ok then Print("Event unknown: UNIT_SPELLCAST_SUCCEEDED") end
end

---------------------------------------------------------------------------
-- Slash-Befehle (SPEC 5). /holyalert ohne Argument öffnet das Menü.
---------------------------------------------------------------------------

local ALERTS = { storm = true, verdict = true }

local function onOff(value)
  return value and L["ON"] or L["OFF"]
end

local function printHelp()
  Print(L["HELP_HEADER"])
  for _, key in ipairs({ "HELP_OPEN", "HELP_HELP", "HELP_STATUS", "HELP_TEST", "HELP_SOUNDS", "HELP_SOUND",
      "HELP_TOGGLE", "HELP_JUDGE", "HELP_CHANNEL", "HELP_COMBAT", "HELP_DEBUG" }) do
    print("  " .. L[key])
  end
  if ns.slashHa == "registered" then print("  " .. L["HELP_SHORT"]) end
end

-- Nach jeder Änderung per Slash-Befehl ein offenes Menü aktualisieren
local function changed(setting)
  ns.Debug:Add("setting", setting)
  ns.Options:Notify()
end

local commands = {}

function commands.help()
  printHelp()
end

function commands.status()
  local A, p = ns.Alerts, ns.db.profile
  Print(L["STATUS_HEADER"]:format(ns.VERSION))
  local state = A.active and L["STATUS_ACTIVE"] or L["STATUS_INACTIVE"]
  print("  " .. L["STATUS_STATE"]:format(state, tostring(A.specName), tostring(A.specID)))
  for _, alert in ipairs(A.ORDER) do
    local a = p.alerts[alert]
    print("  " .. L["STATUS_ALERT"]:format(L["ALERT_" .. alert], onOff(a.enabled), ns.Sounds:Label(a.sound)))
  end
  print("  " .. L["STATUS_OPTIONS"]:format(onOff(p.judgeOnly), L["CHANNEL_" .. p.channel], onOff(p.combatOnly),
    onOff(ns.Debug:IsEnabled())))
end

function commands.test(arg)
  if arg ~= "" and not ALERTS[arg] then printHelp(); return end
  ns.Alerts:Test(arg ~= "" and arg or nil)
end

function commands.sounds()
  Print(L["SOUNDS_HEADER"])
  for i, entry in ipairs(ns.Sounds:List()) do
    print(("  %d. %s"):format(i, entry.label))
  end
  print("  " .. L["SOUNDS_CUSTOM_NOTE"]:format(ns.Sounds.CUSTOM_FOLDER))
end

function commands.sound(arg)
  local alert, choice = arg:match("^(%S+)%s*(.-)$")
  if not ALERTS[alert] or choice == "" then printHelp(); return end
  local key
  if choice == "default" then
    key = ns.Sounds.DEFAULTS[alert]
  else
    local entry = ns.Sounds:List()[tonumber(choice) or 0]
    if not entry then
      Print(L["SOUND_UNKNOWN"])
      return
    end
    key = entry.key
  end
  ns.db.profile.alerts[alert].sound = key
  changed({ alert = alert, sound = key })
  Print(L["SOUND_SET"]:format(L["ALERT_" .. alert], ns.Sounds:Label(key)))
end

function commands.toggle(arg)
  if not ALERTS[arg] then printHelp(); return end
  local a = ns.db.profile.alerts[arg]
  a.enabled = not a.enabled
  changed({ alert = arg, enabled = a.enabled })
  Print(L["ALERT_TOGGLED"]:format(L["ALERT_" .. arg], onOff(a.enabled)))
end

function commands.judge(arg)
  if arg ~= "on" and arg ~= "off" then printHelp(); return end
  ns.db.profile.judgeOnly = arg == "on"
  changed({ judgeOnly = ns.db.profile.judgeOnly })
  Print(L["JUDGE_SET"]:format(onOff(ns.db.profile.judgeOnly)))
end

function commands.channel(arg)
  for _, channel in ipairs(ns.Sounds.CHANNELS) do
    if channel:lower() == arg then
      ns.db.profile.channel = channel
      changed({ channel = channel })
      Print(L["CHANNEL_SET"]:format(L["CHANNEL_" .. channel]))
      return
    end
  end
  printHelp()
end

function commands.combat(arg)
  if arg ~= "on" and arg ~= "off" then printHelp(); return end
  ns.db.profile.combatOnly = arg == "on"
  changed({ combatOnly = ns.db.profile.combatOnly })
  Print(L["COMBAT_SET"]:format(onOff(ns.db.profile.combatOnly)))
end

function commands.debug(arg)
  if arg == "on" then
    ns.Debug:SetEnabled(true)
    ns.Alerts:LogSpec("debugOn")
    ns.Options:Notify()
    Print(L["DEBUG_ON"])
  elseif arg == "off" then
    ns.Debug:Add("debugOff")
    ns.Debug:SetEnabled(false)
    ns.Options:Notify()
    Print(L["DEBUG_OFF"])
  elseif arg == "clear" then
    ns.Debug:Clear()
    Print(L["DEBUG_CLEARED"])
  else
    Print(L["DEBUG_STATUS"]:format(onOff(ns.Debug:IsEnabled()), ns.Debug:Count()))
  end
end

local function onSlash(msg)
  if not ns.db or not ns.loggedIn then return end
  local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  -- LSM-Namen können Großbuchstaben enthalten, werden aber per Nummer gewählt
  arg = arg:lower()
  if cmd == "" then
    -- Menü öffnen; ohne Menü (Bibliothek fehlt, Fehler) die Hilfe zeigen
    if not ns.Options:Open() then printHelp() end
  elseif commands[cmd] then
    local ok, err = pcall(commands[cmd], arg)
    if not ok then
      ns.Debug:Error("slash " .. cmd, err)
      geterrorhandler()(err)
    end
  else
    Print(L["UNKNOWN_COMMAND"])
  end
end

SLASH_HOLYALERT1 = "/holyalert"
SlashCmdList.HOLYALERT = onSlash

-- Kurzform /ha nur, wenn nicht belegt (SPEC 5). Geprüft bei PLAYER_LOGIN, wenn alle Addons
-- geladen sind. Grundlage: Blizzard_ChatFrameBase (wow-ui-source 12.1.0.69933):
--   IsSecureCmd(cmd)          globale Funktion für die geschützten Blizzard-Befehle
--   hash_ChatTypeInfoList     alle schon importierten Slash-Befehle und Chat-Typen (Großbuchstaben)
--   hash_SlashCmdList         schon importierte Slash-Befehle (Großbuchstaben)
--   SlashCmdList + SLASH_<KEY><n>  noch nicht importierte Befehle anderer Addons
-- Eigener Schlüssel HOLYALERTSHORT statt SLASH_HOLYALERT2: Ein bereits importierter Eintrag
-- wird beim Import nicht erneut gelesen (ImportListToHash leert die Liste danach).
local SHORT = "/ha"

local function shortTaken()
  local upper = SHORT:upper()
  if type(IsSecureCmd) == "function" then
    local ok, secure = pcall(IsSecureCmd, SHORT)
    if ok and not issecret(secure) and secure then return "secure" end
  end
  if type(hash_ChatTypeInfoList) == "table" and hash_ChatTypeInfoList[upper] ~= nil then return "chatType" end
  if type(hash_SlashCmdList) == "table" and hash_SlashCmdList[upper] ~= nil then return "slash" end
  if type(SlashCmdList) == "table" then
    for key in pairs(SlashCmdList) do
      if type(key) == "string" then
        local i = 1
        local cmd = _G["SLASH_" .. key .. i]
        while type(cmd) == "string" do
          if cmd:upper() == upper then return "addon:" .. key end
          i = i + 1
          cmd = _G["SLASH_" .. key .. i]
        end
      end
    end
  end
  return nil
end

function registerShortSlash()
  if ns.slashHa then return end
  local ok, taken = pcall(shortTaken)
  if not ok then
    ns.slashHa = "error"
    ns.Debug:Error("shortTaken", taken)
    return
  end
  if taken then
    ns.slashHa = "taken:" .. taken
    return
  end
  SLASH_HOLYALERTSHORT1 = SHORT
  SlashCmdList.HOLYALERTSHORT = onSlash
  ns.slashHa = "registered"
end
