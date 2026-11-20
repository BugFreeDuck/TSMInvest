# Sync TSM Investment Tracker + TSM bridge into Forever AddOns.
$ErrorActionPreference = "Stop"
$src = Join-Path $PSScriptRoot "TSMInvestmentTracker"
$foreverAddOns = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
$dst = Join-Path $foreverAddOns "TSMInvestmentTracker"
$tsm = Join-Path $foreverAddOns "TradeSkillMaster"

New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Force -Recurse "$src\*" $dst -Exclude "TSMBridge"

# Bridge must load inside TradeSkillMaster (same private package as TSM).
Copy-Item -Force (Join-Path $src "TSMBridge\TSMIT_TSMBridge.lua") (Join-Path $tsm "TSMIT_TSMBridge.lua")
$toc = Join-Path $tsm "TradeSkillMaster.toc"
$tocText = Get-Content -Raw $toc
if ($tocText -notmatch "TSMIT_TSMBridge\.lua") {
	if (-not $tocText.EndsWith("`n")) { $tocText += "`r`n" }
	$tocText += "`r`n# TSM Investment Tracker bridge (logout-style Accounting flush)`r`nTSMIT_TSMBridge.lua`r`n"
	Set-Content -Path $toc -Value $tocText -NoNewline
	Write-Host "Patched TradeSkillMaster.toc"
}
Write-Host "Synced to $dst and TSM bridge."
