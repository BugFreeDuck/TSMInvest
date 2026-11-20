--[[
	Reads TSM Accounting purchase history for the Mark Investments tab.

	Default / after /reload: TradeSkillMasterDB csvBuys (TSM writes these on logout,
	which also runs during /reload).

	Refresh button: ask the TSMIT_TSMBridge (loaded inside TradeSkillMaster) to flush
	live Transactions into csvBuys the same way logout does, then re-read SV.
]]

local _, ns = ...
local Accounting = {}
ns.Accounting = Accounting

local lastError
local lastSource -- "saved" | "flushed" | nil
local runtimeError
local CSV_HEADER_MARK = "itemString,"

local function trim(s)
	if not s then
		return ""
	end
	return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Stable fingerprint of an Accounting buy row (dedupe key).
function Accounting.MakeAcctKey(buy)
	return table.concat({
		tostring(buy.itemString or ""),
		tostring(buy.quantity or 0),
		tostring(buy.price or 0),
		tostring(buy.time or 0),
		tostring(buy.player or ""),
		tostring(buy.seller or ""),
		tostring(buy.source or ""),
	}, "|")
end

local function toItemString(raw)
	if not raw or raw == "" then
		return nil
	end
	if TSM_API and TSM_API.ToItemString then
		local ok, converted = pcall(TSM_API.ToItemString, raw)
		if ok and converted and converted ~= "" then
			return converted
		end
	end
	local id = tostring(raw):match("^i:(%d+)$")
	if id then
		return "i:" .. id
	end
	return tostring(raw)
end

local function normalizeBuy(raw)
	if not raw then
		return nil
	end
	local itemString = toItemString(raw.itemString or raw.item)
	if not itemString then
		return nil
	end
	local quantity = tonumber(raw.quantity) or tonumber(raw.stackSize) or 0
	if quantity <= 0 then
		return nil
	end
	local rowType = raw.type
	if rowType and rowType ~= "buy" and rowType ~= "Buy" then
		return nil
	end
	local buy = {
		itemString = itemString,
		quantity = quantity,
		price = tonumber(raw.price) or tonumber(raw.copper) or 0,
		time = tonumber(raw.time) or 0,
		source = raw.source or raw.key or "Unknown",
		seller = raw.seller or raw.otherPlayer or "",
		player = raw.player or "",
	}
	buy.acctKey = Accounting.MakeAcctKey(buy)
	return buy
end

local function splitCsvLine(line)
	local fields = {}
	for field in (line .. ","):gmatch("([^,]*),") do
		fields[#fields + 1] = field
	end
	return fields
end

--- Parse a TSM Accounting csvBuys string into buy records.
function Accounting.ParseCsvBuys(csv)
	local results = {}
	if type(csv) ~= "string" or csv == "" or not csv:find(CSV_HEADER_MARK, 1, true) then
		return results
	end

	local lines = { strsplit("\n", csv) }
	if #lines < 2 then
		return results
	end

	local header = splitCsvLine(lines[1])
	local index = {}
	for i, name in ipairs(header) do
		index[trim(name)] = i
	end

	local function field(fields, name)
		local i = index[name]
		return i and fields[i] or nil
	end

	for i = 2, #lines do
		local line = lines[i]
		if line and line ~= "" then
			local fields = splitCsvLine(line)
			local buy = normalizeBuy({
				itemString = field(fields, "itemString"),
				stackSize = field(fields, "stackSize"),
				quantity = field(fields, "quantity"),
				price = field(fields, "price"),
				otherPlayer = field(fields, "otherPlayer") or field(fields, "seller"),
				seller = field(fields, "seller"),
				player = field(fields, "player"),
				time = field(fields, "time"),
				source = field(fields, "source"),
			})
			if buy then
				results[#results + 1] = buy
			end
		end
	end
	return results
end

local function collectFromCsvSettings(results)
	local sv = _G.TradeSkillMasterDB
	if type(sv) ~= "table" then
		return false
	end

	local found = false
	for key, value in pairs(sv) do
		if type(value) == "string" and type(key) == "string" then
			local isCsvBuysKey = key:find("csvBuys", 1, true)
				and not key:find("saveTime", 1, true)
			if isCsvBuysKey and value:find(CSV_HEADER_MARK, 1, true) then
				for _, buy in ipairs(Accounting.ParseCsvBuys(value)) do
					results[#results + 1] = buy
					found = true
				end
			end
		elseif type(value) == "table" then
			local function walk(node, depth)
				if depth > 5 or type(node) ~= "table" then
					return
				end
				for k, v in pairs(node) do
					if k == "csvBuys" and type(v) == "string" and v:find(CSV_HEADER_MARK, 1, true) then
						for _, buy in ipairs(Accounting.ParseCsvBuys(v)) do
							results[#results + 1] = buy
							found = true
						end
					elseif type(v) == "table" then
						walk(v, depth + 1)
					end
				end
			end
			walk(value, 0)
		end
	end
	return found
end

local function finalizeBuys(results)
	local seen = {}
	local unique = {}
	for _, buy in ipairs(results) do
		if not seen[buy.acctKey] then
			seen[buy.acctKey] = true
			unique[#unique + 1] = buy
		end
	end
	table.sort(unique, function(a, b)
		local at, bt = a.time or 0, b.time or 0
		if at ~= bt then
			return at > bt
		end
		local ak, bk = tostring(a.acctKey or ""), tostring(b.acctKey or "")
		if ak ~= bk then
			return ak < bk
		end
		return tostring(a.itemString or "") < tostring(b.itemString or "")
	end)
	return unique
end

function Accounting.GetLastError()
	return lastError
end

function Accounting.GetSource()
	return lastSource
end

function Accounting.GetRuntimeError()
	return runtimeError
end

function Accounting.GetRuntimeStatus()
	local bridge = _G.TSMIT_TSMBridge
	if type(bridge) == "table" and type(bridge.FlushAccountingToSV) == "function" then
		return "TSM bridge ready (logout-style flush)"
	end
	return "TSM bridge missing: " .. tostring(runtimeError or "TSMIT_TSMBridge not loaded")
end

--- List from TradeSkillMasterDB csvBuys (same data available after /reload).
--- @return table buys, boolean ok, string? err
function Accounting.GetBuys()
	lastError = nil
	lastSource = nil
	runtimeError = nil
	local results = {}

	collectFromCsvSettings(results)

	if #results == 0 then
		if type(_G.TradeSkillMasterDB) ~= "table" then
			lastError = "TradeSkillMasterDB not loaded. Ensure TradeSkillMaster is enabled."
		else
			lastError = "No saved purchases found. Buy something with TSM loaded, then click Refresh (or /reload) to save Accounting data."
		end
		return results, false, lastError
	end

	lastSource = "saved"
	return finalizeBuys(results), true, nil
end

--- Refresh button: flush live TSM Transactions into csvBuys (same as logout//reload), then read SV.
--- @return table buys, boolean ok, string? err
function Accounting.FetchLatestBuys()
	lastError = nil
	lastSource = nil
	runtimeError = nil

	local bridge = _G.TSMIT_TSMBridge
	if type(bridge) ~= "table" or type(bridge.FlushAccountingToSV) ~= "function" then
		runtimeError = "TSMIT_TSMBridge not loaded inside TradeSkillMaster"
		lastError = "Refresh needs the TSM bridge. Re-sync the addon, then /reload."
		-- Still show whatever is already saved.
		local buys, ok = Accounting.GetBuys()
		if ok then
			lastSource = "saved"
			return buys, true, nil
		end
		return {}, false, lastError
	end

	local ok, err = pcall(bridge.FlushAccountingToSV)
	if not ok then
		runtimeError = tostring(err)
		lastError = "TSM Accounting flush failed: " .. tostring(err)
		local buys, getOk = Accounting.GetBuys()
		if getOk then
			lastSource = "saved"
			return buys, true, nil
		end
		return {}, false, lastError
	end

	local buys, getOk, getErr = Accounting.GetBuys()
	if getOk then
		lastSource = "flushed"
	end
	return buys, getOk, getErr
end

function Accounting.FilterBuys(buys, searchText, hideMarked, isMarkedFn)
	local filtered = {}
	local needle = trim(searchText):lower()
	for _, buy in ipairs(buys) do
		local marked = isMarkedFn and isMarkedFn(buy.acctKey)
		if not (hideMarked and marked) then
			if needle == "" then
				filtered[#filtered + 1] = buy
			else
				local name = ns.addon:GetItemName(buy.itemString):lower()
				local hay = (name .. " " .. (buy.seller or "") .. " " .. (buy.source or "") .. " " .. (buy.player or "")):lower()
				if hay:find(needle, 1, true) then
					filtered[#filtered + 1] = buy
				end
			end
		end
	end
	return filtered
end
