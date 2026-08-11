CREATE DATABASE datawarehouseanalytics;
USE datawarehouseanalytics;

# Change-over-time

SELECT
YEAR(order_date) as order_year,
MONTH(order_date) as order_month,
SUM(sales_amount) as total_sales,
COUNT(distinct customer_key) as total_customers,
SUM(quantity) as total_quantity
from fact_sales
WHERE YEAR(order_date) IS NOT NULL
GROUP BY order_year,order_month
ORDER BY order_year,order_month;

# CUMULATIVE ANALYSIS
# finding total sales and running total sales for each month over time

SELECT
order_date,
total_sales,
SUM(total_sales) OVER (ORDER BY order_date) as running_total
FROM
(SELECT
DATE_FORMAT(order_date,'%Y-%m') as order_date,
SUM(sales_amount) as total_sales
FROM
fact_sales
WHERE YEAR(order_date) IS NOT NULL
GROUP BY DATE_FORMAT(order_date,'%Y-%m')
ORDER BY DATE_FORMAT(order_date,'%Y-%m')) t;

/* Analyze the yearly performance of products by comparing its current year sales
   with average sales of product and previous year sales*/
   
WITH yearly_product_sales as (
SELECT
p.product_name,
YEAR(s.order_date) as order_year,
SUM(sales_amount) as cy_sales
FROM
fact_sales s
LEFT JOIN
dim_products p
ON
p.product_key=s.product_key
GROUP BY p.product_name,YEAR(s.order_date)
ORDER BY p.product_name,YEAR(s.order_date))
SELECT
product_name,
order_year,
cy_sales,
AVG(cy_sales) OVER (PARTITION BY product_name) as avg_sales,
cy_sales-AVG(cy_sales) OVER (PARTITION BY product_name) as avg_diff,
CASE WHEN cy_sales-AVG(cy_sales) OVER (PARTITION BY product_name)>0 THEN 'Above Average'
	 WHEN cy_sales-AVG(cy_sales) OVER (PARTITION BY product_name)<0 THEN 'Below Average'
     ELSE 'Average'
END avg_change,
LAG(cy_sales) OVER (PARTITION BY product_name ORDER BY order_year) as py_sales,
cy_sales-LAG(cy_sales) OVER (PARTITION BY product_name ORDER BY order_year) as py_diff,
CASE WHEN LAG(cy_sales) OVER (PARTITION BY product_name ORDER BY order_year)>0 THEN 'Incresing'
     WHEN LAG(cy_sales) OVER (PARTITION BY product_name ORDER BY order_year)<0 THEN 'Decreasing'
     ELSE 'No Change'
END py_change     
FROM 
yearly_product_sales;

# Which category contribute most to the overall sales

WITH category_sales as (
SELECT
p.category,
sum(s.sales_amount) as total_sales
FROM
fact_sales s LEFT JOIN
dim_products p
ON s.product_key=p.product_key
GROUP BY p.category)

SELECT 
category,
total_sales,
SUM(total_sales) OVER () as overall_sales,
(total_sales/SUM(total_sales) OVER ())*100 as percentage_of_total
FROM
category_sales
ORDER BY percentage_of_total desc;

# Segment products into cost range and count how many products fall in each segment

SELECT
count(product_key) as total_products,
CASE WHEN cost<100 THEN 'Below 100'
     WHEN cost BETWEEN 100 AND 500 THEN '100-500'
	 WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
     ELSE 'Above 1000'
     END cost_segment
FROM dim_products
GROUP BY cost_segment
ORDER BY total_products desc;

/* Group customers into three segments based on their spending behaviour:
      - VIP: Customers with atleast 12 months of history and total spending greater than 5000.
      - Regular: Customers with atleast 12 months of history but total spending 5000 or less.
      - New: Customers with less than 12 months of history.
   And find the total no of customers for each group.*/

WITH customer_segments as (
SELECT
customer_key,
TIMESTAMPDIFF(MONTH,first_order_date,last_order_date) as spending_history,
total_spending,
CASE WHEN TIMESTAMPDIFF(MONTH,first_order_date,last_order_date)>=12 AND total_spending>5000 THEN 'VIP'
     WHEN TIMESTAMPDIFF(MONTH,first_order_date,last_order_date)>=12 AND total_spending<=5000 THEN 'Regular'
     ELSE 'New'
     END customer_segment
from(     
SELECT
customer_key,
MAX(order_date) as last_order_date,
MIN(order_date) as first_order_date,
SUM(sales_amount) as total_spending
FROM fact_sales
GROUP BY customer_key) t)
SELECT
customer_segment,
count(customer_key) as total_customers
FROM customer_segments
GROUP BY customer_segment
ORDER BY total_customers desc;

-----------------------------------
#  CUSTOMER REPORT
-----------------------------------
/* Purpose: This report consolidates key customer metrics and behaviors.
   Highlights:
        1. Gather essential fields such as names, ages, transaction details.
        2. Segments customers into categories (VIP, Regular, New) and age groups.
        3.Aggregates customer-level metrics:
                  - total orders
                  - total sales
                  - total quantity purchased
                  - total products 
                  - lifespan (in months)
        4. Calculates valuable KPI's:
                  - recency (months since last order)
                  - average order values
                  - average monthly spend
*/
CREATE VIEW Customer_Report AS
WITH customer_info as (      
SELECT 
c.customer_key,
CONCAT(c.first_name,' ',c.last_name) as customer_name,
TIMESTAMPDIFF(YEAR,c.birthdate,CURDATE()) as age,
MAX(s.order_date) as last_order_date,
TIMESTAMPDIFF(MONTH,MIN(s.order_date),MAX(s.order_date)) as lifespan,
COUNT(DISTINCT s.order_number) as total_orders,
COUNT(DISTINCT s.product_key) as total_products,
SUM(s.sales_amount) as total_spending,
SUM(s.quantity) as total_quantity
FROM fact_sales s 
LEFT JOIN dim_customers c
ON s.customer_key=c.customer_key
WHERE YEAR(s.order_date) IS NOT NULL AND YEAR(c.birthdate) IS NOT NULL
GROUP BY customer_key,customer_name,age)
SELECT
customer_key,
customer_name,
age,
last_order_date,
lifespan,
total_orders,
total_products,
total_spending,
total_quantity,
CASE WHEN lifespan>=12 AND total_spending>5000 THEN 'VIP'
     WHEN lifespan>=12 AND total_spending<=5000 THEN 'Regular'
     ELSE 'New'
     END customer_segment,
CASE WHEN age<20 THEN 'Under 20'
     WHEN age BETWEEN 20 AND 29 THEN '20-29'
     WHEN age BETWEEN 30 AND 39 THEN '30-39'
     WHEN age BETWEEN 40 AND 49 THEN '40-49'
     ELSE '50 And Above'
END age_group,
TIMESTAMPDIFF(MONTH,last_order_date,CURDATE()) as recency,
CASE WHEN total_orders=0 THEN 0
     ELSE ROUND(total_spending/total_orders,2)
END average_order_value,
CASE WHEN lifespan=0 THEN total_spending
     ELSE ROUND(total_spending/lifespan,2)
END average_monthly_order
FROM customer_info;

SELECT *
FROM Customer_Report;

---------------------------------
# PRODUCT REPORT
---------------------------------
/* Purpose: This report consolidates key customer metrics and behaviors.
   Highlights:
        1. Gather essential fields such as product_name, category, sub-category, and cost.
        2. Segments products by revenue to High-Performers, Mid-Range, or Low-Performers.
        3.Aggregates customer-level metrics:
                  - total orders
                  - total sales
                  - total quantity purchased
                  - total customers (unique) 
                  - lifespan (in months)
        4. Calculates valuable KPI's:
                  - recency (months since last order)
                  - average order revenue
                  - average monthly revenue
*/    
CREATE VIEW Product_Report AS
WITH product_info as (      
SELECT 
p.product_key,
p.product_name,
p.category,
p.subcategory,
p.cost,
MAX(s.order_date) as last_order_date,
TIMESTAMPDIFF(MONTH,MIN(s.order_date),MAX(s.order_date)) as lifespan,
COUNT(DISTINCT s.order_number) as total_orders,
COUNT(DISTINCT s.customer_key) as total_customers,
SUM(s.sales_amount) as total_revenue,
SUM(s.quantity) as total_quantity
FROM fact_sales s 
LEFT JOIN dim_products p
ON s.product_key=p.product_key
WHERE YEAR(s.order_date) IS NOT NULL
GROUP BY p.product_key,p.product_name,p.category,p.subcategory,p.cost)
SELECT
product_key,
product_name,
category,
subcategory,
cost,
last_order_date,
lifespan,
total_orders,
total_customers,
total_revenue,
total_quantity,
CASE WHEN total_revenue >50000 THEN 'High-Performer'
     WHEN total_revenue BETWEEN 10000 AND 50000 THEN 'Mid-Range'
     ELSE 'Low-Performer'
END product_segment,
TIMESTAMPDIFF(MONTH,last_order_date,CURDATE()) as recency,
CASE WHEN total_orders=0 THEN 0
     ELSE ROUND(total_revenue/total_orders,2)
END average_order_revenue,
CASE WHEN lifespan=0 THEN total_revenue
     ELSE ROUND(total_revenue/lifespan,2)
END average_monthly_revenue
FROM product_info;

SELECT *
FROM Product_Report;