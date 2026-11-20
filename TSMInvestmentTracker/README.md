# TSM Investment Tracker

WoW: Forever addon that marks TradeSkillMaster Accounting purchases as **investments** and shows a stock-style **Portfolio Overview**.

## Requirements

- **WoW: Forever** (Interface `16001`)
- [TradeSkillMaster](https://www.tradeskillmaster.com/) Forever build (with Accounting purchase history)

## Install

1. Run `sync-to-forever.ps1` from the repo (copies this folder and installs `TSMIT_TSMBridge.lua` into TradeSkillMaster), or install manually and patch TradeSkillMaster.toc to load the bridge.
2. `/reload` (or restart the client).
3. Confirm **TSM Investment Tracker** and TSM are enabled.
4. In game: `/tsminv`

## Usage

### Mark Investments

1. Open `/tsminv` → **Mark Investments**.
2. Browse purchases from TSM Accounting (same data as the Ledger).
3. Click **Mark** on buys you want to track as investments.
4. Use search / “Hide already marked” to filter. **Unmark** removes a lot.

Marked quantity is the portfolio position — physical bags/bank/AH are ignored.

Marks and the portfolio are **account-wide** (shared across all characters). Mark Investments lists TSM purchases from every character that has Accounting data on this account.

### Portfolio Overview

Shows one row per item:

| Column | Meaning |
| --- | --- |
| Qty | Sum of marked lot quantities |
| Avg Cost | Weighted average buy price of marked lots |
| Market | TSM MarketValue (`DBMarket`) |
| Cost Basis | Qty × prices of marked lots |
| Mkt Value | Market × qty |
| Unrealized | Market value − cost basis |
| % | Unrealized / cost basis |

**Remove** clears all lots for that item (closes the position in the tracker).

## Slash commands

- `/tsminv` — toggle the window
- `/tsminvestment` — same
- `/tsminv help` — help text

## Notes

- Market prices need the TSM Desktop App syncing AuctionDB data.
- Selling items in-game does **not** auto-reduce lots; unmark or Remove when you close a position.
- Mark Investments reads TSM's saved Accounting `csvBuys` (same data you get after `/reload`, because reload runs TSM's logout save). **Refresh** runs that same flush via a small bridge file loaded inside TradeSkillMaster (`TSMIT_TSMBridge.lua`), then re-reads `csvBuys` — no `/reload` needed.
