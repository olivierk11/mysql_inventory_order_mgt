-- =====================================================================
--  Inventory and Order Management System
--  09 - Report summaries and index usage (EXPLAIN)
--  Read-only. Safe to run any time.
-- =====================================================================

USE inventory_db;

-- =====================================================================
-- SECTION 9: REPORT SUMMARIES
-- =====================================================================

-- 9.1 Order summary (one row per order)
SELECT * FROM vw_order_summary ORDER BY order_id;

-- 9.2 Order summary per customer
SELECT customer_name,
       COUNT(*)          AS total_orders,
       SUM(total_items)  AS total_items,
       SUM(total_amount) AS total_spent
  FROM vw_order_summary
 GROUP BY customer_id, customer_name
 ORDER BY total_spent DESC;

-- 9.3 Customer spending report with tiers
SELECT * FROM vw_customer_spending ORDER BY total_spent DESC;

-- 9.4 Tier summary
SELECT tier,
       COUNT(*)         AS customers,
       SUM(total_spent) AS tier_revenue
  FROM vw_customer_spending
 GROUP BY tier
 ORDER BY FIELD(tier, 'Gold', 'Silver', 'Bronze');

-- 9.5 Bulk discount report
SELECT od.order_id,
       CONCAT(c.first_name, ' ', c.last_name)       AS customer_name,
       p.product_name,
       od.quantity,
       od.discount_pct,
       od.quantity * od.unit_price                   AS price_before_discount,
       od.line_total                                 AS price_after_discount,
       (od.quantity * od.unit_price) - od.line_total AS customer_saved
  FROM Order_Details od
  JOIN Orders    o ON o.order_id    = od.order_id
  JOIN Customers c ON c.customer_id = o.customer_id
  JOIN Products  p ON p.product_id  = od.product_id
 WHERE od.discount_pct > 0
 ORDER BY customer_saved DESC;

-- 9.6 Stock status for all products
SELECT product_name, stock_quantity, reorder_level,
       CASE
           WHEN stock_quantity = 0                   THEN 'OUT OF STOCK'
           WHEN stock_quantity < reorder_level       THEN 'LOW - REORDER'
           WHEN stock_quantity < reorder_level * 1.5 THEN 'WATCH'
           ELSE 'OK'
       END AS stock_status
  FROM Products
 ORDER BY stock_quantity / reorder_level;

-- 9.7 Best-selling products
SELECT p.product_name, p.category,
       SUM(od.quantity)   AS units_sold,
       SUM(od.line_total) AS revenue
  FROM Order_Details od
  JOIN Products p ON p.product_id = od.product_id
 GROUP BY p.product_id, p.product_name, p.category
 ORDER BY revenue DESC;

-- 9.8 Proof that indexes are used (look at the "key" column)
EXPLAIN SELECT * FROM Inventory_Logs WHERE product_id = 8 ORDER BY change_date;
EXPLAIN SELECT order_id, order_date, total_amount
          FROM Orders WHERE customer_id = 5 ORDER BY order_date DESC;
