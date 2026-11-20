--[[
	TSM Investment Tracker — core lifecycle, DB, slash commands.
]]

local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME

local TSMIT = LibStub("AceAddon-3.0"):NewAddon("TSMInvestmentTracker", "AceConsole-3.0")
ns.addon = TSMIT

-- TSM AuctionDB "Market Value" (RegisterSource DBMarket).
local MARKET_PRICE_SOURCE = "DBMarket"

local defaults = {
	-- Account-wide: shared by every character on this WoW account.
	global = {
		lots = {},
		nextLotId = 1,
		migratedLotsToGlobal = false,
		hideMarkedBuys = false,
		buySearch = "",
		window = {
			width = 960,
			height = 560,
		},
		minimap = {
			hide = false,
		},
		-- Portfolio table sort: "marked" = earliest marked lot first (stable default).
		portfolioSortKey = "marked",
		portfolioSortAsc = true,
	},
	-- Kept so AceDB can still read older factionrealm data during migration.
	factionrealm = {
		lots = {},
		nextLotId = 1,
	},
	profile = {},
}

local function mergeLotsIntoGlobal(globalStore, sourceLots, sourceNextId)
	if type(sourceLots) ~= "table" then
		return
	end
	local existingKeys = {}
	for _, lot in pairs(globalStore.lots) do
		if lot.acctKey then
			existingKeys[lot.acctKey] = true
		end
	end
	for _, lot in pairs(sourceLots) do
		if type(lot) == "table" and lot.itemString then
			local key = lot.acctKey
			if not key or not existingKeys[key] then
				local lotId = tostring(globalStore.nextLotId)
				globalStore.nextLotId = globalStore.nextLotId + 1
				globalStore.lots[lotId] = lot
				if key then
					existingKeys[key] = true
				end
			end
		end
	end
	local nextId = tonumber(sourceNextId) or 1
	if nextId > (globalStore.nextLotId or 1) then
		globalStore.nextLotId = nextId
	end
end

function TSMIT:MigrateLotsToGlobal()
	local globalStore = self.db.global
	if globalStore.migratedLotsToGlobal then
		return
	end

	-- Current factionrealm (AceDB view).
	mergeLotsIntoGlobal(globalStore, self.db.factionrealm.lots, self.db.factionrealm.nextLotId)

	-- All factionrealm buckets in the raw SV (other factions / realms on this account).
	local sv = self.db.sv
	if type(sv) == "table" and type(sv.factionrealm) == "table" then
		for _, data in pairs(sv.factionrealm) do
			if type(data) == "table" then
				mergeLotsIntoGlobal(globalStore, data.lots, data.nextLotId)
			end
		end
	end

	globalStore.migratedLotsToGlobal = true
end

function TSMIT:SetupMinimapButton()
	local LDB = LibStub("LibDataBroker-1.1", true)
	local DBIcon = LibStub("LibDBIcon-1.0", true)
	if not LDB or not DBIcon then
		return
	end
	if self._minimapRegistered then
		return
	end

	local dataObject = LDB:NewDataObject("TSMInvestmentTracker", {
		type = "launcher",
		label = "TSM Investment Tracker",
		icon = "Interface\\AddOns\\TradeSkillMaster\\Media\\Logo",
		OnClick = function(_, button)
			if button == "LeftButton" then
				ns.UI:Toggle()
			elseif button == "RightButton" then
				ns.UI:Open()
				ns.UI:SelectTab("mark")
			end
		end,
		OnTooltipShow = function(tt)
			tt:AddLine("TSM Investment Tracker")
			tt:AddLine("Left-click: toggle window", 0.7, 0.7, 0.7)
			tt:AddLine("Right-click: Mark Investments", 0.7, 0.7, 0.7)
			tt:AddLine("/tsminv", 0.5, 0.5, 0.5)
		end,
	})
	DBIcon:Register("TSMInvestmentTracker", dataObject, self.db.global.minimap)
	self._minimapRegistered = true
end

function TSMIT:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("TSMInvestmentTrackerDB", defaults, true)
	self:MigrateLotsToGlobal()
	self:RegisterChatCommand("tsminv", "SlashCommand")
	self:RegisterChatCommand("tsminvestment", "SlashCommand")
	self:SetupMinimapButton()
end

function TSMIT:OnEnable()
	self:Print("|cff00ff00TSM Investment Tracker|r loaded. /tsminv")
	if not TSM_API then
		self:Print("|cffff6666TradeSkillMaster is required.|r Enable TSM, then /reload.")
	end
	self:SetupMinimapButton()
end

function TSMIT:SlashCommand(input)
	input = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if input == "help" then
		self:Print("Commands:")
		self:Print("  /tsminv — open portfolio window")
		self:Print("  /tsminv debug — data probe")
		self:Print("  /tsminv help — this help")
		return
	end
	if input == "debug" then
		local lotCount = 0
		for _ in pairs(ns.Lots.GetAll()) do
			lotCount = lotCount + 1
		end
		local rows = ns.Portfolio.Build()
		self:Print(string.format("Lots saved=%d  portfolio rows=%d", lotCount, #rows))
		if rows[1] then
			self:Print(string.format("First row: %s x%d", rows[1].itemString, rows[1].quantity))
		end
		local sv = _G.TradeSkillMasterDB
		local csvKeys, csvRows = 0, 0
		if type(sv) == "table" then
			for key, value in pairs(sv) do
				if type(key) == "string" and key:find("csvBuys", 1, true) and type(value) == "string" then
					csvKeys = csvKeys + 1
					csvRows = csvRows + #ns.Accounting.ParseCsvBuys(value)
				end
			end
		end
		local buys, ok, err = ns.Accounting.GetBuys()
		self:Print(string.format("csvBuys keys=%d rows=%d  GetBuys=%d ok=%s",
			csvKeys, csvRows, #buys, tostring(ok)))
		self:Print(ns.Accounting.GetRuntimeStatus())
		if err then
			self:Print(err)
		end
		return
	end
	ns.UI:Toggle()
end

function TSMIT:GetMarketPriceSource()
	return MARKET_PRICE_SOURCE
end

-- Classic WoW coin colors (amount + denomination).
local COIN_GOLD = "|cffffd100"
local COIN_SILVER = "|cffc7c7cf"
local COIN_COPPER = "|cffeda55f"
local COIN_RESET = "|r"

function TSMIT:FormatMoney(copper)
	if copper == nil then
		return "—"
	end
	copper = tonumber(copper) or 0
	local neg = copper < 0
	copper = math.abs(math.floor(copper + 0.5))
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local c = copper % 100
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = string.format("%s%dg%s", COIN_GOLD, gold, COIN_RESET)
	end
	if silver > 0 or gold > 0 then
		parts[#parts + 1] = string.format("%s%ds%s", COIN_SILVER, silver, COIN_RESET)
	end
	parts[#parts + 1] = string.format("%s%dc%s", COIN_COPPER, c, COIN_RESET)
	local text = table.concat(parts, " ")
	if neg then
		return "-" .. text
	end
	return text
end

function TSMIT:GetItemName(itemString)
	if not itemString then
		return "?"
	end
	if TSM_API and TSM_API.GetItemName then
		local name = TSM_API.GetItemName(itemString)
		if name and name ~= "" then
			return name
		end
	end
	local itemId = self:GetItemID(itemString)
	if itemId then
		local name = GetItemInfo(itemId)
		if name then
			return name
		end
		-- Request cache load; UI refreshes on GET_ITEM_INFO_RECEIVED.
		if C_Item and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(itemId)
		end
		return "Item " .. tostring(itemId)
	end
	return tostring(itemString)
end

function TSMIT:GetItemID(itemString)
	return tonumber(tostring(itemString or ""):match("item:(%d+)") or tostring(itemString or ""):match("^i:(%d+)$"))
end

function TSMIT:GetItemIcon(itemString)
	if not itemString then
		return 134400 -- inv_misc_questionmark
	end
	local itemId = self:GetItemID(itemString)
	if itemId then
		-- Try common Forever/Classic APIs in order.
		if C_Item and C_Item.GetItemIconByID then
			local icon = C_Item.GetItemIconByID(itemId)
			if icon then
				return icon
			end
		end
		if GetItemIcon then
			local icon = GetItemIcon(itemId)
			if icon then
				return icon
			end
		end
		if GetItemInfoInstant then
			local icon = select(5, GetItemInfoInstant(itemId))
			if icon then
				return icon
			end
		end
		local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemId)
		if texture then
			return texture
		end
	end
	return 134400
end

function TSMIT:GetItemLink(itemString)
	if TSM_API and TSM_API.GetItemLink then
		local link = TSM_API.GetItemLink(itemString)
		if link then
			return link
		end
	end
	local itemId = self:GetItemID(itemString)
	if itemId then
		local _, link = GetItemInfo(itemId)
		if link then
			return link
		end
		if C_Item and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(itemId)
		end
		return self:GetItemName(itemString)
	end
	return self:GetItemName(itemString)
end
