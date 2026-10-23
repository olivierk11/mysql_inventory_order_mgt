-- =====================================================================
--  Inventory and Order Management System
--  07 - Demo: order placement, stock updates, inventory tracking
--  Run ONCE after 06.
-- =====================================================================

USE inventory_db;

-- =====================================================================
-- SECTION 7: DEMONSTRATION - ORDER PLACEMENT AND STOCK UPDATES
-- =====================================================================

-- Aline: 2 mice + 12 notebooks (5% off)              -> 135.50
CALL sp_place_order(1, '[{"product_id":1,"quantity":2},{"product_id":6,"quantity":12}]', @o);
-- Grace: 60 boxes of pens (15% off)                  -> 216.75
CALL sp_place_order(3, '[{"product_id":7,"quantity":60}]', @o);
-- Patrick: 8 office chairs + 5 desk lamps            -> 1349.95
CALL sp_place_order(4, '[{"product_id":8,"quantity":8},{"product_id":9,"quantity":5}]', @o);
-- Diane: 6 chairs + 25 stands (10% off) + 4 headphones -> 1947.50
CALL sp_place_order(5, '[{"product_id":8,"quantity":6},{"product_id":4,"quantity":25},{"product_id":3,"quantity":4}]', @o);
-- Diane: 20 USB-C chargers (10% off)                 -> 333.00
CALL sp_place_order(5, '[{"product_id":2,"quantity":20}]', @o);
-- Eric: 10 mice (5% off)                             -> 237.50
CALL sp_place_order(2, '[{"product_id":1,"quantity":10}]', @o);
-- Aline: 3 mechanical keyboards                      -> 269.97
CALL sp_place_order(1, '[{"product_id":5,"quantity":3}]', @o);

-- Order lines with prices and discounts
SELECT od.order_id, p.product_name, od.quantity, od.unit_price,
       od.discount_pct, od.line_total
  FROM Order_Details od
  JOIN Products p ON p.product_id = od.product_id
 ORDER BY od.order_id, od.order_detail_id;

-- Stock levels after the orders
SELECT product_id, product_name, stock_quantity, reorder_level, is_low_stock
  FROM Products;

-- Inventory tracking: every stock change caused by orders
SELECT * FROM vw_inventory_history
 WHERE change_type = 'ORDER'
 ORDER BY log_id;
