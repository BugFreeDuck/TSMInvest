# Changelog

## 1.0.0

- Initial release for **WoW: Forever** (Interface 16001).
- Mark TSM Accounting purchases as investments (account-wide lots).
- Portfolio Overview: qty, avg cost, DBMarket, cost basis, market value, unrealized P/L.
- Expand portfolio rows to view/unmark individual lots.
- Minimap button; resizable window; stable portfolio sort (mark order by default).
- Mark Investments **Refresh** flushes TSM Accounting into `csvBuys` via `TSMIT_TSMBridge` (same path as `/reload`), then reloads the list.
