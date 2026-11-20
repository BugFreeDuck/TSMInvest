--[[
	Investment lot storage: mark / unmark Accounting buys, query by acctKey / item.
]]

local _, ns = ...
local Lots = {}
ns.Lots = Lots

local function db()
	-- Account-wide store so marks/portfolio are shared across all characters.
	return ns.addon.db.global
end

function Lots.GetAll()
	return db().lots
end

function Lots.FindByAcctKey(acctKey)
	if not acctKey then
		return nil, nil
	end
	for lotId, lot in pairs(db().lots) do
		if lot.acctKey == acctKey then
			return lotId, lot
		end
	end
	return nil, nil
end

function Lots.IsMarked(acctKey)
	local lotId = Lots.FindByAcctKey(acctKey)
	return lotId ~= nil
end

--- Mark a normalized Accounting buy as an investment lot.
-- @return ok, lotIdOrErr
function Lots.Mark(buy)
	if not buy or not buy.itemString then
		return false, "invalid buy"
	end
	local acctKey = buy.acctKey or ns.Accounting.MakeAcctKey(buy)
	local existingId = Lots.FindByAcctKey(acctKey)
	if existingId then
		return false, "already marked"
	end

	local store = db()
	local lotId = tostring(store.nextLotId)
	store.nextLotId = store.nextLotId + 1
	store.lots[lotId] = {
		itemString = buy.itemString,
		quantity = tonumber(buy.quantity) or 0,
		price = tonumber(buy.price) or 0,
		time = tonumber(buy.time) or 0,
		source = buy.source or "Unknown",
		seller = buy.seller or "",
		player = buy.player or "",
		acctKey = acctKey,
	}
	return true, lotId
end

function Lots.UnmarkByAcctKey(acctKey)
	local lotId = Lots.FindByAcctKey(acctKey)
	if not lotId then
		return false
	end
	db().lots[lotId] = nil
	return true
end

function Lots.Remove(lotId)
	if not lotId or not db().lots[lotId] then
		return false
	end
	db().lots[lotId] = nil
	return true
end

function Lots.RemoveByItem(itemString)
	if not itemString then
		return 0
	end
	local removed = 0
	local store = db().lots
	for lotId, lot in pairs(store) do
		if lot.itemString == itemString then
			store[lotId] = nil
			removed = removed + 1
		end
	end
	return removed
end

function Lots.GetByItem(itemString)
	local list = {}
	for lotId, lot in pairs(db().lots) do
		if lot.itemString == itemString then
			list[#list + 1] = { id = lotId, lot = lot }
		end
	end
	table.sort(list, function(a, b)
		local at, bt = a.lot.time or 0, b.lot.time or 0
		if at ~= bt then
			return at > bt
		end
		local aid, bid = tonumber(a.id) or 0, tonumber(b.id) or 0
		if aid ~= bid then
			return aid < bid
		end
		return tostring(a.id) < tostring(b.id)
	end)
	return list
end
