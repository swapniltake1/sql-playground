-- Daily SQL Practice
-- Topic: Window Functions

WITH ranked_products AS (
    SELECT
        product_id,
        category,
        price,
        RANK() OVER (
            PARTITION BY category
            ORDER BY price DESC
        ) AS price_rank
    FROM products
)
SELECT
    product_id,
    category,
    price,
    price_rank
FROM ranked_products
WHERE price_rank <= 3
ORDER BY category, price_rank;
