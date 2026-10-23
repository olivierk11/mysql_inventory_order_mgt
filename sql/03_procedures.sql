-- =====================================================================
--  Inventory and Order Management System
--  03 - Stored procedures: orders, restocking, replenishment, tiers
--  Requires 01-02. Safe to re-run.
-- =====================================================================

USE inventory_db;

DROP PROCEDURE IF EXISTS sp_place_order;
DROP PROCEDURE IF EXISTS sp_restock_product;
DROP PROCEDURE IF EXISTS sp_replenish_low_stock;
DROP PROCEDURE IF EXISTS sp_update_customer_tier;

DELIMITER $$

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

DELIMITER ;
