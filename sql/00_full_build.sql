-- =====================================================================
--  INVENTORY AND ORDER MANAGEMENT SYSTEM
--  00 - FULL BUILD: everything in one file (MySQL 8.0.16+)
--  Equivalent to running 01_schema.sql ... 09_reports.sql in order.
--
--  Runs from top to bottom in one go and rebuilds everything:
--    Section 1  Database schema (tables, keys, constraints, indexes)
--    Section 2  Functions
--    Section 3  Stored procedures
--    Section 4  Triggers (automation)
--    Section 5  Views
--    Section 6  Sample data
--    Section 7  Demonstration: order placement and stock updates
--    Section 8  Demonstration: replenishment system
--    Section 9  Report summaries
--    Section 10 Error-handling tests (run manually)
-- =====================================================================

DROP DATABASE IF EXISTS inventory_db;
CREATE DATABASE inventory_db;
USE inventory_db;


-- =====================================================================
-- SECTION 1: DATABASE SCHEMA
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1.1 Products
-- is_low_stock is maintained automatically by MySQL and indexed,
-- so low-stock lookups stay fast as the catalogue grows.
-- ---------------------------------------------------------------------
CREATE TABLE Products (
    product_id      INT AUTO_INCREMENT PRIMARY KEY,
    product_name    VARCHAR(100)   NOT NULL,
    category        VARCHAR(50)    NOT NULL,
    price           DECIMAL(10,2)  NOT NULL,
    stock_quantity  INT            NOT NULL DEFAULT 0,
    reorder_level   INT            NOT NULL DEFAULT 10,
    is_low_stock    TINYINT AS (stock_quantity < reorder_level) STORED,
    CONSTRAINT chk_price         CHECK (price >= 0),
    CONSTRAINT chk_stock         CHECK (stock_quantity >= 0),
    CONSTRAINT chk_reorder_level CHECK (reorder_level >= 0),
    INDEX idx_products_category  (category),
    INDEX idx_products_low_stock (is_low_stock)
);

-- ---------------------------------------------------------------------
-- 1.2 Customers
-- ---------------------------------------------------------------------
CREATE TABLE Customers (
    customer_id   INT AUTO_INCREMENT PRIMARY KEY,
    first_name    VARCHAR(50)  NOT NULL,
    last_name     VARCHAR(50)  NOT NULL,
    email         VARCHAR(100) NOT NULL UNIQUE,
    phone         VARCHAR(20),
    tier          ENUM('Bronze','Silver','Gold') NOT NULL DEFAULT 'Bronze',
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 1.3 Orders
-- ---------------------------------------------------------------------
CREATE TABLE Orders (
    order_id      INT AUTO_INCREMENT PRIMARY KEY,
    customer_id   INT           NOT NULL,
    order_date    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_amount  DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT chk_total CHECK (total_amount >= 0),
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES Customers(customer_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    INDEX idx_orders_customer_date (customer_id, order_date),
    INDEX idx_orders_date          (order_date)
);

-- ---------------------------------------------------------------------
-- 1.4 Order_Details (one row per product in an order)
-- unit_price, discount_pct and line_total are filled in by a trigger.
-- ---------------------------------------------------------------------
CREATE TABLE Order_Details (
    order_detail_id  INT AUTO_INCREMENT PRIMARY KEY,
    order_id         INT           NOT NULL,
    product_id       INT           NOT NULL,
    quantity         INT           NOT NULL,
    unit_price       DECIMAL(10,2) NOT NULL DEFAULT 0.00,  -- price at time of sale
    discount_pct     DECIMAL(5,2)  NOT NULL DEFAULT 0.00,
    line_total       DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT chk_quantity CHECK (quantity > 0),
    CONSTRAINT chk_discount CHECK (discount_pct BETWEEN 0 AND 100),
    CONSTRAINT uq_order_product UNIQUE (order_id, product_id),
    CONSTRAINT fk_details_order
        FOREIGN KEY (order_id) REFERENCES Orders(order_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_details_product
        FOREIGN KEY (product_id) REFERENCES Products(product_id)
        ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- 1.5 Inventory_Logs (full audit trail of every stock change)
-- ---------------------------------------------------------------------
CREATE TABLE Inventory_Logs (
    log_id           INT AUTO_INCREMENT PRIMARY KEY,
    product_id       INT          NOT NULL,
    change_type      ENUM('ORDER','RESTOCK','ADJUSTMENT') NOT NULL,
    quantity_change  INT          NOT NULL,   -- negative = out, positive = in
    stock_before     INT          NOT NULL,
    stock_after      INT          NOT NULL,
    reference_id     INT          NULL,       -- order_id for ORDER changes
    change_date      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes            VARCHAR(255),
    CONSTRAINT fk_logs_product
        FOREIGN KEY (product_id) REFERENCES Products(product_id)
        ON DELETE RESTRICT,
    INDEX idx_logs_product_date (product_id, change_date),
    INDEX idx_logs_date         (change_date)
);


DELIMITER $$

-- =====================================================================
-- SECTION 2: FUNCTIONS
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2.1 Bulk discount by quantity: 10-19 -> 5%, 20-49 -> 10%, 50+ -> 15%
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_bulk_discount(p_quantity INT)
RETURNS DECIMAL(5,2)
DETERMINISTIC
BEGIN
    RETURN CASE
        WHEN p_quantity >= 50 THEN 15.00
        WHEN p_quantity >= 20 THEN 10.00
        WHEN p_quantity >= 10 THEN  5.00
        ELSE 0.00
    END;
END$$

-- ---------------------------------------------------------------------
-- 2.2 Customer tier by total spending:
--     Gold >= 2000, Silver >= 1000, otherwise Bronze
-- ---------------------------------------------------------------------
CREATE FUNCTION fn_get_tier(p_total_spent DECIMAL(12,2))
RETURNS VARCHAR(10)
DETERMINISTIC
BEGIN
    RETURN CASE
        WHEN p_total_spent >= 2000 THEN 'Gold'
        WHEN p_total_spent >= 1000 THEN 'Silver'
        ELSE 'Bronze'
    END;
END$$


-- =====================================================================
-- SECTION 3: STORED PROCEDURES
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 Place an order containing one or more products.
-- All-or-nothing: if any product lacks stock, nothing is saved.
--
--   CALL sp_place_order(1, '[{"product_id":1,"quantity":2}]', @order_id);
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_place_order(
    IN  p_customer_id INT,
    IN  p_items       JSON,
    OUT p_order_id    INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_order_id = NULL;
        RESIGNAL;
    END;

    IF NOT EXISTS (SELECT 1 FROM Customers WHERE customer_id = p_customer_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Customer does not exist';
    END IF;

    IF p_items IS NULL OR JSON_LENGTH(p_items) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order must contain at least one product';
    END IF;

    START TRANSACTION;

        INSERT INTO Orders (customer_id) VALUES (p_customer_id);
        SET p_order_id = LAST_INSERT_ID();

        -- Triggers handle pricing, discounts, stock, logging and totals
        INSERT INTO Order_Details (order_id, product_id, quantity)
        SELECT p_order_id, jt.product_id, jt.quantity
          FROM JSON_TABLE(
                 p_items, '$[*]'
                 COLUMNS (
                     product_id INT PATH '$.product_id',
                     quantity   INT PATH '$.quantity'
                 )
               ) AS jt;

    COMMIT;
END$$

-- ---------------------------------------------------------------------
-- 3.2 Restock one product and log the change
--
--   CALL sp_restock_product(10, 30, 'Supplier delivery #1001');
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_restock_product(
    IN p_product_id INT,
    IN p_quantity   INT,
    IN p_notes      VARCHAR(255)
)
BEGIN
    DECLARE v_stock INT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Restock quantity must be greater than zero';
    END IF;

    START TRANSACTION;

        SELECT stock_quantity INTO v_stock
          FROM Products
         WHERE product_id = p_product_id
           FOR UPDATE;

        IF v_stock IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Product does not exist';
        END IF;

        UPDATE Products
           SET stock_quantity = stock_quantity + p_quantity
         WHERE product_id = p_product_id;

        INSERT INTO Inventory_Logs
            (product_id, change_type, quantity_change,
             stock_before, stock_after, notes)
        VALUES
            (p_product_id, 'RESTOCK', p_quantity,
             v_stock, v_stock + p_quantity,
             COALESCE(p_notes, 'Manual restock'));

    COMMIT;
END$$

-- ---------------------------------------------------------------------
-- 3.3 Replenish every low-stock product to (reorder_level x multiplier)
--
--   CALL sp_replenish_low_stock(2);
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_replenish_low_stock(IN p_multiplier DECIMAL(4,2))
BEGIN
    DECLARE v_done        INT DEFAULT 0;
    DECLARE v_product_id  INT;
    DECLARE v_qty         INT;
    DECLARE v_count       INT DEFAULT 0;
    DECLARE v_start_log   INT;

    DECLARE cur_low_stock CURSOR FOR
        SELECT product_id,
               CEIL(reorder_level * p_multiplier) - stock_quantity
          FROM Products
         WHERE is_low_stock = 1;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    IF p_multiplier IS NULL OR p_multiplier < 1 THEN
        SET p_multiplier = 2;
    END IF;

    SELECT COALESCE(MAX(log_id), 0) INTO v_start_log FROM Inventory_Logs;

    OPEN cur_low_stock;

    restock_loop: LOOP
        FETCH cur_low_stock INTO v_product_id, v_qty;
        IF v_done = 1 THEN
            LEAVE restock_loop;
        END IF;

        CALL sp_restock_product(v_product_id, v_qty,
             CONCAT('Auto-replenish to ', p_multiplier, 'x reorder level'));

        SET v_count = v_count + 1;
    END LOOP;

    CLOSE cur_low_stock;

    IF v_count = 0 THEN
        SELECT 'No products needed replenishment' AS result;
    ELSE
        SELECT p.product_name,
               l.stock_before,
               l.quantity_change AS units_added,
               l.stock_after,
               p.reorder_level,
               l.change_date
          FROM Inventory_Logs l
          JOIN Products p ON p.product_id = l.product_id
         WHERE l.log_id > v_start_log
           AND l.change_type = 'RESTOCK'
         ORDER BY l.log_id;
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 3.4 Recalculate one customer's tier from their total spending
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_update_customer_tier(IN p_customer_id INT)
BEGIN
    DECLARE v_total DECIMAL(12,2);

    SELECT COALESCE(SUM(total_amount), 0) INTO v_total
      FROM Orders
     WHERE customer_id = p_customer_id;

    UPDATE Customers
       SET tier = fn_get_tier(v_total)
     WHERE customer_id = p_customer_id;
END$$


-- =====================================================================
-- SECTION 4: TRIGGERS (AUTOMATION)
--
--   CALL sp_place_order
--     -> INSERT Order_Details
--          -> BEFORE trigger: check stock, set price + discount
--          -> AFTER trigger:  deduct stock, write log, update order total
--               -> Orders trigger: recalculate customer tier
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.1 Validate stock and calculate the line price
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_order_details_before_insert
BEFORE INSERT ON Order_Details
FOR EACH ROW
BEGIN
    DECLARE v_price DECIMAL(10,2) DEFAULT NULL;
    DECLARE v_stock INT DEFAULT NULL;
    DECLARE v_name  VARCHAR(100);
    DECLARE v_msg   VARCHAR(255);

    SELECT price, stock_quantity, product_name
      INTO v_price, v_stock, v_name
      FROM Products
     WHERE product_id = NEW.product_id
       FOR UPDATE;

    IF v_price IS NULL THEN
        SET v_msg = CONCAT('Product ID ', NEW.product_id, ' does not exist');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    IF v_stock < NEW.quantity THEN
        SET v_msg = CONCAT('Insufficient stock for "', v_name,
                           '": requested ', NEW.quantity,
                           ', available ', v_stock);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;

    SET NEW.unit_price   = v_price;
    SET NEW.discount_pct = fn_bulk_discount(NEW.quantity);
    SET NEW.line_total   = ROUND(NEW.quantity * v_price
                                 * (1 - NEW.discount_pct / 100), 2);
END$$

-- ---------------------------------------------------------------------
-- 4.2 Deduct stock, log the change, add to the order total
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_order_details_after_insert
AFTER INSERT ON Order_Details
FOR EACH ROW
BEGIN
    DECLARE v_stock_after INT;

    UPDATE Products
       SET stock_quantity = stock_quantity - NEW.quantity
     WHERE product_id = NEW.product_id;

    SELECT stock_quantity INTO v_stock_after
      FROM Products
     WHERE product_id = NEW.product_id;

    INSERT INTO Inventory_Logs
        (product_id, change_type, quantity_change,
         stock_before, stock_after, reference_id, notes)
    VALUES
        (NEW.product_id, 'ORDER', -NEW.quantity,
         v_stock_after + NEW.quantity, v_stock_after,
         NEW.order_id, CONCAT('Sold in order #', NEW.order_id));

    UPDATE Orders
       SET total_amount = total_amount + NEW.line_total
     WHERE order_id = NEW.order_id;
END$$

-- ---------------------------------------------------------------------
-- 4.3 Recalculate tier whenever an order total changes
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_orders_after_update
AFTER UPDATE ON Orders
FOR EACH ROW
BEGIN
    IF NEW.total_amount <> OLD.total_amount THEN
        CALL sp_update_customer_tier(NEW.customer_id);
    END IF;

    IF NEW.customer_id <> OLD.customer_id THEN
        CALL sp_update_customer_tier(OLD.customer_id);
        CALL sp_update_customer_tier(NEW.customer_id);
    END IF;
END$$

-- ---------------------------------------------------------------------
-- 4.4 Recalculate tier when an order is deleted
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_orders_after_delete
AFTER DELETE ON Orders
FOR EACH ROW
BEGIN
    CALL sp_update_customer_tier(OLD.customer_id);
END$$

DELIMITER ;


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


-- =====================================================================
-- SECTION 6: SAMPLE DATA
-- =====================================================================

INSERT INTO Products (product_name, category, price, stock_quantity, reorder_level) VALUES
('Wireless Mouse',          'Electronics',  25.00, 150, 20),
('USB-C Charger',           'Electronics',  18.50,  80, 15),
('Bluetooth Headphones',    'Electronics',  65.00,  12, 10),
('Laptop Stand',            'Accessories',  35.00,  40, 10),
('Mechanical Keyboard',     'Electronics',  89.99,   8, 10),
('Notebook A5 (Pack of 5)', 'Stationery',    7.50, 300, 50),
('Ballpoint Pens (Box 20)', 'Stationery',    4.25, 500, 100),
('Office Chair',            'Furniture',   150.00,  15,  5),
('Desk Lamp LED',           'Furniture',    29.99,  25,  8),
('Water Bottle 1L',         'Accessories',  12.00,   6, 12);

INSERT INTO Customers (first_name, last_name, email, phone) VALUES
('Aline',   'Uwase',        'aline.uwase@example.com',      '+250788000001'),
('Eric',    'Mugisha',      'eric.mugisha@example.com',     '+250788000002'),
('Grace',   'Ingabire',     'grace.ingabire@example.com',   '+250788000003'),
('Patrick', 'Habimana',     'patrick.habimana@example.com', '+250788000004'),
('Diane',   'Mukamana',     'diane.mukamana@example.com',   '+250788000005'),
('Kevin',   'Nshimiyimana', 'kevin.n@example.com',          '+250788000006');

-- Opening stock recorded in the audit trail
INSERT INTO Inventory_Logs
    (product_id, change_type, quantity_change, stock_before, stock_after, notes)
SELECT product_id, 'ADJUSTMENT', stock_quantity, 0, stock_quantity, 'Opening stock'
FROM Products;


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


-- =====================================================================
-- SECTION 10: ERROR-HANDLING TESTS
-- Each of these SHOULD fail. They are commented out so the script
-- runs cleanly. To test, remove the "-- " and run ONE at a time.
-- =====================================================================

-- Not enough stock: nothing is saved, not even the laptop stand
-- CALL sp_place_order(2, '[{"product_id":4,"quantity":1},{"product_id":5,"quantity":500}]', @o);

-- Customer does not exist
-- CALL sp_place_order(999, '[{"product_id":1,"quantity":1}]', @o);

-- Empty order
-- CALL sp_place_order(1, '[]', @o);

-- Invalid restock quantity
-- CALL sp_restock_product(1, -5, 'Bad quantity');

-- Product does not exist
-- CALL sp_restock_product(999, 10, 'Unknown product');

-- Negative price rejected by CHECK constraint
-- INSERT INTO Products (product_name, category, price) VALUES ('Bad', 'Test', -5);

-- Duplicate email rejected by UNIQUE constraint
-- INSERT INTO Customers (first_name, last_name, email) VALUES ('X', 'Y', 'aline.uwase@example.com');

-- =====================================================================
-- END OF SCRIPT
-- =====================================================================
