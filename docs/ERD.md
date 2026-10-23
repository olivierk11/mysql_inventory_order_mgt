# Entity Relationship Diagram

GitHub renders the diagram below automatically.

```mermaid
erDiagram
    CUSTOMERS ||--o{ ORDERS : "places"
    ORDERS ||--|{ ORDER_DETAILS : "contains"
    PRODUCTS ||--o{ ORDER_DETAILS : "appears in"
    PRODUCTS ||--o{ INVENTORY_LOGS : "is tracked by"

    CUSTOMERS {
        int customer_id PK
        varchar first_name
        varchar last_name
        varchar email UK
        varchar phone
        enum tier "Bronze, Silver, Gold"
        datetime created_at
    }

    ORDERS {
        int order_id PK
        int customer_id FK
        datetime order_date
        decimal total_amount "calculated by trigger"
    }

    ORDER_DETAILS {
        int order_detail_id PK
        int order_id FK
        int product_id FK
        int quantity "greater than 0"
        decimal unit_price "price at time of sale"
        decimal discount_pct "bulk discount"
        decimal line_total
    }

    PRODUCTS {
        int product_id PK
        varchar product_name
        varchar category
        decimal price
        int stock_quantity
        int reorder_level
        tinyint is_low_stock "generated column"
    }

    INVENTORY_LOGS {
        int log_id PK
        int product_id FK
        enum change_type "ORDER, RESTOCK, ADJUSTMENT"
        int quantity_change "negative = out"
        int stock_before
        int stock_after
        int reference_id "order_id"
        datetime change_date
        varchar notes
    }
```

## Relationships

| Relationship | Type | Rule on delete |
|---|---|---|
| Customers → Orders | One-to-many | `RESTRICT`: a customer with orders cannot be deleted |
| Orders → Order_Details | One-to-many (at least one) | `CASCADE`: deleting an order removes its lines |
| Products → Order_Details | One-to-many | `RESTRICT`: a product that has been sold cannot be deleted |
| Products → Inventory_Logs | One-to-many | `RESTRICT`: protects the audit trail |

Orders and Products have a **many-to-many** relationship, which is resolved through the Order_Details junction table. A `UNIQUE (order_id, product_id)` constraint ensures each product appears only once per order.
