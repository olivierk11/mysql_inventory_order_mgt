-- =====================================================================
--  Inventory and Order Management System
--  02 - Functions: bulk discount and customer tier rules
--  Requires 01. Safe to re-run.
-- =====================================================================

USE inventory_db;

DROP FUNCTION IF EXISTS fn_bulk_discount;
DROP FUNCTION IF EXISTS fn_get_tier;

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

DELIMITER ;
