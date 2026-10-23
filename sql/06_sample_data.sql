-- =====================================================================
--  Inventory and Order Management System
--  06 - Sample data: products, customers, opening stock
--  Run ONCE on a fresh schema.
-- =====================================================================

USE inventory_db;

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
