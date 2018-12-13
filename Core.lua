--[[--------------------------------------------------------------------
    Copyright (C) 2018 Johnny C. Lam.
    See the file LICENSE.txt for copying permission.
--]]--------------------------------------------------------------------

local format = string.format
local next = next
local wipe = table.wipe
-- GLOBALS: GetSpellInfo
-- GLOBALS: GetTime
-- GLOBALS: Grid
-- GLOBALS: UnitDebuff
-- GLOBALS: UnitGUID
-- GLOBALS: UnitIsUnit
-- GLOBALS: UnitIsVisible

local GridRoster = Grid:GetModule("GridRoster")
local GridStatus = Grid:GetModule("GridStatus")
local GridStatusAuras = GridStatus:GetModule("GridStatusAuras")
local addon = GridStatus:NewModule("GridStatusWeakenedSoulDebuff", "AceTimer-3.0")

-- The localized string table.
local L = Grid.L
do
	L["Weakened Soul"] = GetSpellInfo(6788)
end

-- active[guid] = unit if unit has player's Weakened Soul and
-- we are showing the time left as the status.
local active = {}
addon.active = active -- for debugging

---------------------------------------------------------------------

local STATUS_NAME = "GSWS_Weakened_Soul"
local STATUS_TEXT = GridStatusAuras:TextForSpell(L["Weakened Soul"])

addon.defaultDB = {
	[STATUS_NAME] = {
		enable = true,
		color = { r = 1, g = 0.5, b = 1, a = 1 },
		priority = 90,
		text = "name",
		refresh = 0.3,
		durationTenths = false,
	}
}

addon.menuName = L["Weakened Soul"]
addon.options = false
local options = {
	text = {
		name = L["Text"],
		desc = L["Text to display on text indicators"],
		order = 20,
		type = "select",
		values = {
			name = STATUS_TEXT,
			duration = L["Time left"],
		},
		get = function()
			return addon.db.profile[STATUS_NAME].text
		end,
		set = function(_, v)
			addon.db.profile[STATUS_NAME].text = v
			addon:UpdateAllUnits()
		end,
	},
	refresh = {
		name = L["Refresh interval"],
		desc = L["Time in seconds between each refresh of the duration status."],
		order = 30,
		type = "range",
		min = 0.1,
		max = 0.5,
		step = 0.1,
		get = function()
			return addon.db.profile[STATUS_NAME].refresh
		end,
		set = function(_, v)
			addon.db.profile[STATUS_NAME].refresh = v
			addon:UpdateAllUnit()
		end,
		hidden = function()
			return addon.db.profile[STATUS_NAME].text ~= "duration"
		end,
	},
	durationTenths = {
		name = L["Show time left to tenths"],
		desc = L["Show the time left to tenths of a second, instead of only whole seconds."],
		order = 40,
		type = "toggle",
		get = function()
			return addon.db.profile[STATUS_NAME].durationTenths
		end,
		set = function(_, v)
			addon.db.profile[STATUS_NAME].durationTenths = v
			addon:UpdateAllUnits()
		end,
		hidden = function()
			return addon.db.profile[STATUS_NAME].text ~= "duration"
		end,
	},
}

---------------------------------------------------------------------

function addon:PostInitialize()
	self:RegisterStatus(STATUS_NAME, L["Weakened Soul"], options, true)
end

function addon:OnStatusEnable(status)
	if status == STATUS_NAME then
		self:RegisterEvent("UNIT_AURA", "OnUnitAura")
		self:RegisterMessage("Grid_RosterUpdated", "OnRosterUpdate")
		self:UpdateAllUnits()
	end
end

function addon:OnStatusDisable(status)
	if status == STATUS_NAME then
		self:UnregisterEvent("UNIT_AURA")
		self:UnregisterMessage("Grid_RosterUpdated")
		wipe(active)
		self:UpdateTimer()
		self.core:SendStatusLostAllUnits(status)
	end
end

function addon:OnRosterUpdate(event)
	self:UpdateAllUnits()
end

function addon:OnUnitAura(event, unit)
	local guid = UnitGUID(unit)
	if GridRoster:IsGUIDInGroup(guid) then
		self:UpdateUnit(guid, unit)
	end
	self:UpdateTimer()
end

---------------------------------------------------------------------

local ICON_TEX_COORDS = { left = 0.06, right = 0.94, top = 0.06, bottom = 0.94 } -- Grid/Statuses/Auras.lua

function addon:UpdateUnit(guid, unit)
	local settings = self.db.profile[STATUS_NAME]
	if settings.enable and UnitIsVisible(unit) then
		local seen = false
		-- Scan all debuffs on the unit.  This should be fairly efficient since
		-- there typically very few debuffs on any friendly unit.
		for i = 1, 40 do
			local name, icon, count, _, duration, expirationTime, unitCaster, _, _, _, _, _, isCastByPlayer = UnitDebuff(unit, i)
			if not name then
				break
			elseif isCastByPlayer and name == L["Weakened Soul"] and UnitIsUnit(unitCaster, "player") then
				local start = expirationTime and (expirationTime - duration)
				local text
				if settings.text == "duration" then
					local now = GetTime()
					local remaining = expirationTime and expirationTime > now and (expirationTime - now) or 0
					if settings.durationTenths then
						text = format("%.1f", remaining)
					else
						text = format("%d", remaining)
					end
					active[guid] = unit
				else -- if settings.text == "name" then
					active[guid] = nil
					text = STATUS_TEXT
				end
				self.core:SendStatusGained(guid, STATUS_NAME,
					settings.priority,
					nil, -- range
					settings.color,
					text,
					nil, nil, -- value, maxValue
					icon,
					start, duration, count,
					ICON_TEX_COORDS)
				seen = true
				break
			end
		end
		if not seen then
			self.core:SendStatusLost(guid, STATUS_NAME)
		end
	end
end

function addon:UpdateAllUnits()
	wipe(active)
	for guid, unit in GridRoster:IterateRoster() do
		self:UpdateUnit(guid, unit)
	end
	self:UpdateTimer()
end

do
	-- Timer for updating the status of the debuff on the roster.
	local timer = nil
	local refresh = nil

	function addon:UpdateTimer()
		if next(active) then
			local settings = self.db.profile[STATUS_NAME]
			if not timer or refresh ~= settings.refresh then
				refresh = settings.refresh
				timer = self:StartTimer("UpdateAllUnits", refresh, true)
			end
		else
			refresh = nil
			if timer then
				self:StopTimer("UpdateAllUnits")
				timer = nil
			end
		end
	end
end