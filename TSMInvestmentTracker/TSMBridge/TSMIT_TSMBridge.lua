--[[
	TSM Investment Tracker bridge — must be loaded by TradeSkillMaster.

	Installed into Interface\AddOns\TradeSkillMaster\ and listed at the end of
	TradeSkillMaster.toc. Exposes the same Accounting flush TSM runs on logout
	(/reload), so Mark Investments → Refresh can update TradeSkillMasterDB
	csvBuys without a reload.
]]

local _, TSM = ...

local Bridge = {}
_G.TSMIT_TSMBridge = Bridge

--- Mirror Accounting logout: export live Transactions into realm csvBuys/csvSales.
function Bridge.FlushAccountingToSV()
	local Transactions = TSM.LibTSMService:Include("Ledger.Transactions")
	local AddonSettings = TSM.LibTSMApp:Include("Service.AddonSettings")
	local db = AddonSettings.GetDB()

	local csvSales, saveTimeSales, trimmedSales, csvBuys, saveTimeBuys, trimmedBuys = Transactions.SaveData()
	db:Set("realm", nil, "internalData", "csvSales", csvSales)
	db:Set("realm", nil, "internalData", "saveTimeSales", saveTimeSales)
	db:Set("realm", nil, "internalData", "csvBuys", csvBuys)
	db:Set("realm", nil, "internalData", "saveTimeBuys", saveTimeBuys)

	local trimmed = db:Get("realm", nil, "internalData", "accountingTrimmed")
	if type(trimmed) ~= "table" then
		trimmed = {}
	end
	trimmed.sales = trimmedSales
	trimmed.buys = trimmedBuys
	db:Set("realm", nil, "internalData", "accountingTrimmed", trimmed)

	return true
end
