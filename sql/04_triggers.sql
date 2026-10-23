-- =====================================================================
--  Inventory and Order Management System
--  04 - Triggers: automated stock, logging, totals and tiers
--  Requires 01-03. Safe to re-run.
-- =====================================================================

USE inventory_db;

DROP TRIGGER IF EXISTS trg_order_details_before_insert;
DROP TRIGGER IF EXISTS trg_order_details_after_insert;
DROP TRIGGER IF EXISTS trg_orders_after_update;
DROP TRIGGER IF EXISTS trg_orders_after_delete;

DELIMITER $$

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
