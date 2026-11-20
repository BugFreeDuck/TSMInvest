# Build a CurseForge-ready zip: dist/TSMInvestmentTracker-<version>.zip
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$addon = Join-Path $root "TSMInvestmentTracker"
$toc = Join-Path $addon "TSMInvestmentTracker.toc"
$dist = Join-Path $root "dist"

if (-not (Test-Path $toc)) {
	throw "Missing $toc"
}

$version = "1.0.0"
foreach ($line in Get-Content $toc) {
	if ($line -match '^##\s*Version:\s*(.+)$') {
		$version = $Matches[1].Trim()
		break
	}
}

$stage = Join-Path $dist "_stage"
$stageAddon = Join-Path $stage "TSMInvestmentTracker"
if (Test-Path $stage) {
	Remove-Item -Recurse -Force $stage
}
New-Item -ItemType Directory -Force -Path $stageAddon | Out-Null

# Copy addon; keep TSMBridge inside the zip so CF users can install it manually.
$excludeDirs = @()
Get-ChildItem -Force $addon | ForEach-Object {
	$dest = Join-Path $stageAddon $_.Name
	if ($_.PSIsContainer) {
		Copy-Item -Recurse -Force $_.FullName $dest
	} else {
		Copy-Item -Force $_.FullName $dest
	}
}

Copy-Item -Force (Join-Path $root "LICENSE") (Join-Path $stageAddon "LICENSE")
Copy-Item -Force (Join-Path $root "CHANGELOG.md") (Join-Path $stageAddon "CHANGELOG.md")

$bridgeReadme = @"
# TSM bridge (WoW: Forever)

For Mark Investments → Refresh without /reload:

1. Copy TSMIT_TSMBridge.lua into Interface\AddOns\TradeSkillMaster\
2. Add this line at the end of TradeSkillMaster.toc:

   TSMIT_TSMBridge.lua

3. /reload

TSM updates may remove the toc line; add it again after updating TSM.
"@
Set-Content -Path (Join-Path $stageAddon "TSMBridge\INSTALL.txt") -Value $bridgeReadme -Encoding UTF8

$zipName = "TSMInvestmentTracker-$version.zip"
$zipPath = Join-Path $dist $zipName
if (Test-Path $zipPath) {
	Remove-Item -Force $zipPath
}

Compress-Archive -Path $stageAddon -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item -Recurse -Force $stage

Write-Host "Created $zipPath"
Write-Host "Upload this file on CurseForge (Files → Upload)."
