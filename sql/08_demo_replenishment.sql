-- =====================================================================
--  Inventory and Order Management System
--  08 - Demo: low-stock detection, replenishment, automatic tiers
--  Run ONCE after 07.
-- =====================================================================

USE inventory_db;

-- =====================================================================
-- SECTION 8: DEMONSTRATION - REPLENISHMENT SYSTEM
-- =====================================================================

-- 8.1 Identify low-stock products (expect 4)
SELECT * FROM vw_low_stock;

-- 8.2 Manual restock: a supplier delivery of 30 water bottles
CALL sp_restock_product(10, 30, 'Supplier delivery #1001');

-- 8.3 Automatic replenishment of everything still low
CALL sp_replenish_low_stock(2);

-- 8.4 Nothing left to reorder
SELECT * FROM vw_low_stock;

-- 8.5 Automatic tier upgrades: Kevin goes Bronze -> Silver -> Gold
--     Kevin's tier is recorded after each step, so the whole
--     progression appears in ONE result table at the end.
DROP TEMPORARY TABLE IF EXISTS tier_history;
CREATE TEMPORARY TABLE tier_history (
    step        INT,
    event       VARCHAR(60),
    total_spent DECIMAL(12,2),
    tier        VARCHAR(10)
);

INSERT INTO tier_history
SELECT 1, 'Before any order', total_spent, tier
  FROM vw_customer_spending WHERE customer_id = 6;

CALL sp_place_order(6, '[{"product_id":8,"quantity":7}]', @o);

INSERT INTO tier_history
SELECT 2, 'After order: 7 office chairs', total_spent, tier
  FROM vw_customer_spending WHERE customer_id = 6;

CALL sp_place_order(6, '[{"product_id":3,"quantity":15},{"product_id":4,"quantity":2}]', @o);

INSERT INTO tier_history
SELECT 3, 'After order: 15 headphones + 2 laptop stands', total_spent, tier
  FROM vw_customer_spending WHERE customer_id = 6;

SELECT * FROM tier_history ORDER BY step;

-- 8.6 Kevin's orders pushed stock low again -> replenish again
SELECT * FROM vw_low_stock;
CALL sp_replenish_low_stock(2);
SELECT * FROM vw_low_stock;

-- 8.7 Full audit trail for one product (sell -> low -> restock cycle)
SELECT * FROM vw_inventory_history
 WHERE product_name = 'Office Chair'
 ORDER BY log_id;
