-- =====================================================================
--  Inventory and Order Management System
--  10 - Error-handling tests (each statement should FAIL)
--  Run one statement at a time, after 08.
-- =====================================================================

USE inventory_db;

-- =====================================================================
-- SECTION 10: ERROR-HANDLING TESTS
-- Each statement below SHOULD fail with a clear error message.
-- Run them ONE AT A TIME (Workbench: cursor on the line, Ctrl + Enter).
-- =====================================================================

-- Not enough stock: nothing is saved, not even the laptop stand
CALL sp_place_order(2, '[{"product_id":4,"quantity":1},{"product_id":5,"quantity":500}]', @o);

-- Customer does not exist
CALL sp_place_order(999, '[{"product_id":1,"quantity":1}]', @o);

-- Empty order
CALL sp_place_order(1, '[]', @o);

-- Invalid restock quantity
CALL sp_restock_product(1, -5, 'Bad quantity');

-- Product does not exist
CALL sp_restock_product(999, 10, 'Unknown product');

-- Negative price rejected by CHECK constraint
INSERT INTO Products (product_name, category, price) VALUES ('Bad', 'Test', -5);

-- Duplicate email rejected by UNIQUE constraint
INSERT INTO Customers (first_name, last_name, email) VALUES ('X', 'Y', 'aline.uwase@example.com');

-- After the tests, prove the failed order saved nothing:
SELECT COUNT(*) AS total_orders FROM Orders;                -- still 9
SELECT stock_quantity FROM Products WHERE product_id = 4;   -- still 13
