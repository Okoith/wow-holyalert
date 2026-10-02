local ADDON_NAME, ns = ...
local L = ns.L

-- Einstellungsmenü (SPEC 5) mit AceConfig-3.0 / AceConfigDialog-3.0, aus VoidAlert übernommen.
-- Eingetragen unter Einstellungen > AddOns > HolyAlert; /holyalert öffnet dasselbe Menü als
-- eigenständiges AceConfigDialog-Fenster. Keine Profilseite: AceDB legt automatisch ein Profil
-- pro Charakter an.

local Options = {}
ns.Options = Options

local AceConfig = LibStub("AceConfig-3.0", true)
local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)

---------------------------------------------------------------------------
-- Zugriff auf Profilwerte über info.arg = { "pfad", "zum", "schlüssel" }
---------------------------------------------------------------------------

local function resolve(path)
  local t = ns.db.profile
  for i = 1, #path - 1 do t = t[path[i]] end
  return t, path[#path]
end

local function get(info)
  local t, k = resolve(info.arg)
  return t[k]
end

local function set(info, value)
  local t, k = resolve(info.arg)
  t[k] = value
  ns.Debug:Add("option", { name = table.concat(info.arg, "."), value = value })
end

---------------------------------------------------------------------------
-- Soundauswahl: Werte und Reihenfolge aus ns.Sounds:List() (mitgeliefert, eigene, WoW, LSM).
-- Ein gespeicherter Schlüssel, der nicht mehr in der Liste ist (z. B. LSM-Addon entfernt),
-- erscheint als "<Name> (fehlt)", damit das Dropdown nicht leer ist. Er wird nicht überschrieben.
---------------------------------------------------------------------------

local function missingLabel(key)
  local name = tostring(key):match("^%a+:(.+)$") or tostring(key)
  return L["SOUND_MISSING"]:format(name)
end

local function soundValues(alert)
  local values, sorting = {}, {}
  for _, entry in ipairs(ns.Sounds:List()) do
    values[entry.key] = entry.label
    sorting[#sorting + 1] = entry.key
  end
  local current = ns.db.profile.alerts[alert].sound
  if current ~= nil and values[current] == nil then
    values[current] = missingLabel(current)
    sorting[#sorting + 1] = current
  end
  return values, sorting
end

local function soundGroup(alert, order)
  return {
    type = "group", order = order, inline = true, name = L["ALERT_" .. alert],
    args = {
      enabled = {
        type = "toggle", order = 1, name = L["OPT_ENABLED"],
        arg = { "alerts", alert, "enabled" }, get = get, set = set,
      },
      sound = {
        type = "select", order = 2, name = L["OPT_SOUND"], width = "double",
        values = function() return (soundValues(alert)) end,
        sorting = function() return select(2, soundValues(alert)) end,
        arg = { "alerts", alert, "sound" }, get = get, set = set,
      },
      test = {
        type = "execute", order = 3, name = L["OPT_TEST"],
        func = function() ns.Alerts:Test(alert) end,
      },
    },
  }
end

---------------------------------------------------------------------------
-- Optionstabelle
---------------------------------------------------------------------------

local function buildOptions()
  local channels = {}
  for _, channel in ipairs(ns.Sounds.CHANNELS) do channels[channel] = L["CHANNEL_" .. channel] end

  return {
    type = "group",
    name = "HolyAlert",
    args = {
      -- Hinweis oben (SPEC 3.3 und 5): inaktiv auf anderen Klassen/Specs, sonst Statuszeile
      inactive = {
        type = "description", order = 0, fontSize = "medium", width = "full",
        name = function() return "|cffff8020" .. L["NOT_AVAILABLE"] .. "|r\n" end,
        hidden = function() return ns.Alerts.active end,
      },
      status = {
        type = "description", order = 1, fontSize = "medium", width = "full",
        name = function()
          local A = ns.Alerts
          return L["OPT_STATUS"]:format(tostring(A.specName or "?"), tostring(A.specID or "?")) .. "\n"
        end,
        hidden = function() return not ns.Alerts.active end,
      },

      storm = soundGroup("storm", 10),
      verdict = soundGroup("verdict", 20),

      general = {
        type = "group", order = 30, inline = true, name = L["OPT_GENERAL"],
        args = {
          judgeOnly = {
            type = "toggle", order = 0, width = "full", name = L["OPT_JUDGE_ONLY"], desc = L["OPT_JUDGE_ONLY_DESC"],
            arg = { "judgeOnly" }, get = get, set = set,
          },
          channel = {
            type = "select", order = 1, name = L["OPT_CHANNEL"], desc = L["OPT_CHANNEL_DESC"],
            values = channels, sorting = ns.Sounds.CHANNELS,
            arg = { "channel" }, get = get, set = set,
          },
          combatOnly = {
            type = "toggle", order = 2, name = L["OPT_COMBAT_ONLY"], desc = L["OPT_COMBAT_ONLY_DESC"],
            arg = { "combatOnly" }, get = get, set = set,
          },
          chatMessages = {
            type = "toggle", order = 3, name = L["OPT_CHAT"], desc = L["OPT_CHAT_DESC"],
            arg = { "chatMessages" }, get = get, set = set,
          },
          testBoth = {
            type = "execute", order = 4, name = L["OPT_TEST_BOTH"],
            func = function() ns.Alerts:Test() end,
          },
        },
      },

      custom = {
        type = "group", order = 40, inline = true, name = L["OPT_CUSTOM"],
        args = {
          note = {
            type = "description", order = 1, width = "full",
            name = function() return L["OPT_CUSTOM_NOTE"]:format(ns.Sounds.CUSTOM_FOLDER) end,
          },
        },
      },

      debug = {
        type = "group", order = 90, inline = true, name = L["OPT_DEBUG"],
        args = {
          debug = {
            type = "toggle", order = 1, name = L["OPT_DEBUG"], desc = L["OPT_DEBUG_DESC"],
            get = function() return ns.Debug:IsEnabled() end,
            set = function(_, value)
              if value then
                ns.Debug:SetEnabled(true)
                ns.Debug:Add("option", { name = "debug", value = true })
                ns.Alerts:LogSpec("debugOn")
              else
                ns.Debug:Add("option", { name = "debug", value = false })
                ns.Debug:SetEnabled(false)
              end
            end,
          },
          clear = {
            type = "execute", order = 2, name = L["OPT_DEBUG_CLEAR"],
            desc = function() return L["DEBUG_COUNT"]:format(ns.Debug:Count()) end,
            func = function()
              ns.Debug:Clear()
              ns.Print(L["DEBUG_CLEARED"])
            end,
          },
        },
      },
    },
  }
end

---------------------------------------------------------------------------
-- Registrieren und Öffnen
---------------------------------------------------------------------------

function Options:Init()
  if not (AceConfig and AceConfigDialog) then
    ns.Debug:Error("Options", "AceConfig-3.0 missing")
    return
  end
  local ok, err = pcall(function()
    AceConfig:RegisterOptionsTable(ADDON_NAME, buildOptions())
    local _, categoryID = AceConfigDialog:AddToBlizOptions(ADDON_NAME, "HolyAlert")
    self.categoryID = categoryID
  end)
  if not ok then ns.Debug:Error("Options:Init", err) end
  self.ready = ok
end

-- Eigenständiges AceConfigDialog-Fenster (SPEC 5, wie VoidAlert). Settings.OpenToCategory zeigte
-- bei OwnDPS nicht zuverlässig ein Fenster. Rückgabe true, wenn das Fenster geöffnet wurde.
function Options:Open()
  if not (self.ready and AceConfigDialog) then return false end
  local ok, err = pcall(AceConfigDialog.Open, AceConfigDialog, ADDON_NAME)
  ns.Debug:Add("optionsOpen", { ok = ok, err = err })
  if not ok then ns.Debug:Error("AceConfigDialog:Open", err) end
  return ok
end

-- Offenes Menü aktualisieren, wenn sich etwas außerhalb davon ändert (Slash-Befehl, Spezialisierung)
function Options:Notify()
  local registry = LibStub("AceConfigRegistry-3.0", true)
  if registry then pcall(registry.NotifyChange, registry, ADDON_NAME) end
end
