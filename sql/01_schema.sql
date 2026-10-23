-- =====================================================================
--  Inventory and Order Management System
--  01 - Database schema: tables, relationships, constraints, indexes
--  WARNING: drops and re-creates the inventory_db database.
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
