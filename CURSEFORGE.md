# Publishing on CurseForge

Packaging files in this repo are ready. Creating the CurseForge project and uploading still need your account.

## One-time: create the project

1. Sign in at [console.curseforge.com](https://console.curseforge.com).
2. **Create Project** → game **World of Warcraft**.
3. Title: **TSM Investment Tracker**.
4. Paste description from `README.md` (screenshot: `assets/portfolio-overview.png`).
5. License: **MIT**.
6. Categories: e.g. Auction House / Economy (as available).
7. After creation, note the numeric **Project ID**.

Optional: add to `TSMInvestmentTracker.toc`:

```toc
## X-Curse-Project-ID: YOUR_ID_HERE
```

## Build the upload zip

From the repo root:

```powershell
.\package-release.ps1
```

Output: `dist\TSMInvestmentTracker-1.0.0.zip`  
Zip root must be `TSMInvestmentTracker\` (CurseForge / Twitch client expectation).

## Upload

1. Project → **Files** → **Upload**.
2. Select the zip from `dist\`.
3. Changelog: contents of `CHANGELOG.md` for this version.
4. Game versions: pick the closest Classic / era options CurseForge offers, and state clearly in the description that this targets **WoW: Forever** (`Interface 16001`).
5. Mark as Release.

## Forever + TSM bridge (required for Refresh)

CurseForge only installs `Interface\AddOns\TSMInvestmentTracker\`.  
**Refresh** (new buys without `/reload`) needs `TSMIT_TSMBridge.lua` loaded by TradeSkillMaster:

1. Copy `TSMInvestmentTracker\TSMBridge\TSMIT_TSMBridge.lua` → `Interface\AddOns\TradeSkillMaster\TSMIT_TSMBridge.lua`
2. Append to `TradeSkillMaster.toc`:

   ```toc
   # TSM Investment Tracker bridge
   TSMIT_TSMBridge.lua
   ```

3. `/reload`

Or run `sync-to-forever.ps1` on a Forever install. TSM updates can wipe the toc line — re-run sync after updating TSM.

Without the bridge, the addon still works; Mark Investments uses last-saved Accounting data (same as after a normal `/reload`/logout).

## GitHub + automated packages (optional)

1. Push this repo to GitHub.
2. Add CurseForge API token + project ID as secrets.
3. Use [BigWigs packager](https://github.com/BigWigsMods/packager) on version tags (`v1.0.0`) with this `.pkgmeta`.
