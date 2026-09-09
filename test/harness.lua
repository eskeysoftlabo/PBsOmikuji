-- Stub of just enough ESO client to exercise PBsOmikuji.
--
-- The add-on runs on a console, where one real test costs a whole session: build, upload, boot
-- the PS5, log in. Almost everything this add-on decides is arithmetic over two clock readings
-- and a name, so almost all of it can be decided here instead. What is stubbed is only what
-- the add-on actually touches.
--
-- The two clocks are the interesting part. GetTimeStamp is the server's UTC clock and
-- GetSecondsSinceMidnight is the machine's local one, and the tests drive them independently
-- -- which is the only way to check that a player in Japan does not get a new fortune at nine
-- in the morning.
local DIR = ADDON_DIR

-- ---- string table -------------------------------------------------------------------
local stringValues = {}
local nextId = 1
function ZO_CreateStringId(id, value)
	if not _G[id] then _G[id] = nextId; nextId = nextId + 1 end
	stringValues[_G[id]] = value
end
function SafeAddVersion() end
function GetString(id) return stringValues[id] or ("<missing " .. tostring(id) .. ">") end

-- ---- chat ---------------------------------------------------------------------------
Chat = {}
CHAT_ROUTER = { AddSystemMessage = function(_, t) Chat[#Chat + 1] = t end }
function d(t) print("[d] " .. tostring(t)) end
SLASH_COMMANDS = {}

-- Chat lines with the colour markup taken back off, which is what the assertions want to read.
function PlainChat(index)
	local line = Chat[index]
	if not line then return nil end
	return (line:gsub("|c%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- ---- clocks -------------------------------------------------------------------------
-- Defaults put the machine in JST (UTC+9) at 21:00 local on 2026-09-10, which is the case
-- that matters: an evening in Japan is the previous day in UTC.
local serverStamp = 20706 * 86400 + 12 * 3600      -- 2026-09-10 12:00 UTC
local secondsSinceMidnight = 21 * 3600             -- 21:00 local

function SetClock(stamp, sinceMidnight)
	serverStamp = stamp
	secondsSinceMidnight = sinceMidnight
end

-- Puts the machine at a given local day and local time in a given zone. The offset is in
-- hours and may be fractional, because half-hour zones are real and are exactly the kind of
-- thing a snap-to-the-nearest-something goes wrong on.
function SetLocalTime(dayNumber, hour, minute, zoneOffsetHours)
	minute = minute or 0
	zoneOffsetHours = zoneOffsetHours or 9
	secondsSinceMidnight = hour * 3600 + minute * 60
	serverStamp = dayNumber * 86400 + secondsSinceMidnight - math.floor(zoneOffsetHours * 3600)
end

function GetTimeStamp() return serverStamp end
function GetSecondsSinceMidnight() return secondsSinceMidnight end

-- ---- who --------------------------------------------------------------------------
local characterId = "1000000001"
local characterName = "Bosmer Bunbun"
local displayName = "@PinkBanther"

function SetCharacter(id, name)
	characterId = id
	characterName = name or characterId
end

function GetCurrentCharacterId() return characterId end
function GetUnitName(unit) return unit == "player" and characterName or "" end
function GetDisplayName() return displayName end

-- ---- manifest -----------------------------------------------------------------------
-- Read rather than copied: a test that carries its own idea of the version stops testing the
-- release step the moment somebody edits the manifest and not the harness.
function ManifestLine(field)
	local file = io.open(DIR .. "/PBsOmikuji.addon", "r")
	if not file then return nil end
	local found
	for line in file:lines() do
		found = found or line:match("^## " .. field .. ":%s*(.-)%s*$")
	end
	file:close()
	return found
end

function GetAddOnManager()
	return {
		GetNumAddOns = function() return 1 end,
		GetAddOnInfo = function(_, i)
			return "PBsOmikuji", ManifestLine("Title")
		end,
	}
end

-- ---- events -------------------------------------------------------------------------
EVENT_ADD_ON_LOADED = "EVENT_ADD_ON_LOADED"
EVENT_PLAYER_ACTIVATED = "EVENT_PLAYER_ACTIVATED"

local handlers = {}
EVENT_MANAGER = {
	RegisterForEvent = function(_, namespace, event, fn)
		handlers[event] = handlers[event] or {}
		handlers[event][namespace] = fn
	end,
	UnregisterForEvent = function(_, namespace, event)
		if handlers[event] then handlers[event][namespace] = nil end
	end,
}

function Fire(event, ...)
	for _, fn in pairs(handlers[event] or {}) do
		fn(event, ...)
	end
end

-- ---- saved variables ----------------------------------------------------------------
-- Only the account-wide factory, because that is the only one the add-on calls. SavedVars is
-- exposed so a test can throw it away and check the fortune comes back the same, which is the
-- claim the whole design rests on.
SavedVars = nil

local function DeepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = DeepCopy(v) end
	return copy
end

ZO_SavedVars = {
	NewAccountWide = function(_, name, version, namespace, defaults)
		SavedVars = DeepCopy(defaults or {})
		return SavedVars
	end,
}

function ForgetSavedVars()
	if SavedVars then
		SavedVars.records = {}
	end
end

-- ---- settings library ---------------------------------------------------------------
-- Present so InitSettings runs and its closures are exercised; the rows are recorded by label
-- so a test can press a button.
Panel = nil
LibHarvensAddonSettings = {
	ST_LABEL = 1, ST_SECTION = 2, ST_CHECKBOX = 3, ST_DROPDOWN = 4, ST_BUTTON = 5,
	AddAddon = function(_, title)
		Panel = {
			title = title,
			rows = {},
			byLabel = {},
			AddSetting = function(self, row)
				self.rows[#self.rows + 1] = row
				if row.label then self.byLabel[row.label] = row end
			end,
			UpdateControls = function(self) self.updates = (self.updates or 0) + 1 end,
		}
		return Panel
	end,
}

-- ---- load the add-on ----------------------------------------------------------------
dofile(DIR .. "/lang/strings.lua")
dofile(DIR .. "/Main.lua")
dofile(DIR .. "/Fortunes.lua")
dofile(DIR .. "/Draw.lua")
dofile(DIR .. "/Settings.lua")
