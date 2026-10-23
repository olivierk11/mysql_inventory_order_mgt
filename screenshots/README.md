# Screenshots

Run `sql/00_full_build.sql` in MySQL Workbench, then save these screenshots in this folder **using exactly these file names**, because REPORT.md links to them.

| File name | What to capture |
|---|---|
| `01_schema.png` | Schemas panel expanded: 5 tables, 4 views, stored procedures, functions |
| `02_order_details.png` | Result of the order lines query in Section 7 (prices and discounts) |
| `03_low_stock_before.png` | `SELECT * FROM vw_low_stock;` before replenishment (4 rows) |
| `04_replenishment.png` | Result of `CALL sp_replenish_low_stock(2);` (units added per product) |
| `05_tier_upgrade.png` | `tier_history` table: Kevin's tier Bronze → Silver → Gold |
| `06_audit_trail.png` | `vw_inventory_history` for Office Chair (Section 8.7) |
| `07_order_summary.png` | `SELECT * FROM vw_order_summary;` |
| `08_customer_spending.png` | `SELECT * FROM vw_customer_spending;` |
| `09_discounts.png` | Bulk discount report (Section 9.5) |
| `10_explain.png` | `EXPLAIN` results showing the `key` column (Section 9.8) |
| `11_error_stock.png` | Output panel with the "Insufficient stock" error from `sql/10_error_tests.sql` |


