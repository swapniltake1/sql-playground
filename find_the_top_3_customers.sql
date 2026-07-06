-- Example SQL interview query: find the top 3 customers by total order value in the last 30 days

with recent_orders as (
  select customer_id,
         order_amount
  from orders
  where order_date >= current_date - interval '30' day
)

select customer_id,
       sum(order_amount) as total_amount,
       row_number() over (order by sum(order_amount) desc) as rank
from recent_orders
group by customer_id
order by total_amount desc
limit 3;
