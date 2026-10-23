-- =====================================================================
--  Inventory and Order Management System
--  05 - Views: order summary, low stock, customer spending, audit trail
--  Requires 01. Safe to re-run.
-- =====================================================================

USE inventory_db;

-- =====================================================================
-- SECTION 5: VIEWS
-- =====================================================================

-- 5.1 REQUIRED: order summary
CREATE OR REPLACE VIEW vw_order_summary AS
SELECT
    o.order_id,
    o.customer_id,
    CONCAT(c.first_name, ' ', c.last_name)  AS customer_name,
    c.tier                                  AS customer_tier,
    o.order_date,
    COUNT(od.order_detail_id)               AS different_products,
    COALESCE(SUM(od.quantity), 0)           AS total_items,
    o.total_amount
FROM Orders o
JOIN Customers          c  ON c.customer_id = o.customer_id
LEFT JOIN Order_Details od ON od.order_id   = o.order_id
GROUP BY o.order_id, o.customer_id, c.first_name, c.last_name,
         c.tier, o.order_date, o.total_amount;

-- 5.2 REQUIRED: low stock / products to reorder
CREATE OR REPLACE VIEW vw_low_stock AS
SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.stock_quantity,
    p.reorder_level,
    p.reorder_level - p.stock_quantity        AS units_below_reorder,
    (p.reorder_level * 2) - p.stock_quantity  AS suggested_order_qty,
    CASE WHEN p.stock_quantity = 0
         THEN 'OUT OF STOCK' ELSE 'LOW' END   AS stock_status,
    (SELECT MAX(l.change_date)
       FROM Inventory_Logs l
      WHERE l.product_id = p.product_id
        AND l.change_type = 'RESTOCK')        AS last_restocked
FROM Products p
WHERE p.is_low_stock = 1;

-- 5.3 Customer spending and tiers
CREATE OR REPLACE VIEW vw_customer_spending AS
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name)     AS customer_name,
    c.email,
    c.tier,
    COUNT(o.order_id)                          AS total_orders,
    COALESCE(SUM(o.total_amount), 0)           AS total_spent,
    COALESCE(ROUND(AVG(o.total_amount), 2), 0) AS avg_order_value,
    MAX(o.order_date)                          AS last_order_date
FROM Customers c
LEFT JOIN Orders o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.email, c.tier;

-- 5.4 Readable inventory audit trail
CREATE OR REPLACE VIEW vw_inventory_history AS
SELECT
    l.log_id,
    l.change_date,
    p.product_name,
    l.change_type,
    l.quantity_change,
    l.stock_before,
    l.stock_after,
    l.reference_id AS order_id,
    l.notes
FROM Inventory_Logs l
JOIN Products p ON p.product_id = l.product_id;
