--[[
	Native UI styled like TSM.

	Forever quirk: FontString/Texture on custom Frames inside the list often do not
	draw (headers/totals outside the list do). Row cells therefore use Buttons
	(SetText / SetNormalTexture), which reliably render on this client.
]]

local _, ns = ...

local UI = {}
ns.UI = UI

local C = {
	bg = { 0.10, 0.10, 0.10, 1 },
	panel = { 0.14, 0.14, 0.14, 1 },
	rowA = { 0.16, 0.16, 0.16, 1 },
	rowB = { 0.12, 0.12, 0.12, 1 },
	rowHover = { 0.22, 0.22, 0.18, 1 },
	border = { 0.30, 0.30, 0.30, 1 },
	header = { 1.00, 0.82, 0.00, 1 },
	accent = { 0.95, 0.78, 0.20, 1 },
	text = { 0.90, 0.90, 0.90, 1 },
	muted = { 0.60, 0.60, 0.60, 1 },
	tabOn = { 0.20, 0.20, 0.16, 1 },
	tabOff = { 0.12, 0.12, 0.12, 1 },
	btnBg = { 0.14, 0.14, 0.14, 1 },
	btnBgHover = { 0.20, 0.20, 0.18, 1 },
	btnBgPressed = { 0.24, 0.24, 0.20, 1 },
	btnBorder = { 0.38, 0.38, 0.36, 1 },
	btnBorderHover = { 0.62, 0.58, 0.40, 1 },
	profit = "|cff4ff720",
	loss = "|cfff72d20",
	reset = "|r",
}

-- TSM Media/IconPack.tga (256x256). Coords from TSM TexturePacks 14x14 carets.
local TSM_ICONPACK = "Interface\\AddOns\\TradeSkillMaster\\Media\\IconPack.tga"
local CARET_RIGHT = { 40 / 256, 54 / 256, 176 / 256, 190 / 256 }
local CARET_DOWN = { 40 / 256, 54 / 256, 160 / 256, 174 / 256 }

local ROW_HEIGHT = 26
local HEADER_HEIGHT = 22
local ICON_SIZE = 18
local DEFAULT_VISIBLE_ROWS = 14
local DEFAULT_WIDTH = 960
local DEFAULT_HEIGHT = 560
local MIN_WIDTH = 900
local MIN_HEIGHT = 320

local frame
local activeTab = "portfolio"
local portfolioSortKey = "marked"
local portfolioSortAsc = true

local function LoadPortfolioSortPrefs()
	local g = ns.addon and ns.addon.db and ns.addon.db.global
	if not g then
		return
	end
	if type(g.portfolioSortKey) == "string" then
		portfolioSortKey = g.portfolioSortKey
	end
	if g.portfolioSortAsc ~= nil then
		portfolioSortAsc = g.portfolioSortAsc and true or false
	end
end

local function SavePortfolioSortPrefs()
	local g = ns.addon and ns.addon.db and ns.addon.db.global
	if not g then
		return
	end
	g.portfolioSortKey = portfolioSortKey
	g.portfolioSortAsc = portfolioSortAsc and true or false
end
local portfolioOffset = 0
local markOffset = 0

local portfolioRowsData = {}
local portfolioDisplay = {} -- flat list: item rows + expanded lot rows
local expandedItems = {} -- [itemString] = true
local markRowsData = {}
local markStatusSuffix = ""
local widgets = {}

local function CreateSolid(parent, name)
	local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
	f:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})
	f:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 1)
	f:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
	return f
end

local function CreateLabel(parent, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	fs:SetWordWrap(false)
	return fs
end

--- Forever only draws SetText reliably on UIPanelButtonTemplate buttons.
--- Strip all button chrome so it looks like plain left-aligned text.
local function StripButtonChrome(btn)
	btn:SetNormalTexture("")
	btn:SetPushedTexture("")
	btn:SetHighlightTexture("")
	btn:SetDisabledTexture("")
	for _, key in ipairs({ "Left", "Right", "Middle", "Center", "LeftSeparator", "RightSeparator" }) do
		local tex = btn[key]
		if tex then
			if tex.SetTexture then
				tex:SetTexture(nil)
			end
			tex:SetAlpha(0)
			tex:Hide()
		end
	end
	local regions = { btn:GetRegions() }
	for _, region in ipairs(regions) do
		if region and region.IsObjectType and region:IsObjectType("Texture") then
			region:SetTexture(nil)
			region:SetAlpha(0)
			region:Hide()
		end
	end
end

local function StylePlainTextFont(btn)
	local fs = btn:GetFontString()
	if not fs then
		return
	end
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", btn, "LEFT", 0, 0)
	fs:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	-- Keep fontstring visible even if parent alpha tricks happen.
	fs:SetAlpha(1)
	fs:Show()
end

local function CreateTextCell(parent, width)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width, ROW_HEIGHT - 6)
	btn:EnableMouse(false)
	StripButtonChrome(btn)
	btn.SetCellText = function(self, text)
		self:SetText(text or "")
		StripButtonChrome(self) -- template may restore art on SetText
		StylePlainTextFont(self)
	end
	btn:SetCellText("")
	return btn
end

local function CreateIconCell(parent)
	-- Texture on a tiny frame (icons via Button NormalTexture also work).
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(ICON_SIZE, ICON_SIZE)
	holder.tex = holder:CreateTexture(nil, "ARTWORK")
	holder.tex:SetAllPoints()
	holder.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	holder.SetCellIcon = function(self, texture)
		self.tex:SetTexture(texture or 134400)
		self:SetSize(ICON_SIZE, ICON_SIZE)
	end
	holder:SetCellIcon(134400)
	return holder
end

local function SafeText(value)
	if value == nil then
		return ""
	end
	return tostring(value)
end

local function ColoredMoney(copper, addon)
	if copper == nil then
		return "—"
	end
	-- Keep g/s/c coin colors; only tint the sign for profit/loss.
	local text = addon:FormatMoney(math.abs(copper))
	if copper > 0 then
		return C.profit .. "+" .. C.reset .. text
	elseif copper < 0 then
		return C.loss .. "-" .. C.reset .. text
	end
	return text
end

local function ColoredPct(pct)
	if pct == nil then
		return "—"
	end
	local text = string.format("%+.1f%%", pct)
	if pct > 0 then
		return C.profit .. text .. C.reset
	elseif pct < 0 then
		return C.loss .. text .. C.reset
	end
	return text
end

local function FormatTime(ts)
	ts = tonumber(ts) or 0
	if ts <= 0 then
		return "—"
	end
	return date("%Y-%m-%d %H:%M", ts)
end

local function ItemIdFromString(itemString)
	return tonumber(tostring(itemString or ""):match("item:(%d+)") or tostring(itemString or ""):match("^i:(%d+)$"))
end

local function ShowItemTooltip(owner, itemString)
	local addon = ns.addon
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local link = addon:GetItemLink(itemString)
	if link and link:find("|H") then
		GameTooltip:SetHyperlink(link)
	else
		local itemId = ItemIdFromString(itemString)
		if itemId then
			GameTooltip:SetHyperlink("item:" .. itemId)
		else
			GameTooltip:SetText(addon:GetItemName(itemString))
		end
	end
	GameTooltip:Show()
end

local function SetTabVisual(btn, selected)
	if selected then
		btn:SetBackdropColor(C.tabOn[1], C.tabOn[2], C.tabOn[3], 1)
		btn.label:SetTextColor(C.header[1], C.header[2], C.header[3], 1)
	else
		btn:SetBackdropColor(C.tabOff[1], C.tabOff[2], C.tabOff[3], 1)
		btn.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
	end
end

local function CreateTabButton(parent, text, value)
	local btn = CreateSolid(parent)
	btn:SetSize(160, 26)
	btn.value = value
	btn.label = CreateLabel(btn, "GameFontNormal")
	btn.label:SetPoint("CENTER")
	btn.label:SetText(text)
	btn:EnableMouse(true)
	btn:SetScript("OnMouseUp", function()
		UI:SelectTab(value)
	end)
	btn:SetScript("OnEnter", function(self)
		if activeTab ~= value then
			self:SetBackdropColor(0.18, 0.18, 0.18, 1)
		end
	end)
	btn:SetScript("OnLeave", function(self)
		SetTabVisual(self, activeTab == value)
	end)
	return btn
end

local function CreateHeaderButton(parent, text, width, onClick)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width, HEADER_HEIGHT)
	btn:SetNormalFontObject(GameFontNormalSmall)
	btn:SetHighlightFontObject(GameFontNormalSmall)
	btn:SetPushedTextOffset(0, 0)
	btn:SetNormalTexture("")
	btn:SetHighlightTexture("")
	btn:SetPushedTexture("")
	btn:SetText(text)
	local fs = btn:GetFontString()
	if fs then
		fs:SetTextColor(C.header[1], C.header[2], C.header[3], 1)
		fs:SetJustifyH("LEFT")
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", 2, 0)
	end
	btn:SetScript("OnClick", onClick)
	btn.label = { SetText = function(_, t) btn:SetText(t) end }
	return btn
end

local function StyleActionButtonFont(btn, disabled)
	local fs = btn:GetFontString()
	if not fs then
		return
	end
	fs:ClearAllPoints()
	fs:SetPoint("CENTER")
	fs:SetJustifyH("CENTER")
	fs:SetWordWrap(false)
	if disabled then
		fs:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)
	else
		fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3], 1)
	end
	fs:SetAlpha(1)
	fs:Show()
end

local function PaintActionButton(btn, state)
	local disabled = not btn:IsEnabled()
	if disabled then
		btn.bg:SetVertexColor(0.12, 0.12, 0.12, 1)
		btn.border:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
		StyleActionButtonFont(btn, true)
		return
	end
	if state == "pressed" then
		btn.bg:SetVertexColor(C.btnBgPressed[1], C.btnBgPressed[2], C.btnBgPressed[3], 1)
		btn.border:SetBackdropBorderColor(C.btnBorderHover[1], C.btnBorderHover[2], C.btnBorderHover[3], 1)
	elseif state == "hover" then
		btn.bg:SetVertexColor(C.btnBgHover[1], C.btnBgHover[2], C.btnBgHover[3], 1)
		btn.border:SetBackdropBorderColor(C.btnBorderHover[1], C.btnBorderHover[2], C.btnBorderHover[3], 1)
	else
		btn.bg:SetVertexColor(C.btnBg[1], C.btnBg[2], C.btnBg[3], 1)
		btn.border:SetBackdropBorderColor(C.btnBorder[1], C.btnBorder[2], C.btnBorder[3], 1)
	end
	StyleActionButtonFont(btn, false)
end

--- Flat TSM-like action button (dark fill, gold label). Uses UIPanelButtonTemplate
--- under the hood so Forever still draws the text in list rows.
local function CreateActionButton(parent, text, width)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width or 80, 22)
	StripButtonChrome(btn)

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	btn.bg = bg

	local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
	border:SetAllPoints()
	border:SetBackdrop({
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})
	border:EnableMouse(false)
	btn.border = border

	local rawSetText = btn.SetText
	btn.SetText = function(self, value)
		rawSetText(self, value or "")
		StripButtonChrome(self)
		PaintActionButton(self, self:IsMouseOver() and "hover" or "normal")
	end

	btn:HookScript("OnEnter", function(self)
		PaintActionButton(self, "hover")
	end)
	btn:HookScript("OnLeave", function(self)
		PaintActionButton(self, "normal")
	end)
	btn:HookScript("OnMouseDown", function(self)
		if self:IsEnabled() then
			PaintActionButton(self, "pressed")
		end
	end)
	btn:HookScript("OnMouseUp", function(self)
		PaintActionButton(self, self:IsMouseOver() and "hover" or "normal")
	end)
	btn:HookScript("OnEnable", function(self)
		PaintActionButton(self, "normal")
	end)
	btn:HookScript("OnDisable", function(self)
		PaintActionButton(self, "normal")
	end)

	btn:SetText(text)
	return btn
end

--- TSM IconPack caret expander (right = collapsed, down = expanded).
local function CreateExpandButton(parent)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(16, 16)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(14, 14)
	icon:SetPoint("CENTER")
	icon:SetTexture(TSM_ICONPACK)
	btn.icon = icon

	btn.SetExpanded = function(self, expanded)
		local c = expanded and CARET_DOWN or CARET_RIGHT
		self.icon:SetTexCoord(c[1], c[2], c[3], c[4])
		self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
		self._expanded = expanded and true or false
	end

	btn:SetScript("OnEnter", function(self)
		self.icon:SetVertexColor(1, 1, 0.75, 1)
	end)
	btn:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
	end)

	btn:SetExpanded(false)
	return btn
end

local function EnsurePool(parent, pool, count, builder)
	while #pool < count do
		pool[#pool + 1] = builder(parent, #pool + 1)
	end
end

local function GetVisibleRows(list)
	local h = list and list:GetHeight() or 0
	if not h or h < ROW_HEIGHT then
		return DEFAULT_VISIBLE_ROWS
	end
	return math.max(1, math.floor(h / ROW_HEIGHT))
end

local function ClampOffset(offset, dataCount, visible)
	local maxOffset = math.max(0, dataCount - visible)
	if offset < 0 then
		return 0
	end
	if offset > maxOffset then
		return maxOffset
	end
	return offset
end

local function AttachMouseWheel(listFrame, getOffset, setOffset, getDataCount, refresh)
	listFrame:EnableMouseWheel(true)
	listFrame:SetScript("OnMouseWheel", function(_, delta)
		local offset = getOffset()
		if delta > 0 then
			offset = offset - 1
		else
			offset = offset + 1
		end
		setOffset(ClampOffset(offset, getDataCount(), GetVisibleRows(listFrame)))
		refresh()
	end)
end

local function BuildPortfolioRow(parent, index)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("LEFT", 0, 0)
	row:SetPoint("RIGHT", 0, 0)
	row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	row:SetBackdropColor(C.rowA[1], C.rowA[2], C.rowA[3], 1)
	row:EnableMouse(true)

	row.expand = CreateExpandButton(row)
	row.expand:SetPoint("LEFT", 4, 0)

	row.icon = CreateIconCell(row)
	row.icon:SetPoint("LEFT", 26, 0)

	row.name = CreateTextCell(row, 130)
	row.name:SetPoint("LEFT", 48, 0)
	row.qty = CreateTextCell(row, 40)
	row.qty:SetPoint("LEFT", 182, 0)
	row.avg = CreateTextCell(row, 90)
	row.avg:SetPoint("LEFT", 226, 0)
	row.market = CreateTextCell(row, 90)
	row.market:SetPoint("LEFT", 320, 0)
	row.basis = CreateTextCell(row, 95)
	row.basis:SetPoint("LEFT", 414, 0)
	row.mktVal = CreateTextCell(row, 95)
	row.mktVal:SetPoint("LEFT", 513, 0)
	row.unrealized = CreateTextCell(row, 95)
	row.unrealized:SetPoint("LEFT", 612, 0)
	row.pct = CreateTextCell(row, 55)
	row.pct:SetPoint("LEFT", 711, 0)

	row.remove = CreateActionButton(row, "Remove", 70)
	row.remove:SetPoint("RIGHT", -6, 0)

	row:SetScript("OnEnter", function(self)
		self:SetBackdropColor(C.rowHover[1], C.rowHover[2], C.rowHover[3], 1)
		if self.itemString then
			ShowItemTooltip(self, self.itemString)
		end
	end)
	row:SetScript("OnLeave", function(self)
		local c = (self.stripe == 1) and C.rowA or C.rowB
		self:SetBackdropColor(c[1], c[2], c[3], 1)
		GameTooltip:Hide()
	end)

	return row
end

local function BuildPortfolioLotRow(parent, index)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("LEFT", 0, 0)
	row:SetPoint("RIGHT", 0, 0)
	row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	row:SetBackdropColor(0.10, 0.10, 0.12, 1)
	row:EnableMouse(true)

	row.marker = CreateTextCell(row, 40)
	row.marker:SetPoint("LEFT", 28, 0)
	row.qty = CreateTextCell(row, 40)
	row.qty:SetPoint("LEFT", 70, 0)
	row.price = CreateTextCell(row, 90)
	row.price:SetPoint("LEFT", 114, 0)
	row.time = CreateTextCell(row, 110)
	row.time:SetPoint("LEFT", 208, 0)
	row.source = CreateTextCell(row, 60)
	row.source:SetPoint("LEFT", 322, 0)
	row.buyer = CreateTextCell(row, 100)
	row.buyer:SetPoint("LEFT", 386, 0)
	row.seller = CreateTextCell(row, 100)
	row.seller:SetPoint("LEFT", 490, 0)
	row.unrealized = CreateTextCell(row, 95)
	row.unrealized:SetPoint("LEFT", 594, 0)

	row.unmark = CreateActionButton(row, "Unmark", 70)
	row.unmark:SetPoint("RIGHT", -6, 0)

	return row
end

local function BuildPortfolioDisplay(itemRows)
	local display = {}
	for _, entry in ipairs(itemRows) do
		display[#display + 1] = { kind = "item", entry = entry }
		if expandedItems[entry.itemString] then
			for _, info in ipairs(ns.Lots.GetByItem(entry.itemString)) do
				display[#display + 1] = {
					kind = "lot",
					itemString = entry.itemString,
					lotId = info.id,
					lot = info.lot,
					market = entry.market,
				}
			end
		end
	end
	return display
end

local function BuildMarkRow(parent, index)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("LEFT", 0, 0)
	row:SetPoint("RIGHT", 0, 0)
	row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	row:SetBackdropColor(C.rowA[1], C.rowA[2], C.rowA[3], 1)
	row:EnableMouse(true)

	row.icon = CreateIconCell(row)
	row.icon:SetPoint("LEFT", 6, 0)

	row.name = CreateTextCell(row, 140)
	row.name:SetPoint("LEFT", 28, 0)
	row.qty = CreateTextCell(row, 40)
	row.qty:SetPoint("LEFT", 172, 0)
	row.price = CreateTextCell(row, 90)
	row.price:SetPoint("LEFT", 216, 0)
	row.time = CreateTextCell(row, 110)
	row.time:SetPoint("LEFT", 310, 0)
	row.source = CreateTextCell(row, 60)
	row.source:SetPoint("LEFT", 424, 0)
	row.buyer = CreateTextCell(row, 100)
	row.buyer:SetPoint("LEFT", 488, 0)
	row.seller = CreateTextCell(row, 100)
	row.seller:SetPoint("LEFT", 592, 0)

	row.action = CreateActionButton(row, "Mark", 70)
	row.action:SetPoint("RIGHT", -6, 0)

	row:SetScript("OnEnter", function(self)
		self:SetBackdropColor(C.rowHover[1], C.rowHover[2], C.rowHover[3], 1)
		if self.itemString then
			ShowItemTooltip(self, self.itemString)
		end
	end)
	row:SetScript("OnLeave", function(self)
		local c = (self.stripe == 1) and C.rowA or C.rowB
		self:SetBackdropColor(c[1], c[2], c[3], 1)
		GameTooltip:Hide()
	end)

	return row
end

function UI:RefreshPortfolioRows()
	if not widgets.portfolioList then
		return
	end
	local addon = ns.addon
	local list = widgets.portfolioList
	local itemPool = widgets.portfolioPool
	local lotPool = widgets.portfolioLotPool

	portfolioDisplay = BuildPortfolioDisplay(portfolioRowsData)
	local visibleRows = GetVisibleRows(list)
	portfolioOffset = ClampOffset(portfolioOffset, #portfolioDisplay, visibleRows)

	EnsurePool(list, itemPool, visibleRows, BuildPortfolioRow)
	EnsurePool(list, lotPool, visibleRows, BuildPortfolioLotRow)

	for i = 1, #itemPool do
		itemPool[i]:Hide()
		itemPool[i].itemString = nil
	end
	for i = 1, #lotPool do
		lotPool[i]:Hide()
		lotPool[i].lotId = nil
	end

	local itemUsed, lotUsed = 0, 0
	for vis = 1, visibleRows do
		local d = portfolioDisplay[portfolioOffset + vis]
		if not d then
			break
		end
		local y = -((vis - 1) * ROW_HEIGHT)
		if d.kind == "item" then
			itemUsed = itemUsed + 1
			local row = itemPool[itemUsed]
			local entry = d.entry
			row:Show()
			row:ClearAllPoints()
			row:SetHeight(ROW_HEIGHT)
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, y)
			row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, y)
			row.stripe = ((portfolioOffset + vis) % 2)
			local c = (row.stripe == 1) and C.rowA or C.rowB
			row:SetBackdropColor(c[1], c[2], c[3], 1)
			row.itemString = entry.itemString
			local expanded = expandedItems[entry.itemString]
			row.expand:SetExpanded(expanded)
			row.expand:SetScript("OnClick", function()
				if expandedItems[entry.itemString] then
					expandedItems[entry.itemString] = nil
				else
					expandedItems[entry.itemString] = true
				end
				UI:RefreshPortfolioRows()
			end)
			row.icon:SetCellIcon(addon:GetItemIcon(entry.itemString))
			row.name:SetCellText(SafeText(addon:GetItemName(entry.itemString)))
			row.qty:SetCellText(SafeText(entry.quantity))
			row.avg:SetCellText(SafeText(addon:FormatMoney(math.floor(entry.avgCost + 0.5))))
			row.market:SetCellText(entry.market and SafeText(addon:FormatMoney(entry.market)) or "—")
			row.basis:SetCellText(SafeText(addon:FormatMoney(entry.costBasis)))
			row.mktVal:SetCellText(entry.marketValue and SafeText(addon:FormatMoney(entry.marketValue)) or "—")
			row.unrealized:SetCellText(ColoredMoney(entry.unrealized, addon))
			row.pct:SetCellText(ColoredPct(entry.unrealizedPct))
			row.remove:SetScript("OnClick", function()
				expandedItems[entry.itemString] = nil
				local n = ns.Lots.RemoveByItem(entry.itemString)
				addon:Print(string.format("Removed %d lot(s) for %s", n, addon:GetItemName(entry.itemString)))
				UI:RefreshPortfolioTab()
			end)
		else
			lotUsed = lotUsed + 1
			local row = lotPool[lotUsed]
			local lot = d.lot
			row:Show()
			row:ClearAllPoints()
			row:SetHeight(ROW_HEIGHT)
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, y)
			row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, y)
			row.lotId = d.lotId
			row.marker:SetCellText("|cff888888lot|r")
			row.qty:SetCellText(SafeText(lot.quantity))
			row.price:SetCellText(SafeText(addon:FormatMoney(lot.price)))
			row.time:SetCellText(FormatTime(lot.time))
			row.source:SetCellText(SafeText(lot.source))
			row.buyer:SetCellText(SafeText(lot.player))
			row.seller:SetCellText(SafeText(lot.seller))
			if d.market then
				local lotUr = (d.market - (tonumber(lot.price) or 0)) * (tonumber(lot.quantity) or 0)
				row.unrealized:SetCellText(ColoredMoney(lotUr, addon))
			else
				row.unrealized:SetCellText("—")
			end
			row.unmark:SetScript("OnClick", function()
				ns.Lots.Remove(d.lotId)
				-- Collapse if no lots left for this item.
				if #ns.Lots.GetByItem(d.itemString) == 0 then
					expandedItems[d.itemString] = nil
				end
				UI:RefreshPortfolioTab()
			end)
		end
	end

	if widgets.portfolioEmpty then
		if #portfolioRowsData == 0 then
			widgets.portfolioEmpty:Show()
		else
			widgets.portfolioEmpty:Hide()
		end
	end
end

function UI:RefreshMarkRows()
	if not widgets.markList then
		return
	end
	local addon = ns.addon
	local list = widgets.markList
	local pool = widgets.markPool
	local data = markRowsData

	local visibleRows = GetVisibleRows(list)
	markOffset = ClampOffset(markOffset, #data, visibleRows)
	EnsurePool(list, pool, visibleRows, BuildMarkRow)

	for i = 1, #pool do
		local row = pool[i]
		local buy = i <= visibleRows and data[markOffset + i] or nil
		if buy then
			row:Show()
			row:ClearAllPoints()
			row:SetHeight(ROW_HEIGHT)
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
			row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -((i - 1) * ROW_HEIGHT))
			row.stripe = ((markOffset + i) % 2)
			local c = (row.stripe == 1) and C.rowA or C.rowB
			row:SetBackdropColor(c[1], c[2], c[3], 1)
			row.itemString = buy.itemString
			row.icon:SetCellIcon(addon:GetItemIcon(buy.itemString))
			row.name:SetCellText(SafeText(addon:GetItemName(buy.itemString)))
			row.qty:SetCellText(SafeText(buy.quantity))
			row.price:SetCellText(SafeText(addon:FormatMoney(buy.price)))
			row.time:SetCellText(FormatTime(buy.time))
			row.source:SetCellText(SafeText(buy.source))
			row.buyer:SetCellText(SafeText(buy.player))
			row.seller:SetCellText(SafeText(buy.seller))
			local marked = ns.Lots.IsMarked(buy.acctKey)
			row.action:SetText(marked and "Unmark" or "Mark")
			row.action:SetScript("OnClick", function()
				if marked then
					ns.Lots.UnmarkByAcctKey(buy.acctKey)
				else
					local ok, err = ns.Lots.Mark(buy)
					if not ok then
						addon:Print("Could not mark: " .. tostring(err))
					end
				end
				UI:RefreshMarkTab()
			end)
		else
			row:Hide()
			row.itemString = nil
		end
	end

	if widgets.markStatus then
		widgets.markStatus:SetText(string.format("Showing %d purchases (all characters)%s", #data, markStatusSuffix))
	end
end

function UI:RefreshPortfolioTab()
	if activeTab ~= "portfolio" or not widgets.portfolioList then
		return
	end
	local addon = ns.addon
	local rows, totals = ns.Portfolio.Build()
	ns.Portfolio.SortRows(rows, portfolioSortKey, portfolioSortAsc)
	portfolioRowsData = rows

	if widgets.totalsLabel then
		widgets.totalsLabel:SetText(string.format(
			"Cost Basis: %s    Market Value: %s    Unrealized: %s    Items: %d",
			addon:FormatMoney(totals.costBasis),
			addon:FormatMoney(totals.marketValue),
			ColoredMoney(totals.unrealized, addon),
			#rows
		))
	end

	local function arrow(key)
		if portfolioSortKey ~= key then
			return ""
		end
		return portfolioSortAsc and " ^" or " v"
	end
	if widgets.pHeaders then
		widgets.pHeaders.name.label:SetText("Item" .. arrow("name"))
		widgets.pHeaders.qty.label:SetText("Qty" .. arrow("quantity"))
		widgets.pHeaders.avg.label:SetText("Avg Cost" .. arrow("avgCost"))
		widgets.pHeaders.market.label:SetText("Market" .. arrow("market"))
		widgets.pHeaders.basis.label:SetText("Cost Basis" .. arrow("costBasis"))
		widgets.pHeaders.mktVal.label:SetText("Mkt Value" .. arrow("marketValue"))
		widgets.pHeaders.unrealized.label:SetText("Unrealized" .. arrow("unrealized"))
		widgets.pHeaders.pct.label:SetText("%" .. arrow("unrealizedPct"))
	end

	UI:RefreshPortfolioRows()
end

--- Re-loads Mark Investments.
--- @param fromTsm boolean? if true (Refresh button), pull newest TSM Transactions; else saved csvBuys
function UI:RefreshMarkTab(fromTsm)
	if activeTab ~= "mark" or not widgets.markList then
		return
	end
	local addon = ns.addon
	local buys, ok, err
	if fromTsm then
		buys, ok, err = ns.Accounting.FetchLatestBuys()
	else
		buys, ok, err = ns.Accounting.GetBuys()
	end
	if not ok then
		markRowsData = {}
		markStatusSuffix = ""
		UI:RefreshMarkRows()
		if widgets.markStatus then
			widgets.markStatus:SetText("|cffff6666" .. (err or "No Accounting data") .. "|r")
		end
		return
	end

	if fromTsm and ns.Accounting.GetSource() == "flushed" then
		markStatusSuffix = " - refreshed from TSM"
	elseif fromTsm then
		markStatusSuffix = " - saved data ("
			.. tostring(ns.Accounting.GetRuntimeError() or "bridge unavailable") .. ")"
	else
		markStatusSuffix = ""
	end

	local search = addon.db.global.buySearch or ""
	local hideMarked = addon.db.global.hideMarkedBuys
	markRowsData = ns.Accounting.FilterBuys(buys, search, hideMarked, ns.Lots.IsMarked)
	UI:RefreshMarkRows()
end

function UI:RefreshActiveTab()
	if activeTab == "mark" then
		self:RefreshMarkTab()
	else
		self:RefreshPortfolioTab()
	end
end

local function SortPortfolioBy(key)
	if portfolioSortKey == key then
		portfolioSortAsc = not portfolioSortAsc
	else
		portfolioSortKey = key
		portfolioSortAsc = true
	end
	SavePortfolioSortPrefs()
	UI:RefreshPortfolioTab()
end

local function BuildPortfolioPanel(parent)
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetAllPoints()

	local summary = CreateSolid(panel)
	summary:SetPoint("TOPLEFT", 0, 0)
	summary:SetPoint("TOPRIGHT", 0, 0)
	summary:SetHeight(36)

	widgets.totalsLabel = CreateLabel(summary, "GameFontHighlight")
	widgets.totalsLabel:SetPoint("LEFT", 10, 0)
	widgets.totalsLabel:SetPoint("RIGHT", -100, 0)

	local refresh = CreateActionButton(summary, "Refresh", 80)
	refresh:SetPoint("RIGHT", -8, 0)
	refresh:SetScript("OnClick", function()
		UI:RefreshPortfolioTab()
	end)

	local headerBar = CreateSolid(panel)
	headerBar:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -4)
	headerBar:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", 0, -4)
	headerBar:SetHeight(HEADER_HEIGHT + 4)
	headerBar:SetBackdropColor(0.08, 0.08, 0.08, 1)

	local headers = {}
	local x = 48
	local function addH(sortKey, headerKey, label, width)
		local btn = CreateHeaderButton(headerBar, label, width, function()
			SortPortfolioBy(sortKey)
		end)
		btn:SetPoint("LEFT", headerBar, "LEFT", x, 0)
		headers[headerKey] = btn
		x = x + width + 4
	end
	addH("name", "name", "Item", 130)
	addH("quantity", "qty", "Qty", 40)
	addH("avgCost", "avg", "Avg Cost", 90)
	addH("market", "market", "Market", 90)
	addH("costBasis", "basis", "Cost Basis", 95)
	addH("marketValue", "mktVal", "Mkt Value", 95)
	addH("unrealized", "unrealized", "Unrealized", 95)
	addH("unrealizedPct", "pct", "%", 55)
	widgets.pHeaders = headers

	local list = CreateSolid(panel)
	list:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -2)
	list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 4)
	list:SetBackdropColor(0.08, 0.08, 0.08, 1)
	list:EnableMouse(true)
	list:SetScript("OnSizeChanged", function()
		if activeTab == "portfolio" and frame and frame:IsShown() then
			UI:RefreshPortfolioRows()
		end
	end)
	widgets.portfolioList = list
	widgets.portfolioPool = {}

	widgets.portfolioLotPool = {}

	AttachMouseWheel(list,
		function() return portfolioOffset end,
		function(v) portfolioOffset = v end,
		function() return #portfolioDisplay end,
		function() UI:RefreshPortfolioRows() end
	)

	widgets.portfolioEmpty = CreateActionButton(list, "No investments marked yet", 280)
	widgets.portfolioEmpty:SetPoint("CENTER")
	widgets.portfolioEmpty:Disable()
	widgets.portfolioEmpty:Hide()

	return panel
end

local function BuildMarkPanel(parent)
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetAllPoints()

	local filterBar = CreateSolid(panel)
	filterBar:SetPoint("TOPLEFT", 0, 0)
	filterBar:SetPoint("TOPRIGHT", 0, 0)
	filterBar:SetHeight(40)

	local searchLabel = CreateLabel(filterBar)
	searchLabel:SetPoint("LEFT", 10, 0)
	searchLabel:SetText("Search")
	searchLabel:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)

	local search = CreateFrame("EditBox", nil, filterBar, "InputBoxTemplate")
	search:SetSize(180, 20)
	search:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
	search:SetAutoFocus(false)
	search:SetText(ns.addon.db.global.buySearch or "")
	search:SetScript("OnEnterPressed", function(self)
		ns.addon.db.global.buySearch = self:GetText() or ""
		self:ClearFocus()
		UI:RefreshMarkTab()
	end)
	search:SetScript("OnEditFocusLost", function(self)
		ns.addon.db.global.buySearch = self:GetText() or ""
	end)
	widgets.searchBox = search

	local hide = CreateFrame("CheckButton", nil, filterBar, "UICheckButtonTemplate")
	hide:SetPoint("LEFT", search, "RIGHT", 12, 0)
	hide:SetChecked(ns.addon.db.global.hideMarkedBuys)
	hide.text = hide:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	hide.text:SetPoint("LEFT", hide, "RIGHT", 0, 0)
	hide.text:SetText("Hide marked")
	hide:SetScript("OnClick", function(self)
		ns.addon.db.global.hideMarkedBuys = self:GetChecked() and true or false
		UI:RefreshMarkTab()
	end)

	local apply = CreateActionButton(filterBar, "Apply", 70)
	apply:SetPoint("LEFT", hide.text, "RIGHT", 16, 0)
	apply:SetScript("OnClick", function()
		ns.addon.db.global.buySearch = search:GetText() or ""
		UI:RefreshMarkTab()
	end)

	local refresh = CreateActionButton(filterBar, "Refresh", 70)
	refresh:SetPoint("LEFT", apply, "RIGHT", 6, 0)
	refresh:SetScript("OnClick", function()
		UI:RefreshMarkTab(true)
	end)

	widgets.markStatus = CreateLabel(panel)
	widgets.markStatus:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 8, -4)
	widgets.markStatus:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", -8, -4)
	widgets.markStatus:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1)

	local headerBar = CreateSolid(panel)
	headerBar:SetPoint("TOPLEFT", widgets.markStatus, "BOTTOMLEFT", -8, -4)
	headerBar:SetPoint("TOPRIGHT", widgets.markStatus, "BOTTOMRIGHT", 8, -4)
	headerBar:SetHeight(HEADER_HEIGHT + 4)
	headerBar:SetBackdropColor(0.08, 0.08, 0.08, 1)

	local labels = {
		{ "", 22 },
		{ "Item", 140 },
		{ "Qty", 40 },
		{ "Price", 90 },
		{ "Time", 110 },
		{ "Source", 60 },
		{ "Buyer", 100 },
		{ "Seller", 100 },
	}
	local x = 6
	for _, col in ipairs(labels) do
		local btn = CreateHeaderButton(headerBar, col[1], col[2], function() end)
		btn:SetPoint("LEFT", headerBar, "LEFT", x, 0)
		btn:EnableMouse(false)
		x = x + col[2] + 4
	end

	local list = CreateSolid(panel)
	list:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -2)
	list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 4)
	list:SetBackdropColor(0.08, 0.08, 0.08, 1)
	list:EnableMouse(true)
	list:SetScript("OnSizeChanged", function()
		if activeTab == "mark" and frame and frame:IsShown() then
			UI:RefreshMarkRows()
		end
	end)
	widgets.markList = list
	widgets.markPool = {}

	AttachMouseWheel(list,
		function() return markOffset end,
		function(v) markOffset = v end,
		function() return #markRowsData end,
		function() UI:RefreshMarkRows() end
	)

	return panel
end

function UI:SelectTab(tab)
	activeTab = tab
	SetTabVisual(widgets.tabPortfolio, tab == "portfolio")
	SetTabVisual(widgets.tabMark, tab == "mark")
	if tab == "portfolio" then
		widgets.portfolioPanel:Show()
		widgets.markPanel:Hide()
		UI:RefreshPortfolioTab()
	else
		widgets.markPanel:Show()
		widgets.portfolioPanel:Hide()
		UI:RefreshMarkTab()
	end
end

local function BuildFrame()
	wipe(widgets)
	portfolioRowsData = {}
	portfolioDisplay = {}
	wipe(expandedItems)
	markRowsData = {}
	portfolioOffset = 0
	markOffset = 0

	frame = CreateSolid(UIParent, "TSMInvestmentTrackerFrame")
	local saved = ns.addon.db.global.window or {}
	local maxW = math.floor(UIParent:GetWidth())
	local maxH = math.floor(UIParent:GetHeight())
	local w = math.min(math.max(tonumber(saved.width) or DEFAULT_WIDTH, MIN_WIDTH), math.max(maxW, MIN_WIDTH))
	local h = math.min(math.max(tonumber(saved.height) or DEFAULT_HEIGHT, MIN_HEIGHT), math.max(maxH, MIN_HEIGHT))
	frame:SetSize(w, h)
	frame:SetPoint("CENTER")
	frame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.97)
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetClampedToScreen(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, maxW, maxH)
	elseif frame.SetMinResize then
		frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
	end
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetScript("OnShow", function()
		UI:RefreshActiveTab()
	end)
	tinsert(UISpecialFrames, "TSMInvestmentTrackerFrame")

	local title = CreateLabel(frame, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("TSM Investment Tracker")
	title:SetTextColor(C.header[1], C.header[2], C.header[3], 1)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	widgets.tabPortfolio = CreateTabButton(frame, "Portfolio Overview", "portfolio")
	widgets.tabPortfolio:SetPoint("TOPLEFT", 12, -40)
	widgets.tabMark = CreateTabButton(frame, "Mark Investments", "mark")
	widgets.tabMark:SetPoint("LEFT", widgets.tabPortfolio, "RIGHT", 6, 0)

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 12, -72)
	content:SetPoint("BOTTOMRIGHT", -12, 12)

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(frame:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		ns.addon.db.global.window = {
			width = math.floor(frame:GetWidth() + 0.5),
			height = math.floor(frame:GetHeight() + 0.5),
		}
		UI:RefreshActiveTab()
	end)
	widgets.resizeGrip = grip

	widgets.portfolioPanel = BuildPortfolioPanel(content)
	widgets.markPanel = BuildMarkPanel(content)
	widgets.markPanel:Hide()

	frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	frame:SetScript("OnEvent", function(_, event)
		if event == "GET_ITEM_INFO_RECEIVED" and frame:IsShown() then
			UI:RefreshActiveTab()
		end
	end)

	UI:SelectTab("portfolio")
end

function UI:Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
		return
	end
	LoadPortfolioSortPrefs()
	if not frame then
		BuildFrame()
	end
	frame:Show()
	UI:RefreshActiveTab()
end

function UI:Open()
	LoadPortfolioSortPrefs()
	if not frame then
		BuildFrame()
	end
	frame:Show()
	UI:RefreshActiveTab()
end
