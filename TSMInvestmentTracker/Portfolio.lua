--[[
	Aggregates investment lots into portfolio rows and totals.
]]

local _, ns = ...
local Portfolio = {}
ns.Portfolio = Portfolio

local function getMarketPrice(itemString)
	if not TSM_API or not TSM_API.GetCustomPriceValue then
		return nil
	end
	local source = ns.addon:GetMarketPriceSource()
	local ok, value = pcall(TSM_API.GetCustomPriceValue, source, itemString)
	if ok and type(value) == "number" and value > 0 then
		return value
	end
	return nil
end

--- Stable compare: primary values, then deterministic tie-breakers.
local function stableLess(av, bv, ascending, aKey, bKey)
	if av ~= bv then
		if av == nil then
			return not ascending
		end
		if bv == nil then
			return ascending
		end
		if ascending then
			return av < bv
		end
		return av > bv
	end
	-- Tie-break: itemString, then firstLotId (mark order).
	if aKey ~= bKey then
		return tostring(aKey) < tostring(bKey)
	end
	return false
end

--- Build aggregated portfolio rows from marked lots only.
-- @return rows, totals
function Portfolio.Build()
	local byItem = {}

	for lotId, lot in pairs(ns.Lots.GetAll()) do
		local key = lot.itemString
		local row = byItem[key]
		local numericId = tonumber(lotId) or math.huge
		if not row then
			row = {
				itemString = key,
				quantity = 0,
				costBasis = 0,
				firstLotId = numericId,
			}
			byItem[key] = row
		elseif numericId < row.firstLotId then
			row.firstLotId = numericId
		end
		local qty = tonumber(lot.quantity) or 0
		local price = tonumber(lot.price) or 0
		row.quantity = row.quantity + qty
		row.costBasis = row.costBasis + (qty * price)
	end

	local rows = {}
	local totals = {
		costBasis = 0,
		marketValue = 0,
		unrealized = 0,
		quantity = 0,
		pricedCostBasis = 0,
	}

	for _, row in pairs(byItem) do
		if row.quantity > 0 then
			row.avgCost = row.costBasis / row.quantity
			row.market = getMarketPrice(row.itemString)
			if row.market then
				row.marketValue = row.market * row.quantity
				row.unrealized = row.marketValue - row.costBasis
				if row.costBasis > 0 then
					row.unrealizedPct = (row.unrealized / row.costBasis) * 100
				else
					row.unrealizedPct = nil
				end
				totals.marketValue = totals.marketValue + row.marketValue
				totals.unrealized = totals.unrealized + row.unrealized
				totals.pricedCostBasis = totals.pricedCostBasis + row.costBasis
			else
				row.marketValue = nil
				row.unrealized = nil
				row.unrealizedPct = nil
			end
			totals.costBasis = totals.costBasis + row.costBasis
			totals.quantity = totals.quantity + row.quantity
			rows[#rows + 1] = row
		end
	end

	-- Default: mark order (first lot id). Caller may re-sort via SortRows.
	Portfolio.SortRows(rows, "marked", true)

	return rows, totals
end

function Portfolio.SortRows(rows, key, ascending)
	table.sort(rows, function(a, b)
		local av, bv
		if key == "marked" then
			av, bv = a.firstLotId or math.huge, b.firstLotId or math.huge
		elseif key == "name" then
			av = ns.addon:GetItemName(a.itemString):lower()
			bv = ns.addon:GetItemName(b.itemString):lower()
		else
			av, bv = a[key], b[key]
		end
		return stableLess(av, bv, ascending, a.itemString, b.itemString)
	end)
end
